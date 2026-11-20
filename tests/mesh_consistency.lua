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


local rad, sin, cos = math.rad, math.sin, math.cos
local function qe(x, y, z)
  local q = quat()
  x, y, z = rad(-x) * 0.5, rad(-y) * 0.5, rad(-z) * 0.5
  local sx, cx, sy, cy, sz, cz = sin(x), cos(x), sin(y), cos(y), sin(z), cos(z)
  q:set(cz*sx*cy - sz*cx*sy, cz*cx*sy + sz*sx*cy, sz*cx*cy + cz*sx*sy, cz*cx*cy - sz*sx*sy)
  return q
end
local function rot(v, q) local r = vec3(v); r:setRotate(q); return r end
-- engine mesh rotation for euler (deg), two candidate axis orders
local function RA(v, r) return rot(v, qe(r.x, r.y, r.z)) end                                     -- helper's own order
local function RB(v, r) return rot(rot(rot(v, qe(0, r.y, 0)), qe(r.x, 0, 0)), qe(0, 0, r.z)) end  -- "+Z +X +Y intrinsic"
local jbeamUtils = require("jbeam/utils")

local samples = {vec3(0.05, 0.20, 0.0), vec3(0.05, -0.2, 0.05), vec3(-0.08, 0, 0.2), vec3(0.0, 0.1, -0.2)}
local function run(R, label, cfg)
  local veh, byName = makeVehicle()
  local flex = {
    {mesh="rim_FR", ["[group]:"]={"wheel_FR","wheelhub_FR"}, pos={x=-0.48,y=0,z=0}, rot={x=0,y=0,z=180}, nodeOffset={x=0.26,y=-1.4,z=0.33}},
    {mesh="rim_FL", ["[group]:"]={"wheel_FL","wheelhub_FL"}, pos={x=0.48,y=0,z=0},  rot={x=0,y=0,z=0},   nodeOffset={x=0.26,y=-1.4,z=0.33}},
  }
  veh.flexbodies = flex
  -- where the untouched game puts each mesh, and probe nodes riding on the wheel at sample points
  local probes = {}
  for i, fb in ipairs(flex) do
    local x, y, z, ex, ey, ez = jbeamUtils.getFlexbodyPosRotAfterNodeRotateOffsetMove(fb, fb.pos.x, fb.pos.y, fb.pos.z, fb.rot.x, fb.rot.y, fb.rot.z)
    local pos0, rot0 = vec3(x, y, z), {x = ex or fb.rot.x, y = ey or fb.rot.y, z = ez or fb.rot.z}
    probes[i] = {}
    local grp = (i == 1) and "wheelhub_FR" or "wheelhub_FL"
    for j, v in ipairs(samples) do
      local w = R(v, rot0) + pos0
      local cid = 1000 + i * 10 + j
      veh.nodes[cid] = {name = "probe"..cid, cid = cid, pos = w, group = grp, partOrigin = "wheelpart_F"}
      probes[i][j] = cid
    end
  end
  stance.apply(veh, stance.normalize(cfg))
  local worst = {}
  for i, fb in ipairs(veh.flexbodies) do
    local pos1 = vec3(fb.pos.x, fb.pos.y, fb.pos.z)
    local err = 0
    for j, v in ipairs(samples) do
      local meshPt = R(v, fb.rot) + pos1
      err = math.max(err, (meshPt - veh.nodes[probes[i][j]].pos):length())
    end
    worst[i] = err
  end
  print(string.format("%-34s FR rim off by %6.1f mm   FL rim off by %6.1f mm", label, worst[1] * 1000, worst[2] * 1000))
end
local cfg = {F = {camber = -6, offset = 0.04, toe = 0.3, rideHeight = -0.08}, R = {}}
run(RA, "engine = helper order (A):", cfg)
run(RB, "engine = +Z +X +Y intrinsic (B):", cfg)
run(RA, "A, camber only:", {F = {camber = -6}, R = {}})
run(RA, "A, big stance:", {F = {camber = -15, toe = 2, offset = 0.12, rideHeight = -0.2}, R = {}})
run(RA, "A, offset only:", {F = {offset = 0.04}, R = {}})
run(RA, "A, lift +40 cm:", {F = {rideHeight = 0.40}, R = {}})
run(RA, "A, lift +40 cm + camber:", {F = {rideHeight = 0.40, camber = -8, offset = 0.06}, R = {}})
run(RA, "A, slam -40 cm + camber:", {F = {rideHeight = -0.40, camber = -10, offset = 0.08}, R = {}})
