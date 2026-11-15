-- The shopping list: materials to gather for crafts the player plans. Pure Lua, no WoW API.
--
-- Saved per character (the bags counted are the character's) as CraftProfitCharDB.shopping
-- = { { itemID, qty }, ... } in the order the items were first added. Adding a recipe adds
-- each reagent x the crafts wanted, merging into an item already listed. A crafted
-- reagent (a bolt of cloth) is listed as it is, never broken down into its own materials.
local _, ns = ...
local Util, Vendor = ns.Util, ns.Vendor

local Shopping = {}
ns.Shopping = Shopping

-- Bounds for a save edited by hand or corrupted: 100 different items, a million of one.
Shopping.MAX_ITEMS = 100
Shopping.MAX_QTY = 1000000

-- A clean list from anything: valid rows kept in order, duplicates merged, quantities
-- bounded. Always a new table of new rows.
function Shopping.sanitize(list)
    local clean, index = {}, {}
    if type(list) ~= "table" then return clean end
    for _, row in ipairs(list) do
        local id = type(row) == "table" and Util.id(row.itemID) or nil
        local qty = type(row) == "table" and Util.count(row.qty) or nil
        if id and qty then
            local at = index[id]
            if at then
                clean[at].qty = math.min(clean[at].qty + qty, Shopping.MAX_QTY)
            elseif #clean < Shopping.MAX_ITEMS then
                clean[#clean + 1] = { itemID = id, qty = math.min(qty, Shopping.MAX_QTY) }
                index[id] = #clean
            end
        end
    end
    return clean
end

local function find(list, itemID)
    for i, row in ipairs(list) do
        if row.itemID == itemID then return i end
    end
    return nil
end

-- Adds qty of an item (merged with the row already there). Returns true, or false when the
-- input is invalid or the list is full of other items.
function Shopping.add(list, itemID, qty)
    itemID, qty = Util.id(itemID), Util.count(qty)
    if type(list) ~= "table" or not itemID or not qty then return false end
    local i = find(list, itemID)
    if i then
        list[i].qty = math.min(list[i].qty + qty, Shopping.MAX_QTY)
        return true
    end
    if #list >= Shopping.MAX_ITEMS then return false end
    list[#list + 1] = { itemID = itemID, qty = math.min(qty, Shopping.MAX_QTY) }
    return true
end

-- Adds every reagent of a recipe x crafts (a whole number, 1 at least). Returns how many
-- reagents were added (0 when nothing could be).
function Shopping.addRecipe(list, recipe, crafts)
    crafts = Util.count(crafts) or 1
    if type(recipe) ~= "table" or type(recipe.reagents) ~= "table" then return 0 end
    local added = 0
    for _, r in ipairs(recipe.reagents) do
        local qty = type(r) == "table" and Util.count(r.qty) or nil
        if qty and Shopping.add(list, r.itemID, qty * crafts) then added = added + 1 end
    end
    return added
end

function Shopping.remove(list, itemID)
    local i = type(list) == "table" and find(list, itemID) or nil
    if not i then return false end
    table.remove(list, i)
    return true
end

function Shopping.clear(list)
    if type(list) ~= "table" then return end
    for i = #list, 1, -1 do list[i] = nil end
end

-- The rows to show and what is left to pay. ctx: ownedOf(itemID) -> count in the bags or
-- nil; priceOf(itemID) -> AH unit price or nil; vendorOf(itemID) -> vendor unit or nil
-- (both optional). Each row: { itemID, need, have, buy, unit, source, cost, done }:
-- have = what the bags hold (may exceed need), buy = what is missing, cost = buy x the
-- cheaper of the AH and vendor price (0 when nothing is missing, nil when a missing item
-- has no price). Returns rows, total (nil when any missing item has no price), and the
-- ids of those unpriced items.
function Shopping.rows(list, ctx)
    ctx = ctx or {}
    local rows, total, unpriced = {}, 0, {}
    for _, entry in ipairs(type(list) == "table" and list or {}) do
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
