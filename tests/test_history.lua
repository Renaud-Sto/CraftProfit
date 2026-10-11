local H = ...

local function load()
    return H.newNS("Util", "Data/Skillup", "Recipes", "History")
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
