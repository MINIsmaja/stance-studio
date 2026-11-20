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


-- photo mode: rim pieces with real part paths
local function photoVehicle()
  local veh, byName = makeVehicle()
  local base = "/car/susp_F/wheel_F/steel_15_F"
  local rbase = "/car/susp_R/wheel_R/steel_15_R"
  veh.flexbodies = {
    {mesh="rim_steel", partOrigin="steel_15_F", partPath=base, ["[group]:"]={"wheel_FR","wheelhub_FR"}},
    {mesh="rim_steel", partOrigin="steel_15_F", partPath=base, ["[group]:"]={"wheel_FL","wheelhub_FL"}},
    {mesh="hubcap_a", partOrigin="hubcap_a", partPath=base.."/hubcap_F/hubcap_a", ["[group]:"]={"wheel_FL"}},
    {mesh="tire_15", partOrigin="tire_a", partPath=base.."/tire_F_15/tire_a", ["[group]:"]={"tire_FL","wheel_FL"}},
    {mesh="tire_15", partOrigin="tire_a", partPath=base.."/tire_F_15/tire_a", ["[group]:"]={"tire_FR","wheel_FR"}},
    {mesh="brake_disc", partOrigin="brakes_F", partPath="/car/susp_F/brakes_F", ["[group]:"]={"wheelhub_FL"}},
    {mesh="rim_steel", partOrigin="steel_15_R", partPath=rbase, ["[group]:"]={"wheel_RL","wheelhub_RL"}},
    {mesh="rim_steel", partOrigin="steel_15_R", partPath=rbase, ["[group]:"]={"wheel_RR","wheelhub_RR"}},
    {mesh="body", partOrigin="body", partPath="/car", ["[group]:"]={"body"}},
  }
  veh.props = {{mesh="steering_wheel"}}
  return veh
end

local v = photoVehicle()
local r = stance.photoStrip(v, {part = "steel_15_F"})
local meshes = {}
for _, fb in ipairs(v.flexbodies) do meshes[#meshes + 1] = fb.mesh .. "@" .. table.concat(fb["[group]:"], ",") end
table.sort(meshes)
check("front: keeps FL rim + its hubcap only", #v.flexbodies == 2, table.concat(meshes, " "))
check("front: kept rim is the FL one", meshes[2] == "rim_steel@wheel_FL,wheelhub_FL" and meshes[1] == "hubcap_a@wheel_FL", table.concat(meshes, " "))
check("front: aims at FL", r.wheel == "FL", tostring(r.wheel))
check("props removed", #v.props == 0)

v = photoVehicle()
r = stance.photoStrip(v, {part = "steel_15_R"})
check("rear part: keeps RL rim only", #v.flexbodies == 1 and v.flexbodies[1]["[group]:"][1] == "wheel_RL")
check("rear part: aims at RL", r.wheel == "RL", tostring(r.wheel))

-- meshes not bound to wheel groups: keep every piece of the part
v = photoVehicle()
for _, fb in ipairs(v.flexbodies) do if fb.partOrigin == "steel_15_F" then fb["[group]:"] = {"some_other_group"} end end
r = stance.photoStrip(v, {part = "steel_15_F"})
check("unbound: keeps both rims of the part + hubcap", #v.flexbodies == 3, tostring(#v.flexbodies))

-- tire mesh inside the wheel part itself is dropped
v = photoVehicle()
table.insert(v.flexbodies, {mesh="tire_builtin", partOrigin="steel_15_F", partPath="/car/susp_F/wheel_F/steel_15_F", ["[group]:"]={"wheel_FL"}})
stance.photoStrip(v, {part = "steel_15_F"})
local hasTire = false
for _, fb in ipairs(v.flexbodies) do if fb.mesh:find("tire") then hasTire = true end end
check("tire mesh in the wheel part dropped", not hasTire)

check("missing part handled", stance.photoStrip(photoVehicle(), {}).error == "no part")
print(fails == 0 and "ALL PASSED" or (fails.." FAILED"))
