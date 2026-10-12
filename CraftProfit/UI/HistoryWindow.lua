-- The History window: the tracked recipes on the left (with the arrows of the newest
-- fresh data), on the right the chart of the chosen view (Result, Materials cost or one
-- item) over 7, 30 or 60 days, the key figures and the weekday strip. Only widgets: every
-- figure comes from Controller.historyList / historyData. Built on first open, never at
-- login; Escape closes it; refreshed only while shown (no per-frame work).
-- Under the figures, two actions for the selected recipe: Pause/Resume tracking (the
-- history stays) and Delete history, which asks for a second click on the button itself
-- within CONFIRM_SECONDS (no game dialog) before Controller.deleteHistory.
local _, ns = ...
local L = ns.L
local Native, Colors, Chart, Layout = ns.Native, ns.Colors, ns.Chart, ns.Layout

local HistoryWindow = {}
ns.HistoryWindow = HistoryWindow

local NAME = "CraftProfitHistoryWindow"
local WIDTH = 720
local PAD = Native.CONTENT_PAD
local GAP = 8
local CHROME_H = Native.INSET_TOP + Native.INSET_BOTTOM
local INNER_WIDTH = WIDTH - Native.INSET_LEFT - Native.INSET_RIGHT - PAD * 2
-- Left column: the information line, then the list panel.
local LEFT_W = 210
local INFO_H = 48
local ROW_H = 18
local VISIBLE = 12
local ARROWS_W = 70
-- Right column, top to bottom.
local RIGHT_W = INNER_WIDTH - LEFT_W - GAP
local VIEW_W = 150
local PERIOD_W = 72
local ICON = 24
local ICON_GAP = 4
-- Item icons in two rows of ICONS_PER_ROW (12 reagents, the crafted item and its
-- disenchant materials fit); the period buttons stack at the right of the button rows.
local ICONS_PER_ROW, ICON_ROWS = 10, 2
local HEADER_H = Native.BUTTON_H + 6 + ICON_ROWS * ICON + (ICON_ROWS - 1) * ICON_GAP
local CHART_H = 230
local NAMES_H = 12
local HOVER_H = 12
local FIGURE_ROW_H = 14
local FIGURE_LABEL_W = 110
local STATUS_H = 12
local ACTION_W = 220
local CONFIRM_SECONDS = 4
local ROW_GAP = 6
-- Estimated letter widths (the client cannot measure in tests), as OptionsUI.
local CHAR_W, SMALL_CHAR_W = 7, 6
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"
local PERIODS = { 7, 30, 60 }
local FIGURES = {
    { key = "today", label = "HISTORY_TODAY", field = "today", money = true },
    { key = "usual", label = "HISTORY_USUAL", field = "usual", money = true },
    { key = "low", label = "HISTORY_LOWEST", field = "low", money = true },
    { key = "high", label = "HISTORY_HIGHEST", field = "high", money = true },
    { key = "measures", label = "HISTORY_MEASURES", field = "measures" },
    { key = "days", label = "HISTORY_DAYS", field = "daysCovered" },
}

local ctl, handlers
local frame, content, savedPosition
local origin = { left = 0, right = 0, top = 0 }
local offset = 0
local selected, view, period = nil, "net", 30
-- The recipe whose Delete waits for its confirming click, and the timer that expires it.
local armed, armToken = nil, 0
local parts = { rows = {}, itemButtons = {}, viewButtons = {}, periodButtons = {}, figures = {}, weekdayNames = {} }

HistoryWindow.parts = parts
HistoryWindow.WIDTH = WIDTH
HistoryWindow.LEFT_W = LEFT_W
HistoryWindow.CHAR_W, HistoryWindow.SMALL_CHAR_W = CHAR_W, SMALL_CHAR_W
HistoryWindow.FIGURE_LABEL_W = FIGURE_LABEL_W
HistoryWindow.WEEKDAY_W = (RIGHT_W - Chart.LABEL_W) / 7
HistoryWindow.QUESTION_MARK = QUESTION_MARK
HistoryWindow.ACTION_W = ACTION_W
HistoryWindow.RIGHT_W, HistoryWindow.PERIOD_W = RIGHT_W, PERIOD_W
HistoryWindow.CONFIRM_SECONDS = CONFIRM_SECONDS

function HistoryWindow.state()
    return { selected = selected, view = view, period = period }
end

function HistoryWindow.frame() return frame end

function HistoryWindow.isShown()
    return frame ~= nil and frame:IsShown() == true
end

function HistoryWindow.hide()
    if frame then frame:Hide() end
end

-- Tooltips ---------------------------------------------------------------------------

local function showTip(owner, itemID, text)
    if type(GameTooltip) ~= "table" then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if itemID and type(GameTooltip.SetItemByID) == "function" and pcall(GameTooltip.SetItemByID, GameTooltip, itemID) then
        GameTooltip:Show()
        return
    end
    GameTooltip:SetText(text or "")
    GameTooltip:Show()
end

local function hideTip()
    if type(GameTooltip) == "table" then GameTooltip:Hide() end
end

-- Painting ---------------------------------------------------------------------------

local function paintText(fs, color)
    fs:SetTextColor(color[1], color[2], color[3], color[4])
end

-- "-18%" coloured by whether it is good news (green), bad (red) or flat (grey).
local function arrowText(c)
    if not c then return "" end
    local color = c.good == true and Colors.FIXED.profit or (c.good == false and Colors.FIXED.loss or Colors.text("muted"))
    local text = c.pct == 0 and "0%" or string.format("%+d%%", c.pct)
    return Colors.escape(color) .. text .. "|r"
end

local function money(v)
    if type(v) ~= "number" then return "-" end
    return ctl.fmt(v)
end

local function setLit(button, on)
    button.lit:SetShown(on == true)
end

-- A short date in the language's order (L.SHORT_DATE: "%m/%d" or "%d/%m"), from the
-- local date fields (History.dateFields, the same local days as the chart). "" when unknown.
function HistoryWindow.dateText(t)
    local d = ns.History.dateFields(t)
    if not d then return "" end
    local fields = { d = string.format("%02d", d.day), m = string.format("%02d", d.month) }
    return (L.SHORT_DATE:gsub("%%([dm])", fields))
end
local dayText = HistoryWindow.dateText

local function onHover(row)
    if type(row) ~= "table" then
        parts.hover:SetText("")
        return
    end
    local value, carried, range
    if view:match("^item:") then
        value = row.avg
        carried = row.carried == true
        if type(row.low) == "number" and type(row.high) == "number" and row.low ~= row.high then
            range = money(row.low) .. " - " .. money(row.high)
        end
    else
        value = row[view]
        local flag = row[view .. "Carried"]
        if flag == nil then flag = row.carried end
        carried = flag and true or false
    end
    local text = dayText(row.day) .. "  " .. money(value)
    if range then text = text .. "  (" .. range .. ")" end
    if carried then text = text .. "  · " .. L.HISTORY_CARRIED end
    parts.hover:SetText(text)
end

-- Hides the right side's chart area and shows `message` instead.
local function showEmpty(message, keepButtons)
    parts.empty:SetText(message or "")
    parts.empty:Show()
    parts.chart:clear()
    parts.chart.frame:Hide()
    parts.hover:SetText("")
    parts.status:Hide()
    for _, f in pairs(parts.figures) do
        f.label:Hide()
        f.value:Hide()
    end
    for _, fs in ipairs(parts.weekdayNames) do fs:Hide() end
    parts.buttonRows:SetShown(keepButtons == true)
end

local function paintButtons(data)
    parts.buttonRows:Show()
    setLit(parts.viewButtons[1], data.view == "net")
    setLit(parts.viewButtons[2], data.view == "materials")
    for i, p in ipairs(PERIODS) do setLit(parts.periodButtons[i], data.period == p) end
    local index = 0
    for _, item in ipairs(data.items) do
        if item.itemID then
            index = index + 1
            local b = parts.itemButtons[index]
            if b then
                b.key, b.itemID, b.label = item.key, item.itemID, item.name
                b.icon:SetTexture(item.icon or QUESTION_MARK)
                setLit(b, data.view == item.key)
                b:Show()
            end
        end
    end
    for i = index + 1, #parts.itemButtons do parts.itemButtons[i]:Hide() end
end

local function paintFigures(summary)
    for _, def in ipairs(FIGURES) do
        local f = parts.figures[def.key]
        local v = summary[def.field]
        f.label:SetText(L[def.label])
        f.value:SetText(def.money and money(v) or tostring(type(v) == "number" and v or "-"))
        f.label:Show()
        f.value:Show()
    end
end

local function disarm()
    armed = nil
    armToken = armToken + 1
end

local function paintActions(data)
    local pause, delete = parts.pauseButton, parts.deleteButton
    if not data then
        pause:Hide()
        delete:Hide()
        return
    end
    pause.resume = data.paused == true
    pause:setText(pause.resume and L.HISTORY_RESUME or L.HISTORY_PAUSE)
    delete:setText(armed == data.recipe.recipeID and L.HISTORY_DELETE_CONFIRM or L.HISTORY_DELETE)
    pause:Show()
    delete:Show()
end

local function paintRight(list)
    local data = selected and ctl.historyData(selected, view, period) or nil
    paintActions(data)
    if #list == 0 then return showEmpty(L.HISTORY_NONE) end
    if not data then return showEmpty(L.HISTORY_SELECT) end
    view, period = data.view, data.period
    paintButtons(data)
    if data.status == "nodata" then
        return showEmpty(string.format(L.HISTORY_NODATA, data.measures or 0, data.days or 0), true)
    end
    parts.empty:Hide()
    parts.chart.frame:Show()
    parts.chart:set(data.chart)
    parts.chart:setWeekday(data.weekday)
    for i, fs in ipairs(parts.weekdayNames) do
        fs:SetText(L["WEEKDAY_" .. i])
        fs:Show()
    end
    paintFigures(data.summary)
    parts.status:SetText(data.status == "paused" and L.HISTORY_PAUSED or "")
    parts.status:SetShown(data.status == "paused")
end

local function paintList(list)
    offset = math.max(0, math.min(offset, #list - VISIBLE))
    for i = 1, VISIBLE do
        local row, entry = parts.rows[i], list[offset + i]
        if entry then
            local recipe = entry.recipe
            row.recipeID = recipe.recipeID
            row.name:SetText(ctl.recipeName(recipe))
            paintText(row.name, Colors.FIXED[recipe.difficulty] or Colors.text("main"))
            if not entry.active then
                row.arrows:SetText(L.TRACK_PAUSED)
                paintText(row.arrows, Colors.text("muted"))
            else
                local ind = entry.indicator or {}
                row.arrows:SetText(arrowText(ind.materials) .. " " .. arrowText(ind.sale))
                paintText(row.arrows, Colors.text("main"))
            end
            row.selected:SetShown(recipe.recipeID == selected)
            row:Show()
        else
            row.recipeID = nil
            row:Hide()
        end
    end
    parts.bar:update(#list, VISIBLE, offset)
end

-- Repaints from the controller; does nothing while the window is closed or not built.
-- Keeps the selection, view and period; a selected recipe no longer tracked is dropped.
function HistoryWindow.refresh()
    if not frame or not frame:IsShown() then return end
    local list = ctl.historyList()
    local found = false
    for _, entry in ipairs(list) do
        if entry.recipe.recipeID == selected then found = true end
    end
    if not found then selected = nil end
    parts.title = L.HISTORY_TITLE .. " - " .. ctl.marketName()
    frame:setTitle(parts.title)
    parts.panel:setTitle(L.HISTORY_LIST)
    parts.info:SetText(L.HISTORY_INFO)
    for i, p in ipairs(PERIODS) do parts.periodButtons[i]:setText(string.format(L.HISTORY_PERIOD, p)) end
    parts.viewButtons[1]:setText(L.HISTORY_VIEW_NET)
    parts.viewButtons[2]:setText(L.HISTORY_VIEW_MATERIALS)
    paintList(list)
    paintRight(list)
end

-- Selects a tracked recipe: its Result view, the period kept.
function HistoryWindow.select(recipeID)
    if recipeID ~= selected then disarm() end
    selected, view = recipeID, "net"
    HistoryWindow.refresh()
end

-- First click arms the delete (its label asks for a second click), a second click within
-- CONFIRM_SECONDS deletes; after that the label comes back.
local function onDelete()
    if not selected then return end
    if armed == selected then
        local id = selected
        disarm()
        ctl.deleteHistory(id)
        return
    end
    disarm()
    armed = selected
    local token = armToken
    parts.deleteButton:setText(L.HISTORY_DELETE_CONFIRM)
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(CONFIRM_SECONDS, function()
            if token ~= armToken then return end
            armed = nil
            HistoryWindow.refresh()
        end)
    end
end

local function setView(key)
    view = key
    HistoryWindow.refresh()
end

local function setPeriod(p)
    period = p
    HistoryWindow.refresh()
end

-- Building ---------------------------------------------------------------------------

-- A click that ends a drag (Native.forwardDrag) runs nothing.
local function unlessDragged(fn)
    return function(self, ...)
        if self.dragged == true then return end
        fn(self, ...)
    end
end

-- A gold line under a button, shown on the active choice.
local function addLit(button, width)
    local lit = button:CreateTexture(nil, "OVERLAY")
    local gold = Colors.text("gold")
    lit:SetColorTexture(gold[1], gold[2], gold[3], 1)
    lit:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 2, -1)
    lit:SetSize(width - 4, 2)
    lit:Hide()
    button.lit = lit
end

local function buildRow(body, i)
    local row = Native.listRow(body, i, ROW_H, Native.SCROLL_W + 6)
    row.arrows = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.arrows:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.arrows:SetWidth(ARROWS_W)
    row.arrows:SetJustifyH("RIGHT")
    row.arrows:SetWordWrap(false)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.name:SetPoint("RIGHT", row.arrows, "LEFT", -4, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    Native.forwardDrag(row, frame)
    row:SetScript("OnClick", function(self)
        if self.dragged == true or not self.recipeID then return end
        HistoryWindow.select(self.recipeID)
    end)
    return row
end

local function buildItemButton(parent, i)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(ICON, ICON)
    local col, line = (i - 1) % ICONS_PER_ROW, math.floor((i - 1) / ICONS_PER_ROW)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", col * (ICON + ICON_GAP), -line * (ICON + ICON_GAP))
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    addLit(b, ICON)
    Native.forwardDrag(b, frame)
    b:SetScript("OnClick", function(self)
        if self.dragged == true or not self.key then return end
        setView(self.key)
    end)
    b:SetScript("OnEnter", function(self) showTip(self, self.itemID, self.label) end)
    b:SetScript("OnLeave", hideTip)
    b:Hide()
    return b
end

local function build()
    local panelH = Layout.panelHeight(VISIBLE, ROW_H)
    local leftH = INFO_H + GAP + panelH
    local figuresH = FIGURE_ROW_H * 3
    local rightH = HEADER_H + ROW_GAP + CHART_H + 4 + NAMES_H + 4 + HOVER_H
        + ROW_GAP + figuresH + 4 + STATUS_H + ROW_GAP + Native.BUTTON_H
    frame = Native.window(NAME, L.HISTORY_TITLE, {
        width = WIDTH,
        height = CHROME_H + PAD + math.max(leftH, rightH) + PAD,
        onMoved = function(point, x, y)
            savedPosition = { x = x, y = y }
            if handlers.onMoved then handlers.onMoved(point, x, y) end
        end,
    })
    content = frame.content
    if content == frame then
        origin = { left = Native.INSET_LEFT, right = Native.INSET_RIGHT, top = Native.INSET_TOP }
    end
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, NAME) end
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta)
        HistoryWindow.refresh()
    end)
    local left0, top0 = origin.left + PAD, -(origin.top + PAD)

    -- Left: where the data comes from, then the list.
    parts.info = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    parts.info:SetPoint("TOPLEFT", content, "TOPLEFT", left0, top0)
    parts.info:SetWidth(LEFT_W)
    parts.info:SetJustifyH("LEFT")
    parts.info:SetWordWrap(true)
    parts.panel = Native.panel(content, L.HISTORY_LIST)
    parts.panel.frame:SetPoint("TOPLEFT", content, "TOPLEFT", left0, top0 - INFO_H - GAP)
    parts.panel.frame:SetWidth(LEFT_W)
    parts.panel.frame:SetHeight(panelH)
    for i = 1, VISIBLE do parts.rows[i] = buildRow(parts.panel.body, i) end
    parts.bar = Native.scrollbar(parts.panel.body, VISIBLE * ROW_H)
    parts.bar.frame:SetPoint("TOPRIGHT", parts.panel.body, "TOPRIGHT", -2, 0)
    parts.bar.onScroll = function(newOffset)
        offset = newOffset
        HistoryWindow.refresh()
    end

    -- Right: view and period buttons, item icons, chart, weekday names, hover line, figures.
    local right = CreateFrame("Frame", nil, content)
    right:SetPoint("TOPLEFT", content, "TOPLEFT", left0 + LEFT_W + GAP, top0)
    right:SetSize(RIGHT_W, rightH)
    parts.right = right
    local rows = CreateFrame("Frame", nil, right)
    rows:SetPoint("TOPLEFT", right, "TOPLEFT", 0, 0)
    rows:SetSize(RIGHT_W, HEADER_H)
    parts.buttonRows = rows
    for i, key in ipairs({ "net", "materials" }) do
        local b = Native.button(rows, "", { width = VIEW_W, onClick = unlessDragged(function() setView(key) end) })
        b:SetPoint("TOPLEFT", rows, "TOPLEFT", (i - 1) * (VIEW_W + ICON_GAP), 0)
        Native.forwardDrag(b, frame)
        addLit(b, VIEW_W)
        parts.viewButtons[i] = b
    end
    for i, p in ipairs(PERIODS) do
        local b = Native.button(rows, "", { width = PERIOD_W, onClick = unlessDragged(function() setPeriod(p) end) })
        b:SetPoint("TOPRIGHT", rows, "TOPRIGHT", 0, -(i - 1) * (Native.BUTTON_H + ICON_GAP))
        Native.forwardDrag(b, frame)
        addLit(b, PERIOD_W)
        parts.periodButtons[i] = b
    end
    local icons = CreateFrame("Frame", nil, rows)
    icons:SetPoint("TOPLEFT", rows, "TOPLEFT", 0, -(Native.BUTTON_H + ROW_GAP))
    icons:SetSize(ICONS_PER_ROW * (ICON + ICON_GAP), ICON_ROWS * (ICON + ICON_GAP))
    for i = 1, ICONS_PER_ROW * ICON_ROWS do
        parts.itemButtons[i] = buildItemButton(icons, i)
    end

    local y = -(HEADER_H + ROW_GAP)
    parts.chart = Chart.new(right, RIGHT_W, CHART_H, frame)
    parts.chart.frame:SetPoint("TOPLEFT", right, "TOPLEFT", 0, y)
    parts.chart.onHover = onHover
    y = y - CHART_H - 4
    for i = 1, 7 do
        local fs = right:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        fs:SetPoint("TOP", right, "TOPLEFT", Chart.LABEL_W + (i - 0.5) * HistoryWindow.WEEKDAY_W, y)
        parts.weekdayNames[i] = fs
    end
    y = y - NAMES_H - 4
    parts.hover = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    parts.hover:SetPoint("TOPLEFT", right, "TOPLEFT", Chart.LABEL_W, y)
    parts.hover:SetWidth(RIGHT_W - Chart.LABEL_W)
    parts.hover:SetJustifyH("LEFT")
    parts.hover:SetWordWrap(false)
    y = y - HOVER_H - ROW_GAP
    local colW = RIGHT_W / 2
    for i, def in ipairs(FIGURES) do
        local col, line = (i - 1) % 2, math.floor((i - 1) / 2)
        local label = right:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", right, "TOPLEFT", col * colW, y - line * FIGURE_ROW_H)
        label:SetWidth(FIGURE_LABEL_W)
        label:SetJustifyH("LEFT")
        local value = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        value:SetPoint("TOPLEFT", right, "TOPLEFT", col * colW + FIGURE_LABEL_W, y - line * FIGURE_ROW_H)
        value:SetWidth(colW - FIGURE_LABEL_W - 4)
        value:SetJustifyH("LEFT")
        parts.figures[def.key] = { label = label, value = value }
    end
    y = y - figuresH - 4
    parts.status = right:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    parts.status:SetPoint("TOPLEFT", right, "TOPLEFT", 0, y)
    parts.status:SetWidth(RIGHT_W)
    parts.status:SetJustifyH("LEFT")
    y = y - STATUS_H - ROW_GAP
    parts.pauseButton = Native.button(right, "", { width = ACTION_W, onClick = unlessDragged(function(self)
        if selected then ctl.setHistoryActive(selected, self.resume == true) end
    end) })
    parts.pauseButton:SetPoint("TOPLEFT", right, "TOPLEFT", 0, y)
    parts.deleteButton = Native.button(right, "", { width = ACTION_W, onClick = unlessDragged(onDelete) })
    parts.deleteButton:SetPoint("TOPLEFT", right, "TOPLEFT", ACTION_W + ICON_GAP, y)
    for _, b in ipairs({ parts.pauseButton, parts.deleteButton }) do
        Native.forwardDrag(b, frame)
        b:Hide()
    end
    -- The messages of the empty states, in the middle of the right side.
    parts.empty = right:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    parts.empty:SetPoint("TOP", right, "TOP", 0, -(HEADER_H + ROW_GAP + 60))
    parts.empty:SetWidth(RIGHT_W - 40)
    parts.empty:SetJustifyH("CENTER")
    parts.empty:SetWordWrap(true)
    frame:Hide()
end

function HistoryWindow.show()
    if not ctl then return end
    if not frame then build() end
    HistoryWindow.place()
    frame:Show()
    Native.fitToScreen(frame)
    HistoryWindow.refresh()
end

function HistoryWindow.toggle()
    if HistoryWindow.isShown() then HistoryWindow.hide() else HistoryWindow.show() end
end

-- Builds nothing: the window is made on first open. handlers: onMoved(point, x, y).
function HistoryWindow.init(controller, h)
    ctl, handlers = controller, h or {}
end

-- Position: the saved one once dragged, else beside the rightmost shown CraftProfit
-- window, else the middle of the screen.
function HistoryWindow.place()
    if not frame then return end
    frame:ClearAllPoints()
    local x, y
    if not savedPosition and ctl and ctl.besidePosition then x, y = ctl.besidePosition(frame) end
    if savedPosition then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", savedPosition.x, savedPosition.y)
    elseif x then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

-- The saved position ({ x, y } or nil); applied now when the window exists, else on open.
function HistoryWindow.attach(saved)
    savedPosition = saved
    HistoryWindow.place()
end
