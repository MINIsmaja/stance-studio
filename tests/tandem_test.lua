-- Offline test of the Tandem support (stanceStudio/share.lua + the jbeam hook): Tandem sends a car to
-- friends as parts, tuning values (config.vars) and paint only, so the stance and the simple Fun
-- edits travel as tuning values. Checks that a friend's copy is built the same as your own car.
local G, MOD = os.getenv("G"), os.getenv("MOD")
package.path = G .. "/lua/common/?.lua;" .. G .. "/lua/?.lua;" .. MOD .. "/lua/?.lua;" .. package.path
require("mathlib"); table.clear = require("table.clear")
log = function() end
setExtensionUnloadMode = function() end
local function deepcopy(o)
  if type(o) ~= "table" then return o end
  local r = {}
  for k, v in pairs(o) do r[deepcopy(k)] = deepcopy(v) end
  return r
end

local fails = 0
local function check(name, cond, extra) if not cond then fails = fails + 1 end print((cond and "PASS " or "FAIL ") .. name .. (extra and ("  " .. extra) or "")) end

local share = require("ge/extensions/stanceStudio/share")
local hook = require("ge/extensions/stanceStudio/jbeam")
local fun = require("ge/extensions/stanceStudio/fun")

-- a small car: four wheels with springs, an engine
local function car()
  local nodes, rows, beams, cid = {}, {}, {}, 0
  local function N(x, y, z, group, w)
    nodes[cid] = {cid = cid, pos = vec3(x, y, z), group = group, nodeWeight = w}
    cid = cid + 1
    return cid - 1
  end
  local i = 0
  for _, k in ipairs({{"FR", -1, -1.4}, {"FL", 1, -1.4}, {"RR", -1, 1.4}, {"RL", 1, 1.4}}) do
    local a = N(k[2] * 0.7, k[3], 0.33, "wheelhub_" .. k[1], 10)
    local b = N(k[2] * 0.95, k[3], 0.33, "wheelhub_" .. k[1], 10)
    local top = N(k[2] * 0.6, k[3], 0.9, "body", 20)
    beams[#beams + 1] = {id1 = a, id2 = top, beamType = 6, beamSpring = 50000, beamDamp = 4000}
    rows[i] = {name = k[1], hubGroup = "wheel_" .. k[1], group = "tire_" .. k[1], node1 = b, node2 = a, radius = 0.33,
      frictionCoef = 1, brakeTorque = 2000}
    i = i + 1
  end
  return {nodes = nodes, beams = beams, pressureWheels = rows, flexbodies = {}, options = {},
    mainEngine = {maxRPM = 6500, revLimiterRPM = 6500, torque = {{"rpm", "torque"}, {0, 0}, {3000, 300}, {6500, 250}}}}
end

-- what Tandem's bridge does with your car's setup (beamngFriendsBridge.lua K.buildConfig + cleanConfig):
-- parts, at most 128 tuning values (finite, up to 1e8, names up to 100 letters) and paint. Nothing else.
local function tandemCopy(config)
  local out, n = {}, 0
  local vars = {}
  for k, v in pairs(config.vars or {}) do
    if n < 128 and type(k) == "string" and #k <= 100 and type(v) == "number" and v == v and math.abs(v) <= 1e8 then
      vars[k], n = v, n + 1
    end
  end
  if next(vars) then out.vars = vars end
  if config.parts then out.parts = deepcopy(config.parts) end
  return out
end
local function spawn(id, cfg) local v = car(); hook.onJbeamLoadingPhase1(nil, id, v, nil, deepcopy(cfg), nil); return v end
local function sameGeometry(a, b)
  local worst = 0
  for cid, n in pairs(a.nodes) do worst = math.max(worst, (n.pos - b.nodes[cid].pos):length()) end
  return worst < 1e-9, string.format("%.3g m", worst)
end
local function edits(list) local t = {} for _, e in ipairs(list) do t[fun.idOf(e)] = e end return {v = 1, edits = t} end
local function countOurs(vars) local n = 0 for k in pairs(vars or {}) do if k:sub(1, #share.PREFIX) == share.PREFIX then n = n + 1 end end return n end

-- 1) what gets written
check("neutral stance: no tuning values", next(share.stanceVars({F = {}, R = {}})) == nil)
check("photo car: no tuning values", next(share.stanceVars({photo = {part = "x"}})) == nil)
local sv = share.stanceVars({F = {camber = -3, rideHeight = -0.06}, method = "hub", gain = {R = 1.3}})
check("only what differs from stock", sv["$stanceStudio_F_camber"] == -3 and sv["$stanceStudio_F_rideHeight"] == -0.06
  and sv["$stanceStudio_method"] == 2 and sv["$stanceStudio_R_gain"] == 1.3 and sv["$stanceStudio_R_camber"] == nil
  and sv["$stanceStudio_F_spring"] == nil)

-- 2) your car with a stance and Fun edits, and the copy Tandem gives your friend
local mine = {
  vars = {["$tirepressure_F"] = 30, ["$revLimiterRPM"] = 7000}, -- the car's own tuning values
  stanceStudio = {F = {camber = -4, rideHeight = -0.07, offset = 0.03, toe = 0.2}, R = {rideHeight = -0.05, camber = -2},
    hubExtra = {F = 0.01}, gain = {F = 1.2}},
  stanceStudioFun = edits{
    {kind = "quick", name = "indestructibleEngine", engine = "mainEngine", value = true},
    {kind = "quick", name = "maxRPM", engine = "mainEngine", value = 9000},
    {kind = "quick", name = "weight", scale = 2},
    {kind = "quick", name = "grip", scale = 1.5},
    {kind = "quick", name = "unbreakable", value = false}, -- switched off: not sent
    {kind = "quick", name = "curve", engine = "mainEngine", rows = {{0, 0}, {3000, 3000}, {9000, 2500}}}, -- not sent
    {kind = "value", path = {"mainEngine", "revLimiterRPM"}, value = 8000}, -- Advanced: not sent
  },
}
check("write: changed", share.write(mine, {"mainEngine"}) == true)
check("write: nothing more the second time", share.write(mine, {"mainEngine"}) == false)
check("the car's own tuning values are kept", mine.vars["$tirepressure_F"] == 30 and mine.vars["$revLimiterRPM"] == 7000)
local ok = true
for k, v in pairs(mine.vars) do
  if not (type(v) == "number" and v == v and math.abs(v) <= 1e8 and #k <= 100) then ok = false end
end
check("every value fits Tandem's rules", ok)
check("a handful of values (" .. countOurs(mine.vars) .. ")", countOurs(mine.vars) <= 16)

local theirs = tandemCopy(mine)
check("Tandem's copy has no stanceStudio keys", theirs.stanceStudio == nil and theirs.stanceStudioFun == nil)
local a = spawn(201, mine)
local b = spawn(202, theirs)
local same, worst = sameGeometry(a, b)
check("friend's copy: same stance geometry", same, worst)
check("friend's copy: stance report", hook.reports[202] and hook.reports[202].wheelCount == 4)
check("friend's copy: indestructible engine and max RPM", b.mainEngine.maxTorqueRating == -1 and b.mainEngine.maxRPM == 9000)
check("friend's copy: weight and grip", b.nodes[0].nodeWeight == 20 and b.pressureWheels[0].frictionCoef == 1.5)
check("friend's copy: no curve or Advanced edits", b.mainEngine.torque[3][2] == 300 and a.mainEngine.torque[3][2] == 3000
  and b.mainEngine.revLimiterRPM ~= 8000)
check("friend's copy: 4 Fun edits", hook.funReports[202] and hook.funReports[202].applied == 4, hook.funReports[202] and tostring(hook.funReports[202].applied))

-- 3) you reset the Fun edits (core writes false)
mine.stanceStudioFun = false
share.write(mine, {"mainEngine"})
b = spawn(203, tandemCopy(mine))
check("Fun reset reaches the friend", b.mainEngine.maxRPM == 6500 and hook.funReports[203] == nil and hook.reports[203].wheelCount == 4)

-- 4) back to a stock stance
mine.stanceStudio = {F = {}, R = {}}
share.write(mine, {"mainEngine"})
check("stock stance: no values left, own values kept", countOurs(mine.vars) == 0 and mine.vars["$tirepressure_F"] == 30)
b = spawn(204, tandemCopy(mine))
check("stock stance reaches the friend", hook.reports[204] == nil and sameGeometry(b, car()))

-- 5) the keys win over the tuning values (your own car, a BeamMP copy)
local stale = {stanceStudio = false, stanceStudioFun = false,
  vars = {["$stanceStudio_F_camber"] = -10, ["$stanceStudio_q_weight_0"] = 5}}
b = spawn(205, stale)
check("false keys: tuning values ignored", hook.reports[205] == nil and hook.funReports[205] == nil and b.nodes[0].nodeWeight == 10)
local own = {stanceStudio = {F = {camber = -1}}, vars = {["$stanceStudio_F_camber"] = -10}}
spawn(206, own)
local c = spawn(207, {stanceStudio = {F = {camber = -1}}})
check("table key: tuning values ignored", sameGeometry(spawn(208, own), c))

-- 6) a car with two engines: edits find theirs by place in the sorted list
local fv = share.funVars(edits{{kind = "quick", name = "boost", engine = "rearEngine", psi = 25},
  {kind = "quick", name = "boost", engine = "gone", psi = 9}}, {"frontEngine", "rearEngine"})
check("engine by place", fv["$stanceStudio_q_boost_2"] == 25 and countOurs(fv) == 1)
local _, f2 = share.read(fv, {"frontEngine", "rearEngine"})
local e2 = f2 and f2.edits[fun.quickId("boost", "rearEngine")]
check("read back for the same engine", e2 and e2.psi == 25 and e2.engine == "rearEngine")
local _, f3 = share.read(fv, {"frontEngine"})
check("an engine the car doesn't have is skipped", f3 == nil)
check("infinite values are not sent", next(share.funVars(edits{{kind = "quick", name = "maxRPM", engine = "e", value = "FLT_MAX"}}, {"e"})) == nil)

-- 7) junk in the tuning values never breaks loading
b = spawn(209, {vars = {["$stanceStudio_X_camber"] = 1, ["$stanceStudio_q_nope_0"] = 1, ["$stanceStudio_F_camber"] = 999}})
check("junk names skipped, values clamped", hook.reports[209] and hook.reports[209].wheelCount == 4 and hook.funReports[209] == nil)

print(fails == 0 and "ALL PASSED" or (fails .. " FAILED"))
