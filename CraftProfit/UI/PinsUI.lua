-- The pinned-recipes section of the window, on the native kit, shown while the AH is
-- open, with the "Search prices", "Scan AH" and "Leveling" buttons.
local _, ns = ...
local L = ns.L
local Native, Colors = ns.Native, ns.Colors
-- Only the kit's pure layout maths (panelHeight) until it moves out of Kit.
local Kit = ns.Kit

local PinsUI = {}
ns.PinsUI = PinsUI

local ROW_H = 18
local VISIBLE = 6
local BUTTON_H = Native.BUTTON_H
local BUTTON_GAP = 6
-- The game's small button height, for the sort button in the panel header.
local SORT_H = 18
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
local notFound = 0

PinsUI.parts = parts
PinsUI.FOOTER_H = FOOTER_H
PinsUI.state = "idle"
PinsUI.status = ""

function PinsUI.setStatus(text)
    PinsUI.status = text
    if statusText then statusText:SetText(text) end
end
local setStatus = PinsUI.setStatus

-- Item ids whose prices all the pinned recipes need, each listed once.
function PinsUI.wantedFor(pins, itemInfo, lookup, knowsEnchanting)
    local ids, seen = {}, {}
    for _, recipe in ipairs(pins) do
        for _, id in ipairs(ns.Evaluate.wantedItems(recipe, itemInfo, lookup, knowsEnchanting)) do
            if not seen[id] then
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

-- Text and colour of a row's value in the cost-per-point view.
local function pointValue(perPoint)
    local text, tone = ns.Present.pointRow(L, ctl.fmt, perPoint)
    local colour = tone == "profit" and Colors.FIXED.profit or tone == "loss" and Colors.FIXED.loss
        or Colors.text("muted")
    return text, colour
end

function PinsUI.refresh()
    if not host then return end
    local pins = CraftProfitCharDB.pins
    local byPoint = CraftProfitCharDB.sortMode == ns.DB.SORT_POINT
    local ordered = PinsUI.orderedPins(pins, CraftProfitCharDB.sortMode, ctl.evaluate)
    offset = math.max(0, math.min(offset, #pins - VISIBLE))
    local currentID = ctl.currentRecipeID()

    panel:setTitle(L.PANEL_PINS)
    parts.sort:setText(byPoint and L.SORT_POINT or L.SORT_NET)
    parts.search:setText(L.SEARCH_PRICES)
    parts.scan:setText(L.SCAN)
    parts.level:setText(L.LEVEL_BUTTON)
    parts.empty:SetText(L.PINS_EMPTY)
    parts.empty:SetShown(#pins == 0)

    for i = 1, VISIBLE do
        local row, item = rows[i], ordered[offset + i]
        if item then
            local recipe, result = item.recipe, item.result
            row.recipeID = recipe.recipeID
            row.name:SetText(recipe.name ~= "" and recipe.name or ("#" .. recipe.recipeID))
            -- The difficulty stored with the pin, kept up to date while the profession
            -- window is open; a pin without one keeps the plain text colour.
            local nc = Colors.FIXED[recipe.difficulty] or Colors.text("main")
            row.name:SetTextColor(nc[1], nc[2], nc[3], nc[4])
            local text, c
            if byPoint then
                text, c = pointValue(result.perPoint)
            elseif result.net ~= nil then
                text = ctl.fmt(result.net)
                c = result.net >= 0 and Colors.FIXED.profit or Colors.FIXED.loss
            else
                text, c = L.UNKNOWN, Colors.text("muted")
            end
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
    local panelH = Kit.panelHeight(shownRows, ROW_H)
    panel.frame:SetHeight(panelH)
    parts.bar:update(#pins, VISIBLE, offset)
    local top = panelH + ns.Window.GAP
    parts.search:ClearAllPoints()
    parts.search:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -top)
    parts.scan:ClearAllPoints()
    parts.scan:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, -top)
    parts.level:ClearAllPoints()
    parts.level:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -top - BUTTON_H - BUTTON_GAP)
    statusText:ClearAllPoints()
    statusText:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -top - (BUTTON_H + BUTTON_GAP) * 2)
    host:SetHeight(top + FOOTER_H)
    ns.Window.relayout()
end

local function finishSearch(summary)
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    if summary.cancelled then
        PinsUI.state = "cancelled"
        setStatus(L.SEARCH_CANCELLED)
    else
        PinsUI.state = "done"
        local missing = #summary.failed + notFound
        if missing > 0 then
            setStatus(string.format(L.SEARCH_PARTIAL, missing))
        else
            setStatus(L.SEARCH_DONE)
        end
    end
    ctl.commitSearch()
    ctl.requestRefresh()
end

-- Searches the AH, one item at a time, for everything the pinned recipes need.
function PinsUI.startSearch()
    if not ns.AH.isOpen then
        setStatus(L.SEARCH_NEED_AH)
        return
    end
    if queue and queue.state == "running" then return end
    local ids = PinsUI.wantedFor(CraftProfitCharDB.pins, ctl.itemInfo, ns.Data.Disenchant.lookup,
        ctl.knowsEnchanting())
    if #ids == 0 then return end
    notFound = 0
    queue = ns.PriceQueue.new({
        itemIDs = ids,
        timeout = SEARCH_TIMEOUT,
        send = ns.AH.search,
        onItem = function(itemID, listings, err)
            if not err and not ctl.recordListings(itemID, listings) then notFound = notFound + 1 end
        end,
        onProgress = function(done, total)
            setStatus(string.format(L.SEARCHING, done, total))
            ctl.requestRefresh()
        end,
        onDone = finishSearch,
    })
    PinsUI.state = "running"
    setStatus(string.format(L.SEARCHING, 0, #ids))
    queue:start(GetTime())
    if queue.state == "running" then
        ticker = C_Timer.NewTicker(TICK_SECONDS, function() queue:tick(GetTime()) end)
    end
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
    PinsUI.refresh()
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

    panel = Native.panel(host, L.PANEL_PINS)
    parts.panel = panel
    panel.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    panel.frame:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
    panel.frame:SetHeight(Kit.panelHeight(1, ROW_H))

    -- The sort button lives in the panel header: the game's button at its small height,
    -- centred on the header strip (PANEL_EDGE + (HEAD_H - SORT_H) / 2 from the top).
    parts.sort = Native.button(panel.frame, "", { width = SORT_W, onClick = function() ctl.toggleSort() end })
    parts.sort:SetHeight(SORT_H)
    parts.sort:SetPoint("TOPRIGHT", panel.frame, "TOPRIGHT", -(Native.PANEL_EDGE + 8),
        -(Native.PANEL_EDGE + (Native.HEAD_H - SORT_H) / 2))
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
    parts.search = Native.button(host, "", { width = half, onClick = PinsUI.startSearch })
    parts.scan = Native.button(host, "", { width = half, onClick = PinsUI.scan })
    parts.level = Native.button(host, "", { width = half, onClick = function()
        if ns.LevelingUI then ns.LevelingUI.toggle() end
    end })
    statusText = host:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    statusText:SetWidth(inner)
    statusText:SetJustifyH("LEFT")
    statusText:SetJustifyV("TOP")

    host:EnableMouseWheel(true)
    host:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta)
        PinsUI.refresh()
    end)
    -- No refresh here: it evaluates every pin, which opens the market before the faction
    -- and hardcore state can be trusted (ADDON_LOADED). onAHOpen shows and refreshes it.
    host:Hide()
end
