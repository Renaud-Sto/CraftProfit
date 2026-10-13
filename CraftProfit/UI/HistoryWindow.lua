-- The History window. Left: the tracked recipes in a "Tracked recipes" panel, two columns
-- (materials and sale: today against the usual price), and under it a short hint on where
-- the data comes from. Right, top to bottom, each in its own native panel:
--   verdict  the recipe name, then up to three lines: the auction house profit today (green
--            profit, red loss, grey break even); "<What> today: <amount>" (not in the Profit
--            view: the first line says it); a sentence comparing today with the usual (green
--            good news, red bad, grey about usual). While crafting is at a loss the
--            comparison is grey and gives no "good time to" advice (better is not good yet);
--            so is it with stale data (not measured for a day), whose lines are dated.
--   chart    tabs Materials cost | Sale price | Profit, period buttons, the recipe's items
--            in groups (Materials, Crafted item, Disenchant), a caption saying what is drawn,
--            then the chart (UI/Chart.lua) with its hover bubble
--   figures  Now, Usual, lowest and highest day of the period with their dates, and how
--            many measurements over how many days
--   week     the typical week (Chart.newWeekday), or one muted line without enough data
-- then the paused status and the Pause/Resume and Delete history buttons. Delete asks for a
-- second click on the button itself within CONFIRM_SECONDS (no game dialog).
-- Only widgets: every figure comes from Controller.historyList / historyData. Built on
-- first open, never at login; Escape closes it; refreshed only while shown. The list is
-- cached: HistoryWindow.refresh() (controller, selection, view, period, pause, delete)
-- reads Controller.historyList again; the mouse wheel and the scroll bar only repaint the
-- rows from that cache (repaintList), with no data work and no right-side repaint.
local _, ns = ...
local L = ns.L
local Native, Colors, Chart, Layout = ns.Native, ns.Colors, ns.Chart, ns.Layout

local HistoryWindow = {}
ns.HistoryWindow = HistoryWindow

local NAME = "CraftProfitHistoryWindow"
local WIDTH = 880
local PAD = Native.CONTENT_PAD
local GAP = 8
local PANEL_GAP = 6
local CHROME_H = Native.INSET_TOP + Native.INSET_BOTTOM
local INNER_WIDTH = WIDTH - Native.INSET_LEFT - Native.INSET_RIGHT - PAD * 2
-- Estimated letter widths (the client cannot measure in tests), as OptionsUI.
local CHAR_W, SMALL_CHAR_W = 7, 6
local SMALL_LINE_H = 12
-- Left column: the list panel, then the hint (HINT_LINES lines at most).
local LEFT_W = 250
local HINT_LINES = 3
local ROW_H = 20
local COL_W = 44
local COL_HEAD_H = 14
local COL_HEAD_W = 80
local ROW_INSET = Native.SCROLL_W + 6
-- Right column.
local RIGHT_W = INNER_WIDTH - LEFT_W - GAP
local BODY_W = RIGHT_W - 2 * Native.PANEL_EDGE
local INNER_PAD = 6
local USE_W = BODY_W - 2 * INNER_PAD
local LINE_H = 16
local VERDICT_LINES = 3
local VERDICT_H = Layout.panelHeight(VERDICT_LINES, LINE_H)
local ICON = 24
local ICON_GAP = 4
local ICON_ROWS = 1
local CAPTION_H = 10
local SEP_GAP = 6
local ICON_LINE_H = CAPTION_H + ICON + ICON_GAP
local ICONS_H = ICON_ROWS * ICON_LINE_H
local ICON_POOL = 24
local TABS_H = Native.BUTTON_H
local CHART_H = 204
local CHART_CAPTION_H = SMALL_LINE_H
local CHART_INNER = TABS_H + 6 + ICONS_H + 2 + CHART_CAPTION_H + 4 + CHART_H + 2
local CHART_PANEL_H = Layout.panelHeight(0, 0, CHART_INNER)
local FIGURE_H = 12 + 14 + 12
local FIGURES_PANEL_H = Layout.panelHeight(0, 0, FIGURE_H + 4 + SMALL_LINE_H)
local WEEK_H = 60
local WEEK_PANEL_H = Layout.panelHeight(0, 0, WEEK_H)
local STATUS_H = 12
local ACTION_W = 220
local ACTIONS_H = 4 + STATUS_H + 4 + Native.BUTTON_H
local RIGHT_H = VERDICT_H + CHART_PANEL_H + FIGURES_PANEL_H + WEEK_PANEL_H + ACTIONS_H + 4 * PANEL_GAP
local HINT_H = HINT_LINES * SMALL_LINE_H
local LIST_PANEL_H = RIGHT_H - PANEL_GAP - HINT_H
local VISIBLE = math.floor((LIST_PANEL_H - Layout.panelHeight(0, 0) - COL_HEAD_H) / ROW_H)
local CONFIRM_SECONDS = 4
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"
local PERIODS = { 7, 30, 60 }
-- Tabs, in the order shown.
local TABS = {
    { key = "materials", label = "HISTORY_VIEW_MATERIALS" },
    { key = "sale", label = "HISTORY_VIEW_SALE" },
    { key = "net", label = "HISTORY_VIEW_NET" },
}
local VIEW_LABEL = { net = "HISTORY_VIEW_NET", materials = "HISTORY_VIEW_MATERIALS", sale = "HISTORY_VIEW_SALE" }
local GROUPS = {
    { key = "materials", label = "HISTORY_GROUP_MATERIALS" },
    { key = "crafted", label = "HISTORY_GROUP_CRAFTED" },
    { key = "disenchant", label = "HISTORY_GROUP_DISENCHANT" },
}
-- The labels of the lowest and highest day, by view.
local RANGE_LABELS = {
    net = { "HISTORY_WORST_DAY", "HISTORY_BEST_DAY" },
    materials = { "HISTORY_CHEAPEST_DAY", "HISTORY_PRICIEST_DAY" },
    default = { "HISTORY_LOWEST", "HISTORY_HIGHEST" },
}
local GOOD = { buy = "HISTORY_GOOD_BUY", sell = "HISTORY_GOOD_SELL", craft = "HISTORY_GOOD_CRAFT" }

local ctl, handlers
local frame, content, savedPosition
local origin = { left = 0, right = 0, top = 0 }
local offset = 0
local selected, view, period = nil, "net", 30
-- The last Controller.historyList result: the rows repaint from it while scrolling.
local cachedList = {}
-- The recipe whose Delete waits for its confirming click, and the timer that expires it.
local armed, armToken = nil, 0
local parts = { rows = {}, itemButtons = {}, tabs = {}, periodButtons = {}, figures = {},
    groupCaptions = {}, separators = {}, lines = {} }

HistoryWindow.parts = parts
HistoryWindow.WIDTH = WIDTH
HistoryWindow.LEFT_W, HistoryWindow.RIGHT_W = LEFT_W, RIGHT_W
HistoryWindow.USE_W = USE_W
HistoryWindow.HINT_LINES = HINT_LINES
HistoryWindow.CHAR_W, HistoryWindow.SMALL_CHAR_W = CHAR_W, SMALL_CHAR_W
HistoryWindow.COL_HEAD_W = COL_HEAD_W
HistoryWindow.VISIBLE = VISIBLE
HistoryWindow.QUESTION_MARK = QUESTION_MARK
HistoryWindow.ACTION_W = ACTION_W
HistoryWindow.CONFIRM_SECONDS = CONFIRM_SECONDS
HistoryWindow.ICON, HistoryWindow.ICON_GAP, HistoryWindow.ICON_ROWS = ICON, ICON_GAP, ICON_ROWS
HistoryWindow.SEP_GAP = SEP_GAP
HistoryWindow.FIGURE_W = USE_W / 4

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

-- Pure layout of the item icon groups ---------------------------------------------------

-- groups: { { key, count, captionW }, ... } in display order; an empty group is skipped.
-- Flows the groups along lines of `width` px: a group that does not fit the rest of a line
-- starts the next one; a group wider than a whole line wraps its own icons. Between two
-- groups on one line, a separator (SEP_GAP, 1 px, SEP_GAP). Returns { groups = { { key,
-- x, line, icons = { { x, line }, ... } } }, separators = { { x, line } }, lines }.
-- Lines count from 1; the caller hides what falls beyond ICON_ROWS.
function HistoryWindow.layoutIcons(groups, width)
    local out = { groups = {}, separators = {}, lines = 0 }
    local step = ICON + ICON_GAP
    local sepRoom = 2 * SEP_GAP + 1
    local line, x, first = 1, 0, true
    for _, g in ipairs(groups or {}) do
        local count = tonumber(g.count) or 0
        if count > 0 then
            local w = math.max(count * step - ICON_GAP, g.captionW or 0)
            if not first and x + sepRoom + w > width then
                line, x, first = line + 1, 0, true
            end
            if not first then
                out.separators[#out.separators + 1] = { x = x + SEP_GAP, line = line }
                x = x + sepRoom
            end
            local entry = { key = g.key, x = x, line = line, icons = {} }
            local ix, il = x, line
            for i = 1, count do
                if ix > 0 and ix + ICON > width then il, ix = il + 1, 0 end
                entry.icons[i] = { x = ix, line = il }
                ix = ix + step
            end
            out.groups[#out.groups + 1] = entry
            if il == line then x = x + w else x = ix - ICON_GAP end
            line, first = il, false
        end
    end
    out.lines = first and line - 1 or line
    if #out.groups == 0 then out.lines = 0 end
    return out
end

-- Tooltips ---------------------------------------------------------------------------

local function showTip(owner, itemID, text)
    if type(GameTooltip) ~= "table" then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if itemID and type(GameTooltip.SetItemByID) == "function" and pcall(GameTooltip.SetItemByID, GameTooltip, itemID) then
        GameTooltip:Show()
        return
    end
    GameTooltip:SetText(text or "", 1, 1, 1, 1, true)
    GameTooltip:Show()
end

local function hideTip()
    if type(GameTooltip) == "table" then GameTooltip:Hide() end
end

-- Wording ------------------------------------------------------------------------------

local function paintText(fs, color)
    fs:SetTextColor(color[1], color[2], color[3], color[4])
end

local function goodColor(good)
    if good == true then return Colors.FIXED.profit end
    if good == false then return Colors.FIXED.loss end
    return Colors.text("muted")
end

-- "-18%" coloured by whether it is good news (green), bad (red) or flat (grey); all grey
-- when `muted` (the recipe is crafted at a loss: no move is good news yet).
local function arrowText(c, muted)
    if not c then return "" end
    local text = c.pct == 0 and "0%" or string.format("%+d%%", c.pct)
    return Colors.escape(muted and Colors.text("muted") or goodColor(c.good)) .. text .. "|r"
end

local function money(v)
    if type(v) ~= "number" then return "-" end
    return ctl.fmt(v)
end

-- An amount that may be a loss: never "-9s40c", always "loss 9s40c".
local function signed(v)
    if type(v) == "number" and v < 0 then return string.format(L.HISTORY_LOSS, money(-v)) end
    return money(v)
end

local function labelled(label, value)
    return string.format(L.HISTORY_LABEL_VALUE, label, value)
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

-- The commission as text: "5", "7.5".
local function percentNumber(v)
    if type(v) ~= "number" then return "5" end
    return (string.format("%.2f", v):gsub("%.?0+$", ""))
end

local function itemOf(data, key)
    for _, item in ipairs(data.items) do
        if item.key == key then return item end
    end
    return nil
end

-- What the view shows, in a few words: the tab's name or the item's.
local function whatText(data)
    local item = itemOf(data, data.view)
    if item then return item.name end
    return L[VIEW_LABEL[data.view] or "HISTORY_VIEW_NET"]
end

function HistoryWindow.captionText(data)
    local v = data.view
    if v == "net" then return string.format(L.HISTORY_CAPTION_NET, percentNumber(data.commission)) end
    if v == "materials" then return L.HISTORY_CAPTION_MATERIALS end
    if v == "sale" then return L.HISTORY_CAPTION_SALE end
    return string.format(L.HISTORY_CAPTION_ITEM, whatText(data))
end

-- Whether the recipe is crafted at a loss (or for nothing) at the auction house today.
local function atLoss(data)
    return type(data.profit) == "table" and data.profit.atLoss == true
end

-- Whether the data is too old for today's advice (Controller.historyData's fresh flag).
local function stale(data)
    return data.fresh == false
end

-- The auction house profit line: "Crafted and sold at the auction house today: loss 2s47"
-- and its colour (green profit, red loss, grey break even). "" when the profit is unknown.
function HistoryWindow.profitLine(data)
    local p = data.profit
    if type(p) ~= "table" or type(p.today) ~= "number" then return "", nil end
    local amount, color
    if p.today > 0 then
        amount, color = string.format(L.HISTORY_PROFIT_AMOUNT, money(p.today)), Colors.FIXED.profit
    elseif p.today < 0 then
        amount, color = string.format(L.HISTORY_LOSS, money(-p.today)), Colors.FIXED.loss
    else
        amount, color = L.HISTORY_BREAK_EVEN, Colors.text("muted")
    end
    if p.todayDay == nil or p.todayDay == data.chart.newest then
        return string.format(L.HISTORY_AH_TODAY, amount), color
    end
    return string.format(L.HISTORY_AH_ON, dayText(p.todayDay), amount), color
end

-- The view's figure: "Materials cost today: 12g" (or "on <date>" when the newest day is
-- older). "" in the Profit view, whose figure is the profit line.
function HistoryWindow.verdictLine(data)
    local s = data.summary
    if data.view == "net" or type(s.today) ~= "number" then return "" end
    local amount = money(s.today)
    if s.todayDay == data.chart.newest then
        return string.format(L.HISTORY_VERDICT_TODAY, whatText(data), amount)
    end
    return string.format(L.HISTORY_VERDICT_ON, whatText(data), dayText(s.todayDay), amount)
end

-- The Profit view's comparison, in money (data.compare is HistoryView.profitCompare): a
-- percentage of a profit is meaningless when either side is a loss. Better is green with
-- the advice only while there is a profit; a smaller loss is grey; worse is red.
local function profitCompareLine(data, c)
    local usual = signed(data.summary.usual)
    if c.tone == "flat" then return string.format(L.HISTORY_ABOUT, usual), goodColor(nil) end
    local gap = money(math.abs(c.gap or 0))
    if stale(data) then
        local key = c.tone == "down" and "HISTORY_PROFIT_WORSE"
            or (atLoss(data) and "HISTORY_PROFIT_LESS_LOSS" or "HISTORY_PROFIT_BETTER")
        return string.format(L[key], gap, usual), goodColor(nil)
    end
    if c.tone == "down" then return string.format(L.HISTORY_PROFIT_WORSE, gap, usual), goodColor(false) end
    if atLoss(data) then return string.format(L.HISTORY_PROFIT_LESS_LOSS, gap, usual), goodColor(nil) end
    local text = string.format(L.HISTORY_PROFIT_BETTER, gap, usual)
    return string.format(L.HISTORY_VERDICT_GOOD, text, L[GOOD.craft]), goodColor(true)
end

-- The comparison with the usual price, and its colour. "" without one. At a loss, good
-- news turns grey and loses its advice: cheaper materials do not make a losing craft good.
-- With stale data (no measurement within a day) every comparison is grey, without advice.
function HistoryWindow.compareLine(data)
    local c = data.compare
    if not c then return "", nil end
    if data.view == "net" then return profitCompareLine(data, c) end
    local usual = money(data.summary.usual)
    local text
    if c.tone == "down" then
        text = string.format(data.goal == "buy" and L.HISTORY_CHEAPER or L.HISTORY_LOWER, math.abs(c.pct), usual)
    elseif c.tone == "up" then
        text = string.format(L.HISTORY_HIGHER, c.pct, usual)
    else
        text = string.format(L.HISTORY_ABOUT, usual)
    end
    if stale(data) or (c.good == true and atLoss(data)) then return text, goodColor(nil) end
    if c.good == true and GOOD[data.goal] then
        text = string.format(L.HISTORY_VERDICT_GOOD, text, L[GOOD[data.goal]])
    end
    return text, goodColor(c.good)
end

-- The verdict's lines in order, the empty ones left out: { { text, color }, ... }.
function HistoryWindow.verdictLines(data)
    local out = {}
    local function add(text, color)
        if text ~= "" then out[#out + 1] = { text = text, color = color or Colors.text("main") } end
    end
    add(HistoryWindow.profitLine(data))
    add(HistoryWindow.verdictLine(data))
    add(HistoryWindow.compareLine(data))
    return out
end

-- The lines of the chart's hover bubble for one day row of the shown view.
function HistoryWindow.bubbleLines(row)
    if type(row) ~= "table" then return nil end
    local lines = { dayText(row.day) }
    local carried
    if view:match("^item:") then
        lines[#lines + 1] = labelled(L.HISTORY_AVERAGE, money(row.avg))
        if type(row.low) == "number" and type(row.high) == "number" and row.low ~= row.high then
            lines[#lines + 1] = labelled(L.HISTORY_RANGE, money(row.low) .. " - " .. money(row.high))
        end
        carried = row.carried == true
    else
        lines[#lines + 1] = labelled(L[VIEW_LABEL[view] or "HISTORY_VIEW_NET"], view == "net" and signed(row[view]) or money(row[view]))
        if view == "net" then
            lines[#lines + 1] = labelled(L.HISTORY_VIEW_SALE, money(row.sale))
            lines[#lines + 1] = labelled(L.HISTORY_VIEW_MATERIALS, money(row.materials))
        end
        local flag = row[view .. "Carried"]
        if flag == nil then flag = row.carried end
        carried = flag and true or false
    end
    lines[#lines + 1] = labelled(L.HISTORY_MEASURES, tostring(type(row.n) == "number" and row.n or 0))
    if carried then lines[#lines + 1] = L.HISTORY_CARRIED end
    return lines
end

-- Painting ---------------------------------------------------------------------------

local function setLit(button, on)
    button.lit:SetShown(on == true)
end

local function showPanels(verdict, chartPanel, rest)
    parts.verdict.frame:SetShown(verdict)
    parts.chartPanel.frame:SetShown(chartPanel)
    parts.figuresPanel.frame:SetShown(rest)
    parts.weekPanel.frame:SetShown(rest)
end

-- Hides the chart and shows `message` instead: in the chart panel when a recipe is
-- selected (withPanels), else alone on the right side.
local function showEmpty(message, withPanels)
    parts.empty:SetText(message or "")
    parts.empty:ClearAllPoints()
    if withPanels then
        parts.empty:SetPoint("TOP", parts.chartArea, "TOP", 0, -50)
    else
        parts.empty:SetPoint("TOP", parts.right, "TOP", 0, -120)
    end
    parts.empty:Show()
    parts.chart:clear()
    parts.chart.frame:Hide()
    parts.caption:SetText("")
    parts.status:Hide()
    showPanels(withPanels == true, withPanels == true, false)
end

local function paintTabs(data)
    for i, tab in ipairs(TABS) do setLit(parts.tabs[i], data.view == tab.key) end
    for i, p in ipairs(PERIODS) do setLit(parts.periodButtons[i], data.period == p) end
end

local function paintIcons(data)
    local byGroup = {}
    for _, g in ipairs(GROUPS) do byGroup[g.key] = {} end
    for _, item in ipairs(data.items) do
        local list = byGroup[item.group]
        if list then list[#list + 1] = item end
    end
    local groups = {}
    for _, g in ipairs(GROUPS) do
        groups[#groups + 1] = { key = g.key, count = #byGroup[g.key],
            captionW = Layout.textWidth(L[g.label], SMALL_CHAR_W) }
    end
    local layout = HistoryWindow.layoutIcons(groups, USE_W)
    parts.iconLayout = layout
    local function yOf(line) return -(line - 1) * ICON_LINE_H end
    local used = 0
    local captionShown = {}
    for _, entry in ipairs(layout.groups) do
        local caption = parts.groupCaptions[entry.key]
        if entry.line <= ICON_ROWS then
            caption:ClearAllPoints()
            caption:SetPoint("TOPLEFT", parts.icons, "TOPLEFT", entry.x, yOf(entry.line))
            caption:Show()
            captionShown[entry.key] = true
        end
        for i, pos in ipairs(entry.icons) do
            local item = byGroup[entry.key][i]
            used = used + 1
            local b = parts.itemButtons[used]
            if b and pos.line <= ICON_ROWS then
                b.key, b.itemID, b.label, b.group = item.key, item.itemID, item.name, item.group
                b.icon:SetTexture(item.icon or QUESTION_MARK)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", parts.icons, "TOPLEFT", pos.x, yOf(pos.line) - CAPTION_H)
                setLit(b, data.view == item.key)
                b:Show()
            elseif b then
                b:Hide()
            end
        end
    end
    for i = used + 1, #parts.itemButtons do parts.itemButtons[i]:Hide() end
    for _, g in ipairs(GROUPS) do
        if not captionShown[g.key] then parts.groupCaptions[g.key]:Hide() end
    end
    for i, sep in ipairs(parts.separators) do
        local s = layout.separators[i]
        if s and s.line <= ICON_ROWS then
            sep:ClearAllPoints()
            sep:SetPoint("TOPLEFT", parts.icons, "TOPLEFT", s.x, yOf(s.line))
            sep:SetSize(1, ICON_LINE_H - ICON_GAP)
            sep:Show()
        else
            sep:Hide()
        end
    end
end

local function paintVerdict(data)
    parts.verdict:setTitle(ctl.recipeName(data.recipe))
    local lines = data.status == "nodata" and {} or HistoryWindow.verdictLines(data)
    for i, fs in ipairs(parts.lines) do
        local line = lines[i]
        fs:SetText(line and line.text or "")
        if line then paintText(fs, line.color) end
    end
end

local function paintFigures(data)
    local s = data.summary
    local labels = RANGE_LABELS[data.view] or RANGE_LABELS.default
    local amount = data.view == "net" and signed or money
    local cells = {
        { L.HISTORY_NOW, amount(s.today), dayText(s.todayDay) },
        { L.HISTORY_USUAL, amount(s.usual), L.HISTORY_USUAL_NOTE },
        { L[labels[1]], amount(s.low), dayText(s.lowDay) },
        { L[labels[2]], amount(s.high), dayText(s.highDay) },
    }
    for i, cell in ipairs(cells) do
        local f = parts.figures[i]
        f.label:SetText(cell[1])
        f.value:SetText(cell[2])
        f.date:SetText(cell[3])
    end
    parts.coverage:SetText(string.format(L.HISTORY_COVERAGE, s.measures or 0, s.daysCovered or 0))
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

local function paintRight()
    local data = selected and ctl.historyData(selected, view, period) or nil
    paintActions(data)
    if #cachedList == 0 then return showEmpty(L.HISTORY_NONE) end
    if not data then return showEmpty(L.HISTORY_SELECT) end
    view, period = data.view, data.period
    paintVerdict(data)
    paintTabs(data)
    paintIcons(data)
    if data.status == "nodata" then
        showEmpty(string.format(L.HISTORY_NODATA, data.measures or 0, data.days or 0), true)
        parts.caption:SetText(HistoryWindow.captionText(data))
        -- A paused recipe says so whatever its data.
        parts.status:SetText(data.paused and L.HISTORY_PAUSED or "")
        parts.status:SetShown(data.paused == true)
        return
    end
    showPanels(true, true, true)
    parts.empty:Hide()
    parts.caption:SetText(HistoryWindow.captionText(data))
    parts.chart.frame:Show()
    local model = {}
    for k, v in pairs(data.chart) do model[k] = v end
    model.usualLabel = L.HISTORY_USUAL
    parts.chart:set(model)
    paintFigures(data)
    parts.week:set(data.weekday, L.HISTORY_WEEK_EMPTY)
    parts.status:SetText(data.status == "paused" and L.HISTORY_PAUSED or "")
    parts.status:SetShown(data.status == "paused")
end

local function paintColumn(fs, c, muted)
    fs:SetText(arrowText(c, muted))
end

-- Repaints the rows and the scroll bar from the cached list: no data work.
local function repaintList()
    offset = math.max(0, math.min(offset, #cachedList - VISIBLE))
    for i = 1, VISIBLE do
        local row, entry = parts.rows[i], cachedList[offset + i]
        if entry then
            local recipe = entry.recipe
            row.recipeID = recipe.recipeID
            row.atLoss = entry.active and entry.atLoss == true
            row.name:SetText(ctl.recipeName(recipe))
            paintText(row.name, Colors.FIXED[recipe.difficulty] or Colors.text("main"))
            if not entry.active then
                row.materials:SetText("")
                row.sale:SetText("")
                row.status:SetText(L.TRACK_PAUSED)
                row.status:Show()
            else
                local ind = entry.indicator or {}
                paintColumn(row.materials, ind.materials, entry.atLoss)
                paintColumn(row.sale, ind.sale, entry.atLoss)
                row.status:SetText("")
                row.status:Hide()
            end
            row.selected:SetShown(recipe.recipeID == selected)
            row:Show()
        else
            row.recipeID, row.atLoss = nil, nil
            row:Hide()
        end
    end
    parts.bar:update(#cachedList, VISIBLE, offset)
end
HistoryWindow.repaintList = repaintList

local function scrollTo(newOffset)
    offset = newOffset
    repaintList()
end

-- Repaints from the controller; does nothing while the window is closed or not built.
-- Keeps the selection, view and period; a selected recipe no longer tracked is dropped.
function HistoryWindow.refresh()
    if not frame or not frame:IsShown() then return end
    cachedList = ctl.historyList()
    local found = false
    for _, entry in ipairs(cachedList) do
        if entry.recipe.recipeID == selected then found = true end
    end
    if not found then selected = nil end
    parts.title = L.HISTORY_TITLE .. " - " .. ctl.marketName()
    frame:setTitle(parts.title)
    repaintList()
    paintRight()
end

-- Selects a tracked recipe: its Profit view, the period kept.
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
    -- Without a timer the armed state could never expire: never arm, never delete.
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return end
    armed = selected
    local token = armToken
    parts.deleteButton:setText(L.HISTORY_DELETE_CONFIRM)
    C_Timer.After(CONFIRM_SECONDS, function()
        if token ~= armToken then return end
        armed = nil
        HistoryWindow.refresh()
    end)
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

local function smallText(parent, font, width, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    if width then fs:SetWidth(width) end
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- Width of a button for `text` at CHAR_W, with `pad` for its caps and margin.
local function buttonWidth(text, pad, least)
    return math.max(least, Layout.textWidth(text, CHAR_W) + pad)
end
HistoryWindow.TAB_PAD, HistoryWindow.PERIOD_PAD = 20, 16

local function buildRow(body, i)
    local row = Native.listRow(body, i, ROW_H, ROW_INSET)
    row.sale = smallText(row, nil, COL_W, "RIGHT")
    row.sale:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.materials = smallText(row, nil, COL_W, "RIGHT")
    row.materials:SetPoint("RIGHT", row.sale, "LEFT", 0, 0)
    row.status = smallText(row, "GameFontDisableSmall", 2 * COL_W, "RIGHT")
    row.status:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.status:Hide()
    row.name = smallText(row)
    row.name:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.name:SetPoint("RIGHT", row.materials, "LEFT", -4, 0)
    Native.forwardDrag(row, frame)
    row:SetScript("OnClick", function(self)
        if self.dragged == true or not self.recipeID then return end
        HistoryWindow.select(self.recipeID)
    end)
    row:HookScript("OnEnter", function(self)
        showTip(self, nil, self.atLoss and (L.HISTORY_ROW_TIP .. "\n\n" .. L.HISTORY_ROW_TIP_LOSS) or L.HISTORY_ROW_TIP)
    end)
    row:HookScript("OnLeave", hideTip)
    return row
end

local function buildItemButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(ICON, ICON)
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

-- A native panel at (x, y) of `parent`, `width` x `height`.
local function panelAt(parent, title, x, y, width, height)
    local p = Native.panel(parent, title)
    p.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    p.frame:SetWidth(width)
    p.frame:SetHeight(height)
    return p
end

local function buildLeft(left0, top0)
    parts.panel = panelAt(content, L.HISTORY_LIST, left0, top0, LEFT_W, LIST_PANEL_H)
    local body = parts.panel.body
    -- Column headers, muted, right aligned over the two columns (they may reach left over
    -- the names: the header row has none).
    parts.colSale = smallText(body, "GameFontDisableSmall", COL_HEAD_W, "RIGHT")
    parts.colSale:SetPoint("TOPRIGHT", body, "TOPRIGHT", -(ROW_INSET + 2), 0)
    parts.colSale:SetText(L.HISTORY_COL_SALE)
    parts.colMaterials = smallText(body, "GameFontDisableSmall", COL_HEAD_W, "RIGHT")
    parts.colMaterials:SetPoint("TOPRIGHT", body, "TOPRIGHT", -(ROW_INSET + 2 + COL_W), 0)
    parts.colMaterials:SetText(L.HISTORY_COL_MATERIALS)
    local rows = CreateFrame("Frame", nil, body)
    rows:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -COL_HEAD_H)
    rows:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
    for i = 1, VISIBLE do parts.rows[i] = buildRow(rows, i) end
    parts.bar = Native.scrollbar(rows, VISIBLE * ROW_H)
    parts.bar.frame:SetPoint("TOPRIGHT", rows, "TOPRIGHT", -2, 0)
    parts.bar.onScroll = scrollTo
    parts.info = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    parts.info:SetPoint("TOPLEFT", content, "TOPLEFT", left0, top0 - LIST_PANEL_H - PANEL_GAP)
    parts.info:SetWidth(LEFT_W)
    parts.info:SetJustifyH("LEFT")
    parts.info:SetWordWrap(true)
    parts.info:SetText(L.HISTORY_INFO)
end

local function buildChartPanel(right, y)
    parts.chartPanel = panelAt(right, L.HISTORY_CHART, 0, y, RIGHT_W, CHART_PANEL_H)
    local body = parts.chartPanel.body
    local x = INNER_PAD
    for i, tab in ipairs(TABS) do
        local w = buttonWidth(L[tab.label], HistoryWindow.TAB_PAD, 60)
        local b = Native.button(body, L[tab.label], { width = w, onClick = unlessDragged(function() setView(tab.key) end) })
        b:SetPoint("TOPLEFT", body, "TOPLEFT", x, 0)
        b.width = w
        Native.forwardDrag(b, frame)
        addLit(b, w)
        parts.tabs[i] = b
        x = x + w + ICON_GAP
    end
    parts.tabsRight = x - ICON_GAP
    local pw = 0
    for _, p in ipairs(PERIODS) do pw = math.max(pw, buttonWidth(string.format(L.HISTORY_PERIOD, p), HistoryWindow.PERIOD_PAD, 44)) end
    for i = #PERIODS, 1, -1 do
        local p = PERIODS[i]
        local b = Native.button(body, string.format(L.HISTORY_PERIOD, p), { width = pw, onClick = unlessDragged(function() setPeriod(p) end) })
        b:SetPoint("TOPRIGHT", body, "TOPRIGHT", -(INNER_PAD + (#PERIODS - i) * (pw + ICON_GAP)), 0)
        b.width = pw
        Native.forwardDrag(b, frame)
        addLit(b, pw)
        parts.periodButtons[i] = b
    end
    parts.periodsLeft = USE_W + INNER_PAD - #PERIODS * (pw + ICON_GAP) + ICON_GAP
    local icons = CreateFrame("Frame", nil, body)
    icons:SetPoint("TOPLEFT", body, "TOPLEFT", INNER_PAD, -(TABS_H + 6))
    icons:SetSize(USE_W, ICONS_H)
    parts.icons = icons
    for _, g in ipairs(GROUPS) do
        local fs = smallText(icons, "GameFontDisableSmall")
        fs:SetText(L[g.label])
        fs:Hide()
        parts.groupCaptions[g.key] = fs
    end
    for i = 1, #GROUPS - 1 do
        local sep = icons:CreateTexture(nil, "ARTWORK")
        local muted = Colors.text("muted")
        sep:SetColorTexture(muted[1], muted[2], muted[3], 0.6)
        sep:Hide()
        parts.separators[i] = sep
    end
    for i = 1, ICON_POOL do parts.itemButtons[i] = buildItemButton(icons) end
    local cy = -(TABS_H + 6 + ICONS_H + 2)
    parts.caption = smallText(body, "GameFontDisableSmall", USE_W)
    parts.caption:SetPoint("TOPLEFT", body, "TOPLEFT", INNER_PAD, cy)
    cy = cy - CHART_CAPTION_H - 4
    local area = CreateFrame("Frame", nil, body)
    area:SetPoint("TOPLEFT", body, "TOPLEFT", INNER_PAD, cy)
    area:SetSize(USE_W, CHART_H)
    parts.chartArea = area
    parts.chart = Chart.new(area, USE_W, CHART_H, frame)
    parts.chart.frame:SetPoint("TOPLEFT", area, "TOPLEFT", 0, 0)
    parts.chart.dateText = HistoryWindow.dateText
    parts.chart.bubbleText = HistoryWindow.bubbleLines
end

local function buildFigures(right, y)
    parts.figuresPanel = panelAt(right, L.HISTORY_FIGURES, 0, y, RIGHT_W, FIGURES_PANEL_H)
    local body = parts.figuresPanel.body
    local cellW = USE_W / 4
    for i = 1, 4 do
        local x = INNER_PAD + (i - 1) * cellW
        local f = {
            label = smallText(body, "GameFontNormalSmall", cellW - 6),
            value = smallText(body, "GameFontHighlight", cellW - 6),
            date = smallText(body, "GameFontDisableSmall", cellW - 6),
        }
        f.label:SetPoint("TOPLEFT", body, "TOPLEFT", x, 0)
        f.value:SetPoint("TOPLEFT", body, "TOPLEFT", x, -12)
        f.date:SetPoint("TOPLEFT", body, "TOPLEFT", x, -26)
        parts.figures[i] = f
    end
    parts.coverage = smallText(body, "GameFontDisableSmall", USE_W)
    parts.coverage:SetPoint("TOPLEFT", body, "TOPLEFT", INNER_PAD, -(FIGURE_H + 4))
end

local function buildRight(left0, top0)
    local right = CreateFrame("Frame", nil, content)
    right:SetPoint("TOPLEFT", content, "TOPLEFT", left0 + LEFT_W + GAP, top0)
    right:SetSize(RIGHT_W, RIGHT_H)
    parts.right = right
    local y = 0
    parts.verdict = panelAt(right, "", 0, y, RIGHT_W, VERDICT_H)
    for i = 1, VERDICT_LINES do
        local fs = smallText(parts.verdict.body, "GameFontHighlight", USE_W)
        fs:SetPoint("TOPLEFT", parts.verdict.body, "TOPLEFT", INNER_PAD, -(i - 1) * LINE_H)
        parts.lines[i] = fs
    end
    y = y - VERDICT_H - PANEL_GAP
    buildChartPanel(right, y)
    y = y - CHART_PANEL_H - PANEL_GAP
    buildFigures(right, y)
    y = y - FIGURES_PANEL_H - PANEL_GAP
    parts.weekPanel = panelAt(right, L.HISTORY_WEEK, 0, y, RIGHT_W, WEEK_PANEL_H)
    local names = {}
    for i = 1, 7 do names[i] = L["WEEKDAY_" .. i] end
    parts.week = Chart.newWeekday(parts.weekPanel.body, USE_W, WEEK_H, names)
    parts.week.frame:SetPoint("TOPLEFT", parts.weekPanel.body, "TOPLEFT", INNER_PAD, 0)
    y = y - WEEK_PANEL_H - PANEL_GAP
    parts.status = smallText(right, "GameFontDisableSmall", RIGHT_W)
    parts.status:SetPoint("TOPLEFT", right, "TOPLEFT", 0, y - 4)
    y = y - 4 - STATUS_H - 4
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
    -- The messages of the empty states.
    parts.empty = right:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    parts.empty:SetWidth(RIGHT_W - 40)
    parts.empty:SetJustifyH("CENTER")
    parts.empty:SetWordWrap(true)
end

local function build()
    frame = Native.window(NAME, L.HISTORY_TITLE, {
        width = WIDTH,
        height = CHROME_H + PAD + RIGHT_H + PAD,
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
    -- The wheel only scrolls the cached rows: no data work per step.
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        scrollTo(math.max(0, offset - delta))
    end)
    -- A delete waiting for its second click never survives closing the window.
    frame:HookScript("OnHide", disarm)
    local left0, top0 = origin.left + PAD, -(origin.top + PAD)
    buildLeft(left0, top0)
    buildRight(left0, top0)
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
