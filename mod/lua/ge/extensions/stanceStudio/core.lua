-- Stance Studio: menu, settings, applying stance, ride-height measuring and keybind.
-- The UI (ui/ui-vue/mods/stanceStudio) calls into this extension through engineLua.

local M = {}
M.dependencies = {"stanceStudio_jbeam", "stanceStudio_preview", "stanceStudio_parts", "stanceStudio_photos"}

local stance = require("ge/extensions/stanceStudio/stance")

local ACTION = "stanceStudio_toggle"
local ROUTE = "stanceStudio"
local SETTINGS_FILE = "/settings/stanceStudio/settings.json"
local SETTLE_TIME = 2.0 -- seconds of simulation after a respawn before measuring ride height

local SETTINGS_VERSION = 2
local defaultSettings = {
  settingsVersion = SETTINGS_VERSION,
  applyMode = "release",   -- "release" = apply when you let go of a slider, "button" = Apply button
  units = "metric",        -- "metric" (mm) or "imperial" (in)
  range = "normal",        -- "normal" or "extreme" slider ranges
  preview = true,          -- ghost tire while dragging
  previewColor = "#38bdf8",
  autoFocus = true,        -- camera frames the axle you edit
  autoCorrect = true,      -- one extra respawn when the measured ride height misses the target
  method = "auto",         -- ride height: "auto" (springs, then the hub for anything lower), "springs" or "hub"
  linkAxles = false,
  photoPass = "auto",      -- "auto" (background helper car), "ask" or "off"
  gains = {},              -- learned ride-height gain per vehicle model
}

local settings = nil
local isOpen = false
local pendingMeasure = nil -- after a respawn: measure ride height, maybe auto-correct
local axleCache = {}       -- vehId -> {wheelIndex -> "F"/"R"}
local spawnCount = 0      -- bumps on every respawn so the UI knows to reload part lists
local powerQuery = nil    -- {vehId, timer}: read engine power a moment after a spawn
local queryPower          -- defined below

-- MARK: helpers

local function deepMerge(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" and type(dst[k]) == "table" and k ~= "gains" then
      deepMerge(dst[k], v)
    else
      dst[k] = deepcopy(v)
    end
  end
  return dst
end

local function loadSettings()
  settings = deepcopy(defaultSettings)
  local data = jsonReadFile(SETTINGS_FILE)
  if type(data) == "table" then
    -- v1 saved its defaults: move them to the new ones
    if (tonumber(data.settingsVersion) or 1) < 2 then
      if data.method == "springs" then data.method = "auto" end
      if data.photoPass == "ask" then data.photoPass = "auto" end
      data.settingsVersion = SETTINGS_VERSION
    end
    deepMerge(settings, data)
  end
  if type(settings.gains) ~= "table" then settings.gains = {} end
end

local function saveSettingsFile()
  jsonWriteFile(SETTINGS_FILE, settings, true)
end

local function getVeh()
  local veh = getPlayerVehicle(0)
  if not veh then return nil end
  local data = core_vehicle_manager.getVehicleData(veh:getID())
  if not data then return nil end
  return veh, data, veh:getID()
end

local function careerActive()
  return career_career and career_career.isActive and career_career.isActive()
end

local function toast(kind, msg)
  guihooks.trigger("toastrMsg", {type = kind, title = "Stance Studio", msg = msg})
end

-- jbeam model name ("etk800"): the vehicle bundle keeps it in vdata / config, not at the top level
local function modelOf(vehData)
  if not vehData then return nil end
  local m = (vehData.vdata and vehData.vdata.model) or (vehData.config and vehData.config.model)
  if type(m) == "string" and m ~= "" then return m end
  local veh = vehData.id and getObjectByID(vehData.id)
  if veh then
    local ok, name = pcall(function() return veh:getJBeamFilename() end)
    if ok and type(name) == "string" and name ~= "" then return name end
  end
  return nil
end
M.modelOf = modelOf

local function modelName(vehData)
  local model = modelOf(vehData)
  local name = model or "Vehicle"
  local ok, res = pcall(function()
    local m = core_vehicles.getModel(model)
    return m and m.model and (m.model.Brand and (m.model.Brand .. " ") or "") .. (m.model.Name or "")
  end)
  if ok and type(res) == "string" and res ~= "" then name = res end
  return name
end

local function currentStance(vehData)
  local cfg = stance.normalize(vehData.config and vehData.config.stanceStudio)
  if not (vehData.config and vehData.config.stanceStudio) then
    cfg.method = settings.method
    local g = settings.gains[modelOf(vehData) or ""]
    if type(g) == "table" then
      cfg.gain.F = tonumber(g.F) or 1
      cfg.gain.R = tonumber(g.R) or 1
    end
  end
  return cfg
end

-- MARK: wheels, axles, measuring

local function wheelAxles(vehId, vdata)
  if axleCache[vehId] then return axleCache[vehId] end
  local res, sumY, n = {}, 0, 0
  local centers = {}
  for wi, w in pairs(vdata.wheels or {}) do
    local n1, n2 = vdata.nodes[w.node1], vdata.nodes[w.node2]
    if n1 and n2 and n1.pos and n2.pos then
      local y = (n1.pos.y + n2.pos.y) * 0.5
      local x = (n1.pos.x + n2.pos.x) * 0.5
      centers[wi] = {x = x, y = y}
      sumY, n = sumY + y, n + 1
    end
  end
  local meanY = n > 0 and sumY / n or 0
  for wi, c in pairs(centers) do
    res[wi] = {axle = (n <= 2 or c.y <= meanY) and "F" or "R", side = c.x > 0.02 and 1 or (c.x < -0.02 and -1 or 0)}
  end
  axleCache[vehId] = res
  return res
end

-- ride height per axle: height of the reference node above the wheel centers, along the car's up axis
local function measure(veh, vdata)
  local ref = vdata.refNodes and vdata.refNodes[0] and vdata.refNodes[0].ref
  if not ref or not vdata.wheels then return nil end
  local up = vec3(veh:getDirectionVectorUpXYZ())
  local rp = vec3(veh:getNodePositionXYZ(ref))
  local axles = wheelAxles(veh:getID(), vdata)
  local sums = {F = {0, 0}, R = {0, 0}}
  for wi, w in pairs(vdata.wheels) do
    local info = axles[wi]
    if info and info.side ~= 0 then
      local c = (vec3(veh:getNodePositionXYZ(w.node1)) + vec3(veh:getNodePositionXYZ(w.node2))) * 0.5
      local s = sums[info.axle]
      s[1], s[2] = s[1] + (rp - c):dot(up), s[2] + 1
    end
  end
  local res = {}
  for axle, s in pairs(sums) do
    if s[2] > 0 then res[axle] = s[1] / s[2] end
  end
  return res
end

local function isAtRest(veh)
  local v = veh:getVelocity()
  return v and v:length() < 0.3
end

local function wheelInfo(vehId, vdata)
  local axles = wheelAxles(vehId, vdata)
  local res = {F = {count = 0}, R = {count = 0}}
  for wi, w in pairs(vdata.wheels or {}) do
    local info = axles[wi]
    if info then
      local a = res[info.axle]
      a.count = a.count + 1
      a.radius = math.max(a.radius or 0, tonumber(w.radius) or 0)
      a.width = math.max(a.width or 0, math.min(tonumber(w.tireWidth) or tonumber(w.hubWidth) or 0, 0.6))
      a.hubRadius = math.max(a.hubRadius or 0, tonumber(w.hubRadius) or 0)
      local n1, n2 = vdata.nodes[w.node1], vdata.nodes[w.node2]
      if n1 and n2 and info.side ~= 0 then
        a.trackSum = (a.trackSum or 0) + math.abs((n1.pos.x + n2.pos.x) * 0.5)
        a.trackN = (a.trackN or 0) + 1
      end
    end
  end
  for _, a in pairs(res) do
    if a.trackN then a.halfTrack = a.trackSum / a.trackN end
    a.trackSum, a.trackN = nil, nil
  end
  return res
end

-- store measured stock height for axles that are at stock ride height (no respawn)
local function updateBaseline(veh, vehData, cfg, m)
  if not m then return false end
  local changed = false
  for _, axle in ipairs({"F", "R"}) do
    local a = cfg[axle]
    if m[axle] and math.abs(a.rideHeight) < 1e-6 and math.abs(a.spring - 1) < 1e-6 then
      if not cfg.base[axle] or math.abs(cfg.base[axle] - m[axle]) > 0.001 then
        cfg.base[axle] = m[axle]
        changed = true
      end
    end
  end
  if changed then
    vehData.config.stanceStudio = cfg
    veh:setField('partConfig', '', serialize(vehData.config))
  end
  return changed
end

-- MARK: state for the UI

local function getKeybind()
  local ok, control = pcall(function() return core_input_bindings.getControlForAction(ACTION) end)
  return ok and control or nil
end

function M.getState()
  if not settings then loadSettings() end
  local state = {settings = settings, keybind = getKeybind(), isCareer = careerActive() and true or false}
  local veh, vehData, vehId = getVeh()
  if not veh then
    state.vehicle = nil
    return state
  end
  local cfg = currentStance(vehData)
  local m = isAtRest(veh) and measure(veh, vehData.vdata) or nil
  if m and not pendingMeasure then updateBaseline(veh, vehData, cfg, m) end
  local actual = {}
  if m then
    for _, axle in ipairs({"F", "R"}) do
      if m[axle] and cfg.base[axle] then actual[axle] = m[axle] - cfg.base[axle] end
    end
  end
  state.vehicle = {
    id = vehId,
    model = modelOf(vehData),
    name = modelName(vehData),
    configName = vehData.config and vehData.config.partConfigFilename,
  }
  state.stance = cfg
  state.report = stanceStudio_jbeam.reports[vehId]
  state.wheels = wheelInfo(vehId, vehData.vdata)
  state.measured = m
  state.actual = actual
  state.busy = pendingMeasure ~= nil
  state.photosRunning = stanceStudio_photos.isRunning()
  state.power = M.power[vehId]
  if not state.power and not powerQuery then queryPower(vehId) end
  state.spawnCount = spawnCount
  return state
end

local function pushState()
  guihooks.trigger("stanceStudioState", M.getState())
end
M.pushState = pushState

-- MARK: apply

local function respawnWithStance(veh, vehData, cfg)
  vehData.config.stanceStudio = cfg
  core_vehicle_partmgmt.setConfig({stanceStudio = cfg}, true)
end

-- newCfg comes from the UI (axle values only, the rest is kept)
local VALID_METHODS = {auto = true, springs = true, hub = true}

function M.applyStance(newCfg)
  if careerActive() then toast("warning", "Stance Studio is disabled in career mode") return end
  local veh, vehData, vehId = getVeh()
  if not veh then return end
  stanceStudio_preview.clear()
  newCfg = type(newCfg) == "table" and newCfg or {}
  local old = currentStance(vehData)
  local cfg = stance.normalize(deepMerge(deepcopy(old), newCfg))
  cfg.base = old.base
  cfg.gain = old.gain
  cfg.hubExtra = deepcopy(old.hubExtra)
  if VALID_METHODS[newCfg.method] then cfg.method = newCfg.method end
  -- a new height, stiffness or method needs a fresh measurement-based top-up
  for _, axle in ipairs({"F", "R"}) do
    if math.abs(cfg[axle].rideHeight - old[axle].rideHeight) > 1e-6 or math.abs(cfg[axle].spring - old[axle].spring) > 1e-6
      or cfg.method ~= old.method then
      cfg.hubExtra[axle] = 0
    end
  end

  local prev = isAtRest(veh) and measure(veh, vehData.vdata) or nil
  pendingMeasure = {
    vehId = vehId,
    prev = prev,
    old = old,
    cfg = cfg,
    corrected = false,
    timer = nil,
  }
  respawnWithStance(veh, vehData, cfg)
  pushState()
end

function M.resetStance()
  M.applyStance({F = deepcopy(stance.defaultAxle), R = deepcopy(stance.defaultAxle)})
end

-- After a respawn: measure the real ride height and, if the springs could not get there
-- (bump stops, short travel), make up the rest by moving the wheel up on the hub.
local function finishMeasure()
  local p = pendingMeasure
  pendingMeasure = nil
  local veh, vehData, vehId = getVeh()
  if not veh or vehId ~= p.vehId then return end
  local m = measure(veh, vehData.vdata)
  local cfg = currentStance(vehData)
  local report = stanceStudio_jbeam.reports[vehId] or {}
  local usesSprings = {}
  for _, c in ipairs(report.corners or {}) do
    if c.method == "springs" or c.method == "springs+hub" then usesSprings[c.axle] = true end
  end

  local needsFix = false
  if m and not p.corrected and cfg.method ~= "hub" then
    for _, axle in ipairs({"F", "R"}) do
      local target = cfg[axle].rideHeight
      local err = nil
      if m[axle] and cfg.base[axle] then
        err = (m[axle] - cfg.base[axle]) - target       -- absolute: positive = sits too high
      elseif m[axle] and p.prev and p.prev[axle] then
        err = (m[axle] - p.prev[axle]) - (target - p.old[axle].rideHeight)
      end
      local tol = math.max(0.004, 0.08 * math.abs(target))
      if err and usesSprings[axle] and math.abs(err) > tol and settings.autoCorrect then
        if cfg.method == "auto" and (target < 0 or (cfg.hubExtra[axle] or 0) > 0) then
          local extra = math.min(math.max((cfg.hubExtra[axle] or 0) + err, 0), stance.HUB_EXTRA_MAX)
          if math.abs(extra - (cfg.hubExtra[axle] or 0)) > 0.002 then
            cfg.hubExtra[axle] = extra
            needsFix = true
          end
        else
          local want = target - (p.old[axle].rideHeight or 0)
          if math.abs(want) >= 0.004 then
            local ratio = (want + err) / want
            if ratio > 0.15 and ratio < 6 then
              local newGain = math.min(math.max((cfg.gain[axle] or 1) / ratio, 0.25), 4)
              local model = modelOf(vehData) or "?"
              settings.gains[model] = settings.gains[model] or {}
              settings.gains[model][axle] = newGain
              cfg.gain[axle] = newGain
              needsFix = true
            end
          end
        end
      end
    end
    saveSettingsFile()
  end

  if needsFix then
    pendingMeasure = {vehId = vehId, prev = nil, old = cfg, cfg = cfg, corrected = true, timer = nil}
    respawnWithStance(veh, vehData, cfg)
    toast("info", "Fine-tuning ride height...")
  else
    if m then updateBaseline(veh, vehData, cfg, m) end
  end
  pushState()
end

-- MARK: engine power (read from the real powertrain after each spawn)

M.power = {}

queryPower = function(vid)
  local veh = getObjectByID(vid)
  if not veh then return end
  veh:queueLuaCommand(string.format([[
    local e = powertrain and powertrain.getDevice and powertrain.getDevice("mainEngine")
    local p = e and ((e.torqueData and e.torqueData.maxPower) or e.maxPower) or -1
    obj:queueGameEngineLua("if stanceStudio_core then stanceStudio_core.onEnginePower(%d," .. tostring(p) .. ") end")
  ]], vid))
end

function M.onEnginePower(vid, hp)
  hp = tonumber(hp)
  M.power[vid] = (hp and hp > 0) and hp or nil
  if isOpen then pushState() end
end

function M.onVehicleSpawned(vid)
  axleCache[vid] = nil
  if pendingMeasure and pendingMeasure.vehId == vid then
    pendingMeasure.timer = SETTLE_TIME
  end
  local player = getPlayerVehicle(0)
  if player and player:getID() == vid then
    spawnCount = spawnCount + 1 -- only your own car: the photo car respawns a lot
    M.power[vid] = nil
    powerQuery = {vehId = vid, timer = 1.0}
    if isOpen then pushState() end
  end
end

function M.onVehicleSwitched()
  pendingMeasure = nil
  stanceStudio_preview.clear()
  if isOpen then pushState() end
end

function M.onVehicleDestroyed(vid)
  axleCache[vid] = nil
end

function M.onUpdate(dtReal, dtSim)
  if powerQuery then
    powerQuery.timer = powerQuery.timer - (dtReal or 0)
    if powerQuery.timer <= 0 then
      local vid = powerQuery.vehId
      powerQuery = nil
      queryPower(vid)
    end
  end
  if pendingMeasure and pendingMeasure.timer then
    pendingMeasure.timer = pendingMeasure.timer - (dtSim or 0)
    if pendingMeasure.timer <= 0 then finishMeasure() end
  end
end

-- MARK: preview and camera

function M.previewStance(pendingCfg)
  if not settings.preview then return end
  local veh, vehData, vehId = getVeh()
  if not veh then return end
  local applied = currentStance(vehData)
  local pending = stance.normalize(deepMerge(deepcopy(applied), type(pendingCfg) == "table" and pendingCfg or {}))
  stanceStudio_preview.setPending(vehId, applied, pending, settings.previewColor)
end

function M.clearPreview()
  stanceStudio_preview.clear()
end

local function wheelPartPaths(vdata, axle, vehId)
  local axles = wheelAxles(vehId, vdata)
  local parts = {}
  for wi, w in pairs(vdata.wheels or {}) do
    if axles[wi] and (axle == nil or axles[wi].axle == axle) then
      for _, cid in ipairs({w.node1, w.node2}) do
        local n = vdata.nodes[cid]
        if n and n.partPath then parts[n.partPath] = true end
      end
    end
  end
  return parts
end

function M.focus(axle)
  local veh, vehData, vehId = getVeh()
  if not veh then return end
  local parts = wheelPartPaths(vehData.vdata, axle, vehId)
  if next(parts) then
    core_vehicle_partFocusCamera.focusOnParts(vehId, parts, {}, 0, {distanceMultiplier = 1.6})
  end
end

function M.releaseFocus()
  if core_vehicle_partFocusCamera then core_vehicle_partFocusCamera.release(true) end
end

-- MARK: open / close

-- same route as ui/ui-vue/mods/stanceStudio/index.js registers; used when the router lost it
-- (for a few seconds after a Lua reload, before the UI mod registers it again)
local ROUTE_SOURCE = "stanceStudio.routes"
local ROUTE_DEF = {{
  name = ROUTE, path = "/stance-studio",
  meta = {
    infoBar = {visible = false, showSysInfo = false},
    topBar = {visible = false},
    uiApps = {shown = false},
    luaRoute = {title = "Stance Studio", backTarget = "play"},
  },
}}

local function ensureRoute()
  local rm = extensions.ui_router_routeManager
  if not (rm and rm.getRoute and rm.registerModRoutes) then return end
  local ok, route = pcall(rm.getRoute, ROUTE)
  if ok and route then return end
  local ok2, res = pcall(rm.registerModRoutes, ROUTE_SOURCE, ROUTE_DEF)
  log('I', 'stanceStudio', 'menu route was missing, registered it again: ' .. tostring(ok2 and type(res) == "table" and res.success))
end

function M.open()
  if getMissionFilename() == '' then return end
  if not getPlayerVehicle(0) then toast("warning", "Get in a vehicle first") return end
  if careerActive() then toast("warning", "Stance Studio is disabled in career mode") return end
  ensureRoute()
  extensions.ui_router.navigate(ROUTE)
end

function M.close()
  extensions.ui_router.navigate("play")
end

function M.toggle()
  if isOpen then M.close() else M.open() end
end

-- called by the UI when the screen mounts / unmounts
function M.onUiOpened()
  isOpen = true
end

function M.onUiClosed()
  isOpen = false
  stanceStudio_preview.clear()
  M.releaseFocus()
  stanceStudio_photos.cancel()
end

-- MARK: settings and keybind

function M.saveSettings(newSettings)
  if type(newSettings) ~= "table" then return settings end
  for k, v in pairs(newSettings) do
    if defaultSettings[k] ~= nil and k ~= "gains" then settings[k] = v end
  end
  saveSettingsFile()
  if not settings.preview then stanceStudio_preview.clear() end
  return settings
end

function M.getSettings()
  return settings
end

-- control is a BeamNG key name such as "alt e" or "ctrl shift f"; empty string removes the binding
function M.setKeybind(control)
  log('I', 'stanceStudio', 'saving open key: ' .. tostring(control))
  local ok, err = pcall(function()
    for _, dev in ipairs(core_input_bindings.bindings or {}) do
      local c = dev.contents
      if c and c.devicetype == "keyboard" then
        local data = deepcopy(c)
        local list = {}
        for _, b in ipairs(data.bindings or {}) do
          if b.action ~= ACTION then list[#list + 1] = b end
        end
        if type(control) == "string" and control ~= "" then
          list[#list + 1] = {action = ACTION, control = control}
        end
        data.bindings = list
        core_input_bindings.saveBindingsToDisk(data)
        return
      end
    end
    error("no keyboard found")
  end)
  if not ok then
    log('E', 'stanceStudio', 'setKeybind failed: ' .. tostring(err))
    toast("error", "Could not save the key. Set it in Options > Controls > Bindings instead.")
    return false
  end
  toast("success", control ~= "" and ("Stance Studio key set to " .. string.upper(control)) or "Stance Studio key removed")
  return true
end

-- other actions already on that key (shown as a warning before saving)
function M.getKeyConflicts(control)
  local res = {}
  for _, dev in ipairs(core_input_bindings.bindings or {}) do
    local c = dev.contents
    if c and c.devicetype == "keyboard" then
      for _, b in ipairs(c.bindings or {}) do
        if b.control == control and b.action ~= ACTION then
          local a = core_input_actions.getActiveActions()[b.action]
          res[#res + 1] = a and a.title and _tr(a.title) or b.action
        end
      end
    end
  end
  return res
end

-- MARK: lifecycle

function M.onExtensionLoaded()
  setExtensionUnloadMode(M, "manual")
  loadSettings()
end

function M.onSerialize()
  return {isOpen = isOpen}
end

function M.onDeserialized(data)
  isOpen = type(data) == "table" and data.isOpen or false
end

return M
