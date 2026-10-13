-- Geometry of the price history chart and the weekday strip, in pixels of an abstract
-- area: no frames, no textures. Pure Lua, no WoW API. Never raises on empty or hostile
-- input; it returns an empty result instead.
--
-- ChartModel.scale(lo, hi, steps) -> { min, max, step, ticks }
--   A readable axis around [lo, hi]: 5 % padding (a range of 0 is padded by 10 % of the
--   value, at least 1 copper), never below 0 when lo >= 0, step 1, 2 or 5 x 10^k copper
--   (at least 1) for about `steps` intervals (default 4, kept within 2 to 20), min and max
--   multiples of the step, so 0 is a tick whenever the range crosses it. Always max > min.
--   A bound that is not finite is ignored and the padded range is kept within
--   +-Util.MAX_COPPER, so a hostile value never makes a long tick list.
-- ChartModel.priceLabel(copper) -> plain text, never icons: the two largest units, "12g 40s",
--   "12g", "40s 5c", "5c", "0c"; from 1000 gold, thousands of gold rounded down to one
--   decimal ("1.2k g", "1k g") and none from 100k ("999k g"); from 1 million gold, millions
--   the same way ("1M g", "12.3M g", "1000M g" for Util.MAX_COPPER, the cap applied to any
--   larger amount); a minus sign for a loss ("-3g 10s"); "?" for anything not finite.
-- ChartModel.slots(period) -> { count, index(day, newest) } for a period of `period` days
--   (1 to 62) ending at the local day `newest`: index is 1 (oldest) to count (newest), nil
--   outside the period. Days are counted by rounding, so 23 and 25 hour days still count once.
-- ChartModel.extent(days, field) -> lo, hi of the values bars() would draw, or nil.
-- ChartModel.range(days, period, newest, field) -> { first, last, count } or nil: the slots
--   the chart draws. They end at `newest` (default: the newest drawn day) and start at the
--   oldest drawn day inside the period, with at least MIN_SLOTS and at most `period` slots,
--   so a few days of data on a 60-day period never leave the plot mostly empty. first is
--   `last` minus count - 1 days (in seconds). nil when nothing in the period can be drawn.
-- ChartModel.dateTicks(count, newest) -> { { slot, t }, ... }: the first, middle and last
--   slot (distinct ones only), t at midday of that slot's day (safe from 23/25 hour days).
-- ChartModel.zeroY(scale, height) -> y of 0, or nil when the scale does not hold 0.
-- ChartModel.dashes(width, dash, gap) -> { { x, w }, ... } segments of a dashed line over
--   [0, width), the last one cut at the width; at most MAX_DASHES; {} when unusable.
-- ChartModel.bars(days, scale, width, height, field, period, newest)
--   -> { { slot, x, w, yLow, yHigh, yAvg, yEdge, carried, row }, ... } inside a width x
--   height area, y from the top. `days` are HistoryView.recipeDays rows charted on `field`
--   ("net", "materials", "sale"; low = high = the value, carried from `<field>Carried`,
--   else `carried`) or, with no field, History.dailySeries rows (avg, low, high). A net
--   bar stands on the zero line (from 0 to the value, 0 clamped into the area); yEdge is
--   the bar's outer end: the value for a recipe view, the high for an item. A row without
--   a finite value is skipped and its slot stays empty: missing days are gaps, never zeros.
--   `newest` defaults to the newest drawn day. Values outside the scale are clamped.
-- ChartModel.usualY(usual, scale, height) -> { y, outside } or nil: outside is "above" or
--   "below" when the usual price is off the scale (y then sits on that border).
-- ChartModel.weekdayBars(profile, width, height) -> 7 entries Monday to Sunday
--   { x, w, y, h, pct, n, empty } around a zero line at mid-height, plus `limit`: the scale
--   is symmetric, +-limit %, limit = the largest |pct| rounded up to 5, at least 10. An
--   entry without a finite pct (fewer than 2 days) is empty, with a height of 0.
local _, ns = ...
local Util = ns.Util

local ChartModel = {}
ns.ChartModel = ChartModel

local DAY = 86400
ChartModel.DEFAULT_STEPS = 4
ChartModel.MIN_STEPS, ChartModel.MAX_STEPS = 2, 20
ChartModel.MAX_SLOTS = 62
ChartModel.BAR_FILL = 0.6        -- share of a slot a bar covers
ChartModel.MIN_WEEKDAY_LIMIT = 10
ChartModel.MIN_SLOTS = 7
ChartModel.MAX_DASHES = 400

-- The smallest step 1, 2 or 5 x 10^k at least `raw`, and at least 1.
local function niceStep(raw)
    if not Util.isFinite(raw) or raw <= 1 then return 1 end
    local base = 10 ^ math.floor(math.log10(raw))
    if base * 10 <= raw then base = base * 10 end
    if base > raw then base = base / 10 end
    for _, m in ipairs({ 1, 2, 5, 10 }) do
        if m * base >= raw then return math.max(1, m * base) end
    end
    return base * 10
end

function ChartModel.scale(lo, hi, steps)
    steps = Util.clamp(Util.count(steps) or ChartModel.DEFAULT_STEPS, ChartModel.MIN_STEPS, ChartModel.MAX_STEPS)
    local cap = Util.MAX_COPPER
    if not Util.isFinite(lo) then lo = Util.isFinite(hi) and hi or 0 end
    if not Util.isFinite(hi) then hi = lo end
    if lo > hi then lo, hi = hi, lo end
    local positive = lo >= 0
    local pad = (hi - lo) * 0.05
    if hi == lo then pad = math.max(math.abs(lo) * 0.1, 1) end
    lo = Util.clamp(lo - pad, -cap, cap)
    hi = Util.clamp(hi + pad, -cap, cap)
    if hi <= lo then lo = hi - 1 end
    if positive and lo < 0 then lo = 0 end
    local step = niceStep((hi - lo) / steps)
    local min = math.floor(lo / step) * step
    local max = math.ceil(hi / step) * step
    if max <= min then max = min + step end
    local ticks = {}
    local count = Util.round((max - min) / step)
    for i = 0, count do ticks[#ticks + 1] = min + i * step end
    return { min = min, max = max, step = step, ticks = ticks }
end

function ChartModel.priceLabel(copper)
    if not Util.isFinite(copper) then return "?" end
    local c = Util.round(Util.clamp(copper, -Util.MAX_COPPER, Util.MAX_COPPER))
    if c < 0 then return "-" .. ChartModel.priceLabel(-c) end
    local g = math.floor(c / 10000)
    local s = math.floor(c % 10000 / 100)
    local cc = c % 100
    -- Thousands (k) or millions (M) of gold, rounded down to one decimal, none from 100.
    local function big(units, size, suffix)
        local v = math.floor(units / (size / 10)) / 10
        if v >= 100 then return string.format("%d%s g", math.floor(v), suffix) end
        return (string.format("%.1f", v):gsub("%.0$", "")) .. suffix .. " g"
    end
    if g >= 1000000 then return big(g, 1000000, "M") end
    if g >= 1000 then return big(g, 1000, "k") end
    if g >= 1 then return s > 0 and string.format("%dg %ds", g, s) or string.format("%dg", g) end
    if s >= 1 then return cc > 0 and string.format("%ds %dc", s, cc) or string.format("%ds", s) end
    return string.format("%dc", cc)
end

function ChartModel.slots(period)
    local count = Util.count(period)
    if not count or count > ChartModel.MAX_SLOTS then return nil end
    return {
        count = count,
        index = function(day, newest)
            if not Util.isFinite(day) or not Util.isFinite(newest) then return nil end
            local i = count - math.floor((newest - day) / DAY + 0.5)
            if i < 1 or i > count then return nil end
            return i
        end,
    }
end

-- The value, low and high a row draws, or nil.
local function rowValues(row, field)
    if type(row) ~= "table" or not Util.isFinite(row.day) then return nil end
    if field then
        local v = row[field]
        if not Util.isFinite(v) then return nil end
        return v, v, v
    end
    local v = row.avg
    if not Util.isFinite(v) then return nil end
    local low = Util.isFinite(row.low) and row.low or v
    local high = Util.isFinite(row.high) and row.high or v
    return v, math.min(low, v), math.max(high, v)
end

-- The newest day with a drawable value, or nil.
local function newestDrawn(days, field)
    local newest
    for _, row in ipairs(days) do
        if rowValues(row, field) and (not newest or row.day > newest) then newest = row.day end
    end
    return newest
end

function ChartModel.extent(days, field)
    if type(days) ~= "table" then return nil end
    local lo, hi
    for _, row in ipairs(days) do
        local _, low, high = rowValues(row, field)
        if low then
            lo = lo and math.min(lo, low) or low
            hi = hi and math.max(hi, high) or high
        end
    end
    if lo == nil then return nil end
    return lo, hi
end

local function validScale(scale)
    return type(scale) == "table" and Util.isFinite(scale.min) and Util.isFinite(scale.max)
        and scale.max > scale.min
end

-- y of a value from the top of an area of `height`, clamped into it.
local function yOf(value, scale, height)
    local y = (scale.max - value) / (scale.max - scale.min) * height
    return Util.clamp(y, 0, height)
end

local function validSize(n)
    return Util.isFinite(n) and n > 0
end

function ChartModel.bars(days, scale, width, height, field, period, newest)
    local out = {}
    local slots = ChartModel.slots(period)
    if type(days) ~= "table" or not validScale(scale) or not validSize(width) or not validSize(height)
        or not slots then
        return out
    end
    if not Util.isFinite(newest) then
        newest = newestDrawn(days, field)
        if not newest then return out end
    end
    local slotW = width / slots.count
    local w = math.max(1, math.floor(slotW * ChartModel.BAR_FILL))
    for _, row in ipairs(days) do
        local v, low, high = rowValues(row, field)
        local slot = v and slots.index(row.day, newest)
        if slot then
            local flag = field and row[field .. "Carried"]
            if flag == nil then flag = row.carried end
            if field == "net" then low, high = math.min(v, 0), math.max(v, 0) end
            local yAvg = yOf(v, scale, height)
            out[#out + 1] = {
                slot = slot, x = (slot - 1) * slotW + (slotW - w) / 2, w = w,
                yLow = yOf(low, scale, height), yHigh = yOf(high, scale, height), yAvg = yAvg,
                yEdge = field and yAvg or yOf(high, scale, height),
                carried = flag and true or false, row = row,
            }
        end
    end
    table.sort(out, function(a, b) return a.slot < b.slot end)
    return out
end

function ChartModel.range(days, period, newest, field)
    local slots = ChartModel.slots(period)
    if type(days) ~= "table" or not slots then return nil end
    if not Util.isFinite(newest) then newest = newestDrawn(days, field) end
    if not newest then return nil end
    local oldest
    for _, row in ipairs(days) do
        local i = rowValues(row, field) and slots.index(row.day, newest)
        if i and (not oldest or i < oldest) then oldest = i end
    end
    if not oldest then return nil end
    local count = math.min(slots.count, math.max(ChartModel.MIN_SLOTS, slots.count - oldest + 1))
    return { first = newest - (count - 1) * DAY, last = newest, count = count }
end

function ChartModel.dateTicks(count, newest)
    local out = {}
    count = Util.count(count)
    if not count or not Util.isFinite(newest) then return out end
    local seen = {}
    for _, slot in ipairs({ 1, math.ceil(count / 2), count }) do
        if not seen[slot] then
            seen[slot] = true
            out[#out + 1] = { slot = slot, t = newest - (count - slot) * DAY + DAY / 2 }
        end
    end
    return out
end

function ChartModel.zeroY(scale, height)
    if not validScale(scale) or not validSize(height) or scale.min > 0 or scale.max < 0 then return nil end
    return yOf(0, scale, height)
end

function ChartModel.dashes(width, dash, gap)
    local out = {}
    if not validSize(width) or not validSize(dash) or not Util.isFinite(gap) or gap < 0 then return out end
    local x = 0
    while x < width and #out < ChartModel.MAX_DASHES do
        out[#out + 1] = { x = x, w = math.min(dash, width - x) }
        x = x + dash + gap
    end
    return out
end

function ChartModel.usualY(usual, scale, height)
    if not Util.isFinite(usual) or not validScale(scale) or not validSize(height) then return nil end
    local outside
    if usual > scale.max then outside = "above" elseif usual < scale.min then outside = "below" end
    return { y = yOf(usual, scale, height), outside = outside }
end

function ChartModel.weekdayBars(profile, width, height)
    local out = {}
    if not validSize(width) or not validSize(height) then return out end
    if type(profile) ~= "table" then profile = {} end
    local pcts, limit = {}, ChartModel.MIN_WEEKDAY_LIMIT
    for i = 1, 7 do
        local entry = profile[i]
        local pct = type(entry) == "table" and entry.pct or nil
        if Util.isFinite(pct) then
            pcts[i] = pct
            limit = math.max(limit, math.ceil(math.abs(pct) / 5) * 5)
        end
    end
    local mid = height / 2
    local slotW = width / 7
    local w = math.max(1, math.floor(slotW * ChartModel.BAR_FILL))
    for i = 1, 7 do
        local entry = profile[i]
        local n = type(entry) == "table" and Util.count(entry.n) or 0
        local pct = pcts[i]
        local bar = { x = (i - 1) * slotW + (slotW - w) / 2, w = w, y = mid, h = 0, pct = pct, n = n, empty = pct == nil }
        if pct then
            bar.h = math.abs(pct) / limit * mid
            if pct > 0 then bar.y = mid - bar.h end
        end
        out[i] = bar
    end
    out.limit = limit
    return out
end
