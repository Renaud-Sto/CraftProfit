-- The price history chart: daily bars (lowest to highest price, a tick at the average),
-- the usual price line, gridlines with plain text amounts, and the weekday strip under it.
-- Geometry comes from ChartModel (pure); this file only places pooled textures, font
-- strings and slot buttons. Built from coloured textures on plain frames: no template, no
-- atlas, no image file.
--
-- Chart.new(parent, width, height) -> chart, with:
--   chart.frame               the root frame (the caller anchors it; it starts shown)
--   chart:set(model)          model = { days, field, scale, usual, period, newest, carriedTint }
--                             (see ChartModel.bars for days/field/period/newest; scale is
--                             computed from the days and the usual price when absent;
--                             carriedTint, default 0.4, multiplies a carried day's alpha);
--                             nil or anything unusable clears the chart
--   chart:clear()
--   chart:setWeekday(profile) History.weekdayProfile output (7 entries, Monday first), nil clears
--   chart.onHover(row, slot)  set by the caller: called with the day row under the pointer
--                             (nil over a gap, and when the pointer leaves the chart)
-- Everything drawn comes from pools (bars, gridline labels, slot buttons, lines, weekday
-- bars): a redraw reuses what exists and hides the rest, so drawing 60 days then 7 creates
-- nothing new. Nothing runs per frame: drawing happens in set/setWeekday only.
-- Chart.USE_LINES adds a line through the daily averages with the game's Line objects
-- (frame:CreateLine), off until the probe (/cppn line, docs/probe-findings.md F14) shows
-- they work on Forever; when CreateLine is missing or raises, the bars stay alone.
local _, ns = ...
local Util, Colors, ChartModel = ns.Util, ns.Colors, ns.ChartModel

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
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    region:SetSize(math.max(1, w), math.max(1, h))
end

local function size(n, default)
    if Util.isFinite(n) and n > 0 then return n end
    return default
end

function Chart.new(parent, width, height)
    local self = setmetatable({}, Chart)
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
            if type(self.onHover) == "function" then self.onHover(self.rowsBySlot[button.slot], button.slot) end
        end)
        b:SetScript("OnLeave", function()
            if type(self.onHover) == "function" then self.onHover(nil) end
        end)
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

function Chart:clear()
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

-- Line segments through the points, from the pool. False (and nothing shown) when the
-- client cannot draw lines.
function Chart:drawLine(points)
    local lines = self.pools.lines
    local ok = true
    for i = 1, #points - 1 do
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
        local a, b = points[i], points[i + 1]
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
    hideFrom(lines, math.max(1, #points))
    return true
end

function Chart:set(model)
    self:clear()
    if type(model) ~= "table" or type(model.days) ~= "table" then return end
    local field = model.field
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
        paint(bar.span, color, alpha)
        place(bar.span, self.plot, d.x, d.yHigh, d.w, d.yLow - d.yHigh)
        paint(bar.tick, Colors.text("main"), alpha)
        place(bar.tick, self.plot, d.x - 2, d.yAvg - 1, d.w + 4, 2)
        self.rowsBySlot[d.slot] = d.row
    end
    hideFrom(self.pools.bars, #drawn + 1, BAR_PARTS)

    for i, v in ipairs(scale.ticks or {}) do
        local grid, label = acquireTick(self, i)
        local y = yOf(scale, v, Hh)
        place(grid, self.plot, 0, y, W, 1)
        label:SetText(ChartModel.priceLabel(v))
        label:ClearAllPoints()
        label:SetPoint("RIGHT", self.plot, "TOPLEFT", -4, -y)
    end
    if scale.min < 0 and scale.max > 0 then
        place(self.zeroLine, self.plot, 0, yOf(scale, 0, Hh), W, 1)
        self.zeroLine:Show()
    end

    local u = usual and ChartModel.usualY(usual, scale, Hh)
    if u then
        place(self.usualLine, self.plot, 0, u.y, W, 1)
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

    self.linesOk = nil
    if Chart.USE_LINES and #drawn >= 2 then
        local points = {}
        for _, d in ipairs(drawn) do points[#points + 1] = { d.x + d.w / 2, d.yAvg } end
        self.linesOk = self:drawLine(points)
    end
end

-- Weekday strip ----------------------------------------------------------------------

local function percentText(pct)
    if pct == 0 then return "0%" end
    return string.format("%+d%%", pct)
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
