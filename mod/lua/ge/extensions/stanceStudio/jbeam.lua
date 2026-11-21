-- Stance Studio: hooks the jbeam loader (same hook as the game's lua/common/extensions/jbeam/jbeamMod.lua)
-- and applies the stance stored in vehicleConfig.stanceStudio to every vehicle that has one.

local M = {}

local stance = require("ge/extensions/stanceStudio/stance")
local fun = require("ge/extensions/stanceStudio/fun")
local share = require("ge/extensions/stanceStudio/share")

-- objID -> report of the last spawn (which method each corner used)
M.reports = {}
-- objID -> stock size of the vehicle ({height, tireRadius}), measured before any stance edits
M.sizes = {}
-- objID -> result of the "Fun stuff" JBeam edits ({applied, missed, original})
M.funReports = {}

local function onJbeamLoadingPhase1(loadingProgress, objID, vehicle, unifyJournal, vehicleConfig, vars)
  local okSize, size = pcall(stance.measureSize, vehicle)
  M.sizes[objID] = okSize and size or nil
  -- (false = "none" on purpose, see mp.lua: keep it apart from a missing key)
  local raw, rawFun = nil, nil
  if type(vehicleConfig) == "table" then raw, rawFun = vehicleConfig.stanceStudio, vehicleConfig.stanceStudioFun end

  -- a friend's car in Tandem arrives with parts, tuning values and paint only: the stance and the
  -- simple Fun edits come as tuning values then (see share.lua). The keys win when they are there.
  if (raw == nil or rawFun == nil) and type(vehicleConfig) == "table" and type(vehicleConfig.vars) == "table" then
    local okE, engines = pcall(fun.engineSections, vehicle)
    local ok, s, f = pcall(share.read, vehicleConfig.vars, okE and engines or {})
    if ok then
      if raw == nil and s then raw = s end
      if rawFun == nil and f then rawFun = f end
    else
      log('E', 'stanceStudio', 'reading the stance from tuning values failed: ' .. tostring(s))
    end
  end

  -- "Fun stuff" JBeam edits, on top of the parts and before the stance (never on the photo car)
  if type(rawFun) == "table" and not (type(raw) == "table" and type(raw.photo) == "table") then
    local ok, res = pcall(fun.apply, vehicle, rawFun)
    M.funReports[objID] = ok and res or {applied = 0, missed = {}, original = {}, error = tostring(res)}
    if ok then
      log('D', 'stanceStudio', 'JBeam edits on ' .. tostring(objID) .. ': ' .. res.applied .. ' applied, ' .. #res.missed .. ' did not match')
    else
      log('E', 'stanceStudio', 'JBeam edits failed: ' .. tostring(res))
    end
  else
    M.funReports[objID] = nil
  end
  if type(raw) ~= "table" then
    M.reports[objID] = nil
    return
  end
  if type(raw.photo) == "table" then
    -- the wheel photo car: strip it down to one rim, no stance
    local ok, res = pcall(stance.photoStrip, vehicle, raw.photo)
    M.reports[objID] = ok and res or {photo = true, error = tostring(res), corners = {}}
    if not ok then log('E', 'stanceStudio', 'photo strip failed: ' .. tostring(res)) end
    return
  end
  local cfg = stance.normalize(raw)
  if stance.isNeutral(cfg) then
    M.reports[objID] = {neutral = true, corners = {}}
    return
  end
  local ok, res = pcall(stance.apply, vehicle, cfg)
  if ok then
    M.reports[objID] = res
    local reinforced = 0
    for _, c in ipairs(res.corners or {}) do reinforced = reinforced + (c.reinforced or 0) end
    log('D', 'stanceStudio', 'stance applied to ' .. tostring(objID) .. ': ' .. tostring(res.wheelCount) .. ' wheels, '
      .. reinforced .. ' stretched hub beams reinforced')
  else
    M.reports[objID] = {error = tostring(res), corners = {}}
    log('E', 'stanceStudio', 'stance apply failed: ' .. tostring(res))
  end
end

local function onVehicleDestroyed(vid)
  M.reports[vid] = nil
  M.sizes[vid] = nil
  M.funReports[vid] = nil
end

local function onExtensionLoaded()
  setExtensionUnloadMode(M, "manual")
end

M.onJbeamLoadingPhase1 = onJbeamLoadingPhase1
M.onVehicleDestroyed = onVehicleDestroyed
M.onExtensionLoaded = onExtensionLoaded

return M
