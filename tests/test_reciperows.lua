local H = ...
local W = dofile("tests/fakewow.lua")

-- classID 0: disenchanting never applies, so the figures do not depend on the disenchant table.
local ITEMS = {
    [100] = { quality = 2, ilvl = 15, sellPrice = 200, classID = 0, bindType = 2 },
    [101] = { quality = 2, ilvl = 15, sellPrice = 1, classID = 0, bindType = 2 },
}

-- A learned recipe as the profession scan stores it: two of item 1 and one of item 2 make
-- `output` (100 sells well, 101 badly).
local function raw(id, output)
    return {
        recipeID = id, name = "R" .. id, locale = "enUS", difficulty = 1, outputItemID = output or 100,
        qtyMin = 1, qtyMax = 1, reagents = { { itemID = 1, qty = 2 }, { itemID = 2, qty = 1 } },
    }
end

-- Boots with Blacksmithing (164) open; `known` recipes stored for it.
local function boot(known, settings)
    local T = W.boot(H, { items = ITEMS })
    T.env.CraftProfitDB = settings and { settings = settings } or nil
    T.env.ProfessionsFrame = { IsShown = function() return true end }
    T.env.C_TradeSkillUI = {
        GetBaseProfessionInfo = function() return { professionID = 164, professionName = "Forge" } end,
    }
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    if known then T.ns.DB.setKnown(T.env.CraftProfitCharDB, "164", "Forge", known, 1700000000) end
    return T
end

local function stock(T)
    local P, db = T.ns.Prices, T.ns.Controller.market()
    P.store(db, 1, 100, 10, 1699999940)
    P.store(db, 2, 50, 10, 1699999880)
    P.store(db, 100, 1000, 10, 1699999970)
end

-- Controller ------------------------------------------------------------------------------

H.test("rowTag: the net of one craft of a known recipe, as the pinned list counts it, in its colour", function()
    local T = boot({ raw(5), raw(6, 101) })
    stock(T)
    local C, Colors, F = T.ns.Controller, T.ns.Colors, T.ns.Format
    local recipe = T.env.CraftProfitCharDB.known[1].recipes[1]
    local net = C.evaluate(recipe, 1).net
    H.truthy(net > 0)
    H.eq({ C.rowTag(5) }, { "+" .. F.short(net), Colors.FIXED.profit })
    -- Its output sells for 1 copper anywhere: a loss.
    T.ns.Prices.store(C.market(), 101, 1, 10, 1699999970)
    local text, color = C.rowTag(6)
    H.eq(text:sub(1, 1), "-")
    H.eq(color, Colors.FIXED.loss)
end)

H.test("rowTag: nothing for a recipe not stored, another profession's, or one without prices", function()
    local T = boot({ raw(5) })
    local C = T.ns.Controller
    -- No price at all.
    H.eq({ C.rowTag(5) }, {})
    stock(T)
    H.truthy(C.rowTag(5))
    H.eq({ C.rowTag(7) }, {})
    H.eq({ C.rowTag(nil) }, {})
    H.eq({ C.rowTag("5") }, {})
    -- Another profession open: its stored list (none here) is the one read.
    T.env.C_TradeSkillUI.GetBaseProfessionInfo = function() return { professionID = 197, professionName = "Couture" } end
    H.eq({ C.rowTag(5) }, {})
    -- The client cannot say which profession is open.
    T.env.C_TradeSkillUI.GetBaseProfessionInfo = function() error("boom") end
    H.eq({ C.rowTag(5) }, {})
end)

H.test("rowTag follows a new scan of the profession", function()
    local T = boot({ raw(5) })
    stock(T)
    local C = T.ns.Controller
    H.eq({ C.rowTag(6) }, {})
    T.ns.DB.setKnown(T.env.CraftProfitCharDB, "164", "Forge", { raw(6) }, 1700000000)
    H.truthy(C.rowTag(6))
    H.eq({ C.rowTag(5) }, {})
end)

H.test("rowTag: a missing resale price keeps the known figure in the incomplete colour", function()
    local T = boot({ raw(5) })
    local C, Colors = T.ns.Controller, T.ns.Colors
    -- Reagents priced, the output not: the vendor price is known, the AH one is missing.
    local P, db = T.ns.Prices, C.market()
    P.store(db, 1, 100, 10, 1699999940)
    P.store(db, 2, 50, 10, 1699999880)
    local result = C.evaluate(T.env.CraftProfitCharDB.known[1].recipes[1], 1)
    H.truthy(result.net ~= nil and result.incomplete)
    H.eq({ C.rowTag(5) }, { T.ns.Format.short(result.net), Colors.FIXED.incomplete })
    H.eq(T.ns.Format.short(result.net):sub(1, 1), "-")
end)

H.test("showRowTags defaults to on, setShowRowTags saves a boolean and repaints the rows", function()
    local T = boot()
    local C = T.ns.Controller
    H.eq(C.showRowTags(), true)
    local repaints = 0
    T.ns.RecipeRows = { refresh = function() repaints = repaints + 1 end }
    C.setShowRowTags(false)
    H.eq(T.env.CraftProfitDB.settings.showRowTags, false)
    H.eq(C.showRowTags(), false)
    H.eq(repaints, 1)
    C.setShowRowTags("yes")
    H.eq(T.env.CraftProfitDB.settings.showRowTags, true)
    H.eq(repaints, 2)
    -- A saved "off" survives the next login.
    local T2 = boot(nil, { showRowTags = false })
    H.eq(T2.ns.Controller.showRowTags(), false)
end)
