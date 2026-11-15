-- Controller: the shopping lists (Shopping.lua, CraftProfitDB.shopping, one per
-- character, account wide) and what the shopping window shows. The window shows one list
-- at a time: the character's own, or another character's chosen with its owner button.
local _, ns = ...
local Util, Shopping, Prices, Vendor = ns.Util, ns.Shopping, ns.Prices, ns.Vendor
local L = ns.L

local Controller = ns.Controller

-- The list shown in the window (a key of CraftProfitDB.shopping); nil = the own list.
local viewKey

-- "Name-Realm" of the logged-in character, its name and realm; nil while unknown.
function Controller.shoppingSelf()
    local name = type(UnitName) == "function" and UnitName("player") or nil
    local realm = type(GetNormalizedRealmName) == "function" and GetNormalizedRealmName() or nil
    if type(realm) ~= "string" or realm == "" then
        realm = type(GetRealmName) == "function" and GetRealmName() or ""
    end
    name, realm = Util.text(name, Util.isSecret), Util.text(realm, Util.isSecret) or ""
    if not name then return nil end
    return name .. "-" .. realm, name, realm
end

local function ownList()
    local key, name, realm = Controller.shoppingSelf()
    if not key then return nil end
    return Shopping.list(CraftProfitDB.shopping, key, name, realm), key
end

local function shownKey()
    local own = Controller.shoppingSelf()
    if viewKey and viewKey ~= own and CraftProfitDB.shopping[viewKey] then return viewKey end
    viewKey = nil
    return own
end

-- Adds a recipe's reagents x crafts to the own list and says so in the chat (with the
-- crafts now planned). Returns true when added.
function Controller.addToShopping(recipe, crafts)
    if type(recipe) ~= "table" then return false end
    crafts = Util.count(crafts) or 1
    local list = ownList()
    local planned = list and Shopping.addRecipe(list, recipe, crafts, time()) or nil
    if not planned then
        Controller.say(L.SHOP_FULL)
        return false
    end
    Shopping.snapshotBags(list, Controller.bagCount)
    Controller.say(string.format(L.SHOP_ADDED, crafts, Controller.recipeName(recipe), planned))
    -- Adding shows the own list again.
    viewKey = nil
    Controller.refresh()
    return true
end

function Controller.shoppingRemoveRecipe(recipeID)
    local list = CraftProfitDB.shopping[shownKey() or ""]
    if Shopping.removeRecipe(list, recipeID) then Controller.refresh() end
end

function Controller.shoppingClear()
    local list = CraftProfitDB.shopping[shownKey() or ""]
    if list then
        Shopping.clear(list)
        Controller.refresh()
    end
end

-- The owner button: the next list (own first, then the others holding recipes).
function Controller.shoppingNextOwner()
    local current = shownKey()
    local owners = Shopping.owners(CraftProfitDB.shopping, Controller.shoppingSelf())
    if #owners <= 1 then return end
    local index = 1
    for i, key in ipairs(owners) do
        if key == current then index = i end
    end
    local nextKey = owners[index % #owners + 1]
    viewKey = nextKey ~= Controller.shoppingSelf() and nextKey or nil
    Controller.refresh()
end

-- The bags changed: the own list remembers what they hold of its materials (another
-- character reads it). Returns true when that changed.
function Controller.shoppingBagsChanged()
    local key = Controller.shoppingSelf()
    local list = key and CraftProfitDB.shopping[key]
    if not list or #list.recipes == 0 then return false end
    return Shopping.snapshotBags(list, Controller.bagCount)
end

function Controller.saveShoppingPosition(x, y)
    if Util.isFinite(x) and Util.isFinite(y) then
        CraftProfitDB.settings.shoppingWindow = { x = x, y = y }
    end
end

-- What the shopping window shows: the owner button text, the recipes of the list (each
-- with its crafts), the material rows, the total left to pay, and a note when the list is
-- another character's (its bags as last seen plus the current character's are counted).
function Controller.shoppingData()
    local key = shownKey()
    local own = Controller.shoppingSelf()
    local list = key and CraftProfitDB.shopping[key]
    if not list and key == own then list = ownList() end
    local isOwn = key == own
    local now = time()
    local market = Controller.market()
    local ownedOf = Controller.bagCount
    if not isOwn and list then
        ownedOf = function(id) return (list.bags[id] or 0) + (Controller.bagCount(id) or 0) end
    end
    local rows, total, unpriced = Shopping.rows(list, {
        ownedOf = ownedOf,
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
    local recipes = {}
    for _, e in ipairs(list and list.recipes or {}) do
        recipes[#recipes + 1] = {
            recipeID = e.recipe.recipeID,
            text = e.crafts .. "x " .. Controller.recipeName(e.recipe),
        }
    end
    local totalText
    if total then
        totalText = string.format(L.SHOP_TOTAL, fmt(total))
    else
        local known = 0
        for _, row in ipairs(rows) do known = known + (row.cost or 0) end
        totalText = string.format(L.SHOP_TOTAL_PARTIAL, fmt(known), #unpriced)
    end
    local ownerName = list and list.name or (key or "?")
    local owners = Shopping.owners(CraftProfitDB.shopping, own)
    return {
        rows = rows,
        recipes = recipes,
        totalText = totalText,
        incomplete = total == nil,
        title = string.format(L.SHOP_PANEL, #rows),
        recipesTitle = string.format(L.SHOP_RECIPES, #recipes),
        ownerText = string.format(L.SHOP_OWNER, ownerName),
        canSwitch = #owners > 1,
        note = not isOwn and string.format(L.SHOP_OTHER_NOTE, ownerName) or "",
        isOwn = isOwn,
    }
end
