-- Stance Studio: ghost tire preview.
-- While a slider moves, draws where each tire will sit once the change is applied (relative to the
-- body), plus an outline of where it is now. Nothing is respawned until the change is applied.

local M = {}

local rad, cos, sin = math.rad, math.cos, math.sin

local active = nil   -- {vehId, applied, pending, color}
local SEGMENTS = 28

local function hexToColor(hex, alpha)
  local r, g, b = tostring(hex or ""):match("#?(%x%x)(%x%x)(%x%x)")
  if not r then return ColorF(0.22, 0.74, 0.97, alpha) end
  return ColorF(tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255, alpha)
end

-- right-hand rotation of v around unit axis k
local function rotate(v, k, angle)
  local c, s = cos(angle), sin(angle)
  return v * c + k:cross(v) * s + k * (k:dot(v) * (1 - c))
end

local function drawRing(center, axle, radius, color, upHint)
  local u = axle:cross(upHint)
  if u:length() < 1e-4 then u = axle:cross(vec3(1, 0, 0)) end
  u = u:normalized()
  local v = axle:cross(u):normalized()
  local prev = nil
  for i = 0, SEGMENTS do
    local t = i / SEGMENTS * 2 * math.pi
    local p = center + (u * cos(t) + v * sin(t)) * radius
    if prev then debugDrawer:drawLine(prev, p, color) end
    prev = p
  end
end

function M.setPending(vehId, applied, pending, colorHex)
  active = {
    vehId = vehId,
    applied = applied,
    pending = pending,
    ghost = hexToColor(colorHex, 0.32),
    ghostLine = hexToColor(colorHex, 1),
  }
end

function M.clear()
  active = nil
end

function M.isActive()
  return active ~= nil
end

local outlineColor = ColorF(1, 1, 1, 0.75)

local function draw()
  local veh = getObjectByID(active.vehId)
  if not veh then active = nil return end
  local data = core_vehicle_manager.getVehicleData(active.vehId)
  local vdata = data and data.vdata
  if not vdata or not vdata.wheels then return end

  local fwd = vec3(veh:getDirectionVectorXYZ())
  local up = vec3(veh:getDirectionVectorUpXYZ())
  local right = fwd:cross(up):normalized()
  local vehPos = vec3(veh:getPositionXYZ())

  -- axle of each wheel from its spawn position (front = -y in jbeam space)
  local sumY, n = 0, 0
  for _, w in pairs(vdata.wheels) do
    local a, b = vdata.nodes[w.node1], vdata.nodes[w.node2]
    if a and b then sumY, n = sumY + (a.pos.y + b.pos.y) * 0.5, n + 1 end
  end
  local meanY = n > 0 and sumY / n or 0

  for _, w in pairs(vdata.wheels) do
    local a, b = vdata.nodes[w.node1], vdata.nodes[w.node2]
    if a and b then
      local jx = (a.pos.x + b.pos.x) * 0.5
      local side = jx > 0.02 and 1 or (jx < -0.02 and -1 or 0)
      local axleKey = (n <= 2 or (a.pos.y + b.pos.y) * 0.5 <= meanY) and "F" or "R"
      local ap, pp = active.applied[axleKey], active.pending[axleKey]
      if side ~= 0 and ap and pp then
        local d = {
          camber = pp.camber - ap.camber,
          toe = pp.toe - ap.toe,
          offset = pp.offset - ap.offset,
          rideHeight = pp.rideHeight - ap.rideHeight,
        }
        if math.abs(d.camber) + math.abs(d.toe) + math.abs(d.offset) * 50 + math.abs(d.rideHeight) * 50 > 1e-4 then
          local p1 = vehPos + vec3(veh:getNodePositionXYZ(w.node1))
          local p2 = vehPos + vec3(veh:getNodePositionXYZ(w.node2))
          local center = (p1 + p2) * 0.5
          local out = side == 1 and -right or right -- jbeam +x is the car's left
          local axle = (p2 - p1):normalized()
          if axle:dot(out) < 0 then axle = -axle end
          local radius = tonumber(w.radius) or 0.33
          local width = tonumber(w.tireWidth) or tonumber(w.hubWidth) or 0.22
          if width > 0.6 then width = 0.22 end

          -- now: white outline
          drawRing(center + axle * (width * 0.5), axle, radius, outlineColor, up)
          drawRing(center - axle * (width * 0.5), axle, radius, outlineColor, up)

          -- after: rotate the axle, then move the center (body-relative: lowering lifts the wheel)
          local gAxle = axle
          if math.abs(d.camber) > 1e-6 then gAxle = rotate(gAxle, fwd * side, rad(-d.camber)) end
          if math.abs(d.toe) > 1e-6 then gAxle = rotate(gAxle, up * (-side), rad(d.toe)) end
          gAxle = gAxle:normalized()
          local gCenter = center + out * d.offset - up * d.rideHeight
          local half = gAxle * (width * 0.5)
          debugDrawer:drawCylinder(gCenter - half, gCenter + half, radius, active.ghost)
          drawRing(gCenter + half, gAxle, radius, active.ghostLine, up)
          drawRing(gCenter - half, gAxle, radius, active.ghostLine, up)
        end
      end
    end
  end
end

function M.onPreRender(dt)
  if not active then return end
  local ok, err = pcall(draw)
  if not ok then
    log('E', 'stanceStudio', 'preview failed: ' .. tostring(err))
    active = nil
  end
end

function M.onVehicleSpawned(vid)
  if active and active.vehId == vid then active = nil end
end

function M.onExtensionLoaded()
  setExtensionUnloadMode(M, "manual")
end

return M
