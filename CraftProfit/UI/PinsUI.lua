-- The pinned-recipes section of the window, shown while the AH is open, with
-- the "Search prices" and "Scan AH" buttons.
local _, ns = ...
local L = ns.L

local PinsUI = {}
ns.PinsUI = PinsUI

local PAD = 10
local ROW_H = 18
local VISIBLE = 6
local TOP = 26
local FOOTER_H = 50
local SEARCH_TIMEOUT = 6
local TICK_SECONDS = 0.2

local COLORS = {
    profit = { 0.35, 0.90, 0.45 },
    loss = { 1.00, 0.40, 0.35 },
    muted = { 0.65, 0.65, 0.70 },
}

local ctl
local host, header, emptyText, statusText, searchButton, scanButton
local rows = {}
local offset = 0
local queue, ticker
local notFound = 0
local SCAN_REPLY_TIMEOUT = 15

PinsUI.state = "idle"
PinsUI.status = ""

function PinsUI.setStatus(text)
    PinsUI.status = text
    if statusText then statusText:SetText(text) end
end
local setStatus = PinsUI.setStatus

-- Item ids whose prices all the pinned recipes need, each listed once.
function PinsUI.wantedFor(pins, itemInfo, lookup)
    local ids, seen = {}, {}
    for _, recipe in ipairs(pins) do
        for _, id in ipairs(ns.Evaluate.wantedItems(recipe, itemInfo, lookup)) do
            if not seen[id] then
                seen[id] = true
                ids[#ids + 1] = id
            end
        end
    end
    return ids
end

function PinsUI.refresh()
    if not host then return end
    local pins = CraftProfitCharDB.pins
    offset = math.max(0, math.min(offset, #pins - VISIBLE))
    local currentID = ctl.currentRecipeID()

    header:SetText(L.PINS_TITLE)
    searchButton:SetText(L.SEARCH_PRICES)
    scanButton:SetText(L.SCAN)
    emptyText:SetText(L.PINS_EMPTY)
    emptyText:SetShown(#pins == 0)

    for i = 1, VISIBLE do
        local row, recipe = rows[i], pins[offset + i]
        if recipe then
            local result = ctl.evaluate(recipe)
            row.recipeID = recipe.recipeID
            row.name:SetText(recipe.name ~= "" and recipe.name or ("#" .. recipe.recipeID))
            if result.net ~= nil then
                row.value:SetText(ctl.fmt(result.net))
                local c = result.net >= 0 and COLORS.profit or COLORS.loss
                row.value:SetTextColor(c[1], c[2], c[3])
            else
                row.value:SetText("?")
                row.value:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])
            end
            row.selected:SetShown(recipe.recipeID == currentID)
            row:Show()
        else
            row.recipeID = nil
            row:Hide()
        end
    end

    local shown = math.max(1, math.min(#pins, VISIBLE))
    local top = TOP + shown * ROW_H + 6
    searchButton:ClearAllPoints()
    searchButton:SetPoint("TOPLEFT", host, "TOPLEFT", PAD, -top)
    scanButton:ClearAllPoints()
    scanButton:SetPoint("TOPRIGHT", host, "TOPRIGHT", -PAD, -top)
    statusText:ClearAllPoints()
    statusText:SetPoint("TOPLEFT", host, "TOPLEFT", PAD, -top - 26)
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
    ctl.requestRefresh()
end

-- Searches the AH, one item at a time, for everything the pinned recipes need.
function PinsUI.startSearch()
    if not ns.AH.isOpen then
        setStatus(L.SEARCH_NEED_AH)
        return
    end
    if queue and queue.state == "running" then return end
    local ids = PinsUI.wantedFor(CraftProfitCharDB.pins, ctl.itemInfo, ns.Data.Disenchant.lookup)
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

    header = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", host, "TOPLEFT", PAD, -6)
    emptyText = host:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyText:SetPoint("TOPLEFT", host, "TOPLEFT", PAD, -TOP - 2)

    for i = 1, VISIBLE do
        local row = CreateFrame("Button", nil, host)
        row:SetSize(ns.Window.WIDTH - PAD * 2, ROW_H)
        row:SetPoint("TOPLEFT", host, "TOPLEFT", PAD, -(TOP + (i - 1) * ROW_H))
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.selected = row:CreateTexture(nil, "BACKGROUND")
        row.selected:SetAllPoints()
        row.selected:SetColorTexture(1, 1, 1, 0.08)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.name:SetWidth(ns.Window.WIDTH - PAD * 2 - 90)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.value:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.value:SetJustifyH("RIGHT")
        row:SetScript("OnClick", function(self)
            if self.recipeID then ctl.selectPin(self.recipeID) end
        end)
        rows[i] = row
    end

    searchButton = CreateFrame("Button", nil, host, "UIPanelButtonTemplate")
    searchButton:SetSize(120, 22)
    searchButton:SetScript("OnClick", PinsUI.startSearch)
    scanButton = CreateFrame("Button", nil, host, "UIPanelButtonTemplate")
    scanButton:SetSize(90, 22)
    scanButton:SetScript("OnClick", PinsUI.scan)
    statusText = host:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    statusText:SetWidth(ns.Window.WIDTH - PAD * 2)
    statusText:SetJustifyH("LEFT")

    host:EnableMouseWheel(true)
    host:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta)
        PinsUI.refresh()
    end)
    host:Hide()
end
