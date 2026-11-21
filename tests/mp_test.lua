-- Offline test of the BeamMP (multiplayer) support: stanceStudio/mp.lua, the config round trip a car
-- takes to the other players (BeamMP sends the config and merges edits key by key into its copy),
-- and the guards in core.lua (someone else's car, world settings, false markers).
local G, MOD = os.getenv("G"), os.getenv("MOD")
package.path = G .. "/lua/common/?.lua;" .. G .. "/lua/?.lua;" .. MOD .. "/lua/?.lua;" .. package.path
require("mathlib"); table.clear = require("table.clear")
log = function() end
setExtensionUnloadMode = function() end
local toasts = {}
guihooks = {trigger = function(name, data) if name == "toastrMsg" then toasts[#toasts + 1] = data.msg end end}
function deepcopy(o)
  if type(o) ~= "table" then return o end
  local r = {}
  for k, v in pairs(o) do r[deepcopy(k)] = deepcopy(v) end
  return r
end

local fails = 0
local function check(name, cond, extra) if not cond then fails = fails + 1 end print((cond and "PASS " or "FAIL ") .. name .. (extra and ("  " .. extra) or "")) end

local mp = require("ge/extensions/stanceStudio/mp")
local hook = require("ge/extensions/stanceStudio/jbeam")
local fun = require("ge/extensions/stanceStudio/fun")

-- MARK: BeamMP stand-ins (same functions the real MPCoreNetwork / MPVehicleGE export)
local session = false
local cars = { -- gameVehicleID -> {sid, own, owner}
  [10] = {sid = "1-0", own = true, owner = "Me"},
  [20] = {sid = "2-0", own = false, owner = "Bob"},
}
local function beammp(on)
  if on then
    MPCoreNetwork = {isMPSession = function() return session end}
    MPVehicleGE = {
      isOwn = function(id) return cars[id] and cars[id].own or false end,
      getServerVehicleID = function(id) return cars[id] and cars[id].sid or nil end,
      getVehicleByGameID = function(id)
        local c = cars[id]
        return c and {ownerName = c.owner, getOwner = function() return {name = c.owner} end} or nil
      end,
    }
  else
    MPCoreNetwork, MPVehicleGE = nil, nil
  end
end

-- 1) singleplayer: no BeamMP at all
beammp(false)
check("no BeamMP: singleplayer", not mp.active() and not mp.isRemote(20) and not mp.isOwn(10) and mp.blockReason(20) == nil)
beammp(true)
session = false
check("BeamMP loaded, not on a server: singleplayer", not mp.active() and not mp.isRemote(20))
session = true
check("on a server", mp.active())
check("own car is not remote", not mp.isRemote(10) and mp.isOwn(10))
check("other player's car is remote", mp.isRemote(20) and not mp.isOwn(20))
check("a car BeamMP doesn't know yet is not remote", not mp.isRemote(30) and not mp.isOwn(30))
check("block reason names the owner", (mp.blockReason(20) or ""):find("Bob's car", 1, true) ~= nil, mp.blockReason(20))
MPVehicleGE.isOwn = function() error("boom") end
check("a BeamMP error counts as not remote", not mp.isRemote(20))
beammp(true)
local c = {stanceStudio = {F = {camber = -1}}}
check("fillMissing adds false for the missing key only", mp.fillMissing(c) and c.stanceStudioFun == false and type(c.stanceStudio) == "table")
check("fillMissing: nothing to do the second time", not mp.fillMissing(c))

-- MARK: 2) the round trip to another player's screen
-- a small car: four wheels, an engine
local function car()
  local nodes, rows, cid = {}, {}, 0
  local function N(x, y, z, group, w)
    nodes[cid] = {cid = cid, pos = vec3(x, y, z), group = group, nodeWeight = w}
    cid = cid + 1
    return cid - 1
  end
  local i = 0
  for _, k in ipairs({{"FR", -1, -1.4}, {"FL", 1, -1.4}, {"RR", -1, 1.4}, {"RL", 1, 1.4}}) do
    local a = N(k[2] * 0.7, k[3], 0.33, "wheelhub_" .. k[1], 10)
    local b = N(k[2] * 0.95, k[3], 0.33, "wheelhub_" .. k[1], 10)
    rows[i] = {name = k[1], hubGroup = "wheel_" .. k[1], group = "tire_" .. k[1], node1 = b, node2 = a, radius = 0.33}
    i = i + 1
  end
  return {nodes = nodes, beams = {}, pressureWheels = rows, flexbodies = {}, options = {},
    mainEngine = {maxRPM = 6500, torque = {{"rpm", "torque"}, {0, 0}, {3000, 300}}}}
end
local function edits(list) local t = {} for _, e in ipairs(list) do t[fun.idOf(e)] = e end return {v = 1, edits = t} end
-- what BeamMP does: sendVehicleEdit sends a copy of the config, applyVehEdit runs the game's
-- tableMerge (one level: config[key] = value) into its copy, then respawns the car with it
local function send(cfg) return deepcopy(cfg) end
local function merge(dst, src) for k, v in pairs(src) do dst[k] = v end return dst end
local function spawn(id, cfg) local v = car(); hook.onJbeamLoadingPhase1(nil, id, v, nil, deepcopy(cfg), nil); return v end

local mine = {
  stanceStudio = {F = {camber = -3}},
  stanceStudioFun = edits{{kind = "value", path = {"mainEngine", "maxRPM"}, value = 20000}},
}
local theirs = send(mine)
local v = spawn(101, theirs)
check("their copy: edits and stance", v.mainEngine.maxRPM == 20000 and hook.reports[101] and hook.reports[101].wheelCount == 4)

-- you reset the Fun edits: core.funApply writes false
mine.stanceStudioFun = false
merge(theirs, send(mine))
v = spawn(102, theirs)
check("reset reaches them (false)", v.mainEngine.maxRPM == 6500 and hook.funReports[102] == nil)

-- the old way (nil) is what broke: the key isn't sent, their copy keeps the old edits
local old = merge(send({stanceStudioFun = edits{{kind = "value", path = {"mainEngine", "maxRPM"}, value = 20000}}}), {})
local oldMine = {stanceStudio = {F = {camber = -3}}}
merge(old, send(oldMine))
v = spawn(103, old)
check("(control) nil keeps the old edits on their screen", v.mainEngine.maxRPM == 20000)

-- you load a stock config (no Stance Studio keys): on spawn core fills false for both
mine = {}
mp.fillMissing(mine)
merge(theirs, send(mine))
v = spawn(104, theirs)
check("stock config reaches them", v.mainEngine.maxRPM == 6500 and hook.reports[104] == nil and hook.funReports[104] == nil)

-- new edits again after that
mine.stanceStudioFun = edits{{kind = "quick", name = "indestructibleEngine", value = true}}
mine.stanceStudio = {R = {rideHeight = -0.05}}
merge(theirs, send(mine))
v = spawn(105, theirs)
check("later edits reach them", v.mainEngine.maxTorqueRating == -1 and hook.reports[105] and hook.reports[105].wheelCount == 4)

-- MARK: 3) core.lua guards (with stand-ins for the game)
local setConfigCalls, gravity, speed = {}, -9.81, 1
local configs = {
  [10] = {config = {stanceStudioFun = edits{{kind = "value", path = {"mainEngine", "maxRPM"}, value = 20000}}}, vdata = {model = "pickup"}},
  [20] = {config = {}, vdata = {model = "etk800"}},
}
for id, d in pairs(configs) do d.id = id end
local playerId = 10
local function vehObj(id)
  return {getID = function() return id end, getVelocity = function() return vec3(10, 0, 0) end, queueLuaCommand = function() end}
end
getPlayerVehicle = function() return vehObj(playerId) end
getObjectByID = function() return nil end
core_vehicle_manager = {getVehicleData = function(id) return configs[id] end}
core_vehicle_partmgmt = {setConfig = function(data, respawn)
  setConfigCalls[#setConfigCalls + 1] = data
  merge(configs[playerId].config, data)
end}
core_environment = {getGravity = function() return gravity end, setGravity = function(g) gravity = g end}
simTimeAuthority = {get = function() return speed end, set = function(s) speed = s end}
stanceStudio_preview = {clear = function() end, setPending = function() end}
stanceStudio_photos = {isRunning = function() return false end, cancel = function() end}
jsonReadFile = function() return nil end
jsonWriteFile = function() end
getMissionFilename = function() return "levels/gridmap_v2/info.json" end
local navigated = nil
extensions = {ui_router = {navigate = function(r) navigated = r end}}
local core = require("ge/extensions/stanceStudio/core")
core.onExtensionLoaded()

-- singleplayer: the world settings work, a reset writes false
beammp(false)
core.funSetGravity(-1.62)
check("singleplayer: gravity changes", gravity == -1.62)
core.funSetGravity(-9.81)
core.funApply({})
check("reset writes false, not nil", configs[10].config.stanceStudioFun == false and setConfigCalls[1] and setConfigCalls[1].stanceStudioFun == false)

-- multiplayer
beammp(true)
session = true
toasts = {}
core.funSetGravity(-1.62)
core.funSetSimSpeed(0.25)
check("multiplayer: no gravity or time speed", gravity == -9.81 and speed == 1 and #toasts == 2)
check("funWorld says multiplayer", core.funWorld().multiplayer == true)

-- your own car, second spawn: the missing key gets false (the config was {stanceStudioFun = false})
configs[10].config = {}
core.onVehicleSpawned(10)
check("own car: false for both keys", configs[10].config.stanceStudio == false and configs[10].config.stanceStudioFun == false)
core.onVehicleSpawned(20)
check("someone else's car: config untouched", next(configs[20].config) == nil)
local st = core.getState()
check("state: multiplayer, own car", st.multiplayer == "beammp" and st.vehicle and not st.vehicle.remote)

-- sitting in Bob's car
playerId = 20
toasts = {}
local before = #setConfigCalls
core.funApply({{kind = "quick", name = "indestructibleEngine", value = true}})
core.applyStance({F = {camber = -2}})
check("Bob's car: no changes", #setConfigCalls == before and next(configs[20].config) == nil)
check("Bob's car: says why", #toasts == 2 and toasts[1]:find("Bob's car", 1, true) ~= nil, toasts[1])
st = core.getState()
check("state: remote car with owner", st.vehicle and st.vehicle.remote == true and st.vehicle.owner == "Bob")
navigated = nil
core.open()
check("menu doesn't open in Bob's car", navigated == nil)
playerId = 10
core.open()
check("menu opens in your own car", navigated == "stanceStudio")

-- MARK: 4) Tandem (its bridge extension is loaded, no BeamMP session)
session = false
beammp(false)
beamngFriendsBridge = {}
check("Tandem is multiplayer", mp.tandem() and mp.active() and mp.kind() == "tandem" and not mp.beammp())
st = core.getState()
check("state says tandem", st.multiplayer == "tandem")
toasts = {}
core.funSetGravity(-1.62)
check("Tandem: no gravity", gravity == -9.81 and #toasts == 1)
-- your car: core keeps the tuning-value copy (what Tandem sends) in step after every spawn
configs[10].config = {vars = {["$tirepressure_F"] = 30}, stanceStudio = {F = {camber = -2}}, stanceStudioFun = false}
core.onVehicleSpawned(10)
local vars = configs[10].config.vars
check("own car: stance copied into tuning values", vars["$stanceStudio_F_camber"] == -2 and vars["$tirepressure_F"] == 30)
-- a friend's copy (Tandem spawns it with tuning values only): left as it came
configs[20].config = {vars = {["$stanceStudio_F_camber"] = -5}}
core.onVehicleSpawned(20)
check("friend's copy: tuning values untouched", configs[20].config.vars["$stanceStudio_F_camber"] == -5 and configs[20].config.stanceStudio == nil)
-- applying a stance writes the copy before the respawn
playerId = 10
before = #setConfigCalls
core.applyStance({F = {camber = -3}})
local sent = setConfigCalls[#setConfigCalls]
check("apply sends the copy with the config", #setConfigCalls == before + 1 and sent.vars and sent.vars["$stanceStudio_F_camber"] == -3)
core.funApply({{kind = "quick", name = "weight", scale = 3}})
sent = setConfigCalls[#setConfigCalls]
check("Fun edits too", sent.vars and sent.vars["$stanceStudio_q_weight_0"] == 3 and sent.vars["$stanceStudio_F_camber"] == -3)
core.funApply({})
sent = setConfigCalls[#setConfigCalls]
check("and their reset", sent.vars and sent.vars["$stanceStudio_q_weight_0"] == nil and sent.stanceStudioFun == false)
beamngFriendsBridge = nil

print(fails == 0 and "ALL PASSED" or (fails .. " FAILED"))
