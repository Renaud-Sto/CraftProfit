local H = ...
local W = dofile("tests/fakewow.lua")

-- classID 0 (not weapon/armor): disenchanting never applies, so these smoke
-- tests do not depend on the contents of the disenchant table.
local ITEMS = {
    [100] = { quality = 2, ilvl = 15, sellPrice = 200, classID = 0, bindType = 2 },
}

local RAW = {
    -- Read in the fake client's language (enUS): its stored name is the current one.
    recipeID = 5, name = "Sword", locale = "enUS", difficulty = 1, outputItemID = 100, qtyMin = 1, qtyMax = 1,
    reagents = { { itemID = 1, qty = 2 }, { itemID = 2, qty = 1 } },
}

local function boot(opts)
    local T = W.boot(H, opts or { items = ITEMS })
    -- Forever draws coin icons with GetMoneyString (there is no GetCoinTextureString).
    T.env.GetMoneyString = function(c) return "<" .. c .. ">" end
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    return T
end

H.test("amounts use GetMoneyString and fall back to plain text when it answers nothing", function()
    local T = boot()
    H.eq(T.ns.Controller.fmt(250), "<250>")
    T.env.GetMoneyString = function() return nil end
    H.eq(T.ns.Controller.fmt(250), "2s 50c")
    T.env.GetMoneyString = function() error("boom") end
    H.eq(T.ns.Controller.fmt(250), "2s 50c")
end)

local function stock(T)
    local P, db = T.ns.Prices, T.ns.Controller.market()
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
    H.eq(T.ns.Controller.market().prices[7][1], 20)
    H.eq(C.recordListings(8, {}), false)
    H.eq(T.ns.Controller.market().prices[8], nil)
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
H.test("the window model carries the recipe name, or the output item name, or #id", function()
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
    H.eq(T2.ns.Window.lastModel.title, "#5")
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
    T.ns.Controller.market().prices[100][1] = 1
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

-- Pins sorted by cost per point
H.test("pinned difficulties follow the open profession window", function()
    local T = boot()
    mockProfession(T)
    local pin = T.ns.Recipes.normalize(RAW)
    T.ns.DB.pinAdd(T.env.CraftProfitCharDB, pin)
    T.env.C_TradeSkillUI.GetRecipeInfo = function(id)
        return { recipeID = id, learned = true, relativeDifficulty = 2 }
    end
    T.ns.Controller.onEvent("TRADE_SKILL_LIST_UPDATE")
    H.eq(T.env.CraftProfitCharDB.pins[1].difficulty, "easy")
end)

H.test("pinned difficulties are left alone when the window is closed or the recipe is unreadable", function()
    local T = boot()
    mockProfession(T)
    T.ns.DB.pinAdd(T.env.CraftProfitCharDB, T.ns.Recipes.normalize(RAW))
    T.env.ProfessionsFrame.IsShown = function() return false end
    T.env.C_TradeSkillUI.GetRecipeInfo = function() return { learned = true, relativeDifficulty = 3 } end
    T.ns.Controller.onEvent("TRADE_SKILL_LIST_UPDATE")
    H.eq(T.env.CraftProfitCharDB.pins[1].difficulty, "medium")
    T.env.ProfessionsFrame.IsShown = function() return true end
    T.env.C_TradeSkillUI.GetRecipeInfo = function() return { learned = false, relativeDifficulty = 3 } end
    T.ns.Controller.onEvent("TRADE_SKILL_LIST_UPDATE")
    H.eq(T.env.CraftProfitCharDB.pins[1].difficulty, "medium")
    T.env.C_TradeSkillUI.GetRecipeInfo = function() return { learned = true, relativeDifficulty = 99 } end
    T.ns.Controller.onEvent("TRADE_SKILL_LIST_UPDATE")
    H.eq(T.env.CraftProfitCharDB.pins[1].difficulty, "medium")
end)

H.test("sorting by cost per point switches the cost per point option on", function()
    local T = boot()
    H.eq(T.env.CraftProfitCharDB.sortMode, "net")
    H.falsy(T.env.CraftProfitDB.settings.showPerPoint)
    T.ns.Controller.toggleSort()
    H.eq(T.env.CraftProfitCharDB.sortMode, "point")
    H.truthy(T.env.CraftProfitDB.settings.showPerPoint)
    T.ns.Controller.toggleSort()
    H.eq(T.env.CraftProfitCharDB.sortMode, "net")
    H.truthy(T.env.CraftProfitDB.settings.showPerPoint)
end)

H.test("turning the cost per point option off also leaves the point sort", function()
    local T = boot()
    T.ns.Controller.toggleSort()
    T.ns.Window.lastHandlers.onPerPointToggle(false)
    H.eq(T.env.CraftProfitCharDB.sortMode, "net")
    H.falsy(T.env.CraftProfitDB.settings.showPerPoint)
end)

H.test("the sort mode is saved with the character and repaired when corrupt", function()
    local T = W.boot(H, { items = ITEMS })
    T.env.CraftProfitCharDB = { pins = {}, sortMode = "point" }
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    H.eq(T.env.CraftProfitCharDB.sortMode, "point")
    local T2 = W.boot(H, { items = ITEMS })
    T2.env.CraftProfitCharDB = { pins = {}, sortMode = "banana" }
    T2.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    H.eq(T2.env.CraftProfitCharDB.sortMode, "net")
end)

H.test("clicking a reagent searches it at the AH, or says why it cannot", function()
    local T = boot()
    local C = T.ns.Controller
    local searched
    T.ns.AH.browse = function(name, id, qty) searched = { name, id, qty }; return true end
    C.onReagentClick(1, 20)
    H.eq(searched, nil)
    H.eq(T.chat[#T.chat], "|cff66ccffCraftProfit|r Open the auction house first")
    T.ns.AH.isOpen = true
    C.onReagentClick(1, 20)
    H.eq(searched, nil)
    H.eq(T.chat[#T.chat], "|cff66ccffCraftProfit|r Item not loaded yet, try again in a moment")
    T.env.C_Item.GetItemInfo = function() return "Bronze Bar" end
    C.onReagentClick(1, 20)
    H.eq(searched, { "Bronze Bar", 1, 20 })
    T.ns.AH.browse = function() return false, "unavailable" end
    C.onReagentClick(1, 20)
    H.eq(T.chat[#T.chat], "|cff66ccffCraftProfit|r The auction house search is not available")
end)

H.test("a reagent row click in the window reaches the controller", function()
    local T = boot()
    T.ns.Window.lastHandlers.onReagentClick(1, 2)
    H.eq(T.chat[#T.chat], "|cff66ccffCraftProfit|r Open the auction house first")
end)

-- Several crafts
H.test("setCrafts scales the window only, clamps bad input and starts again on another recipe", function()
    local T = boot()
    stock(T)
    local C = T.ns.Controller
    C.setRecipe(T.ns.Recipes.normalize(RAW), "profession")
    H.eq(T.ns.Window.lastModel.crafts, 1)
    local single = T.ns.Window.lastModel.lines[1].value
    C.setCrafts("5")
    H.eq(T.ns.Window.lastModel.crafts, 5)
    H.eq(T.ns.Window.lastModel.costLines[1].qty, 10)
    H.truthy(T.ns.Window.lastModel.lines[1].value ~= single)
    C.setCrafts("0")
    H.eq(T.ns.Window.lastModel.crafts, 1)
    C.setCrafts("")
    H.eq(T.ns.Window.lastModel.crafts, 1)
    C.setCrafts(50000)
    H.eq(T.ns.Window.lastModel.crafts, 9999)
    -- the pinned list is one craft whatever the multiplier
    H.eq(C.evaluate(T.ns.Recipes.normalize(RAW)).crafts, 1)
    -- same recipe keeps the multiplier, another one resets it
    C.setCrafts(4)
    C.setRecipe(T.ns.Recipes.normalize(RAW), "profession")
    H.eq(T.ns.Window.lastModel.crafts, 4)
    local other = T.ns.Recipes.normalize(RAW)
    other.recipeID = 6
    C.setRecipe(other, "profession")
    H.eq(T.ns.Window.lastModel.crafts, 1)
end)

H.test("a reagent click searches the multiplied quantity", function()
    local T = boot()
    stock(T)
    local C = T.ns.Controller
    C.setRecipe(T.ns.Recipes.normalize(RAW), "profession")
    C.setCrafts(3)
    T.ns.AH.isOpen = true
    T.env.C_Item.GetItemInfo = function() return "Bronze Bar" end
    local searched
    T.ns.AH.browse = function(name, id, qty) searched = { name, id, qty }; return true end
    local row = T.ns.Window.lastModel.costLines[1]
    T.ns.Window.lastHandlers.onReagentClick(row.itemID, row.qty)
    H.eq(searched, { "Bronze Bar", 1, 6 })
end)

-- Price history
local function track(T, recipe)
    local ok = T.ns.History.track(T.env.CraftProfitDB, T.ns.Recipes.normalize(recipe or RAW))
    H.truthy(ok)
end

H.test("the first market adopts the prices saved before markets existed", function()
    local T = W.boot(H, { items = ITEMS })
    T.env.CraftProfitDB = { prices = { [1] = { 100, 5, 1699999000 } }, snapshotTime = 1699999000 }
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    local market = T.ns.Controller.market()
    H.eq(market.prices[1], { 100, 5, 1699999000 })
    H.eq(market.snapshotTime, 1699999000)
    H.eq(T.env.CraftProfitDB.prices, {})
end)

H.test("each realm id and faction has its own prices, with the realm name as fallback", function()
    local T = boot()
    T.env.GetRealmID = function() return 4613 end
    T.env.UnitFactionGroup = function() return "Horde" end
    H.eq(T.ns.Controller.marketKey(), "4613-Horde")
    T.ns.Prices.store(T.ns.Controller.market(), 1, 100, 1, 1700000000)
    T.env.GetRealmID = function() return 4702 end
    H.eq(T.ns.Controller.marketKey(), "4702-Horde")
    H.eq(T.ns.Controller.market().prices[1], nil)
    T.env.GetRealmID = function() return 4613 end
    T.env.UnitFactionGroup = function() return "Alliance" end
    H.eq(T.ns.Controller.marketKey(), "4613-Alliance")
    H.eq(T.ns.Controller.market().prices[1], nil)
    T.env.GetRealmID = nil
    T.env.GetNormalizedRealmName = function() return "ClassicBetaPvP2" end
    H.eq(T.ns.Controller.marketKey(), "ClassicBetaPvP2-Alliance")
    T.env.GetNormalizedRealmName = function() return nil end
    T.env.GetRealmName = function() return nil end
    T.env.UnitFactionGroup = function() return nil end
    H.eq(T.ns.Controller.marketKey(), "unknown-Neutral")
end)

H.test("a price search records a history point for a tracked recipe it touches, once complete", function()
    local T = boot()
    local C = T.ns.Controller
    track(T)
    local listing = { { unit = 100, qty = 5 } }
    C.recordListings(1, listing)
    C.commitSearch()
    H.eq(C.market().series[1], nil)       -- reagent 2 and the output have no price yet
    C.recordListings(1, listing)
    C.recordListings(2, listing)
    C.recordListings(100, listing)
    C.commitSearch()
    H.eq(#C.market().series[1], 1)
    H.eq(#C.market().series[2], 1)
    H.eq(#C.market().series[100], 1)
    H.eq(C.market().series[1][1][2], 100)
end)

H.test("a point needs a touched item: an unrelated search records nothing", function()
    local T = boot()
    local C = T.ns.Controller
    track(T)
    stock(T)
    C.recordListings(999, { { unit = 5, qty = 1 } })
    C.commitSearch()
    H.eq(C.market().series[1], nil)
end)

H.test("a scan records points for the tracked recipes it covers", function()
    local T = boot()
    local C = T.ns.Controller
    track(T)
    local agg = T.ns.Prices.newAggregator()
    agg.add(1, 100, 1)
    agg.add(2, 50, 1)
    agg.add(100, 1000, 1)
    agg.add(555, 7, 1)
    C.onSnapshot(agg)
    H.eq(#C.market().series[1], 1)
    H.eq(#C.market().series[100], 1)
    H.eq(C.market().series[555], nil)
end)

H.test("a paused recipe records nothing; resuming records again", function()
    local T = boot()
    local C = T.ns.Controller
    track(T)
    T.ns.History.pause(T.env.CraftProfitDB, 5)
    stock(T)
    local agg = T.ns.Prices.newAggregator()
    agg.add(1, 100, 1)
    C.onSnapshot(agg)
    H.eq(C.market().series[1], nil)
    T.ns.History.track(T.env.CraftProfitDB, T.ns.Recipes.normalize(RAW))
    T.clock = T.clock + 10
    C.onSnapshot(agg)
    H.eq(#C.market().series[1], 1)
end)

H.test("a bind-on-pickup output does not have to be priced for a point to be recorded", function()
    local T = boot({ items = { [100] = { quality = 2, ilvl = 15, sellPrice = 200, classID = 0, bindType = 1 } } })
    local C = T.ns.Controller
    track(T)
    local agg = T.ns.Prices.newAggregator()
    agg.add(1, 100, 1)
    agg.add(2, 50, 1)
    C.onSnapshot(agg)
    H.eq(#C.market().series[1], 1)
    H.eq(C.market().series[100], nil)
end)

H.test("the tracking box starts and pauses recording and refuses a sixteenth recipe", function()
    local T = boot()
    local C = T.ns.Controller
    C.setRecipe(T.ns.Recipes.normalize(RAW), "profession")
    H.falsy(T.ns.Window.lastModel.tracked)
    T.ns.Window.lastHandlers.onTrackToggle(true)
    H.truthy(T.ns.Window.lastModel.tracked)
    H.eq(#T.env.CraftProfitDB.tracked, 1)
    T.ns.Window.lastHandlers.onTrackToggle(false)
    H.falsy(T.ns.Window.lastModel.tracked)
    H.eq(#T.env.CraftProfitDB.tracked, 1)
    for id = 1000, 1013 do
        local r = T.ns.Recipes.normalize(RAW)
        r.recipeID = id
        H.truthy(T.ns.History.track(T.env.CraftProfitDB, r))
    end
    H.eq(#T.env.CraftProfitDB.tracked, 15)
    local extra = T.ns.Recipes.normalize(RAW)
    extra.recipeID = 2000
    C.setRecipe(extra, "profession")
    T.ns.Window.lastHandlers.onTrackToggle(true)
    H.falsy(T.ns.Window.lastModel.tracked)
    H.eq(T.chat[#T.chat], "|cff66ccffCraftProfit|r Too many tracked recipes (15 max)")
end)

H.test("/cp history lists the tracked recipes and removes one with its history", function()
    local T = boot()
    local C = T.ns.Controller
    C.historyCommand("")
    H.eq(T.chat[#T.chat], "|cff66ccffCraftProfit|r No tracked recipe")
    track(T)
    stock(T)
    local agg = T.ns.Prices.newAggregator()
    agg.add(1, 100, 1)
    C.onSnapshot(agg)
    H.truthy(C.market().series[1])
    C.historyCommand("")
    H.eq(T.chat[#T.chat], "|cff66ccffCraftProfit|r 1. Sword (tracking)")
    C.historyCommand("remove 9")
    H.eq(T.chat[#T.chat], "|cff66ccffCraftProfit|r No such tracked recipe. Use /cp history to list them")
    C.historyCommand("remove 1")
    H.eq(#T.env.CraftProfitDB.tracked, 0)
    H.eq(C.market().series[1], nil)
end)

H.test("a hardcore character has its own market, and /cp market tells which one is in use", function()
    local T = boot()
    T.env.GetRealmID = function() return 4613 end
    T.env.GetRealmName = function() return "Classic Beta PvP 2" end
    T.env.UnitFactionGroup = function() return "Horde" end
    T.env.C_GameRules = { IsHardcoreActive = function() return false end }
    H.eq(T.ns.Controller.marketKey(), "4613-Horde")
    T.env.C_GameRules = { IsHardcoreActive = function() return true end }
    H.eq(T.ns.Controller.marketKey(), "4613-Horde-HC")
    T.env.C_GameRules = { IsHardcoreActive = function() error("boom") end }
    H.eq(T.ns.Controller.marketKey(), "4613-Horde")
    T.env.SlashCmdList.CRAFTPROFIT("market")
    H.eq(T.chat[#T.chat], "|cff66ccffCraftProfit|r Market: Classic Beta PvP 2 (saved as 4613-Horde)")
end)

-- Leveling list
local function raw(id, difficulty, reagentID)
    return { recipeID = id, name = "R" .. id, difficulty = difficulty, outputItemID = 100, qtyMin = 1, qtyMax = 1,
        reagents = { { itemID = reagentID or 1, qty = 2 } } }
end

H.test("opening a profession stores its learned recipes, once per burst, and abandons nothing on a closed window", function()
    local T = boot()
    local C = T.ns.Controller
    mockProfession(T)
    T.env.C_TradeSkillUI.GetBaseProfessionInfo = function() return { professionID = 164, professionName = "Forge" } end
    T.env.C_TradeSkillUI.GetAllRecipeIDs = function() return { 5, 6 } end
    T.env.C_TradeSkillUI.GetRecipeInfo = function(id)
        return { recipeID = id, name = "R" .. id, learned = true, relativeDifficulty = id == 5 and 0 or 1 }
    end
    C.onEvent("TRADE_SKILL_LIST_UPDATE")
    T.run()
    local known = T.env.CraftProfitCharDB.known
    H.eq(#known, 1)
    H.eq(known[1].key, "164")
    H.eq(known[1].name, "Forge")
    H.eq(#known[1].recipes, 2)
    -- a second update right after does not read again
    T.env.C_TradeSkillUI.GetAllRecipeIDs = function() return { 5 } end
    C.onEvent("TRADE_SKILL_LIST_UPDATE")
    T.run()
    H.eq(#T.env.CraftProfitCharDB.known[1].recipes, 2)
    -- later it does
    T.clock = T.clock + 10
    C.onEvent("TRADE_SKILL_LIST_UPDATE")
    T.run()
    H.eq(#T.env.CraftProfitCharDB.known[1].recipes, 1)
    -- a closed window reads nothing
    T.clock = T.clock + 10
    T.env.ProfessionsFrame.IsShown = function() return false end
    H.eq(C.refreshKnown(), false)
end)

H.test("the leveling data ranks the known recipes by cost per point, hides grey ones by default", function()
    local T = boot()
    local C = T.ns.Controller
    stock(T)
    -- the reagents cost more than the output is worth: every craft loses money
    T.ns.Prices.store(C.market(), 1, 500, 10, 1699999940)
    T.ns.DB.setKnown(T.env.CraftProfitCharDB, "164", "Forge", {
        raw(1, 1), raw(2, 0), raw(3, 3), raw(4, 2),
    }, 1700000000)
    local data = C.levelData()
    H.eq(data.profession.name, "Forge")
    H.eq(data.hiddenGrey, 1)
    local ids = {}
    for i, item in ipairs(data.items) do ids[i] = item.recipe.recipeID end
    -- the same loss per craft, so the likeliest point (orange, then yellow, then green) is the cheapest
    H.eq(ids, { 2, 1, 4 })
    C.setLevelShowGrey(true)
    data = C.levelData()
    H.eq(#data.items, 4)
    H.eq(data.hiddenGrey, 0)
    H.eq(data.items[#data.items].recipe.recipeID, 3)
end)

H.test("a grey learned recipe is stored when the profession is read, hidden by default and listed on request", function()
    local T = boot()
    local C = T.ns.Controller
    mockProfession(T)
    T.env.C_TradeSkillUI.GetBaseProfessionInfo = function() return { professionID = 164, professionName = "Forge" } end
    T.env.C_TradeSkillUI.GetAllRecipeIDs = function() return { 5, 6 } end
    T.env.C_TradeSkillUI.GetRecipeInfo = function(id)
        return { recipeID = id, name = "R" .. id, learned = true, relativeDifficulty = id == 5 and 3 or 1 }
    end
    C.onEvent("TRADE_SKILL_LIST_UPDATE")
    T.run()
    H.eq(#T.env.CraftProfitCharDB.known[1].recipes, 2)
    local data = C.levelData()
    H.eq(data.hiddenGrey, 1)
    H.eq(#data.items, 1)
    H.eq(data.items[1].recipe.recipeID, 6)
    C.setLevelShowGrey(true)
    data = C.levelData()
    H.eq(#data.items, 2)
    H.eq(data.hiddenGrey, 0)
end)

H.test("the leveling window lists the recipes, opens with /cp level and selecting one shows it", function()
    local T = boot()
    local C = T.ns.Controller
    stock(T)
    T.ns.DB.setKnown(T.env.CraftProfitCharDB, "164", "Forge", { raw(1, 1), raw(2, 0) }, 1700000000)
    H.falsy(T.ns.LevelingUI.isShown())
    T.env.SlashCmdList.CRAFTPROFIT("level")
    H.truthy(T.ns.LevelingUI.isShown())
    T.env.SlashCmdList.CRAFTPROFIT("level")
    H.falsy(T.ns.LevelingUI.isShown())
    T.ns.LevelingUI.show()
    C.selectKnown(T.env.CraftProfitCharDB.known[1].recipes[2])
    H.eq(C.currentRecipeID(), 2)
    H.truthy(T.ns.Window.isShown())
    C.nextLevelProfession()
    T.ns.LevelingUI.refresh()
end)

H.test("with nothing known the leveling window says so and cycling professions is harmless", function()
    local T = boot()
    T.ns.LevelingUI.show()
    T.ns.Controller.nextLevelProfession()
    H.eq(T.ns.Controller.levelData().profession, nil)
    H.eq(#T.ns.Controller.levelData().items, 0)
end)

H.test("the leveling window opens beside the main window, or at the saved position once moved", function()
    local T = boot()
    local frame = T.ns.LevelingUI.frame()
    local points = {}
    frame.SetPoint = function(_, ...) points[#points + 1] = { ... } end
    local main = T.ns.Window.frame()
    T.ns.Window.show()
    T.ns.LevelingUI.show()
    H.eq(points[#points][1], "TOPLEFT")
    H.truthy(points[#points][2] == main)
    H.eq(points[#points][3], "TOPRIGHT")
    T.ns.LevelingUI.hide()
    T.ns.Window.hide()
    T.ns.LevelingUI.show()
    H.eq(points[#points][1], "CENTER")
    T.ns.LevelingUI.hide()
    T.ns.LevelingUI.attach({ x = 120, y = 640 })
    T.ns.Window.show()
    T.ns.LevelingUI.show()
    H.eq(points[#points], { "TOPLEFT", T.env.UIParent, "BOTTOMLEFT", 120, 640 })
end)

H.test("the leveling window switches between the cost sort and the speed sort and remembers it", function()
    local T = boot()
    local C = T.ns.Controller
    stock(T)
    T.ns.Prices.store(C.market(), 1, 500, 10, 1699999940)
    T.ns.DB.setKnown(T.env.CraftProfitCharDB, "164", "Forge", { raw(1, 1), raw(2, 0), raw(4, 2) }, 1700000000)
    H.eq(C.levelData().sort, "cost")
    C.toggleLevelSort()
    H.eq(T.env.CraftProfitDB.settings.levelSort, "speed")
    local ids = {}
    for i, item in ipairs(C.levelData().items) do ids[i] = item.recipe.recipeID end
    H.eq(ids, { 2, 1, 4 })    -- orange (100%), yellow (75%), green (25%)
    C.toggleLevelSort()
    H.eq(C.levelData().sort, "cost")
    T.ns.LevelingUI.show()
    C.toggleLevelSort()
end)

H.test("clicking the crafted item searches it at the AH without a quantity preset", function()
    local T = boot()
    local C = T.ns.Controller
    local calls = {}
    T.ns.AH.isOpen = true
    T.ns.AH.browse = function(name, itemID, qty) calls[#calls + 1] = { name, itemID, qty }; return true end
    C.setRecipe(T.ns.Recipes.normalize(RAW), "profession")
    C.onOutputClick()
    H.eq(calls, { { "Item100", 100, nil } })
end)

H.test("clicking the crafted item with the AH closed says so and searches nothing", function()
    local T = boot()
    local C = T.ns.Controller
    local calls = 0
    T.ns.AH.browse = function() calls = calls + 1; return true end
    C.setRecipe(T.ns.Recipes.normalize(RAW), "profession")
    C.onOutputClick()
    H.eq(calls, 0)
    H.truthy(table.concat(T.chat, "\n"):find("Open the auction house first", 1, true))
end)

H.test("clicking a bind-on-pickup crafted item says it cannot be sold", function()
    local T = boot({ items = { [100] = { quality = 2, ilvl = 15, sellPrice = 200, classID = 0, bindType = 1 } } })
    local C = T.ns.Controller
    local calls = 0
    T.ns.AH.isOpen = true
    T.ns.AH.browse = function() calls = calls + 1; return true end
    C.setRecipe(T.ns.Recipes.normalize(RAW), "profession")
    C.onOutputClick()
    H.eq(calls, 0)
    H.truthy(table.concat(T.chat, "\n"):find("cannot be sold at the auction house", 1, true))
end)

H.test("clicking the crafted item before its name is loaded says so and searches nothing", function()
    local T = boot({ items = {} })
    local C = T.ns.Controller
    local calls = 0
    T.ns.AH.isOpen = true
    T.ns.AH.browse = function() calls = calls + 1; return true end
    C.setRecipe(T.ns.Recipes.normalize(RAW), "profession")
    C.onOutputClick()
    H.eq(calls, 0)
    H.truthy(table.concat(T.chat, "\n"):find("Item not loaded yet", 1, true))
end)

H.test("clicking with no recipe shown, or when the AH cannot browse, does not raise and says what is wrong", function()
    local T = boot()
    local C = T.ns.Controller
    T.ns.AH.isOpen = true
    local before = #T.chat
    C.onOutputClick()
    H.eq(#T.chat, before)
    T.ns.AH.browse = function() return false, "unavailable" end
    C.setRecipe(T.ns.Recipes.normalize(RAW), "profession")
    C.onOutputClick()
    H.truthy(table.concat(T.chat, "\n"):find("The auction house search is not available", 1, true))
end)

H.test("the window is given the output click handler", function()
    local T = boot()
    H.truthy(T.ns.Window.lastHandlers.onOutputClick)
    H.eq(T.ns.Window.lastHandlers.onOutputClick, T.ns.Controller.onOutputClick)
end)

H.test("an old save's colour theme is dropped at login", function()
    local T = W.boot(H, { items = ITEMS })
    T.env.CraftProfitDB = { settings = { theme = "copper" } }
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    H.eq(T.env.CraftProfitDB.settings.theme, nil)
end)

H.test("the removed theme command only prints the help (in French)", function()
    local T = boot({ locale = "frFR", items = ITEMS })
    T.env.SlashCmdList.CRAFTPROFIT("theme copper")
    H.truthy(T.chat[#T.chat]:find(T.ns.L.SLASH_HELP, 1, true))
    H.truthy(T.chat[#T.chat]:find("Commandes", 1, true))
    H.falsy(T.chat[#T.chat]:find("theme", 1, true))
    H.eq(T.env.CraftProfitDB.settings.theme, nil)
end)

-- Appearance ------------------------------------------------------------------------

H.test("the saved appearance is applied before the main window is built", function()
    local T = W.boot(H, { items = ITEMS })
    T.env.CraftProfitDB = { settings = { appearance = { header = "c", tile = "a" } } }
    local Native, seen = T.ns.Native, nil
    local create = T.ns.Window.create
    T.ns.Window.create = function(...)
        seen = { Native.appearance() }
        return create(...)
    end
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    H.eq(seen, { "c", "a" })
    -- The main window's own tiles were built with that card.
    H.eq(T.ns.Window.parts.tiles[1].variant, "a")
end)

H.test("a bad saved appearance falls back to b b at login", function()
    local T = W.boot(H, { items = ITEMS })
    T.env.CraftProfitDB = { settings = { appearance = { header = "x", tile = {} } } }
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    H.eq({ T.ns.Native.appearance() }, { "b", "b" })
    H.eq(T.env.CraftProfitDB.settings.appearance, { header = "b", tile = "b" })
end)

H.test("setAppearance applies and saves each part, nil keeps it, and says whether anything changed", function()
    local T = boot()
    local C, Native = T.ns.Controller, T.ns.Native
    local saved = function() return T.env.CraftProfitDB.settings.appearance end
    H.eq(C.setAppearance("a", nil), true)
    H.eq({ Native.appearance() }, { "a", "b" })
    H.eq(saved(), { header = "a", tile = "b" })
    H.eq(C.setAppearance(nil, "a"), true)
    H.eq({ Native.appearance() }, { "a", "a" })
    H.eq(saved(), { header = "a", tile = "a" })
    -- The tiles already built follow at once.
    H.eq(T.ns.Window.parts.tiles[1].variant, "a")
    H.eq(C.setAppearance("a", "a"), false)
    H.eq(C.setAppearance(nil, nil), false)
    H.eq(C.setAppearance("c", "b"), true)
    H.eq(saved(), { header = "c", tile = "b" })
end)

H.test("setAppearance refuses an unknown key and changes nothing", function()
    local T = boot()
    local C, Native = T.ns.Controller, T.ns.Native
    for _, args in ipairs({ { "z", "a" }, { "a", "c" }, { 1, nil }, { nil, {} }, { "A", nil } }) do
        H.eq(C.setAppearance(args[1], args[2]), false)
        H.eq({ Native.appearance() }, { "b", "b" })
        H.eq(T.env.CraftProfitDB.settings.appearance, { header = "b", tile = "b" })
    end
end)

H.test("the saved keys and the native variants are the same sets", function()
    local T = boot()
    local DB, Native = T.ns.DB, T.ns.Native
    for key in pairs(Native.HEADER_VARIANTS) do H.truthy(DB.HEADER_KEYS[key]) end
    for key in pairs(DB.HEADER_KEYS) do H.truthy(Native.HEADER_VARIANTS[key]) end
    for key in pairs(Native.TILE_VARIANTS) do H.truthy(DB.TILE_KEYS[key]) end
    for key in pairs(DB.TILE_KEYS) do H.truthy(Native.TILE_VARIANTS[key]) end
    H.truthy(Native.HEADER_VARIANTS[DB.DEFAULTS.appearance.header])
    H.truthy(Native.TILE_VARIANTS[DB.DEFAULTS.appearance.tile])
end)

H.test("the slash help lists options, pins and minimap in every language", function()
    for _, locale in ipairs({ "enUS", "frFR", "esES" }) do
        local T = boot({ locale = locale, items = ITEMS })
        T.env.SlashCmdList.CRAFTPROFIT("nope")
        local help = T.chat[#T.chat]
        H.truthy(help:find("| options |", 1, true))
        H.truthy(help:find("| pins |", 1, true))
        H.truthy(help:find("| minimap |", 1, true))
    end
end)

H.test("/cp show and /cp hide go through the controller's main window functions", function()
    local T = boot()
    local slash = T.env.SlashCmdList.CRAFTPROFIT
    slash("show")
    H.truthy(T.ns.Window.isShown())
    slash("hide")
    H.falsy(T.ns.Window.isShown())
    T.ns.Controller.toggleMainWindow()
    H.truthy(T.ns.Window.isShown())
    T.ns.Controller.toggleMainWindow()
    H.falsy(T.ns.Window.isShown())
end)

H.test("setAppearance saves the saved choice merged with the new part, not what is on screen", function()
    local T = boot()
    local C, Native = T.ns.Controller, T.ns.Native
    -- Something drew another look without saving it (a developer preview).
    Native.setTileVariant("a")
    H.eq(C.setAppearance("c", nil), true)
    H.eq(T.env.CraftProfitDB.settings.appearance, { header = "c", tile = "b" })
    -- And the screen is brought back to the saved choice.
    H.eq({ Native.appearance() }, { "c", "b" })
    Native.setHeaderVariant("a")
    H.eq(C.setAppearance(nil, nil), false)
    H.eq({ Native.appearance() }, { "c", "b" })
end)


-- Pinned window data ---------------------------------------------------------------

local function pinRaw(id, output)
    return { recipeID = id, name = "P" .. id, difficulty = "easy", outputItemID = output, qtyMin = 1, qtyMax = 1,
        reagents = { { itemID = 1, qty = 2 }, { itemID = 2, qty = 1 } } }
end

H.test("pinsData lists the pins in the pinned list's order", function()
    local T = boot({ items = { [100] = ITEMS[100], [101] = { quality = 1, ilvl = 1, sellPrice = 10, classID = 0, bindType = 2 } } })
    local C, DB = T.ns.Controller, T.ns.DB
    stock(T)
    DB.pinAdd(T.env.CraftProfitCharDB, pinRaw(1, 101))
    DB.pinAdd(T.env.CraftProfitCharDB, pinRaw(2, 100))
    local data = C.pinsData()
    local ids = {}
    for i, item in ipairs(data.items) do ids[i] = item.recipe.recipeID end
    -- Recipe 2 sells at a profit, recipe 1 has no price for its output.
    H.eq(ids, { 2, 1 })
    H.eq(data.byPoint, false)
    H.truthy(data.items[1].result.net > 0)
    local expected = T.ns.PinsUI.orderedPins(T.env.CraftProfitCharDB.pins, "net", C.evaluate)
    H.eq(data.items[1].recipe, expected[1].recipe)
    C.toggleSort()
    H.eq(C.pinsData().byPoint, true)
end)

H.test("the pinned age is the oldest price the pins use, searched or scanned, never the scan time alone", function()
    local T = boot()
    local C, DB, P = T.ns.Controller, T.ns.DB, T.ns.Prices
    -- No pin, no price: never priced, stale.
    local data = C.pinsData()
    H.eq(data.ageText, "Prices: never scanned")
    H.eq(data.stale, true)
    DB.pinAdd(T.env.CraftProfitCharDB, pinRaw(1, 100))
    data = C.pinsData()
    H.eq(data.ageText, "Prices: never scanned")
    H.eq(data.stale, true)
    -- Prices from "Search prices" only (no full scan): their age counts.
    P.store(C.market(), 1, 100, 10, 1700000000 - 60)
    P.store(C.market(), 100, 1000, 10, 1700000000 - 300)
    H.eq(C.market().snapshotTime, nil)
    data = C.pinsData()
    H.eq(data.ageText, "Prices: 5m ago")
    H.eq(data.stale, false)
    -- The same text as the main window's line for that recipe.
    C.selectPin(1)
    H.eq(T.ns.Window.lastModel.ageText, data.ageText)
    -- A recent full scan does not hide an old price of a pin.
    C.market().snapshotTime = 1700000000 - 10
    P.store(C.market(), 2, 50, 10, 1700000000 - 7200)
    data = C.pinsData()
    H.eq(data.ageText, "Prices: 2h ago")
    H.eq(data.stale, true)
    -- Oldest over every pin.
    DB.pinAdd(T.env.CraftProfitCharDB, { recipeID = 2, name = "Q", outputItemID = 100,
        reagents = { { itemID = 3, qty = 1 } } })
    P.store(C.market(), 3, 10, 10, 1700000000 - 2 * 86400)
    H.eq(C.pinsData().ageText, "Prices: 2d ago")
end)

H.test("pinsData is empty with no pin", function()
    local T = boot()
    local data = T.ns.Controller.pinsData()
    H.eq(data.items, {})
    H.eq(data.byPoint, false)
end)

H.test("unpin removes the pin, refreshes and keeps the selection", function()
    local T = boot()
    local C, DB = T.ns.Controller, T.ns.DB
    C.setRecipe(T.ns.Recipes.normalize(RAW), "profession")
    C.togglePin()
    DB.pinAdd(T.env.CraftProfitCharDB, pinRaw(9, 100))
    H.eq(T.ns.Window.lastModel.pinned, true)
    C.unpin(5)
    H.eq(DB.pinIndex(T.env.CraftProfitCharDB, 5), nil)
    H.eq(#T.env.CraftProfitCharDB.pins, 1)
    H.eq(T.ns.Window.lastModel.pinned, false)
    H.eq(C.currentRecipeID(), 5)
    -- An id that is not pinned: nothing changes, nothing raises.
    C.unpin(12345)
    H.eq(#T.env.CraftProfitCharDB.pins, 1)
end)

H.test("savePinsPosition keeps a finite position and ignores anything else", function()
    local T = boot()
    local C, settings = T.ns.Controller, T.env.CraftProfitDB.settings
    C.savePinsPosition(10, 20)
    H.eq(settings.pinsWindow, { x = 10, y = 20 })
    C.savePinsPosition(0 / 0, 5)
    C.savePinsPosition(5, math.huge)
    C.savePinsPosition("1", 2)
    C.savePinsPosition(nil, nil)
    H.eq(settings.pinsWindow, { x = 10, y = 20 })
end)

H.test("/cp pins toggles the pinned window, whatever the case, without touching the main window", function()
    local T = boot()
    local slash = T.env.SlashCmdList.CRAFTPROFIT
    H.falsy(T.ns.PinnedWindow.isShown())
    slash("pins")
    H.truthy(T.ns.PinnedWindow.isShown())
    H.falsy(T.ns.Window.isShown())
    slash("PINS")
    H.falsy(T.ns.PinnedWindow.isShown())
    -- No help line: it is a known command.
    H.eq(#T.chat, 0)
end)

H.test("the tooltip and the minimap click line are translated in French and Spanish", function()
    for locale, words in pairs({ frFR = "recettes épinglées", esES = "recetas fijadas" }) do
        local T = boot({ locale = locale, items = ITEMS })
        local L = T.ns.L
        H.truthy(L.MINIMAP_TIP_RIGHT:find(words, 1, true))
        H.eq(L.CMD_PINS, words)
    end
end)


-- Default placement --------------------------------------------------------------------

-- Gives a window a measured box (left edge and top in screen pixels).
local function measure(f, left, top, width)
    f.GetRight = function() return left + width end
    f.GetTop = function() return top end
end

local function lastPoint(f) return f.points[#f.points] end

local function recordPoints(f)
    f.points = {}
    f.SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end
end

H.test("besidePosition is just right of the rightmost shown CraftProfit window, never the window itself", function()
    local T = boot()
    local C = T.ns.Controller
    H.eq(C.besidePosition(nil), nil)
    local main = T.ns.Window.frame()
    measure(main, 100, 800, 372)
    T.ns.Window.show()
    H.eq({ C.besidePosition(nil) }, { 478, 800 })
    -- Its own box does not count.
    H.eq(C.besidePosition(main), nil)
    T.ns.LevelingUI.show()
    local level = T.ns.LevelingUI.frame()
    measure(level, 478, 790, 396)
    H.eq({ C.besidePosition(nil) }, { 880, 790 })
    H.eq({ C.besidePosition(level) }, { 478, 800 })
    T.ns.LevelingUI.hide()
    H.eq({ C.besidePosition(nil) }, { 478, 800 })
end)

H.test("without a saved place the pinned, leveling and options windows open beside the rightmost one", function()
    local T = boot()
    local main = T.ns.Window.frame()
    measure(main, 100, 800, 372)
    T.ns.Window.show()
    T.ns.PinnedWindow.show()
    local pinned = T.ns.PinnedWindow.frame()
    recordPoints(pinned)
    T.ns.PinnedWindow.place()
    H.eq(lastPoint(pinned), { "TOPLEFT", T.env.UIParent, "BOTTOMLEFT", 478, 800 })
    measure(pinned, 478, 800, 396)
    local level = T.ns.LevelingUI.frame()
    recordPoints(level)
    T.ns.LevelingUI.show()
    H.eq(lastPoint(level), { "TOPLEFT", T.env.UIParent, "BOTTOMLEFT", 880, 800 })
    T.ns.OptionsUI.show()
    local options = T.ns.OptionsUI.frame()
    recordPoints(options)
    T.ns.OptionsUI.place()
    H.eq(lastPoint(options), { "TOPLEFT", T.env.UIParent, "BOTTOMLEFT", 880, 800 })
    -- A saved position always wins.
    T.ns.PinnedWindow.attach({ x = 5, y = 600 })
    H.eq(lastPoint(pinned), { "TOPLEFT", T.env.UIParent, "BOTTOMLEFT", 5, 600 })
    -- None shown (or none measured): today's defaults.
    T.ns.Window.hide()
    T.ns.LevelingUI.hide()
    T.ns.OptionsUI.hide()
    T.ns.PinnedWindow.attach(nil)
    H.eq(lastPoint(pinned), { "CENTER", T.env.UIParent, "CENTER", -260, 0 })
    T.ns.PinnedWindow.hide()
    T.ns.OptionsUI.place()
    H.eq(lastPoint(options), { "CENTER", T.env.UIParent, "CENTER", 0, 0 })
end)

H.test("the main window without a saved place opens beside a shown CraftProfit window, else beside the trade window", function()
    local T = boot()
    local C = T.ns.Controller
    local main = T.ns.Window.frame()
    recordPoints(main)
    T.ns.PinnedWindow.show()
    measure(T.ns.PinnedWindow.frame(), 200, 700, 396)
    C.showMainWindow()
    H.eq(lastPoint(main), { "TOPLEFT", T.env.UIParent, "BOTTOMLEFT", 602, 700 })
    T.ns.Window.hide()
    T.ns.PinnedWindow.hide()
    C.showMainWindow()
    H.eq(lastPoint(main), { "CENTER", T.env.UIParent, "CENTER", 300, 0 })
    -- A saved position wins.
    T.ns.Window.hide()
    T.ns.PinnedWindow.show()
    T.env.CraftProfitDB.settings.window = { point = "TOPLEFT", x = 7, y = 500 }
    C.showMainWindow()
    H.eq(lastPoint(main), { "TOPLEFT", T.env.UIParent, "BOTTOMLEFT", 7, 500 })
    -- Selecting a recipe from the profession window places it the same way.
    T.ns.Window.hide()
    T.env.CraftProfitDB.settings.window = nil
    C.setRecipe(T.ns.Recipes.normalize(RAW), "profession")
    H.eq(lastPoint(main), { "TOPLEFT", T.env.UIParent, "BOTTOMLEFT", 602, 700 })
end)

H.test("every window keeps the least height the border needs", function()
    local T = W.boot(H, { items = ITEMS })
    T.ns.Native.MIN_WINDOW_H = 2000
    local create = T.env.CreateFrame
    T.env.CreateFrame = function(...)
        local f = create(...)
        f.SetSize = function(self, _, h) self.height = h end
        return f
    end
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    local C = T.ns.Controller
    C.showMainWindow()
    H.eq(T.ns.Window.frame().height, 2000)
    T.ns.LevelingUI.show()
    H.eq(T.ns.LevelingUI.frame().height, 2000)
    T.ns.PinnedWindow.show()
    H.eq(T.ns.PinnedWindow.frame().height, 2000)
    T.ns.OptionsUI.show()
    H.eq(T.ns.OptionsUI.frame().height, 2000)
    -- With a recipe the main window still never goes below it.
    C.setRecipe(T.ns.Recipes.normalize(RAW), "profession")
    H.eq(T.ns.Window.frame().height, 2000)
end)

H.test("besidePosition measures a window from its left edge and width when the client gives no right edge", function()
    local T = boot()
    local C = T.ns.Controller
    T.ns.PinnedWindow.show()
    local pinned = T.ns.PinnedWindow.frame()
    pinned.GetRight = function() return nil end
    pinned.GetLeft = function() return 200 end
    pinned.GetWidth = function() return 396 end
    pinned.GetTop = function() return nil end
    pinned.GetBottom = function() return 300 end
    pinned.GetHeight = function() return 400 end
    H.eq({ C.besidePosition(nil) }, { 602, 700 })
    -- Nothing measurable at all: no position, the caller keeps its default.
    pinned.GetLeft = function() return nil end
    H.eq(C.besidePosition(nil), nil)
end)

H.test("the main window opens beside a shown CraftProfit window even with the trade window open, else beside the trade window", function()
    local T = boot()
    local C = T.ns.Controller
    local main = T.ns.Window.frame()
    recordPoints(main)
    local trade = W.frame()
    T.ns.Trade.frame = function() return trade end
    C.showMainWindow()
    H.eq(lastPoint(main), { "TOPLEFT", trade, "TOPRIGHT", 6, 0 })
    T.ns.Window.hide()
    T.ns.PinnedWindow.show()
    measure(T.ns.PinnedWindow.frame(), 200, 700, 396)
    C.showMainWindow()
    H.eq(lastPoint(main), { "TOPLEFT", T.env.UIParent, "BOTTOMLEFT", 602, 700 })
end)

-- Names follow the game's language
local function frenchPin(T, items)
    local pin = T.ns.Recipes.normalize({
        recipeID = 3398, name = "Côtelettes de lion épicées", locale = "frFR", outputItemID = 3727,
        reagents = { { itemID = 1, qty = 1 } },
    })
    T.ns.DB.pinAdd(T.env.CraftProfitCharDB, pin)
    if items then items[3727] = { quality = 1, ilvl = 25, sellPrice = 125, classID = 0, bindType = 0 } end
    return T.env.CraftProfitCharDB.pins[1]
end

H.test("recipeName prefers the client's recipe name, then the item's, then the stored one", function()
    local items = { [100] = ITEMS[100] }
    local T = boot({ items = items })
    local C = T.ns.Controller
    local pin = frenchPin(T, nil)
    -- Nothing current is known yet: the stored name, and the item is asked for.
    H.eq(C.recipeName(pin), "Côtelettes de lion épicées")
    local asked = false
    for _, id in ipairs(T.loadRequests) do if id == 3727 then asked = true end end
    H.truthy(asked)
    -- The item arrives: its name, written back into the pin with the language.
    items[3727] = { quality = 1, ilvl = 25, sellPrice = 125, classID = 0, bindType = 0 }
    H.eq(C.recipeName(pin), "Item3727")
    H.eq(pin.name, "Item3727")
    H.eq(pin.locale, "enUS")
    -- The client's recipe name wins over everything.
    T.env.C_TradeSkillUI = { GetRecipeInfo = function(id) return { recipeID = id, name = "Hot Lion Chops" } end }
    H.eq(C.recipeName(pin), "Hot Lion Chops")
    H.eq(T.env.CraftProfitCharDB.pins[1].name, "Hot Lion Chops")
    H.eq(C.recipeName(nil), "")
end)

H.test("recipeName skips a client recipe name that is secret, empty, not a string or raising", function()
    local items = {}
    local T = boot({ items = items })
    local C = T.ns.Controller
    local pin = frenchPin(T, items)
    T.env.issecretvalue = function(v) return v == "SECRET" end
    for _, bad in ipairs({ "SECRET", "", 5 }) do
        T.env.C_TradeSkillUI = { GetRecipeInfo = function() return { name = bad } end }
        H.eq(C.recipeName(pin), "Item3727")
    end
    T.env.C_TradeSkillUI = { GetRecipeInfo = function() error("boom") end }
    H.eq(C.recipeName(pin), "Item3727")
    T.env.C_TradeSkillUI = { GetRecipeInfo = function() return "not a table" end }
    H.eq(C.recipeName(pin), "Item3727")
end)

H.test("the main window title follows the game's language and the item load refreshes it", function()
    local items = { [100] = ITEMS[100] }
    local T = boot({ items = items })
    local C = T.ns.Controller
    frenchPin(T, nil)
    C.selectPin(3398)
    H.eq(T.ns.Window.lastModel.title, "Côtelettes de lion épicées")
    items[3727] = { quality = 1, ilvl = 25, sellPrice = 125, classID = 0, bindType = 0 }
    C.onEvent("ITEM_DATA_LOAD_RESULT", 3727, true)
    T.run()
    H.eq(T.ns.Window.lastModel.title, "Item3727")
end)

H.test("/cp history lists tracked recipes by their current-language name", function()
    local items = {}
    local T = boot({ items = items })
    local C = T.ns.Controller
    C.selectPin(frenchPin(T, items).recipeID)
    T.ns.Window.lastHandlers.onTrackToggle(true)
    C.historyCommand("")
    H.eq(T.chat[#T.chat], "|cff66ccffCraftProfit|r 1. Item3727 (tracking)")
    C.historyCommand("remove 1")
    H.eq(T.chat[#T.chat], "|cff66ccffCraftProfit|r Removed from history: Item3727")
end)

H.test("professionName reads the current-language name and writes it back, else keeps the stored one", function()
    local T = boot()
    local C = T.ns.Controller
    local prof = { key = "185", name = "Cuisine" }
    H.eq(C.professionName(prof), "Cuisine")
    T.env.GetProfessions = function() return 1 end
    T.env.GetProfessionInfo = function() return "Cooking", "icon", 60, 75, 0, 0, 185 end
    H.eq(C.professionName(prof), "Cooking")
    H.eq(prof.name, "Cooking")
    H.eq(C.professionName({ key = "185", name = "" }), "Cooking")
    H.eq(C.professionName({ key = "Forge", name = "" }), "Forge")
    H.eq(C.professionName({ key = "Forge", name = "Forge" }), "Forge")
    H.eq(C.professionName(nil), "-")
    -- A live name too long to store is not used.
    T.env.GetProfessionInfo = function() return string.rep("x", 65), "icon", 60, 75, 0, 0, 185 end
    H.eq(C.professionName(prof), "Cooking")
end)
