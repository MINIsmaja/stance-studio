local G, MOD = os.getenv("G"), os.getenv("MOD")
package.path = G.."/lua/common/?.lua;"..G.."/lua/?.lua;"..MOD.."/lua/?.lua;"..package.path
require("mathlib"); table.clear = require("table.clear")
local stance = require("ge/extensions/stanceStudio/stance")
local fails = 0
local function check(name, cond, extra) if not cond then fails = fails + 1 end print((cond and "PASS " or "FAIL ")..name..(extra and ("  "..extra) or "")) end

local function makeVehicle()
  local nodes, beams, cid = {}, {}, 0
  local byName = {}
  local function N(name, x, y, z, group, part)
    nodes[cid] = {name=name, cid=cid, pos=vec3(x,y,z), group=group, partOrigin=part}; byName[name]=cid; cid = cid + 1
  end
  -- right front corner (x<0), left front (x>0), rears at y=+1.4
  for _, c in ipairs({{"r",-1,"F",-1.4},{"l",1,"F",-1.4},{"r",-1,"R",1.4},{"l",1,"R",1.4}}) do
    local s, sx, ax, y = c[1], c[2], c[3], c[4]
    local p = ax:lower()
    N(p.."w1"..s,      sx*0.70, y, 0.33, "wheelhub_"..ax..s:upper(), "wheelpart_"..ax)
    N(p.."w1"..s..s,   sx*0.95, y, 0.33, "wheelhub_"..ax..s:upper(), "wheelpart_"..ax)
    N(p.."h4"..s,      sx*0.62, y, 0.45, "hub", "susp_"..ax)   -- knuckle upper
    N(p.."h1"..s,      sx*0.62, y, 0.20, "hub", "susp_"..ax)   -- knuckle lower
    N(p.."s1"..s,      sx*0.50, y, 0.85, "body", "body")       -- shock tower
    N(p.."x1"..s,      sx*0.25, y, 0.25, "body", "body")       -- arm pivot on body
  end
  local function B(a, b, opt) local t = opt or {}; t.id1, t.id2 = byName[a], byName[b]; t.cid = #beams + 1; beams[#beams + 1] = t; return t end
  local springs = {}
  for _, c in ipairs({{"r","F"},{"l","F"},{"r","R"},{"l","R"}}) do
    local s, ax = c[1], c[2]; local p = ax:lower()
    B(p.."w1"..s, p.."w1"..s..s, {beamSpring=1501000})
    B(p.."h4"..s, p.."w1"..s..s, {beamSpring=1501000, beamPrecompression=1.002})
    B(p.."h1"..s, p.."w1"..s, {beamSpring=1501000})
    B(p.."h4"..s, p.."h1"..s, {beamSpring=2000000})
    B(p.."h1"..s, p.."x1"..s, {beamSpring=3000000})       -- lower arm
    springs[ax..s] = B(p.."h4"..s, p.."s1"..s, {beamSpring=60000, beamDamp=100, precompressionRange=0.13, name="spring_"..ax..s})
    B(p.."h4"..s, p.."s1"..s, {beamType=2, beamSpring=0, beamDamp=3000, beamDampRebound=2500, name="shock"})
  end
  local wheelRows = {}
  local i = 0
  for _, c in ipairs({{"FR","r","f"},{"FL","l","f"},{"RR","r","r"},{"RL","l","r"}}) do
    wheelRows[i] = {name=c[1], hubGroup="wheel_"..c[1], group="tire_"..c[1], node1=byName[c[3].."w1"..c[2]..c[2]], node2=byName[c[3].."w1"..c[2]]}
    i = i + 1
  end
  local flex = {
    {mesh="rim_FR",  ["[group]:"]={"wheel_FR","wheelhub_FR"}, pos={x=-0.51,y=0,z=0}, rot={x=0,y=0,z=180}, nodeOffset={x=0.31,y=-1.4,z=0.33}},
    {mesh="tire_FR", ["[group]:"]={"wheel_FR","tire_FR"},     pos={x=-0.50,y=0,z=0}, rot={x=0,y=0,z=180}, nodeOffset={x=0.31,y=-1.4,z=0.33}},
    {mesh="rim_FL",  ["[group]:"]={"wheel_FL","wheelhub_FL"}, pos={x=0.51,y=0,z=0},  rot={x=0,y=0,z=0},   nodeOffset={x=0.31,y=-1.4,z=0.33}},
    {mesh="brake_disc_FR", partOrigin="brakes_F", ["[group]:"]={"wheelhub_FR"}, pos={x=-0.6,y=-1.4,z=0.33}, rot={x=0,y=0,z=0}},
    {mesh="body", ["[group]:"]={"body"}, pos={x=0,y=0,z=0}, rot={x=0,y=0,z=0}},
  }
  return {nodes=nodes, beams=beams, pressureWheels=wheelRows, flexbodies=flex}, byName, springs
end

-- 1) neutral config does nothing
local cfg0 = stance.normalize({})
check("neutral is neutral", stance.isNeutral(cfg0))

-- 2) camber / toe / offset on front, lowering on rear
local veh, byName, springs = makeVehicle()
local before = {}
for k, n in pairs(veh.nodes) do before[k] = vec3(n.pos) end
local fbBefore = {}
for i, fb in ipairs(veh.flexbodies) do
  local U = require("jbeam/utils")
  local x,y,z = U.getFlexbodyPosRotAfterNodeRotateOffsetMove(fb, fb.pos.x, fb.pos.y, fb.pos.z, fb.rot.x, fb.rot.y, fb.rot.z)
  fbBefore[i] = x and vec3(x,y,z) or vec3(fb.pos.x, fb.pos.y, fb.pos.z)
end
local cfg = stance.normalize({F={camber=-5, offset=0.03}, R={rideHeight=-0.05, spring=1.5, damp=0.8}})
local report = stance.apply(veh, cfg)
local function P(name) return veh.nodes[byName[name]].pos end
local function B0(name) return before[byName[name]] end

-- right front: outer axle node goes up, inner goes down (top leans in), and both move out by 3 cm
local outerR, innerR = P("fw1rr"), P("fw1r")
check("FR outer node rises (negative camber)", outerR.z > B0("fw1rr").z + 0.005, string.format("dz=%.4f", outerR.z - B0("fw1rr").z))
check("FR inner node drops", innerR.z < B0("fw1r").z - 0.005)
local midBefore = (B0("fw1rr") + B0("fw1r")) * 0.5
local midAfter = (outerR + innerR) * 0.5
check("FR center moved out by 3 cm", math.abs((midBefore.x - midAfter.x) - 0.03) < 1e-6, string.format("dx=%.4f", midBefore.x - midAfter.x))
local outerL = P("fw1ll")
check("FL mirrored: outer node rises too", outerL.z > B0("fw1ll").z + 0.005)
check("FL center moved out (+x)", ((P("fw1ll") + P("fw1l")) * 0.5).x - ((B0("fw1ll") + B0("fw1l")) * 0.5).x > 0.029)
check("knuckle node untouched", P("fh4r"):distance(B0("fh4r")) < 1e-9)
check("body node untouched", P("fs1r"):distance(B0("fs1r")) < 1e-9)
-- camber angle of the axle (FR): angle between axle and horizontal should be 5 deg
local ax = (outerR - innerR):normalized()
check("FR camber is 5 deg", math.abs(math.deg(math.asin(ax.z)) - 5) < 0.01, string.format("%.3f deg", math.deg(math.asin(ax.z))))

-- meshes: rim and tire followed (same center shift), brake disc kept its lateral place, body untouched
local U = require("jbeam/utils")
local function fbPos(fb) local x,y,z = U.getFlexbodyPosRotAfterNodeRotateOffsetMove(fb, fb.pos.x, fb.pos.y, fb.pos.z, fb.rot.x, fb.rot.y, fb.rot.z); return x and vec3(x,y,z) or vec3(fb.pos.x, fb.pos.y, fb.pos.z) end
local rim = veh.flexbodies[1]
check("rim flattened (no nodeOffset left)", rim.nodeOffset == nil and rim.__stanceStudioFlat)
local rimShift = fbPos(rim) - fbBefore[1]
check("rim moved outward ~3 cm", rimShift.x < -0.025, string.format("dx=%.4f", rimShift.x))
check("rim rotation changed (camber applied)", math.abs(rim.rot.y) > 0.1 or math.abs(rim.rot.x) > 0.1, string.format("rot=%.2f %.2f %.2f", rim.rot.x, rim.rot.y, rim.rot.z))
local disc = veh.flexbodies[4]
check("brake disc not pushed out by spacer", math.abs(fbPos(disc).x - fbBefore[4].x) < 0.01, string.format("dx=%.4f", fbPos(disc).x - fbBefore[4].x))
check("body mesh untouched", (fbPos(veh.flexbodies[5]) - fbBefore[5]):length() < 1e-9)

-- rear: springs shortened, stiffer, softer shocks; geometry untouched
local sRR = springs.Rr
check("RR spring precompressionRange lowered", sRR.precompressionRange < 0.13 - 0.03, string.format("%.4f", sRR.precompressionRange))
check("RR spring stiffer x1.5", math.abs(sRR.beamSpring - 90000) < 1e-6)
check("FR spring untouched", springs.Fr.precompressionRange == 0.13 and springs.Fr.beamSpring == 60000)
local shockRR
for _, b in ipairs(veh.beams) do if b.name == "shock" and b.id1 == byName["rh4r"] then shockRR = b end end
check("RR shock damping x0.8", shockRR and math.abs(shockRR.beamDamp - 2400) < 1e-6 and math.abs(shockRR.beamDampRebound - 2000) < 1e-6)
check("RR axle nodes not moved (springs method)", P("rw1r"):distance(B0("rw1r")) < 1e-9)
local methods = {}
for _, c in ipairs(report.corners) do methods[c.name] = c.method end
check("report methods", methods.FR == "geometry" and methods.RR == "springs", string.format("FR=%s RR=%s", tostring(methods.FR), tostring(methods.RR)))

-- 3) hub method moves the wheel up instead
local veh2, byName2 = makeVehicle()
local r0 = vec3(veh2.nodes[byName2["rw1r"]].pos)
stance.apply(veh2, stance.normalize({method="hub", R={rideHeight=-0.04}}))
check("hub method: rear wheel nodes up 4 cm", math.abs(veh2.nodes[byName2["rw1r"]].pos.z - r0.z - 0.04) < 1e-9)

-- 4) toe-in: front of the right wheel points inward (+x)
local veh3, byName3 = makeVehicle()
stance.apply(veh3, stance.normalize({F={toe=2}}))
local a3 = (veh3.nodes[byName3["fw1rr"]].pos - veh3.nodes[byName3["fw1r"]].pos):normalized() -- outward axle of the right wheel (-x)
-- wheel heading = up x axle for right wheel... check: axle's y component; toe-in on the right wheel turns the outer end toward the rear (+y)
check("FR toe-in turns outer axle end forward (-y)", a3.y < -0.03, string.format("axle y=%.4f", a3.y))
local a3l = (veh3.nodes[byName3["fw1ll"]].pos - veh3.nodes[byName3["fw1l"]].pos):normalized()
check("FL toe mirrored (outer end forward too)", a3l.y < -0.03, string.format("axle y=%.4f", a3l.y))

-- 5) clamping
local cl = stance.normalize({F={camber=-99, offset=9}, R={spring=0}})
check("clamping", cl.F.camber == -30 and cl.F.offset == 0.35 and cl.R.spring == 0.2)
-- 6) auto method: deep lowering = 5 cm on springs + the rest by moving the wheel up
local veh6, byName6, springs6 = makeVehicle()
local w0 = vec3(veh6.nodes[byName6["rw1r"]].pos)
local rep6 = stance.apply(veh6, stance.normalize({R={rideHeight=-0.15}}))
local rr6 = springs6.Rr
check("auto: springs take 5 cm", math.abs(rr6.precompressionRange - (0.13 - 0.05 * 1.0)) < 0.02, string.format("%.4f", rr6.precompressionRange))
check("auto: wheel moves up the other 10 cm", math.abs(veh6.nodes[byName6["rw1r"]].pos.z - w0.z - 0.10) < 1e-9, string.format("dz=%.4f", veh6.nodes[byName6["rw1r"]].pos.z - w0.z))
local m6 = {}
for _, c in ipairs(rep6.corners) do m6[c.name] = c.method end
check("auto: method springs+hub", m6.RR == "springs+hub", tostring(m6.RR))

-- 7) hubExtra from the measurement adds on top
local veh7, byName7 = makeVehicle()
local w7 = vec3(veh7.nodes[byName7["fw1r"]].pos)
stance.apply(veh7, stance.normalize({F={rideHeight=-0.04}, hubExtra={F=0.02}}))
check("hubExtra lifts the wheel 2 cm more", math.abs(veh7.nodes[byName7["fw1r"]].pos.z - w7.z - 0.02) < 1e-9)
check("hubExtra alone is not neutral", not stance.isNeutral(stance.normalize({hubExtra={R=0.01}})))

-- 8) steering lock doubles the rack travel on the front only
local veh8, byName8 = makeVehicle()
veh8.hydros = {
  [0] = {id1=byName8["fh4r"], id2=byName8["fh4l"], inputSource="steering", inLimit=0.9, outLimit=1.1},
  [1] = {id1=byName8["rh4r"], id2=byName8["rh4l"], inputSource="steering", inLimit=0.95, outLimit=1.05},
  [2] = {id1=byName8["fs1r"], id2=byName8["fs1l"], inputSource="throttle", inLimit=0.5, outLimit=1.5},
}
stance.apply(veh8, stance.normalize({F={steer=2}}))
check("front steering doubled", math.abs(veh8.hydros[0].inLimit - 0.8) < 1e-9 and math.abs(veh8.hydros[0].outLimit - 1.2) < 1e-9)
check("rear steering untouched", veh8.hydros[1].inLimit == 0.95 and veh8.hydros[1].outLimit == 1.05)
check("non-steering hydro untouched", veh8.hydros[2].inLimit == 0.5)
check("deep limits accepted", stance.normalize({F={rideHeight=-0.45, offset=0.3, steer=3.5}}).F.rideHeight == -0.45)
check("v1 springs becomes auto", stance.normalize({v=1, method="springs"}).method == "auto" and stance.normalize({v=2, method="springs"}).method == "springs")

-- 9) big lift: springs take the first 10 cm, the wheel drops on the hub for the rest
local veh9, byName9, springs9 = makeVehicle()
local w9 = vec3(veh9.nodes[byName9["rw1r"]].pos)
local w9l = vec3(veh9.nodes[byName9["rw1l"]].pos)
local rep9 = stance.apply(veh9, stance.normalize({R={rideHeight=0.40}}))
check("lift: springs take 10 cm", math.abs(springs9.Rr.precompressionRange - (0.13 + 0.10)) < 0.02, string.format("%.4f", springs9.Rr.precompressionRange))
check("lift: right wheel drops the other 30 cm", math.abs(veh9.nodes[byName9["rw1r"]].pos.z - w9.z + 0.30) < 1e-9, string.format("dz=%.4f", veh9.nodes[byName9["rw1r"]].pos.z - w9.z))
check("lift: left wheel drops the same", math.abs(veh9.nodes[byName9["rw1l"]].pos.z - w9l.z + 0.30) < 1e-9, string.format("dz=%.4f", veh9.nodes[byName9["rw1l"]].pos.z - w9l.z))
local m9 = {}
for _, c in ipairs(rep9.corners) do m9[c.name] = c.method end
check("lift: method springs+hub", m9.RR == "springs+hub" and m9.RL == "springs+hub", tostring(m9.RR) .. "/" .. tostring(m9.RL))
-- small lift stays on the springs
local veh9b, byName9b = makeVehicle()
local w9b = vec3(veh9b.nodes[byName9b["rw1r"]].pos)
stance.apply(veh9b, stance.normalize({R={rideHeight=0.08}}))
check("small lift: wheel not moved", math.abs(veh9b.nodes[byName9b["rw1r"]].pos.z - w9b.z) < 1e-9)
-- limits and the signed hub top-up
check("+40 cm accepted", stance.normalize({F={rideHeight=0.40}}).F.rideHeight == 0.40)
check("-40 cm accepted", stance.normalize({F={rideHeight=-0.40}}).F.rideHeight == -0.40)
local cl9 = stance.normalize({F={rideHeight=0.9}, R={rideHeight=-0.9}})
check("ride height clamped to +-50 cm", cl9.F.rideHeight == 0.50 and cl9.R.rideHeight == -0.50)
check("negative hubExtra kept", stance.normalize({hubExtra={F=-0.03}}).hubExtra.F == -0.03)
check("negative hubExtra not neutral", not stance.isNeutral(stance.normalize({hubExtra={F=-0.03}})))
local veh9c, byName9c = makeVehicle()
local w9c = vec3(veh9c.nodes[byName9c["fw1r"]].pos)
stance.apply(veh9c, stance.normalize({F={rideHeight=0.20}, hubExtra={F=-0.02}}))
check("lift top-up drops the wheel 2 cm more", math.abs(veh9c.nodes[byName9c["fw1r"]].pos.z - w9c.z + 0.12) < 1e-9, string.format("dz=%.4f", veh9c.nodes[byName9c["fw1r"]].pos.z - w9c.z))
local sp, hub = stance.splitRideHeight(stance.normalize({F={rideHeight=0.40}}), "F", true)
check("split +40: 10 springs / 30 down", math.abs(sp - 0.10) < 1e-9 and math.abs(hub + 0.30) < 1e-9)
local sp2, hub2 = stance.splitRideHeight(stance.normalize({v=2, method="springs", F={rideHeight=0.40}}), "F", true)
check("springs only keeps all of it on the springs", math.abs(sp2 - 0.40) < 1e-9 and math.abs(hub2) < 1e-9)
local sp3, hub3 = stance.splitRideHeight(stance.normalize({method="hub", F={rideHeight=0.40}}), "F", true)
check("hub only drops the wheel 40 cm", sp3 == 0 and math.abs(hub3 + 0.40) < 1e-9)

-- 10) stock size: highest node down to the bottom of the lowest tire
local veh10 = makeVehicle()
local s10 = stance.measureSize(veh10)
check("size without tire radius uses 0.3 m", s10 and math.abs(s10.height - (0.85 - (0.33 - 0.3))) < 1e-9, s10 and string.format("%.3f", s10.height))
for _, row in pairs(veh10.pressureWheels) do row.radius = 0.33 end
local s10b = stance.measureSize(veh10)
check("size uses the tire radius", math.abs(s10b.height - 0.85) < 1e-9 and math.abs(s10b.tireRadius - 0.33) < 1e-9, string.format("%.3f", s10b.height))
check("no wheels, no size", stance.measureSize({nodes = {}}) == nil)

-- 11) wheels must not fall off: stretched hub beams get reinforced, others keep stock limits
local function hubBeams(veh, byName, p, s)
  local res = {}
  for _, b in pairs(veh.beams) do
    local a, c = b.id1, b.id2
    local isW = function(id) return id == byName[p.."w1"..s] or id == byName[p.."w1"..s..s] end
    if isW(a) ~= isW(c) then res[#res + 1] = b end
  end
  return res
end
local function stockLimits(veh)
  for _, b in pairs(veh.beams) do b.beamStrength, b.beamDeform, b.breakGroup = 276500, 85000, "grp" end
end
local veh11, byName11 = makeVehicle(); stockLimits(veh11)
for _, row in pairs(veh11.pressureWheels) do row.nodeS = byName11["fh4r"] end
local rep11 = stance.apply(veh11, stance.normalize({F={rideHeight=0.40}}))
local hb = hubBeams(veh11, byName11, "f", "r")
local allStrong = #hb > 0
for _, b in ipairs(hb) do allStrong = allStrong and b.beamStrength == math.huge and b.beamDeform == math.huge and b.breakGroup == nil end
check("lift 40 cm: FR hub beams unbreakable", allStrong, #hb .. " beams")
local innerOk, otherOk = true, true
for _, b in pairs(veh11.beams) do
  if b.id1 == byName11["fw1r"] and b.id2 == byName11["fw1rr"] then innerOk = b.beamStrength == 276500 end
  if b.id1 == byName11["fh1r"] and b.id2 == byName11["fx1r"] then otherOk = b.beamStrength == 276500 and b.breakGroup == "grp" end
end
check("beam inside the wheel untouched", innerOk)
check("control arm keeps stock limits", otherOk)
local rearOk = true
for _, b in ipairs(hubBeams(veh11, byName11, "r", "r")) do rearOk = rearOk and b.beamStrength == 276500 end
check("rear (not moved) keeps stock limits", rearOk)
local r11 = {}
for _, c in ipairs(rep11.corners) do r11[c.name] = c end
check("report counts reinforced beams", (r11.FR.reinforced or 0) >= 2 and (r11.RR.reinforced or 0) == 0, tostring(r11.FR.reinforced))
local rowFR
for _, row in pairs(veh11.pressureWheels) do if row.name == "FR" then rowFR = row end end
check("stabilizer beams reinforced too", rowFR.hubStabilizerBeamStrength == math.huge)

local veh12, byName12 = makeVehicle(); stockLimits(veh12)
stance.apply(veh12, stance.normalize({F={camber=-2, offset=0.01, rideHeight=-0.04}}))
local smallOk = true
for _, b in ipairs(hubBeams(veh12, byName12, "f", "r")) do smallOk = smallOk and b.beamStrength == 276500 and b.breakGroup == "grp" end
check("small stance keeps stock limits", smallOk)

local veh13, byName13 = makeVehicle(); stockLimits(veh13)
stance.apply(veh13, stance.normalize({R={offset=0.30}}))
local offOk = true
for _, b in ipairs(hubBeams(veh13, byName13, "r", "l")) do offOk = offOk and b.beamStrength == math.huge end
check("30 cm offset: rear hub beams unbreakable", offOk)

local veh14, byName14 = makeVehicle(); stockLimits(veh14)
stance.apply(veh14, stance.normalize({F={rideHeight=-0.30}}))
local slamOk = true
for _, b in ipairs(hubBeams(veh14, byName14, "f", "l")) do slamOk = slamOk and b.beamStrength == math.huge end
check("slam -30 cm: hub beams unbreakable", slamOk)

-- 12) mass: node weights, 25 kg for nodes without one
local veh15 = makeVehicle()
local count = 0
for _ in pairs(veh15.nodes) do count = count + 1 end
check("mass defaults to 25 kg per node", math.abs(stance.measureSize(veh15).mass - 25 * count) < 1e-9, tostring(stance.measureSize(veh15).mass))
for _, n in pairs(veh15.nodes) do n.nodeWeight = 10 end
veh15.nodes[next(veh15.nodes)].nodeWeight = "$=bad"
check("mass uses nodeWeight", math.abs(stance.measureSize(veh15).mass - (10 * (count - 1) + 25)) < 1e-9)

-- 13) dual rear wheels like the Gavril MD: two wheel rows on the same axle nodes. The inner rim is
-- bound to a group no node has ("wheelhub_RR2"), the split rim barrel spans both wheels, and a
-- caliper hangs on the knuckle too (it must stay and stretch).
local veh16, byName16 = makeVehicle()
local n = 0
for _ in pairs(veh16.pressureWheels) do n = n + 1 end
local rr
for _, row in pairs(veh16.pressureWheels) do if row.name == "RR" then rr = row end end
rr.hubGroup, rr.group = "wheel_RR", "tire_RR"
veh16.pressureWheels[n] = {name="RR2", hubGroup="wheel_RR2", group="tire_RR2", node1=rr.node1, node2=rr.node2}
local function fbAt(mesh, groups) return {mesh=mesh, ["[group]:"]=groups, pos={x=-0.8, y=1.4, z=0.33}, rot={x=0, y=0, z=180}} end
local dual = {
  outerRim = fbAt("outer_rim", {"wheel_RR", "wheelhub_RR"}),
  innerRim = fbAt("inner_rim_bare", {"wheel_RR2", "wheelhub_RR2"}),
  barrel   = fbAt("split_barrel", {"wheel_RR2", "wheelhub_RR2", "wheel_RR", "wheelhub_RR"}),
  outerTire= fbAt("outer_tire", {"wheel_RR", "tire_RR"}),
  innerTire= fbAt("inner_tire", {"wheel_RR2", "tire_RR2"}),
  caliper  = fbAt("caliper", {"hub", "wheelhub_RR"}),
}
veh16.flexbodies = {}
for _, fb in pairs(dual) do veh16.flexbodies[#veh16.flexbodies + 1] = fb end
stance.apply(veh16, stance.normalize({R={rideHeight=0.40}}))
local wheelNode = veh16.nodes[byName16["rw1r"]].pos.z
for _, k in ipairs({"outerRim", "innerRim", "barrel", "outerTire", "innerTire"}) do
  local dz = dual[k].pos.z - 0.33
  check("dual: " .. k .. " drops 30 cm with the wheel", math.abs(dz + 0.30) < 1e-9, string.format("dz=%.3f", dz))
end
check("dual: wheel node dropped once", math.abs(wheelNode - (0.33 - 0.30)) < 1e-9, string.format("z=%.3f", wheelNode))
check("dual: caliper on the knuckle stays", math.abs(dual.caliper.pos.z - 0.33) < 1e-9)
local veh17, byName17 = makeVehicle()
for _, row in pairs(veh17.pressureWheels) do if row.name == "RR" then rr = row end end
local m17 = 0
for _ in pairs(veh17.pressureWheels) do m17 = m17 + 1 end
veh17.pressureWheels[m17] = {name="RR2", hubGroup="wheel_RR2", group="tire_RR2", node1=rr.node1, node2=rr.node2}
local rep17 = stance.apply(veh17, stance.normalize({R={rideHeight=0.40}}))
local c17 = {}
for _, c in ipairs(rep17.corners) do c17[c.name] = c end
check("dual: second wheel uses the first one's split", c17.RR2.hubPart == c17.RR.hubPart and c17.RR2.method == "springs+hub",
  string.format("%s %s / %s %s", tostring(c17.RR.hubPart), c17.RR.method, tostring(c17.RR2.hubPart), c17.RR2.method))
print(fails == 0 and "ALL PASSED" or (fails.." FAILED"))
