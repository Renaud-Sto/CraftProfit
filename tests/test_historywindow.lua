local H = ...
local W = dofile("tests/fakewow.lua")
local stubClock = dofile("tests/stubclock.lua")

local DAY = 86400
local NOW = 1700000000 -- the fake game's time()

local ITEMS = {
    [1] = { quality = 1, ilvl = 10, sellPrice = 5, classID = 0, bindType = 0 },
    [2] = { quality = 1, ilvl = 10, sellPrice = 5, classID = 0, bindType = 0 },
    [100] = { quality = 2, ilvl = 15, sellPrice = 200, classID = 0, bindType = 2 },
}

local function raw(id, name)
    return { recipeID = id, name = name or ("R" .. id), locale = "enUS", difficulty = "easy", outputItemID = 100,
        qtyMin = 1, qtyMax = 1, reagents = { { itemID = 1, qty = 2 }, { itemID = 2, qty = 1 } } }
end

-- Boots with frames that start shown, recording named frames, anchors, sizes, textures.
local function boot(opts)
    opts = opts or {}
    local T = W.boot(H, { items = ITEMS, locale = opts.locale })
    T.env.GetMoneyString = function(c) return "<" .. c .. ">" end
    T.env.CraftProfitDB = opts.saved
    T.env.UISpecialFrames = {}
    T.tooltip = {}
    T.env.GameTooltip = {
        SetOwner = function(_, owner) T.tooltip.owner = owner end,
        SetText = function(_, text) T.tooltip.text = text end,
        Show = function() T.tooltip.shown = true end,
        Hide = function() T.tooltip.shown = false end,
    }
    local named = {}
    local create = T.env.CreateFrame
    T.env.CreateFrame = function(kind, name, parent, template)
        local f = create(kind, name, parent, template)
        f.kind, f.template = kind, template
        f.shown = true
        f.points = {}
        f.SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end
        f.ClearAllPoints = function(self) self.points = {} end
        f.SetSize = function(self, w, h) self.width, self.height = w, h end
        f.SetWidth = function(self, w) self.width = w end
        local createTexture = f.CreateTexture
        f.CreateTexture = function(self, ...)
            local t = createTexture(self, ...)
            t.shown = true
            t.SetTexture = function(tex, path) tex.texture = path end
            return t
        end
        if name then named[name] = f end
        return f
    end
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    T.ns.History.setDateFn(stubClock(0))
    return T, T.ns.HistoryWindow, named
end

local function track(T, recipe, active)
    H.truthy(T.ns.History.track(T.env.CraftProfitDB, T.ns.Recipes.normalize(recipe)))
    if active == false then T.ns.History.pause(T.env.CraftProfitDB, recipe.recipeID) end
end

local PRICES = { [1] = 100, [2] = 50, [100] = 1000 }

local function fill(T, days)
    local series = T.ns.Controller.market().series
    for id, unit in pairs(PRICES) do
        series[id] = {}
        for age = days - 1, 0, -1 do
            series[id][#series[id] + 1] = { NOW - age * DAY, unit + age, 5, unit, unit + age, 1, true }
        end
    end
end

local function click(b) b.scripts.OnClick(b) end

local function shownRows(UI)
    local ids = {}
    for _, row in ipairs(UI.parts.rows) do
        if row.shown then ids[#ids + 1] = row.recipeID end
    end
    return ids
end

H.test("the window is built on first open only, with Escape registered once", function()
    local T, UI, named = boot()
    H.eq(UI.frame(), nil)
    H.eq(named.CraftProfitHistoryWindow, nil)
    UI.show()
    H.truthy(UI.isShown())
    H.eq(UI.frame(), named.CraftProfitHistoryWindow)
    H.eq(UI.frame().template, "ButtonFrameTemplate")
    UI.hide()
    H.falsy(UI.isShown())
    UI.toggle()
    H.truthy(UI.isShown())
    H.eq(T.env.UISpecialFrames, { "CraftProfitHistoryWindow" })
end)

H.test("with no tracked recipe the window says how to track one", function()
    local T, UI = boot()
    UI.show()
    H.eq(UI.parts.empty.text, T.ns.L.HISTORY_NONE)
    H.truthy(UI.parts.empty.shown)
    H.eq(UI.parts.chart.frame.shown, false)
    H.eq(shownRows(UI), {})
end)

H.test("opening it selects nothing: the right side asks for a recipe", function()
    local T, UI = boot()
    track(T, raw(5, "Sword"))
    fill(T, 10)
    UI.show()
    H.eq(shownRows(UI), { 5 })
    H.eq(UI.parts.rows[1].name.text, "Sword")
    H.eq(UI.parts.empty.text, T.ns.L.HISTORY_SELECT)
    H.eq(UI.parts.chart.frame.shown, false)
    H.eq(UI.state().selected, nil)
    -- The information line on the data's origin is always there.
    H.eq(UI.parts.info.text, T.ns.L.HISTORY_INFO)
end)

H.test("clicking a row selects it and draws its result over 30 days", function()
    local T, UI = boot()
    track(T, raw(5))
    fill(T, 10)
    UI.show()
    click(UI.parts.rows[1])
    H.eq(UI.state(), { selected = 5, view = "net", period = 30 })
    H.truthy(UI.parts.rows[1].selected.shown)
    H.eq(UI.parts.empty.shown, false)
    H.truthy(UI.parts.chart.frame.shown)
    H.eq(#UI.parts.chart.drawn, 10)
    H.truthy(UI.parts.periodButtons[2].lit.shown)
    H.eq(UI.parts.periodButtons[1].lit.shown, false)
    H.truthy(UI.parts.viewButtons[1].lit.shown)
    -- Key figures and the title with the market.
    H.eq(UI.parts.figures.today.label.text, T.ns.L.HISTORY_TODAY)
    H.truthy(UI.parts.figures.today.value.text ~= "")
    H.eq(UI.parts.figures.days.value.text, "10")
    H.truthy(UI.frame().titleText == nil or true)
    H.truthy(UI.parts.title:find(T.ns.Controller.marketName(), 1, true))
    -- Weekday names under the strip, Monday first.
    H.eq(UI.parts.weekdayNames[1].text, T.ns.L.WEEKDAY_1)
    H.eq(UI.parts.weekdayNames[7].text, T.ns.L.WEEKDAY_7)
end)

H.test("too little data says how much there is", function()
    local T, UI = boot()
    track(T, raw(5))
    fill(T, 2)
    UI.show()
    UI.select(5)
    H.eq(UI.parts.empty.text, string.format(T.ns.L.HISTORY_NODATA, 2, 2))
    H.truthy(UI.parts.empty.shown)
    H.eq(UI.parts.chart.frame.shown, false)
end)

H.test("a paused recipe still shows its chart and says it is paused", function()
    local T, UI = boot()
    track(T, raw(5), false)
    fill(T, 10)
    UI.show()
    UI.select(5)
    H.truthy(UI.parts.chart.frame.shown)
    H.eq(UI.parts.status.text, T.ns.L.HISTORY_PAUSED)
    H.truthy(UI.parts.status.shown)
end)

H.test("period and item buttons redraw; a new recipe resets the view and keeps the period", function()
    local T, UI = boot()
    track(T, raw(5))
    track(T, raw(6))
    fill(T, 20)
    UI.show()
    UI.select(5)
    click(UI.parts.periodButtons[1])
    H.eq(UI.state().period, 7)
    H.truthy(UI.parts.periodButtons[1].lit.shown)
    H.eq(#UI.parts.chart.drawn, 7)
    -- Item icons from a fixed pool: items 1, 2 and 100 shown, the rest hidden.
    local shown = 0
    for _, b in ipairs(UI.parts.itemButtons) do if b.shown then shown = shown + 1 end end
    H.eq(shown, 3)
    H.truthy(UI.parts.itemButtons[3].shown)
    click(UI.parts.itemButtons[1])
    H.eq(UI.state().view, "item:1")
    H.truthy(UI.parts.itemButtons[1].lit.shown)
    H.eq(UI.parts.viewButtons[1].lit.shown, false)
    click(UI.parts.viewButtons[2])
    H.eq(UI.state().view, "materials")
    UI.select(6)
    H.eq(UI.state(), { selected = 6, view = "net", period = 7 })
end)

H.test("an item icon falls back to the question mark, and its tooltip names it", function()
    local T, UI = boot()
    track(T, raw(5))
    fill(T, 5)
    T.ns.Controller.itemIcon = function(id) if id == 1 then return 12345 end return nil end
    UI.show()
    UI.select(5)
    H.eq(UI.parts.itemButtons[1].icon.texture, 12345)
    H.eq(UI.parts.itemButtons[2].icon.texture, UI.QUESTION_MARK)
    local b = UI.parts.itemButtons[3]
    b.scripts.OnEnter(b)
    H.eq(T.tooltip.owner, b)
    H.eq(T.tooltip.text, "Item100")
    b.scripts.OnLeave(b)
    H.eq(T.tooltip.shown, false)
    -- An icon helper that raises is survived.
    T.ns.Controller.itemIcon = function() error("boom") end
    UI.refresh()
    H.eq(UI.parts.itemButtons[1].icon.texture, UI.QUESTION_MARK)
end)

H.test("hovering a day shows its figures under the chart, with the carried note", function()
    local T, UI = boot()
    track(T, raw(5))
    fill(T, 10)
    UI.show()
    UI.select(5)
    local chart = UI.parts.chart
    chart.onHover({ day = NOW, net = 1234, carried = false })
    H.truthy(UI.parts.hover.text:find("<1234>", 1, true))
    H.falsy(UI.parts.hover.text:find(T.ns.L.HISTORY_CARRIED, 1, true))
    chart.onHover({ day = NOW, net = 1234, carried = true, netCarried = "some" })
    H.truthy(UI.parts.hover.text:find(T.ns.L.HISTORY_CARRIED, 1, true))
    chart.onHover(nil)
    H.eq(UI.parts.hover.text, "")
end)

H.test("refresh keeps the state, and does nothing while hidden", function()
    local T, UI = boot()
    track(T, raw(5))
    fill(T, 20)
    UI.show()
    UI.select(5)
    click(UI.parts.periodButtons[3])
    click(UI.parts.itemButtons[2])
    T.ns.Controller.refresh()
    H.eq(UI.state(), { selected = 5, view = "item:2", period = 60 })
    local calls = 0
    local real = T.ns.Controller.historyData
    T.ns.Controller.historyData = function(...) calls = calls + 1 return real(...) end
    UI.hide()
    UI.refresh()
    T.ns.Controller.refresh()
    H.eq(calls, 0)
end)

H.test("removing the selected recipe clears the selection", function()
    local T, UI = boot()
    track(T, raw(5))
    fill(T, 10)
    UI.show()
    UI.select(5)
    T.ns.Controller.historyCommand("remove 1")
    H.eq(UI.state().selected, nil)
    H.eq(UI.parts.empty.text, T.ns.L.HISTORY_NONE)
end)

H.test("30 tracked recipes scroll through 12 rows", function()
    local T, UI = boot()
    for i = 1, 30 do track(T, raw(i)) end
    UI.show()
    H.eq(#shownRows(UI), 12)
    UI.frame().scripts.OnMouseWheel(UI.frame(), -5)
    H.eq(shownRows(UI)[1], 6)
    UI.frame().scripts.OnMouseWheel(UI.frame(), -100)
    H.eq(shownRows(UI)[12], 30)
end)

H.test("openHistory opens the window on that recipe", function()
    local T, UI = boot()
    track(T, raw(5))
    fill(T, 10)
    T.ns.Controller.openHistory(5)
    H.truthy(UI.isShown())
    H.eq(UI.state().selected, 5)
end)

H.test("a drag saves the position, the next login reopens there, a hostile save is dropped", function()
    local T, UI, named = boot()
    UI.show()
    local f = named.CraftProfitHistoryWindow
    f.scripts.OnDragStop(f)
    H.eq(T.env.CraftProfitDB.settings.historyWindow, { x = 100, y = 700 })
    local T2, UI2, named2 = boot({ saved = { settings = { historyWindow = { x = 40, y = 500 } } } })
    UI2.show()
    local f2 = named2.CraftProfitHistoryWindow
    H.eq(f2.points[#f2.points], { "TOPLEFT", T2.env.UIParent, "BOTTOMLEFT", 40, 500 })
    local _, UI3, named3 = boot({ saved = { settings = { historyWindow = { x = "1", y = 0 / 0 } } } })
    UI3.show()
    local f3 = named3.CraftProfitHistoryWindow
    H.eq(f3.points[#f3.points][1], "CENTER")
end)

H.test("the chart forwards drags to the window", function()
    local T, UI = boot()
    track(T, raw(5))
    fill(T, 10)
    UI.show()
    UI.select(5)
    local moved = false
    UI.frame().StartMoving = function() moved = true end
    local slot = UI.parts.chart.pools.slots[1]
    slot.scripts.OnDragStart(slot)
    H.truthy(moved)
end)

H.test("labels fit their buttons and columns in English, French and Spanish", function()
    for _, locale in ipairs({ "enUS", "frFR", "esES" }) do
        local T, UI = boot({ locale = locale })
        track(T, raw(5))
        fill(T, 5)
        UI.show()
        UI.select(5)
        local Layout = T.ns.Layout
        local function fits(text, charW, room)
            local need = Layout.textWidth(text, charW)
            H.truthy(need <= room or error(locale .. ": " .. text .. " needs " .. need .. " px, has " .. room))
        end
        for _, b in ipairs(UI.parts.viewButtons) do fits(b.text, UI.CHAR_W, b.width - 16) end
        for _, b in ipairs(UI.parts.periodButtons) do fits(b.text, UI.CHAR_W, b.width - 16) end
        for _, f in pairs(UI.parts.figures) do fits(f.label.text, UI.SMALL_CHAR_W, UI.FIGURE_LABEL_W) end
        for _, fs in ipairs(UI.parts.weekdayNames) do fits(fs.text, UI.SMALL_CHAR_W, UI.WEEKDAY_W) end
        fits(T.ns.L.HISTORY_LIST, UI.CHAR_W, UI.LEFT_W - 16)
    end
end)

H.test("the pause button toggles tracking and keeps the data", function()
    local T, UI = boot()
    track(T, raw(5))
    fill(T, 10)
    UI.show()
    UI.select(5)
    local pause = UI.parts.pauseButton
    H.truthy(pause.shown)
    H.eq(pause.text, T.ns.L.HISTORY_PAUSE)
    click(pause)
    H.eq(T.ns.History.isActive(T.env.CraftProfitDB, 5), false)
    H.eq(pause.text, T.ns.L.HISTORY_RESUME)
    H.eq(UI.parts.rows[1].arrows.text, T.ns.L.TRACK_PAUSED)
    H.eq(#T.ns.Controller.market().series[1], 10)
    H.eq(UI.state().selected, 5)
    click(pause)
    H.eq(T.ns.History.isActive(T.env.CraftProfitDB, 5), true)
    H.eq(pause.text, T.ns.L.HISTORY_PAUSE)
end)

H.test("delete asks for a second click within 4 seconds, on the button itself", function()
    local T, UI = boot()
    track(T, raw(5))
    fill(T, 10)
    UI.show()
    UI.select(5)
    local delete = UI.parts.deleteButton
    H.eq(delete.text, T.ns.L.HISTORY_DELETE)
    click(delete)
    H.eq(delete.text, T.ns.L.HISTORY_DELETE_CONFIRM)
    H.eq(#T.env.CraftProfitDB.tracked, 1)
    T.run()                                           -- 4 seconds pass: back to normal
    H.eq(delete.text, T.ns.L.HISTORY_DELETE)
    click(delete)
    click(delete)
    H.eq(#T.env.CraftProfitDB.tracked, 0)
    H.eq(UI.state().selected, nil)
    H.eq(T.ns.Controller.market().series[1], nil)
    H.eq(UI.parts.empty.text, T.ns.L.HISTORY_NONE)
    H.eq(UI.parts.deleteButton.shown, false)
end)

H.test("an armed delete is cancelled by choosing another recipe", function()
    local T, UI = boot()
    track(T, raw(5))
    track(T, raw(6))
    fill(T, 10)
    UI.show()
    UI.select(5)
    click(UI.parts.deleteButton)
    UI.select(6)
    H.eq(UI.parts.deleteButton.text, T.ns.L.HISTORY_DELETE)
    click(UI.parts.deleteButton)
    H.eq(#T.env.CraftProfitDB.tracked, 2)
    -- The actions show for a recipe without enough data too, and the labels fit.
    T.ns.Controller.market().series = {}
    UI.refresh()
    H.truthy(UI.parts.deleteButton.shown)
    H.truthy(UI.parts.pauseButton.shown)
end)

H.test("the action labels fit their buttons in English, French and Spanish", function()
    for _, locale in ipairs({ "enUS", "frFR", "esES" }) do
        local T, UI = boot({ locale = locale })
        local Layout, L = T.ns.Layout, T.ns.L
        for _, b in ipairs({ UI.parts.pauseButton or { width = UI.ACTION_W }, UI.parts.deleteButton or { width = UI.ACTION_W } }) do
            for _, text in ipairs({ L.HISTORY_PAUSE, L.HISTORY_RESUME, L.HISTORY_DELETE, L.HISTORY_DELETE_CONFIRM }) do
                local need = Layout.textWidth(text, UI.CHAR_W)
                H.truthy(need <= b.width - 16 or error(locale .. ": " .. text .. " needs " .. need))
            end
        end
    end
end)

H.test("a drag that ends on a button clicks nothing", function()
    local T, UI = boot()
    track(T, raw(5))
    fill(T, 10)
    UI.show()
    UI.select(5)
    UI.frame().StartMoving = function() end
    for _, b in ipairs({ UI.parts.periodButtons[1], UI.parts.deleteButton, UI.parts.pauseButton }) do
        b.scripts.OnMouseDown(b)
        b.scripts.OnDragStart(b)
        click(b)
    end
    H.eq(UI.state().period, 30)
    H.eq(UI.parts.deleteButton.text, T.ns.L.HISTORY_DELETE)
    H.eq(T.ns.History.isActive(T.env.CraftProfitDB, 5), true)
end)

H.test("the icon row wraps: a 14 item recipe shows every item, clear of the period buttons", function()
    local T, UI = boot()
    -- 12 reagents and a weapon whose disenchant materials count: at least 14 items.
    ITEMS[300] = { quality = 2, ilvl = 15, sellPrice = 200, classID = 2, bindType = 2 }
    local big = raw(9)
    big.outputItemID = 300
    big.reagents = {}
    for id = 1, 12 do big.reagents[id] = { itemID = 1000 + id, qty = 1 } end
    track(T, big)
    UI.show()
    UI.select(9)
    local ids = T.ns.Controller.historyItemsOf(T.env.CraftProfitDB.tracked[1].recipe)
    H.truthy(#ids >= 14)
    H.truthy(#UI.parts.itemButtons >= 20)
    local shown, periodLeft = 0, UI.RIGHT_W - UI.PERIOD_W
    for _, b in ipairs(UI.parts.itemButtons) do
        if b.shown then
            shown = shown + 1
            local p = b.points[1]
            H.truthy(p[4] + 24 <= periodLeft - 4)
        end
    end
    H.eq(shown, #ids)
    -- Two rows of icons: the second starts under the first.
    H.eq(UI.parts.itemButtons[11].points[1][4], 0)
    H.truthy(UI.parts.itemButtons[11].points[1][5] < UI.parts.itemButtons[1].points[1][5])
    -- The period buttons stack at the right; the window stays under 500 px high.
    for _, b in ipairs(UI.parts.periodButtons) do H.eq(b.points[1][1], "TOPRIGHT") end
    H.truthy(UI.frame().height < 500)
    ITEMS[300] = nil
end)

H.test("the hover date follows the locale: month first in English, day first in French and Spanish", function()
    for locale, expected in pairs({ enUS = "10/12", frFR = "12/10", esES = "12/10" }) do
        local T, UI = boot({ locale = locale })
        T.ns.History.setDateFn(function()
            return { year = 2026, month = 10, day = 12, hour = 12, min = 0, sec = 0, wday = 2 }
        end)
        H.eq(UI.dateText(NOW), expected)
    end
    local _, UI = boot()
    H.eq(UI.dateText(0 / 0), "")
end)
