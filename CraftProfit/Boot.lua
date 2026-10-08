-- Entry point: wires the modules together and owns the controller.
local ADDON, ns = ...
local Util, Format, Core, Prices = ns.Util, ns.Format, ns.Core, ns.Prices
local DB, Evaluate, Present, Recipes = ns.DB, ns.Evaluate, ns.Present, ns.Recipes
local Disenchant = ns.Data.Disenchant
local L = ns.L

local Controller = {}
ns.Controller = Controller

local state = { recipe = nil, source = nil }
local requestedItems = {}
local refreshQueued = false

function Controller.say(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffCraftProfit|r " .. tostring(text))
end
local say = Controller.say

function Controller.fmt(copper)
    return Format.money(copper, GetCoinTextureString)
end

-- Item facts, or nil while the game has not loaded the item yet. The request is
-- made once per item; ITEM_DATA_LOAD_RESULT triggers the refresh.
function Controller.itemInfo(itemID)
    local _, _, quality, ilvl, _, _, _, _, _, _, sellPrice, classID, _, bindType = C_Item.GetItemInfo(itemID)
    if quality == nil then
        if not requestedItems[itemID] then
            requestedItems[itemID] = true
            C_Item.RequestLoadItemDataByID(itemID)
        end
        return nil
    end
    return { quality = quality, ilvl = ilvl, sellPrice = sellPrice, classID = classID, bindType = bindType }
end

-- Item name read secret-safely (a secret value raises when concatenated), or
-- nil while the game has not loaded the item.
function Controller.itemName(itemID)
    local ok, name = pcall(C_Item.GetItemInfo, itemID)
    if ok and type(name) == "string" then
        local fine, text = pcall(function() return name .. "" end)
        if fine and text ~= "" then return text end
    end
    Controller.itemInfo(itemID) -- not loaded yet: ask the game, the refresh follows
    return nil
end

function Controller.knowsEnchanting()
    return ns.Trade.hasProfession(ns.Trade.ENCHANTING_SKILL_LINE)
end

function Controller.evaluate(recipe)
    local settings = CraftProfitDB.settings
    return Evaluate.run({
        recipe = recipe,
        priceOf = Prices.priceOf(CraftProfitDB, time()),
        itemInfo = Controller.itemInfo,
        cut = settings.cut,
        showPerPoint = settings.showPerPoint,
        lookupDisenchant = Disenchant.lookup,
        knowsEnchanting = Controller.knowsEnchanting(),
    })
end

function Controller.currentRecipeID()
    return state.recipe and state.recipe.recipeID or nil
end

function Controller.refresh()
    local settings = CraftProfitDB.settings
    local recipe = state.recipe
    if recipe then
        local model = Present.build(Controller.evaluate(recipe), L, Controller.fmt,
            { staleAfter = settings.staleAfter, itemName = Controller.itemName })
        if type(recipe.name) == "string" and recipe.name ~= "" then
            model.title = recipe.name
        else
            model.title = Controller.itemName(recipe.outputItemID)
        end
        for _, reagent in ipairs(recipe.reagents or {}) do Controller.itemInfo(reagent.itemID) end
        model.pinned = DB.pinIndex(CraftProfitCharDB, recipe.recipeID) ~= nil
        model.showPerPoint = settings.showPerPoint
        model.costExpanded = settings.costExpanded
        ns.Window.render(model)
    else
        ns.Window.showEmpty(L.NO_RECIPE)
    end
    if ns.PinsUI then ns.PinsUI.refresh() end
end

-- Coalesces bursts (many ITEM_DATA_LOAD_RESULT events, one per search result).
function Controller.requestRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.1, function()
        refreshQueued = false
        Controller.refresh()
    end)
end

function Controller.setRecipe(recipe, source)
    state.recipe, state.source = recipe, source
    local window = ns.Window
    if not window.isShown() then
        local target = ns.Trade.frame()
        if source == "pin" then target = AuctionHouseFrame or AuctionFrame end
        window.attach(target, CraftProfitDB.settings.window)
        window.show()
    end
    Controller.refresh()
end

function Controller.selectPin(recipeID)
    local index = DB.pinIndex(CraftProfitCharDB, recipeID)
    if not index then return end
    state.recipe, state.source = CraftProfitCharDB.pins[index], "pin"
    Controller.refresh()
end

-- Pinned recipes keep the difficulty they had when pinned; the open profession
-- window knows the current one, which changes as the skill rises.
function Controller.refreshPinDifficulties()
    if not ns.Trade.isShown() then return false end
    local changed = false
    for _, pin in ipairs(CraftProfitCharDB.pins) do
        local current = ns.Trade.difficultyOf(pin.recipeID)
        if current and current ~= pin.difficulty then
            pin.difficulty = current
            changed = true
        end
    end
    if changed then Controller.requestRefresh() end
    return changed
end

-- Sorting by cost per point needs the cost per point: it switches the option on.
function Controller.setSortMode(mode)
    DB.setSortMode(CraftProfitCharDB, mode)
    if CraftProfitCharDB.sortMode == DB.SORT_POINT then
        CraftProfitDB.settings.showPerPoint = true
    end
    Controller.refresh()
end

function Controller.toggleSort()
    Controller.setSortMode(CraftProfitCharDB.sortMode == DB.SORT_POINT and DB.SORT_NET or DB.SORT_POINT)
end

function Controller.togglePin()
    local recipe = state.recipe
    if not recipe then return end
    if DB.pinIndex(CraftProfitCharDB, recipe.recipeID) then
        DB.pinRemove(CraftProfitCharDB, recipe.recipeID)
    else
        local ok, reason = DB.pinAdd(CraftProfitCharDB, recipe)
        if not ok and reason == "full" then say(L.PINS_FULL) end
    end
    Controller.refresh()
end

-- Stores the median price of an AH search result. False when nothing was listed.
function Controller.recordListings(itemID, listings)
    local unit, volume = Prices.summarize(listings, CraftProfitDB.settings.medianN)
    if unit then Prices.store(CraftProfitDB, itemID, unit, volume, time()) end
    return unit ~= nil
end

function Controller.onSnapshot(agg)
    local count = Prices.merge(CraftProfitDB, agg.result(CraftProfitDB.settings.medianN), time())
    if ns.PinsUI then ns.PinsUI.setStatus(string.format(L.SCAN_DONE, count)) end
    Controller.requestRefresh()
end

function Controller.onAHOpen(open)
    if ns.PinsUI then ns.PinsUI.onAHOpen(open) end
    local window = ns.Window
    if open then
        if not state.recipe then
            local first = CraftProfitCharDB.pins[1]
            if first then state.recipe, state.source = first, "pin" end
        end
        if not window.isShown() then
            window.attach(AuctionHouseFrame or AuctionFrame, CraftProfitDB.settings.window)
            window.show()
        end
        Controller.refresh()
    elseif state.source == "profession" then
        Controller.refresh()
    else
        state.recipe, state.source = nil, nil
        window.hide()
        -- The profession window may still be open: let the watcher report it again.
        ns.Trade.invalidate()
    end
end

-- The profession window selection changed (or the window closed).
local function onSelection(recipeID)
    if recipeID then
        local recipe = Recipes.normalize(ns.Trade.readSelected())
        if recipe then
            Controller.setRecipe(recipe, "profession")
            return
        end
    end
    if state.source == "profession" then
        -- A pinned recipe stays selected as a pin, so it is still there at the AH.
        local recipe = state.recipe
        local index = recipe and DB.pinIndex(CraftProfitCharDB, recipe.recipeID)
        if index then
            state.recipe, state.source = CraftProfitCharDB.pins[index], "pin"
        else
            state.recipe, state.source = nil, nil
        end
        if ns.AH.isOpen then
            -- The window was anchored to the profession window that just closed.
            local ahFrame = AuctionHouseFrame or AuctionFrame
            if ahFrame then ns.Window.attach(ahFrame, CraftProfitDB.settings.window) end
            Controller.refresh()
        else
            ns.Window.hide()
        end
    end
end

-- Runs a few checks inside the game's own Lua 5.1, the only place that can
-- reveal a difference with the LuaJIT used by the offline tests. The game raises
-- "Division by zero", so NaN and infinity are built from math.huge, never by
-- dividing by zero.
function Controller.selftest()
    local checks = 0
    local function check(condition, name)
        checks = checks + 1
        if not condition then error(name, 0) end
    end
    local ok, err = pcall(function()
        check(Core.sumCost({ { itemID = 1, qty = 2 } }, function() return 100 end) == 200, "Core.sumCost")
        check(Core.netSale(1000, 1, 0.05) == 950, "Core.netSale")
        check(Prices.summarize({ { unit = 10, qty = 1 }, { unit = 20, qty = 1 }, { unit = 1000, qty = 1 } }, 5) == 20,
            "Prices.summarize")
        check(Util.isFinite(math.huge - math.huge) == false, "NaN is not finite")
        check(Util.isFinite(math.huge) == false, "infinity is not finite")
        check(Format.money(nil) == "?", "Format.money(nil)")
        check(Format.money(math.huge - math.huge) == "?", "Format.money(NaN)")
        check(Format.money(12345, GetCoinTextureString) ~= "?", "coin string")
        check(string.format("%d", 5) == "5", "string.format")
        check(L.MATERIALS ~= "MATERIALS", "locale strings")
        check(Recipes.normalize({ recipeID = 1, outputItemID = 2, reagents = { { itemID = 3, qty = 1 } } }) ~= nil,
            "Recipes.normalize")
    end)
    if ok then
        say(string.format(L.SELFTEST_OK, checks))
    else
        say(string.format(L.SELFTEST_FAIL, tostring(err)))
    end
    return ok
end

function Controller.init()
    CraftProfitDB = CraftProfitDB or {}
    CraftProfitCharDB = CraftProfitCharDB or {}
    DB.initAccount(CraftProfitDB)
    DB.prune(CraftProfitDB, time())
    DB.initChar(CraftProfitCharDB)
    ns.Locale.select(GetLocale())

    ns.Window.create({
        onPinClick = Controller.togglePin,
        onPerPointToggle = function(checked)
            CraftProfitDB.settings.showPerPoint = checked and true or false
            -- The point-cost sort cannot outlive the point-cost option.
            if not checked and CraftProfitCharDB.sortMode == DB.SORT_POINT then
                DB.setSortMode(CraftProfitCharDB, DB.SORT_NET)
            end
            Controller.refresh()
        end,
        onCostToggle = function(isExpanded)
            CraftProfitDB.settings.costExpanded = isExpanded and true or false
            Controller.refresh()
        end,
        onMoved = function(point, x, y)
            CraftProfitDB.settings.window = { point = point, x = x, y = y }
        end,
    })
    if ns.PinsUI then ns.PinsUI.init(Controller) end
    ns.AH.setHandlers({
        onOpen = Controller.onAHOpen,
        onSearch = function(itemID, listings)
            if ns.PinsUI then ns.PinsUI.onSearchResults(itemID, listings) end
        end,
        onSnapshot = Controller.onSnapshot,
    })
    local ahFrame = AuctionHouseFrame or AuctionFrame
    if type(ahFrame) == "table" and type(ahFrame.IsShown) == "function" and ahFrame:IsShown() then
        ns.AH.onEvent("AUCTION_HOUSE_SHOW")
    end
    ns.Trade.watch(onSelection)
    Controller.ready = true
end

function Controller.onEvent(event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then Controller.init() end
        return
    end
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if arg1 == ADDON then say(event .. ": " .. tostring(arg2)) end
        return
    end
    if not Controller.ready then return end
    if event == "ITEM_DATA_LOAD_RESULT" then
        -- On failure the id stays marked: clearing it would re-request the item
        -- at every refresh, forever.
        if arg2 ~= false and requestedItems[arg1] then
            requestedItems[arg1] = nil
            Controller.requestRefresh()
        end
    elseif event == "TRADE_SKILL_LIST_UPDATE" then
        Controller.refreshPinDifficulties()
        ns.Trade.invalidate()
    end
end

local function slash(msg)
    if not Controller.ready then return end
    local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    local window = ns.Window
    local anchor = ns.Trade.frame() or AuctionHouseFrame or AuctionFrame
    if cmd == "show" then
        if not window.isShown() then
            window.attach(anchor, CraftProfitDB.settings.window)
            window.show()
        end
        Controller.refresh()
    elseif cmd == "hide" then
        window.hide()
    elseif cmd == "reset" then
        CraftProfitDB.settings.window = nil
        window.attach(anchor, nil)
    elseif cmd == "scan" then
        if ns.PinsUI then ns.PinsUI.scan() end
    elseif cmd == "locale" then
        ns.Locale.select(arg ~= "" and arg or GetLocale())
        Controller.refresh()
    elseif cmd == "selftest" then
        Controller.selftest()
    else
        say(L.SLASH_HELP)
    end
end

SLASH_CRAFTPROFIT1 = "/craftprofit"
SLASH_CRAFTPROFIT2 = "/cp"
SlashCmdList.CRAFTPROFIT = slash

local frame = CreateFrame("Frame")
for _, event in ipairs({
    "ADDON_LOADED", "ITEM_DATA_LOAD_RESULT", "TRADE_SKILL_LIST_UPDATE",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
}) do
    pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event, ...) Controller.onEvent(event, ...) end)
