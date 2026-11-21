-- Stance Studio: rim photo pass.
-- Spawns a temporary copy of your car behind you in "photo mode": the jbeam hook strips it down to
-- one rim (no body, tire, brakes or other wheels, see stance.photoStrip). An offscreen render view
-- that only draws that car then shoots the rim face-on against a plain background, like a product
-- shot. One respawn per wheel; your own car, camera and the menu are not touched.
-- Photos are cached by part name, so cars that share wheels share photos.

local M = {}
M.dependencies = {"stanceStudio_jbeam", "stanceStudio_parts"}
local mp = require("ge/extensions/stanceStudio/mp")

local SETTLE = 0.5           -- real seconds after a respawn before aiming
local EXPOSE_FIRST = 1.0     -- a fresh render view needs a moment before post effects converge
local EXPOSE = 0.3
local STEP_TIMEOUT = 20      -- give up on one wheel after this many real seconds
local SIZE = 320             -- saved photo size (square)
local SUPERSAMPLE = 2
local FOV = 18
local BLANK_BYTES = 3000
local HELPER_NAME = "stanceStudio_photocar"
local VIEW_NAME = "stanceStudioRimView"
-- black background: it stays black whatever the exposure, the UI screens it onto its tile color
M.BG = {0, 0, 0}

local job = nil

local function getVeh()
  local veh = getPlayerVehicle(0)
  if not veh then return nil end
  local data = core_vehicle_manager.getVehicleData(veh:getID())
  if not data then return nil end
  return veh, data, veh:getID()
end

local function progress(extra)
  local msg = {
    running = job ~= nil,
    index = job and job.index or 0,
    total = job and #job.queue or 0,
    current = job and job.queue[job.index] and job.queue[job.index].name or nil,
    helper = job ~= nil,
  }
  if extra then for k, v in pairs(extra) do msg[k] = v end end
  guihooks.trigger("stanceStudioPhotos", msg)
end

local function findNode(tree, path)
  if tree.path == path then return tree end
  for _, child in pairs(tree.children or {}) do
    local found = findNode(child, path)
    if found then return found end
  end
end

-- MARK: render view

local function mainExposure()
  local mainView = RenderViewManagerInstance:getView("main")
  return mainView and mainView.currentExposure or nil
end

local function destroyView()
  if job and job.view then
    pcall(function() RenderViewManagerInstance:destroyView(job.view) end)
    job.view = nil
  end
end

local function ensureView(helper)
  if job.view then return job.view end
  local rv = RenderViewManagerInstance:getOrCreateView(VIEW_NAME)
  if not rv then return nil end
  rv.luaOwned = true
  rv.namedTexTargetColor = VIEW_NAME
  rv.renderCubemap = false
  rv.renderEditorIcons = false
  pcall(function() rv.renderEditorGizmo = false end)
  rv.usePostEffects = true
  rv.clearColor = ColorI(M.BG[1], M.BG[2], M.BG[3], 255)
  rv:enterFocusObjectsMode() -- draw only the photo car (no terrain, sky, traffic or markers)
  rv:addFocusObject(helper)
  local px = SIZE * SUPERSAMPLE
  rv.resolution = Point2I(px, px)
  rv.viewPort = RectI(0, 0, px, px)
  job.view = rv
  return rv
end

-- face-on camera on the kept rim
local function rimCamera(veh, vdata, report)
  local wheel = nil
  for _, w in pairs(vdata.wheels or {}) do
    if report and report.wheel and w.name == report.wheel then wheel = w; break end
  end
  if not wheel then
    -- front-left (jbeam +x = left, -y = front)
    local bestY = math.huge
    for _, w in pairs(vdata.wheels or {}) do
      local a, b = vdata.nodes[w.node1], vdata.nodes[w.node2]
      if a and b then
        local x, y = (a.pos.x + b.pos.x) * 0.5, (a.pos.y + b.pos.y) * 0.5
        if x > 0.02 and y < bestY then wheel, bestY = w, y end
      end
    end
  end
  if not wheel then return nil end
  local vehPos = vec3(veh:getPositionXYZ())
  local p1 = vehPos + vec3(veh:getNodePositionXYZ(wheel.node1))
  local p2 = vehPos + vec3(veh:getNodePositionXYZ(wheel.node2))
  local center = (p1 + p2) * 0.5
  local axis = p2 - p1
  if axis:length() < 1e-4 then return nil end
  axis = axis:normalized()
  -- look at the outside of the rim: the axis pointing away from the middle of all wheels
  local mid, n = vec3(0, 0, 0), 0
  for _, w in pairs(vdata.wheels or {}) do
    if w.node1 and w.node2 then
      mid = mid + vec3(veh:getNodePositionXYZ(w.node1)) + vec3(veh:getNodePositionXYZ(w.node2))
      n = n + 2
    end
  end
  if n > 0 and axis:dot(center - (vehPos + mid / n)) < 0 then axis = -axis end
  local up = vec3(veh:getDirectionVectorUpXYZ())
  up = up - axis * up:dot(axis)
  if up:length() < 1e-4 then up = vec3(0, 0, 1) end
  up = up:normalized()

  local rimR = (report and report.hubRadius) or tonumber(wheel.hubRadius)
  local tireR = (report and report.radius) or tonumber(wheel.radius) or 0.33
  if not rimR or rimR <= 0.05 or rimR > tireR then rimR = tireR * 0.72 end
  local half = rimR * 1.14 -- a little air around the lip
  local dist = half / math.tan(math.rad(FOV * 0.5))
  local pos = center + axis * dist
  return {pos = pos, rot = quatFromDir(-axis, up), dist = dist}
end

local function aim()
  local helper = getObjectByID(job.vehId)
  local data = helper and core_vehicle_manager.getVehicleData(job.vehId)
  if not helper or not data then return false end
  local jb = rawget(_G, "stanceStudio_jbeam")
  local report = jb and jb.reports[job.vehId]
  local cam = rimCamera(helper, data.vdata, report)
  if not cam then return false end
  local rv = ensureView(helper)
  if not rv then return false end
  local mat = QuatF(cam.rot.x, cam.rot.y, cam.rot.z, cam.rot.w):getMatrix()
  mat:setPosition(cam.pos)
  rv.cameraMatrix = mat
  local main = RenderViewManagerInstance:getView("main")
  local far = main and main.frustum and main.frustum:getFarDist() or 2000
  rv.frustum = Frustum.construct(false, math.rad(FOV), 1, math.max(0.05, cam.dist * 0.25), far)
  rv.fov = FOV
  local ev = mainExposure()
  if ev and ev > 0 then rv.currentExposure = ev end
  return true
end

local function save(pn)
  local final = stanceStudio_parts.photoPath(pn)
  local tmp = final .. ".tmp.png"
  FS:removeFile(tmp)
  local ok = false
  if job.view and job.view:saveToDisk(tmp) then
    local bmp = GBitmap()
    if bmp:loadFile(tmp) then
      bmp:setFormat(10) -- GFXFormatR8G8B8, same as the game's thumbnails
      local small = bmp:createDownscaledBitmap(SUPERSAMPLE)
      ok = small and small:saveFile(final) or false
    end
  end
  FS:removeFile(tmp)
  -- an empty frame compresses to a few hundred bytes; real rims are 50 KB and up
  if ok and (FS:fileSize(final) or 0) < BLANK_BYTES then
    FS:removeFile(final)
    writeFile(stanceStudio_parts.noPhotoPath(pn), "empty shot")
    log('I', 'stanceStudio', 'rim photo came out empty, skipping it from now on: ' .. tostring(pn))
    return false, true
  end
  return ok
end

-- MARK: job steps

local function finish(cancelled)
  local j = job
  if j then
    destroyView()
    local helper = getObjectByID(j.vehId)
    if helper then pcall(function() helper:delete() end) end
  end
  job = nil
  progress({done = true, cancelled = cancelled or false})
end

-- put the next wheel on the photo car
local nextPart
nextPart = function()
  if not job then return end
  job.index = job.index + 1
  if job.index > #job.queue then return finish(false) end
  local helper = getObjectByID(job.vehId)
  local data = helper and core_vehicle_manager.getVehicleData(job.vehId)
  if not helper or not data then return finish(true) end
  local item = job.queue[job.index]
  progress()
  local tree = deepcopy(data.config.partsTree)
  local node = findNode(tree, item.path)
  if not node then return nextPart() end
  node.chosenPartName = item.name
  if job.view then job.view.active = false end
  job.phase, job.timer = "spawning", STEP_TIMEOUT
  core_vehicle_partmgmt.setConfigOfVehicle(helper, {partsTree = tree, stanceStudio = {photo = {part = item.name}}}, true)
end

local function shoot()
  local pn = job.queue[job.index].name
  local ok, blank = save(pn)
  if ok then
    progress({photo = {name = pn, path = stanceStudio_parts.photoFor(pn)}})
  elseif not blank then
    log('W', 'stanceStudio', 'rim photo failed for ' .. tostring(pn))
  end
  nextPart()
end

-- somewhere on the ground behind the player, out of the way
local function helperSpot(veh)
  local pos = vec3(veh:getPositionXYZ())
  local fwd = vec3(veh:getDirectionVectorXYZ())
  local up = vec3(veh:getDirectionVectorUpXYZ())
  local spot = pos - fwd * 30
  local ground = be:getSurfaceHeightBelow(vec3(spot.x, spot.y, spot.z + 20))
  if type(ground) == "number" and ground > spot.z - 60 then spot.z = ground + 0.3 end
  return spot, quatFromDir(fwd, up)
end

-- onlyMissing: skip wheels that already have a photo
function M.start(onlyMissing)
  if job then return {ok = false, reason = "running"} end
  -- the helper car would be sent to the server like any other car: everyone would see it
  -- (BeamMP only: Tandem sends just the car you drive)
  if mp.beammp() then return {ok = false, reason = "multiplayer"} end
  local veh, vehData = getVeh()
  if not veh then log('I', 'stanceStudio', 'photo pass: no vehicle'); return {ok = false, reason = "novehicle"} end
  local wheels = stanceStudio_parts.getWheels()
  -- front (or all-wheel) slot first, then rear rims that have no front twin
  local first, rear = nil, nil
  for _, a in ipairs(wheels.axles or {}) do
    if a.axle == "F" or a.axle == "B" then first = first or a elseif a.axle == "R" then rear = a end
  end
  first = first or rear or (wheels.axles or {})[1]
  if not first then log('I', 'stanceStudio', 'photo pass: no wheel slots'); return {ok = false, reason = "nowheels"} end
  local queue, seen = {}, {}
  local function hasTwin(name)
    for _, twin in ipairs(stanceStudio_parts.photoTwins(name)) do
      if seen[twin] then return true end
    end
    return false
  end
  local function add(a)
    for _, o in ipairs(a.options) do
      local skip = seen[o.name] or (onlyMissing ~= false and (o.photo or o.noPhoto))
      if not skip then seen[o.name] = true end
      if not skip and not hasTwin(o.name) then
        seen[o.name] = true
        queue[#queue + 1] = {name = o.name, path = a.path}
      end
    end
  end
  add(first)
  if rear and rear ~= first then add(rear) end
  if #queue == 0 then
    progress({done = true})
    return {ok = true, total = 0}
  end
  FS:directoryCreate(stanceStudio_parts.PHOTO_DIR, true)

  -- spawn the photo car with the first wheel already on it
  local cfg = deepcopy(vehData.config)
  local node = findNode(cfg.partsTree, queue[1].path)
  if node then node.chosenPartName = queue[1].name end
  cfg.stanceStudio = {photo = {part = queue[1].name}}
  cfg.stanceStudioFun = false
  local pos, rot = helperSpot(veh)
  local model = stanceStudio_core.modelOf(vehData)
  if not model then log('W', 'stanceStudio', 'photo pass: unknown vehicle model'); return {ok = false, reason = "spawn"} end
  local ok, helper = pcall(core_vehicles.spawnNewVehicle, model, {
    config = serialize(cfg), pos = pos, rot = rot, autoEnterVehicle = false, vehicleName = HELPER_NAME,
  })
  if not ok or not helper then
    log('W', 'stanceStudio', 'photo car could not spawn: ' .. tostring(helper))
    return {ok = false, reason = "spawn"}
  end
  job = {vehId = helper:getID(), queue = queue, index = 1,
    phase = "spawning", timer = STEP_TIMEOUT, shots = 0}
  -- the spawn can finish inside spawnNewVehicle, before onVehicleSpawned could see the job
  if core_vehicle_manager.getVehicleData(job.vehId) then M.onVehicleSpawned(job.vehId) end
  log('I', 'stanceStudio', 'photo car spawned for ' .. #queue .. ' rims')
  progress()
  return {ok = true, total = #queue}
end

function M.cancel()
  if job then finish(true) end
end

function M.isRunning()
  return job ~= nil
end

function M.isHelper(vid)
  return job ~= nil and job.vehId == vid
end

function M.onVehicleSpawned(vid)
  if job and vid == job.vehId and job.phase == "spawning" then
    job.phase, job.timer = "settling", SETTLE
    -- hold it in place (same as the career part shop preview cars)
    local helper = getObjectByID(vid)
    if helper and core_vehicleBridge then
      pcall(core_vehicleBridge.executeAction, helper, 'setFreeze', true)
    end
  end
end

function M.onVehicleDestroyed(vid)
  if job and vid == job.vehId then
    destroyView()
    job = nil
    progress({done = true, cancelled = true})
  end
end

function M.onVehicleSwitched(oldId, newId)
  -- never leave the player in the photo car
  if job and newId == job.vehId and oldId and getObjectByID(oldId) then
    be:enterVehicle(0, getObjectByID(oldId))
  end
end

function M.onUpdate(dtReal)
  if not job or not job.timer then return end
  -- follow the rim every frame (the car may still settle or roll) and keep it lit like the main
  -- view (a lone object on an empty frame would otherwise blow out)
  if job.view and job.phase == "exposing" then aim() end
  job.timer = job.timer - (dtReal or 0)
  if job.timer > 0 then return end
  if job.phase == "settling" then
    if aim() then
      job.view.active = true
      job.phase = "exposing"
      job.timer = (job.shots == 0) and EXPOSE_FIRST or EXPOSE
    else
      log('W', 'stanceStudio', 'no rim to aim at for ' .. tostring(job.queue[job.index] and job.queue[job.index].name))
      nextPart()
    end
  elseif job.phase == "exposing" then
    job.shots = job.shots + 1
    shoot()
  elseif job.phase == "spawning" then
    log('W', 'stanceStudio', 'photo car respawn timed out for ' .. tostring(job.queue[job.index] and job.queue[job.index].name))
    nextPart()
  end
end

function M.onExtensionLoaded()
  setExtensionUnloadMode(M, "manual")
end

function M.onExtensionUnloaded()
  if job then finish(true) end
end

return M
