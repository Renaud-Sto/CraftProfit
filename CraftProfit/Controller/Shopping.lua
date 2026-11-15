-- Controller: the shopping list (Shopping.lua, saved per character in
-- CraftProfitCharDB.shopping) and what its window shows.
local _, ns = ...
local Util, Shopping, Prices, Vendor = ns.Util, ns.Shopping, ns.Prices, ns.Vendor
local L = ns.L

local Controller = ns.Controller

-- Adds a recipe's reagents x crafts and says so in the chat. Returns true when anything
-- was added.
function Controller.addToShopping(recipe, crafts)
    if type(recipe) ~= "table" then return false end
    crafts = Util.count(crafts) or 1
    local added = Shopping.addRecipe(CraftProfitCharDB.shopping, recipe, crafts)
    if added == 0 then
        Controller.say(L.SHOP_FULL)
        return false
    end
    Controller.say(string.format(L.SHOP_ADDED, crafts, Controller.recipeName(recipe)))
    Controller.refresh()
    return true
end

function Controller.shoppingRemove(itemID)
    if Shopping.remove(CraftProfitCharDB.shopping, itemID) then Controller.refresh() end
end

function Controller.shoppingClear()
    Shopping.clear(CraftProfitCharDB.shopping)
    Controller.refresh()
end

function Controller.saveShoppingPosition(x, y)
    if Util.isFinite(x) and Util.isFinite(y) then
        CraftProfitDB.settings.shoppingWindow = { x = x, y = y }
    end
end

-- What the shopping window shows: one row per item with its texts, the total still to pay
-- (amber and partial when a missing item has no price), and the panel title with the count.
function Controller.shoppingData()
    local now = time()
    local market = Controller.market()
    local rows, total, unpriced = Shopping.rows(CraftProfitCharDB.shopping, {
        ownedOf = Controller.bagCount,
        priceOf = function(id) return (Prices.get(market, id, now)) end,
        vendorOf = function(id) return (Vendor.get(CraftProfitDB.vendor, id, now)) end,
    })
    local fmt = Controller.fmt
    for _, row in ipairs(rows) do
        local name = Controller.itemName(row.itemID) or ("#" .. row.itemID)
        if row.source == "vendor" and not row.done then name = name .. " |cff808080(" .. L.SOURCE_VENDOR .. ")|r" end
        row.nameText = name
        row.haveText = tostring(row.have)
        row.needText = tostring(row.need)
        if row.done then
            row.costText = L.SHOP_DONE
        elseif row.cost then
            row.costText = fmt(row.cost)
        else
            row.costText = L.UNKNOWN
        end
    end
    local totalText
    if total then
        totalText = string.format(L.SHOP_TOTAL, fmt(total))
    else
        local known = 0
        for _, row in ipairs(rows) do known = known + (row.cost or 0) end
        totalText = string.format(L.SHOP_TOTAL_PARTIAL, fmt(known), #unpriced)
    end
    return {
        rows = rows,
        totalText = totalText,
        incomplete = total == nil,
        title = string.format(L.SHOP_PANEL, #rows),
    }
end
