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
    for id = 2, H2.MAX_TRACKED do H.truthy(H2.track(db, recipe(id))) end
    H.eq({ H2.track(db, recipe(999)) }, { false, "full" })
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
    -- sanitize drops it too, while a point less than a day ahead is kept (clock drift).
    local saved = { tracked = {}, markets = { k = { prices = {}, series = {
        [5] = { { NOW - DAY, 3, 1, 3, 3, 1 }, { NOW + 2 * DAY, 9, 1, 9, 9, 1 } },
        [6] = { { NOW + 3600, 4, 1, 4, 4, 1 } },
    } } } }
    H2.sanitize(saved, NOW)
    H.eq(saved.markets.k.series[5], { { NOW - DAY, 3, 1, 3, 3, 1 } })
    H.eq(saved.markets.k.series[6], { { NOW + 3600, 4, 1, 4, 4, 1 } })
end)

H.test("a recipe blocked by a near future point is not counted as recorded", function()
    local H2, db = load().History, newDB()
    H2.track(db, recipe(1))
    local m = market({ [1] = { 100, 5, NOW }, [2] = { 50, 3, NOW }, [100] = { 1000, 2, NOW } })
    for _, id in ipairs({ 1, 2, 100 }) do m.series[id] = { { NOW + 60, 7, 1, 7, 7, 1 } } end
    H.eq(H2.record(db, m, NOW, { [1] = true }, itemsOf), 0)
    H.eq(#m.series[1], 1)
end)

-- One point a day for a year, as a quiet user leaves it.
local function yearOfDays(H2)
    local series = {}
    for age = 364, 1, -1 do series[#series + 1] = { NOW - age * DAY, 100, 1, 100, 100, 1 } end
    -- Twice: a first pass can date a weekly point (its week's start) over a year back,
    -- and the next pass drops it, as the daily records of a real year did.
    return H2.compact(H2.compact(series, NOW), NOW)
end

local function tiers(H2, series, now)
    local raw, daily, weekly = 0, 0, 0
    for _, p in ipairs(series) do
        local age = (now or NOW) - p[1]
        if age > H2.DAILY_SECONDS then weekly = weekly + 1
        elseif age > H2.RAW_SECONDS then daily = daily + 1
        else raw = raw + 1 end
    end
    return raw, daily, weekly
end

H.test("a busy fortnight never evicts the daily and weekly tiers", function()
    local H2 = load().History
    local year = yearOfDays(H2)
    local _, daily, weekly = tiers(H2, year)
    H.truthy(daily > 70)
    H.truthy(weekly > 35)
    -- 50 operations a day for the last 14 days.
    local series = {}
    for _, p in ipairs(year) do series[#series + 1] = p end
    for i = 1, 14 * 50 do series[#series + 1] = { NOW - 14 * DAY + i * 1700, 200, 1, 200, 200, 1 } end
    local out = H2.compact(series, NOW)
    local raw, daily2, weekly2 = tiers(H2, out)
    H.eq(raw, H2.MAX_RAW)
    H.eq(daily2, daily)
    H.eq(weekly2, weekly)
    H.eq(out[1], year[1])                       -- the oldest point survives
    H.eq(out[#out][1], NOW - 14 * DAY + 14 * 50 * 1700)  -- the newest raw point too
    H.eq(H2.compact(out, NOW), out)             -- still idempotent
end)

H.test("every save the old 600 point cap kept loads unchanged", function()
    local H2 = load().History
    -- 600 raw points and nothing older: the most raw points the old cap allowed.
    local raw = {}
    for i = 1, 600 do raw[i] = { NOW - 13 * DAY + i * 60, 100, 1, 100, 100, 1 } end
    H.eq(H2.compact(raw, NOW), raw)
    -- A full year (daily and weekly tiers at their largest) plus raw points up to 600 in all.
    local year = yearOfDays(H2)
    local series = {}
    for _, p in ipairs(year) do
        if NOW - p[1] > H2.RAW_SECONDS then series[#series + 1] = p end
    end
    for i = 1, 600 - #series do series[#series + 1] = { NOW - 13 * DAY + i * 60, 100, 1, 100, 100, 1 } end
    H.eq(#series, 600)
    H.eq(H2.compact(series, NOW), series)
end)

H.test("the tier caps hold above the most points each tier can ever hold", function()
    local H2 = load().History
    -- One point every hour for a year: each daily and weekly bucket is filled.
    local series = {}
    for age = 365 * 24, 1, -1 do series[#series + 1] = { NOW - age * 3600, 100, 1, 100, 100, 1 } end
    local out = H2.compact(series, NOW)
    local raw, daily, weekly = tiers(H2, out)
    H.eq(raw, 14 * 24)
    H.truthy(daily >= 76 and daily <= H2.MAX_DAILY)
    H.truthy(weekly >= 39 and weekly <= H2.MAX_WEEKLY)
    -- At any time of the day or week the daily and weekly caps never bind: lifting them
    -- changes nothing.
    for _, shift in ipairs({ 0, 43210, 3 * DAY + 43210, 5 * DAY + 1 }) do
        local capped = H2.compact(series, NOW + shift)
        local maxDaily, maxWeekly = H2.MAX_DAILY, H2.MAX_WEEKLY
        H2.MAX_DAILY, H2.MAX_WEEKLY = 1e9, 1e9
        local free = H2.compact(series, NOW + shift)
        H2.MAX_DAILY, H2.MAX_WEEKLY = maxDaily, maxWeekly
        H.eq(capped, free)
    end
    -- Each cap applies to its own tier and keeps its newest points.
    local caps = { H2.MAX_RAW, H2.MAX_DAILY, H2.MAX_WEEKLY }
    H2.MAX_RAW, H2.MAX_DAILY, H2.MAX_WEEKLY = 3, 3, 3
    out = H2.compact(series, NOW)
    H2.MAX_RAW, H2.MAX_DAILY, H2.MAX_WEEKLY = caps[1], caps[2], caps[3]
    H.eq(#out, 9)
    H.eq(out[9], series[#series])
    H.eq(out[1][6], 7 * 24)                     -- a full week, not the oldest partial one
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

H.test("old points are merged by day then by week, keeping low, high and count", function()
    local H2 = load().History
    local series = {}
    local function add(age, unit) series[#series + 1] = { NOW - age, unit, 10, unit, unit, 1 } end
    add(1 * DAY, 100)                         -- raw
    add(20 * DAY + 100, 100)                  -- same day as the next one
    add(20 * DAY + 5000, 300)
    add(120 * DAY + 100, 50)                  -- same week as the next
    add(120 * DAY + 90000, 150)
    add(400 * DAY, 77)                        -- too old: dropped
    local out = H2.compact(series, NOW)
    H.eq(#out, 3)
    H.eq(out[1][6], 2)                        -- the two weekly points were merged
    H.eq(out[1][2], 100)
    H.eq(out[1][4], 50)
    H.eq(out[1][5], 150)
    H.eq(out[2][2], 200)                      -- daily average of 100 and 300
    H.eq(out[2][4], 100)
    H.eq(out[2][5], 300)
    H.eq(out[3], { NOW - 1 * DAY, 100, 10, 100, 100, 1 })
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
