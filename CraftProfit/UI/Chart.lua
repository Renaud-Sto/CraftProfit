-- The price history chart and the typical week widget. Geometry comes from ChartModel
-- (pure); this file only places pooled textures, font strings and slot buttons, on plain
-- frames with coloured textures (the plot sits on the game's InsetFrameTemplate).
--
-- Chart.new(parent, width, height, window) -> chart, with:
--   chart.frame               the root frame (the caller anchors it; it starts shown)
--   chart:set(model)          model = { days, field, scale, usual, usualLabel, period, newest,
--                             carriedTint } (see ChartModel.bars for days/field/newest).
--                             The x range is ChartModel.range: from the oldest drawn day of
--                             the period to `newest`, 7 slots at least, `period` at most; the
--                             slot count drives the bar width. scale is computed from the days
--                             and the usual price when absent (the net view always holds 0).
--                             usualLabel is the text of the chip at the right end of the
--                             dashed usual line; carriedTint (default 0.4) multiplies a
--                             carried day's alpha. nil or anything unusable clears the chart.
--   chart:clear()
--   chart.dateText(t)         set by the caller: the short date under the plot for the time t
--                             (first, middle and last slot); without it no date is written
--   chart.bubbleText(row)     set by the caller: the lines (array of strings, the first one
--                             the title) of the bubble the chart draws, inside the plot, over
--                             a hovered day; nil or {} draws no bubble. The chart draws the
--                             bubble itself, so the window only words it.
--   chart.onHover(row, slot)  optional, set by the caller: called with the day row under the
--                             pointer (nil over a gap, when the pointer leaves the chart, when
--                             a drag starts, and when the chart is cleared while hovered)
-- Look: faint gridlines with plain amounts at the left ("0" for zero), dates under the plot,
-- for each day a semi-transparent body (low to high of the day; a net day stands on the
-- zero line, green for a profit, red for a loss) with a lighter outer edge, a bright dash
-- and a dot at the day's value, a line through the values (Line objects, Chart.USE_LINES),
-- the usual price as a gold dashed line with its chip; carried days lighter.
-- The slot buttons cover the plot, so they would swallow a drag of the window: with
-- `window` (a Native.window) they forward a left drag to it (Native.forwardDrag) and report
-- no hover while it moves. Without `window` they only hover.
-- Everything drawn comes from pools: a redraw reuses what exists and hides the rest, so
-- drawing 60 days then 7 creates nothing new. Nothing runs per frame.
--
-- Chart.newWeekday(parent, width, height, names) -> week, with:
--   week.frame                the root frame
--   week:set(profile, emptyText)  History.weekdayProfile output (7 entries, Monday first):
--                             the percentage above each bar, the weekday name (names[i])
--                             under it; when no weekday has a value, only `emptyText` shows,
--                             on one muted line.
-- Chart.USE_LINES: on since the probe (/cppn line, docs/probe-findings.md F14) showed Line
-- objects work on Forever; when CreateLine is missing or raises, the bars stay alone.
local _, ns = ...
local Util, Colors, ChartModel, Native, Layout = ns.Util, ns.Colors, ns.ChartModel, ns.Native, ns.Layout

local Chart = {}
Chart.__index = Chart
ns.Chart = Chart

Chart.USE_LINES = true
Chart.DEFAULT_W, Chart.DEFAULT_H = 400, 240
Chart.FLAT_PX = 2          -- a bar this thin or thinner is drawn as its dot only
Chart.LABEL_W = 38          -- left gutter for the axis amounts
Chart.DATE_H = 18           -- dates under the plot
Chart.CARRIED_TINT = 0.4
Chart.BODY_ALPHA = 0.35     -- a day's body; its outer edge and its dash are opaque
Chart.EDGE_H = 2
Chart.DOT = 4
Chart.LINE_THICKNESS = 2
Chart.DASH, Chart.DASH_GAP = 6, 4
Chart.BUBBLE_W = 260
Chart.BUBBLE_LINE_H = 14
Chart.BUBBLE_PAD = 6
Chart.BUBBLE_LINES = 7
Chart.FONT = "GameFontHighlightSmall"
Chart.BUBBLE_FONT = "GameFontHighlight"
Chart.CHIP_CHAR_W = 6
Chart.WEEK_LABEL_H = 12     -- the typical week's percentage row and name row

local GRID, ZERO = Colors.CHART.grid, Colors.CHART.zero
local BACKDROP = { 0, 0, 0, 0.35 }
local HIGHLIGHT = { 1, 1, 1, 0.08 }
local BUBBLE_BG = { 0.05, 0.05, 0.05, 0.92 }

local function paint(tex, c, alpha)
    local a = (c[4] or 1) * (alpha or 1)
    tex:SetColorTexture(c[1], c[2], c[3], a)
    tex.color = { c[1], c[2], c[3], a }
end

-- Halfway to white: the lighter outer edge of a bar.
local function lighter(c)
    return { c[1] + (1 - c[1]) * 0.5, c[2] + (1 - c[2]) * 0.5, c[3] + (1 - c[3]) * 0.5, c[4] or 1 }
end

local function place(region, parent, x, y, w, h)
    w, h = math.max(1, w), math.max(1, h)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    region:SetSize(w, h)
    region.box = { x = x, y = y, w = w, h = h }
end

-- A horizontal span [x, x + w) kept inside [0, limit), at least 1 px wide.
local function within(x, w, limit)
    local left = Util.clamp(x, 0, math.max(0, limit - 1))
    local right = Util.clamp(x + w, left + 1, math.max(left + 1, limit))
    return left, right - left
end

-- A vertical position y with `h` pixels kept inside [0, limit].
local function inside(y, h, limit)
    return Util.clamp(y, 0, math.max(0, limit - h))
end

local function size(n, default)
    if Util.isFinite(n) and n > 0 then return n end
    return default
end

-- Puts a frame `above` another's level, when the client says what that level is.
local function raiseAbove(f, other, by)
    if type(other.GetFrameLevel) ~= "function" then return end
    local level = other:GetFrameLevel()
    if type(level) == "number" then f:SetFrameLevel(level + by) end
end

function Chart.new(parent, width, height, window)
    local self = setmetatable({}, Chart)
    if type(window) == "table" then
        -- Stands for the window in Native.forwardDrag: the drag also ends any hover, and
        -- raising walks up to the real window through GetParent.
        self.dragProxy = {
            StartMoving = function()
                self.dragging = true
                self:endHover()
                window:StartMoving()
            end,
            stopDrag = function()
                self.dragging = false
                window.stopDrag(window)
            end,
            GetParent = function() return window end,
        }
    end
    self.width = size(width, Chart.DEFAULT_W)
    self.height = size(height, Chart.DEFAULT_H)
    self.plotW = math.max(10, self.width - Chart.LABEL_W)
    self.plotH = math.max(10, self.height - Chart.DATE_H)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(self.width, self.height)
    self.frame = frame
    -- The plot's own darker inset (it shares the frame's level; the plot is one up).
    self.inset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    self.inset:SetPoint("TOPLEFT", frame, "TOPLEFT", Chart.LABEL_W - 2, 2)
    self.inset:SetSize(self.plotW + 4, self.plotH + 4)
    local plot = CreateFrame("Frame", nil, frame)
    plot:SetPoint("TOPLEFT", frame, "TOPLEFT", Chart.LABEL_W, 0)
    plot:SetSize(self.plotW, self.plotH)
    self.plot = plot
    self.backdrop = plot:CreateTexture(nil, "BACKGROUND", nil, -8)
    paint(self.backdrop, BACKDROP)
    self.backdrop:SetAllPoints(plot)
    self.highlight = plot:CreateTexture(nil, "BACKGROUND", nil, 2)
    paint(self.highlight, HIGHLIGHT)
    self.pools = { bars = {}, grid = {}, labels = {}, slots = {}, lines = {}, dashes = {}, dates = {} }
    self.zeroLine = plot:CreateTexture(nil, "BORDER")
    paint(self.zeroLine, ZERO)
    self.chip = plot:CreateTexture(nil, "OVERLAY", nil, 1)
    paint(self.chip, BUBBLE_BG)
    self.usualLabel = plot:CreateFontString(nil, "OVERLAY", Chart.FONT)
    self:buildBubble()
    self.rowsBySlot = {}
    self:clear()
    return self
end

-- The hover bubble: a small dark panel with a thin gold rim and BUBBLE_LINES lines.
function Chart:buildBubble()
    local b = CreateFrame("Frame", nil, self.plot)
    raiseAbove(b, self.plot, 20)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    paint(b.bg, BUBBLE_BG)
    b.bg:SetAllPoints(b)
    local gold = Colors.text("gold")
    b.rim = {}
    for i, side in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" } }) do
        local t = b:CreateTexture(nil, "BORDER")
        paint(t, gold, 0.6)
        t:SetPoint(side[1], b, side[1], 0, 0)
        t:SetPoint(side[2], b, side[2], 0, 0)
        t:SetHeight(1)
        b.rim[i] = t
    end
    b.lines = {}
    for i = 1, Chart.BUBBLE_LINES do
        local fs = b:CreateFontString(nil, "OVERLAY", i == 1 and "GameFontNormal" or Chart.BUBBLE_FONT)
        fs:SetPoint("TOPLEFT", b, "TOPLEFT", Chart.BUBBLE_PAD, -(Chart.BUBBLE_PAD + (i - 1) * Chart.BUBBLE_LINE_H))
        fs:SetWidth(Chart.BUBBLE_W - 2 * Chart.BUBBLE_PAD)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        b.lines[i] = fs
    end
    b:Hide()
    self.bubble = b
end

-- Pools ------------------------------------------------------------------------------

local BAR_PARTS = { "span", "edge", "tick", "dot" }

local function acquireBar(self, i)
    local bar = self.pools.bars[i]
    if not bar then
        bar = {
            span = self.plot:CreateTexture(nil, "ARTWORK"),
            edge = self.plot:CreateTexture(nil, "ARTWORK", nil, 1),
            tick = self.plot:CreateTexture(nil, "OVERLAY"),
            dot = self.plot:CreateTexture(nil, "OVERLAY", nil, 1),
        }
        self.pools.bars[i] = bar
    end
    for _, k in ipairs(BAR_PARTS) do bar[k]:Show() end
    bar.shown = true
    return bar
end

local function acquireTick(self, i)
    local grid, label = self.pools.grid[i], self.pools.labels[i]
    if not grid then
        grid = self.plot:CreateTexture(nil, "BACKGROUND", nil, 1)
        paint(grid, GRID)
        label = self.plot:CreateFontString(nil, "OVERLAY", Chart.FONT)
        self.pools.grid[i], self.pools.labels[i] = grid, label
    end
    grid:Show()
    label:Show()
    return grid, label
end

local function acquire(self, pool, i, make)
    local x = self.pools[pool][i]
    if not x then
        x = make()
        self.pools[pool][i] = x
    end
    x:Show()
    return x
end

local function acquireSlot(self, i)
    local b = self.pools.slots[i]
    if not b then
        b = CreateFrame("Button", nil, self.plot)
        b.slot = i
        b:EnableMouse(true)
        b:SetScript("OnEnter", function(button)
            if self.dragging then return end
            self:hover(button.slot)
        end)
        b:SetScript("OnLeave", function() self:endHover() end)
        if self.dragProxy then Native.forwardDrag(b, self.dragProxy) end
        self.pools.slots[i] = b
    end
    b:Show()
    return b
end

local function hideFrom(list, first, key)
    for i = first, #list do
        local item = list[i]
        if key then
            for _, k in ipairs(key) do item[k]:Hide() end
            item.shown = false
        else
            item:Hide()
        end
    end
end

-- Hover --------------------------------------------------------------------------------

-- Highlights slot `slot`, draws the bubble of its day (when there is one and the caller
-- words it) and reports the day.
function Chart:hover(slot)
    self.hovered = slot
    local count = self.range and self.range.count
    if not count then return end
    local slotW = self.plotW / count
    place(self.highlight, self.plot, (slot - 1) * slotW, 0, slotW, self.plotH)
    self.highlight:Show()
    local row = self.rowsBySlot[slot]
    local lines = row and type(self.bubbleText) == "function" and self.bubbleText(row) or nil
    local b = self.bubble
    if type(lines) == "table" and #lines > 0 then
        local n = math.min(#lines, Chart.BUBBLE_LINES)
        for i, fs in ipairs(b.lines) do
            fs:SetText(i <= n and tostring(lines[i]) or "")
            fs:SetShown(i <= n)
        end
        local h = n * Chart.BUBBLE_LINE_H + 2 * Chart.BUBBLE_PAD
        local w = math.min(Chart.BUBBLE_W, self.plotW)
        local centre = (slot - 0.5) * slotW
        local x = centre + 8
        if x + w > self.plotW then x = math.max(0, centre - 8 - w) end
        place(b, self.plot, x, 4, w, math.min(h, self.plotH))
        b.lineCount = n
        b:Show()
    else
        b:Hide()
    end
    if type(self.onHover) == "function" then self.onHover(row, slot) end
end

-- Reports the end of a hover once (hiding a button fires no OnLeave).
function Chart:endHover()
    if self.hovered == nil then return end
    self.hovered = nil
    self.highlight:Hide()
    self.bubble:Hide()
    if type(self.onHover) == "function" then self.onHover(nil) end
end

function Chart:clear()
    self:endHover()
    self.highlight:Hide()
    self.bubble:Hide()
    hideFrom(self.pools.bars, 1, BAR_PARTS)
    for _, pool in ipairs({ "grid", "labels", "slots", "lines", "dashes", "dates" }) do
        hideFrom(self.pools[pool], 1)
    end
    self.zeroLine:Hide()
    self.chip:Hide()
    self.usualLabel:Hide()
    self.usualShown = false
    self.usualOutside = nil
    self.drawn = {}
    self.scale = nil
    self.range = nil
    self.rowsBySlot = {}
end

-- Drawing ----------------------------------------------------------------------------

local function yOf(scale, value, height)
    return Util.clamp((scale.max - value) / (scale.max - scale.min) * height, 0, height)
end

local function barColor(field, row)
    if field == "net" and Util.isFinite(row.net) then
        return row.net < 0 and Colors.FIXED.loss or Colors.FIXED.profit
    end
    return Colors.text("gold")
end

-- Line segments { a, b } (points { x, y }), from the pool. False (and nothing shown) when
-- the client cannot draw lines.
function Chart:drawLine(segments)
    local lines = self.pools.lines
    local ok = true
    local c = Colors.text("main")
    for i = 1, #segments do
        local line = lines[i]
        if not line then
            local created, l = pcall(self.plot.CreateLine, self.plot, nil, "ARTWORK", nil, 2)
            if not created or type(l) ~= "table" then
                ok = false
                break
            end
            line = l
            lines[i] = line
        end
        local a, b = segments[i][1], segments[i][2]
        local drawn = pcall(function()
            line:SetColorTexture(c[1], c[2], c[3], 0.8)
            line:SetThickness(Chart.LINE_THICKNESS)
            line:SetStartPoint("TOPLEFT", self.plot, a[1], -a[2])
            line:SetEndPoint("TOPLEFT", self.plot, b[1], -b[2])
            line:Show()
        end)
        if not drawn then
            ok = false
            break
        end
    end
    if not ok then
        hideFrom(lines, 1)
        return false
    end
    hideFrom(lines, #segments + 1)
    return true
end

function Chart:drawBars(drawn, field, tint)
    local W, Hh = self.plotW, self.plotH
    local main = Colors.text("main")
    for i, d in ipairs(drawn) do
        local bar = acquireBar(self, i)
        local color = barColor(field, d.row)
        local alpha = d.carried and tint or 1
        -- Kept inside the plot: at least one pixel of each bar shows, nothing spills out.
        local x, w = within(d.x, d.w, W)
        local top = Util.clamp(d.yHigh, 0, Hh - 1)
        local bottom = Util.clamp(d.yLow, top + 1, Hh)
        paint(bar.span, color, alpha * Chart.BODY_ALPHA)
        place(bar.span, self.plot, x, top, w, bottom - top)
        paint(bar.edge, lighter(color), alpha)
        place(bar.edge, self.plot, x, inside(d.yEdge - Chart.EDGE_H / 2, Chart.EDGE_H, Hh), w, Chart.EDGE_H)
        local tx, tw = within(d.x - 2, d.w + 4, W)
        paint(bar.tick, main, alpha)
        place(bar.tick, self.plot, tx, Util.clamp(d.yAvg - 1, 0, Hh - 2), tw, 2)
        local cx = d.x + d.w / 2
        local dx, dw = within(cx - Chart.DOT / 2, Chart.DOT, W)
        -- A day with no spread (a single measurement) is only its dot: no rectangle, edge or dash.
        if bottom - top <= Chart.FLAT_PX then
            bar.span:Hide()
            bar.edge:Hide()
            bar.tick:Hide()
        end
        paint(bar.dot, color, alpha)
        place(bar.dot, self.plot, dx, inside(d.yAvg - Chart.DOT / 2, Chart.DOT, Hh), dw, Chart.DOT)
        self.rowsBySlot[d.slot] = d.row
    end
    hideFrom(self.pools.bars, #drawn + 1, BAR_PARTS)
end

function Chart:drawGrid(scale)
    local W, Hh = self.plotW, self.plotH
    local ticks = {}
    for _, v in ipairs(type(scale.ticks) == "table" and scale.ticks or {}) do
        if Util.isFinite(v) then ticks[#ticks + 1] = v end
    end
    for i, v in ipairs(ticks) do
        local grid, label = acquireTick(self, i)
        local y = math.min(yOf(scale, v, Hh), Hh - 1)
        place(grid, self.plot, 0, y, W, 1)
        label:SetText(v == 0 and "0" or ChartModel.priceLabel(v))
        label:ClearAllPoints()
        label:SetPoint("RIGHT", self.plot, "TOPLEFT", -4, -y)
    end
    hideFrom(self.pools.grid, #ticks + 1)
    hideFrom(self.pools.labels, #ticks + 1)
end

function Chart:drawUsual(usual, label, scale)
    local W, Hh = self.plotW, self.plotH
    local u = usual and ChartModel.usualY(usual, scale, Hh)
    if not u then return end
    local gold = Colors.text("gold")
    local y = math.min(u.y, Hh - 1)
    local dashes = ChartModel.dashes(W, Chart.DASH, Chart.DASH_GAP)
    for i, d in ipairs(dashes) do
        local tex = acquire(self, "dashes", i, function() return self.plot:CreateTexture(nil, "OVERLAY") end)
        paint(tex, gold, 0.85)
        place(tex, self.plot, d.x, y, d.w, 1)
    end
    hideFrom(self.pools.dashes, #dashes + 1)
    local mark = u.outside == "above" and " ^" or (u.outside == "below" and " v" or "")
    local text = (type(label) == "string" and label ~= "" and (label .. " ") or "") .. ChartModel.priceLabel(usual) .. mark
    self.usualLabel:SetText(text)
    self.usualLabel:SetTextColor(gold[1], gold[2], gold[3], 1)
    local chipW = math.min(W, Layout.textWidth(text, Chart.CHIP_CHAR_W) + 6)
    place(self.chip, self.plot, W - chipW, inside(y - 7, 14, Hh), chipW, 14)
    self.chip:Show()
    self.usualLabel:ClearAllPoints()
    self.usualLabel:SetPoint("RIGHT", self.chip, "RIGHT", -3, 0)
    self.usualLabel:Show()
    self.usualShown = true
    self.usualOutside = u.outside
end

function Chart:drawDates(range)
    local slotW = self.plotW / range.count
    local ticks = ChartModel.dateTicks(range.count, range.last)
    for i, tick in ipairs(ticks) do
        local fs = acquire(self, "dates", i, function() return self.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall") end)
        fs:SetText(type(self.dateText) == "function" and self.dateText(tick.t) or "")
        fs:ClearAllPoints()
        if tick.slot == range.count then
            fs:SetPoint("TOPRIGHT", self.plot, "BOTTOMRIGHT", 0, -2)
        elseif tick.slot == 1 then
            fs:SetPoint("TOPLEFT", self.plot, "BOTTOMLEFT", 0, -2)
        else
            fs:SetPoint("TOP", self.plot, "BOTTOMLEFT", (tick.slot - 0.5) * slotW, -2)
        end
        fs.slot = tick.slot
    end
    hideFrom(self.pools.dates, #ticks + 1)
end

function Chart:set(model)
    self:clear()
    if type(model) ~= "table" or type(model.days) ~= "table" then return end
    local field = model.field
    if field ~= nil and type(field) ~= "string" then return end
    local range = ChartModel.range(model.days, model.period or 30, model.newest, field)
    if not range then return end
    local usual = Util.isFinite(model.usual) and model.usual or nil
    local scale = model.scale
    if scale == nil then
        local lo, hi = ChartModel.extent(model.days, field)
        if lo == nil then return end
        if usual then lo, hi = math.min(lo, usual), math.max(hi, usual) end
        -- A profit is read against zero: the net view always shows it.
        if field == "net" then lo, hi = math.min(lo, 0), math.max(hi, 0) end
        scale = ChartModel.scale(lo, hi)
    end
    local W, Hh = self.plotW, self.plotH
    local drawn = ChartModel.bars(model.days, scale, W, Hh, field, range.count, range.last)
    if #drawn == 0 then return end
    self.scale, self.drawn, self.range = scale, drawn, range

    local tint = Util.isFinite(model.carriedTint) and Util.clamp(model.carriedTint, 0, 1) or Chart.CARRIED_TINT
    self:drawBars(drawn, field, tint)
    self:drawGrid(scale)
    local zero = ChartModel.zeroY(scale, Hh)
    if zero and (field == "net" or (scale.min < 0 and scale.max > 0)) then
        place(self.zeroLine, self.plot, 0, inside(zero - 1, 2, Hh), W, 2)
        self.zeroLine:Show()
    end
    self:drawUsual(usual, model.usualLabel, scale)
    self:drawDates(range)

    local slotW = W / range.count
    for i = 1, range.count do
        local b = acquireSlot(self, i)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", self.plot, "TOPLEFT", (i - 1) * slotW, 0)
        b:SetSize(slotW, Hh)
    end
    hideFrom(self.pools.slots, range.count + 1)

    -- One segment between each pair of neighbouring slots: a gap day stays a gap.
    self.linesOk = nil
    if Chart.USE_LINES then
        local segments = {}
        for i = 2, #drawn do
            local a, b = drawn[i - 1], drawn[i]
            if b.slot == a.slot + 1 then
                segments[#segments + 1] = { { a.x + a.w / 2, a.yAvg }, { b.x + b.w / 2, b.yAvg } }
            end
        end
        if #segments > 0 then self.linesOk = self:drawLine(segments) end
    else
        hideFrom(self.pools.lines, 1)
    end
end

-- Typical week -------------------------------------------------------------------------

local Week = {}
Week.__index = Week

-- A whole percentage, within +-999 so a hostile value stays short.
local function percentText(pct)
    local v = Util.clamp(Util.round(pct), -999, 999)
    if v == 0 then return "0%" end
    return string.format("%+d%%", v)
end

function Chart.newWeekday(parent, width, height, names)
    local self = setmetatable({}, Week)
    self.width = size(width, Chart.DEFAULT_W)
    self.height = size(height, 60)
    self.barsH = math.max(4, self.height - 2 * Chart.WEEK_LABEL_H)
    self.names = type(names) == "table" and names or {}
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(self.width, self.height)
    self.frame = frame
    self.zero = frame:CreateTexture(nil, "BORDER")
    paint(self.zero, ZERO)
    place(self.zero, frame, 0, Chart.WEEK_LABEL_H + self.barsH / 2, self.width, 1)
    self.pools = { weekday = {} }
    local slotW = self.width / 7
    for i = 1, 7 do
        local entry = {
            bar = frame:CreateTexture(nil, "ARTWORK"),
            label = frame:CreateFontString(nil, "OVERLAY", Chart.FONT),
            name = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"),
        }
        local x = (i - 0.5) * slotW
        entry.label:SetPoint("TOP", frame, "TOPLEFT", x, 0)
        entry.name:SetPoint("TOP", frame, "TOPLEFT", x, -(Chart.WEEK_LABEL_H + self.barsH))
        self.pools.weekday[i] = entry
    end
    self.note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.note:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    self.note:SetWidth(self.width)
    self.note:SetJustifyH("LEFT")
    self.note:SetWordWrap(false)
    self:set(nil)
    return self
end

function Week:set(profile, emptyText)
    local bars = ChartModel.weekdayBars(profile, self.width, self.barsH)
    local any = false
    for i = 1, 7 do
        if bars[i] and not bars[i].empty then any = true end
    end
    self.empty = not any
    self.zero:SetShown(any)
    self.note:SetText(any and "" or (emptyText or ""))
    self.note:SetShown(not any)
    for i = 1, 7 do
        local entry, b = self.pools.weekday[i], bars[i]
        if any and b and not b.empty then
            local color = b.pct < 0 and Colors.FIXED.loss or Colors.FIXED.profit
            paint(entry.bar, color)
            place(entry.bar, self.frame, b.x, Chart.WEEK_LABEL_H + b.y, b.w, math.max(1, b.h))
            entry.bar:Show()
            entry.label:SetText(percentText(b.pct))
        else
            entry.bar:Hide()
            entry.label:SetText("")
        end
        entry.label:SetShown(any)
        entry.name:SetText(self.names[i] or "")
        entry.name:SetShown(any)
    end
end
