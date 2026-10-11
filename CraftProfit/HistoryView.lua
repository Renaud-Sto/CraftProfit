-- Turns a tracked recipe and its items' price series into the figures the history window
-- and the main window arrows show. Pure Lua, no WoW API, no widgets.
--
-- HistoryView.recipeDays(recipe, itemSeriesOf, now, days, cut, itemsOf)
--   -> { { day, materials, sale, net, carried, n }, ... } ascending, one entry per local
--   day of the last `days` days on which at least one item of the recipe was measured.
--   itemSeriesOf(itemID) returns that item's saved series (or nil); itemsOf is the same
--   function History.record uses (Controller.historyItems): a crafted item it does not
--   require (bound on pickup) is never sold. An item without a point on a day takes its
--   last known daily price, from the whole daily tier, and the day is marked `carried`;
--   before an item's first point it has no price and whatever needs it stays nil.
--   materials = sum of qty x day price (Core.sumCost), sale = Core.netSale of the crafted
--   item (commission `cut`), net = sale - materials, as Evaluate computes them; n = the
--   most measures of one item that day. Never mutates the saved series.
-- HistoryView.summary(days, field) -> { today, usual, low, high, measures, daysCovered,
--   enough } for one view: `field` names the value of recipeDays entries ("net",
--   "materials", "sale"); without it the entries are a History.dailySeries (avg, low,
--   high). today = the value of the newest day, usual = median of the days of the 30 days
--   up to it (nil under 3 days, then enough = false). Entries without a value are skipped.
-- HistoryView.indicators(recipe, itemSeriesOf, now, itemsOf, cut)
--   -> { materials = { pct, tone, good } or nil, sale = { pct, tone, good } or nil }:
--   today against the usual price over 30 days. Materials cheaper and a sale higher are
--   good (true), the opposite bad (false); within the flat band good is nil.
local _, ns = ...
local Util, Core, History = ns.Util, ns.Core, ns.History

local HistoryView = {}
ns.HistoryView = HistoryView

local DAY = 86400
-- How far back a price may be carried from: the whole daily tier.
HistoryView.LOOKBACK_DAYS = 62

-- Whether itemsOf requires the crafted item (it is sold at the auction house).
local function sellsOutput(recipe, itemsOf)
    if type(itemsOf) ~= "function" then return true end
    local _, required = itemsOf(recipe)
    for _, id in ipairs(type(required) == "table" and required or {}) do
        if id == recipe.outputItemID then return true end
    end
    return false
end

function HistoryView.recipeDays(recipe, itemSeriesOf, now, days, cut, itemsOf)
    local out = {}
    days = Util.count(days)
    if type(recipe) ~= "table" or type(recipe.reagents) ~= "table" or type(itemSeriesOf) ~= "function"
        or not Util.isCopper(now) or not days then
        return out
    end
    local sells = sellsOutput(recipe, itemsOf)
    local ids, seen = {}, {}
    local function want(id)
        if Util.id(id) and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    for _, r in ipairs(recipe.reagents) do want(type(r) == "table" and r.itemID or nil) end
    if sells then want(recipe.outputItemID) end

    -- Daily points of each item, over the period and the lookback a carried price may need.
    local first = History.dayOf(History.dayOf(now) - (days - 1) * DAY + DAY / 2)
    local daily, measured, order = {}, {}, {}
    for _, id in ipairs(ids) do
        local entries = History.dailySeries(itemSeriesOf(id), now, math.max(days, HistoryView.LOOKBACK_DAYS))
        daily[id] = entries
        for _, e in ipairs(entries) do
            if e.day >= first and not measured[e.day] then
                measured[e.day] = true
                order[#order + 1] = e.day
            end
        end
    end
    table.sort(order)

    for _, day in ipairs(order) do
        local carried, n = false, 0
        local prices = {}
        for _, id in ipairs(ids) do
            -- The newest entry on or before this day.
            local found
            for _, e in ipairs(daily[id]) do
                if e.day > day then break end
                found = e
            end
            if found then
                prices[id] = found.avg
                if found.day == day then
                    n = math.max(n, found.n)
                else
                    carried = true
                end
            end
        end
        local function priceOf(id) return prices[id] end
        local materials = Core.sumCost(recipe.reagents, priceOf)
        local sale = sells and Core.netSale(prices[recipe.outputItemID], recipe.outputQty, cut) or nil
        local net = (materials and sale) and sale - materials or nil
        out[#out + 1] = { day = day, materials = materials, sale = sale, net = net, carried = carried, n = n }
    end
    return out
end

function HistoryView.summary(days, field)
    local result = { measures = 0, daysCovered = 0, enough = false }
    if type(days) ~= "table" then return result end
    local rows = {}
    for _, d in ipairs(days) do
        if type(d) == "table" and Util.isFinite(d.day) then
            local value
            if field then value = d[field] else value = d.avg end
            if Util.isFinite(value) then
                local low, high = value, value
                if not field and Util.isFinite(d.low) and Util.isFinite(d.high) then low, high = d.low, d.high end
                rows[#rows + 1] = { day = d.day, value = value, low = low, high = high,
                    n = Util.count(d.n) or 0 }
            end
        end
    end
    if #rows == 0 then return result end
    local newest = rows[1]
    for _, r in ipairs(rows) do
        if r.day >= newest.day then newest = r end
        result.low = result.low and math.min(result.low, r.low) or r.low
        result.high = result.high and math.max(result.high, r.high) or r.high
        result.measures = result.measures + r.n
    end
    result.today = newest.value
    result.daysCovered = #rows
    local from = History.dayOf(newest.day - (History.USUAL_DAYS - 1) * DAY + DAY / 2)
    local values = {}
    for _, r in ipairs(rows) do
        if r.day >= from then values[#values + 1] = r.value end
    end
    if #values >= History.USUAL_MIN_DAYS then
        result.usual = History.median(values)
        result.enough = true
    end
    return result
end

local function indicator(summary, higherIsGood)
    local c = History.compare(summary.today, summary.usual)
    if not c then return nil end
    if c.tone == "up" then c.good = higherIsGood elseif c.tone == "down" then c.good = not higherIsGood end
    return c
end

function HistoryView.indicators(recipe, itemSeriesOf, now, itemsOf, cut)
    local days = HistoryView.recipeDays(recipe, itemSeriesOf, now, History.USUAL_DAYS, cut, itemsOf)
    return {
        materials = indicator(HistoryView.summary(days, "materials"), false),
        sale = indicator(HistoryView.summary(days, "sale"), true),
    }
end
