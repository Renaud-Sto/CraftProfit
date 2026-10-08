local H = ...
local W = dofile("tests/fakewow.lua")

-- classID 0 (not weapon/armor): disenchanting never applies, so these smoke
-- tests do not depend on the contents of the disenchant table.
local ITEMS = {
    [100] = { quality = 2, ilvl = 15, sellPrice = 200, classID = 0, bindType = 2 },
}

local RAW = {
    recipeID = 5, name = "Sword", difficulty = 1, outputItemID = 100, qtyMin = 1, qtyMax = 1,
    reagents = { { itemID = 1, qty = 2 }, { itemID = 2, qty = 1 } },
}

local function boot(opts)
    local T = W.boot(H, opts or { items = ITEMS })
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    return T
end

local function stock(T)
    local P, db = T.ns.Prices, T.env.CraftProfitDB
    P.store(db, 1, 100, 10, 1699999940)
    P.store(db, 2, 50, 10, 1699999880)
    P.store(db, 100, 1000, 10, 1699999970)
end

H.test("every file listed in the TOC loads without error", function()
    local T = W.boot(H, { items = ITEMS })
    H.truthy(T.ns.Controller)
    H.truthy(T.ns.Window)
    H.truthy(T.ns.AH)
    H.truthy(T.ns.Trade)
end)

H.test("the addon only reacts to its own ADDON_LOADED", function()
    local T = W.boot(H, { items = ITEMS })
    T.ns.Controller.onEvent("ADDON_LOADED", "SomethingElse")
    H.falsy(T.ns.Controller.ready)
    T.ns.Controller.onEvent("ITEM_DATA_LOAD_RESULT", 100)
    T.ns.Controller.onEvent("TRADE_SKILL_LIST_UPDATE")
end)

H.test("ADDON_LOADED creates and repairs the saved variables", function()
    local T = boot()
    H.truthy(T.ns.Controller.ready)
    H.eq(T.env.CraftProfitDB.dbVersion, 1)
    H.eq(T.env.CraftProfitDB.settings.cut, 0.05)
    H.eq(T.env.CraftProfitCharDB.pins, {})
end)

H.test("existing saved variables are kept and repaired in place", function()
    local T = W.boot(H, { items = ITEMS })
    local db = { settings = { cut = 0 / 0, medianN = 3 }, prices = { [9] = "junk" } }
    T.env.CraftProfitDB = db
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    H.truthy(T.env.CraftProfitDB == db)
    H.eq(db.settings.cut, 0.05)
    H.eq(db.settings.medianN, 3)
    H.eq(db.prices, {})
end)

H.test("the client locale selects the language", function()
    local T = boot({ locale = "frFR", items = ITEMS })
    H.eq(T.ns.Locale.current, "frFR")
    local unsupported = boot({ locale = "deDE", items = ITEMS })
    H.eq(unsupported.ns.Locale.current, "enUS")
end)

H.test("a selected recipe is evaluated and rendered", function()
    local T = boot()
    stock(T)
    local recipe = T.ns.Recipes.normalize(RAW)
    T.ns.Controller.setRecipe(recipe, "profession")
    local model = T.ns.Window.lastModel
    H.eq(model.verdict.kind, "profit")
    H.eq(model.lines[1].value, "<250>")
    H.eq(model.pinned, false)
    H.truthy(T.ns.Window.isShown())
end)

H.test("an unloaded item shows unknown values and asks the game to load it", function()
    local T = boot({ items = {} })
    stock(T)
    T.ns.Controller.setRecipe(T.ns.Recipes.normalize(RAW), "profession")
    local model = T.ns.Window.lastModel
    H.eq(model.verdict.kind, "incomplete")
    H.eq(model.lines[3].value, "?")
    H.truthy(#T.loadRequests > 0)
    T.ns.Controller.onEvent("ITEM_DATA_LOAD_RESULT", 100)
    T.run()
end)

H.test("a recipe with no prices at all renders as incomplete without errors", function()
    local T = boot()
    T.ns.Controller.setRecipe(T.ns.Recipes.normalize(RAW), "profession")
    H.eq(T.ns.Window.lastModel.verdict.kind, "incomplete")
    H.eq(T.ns.Window.lastModel.ageText, "Prices: never scanned")
end)

H.test("pinning toggles the recipe in the character's pins", function()
    local T = boot()
    local C = T.ns.Controller
    C.setRecipe(T.ns.Recipes.normalize(RAW), "profession")
    C.togglePin()
    H.eq(#T.env.CraftProfitCharDB.pins, 1)
    H.eq(T.ns.Window.lastModel.pinned, true)
    C.togglePin()
    H.eq(#T.env.CraftProfitCharDB.pins, 0)
    H.eq(T.ns.Window.lastModel.pinned, false)
end)

H.test("togglePin with no recipe selected does nothing", function()
    local T = boot()
    T.ns.Controller.togglePin()
    H.eq(#T.env.CraftProfitCharDB.pins, 0)
end)

H.test("recordListings stores the median price and ignores empty answers", function()
    local T = boot()
    local C = T.ns.Controller
    H.eq(C.recordListings(7, { { unit = 10, qty = 1 }, { unit = 20, qty = 1 }, { unit = 1000, qty = 1 } }), true)
    H.eq(T.env.CraftProfitDB.prices[7][1], 20)
    H.eq(C.recordListings(8, {}), false)
    H.eq(T.env.CraftProfitDB.prices[8], nil)
end)

H.test("the selection watcher shows, updates and hides the window", function()
    local T = boot()
    stock(T)
    local C, ns = T.ns.Controller, T.ns
    T.env.ProfessionsFrame = {
        IsShown = function() return true end,
        CraftingPage = { SchematicForm = { GetRecipeInfo = function() return { recipeID = 5 } end } },
    }
    T.env.Enum = { CraftingReagentType = { Basic = 1 } }
    T.env.C_TradeSkillUI = {
        GetRecipeInfo = function(id) return { recipeID = id, name = "Sword", learned = true, relativeDifficulty = 1 } end,
        GetRecipeSchematic = function()
            return { outputItemID = 100, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = {
                { reagentType = 1, quantityRequired = 2, reagents = { { itemID = 1 } } },
                { reagentType = 1, quantityRequired = 1, reagents = { { itemID = 2 } } },
            } }
        end,
    }
    H.truthy(#T.tickers >= 1)
    T.tickers[#T.tickers].fn()
    H.eq(ns.Window.lastModel.verdict.kind, "profit")
    T.env.ProfessionsFrame.IsShown = function() return false end
    T.tickers[#T.tickers].fn()
    H.falsy(ns.Window.isShown())
    H.eq(C.currentRecipeID(), nil)
end)

H.test("the slash command runs the self-test and reports in chat", function()
    local T = boot()
    T.env.SlashCmdList.CRAFTPROFIT("selftest")
    H.truthy(T.chat[#T.chat]:find("Self-test passed", 1, true))
    T.env.SlashCmdList.CRAFTPROFIT("locale frFR")
    H.eq(T.ns.Locale.current, "frFR")
    T.env.SlashCmdList.CRAFTPROFIT("")
    H.truthy(T.chat[#T.chat]:find("/cp", 1, true))
end)

H.test("an unknown or malformed slash argument never raises", function()
    local T = boot()
    local slash = T.env.SlashCmdList.CRAFTPROFIT
    slash("nonsense")
    slash("locale")
    slash("locale xxXX")
    slash("show")
    slash("hide")
    slash("reset")
    slash(nil)
end)

H.test("a moved window is saved and reused", function()
    local T = boot()
    T.ns.Window.lastHandlers.onMoved("TOPLEFT", 120, 640)
    H.eq(T.env.CraftProfitDB.settings.window, { point = "TOPLEFT", x = 120, y = 640 })
end)

H.test("toggling the per-point option is saved and re-renders", function()
    local T = boot()
    stock(T)
    T.ns.Controller.setRecipe(T.ns.Recipes.normalize(RAW), "profession")
    T.ns.Window.lastHandlers.onPerPointToggle(true)
    H.eq(T.env.CraftProfitDB.settings.showPerPoint, true)
    H.eq(T.ns.Window.lastModel.lines[5].key, "perpoint")
end)

H.test("folding the materials detail is saved and re-renders", function()
    local T = boot()
    stock(T)
    T.ns.Controller.setRecipe(T.ns.Recipes.normalize(RAW), "profession")
    H.eq(T.ns.Window.lastModel.costExpanded, true)
    T.ns.Window.lastHandlers.onCostToggle(false)
    H.eq(T.env.CraftProfitDB.settings.costExpanded, false)
    H.eq(T.ns.Window.lastModel.costExpanded, false)
    T.ns.Window.lastHandlers.onCostToggle(true)
    H.eq(T.ns.Window.lastModel.costExpanded, true)
end)

H.test("ADDON_ACTION_BLOCKED for this addon is reported", function()
    local T = boot()
    T.ns.Controller.onEvent("ADDON_ACTION_BLOCKED", "CraftProfit", "SomeProtectedFunction")
    H.truthy(T.chat[#T.chat]:find("SomeProtectedFunction", 1, true))
    local before = #T.chat
    T.ns.Controller.onEvent("ADDON_ACTION_BLOCKED", "OtherAddon", "X")
    H.eq(#T.chat, before)
end)

local function mockProfession(T)
    T.env.ProfessionsFrame = {
        IsShown = function() return true end,
        CraftingPage = { SchematicForm = { GetRecipeInfo = function() return { recipeID = 5 } end } },
    }
    T.env.Enum = { CraftingReagentType = { Basic = 1 } }
    T.env.C_TradeSkillUI = {
        GetRecipeInfo = function(id) return { recipeID = id, name = "Sword", learned = true, relativeDifficulty = 1 } end,
        GetRecipeSchematic = function()
            return { outputItemID = 100, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = {
                { reagentType = 1, quantityRequired = 2, reagents = { { itemID = 1 } } },
                { reagentType = 1, quantityRequired = 1, reagents = { { itemID = 2 } } },
            } }
        end,
    }
end

-- Fix wave item 1
H.test("the window model carries the recipe name, or the output item name, or nil", function()
    local T = boot()
    T.ns.Controller.setRecipe(T.ns.Recipes.normalize(RAW), "profession")
    H.eq(T.ns.Window.lastModel.title, "Sword")
    local unnamed = {}
    for k, v in pairs(RAW) do unnamed[k] = v end
    unnamed.name = ""
    T.ns.Controller.setRecipe(T.ns.Recipes.normalize(unnamed), "profession")
    H.eq(T.ns.Window.lastModel.title, "Item100")
    local T2 = boot({ items = {} })
    T2.ns.Controller.setRecipe(T2.ns.Recipes.normalize(unnamed), "profession")
    H.eq(T2.ns.Window.lastModel.title, nil)
    H.eq(T2.ns.Controller.itemName(100), nil)
end)

-- Fix wave item 2
H.test("every verdict kind renders without errors", function()
    local T = boot()
    local C = T.ns.Controller
    C.setRecipe(T.ns.Recipes.normalize(RAW), "profession")
    H.eq(T.ns.Window.lastModel.verdict.kind, "incomplete")
    stock(T)
    H.eq(T.ns.Window.lastModel.verdict.kind, "incomplete")
    C.refresh()
    H.eq(T.ns.Window.lastModel.verdict.kind, "profit")
    T.env.CraftProfitDB.prices[100][1] = 1
    C.refresh()
    H.eq(T.ns.Window.lastModel.verdict.kind, "loss")
    T.ns.Window.render({
        lines = {}, verdict = { kind = "none", text = "x", value = "?" }, ageText = "",
    })
    H.eq(T.ns.Window.lastModel.verdict.kind, "none")
end)

-- Fix wave item 3
H.test("a failed item load is not retried forever", function()
    local T = boot({ items = {} })
    local C = T.ns.Controller
    C.setRecipe(T.ns.Recipes.normalize(RAW), "profession")
    local n = #T.loadRequests
    H.truthy(n > 0)
    C.onEvent("ITEM_DATA_LOAD_RESULT", 100, false)
    T.run()
    C.onEvent("ITEM_DATA_LOAD_RESULT", 1, false)
    T.run()
    H.eq(#T.loadRequests, n)
    H.eq(#T.timers, 0)
    C.onEvent("ITEM_DATA_LOAD_RESULT", 2, true)
    H.eq(#T.timers, 1)
    T.run()
end)

H.test("a successful item load clears the mark so a missing item can be requested again", function()
    local T = boot({ items = {} })
    local C = T.ns.Controller
    C.setRecipe(T.ns.Recipes.normalize(RAW), "profession")
    local n = #T.loadRequests
    C.onEvent("ITEM_DATA_LOAD_RESULT", 100, true)
    T.run()
    H.truthy(#T.loadRequests > n)
end)

-- Fix wave item 4
H.test("an AH that is already open when the addon loads is detected", function()
    local T = W.boot(H, { items = ITEMS })
    T.env.AuctionHouseFrame = { IsShown = function() return true end }
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    H.eq(T.ns.AH.isOpen, true)
    local T2 = boot()
    H.falsy(T2.ns.AH.isOpen)
    local T3 = W.boot(H, { items = ITEMS })
    T3.env.AuctionHouseFrame = {}
    T3.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    H.falsy(T3.ns.AH.isOpen)
end)

-- Fix wave item 6
H.test("reagent item data is requested for the displayed recipe", function()
    local T = boot({ items = {} })
    T.ns.Controller.setRecipe(T.ns.Recipes.normalize(RAW), "profession")
    local seen = {}
    for _, id in ipairs(T.loadRequests) do seen[id] = true end
    H.truthy(seen[1])
    H.truthy(seen[2])
    H.truthy(seen[100])
end)

-- Fix wave item 7
H.test("the profession recipe comes back after the AH closes", function()
    local T = boot()
    stock(T)
    mockProfession(T)
    T.tickers[#T.tickers].fn()
    H.eq(T.ns.Controller.currentRecipeID(), 5)
    T.ns.Controller.selectPin(999)
    T.ns.DB.pinAdd(T.env.CraftProfitCharDB, RAW)
    T.ns.Controller.selectPin(5)
    T.ns.Controller.onAHOpen(true)
    T.ns.Controller.onAHOpen(false)
    H.falsy(T.ns.Window.isShown())
    T.ns.Window.lastModel = nil
    T.tickers[#T.tickers].fn()
    H.truthy(T.ns.Window.isShown())
    H.truthy(T.ns.Window.lastModel)
end)

-- Pinned recipe survives closing the profession window (field report: it vanished at the AH)
H.test("a pinned recipe stays available after the profession window closes, outside the AH", function()
    local T = boot()
    stock(T)
    mockProfession(T)
    T.tickers[#T.tickers].fn()
    T.ns.Controller.togglePin()
    T.env.ProfessionsFrame.IsShown = function() return false end
    T.tickers[#T.tickers].fn()
    H.falsy(T.ns.Window.isShown())
    T.env.AuctionHouseFrame = {}
    T.ns.Controller.onAHOpen(true)
    H.truthy(T.ns.Window.isShown())
    H.eq(T.ns.Controller.currentRecipeID(), 5)
end)

H.test("a pinned recipe stays shown when the profession window closes while the AH is open", function()
    local T = boot()
    stock(T)
    mockProfession(T)
    T.env.AuctionHouseFrame = {}
    T.tickers[#T.tickers].fn()
    T.ns.Controller.togglePin()
    T.ns.AH.onEvent("AUCTION_HOUSE_SHOW")
    T.env.ProfessionsFrame.IsShown = function() return false end
    T.tickers[#T.tickers].fn()
    H.truthy(T.ns.Window.isShown())
    H.eq(T.ns.Controller.currentRecipeID(), 5)
end)

H.test("an unpinned recipe is dropped when the profession window closes", function()
    local T = boot()
    stock(T)
    mockProfession(T)
    T.tickers[#T.tickers].fn()
    T.env.ProfessionsFrame.IsShown = function() return false end
    T.tickers[#T.tickers].fn()
    H.eq(T.ns.Controller.currentRecipeID(), nil)
    H.falsy(T.ns.Window.isShown())
end)

H.test("asking for the name of an unloaded item requests it once", function()
    local T = boot({ items = {} })
    T.ns.Controller.itemName(555)
    T.ns.Controller.itemName(555)
    local n = 0
    for _, id in ipairs(T.loadRequests) do if id == 555 then n = n + 1 end end
    H.eq(n, 1)
end)
