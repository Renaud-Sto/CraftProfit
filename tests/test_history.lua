local H = ...

local stubClock = dofile("tests/stubclock.lua")

-- Every test runs with a local clock at UTC unless it sets its own.
local function load()
    local ns = H.newNS("Util", "Data/Skillup", "Recipes", "History")
    ns.History.setDateFn(stubClock(0))
    return ns
end

local DAY = 86400
local NOW = 500 * DAY

local function newDB() return { tracked = {}, markets = {} } end

local function recipe(id, reagents, output)
    return { recipeID = id, name = "R" .. id, difficulty = 1, outputItemID = output or 100, outputQty = 1,
        reagents = reagents or { { itemID = 1, qty = 2 }, { itemID = 2, qty = 1 } } }
end

local function market(prices) return { prices = prices or {}, series = {} } end

local function itemsOf(r)
    local all, required = {}, {}
    for _, x in ipairs(r.reagents) do all[#all + 1] = x.itemID; required[#required + 1] = x.itemID end
    all[#all + 1] = r.outputItemID
    required[#required + 1] = r.outputItemID
    return all, required
end

H.test("tracking is capped, resumable, and keeps the recipe copy", function()
    local ns = load()
    local H2, db = ns.History, newDB()
    H.truthy(H2.track(db, recipe(1)))
    H.eq(H2.track(db, { recipeID = 0 }), false)
    H.truthy(H2.isActive(db, 1))
    H.truthy(H2.pause(db, 1))
    H.falsy(H2.isActive(db, 1))
    H.eq(#db.tracked, 1)
    H.truthy(H2.track(db, recipe(1)))
    H.truthy(H2.isActive(db, 1))
    H.eq(#db.tracked, 1)
    for id = 2, 30 do H.truthy(H2.track(db, recipe(id))) end
    H.eq(#db.tracked, 30)
    H.eq({ H2.track(db, recipe(999)) }, { false, "full" })
    H.eq(#db.tracked, 30)
    H.truthy(H2.remove(db, 1))
    H.falsy(H2.remove(db, 99))
    H.truthy(H2.track(db, recipe(999)))
end)

H.test("a point is recorded for every item of a touched, fully priced active recipe", function()
    local H2, db = load().History, newDB()
    H2.track(db, recipe(1))
    local m = market({ [1] = { 100, 5, NOW }, [2] = { 50, 3, NOW }, [100] = { 1000, 2, NOW } })
    H.eq(H2.record(db, m, NOW, { [1] = true }, itemsOf), 1)
    H.eq(m.series[1], { { NOW, 100, 5, 100, 100, 1 } })
    H.eq(m.series[100], { { NOW, 1000, 2, 1000, 1000, 1 } })
    -- same instant twice: no duplicate point, and the recipe is not counted as recorded
    H.eq(H2.record(db, m, NOW, { [1] = true }, itemsOf), 0)
    H.eq(#m.series[1], 1)
end)

H.test("a far future point is dropped, so it cannot block recording for good", function()
    local H2, db = load().History, newDB()
    H2.track(db, recipe(1))
    local m = market({ [1] = { 100, 5, NOW }, [2] = { 50, 3, NOW }, [100] = { 1000, 2, NOW } })
    -- Written while the clock was a year ahead (or hand edited).
    m.series[1] = { { NOW + 365 * DAY, 7, 1, 7, 7, 1 } }
    H.eq(H2.record(db, m, NOW, { [1] = true }, itemsOf), 1)
    H.eq(m.series[1], { { NOW, 100, 5, 100, 100, 1 } })
    -- Loading keeps points ahead of the clock: a clock set back must not erase newer
    -- history for good. Only adding a point drops the ones that block it.
    local saved = { tracked = {}, markets = { k = { prices = {}, series = {
        [5] = { { NOW - DAY, 3, 1, 3, 3, 1 }, { NOW + 2 * DAY, 9, 1, 9, 9, 1 } },
        [6] = { { NOW + 3600, 4, 1, 4, 4, 1 } },
    } } } }
    H2.sanitize(saved, NOW)
    H.eq(saved.markets.k.series[5], { { NOW - DAY, 3, 1, 3, 3, 1 }, { NOW + 2 * DAY, 9, 1, 9, 9, 1 } })
    H.eq(saved.markets.k.series[6], { { NOW + 3600, 4, 1, 4, 4, 1 } })
end)

H.test("compact keeps points ahead of a smaller now, and an invalid now changes nothing", function()
    local H2 = load().History
    local series = { { NOW - 3 * DAY, 3, 1, 3, 3, 1 }, { NOW + 30 * DAY, 9, 1, 9, 9, 1 } }
    H.eq(H2.compact(series, NOW), series)
    for _, bad in ipairs({ 0 / 0, -1, nil, "x", math.huge }) do
        H.eq(H2.compact(series, bad), series)
    end
end)

H.test("a recipe blocked by a near future point is not counted as recorded", function()
    local H2, db = load().History, newDB()
    H2.track(db, recipe(1))
    local m = market({ [1] = { 100, 5, NOW }, [2] = { 50, 3, NOW }, [100] = { 1000, 2, NOW } })
    for _, id in ipairs({ 1, 2, 100 }) do m.series[id] = { { NOW + 60, 7, 1, 7, 7, 1 } } end
    H.eq(H2.record(db, m, NOW, { [1] = true }, itemsOf), 0)
    H.eq(#m.series[1], 1)
end)

H.test("retention is 7 days raw and 60 days daily, with no weekly tier, for 30 recipes", function()
    local H2 = load().History
    H.eq(H2.RAW_SECONDS, 7 * DAY)
    H.eq(H2.DAILY_SECONDS, 60 * DAY)
    H.eq(H2.MAX_RAW, 150)
    H.eq(H2.MAX_DAILY, 62)
    H.eq(H2.MAX_TRACKED, 30)
    H.eq(H2.WEEKLY_SECONDS, nil)
    H.eq(H2.MAX_WEEKLY, nil)
end)

-- One point a day (an hour into the day) for `days` days, as a quiet user leaves it.
local function quietDays(days)
    local series = {}
    for age = days, 1, -1 do series[#series + 1] = { NOW - age * DAY + 3600, 100, 1, 100, 100, 1 } end
    return series
end

-- Counts the points of each tier. A daily point is dated at the start of its day, so the
-- oldest kept day may start up to a day before the 60 day limit.
local function tiers(H2, series, now)
    local raw, daily, older = 0, 0, 0
    for _, p in ipairs(series) do
        local age = (now or NOW) - p[1]
        if age >= H2.DAILY_SECONDS + DAY then older = older + 1
        elseif age > H2.RAW_SECONDS then daily = daily + 1
        else raw = raw + 1 end
    end
    return raw, daily, older
end

H.test("a busy week never evicts the daily tier", function()
    local H2 = load().History
    local quiet = H2.compact(quietDays(60), NOW)
    local raw0, daily, older = tiers(H2, quiet)
    H.eq(raw0, 7)
    H.eq(daily, 53)
    H.eq(older, 0)
    -- 50 operations a day for the last 7 days.
    local series = {}
    for _, p in ipairs(quiet) do series[#series + 1] = p end
    for i = 1, 7 * 50 do series[#series + 1] = { NOW - 7 * DAY + i * 1700, 200, 1, 200, 200, 1 } end
    local out = H2.compact(series, NOW)
    local raw, daily2 = tiers(H2, out)
    H.eq(raw, H2.MAX_RAW)
    H.eq(daily2, daily)
    H.eq(out[1], quiet[1])                      -- the oldest daily point survives
    H.eq(out[#out][1], NOW - 7 * DAY + 7 * 50 * 1700)  -- the newest raw point too
    H.eq(H2.compact(out, NOW), out)             -- still idempotent
end)

H.test("the tier caps hold above the most points each tier can ever hold", function()
    local H2 = load().History
    -- One point every hour for 90 days: each daily bucket is filled.
    local series = {}
    for age = 90 * 24, 1, -1 do series[#series + 1] = { NOW - age * 3600, 100, 1, 100, 100, 1 } end
    local out = H2.compact(series, NOW)
    local raw, daily, older = tiers(H2, out)
    H.eq(raw, H2.MAX_RAW)                       -- 168 raw points in 7 days: the cap binds
    H.eq(daily, 53)
    H.eq(older, 0)
    -- At any time of the day the daily cap never binds: lifting it changes nothing.
    for _, shift in ipairs({ 0, 43210, 3 * DAY + 43210, 5 * DAY + 1, DAY - 1 }) do
        local capped = H2.compact(series, NOW + shift)
        local _, d = tiers(H2, capped, NOW + shift)
        H.truthy(d >= 53 and d <= 55)
        local maxDaily = H2.MAX_DAILY
        H2.MAX_DAILY = 1e9
        local free = H2.compact(series, NOW + shift)
        H2.MAX_DAILY = maxDaily
        H.eq(capped, free)
    end
    -- Each cap applies to its own tier and keeps its newest points.
    local caps = { H2.MAX_RAW, H2.MAX_DAILY }
    H2.MAX_RAW, H2.MAX_DAILY = 3, 3
    out = H2.compact(series, NOW)
    H2.MAX_RAW, H2.MAX_DAILY = caps[1], caps[2]
    H.eq(#out, 6)
    H.eq(out[6], series[#series])
    H.eq(out[1], { NOW - 10 * DAY, 100, 1, 100, 100, 24 })  -- a full day, the newest three kept
end)

H.test("an old save (raw 14 days, daily 90, weekly 365) compacts to the new tiers without loss", function()
    local H2 = load().History
    local WEEK = 7 * DAY
    local series = {}
    -- Weekly points of the old tier, dated at the start of their week.
    for age = 365, 91, -7 do
        local t = math.floor((NOW - age * DAY) / WEEK) * WEEK
        series[#series + 1] = { t, 50, 2, 40, 60, 7 }
    end
    -- Daily points of the old tier, 15 to 90 days back.
    for age = 90, 15, -1 do series[#series + 1] = { NOW - age * DAY, 100 + age, 3, 90, 200, 5 } end
    -- Raw points every 3 hours for the last 14 days.
    for i = 1, 112 do
        series[#series + 1] = { NOW - 14 * DAY + i * 10800 - 60, 300 + 2 * i, 1, 300 + 2 * i, 300 + 2 * i, 1 }
    end
    local expected = {}
    for age = 60, 15, -1 do expected[#expected + 1] = { NOW - age * DAY, 100 + age, 3, 90, 200, 5 } end
    -- Raw points 8 to 14 days old become one daily point a day (8 points a day).
    for k = 0, 6 do
        expected[#expected + 1] = { NOW - (14 - k) * DAY, 309 + 16 * k, 1, 302 + 16 * k, 316 + 16 * k, 8 }
    end
    for i = 57, 112 do
        expected[#expected + 1] = { NOW - 14 * DAY + i * 10800 - 60, 300 + 2 * i, 1, 300 + 2 * i, 300 + 2 * i, 1 }
    end
    local out = H2.compact(series, NOW)
    H.eq(out, expected)                         -- weekly points and days over 60 are gone
    H.eq(H2.compact(out, NOW), out)             -- idempotent
    H.eq(H2.compact(H2.compact(out, NOW + 3600), NOW + 3600), H2.compact(out, NOW + 3600))
    -- Loading the save goes through the same compaction.
    local saved = { tracked = {}, markets = { k = { prices = {}, series = { [7] = series } } } }
    H2.sanitize(saved, NOW)
    H.eq(saved.markets.k.series[7], expected)
end)

H.test("a day is kept while any of it is within 60 days, at any time of day", function()
    local H2 = load().History
    for _, shift in ipairs({ 0, 1, 43210, DAY - 1 }) do
        local now = NOW + shift
        -- The point exactly 60 days old is kept: its day ends within the window.
        local series = { { now - 60 * DAY, 100, 1, 100, 100, 1 }, { now - 60 * DAY - DAY - 1, 9, 1, 9, 9, 1 } }
        local out = H2.compact(series, now)
        H.eq(#out, 1)
        H.eq(out[1][2], 100)
        H.eq(H2.compact(out, now), out)
    end
end)

H.test("no point when nothing of the recipe was touched, a required price is missing, or it is paused", function()
    local H2, db = load().History, newDB()
    H2.track(db, recipe(1))
    local m = market({ [1] = { 100, 5, NOW }, [2] = { 50, 3, NOW } })
    H.eq(H2.record(db, m, NOW, { [1] = true }, itemsOf), 0)   -- output unpriced
    m.prices[100] = { 1000, 2, NOW }
    H.eq(H2.record(db, m, NOW, { [999] = true }, itemsOf), 0) -- unrelated update
    H2.pause(db, 1)
    H.eq(H2.record(db, m, NOW, { [1] = true }, itemsOf), 0)
    H.eq(next(m.series), nil)
    H.eq(H2.record(db, m, math.huge - math.huge, { [1] = true }, itemsOf), 0)
end)

H.test("optional items are recorded when priced and never required", function()
    local H2, db = load().History, newDB()
    H2.track(db, recipe(1))
    local m = market({ [1] = { 100, 5, NOW }, [2] = { 50, 3, NOW }, [77] = { 9, 1, NOW } })
    local function items()
        return { 1, 2, 77, 100 }, { 1, 2 }
    end
    H.eq(H2.record(db, m, NOW, { [1] = true }, items), 1)
    H.truthy(m.series[77])
    H.eq(m.series[100], nil)
end)

H.test("points older than 7 days are merged by day, keeping low, high and count; over 60 days dropped", function()
    local H2 = load().History
    local series = {}
    local function add(age, unit) series[#series + 1] = { NOW - age, unit, 10, unit, unit, 1 } end
    add(1 * DAY, 100)                         -- raw
    add(7 * DAY - 60, 40)                     -- still raw
    add(20 * DAY + 100, 100)                  -- same day as the next one
    add(20 * DAY + 5000, 300)
    add(59 * DAY + 100, 70)                   -- its day starts 60 days back: kept
    add(60 * DAY + 100, 60)                   -- its day ended 60 days back: dropped
    add(120 * DAY + 100, 50)                  -- a former weekly age: dropped
    add(400 * DAY, 77)
    local out = H2.compact(series, NOW)
    H.eq(out, {
        { NOW - 60 * DAY, 70, 10, 70, 70, 1 },
        { NOW - 21 * DAY, 200, 10, 100, 300, 2 },  -- daily average of 100 and 300
        { NOW - 7 * DAY + 60, 40, 10, 40, 40, 1 },
        { NOW - 1 * DAY, 100, 10, 100, 100, 1 },
    })
    -- running it again changes nothing
    H.eq(H2.compact(out, NOW), out)
end)

H.test("a merged point is complete only if every merged point was, and keeps the count", function()
    local H2 = load().History
    local function at(age, volume, full) return { NOW - age, 100, volume, 100, 100, 1, full } end
    local series = {
        at(20 * DAY + 100, 10, true), at(20 * DAY + 200, 30, true),    -- one day, all complete
        at(19 * DAY + 100, 10, true), at(19 * DAY + 200, 30),          -- one partial point
        at(18 * DAY + 100, 10), { NOW - 18 * DAY - 50, 100, 20, 100, 100, 3 },  -- saved before the flag
        at(1 * DAY, 7, true), at(2 * DAY, 8),                          -- raw: kept as they are
    }
    local out = H2.compact(series, NOW)
    H.eq(out, {
        { NOW - 21 * DAY, 100, 20, 100, 100, 2, true },
        { NOW - 20 * DAY, 100, 20, 100, 100, 2 },
        { NOW - 19 * DAY, 100, 18, 100, 100, 4 },
        at(2 * DAY, 8), at(1 * DAY, 7, true),
    })
    H.eq(H2.compact(out, NOW), out)
    -- Loading: anything but true reads as partial, then compacts the same way.
    local saved = { tracked = {}, markets = { k = { prices = {}, series = { [7] = {
        { NOW - DAY, 5, 1, 5, 5, 1, "yes" }, { NOW - 3600, 5, 1, 5, 5, 1, true }, { NOW - 60, 5, 1, 5, 5, 1, false },
    } } } } }
    H2.sanitize(saved, NOW)
    H.eq(saved.markets.k.series[7], { { NOW - DAY, 5, 1, 5, 5, 1 }, { NOW - 3600, 5, 1, 5, 5, 1, true },
        { NOW - 60, 5, 1, 5, 5, 1 } })
end)

H.test("a recorded point carries the price row's volume flag", function()
    local H2, db = load().History, newDB()
    H2.track(db, recipe(1))
    local m = market({ [1] = { 100, 5, NOW, true }, [2] = { 50, 3, NOW }, [100] = { 1000, 2, NOW, "x" } })
    H.eq(H2.record(db, m, NOW, { [1] = true }, itemsOf), 1)
    H.eq(m.series[1], { { NOW, 100, 5, 100, 100, 1, true } })
    H.eq(m.series[2], { { NOW, 50, 3, 50, 50, 1 } })
    H.eq(m.series[100], { { NOW, 1000, 2, 1000, 1000, 1 } })
end)

H.test("compact drops corrupt points and keeps the series ordered", function()
    local H2 = load().History
    local out = H2.compact({
        { NOW - 2 * DAY, 100, 1, 100, 100, 1 }, "junk", { NOW - 3 * DAY, math.huge - math.huge, 1, 1, 1, 1 },
        { NOW - 5 * DAY, 80, 1, 80, 80, 1 }, { NOW - 3 * DAY, -4, 1, 1, 1, 1 },
    }, NOW)
    H.eq(#out, 2)
    H.eq(out[1][1] < out[2][1], true)
end)

H.test("prune drops the series nobody needs, sanitize repairs the saved tables", function()
    local H2, db = load().History, newDB()
    H2.track(db, recipe(1))
    local m = market()
    m.series = { [1] = { { NOW, 100, 1, 100, 100, 1 } }, [2] = {}, [555] = { { NOW, 5, 1, 5, 5, 1 } } }
    H.eq(H2.prune(db, m, itemsOf), 1)
    H.eq(m.series[555], nil)
    H.truthy(m.series[1])
    local bad = { tracked = { { recipe = recipe(2), active = true }, "junk", { recipe = { recipeID = -1 } } },
        markets = { m, ["a-b"] = { series = { [3] = "x", [4] = { { NOW, 5, 1, 5, 5, 1 }, "junk" } } } } }
    H2.sanitize(bad, NOW)
    H.eq(#bad.tracked, 1)
    H.eq(bad.markets["a-b"].series[3], nil)
    H.eq(#bad.markets["a-b"].series[4], 1)
    local empty = {}
    H2.sanitize(empty, NOW)
    H.eq(empty.tracked, {})
    H.eq(empty.markets, {})
end)

H.test("sanitize keeps the first 30 tracked recipes", function()
    local H2 = load().History
    local saved = { tracked = {}, markets = {} }
    for id = 1, 31 do saved.tracked[id] = { recipe = recipe(id), active = true } end
    H2.sanitize(saved, NOW)
    H.eq(#saved.tracked, 30)
    H.eq(saved.tracked[30].recipe.recipeID, 30)
end)

-- Daily views ---------------------------------------------------------------------
-- NOW (day 500 since the epoch) is a Sunday at 00:00 UTC.
local function withDate(offset, dstFrom, dstTo)
    local H2 = load().History
    H2.setDateFn(stubClock(offset, dstFrom, dstTo))
    return H2
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x) end
    return t
end

H.test("dayOf and weekday follow the local date function", function()
    local H2 = withDate(2 * 3600)
    H.eq(H2.dayOf(NOW), NOW - 2 * 3600)          -- Sunday 02:00 local
    H.eq(H2.weekday(NOW), 7)
    H.eq(H2.weekday(NOW + DAY), 1)               -- Monday
    H2.setDateFn(stubClock(-5 * 3600))
    H.eq(H2.dayOf(NOW), NOW - DAY + 5 * 3600)    -- Saturday 19:00 local
    H.eq(H2.weekday(NOW), 6)
end)

H.test("dailySeries folds raw points per local day and keeps merged points on their date", function()
    local H2 = withDate(2 * 3600)
    local series = {
        { NOW - 20 * DAY - 2 * 3600, 300, 1, 250, 380, 4 },  -- a merged daily point
        { NOW - 3 * 3600, 100, 1, 100, 100, 1 },     -- Saturday 23:00 local
        { NOW - 3600, 200, 1, 200, 200, 1 },         -- Sunday 01:00 local
        { NOW - 1800, 300, 1, 300, 300, 2 },         -- Sunday 01:30 local, two measures
        { NOW + 60, 999, 1, 999, 999, 1 },           -- ahead of now: ignored
        "junk", { NOW - 100, math.huge, 1, 1, 1, 1 }, { NOW - 50, -3, 1, 1, 1, 1 }, { NOW - 40, 5, 1, 5, 5, 0 },
    }
    local saved = copy(series)
    local daily = H2.dailySeries(series, NOW, 30)
    H.eq(daily, {
        { day = NOW - 20 * DAY - 2 * 3600, avg = 300, low = 250, high = 380, n = 4 },
        { day = NOW - DAY - 2 * 3600, avg = 100, low = 100, high = 100, n = 1 },
        { day = NOW - 2 * 3600, avg = 267, low = 200, high = 300, n = 3 },
    })
    H.eq(series, saved)                          -- never mutated
    -- The period: 7 days is today and the 6 days before.
    H2.setDateFn(stubClock(0))
    local week = H2.dailySeries({ { NOW - 7 * DAY + 1, 5, 1, 5, 5, 1 }, { NOW - 6 * DAY, 6, 1, 6, 6, 1 } }, NOW, 7)
    H.eq(#week, 1)
    H.eq(week[1].avg, 6)
    for _, bad in ipairs({ { "x", NOW, 7 }, { series, 0 / 0, 7 }, { series, NOW, 0 }, { series, NOW, "7" } }) do
        H.eq(H2.dailySeries(bad[1], bad[2], bad[3]), {})
    end
end)

H.test("usual is the median of the daily averages of 30 days, from 3 distinct days", function()
    local H2 = withDate(0)
    -- A flat month, one measure a day, compacted as the addon keeps it.
    local month = {}
    for age = 29, 0, -1 do month[#month + 1] = { NOW - age * DAY + 3600, 100, 1, 100, 100, 1 } end
    month = H2.compact(month, NOW + 7200)
    H.eq(H2.usual(month, NOW + 7200), { price = 100, days = 30, measures = 30 })
    -- Odd and even counts, gaps, an older day left out.
    local function at(age, unit) return { NOW - age * DAY, unit, 1, unit, unit, 1 } end
    H.eq(H2.usual({ at(40, 5000), at(25, 100), at(10, 300), at(1, 200) }, NOW).price, 200)
    H.eq(H2.usual({ at(25, 100), at(10, 300), at(3, 1000), at(1, 200) }, NOW).price, 250)
    -- All prices equal: the median is that price.
    H.eq(H2.usual({ at(3, 70), at(2, 70), at(1, 70) }, NOW), { price = 70, days = 3, measures = 3 })
    -- Under 3 distinct days (several measures on one day count once).
    H.eq(H2.usual({ at(2, 100), at(1, 200), { NOW - DAY + 60, 300, 1, 300, 300, 1 } }, NOW), nil)
    H.eq(H2.usual({}, NOW), nil)
    H.eq(H2.usual("junk", NOW), nil)
    H.eq(H2.usual({ "junk", at(2, 0 / 0), at(1, -1) }, NOW), nil)
end)

H.test("compare gives a rounded percentage and a tone, never dividing by zero", function()
    local H2 = load().History
    H.eq(H2.compare(103, 100), { pct = 3, tone = "flat" })
    H.eq(H2.compare(97, 100), { pct = -3, tone = "flat" })
    H.eq(H2.compare(104, 100), { pct = 4, tone = "up" })
    H.eq(H2.compare(82, 100), { pct = -18, tone = "down" })
    H.eq(H2.compare(-50, 100), { pct = -150, tone = "down" })
    H.eq(H2.compare(100, 100), { pct = 0, tone = "flat" })
    for _, bad in ipairs({ { 100, 0 }, { 100, -5 }, { nil, 100 }, { 100, nil }, { 0 / 0, 100 }, { 100, math.huge }, { "1", 100 } }) do
        H.eq(H2.compare(bad[1], bad[2]), nil)
    end
end)

H.test("weekdayProfile shows a rising weekend and a falling Monday", function()
    local H2 = withDate(0)
    local days = {}
    for k = 27, 0, -1 do
        local day = NOW - k * DAY
        local w = H2.weekday(day)
        local avg = (w == 6 or w == 7) and 120 or (w == 1 and 80 or 100)
        days[#days + 1] = { day = day, avg = avg, low = avg, high = avg, n = 1 }
    end
    local profile = H2.weekdayProfile(days, 100)
    H.eq(#profile, 7)
    H.eq(profile[1], { pct = -20, n = 4 })       -- Monday
    H.eq(profile[2], { pct = 0, n = 4 })
    H.eq(profile[6], { pct = 20, n = 4 })        -- Saturday
    H.eq(profile[7], { pct = 20, n = 4 })        -- Sunday
    -- One day of a weekday is not enough; entries with `value` work too.
    local few = H2.weekdayProfile({ { day = NOW, value = 50 }, { day = NOW - 7 * DAY, value = 70 },
        { day = NOW - DAY, value = 10 } }, 100)
    H.eq(few[7], { pct = -40, n = 2 })
    H.eq(few[6], { n = 1 })
    H.eq(few[1], { n = 0 })
    -- No usable usual price, no data, hostile entries.
    for _, usual in ipairs({ 0, -1, 0 / 0 }) do H.eq(H2.weekdayProfile(days, usual)[1], { n = 4 }) end
    H.eq(H2.weekdayProfile(nil, 100)[3], { n = 0 })
    H.eq(H2.weekdayProfile({ "junk", { day = 0 / 0, avg = 5 }, { day = NOW, avg = "x" } }, 100)[7], { n = 0 })
end)

-- Paris-like zone (UTC+1, UTC+2 in summer). Spring forward on local day SF at 02:00 local
-- (01:00 UTC): a 23 hour day. Fall back on local day FB at 03:00 summer time (01:00 UTC):
-- a 25 hour day.
local SF, FB = NOW - 20 * DAY, NOW - 6 * DAY
local function paris() return withDate(3600, SF + 3600, FB + 3600) end

H.test("a 23 hour day (spring forward) is one day with the right weekday", function()
    local H2 = paris()
    local midnight = SF - 3600                   -- 00:00 local, winter time
    -- 01:00 local (winter), 05:00 and 11:00 local (summer time), 23:30 local.
    local times = { SF, SF + 3 * 3600, SF + 9 * 3600, SF + 21 * 3600 + 1800 }
    for _, t in ipairs(times) do
        H.eq(H2.dayOf(t), midnight)
        H.eq(H2.weekday(t), H2.weekday(midnight))
    end
    H.eq(H2.dayOf(SF + 22 * 3600), SF + 22 * 3600)  -- 00:00 local the next day
    H.eq(H2.weekday(SF + 22 * 3600), H2.weekday(midnight) % 7 + 1)
    local series = {}
    for _, t in ipairs(times) do series[#series + 1] = { t, 100, 1, 100, 100, 1 } end
    series[#series + 1] = { SF - 2 * 3600, 100, 1, 100, 100, 1 }  -- the day before, 23:00
    series[#series + 1] = { SF + 23 * 3600, 100, 1, 100, 100, 1 } -- the day after, 01:00
    local daily = H2.dailySeries(series, SF + 2 * DAY, 30)
    H.eq(#daily, 3)
    H.eq(daily[2], { day = midnight, avg = 100, low = 100, high = 100, n = 4 })
    H.eq(H2.usual(series, SF + 2 * DAY), { price = 100, days = 3, measures = 6 })
    -- Merged once older than 7 days, and compacting again changes nothing.
    local out = H2.compact(series, SF + 10 * DAY)
    H.eq(#out, 3)
    H.eq(out[2], { midnight, 100, 1, 100, 100, 4 })
    H.eq(H2.compact(out, SF + 10 * DAY), out)
end)

H.test("a 25 hour day (fall back) is one day with the right weekday", function()
    local H2 = paris()
    local midnight = FB - 7200                   -- 00:00 local, summer time
    -- 01:00 local (summer), 02:30 local twice (summer, then winter), 23:30 local (winter).
    local times = { FB - 3600, FB + 1800, FB + 5400, FB + 22 * 3600 + 1800 }
    for _, t in ipairs(times) do
        H.eq(H2.dayOf(t), midnight)
        H.eq(H2.weekday(t), H2.weekday(midnight))
    end
    H.eq(H2.dayOf(FB + 23 * 3600), FB + 23 * 3600)  -- 00:00 local the next day
    local series = {}
    for _, t in ipairs(times) do series[#series + 1] = { t, 100, 1, 100, 100, 1 } end
    local daily = H2.dailySeries(series, FB + DAY + 3600, 7)
    H.eq(#daily, 1)
    H.eq(daily[1].day, midnight)
    H.eq(daily[1].n, 4)
end)

H.test("an unusable date or time function never raises", function()
    local H2 = load().History
    local series = { { NOW - DAY, 100, 1, 100, 100, 1 }, { NOW - 3600, 50, 1, 50, 50, 1 } }
    for _, bad in ipairs({
        function() return nil end, function() error("boom") end, function() return { hour = 1 } end,
        function() return { year = 1970, month = 1, day = 1, hour = 0 / 0, min = 0, sec = 0, wday = 1 } end,
    }) do
        H2.setDateFn(bad)
        H.eq(H2.dayOf(NOW), nil)
        H.eq(H2.weekday(NOW), nil)
        H.eq(H2.dailySeries(series, NOW, 7), {})
        H.eq(H2.usual(series, NOW), nil)
        H.eq(H2.weekdayProfile({ { day = NOW, avg = 1 } }, 1)[7], { n = 0 })
    end
    H.eq(H2.dayOf(0 / 0), nil)
    -- A time function that ignores its argument (as the fake game clock does) or fails:
    -- the start comes from the clock fields.
    local dateFn = stubClock(2 * 3600)
    for _, timeFn in ipairs({ function() return 1700000000 end, function() error("boom") end, function() end }) do
        H2.setDateFn(dateFn, timeFn)
        H.eq(H2.dayOf(NOW + 5000), NOW - 2 * 3600)
    end
end)

H.test("west of UTC a scan at 20:00 stays on its local day once merged", function()
    local H2 = withDate(-8 * 3600)
    local X = NOW - 20 * DAY                     -- a UTC day; its local day starts 8 hours later
    local localStart = X + 8 * 3600
    -- 10:00 and 20:00 local on the same local day: two different UTC days.
    local series = { { localStart + 10 * 3600, 100, 1, 100, 100, 1 }, { localStart + 20 * 3600, 300, 1, 300, 300, 1 } }
    local out = H2.compact(series, NOW)
    H.eq(out, { { localStart, 200, 1, 100, 300, 2 } })
    H.eq(H2.compact(out, NOW), out)
    local daily = H2.dailySeries(out, NOW, 30)
    H.eq(daily, { { day = localStart, avg = 200, low = 100, high = 300, n = 2 } })
    H.eq(H2.weekday(daily[1].day), H2.weekday(localStart + 20 * 3600))
end)

H.test("old daily points dated at UTC midnight load once onto a local day, then stay", function()
    -- Saved by the earlier compaction, which dated a daily point at the start of its UTC day.
    local old = { { NOW - 20 * DAY, 300, 1, 250, 380, 5 }, { NOW - 19 * DAY, 310, 1, 300, 320, 2 } }
    -- East of UTC (UTC+2) midnight UTC is 02:00 local: the same date.
    local east = withDate(2 * 3600)
    local saved = { tracked = {}, markets = { k = { prices = {}, series = { [7] = old } } } }
    east.sanitize(saved, NOW)
    H.eq(saved.markets.k.series[7], { { NOW - 20 * DAY - 7200, 300, 1, 250, 380, 5 }, { NOW - 19 * DAY - 7200, 310, 1, 300, 320, 2 } })
    -- West of UTC (UTC-8) it is 16:00 the day before: each point moves to that date, once.
    local west = withDate(-8 * 3600)
    local out = west.compact(old, NOW)
    H.eq(out, { { NOW - 21 * DAY + 8 * 3600, 300, 1, 250, 380, 5 }, { NOW - 20 * DAY + 8 * 3600, 310, 1, 300, 320, 2 } })
    H.eq(west.compact(out, NOW), out)
    H.eq(west.dailySeries(out, NOW, 30)[1], { day = NOW - 21 * DAY + 8 * 3600, avg = 300, low = 250, high = 380, n = 5 })
end)

H.test("volumeSeries gives the last complete volume of each day and whether all were complete", function()
    local H2 = withDate(0)
    local series = {
        { NOW - 2 * DAY + 3600, 100, 50, 100, 100, 1, true },
        { NOW - 2 * DAY + 7200, 100, 40, 100, 100, 1, true },
        { NOW - DAY + 3600, 100, 30, 100, 100, 1, true },
        { NOW - DAY + 7200, 100, 999, 100, 100, 1 },             -- partial: not the day's volume
        { NOW + 3600, 100, 12, 100, 100, 1 },                     -- only partial today
        { NOW + 7300, 100, 1, 100, 100, 1, true },                -- ahead of now: ignored
        { NOW - 20 * DAY, 100, 25, 100, 100, 4, true },           -- a merged complete day
        "junk", { NOW - 100, math.huge, 1, 1, 1, 1, true },
    }
    local saved = copy(series)
    H.eq(H2.volumeSeries(series, NOW + 7200, 30), {
        { day = NOW - 20 * DAY, volume = 25, full = true },
        { day = NOW - 2 * DAY, volume = 40, full = true },
        { day = NOW - DAY, volume = 30, full = false },
        { day = NOW, volume = nil, full = false },
    })
    H.eq(series, saved)
    H.eq(#H2.volumeSeries(series, NOW + 7200, 2), 2)
    H.eq(H2.volumeSeries("x", NOW, 7), {})
    H.eq(H2.volumeSeries(series, 0 / 0, 7), {})
    H.eq(H2.volumeSeries(series, NOW, 0), {})
end)
