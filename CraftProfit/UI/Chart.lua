-- The price history chart: daily bars (lowest to highest price, a tick at the average),
-- the usual price line, gridlines with plain text amounts, and the weekday strip under it.
-- Geometry comes from ChartModel (pure); this file only places pooled textures, font
-- strings and slot buttons. Built from coloured textures on plain frames: no template, no
-- atlas, no image file.
--
-- Chart.new(parent, width, height, window) -> chart, with:
--   chart.frame               the root frame (the caller anchors it; it starts shown)
--   chart:set(model)          model = { days, field, scale, usual, period, newest, carriedTint }
--                             (see ChartModel.bars for days/field/period/newest; scale is
--                             computed from the days and the usual price when absent;
--                             carriedTint, default 0.4, multiplies a carried day's alpha);
--                             nil or anything unusable clears the chart
--   chart:clear()
--   chart:setWeekday(profile) History.weekdayProfile output (7 entries, Monday first), nil clears
--   chart.onHover(row, slot)  set by the caller: called with the day row under the pointer
--                             (nil over a gap, when the pointer leaves the chart, when a
--                             drag starts, and when the chart is cleared while hovered)
-- The slot buttons cover the plot, so they would swallow a drag of the window: with
-- `window` (a Native.window) they forward a left drag to it (Native.forwardDrag) and report
-- no hover while it moves. Without `window` they only hover.
-- Everything drawn comes from pools (bars, gridline labels, slot buttons, lines, weekday
-- bars): a redraw reuses what exists and hides the rest, so drawing 60 days then 7 creates
-- nothing new. Nothing runs per frame: drawing happens in set/setWeekday only.
-- Chart.USE_LINES adds a line through the daily averages with the game's Line objects
-- (frame:CreateLine), off until the probe (/cppn line, docs/probe-findings.md F14) shows
-- they work on Forever; when CreateLine is missing or raises, the bars stay alone.
local _, ns = ...
local Util, Colors, ChartModel, Native = ns.Util, ns.Colors, ns.ChartModel, ns.Native

local Chart = {}
Chart.__index = Chart
ns.Chart = Chart

Chart.USE_LINES = false
Chart.DEFAULT_W, Chart.DEFAULT_H = 400, 240
Chart.LABEL_W = 60          -- left gutter for the axis amounts
Chart.STRIP_H = 50          -- weekday strip at the bottom (bars and their percentages)
Chart.STRIP_LABEL_H = 12
Chart.STRIP_GAP = 8
Chart.CARRIED_TINT = 0.4
Chart.FONT = "GameFontHighlightSmall"

local GRID = { 0.5, 0.5, 0.5, 0.25 }
local ZERO = { 0.8, 0.8, 0.8, 0.6 }
local USUAL = { 1, 1, 1, 0.7 }

local function paint(tex, c, alpha)
    local a = (c[4] or 1) * (alpha or 1)
    tex:SetColorTexture(c[1], c[2], c[3], a)
    tex.color = { c[1], c[2], c[3], a }
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

local function size(n, default)
    if Util.isFinite(n) and n > 0 then return n end
    return default
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
    self.plotH = math.max(10, self.height - Chart.STRIP_H - Chart.STRIP_GAP)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(self.width, self.height)
    self.frame = frame
    local plot = CreateFrame("Frame", nil, frame)
    plot:SetPoint("TOPLEFT", frame, "TOPLEFT", Chart.LABEL_W, 0)
    plot:SetSize(self.plotW, self.plotH)
    self.plot = plot
    local strip = CreateFrame("Frame", nil, frame)
    strip:SetPoint("TOPLEFT", plot, "BOTTOMLEFT", 0, -Chart.STRIP_GAP)
    strip:SetSize(self.plotW, Chart.STRIP_H)
    self.strip = strip
    self.pools = { bars = {}, grid = {}, labels = {}, slots = {}, lines = {}, weekday = {} }
    self.zeroLine = plot:CreateTexture(nil, "BORDER")
    paint(self.zeroLine, ZERO)
    self.usualLine = plot:CreateTexture(nil, "OVERLAY")
    paint(self.usualLine, USUAL)
    self.usualLabel = plot:CreateFontString(nil, "OVERLAY", Chart.FONT)
    self.stripZero = strip:CreateTexture(nil, "BORDER")
    paint(self.stripZero, ZERO)
    self.rowsBySlot = {}
    self:clear()
    self:setWeekday(nil)
    return self
end

-- Pools ------------------------------------------------------------------------------

local function acquireBar(self, i)
    local bar = self.pools.bars[i]
    if not bar then
        bar = { span = self.plot:CreateTexture(nil, "ARTWORK"), tick = self.plot:CreateTexture(nil, "OVERLAY") }
        self.pools.bars[i] = bar
    end
    bar.span:Show()
    bar.tick:Show()
    bar.shown = true
    return bar
end

local function acquireTick(self, i)
    local grid, label = self.pools.grid[i], self.pools.labels[i]
    if not grid then
        grid = self.plot:CreateTexture(nil, "BACKGROUND")
        paint(grid, GRID)
        label = self.plot:CreateFontString(nil, "OVERLAY", Chart.FONT)
        self.pools.grid[i], self.pools.labels[i] = grid, label
    end
    grid:Show()
    label:Show()
    return grid, label
end

local function acquireSlot(self, i)
    local b = self.pools.slots[i]
    if not b then
        b = CreateFrame("Button", nil, self.plot)
        b.slot = i
        b:EnableMouse(true)
        b:SetScript("OnEnter", function(button)
            if self.dragging then return end
            self.hovered = button.slot
            if type(self.onHover) == "function" then self.onHover(self.rowsBySlot[button.slot], button.slot) end
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

local BAR_PARTS = { "span", "tick" }

-- Reports the end of a hover once (hiding a button fires no OnLeave).
function Chart:endHover()
    if self.hovered == nil then return end
    self.hovered = nil
    if type(self.onHover) == "function" then self.onHover(nil) end
end

function Chart:clear()
    self:endHover()
    hideFrom(self.pools.bars, 1, BAR_PARTS)
    hideFrom(self.pools.grid, 1)
    hideFrom(self.pools.labels, 1)
    hideFrom(self.pools.slots, 1)
    hideFrom(self.pools.lines, 1)
    self.zeroLine:Hide()
    self.usualLine:Hide()
    self.usualLabel:Hide()
    self.usualOutside = nil
    self.drawn = {}
    self.scale = nil
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
    for i = 1, #segments do
        local line = lines[i]
        if not line then
            local created, l = pcall(self.plot.CreateLine, self.plot, nil, "OVERLAY")
            if not created or type(l) ~= "table" then
                ok = false
                break
            end
            line = l
            lines[i] = line
        end
        local a, b = segments[i][1], segments[i][2]
        local drawn = pcall(function()
            line:SetColorTexture(USUAL[1], USUAL[2], USUAL[3], 0.9)
            line:SetThickness(1)
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

function Chart:set(model)
    self:clear()
    if type(model) ~= "table" or type(model.days) ~= "table" then return end
    local field = model.field
    if field ~= nil and type(field) ~= "string" then return end
    local period = model.period or 30
    if not ChartModel.slots(period) then return end
    local usual = Util.isFinite(model.usual) and model.usual or nil
    local scale = model.scale
    if scale == nil then
        local lo, hi = ChartModel.extent(model.days, field)
        if lo == nil then return end
        if usual then lo, hi = math.min(lo, usual), math.max(hi, usual) end
        scale = ChartModel.scale(lo, hi)
    end
    local W, Hh = self.plotW, self.plotH
    local drawn = ChartModel.bars(model.days, scale, W, Hh, field, period, model.newest)
    if #drawn == 0 then return end
    self.scale, self.drawn = scale, drawn

    local tint = Util.isFinite(model.carriedTint) and Util.clamp(model.carriedTint, 0, 1) or Chart.CARRIED_TINT
    for i, d in ipairs(drawn) do
        local bar = acquireBar(self, i)
        local color = barColor(field, d.row)
        local alpha = d.carried and tint or 1
        -- Kept inside the plot: at least one pixel of each bar shows, nothing spills out.
        local x, w = within(d.x, d.w, W)
        local top = Util.clamp(d.yHigh, 0, Hh - 1)
        local bottom = Util.clamp(d.yLow, top + 1, Hh)
        paint(bar.span, color, alpha)
        place(bar.span, self.plot, x, top, w, bottom - top)
        local tx, tw = within(d.x - 2, d.w + 4, W)
        paint(bar.tick, Colors.text("main"), alpha)
        place(bar.tick, self.plot, tx, Util.clamp(d.yAvg - 1, 0, Hh - 2), tw, 2)
        self.rowsBySlot[d.slot] = d.row
    end
    hideFrom(self.pools.bars, #drawn + 1, BAR_PARTS)

    local ticks = {}
    for _, v in ipairs(type(scale.ticks) == "table" and scale.ticks or {}) do
        if Util.isFinite(v) then ticks[#ticks + 1] = v end
    end
    for i, v in ipairs(ticks) do
        local grid, label = acquireTick(self, i)
        local y = math.min(yOf(scale, v, Hh), Hh - 1)
        place(grid, self.plot, 0, y, W, 1)
        label:SetText(ChartModel.priceLabel(v))
        label:ClearAllPoints()
        label:SetPoint("RIGHT", self.plot, "TOPLEFT", -4, -y)
    end
    if scale.min < 0 and scale.max > 0 then
        place(self.zeroLine, self.plot, 0, math.min(yOf(scale, 0, Hh), Hh - 1), W, 1)
        self.zeroLine:Show()
    end

    local u = usual and ChartModel.usualY(usual, scale, Hh)
    if u then
        place(self.usualLine, self.plot, 0, math.min(u.y, Hh - 1), W, 1)
        self.usualLine:Show()
        local mark = u.outside == "above" and " ^" or (u.outside == "below" and " v" or "")
        self.usualLabel:SetText(ChartModel.priceLabel(usual) .. mark)
        self.usualLabel:ClearAllPoints()
        self.usualLabel:SetPoint("BOTTOMRIGHT", self.plot, "TOPRIGHT", -2, -u.y + 1)
        self.usualLabel:Show()
        self.usualOutside = u.outside
    end

    local count = ChartModel.slots(period).count
    local slotW = W / count
    for i = 1, count do
        local b = acquireSlot(self, i)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", self.plot, "TOPLEFT", (i - 1) * slotW, 0)
        b:SetSize(slotW, Hh)
    end
    hideFrom(self.pools.slots, count + 1)

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
    end
end

-- Weekday strip ----------------------------------------------------------------------

-- A whole percentage, within +-999 so a hostile value stays short.
local function percentText(pct)
    local v = Util.clamp(Util.round(pct), -999, 999)
    if v == 0 then return "0%" end
    return string.format("%+d%%", v)
end

function Chart:setWeekday(profile)
    local barsH = Chart.STRIP_H - Chart.STRIP_LABEL_H
    local bars = ChartModel.weekdayBars(profile, self.plotW, barsH)
    place(self.stripZero, self.strip, 0, barsH / 2, self.plotW, 1)
    for i = 1, 7 do
        local entry = self.pools.weekday[i]
        if not entry then
            entry = { bar = self.strip:CreateTexture(nil, "ARTWORK"),
                label = self.strip:CreateFontString(nil, "OVERLAY", Chart.FONT) }
            self.pools.weekday[i] = entry
        end
        local b = bars[i]
        if b and not b.empty then
            local color = b.pct < 0 and Colors.FIXED.loss or Colors.FIXED.profit
            paint(entry.bar, color)
            place(entry.bar, self.strip, b.x, b.y, b.w, math.max(1, b.h))
            entry.bar:Show()
            entry.label:SetText(percentText(b.pct))
        else
            entry.bar:Hide()
            entry.label:SetText("")
        end
        local x = b and (b.x + b.w / 2) or 0
        entry.label:ClearAllPoints()
        entry.label:SetPoint("TOP", self.strip, "TOPLEFT", x, -barsH)
    end
end
