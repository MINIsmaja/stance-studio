-- Stance Studio: engine power estimate from jbeam data, so the parts menu can say "+42 hp".
-- Mirrors the game's own math in lua/vehicle/powertrain/combustionEngine.lua (torque table times
-- torqueModMult, plus torqueModIntake / torqueModExhaust), turbocharger.lua getTorqueCoefs and
-- supercharger.lua getTorqueCoefs. Pure module: no engine calls, testable outside the game.

local M = {}

local min, max, sqrt, floor, ceil, abs = math.min, math.max, math.sqrt, math.floor, math.ceil, math.abs
local RPM_TO_AV = math.pi / 30
local PSI_TO_PA = 6894.757
local TORQUE_TO_HP = 1 / 7120.9 -- same constant as combustionEngine.lua (torque * rpm -> hp)

-- fields of mainEngine that change power
M.ENGINE_KEYS = {"torque", "torqueModMult", "torqueModIntake", "torqueModExhaust", "maxRPM", "revLimiterRPM",
  "hasRevLimiter", "friction", "dynamicFriction", "turbocharger", "supercharger"}

local SC_TYPES = {
  roots = {b1 = -0.55, b3 = 1},
  rootsTwisted = {b1 = -0.35, b3 = 1},
  screws = {b1 = 0.3, b3 = 0.7},
  centrifugal = {b1 = 0.6, b3 = 0.45},
}

local function num(v, resolve)
  if type(v) == "number" then return v end
  if resolve and type(v) == "string" then
    local r = resolve(v)
    if type(r) == "number" then return r end
  end
  return nil
end

-- piecewise linear curve from a jbeam header table ({"rpm","torque"}, {0,0}, ...)
-- col = which column holds the value (2 by default)
local function curve(rows, col, resolve)
  if type(rows) ~= "table" then return nil end
  col = col or 2
  local pts = {}
  for _, row in pairs(rows) do
    if type(row) == "table" then
      local x, y = num(row[1], resolve), num(row[col], resolve)
      if x and y then pts[#pts + 1] = {x, y} end
    end
  end
  if #pts == 0 then return nil end
  table.sort(pts, function(a, b) return a[1] < b[1] end)
  local c = {pts = pts, first = pts[1][1], last = pts[#pts][1], lastValue = pts[#pts][2]}
  function c.at(x, outside)
    if x < c.first then return outside ~= nil and outside or pts[1][2] end
    if x > c.last then return outside ~= nil and outside or c.lastValue end
    for i = 2, #pts do
      local a, b = pts[i - 1], pts[i]
      if x <= b[1] then
        local span = b[1] - a[1]
        if span <= 0 then return b[2] end
        return a[2] + (b[2] - a[2]) * (x - a[1]) / span
      end
    end
    return c.lastValue
  end
  return c
end
M.curve = curve

local function wastegatePsi(turbo, resolve)
  local function lastOf(v)
    if type(v) == "table" then
      local last = nil
      for _, x in pairs(v) do
        local n = num(x, resolve)
        if n then last = n end
      end
      return last
    end
    return num(v, resolve)
  end
  local start = lastOf(turbo.wastegateStart) or 0
  local limit = lastOf(turbo.wastegateLimit) or (start + 0.01)
  return start + (limit - start) * 0.5
end

local function turboCoefFn(turbo, maxRPM, resolve)
  if type(turbo) ~= "table" then return nil end
  local pressure = curve(turbo.pressurePSI, 2, resolve)
  local eff = curve(turbo.engineDef, 2, resolve)
  local exh = curve(turbo.engineDef, 3, resolve)
  if not (pressure and eff and exh) then return nil end
  local maxTurboAV = max(pressure.last * RPM_TO_AV, 1)
  local maxExhaustPower = num(turbo.maxExhaustPower, resolve) or 1
  local backPressureCoef = num(turbo.backPressureCoef, resolve) or 0.0005
  local frictionCoef = num(turbo.frictionCoef, resolve) or 0.01
  local wg = wastegatePsi(turbo, resolve)
  local invEngMaxAV = 1 / max(maxRPM * RPM_TO_AV, 1)
  return function(rpm)
    local e = min(exh.at(rpm), 1)
    local turboAV = sqrt(max(0.9 * rpm * RPM_TO_AV * invEngMaxAV * e * maxExhaustPower - frictionCoef, 0) / backPressureCoef)
    turboAV = min(turboAV, maxTurboAV)
    local psi = pressure.at(floor(turboAV / RPM_TO_AV))
    local actual = min(psi, wg)
    return 1 + 0.0000087 * actual * PSI_TO_PA * eff.at(rpm), actual
  end
end

local function superchargerCoefFn(sc, maxRPM, resolve)
  if type(sc) ~= "table" then return nil end
  local per1k = num(sc.pressurePSIPer1kRPM, resolve)
  if not per1k then return nil end
  local ratio = num(sc.gearRatio, resolve) or 1
  local maxBlowerRPM = num(sc.maxRPM, resolve) or ceil(maxRPM * ratio)
  if maxBlowerRPM <= 0 then return nil end
  local t = string.lower(tostring(sc.type or "roots"))
  local shape
  if t == "screws" then shape = SC_TYPES.screws
  elseif t == "centrifugal" then shape = SC_TYPES.centrifugal
  elseif sc.twistedLobes then shape = SC_TYPES.rootsTwisted
  else shape = SC_TYPES.roots end
  local engageRPM = num(sc.clutchEngageRPM, resolve) or 1000
  local engageRange = num(sc.clutchEngageRange, resolve) or engageRPM * 0.2
  local disRPM = num(sc.clutchDisengageRPM, resolve) or maxRPM * 2
  local disRange = num(sc.clutchDisengageRange, resolve) or disRPM * 0.05
  local crankLoss = (num(sc.crankLossPer1kRPM, resolve) or 5) * 0.001
  return function(rpm)
    local engage = engageRange > 0 and min(max((rpm - engageRPM) / engageRange, 0), 1) or (rpm >= engageRPM and 1 or 0)
    local disengage = disRange > 0 and min(max(-(rpm - disRPM) / disRange + 1, 0), 1) or 1
    local blower = rpm * ratio * min(engage, disengage)
    local r = blower / maxBlowerRPM
    local psi = max((shape.b1 * r * r + shape.b3) * per1k * 0.001 * blower, 0)
    return 1 + 0.0000087 * psi * PSI_TO_PA - crankLoss * blower, psi
  end
end

-- engine = merged mainEngine fields, turbo / sc = merged sections (or nil)
-- returns peak hp, peak rpm, peak boost psi
function M.estimate(engine, turbo, sc, resolve)
  if type(engine) ~= "table" then return nil end
  local base = curve(engine.torque, 2, resolve)
  if not base then return nil end
  local mult = curve(engine.torqueModMult, 2, resolve)
  local intake = curve(engine.torqueModIntake, 2, resolve)
  local exhaust = curve(engine.torqueModExhaust, 2, resolve)
  local maxAvail = base.last
  if mult then maxAvail = max(maxAvail, mult.last) end
  if intake then maxAvail = max(maxAvail, intake.last) end
  if exhaust then maxAvail = max(maxAvail, exhaust.last) end
  local maxRPM = min(num(engine.maxRPM, resolve) or maxAvail, maxAvail)
  if engine.hasRevLimiter ~= false then maxRPM = num(engine.revLimiterRPM, resolve) or maxRPM end
  local friction = num(engine.friction, resolve) or 0
  local dynFriction = num(engine.dynamicFriction, resolve) or 0
  local tc = engine.turbocharger and turboCoefFn(turbo, maxRPM, resolve) or nil
  local scc = engine.supercharger and superchargerCoefFn(sc, maxRPM, resolve) or nil

  local best, bestRPM, bestBoost = 0, 0, 0
  local step = 25
  for rpm = step, floor(maxRPM) - 1, step do
    local t = base.at(rpm, 0) * (mult and mult.at(rpm) or 1)
      + (intake and intake.at(rpm) or 0) + (exhaust and exhaust.at(rpm) or 0)
    local coef, boost = 1, 0
    if tc then local c, b = tc(rpm); coef, boost = coef * c, max(boost, b) end
    if scc then local c, b = scc(rpm); coef, boost = coef * c, max(boost, b) end
    local net = t * coef - friction - dynFriction * rpm * RPM_TO_AV
    local hp = net * rpm * TORQUE_TO_HP
    if hp > best then best, bestRPM = hp, rpm end
    if boost > bestBoost then bestBoost = boost end
  end
  return best, bestRPM, bestBoost
end

-- MARK: merging parts the way the game does
-- jbeam/slotSystem.unifyParts merges every part's subtree into it after that subtree was merged
-- itself (post-order, children in slot order). Plain keys from children override, "$+" / "$*" /
-- "$<" / "$>" keys combine with the value already there, or stay as modifiers if there is none yet.
-- So a 250 ECU that only sets the wastegate of the intake's turbo keeps the rest of that turbo.

local function mergeSection(t, src, resolve)
  for k, v in pairs(src) do
    if resolve and type(v) == "string" and v:byte(1) == 36 and v:byte(2) ~= 61 then
      local r = resolve(v)
      if type(r) == "number" then v = r end
    end
    if type(k) == "string" and type(v) == "number" and k:byte(1) == 36 then
      local key, existing = k:sub(3), nil
      existing = t[key]
      if type(t[k]) == "number" then key, existing = k, t[k] end
      if type(existing) == "number" then
        local op = k:byte(2)
        if op == 43 then t[key] = existing + v
        elseif op == 42 then t[key] = existing * v
        elseif op == 60 then t[key] = min(existing, v)
        elseif op == 62 then t[key] = max(existing, v)
        else t[k] = v end
      else
        t[k] = v
      end
    else
      t[k] = v
    end
  end
end
M.mergeSection = mergeSection

-- node = {part = <raw jbeam part>, children = {node, ...}} with children in slot order
-- names = set of section names to merge (mainEngine, turbocharger, supercharger, ...)
function M.mergeTree(node, names, resolve)
  local acc = {}
  local part = node.part
  if type(part) == "table" then
    for name in pairs(names) do
      if type(part[name]) == "table" then
        acc[name] = {}
        mergeSection(acc[name], part[name], resolve)
      end
    end
  end
  for _, child in ipairs(node.children or {}) do
    for name, sec in pairs(M.mergeTree(child, names, resolve)) do
      acc[name] = acc[name] or {}
      mergeSection(acc[name], sec, resolve)
    end
  end
  return acc
end

-- peak hp of merged sections (engineName defaults to mainEngine)
function M.estimateMerged(merged, engineName, resolve)
  local me = merged[engineName or "mainEngine"]
  if type(me) ~= "table" then return nil end
  local tname = type(me.turbocharger) == "string" and me.turbocharger or "turbocharger"
  local sname = type(me.supercharger) == "string" and me.supercharger or "supercharger"
  return M.estimate(me, merged[tname], merged[sname], resolve)
end

-- What one set of parts adds to the engine: mainEngine fields and forced induction sections.
-- parts = list of raw jbeam part tables
function M.contributions(parts)
  local res = {engine = {}, turbo = nil, sc = nil, keys = {}, add = {}, mul = {}, hasTurbo = false, hasSC = false}
  for _, part in ipairs(parts) do
    local me = type(part) == "table" and part.mainEngine
    if type(me) == "table" then
      for _, k in ipairs(M.ENGINE_KEYS) do
        if me[k] ~= nil then
          res.engine[k] = me[k]
          res.keys[k] = true
        end
        -- jbeam modifier keys: "$+key" adds to the value, "$*key" multiplies it
        if type(me["$+" .. k]) == "number" then res.add[k] = (res.add[k] or 0) + me["$+" .. k] end
        if type(me["$*" .. k]) == "number" then res.mul[k] = (res.mul[k] or 1) * me["$*" .. k] end
      end
    end
    if type(part) == "table" then
      local tname = (type(me) == "table" and type(me.turbocharger) == "string") and me.turbocharger or "turbocharger"
      local sname = (type(me) == "table" and type(me.supercharger) == "string") and me.supercharger or "supercharger"
      if type(part[tname]) == "table" then
        res.turbo = res.turbo or {}
        for k, v in pairs(part[tname]) do res.turbo[k] = v end
        res.hasTurbo = true
      end
      if type(part[sname]) == "table" then
        res.sc = res.sc or {}
        for k, v in pairs(part[sname]) do res.sc[k] = v end
        res.hasSC = true
      end
    end
  end
  return res
end

-- current = {engine, turbo, sc} of the whole car; removed = contributions of the parts being
-- swapped out; added = contributions of the parts coming in. Returns the hypothetical set.
function M.swap(current, removed, added)
  local engine = {}
  for k, v in pairs(current.engine or {}) do engine[k] = v end
  -- undo the modifiers of the parts going out, then apply the ones coming in
  for k, a in pairs(removed.add or {}) do if type(engine[k]) == "number" then engine[k] = engine[k] - a end end
  for k, m in pairs(removed.mul or {}) do if type(engine[k]) == "number" and m ~= 0 then engine[k] = engine[k] / m end end
  for k in pairs(removed.keys or {}) do engine[k] = nil end
  for k, v in pairs(added.engine or {}) do engine[k] = v end
  for k, a in pairs(added.add or {}) do if type(engine[k]) == "number" then engine[k] = engine[k] + a end end
  for k, m in pairs(added.mul or {}) do if type(engine[k]) == "number" then engine[k] = engine[k] * m end end
  local turbo = (not removed.hasTurbo) and current.turbo or nil
  if added.hasTurbo then
    local t = {}
    for k, v in pairs(turbo or {}) do t[k] = v end
    for k, v in pairs(added.turbo) do t[k] = v end
    turbo = t
  end
  local sc = (not removed.hasSC) and current.sc or nil
  if added.hasSC then
    local s = {}
    for k, v in pairs(sc or {}) do s[k] = v end
    for k, v in pairs(added.sc) do s[k] = v end
    sc = s
  end
  return {engine = engine, turbo = turbo, sc = sc}
end

return M
