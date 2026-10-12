local H = ...
local W = dofile("tests/fakewow.lua")

local DAY = 86400
local NOW = 500 * DAY
local NAN, INF = 0 / 0, math.huge

-- The fake game with every frame, texture, font string and line recorded.
local function boot()
    local T = W.boot(H)
    local made = { frames = {}, textures = 0, fonts = 0 }
    local function track(f)
        local createTexture, createFont = f.CreateTexture, f.CreateFontString
        f.CreateTexture = function(self, ...)
            made.textures = made.textures + 1
            local t = createTexture(self, ...)
            t.shown = true
            return t
        end
        f.CreateFontString = function(self, ...)
            made.fonts = made.fonts + 1
            local fs = createFont(self, ...)
            fs.shown = true
            fs.font = select(3, ...)
            return fs
        end
        return f
    end
    local create = T.env.CreateFrame
    T.env.CreateFrame = function(kind, name, parent, template)
        local f = track(create(kind, name, parent, template))
        f.shown = true
        f.kind = kind
        made.frames[#made.frames + 1] = f
        return f
    end
    return T, T.ns.Chart, made
end

local function netDays(count, value)
    local days = {}
    for k = count - 1, 0, -1 do
        days[#days + 1] = { day = NOW - k * DAY, net = value or (1000 + k * 10), carried = false }
    end
    return days
end

local function shownCount(list)
    local n = 0
    for _, x in ipairs(list) do
        if x.shown then n = n + 1 end
    end
    return n
end

H.test("the chart is loaded after the native kit and draws no Line by default", function()
    local T, Chart = boot()
    H.truthy(Chart)
    H.eq(Chart.USE_LINES, false)
    H.truthy(T.ns.ChartModel)
end)

H.test("bars come from a pool: 60 days then 7 reuse the textures and hide the rest", function()
    local T, Chart, made = boot()
    local chart = Chart.new(T.env.UIParent, 600, 300)
    chart:set({ days = netDays(60), field = "net", period = 60 })
    H.eq(#chart.pools.bars, 60)
    H.eq(shownCount(chart.pools.bars), 60)
    local textures = made.textures
    chart:set({ days = netDays(7), field = "net", period = 7 })
    H.eq(#chart.pools.bars, 60)
    H.eq(shownCount(chart.pools.bars), 7)
    -- No texture or font string is created on a redraw that needs no more than before.
    chart:set({ days = netDays(60), field = "net", period = 60 })
    H.eq(made.textures, textures)
    H.eq(shownCount(chart.pools.bars), 60)
end)

H.test("clear and a nil model hide everything", function()
    local T, Chart = boot()
    local chart = Chart.new(T.env.UIParent, 600, 300)
    chart:set({ days = netDays(10), field = "net", period = 30, usual = 1050 })
    chart:clear()
    H.eq(shownCount(chart.pools.bars), 0)
    H.eq(shownCount(chart.pools.labels), 0)
    H.eq(shownCount(chart.pools.slots), 0)
    H.eq(chart.usualLine.shown, false)
    chart:set({ days = netDays(10), field = "net", period = 30 })
    chart:set(nil)
    H.eq(shownCount(chart.pools.bars), 0)
end)

H.test("empty and hostile models never raise and draw nothing", function()
    local T, Chart = boot()
    local chart = Chart.new(T.env.UIParent, 600, 300)
    for _, model in ipairs({
        {}, { days = "x" }, { days = {} }, { days = { { day = NAN, net = 1 }, { day = NOW, net = INF } }, field = "net" },
        { days = netDays(5), field = "net", period = 0 }, { days = netDays(5), field = "net", period = NAN },
        { days = netDays(5), field = "net", scale = { min = 5, max = 5 } }, { days = netDays(5), field = "nope" },
        "junk", 42,
    }) do
        chart:set(model)
        H.eq(shownCount(chart.pools.bars), 0)
    end
    chart:setWeekday(nil)
    chart:setWeekday({ { pct = NAN, n = 2 } })
    -- A hostile size is replaced by a usable one.
    local small = Chart.new(T.env.UIParent, NAN, -5)
    small:set({ days = netDays(3), field = "net", period = 7 })
    H.eq(shownCount(small.pools.bars), 3)
end)

H.test("one axis label per tick, plain text, in the game's small font", function()
    local T, Chart = boot()
    local chart = Chart.new(T.env.UIParent, 600, 300)
    chart:set({ days = { { day = NOW - DAY, net = -3500 }, { day = NOW, net = 12000 } }, field = "net", period = 7 })
    local scale = chart.scale
    H.eq(shownCount(chart.pools.labels), #scale.ticks)
    for i, v in ipairs(scale.ticks) do
        H.eq(chart.pools.labels[i].text, T.ns.ChartModel.priceLabel(v))
        H.eq(chart.pools.labels[i].font, "GameFontHighlightSmall")
    end
    -- The range crosses zero: the zero gridline is marked.
    H.truthy(chart.zeroLine.shown)
    chart:set({ days = netDays(3), field = "net", period = 7 })
    H.eq(chart.zeroLine.shown, false)
end)

H.test("missing days are gaps and carried days a lighter tint", function()
    local T, Chart = boot()
    local chart = Chart.new(T.env.UIParent, 700, 300)
    chart:set({
        days = {
            { day = NOW - 6 * DAY, net = 100, carried = false },
            { day = NOW - 3 * DAY, net = 200, carried = true, netCarried = "some" },
            { day = NOW, net = 150 },
        },
        field = "net", period = 7, carriedTint = 0.4,
    })
    H.eq(shownCount(chart.pools.bars), 3)
    local slots = {}
    for i = 1, 3 do slots[i] = chart.drawn[i].slot end
    H.eq(slots, { 1, 4, 7 })
    local a1 = chart.pools.bars[1].span.color[4]
    local a2 = chart.pools.bars[2].span.color[4]
    H.eq(a2, a1 * 0.4)
end)

H.test("the usual line sits at its price, clamped with a mark when off the scale", function()
    local T, Chart = boot()
    local chart = Chart.new(T.env.UIParent, 600, 300)
    chart:set({ days = netDays(5, 1000), field = "net", period = 7, usual = 1000 })
    H.truthy(chart.usualLine.shown)
    H.eq(chart.usualOutside, nil)
    -- An explicit scale the usual price is above.
    chart:set({ days = netDays(5, 1000), field = "net", period = 7, usual = 99999,
        scale = { min = 0, max = 2000, step = 500, ticks = { 0, 500, 1000, 1500, 2000 } } })
    H.eq(chart.usualOutside, "above")
    H.truthy(chart.usualLabel.text:find(T.ns.ChartModel.priceLabel(99999), 1, true))
    chart:set({ days = netDays(5, 1000), field = "net", period = 7 })
    H.eq(chart.usualLine.shown, false)
end)

H.test("hover: invisible slot buttons report the day under the pointer", function()
    local T, Chart, made = boot()
    local chart = Chart.new(T.env.UIParent, 700, 300)
    local seen = {}
    chart.onHover = function(row) seen[#seen + 1] = row or false end
    local days = { { day = NOW - 6 * DAY, net = 100 }, { day = NOW, net = 150 } }
    chart:set({ days = days, field = "net", period = 7 })
    H.eq(shownCount(chart.pools.slots), 7)
    for _, b in ipairs(chart.pools.slots) do H.eq(b.kind, "Button") end
    local first, gap, last = chart.pools.slots[1], chart.pools.slots[3], chart.pools.slots[7]
    first.scripts.OnEnter(first)
    gap.scripts.OnEnter(gap)
    last.scripts.OnEnter(last)
    last.scripts.OnLeave(last)
    H.eq(seen, { days[1], false, days[2], false })
    -- Without a callback nothing raises.
    chart.onHover = nil
    first.scripts.OnEnter(first)
    -- 60 slots then 7: the extra buttons are hidden, none created again.
    local frames = #made.frames
    chart:set({ days = netDays(60), field = "net", period = 60 })
    chart:set({ days = days, field = "net", period = 7 })
    H.eq(shownCount(chart.pools.slots), 7)
    chart:set({ days = netDays(60), field = "net", period = 60 })
    H.eq(#made.frames, frames + 53)
end)

H.test("the weekday strip draws seven bars, Monday first, empty ones hidden", function()
    local T, Chart = boot()
    local chart = Chart.new(T.env.UIParent, 700, 300)
    chart:setWeekday({ { pct = -20, n = 4 }, { pct = 0, n = 4 }, { pct = 5, n = 4 }, { n = 1 },
        { pct = 0, n = 4 }, { pct = 20, n = 4 }, { pct = 20, n = 4 } })
    H.eq(#chart.pools.weekday, 7)
    H.eq(chart.pools.weekday[1].bar.shown, true)
    H.eq(chart.pools.weekday[4].bar.shown, false)
    H.eq(chart.pools.weekday[1].label.text, "-20%")
    H.eq(chart.pools.weekday[6].label.text, "+20%")
    H.eq(chart.pools.weekday[4].label.text, "")
    chart:setWeekday(nil)
    for i = 1, 7 do H.eq(chart.pools.weekday[i].bar.shown, false) end
    H.eq(#chart.pools.weekday, 7)
end)

H.test("the line path is guarded: no CreateLine, a failing one, or a working one", function()
    local T, Chart = boot()
    Chart.USE_LINES = true
    -- The fake frame has no real CreateLine (it answers nil): bars only, no error.
    local chart = Chart.new(T.env.UIParent, 600, 300)
    chart:set({ days = netDays(5), field = "net", period = 7 })
    H.eq(chart.linesOk, false)
    H.eq(shownCount(chart.pools.bars), 5)
    -- A CreateLine that raises.
    local failing = Chart.new(T.env.UIParent, 600, 300)
    failing.plot.CreateLine = function() error("no lines here") end
    failing:set({ days = netDays(5), field = "net", period = 7 })
    H.eq(failing.linesOk, false)
    H.eq(shownCount(failing.pools.bars), 5)
    -- A working one: one segment between each pair of drawn days, pooled.
    local made = 0
    local working = Chart.new(T.env.UIParent, 600, 300)
    working.plot.CreateLine = function()
        made = made + 1
        local l = W.frame()
        l.shown = true
        return l
    end
    working:set({ days = netDays(5), field = "net", period = 7 })
    H.eq(working.linesOk, true)
    H.eq(shownCount(working.pools.lines), 4)
    working:set({ days = netDays(3), field = "net", period = 7 })
    H.eq(shownCount(working.pools.lines), 2)
    H.eq(made, 4)
    Chart.USE_LINES = false
    working:set({ days = netDays(5), field = "net", period = 7 })
    H.eq(shownCount(working.pools.lines), 0)
end)
