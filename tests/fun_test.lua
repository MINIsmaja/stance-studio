-- Offline tests for the "Fun stuff" JBeam editor (stanceStudio/fun.lua).
local MOD = os.getenv("MOD")
package.path = MOD .. "/lua/?.lua;" .. package.path
local fun = require("ge/extensions/stanceStudio/fun")
local fails = 0
local function check(name, cond, extra) if not cond then fails = fails + 1 end print((cond and "PASS " or "FAIL ") .. name .. (extra and ("  " .. extra) or "")) end

local function car()
  local v = {
    options = {},
    information = {name = "Test"},
    mainEngine = {
      torque = {{"rpm", "torque"}, {0, 0}, {1000, 150}, {3000, 300}, {6000, 250}},
      maxRPM = 6500, idleRPM = 800, inertia = 0.12, hasFuelCut = true, fuel = "gasoline",
      particulates = {enabled = false, rate = 0.5},
      maxTorqueRating = 400,
    },
    gearbox = {gearRatios = {-3.5, 0, 3.6, 2.1, 1.4, 1.0}},
    turbocharger = {wastegateStart = 1.2},
    nodes = {
      [0] = {name = "n1", nodeWeight = 10, posX = 0, posY = 0, posZ = 0},
      [1] = {name = "n2", posX = 1, posY = 0, posZ = 0}, -- no weight: loader default 25
      [2] = {name = "n3", nodeWeight = 5, posX = 2, posY = 0, posZ = 0},
    },
    beams = {
      [0] = {id1 = 0, id2 = 1, beamSpring = 1000, beamStrength = math.huge},
      [1] = {id1 = 1, id2 = 2, beamSpring = 2000, beamStrength = 500},
    },
    pressureWheels = {
      [0] = {name = "FL", brakeTorque = 2000, radius = 0.33, node1 = 0, node2 = 1, hasTire = true},
      [1] = {name = "FR", brakeTorque = 2000, radius = 0.33, node1 = 1, node2 = 2, hasTire = true},
    },
    maxIDs = {nodes = 3},
  }
  return v
end

local function ed(list) local t = {} for _, e in ipairs(list) do t[fun.idOf(e)] = e end return {v = 1, edits = t} end

-- 1) single values
local v = car()
local rep = fun.apply(v, ed{
  {kind = "value", path = {"mainEngine", "maxRPM"}, value = 20000},
  {kind = "value", path = {"mainEngine", "hasFuelCut"}, value = false},
  {kind = "value", path = {"mainEngine", "fuel"}, value = "diesel"},
  {kind = "value", path = {"mainEngine", "particulates", "rate"}, value = 0},
  {kind = "value", path = {"gearbox", "gearRatios", 3}, value = 5},
  {kind = "value", path = {"mainEngine", "maxTorqueRating"}, value = "FLT_MAX"},
})
check("number set", v.mainEngine.maxRPM == 20000)
check("bool set", v.mainEngine.hasFuelCut == false)
check("text set", v.mainEngine.fuel == "diesel")
check("nested set", v.mainEngine.particulates.rate == 0)
check("list element set", v.gearbox.gearRatios[3] == 5 and v.gearbox.gearRatios[4] == 2.1)
check("FLT_MAX becomes infinite", v.mainEngine.maxTorqueRating == math.huge)
check("all applied", rep.applied == 6 and #rep.missed == 0, rep.applied .. " / missed " .. #rep.missed)
check("stock kept for the menu", rep.original[fun.valueId({"mainEngine", "maxRPM"})] == 6500)

-- 2) torque column x1000 (the 1,000,000 hp way)
v = car()
rep = fun.apply(v, ed{{kind = "column", path = {"mainEngine", "torque"}, column = 2, scale = 1000}})
check("torque column scaled", v.mainEngine.torque[4][2] == 300000 and v.mainEngine.torque[3][2] == 150000)
check("rpm column untouched", v.mainEngine.torque[4][1] == 3000)
check("header untouched", v.mainEngine.torque[1][2] == "torque")

-- 3) rows: every beam, every node (with the loader default for nodes without a weight)
v = car()
rep = fun.apply(v, ed{
  {kind = "rows", section = "beams", field = "beamSpring", scale = 2},
  {kind = "rows", section = "beams", field = "beamStrength", scale = 0},
  {kind = "rows", section = "nodes", field = "nodeWeight", scale = 0.5},
})
check("beams spring x2", v.beams[0].beamSpring == 2000 and v.beams[1].beamSpring == 4000)
check("infinite strength stays infinite at x0", v.beams[0].beamStrength == math.huge and v.beams[1].beamStrength == 0)
check("node weights x0.5 incl. default", v.nodes[0].nodeWeight == 5 and v.nodes[1].nodeWeight == 12.5 and v.nodes[2].nodeWeight == 2.5)
check("positions untouched", v.nodes[1].posX == 1)

-- 4) one row by name
v = car()
rep = fun.apply(v, ed{{kind = "row", section = "pressureWheels", row = "FR", field = "brakeTorque", value = 9000}})
check("FR brakes only", v.pressureWheels[1].brakeTorque == 9000 and v.pressureWheels[0].brakeTorque == 2000)
check("row stock kept", rep.original[fun.rowId("pressureWheels", "FR", "brakeTorque")] == 2000)

-- 5) refusals: missing paths, references, wrong types
v = car()
rep = fun.apply(v, ed{
  {kind = "value", path = {"mainEngine", "doesNotExist"}, value = 1},
  {kind = "value", path = {"nope", "x"}, value = 1},
  {kind = "value", path = {"mainEngine", "maxRPM"}, value = "abc"},
  {kind = "rows", section = "beams", field = "id1", scale = 2},
  {kind = "row", section = "pressureWheels", row = "FR", field = "node1", value = 5},
  {kind = "column", path = {"gearbox", "gearRatios"}, column = 1, scale = 2},
})
check("nothing applied", rep.applied == 0 and #rep.missed == 6, rep.applied .. " / " .. #rep.missed)
check("car untouched", v.mainEngine.maxRPM == 6500 and v.beams[0].id1 == 0 and v.pressureWheels[1].node1 == 1)
check("no new keys", v.mainEngine.doesNotExist == nil and v.nope == nil)

-- 6) describe for the menu
v = car()
local cfgFun = ed{{kind = "value", path = {"mainEngine", "maxRPM"}, value = 9000}, {kind = "column", path = {"mainEngine", "torque"}, column = 2, scale = 10}}
rep = fun.apply(v, cfgFun)
local list = fun.describe(v, cfgFun, rep)
local names = {}
for _, s in ipairs(list) do names[#names + 1] = s.name end
local joined = table.concat(names, ",")
check("sections listed, bookkeeping skipped", joined:find("mainEngine") and joined:find("beams") and not joined:find("information") and not joined:find("maxIDs"), joined)
check("engine first", list[1].group == "Engine & power", list[1].name)
local me = fun.describeSection(v, "mainEngine", cfgFun, rep)
local byId = {}
for _, f in ipairs(me.fields) do if f.id then byId[f.id] = f end end
local rpm = byId[fun.valueId({"mainEngine", "maxRPM"})]
check("edited value: current + stock", rpm and rpm.value == 9000 and rpm.stock == 6500 and rpm.edited, rpm and (rpm.value .. "/" .. rpm.stock))
local torque
for _, f in ipairs(me.fields) do if f.kind == "column" then torque = f end end
local tcol
for _, c in ipairs(torque.columns) do if c.name == "torque" then tcol = c end end
check("torque column: scale and stock peak", tcol and tcol.scale == 10 and tcol.stockMax == 300 and tcol.edited, tcol and (tcol.scale .. " " .. tcol.stockMax))
local cell = torque.rows[2].cells[2]
check("curve points listed with ids", cell and cell.value == 1500 and cell.id == fun.valueId({"mainEngine", "torque", 3, 2}), cell and tostring(cell.value))
local v2 = car()
fun.apply(v2, ed{{kind = "value", path = {"mainEngine", "torque", 4, 2}, value = 999}})
check("one curve point set", v2.mainEngine.torque[4][2] == 999 and v2.mainEngine.torque[3][2] == 150)
check("nested field flattened", byId[fun.valueId({"mainEngine", "particulates", "rate"})] ~= nil)
local beams = fun.describeSection(v, "beams", cfgFun, rep)
local fieldNames = {}
for _, f in ipairs(beams.fields) do fieldNames[#fieldNames + 1] = f.field end
local fj = table.concat(fieldNames, ",")
check("beam fields without references", fj:find("beamSpring") and not fj:find("id1"), fj)
check("infinite values sent as text", (function() for _, f in ipairs(beams.fields) do if f.field == "beamStrength" then return f.stockMax == "FLT_MAX" end end end)())
local nodes = fun.describeSection(v, "nodes", cfgFun, rep)
local nf = {}
for _, f in ipairs(nodes.fields) do nf[#nf + 1] = f.field end
check("nodes: weight listed, positions not", table.concat(nf, ","):find("nodeWeight") and not table.concat(nf, ","):find("posX"), table.concat(nf, ","))
local wheels = fun.describeSection(v, "pressureWheels", cfgFun, rep)
check("small row sections list each row by name", wheels.rows and #wheels.rows == 2 and wheels.rows[1].row == "FL", wheels.rows and tostring(#wheels.rows))

-- 7) search
local hits = fun.search(v, "brake", cfgFun, rep)
check("search finds brakeTorque", #hits >= 1 and hits[1].name == "pressureWheels", hits[1] and hits[1].name)
hits = fun.search(v, "torque", cfgFun, rep)
local foundCol = false
for _, h in ipairs(hits) do for _, f in ipairs(h.fields) do if f.kind == "column" then foundCol = true end end end
check("search finds the torque curve by column name", foundCol)

-- 8) normalizeEdits rebuilds ids and drops junk
local norm = fun.normalizeEdits({
  {kind = "value", path = {"mainEngine", "maxRPM"}, value = 1},
  {kind = "bogus"}, "text", {kind = "rows", section = "beams", field = "beamSpring", scale = 3},
})
local n = 0
for _ in pairs(norm) do n = n + 1 end
check("normalize keeps 2 edits", n == 2 and norm[fun.valueId({"mainEngine", "maxRPM"})] and norm[fun.rowsId("beams", "beamSpring")])


-- 9) quick edits (the simple Fun menu)
local function quickCar()
  return {
    options = {},
    powertrain = {[0] = {type = "combustionEngine", name = "mainEngine", inputName = "dummy", inputIndex = 0},
                  [1] = {type = "manualGearbox", name = "gearbox", inputName = "mainEngine", inputIndex = 1}},
    mainEngine = {
      torque = {{"rpm", "torque"}, {0, 0}, {3000, 300}, {6000, 250}},
      maxRPM = 6500, revLimiterRPM = 6500, maxTorqueRating = 400, thermalsEnabled = true,
      turbocharger = "turbocharger", nitrousOxideInjection = "n2o", breakTriggerBeam = "engine_mount",
      instantAfterFireCoef = 0.5, sustainedAfterFireCoef = 0.5,
    },
    turbocharger = {wastegateStart = 12, wastegateLimit = 13, damageThresholdTemperature = 650,
      pressurePSI = {{0, -3}, {100000, 10}, {200000, 18}}},
    n2o = {addedPower = 50},
    nodes = {[0] = {nodeWeight = 10}, [1] = {}},
    beams = {[0] = {beamSpring = 1000, beamDeform = 50000, beamStrength = 100000}, [1] = {beamSpring = 1000, beamStrength = math.huge}},
    pressureWheels = {[0] = {name = "FL", frictionCoef = 1.0, slidingFrictionCoef = 0.8, brakeTorque = 2000, nodeWeight = 2, hubNodeWeight = 1},
                      [1] = {name = "FR", frictionCoef = 1.0, slidingFrictionCoef = 0.8, brakeTorque = 2000, nodeWeight = 2, hubNodeWeight = 1}},
  }
end
local function q(name, extra) local e = {kind = "quick", name = name, engine = "mainEngine"} for k, x in pairs(extra or {}) do e[k] = x end return e end

local c = quickCar()
rep = fun.apply(c, ed{q("indestructibleEngine", {value = true}), q("noRevLimiter", {value = true})})
local me = c.mainEngine
check("indestructible: no torque damage", me.maxTorqueRating == -1)
check("indestructible: no heat or rev damage, thermals stay on", me.headGasketDamageThreshold >= 1e29 and me.maxOverRevDamage >= 1e29 and me.thermalsEnabled == true)
check("indestructible: crashes and water can't kill it", me.breakTriggerBeam == "" and next(me.waterDamage) == nil and me.hasOilStarvingDamage == false)
check("indestructible: turbo can't overheat", c.turbocharger.damageThresholdTemperature >= 1e5)
check("no rev limiter", me.hasRevLimiter == false)

c = quickCar()
rep = fun.apply(c, ed{q("maxRPM", {value = 12000}), q("curve", {rows = {{9000, 500}, {0, 0}, {3000, 1000}}})})
check("max rpm + limiter", c.mainEngine.maxRPM == 12000 and c.mainEngine.revLimiterRPM == 12000)
check("curve replaced, sorted, header kept, extended to max rpm", c.mainEngine.torque[1][2] == "torque" and #c.mainEngine.torque == 5 and c.mainEngine.torque[3][1] == 3000
  and c.mainEngine.torque[4][2] == 500 and c.mainEngine.torque[5][1] == 12100 and c.mainEngine.torque[5][2] == 500)
local stockCurve = rep.original[fun.quickId("curve", "mainEngine")]
check("stock curve remembered", stockCurve and #stockCurve == 3 and stockCurve[2][2] == 300)
check("stock max rpm remembered", rep.original[fun.quickId("maxRPM", "mainEngine")] == 6500)
c = quickCar()
rep = fun.apply(c, ed{q("curve", {rows = {{1000, 5}}})})
check("curve needs 2 points", rep.applied == 0 and c.mainEngine.torque[3][2] == 300)

c = quickCar()
rep = fun.apply(c, ed{q("boost", {psi = 30})})
local top = 0
for _, r in ipairs(c.turbocharger.pressurePSI) do if r[2] > top then top = r[2] end end
check("turbo boost 30 psi", c.turbocharger.wastegateStart == 30 and math.abs(c.turbocharger.wastegateLimit - 32.5) < 1e-9, tostring(c.turbocharger.wastegateLimit))
check("turbo can reach it", top >= 30, tostring(top))
check("negative pressure stays", c.turbocharger.pressurePSI[1][2] == -3)
check("stock boost remembered", rep.original[fun.quickId("boost", "mainEngine")] == 12)
c = quickCar()
c.turbocharger.wastegateStart = {[1] = 8, [2] = 10, [3] = 12}
fun.apply(c, ed{q("boost", {psi = 24})})
check("per-gear boost scaled", c.turbocharger.wastegateStart[1] == 16 and c.turbocharger.wastegateStart[3] == 24)
c = quickCar()
c.mainEngine.turbocharger = nil
c.mainEngine.supercharger = "sc"
c.sc = {pressurePSIPer1kRPM = 1, gearRatio = 2}
fun.apply(c, ed{q("boost", {psi = 26})})
check("supercharger boost scaled (13 psi stock -> 26)", math.abs(c.sc.pressurePSIPer1kRPM - 2) < 1e-9, tostring(c.sc.pressurePSIPer1kRPM))

c = quickCar()
fun.apply(c, ed{q("afterfire", {level = 8}), q("nitrous", {hp = 300})})
check("pops and bangs level 8", c.mainEngine.instantAfterFireCoef == 2 and c.mainEngine.sustainedAfterFireCoef == 2)
check("nitrous 300 hp", math.abs(c.n2o.addedPower * fun.HP_PER_KW - 300) < 1e-9)

c = quickCar()
fun.apply(c, ed{{kind = "quick", name = "weight", scale = 2}, {kind = "quick", name = "grip", scale = 1.5}, {kind = "quick", name = "brakes", scale = 3}})
check("weight x2 incl. default nodes and tires", c.nodes[0].nodeWeight == 20 and c.nodes[1].nodeWeight == 50 and c.pressureWheels[0].nodeWeight == 4 and c.pressureWheels[0].hubNodeWeight == 2)
check("grip x1.5", c.pressureWheels[1].frictionCoef == 1.5 and math.abs(c.pressureWheels[1].slidingFrictionCoef - 1.2) < 1e-9)
check("brakes x3", c.pressureWheels[0].brakeTorque == 6000)

c = quickCar()
fun.apply(c, ed{{kind = "quick", name = "unbreakable", value = true}})
check("unbreakable car", c.beams[0].beamDeform == math.huge and c.beams[0].beamStrength == math.huge and c.beams[1].beamDeform == math.huge)
c = quickCar()
fun.apply(c, ed{{kind = "quick", name = "fragile", value = true}})
check("paper car", math.abs(c.beams[0].beamDeform - 2000) < 1e-9 and math.abs(c.beams[0].beamStrength - 15000) < 1e-9 and math.abs(c.beams[1].beamDeform - 8800) < 1e-9 and c.beams[1].beamStrength == math.huge)

-- max rpm past the end of the torque curve: the curve is extended (the game's shift logic reads it up to max rpm)
c = quickCar()
rep = fun.apply(c, ed{q("maxRPM", {value = 12000})})
local tq = c.mainEngine.torque
check("curve extended to the new max rpm", tq[#tq][1] == 12100 and tq[#tq][2] == 250 and rep.extendedCurve and rep.extendedCurve.mainEngine == 12100,
  tostring(tq[#tq][1]) .. " " .. tostring(tq[#tq][2]))
c = quickCar()
fun.apply(c, ed{{kind = "value", path = {"mainEngine", "revLimiterRPM"}, value = 8000.5}})
tq = c.mainEngine.torque
check("fractional limiter rounded, curve extended", c.mainEngine.revLimiterRPM == 8001 and tq[#tq][1] == 8200, tostring(c.mainEngine.revLimiterRPM) .. " " .. tostring(tq[#tq][1]))
c = quickCar()
fun.apply(c, ed{q("maxRPM", {value = 5000})})
check("lower max rpm: curve left alone", #c.mainEngine.torque == 4)
c = quickCar()
c.mainEngine.revLimiterRPM = 9000 -- a broken stock engine is not touched without edits
fun.apply(c, {edits = {}})
check("no edits, no fix-ups", #c.mainEngine.torque == 4)

-- what the simple menu shows: stock values even after editing
c = quickCar()
local cf = ed{q("boost", {psi = 40}), q("maxRPM", {value = 9000}), {kind = "quick", name = "weight", scale = 2}}
rep = fun.apply(c, cf)
local info = fun.quickInfo(c, cf, rep)
local e1 = info.engines[1]
check("menu: one engine found from the powertrain", #info.engines == 1 and e1.name == "mainEngine")
check("menu: boost now 40, stock 12", e1.boost and e1.boost.kind == "turbo" and e1.boost.psi == 40 and e1.boost.stock == 12)
check("menu: max rpm now 9000, stock 6500", e1.maxRPM == 9000 and e1.stockMaxRPM == 6500)
check("menu: nitrous found", e1.nitrous and math.abs(e1.nitrous.hp - 50 * fun.HP_PER_KW) < 1e-9)
check("menu: weight and stock weight", info.car.mass == 2 * info.car.stockMass and info.car.wheels == 2, info.car.mass .. "/" .. info.car.stockMass)
check("menu: afterfire level 2 stock", e1.afterfire.level == 2 and e1.afterfire.stock == 2)

local nq = fun.normalizeEdits({q("curve", {rows = {{0, 0}, {"5000", "300"}, {"x", 1}}}), {kind = "quick", name = "selfDestruct"}})
local qc = nq[fun.quickId("curve", "mainEngine")]
local nn = 0
for _ in pairs(nq) do nn = nn + 1 end
check("normalize: quick curve kept with clean rows, unknown quick dropped", nn == 1 and qc and #qc.rows == 2 and qc.rows[2][1] == 5000)
print(fails == 0 and "ALL PASSED" or (fails .. " FAILED"))
