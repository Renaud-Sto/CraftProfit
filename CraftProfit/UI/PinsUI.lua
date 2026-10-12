-- The pinned-recipes section of the window, on the native kit, shown while the AH is
-- open, with the "Refresh pinned", "Scan AH" and "Leveling" buttons. It also runs the
-- main window's "Refresh recipe" search (startSearch with that one recipe).
local _, ns = ...
local L = ns.L
local Native, Colors = ns.Native, ns.Colors
-- Pure layout maths (panelHeight).
local Layout = ns.Layout

local PinsUI = {}
ns.PinsUI = PinsUI

local ROW_H = 18
local VISIBLE = 6
local BUTTON_H = Native.BUTTON_H
local BUTTON_GAP = 6
-- The game's small button height, for the sort button in the panel header.
local SORT_H = 18
-- Raised 1 px above the geometric centre: the title's capitals sit above the middle of their
-- line box (room for descenders), so a centred button looked too low next to them.
local SORT_LIFT = 1.5
local SORT_W = 120
-- Two lines of the small font: a long translated status wraps rather than being cut.
local STATUS_H = 28
local FOOTER_H = BUTTON_H + BUTTON_GAP + BUTTON_H + BUTTON_GAP + STATUS_H
local SEARCH_TIMEOUT = 6
local TICK_SECONDS = 0.2
local SCAN_REPLY_TIMEOUT = 15

local ctl
local host, panel, statusText
-- The widgets, exposed for tests.
local parts = { rows = {} }
local rows = parts.rows
local offset = 0
local queue, ticker
-- A miss of one kind is named when there are at most this many of it, else counted.
local NAMED_MAX = 2

PinsUI.parts = parts
PinsUI.FOOTER_H = FOOTER_H
PinsUI.state = "idle"
PinsUI.status = ""

function PinsUI.setStatus(text)
    PinsUI.status = text
    if statusText then statusText:SetText(text) end
end
local setStatus = PinsUI.setStatus

-- True when the recipe's crafted item can never be sold at the AH (bind on pickup): its
-- price is not worth a search (the AH tile already says n/a). When the item info is not
-- loaded yet, the binding is unknown: it is searched, as before.
local function unsellableOutput(recipe, itemInfo)
    -- The same rule as Evaluate and Controller.historyItems.
    if not ns.Evaluate.isBindOnPickup(itemInfo(recipe.outputItemID)) then return false end
    -- Also one of its own reagents (unlikely): the reagent still needs its price.
    for _, r in ipairs(recipe.reagents or {}) do
        if r.itemID == recipe.outputItemID then return false end
    end
    return true
end

-- Item ids whose prices all the given recipes need, each listed once. A crafted item bound
-- on pickup is left out (it cannot be sold at the AH), so it is never searched nor counted
-- in the summary; its reagents and disenchant materials are kept.
function PinsUI.wantedFor(pins, itemInfo, lookup, knowsEnchanting)
    local ids, seen = {}, {}
    for _, recipe in ipairs(pins) do
        local skip = unsellableOutput(recipe, itemInfo) and recipe.outputItemID or nil
        for _, id in ipairs(ns.Evaluate.wantedItems(recipe, itemInfo, lookup, knowsEnchanting)) do
            if id ~= skip and not seen[id] then
                seen[id] = true
                ids[#ids + 1] = id
            end
        end
    end
    return ids
end

-- Pinned recipes with their evaluation, in display order: most profitable first, or
-- cheapest cost per point first.
function PinsUI.orderedPins(pins, sortMode, evaluate)
    local items, entries = {}, {}
    local byPoint = sortMode == ns.DB.SORT_POINT
    for i, recipe in ipairs(pins) do
        local result = evaluate(recipe)
        items[i] = { recipe = recipe, result = result }
        local pp = result.perPoint
        entries[i] = byPoint and { cost = pp and pp.cost, chance = pp and pp.chance } or { net = result.net }
    end
    local order = byPoint and ns.Core.rankByPointCost(entries) or ns.Core.rankByNet(entries)
    local sorted = {}
    for i, index in ipairs(order) do sorted[i] = items[index] end
    return sorted
end

-- Amounts with the game's coin icons. The controller's own formatter when this list was
-- never initialised: the pinned window shares rowValue.
local function fmt(copper)
    return (ctl or ns.Controller).fmt(copper)
end

-- Text and colour ({ r, g, b, a }) of the value of one ordered pin (`item.recipe`,
-- `item.result`): its cost per point, or its net profit; "?" when it is unknown. Shared by
-- this list and the pinned window.
function PinsUI.rowValue(item, byPoint)
    local result = item.result
    if byPoint then
        local text, tone = ns.Present.pointRow(L, fmt, result.perPoint, result)
        return text, Colors.tone(tone, "muted")
    elseif result.net ~= nil then
        return fmt(result.net), result.net >= 0 and Colors.FIXED.profit or Colors.FIXED.loss
    end
    return ns.Present.unknownText(L, result), Colors.text("muted")
end

function PinsUI.refresh()
    -- Hidden (AH closed): nothing to draw, so no pin is evaluated. onAHOpen refreshes the
    -- list when it shows again.
    if not host or not host:IsShown() then return end
    local pins = CraftProfitCharDB.pins
    local byPoint = CraftProfitCharDB.sortMode == ns.DB.SORT_POINT
    local ordered = PinsUI.orderedPins(pins, CraftProfitCharDB.sortMode, ctl.evaluate)
    offset = math.max(0, math.min(offset, #pins - VISIBLE))
    local currentID = ctl.currentRecipeID()

    -- The count follows every pin, unpin and limit change: each ends in Controller.refresh.
    panel:setTitle(ctl.pinsTitle())
    parts.sort:setText(byPoint and L.SORT_POINT or L.SORT_NET)
    parts.search:setText(L.SEARCH_PRICES)
    parts.scan:setText(L.SCAN)
    parts.level:setText(L.LEVEL_BUTTON)
    parts.history:setText(L.HISTORY_BUTTON)
    parts.empty:SetText(L.PINS_EMPTY)
    parts.empty:SetShown(#pins == 0)

    for i = 1, VISIBLE do
        local row, item = rows[i], ordered[offset + i]
        if item then
            local recipe = item.recipe
            row.recipeID = recipe.recipeID
            row.name:SetText(ctl.recipeName(recipe))
            -- The difficulty stored with the pin, kept up to date while the profession
            -- window is open; a pin without one keeps the plain text colour.
            local nc = Colors.FIXED[recipe.difficulty] or Colors.text("main")
            row.name:SetTextColor(nc[1], nc[2], nc[3], nc[4])
            local text, c = PinsUI.rowValue(item, byPoint)
            row.value:SetText(text)
            row.value:SetTextColor(c[1], c[2], c[3], c[4])
            row.selected:SetShown(recipe.recipeID == currentID)
            row:Show()
        else
            row.recipeID = nil
            row:Hide()
        end
    end

    local shownRows = math.max(1, math.min(#pins, VISIBLE))
    local panelH = Layout.panelHeight(shownRows, ROW_H)
    panel.frame:SetHeight(panelH)
    parts.bar:update(#pins, VISIBLE, offset)
    local top = panelH + ns.Window.GAP
    parts.search:ClearAllPoints()
    parts.search:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -top)
    parts.scan:ClearAllPoints()
    parts.scan:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, -top)
    parts.level:ClearAllPoints()
    parts.level:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -top - BUTTON_H - BUTTON_GAP)
    parts.history:ClearAllPoints()
    parts.history:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, -top - BUTTON_H - BUTTON_GAP)
    statusText:ClearAllPoints()
    statusText:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -top - (BUTTON_H + BUTTON_GAP) * 2)
    host:SetHeight(top + FOOTER_H)
    ns.Window.relayout()
end

-- What one kind of miss shows: the item names when there are at most NAMED_MAX of them
-- (`ids`, named by `nameOf`, "#id" when it has no name yet), else the count.
local function missText(count, ids, nameOf)
    if type(ids) == "table" and #ids > 0 and #ids <= NAMED_MAX and #ids == count then
        local names = {}
        for i, id in ipairs(ids) do
            local name = type(nameOf) == "function" and nameOf(id) or nil
            names[i] = type(name) == "string" and name ~= "" and name or ("#" .. tostring(id))
        end
        return table.concat(names, ", ")
    end
    return tostring(count)
end

-- The status line after a search. The unit is a price: one per item searched (the reagents,
-- the crafted item and its disenchant materials). counts: ok (items whose search returned,
-- with or without listings), total, noListing (returned no usable listing), failed (did not
-- answer), and optionally noListingIDs / failedIDs (their item ids, to name them through
-- `nameOf(itemID)`). ok + failed = total for a search that ran to its end. "Updated" counts
-- only the prices actually stored (ok - noListing), so updated + no listing + no answer =
-- total. All stored: the short form; otherwise "x of y" and a fragment for each kind of miss.
function PinsUI.searchSummary(locale, counts, nameOf)
    local ok, total = counts.ok or 0, counts.total or 0
    local noListing, failed = counts.noListing or 0, counts.failed or 0
    local updated = math.max(0, ok - noListing)
    if updated == total and noListing == 0 and failed == 0 then
        return string.format(locale.SEARCH_UPDATED, updated)
    end
    local text = string.format(locale.SEARCH_UPDATED_OF, updated, total)
    if noListing > 0 then
        text = text .. string.format(locale.SEARCH_NO_LISTING, missText(noListing, counts.noListingIDs, nameOf))
    end
    if failed > 0 then
        text = text .. string.format(locale.SEARCH_NO_ANSWER, missText(failed, counts.failedIDs, nameOf))
    end
    return text
end

-- One ticker drives whichever queue runs (first pass, then the retry).
local function ensureTicker()
    if ticker or PinsUI.state ~= "running" then return end
    ticker = C_Timer.NewTicker(TICK_SECONDS, function()
        if queue then queue:tick(GetTime()) end
    end)
end

-- The whole search is over (both passes, or cancelled): one status, one history batch.
local function endSearch(state, text)
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    PinsUI.state = state
    setStatus(text)
    -- "Refresh recipe" comes back now that no search runs.
    ns.Window.updateRefreshButton()
    -- Once, at the very end: the prices stored by both passes make one batch.
    ctl.commitSearch()
    ctl.requestRefresh()
end

-- The item ids of a finished queue that did not answer.
local function failedOf(summary)
    local ids = {}
    for i, miss in ipairs(summary.failed) do ids[i] = miss.itemID end
    return ids
end

-- Runs one pass over `ids`: a fresh queue, its own no-listing list, progress shown with
-- `progressKey`, `onDone(summary, noListing)` at the end.
local function runPass(ids, progressKey, onDone)
    local noListing = {}
    queue = ns.PriceQueue.new({
        itemIDs = ids,
        timeout = SEARCH_TIMEOUT,
        send = ns.AH.search,
        onItem = function(itemID, listings, err)
            -- recordListings stores (and marks for history) only a usable listing, so an
            -- item retried after a miss is never counted twice.
            if not err and not ctl.recordListings(itemID, listings) then
                noListing[#noListing + 1] = itemID
            end
        end,
        onProgress = function(done, total)
            setStatus(string.format(L[progressKey], done, total))
            ctl.requestRefresh()
        end,
        onDone = function(summary) onDone(summary, noListing) end,
    })
    setStatus(string.format(L[progressKey], 0, #ids))
    queue:start(GetTime())
end

-- Second pass over the prices the first one missed (no answer or no listing): a search the
-- server dropped or answered too early often finds the price when asked again. The summary
-- counts both passes over the first pass's total: an item found now counts as updated.
local function retryPass(total, retry)
    runPass(retry, "SEARCH_RETRYING", function(summary, noListing)
        if summary.cancelled then
            endSearch("cancelled", L.SEARCH_CANCELLED)
            return
        end
        local failedIDs = failedOf(summary)
        -- Names read now: the items were just searched, so the game usually has them.
        endSearch("done", PinsUI.searchSummary(L, {
            ok = total - #failedIDs, total = total, noListing = #noListing, failed = #failedIDs,
            noListingIDs = noListing, failedIDs = failedIDs,
        }, ctl.itemName))
    end)
    ensureTicker()
end

local function firstPassDone(ids)
    return function(summary, noListing)
        if summary.cancelled then
            endSearch("cancelled", L.SEARCH_CANCELLED)
            return
        end
        local failedIDs = failedOf(summary)
        local missed = {}
        for _, id in ipairs(failedIDs) do missed[id] = true end
        for _, id in ipairs(noListing) do missed[id] = true end
        -- In the first pass's order; no third pass.
        local retry = {}
        for _, id in ipairs(ids) do
            if missed[id] then retry[#retry + 1] = id end
        end
        if #retry == 0 then
            endSearch("done", PinsUI.searchSummary(L, { ok = summary.ok, total = summary.total }, ctl.itemName))
        else
            retryPass(summary.total, retry)
        end
    end
end

-- Searches the AH, one item at a time, for everything `recipes` need: every pinned recipe
-- when nil ("Refresh pinned"), or the recipe on screen ("Refresh recipe"); then once more for
-- what that pass missed. Ignored while a search runs, so one never cancels or mixes into the
-- other.
function PinsUI.startSearch(recipes)
    if not ns.AH.isOpen then
        setStatus(L.SEARCH_NEED_AH)
        return
    end
    if queue and queue.state == "running" then return end
    if type(recipes) ~= "table" then recipes = CraftProfitCharDB.pins end
    local ids = PinsUI.wantedFor(recipes, ctl.itemInfo, ns.Data.Disenchant.lookup,
        ctl.knowsEnchanting())
    if #ids == 0 then
        -- Said rather than silent: the click did something, there was simply nothing to price.
        setStatus(L.SEARCH_NOTHING)
        return
    end
    PinsUI.state = "running"
    ns.Window.updateRefreshButton()
    -- wantedFor lists each item once, so the retry order follows the first pass's.
    runPass(ids, "SEARCHING", firstPassDone(ids))
    ensureTicker()
end

function PinsUI.scan()
    local ok, reason, left = ns.AH.requestSnapshot(GetTime())
    if ok then
        setStatus(L.SCAN_STARTED)
        -- The server ignores a scan inside its 15 minute window and sends nothing.
        local startedAt = GetTime()
        C_Timer.After(SCAN_REPLY_TIMEOUT, function()
            local replied = ns.AH.lastEventTime and ns.AH.lastEventTime >= startedAt
            if PinsUI.status == L.SCAN_STARTED and not replied then setStatus(L.SCAN_NO_REPLY) end
        end)
    elseif reason == "cooldown" then
        setStatus(string.format(L.SCAN_COOLDOWN, ns.Present.durationText(L, left) or "?"))
    else
        setStatus(L.SEARCH_NEED_AH)
    end
end

function PinsUI.onAHOpen(open)
    if not host then return end
    host:SetShown(open)
    if not open and queue and queue.state == "running" then queue:cancel() end
    if open then
        PinsUI.refresh()
    else
        -- The hidden list no longer takes room: the window shrinks (refresh would skip it).
        ns.Window.relayout()
    end
end

function PinsUI.onSearchResults(itemID, listings)
    if queue and queue.state == "running" then queue:results(itemID, listings, GetTime()) end
end

function PinsUI.init(controller)
    ctl = controller
    host = ns.Window.pinsHost()
    local window = ns.Window.frame()
    local inner = ns.Window.INNER_WIDTH
    local half = math.floor((inner - ns.Window.GAP) / 2)

    panel = Native.panel(host, ctl.pinsTitle())
    parts.panel = panel
    panel.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    panel.frame:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
    panel.frame:SetHeight(Layout.panelHeight(1, ROW_H))

    -- The sort button lives in the panel header: the game's button at its small height,
    -- centred on the header strip (PANEL_EDGE + (HEAD_H - SORT_H) / 2 from the top).
    parts.sort = Native.button(panel.frame, "", { width = SORT_W, onClick = function() ctl.toggleSort() end })
    parts.sort:SetHeight(SORT_H)
    parts.sort:SetPoint("TOPRIGHT", panel.frame, "TOPRIGHT", -(Native.PANEL_EDGE + 8),
        -(Native.PANEL_EDGE + (Native.HEAD_H - SORT_H) / 2 - SORT_LIFT))
    -- The header frame is a child of the panel frame, one level up: lift the button above
    -- it (a header hit area, if any, stays at the panel frame's level).
    local level = panel.frame:GetFrameLevel()
    if type(level) == "number" then parts.sort:SetFrameLevel(level + 2) end
    -- A long (translated) title stops before the button instead of running under it.
    panel.title:SetPoint("RIGHT", parts.sort, "LEFT", -8, 0)

    local body = panel.body
    -- The game's grey small font: the muted colour without painting it.
    parts.empty = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    parts.empty:SetPoint("TOPLEFT", body, "TOPLEFT", 8, -2)

    for i = 1, VISIBLE do
        local row = Native.listRow(body, i, ROW_H, Native.SCROLL_W + 6)
        row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.value:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.value:SetJustifyH("RIGHT")
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.name:SetPoint("RIGHT", row.value, "LEFT", -8, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        -- The rows cover the window's body: a drag on them still moves the window, and the
        -- click that ends it selects nothing.
        if window then Native.forwardDrag(row, window) end
        row:SetScript("OnClick", function(self)
            if self.dragged == true then return end
            if self.recipeID then ctl.selectPin(self.recipeID) end
        end)
        rows[i] = row
    end

    parts.bar = Native.scrollbar(body, VISIBLE * ROW_H)
    parts.bar.frame:SetPoint("TOPRIGHT", body, "TOPRIGHT", -2, 0)
    parts.bar.onScroll = function(newOffset)
        offset = newOffset
        PinsUI.refresh()
    end

    -- UIPanelButtonTemplate is the game's red panel button: search keeps the primary
    -- place (first, top left), all three keep their half-width.
    parts.search = Native.button(host, "", { width = half, onClick = function() PinsUI.startSearch() end })
    parts.scan = Native.button(host, "", { width = half, onClick = PinsUI.scan })
    parts.level = Native.button(host, "", { width = half, onClick = function()
        if ns.LevelingUI then ns.LevelingUI.toggle() end
    end })
    -- Right of Leveling, on the same row: the footer keeps its height.
    parts.history = Native.button(host, "", { width = half, onClick = function()
        if ns.HistoryWindow then ns.HistoryWindow.toggle() end
    end })
    statusText = host:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    statusText:SetWidth(inner)
    -- Two lines in a fixed box: a longer status (long item names) is cut with "...", never
    -- drawn past the window's bottom.
    statusText:SetHeight(STATUS_H)
    statusText:SetWordWrap(true)
    if type(statusText.SetMaxLines) == "function" then statusText:SetMaxLines(2) end
    statusText:SetJustifyH("LEFT")
    statusText:SetJustifyV("TOP")
    parts.status = statusText

    host:EnableMouseWheel(true)
    host:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta)
        PinsUI.refresh()
    end)
    -- No refresh here: it evaluates every pin, which opens the market before the faction
    -- and hardcore state can be trusted (ADDON_LOADED). onAHOpen shows and refreshes it.
    host:Hide()
end
