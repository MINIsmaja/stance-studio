-- Stance Studio: a copy of the stance and the simple Fun edits as tuning values (config.vars).
--
-- Tandem (the BeamNG Friends launcher) sends your car to friends as parts, tuning values and paint
-- only, so config.stanceStudio and config.stanceStudioFun never reach them. A copy of them as
-- numbers in config.vars does: the game ignores tuning values that no part defines, and the jbeam
-- hook on a friend's PC (Stance Studio is a shared mod of the session there) rebuilds the stance
-- and the edits from them.
--
-- Tandem takes up to 128 tuning values per car, finite numbers up to 1e8, names up to 100 letters.
-- Only values that differ from stock are written, so a typical stance is 4 to 10 of them.
-- Not copied: the torque curve and the Advanced edits (their paths are text, and long curves would
-- push the car's own tuning values out of Tandem's 128).
--
-- Precedence when a car spawns: config.stanceStudio / stanceStudioFun (a table, or false = none)
-- win; the tuning values only count when those keys are missing (a friend's copy in Tandem).

local M = {}

local stance = require("ge/extensions/stanceStudio/stance")
local fun = require("ge/extensions/stanceStudio/fun")

local P = "$stanceStudio_"
local Q = P .. "q_"
M.PREFIX = P
local LIMIT = 1e8

local METHOD_CODE = {springs = 1, hub = 2}
local METHOD_NAME = {[1] = "springs", [2] = "hub"}

-- the simple Fun edits that are copied, and the field that holds their number
local QUICK_FIELD = {
  indestructibleEngine = "value", noRevLimiter = "value", maxRPM = "value", boost = "psi", afterfire = "level",
  nitrous = "hp", weight = "scale", grip = "scale", brakes = "scale", unbreakable = "value", fragile = "value",
}
local QUICK_BOOL = {indestructibleEngine = true, noRevLimiter = true, unbreakable = true, fragile = true}
M.QUICK_FIELD = QUICK_FIELD

local function num(v)
  if v == true then return 1 end
  v = tonumber(v) -- "FLT_MAX" and other text: not copied
  if not v or v ~= v or math.abs(v) > LIMIT then return nil end
  return v
end

local function isStanceVar(k) return type(k) == "string" and k:sub(1, #P) == P and k:sub(1, #Q) ~= Q end
local function isFunVar(k) return type(k) == "string" and k:sub(1, #Q) == Q end
M.isStanceVar, M.isFunVar = isStanceVar, isFunVar

-- tuning values for a stance config (only what differs from stock; none for the photo car)
function M.stanceVars(raw)
  local out = {}
  if type(raw) ~= "table" or type(raw.photo) == "table" then return out end
  local cfg = stance.normalize(raw)
  if stance.isNeutral(cfg) then return out end
  if METHOD_CODE[cfg.method] then out[P .. "method"] = METHOD_CODE[cfg.method] end
  for _, axle in ipairs({"F", "R"}) do
    for _, k in ipairs(stance.axleKeys) do
      local v = cfg[axle][k]
      if math.abs(v - stance.defaultAxle[k]) > 1e-9 then out[P .. axle .. "_" .. k] = v end
    end
    local g = cfg.gain[axle] or 1
    if math.abs(g - 1) > 1e-9 then out[P .. axle .. "_gain"] = g end
    local h = cfg.hubExtra[axle] or 0
    if math.abs(h) > 1e-9 then out[P .. axle .. "_hubExtra"] = h end
  end
  return out
end

-- tuning values for the Fun edits. engines: the car's engine sections (fun.engineSections), an
-- edit for an engine is stored by its place in that sorted list (0 = not for one engine).
function M.funVars(rawFun, engines)
  local out = {}
  if type(rawFun) ~= "table" or type(rawFun.edits) ~= "table" then return out end
  local index = {}
  for i, name in ipairs(engines or {}) do index[name] = i end
  for _, e in pairs(rawFun.edits) do
    local field = type(e) == "table" and e.kind == "quick" and QUICK_FIELD[e.name]
    if field and e.value ~= false then
      local i = e.engine == nil and 0 or index[e.engine]
      local v = num(e[field])
      if i and v then out[Q .. e.name .. "_" .. i] = v end
    end
  end
  return out
end

-- Brings config.vars in step with config.stanceStudio / stanceStudioFun, in place (the car's own
-- tuning values are kept). A key that is missing leaves its half of the copy alone: a friend's
-- copy has no stanceStudio key, only the tuning values. Returns true when something changed.
function M.write(config, engines)
  if type(config) ~= "table" then return false end
  local s, f = config.stanceStudio, config.stanceStudioFun
  if s == nil and f == nil then return false end
  local want = {}
  if s ~= nil then for k, v in pairs(M.stanceVars(s)) do want[k] = v end end
  if f ~= nil then for k, v in pairs(M.funVars(f, engines)) do want[k] = v end end
  local vars = config.vars
  if type(vars) ~= "table" then
    if next(want) == nil then return false end
    vars = {}
    config.vars = vars
  end
  local changed = false
  for k in pairs(vars) do
    if ((s ~= nil and isStanceVar(k)) or (f ~= nil and isFunVar(k))) and want[k] == nil then
      vars[k] = nil
      changed = true
    end
  end
  for k, v in pairs(want) do
    if vars[k] ~= v then
      vars[k] = v
      changed = true
    end
  end
  return changed
end

-- The stance and Fun edits a config carries as tuning values, or nil. engines: as in funVars, for
-- the car being built (the same parts give the same sorted list).
function M.read(vars, engines)
  if type(vars) ~= "table" then return nil, nil end
  local st, edits, any = {F = {}, R = {}, gain = {}, hubExtra = {}}, {}, false
  for k, v in pairs(vars) do
    v = tonumber(v)
    if v and v == v and isStanceVar(k) then
      local rest = k:sub(#P + 1)
      local axle, key = rest:match("^([FR])_(%a+)$")
      if rest == "method" then
        st.method = METHOD_NAME[v]
        any = true
      elseif axle and (key == "gain" or key == "hubExtra") then
        st[key][axle] = v
        any = true
      elseif axle and stance.defaultAxle[key] ~= nil then
        st[axle][key] = v
        any = true
      end
    elseif v and v == v and isFunVar(k) then
      local name, i = k:sub(#Q + 1):match("^(%a+)_(%d+)$")
      i = tonumber(i)
      local field = name and QUICK_FIELD[name]
      local engine = i and i > 0 and engines and engines[i] or nil
      if field and (i == 0 or engine) then
        local e = {kind = "quick", name = name, engine = engine}
        if QUICK_BOOL[name] then e[field] = v ~= 0 else e[field] = v end
        if e[field] ~= false then edits[fun.idOf(e)] = e end
      end
    end
  end
  local fn = next(edits) and {v = fun.VERSION, edits = edits} or nil
  if any then st.v = stance.version end
  return any and st or nil, fn
end

return M
