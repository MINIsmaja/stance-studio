-- Stance Studio: BeamMP (multiplayer) support. Everything here is optional: without BeamMP every
-- check says "singleplayer" and nothing changes.
--
-- How a car's stance reaches the other players: BeamMP sends your car's whole config (with
-- config.stanceStudio and config.stanceStudioFun in it) when you spawn it and ~15 s after every
-- respawn, and every player who has this mod (the server hands it out from Resources/Client)
-- spawns your car with it, so the jbeam hook builds the same stanced car on their screen.
-- BeamMP merges an edit into the copy it has with a shallow merge (config[key] = value), so a key
-- you remove never reaches them: their copy keeps the old one. That is why these keys are set to
-- false instead of nil (see M.fillMissing and core.funApply).

local M = {}

M.KEYS = {"stanceStudio", "stanceStudioFun"}

-- true while connected to a BeamMP server
function M.active()
  local net = rawget(_G, "MPCoreNetwork")
  if not (type(net) == "table" and type(net.isMPSession) == "function") then return false end
  local ok, res = pcall(net.isMPSession)
  return ok and res == true
end

-- true for another player's car on your screen. A car BeamMP doesn't know yet (your own car while
-- it spawns, or someone's car that is still loading) counts as not remote.
function M.isRemote(vid)
  if not vid or not M.active() then return false end
  local mpv = rawget(_G, "MPVehicleGE")
  if not (type(mpv) == "table" and type(mpv.isOwn) == "function") then return false end
  if type(mpv.getServerVehicleID) == "function" then
    local ok, sid = pcall(mpv.getServerVehicleID, vid)
    if ok and sid == nil then return false end
  end
  local ok, own = pcall(mpv.isOwn, vid)
  return ok and own == false
end

-- true for your own car once BeamMP has registered it (from the second spawn on)
function M.isOwn(vid)
  if not vid or not M.active() then return false end
  local mpv = rawget(_G, "MPVehicleGE")
  if not (type(mpv) == "table" and type(mpv.isOwn) == "function") then return false end
  local ok, own = pcall(mpv.isOwn, vid)
  return ok and own == true
end

-- name of the player who owns a car, if BeamMP knows it
function M.ownerName(vid)
  local mpv = rawget(_G, "MPVehicleGE")
  if not (type(mpv) == "table" and type(mpv.getVehicleByGameID) == "function") then return nil end
  local ok, name = pcall(function()
    local v = mpv.getVehicleByGameID(vid)
    local owner = v and v.getOwner and v:getOwner()
    return (owner and owner.name) or (v and v.ownerName)
  end)
  return ok and type(name) == "string" and name ~= "" and name or nil
end

-- why this car can't be edited right now, or nil
function M.blockReason(vid)
  if M.isRemote(vid) then
    local owner = M.ownerName(vid)
    return (owner and (owner .. "'s car") or "This car belongs to another player")
      .. ": in multiplayer you can only change your own car."
  end
  return nil
end

-- shows the reason as a toast and returns true when the car can't be edited
function M.blocked(vid)
  local why = M.blockReason(vid)
  if why then
    guihooks.trigger("toastrMsg", {type = "warning", title = "Stance Studio", msg = why})
    return true
  end
  return false
end

-- own car in multiplayer: write false for our keys the config doesn't have. Loading a config
-- without them (a stock .pc, the game's own config menu) would otherwise leave the old stance and
-- edits on the other players' copy of the car (see the top of this file). Only the stored config
-- changes, the car is not respawned: false means the same as "none" everywhere in this mod.
function M.fillMissing(config)
  if type(config) ~= "table" then return false end
  local changed = false
  for _, k in ipairs(M.KEYS) do
    if config[k] == nil then
      config[k] = false
      changed = true
    end
  end
  return changed
end

return M
