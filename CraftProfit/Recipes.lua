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
    local merged, order = {}, {}
    for _, r in ipairs(list) do
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
    if #order == 0 or #order > Recipes.MAX_REAGENTS then return nil end
    local out = {}
    for i, id in ipairs(order) do out[i] = { itemID = id, qty = merged[id] } end
    return out
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
        difficulty = Skillup.name(raw.difficulty),
        outputItemID = outputItemID,
        outputQty = qty,
        reagents = list,
    }
end
