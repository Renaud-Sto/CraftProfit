-- Entry point: wires the modules together and owns the controller.
local ADDON, ns = ...
local Util, Format, Core, Prices = ns.Util, ns.Format, ns.Core, ns.Prices
local DB, Evaluate, Present, Recipes = ns.DB, ns.Evaluate, ns.Present, ns.Recipes
local History, Leveling = ns.History, ns.Leveling
local Disenchant = ns.Data.Disenchant
local L = ns.L

local Controller = {}
ns.Controller = Controller

local state = { recipe = nil, source = nil, crafts = 1 }
local requestedItems = {}
local refreshQueued = false

function Controller.say(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffCraftProfit|r " .. tostring(text))
end
local say = Controller.say

-- Forever has no GetCoinTextureString: GetMoneyString draws the gold, silver and copper
-- icons (measured with /cppn money). Anything else it answers falls back to plain text.
local function coinString(copper)
    if type(GetMoneyString) ~= "function" then return nil end
    local ok, text = pcall(GetMoneyString, copper)
    return ok and text or nil
end

function Controller.fmt(copper)
    return Format.money(copper, coinString)
end

-- Item facts, or nil while the game has not loaded the item yet. The request is
-- made once per item; ITEM_DATA_LOAD_RESULT triggers the refresh.
-- Prices differ between markets, so each one has its own price table and history.
-- Forever has rulesets (Normal, PvP, RP, Hardcore) instead of realms; in the beta the
-- ruleset is the "realm" the character is on (for example "Classic Beta PvP 2", realm
-- id 4613). The realm id follows the real economy best, the faction picks the faction
-- auction house. The realm name is the fallback when no id is given. The neutral
-- auction house is not told apart from the faction one yet.
function Controller.marketKey()
    local id = type(GetRealmID) == "function" and GetRealmID() or nil
    local realm = Util.id(id) and tostring(id) or nil
    if not realm then
        local name = type(GetNormalizedRealmName) == "function" and GetNormalizedRealmName() or nil
        if type(name) ~= "string" or name == "" then
            name = type(GetRealmName) == "function" and GetRealmName() or nil
        end
        realm = type(name) == "string" and name ~= "" and name or "unknown"
    end
    local faction = type(UnitFactionGroup) == "function" and UnitFactionGroup("player") or nil
    local key = realm .. "-" .. (type(faction) == "string" and faction ~= "" and faction or "Neutral")
    -- A hardcore character never shares a market with a normal one, whatever its realm.
    local rules = C_GameRules
    if type(rules) == "table" and type(rules.IsHardcoreActive) == "function" then
        local ok, hardcore = pcall(rules.IsHardcoreActive)
        if ok and hardcore == true then key = key .. "-HC" end
    end
    return key
end

function Controller.market()
    return DB.market(CraftProfitDB, Controller.marketKey())
end

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
    local info = Controller.itemInfo(itemID)
    if info and info.bindType == 1 then
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

-- crafts is only given for the recipe shown in the window; the pinned list is always
-- one craft.
function Controller.evaluate(recipe, crafts, forcePerPoint)
    local settings = CraftProfitDB.settings
    return Evaluate.run({
        recipe = recipe,
        crafts = crafts,
        priceOf = Prices.priceOf(Controller.market(), time()),
        itemInfo = Controller.itemInfo,
        cut = settings.cut,
        showPerPoint = settings.showPerPoint or forcePerPoint == true,
        lookupDisenchant = Disenchant.lookup,
        knowsEnchanting = Controller.knowsEnchanting(),
    })
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

function Controller.refresh()
    local settings = CraftProfitDB.settings
    local recipe = state.recipe
    if recipe then
        local model = Present.build(Controller.evaluate(recipe, state.crafts), L, Controller.fmt,
            { staleAfter = settings.staleAfter, itemName = Controller.itemName })
        if type(recipe.name) == "string" and recipe.name ~= "" then
            model.title = recipe.name
        else
            model.title = Controller.itemName(recipe.outputItemID)
        end
        for _, reagent in ipairs(recipe.reagents or {}) do Controller.itemInfo(reagent.itemID) end
        model.pinned = DB.pinIndex(CraftProfitCharDB, recipe.recipeID) ~= nil
        model.tracked = History.isActive(CraftProfitDB, recipe.recipeID)
        model.showPerPoint = settings.showPerPoint
        model.costExpanded = settings.costExpanded
        ns.Window.render(model)
    else
        ns.Window.showEmpty(L.NO_RECIPE)
    end
    if ns.PinsUI then ns.PinsUI.refresh() end
    if ns.LevelingUI then ns.LevelingUI.refresh() end
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
    choose(recipe, source)
    local window = ns.Window
    if not window.isShown() then
        local target = ns.Trade.frame()
        if source == "pin" and ns.AH.isOpen then target = AuctionHouseFrame or AuctionFrame end
        window.attach(target, CraftProfitDB.settings.window)
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

-- Themes -------------------------------------------------------------------------

-- Localized name of a theme; the code itself when no language has one (ns.L then
-- returns the key).
function Controller.themeLabel(code)
    if type(code) ~= "string" then return tostring(code) end
    local key = "THEME_" .. code:upper()
    local label = L[key]
    if label == key then return code end
    return label
end

-- Repaints every window with the theme `code` and saves the choice. False, and
-- nothing changed, for an unknown theme.
function Controller.setTheme(code)
    if not ns.Theme.exists(code) then return false end
    ns.Kit.applyTheme(code)
    CraftProfitDB.settings.theme = code
    Controller.refresh()
    return true
end

-- The next theme of the list, back to the first after the last. No window calls it since
-- the main window lost its swatch (native frame); kept with the themes until step 5.
function Controller.cycleTheme()
    local list = ns.Theme.list()
    local nextCode = list[1]
    for i, code in ipairs(list) do
        if code == ns.Kit.themeName then nextCode = list[i % #list + 1] end
    end
    if Controller.setTheme(nextCode) then say(string.format(L.THEME_SET, Controller.themeLabel(nextCode))) end
end

-- The "Track history" box: starts recording this recipe (or pauses it, keeping
-- what was recorded).
function Controller.setTracking(checked)
    local recipe = state.recipe
    if not recipe then return end
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
-- TRADE_SKILL_LIST_UPDATE are coalesced: one read at most every few seconds.
function Controller.refreshKnown()
    if knownBusy or not ns.Trade.isShown() then return false end
    local now = GetTime()
    if knownLast and now - knownLast < 5 then return false end
    local key, name = ns.Trade.professionInfo()
    if not key then return false end
    knownBusy, knownLast = true, now
    local started = ns.Trade.scanKnown(function(raws)
        knownBusy = false
        DB.setKnown(CraftProfitCharDB, key, name, raws, time())
        if ns.LevelingUI then ns.LevelingUI.refresh() end
    end, function() knownBusy = false end)
    if not started then knownBusy = false end
    return started
end

-- What the leveling window shows: the current profession, its known recipes ranked
-- by cost per point from the last scan's prices, and how old those prices are.
function Controller.levelData()
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
        local ok, reason = DB.pinAdd(CraftProfitCharDB, recipe)
        if not ok and reason == "full" then say(L.PINS_FULL) end
    end
    Controller.refresh()
end

-- The items worth a history point for a tracked recipe, and the ones that must be
-- priced for the point to count. The output of a bind-on-pickup recipe cannot be
-- sold at the auction house, so it is recorded when priced but never required.
function Controller.historyItems(recipe)
    local all = Evaluate.wantedItems(recipe, Controller.itemInfo, Disenchant.lookup, Controller.knowsEnchanting())
    local info = Controller.itemInfo(recipe.outputItemID)
    local optional = { [recipe.outputItemID] = info ~= nil and info.bindType == 1 or nil }
    local isReagent = {}
    for _, r in ipairs(recipe.reagents) do isReagent[r.itemID] = true end
    local required = {}
    for _, id in ipairs(all) do
        if isReagent[id] or (id == recipe.outputItemID and not optional[id]) then required[#required + 1] = id end
    end
    return all, required
end

local searched = {}

-- Writes one history point per tracked recipe the update touched.
function Controller.recordHistory(updated)
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
    if unit and Prices.store(Controller.market(), itemID, unit, volume, time()) then searched[itemID] = true end
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
            window.attach(AuctionHouseFrame or AuctionFrame, CraftProfitDB.settings.window)
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
    -- Before any window is built, so every widget is painted once, in the saved theme.
    ns.Kit.applyTheme(CraftProfitDB.settings.theme)

    ns.Window.create({
        onPinClick = Controller.togglePin,
        onReagentClick = Controller.onReagentClick,
        onOutputClick = Controller.onOutputClick,
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
            onMoved = function(_, x, y) CraftProfitDB.settings.levelWindow = { x = x, y = y } end,
        })
        ns.LevelingUI.attach(CraftProfitDB.settings.levelWindow)
    end
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
        Controller.refreshKnown()
        ns.Trade.invalidate()
    end
end

-- /cp history: list the tracked recipes; /cp history remove <n>: delete one.
function Controller.historyCommand(arg)
    local tracked = CraftProfitDB.tracked
    local index = tonumber(arg:match("^remove%s+(%d+)$"))
    if index then
        local entry = tracked[index]
        if History.remove(CraftProfitDB, index) then
            History.prune(CraftProfitDB, Controller.market(), Controller.historyItems)
            say(string.format(L.HISTORY_REMOVED, entry.recipe.name ~= "" and entry.recipe.name or entry.recipe.recipeID))
            Controller.refresh()
        else
            say(L.HISTORY_NO_SUCH)
        end
        return
    end
    if #tracked == 0 then
        say(L.HISTORY_EMPTY)
        return
    end
    say(string.format(L.HISTORY_HEADER, #tracked, History.MAX_TRACKED))
    for i, entry in ipairs(tracked) do
        local name = entry.recipe.name ~= "" and entry.recipe.name or ("#" .. entry.recipe.recipeID)
        say(string.format("%d. %s (%s)", i, name, entry.active and L.TRACK_ACTIVE or L.TRACK_PAUSED))
    end
end

-- /cp theme: name the current theme and list them all; /cp theme <code>: switch to it.
function Controller.themeCommand(code)
    local available = table.concat(ns.Theme.list(), ", ")
    if code == "" then
        say(string.format(L.THEME_INFO, Controller.themeLabel(ns.Kit.themeName), available))
    elseif Controller.setTheme(code) then
        say(string.format(L.THEME_SET, Controller.themeLabel(code)))
    else
        say(string.format(L.THEME_UNKNOWN, code, available))
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
    elseif cmd == "history" then
        Controller.historyCommand(arg)
    elseif cmd == "level" then
        if ns.LevelingUI then ns.LevelingUI.toggle() end
    elseif cmd == "theme" then
        Controller.themeCommand(arg:lower():match("^(.-)%s*$"))
    elseif cmd == "kitdemo" then
        if ns.KitDemo then ns.KitDemo.command(arg) end
    elseif cmd == "market" then
        local name = type(GetRealmName) == "function" and GetRealmName() or "?"
        say(string.format(L.MARKET_INFO, tostring(name), Controller.marketKey()))
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
