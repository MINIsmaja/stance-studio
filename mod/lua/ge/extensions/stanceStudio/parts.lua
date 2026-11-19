-- Stance Studio: part lists for the Performance, Wheels and Tuning tabs.
-- Slots come from the vehicle's partsTree, options from the slot's suitablePartNames (the same lists
-- the base parts menu shows, so mod parts are included). Options are ranked best -> worst.

local M = {}

local jbeamIO = require('jbeam/io')
local power = require('ge/extensions/stanceStudio/power')

-- lowercase: the game stores files under screenshots/ in lowercase anyway
local PHOTO_DIR = "/screenshots/stancestudio/rims/"

-- category rules, first match wins (matched against slot id, slot description and chosen part)
local CATEGORIES = {
  {id = "wheels",       title = "Wheels & tires",   words = {"wheel", "tire", "tyre", "hubcap", "rim"}, exclude = {"steering", "steer_", "spare", "wheelie", "wheelbase"}},
  {id = "induction",    title = "Forced induction", words = {"turbo", "supercharger", "charger", "intercooler", "wastegate", "blower", "compressor"}},
  {id = "ecu",          title = "ECU & tune",       words = {"ecu", "chip", "tune", "rev_limit", "revlimit", "speedlimit"}},
  {id = "intake",       title = "Intake & exhaust", words = {"intake", "exhaust", "header", "muffler", "manifold", "airbox", "air_filter", "filter", "throttle", "carb", "injector", "downpipe"}},
  {id = "engine",       title = "Engine",           words = {"engine", "motor", "internals", "longblock", "block", "cam", "nitrous", "n2o", "fuel", "oilpan", "flywheel", "radiator", "cooling", "battery", "elec"}, exclude = {"mount"}},
  {id = "drivetrain",   title = "Transmission & diffs", words = {"transmission", "gearbox", "transfer", "clutch", "converter", "differential", "diff", "driveshaft", "finaldrive", "lsd", "halfshaft", "axle"}},
  {id = "brakes",       title = "Brakes",           words = {"brake", "abs", "caliper", "rotor"}},
  {id = "suspension",   title = "Suspension & steering", words = {"suspension", "coilover", "spring", "shock", "damper", "strut", "swaybar", "sway_bar", "arb", "steering", "hub", "knuckle", "camber", "subframe"}},
  {id = "body",         title = "Body & interior",  words = {"body", "bumper", "fender", "hood", "door", "trunk", "tailgate", "spoiler", "wing", "mirror", "skirt", "light", "grille", "roof", "glass", "window", "interior", "seat", "dash", "bed", "cage", "bar", "plate", "skin", "livery", "trim", "frame", "chassis"}},
}

-- MARK: translation helpers (same approach as core_vehicle_partmgmt)

local function tr(name, prefix)
  if not name then return nil end
  if type(name) == "table" and name.txt and type(name.ctx) == "table" then
    local ctx = {}
    for k, v in pairs(name.ctx) do
      if type(v) == "table" and v.txt then ctx[k] = tr(v, prefix) else ctx[k] = _tr(v) end
    end
    return core_locales.contextTranslate(name.txt, ctx)
  elseif type(name) == "table" then
    return nil
  end
  return core_locales.translateWithPrefixFallback(name, prefix or "ui.vehicleconfig.information.name.")
end

local function getVeh()
  local veh = getPlayerVehicle(0)
  if not veh then return nil end
  local data = core_vehicle_manager.getVehicleData(veh:getID())
  if not data then return nil end
  return veh, data, veh:getID()
end

local function safeGetPart(ioCtx, partName)
  if not partName or partName == "" then return nil end
  local ok, part = pcall(jbeamIO.getPart, ioCtx, partName)
  if ok then return part end
  return nil
end

local function lower(s) return string.lower(tostring(s or "")) end

local function matchesAny(text, words)
  for _, w in ipairs(words) do
    if text:find(w, 1, true) then return true end
  end
  return false
end

local function categorize(slotId, desc, chosen)
  local text = lower(slotId) .. " " .. lower(desc) .. " " .. lower(chosen)
  local slotText = lower(slotId) .. " " .. lower(desc)
  for _, cat in ipairs(CATEGORIES) do
    if matchesAny(slotText, cat.words) and not (cat.exclude and matchesAny(slotText, cat.exclude)) then
      return cat.id
    end
  end
  for _, cat in ipairs(CATEGORIES) do
    if matchesAny(text, cat.words) and not (cat.exclude and matchesAny(text, cat.exclude)) then
      return cat.id
    end
  end
  return "other"
end

-- MARK: scoring (best -> worst)

local function numericRows(tbl)
  local rows = {}
  if type(tbl) ~= "table" then return rows end
  for _, row in pairs(tbl) do
    if type(row) == "table" and type(row[1]) == "number" and type(row[2]) == "number" then
      rows[#rows + 1] = row
    end
  end
  return rows
end

local function peakHp(part)
  local me = part and part.mainEngine
  if type(me) ~= "table" then return nil end
  local best = nil
  for _, row in ipairs(numericRows(me.torque)) do
    local hp = row[1] * row[2] / 7121 -- rpm * Nm -> metric hp
    if not best or hp > best then best = hp end
  end
  if best then
    best = best * (tonumber(me.torqueModMult) or 1)
  end
  return best
end

local function turboPsi(part)
  local t = part and part.turbocharger
  if type(t) ~= "table" then return nil end
  local best = nil
  for _, row in ipairs(numericRows(t.pressurePSI)) do
    if not best or row[2] > best then best = row[2] end
  end
  local wg = tonumber(t.wastegateStart)
  if wg and (not best or wg > best) then best = wg end
  return best
end

local function superchargerPsi(part)
  local s = part and part.supercharger
  if type(s) ~= "table" then return nil end
  local per1k = tonumber(s.pressurePSIPer1kRPM)
  local ratio = tonumber(s.gearRatio) or 1
  if per1k then return per1k * ratio * 6 end -- boost estimate at 6000 engine rpm
  return tonumber(s.maxPressurePSI) or tonumber(s.pressureRatePSI)
end

local function formatPrice(v)
  local s = tostring(math.floor(v + 0.5))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  if out:sub(1, 1) == "," then out = out:sub(2) end
  return "$" .. out
end

-- returns score, badge text, kind
local function scorePart(part)
  if not part then return -1, nil, "none" end
  local price = part.information and tonumber(part.information.value) or nil
  local hp = peakHp(part)
  if hp then return 1e6 + hp, string.format("≈%d hp", math.floor(hp + 0.5)), "power" end
  local psi = turboPsi(part) or superchargerPsi(part)
  if psi then return 1e6 + psi, string.format("≈%d psi", math.floor(psi + 0.5)), "boost" end
  if price then return price, formatPrice(price), "price" end
  return 0, nil, "none"
end

-- MARK: wheel size parsing

local function parseWheelSize(text)
  local d, w = tostring(text or ""):match("(%d%d)%s*[xX]%s*(%d+%.?%d*)")
  return tonumber(d), tonumber(w)
end

local function photoPath(partName)
  return PHOTO_DIR .. string.lower((tostring(partName):gsub("[^%w_%-%.]", "_"))) .. ".png"
end
M.photoPath = photoPath

-- marker for rims that can't be photographed (the shot came out empty), so they aren't retried
local function noPhotoPath(partName)
  return (photoPath(partName):gsub("%.png$", ".none"))
end
M.noPhotoPath = noPhotoPath

-- front part names a rear wheel part may share its rim with (same mesh, other axle)
local TWINS = {{"_R$", "_F"}, {"_r$", "_f"}, {"_R_", "_F_"}, {"_rear", "_front"}, {"_Rear", "_Front"}}
local function photoTwins(partName)
  local list = {}
  for _, pat in ipairs(TWINS) do
    local n, count = tostring(partName):gsub(pat[1], pat[2])
    if count > 0 then list[#list + 1] = n end
  end
  return list
end
M.photoTwins = photoTwins

local function photoFor(partName)
  local p = photoPath(partName)
  if FS:fileExists(p) then return p end
  for _, twin in ipairs(photoTwins(partName)) do
    p = photoPath(twin)
    if FS:fileExists(p) then return p end
  end
  return nil
end
M.photoFor = photoFor
M.PHOTO_DIR = PHOTO_DIR

-- MARK: tree walking

local function walk(node, parentPartName, fn, depth)
  depth = depth or 0
  if type(node) ~= "table" or depth > 40 then return end
  for slotId, child in pairs(node.children or {}) do
    fn(child, slotId, parentPartName, depth)
    walk(child, child.chosenPartName, fn, depth + 1)
  end
end

local function findNode(tree, path)
  if tree.path == path then return tree end
  for _, child in pairs(tree.children or {}) do
    local found = findNode(child, path)
    if found then return found end
  end
  return nil
end

local function slotDescription(available, parentPartName, slotId)
  local parent = parentPartName and available[parentPartName]
  local info = parent and parent.slotInfoUi and parent.slotInfoUi[slotId]
  local d = info and info.description
  if d then
    local t = tr(d, "ui.vehicleconfig.slot.description.")
    if t and t ~= "" then return t end
  end
  return slotId
end

local function partInfo(available, ioCtx, partName, withScore)
  local a = available[partName] or {}
  local res = {
    name = partName,
    title = tr(a.description) or partName,
    mod = a.modName,
  }
  if res.title == "" then res.title = partName end
  if withScore then
    local part = safeGetPart(ioCtx, partName)
    res.score, res.badge, res.kind = scorePart(part)
    res.price = part and part.information and tonumber(part.information.value) or nil
  end
  return res
end

local function sortOptions(options)
  table.sort(options, function(a, b)
    if a.name == "" then return false end
    if b.name == "" then return true end
    if (a.score or 0) ~= (b.score or 0) then return (a.score or 0) > (b.score or 0) end
    return tostring(a.title) < tostring(b.title)
  end)
end

-- MARK: horsepower estimate
-- The car's parts tree is rebuilt with the candidate part in its slot, then the engine sections are
-- merged with the game's own rules (power.mergeTree) and run through its engine math. Rebuilding the
-- whole set (instead of adding / removing single sections) keeps partial sections right, like an
-- ECU that only changes the wastegate of the intake's turbo.

-- slot ids (the keys of a partsTree node's children) and default parts, in the part's own order
local function slotRows(part)
  local res = {}
  local rows = type(part) == "table" and (part.slots2 or part.slots) or nil
  if type(rows) ~= "table" or type(rows[1]) ~= "table" then return res end
  local nameCol, typeCol, defCol
  for i, h in ipairs(rows[1]) do
    if h == "name" then nameCol = i elseif h == "type" then typeCol = i elseif h == "default" then defCol = i end
  end
  local idCol = nameCol or typeCol
  if not idCol then return res end
  for i = 2, #rows do
    local r = rows[i]
    if type(r) == "table" and type(r[idCol]) == "string" then
      res[#res + 1] = {id = r[idCol], default = defCol and r[defCol] or nil}
    end
  end
  return res
end

-- decoded parts for one estimate pass (getPart decodes the whole part on every call)
local function makeBuilder(ioCtx)
  local cache = {}
  local b = {}
  function b.part(name)
    if not name or name == "" then return nil end
    local p = cache[name]
    if p == nil then
      p = safeGetPart(ioCtx, name) or false
      cache[name] = p
    end
    return p or nil
  end
  -- sections that matter for power, plus the turbo / supercharger section names engines point at
  function b.note(part, ctx)
    ctx.parts[#ctx.parts + 1] = part
    local me = part.mainEngine
    if type(me) == "table" then
      if type(me.turbocharger) == "string" then ctx.names[me.turbocharger] = true end
      if type(me.supercharger) == "string" then ctx.names[me.supercharger] = true end
    end
  end
  -- a part as it gets installed: its own sub slots keep what the old part had there (same slot id),
  -- like setPart does, the rest get their defaults
  function b.fresh(name, oldNode, ctx, depth)
    local part = b.part(name)
    if not part then return nil end
    b.note(part, ctx)
    local node = {part = part, children = {}}
    if depth > 10 then return node end
    local oldKids = oldNode and oldNode.children or {}
    for _, s in ipairs(slotRows(part)) do
      local old = oldKids[s.id]
      local c
      if old and old.chosenPartName and old.chosenPartName ~= "" then
        c = b.installed(old, ctx, nil, depth + 1)
      elseif not old and type(s.default) == "string" and s.default ~= "" then
        c = b.fresh(s.default, nil, ctx, depth + 1)
      end
      if c then node.children[#node.children + 1] = c end
    end
    return node
  end
  -- the installed subtree of a partsTree node, with override = {path, part} swapped in
  function b.installed(treeNode, ctx, override, depth)
    if override and treeNode.path == override.path then
      if not override.part or override.part == "" then return nil end
      return b.fresh(override.part, treeNode, ctx, depth)
    end
    if not treeNode.chosenPartName or treeNode.chosenPartName == "" then return nil end
    -- a part that can't be read still gets its sub parts walked
    local part = b.part(treeNode.chosenPartName)
    if part then b.note(part, ctx) end
    local node = {part = part, children = {}}
    if depth > 10 then return node end
    local kids = treeNode.children or {}
    local used = {}
    local order = {}
    for _, s in ipairs(slotRows(part)) do
      if kids[s.id] and not used[s.id] then used[s.id] = true; order[#order + 1] = s.id end
    end
    local rest = {}
    for id in pairs(kids) do if not used[id] then rest[#rest + 1] = id end end
    table.sort(rest)
    for _, id in ipairs(rest) do order[#order + 1] = id end
    for _, id in ipairs(order) do
      local c = b.installed(kids[id], ctx, override, depth + 1)
      if c then node.children[#node.children + 1] = c end
    end
    return node
  end
  return b
end

local function variableDefaults(parts)
  local res = {}
  for _, part in ipairs(parts) do
    local rows = part.variables
    if type(rows) == "table" then
      for _, r in ipairs(rows) do
        if type(r) == "table" and type(r[1]) == "string" and r[1]:sub(1, 1) == "$" and type(r[5]) == "number" then
          res[r[1]] = r[5]
        end
      end
    end
  end
  return res
end

-- the car's engine as it is now, from the merged vehicle data
local function engineContext(vehData)
  local vdata = vehData.vdata
  if not vdata then return nil end
  local engineName = "mainEngine"
  for _, dev in pairs(vdata.powertrain or {}) do
    if type(dev) == "table" and dev.type == "combustionEngine" and type(dev.name) == "string" then
      engineName = dev.name
      if dev.name == "mainEngine" then break end
    end
  end
  local me = vdata[engineName]
  if type(me) ~= "table" or type(me.torque) ~= "table" then return nil end
  local tname = type(me.turbocharger) == "string" and me.turbocharger or "turbocharger"
  local sname = type(me.supercharger) == "string" and me.supercharger or "supercharger"
  local current = {
    engine = me,
    turbo = type(vdata[tname]) == "table" and vdata[tname] or nil,
    sc = type(vdata[sname]) == "table" and vdata[sname] or nil,
  }
  local vars = vdata.variables or {}
  local values = vehData.config.vars or {}
  local function varValue(name)
    if values[name] ~= nil then return tonumber(values[name]) end
    local v = vars[name] or vars[name:sub(2)]
    if type(v) == "table" then return tonumber(v.val) or tonumber(v.default) end
    return nil
  end
  return {current = current, varValue = varValue, engineName = engineName}
end

local function makeResolver(ctx, extraDefaults)
  return function(s)
    if s:sub(1, 2) == "$=" then return nil end
    return ctx.varValue(s) or extraDefaults[s]
  end
end

-- peak hp of the whole car with override = {path, part} installed (nil = as it is now)
local function carHpWith(ctx, builder, tree, override)
  local bctx = {parts = {}, names = {mainEngine = true, turbocharger = true, supercharger = true}}
  if ctx.engineName then bctx.names[ctx.engineName] = true end
  local root = builder.installed(tree, bctx, override, 0)
  if not root then return nil end
  local resolve = makeResolver(ctx, variableDefaults(bctx.parts))
  local merged = power.mergeTree(root, bctx.names, resolve)
  local ok, hp = pcall(power.estimateMerged, merged, ctx.engineName, resolve)
  return ok and hp or nil
end

-- for every option of a slot: estimated peak hp of the whole car with that part installed
local function powerForSlot(ctx, builder, tree, node, optionNames)
  local baseHp = carHpWith(ctx, builder, tree, nil)
  if not baseHp then return nil end
  local res = {}
  for _, pn in ipairs(optionNames) do
    if pn == node.chosenPartName then
      res[pn] = baseHp
    else
      res[pn] = carHpWith(ctx, builder, tree, {path = node.path, part = pn})
    end
  end
  return res, baseHp
end

-- MARK: public: performance / all parts

-- returns {categories = {{id, title, slots = {{path, id, title, chosen, options = {...}}}}}}
-- Options are ranked best -> worst. Parts that change engine power get "+N hp" (estimated gain
-- over what is on the car now); everything else is ranked by its part value, which is not shown.
function M.getCategories(onlyCategory)
  local veh, vehData = getVeh()
  if not veh then return {categories = {}} end
  local tree = vehData.config.partsTree
  local ioCtx = vehData.ioCtx
  local available = jbeamIO.getAvailableParts(ioCtx) or {}
  local ctx = onlyCategory and engineContext(vehData) or nil
  local builder = ctx and makeBuilder(ioCtx) or nil
  local byCat = {}
  local carHp = nil
  walk(tree, tree.chosenPartName, function(node, slotId, parentPartName)
    local options = node.suitablePartNames
    if type(options) ~= "table" or #options == 0 then return end
    local desc = slotDescription(available, parentPartName, slotId)
    local cat = categorize(slotId, desc, node.chosenPartName)
    if cat == "wheels" then return end -- the Wheels tab handles these
    if onlyCategory and cat ~= onlyCategory then return end
    local scored = onlyCategory ~= nil
    local list = {}
    for _, pn in ipairs(options) do
      local o = partInfo(available, ioCtx, pn, false)
      if scored then
        local part = safeGetPart(ioCtx, pn)
        o.value = part and part.information and tonumber(part.information.value) or 0
      end
      list[#list + 1] = o
    end
    list[#list + 1] = {name = "", title = "Empty", value = -1}

    if scored then
      local names = {}
      for _, o in ipairs(list) do names[#names + 1] = o.name end
      local hpByName, baseHp = nil, nil
      if ctx then
        local ok, a, b = pcall(powerForSlot, ctx, builder, tree, node, names)
        if ok then hpByName, baseHp = a, b else log('W', 'stanceStudio', 'power estimate failed: ' .. tostring(a)) end
      end
      carHp = carHp or baseHp
      local affectsPower = false
      if hpByName and baseHp then
        for _, o in ipairs(list) do
          local hp = hpByName[o.name]
          if hp and math.abs(hp - baseHp) >= 0.5 then affectsPower = true end
        end
      end
      for _, o in ipairs(list) do
        local hp = hpByName and hpByName[o.name]
        if affectsPower and hp then
          local gain = hp - baseHp
          o.score = 1e7 + hp
          local rounded = math.floor(math.abs(gain) + 0.5)
          if rounded >= 1 and o.name ~= node.chosenPartName and o.name ~= "" then
            o.badge = string.format("%s%d hp", gain > 0 and "+" or "−", rounded)
            o.kind = gain > 0 and "power" or "loss"
          end
        else
          o.score = o.value or 0
        end
        o.value = nil
      end
      sortOptions(list)
    end
    byCat[cat] = byCat[cat] or {}
    table.insert(byCat[cat], {
      path = node.path,
      id = slotId,
      title = desc,
      chosen = node.chosenPartName or "",
      options = list,
    })
  end)
  local res = {categories = {}, carHp = carHp}
  local order = {}
  for _, c in ipairs(CATEGORIES) do order[#order + 1] = {id = c.id, title = c.title} end
  order[#order + 1] = {id = "other", title = "Other"}
  for _, c in ipairs(order) do
    if c.id ~= "wheels" and byCat[c.id] then
      table.sort(byCat[c.id], function(a, b) return a.title < b.title end)
      res.categories[#res.categories + 1] = {id = c.id, title = c.title, count = #byCat[c.id], slots = byCat[c.id]}
    end
  end
  return res
end

function M.setPart(slotPath, partName)
  local veh, vehData = getVeh()
  if not veh then return false end
  local tree = deepcopy(vehData.config.partsTree)
  local node = findNode(tree, slotPath)
  if not node then
    log('W', 'stanceStudio', 'slot not found: ' .. tostring(slotPath))
    return false
  end
  node.chosenPartName = partName or ""
  core_vehicle_partmgmt.setPartsTreeConfig(tree, true)
  return true
end

-- MARK: public: wheels

-- slots with "wheel" in the name that aren't road wheels
local WHEEL_EXCLUDE = {"steering", "steer_", "spare", "wheelie", "hubcap", "tire", "tyre", "wheelbase", "wheeldata",
  "wheel_data", "flywheel", "fifthwheel", "fifth_wheel", "fifth wheel", "wheelskirt", "wheel_skirt", "wheel skirt",
  "wheelarch", "wheel_arch", "wheel arch", "wheelwell", "wheel_well", "wheel well", "wheelchair", "handwheel"}

-- wheels carry their tire slot; hubs, axles and trims don't
local function hasTireChild(node)
  for childId in pairs(node.children or {}) do
    local c = lower(childId)
    if c:find("tire", 1, true) or c:find("tyre", 1, true) then return true end
  end
  return false
end

-- how sure we are that a slot holds the wheels (rims) themselves
local function wheelSlotScore(node, id, text)
  local score = 0
  if hasTireChild(node) then score = score + 4 end
  if id:match("^wheels?_") then score = score + 2 end            -- the game's wheel_F_5 / wheel_R_4 slots
  if text:find("hub", 1, true) then score = score - 3 end        -- "Front Wheel Hubs" hold the wheels one level down
  return score
end

local function wheelSlots(vehData, available)
  local tree = vehData.config.partsTree
  local slots = {}
  walk(tree, tree.chosenPartName, function(node, slotId, parentPartName, depth)
    local options = node.suitablePartNames
    if type(options) ~= "table" or #options == 0 then return end
    local id = lower(slotId)
    local desc = slotDescription(available, parentPartName, slotId)
    local text = id .. " " .. lower(desc)
    if not (text:find("wheel", 1, true) or text:find("%f[%a]rims?%f[%A]")) then return end
    if matchesAny(text, WHEEL_EXCLUDE) then return end
    local axle = nil
    if id:find("_f[_%d]", 1) or id:match("_f$") or text:find("front", 1, true) then axle = "F"
    elseif id:find("_r[_%d]", 1) or id:match("_r$") or text:find("rear", 1, true) then axle = "R" end
    slots[#slots + 1] = {node = node, slotId = slotId, desc = desc, axle = axle, depth = depth,
      score = wheelSlotScore(node, id, text)}
  end)
  -- per axle: the most wheel-like slot; on a tie the shallowest (a wheel's own trim slots sit below it)
  local best = {}
  for _, s in ipairs(slots) do
    local key = s.axle or "B"
    local b = best[key]
    if not b or s.score > b.score or (s.score == b.score and s.depth < b.depth) then best[key] = s end
  end
  -- a slot with no axle in its name only counts as "all wheels" when it beats the front / rear ones
  if best.B and (best.F or best.R) then
    local fr = math.max(best.F and best.F.score or -math.huge, best.R and best.R.score or -math.huge)
    if best.B.score <= fr then best.B = nil end
  end
  return best
end

local function wheelOption(available, ioCtx, partName)
  local info = partInfo(available, ioCtx, partName, false)
  local d, w = parseWheelSize(info.title)
  if not d then d, w = parseWheelSize(partName) end
  info.diameter, info.width = d, w
  info.photo = photoFor(partName)
  if not info.photo and FS:fileExists(noPhotoPath(partName)) then info.noPhoto = true end
  return info
end

function M.getWheels()
  local veh, vehData = getVeh()
  if not veh then return {axles = {}} end
  local ioCtx = vehData.ioCtx
  local available = jbeamIO.getAvailableParts(ioCtx) or {}
  local slots = wheelSlots(vehData, available)
  local res = {axles = {}}
  for _, key in ipairs({"F", "R", "B"}) do
    local s = slots[key]
    if s then
      local opts = {}
      for _, pn in ipairs(s.node.suitablePartNames) do
        opts[#opts + 1] = wheelOption(available, ioCtx, pn)
      end
      table.sort(opts, function(a, b)
        if (a.diameter or 0) ~= (b.diameter or 0) then return (a.diameter or 0) > (b.diameter or 0) end
        return tostring(a.title) < tostring(b.title)
      end)
      -- tire slot under the chosen wheel
      local tires = nil
      for childId, child in pairs(s.node.children or {}) do
        local cid = lower(childId)
        if (cid:find("tire", 1, true) or cid:find("tyre", 1, true)) and type(child.suitablePartNames) == "table" then
          local topts = {}
          for _, pn in ipairs(child.suitablePartNames) do
            topts[#topts + 1] = partInfo(available, ioCtx, pn, false)
          end
          table.sort(topts, function(a, b) return tostring(a.title) < tostring(b.title) end)
          tires = {path = child.path, chosen = child.chosenPartName or "", options = topts}
          break
        end
      end
      res.axles[#res.axles + 1] = {
        axle = key,
        path = s.node.path,
        title = s.desc,
        chosen = s.node.chosenPartName or "",
        options = opts,
        tires = tires,
      }
    end
  end
  return res
end

-- rear part that matches a front part (same wheel, other axle)
local function matchingRear(frontName, frontTitle, rearOptions, available)
  local candidates = {}
  for _, pat in ipairs({{"_F$", "_R"}, {"_f$", "_r"}, {"_F_", "_R_"}, {"_front", "_rear"}, {"_F", "_R"}}) do
    local n = frontName:gsub(pat[1], pat[2])
    if n ~= frontName then candidates[#candidates + 1] = n end
  end
  local set = {}
  for _, pn in ipairs(rearOptions) do set[pn] = true end
  for _, c in ipairs(candidates) do
    if set[c] then return c end
  end
  -- same title apart from Front/Rear
  local want = lower(frontTitle):gsub("front", ""):gsub("%s+", " ")
  for _, pn in ipairs(rearOptions) do
    local t = lower(tr((available[pn] or {}).description) or pn):gsub("rear", ""):gsub("%s+", " ")
    if t == want then return pn end
  end
  return nil
end

-- axle: "F", "R", "B" (single slot) or "both"
function M.setWheel(axle, partName)
  local veh, vehData = getVeh()
  if not veh then return {ok = false} end
  local available = jbeamIO.getAvailableParts(vehData.ioCtx) or {}
  local slots = wheelSlots(vehData, available)
  local tree = deepcopy(vehData.config.partsTree)
  local result = {ok = true}
  local function setSlot(slot, pn)
    local node = findNode(tree, slot.node.path)
    if node then node.chosenPartName = pn end
  end
  if axle == "both" then
    local front, rear = slots.F or slots.B, slots.R
    if front then setSlot(front, partName) end
    if rear and front ~= rear then
      local title = tr((available[partName] or {}).description) or partName
      local rearName = matchingRear(partName, title, rear.node.suitablePartNames or {}, available)
      if rearName then
        setSlot(rear, rearName)
      else
        result.rearMissing = true
      end
    end
  elseif slots[axle] then
    setSlot(slots[axle], partName)
  else
    return {ok = false}
  end
  core_vehicle_partmgmt.setPartsTreeConfig(tree, true)
  return result
end

-- MARK: public: tuning (the car's own jbeam variables)

function M.getTuning()
  local veh, vehData = getVeh()
  if not veh then return {variables = {}} end
  local vars = vehData.vdata.variables or {}
  local values = vehData.config.vars or {}
  local list = {}
  for name, v in pairs(vars) do
    if type(v) == "table" and v.type == "range" then
      list[#list + 1] = {
        name = name,
        title = tr(v.title, "ui.vehicleconfig.variables.title.") or name,
        description = tr(v.description, "ui.vehicleconfig.variables.description."),
        category = tr(v.category, "ui.vehicleconfig.variables.category.") or "Other",
        subCategory = v.subCategory and tr(v.subCategory, "ui.vehicleconfig.variables.subCategory.") or nil,
        unit = v.unit,
        min = v.min, max = v.max,
        minDis = v.minDis, maxDis = v.maxDis, stepDis = v.stepDis,
        default = v.default,
        val = values[name] or v.val or v.default,
      }
    end
  end
  table.sort(list, function(a, b)
    if a.category ~= b.category then return tostring(a.category) < tostring(b.category) end
    if (a.subCategory or "") ~= (b.subCategory or "") then return tostring(a.subCategory or "") < tostring(b.subCategory or "") end
    return tostring(a.title) < tostring(b.title)
  end)
  return {variables = list}
end

function M.setVars(vars)
  if type(vars) ~= "table" then return end
  local veh, vehData = getVeh()
  if not veh then return end
  local merged = deepcopy(vehData.config.vars or {})
  for k, v in pairs(vars) do merged[k] = tonumber(v) or v end
  core_vehicle_partmgmt.setConfigVars(merged, true)
end

function M.onExtensionLoaded()
  setExtensionUnloadMode(M, "manual")
end

-- exposed for tests
M._categorize = categorize
M._scorePart = scorePart
M._parseWheelSize = parseWheelSize

return M
