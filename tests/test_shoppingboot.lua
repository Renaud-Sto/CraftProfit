local H = ...
local W = dofile("tests/fakewow.lua")

-- Shopping lists through the real controller and window, in the fake game.
local ITEMS = {
    [100] = { quality = 2, ilvl = 15, sellPrice = 200, classID = 0, bindType = 2 },
}

local RAW = {
    recipeID = 5, name = "Sword", locale = "enUS", difficulty = 1, outputItemID = 100, qtyMin = 1, qtyMax = 1,
    reagents = { { itemID = 1, qty = 2 }, { itemID = 2, qty = 1 } },
}

-- The realm is set first: without GetRealmID the market key falls back to its name.
local function boot()
    local T = W.boot(H, { items = ITEMS })
    T.env.GetNormalizedRealmName = function() return "Greyson" end
    T.env.GetMoneyString = function(c) return "<" .. c .. ">" end
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    local P, db = T.ns.Prices, T.ns.Controller.market()
    P.store(db, 1, 100, 10, 1699999940)
    P.store(db, 2, 50, 10, 1699999880)
    P.store(db, 100, 1000, 10, 1699999970)
    return T
end

local function asChar(T, name)
    T.env.UnitName = function() return name end
    T.env.GetNormalizedRealmName = function() return "Greyson" end
end

H.test("the main window adds its recipe x crafts; the window shows recipes, bags, needs and costs", function()
    local T = boot()
    asChar(T, "Sto")
    local C = T.ns.Controller
    local counts = { [1] = 5 }
    T.env.C_Item.GetItemCount = function(id) return counts[id] or 0 end
    C.setRecipe(T.ns.Recipes.normalize(RAW), "profession")
    C.setCrafts(4)
    T.ns.Window.lastHandlers.onAddToShopping()
    local list = T.env.CraftProfitDB.shopping["Sto-Greyson"]
    H.eq(#list.recipes, 1)
    H.eq(list.recipes[1].crafts, 4)
    H.truthy(T.chat[#T.chat]:find("Added 4x Sword to the shopping list (4 planned)", 1, true))
    local data = C.shoppingData()
    H.eq(data.recipes, { { recipeID = 5, text = "4x Sword" } })
    H.eq(data.ownerText, "List: Sto")
    H.eq(data.note, "")
    H.eq({ data.rows[1].haveText, data.rows[1].needText, data.rows[1].costText }, { "5", "8", "<300>" })
    H.eq(data.totalText, "Left to buy: <500>")
    T.ns.ShoppingWindow.show()
    H.truthy(T.ns.ShoppingWindow.isShown())
    local row = T.ns.ShoppingWindow.parts.rows[1]
    H.eq(row.qty, 3)
    T.ns.AH.isOpen = true
    T.env.C_Item.GetItemInfo = function() return "Bronze Bar" end
    local searched
    T.ns.AH.browse = function(name, id, qty) searched = { name, id, qty }; return true end
    row.scripts.OnClick(row)
    H.eq(searched, { "Bronze Bar", 1, 3 })
    -- Gathered: done, nothing to pay.
    counts[1] = 8
    H.eq(C.shoppingData().rows[1].costText, "done")
    -- The recipe's "x" removes it and its materials.
    local x = T.ns.ShoppingWindow.parts.recipes[1].remove
    x.scripts.OnClick(x)
    H.eq(#list.recipes, 0)
    H.eq(C.shoppingData().rows, {})
end)

H.test("another character's list is chosen with the owner button, its bags plus yours counted", function()
    local T = boot()
    local C = T.ns.Controller
    local counts = { [1] = 2 }
    T.env.C_Item.GetItemCount = function(id) return counts[id] or 0 end
    asChar(T, "Grom")
    C.addToShopping(T.ns.Recipes.normalize(RAW), 4)
    H.eq(T.env.CraftProfitDB.shopping["Grom-Greyson"].bags[1], 2)
    -- On the mage at the auction house, 3 bars already bought.
    asChar(T, "Aya")
    counts[1] = 3
    local own = C.shoppingData()
    H.eq(own.ownerText, "List: Aya")
    H.eq(own.canSwitch, true)
    C.shoppingNextOwner()
    local war = C.shoppingData()
    H.eq(war.ownerText, "List: Grom")
    H.eq(war.rows[1].haveText, "5")
    H.eq(war.rows[1].needText, "8")
    H.truthy(war.note:find("Grom", 1, true))
    -- The bags of the war, seen again later, refresh its snapshot.
    asChar(T, "Grom")
    counts[1] = 7
    H.truthy(C.shoppingBagsChanged())
    H.eq(T.env.CraftProfitDB.shopping["Grom-Greyson"].bags[1], 7)
    -- Adding from the mage goes to the mage's own list and shows it again.
    asChar(T, "Aya")
    C.addToShopping(T.ns.Recipes.normalize(RAW), 1)
    H.eq(C.shoppingData().ownerText, "List: Aya")
    H.eq(#T.env.CraftProfitDB.shopping["Grom-Greyson"].recipes, 1)
end)

H.test("broken saved lists are repaired at load and an old per-character list is dropped", function()
    local T = W.boot(H, { items = ITEMS })
    T.env.CraftProfitDB = { shopping = {
        ["Sto-Greyson"] = { name = "Sto", recipes = { { recipe = RAW, crafts = 2 }, "junk" } }, x = 5,
    } }
    T.env.CraftProfitCharDB = { shopping = { { itemID = 1, qty = 2 } } }
    T.env.GetMoneyString = function(c) return "<" .. c .. ">" end
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    H.eq(#T.env.CraftProfitDB.shopping["Sto-Greyson"].recipes, 1)
    H.eq(T.env.CraftProfitDB.shopping.x, nil)
    H.eq(T.env.CraftProfitCharDB.shopping, nil)
end)
