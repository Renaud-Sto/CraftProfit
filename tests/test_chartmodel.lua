local H = ...

local function load()
    return H.newNS("Util", "ChartModel").ChartModel
end

local DAY = 86400
local NOW = 500 * DAY
local NAN, INF = 0 / 0, math.huge

local function isTick(scale, v)
    for _, t in ipairs(scale.ticks) do
        if t == v then return true end
    end
    return false
end

-- Every scale: max above min, ticks from min to max by step, all whole copper.
local function wellFormed(s)
    H.truthy(s.max > s.min)
    H.truthy(s.step >= 1)
    H.eq(s.ticks[1], s.min)
    H.eq(s.ticks[#s.ticks], s.max)
    for i = 2, #s.ticks do H.eq(s.ticks[i] - s.ticks[i - 1], s.step) end
    for _, t in ipairs(s.ticks) do H.eq(t, math.floor(t)) end
    local m = s.step / 10 ^ math.floor(math.log10(s.step) + 1e-9)
    H.truthy(m == 1 or m == 2 or m == 5)
end

H.test("scale gives readable steps around the range", function()
    local C = load()
    local s = C.scale(12000, 18000, 4)
    wellFormed(s)
    H.truthy(s.min <= 12000 and s.max >= 18000)
    H.truthy(#s.ticks >= 3 and #s.ticks <= 7)
    -- Prices never get a negative axis.
    local p = C.scale(100, 5000, 4)
    wellFormed(p)
    H.truthy(p.min >= 0)
end)

H.test("a range of 0 is padded, never a zero divisor", function()
    local C = load()
    for _, v in ipairs({ 0, 1, 5000, -2500, 1e9 }) do
        local s = C.scale(v, v, 4)
        wellFormed(s)
        H.truthy(s.min < v + 1 and s.max > v - 1)
        H.truthy(s.min <= v and s.max >= v)
    end
end)

H.test("a loss crossing zero shows a zero tick", function()
    local C = load()
    local s = C.scale(-3500, 12000, 4)
    wellFormed(s)
    H.truthy(s.min <= -3500 and s.max >= 12000)
    H.truthy(isTick(s, 0))
    local loss = C.scale(-9000, -1000, 4)
    wellFormed(loss)
    H.truthy(loss.max >= -1000 and loss.min <= -9000)
end)

H.test("huge amounts and hostile bounds still give a scale", function()
    local C = load()
    local s = C.scale(2e8, 1e9, 4)
    wellFormed(s)
    H.truthy(s.max >= 1e9 and #s.ticks <= 7)
    wellFormed(C.scale(5000, 100, 4))                -- swapped bounds
    wellFormed(C.scale(NAN, 100, 4))
    wellFormed(C.scale(100, INF, 4))
    wellFormed(C.scale(NAN, NAN, 4))
    wellFormed(C.scale(nil, nil))
    wellFormed(C.scale(0, 1, 0))
    H.truthy(C.scale(NAN, 100, 4).max >= 100)
end)

H.test("priceLabel is plain text gold, silver and copper", function()
    local C = load()
    H.eq(C.priceLabel(124000), "12g 40s")
    H.eq(C.priceLabel(120000), "12g")
    H.eq(C.priceLabel(4000), "40s")
    H.eq(C.priceLabel(4005), "40s 5c")
    H.eq(C.priceLabel(5), "5c")
    H.eq(C.priceLabel(0), "0c")
    H.eq(C.priceLabel(-31000), "-3g 10s")
    H.eq(C.priceLabel(12000000), "1.2k g")
    H.eq(C.priceLabel(10000000), "1k g")
    H.eq(C.priceLabel(1e9), "100k g")
    -- Thousands of gold round down to one decimal; millions from 1M gold, so the largest
    -- amount the addon keeps (1e13 copper, 1e9 gold) stays short.
    H.eq(C.priceLabel(12990000), "1.2k g")
    H.eq(C.priceLabel(9999990000), "999k g")
    H.eq(C.priceLabel(10000000000), "1M g")
    H.eq(C.priceLabel(123400000000), "12.3M g")
    H.eq(C.priceLabel(1e13), "1000M g")
    H.eq(C.priceLabel(1e300), "1000M g")
    H.eq(C.priceLabel(-1e300), "-1000M g")
    H.eq(C.priceLabel(124000.4), "12g 40s")
    H.eq(C.priceLabel(NAN), "?")
    H.eq(C.priceLabel(INF), "?")
    H.eq(C.priceLabel("x"), "?")
    H.falsy(C.priceLabel(124000):find("|", 1, true))   -- never an icon or escape
end)

H.test("slots number the days of a period ending at the newest day", function()
    local C = load()
    local s = C.slots(7)
    H.eq(s.count, 7)
    H.eq(s.index(NOW, NOW), 7)
    H.eq(s.index(NOW - 6 * DAY, NOW), 1)
    H.eq(s.index(NOW - 7 * DAY, NOW), nil)          -- before the period
    H.eq(s.index(NOW + DAY, NOW), nil)
    -- A day of 23 or 25 hours (daylight saving) still counts as one day.
    H.eq(s.index(NOW - 3 * DAY + 3600, NOW), 4)
    H.eq(s.index(NOW - 3 * DAY - 3600, NOW), 4)
    H.eq(C.slots(30).count, 30)
    H.eq(C.slots(60).count, 60)
    H.eq(C.slots(0), nil)
    H.eq(C.slots(NAN), nil)
    H.eq(C.slots(1000), nil)
end)

local SCALE = { min = 0, max = 400, step = 100, ticks = { 0, 100, 200, 300, 400 } }

H.test("bars place each day in its slot, keep gaps, and tint carried days", function()
    local C = load()
    local days = {
        { day = NOW - 6 * DAY, net = 100, carried = false },
        { day = NOW - 4 * DAY, net = 200, carried = true, netCarried = "some" },  -- day 2 and 4 missing: gaps
        { day = NOW - 3 * DAY, net = NAN },                                         -- no value: skipped
        { day = NOW, net = 300 },
    }
    local bars = C.bars(days, SCALE, 700, 400, "net", 7)
    H.eq(#bars, 3)
    H.eq(bars[1].slot, 1)
    H.eq(bars[2].slot, 3)
    H.eq(bars[3].slot, 7)
    H.eq(bars[1].x + bars[1].w / 2, 50)            -- slot 1 of 7 in 700 px: centre 50
    H.eq(bars[3].x + bars[3].w / 2, 650)
    H.truthy(bars[1].w > 0 and bars[1].w < 100)
    H.eq(bars[1].yAvg, 300)                         -- 100 on a 0..400 scale, 400 px, y from the top
    H.eq(bars[3].yAvg, 100)
    -- A recipe value has no range: low = high = avg.
    H.eq(bars[1].yLow, 300)
    H.eq(bars[1].yHigh, 300)
    H.eq(bars[1].carried, false)
    H.eq(bars[2].carried, true)
end)

H.test("bars of an item series span low to high with a tick at the average", function()
    local C = load()
    local days = {
        { day = NOW - DAY, avg = 200, low = 100, high = 300, n = 3 },
        { day = NOW, avg = 250, low = 250, high = 250, n = 1 },
        { day = NOW - 2 * DAY, avg = INF, low = 1, high = 2, n = 1 },               -- hostile: skipped
        "junk",
    }
    local bars = C.bars(days, SCALE, 300, 400, nil, 3)
    H.eq(#bars, 2)
    H.eq(bars[1].yHigh, 100)
    H.eq(bars[1].yLow, 300)
    H.eq(bars[1].yAvg, 200)
    H.eq(bars[2].slot, 3)
    -- Out of the scale: clamped into the area.
    local clamped = C.bars({ { day = NOW, avg = 900, low = -50, high = 900 } }, SCALE, 300, 400, nil, 3)
    H.eq(clamped[1].yHigh, 0)
    H.eq(clamped[1].yLow, 400)
end)

H.test("bars ignore what cannot be drawn", function()
    local C = load()
    H.eq(C.bars({}, SCALE, 300, 400, "net", 7), {})
    H.eq(C.bars(nil, SCALE, 300, 400, "net", 7), {})
    H.eq(C.bars({ { day = NOW, net = 1 } }, nil, 300, 400, "net", 7), {})
    H.eq(C.bars({ { day = NOW, net = 1 } }, { min = 5, max = 5, step = 1, ticks = { 5 } }, 300, 400, "net", 7), {})
    H.eq(C.bars({ { day = NOW, net = 1 } }, SCALE, 0, 400, "net", 7), {})
    H.eq(C.bars({ { day = NOW, net = 1 } }, SCALE, 300, NAN, "net", 7), {})
    H.eq(C.bars({ { day = NOW, net = 1 } }, SCALE, 300, 400, "net", 0), {})
    -- One day.
    local one = C.bars({ { day = NOW, net = 200 } }, SCALE, 300, 400, "net", 30)
    H.eq(#one, 1)
    H.eq(one[1].slot, 30)
    H.eq(one[1].yAvg, 200)
end)

H.test("extent gives the drawn range of a field", function()
    local C = load()
    H.eq({ C.extent({ { day = 1, net = -50 }, { day = 2, net = 300 }, { day = 3, net = NAN } }, "net") }, { -50, 300 })
    H.eq({ C.extent({ { day = 1, avg = 20, low = 10, high = 40 } }) }, { 10, 40 })
    H.eq(C.extent({}, "net"), nil)
    H.eq(C.extent(nil), nil)
end)

H.test("the usual price line is clamped to the area with an indicator", function()
    local C = load()
    H.eq(C.usualY(100, SCALE, 400), { y = 300 })
    H.eq(C.usualY(900, SCALE, 400), { y = 0, outside = "above" })
    H.eq(C.usualY(-10, SCALE, 400), { y = 400, outside = "below" })
    H.eq(C.usualY(nil, SCALE, 400), nil)
    H.eq(C.usualY(NAN, SCALE, 400), nil)
    H.eq(C.usualY(100, nil, 400), nil)
end)

H.test("the weekday strip starts on Monday, around a zero line, symmetric", function()
    local C = load()
    local profile = {
        { pct = -20, n = 4 }, { pct = 0, n = 4 }, { pct = 5, n = 4 }, { n = 1 },
        { pct = 0, n = 4 }, { pct = 20, n = 4 }, { pct = 20, n = 4 },
    }
    local bars = C.weekdayBars(profile, 700, 100)
    H.eq(#bars, 7)
    H.eq(bars.limit, 20)
    -- Monday: 20 % below, a bar down from the zero line to the bottom.
    H.eq(bars[1].y, 50)
    H.eq(bars[1].h, 50)
    H.eq(bars[1].pct, -20)
    H.eq(bars[1].x + bars[1].w / 2, 50)
    -- Saturday: 20 % above, up to the top.
    H.eq(bars[6].y, 0)
    H.eq(bars[6].h, 50)
    -- Thursday has 1 day: empty.
    H.eq(bars[4].empty, true)
    H.eq(bars[4].h, 0)
    H.eq(bars[4].n, 1)
    H.eq(bars[2].h, 0)
    H.eq(bars[2].empty, false)
    -- A quiet week: the scale stays at least +-10 %.
    local quiet = C.weekdayBars({ { pct = 2, n = 2 }, { pct = -1, n = 2 } }, 700, 100)
    H.eq(quiet.limit, 10)
    H.eq(quiet[1].h, 10)
    H.eq(quiet[3].empty, true)
    -- Hostile input: 7 empty bars.
    for _, bad in ipairs({ nil, "x", { { pct = NAN, n = 3 }, { pct = INF, n = 3 } } }) do
        local out = C.weekdayBars(bad, 700, 100)
        H.eq(#out, 7)
        H.eq(out[1].empty, true)
        H.eq(out.limit, 10)
    end
    H.eq(C.weekdayBars(profile, 0, 100), {})
end)

H.test("hostile steps and bounds can never make a long tick list", function()
    local C = load()
    for _, args in ipairs({ { 0, 1e6, 1e9 }, { -1e308, 1e308, 4 }, { 1e308, 1e308, 4 }, { -1e308, 5, 1e9 },
        { 0, 100, -3 }, { 0, 100, 1 } }) do
        local s = C.scale(args[1], args[2], args[3])
        wellFormed(s)
        H.truthy(#s.ticks <= 23)
        H.truthy(s.min >= -1e13 - s.step and s.max <= 1e13 + s.step)
    end
    H.truthy(#C.scale(0, 1e6, 1e9).ticks <= 21)     -- at most 20 intervals
    H.truthy(#C.scale(0, 1e6, 1).ticks >= 3)        -- at least 2
end)
