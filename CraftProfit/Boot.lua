-- Entry point: wires the modules together and owns the controller.
local ADDON, ns = ...
local Util, Format, Core, Prices = ns.Util, ns.Format, ns.Core, ns.Prices
local DB, Evaluate, Present, Recipes = ns.DB, ns.Evaluate, ns.Present, ns.Recipes
local History, HistoryView, Leveling = ns.History, ns.HistoryView, ns.Leveling
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

local isSecret = Util.isSecret

-- A game value, or nil when it is secret.
local function plain(v)
    if isSecret(v) then return nil end
    return v
end

-- Item facts, or nil while the game has not loaded the item yet. The request is
-- made once per item; ITEM_DATA_LOAD_RESULT triggers the refresh.
function Controller.itemInfo(itemID)
    local ok, _, _, quality, ilvl, _, _, _, _, _, _, sellPrice, classID, _, bindType = pcall(C_Item.GetItemInfo, itemID)
    if not ok then return nil end
    -- A secret field is dropped (nil): each one is compared or multiplied later. A secret
    -- quality reads as "not loaded".
    quality, ilvl, sellPrice = plain(quality), plain(ilvl), plain(sellPrice)
    classID, bindType = plain(classID), plain(bindType)
    if quality == nil then
        if not requestedItems[itemID] then
            requestedItems[itemID] = true
            C_Item.RequestLoadItemDataByID(itemID)
        end
        return nil
    end
    return { quality = quality, ilvl = ilvl, sellPrice = sellPrice, classID = classID, bindType = bindType }
end

-- Item icon (file id or path) read secret-safely, or nil while the game has not loaded it.
function Controller.itemIcon(itemID)
    local api = C_Item
    local ok, icon
    if type(api.GetItemIconByID) == "function" then ok, icon = pcall(api.GetItemIconByID, itemID) end
    if not ok or isSecret(icon) or (type(icon) ~= "number" and type(icon) ~= "string") or icon == "" then
        local found, _, _, _, _, _, _, _, _, _, texture = pcall(api.GetItemInfo, itemID)
        icon = found and not isSecret(texture) and texture or nil
    end
    if (type(icon) ~= "number" and type(icon) ~= "string") or icon == "" then return nil end
    return icon
end

-- Item name read secret-safely (Util.text: a secret value raises when concatenated), or
-- nil while the game has not loaded the item.
function Controller.itemName(itemID)
    local ok, name = pcall(C_Item.GetItemInfo, itemID)
    local text = ok and Util.text(name, isSecret) or nil
    if text then return text end
    Controller.itemInfo(itemID) -- not loaded yet: ask the game, the refresh follows
    return nil
end

-- The name shown for a stored recipe (pin, known recipe, tracked recipe), in the game's
-- current language: names are stored when pinned or read and would stay in the old
-- language after a language switch. Recipes.liveName picks the client's recipe name, else
-- the crafted item's (loaded on demand: ITEM_DATA_LOAD_RESULT refreshes), else the stored
-- one, and writes a newer name back into the stored recipe. Identity stays the recipe id.
function Controller.recipeName(recipe)
    if type(recipe) ~= "table" then return "" end
    return Recipes.liveName(recipe, {
        locale = ns.Trade.locale(),
        recipeName = ns.Trade.recipeName,
        itemName = Controller.itemName,
    })
end

-- The name shown for a stored profession (a CraftProfitCharDB.known entry) in the game's
-- current language, else the stored one; a newer name is written back.
function Controller.professionName(prof)
    if type(prof) ~= "table" then return "-" end
    local live = ns.Trade.professionName(prof.key)
    if live and #live <= DB.MAX_PROFESSION_NAME then
        if live ~= prof.name then prof.name = live end
        return live
    end
    if type(prof.name) == "string" and prof.name ~= "" then return prof.name end
    return tostring(prof.key or "-")
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
        model.title = Controller.recipeName(recipe)
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
    if ns.PinnedWindow then ns.PinnedWindow.refresh() end
    if ns.HistoryWindow then ns.HistoryWindow.refresh() end
    if ns.OptionsUI then ns.OptionsUI.refresh() end
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

-- Appearance ---------------------------------------------------------------------

-- Picks the header strip and the tile card (either nil = keep), repaints every window at
-- once (Native keeps its panels and tiles) and saves the choice. An unknown key refuses the
-- whole call: nothing changes. Returns true when the look changed.
function Controller.setAppearance(header, tile)
    if header ~= nil and not DB.HEADER_KEYS[header] then return false end
    if tile ~= nil and not DB.TILE_KEYS[tile] then return false end
    -- Merged into the SAVED choice, never read back from Native: what is on screen may
    -- differ (a developer preview), and must not leak into the save.
    local saved = CraftProfitDB.settings.appearance
    local newHeader, newTile = header or saved.header, tile or saved.tile
    local changed = newHeader ~= saved.header or newTile ~= saved.tile
    ns.Native.setHeaderVariant(newHeader)
    ns.Native.setTileVariant(newTile)
    CraftProfitDB.settings.appearance = { header = newHeader, tile = newTile }
    return changed
end

-- The saved look: header, tile keys.
function Controller.appearance()
    local appearance = CraftProfitDB.settings.appearance
    return appearance.header, appearance.tile
end

-- Pinned recipes limit -------------------------------------------------------------

-- How many recipes a character may pin (account wide setting, one of DB.PIN_LIMITS).
function Controller.pinLimit()
    return DB.pinLimit(CraftProfitDB.settings.maxPins)
end

-- The pinned panels' title with the pin count over the limit, e.g. "PINNED RECIPES (21/30)".
-- The count can exceed the limit after it was lowered (pins are never deleted for it).
function Controller.pinsTitle()
    return string.format(L.PANEL_PINS_COUNT, #CraftProfitCharDB.pins, Controller.pinLimit())
end

-- Saves a new limit and refreshes every view (the options window lights it). Anything but a
-- listed limit is refused and changes nothing. Pins over a lower limit are kept: it only
-- blocks new ones. Returns true when the limit was accepted.
function Controller.setPinLimit(n)
    if not DB.isPinLimit(n) then return false end
    CraftProfitDB.settings.maxPins = n
    Controller.refresh()
    return true
end

-- Options window and minimap button ---------------------------------------------------

function Controller.minimapHidden()
    return CraftProfitDB.settings.minimap.hide == true
end

-- Hides (true) or shows the minimap button, saves it, and applies it when the button
-- module is loaded.
function Controller.setMinimapHidden(hidden)
    CraftProfitDB.settings.minimap.hide = hidden and true or false
    local button = ns.MinimapButton
    if type(button) == "table" and type(button.apply) == "function" then button.apply() end
    -- The options window's check box follows a change made elsewhere (/cp minimap).
    if ns.OptionsUI then ns.OptionsUI.refresh() end
end

function Controller.minimapAngle()
    return CraftProfitDB.settings.minimap.angle
end

-- Saves where the minimap button was dragged; a bad angle is ignored.
function Controller.setMinimapAngle(angle)
    local clean = DB.angle(angle)
    if clean then CraftProfitDB.settings.minimap.angle = clean end
end

-- /cp minimap: hides the button, or shows it again, and says which in one line.
function Controller.minimapCommand()
    local hidden = not Controller.minimapHidden()
    Controller.setMinimapHidden(hidden)
    say(hidden and L.MINIMAP_HIDDEN or L.MINIMAP_SHOWN)
end

function Controller.saveOptionsPosition(x, y)
    if Util.isFinite(x) and Util.isFinite(y) then
        CraftProfitDB.settings.optionsWindow = { x = x, y = y }
    end
end

function Controller.savePinsPosition(x, y)
    if Util.isFinite(x) and Util.isFinite(y) then
        CraftProfitDB.settings.pinsWindow = { x = x, y = y }
    end
end

function Controller.saveHistoryPosition(x, y)
    if Util.isFinite(x) and Util.isFinite(y) then
        CraftProfitDB.settings.historyWindow = { x = x, y = y }
    end
end

function Controller.saveLevelPosition(x, y)
    if Util.isFinite(x) and Util.isFinite(y) then
        CraftProfitDB.settings.levelWindow = { x = x, y = y }
    end
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
function Controller.pinsData()
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

-- The items worth a history point for a tracked recipe, and the ones that must be
-- priced for the point to count. The output of a bind-on-pickup recipe cannot be
-- sold at the auction house, so it is recorded when priced but never required.
function Controller.historyItems(recipe)
    local all = Evaluate.wantedItems(recipe, Controller.itemInfo, Disenchant.lookup, Controller.knowsEnchanting())
    local info = Controller.itemInfo(recipe.outputItemID)
    local optional = { [recipe.outputItemID] = Evaluate.isBindOnPickup(info) or nil }
    local isReagent = {}
    for _, r in ipairs(recipe.reagents) do isReagent[r.itemID] = true end
    local required = {}
    for _, id in ipairs(all) do
        if isReagent[id] or (id == recipe.outputItemID and not optional[id]) then required[#required + 1] = id end
    end
    return all, required
end

-- History window data ----------------------------------------------------------------

-- The item ids of a tracked recipe in the order of the window's icon row: reagents, the
-- crafted item unless it is bound on pickup (never sold), then disenchant materials when
-- they count (Controller.historyItems: the list recording uses).
function Controller.historyItemsOf(recipe)
    local all, required = Controller.historyItems(recipe)
    local needed = {}
    for _, id in ipairs(required) do needed[id] = true end
    local out = {}
    for _, id in ipairs(all) do
        if id ~= recipe.outputItemID or needed[id] then out[#out + 1] = id end
    end
    return out
end

-- The market the history comes from, readable: the ruleset ("realm") name and the faction,
-- with (HC) for a hardcore character. Falls back to the market key.
function Controller.marketName()
    local realm = type(GetRealmName) == "function" and GetRealmName() or nil
    if type(realm) ~= "string" or realm == "" then return Controller.marketKey() end
    local name = realm
    if type(UnitFactionGroup) == "function" then
        local faction, localized = UnitFactionGroup("player")
        local shown = type(localized) == "string" and localized ~= "" and localized or faction
        if type(shown) == "string" and shown ~= "" then name = name .. " - " .. shown end
    end
    if Controller.marketKey():find("%-HC$") then name = name .. " (HC)" end
    return name
end

Controller.HISTORY_PERIODS = { [7] = true, [30] = true, [60] = true }
Controller.HISTORY_FRESH = 86400   -- arrows only when the newest measurement is this recent

local function seriesReader()
    local series = Controller.market().series
    return function(itemID) return series[itemID] end
end

-- Time of the newest valid measurement of any of `ids`, or nil.
local function newestPoint(ids, seriesOf, now)
    local newest
    for _, id in ipairs(ids) do
        local series = seriesOf(id)
        if type(series) == "table" then
            for _, p in ipairs(series) do
                local t = type(p) == "table" and p[1] or nil
                if Util.isFinite(t) and t <= now and (not newest or t > newest) then newest = t end
            end
        end
    end
    return newest
end

-- Whether the recipe's figures are fresh: the newest measurement of a reagent or of the
-- crafted item when sold (the items HistoryView.recipeDays reads; disenchant materials do
-- not count) is at most Controller.HISTORY_FRESH old. Returns fresh, materialsFresh (a
-- reagent is) and saleFresh (the crafted item is), so no figure is claimed from old prices.
local function freshness(recipe, seriesOf, now)
    local _, required = Controller.historyItems(recipe)
    local reagents, sale = {}, {}
    for _, id in ipairs(required) do
        if id == recipe.outputItemID then sale[1] = id else reagents[#reagents + 1] = id end
    end
    local function isFresh(ids)
        local newest = newestPoint(ids, seriesOf, now)
        return newest ~= nil and now - newest <= Controller.HISTORY_FRESH
    end
    local materialsFresh, saleFresh = isFresh(reagents), isFresh(sale)
    return materialsFresh or saleFresh, materialsFresh, saleFresh
end

-- The tracked recipes for the window's list, in saved order. `indicator` holds the arrows
-- (HistoryView.indicators) only when there is enough data and the newest measurement is
-- under 24 hours old (`fresh`: a reagent or the sold crafted item, see freshness), each
-- arrow only when its own items are (materials: a reagent, sale: the crafted item); older
-- data never shows as today's. atLoss: when the crafted item's sale price is fresh too,
-- whether crafting and selling at the auction house loses money (or earns 0) on the newest
-- day (indicators' netToday <= 0); nil when unknown (stale data or sale price, no sale).
function Controller.historyList()
    local now, seriesOf, cut = time(), seriesReader(), CraftProfitDB.settings.cut
    local out = {}
    for _, entry in ipairs(CraftProfitDB.tracked) do
        local fresh, materialsFresh, saleFresh = freshness(entry.recipe, seriesOf, now)
        local indicator, atLoss
        if fresh then
            local ind = HistoryView.indicators(entry.recipe, seriesOf, now, Controller.historyItems, cut)
            if not materialsFresh then ind.materials = nil end
            if not saleFresh then ind.sale = nil end
            if ind.materials or ind.sale then indicator = ind end
            if saleFresh and type(ind.netToday) == "number" then atLoss = ind.netToday <= 0 end
        end
        out[#out + 1] = { recipe = entry.recipe, active = entry.active == true, indicator = indicator, fresh = fresh,
            atLoss = atLoss }
    end
    return out
end

-- Rows a recipe view keeps for the weekday strip: the ones with a value that is not only
-- carried prices (as HistoryView.summary counts them).
local function viewDays(days, field)
    local out = {}
    for _, d in ipairs(days) do
        if Util.isFinite(d[field]) and d[field .. "Carried"] ~= "all" then
            out[#out + 1] = { day = d.day, value = d[field] }
        end
    end
    return out
end

-- Everything the History window shows for one tracked recipe, one view ("net",
-- "materials", "sale" or "item:<itemID>", default "net") and one period (7, 30 or 60
-- days, default 30), from the current market only. nil for a recipe that is not tracked.
-- The usual price and `enough` always cover 30 days (History.usual, HistoryView.summary of
-- 30 days), whatever the period; the other key figures cover the period. status: "nodata"
-- (fewer than 3 days: `measures` and `days` over 30 days for the message), else "paused"
-- for a paused recipe, else "ok".
-- items: the recipe's items for the icon row, { key = "item:<id>", itemID, name, icon,
-- group }, group "materials" (a reagent), "crafted" (the crafted item, when it is sold) or
-- "disenchant"; the recipe views (net, materials, sale) are the window's tabs, not items.
-- goal: what the shown price matters for, "buy" (materials, one reagent), "sell" (sale, the
-- crafted item, a disenchant material) or "craft" (net). compare: today against the usual
-- price (HistoryView.compare: good news is a lower price to buy, a higher one otherwise),
-- nil without enough data; in the Profit view it is profit.compare (in money).
-- profit: the recipe's auction house profit whatever the view (HistoryView.summary "net" of
-- the period's rows, usual over 30 days): { today, todayDay, usual, enough, compare
-- (HistoryView.profitCompare), atLoss (today is a number <= 0) }; vendor and disenchant are
-- not counted. commission: the auction house cut in percent (5 for 0.05).
function Controller.historyData(recipeID, view, period)
    local _, entry = History.find(CraftProfitDB, recipeID)
    if not entry then return nil end
    local recipe = entry.recipe
    local now, seriesOf, cut = time(), seriesReader(), CraftProfitDB.settings.cut
    period = Controller.HISTORY_PERIODS[period] and period or 30
    local ids = Controller.historyItemsOf(recipe)
    local isReagent = {}
    for _, r in ipairs(recipe.reagents) do isReagent[r.itemID] = true end
    local items, groupOf = {}, {}
    local valid = { net = true, materials = true, sale = true }
    for _, id in ipairs(ids) do
        local key = "item:" .. id
        valid[key] = true
        local group = "disenchant"
        if isReagent[id] then group = "materials" elseif id == recipe.outputItemID then group = "crafted" end
        groupOf[key] = group
        -- The icon helper is not measured on Forever yet: a failure only loses the icon.
        local okIcon, icon = pcall(Controller.itemIcon, id)
        items[#items + 1] = { key = key, itemID = id, name = Controller.itemName(id) or ("#" .. id),
            icon = okIcon and icon or nil, group = group }
    end
    if not valid[view] then view = "net" end
    local goal = "craft"
    if view == "materials" or groupOf[view] == "materials" then goal = "buy"
    elseif view ~= "net" then goal = "sell" end

    local days, field, summary, usual30, weekdayDays
    local itemID = tonumber(view:match("^item:(%d+)$"))
    -- The recipe's rows over the period and over 30 days: the profit whatever the view.
    local rows = HistoryView.recipeDays(recipe, seriesOf, now, period, cut, Controller.historyItems)
    local month = HistoryView.recipeDays(recipe, seriesOf, now, History.USUAL_DAYS, cut, Controller.historyItems)
    local profit = HistoryView.summary(rows, "net")
    local profit30 = HistoryView.summary(month, "net")
    profit = { today = profit.today, todayDay = profit.todayDay, usual = profit30.usual, enough = profit30.enough }
    profit.compare = HistoryView.profitCompare(profit)
    profit.atLoss = type(profit.today) == "number" and profit.today <= 0
    if itemID then
        local series = seriesOf(itemID)
        days = History.dailySeries(series, now, period)
        summary = HistoryView.summary(days)
        usual30 = HistoryView.summary(History.dailySeries(series, now, History.USUAL_DAYS))
        local usual = History.usual(series, now)
        usual30.usual = usual and usual.price or nil
        usual30.enough = usual ~= nil
        weekdayDays = days
    else
        field = view
        days = rows
        summary = HistoryView.summary(days, field)
        usual30 = HistoryView.summary(month, field)
        weekdayDays = viewDays(days, field)
    end
    summary.usual, summary.enough = usual30.usual, usual30.enough
    local status = "ok"
    if not summary.enough then status = "nodata" elseif entry.active ~= true then status = "paused" end
    return {
        recipe = recipe, items = items, view = view, period = period,
        chart = { days = days, field = field, usual = summary.usual, period = period, newest = History.dayOf(now) },
        summary = summary,
        weekday = History.weekdayProfile(weekdayDays, summary.usual),
        status = status, paused = entry.active ~= true,
        measures = usual30.measures, days = usual30.daysCovered,
        market = Controller.marketName(),
        goal = goal, profit = profit,
        compare = view == "net" and profit.compare or HistoryView.compare(summary, goal ~= "buy"),
        commission = Util.round((cut or 0) * 10000) / 100,
    }
end

-- Opens the History window on a tracked recipe (the window arrives with step 3, Task 2).
function Controller.openHistory(recipeID)
    local window = ns.HistoryWindow
    if type(window) ~= "table" then return end
    if type(window.show) == "function" then window.show() end
    if type(window.select) == "function" then window.select(recipeID) end
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

-- Every item a tracked recipe's history could hold, whoever is playing: reagents, crafted
-- item and every disenchant material its crafted item can give, as if the character knew
-- Enchanting (Controller.historyItems depends on the character and on the item cache).
-- `complete` is false while the crafted item's info (or item level) is not loaded: its
-- disenchant materials are then unknown.
function Controller.historyItemsAll(recipe)
    local info = Controller.itemInfo(recipe.outputItemID)
    local ids = Evaluate.wantedItems(recipe, Controller.itemInfo, Disenchant.lookup, true)
    return ids, info ~= nil and Util.isFinite(info.ilvl)
end

-- Deletes, in every market (other rulesets and factions too), the history series of a recipe
-- that was just removed from the tracked list. Conservative: only an id of that recipe's own
-- list goes, and only when no remaining tracked recipe (active or paused) could need it; while
-- a remaining recipe's list is incomplete (item not loaded), that recipe could need any
-- disenchant material: only the removed recipe's own reagents and crafted item can go, and
-- never one that is a disenchant material (a Lesser Magic Essence reagent, say). Current
-- prices stay.
local function deleteSeriesOf(recipe)
    local candidates = Controller.historyItemsAll(recipe)
    local own = { [recipe.outputItemID] = true }
    for _, r in ipairs(recipe.reagents) do own[r.itemID] = true end
    local keep, othersComplete = {}, true
    for _, entry in ipairs(CraftProfitDB.tracked) do
        local ids, complete = Controller.historyItemsAll(entry.recipe)
        for _, id in ipairs(ids) do keep[id] = true end
        if not complete then othersComplete = false end
    end
    if not othersComplete then
        for _, bracket in ipairs(Disenchant.brackets) do
            for _, result in ipairs(bracket.results) do keep[result.itemID] = true end
        end
    end
    for _, market in pairs(CraftProfitDB.markets) do
        if type(market) == "table" and type(market.series) == "table" then
            for _, id in ipairs(candidates) do
                if not keep[id] and (othersComplete or own[id]) then market.series[id] = nil end
            end
        end
    end
end

-- Stops tracking the n-th tracked recipe and deletes its history (items another tracked
-- recipe uses keep theirs). Returns the recipe's name, or nil when there is no such entry.
local function removeTracked(index)
    local entry = CraftProfitDB.tracked[index]
    if not entry or not History.remove(CraftProfitDB, index) then return nil end
    deleteSeriesOf(entry.recipe)
    return Controller.recipeName(entry.recipe)
end

-- Pauses (false) or resumes (true) the tracking of a recipe; its recorded history stays,
-- and a paused recipe still counts as tracked (limit, pruning).
function Controller.setHistoryActive(recipeID, active)
    local _, entry = History.find(CraftProfitDB, recipeID)
    if not entry then return false end
    if active then History.track(CraftProfitDB, entry.recipe) else History.pause(CraftProfitDB, recipeID) end
    Controller.refresh()
    return true
end

-- The History window's Delete: stops tracking the recipe and deletes its history.
function Controller.deleteHistory(recipeID)
    local index = History.find(CraftProfitDB, recipeID)
    local name = index and removeTracked(index)
    if not name then return false end
    say(string.format(L.HISTORY_DELETED, name))
    Controller.refresh()
    return true
end

-- /cp history: opens the History window; /cp history <n>: opens it on the n-th tracked
-- recipe; /cp history list: the tracked recipes in chat; /cp history remove <n>: deletes one.
function Controller.historyCommand(arg)
    local tracked = CraftProfitDB.tracked
    arg = (type(arg) == "string" and arg or ""):match("^%s*(.-)%s*$")
    -- A tracked entry by its number: a whole number from 1 to the list's length, else nil.
    local function entryAt(text)
        local n = Util.id(tonumber(text))
        return n and tracked[n] and n or nil
    end
    if arg == "" then
        if ns.HistoryWindow then ns.HistoryWindow.show() end
        return
    end
    if tonumber(arg) then
        local n = entryAt(arg)
        if n then Controller.openHistory(tracked[n].recipe.recipeID) else say(L.HISTORY_NO_SUCH) end
        return
    end
    local removeArg = arg:match("^remove%s+(%S+)$")
    if removeArg and tonumber(removeArg) then
        local n = entryAt(removeArg)
        local name = n and removeTracked(n)
        if name then
            say(string.format(L.HISTORY_REMOVED, name))
            Controller.refresh()
        else
            say(L.HISTORY_NO_SUCH)
        end
        return
    end
    if arg ~= "list" then
        say(L.SLASH_HELP)
        return
    end
    if #tracked == 0 then
        say(L.HISTORY_EMPTY)
        return
    end
    say(string.format(L.HISTORY_HEADER, #tracked, History.MAX_TRACKED))
    for i, entry in ipairs(tracked) do
        say(string.format("%d. %s (%s)", i, Controller.recipeName(entry.recipe),
            entry.active and L.TRACK_ACTIVE or L.TRACK_PAUSED))
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
