-- Stance Studio: hooks the jbeam loader (same hook as the game's lua/common/extensions/jbeam/jbeamMod.lua)
-- and applies the stance stored in vehicleConfig.stanceStudio to every vehicle that has one.

local M = {}

local stance = require("ge/extensions/stanceStudio/stance")

-- objID -> report of the last spawn (which method each corner used)
M.reports = {}
-- objID -> stock size of the vehicle ({height, tireRadius}), measured before any stance edits
M.sizes = {}

local function onJbeamLoadingPhase1(loadingProgress, objID, vehicle, unifyJournal, vehicleConfig, vars)
  local okSize, size = pcall(stance.measureSize, vehicle)
  M.sizes[objID] = okSize and size or nil
  local raw = type(vehicleConfig) == "table" and vehicleConfig.stanceStudio or nil
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
end

local function onExtensionLoaded()
  setExtensionUnloadMode(M, "manual")
end

M.onJbeamLoadingPhase1 = onJbeamLoadingPhase1
M.onVehicleDestroyed = onVehicleDestroyed
M.onExtensionLoaded = onExtensionLoaded

return M
