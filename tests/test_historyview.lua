local H = ...

local DAY = 86400
-- Day 500 since the epoch: a Sunday at 00:00 UTC. The local date is stubbed at UTC.
local NOW = 500 * DAY
local CUT = 0.05

local stubClock = dofile("tests/stubclock.lua")

local function load()
    local ns = H.newNS("Util", "Core", "Data/Skillup", "Data/Disenchant", "Recipes", "History", "Evaluate",
        "HistoryView")
    ns.History.setDateFn(stubClock(0))
    return ns
end

local RECIPE = {
    recipeID = 1, name = "Sword", difficulty = 1, outputItemID = 100, outputQty = 3,
    reagents = { { itemID = 1, qty = 2 }, { itemID = 2, qty = 1 } },
}

local function itemsOf(r)
    return { 1, 2, r.outputItemID, 200 }, { 1, 2, r.outputItemID }
end

-- The crafted item is bound on pickup: never required, never sold.
local function itemsOfBound()
    return { 1, 2, 100 }, { 1, 2 }
end

-- A raw point `age` days (plus `extra` seconds) before NOW.
local function pt(age, unit, extra)
    return { NOW - age * DAY + (extra or 3600), unit, 1, unit, unit, 1 }
end

local function seriesOf(map)
    return function(id) return map[id] end
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x) end
    return t
end

local function sale(unit) return math.floor(unit * 3 * (1 - CUT) + 0.5) end

H.test("recipeDays gives materials, sale after commission and net for each measured day", function()
    local V = load().HistoryView
    local map = {
        [1] = { pt(2, 100), pt(1, 110) },
        [2] = { pt(2, 50), pt(1, 40) },
        [100] = { pt(2, 1013), pt(1, 1100) },
    }
    local days = V.recipeDays(RECIPE, seriesOf(map), NOW, 7, CUT, itemsOf)
    H.eq(days, {
        { day = NOW - 2 * DAY, materials = 250, sale = sale(1013), net = sale(1013) - 250, carried = false, n = 1 },
        { day = NOW - DAY, materials = 260, sale = sale(1100), net = sale(1100) - 260, carried = false, n = 1 },
    })
end)

H.test("the net result equals Evaluate's for the same prices", function()
    local ns = load()
    local prices = { [1] = 137, [2] = 41, [100] = 1013 }
    local map = {}
    for id, unit in pairs(prices) do map[id] = { pt(0, unit, 60) } end
    local day = ns.HistoryView.recipeDays(RECIPE, seriesOf(map), NOW + 120, 1, CUT, itemsOf)[1]
    local r = ns.Evaluate.run({
        recipe = RECIPE, cut = CUT, showPerPoint = false,
        priceOf = function(id) return prices[id], 0 end,
        itemInfo = function() return { quality = 2, ilvl = 15, sellPrice = 1, classID = 2, bindType = 2 } end,
        lookupDisenchant = function() return { { itemID = 200, chance = 1, min = 1, max = 1 } } end,
    })
    H.eq(r.best, "ah")
    H.eq(day.materials, r.cost.total)
    H.eq(day.sale, r.options.ah.value)
    H.eq(day.net, r.net)
end)

H.test("a missing day carries the last known price and says so", function()
    local V = load().HistoryView
    local map = {
        [1] = { pt(3, 100), pt(2, 120), pt(1, 130) },
        [2] = { pt(3, 50), pt(1, 60) },             -- nothing two days back
        [100] = { pt(3, 1000) },                    -- only three days back
    }
    local days = V.recipeDays(RECIPE, seriesOf(map), NOW, 7, CUT, itemsOf)
    H.eq(#days, 3)
    H.eq(days[1].carried, false)
    H.eq(days[2], { day = NOW - 2 * DAY, materials = 290, sale = sale(1000), net = sale(1000) - 290,
        carried = true, n = 1 })
    H.eq(days[3].carried, true)
    H.eq(days[3].sale, sale(1000))
    -- A price from before the period is carried into it.
    local old = { [1] = { pt(10, 100), pt(1, 100) }, [2] = { pt(10, 50) }, [100] = { pt(1, 1000) } }
    local week = V.recipeDays(RECIPE, seriesOf(old), NOW, 7, CUT, itemsOf)
    H.eq(#week, 1)
    H.eq(week[1].materials, 250)
    H.eq(week[1].carried, true)
end)

H.test("no price is invented before an item's first point", function()
    local V = load().HistoryView
    local map = {
        [1] = { pt(3, 100), pt(1, 100) },
        [2] = { pt(2, 50) },                        -- first seen two days back
        [100] = { pt(1, 1000) },                    -- first seen yesterday
    }
    local days = V.recipeDays(RECIPE, seriesOf(map), NOW, 7, CUT, itemsOf)
    H.eq(days[1], { day = NOW - 3 * DAY, carried = false, n = 1 })  -- incomplete: no result
    H.eq(days[2], { day = NOW - 2 * DAY, materials = 250, carried = true, n = 1 })
    H.eq(days[3].net, sale(1000) - 250)
end)

H.test("a bound crafted item gives the materials only", function()
    local V = load().HistoryView
    local map = { [1] = { pt(1, 100) }, [2] = { pt(1, 50) }, [100] = { pt(1, 1000) } }
    local days = V.recipeDays(RECIPE, seriesOf(map), NOW, 7, CUT, itemsOfBound)
    H.eq(days, { { day = NOW - DAY, materials = 250, carried = false, n = 1 } })
end)

H.test("recipeDays never mutates the saved series and survives hostile input", function()
    local V = load().HistoryView
    local map = {
        [1] = { pt(2, 100), "junk", { NOW, 0 / 0, 1, 1, 1, 1 } },
        [2] = "junk",
        [100] = { pt(2, 1000), pt(1, 1000) },
    }
    local saved = { [1] = copy(map[1]), [100] = copy(map[100]) }
    saved[1][3] = nil
    local days = V.recipeDays(RECIPE, seriesOf(map), NOW, 7, CUT, itemsOf)
    H.eq(#days, 2)
    H.eq(days[1].materials, nil)
    H.eq(days[2].sale, sale(1000))
    H.eq(map[100], saved[100])
    H.eq(map[1][1], saved[1][1])
    H.eq(#map[1], 3)
    H.eq(V.recipeDays(nil, seriesOf(map), NOW, 7, CUT, itemsOf), {})
    H.eq(V.recipeDays(RECIPE, seriesOf(map), 0 / 0, 7, CUT, itemsOf), {})
    H.eq(V.recipeDays(RECIPE, seriesOf(map), NOW, 0, CUT, itemsOf), {})
    H.eq(V.recipeDays(RECIPE, nil, NOW, 7, CUT, itemsOf), {})
    H.eq(V.recipeDays(RECIPE, seriesOf({}), NOW, 7, CUT, itemsOf), {})
end)

H.test("summary gives today, usual, range, measures and days covered", function()
    local ns = load()
    local V = ns.HistoryView
    local days = {}
    for k, net in ipairs({ 100, 300, 200, 250 }) do
        days[k] = { day = NOW - (4 - k) * DAY, net = net, materials = 10, n = 2, carried = k == 2 }
    end
    H.eq(V.summary(days, "net"), { today = 250, usual = 225, low = 100, high = 300, measures = 8,
        daysCovered = 4, enough = true })
    -- All equal: a range of 0.
    H.eq(V.summary(days, "materials"), { today = 10, usual = 10, low = 10, high = 10, measures = 8,
        daysCovered = 4, enough = true })
    -- Fewer than 3 days: no usual price.
    H.eq(V.summary({ days[1], days[2] }, "net"), { today = 300, low = 100, high = 300, measures = 4,
        daysCovered = 2, enough = false })
    -- Days without a value are not counted; the usual covers the last 30 days only.
    local old = { { day = NOW - 40 * DAY, net = 9000, n = 1 }, { day = NOW - 3 * DAY, n = 1 } }
    for _, d in ipairs(days) do old[#old + 1] = d end
    H.eq(V.summary(old, "net").usual, 225)
    H.eq(V.summary(old, "net").daysCovered, 5)
    H.eq(V.summary(old, "net").high, 9000)
    -- An item's daily series: avg, low and high come from the entries.
    local item = ns.History.dailySeries({ pt(3, 100), pt(2, 120), { NOW - DAY, 90, 1, 80, 95, 3 } }, NOW, 30)
    H.eq(V.summary(item), { today = 90, usual = 100, low = 80, high = 120, measures = 5,
        daysCovered = 3, enough = true })
    H.eq(V.summary({}), { measures = 0, daysCovered = 0, enough = false })
    H.eq(V.summary(nil, "net"), { measures = 0, daysCovered = 0, enough = false })
end)

H.test("indicators say whether materials are cheaper and the sale higher than usual", function()
    local V = load().HistoryView
    local map = { [1] = {}, [2] = {}, [100] = {} }
    for age = 10, 2, -1 do
        map[1][#map[1] + 1] = pt(age, 100)
        map[2][#map[2] + 1] = pt(age, 50)
        map[100][#map[100] + 1] = pt(age, 1000)
    end
    -- Today: materials 18 % cheaper is good, sale 12 % higher is good.
    map[1][#map[1] + 1] = pt(0, 80, 60)
    map[2][#map[2] + 1] = pt(0, 45, 60)
    map[100][#map[100] + 1] = pt(0, 1120, 60)
    local ind = V.indicators(RECIPE, seriesOf(map), NOW + 120, itemsOf, CUT)
    H.eq(ind.materials, { pct = -18, tone = "down", good = true })
    H.eq(ind.sale, { pct = 12, tone = "up", good = true })
    -- The opposite is bad; within 3 % is neutral.
    map[1][#map[1]] = pt(0, 130, 60)
    map[100][#map[100]] = pt(0, 1020, 60)
    ind = V.indicators(RECIPE, seriesOf(map), NOW + 120, itemsOf, CUT)
    H.eq(ind.materials, { pct = 22, tone = "up", good = false })
    H.eq(ind.sale.tone, "flat")
    H.eq(ind.sale.good, nil)
    -- A bound crafted item has no sale arrow; too little data has none at all.
    H.eq(V.indicators(RECIPE, seriesOf(map), NOW + 120, itemsOfBound, CUT).sale, nil)
    local few = { [1] = { pt(1, 100), pt(0, 90, 60) }, [2] = { pt(1, 50) }, [100] = { pt(1, 1000) } }
    H.eq(V.indicators(RECIPE, seriesOf(few), NOW + 120, itemsOf, CUT), {})
end)
