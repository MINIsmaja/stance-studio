-- Offline test of the jbeam phase-1 hook (stanceStudio/jbeam.lua): "Fun stuff" edits and stance together.
local G, MOD = os.getenv("G"), os.getenv("MOD")
package.path = G .. "/lua/common/?.lua;" .. G .. "/lua/?.lua;" .. MOD .. "/lua/?.lua;" .. package.path
require("mathlib"); table.clear = require("table.clear")
log = function() end
setExtensionUnloadMode = function() end
local hook = require("ge/extensions/stanceStudio/jbeam")
local fun = require("ge/extensions/stanceStudio/fun")
local fails = 0
local function check(name, cond, extra) if not cond then fails = fails + 1 end print((cond and "PASS " or "FAIL ") .. name .. (extra and ("  " .. extra) or "")) end

-- a small car: four wheels, a body node, an engine section
local function car()
  local nodes, rows, cid = {}, {}, 0
  local function N(x, y, z, group, w)
    nodes[cid] = {cid = cid, pos = vec3(x, y, z), group = group, nodeWeight = w}
    cid = cid + 1
    return cid - 1
  end
  local i = 0
  for _, c in ipairs({{"FR", -1, -1.4}, {"FL", 1, -1.4}, {"RR", -1, 1.4}, {"RL", 1, 1.4}}) do
    local a = N(c[2] * 0.7, c[3], 0.33, "wheelhub_" .. c[1], 10)
    local b = N(c[2] * 0.95, c[3], 0.33, "wheelhub_" .. c[1], 10)
    rows[i] = {name = c[1], hubGroup = "wheel_" .. c[1], group = "tire_" .. c[1], node1 = b, node2 = a, radius = 0.33, brakeTorque = 2000}
    i = i + 1
  end
  N(0, 0, 1.4, "body", nil) -- roof, no weight: 25 kg default
  return {nodes = nodes, beams = {}, pressureWheels = rows, flexbodies = {}, options = {},
    mainEngine = {maxRPM = 6500, torque = {{"rpm", "torque"}, {0, 0}, {3000, 300}}}}
end

local function edits(list) local t = {} for _, e in ipairs(list) do t[fun.idOf(e)] = e end return {v = 1, edits = t} end

-- 1) edits + stance
local v = car()
local cfg = {
  stanceStudioFun = edits{
    {kind = "value", path = {"mainEngine", "maxRPM"}, value = 20000},
    {kind = "rows", section = "nodes", field = "nodeWeight", scale = 2},
    {kind = "column", path = {"mainEngine", "torque"}, column = 2, scale = 1000},
  },
  stanceStudio = {F = {camber = -3}},
}
hook.onJbeamLoadingPhase1(nil, 1, v, nil, cfg, nil)
check("edit applied", v.mainEngine.maxRPM == 20000 and v.mainEngine.torque[3][2] == 300000)
check("node weights doubled", v.nodes[0].nodeWeight == 20 and v.nodes[8].nodeWeight == 50, tostring(v.nodes[8].nodeWeight))
local rep = hook.funReports[1]
check("report: 3 applied", rep and rep.applied == 3 and #rep.missed == 0, rep and (rep.applied .. "/" .. #rep.missed))
check("stock mass measured before the edits", hook.sizes[1] and math.abs(hook.sizes[1].mass - (8 * 10 + 25)) < 1e-9, hook.sizes[1] and tostring(hook.sizes[1].mass))
check("stance still applied", hook.reports[1] and hook.reports[1].wheelCount == 4)

-- 2) the wheel photo car never gets the edits
v = car()
cfg.stanceStudio = {photo = {part = "nothing"}}
hook.onJbeamLoadingPhase1(nil, 2, v, nil, cfg, nil)
check("photo car: no edits", v.mainEngine.maxRPM == 6500 and hook.funReports[2] == nil)

-- 3) edits without any stance
v = car()
hook.onJbeamLoadingPhase1(nil, 3, v, nil, {stanceStudioFun = edits{{kind = "row", section = "pressureWheels", row = "RL", field = "brakeTorque", value = 1}}}, nil)
check("edits without stance", v.pressureWheels[3].brakeTorque == 1 and v.pressureWheels[0].brakeTorque == 2000 and hook.reports[3] == nil)

-- 4) a broken edit list does not stop the car from loading
v = car()
hook.onJbeamLoadingPhase1(nil, 4, v, nil, {stanceStudioFun = {edits = {x = {kind = "value", path = "not a list"}, y = 5}}}, nil)
check("junk edits are skipped", hook.funReports[4] and hook.funReports[4].applied == 0 and v.mainEngine.maxRPM == 6500)

-- 5) cleanup
hook.onVehicleDestroyed(1)
check("report dropped with the car", hook.funReports[1] == nil and hook.sizes[1] == nil)

print(fails == 0 and "ALL PASSED" or (fails .. " FAILED"))
