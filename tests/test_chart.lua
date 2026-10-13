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
            fs.points = {}
            fs.SetPoint = function(x, ...) x.points[#x.points + 1] = { ... } end
            fs.ClearAllPoints = function(x) x.points = {} end
            fs.font = select(3, ...)
            return fs
        end
        return f
    end
    local create = T.env.CreateFrame
    T.env.CreateFrame = function(kind, name, parent, template)
        local f = track(create(kind, name, parent, template))
        f.shown = true
        f.kind, f.template = kind, template
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

H.test("the chart is loaded after the native kit and draws Lines by default", function()
    local T, Chart = boot()
    H.truthy(Chart)
    H.eq(Chart.USE_LINES, true)
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
    H.eq(shownCount(chart.pools.dashes), 0)
    H.eq(chart.usualShown, false)
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
    local week = Chart.newWeekday(T.env.UIParent, 300, 60, {})
    week:set(nil)
    week:set({ { pct = NAN, n = 2 } })
    week:set("junk", 42)
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
        H.eq(chart.pools.labels[i].text, v == 0 and "0" or T.ns.ChartModel.priceLabel(v))
        H.eq(chart.pools.labels[i].font, "GameFontHighlightSmall")
    end
    -- The range crosses zero: the zero line is drawn, its amount reads "0".
    H.truthy(chart.zeroLine.shown)
    H.truthy(scale.ticks[1] < 0)
    -- A profit only: the net view still holds 0 and its line.
    chart:set({ days = netDays(3), field = "net", period = 7 })
    H.eq(chart.scale.min, 0)
    H.truthy(chart.zeroLine.shown)
    -- An item's prices far from 0: no zero line.
    chart:set({ days = { { day = NOW, avg = 5000, low = 4000, high = 6000 } }, period = 7 })
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
    H.truthy(chart.usualShown)
    H.eq(chart.usualOutside, nil)
    -- A dashed line across the plot, in short segments, and its chip.
    H.truthy(shownCount(chart.pools.dashes) > 10)
    H.truthy(chart.chip.shown)
    -- An explicit scale the usual price is above.
    chart:set({ days = netDays(5, 1000), field = "net", period = 7, usual = 99999,
        scale = { min = 0, max = 2000, step = 500, ticks = { 0, 500, 1000, 1500, 2000 } } })
    H.eq(chart.usualOutside, "above")
    H.truthy(chart.usualLabel.text:find(T.ns.ChartModel.priceLabel(99999), 1, true))
    chart:set({ days = netDays(5, 1000), field = "net", period = 7, usual = 1000, usualLabel = "Usual" })
    H.eq(chart.usualLabel.text, "Usual " .. T.ns.ChartModel.priceLabel(1000))
    chart:set({ days = netDays(5, 1000), field = "net", period = 7 })
    H.eq(chart.usualShown, false)
    H.eq(shownCount(chart.pools.dashes), 0)
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

local NAMES = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }

H.test("the typical week draws seven bars, Monday first, the name under each", function()
    local T, Chart = boot()
    local week = Chart.newWeekday(T.env.UIParent, 500, 60, NAMES)
    week:set({ { pct = -20, n = 4 }, { pct = 0, n = 4 }, { pct = 5, n = 4 }, { n = 1 },
        { pct = 0, n = 4 }, { pct = 20, n = 4 }, { pct = 20, n = 4 } }, "empty")
    local pool = week.pools.weekday
    H.eq(#pool, 7)
    H.eq(pool[1].bar.shown, true)
    H.eq(pool[4].bar.shown, false)
    H.eq(pool[1].label.text, "-20%")
    H.eq(pool[6].label.text, "+20%")
    H.eq(pool[4].label.text, "")
    H.eq(pool[1].name.text, "Mon")
    H.eq(pool[7].name.text, "Sun")
    H.truthy(pool[4].name.shown)                    -- a weekday without data keeps its name
    H.eq(week.note.shown, false)
    -- The percentage above the bars, the name under them.
    H.eq(pool[1].label.points[1][5], 0)
    H.truthy(pool[1].name.points[1][5] < -40)
end)

H.test("an empty typical week is one muted line, not seven empty labels", function()
    local T, Chart = boot()
    local week = Chart.newWeekday(T.env.UIParent, 500, 60, NAMES)
    week:set({ { n = 1 }, { n = 1 } }, "Shows after about two weeks of data.")
    H.truthy(week.empty)
    H.eq(week.note.text, "Shows after about two weeks of data.")
    H.truthy(week.note.shown)
    H.eq(week.note.font, "GameFontDisableSmall")
    for _, e in ipairs(week.pools.weekday) do
        H.eq(e.bar.shown, false)
        H.eq(e.label.shown, false)
        H.eq(e.name.shown, false)
    end
    H.eq(week.zero.shown, false)
    week:set(nil)
    H.truthy(week.note.shown)
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

-- A stand-in for a Native.window: records moves, stops and raises.
local function fakeWindow()
    local win = W.frame()
    win.isNativeWindow = true
    win.calls = {}
    win.StartMoving = function(self) self.calls[#self.calls + 1] = "start" end
    win.Raise = function(self) self.calls[#self.calls + 1] = "raise" end
    win.stopDrag = function(self) self.calls[#self.calls + 1] = "stop" end
    return win
end

H.test("a drag on the plot moves the window, and no hover is reported while it moves", function()
    local T, Chart = boot()
    local win = fakeWindow()
    local chart = Chart.new(T.env.UIParent, 700, 300, win)
    local seen = {}
    chart.onHover = function(row) seen[#seen + 1] = row or false end
    local days = { { day = NOW - 6 * DAY, net = 100 }, { day = NOW, net = 150 } }
    chart:set({ days = days, field = "net", period = 7 })
    local first, last = chart.pools.slots[1], chart.pools.slots[7]
    first.scripts.OnEnter(first)
    first.scripts.OnMouseDown(first)
    first.scripts.OnDragStart(first)
    last.scripts.OnEnter(last)                      -- the pointer crosses slots while moving
    first.scripts.OnDragStop(first)
    H.eq(win.calls, { "raise", "start", "stop" })
    H.eq(seen, { days[1], false })                  -- the drag start hides the hover
    -- After the drag, hovering works again.
    last.scripts.OnEnter(last)
    H.eq(seen[3], days[2])
    -- Slots made later forward drags too.
    chart:set({ days = netDays(30), field = "net", period = 30 })
    local b = chart.pools.slots[30]
    b.scripts.OnDragStart(b)
    H.eq(win.calls[#win.calls], "start")
end)

H.test("without a window, slot buttons do not drag anything", function()
    local T, Chart = boot()
    local chart = Chart.new(T.env.UIParent, 700, 300)
    chart:set({ days = netDays(3), field = "net", period = 7 })
    H.eq(chart.pools.slots[1].scripts.OnDragStart, nil)
end)

H.test("clearing while a day is hovered reports the end of the hover", function()
    local T, Chart = boot()
    local chart = Chart.new(T.env.UIParent, 700, 300)
    local seen = {}
    chart.onHover = function(row) seen[#seen + 1] = row or false end
    chart:set({ days = netDays(3), field = "net", period = 7 })
    local b = chart.pools.slots[7]
    b.scripts.OnEnter(b)
    chart:clear()
    H.eq(#seen, 2)
    H.eq(seen[2], false)
    chart:clear()                                   -- nothing hovered any more: no call
    H.eq(#seen, 2)
end)

H.test("nothing spills outside the plot", function()
    local T, Chart = boot()
    local chart = Chart.new(T.env.UIParent, 100, 300)  -- a 40 px plot: slots under a pixel wide
    local days = netDays(60)
    days[1].net = 0
    chart:set({ days = days, field = "net", period = 60,
        scale = { min = 0, max = 2000, step = 500, ticks = { 0, 500, 1000, 1500, 2000 } } })
    local PW, Hh = chart.plotW, chart.plotH
    for i = 1, #chart.drawn do
        local bar = chart.pools.bars[i]
        for _, part in ipairs({ bar.span, bar.edge, bar.tick, bar.dot }) do
            local b = part.box
            H.truthy(b.x >= 0 and b.x + b.w <= PW + 1e-9)
            H.truthy(b.y >= 0 and b.y <= Hh - 1 and b.y + b.h <= Hh + 1e-9)
        end
    end
    -- The bar at the bottom of the scale (0) still has a pixel inside the plot.
    H.eq(chart.pools.bars[1].span.box.y, Hh - 1)
end)

H.test("hostile ticks and fields are ignored", function()
    local T, Chart = boot()
    local chart = Chart.new(T.env.UIParent, 600, 300)
    chart:set({ days = netDays(3, 200), field = "net", period = 7,
        scale = { min = 0, max = 400, step = 100, ticks = { 0, "x", NAN, 200, INF, 400, {} } } })
    H.eq(shownCount(chart.pools.labels), 3)
    H.eq(shownCount(chart.pools.bars), 3)
    for _, field in ipairs({ 42, {}, true }) do
        chart:set({ days = netDays(3, 200), field = field, period = 7 })
        H.eq(shownCount(chart.pools.bars), 0)
    end
end)

H.test("weekday percentages are rounded and bounded", function()
    local T, Chart = boot()
    local week = Chart.newWeekday(T.env.UIParent, 700, 60, NAMES)
    week:set({ { pct = -0.4, n = 2 }, { pct = 12.7, n = 2 }, { pct = 1e9, n = 2 }, { pct = -1e9, n = 2 } })
    H.eq(week.pools.weekday[1].label.text, "0%")
    H.eq(week.pools.weekday[2].label.text, "+13%")
    H.eq(week.pools.weekday[3].label.text, "+999%")
    H.eq(week.pools.weekday[4].label.text, "-999%")
end)

H.test("the line through the averages stops at gaps", function()
    local T, Chart = boot()
    Chart.USE_LINES = true
    local chart = Chart.new(T.env.UIParent, 700, 300)
    local made = 0
    chart.plot.CreateLine = function()
        made = made + 1
        local l = W.frame()
        l.shown = true
        return l
    end
    -- Slots 1, 2, 3, then a gap, then 5 and 6: two runs, 2 + 1 segments.
    local days = {}
    for _, k in ipairs({ 6, 5, 4, 2, 1 }) do days[#days + 1] = { day = NOW - k * DAY, net = 100 + k } end
    chart:set({ days = days, field = "net", period = 7 })
    Chart.USE_LINES = false
    H.eq(chart.linesOk, true)
    H.eq(shownCount(chart.pools.lines), 3)
    -- Lone days (no neighbour) draw no segment.
    Chart.USE_LINES = true
    chart:set({ days = { { day = NOW - 6 * DAY, net = 1 }, { day = NOW - 3 * DAY, net = 2 }, { day = NOW, net = 3 } },
        field = "net", period = 7 })
    Chart.USE_LINES = false
    H.eq(shownCount(chart.pools.lines), 0)
end)

H.test("4 days on a 60-day period draw over 7 slots from the first day, not 60", function()
    local T, Chart = boot()
    local chart = Chart.new(T.env.UIParent, 600, 300)
    local days = {}
    for k = 3, 0, -1 do days[#days + 1] = { day = NOW - k * DAY, net = 100 + k } end
    chart:set({ days = days, field = "net", period = 60, newest = NOW })
    H.eq(chart.range.count, 7)
    H.eq(shownCount(chart.pools.slots), 7)
    H.eq(chart.drawn[1].slot, 4)
    H.eq(chart.drawn[4].slot, 7)
    -- Bars as wide as the 7 slots allow.
    H.truthy(chart.drawn[1].w >= math.floor(chart.plotW / 7 * 0.6))
end)

H.test("dates under the plot: first, middle and last day of the drawn range", function()
    local T, Chart = boot()
    local chart = Chart.new(T.env.UIParent, 600, 300)
    local seen = {}
    chart.dateText = function(t) seen[#seen + 1] = t return "d" .. #seen end
    chart:set({ days = netDays(10), field = "net", period = 30, newest = NOW })
    H.eq(chart.range.count, 10)
    H.eq(shownCount(chart.pools.dates), 3)
    H.eq(seen, { NOW - 9 * DAY + DAY / 2, NOW - 5 * DAY + DAY / 2, NOW + DAY / 2 })
    H.eq(chart.pools.dates[1].points[1][1], "TOPLEFT")
    H.eq(chart.pools.dates[2].points[1][1], "TOP")
    H.eq(chart.pools.dates[3].points[1][1], "TOPRIGHT")
    H.eq(chart.pools.dates[3].text, "d3")
    -- No weekday names on the chart any more.
    H.eq(chart.pools.weekday, nil)
end)

H.test("the plot sits on its own inset", function()
    local T, Chart = boot()
    local chart = Chart.new(T.env.UIParent, 600, 300)
    H.eq(chart.inset.template, "InsetFrameTemplate")
    H.truthy(chart.backdrop)
end)

H.test("hovering a day highlights its column and draws the bubble the caller words", function()
    local T, Chart = boot()
    local chart = Chart.new(T.env.UIParent, 700, 300)
    local days = { { day = NOW - 6 * DAY, net = 100 }, { day = NOW, net = -150 } }
    chart.bubbleText = function(row) return { "date", "value " .. row.net, "n 3" } end
    chart:set({ days = days, field = "net", period = 7 })
    local first, gap, last = chart.pools.slots[1], chart.pools.slots[3], chart.pools.slots[7]
    first.scripts.OnEnter(first)
    H.truthy(chart.highlight.shown)
    H.truthy(chart.bubble.shown)
    H.eq(chart.bubble.lines[1].text, "date")
    H.eq(chart.bubble.lines[2].text, "value 100")
    H.eq(chart.bubble.lines[4].shown, false)
    H.eq(chart.bubble.lineCount, 3)
    -- The bubble stays inside the plot: right of the first column, left of the last.
    local b = chart.bubble.box
    H.truthy(b.x >= 0 and b.x + b.w <= chart.plotW)
    last.scripts.OnEnter(last)
    b = chart.bubble.box
    H.truthy(b.x >= 0 and b.x + b.w <= chart.plotW)
    H.eq(chart.bubble.lines[2].text, "value -150")
    -- A gap: the column lights up, no bubble.
    gap.scripts.OnEnter(gap)
    H.truthy(chart.highlight.shown)
    H.eq(chart.bubble.shown, false)
    gap.scripts.OnLeave(gap)
    H.eq(chart.highlight.shown, false)
    H.eq(chart.bubble.shown, false)
    -- Without a wording callback, no bubble either.
    chart.bubbleText = nil
    first.scripts.OnEnter(first)
    H.eq(chart.bubble.shown, false)
end)

H.test("net days: green body for a profit, red for a loss, both from the zero line", function()
    local T, Chart = boot()
    local chart = Chart.new(T.env.UIParent, 700, 300)
    chart:set({ days = { { day = NOW - DAY, net = 2000 }, { day = NOW, net = -1000 } }, field = "net", period = 7 })
    local profit, loss = T.ns.Colors.FIXED.profit, T.ns.Colors.FIXED.loss
    local up, down = chart.pools.bars[1], chart.pools.bars[2]
    H.eq(up.dot.color, { profit[1], profit[2], profit[3], 1 })
    H.eq(down.dot.color, { loss[1], loss[2], loss[3], 1 })
    -- Semi-transparent body, opaque lighter edge.
    H.eq(up.span.color[4], T.ns.Chart.BODY_ALPHA)
    H.eq(up.edge.color[4], 1)
    H.truthy(up.edge.color[1] > profit[1])
    -- Both bodies touch the zero line.
    local zeroY = chart.zeroLine.box.y + 1
    H.truthy(math.abs(up.span.box.y + up.span.box.h - zeroY) <= 1)
    H.truthy(math.abs(down.span.box.y - zeroY) <= 1)
end)
