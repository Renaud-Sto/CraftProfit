-- Entry point: the controller's init, the events, the slash commands, the self-test and the
-- addon compartment entry (the controller's functions: Controller/*.lua, in TOC order before it).
local ADDON, ns = ...
local Util, Format, Core, Prices = ns.Util, ns.Format, ns.Core, ns.Prices
local DB, Recipes, History = ns.DB, ns.Recipes, ns.History
local L = ns.L

local Controller = ns.Controller
local say = Controller.say
local coinString = Controller._coinString
local requestedItems = Controller._requestedItems
local onSelection = Controller._onSelection

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
        check(Format.money(12345, coinString) ~= "?", "coin string")
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
    History.sanitize(CraftProfitDB, time())
    DB.prune(CraftProfitDB, time())
    DB.initChar(CraftProfitCharDB)
    ns.Locale.select(GetLocale())
    -- The saved look, before any window is built (sanitised by DB.initAccount).
    local appearance = CraftProfitDB.settings.appearance
    ns.Native.setHeaderVariant(appearance.header)
    ns.Native.setTileVariant(appearance.tile)

    ns.Window.create({
        onPinClick = Controller.togglePin,
        onRefreshRecipe = Controller.refreshRecipe,
        onReagentClick = Controller.onReagentClick,
        onOutputClick = Controller.onOutputClick,
        itemName = Controller.itemName,
        -- The history indicators' tooltips.
        historyData = Controller.historyData,
        fmt = Controller.fmt,
        onCraftsChange = Controller.setCrafts,
        onTrackToggle = Controller.setTracking,
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
    if ns.LevelingUI then
        ns.LevelingUI.init(Controller, {
            onMoved = function(_, x, y) Controller.saveLevelPosition(x, y) end,
        })
        ns.LevelingUI.attach(CraftProfitDB.settings.levelWindow)
    end
    -- Nothing is built here either: the pinned window is made on first open.
    if ns.PinnedWindow then
        ns.PinnedWindow.init(Controller, {
            onMoved = function(_, x, y) Controller.savePinsPosition(x, y) end,
        })
        ns.PinnedWindow.attach(CraftProfitDB.settings.pinsWindow)
    end
    -- Nor the history window.
    if ns.HistoryWindow then
        ns.HistoryWindow.init(Controller, {
            onMoved = function(_, x, y) Controller.saveHistoryPosition(x, y) end,
        })
        ns.HistoryWindow.attach(CraftProfitDB.settings.historyWindow)
    end
    -- Nothing is built here: the options window is made on first open.
    if ns.OptionsUI then
        ns.OptionsUI.init(Controller)
        ns.OptionsUI.attach(CraftProfitDB.settings.optionsWindow)
    end
    -- Nothing is built here: the tags attach to the profession window's list when it shows.
    if ns.RecipeRows then ns.RecipeRows.init(Controller) end
    -- After the windows exist; makes nothing while the player keeps the button hidden.
    if ns.MinimapButton then ns.MinimapButton.apply() end
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
            -- Names, icons, bound or disenchant status of a history item may change.
            Controller.historyChanged()
            Controller.requestRefresh()
        end
    elseif event == "TRADE_SKILL_LIST_UPDATE" then
        Controller.refreshPinDifficulties()
        Controller.refreshKnown()
        ns.Trade.invalidate()
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
        Controller.onProfessionChanged()
    end
end

local function slash(msg)
    if not Controller.ready then return end
    local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    local window = ns.Window
    local anchor = ns.Trade.frame() or AuctionHouseFrame or AuctionFrame
    if cmd == "show" then
        Controller.showMainWindow()
    elseif cmd == "hide" then
        Controller.hideMainWindow()
    elseif cmd == "options" then
        if ns.OptionsUI then ns.OptionsUI.toggle() end
    elseif cmd == "minimap" then
        Controller.minimapCommand()
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
    elseif cmd == "history" then
        Controller.historyCommand(arg)
    elseif cmd == "level" then
        if ns.LevelingUI then ns.LevelingUI.toggle() end
    elseif cmd == "pins" then
        if ns.PinnedWindow then ns.PinnedWindow.toggle() end
    elseif cmd == "market" then
        local name = type(GetRealmName) == "function" and GetRealmName() or "?"
        say(string.format(L.MARKET_INFO, tostring(name), Controller.marketKey()))
    else
        say(L.SLASH_HELP)
    end
end

-- The addon compartment entry (TOC AddonCompartmentFunc): the game calls it with the
-- addon's name and the mouse button. Left: options window; right: pinned window.
function CraftProfit_OnCompartmentClick(_, mouseButton)
    if not Controller.ready then return end
    if mouseButton == "RightButton" then
        if ns.PinnedWindow then ns.PinnedWindow.toggle() end
    elseif ns.OptionsUI then
        ns.OptionsUI.toggle()
    end
end

SLASH_CRAFTPROFIT1 = "/craftprofit"
SLASH_CRAFTPROFIT2 = "/cp"
SlashCmdList.CRAFTPROFIT = slash

local frame = CreateFrame("Frame")
for _, event in ipairs({
    "ADDON_LOADED", "ITEM_DATA_LOAD_RESULT", "TRADE_SKILL_LIST_UPDATE",
    "TRADE_SKILL_SHOW", "TRADE_SKILL_DATA_SOURCE_CHANGED",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
}) do
    pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event, ...) Controller.onEvent(event, ...) end)
