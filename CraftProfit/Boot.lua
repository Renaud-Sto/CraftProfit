-- Entry point: the controller's init, the events, the slash commands, the self-test and the
-- addon compartment entry (the controller's functions: Controller/*.lua, in TOC order before it).
local ADDON, ns = ...
local Util, Format, Core, Prices = ns.Util, ns.Format, ns.Core, ns.Prices
local DB, Evaluate, Present, Recipes = ns.DB, ns.Evaluate, ns.Present, ns.Recipes
local History, Leveling = ns.History, ns.Leveling
local L = ns.L

local Controller = ns.Controller
local say = Controller.say
local coinString = Controller._coinString
local requestedItems = Controller._requestedItems

local state = { recipe = nil, source = nil, crafts = 1 }

-- A reagent was clicked in the window: search it at the AH, quantity preset.
function Controller.onReagentClick(itemID, qty)
    if not ns.AH.isOpen then
        say(L.SEARCH_NEED_AH)
        return
    end
    local name = Controller.itemName(itemID)
    if not name then
        say(L.ITEM_NOT_LOADED)
        return
    end
    local ok = ns.AH.browse(name, itemID, qty)
    if not ok then say(L.BROWSE_UNAVAILABLE) end
end

-- The AH tile or the title of the window was clicked: search the crafted item at the AH
-- (no quantity preset), to see how many are for sale next to the price shown.
function Controller.onOutputClick()
    local recipe = state.recipe
    if not recipe or not recipe.outputItemID then return end
    if not ns.AH.isOpen then
        say(L.SEARCH_NEED_AH)
        return
    end
    local itemID = recipe.outputItemID
    -- Same rule as Evaluate: an item bound when picked up cannot be auctioned.
    if Evaluate.isBindOnPickup(Controller.itemInfo(itemID)) then
        say(L.SEARCH_UNSELLABLE)
        return
    end
    local name = Controller.itemName(itemID)
    if not name then
        say(L.ITEM_NOT_LOADED)
        return
    end
    if not ns.AH.browse(name, itemID, nil) then say(L.BROWSE_UNAVAILABLE) end
end

-- The multiplier belongs to one recipe: selecting another one starts again at 1.
local function choose(recipe, source)
    if not (state.recipe and recipe and state.recipe.recipeID == recipe.recipeID) then state.crafts = 1 end
    state.recipe, state.source = recipe, source
end

function Controller.setCrafts(value)
    state.crafts = Evaluate.craftCount(value)
    Controller.refresh()
end

function Controller.currentRecipeID()
    return state.recipe and state.recipe.recipeID or nil
end

local function refreshAll()
    local settings = CraftProfitDB.settings
    local recipe = state.recipe
    if recipe then
        local model = Present.build(Controller.evaluate(recipe, state.crafts), L, Controller.fmt,
            { staleAfter = settings.staleAfter, itemName = Controller.itemName })
        model.title = Controller.recipeName(recipe)
        for _, reagent in ipairs(recipe.reagents or {}) do Controller.itemInfo(reagent.itemID) end
        model.pinned = DB.pinIndex(CraftProfitCharDB, recipe.recipeID) ~= nil
        model.tracked = History.isActive(CraftProfitDB, recipe.recipeID)
        model.history = model.tracked and Controller.windowHistory(recipe.recipeID) or nil
        model.showPerPoint = settings.showPerPoint
        model.costExpanded = settings.costExpanded
        ns.Window.render(model)
    else
        ns.Window.showEmpty(L.NO_RECIPE)
    end
    if ns.PinsUI then ns.PinsUI.refresh() end
    if ns.LevelingUI then ns.LevelingUI.refresh() end
    if ns.PinnedWindow then ns.PinnedWindow.refresh() end
    if ns.HistoryWindow then ns.HistoryWindow.refresh() end
    if ns.OptionsUI then ns.OptionsUI.refresh() end
end

-- Every view, in one refresh pass.
function Controller.refresh()
    Controller.inPass(refreshAll)
end

-- Coalesces bursts (many ITEM_DATA_LOAD_RESULT events, one per search result). While a
-- price search runs, each answered item asks for a refresh: they are coalesced over about
-- a second instead (the values still move, less often). A request at the usual pace does
-- not wait for a slower one already queued (the search just ended): it replaces it.
local REFRESH_DELAY, SEARCH_REFRESH_DELAY = 0.1, 1
local refreshQueued, refreshToken = nil, 0

function Controller.requestRefresh()
    local searching = ns.PinsUI and ns.PinsUI.state == "running"
    local delay = searching and SEARCH_REFRESH_DELAY or REFRESH_DELAY
    if refreshQueued and refreshQueued <= delay then return end
    refreshToken = refreshToken + 1
    local token = refreshToken
    refreshQueued = delay
    C_Timer.After(delay, function()
        if token ~= refreshToken then return end
        refreshQueued = nil
        Controller.refresh()
    end)
end

-- Default placement: a window without a saved position opens with its top left corner
-- 6 px right of the shown CraftProfit window that reaches furthest right (itself excluded),
-- so the windows never open on top of each other. Returns x, y (TOPLEFT against UIParent's
-- BOTTOMLEFT: absolute, so no window is ever anchored to another that depends on it), or
-- nil when no such window is shown and measured: the caller keeps its own default.
local BESIDE_GAP = 6

-- A number the frame answers through `method`, or nil (missing method, no answer).
local function ask(f, method)
    local fn = f[method]
    if type(fn) ~= "function" then return nil end
    local v = fn(f)
    return Util.isFinite(v) and v or nil
end

-- The right edge and top of `f` on screen; from the left edge and width (bottom and height)
-- when the client does not answer them directly. nil when it cannot be measured.
local function edges(f)
    local right, top = ask(f, "GetRight"), ask(f, "GetTop")
    if not right then
        local left, width = ask(f, "GetLeft"), ask(f, "GetWidth")
        right = left and width and left + width or nil
    end
    if not top then
        local bottom, height = ask(f, "GetBottom"), ask(f, "GetHeight")
        top = bottom and height and bottom + height or nil
    end
    return right, top
end

function Controller.besidePosition(except)
    local tops, entries = {}, {}
    for _, mod in ipairs({ ns.Window, ns.LevelingUI, ns.PinnedWindow, ns.HistoryWindow, ns.OptionsUI }) do
        local f = type(mod) == "table" and type(mod.frame) == "function" and mod.frame() or nil
        if f and f ~= except then
            local right, top = edges(f)
            -- A window whose top cannot be measured cannot be sat beside.
            entries[#entries + 1] = { shown = f:IsShown() == true and top ~= nil, right = right }
            tops[#entries] = top
        end
    end
    local index = ns.Layout.rightmost(entries)
    if not index then return nil end
    return entries[index].right + BESIDE_GAP, tops[index]
end

-- The main window's position: the saved one, else beside a shown CraftProfit window, else
-- nil (Window.attach then places it beside `target`).
local function mainPosition()
    local saved = CraftProfitDB.settings.window
    if saved then return saved end
    local x, y = Controller.besidePosition(ns.Window.frame())
    if x then return { point = "TOPLEFT", x = x, y = y } end
    return nil
end

function Controller.setRecipe(recipe, source)
    choose(recipe, source)
    local window = ns.Window
    if not window.isShown() then
        local target = ns.Trade.frame()
        if source == "pin" and ns.AH.isOpen then target = AuctionHouseFrame or AuctionFrame end
        window.attach(target, mainPosition())
        window.show()
    end
    Controller.refresh()
end

function Controller.selectPin(recipeID)
    local index = DB.pinIndex(CraftProfitCharDB, recipeID)
    if not index then return end
    choose(CraftProfitCharDB.pins[index], "pin")
    Controller.refresh()
end

-- Pinned recipes keep the difficulty they had when pinned; the open profession
-- window knows the current one, which changes as the skill rises. Runs when the window
-- opens, switches profession and updates its list.
function Controller.refreshPinDifficulties()
    if not ns.Trade.isShown() or ns.Trade.isDataSourceChanging() then return false end
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

-- The main window, as /cp show and /cp hide drive it.
function Controller.showMainWindow()
    local window = ns.Window
    if not window.isShown() then
        window.attach(ns.Trade.frame() or AuctionHouseFrame or AuctionFrame, mainPosition())
        window.show()
    end
    Controller.refresh()
end

function Controller.hideMainWindow()
    ns.Window.hide()
end

function Controller.toggleMainWindow()
    if ns.Window.isShown() then Controller.hideMainWindow() else Controller.showMainWindow() end
end

-- The "Track history" box: starts recording this recipe (or pauses it, keeping
-- what was recorded).
function Controller.setTracking(checked)
    local recipe = state.recipe
    if not recipe then return end
    Controller.historyChanged()
    if checked then
        local ok, reason = History.track(CraftProfitDB, recipe)
        if not ok and reason == "full" then say(string.format(L.TRACK_FULL, History.MAX_TRACKED)) end
    else
        History.pause(CraftProfitDB, recipe.recipeID)
    end
    Controller.refresh()
end

-- Known recipes ------------------------------------------------------------------

local knownBusy, knownLast = false, nil

-- Reads the learned recipes of the open profession for the leveling list. Bursts of
-- TRADE_SKILL_LIST_UPDATE are coalesced: one read at most every few seconds. Nothing is
-- read while the game is switching profession (the list is the old one or empty).
function Controller.refreshKnown()
    if knownBusy or not ns.Trade.isShown() or ns.Trade.isDataSourceChanging() then return false end
    local now = GetTime()
    if knownLast and now - knownLast < 5 then return false end
    local key, name = ns.Trade.professionInfo()
    if not key then return false end
    knownBusy, knownLast = true, now
    local started = ns.Trade.scanKnown(function(raws)
        knownBusy = false
        -- An empty read (the list was not built yet) never replaces a stored list, and the
        -- next list update may read again at once.
        if #raws == 0 then
            knownLast = nil
            return
        end
        DB.setKnown(CraftProfitCharDB, key, name, raws, time())
        if ns.LevelingUI then ns.LevelingUI.refresh() end
    end, function() knownBusy = false end)
    if not started then knownBusy = false end
    return started
end

-- The profession window opened or switched profession (Forever's profession tabs switch
-- inside the open window, firing TRADE_SKILL_SHOW and TRADE_SKILL_DATA_SOURCE_CHANGED but
-- no close): the scan in progress reads the previous profession and is dropped, and the
-- few seconds of coalescing, which belonged to the previous profession, start again.
function Controller.onProfessionChanged()
    ns.Trade.cancelScan()
    knownBusy, knownLast = false, nil
    Controller.refreshPinDifficulties()
    Controller.refreshKnown()
    ns.Trade.invalidate()
end

-- What the leveling window shows: the current profession, its known recipes ranked
-- by cost per point from the last scan's prices, and how old those prices are.
local function levelData()
    local settings = CraftProfitDB.settings
    local prof = DB.currentKnown(CraftProfitCharDB)
    local age = Prices.snapshotAge(Controller.market(), time())
    local data = {
        showGrey = settings.levelShowGrey == true, sort = settings.levelSort, profession = prof,
        items = {}, hiddenGrey = 0,
        ageText = Present.ageText(L, age), stale = age == nil or age > settings.staleAfter,
    }
    if prof then
        local ranked = Leveling.rank(prof.recipes, function(recipe)
            return Controller.evaluate(recipe, 1, true)
        end, { showGrey = data.showGrey, sort = data.sort })
        data.items, data.hiddenGrey = ranked.items, ranked.hiddenGrey
    end
    return data
end

-- In one refresh pass (the one running, when Controller.refresh asks).
function Controller.levelData()
    return Controller.inPass(levelData)
end

function Controller.setLevelShowGrey(value)
    CraftProfitDB.settings.levelShowGrey = value and true or false
    if ns.LevelingUI then ns.LevelingUI.refresh() end
end

function Controller.toggleLevelSort()
    local settings = CraftProfitDB.settings
    settings.levelSort = settings.levelSort == "speed" and "cost" or "speed"
    if ns.LevelingUI then ns.LevelingUI.refresh() end
end

function Controller.nextLevelProfession()
    DB.nextKnown(CraftProfitCharDB)
    if ns.LevelingUI then ns.LevelingUI.refresh() end
end

-- A row of the leveling list was clicked: show that recipe in the main window.
function Controller.selectKnown(recipe)
    Controller.setRecipe(recipe, "pin")
end

function Controller.togglePin()
    local recipe = state.recipe
    if not recipe then return end
    if DB.pinIndex(CraftProfitCharDB, recipe.recipeID) then
        DB.pinRemove(CraftProfitCharDB, recipe.recipeID)
    else
        -- Read at each attempt: a limit changed in the options window applies at once.
        local limit = Controller.pinLimit()
        local ok, reason = DB.pinAdd(CraftProfitCharDB, recipe, limit)
        if not ok and reason == "full" then say(string.format(L.PINS_LIMIT_REACHED, limit)) end
    end
    Controller.refresh()
end

-- "Refresh recipe": searches the AH for the items of the recipe on screen only (reagents,
-- output, disenchant materials when relevant), through the pinned list's search. Ignored
-- while a search runs; with the AH closed it says so in chat.
function Controller.refreshRecipe()
    local recipe = state.recipe
    if not recipe then return end
    if not ns.AH.isOpen then
        say(L.SEARCH_NEED_AH)
        return
    end
    if ns.PinsUI then ns.PinsUI.startSearch({ recipe }) end
end

-- The "x" of a row in the pinned window: removes that pin and refreshes every view; the
-- selection stays as it was.
function Controller.unpin(recipeID)
    DB.pinRemove(CraftProfitCharDB, recipeID)
    Controller.refresh()
end

-- What the pinned window shows: the pins in the pinned list's order with their
-- evaluation, the sort, and how old their prices are (it never searches). The age is the
-- main window's: the oldest price the evaluations used (result.oldestAge, whether it came
-- from a full scan or a "Refresh pinned" or "Refresh recipe"), here over every pin; none -> never priced, stale.
local function pinsData()
    local settings = CraftProfitDB.settings
    local sortMode = CraftProfitCharDB.sortMode
    local items = ns.PinsUI.orderedPins(CraftProfitCharDB.pins, sortMode, Controller.evaluate)
    local age
    for _, item in ipairs(items) do
        local itemAge = item.result.oldestAge
        if Util.isFinite(itemAge) and (age == nil or itemAge > age) then age = itemAge end
    end
    return {
        items = items,
        byPoint = sortMode == DB.SORT_POINT,
        ageText = Present.ageText(L, age),
        stale = age == nil or age > settings.staleAfter,
    }
end

function Controller.pinsData()
    return Controller.inPass(pinsData)
end

local searched = {}

-- Writes one history point per tracked recipe the update touched.
function Controller.recordHistory(updated)
    Controller.historyChanged()
    History.record(CraftProfitDB, Controller.market(), time(), updated, Controller.historyItems)
end

-- A price search is over (finished or cancelled): its results make one batch.
function Controller.commitSearch()
    local updated = searched
    searched = {}
    Controller.recordHistory(updated)
end

-- Stores the median price of an AH search result. False when nothing was listed.
function Controller.recordListings(itemID, listings)
    local unit, volume = Prices.summarize(listings, CraftProfitDB.settings.medianN)
    -- `full` (set by the AH adapter) says the listings hold every unit on offer.
    local full = type(listings) == "table" and listings.full == true
    if unit and Prices.store(Controller.market(), itemID, unit, volume, time(), full) then searched[itemID] = true end
    return unit ~= nil
end

function Controller.onSnapshot(agg)
    local prices = agg.result(CraftProfitDB.settings.medianN)
    local count = Prices.merge(Controller.market(), prices, time())
    Controller.recordHistory(prices)
    if ns.PinsUI then ns.PinsUI.setStatus(string.format(L.SCAN_DONE, count)) end
    Controller.requestRefresh()
end

function Controller.onAHOpen(open)
    if ns.PinsUI then ns.PinsUI.onAHOpen(open) end
    local window = ns.Window
    if open then
        if not state.recipe then
            local first = CraftProfitCharDB.pins[1]
            if first then choose(first, "pin") end
        end
        if not window.isShown() then
            window.attach(AuctionHouseFrame or AuctionFrame, mainPosition())
            window.show()
        end
        Controller.refresh()
    elseif state.source == "profession" then
        Controller.refresh()
    else
        choose(nil, nil)
        window.hide()
        -- The profession window may still be open: let the watcher report it again.
        ns.Trade.invalidate()
    end
    -- The hidden window keeps its last recipe: its button must still follow the AH.
    if window.updateRefreshButton then window.updateRefreshButton() end
end

-- The recipe id the profession window reported last; nil while it is closed.
local lastProfessionID

-- The profession window selection changed (or the window closed), or the watcher reports
-- the same one again (Trade.invalidate: the list updated after a craft, a skill-up or a
-- filter change). Only a new selection replaces the recipe shown and opens the main window:
-- the same one again refreshes its data (difficulty, quantities) without reopening a window
-- the player closed, and leaves a recipe picked from a list (source "pin") in place.
local function onSelection(recipeID)
    local previous = lastProfessionID
    lastProfessionID = recipeID
    if recipeID then
        if state.source == "pin" and recipeID == previous then return end
        local recipe = Recipes.normalize(ns.Trade.readSelected())
        if recipe then
            if state.source == "profession" and recipeID == Controller.currentRecipeID() then
                choose(recipe, "profession")
                Controller.refresh()
            else
                Controller.setRecipe(recipe, "profession")
            end
            return
        end
    end
    if state.source == "profession" then
        -- A pinned recipe stays selected as a pin, so it is still there at the AH.
        local recipe = state.recipe
        local index = recipe and DB.pinIndex(CraftProfitCharDB, recipe.recipeID)
        if index then
            choose(CraftProfitCharDB.pins[index], "pin")
        else
            choose(nil, nil)
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
