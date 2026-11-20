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

print(fails == 0 and "ALL PASSED" or (fails .. " FAILED"))
