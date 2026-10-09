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
    -- same instant twice: no duplicate point
    H.eq(H2.record(db, m, NOW, { [1] = true }, itemsOf), 1)
    H.eq(#m.series[1], 1)
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
