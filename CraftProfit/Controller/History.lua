-- Controller: price history (the items a tracked recipe records, the History window's data
-- and its cache, pause, delete, /cp history).
local _, ns = ...
local Util, Evaluate, History, HistoryView = ns.Util, ns.Evaluate, ns.History, ns.HistoryView
local Disenchant = ns.Data.Disenchant
local L = ns.L

local Controller = ns.Controller
local say = Controller.say

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
Controller.HISTORY_FRESH = 86400   -- percentages only when the newest measurement is this recent

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
    local flip
    local function isFresh(ids)
        local newest = newestPoint(ids, seriesOf, now)
        local ok = newest ~= nil and now - newest <= Controller.HISTORY_FRESH
        if ok then
            local at = newest + Controller.HISTORY_FRESH + 1
            if not flip or at < flip then flip = at end
        end
        return ok
    end
    local materialsFresh, saleFresh = isFresh(reagents), isFresh(sale)
    return materialsFresh or saleFresh, materialsFresh, saleFresh, flip
end

-- Cache of historyList and historyData: the History window refreshes with every controller
-- refresh, and recomputing every tracked recipe's days each time is the costly part. A
-- result is reused while its key holds: Controller.historyVersion (bumped by
-- historyChanged: a record, a pause or resume, a track, a delete, an item loaded), the
-- market, the commission, whether Enchanting is known, and the local day; and while no
-- fresh flag has expired (freshness's flip time). Callers must not modify a result.
Controller.historyVersion = 0
function Controller.historyChanged()
    Controller.historyVersion = Controller.historyVersion + 1
end

local historyCache = { key = nil, entries = {} }

-- A fresh flag expires by itself, with nothing else to refresh the windows: one timer asks
-- for a refresh at the soonest expiry of the cached results (+1 s, so time() has passed
-- it), so a percentage shown in the main window or the History list goes away once its
-- data are a day old. Replaced (the old one does nothing) when the soonest expiry changes;
-- none while nothing expires. A result already expired is left out: it is recomputed when
-- next asked for.
local expiry = { at = nil, token = 0 }

local function scheduleExpiry(now)
    local soonest
    for _, entry in pairs(historyCache.entries) do
        local at = entry.expires
        if at and at > now and (not soonest or at < soonest) then soonest = at end
    end
    if soonest == expiry.at then return end
    expiry.token = expiry.token + 1
    expiry.at = soonest
    if not soonest then return end
    local token = expiry.token
    C_Timer.After(soonest - now + 1, function()
        if token ~= expiry.token then return end
        expiry.at = nil
        Controller.requestRefresh()
    end)
end

local function cached(slot, now, compute)
    local key = table.concat({ Controller.historyVersion, Controller.marketKey(),
        tostring(CraftProfitDB.settings.cut), tostring(Controller.knowsEnchanting()),
        tostring(History.dayOf(now)) }, "|")
    if historyCache.key ~= key then historyCache.key, historyCache.entries = key, {} end
    local hit = historyCache.entries[slot]
    if hit and (not hit.expires or now < hit.expires) then return hit.value end
    local value, expires = compute()
    historyCache.entries[slot] = { value = value, expires = expires }
    scheduleExpiry(now)
    return value
end

-- The tracked recipes for the window's list, in saved order. `indicator` holds the percentages
-- (HistoryView.indicators) only when there is enough data and the newest measurement is
-- under 24 hours old (`fresh`: a reagent or the sold crafted item, see freshness), each
-- one only when its own items are (materials: a reagent, sale: the crafted item); older
-- data never shows as today's. atLoss: when the crafted item's sale price is fresh too,
-- whether crafting and selling at the auction house loses money (or earns 0) on the newest
-- day (indicators' netToday <= 0); nil when unknown (stale data or sale price, no sale).
local function computeList(now)
    local seriesOf, cut = seriesReader(), CraftProfitDB.settings.cut
    local out, expires = {}, nil
    for _, entry in ipairs(CraftProfitDB.tracked) do
        local fresh, materialsFresh, saleFresh, flip = freshness(entry.recipe, seriesOf, now)
        if flip and (not expires or flip < expires) then expires = flip end
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
    return out, expires
end

function Controller.historyList()
    local now = time()
    return cached("list", now, function() return computeList(now) end)
end

-- The main window's indicators for one recipe, from the cached historyList entry (no
-- computation of its own): { materials, sale (HistoryView comparisons, each nil when not
-- fresh), atLoss (true only when known), recipeID }, or nil unless the recipe is tracked,
-- active and has an indicator (fresh data, enough days). Callers must not modify it.
function Controller.windowHistory(recipeID)
    for _, entry in ipairs(Controller.historyList()) do
        if entry.recipe.recipeID == recipeID then
            local ind = entry.indicator
            if not entry.active or type(ind) ~= "table" then return nil end
            return { materials = ind.materials, sale = ind.sale, atLoss = entry.atLoss == true, recipeID = recipeID }
        end
    end
    return nil
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
-- The usual price, `enough` and the typical week always cover 30 days (History.usual,
-- HistoryView.summary of 30 days), whatever the period; the other key figures cover the period. status: "nodata"
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
-- not counted. weekday: History.weekdayProfile of 30 days, in money (gap) in the Profit view;
-- weekdayEmpty: why it has no bar, "days" (no weekday measured twice) or "usual" (no usable
-- usual price), nil when it has one. commission: the auction house cut in percent (5 for 0.05). fresh: as
-- historyList's (a reagent or the sold crafted item measured within HISTORY_FRESH); stale
-- figures are still shown, dated, but never as good news.
-- thin: the items that hold the recipe back, at most THIN_MAX in icon order (reagents, then
-- the crafted item when sold; disenchant materials are not needed to judge it): each one
-- with fewer than History.USUAL_MIN_DAYS days in its own 30 day series, { itemID, name,
-- measures, days } (0 and 0 when never measured).
local THIN_MAX = 3
local function computeData(recipeID, view, period, now)
    local _, entry = History.find(CraftProfitDB, recipeID)
    if not entry then return nil end
    local recipe = entry.recipe
    local seriesOf, cut = seriesReader(), CraftProfitDB.settings.cut
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
        local monthDays = History.dailySeries(series, now, History.USUAL_DAYS)
        usual30 = HistoryView.summary(monthDays)
        local usual = History.usual(series, now)
        usual30.usual = usual and usual.price or nil
        usual30.enough = usual ~= nil
        weekdayDays = monthDays
    else
        field = view
        days = rows
        summary = HistoryView.summary(days, field)
        usual30 = HistoryView.summary(month, field)
        weekdayDays = viewDays(month, field)
    end
    summary.usual, summary.enough = usual30.usual, usual30.enough
    local status = "ok"
    if not summary.enough then status = "nodata" elseif entry.active ~= true then status = "paused" end
    -- The profit's usual may be 0 or a loss: its typical week is in money.
    local weekday = History.weekdayProfile(weekdayDays, summary.usual, view == "net")
    local weekdayEmpty
    local filled, enoughDays = false, false
    for i = 1, 7 do
        if weekday[i].pct or weekday[i].gap then filled = true end
        if weekday[i].n >= History.WEEKDAY_MIN_DAYS then enoughDays = true end
    end
    if not filled then weekdayEmpty = enoughDays and "usual" or "days" end
    local fresh, _, _, expires = freshness(recipe, seriesOf, now)
    local thin = {}
    for _, group in ipairs({ "materials", "crafted" }) do
        for _, item in ipairs(items) do
            if item.group == group and #thin < THIN_MAX then
                local own = HistoryView.summary(History.dailySeries(seriesOf(item.itemID), now, History.USUAL_DAYS))
                if own.daysCovered < History.USUAL_MIN_DAYS then
                    thin[#thin + 1] = { itemID = item.itemID, name = item.name, measures = own.measures,
                        days = own.daysCovered }
                end
            end
        end
    end
    return {
        recipe = recipe, items = items, view = view, period = period,
        chart = { days = days, field = field, usual = summary.usual, period = period, newest = History.dayOf(now) },
        summary = summary,
        weekday = weekday, weekdayEmpty = weekdayEmpty,
        status = status, paused = entry.active ~= true,
        measures = usual30.measures, days = usual30.daysCovered,
        market = Controller.marketName(),
        goal = goal, profit = profit,
        compare = view == "net" and profit.compare or HistoryView.compare(summary, goal ~= "buy"),
        fresh = fresh, thin = thin,
        commission = Util.round((cut or 0) * 10000) / 100,
    }, expires
end

function Controller.historyData(recipeID, view, period)
    local now = time()
    return cached(tostring(recipeID) .. ":" .. tostring(view) .. ":" .. tostring(period), now,
        function() return computeData(recipeID, view, period, now) end)
end

-- Opens the History window on a tracked recipe (the window arrives with step 3, Task 2).
function Controller.openHistory(recipeID)
    local window = ns.HistoryWindow
    if type(window) ~= "table" then return end
    if type(window.show) == "function" then window.show() end
    if type(window.select) == "function" then window.select(recipeID) end
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
    Controller.historyChanged()
    deleteSeriesOf(entry.recipe)
    return Controller.recipeName(entry.recipe)
end

-- Pauses (false) or resumes (true) the tracking of a recipe; its recorded history stays,
-- and a paused recipe still counts as tracked (limit, pruning).
function Controller.setHistoryActive(recipeID, active)
    local _, entry = History.find(CraftProfitDB, recipeID)
    if not entry then return false end
    if active then History.track(CraftProfitDB, entry.recipe) else History.pause(CraftProfitDB, recipeID) end
    Controller.historyChanged()
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
