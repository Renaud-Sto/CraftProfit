-- Recipe validation and normalization. Pure Lua, no WoW API.
-- Raw tables come from the game adapter or from SavedVariables; neither is trusted.
local _, ns = ...
local Util = ns.Util
local Skillup = ns.Data.Skillup

local Recipes = {}
ns.Recipes = Recipes

Recipes.MAX_REAGENTS = 12
local MAX_NAME_BYTES = 200
local MAX_YIELD = 1000
-- The most of one reagent a recipe may ask for (after merging duplicates). Real recipes
-- ask for a few dozen at most; the bound keeps a corrupt save from making the cost
-- infinite (12 reagents x 1000 x Util.MAX_COPPER stays finite).
Recipes.MAX_REAGENT_QTY = 1000

-- Average yield. Absent min/max means a single item; present but invalid means
-- the whole recipe is unusable (nil).
local function outputQty(raw)
    if raw.outputQty ~= nil then
        local q = raw.outputQty
        if Util.isFinite(q) and q >= 1 and q <= MAX_YIELD then return q end
        return nil
    end
    if raw.qtyMin == nil and raw.qtyMax == nil then return 1 end
    local lo = raw.qtyMin or raw.qtyMax
    local hi = raw.qtyMax or raw.qtyMin
    if Util.isFinite(lo) and Util.isFinite(hi) and lo >= 1 and hi >= lo and hi <= MAX_YIELD then
        return (lo + hi) / 2
    end
    return nil
end

-- One invalid reagent invalidates the list: dropping it would hide a cost.
local function reagents(list)
    if type(list) ~= "table" then return nil end
    local len = #list
    if len == 0 then return nil end

    -- Verify table has exactly integer keys 1..len (no holes, no extra keys)
    local keyCount = 0
    for k, _ in pairs(list) do
        keyCount = keyCount + 1
        if type(k) ~= "number" or k ~= math.floor(k) or k < 1 or k > len then
            return nil
        end
    end
    if keyCount ~= len then return nil end

    -- Verify no holes: each position 1..len exists
    for i = 1, len do
        if list[i] == nil then return nil end
    end

    local merged, order = {}, {}
    for i = 1, len do
        local r = list[i]
        if type(r) ~= "table" then return nil end
        local id, qty = Util.id(r.itemID), Util.id(r.qty)
        if not id or not qty then return nil end
        if merged[id] then
            merged[id] = merged[id] + qty
        else
            merged[id] = qty
            order[#order + 1] = id
        end
    end
    if #order > Recipes.MAX_REAGENTS then return nil end
    for _, id in ipairs(order) do
        if merged[id] > Recipes.MAX_REAGENT_QTY then return nil end
    end
    local out = {}
    for i, id in ipairs(order) do out[i] = { itemID = id, qty = merged[id] } end
    return out
end

-- A client language code ("enUS", "frFR"), or nil.
local function validLocale(v)
    if type(v) == "string" and v:match("^%a%a%a%a$") then return v end
    return nil
end

function Recipes.normalize(raw)
    if type(raw) ~= "table" then return nil end
    local recipeID, outputItemID = Util.id(raw.recipeID), Util.id(raw.outputItemID)
    if not recipeID or not outputItemID then return nil end
    local qty, list = outputQty(raw), reagents(raw.reagents)
    if not qty or not list then return nil end
    local name = raw.name
    if type(name) ~= "string" or #name > MAX_NAME_BYTES then name = "" end
    return {
        recipeID = recipeID,
        name = name,
        -- The client language the name was read in ("frFR"); absent on older saves.
        locale = validLocale(raw.locale),
        difficulty = Skillup.name(raw.difficulty),
        outputItemID = outputItemID,
        outputQty = qty,
        reagents = list,
    }
end

-- The stored name, or "#<recipeID>" when there is none. No game call.
function Recipes.label(recipe)
    local name = recipe.name
    if type(name) == "string" and name ~= "" then return name end
    return "#" .. tostring(recipe.recipeID)
end

-- The name to show for a stored recipe, in the client's current language. Names are
-- saved when a recipe is pinned or read, so they stay in the old language after the
-- player switches the game's language. `live` gives the current facts (each function
-- returns a plain non-empty string or nil, and must never raise):
--   live.recipeName(recipeID)  the client's own recipe name
--   live.itemName(itemID)      the crafted item's name (nil while not loaded)
--   live.locale                the client language now ("enUS")
-- Order: the client's recipe name; the stored name when it was read in this language
-- (a recipe name can differ from its item's: "Smelt Copper" makes "Copper Bar"); the
-- item name; the stored name; "#id". A live name that differs from the stored one is
-- written back with the language, so the saved fallback follows the language too.
function Recipes.liveName(recipe, live)
    live = live or {}
    local stored = type(recipe.name) == "string" and recipe.name ~= "" and recipe.name or nil
    local locale = validLocale(live.locale)
    local name = live.recipeName and live.recipeName(recipe.recipeID)
    if not name and stored and locale and recipe.locale == locale then return stored end
    if not name and live.itemName and recipe.outputItemID then name = live.itemName(recipe.outputItemID) end
    if type(name) == "string" and name ~= "" and #name <= MAX_NAME_BYTES then
        if name ~= recipe.name or recipe.locale ~= locale then
            recipe.name, recipe.locale = name, locale
        end
        return name
    end
    return Recipes.label(recipe)
end
