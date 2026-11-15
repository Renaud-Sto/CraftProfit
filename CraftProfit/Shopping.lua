-- Shopping lists: the crafts each character plans and the materials they need. Pure Lua,
-- no WoW API.
--
-- Saved account wide, one list per character, so another character (one standing at the
-- auction house) can open it, buy and mail the materials:
-- CraftProfitDB.shopping = { [key] = { name, realm, updated, recipes, bags } }, key
-- "Name-Realm"; recipes = { { recipe = normalised recipe, crafts = n }, ... } in the order
-- added (the same recipe twice adds up its crafts); bags = { [itemID] = count }, what the
-- owner carried of its list's materials when last seen. The materials are always derived
-- from the recipes: removing a recipe added by mistake takes its materials away. A crafted
-- material (a bolt of cloth) is listed as it is, never broken down.
local _, ns = ...
local Util, Vendor, Recipes = ns.Util, ns.Vendor, ns.Recipes

local Shopping = {}
ns.Shopping = Shopping

Shopping.MAX_LISTS = 50
Shopping.MAX_RECIPES = 30
Shopping.MAX_CRAFTS = 9999

local function cleanRecipes(raw)
    local out, index = {}, {}
    for _, e in ipairs(type(raw) == "table" and raw or {}) do
        local recipe = type(e) == "table" and Recipes.normalize(e.recipe) or nil
        local crafts = type(e) == "table" and Util.count(e.crafts) or nil
        if recipe and crafts then
            local at = index[recipe.recipeID]
            if at then
                out[at].crafts = math.min(out[at].crafts + crafts, Shopping.MAX_CRAFTS)
            elseif #out < Shopping.MAX_RECIPES then
                out[#out + 1] = { recipe = recipe, crafts = math.min(crafts, Shopping.MAX_CRAFTS) }
                index[recipe.recipeID] = #out
            end
        end
    end
    return out
end

local function cleanBags(raw)
    local out = {}
    for id, n in pairs(type(raw) == "table" and raw or {}) do
        if Util.id(id) == id and Util.count(n) then out[id] = Util.count(n) end
    end
    return out
end

-- A clean account table: valid lists only, each rebuilt. Returns a new table.
function Shopping.sanitize(db)
    local out, n = {}, 0
    for key, list in pairs(type(db) == "table" and db or {}) do
        if type(key) == "string" and key ~= "" and type(list) == "table" and n < Shopping.MAX_LISTS then
            n = n + 1
            out[key] = {
                name = type(list.name) == "string" and list.name ~= "" and list.name or key,
                realm = type(list.realm) == "string" and list.realm or "",
                updated = Util.isCopper(list.updated) and list.updated or 0,
                recipes = cleanRecipes(list.recipes),
                bags = cleanBags(list.bags),
            }
        end
    end
    return out
end

-- The list of `key`, created when missing (name and realm refreshed). nil when the table
-- already holds MAX_LISTS other lists.
function Shopping.list(db, key, name, realm)
    if type(db) ~= "table" or type(key) ~= "string" or key == "" then return nil end
    local list = db[key]
    if not list then
        local n = 0
        for _ in pairs(db) do n = n + 1 end
        if n >= Shopping.MAX_LISTS then return nil end
        list = { name = key, realm = "", updated = 0, recipes = {}, bags = {} }
        db[key] = list
    end
    if type(name) == "string" and name ~= "" then list.name = name end
    if type(realm) == "string" then list.realm = realm end
    return list
end

-- Adds a recipe x crafts (merged with the same recipe already there). Returns the crafts
-- now planned for it, or nil when the recipe is invalid or the list is full.
function Shopping.addRecipe(list, recipe, crafts, now)
    crafts = Util.count(crafts) or 1
    local clean = Recipes.normalize(recipe)
    if type(list) ~= "table" or not clean then return nil end
    if Util.isCopper(now) then list.updated = now end
    for _, e in ipairs(list.recipes) do
        if e.recipe.recipeID == clean.recipeID then
            e.crafts = math.min(e.crafts + crafts, Shopping.MAX_CRAFTS)
            return e.crafts
        end
    end
    if #list.recipes >= Shopping.MAX_RECIPES then return nil end
    list.recipes[#list.recipes + 1] = { recipe = clean, crafts = math.min(crafts, Shopping.MAX_CRAFTS) }
    return list.recipes[#list.recipes].crafts
end

function Shopping.removeRecipe(list, recipeID)
    if type(list) ~= "table" then return false end
    for i, e in ipairs(list.recipes) do
        if e.recipe.recipeID == recipeID then
            table.remove(list.recipes, i)
            return true
        end
    end
    return false
end

function Shopping.clear(list)
    if type(list) ~= "table" then return end
    list.recipes = {}
    list.bags = {}
end

-- The materials of the list: { { itemID, qty }, ... } in the order first met.
function Shopping.items(list)
    local out, index = {}, {}
    for _, e in ipairs(type(list) == "table" and list.recipes or {}) do
        for _, r in ipairs(e.recipe.reagents) do
            local qty = r.qty * e.crafts
            local at = index[r.itemID]
            if at then
                out[at].qty = out[at].qty + qty
            else
                out[#out + 1] = { itemID = r.itemID, qty = qty }
                index[r.itemID] = #out
            end
        end
    end
    return out
end

-- Remembers what the owner carries of its list's materials (countOf(itemID) -> count or
-- nil), so another character sees it. Returns true when anything changed.
function Shopping.snapshotBags(list, countOf)
    if type(list) ~= "table" or type(countOf) ~= "function" then return false end
    local bags, changed = {}, false
    for _, item in ipairs(Shopping.items(list)) do
        local n = Util.count(countOf(item.itemID))
        if n then bags[item.itemID] = n end
        if bags[item.itemID] ~= list.bags[item.itemID] then changed = true end
    end
    for id in pairs(list.bags) do
        if bags[id] == nil then changed = true end
    end
    list.bags = bags
    return changed
end

-- The material rows and what is left to pay. ctx: ownedOf(itemID) -> count held (nil =
-- none), priceOf(itemID) -> AH unit or nil, vendorOf(itemID) -> vendor unit or nil. Each
-- row: { itemID, need, have, buy, unit, source, cost, done }; cost = buy x the cheaper of
-- the AH and vendor price (0 when nothing is missing, nil when a missing item has no
-- price). Returns rows, total (nil when a missing item has no price), unpriced ids.
function Shopping.rows(list, ctx)
    ctx = ctx or {}
    local rows, total, unpriced = {}, 0, {}
    for _, entry in ipairs(Shopping.items(list)) do
        local have = type(ctx.ownedOf) == "function" and Util.count(ctx.ownedOf(entry.itemID)) or 0
        have = have or 0
        local buy = math.max(0, entry.qty - have)
        local ah = type(ctx.priceOf) == "function" and ctx.priceOf(entry.itemID) or nil
        local vendor = type(ctx.vendorOf) == "function" and ctx.vendorOf(entry.itemID) or nil
        local unit, source = Vendor.cheapest(ah, vendor)
        local cost
        if buy == 0 then
            cost = 0
        elseif unit then
            cost = unit * buy
        else
            unpriced[#unpriced + 1] = entry.itemID
        end
        if total and cost then total = total + cost else total = nil end
        rows[#rows + 1] = {
            itemID = entry.itemID, need = entry.qty, have = have, buy = buy,
            unit = unit, source = source, cost = cost, done = buy == 0,
        }
    end
    return rows, total, unpriced
end

-- The keys of the lists worth choosing: `current` first, then every other list that holds
-- a recipe, by name.
function Shopping.owners(db, current)
    local others = {}
    for key, list in pairs(type(db) == "table" and db or {}) do
        if key ~= current and #list.recipes > 0 then others[#others + 1] = key end
    end
    table.sort(others, function(a, b)
        local na, nb = db[a].name, db[b].name
        if na ~= nb then return na < nb end
        return a < b
    end)
    local out = {}
    if current then out[1] = current end
    for _, key in ipairs(others) do out[#out + 1] = key end
    return out
end
