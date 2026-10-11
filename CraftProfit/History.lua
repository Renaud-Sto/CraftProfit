-- Price history of the tracked recipes. Pure Lua, no WoW API.
--
-- A tracked recipe is a copy of a recipe plus an `active` flag, kept account wide in
-- db.tracked (at most MAX_TRACKED, paused ones included). Each price measurement of
-- an item of an active tracked recipe becomes a point in market.series[itemID]:
-- { t, unit, volume, low, high, n }. A raw point has low = high = unit and n = 1.
-- Points older than 7 days are merged into one point per local day, and a day is dropped once
-- it ended more than 60 days ago. Each tier has its own cap, so a busy week can only drop
-- raw points, never the daily history.
local _, ns = ...
local Util, Recipes = ns.Util, ns.Recipes

local History = {}
ns.History = History

History.MAX_TRACKED = 30
local DAY = 86400
History.RAW_SECONDS = 7 * DAY
History.DAILY_SECONDS = 60 * DAY
-- Points kept per item in each tier. Raw points have no natural bound (one per operation
-- that touches the item): the newest 150 are kept. The daily tier spans 53 days (55 buckets
-- at most), so its cap never binds on sane data. At most 212 points an item.
History.MAX_RAW = 150
History.MAX_DAILY = 62
-- A point dated further ahead than this blocks recording (written with a clock that ran
-- ahead, or edited by hand): it is dropped when a new point is added. Loading and compacting
-- keep it, so a clock set back for a while never erases newer history.
History.FUTURE_SLACK = DAY

-- Tracked list ----------------------------------------------------------------

function History.find(db, recipeID)
    for i, entry in ipairs(db.tracked) do
        if entry.recipe.recipeID == recipeID then return i, entry end
    end
    return nil
end

function History.isActive(db, recipeID)
    local _, entry = History.find(db, recipeID)
    return entry ~= nil and entry.active == true
end

-- Starts (or resumes) tracking. Returns true, or false and "invalid" / "full".
function History.track(db, recipe)
    local clean = Recipes.normalize(recipe)
    if not clean then return false, "invalid" end
    local _, entry = History.find(db, clean.recipeID)
    if entry then
        entry.active = true
        entry.recipe = clean
        return true
    end
    if #db.tracked >= History.MAX_TRACKED then return false, "full" end
    db.tracked[#db.tracked + 1] = { recipe = clean, active = true }
    return true
end

-- Stops recording but keeps the entry and its history.
function History.pause(db, recipeID)
    local _, entry = History.find(db, recipeID)
    if not entry then return false end
    entry.active = false
    return true
end

-- Deletes the entry. Series are not touched here (see History.prune).
function History.remove(db, index)
    if type(index) ~= "number" or not db.tracked[index] then return false end
    table.remove(db.tracked, index)
    return true
end

-- Local days ---------------------------------------------------------------------
--
-- The local calendar date comes from a function like the game's date("*t", t) and the
-- start of a day from a function like time(fields): History.setDateFn(dateFn, timeFn)
-- injects both (nil restores the game's). A day start is built from the date fields
-- (year, month, day at 00:00), so a day with a daylight saving change (23 or 25 hours)
-- is still one day. If the time function gives something that is not that day's start
-- (missing, or a stub that ignores its argument), the start is derived from the clock
-- fields, which is exact except after the change hour of a daylight saving day.

local dateFn, timeFn

function History.setDateFn(dateF, timeF)
    dateFn, timeFn = dateF, timeF
end

local DATE_FIELDS = { "year", "month", "day", "hour", "min", "sec", "wday" }

-- The local date fields of t, or nil when the date function gives nothing usable.
local function localDate(t)
    if not Util.isFinite(t) then return nil end
    -- `date` and `time` are the game's globals (os.date and os.time in plain Lua).
    local fn = dateFn or date or (os and os.date)
    if type(fn) ~= "function" then return nil end
    local ok, d = pcall(fn, "*t", t)
    if not ok or type(d) ~= "table" then return nil end
    for _, k in ipairs(DATE_FIELDS) do
        if not Util.isFinite(d[k]) then return nil end
    end
    return d
end

-- Start of the local calendar day holding t, or nil when the local date is unknown.
function History.dayOf(t)
    local d = localDate(t)
    if not d then return nil end
    local approx = t - ((d.hour * 60 + d.min) * 60 + d.sec)
    local fn = timeFn or time or (os and os.time)
    if type(fn) == "function" then
        local ok, s = pcall(fn, { year = d.year, month = d.month, day = d.day, hour = 0, min = 0, sec = 0 })
        -- The real start equals the clock-field estimate, or differs from it by the
        -- daylight saving shift (one hour) after the change, and never comes after t.
        if ok and Util.isFinite(s) and s <= t and (s == approx or math.abs(s - approx) == 3600) then return s end
    end
    return approx
end

-- Day of the week of t, local time: 1 Monday .. 7 Sunday, or nil when unknown.
function History.weekday(t)
    local d = localDate(t)
    if not d then return nil end
    return (d.wday + 5) % 7 + 1
end

-- Points -----------------------------------------------------------------------

local function validPoint(p)
    return type(p) == "table"
        and Util.isCopper(p[1]) and Util.isCopper(p[2]) and p[2] > 0
        and Util.isCopper(p[3]) and Util.isCopper(p[4]) and Util.isCopper(p[5])
        and Util.count(p[6]) ~= nil
end

-- The newest `max` points of a time-ordered array, in order.
local function newest(points, max)
    if #points <= max then return points end
    local out = {}
    for i = #points - max + 1, #points do out[#out + 1] = points[i] end
    return out
end

local function byTime(a, c) return a[1] < c[1] end

-- Merges the points older than RAW_SECONDS into one point per local calendar day (dated
-- at the start of that local day, History.dayOf), drops a day once it ended DAILY_SECONDS ago or more, and caps each tier to its
-- newest points (a point ahead of `now` counts as raw). Whether a day is kept depends only
-- on its start, never on the date of a point in it, so a daily point is never dropped by a
-- later pass while its day is still in the window: running it again changes nothing.
-- Returns a new, time-ordered array. An invalid `now` changes nothing: the series is
-- returned as it is.
function History.compact(series, now)
    if not Util.isCopper(now) then return series end
    local raw, buckets, order = {}, {}, {}
    local oldestEnd = now - History.DAILY_SECONDS
    for _, p in ipairs(series) do
        if validPoint(p) then
            if now - p[1] <= History.RAW_SECONDS then
                raw[#raw + 1] = p
            else
                -- Unknown local date: the point stays alone, dated as it is.
                local t = History.dayOf(p[1]) or p[1]
                if t + DAY > oldestEnd then
                    local b = buckets[t]
                    if not b then
                        b = { t, 0, 0, p[4], p[5], 0 }
                        buckets[t] = b
                        order[#order + 1] = t
                    end
                    -- Weighted by the number of measurements merged into each point.
                    b[2] = b[2] + p[2] * p[6]
                    b[3] = b[3] + p[3] * p[6]
                    b[4] = math.min(b[4], p[4])
                    b[5] = math.max(b[5], p[5])
                    b[6] = b[6] + p[6]
                end
            end
        end
    end
    local daily = {}
    for _, t in ipairs(order) do
        local b = buckets[t]
        daily[#daily + 1] = { b[1], Util.round(b[2] / b[6]), Util.round(b[3] / b[6]), b[4], b[5], b[6] }
    end
    -- Each tier is sorted on its own so its cap keeps its newest points.
    table.sort(raw, byTime)
    table.sort(daily, byTime)
    local keep = {}
    for _, tier in ipairs({ newest(daily, History.MAX_DAILY), newest(raw, History.MAX_RAW) }) do
        for _, p in ipairs(tier) do keep[#keep + 1] = p end
    end
    -- A daily point is dated at the start of its day, before its own points, so the two
    -- tiers may interleave at their edge: the joined array is sorted once more.
    table.sort(keep, byTime)
    return keep
end

local function addPoint(market, itemID, now, unit, volume)
    local series = market.series[itemID]
    if not series then
        series = {}
        market.series[itemID] = series
    end
    local last = series[#series]
    if last and last[1] >= now then
        -- A point from a clock that ran ahead blocks the series: the points more than
        -- FUTURE_SLACK ahead are dropped now, as this one is added. A point of this very
        -- second (or within the slack) still wins, so the same instant is never recorded twice.
        local kept = {}
        for _, p in ipairs(series) do
            if not (type(p) == "table" and Util.isFinite(p[1]) and p[1] > now + History.FUTURE_SLACK) then
                kept[#kept + 1] = p
            end
        end
        series = kept
        market.series[itemID] = series
        last = series[#series]
        if last and last[1] >= now then return false end
    end
    series[#series + 1] = { now, unit, volume, unit, unit, 1 }
    market.series[itemID] = History.compact(series, now)
    return true
end

-- Records one point for each item of every active tracked recipe touched by this
-- operation. `updated` is the set of itemIDs whose price was just written;
-- itemsOf(recipe) returns the item ids to record and the ones that must have a
-- price (the output of a bind-on-pickup recipe, for example, is never priced).
-- A recipe is recorded only when every required item has a price. Returns how
-- many recipes got at least one new point.
function History.record(db, market, now, updated, itemsOf)
    if not Util.isCopper(now) or type(updated) ~= "table" then return 0 end
    local recorded = 0
    for _, entry in ipairs(db.tracked) do
        if entry.active then
            local items, required = itemsOf(entry.recipe)
            local touched, complete = false, true
            for _, id in ipairs(items) do
                if updated[id] then touched = true end
            end
            for _, id in ipairs(required) do
                local row = market.prices[id]
                if type(row) ~= "table" or not Util.isCopper(row[1]) or row[1] <= 0 then complete = false end
            end
            if touched and complete then
                local added = false
                for _, id in ipairs(items) do
                    local row = market.prices[id]
                    if type(row) == "table" and Util.isCopper(row[1]) and row[1] > 0
                        and addPoint(market, id, now, row[1], row[2]) then
                        added = true
                    end
                end
                if added then recorded = recorded + 1 end
            end
        end
    end
    return recorded
end

-- Drops the series of items no tracked recipe (active or paused) needs any more.
-- Needs the same itemsOf as record. Returns how many series were removed.
function History.prune(db, market, itemsOf)
    local needed = {}
    for _, entry in ipairs(db.tracked) do
        for _, id in ipairs((itemsOf(entry.recipe))) do needed[id] = true end
    end
    local removed = 0
    for id in pairs(market.series) do
        if not needed[id] then
            market.series[id] = nil
            removed = removed + 1
        end
    end
    return removed
end

-- Repairs db.tracked and every market's series in place. Called after DB.initAccount.
function History.sanitize(db, now)
    if type(db.tracked) ~= "table" then db.tracked = {} end
    local keep, seen = {}, {}
    local keys = {}
    for k in pairs(db.tracked) do
        if Util.isFinite(k) and k >= 1 then keys[#keys + 1] = k end
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local entry = db.tracked[k]
        local recipe = type(entry) == "table" and Recipes.normalize(entry.recipe) or nil
        if recipe and not seen[recipe.recipeID] and #keep < History.MAX_TRACKED then
            seen[recipe.recipeID] = true
            keep[#keep + 1] = { recipe = recipe, active = entry.active == true }
        end
    end
    for k in pairs(db.tracked) do db.tracked[k] = nil end
    for i, entry in ipairs(keep) do db.tracked[i] = entry end
    if type(db.markets) ~= "table" then db.markets = {} end
    for _, market in pairs(db.markets) do
        if type(market.series) ~= "table" then market.series = {} end
        for itemID, series in pairs(market.series) do
            if Util.id(itemID) ~= itemID or type(series) ~= "table" then
                market.series[itemID] = nil
            else
                market.series[itemID] = History.compact(series, now)
            end
        end
    end
end

-- Daily views -------------------------------------------------------------------
--
-- History.dailySeries(series, now, days) -> { { day, avg, low, high, n }, ... }
--   One entry per local calendar day of the last `days` days (today included) that has
--   at least one point, ascending; days without data are absent. `day` is the epoch of
--   the start of that local day. Every point goes to the local day holding its date (a
--   merged daily point is dated at the start of its local day), weighted by its count.
--   Points after `now`, and points whose local date is unknown, are ignored. Never mutates
--   `series`; a hostile series or argument gives an empty array.
-- History.usual(series, now) -> { price, days, measures } or nil
--   Median of the daily averages of the last 30 days; nil under 3 distinct days.
-- History.compare(today, usual) -> { pct, tone } or nil
--   pct = rounded percent difference (today - usual) / usual; tone "flat" when |pct| <= 3,
--   else "up" or "down". nil when either is not finite or usual <= 0.
-- History.weekdayProfile(days, usual) -> 7 entries, Monday to Sunday, { pct, n }
--   From dailySeries entries (or any entries with `day` and `avg` or `value`): the mean of
--   the daily values of that weekday against `usual`, as a rounded percentage; pct is nil
--   with fewer than 2 days or without a usable usual price.
-- History.dayOf(t), History.weekday(t) (1 Monday .. 7 Sunday): see Local days above.

History.USUAL_DAYS = 30
History.USUAL_MIN_DAYS = 3
History.FLAT_PERCENT = 3
History.WEEKDAY_MIN_DAYS = 2

-- Start of the local day `k` days before the local day starting at `day`. Local days are
-- 23 to 25 hours long, and the shifts of 60 days add up to an hour at most, so the middle
-- of the target day is never missed.
local function daysBefore(day, k)
    return History.dayOf(day - k * DAY + DAY / 2)
end

function History.dailySeries(series, now, days)
    local out = {}
    if type(series) ~= "table" or not Util.isCopper(now) then return out end
    days = Util.count(days)
    if not days then return out end
    local today = History.dayOf(now)
    local first = today and daysBefore(today, days - 1)
    if not first then return out end
    local byDay, order = {}, {}
    for _, p in ipairs(series) do
        if validPoint(p) and p[1] <= now then
            local day = History.dayOf(p[1])
            if day and day >= first then
                local b = byDay[day]
                if not b then
                    b = { day = day, sum = 0, low = p[4], high = p[5], n = 0 }
                    byDay[day] = b
                    order[#order + 1] = b
                end
                b.sum = b.sum + p[2] * p[6]
                b.low = math.min(b.low, p[4])
                b.high = math.max(b.high, p[5])
                b.n = b.n + p[6]
            end
        end
    end
    for _, b in ipairs(order) do
        out[#out + 1] = { day = b.day, avg = Util.round(b.sum / b.n), low = b.low, high = b.high, n = b.n }
    end
    table.sort(out, function(a, c) return a.day < c.day end)
    return out
end

-- Median of an array of finite numbers (rounded mean of the two middle ones when even).
function History.median(values)
    local sorted = {}
    for _, v in ipairs(values) do sorted[#sorted + 1] = v end
    if #sorted == 0 then return nil end
    table.sort(sorted)
    local mid = math.floor((#sorted + 1) / 2)
    if #sorted % 2 == 1 then return sorted[mid] end
    return Util.round((sorted[mid] + sorted[mid + 1]) / 2)
end

function History.usual(series, now)
    local daily = History.dailySeries(series, now, History.USUAL_DAYS)
    if #daily < History.USUAL_MIN_DAYS then return nil end
    local values, measures = {}, 0
    for _, d in ipairs(daily) do
        values[#values + 1] = d.avg
        measures = measures + d.n
    end
    return { price = History.median(values), days = #daily, measures = measures }
end

function History.compare(today, usual)
    if not Util.isFinite(today) or not Util.isFinite(usual) or usual <= 0 then return nil end
    local pct = Util.round((today - usual) / usual * 100)
    local tone = "flat"
    if pct > History.FLAT_PERCENT then tone = "up" elseif pct < -History.FLAT_PERCENT then tone = "down" end
    return { pct = pct, tone = tone }
end

function History.weekdayProfile(days, usual)
    local sums, counts = {}, {}
    for i = 1, 7 do sums[i], counts[i] = 0, 0 end
    if type(days) == "table" then
        for _, d in ipairs(days) do
            local value = type(d) == "table" and (d.value or d.avg) or nil
            local w = Util.isFinite(value) and History.weekday(d.day) or nil
            if w then
                sums[w] = sums[w] + value
                counts[w] = counts[w] + 1
            end
        end
    end
    local usable = Util.isFinite(usual) and usual > 0
    local out = {}
    for i = 1, 7 do
        local pct
        if usable and counts[i] >= History.WEEKDAY_MIN_DAYS then
            pct = Util.round((sums[i] / counts[i] - usual) / usual * 100)
        end
        out[i] = { pct = pct, n = counts[i] }
    end
    return out
end
