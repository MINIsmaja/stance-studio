-- Stance Studio: universal stance geometry, applied while the jbeam is loading.
--
-- Runs from onJbeamLoadingPhase1: nodes already have their final positions, wheels and
-- flexbodies are not built yet. Moving a wheel's axle nodes here means every beam takes its rest
-- length from the new geometry, so the car spawns already stanced. Meshes get the very same
-- transform through the game's own nodeRotate / nodeMove helpers, so rims and tires stay glued
-- to their physics nodes.
--
-- Pure module (no engine calls), so it can be tested outside the game.

local M = {}

local jbeamUtils = require("jbeam/utils")

local abs, min, max, sqrt = math.abs, math.min, math.max, math.sqrt

local WHEEL_SECTIONS = {"wheels", "monoHubWheels", "hubWheelsTSV", "hubWheelsTSI", "hubWheels", "pressureWheels"}
local NORMALTYPE, BEAM_BOUNDED = 0, 2

M.version = 2
M.axleKeys = {"rideHeight", "camber", "toe", "offset", "spring", "damp", "steer"}
M.defaultAxle = {rideHeight = 0, camber = 0, toe = 0, offset = 0, spring = 1, damp = 1, steer = 1}
-- hard limits, the UI ranges sit inside these
M.limits = {
  rideHeight = {-0.50, 0.25}, -- m, negative = lower
  camber     = {-30, 15},     -- deg, negative = top of the wheel leans in
  toe        = {-5, 5},       -- deg, positive = toe-in
  offset     = {-0.10, 0.35}, -- m per side, positive = wheel moves out
  spring     = {0.2, 5},      -- stiffness multiplier
  damp       = {0.2, 5},      -- damping multiplier
  steer      = {0.5, 4},      -- steering lock multiplier (drift-kit style)
}
-- "auto" ride height: the springs do the first part (like coilovers), anything lower moves the
-- wheel up on the hub, so the car can sit as low as you like and still has its suspension travel
M.SPRING_RANGE = 0.05
M.HUB_EXTRA_MAX = 0.45

local function clampNum(v, lim, default)
  v = tonumber(v)
  if not v or v ~= v then return default end
  return min(max(v, lim[1]), lim[2])
end

local METHODS = {auto = true, springs = true, hub = true}

-- returns a clean copy of a stance config (missing values become neutral)
function M.normalize(cfg)
  cfg = type(cfg) == "table" and cfg or {}
  local method = METHODS[cfg.method] and cfg.method or "auto"
  if (tonumber(cfg.v) or 1) < 2 and method == "springs" then method = "auto" end -- v1 default
  local out = {v = M.version, method = method, gain = {}, base = {}, hubExtra = {}}
  for _, axle in ipairs({"F", "R"}) do
    local src = type(cfg[axle]) == "table" and cfg[axle] or {}
    local dst = {}
    for _, k in ipairs(M.axleKeys) do
      dst[k] = clampNum(src[k], M.limits[k], M.defaultAxle[k])
    end
    out[axle] = dst
    local g = type(cfg.gain) == "table" and tonumber(cfg.gain[axle]) or nil
    out.gain[axle] = g and min(max(g, 0.25), 4) or 1
    local b = type(cfg.base) == "table" and tonumber(cfg.base[axle]) or nil
    out.base[axle] = b
    local h = type(cfg.hubExtra) == "table" and tonumber(cfg.hubExtra[axle]) or 0
    out.hubExtra[axle] = min(max(h, 0), M.HUB_EXTRA_MAX)
  end
  return out
end

-- how a ride height is split between springs and the hub for one axle
function M.splitRideHeight(cfg, axleKey, hasSprings)
  local h = cfg[axleKey].rideHeight
  local extra = cfg.hubExtra and cfg.hubExtra[axleKey] or 0
  if cfg.method == "hub" or not hasSprings then
    return 0, -h + extra
  elseif cfg.method == "springs" then
    return h, extra
  end
  local springPart = h < 0 and max(h, -M.SPRING_RANGE) or h
  return springPart, -(h - springPart) + extra
end

local function axleIsNeutral(a)
  for _, k in ipairs(M.axleKeys) do
    if abs(a[k] - M.defaultAxle[k]) > 1e-6 then return false end
  end
  return true
end

function M.isNeutral(cfg)
  local extra = cfg.hubExtra or {}
  return axleIsNeutral(cfg.F) and axleIsNeutral(cfg.R) and (extra.F or 0) < 1e-6 and (extra.R or 0) < 1e-6
end

local function addGroups(set, g)
  if type(g) == "string" then
    if g ~= "" then set[g] = true end
  elseif type(g) == "table" then
    for _, v in pairs(g) do
      if type(v) == "string" and v ~= "" then set[v] = true end
    end
  end
end

local function groupsOf(g)
  local list = {}
  if type(g) == "string" then
    if g ~= "" then list[1] = g end
  elseif type(g) == "table" then
    for _, v in pairs(g) do
      if type(v) == "string" and v ~= "" then list[#list + 1] = v end
    end
  end
  return list
end

local function sign(x)
  if x > 0.02 then return 1 elseif x < -0.02 then return -1 end
  return 0
end

-- every wheel row that will become a physics wheel
local function collectWheels(vehicle)
  local list = {}
  local nodes = vehicle.nodes
  if type(nodes) ~= "table" then return list end
  for _, section in ipairs(WHEEL_SECTIONS) do
    local rows = vehicle[section]
    if type(rows) == "table" then
      for _, row in pairs(rows) do
        if type(row) == "table" and (row.numRays == nil or (tonumber(row.numRays) or 1) > 0) then
          local n1, n2 = nodes[row.node1], nodes[row.node2]
          if type(n1) == "table" and type(n2) == "table" and n1.pos and n2.pos then
            local c = (n1.pos + n2.pos) * 0.5
            list[#list + 1] = {row = row, section = section, n1 = n1, n2 = n2, center = c, side = sign(c.x), name = row.name}
          end
        end
      end
    end
  end
  -- front is -y in jbeam space
  local sumY = 0
  for _, w in ipairs(list) do sumY = sumY + w.center.y end
  local meanY = #list > 0 and sumY / #list or 0
  for _, w in ipairs(list) do
    w.axle = (w.center.y <= meanY) and "F" or "R"
    if #list <= 2 then w.axle = "F" end
  end
  return list
end
M.collectWheels = collectWheels

local function nodeInGroups(node, set)
  local g = node.group
  if type(g) == "string" then return set[g] == true end
  if type(g) == "table" then
    for _, v in pairs(g) do if set[v] then return true end end
  end
  return false
end

-- nodes that move with the wheel: the axle nodes plus anything sharing their own node group
local function findAssembly(vehicle, w)
  local hubGroups = {}
  addGroups(hubGroups, w.n1.group)
  addGroups(hubGroups, w.n2.group)
  local set, list = {}, {}
  local function add(cid, node)
    if not set[cid] then set[cid] = true; list[#list + 1] = node end
  end
  add(w.row.node1, w.n1)
  add(w.row.node2, w.n2)
  if next(hubGroups) then
    for cid, node in pairs(vehicle.nodes) do
      if type(node) == "table" and node.pos and not set[cid] and nodeInGroups(node, hubGroups)
        and sign(node.pos.x) == w.side and node.pos:distance(w.center) < 0.6 then
        add(cid, node)
      end
    end
  end
  -- groups the wheel meshes are bound to
  local wheelGroups = {}
  addGroups(wheelGroups, w.row.group)
  addGroups(wheelGroups, w.row.hubGroup)
  addGroups(wheelGroups, w.row.hubcapGroup)
  for g in pairs(hubGroups) do wheelGroups[g] = true end
  return set, list, wheelGroups
end

local function isBrakeLike(fb)
  local s = string.lower(tostring(fb.mesh or "") .. " " .. tostring(fb.partPath or fb.partOrigin or ""))
  return s:find("brake", 1, true) or s:find("rotor", 1, true) or s:find("caliper", 1, true)
    or s:find("disc", 1, true) or s:find("drum", 1, true)
end

local function findFlexbodies(vehicle, wheelGroups)
  local list = {}
  if type(vehicle.flexbodies) ~= "table" or not next(wheelGroups) then return list end
  for _, fb in pairs(vehicle.flexbodies) do
    if type(fb) == "table" then
      local groups = groupsOf(fb["[group]:"] or fb.group)
      if #groups > 0 then
        local all = true
        for _, g in ipairs(groups) do
          if not wheelGroups[g] then all = false; break end
        end
        if all then list[#list + 1] = fb end
      end
    end
  end
  return list
end

local function isTransformKey(k, v)
  return type(k) == "string" and type(v) == "table"
    and (k:match("^nodeRotate%d*$") or k:match("^nodeOffset%d*$") or k:match("^nodeMove%d*$"))
end

-- bake all node transforms of a flexbody row into its pos / rot so ours can be stacked on top
local function flattenFlexbody(fb)
  if fb.__stanceStudioFlat then return end
  local px = fb.pos and tonumber(fb.pos.x) or 0
  local py = fb.pos and tonumber(fb.pos.y) or 0
  local pz = fb.pos and tonumber(fb.pos.z) or 0
  local rx = fb.rot and tonumber(fb.rot.x) or 0
  local ry = fb.rot and tonumber(fb.rot.y) or 0
  local rz = fb.rot and tonumber(fb.rot.z) or 0
  local x, y, z, ex, ey, ez = jbeamUtils.getFlexbodyPosRotAfterNodeRotateOffsetMove(fb, px, py, pz, rx, ry, rz)
  if x then px, py, pz = x, y, z end
  if ex then rx, ry, rz = ex, ey, ez end
  local strip = {}
  for k, v in pairs(fb) do
    if isTransformKey(k, v) then strip[#strip + 1] = k end
  end
  for _, k in ipairs(strip) do fb[k] = nil end
  fb.pos = {x = px, y = py, z = pz}
  fb.rot = {x = rx, y = ry, z = rz}
  fb.__stanceStudioFlat = true
end

-- flexbody euler angles (degrees) <-> quaternion, the same conversion as jbeam/utils
-- (setQuatFromEuler / quatToEuler, with the game's negated angles)
local function eulerToQuat(x, y, z)
  x, y, z = math.rad(-x) * 0.5, math.rad(-y) * 0.5, math.rad(-z) * 0.5
  local sx, cx, sy, cy, sz, cz = math.sin(x), math.cos(x), math.sin(y), math.cos(y), math.sin(z), math.cos(z)
  local q = quat()
  q:set(cz*sx*cy - sz*cx*sy, cz*cx*sy + sz*sx*cy, sz*cx*cy + cz*sx*sy, cz*cx*cy - sz*sx*sy)
  return q
end
M.eulerToQuat = eulerToQuat

local function quatToEulerDeg(q)
  local x, y, z, w = q.x, q.y, q.z, q.w
  local xx, yy, zz, ww = x*x, y*y, z*z, w*w
  local cxsy, cxcy = 2 * (w*y - x*z), ww - xx - yy + zz
  local cx = sqrt(cxsy*cxsy + cxcy*cxcy)
  local ex = math.atan2(2 * (y*z + w*x), cx)
  local ey, ez
  if cx < 1e-7 then -- gimbal lock
    ey, ez = 0, math.atan2(2 * (x*y + w*z), ww + xx - yy - zz)
  else
    ey, ez = math.atan2(cxsy, cxcy), math.atan2(2 * (w*z - x*y), ww - xx + yy - zz)
  end
  return math.deg(-ex), math.deg(-ey), math.deg(-ez)
end

-- one transform step. Nodes go through the game's helper; meshes take the very same rigid motion:
-- their origin moves like a node, and their orientation is the mesh's own rotation followed by the
-- step's rotation. (The game's flexbody helper multiplies those two the other way round, which only
-- shows on meshes that are already rotated, like the 180° mirrored right-side rims: their camber
-- came out reversed, poking the rim out of the arch and the caliper through the spokes.)
local function applyStep(step, nodesList, flexList)
  for _, node in ipairs(nodesList) do
    local x, y, z = jbeamUtils.getPosAfterNodeRotateOffsetMove(step, node.pos.x, node.pos.y, node.pos.z)
    node.pos = vec3(x, y, z)
  end
  local r = step.nodeRotate
  local qStep = r and eulerToQuat(r.x or 0, r.y or 0, r.z or 0) or nil
  for _, fb in ipairs(flexList) do
    flattenFlexbody(fb)
    local x, y, z = jbeamUtils.getPosAfterNodeRotateOffsetMove(step, fb.pos.x, fb.pos.y, fb.pos.z)
    fb.pos = {x = x, y = y, z = z}
    if qStep then
      local q = quat()
      q:setMul2(eulerToQuat(fb.rot.x, fb.rot.y, fb.rot.z), qStep) -- mesh rotation first, then the step
      local ex, ey, ez = quatToEulerDeg(q)
      fb.rot = {x = ex, y = ey, z = ez}
    end
  end
end

local function beamLengthAndVerticality(vehicle, beam)
  local a, b = vehicle.nodes[beam.id1], vehicle.nodes[beam.id2]
  if not (a and b and a.pos and b.pos) then return nil end
  local d = b.pos - a.pos
  local L = d:length()
  if L < 1e-4 then return nil end
  return L, abs(d.z) / L, (a.pos + b.pos) * 0.5
end

local function lowerName(beam)
  return string.lower(tostring(beam.name or "") .. " " .. tostring(beam.vkTag or ""))
end

-- Unsprung nodes of one corner: walk the beams out from the wheel, staying inside the part the
-- knuckle belongs to (suspension parts own the knuckle and arms, the body owns the towers).
local function findUnsprung(vehicle, adjacency, assemblySet, w)
  local nodes = vehicle.nodes
  local hubPart = nil
  for cid in pairs(assemblySet) do
    for _, nb in ipairs(adjacency[cid] or {}) do
      local n = nodes[nb]
      if n and not assemblySet[nb] and n.partOrigin then hubPart = n.partOrigin; break end
    end
    if hubPart then break end
  end
  local set = {}
  for cid in pairs(assemblySet) do set[cid] = true end
  local frontier = {}
  for cid in pairs(assemblySet) do frontier[#frontier + 1] = cid end
  for _ = 1, 4 do
    local nextF = {}
    for _, cid in ipairs(frontier) do
      for _, nb in ipairs(adjacency[cid] or {}) do
        local n = nodes[nb]
        if not set[nb] and n and n.pos and n.partOrigin == hubPart and sign(n.pos.x) == w.side
          and n.pos:distance(w.center) < 0.9 then
          set[nb] = true
          nextF[#nextF + 1] = nb
        end
      end
    end
    frontier = nextF
    if #frontier == 0 then break end
  end
  return set
end

-- springs and dampers of one corner
local function findSuspension(vehicle, adjacency, assemblySet, w, wheels)
  local springs, dampers = {}, {}
  local explicitSprings = {}
  local unsprung = findUnsprung(vehicle, adjacency, assemblySet, w)

  local function nearestCorner(mid)
    local best, bestD = nil, math.huge
    for _, o in ipairs(wheels) do
      if o.side ~= 0 then
        local d = mid:distance(o.center)
        if d < bestD then best, bestD = o, d end
      end
    end
    return best, bestD
  end

  for _, beam in pairs(vehicle.beams or {}) do
    if type(beam) == "table" and type(beam.id1) == "number" and type(beam.id2) == "number" then
      local L, vert, mid = beamLengthAndVerticality(vehicle, beam)
      if L and not (assemblySet[beam.id1] and assemblySet[beam.id2]) then
        local owner, dist = nearestCorner(mid)
        if owner == w and dist < 1.0 then
          local bt = beam.beamType or NORMALTYPE
          local name = lowerName(beam)
          local spring = tonumber(beam.beamSpring) or 0
          local damp = tonumber(beam.beamDamp) or 0
          local crosses = (unsprung[beam.id1] and not unsprung[beam.id2]) or (unsprung[beam.id2] and not unsprung[beam.id1])
          local explicit = type(beam.precompressionRange) == "number"
            or name:find("spring", 1, true) or name:find("coilover", 1, true)
          if explicit and (bt == NORMALTYPE or bt == BEAM_BOUNDED) and spring > 0 then
            explicitSprings[#explicitSprings + 1] = {beam = beam, L = L, vert = vert}
          elseif crosses and (bt == NORMALTYPE or bt == BEAM_BOUNDED) and spring >= 8000 and spring <= 400000
            and L > 0.12 and vert > 0.55 then
            springs[#springs + 1] = {beam = beam, L = L, vert = vert}
          end
          if bt == BEAM_BOUNDED and damp > 0 and (crosses or name:find("shock", 1, true) or name:find("damp", 1, true)) and vert > 0.4 then
            dampers[#dampers + 1] = beam
          end
        end
      end
    end
  end

  if #explicitSprings > 0 then return explicitSprings, dampers, "explicit" end
  if #springs >= 1 and #springs <= 3 then return springs, dampers, "guessed" end
  return {}, dampers, "none"
end

local function buildAdjacency(vehicle)
  local adj = {}
  for _, beam in pairs(vehicle.beams or {}) do
    if type(beam) == "table" and type(beam.id1) == "number" and type(beam.id2) == "number" then
      local a, b = beam.id1, beam.id2
      adj[a] = adj[a] or {}; adj[a][#adj[a] + 1] = b
      adj[b] = adj[b] or {}; adj[b][#adj[b] + 1] = a
    end
  end
  return adj
end

local function scaleField(t, key, k)
  local v = tonumber(t[key])
  if v then t[key] = v * k end
end

-- Main entry. vehicle = the jbeam tables at loading phase 1, cfg = normalized stance config.
-- Returns a small report the UI shows (which method each corner used).
function M.apply(vehicle, cfg)
  local report = {corners = {}, wheelCount = 0}
  local wheels = collectWheels(vehicle)
  report.wheelCount = #wheels
  if #wheels == 0 then return report end

  local adjacency = nil
  local touched = {} -- nodes are shared by twin wheels (duallies), move each node once

  for _, w in ipairs(wheels) do
    local a = cfg[w.axle]
    local corner = {axle = w.axle, side = w.side, name = w.name, method = "none", springs = 0, dampers = 0}
    report.corners[#report.corners + 1] = corner
    if a and w.side ~= 0 then
      local assemblySet, assemblyList, wheelGroups = findAssembly(vehicle, w)
      local moveNodes = {}
      for _, node in ipairs(assemblyList) do
        if not touched[node] then touched[node] = true; moveNodes[#moveNodes + 1] = node end
      end
      local flex = findFlexbodies(vehicle, wheelGroups)
      local flexOffset = {}
      for _, fb in ipairs(flex) do
        if not isBrakeLike(fb) then flexOffset[#flexOffset + 1] = fb end
      end
      corner.meshes = #flex

      -- ride height, stiffness, damping
      local dropZ = 0
      local hubExtra = cfg.hubExtra and cfg.hubExtra[w.axle] or 0
      local wantsHeight = abs(a.rideHeight) > 1e-5 or hubExtra > 1e-5
      local wantsSusp = wantsHeight or abs(a.spring - 1) > 1e-5 or abs(a.damp - 1) > 1e-5
      if wantsSusp then
        adjacency = adjacency or buildAdjacency(vehicle)
        local springs, dampers, how = findSuspension(vehicle, adjacency, assemblySet, w, wheels)
        corner.springs, corner.dampers, corner.found = #springs, #dampers, how
        if wantsHeight then
          local springPart, hubUp = M.splitRideHeight(cfg, w.axle, #springs > 0)
          dropZ = hubUp
          corner.springPart, corner.hubPart = springPart, hubUp
          if abs(springPart) > 1e-5 then
            local gain = cfg.gain[w.axle] or 1
            for _, s in ipairs(springs) do
              local beam = s.beam
              local baseRange
              if type(beam.precompressionRange) == "number" then
                baseRange = beam.precompressionRange
              else
                baseRange = s.L * ((tonumber(beam.beamPrecompression) or 1) - 1)
              end
              local delta = springPart * max(s.vert, 0.3) * gain
              beam.precompressionRange = max(baseRange + delta, -0.7 * s.L)
            end
          end
          if abs(springPart) > 1e-5 and abs(hubUp) > 1e-5 then corner.method = "springs+hub"
          elseif abs(hubUp) > 1e-5 then corner.method = "hub"
          else corner.method = "springs" end
        end
        if abs(a.spring - 1) > 1e-5 then
          for _, s in ipairs(springs) do scaleField(s.beam, "beamSpring", a.spring) end
        end
        if abs(a.damp - 1) > 1e-5 then
          for _, beam in ipairs(dampers) do
            scaleField(beam, "beamDamp", a.damp)
            scaleField(beam, "beamDampRebound", a.damp)
            scaleField(beam, "beamDampFast", a.damp)
            scaleField(beam, "beamDampReboundFast", a.damp)
          end
        end
      end

      -- geometry: rotate about the wheel center, then move
      local c = w.center
      local s = w.side
      if abs(a.camber) > 1e-6 then
        local step = {nodeRotate = {x = 0, y = s * a.camber, z = 0, px = c.x, py = c.y, pz = c.z}}
        applyStep(step, moveNodes, flex)
      end
      if abs(a.toe) > 1e-6 then
        local step = {nodeRotate = {x = 0, y = 0, z = -s * a.toe, px = c.x, py = c.y, pz = c.z}}
        applyStep(step, moveNodes, flex)
      end
      if abs(a.offset) > 1e-6 then
        local step = {nodeMove = {x = s * a.offset, y = 0, z = 0}}
        applyStep(step, moveNodes, flexOffset)
      end
      if abs(dropZ) > 1e-6 then
        local step = {nodeMove = {x = 0, y = 0, z = dropZ}}
        applyStep(step, moveNodes, flex)
      end
      if corner.method == "none" and (abs(a.camber) > 1e-6 or abs(a.toe) > 1e-6 or abs(a.offset) > 1e-6) then
        corner.method = "geometry"
      end
    end
  end

  -- steering lock: widen the travel of the steering rack hydros on each axle
  report.steerHydros = {F = 0, R = 0}
  local sumY = 0
  for _, w in ipairs(wheels) do sumY = sumY + w.center.y end
  local meanY = sumY / #wheels
  for _, h in pairs(vehicle.hydros or {}) do
    if type(h) == "table" and (h.inputSource == nil or h.inputSource == "steering" or h.inputSource == "steering_input") then
      local n1, n2 = vehicle.nodes[h.id1], vehicle.nodes[h.id2]
      if n1 and n2 and n1.pos and n2.pos then
        local axleKey = (#wheels <= 2 or (n1.pos.y + n2.pos.y) * 0.5 <= meanY) and "F" or "R"
        local k = cfg[axleKey] and cfg[axleKey].steer or 1
        if abs(k - 1) > 1e-4 then
          local inL, outL = tonumber(h.inLimit), tonumber(h.outLimit)
          if inL and outL and inL < 1 and outL > 1 then
            h.inLimit = max(1 - (1 - inL) * k, 0.05)
            h.outLimit = min(1 + (outL - 1) * k, 3)
            report.steerHydros[axleKey] = report.steerHydros[axleKey] + 1
          end
        end
      end
    end
  end
  return report
end

-- MARK: photo mode
-- The wheel photo car keeps a single rim: the wheel part being photographed (plus its own caps,
-- trims and lug nuts, but not its tire) on one corner. Body, props, brakes and the other wheels
-- are dropped, so a render of that car shows the rim alone.

local function meshIsTireOrBrake(fb)
  local m = string.lower(tostring(fb.mesh or ""))
  return m:find("tire", 1, true) or m:find("tyre", 1, true) or m:find("brake", 1, true)
    or m:find("caliper", 1, true) or m:find("rotor", 1, true)
end

local function photoPieceFilter(vehicle, part)
  -- where the wheel part sits in the parts tree, so its child parts (caps, trims) can be kept
  local basePath = nil
  for _, fb in pairs(vehicle.flexbodies) do
    if type(fb) == "table" and fb.partOrigin == part and type(fb.partPath) == "string" and fb.partPath ~= "" then
      basePath = fb.partPath
      break
    end
  end
  return function(fb)
    if type(fb) ~= "table" or meshIsTireOrBrake(fb) then return false end
    if fb.partOrigin == part then return true end
    local p = fb.partPath
    if basePath and type(p) == "string" and p:sub(1, #basePath + 1) == basePath .. "/" then
      local rest = string.lower(p:sub(#basePath + 2))
      return not (rest:find("tire", 1, true) or rest:find("tyre", 1, true))
    end
    return false
  end
end

-- photo = {part = "<wheel part name>"}; returns a report for the GE side (which wheel to aim at)
function M.photoStrip(vehicle, photo)
  local part = type(photo) == "table" and photo.part or nil
  if type(part) ~= "string" or part == "" then return {photo = true, error = "no part", corners = {}} end
  if type(vehicle.flexbodies) ~= "table" then vehicle.flexbodies = {} end
  local isPiece = photoPieceFilter(vehicle, part)

  -- left side first (+x), then front first (-y): the shot looks at the outside of that wheel
  local wheels = collectWheels(vehicle)
  table.sort(wheels, function(a, b)
    local sa, sb = (a.side == 1) and 0 or 1, (b.side == 1) and 0 or 1
    if sa ~= sb then return sa < sb end
    return a.center.y < b.center.y
  end)

  -- which corner each piece of the part belongs to (by the node groups its mesh is bound to)
  local groupsByWheel = {}
  for i, w in ipairs(wheels) do
    local _, _, groups = findAssembly(vehicle, w)
    groupsByWheel[i] = groups
  end
  local function ownerOf(fb)
    local groups = groupsOf(fb["[group]:"] or fb.group)
    if #groups == 0 then return nil end
    for i, wg in ipairs(groupsByWheel) do
      local all = true
      for _, g in ipairs(groups) do
        if not wg[g] then all = false; break end
      end
      if all then return i end
    end
    return nil
  end
  local pieces, chosenIdx = {}, nil
  for _, fb in pairs(vehicle.flexbodies) do
    if isPiece(fb) then
      local owner = ownerOf(fb)
      pieces[#pieces + 1] = {fb = fb, owner = owner}
      if owner and (not chosenIdx or owner < chosenIdx) then chosenIdx = owner end
    end
  end
  -- the chosen corner's pieces, plus pieces bound to no wheel at all (unusual mods)
  local keep = {}
  for _, p in ipairs(pieces) do
    if not chosenIdx or p.owner == chosenIdx or p.owner == nil then keep[#keep + 1] = p.fb end
  end
  local chosen = wheels[chosenIdx or 1]

  vehicle.flexbodies = keep
  vehicle.props = {}
  vehicle.mirrors = nil -- they point at meshes that are gone now
  return {
    photo = true,
    corners = {},
    kept = #keep,
    wheel = chosen and chosen.name or nil,
    hubRadius = chosen and tonumber(chosen.row.hubRadius) or nil,
    radius = chosen and tonumber(chosen.row.radius) or nil,
    width = chosen and tonumber(chosen.row.hubWidth or chosen.row.tireWidth) or nil,
  }
end

return M
