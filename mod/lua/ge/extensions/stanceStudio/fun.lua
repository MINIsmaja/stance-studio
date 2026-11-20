-- Stance Studio "Fun stuff": edit any JBeam value of the current car from the menu, without touching
-- a single game file. Edits live in vehicleConfig.stanceStudioFun = {v = 1, edits = {[id] = edit}},
-- so they are saved with the car's config, and are applied in the jbeam phase-1 hook, before the
-- wheels and meshes are built.
--
-- Edit kinds:
--   {kind = "value",  path = {"mainEngine", "maxRPM"}, value = 9000}            one value (number, bool, text)
--   {kind = "column", path = {"mainEngine", "torque"}, column = 2, scale = 100} one column of a table (torque curve)
--   {kind = "rows",   section = "beams", field = "beamStrength", scale = 10}     that field on every row
--   {kind = "row",    section = "pressureWheels", row = "FR", field = "brakeTorque", value = 5000}
--
-- Values that are infinite in the game (FLT_MAX) travel as the text "FLT_MAX" (JSON has no infinity).

local M = {}

M.VERSION = 1
M.MAX_LISTED_ROWS = 24  -- row sections up to this size also get one slider per row
M.MAX_FIELDS = 600      -- per section, so a huge section can not flood the menu
M.MAX_DEPTH = 4

local huge = math.huge

-- top-level keys that are bookkeeping, parts, meshes or generated later, not values to tune
M.SKIP = {
  maxIDs = true, information = true, slots = true, slots2 = true, slotType = true, flexbodies = true,
  props = true, activePartsData = true, activeParts = true, slotPartMap = true, directoriesLoaded = true,
  vehicleDirectory = true, model = true, partName = true, partOrigin = true, partPath = true,
  variables = true, validTables = true, paints = true, materials = true, glowMap = true, wheels = true,
  rotators = true, refNodes = true, events = true, sounds = true, licenseplates = true, partsCondition = true,
  occupantSlots = true, interactions = true, components = true, stanceStudio = true,
}

-- numbers on rows that are references to nodes or enums, not values (editing them breaks the car)
local REF_FIELDS = {
  cid = true, beamType = true, posX = true, posY = true, posZ = true, pos = true, wheelID = true,
  partIndex = true, breakGroupType = true, nodeArm = true, nodeS = true, nodeStabilizer = true,
  nodeCoupling = true, nodeMaterial = true, refNode = true, nodeOffset = true, inputIndex = true,
}
local function isRefField(f)
  if type(f) ~= "string" then return true end
  return REF_FIELDS[f] == true or f:match("^id%d*$") ~= nil or f:match("^node%d") ~= nil
    or f:match("^torqueArm") ~= nil or f:match("^torqueCoupling") ~= nil
end

-- loader defaults for rows that leave these fields out (lua/common/jbeam/loader.lua)
local ROW_DEFAULTS = {
  nodes = {nodeWeight = 25},
  beams = {beamSpring = 4300000, beamDeform = 220000, beamDamp = 580, beamStrength = huge},
}

-- MARK: values

local function encode(v)
  if type(v) == "number" then
    if v ~= v then return nil end
    if v == huge then return "FLT_MAX" end
    if v == -huge then return "-FLT_MAX" end
  end
  return v
end
M.encode = encode

local function decode(v)
  if v == "FLT_MAX" then return huge end
  if v == "-FLT_MAX" then return -huge end
  return v
end
M.decode = decode

local function isArray(t)
  local n = #t
  if n == 0 then return false, 0 end
  local count = 0
  for k in pairs(t) do
    count = count + 1
    if type(k) ~= "number" then return false, n end
  end
  return count == n, n
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    if type(a) == type(b) and (type(a) == "number" or type(a) == "string") then return a < b end
    return type(a) == "number"
  end)
  return keys
end

-- MARK: ids (the UI keys edits by these)

local function pathText(path)
  local parts = {}
  for i, p in ipairs(path) do parts[i] = tostring(p) end
  return table.concat(parts, "|")
end

function M.valueId(path) return "v|" .. pathText(path) end
function M.columnId(path, column) return "c|" .. pathText(path) .. "|#" .. tostring(column) end
function M.rowsId(section, field) return "r|" .. tostring(section) .. "|" .. tostring(field) end
function M.rowId(section, row, field) return "w|" .. tostring(section) .. "|" .. tostring(row) .. "|" .. tostring(field) end

function M.idOf(e)
  if type(e) ~= "table" then return nil end
  if e.kind == "value" and type(e.path) == "table" then return M.valueId(e.path) end
  if e.kind == "column" and type(e.path) == "table" then return M.columnId(e.path, e.column) end
  if e.kind == "rows" then return M.rowsId(e.section, e.field) end
  if e.kind == "row" then return M.rowId(e.section, e.row, e.field) end
  return nil
end

-- a row's name for "row" edits: its own name, else its key in the section
local function rowName(key, row)
  if type(row.name) == "string" and row.name ~= "" then return row.name end
  return tostring(key)
end

-- a table that is a list of rows (nodes, beams, wheels): every entry is a key/value row
local function isRowsSection(t)
  local n = 0
  for _, v in pairs(t) do
    n = n + 1
    if type(v) ~= "table" then return false end
    local arr = isArray(v)
    if arr then return false end
    if n >= 40 then break end
  end
  return n > 0
end

-- [["rpm", "torque"], [0, 0], [1000, 150], ...]: a header row of names, then rows of values
local function isHeaderTable(t)
  local arr, n = isArray(t)
  if not arr or n < 2 or type(t[1]) ~= "table" then return false end
  local h = t[1]
  local harr, hn = isArray(h)
  if not harr then return false end
  for i = 1, hn do if type(h[i]) ~= "string" then return false end end
  for i = 2, n do if type(t[i]) ~= "table" then return false end end
  return true
end

local function allNumbers(t)
  local arr, n = isArray(t)
  if not arr then return false end
  for i = 1, n do if type(t[i]) ~= "number" then return false end end
  return true
end

-- MARK: apply (jbeam phase 1)

local function resolveParent(root, path)
  if type(path) ~= "table" or #path == 0 then return nil end
  local t = root
  for i = 1, #path - 1 do
    t = t[path[i]]
    if type(t) ~= "table" then return nil end
  end
  return t, path[#path]
end

local function coerce(old, new)
  new = decode(new)
  if type(old) == "number" then return tonumber(new) end
  if type(old) == "boolean" then
    if type(new) == "boolean" then return new end
    if new == "true" or new == 1 then return true end
    if new == "false" or new == 0 then return false end
    return nil
  end
  if type(old) == "string" then return new ~= nil and tostring(new) or nil end
  return nil
end

local function scaleNumber(v, k)
  if v == huge or v == -huge then return v end -- infinite stays infinite (0 * inf is not a number)
  return v * k
end

local function applyOne(vehicle, e, id, report)
  local kind = e.kind
  if kind == "value" then
    local parent, key = resolveParent(vehicle, e.path)
    if not parent or parent[key] == nil or type(parent[key]) == "table" then return false end
    local new = coerce(parent[key], e.value)
    if new == nil then return false end
    if report.original[id] == nil then report.original[id] = encode(parent[key]) end
    parent[key] = new
    return true

  elseif kind == "column" then
    local parent, key = resolveParent(vehicle, e.path)
    local t = parent and parent[key]
    local col, k = tonumber(e.column), tonumber(decode(e.scale))
    if type(t) ~= "table" or not col or not k or not isHeaderTable(t) then return false end
    local n = 0
    for i = 2, #t do
      local row = t[i]
      if type(row) == "table" and type(row[col]) == "number" then
        row[col] = scaleNumber(row[col], k)
        n = n + 1
      end
    end
    return n > 0

  elseif kind == "rows" or kind == "row" then
    local sec = vehicle[e.section]
    local field = e.field
    if type(sec) ~= "table" or type(field) ~= "string" or isRefField(field) then return false end
    local k = e.scale ~= nil and tonumber(decode(e.scale)) or nil
    local v = e.value ~= nil and decode(e.value) or nil
    if k == nil and v == nil then return false end
    local defaults = ROW_DEFAULTS[e.section] or {}
    local default = defaults[field]
    if default ~= nil and type(vehicle.options) == "table" and type(vehicle.options[field]) == "number" then
      default = vehicle.options[field]
    end
    local n = 0
    for key, row in pairs(sec) do
      if type(row) == "table" and (kind == "rows" or rowName(key, row) == tostring(e.row)) then
        local old = row[field]
        if old == nil and default ~= nil then old = default end
        if type(old) == "number" then
          local new = k and scaleNumber(old, k) or tonumber(v)
          if new then
            if kind == "row" and report.original[id] == nil then report.original[id] = encode(old) end
            row[field] = new
            n = n + 1
          end
        elseif type(old) == "boolean" and kind == "row" and v ~= nil then
          local new = coerce(old, v)
          if new ~= nil then
            if report.original[id] == nil then report.original[id] = old end
            row[field] = new
            n = n + 1
          end
        end
      end
    end
    return n > 0
  end
  return false
end

-- fun = vehicleConfig.stanceStudioFun; returns {applied, missed = {ids}, original = {id = stock value}}
function M.apply(vehicle, fun)
  local report = {applied = 0, missed = {}, original = {}}
  local edits = type(fun) == "table" and fun.edits or nil
  if type(edits) ~= "table" then return report end
  -- stable order: rows and columns first, then single values on top of them
  local ids = sortedKeys(edits)
  table.sort(ids, function(a, b)
    local ka, kb = tostring(a):sub(1, 1), tostring(b):sub(1, 1)
    local order = {r = 1, c = 2, w = 3, v = 4}
    if ka ~= kb then return (order[ka] or 9) < (order[kb] or 9) end
    return tostring(a) < tostring(b)
  end)
  for _, id in ipairs(ids) do
    local e = edits[id]
    local ok, res = pcall(applyOne, vehicle, type(e) == "table" and e or {}, id, report)
    if ok and res then
      report.applied = report.applied + 1
    else
      report.missed[#report.missed + 1] = tostring(id)
    end
  end
  return report
end

-- MARK: describe (for the menu, from the spawned car's data)

local GROUPS = {
  {name = "Engine & power", words = {"engine", "turbo", "supercharger", "nitrous", "n2o", "motor", "fuel", "energy",
    "exhaust", "intake", "radiator", "thermal", "battery", "tank", "ignition", "ecu", "power"}},
  {name = "Drivetrain", words = {"gearbox", "transmission", "diff", "shaft", "clutch", "converter", "transfer",
    "axle", "rangebox", "splitter", "gear"}},
  {name = "Wheels & brakes", words = {"wheel", "tire", "tyre", "brake", "hub"}},
  {name = "Body & physics", words = {"nodes", "beams", "triangles", "torsionbar", "hydro", "rail", "slidenode", "quads", "options"}},
  {name = "Camera", words = {"camera"}},
}
local function groupOf(name)
  local s = string.lower(tostring(name))
  for i, g in ipairs(GROUPS) do
    for _, w in ipairs(g.words) do
      if s:find(w, 1, true) then return g.name, i end
    end
  end
  return "Other", #GROUPS + 1
end

local function editsOf(fun)
  return type(fun) == "table" and type(fun.edits) == "table" and fun.edits or {}
end

-- every editable field of a key/value section, flattened
local function flatten(t, path, out, depth, edits, original)
  for _, k in ipairs(sortedKeys(t)) do
    if #out >= M.MAX_FIELDS then return end
    local v = t[k]
    local p = {}
    for i, x in ipairs(path) do p[i] = x end
    p[#p + 1] = k
    local tv = type(v)
    if tv == "number" or tv == "boolean" or tv == "string" then
      if tv ~= "number" or v == v then
        local id = M.valueId(p)
        local orig = original[id]
        out[#out + 1] = {kind = "value", id = id, path = p, type = tv, value = encode(v),
          stock = orig ~= nil and orig or encode(v), edited = edits[id] ~= nil}
      end
    elseif tv == "table" then
      if isHeaderTable(v) then
        local cols = {}
        local header = v[1]
        for c = 1, #header do
          local lo, hi, n = huge, -huge, 0
          for i = 2, #v do
            local x = type(v[i]) == "table" and v[i][c] or nil
            if type(x) == "number" and x == x then
              n = n + 1
              if x < lo then lo = x end
              if x > hi then hi = x end
            end
          end
          if n > 0 then
            local id = M.columnId(p, c)
            local e = edits[id]
            local k = e and tonumber(decode(e.scale)) or 1
            if not k or k == 0 then k = 1 end
            cols[#cols + 1] = {column = c, name = tostring(header[c]), id = id, scale = encode(e and tonumber(decode(e.scale)) or 1),
              stockMin = encode(lo / k), stockMax = encode(hi / k), edited = e ~= nil}
          end
        end
        -- every point, so single points get their own slider (a "value" edit on path .. row, column)
        local rows = {}
        for i = 2, math.min(#v, 200) do
          local cells = {}
          for c = 1, #header do
            local x = type(v[i]) == "table" and v[i][c] or nil
            if type(x) == "number" and x == x then
              local pp = {}
              for j, y in ipairs(p) do pp[j] = y end
              pp[#pp + 1] = i
              pp[#pp + 1] = c
              local id = M.valueId(pp)
              local orig = original[id]
              cells[c] = {column = c, id = id, path = pp, value = encode(x), stock = orig ~= nil and orig or encode(x), edited = edits[id] ~= nil}
            else
              cells[c] = {column = c, text = x ~= nil and tostring(x) or ""}
            end
          end
          rows[#rows + 1] = {index = i, cells = cells}
        end
        if #cols > 0 then
          out[#out + 1] = {kind = "column", path = p, type = "table", header = header, columns = cols, rows = rows}
        end
      elseif allNumbers(v) then
        local values = {}
        for i = 1, #v do
          local pp = {}
          for j, x in ipairs(p) do pp[j] = x end
          pp[#pp + 1] = i
          local id = M.valueId(pp)
          local orig = original[id]
          values[i] = {id = id, path = pp, value = encode(v[i]), stock = orig ~= nil and orig or encode(v[i]), edited = edits[id] ~= nil}
        end
        out[#out + 1] = {kind = "list", path = p, type = "numbers", values = values}
      elseif depth < M.MAX_DEPTH then
        flatten(v, p, out, depth + 1, edits, original)
      end
    end
  end
end

local function describeRows(name, sec, edits, original)
  local stats, order, count = {}, {}, 0
  for _, row in pairs(sec) do
    if type(row) == "table" then
      count = count + 1
      for f, x in pairs(row) do
        if type(x) == "number" and x == x and not isRefField(f) then
          local s = stats[f]
          if not s then s = {n = 0, lo = huge, hi = -huge}; stats[f] = s; order[#order + 1] = f end
          s.n = s.n + 1
          if x < s.lo then s.lo = x end
          if x > s.hi then s.hi = x end
        end
      end
    end
  end
  -- fields the loader fills in later (node weight, beam defaults) can be scaled even when left out
  for f in pairs(ROW_DEFAULTS[name] or {}) do
    if not stats[f] then stats[f] = {n = 0, lo = huge, hi = -huge, default = true}; order[#order + 1] = f end
  end
  table.sort(order)
  local fields = {}
  for _, f in ipairs(order) do
    local s = stats[f]
    local id = M.rowsId(name, f)
    local e = edits[id]
    local k = e and tonumber(decode(e.scale)) or 1
    if not k or k == 0 then k = 1 end
    fields[#fields + 1] = {field = f, id = id, count = s.n, scale = encode(e and tonumber(decode(e.scale)) or 1),
      stockMin = s.n > 0 and encode(s.lo / k) or nil, stockMax = s.n > 0 and encode(s.hi / k) or nil,
      defaultOnly = s.default == true, edited = e ~= nil}
  end
  local rows = nil
  if count <= M.MAX_LISTED_ROWS then
    rows = {}
    for _, key in ipairs(sortedKeys(sec)) do
      local row = sec[key]
      if type(row) == "table" then
        local rn = rowName(key, row)
        local values = {}
        for _, f in ipairs(order) do
          local x = row[f]
          if type(x) == "number" and x == x then
            local id = M.rowId(name, rn, f)
            local orig = original[id]
            values[#values + 1] = {field = f, id = id, value = encode(x), stock = orig ~= nil and orig or encode(x), edited = edits[id] ~= nil}
          end
        end
        if #values > 0 then rows[#rows + 1] = {row = rn, values = values} end
      end
    end
  end
  return {name = name, kind = "rows", count = count, fields = fields, rows = rows}
end

-- one section in full: {name, kind = "settings" | "rows", fields | rows}
function M.describeSection(vdata, name, fun, report)
  local sec = type(vdata) == "table" and vdata[name] or nil
  if type(sec) ~= "table" or M.SKIP[name] then return nil end
  local edits = editsOf(fun)
  local original = type(report) == "table" and type(report.original) == "table" and report.original or {}
  local group = groupOf(name)
  local res
  if isRowsSection(sec) then
    res = describeRows(name, sec, edits, original)
  else
    local fields = {}
    flatten(sec, {name}, fields, 1, edits, original)
    res = {name = name, kind = "settings", fields = fields}
  end
  res.group = group
  return res
end

local function countEdited(d)
  local n = 0
  for _, f in ipairs(d.fields or {}) do
    if f.edited then n = n + 1 end
    for _, c in ipairs(f.columns or {}) do if c.edited then n = n + 1 end end
    for _, v in ipairs(f.values or {}) do if v.edited then n = n + 1 end end
  end
  for _, r in ipairs(d.rows or {}) do
    for _, v in ipairs(r.values or {}) do if v.edited then n = n + 1 end end
  end
  return n
end

-- the list of sections for the menu: {name, kind, group, count, edited}
function M.describe(vdata, fun, report)
  local list = {}
  if type(vdata) ~= "table" then return list end
  for _, name in ipairs(sortedKeys(vdata)) do
    if type(name) == "string" and not M.SKIP[name] and type(vdata[name]) == "table" then
      local d = M.describeSection(vdata, name, fun, report)
      local n = d and #d.fields or 0
      if d and n > 0 then
        local group, order = groupOf(name)
        list[#list + 1] = {name = name, kind = d.kind, group = group, groupOrder = order,
          count = d.kind == "rows" and d.count or #d.fields, fields = n, edited = countEdited(d)}
      end
    end
  end
  table.sort(list, function(a, b)
    if a.groupOrder ~= b.groupOrder then return a.groupOrder < b.groupOrder end
    return string.lower(a.name) < string.lower(b.name)
  end)
  return list
end

-- fields matching a search across all sections (labels like "mainEngine › maxRPM")
function M.search(vdata, query, fun, report, limit)
  limit = limit or 120
  local q = string.lower(tostring(query or ""))
  local res = {}
  if q == "" or type(vdata) ~= "table" then return res end
  for _, s in ipairs(M.describe(vdata, fun, report)) do
    local d = M.describeSection(vdata, s.name, fun, report)
    local hitsSection = string.lower(s.name):find(q, 1, true) ~= nil
    local keep = {}
    for _, f in ipairs(d.fields or {}) do
      local label = string.lower(f.field or pathText(f.path or {}))
      local cols = ""
      for _, c in ipairs(f.columns or {}) do cols = cols .. " " .. string.lower(c.name) end
      if hitsSection or label:find(q, 1, true) or cols:find(q, 1, true) then keep[#keep + 1] = f end
    end
    local rows = nil
    if d.rows then
      for _, r in ipairs(d.rows) do
        local vals = {}
        for _, v in ipairs(r.values) do
          if hitsSection or string.lower(v.field):find(q, 1, true) or string.lower(r.row):find(q, 1, true) then vals[#vals + 1] = v end
        end
        if #vals > 0 then rows = rows or {}; rows[#rows + 1] = {row = r.row, values = vals} end
      end
    end
    if #keep > 0 or rows then
      res[#res + 1] = {name = d.name, kind = d.kind, group = d.group, count = d.count, fields = keep, rows = rows}
      limit = limit - #keep
      if limit <= 0 then break end
    end
  end
  return res
end

-- clean up edits that come from the UI: drop unknown kinds, rebuild the ids
function M.normalizeEdits(edits)
  local out = {}
  if type(edits) ~= "table" then return out end
  for _, e in pairs(edits) do
    if type(e) == "table" then
      local id = M.idOf(e)
      if id then
        local clean = {kind = e.kind}
        if e.kind == "value" then clean.path, clean.value = e.path, e.value
        elseif e.kind == "column" then clean.path, clean.column, clean.scale = e.path, tonumber(e.column), e.scale
        elseif e.kind == "rows" then clean.section, clean.field, clean.scale, clean.value = e.section, e.field, e.scale, e.value
        elseif e.kind == "row" then clean.section, clean.row, clean.field, clean.value = e.section, tostring(e.row), e.field, e.value end
        out[id] = clean
      end
    end
  end
  return out
end

return M
