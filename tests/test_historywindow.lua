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
    H.truthy(UI.parts.tabs[3].lit.shown)              -- Profit
    H.eq(UI.parts.tabs[1].lit.shown, false)
    -- Key figures, each with its date, and the title with the market.
    local L = T.ns.L
    H.eq(UI.parts.figures[1].label.text, L.HISTORY_NOW)
    H.truthy(UI.parts.figures[1].value.text ~= "")
    H.eq(UI.parts.figures[1].date.text, UI.dateText(NOW))
    H.eq(UI.parts.figures[2].label.text, L.HISTORY_USUAL)
    H.eq(UI.parts.figures[2].date.text, L.HISTORY_USUAL_NOTE)
    H.eq(UI.parts.figures[3].label.text, L.HISTORY_WORST_DAY)
    H.eq(UI.parts.figures[4].label.text, L.HISTORY_BEST_DAY)
    local summary = T.ns.Controller.historyData(5, "net", 30).summary
    H.eq(UI.parts.coverage.text, string.format(L.HISTORY_COVERAGE, summary.measures, 10))
    H.truthy(UI.parts.title:find(T.ns.Controller.marketName(), 1, true))
    -- The typical week: weekday names under its bars, Monday first.
    H.eq(UI.parts.week.pools.weekday[1].name.text, L.WEEKDAY_1)
    H.eq(UI.parts.week.pools.weekday[7].name.text, L.WEEKDAY_7)
    -- Every part in its own native panel.
    for _, key in ipairs({ "panel", "verdict", "chartPanel", "figuresPanel", "weekPanel" }) do
        H.eq(UI.parts[key].inset.template, "InsetFrameTemplate")
        H.truthy(UI.parts[key].frame.shown)
    end
    H.eq(UI.parts.verdict.title.text, "R5")
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
    -- An item shown: no tab lit.
    for _, tab in ipairs(UI.parts.tabs) do H.eq(tab.lit.shown, false) end
    click(UI.parts.tabs[1])
    H.eq(UI.state().view, "materials")
    H.truthy(UI.parts.tabs[1].lit.shown)
    click(UI.parts.tabs[2])
    H.eq(UI.state().view, "sale")
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

H.test("the hover bubble words the day: date, value, sale and materials for Profit, carried note", function()
    local T, UI = boot()
    track(T, raw(5))
    fill(T, 10)
    UI.show()
    UI.select(5)
    local L = T.ns.L
    H.eq(UI.parts.chart.bubbleText, UI.bubbleLines)
    local lines = UI.bubbleLines({ day = NOW, net = 1234, sale = 2000, materials = 766, n = 3, carried = false })
    H.eq(lines, {
        UI.dateText(NOW),
        string.format(L.HISTORY_LABEL_VALUE, L.HISTORY_VIEW_NET, "<1234>"),
        string.format(L.HISTORY_LABEL_VALUE, L.HISTORY_VIEW_SALE, "<2000>"),
        string.format(L.HISTORY_LABEL_VALUE, L.HISTORY_VIEW_MATERIALS, "<766>"),
        string.format(L.HISTORY_LABEL_VALUE, L.HISTORY_MEASURES, "3"),
    })
    -- A loss reads as a loss, never with a minus sign; a carried day says so.
    lines = UI.bubbleLines({ day = NOW, net = -940, sale = 100, materials = 1040, n = 1, carried = true, netCarried = "some" })
    H.eq(lines[2], string.format(L.HISTORY_LABEL_VALUE, L.HISTORY_VIEW_NET, string.format(L.HISTORY_LOSS, "<940>")))
    H.eq(lines[#lines], L.HISTORY_CARRIED)
    -- An item: average, low - high, measurements.
    click(UI.parts.itemButtons[1])
    lines = UI.bubbleLines({ day = NOW, avg = 100, low = 90, high = 120, n = 4 })
    H.eq(lines[2], string.format(L.HISTORY_LABEL_VALUE, L.HISTORY_AVERAGE, "<100>"))
    H.eq(lines[3], string.format(L.HISTORY_LABEL_VALUE, L.HISTORY_RANGE, "<90> - <120>"))
    H.eq(#lines, 4)
    H.eq(UI.bubbleLines(nil), nil)
    -- The old line under the chart is gone.
    H.eq(UI.parts.hover, nil)
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

H.test("30 tracked recipes scroll through the visible rows", function()
    local T, UI = boot()
    for i = 1, 30 do track(T, raw(i)) end
    UI.show()
    H.truthy(UI.VISIBLE < 30)
    H.eq(#shownRows(UI), UI.VISIBLE)
    UI.frame().scripts.OnMouseWheel(UI.frame(), -2)
    H.eq(shownRows(UI)[1], 3)
    UI.frame().scripts.OnMouseWheel(UI.frame(), -100)
    H.eq(shownRows(UI)[UI.VISIBLE], 30)
end)

H.test("scrolling repaints the rows from the cached list: no data work per step", function()
    local T, UI = boot()
    for i = 1, 30 do track(T, raw(i)) end
    fill(T, 10)
    UI.show()
    UI.select(1)
    local C = T.ns.Controller
    local lists, datas = 0, 0
    local realList, realData = C.historyList, C.historyData
    C.historyList = function(...) lists = lists + 1 return realList(...) end
    C.historyData = function(...) datas = datas + 1 return realData(...) end
    local wheel = UI.frame().scripts.OnMouseWheel
    for _ = 1, 5 do wheel(UI.frame(), -1) end
    wheel(UI.frame(), 1)
    UI.parts.bar.onScroll(3)
    UI.parts.bar.onScroll(0)
    H.eq(lists, 0)
    H.eq(datas, 0)
    H.eq(shownRows(UI)[1], 1)
    UI.parts.bar.onScroll(2)
    H.eq(shownRows(UI)[1], 3)
    -- A refresh (selection, view, period, controller) reads the data once.
    UI.refresh()
    H.eq(lists, 1)
    H.eq(datas, 1)
    -- The offset survives the refresh.
    H.eq(shownRows(UI)[1], 3)
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

H.test("labels fit their buttons, cells and columns in English, French and Spanish", function()
    for _, locale in ipairs({ "enUS", "frFR", "esES" }) do
        local T, UI = boot({ locale = locale })
        track(T, raw(5))
        fill(T, 5)
        UI.show()
        UI.select(5)
        local Layout, L = T.ns.Layout, T.ns.L
        local function fits(text, charW, room)
            local need = Layout.textWidth(text, charW)
            H.truthy(need <= room or error(locale .. ": " .. text .. " needs " .. need .. " px, has " .. room))
        end
        for _, b in ipairs(UI.parts.tabs) do fits(b.text, UI.CHAR_W, b.width - 16) end
        for _, b in ipairs(UI.parts.periodButtons) do fits(b.text, UI.CHAR_W, b.width - 16) end
        -- Tabs and period buttons share one row without overlapping.
        H.truthy(UI.parts.tabsRight + 8 <= UI.parts.periodsLeft or error(locale .. ": tabs and periods overlap"))
        for _, key in ipairs({ "HISTORY_NOW", "HISTORY_USUAL", "HISTORY_LOWEST", "HISTORY_HIGHEST", "HISTORY_WORST_DAY",
            "HISTORY_BEST_DAY", "HISTORY_CHEAPEST_DAY", "HISTORY_PRICIEST_DAY", "HISTORY_USUAL_NOTE" }) do
            fits(L[key], UI.SMALL_CHAR_W, UI.FIGURE_W - 6)
        end
        fits(L.HISTORY_COL_MATERIALS, UI.SMALL_CHAR_W, UI.COL_HEAD_W)
        fits(L.HISTORY_COL_SALE, UI.SMALL_CHAR_W, 44)
        fits(L.HISTORY_LIST, UI.CHAR_W, UI.LEFT_W - 16)
        for i = 1, 7 do fits(L["WEEKDAY_" .. i], UI.SMALL_CHAR_W, UI.USE_W / 7) end
        fits(L.HISTORY_WEEK_EMPTY, UI.SMALL_CHAR_W, UI.USE_W)
        fits(string.format(L.HISTORY_COVERAGE, 9999, 60), UI.SMALL_CHAR_W, UI.USE_W)
        -- Captions (small) and the verdict (normal font) with long amounts.
        for _, text in ipairs({ string.format(L.HISTORY_CAPTION_NET, "7.5"), L.HISTORY_CAPTION_MATERIALS,
            L.HISTORY_CAPTION_SALE, string.format(L.HISTORY_CAPTION_ITEM, "Elixir of the Mongoose Supreme") }) do
            fits(text, UI.SMALL_CHAR_W, UI.USE_W)
        end
        local amount = "999g 99s 99c"
        fits(string.format(L.HISTORY_VERDICT_GOOD, string.format(L.HISTORY_CHEAPER, 99, amount), L.HISTORY_GOOD_BUY), UI.CHAR_W, UI.USE_W)
        fits(string.format(L.HISTORY_VERDICT_GOOD, string.format(L.HISTORY_HIGHER, 99, amount), L.HISTORY_GOOD_CRAFT), UI.CHAR_W, UI.USE_W)
        fits(string.format(L.HISTORY_VERDICT_ON, L.HISTORY_VIEW_MATERIALS, "12/10", string.format(L.HISTORY_LOSS, amount)), UI.CHAR_W, UI.USE_W)
        -- Bubble lines (normal font) inside the bubble.
        local room = T.ns.Chart.BUBBLE_W - 2 * T.ns.Chart.BUBBLE_PAD
        fits(string.format(L.HISTORY_LABEL_VALUE, L.HISTORY_VIEW_NET, string.format(L.HISTORY_LOSS, "99g 99s 99c")), UI.CHAR_W, room)
        for _, key in ipairs({ "HISTORY_VIEW_SALE", "HISTORY_VIEW_MATERIALS", "HISTORY_AVERAGE", "HISTORY_MEASURES" }) do
            fits(string.format(L.HISTORY_LABEL_VALUE, L[key], "999g 99s 99c"), UI.CHAR_W, room)
        end
        fits(string.format(L.HISTORY_LABEL_VALUE, L.HISTORY_RANGE, "99g 99s - 99g 99s"), UI.CHAR_W, room)
        fits(L.HISTORY_CARRIED, UI.CHAR_W, room)
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
    H.eq(UI.parts.rows[1].status.text, T.ns.L.TRACK_PAUSED)
    H.eq(UI.parts.rows[1].materials.text, "")
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

H.test("the action labels fit their buttons with room to spare in English, French and Spanish", function()
    for _, locale in ipairs({ "enUS", "frFR", "esES" }) do
        local T, UI = boot({ locale = locale })
        track(T, raw(5))
        fill(T, 5)
        UI.show()
        UI.select(5)
        local Layout, L = T.ns.Layout, T.ns.L
        for _, b in ipairs({ UI.parts.pauseButton, UI.parts.deleteButton }) do
            H.eq(b.width, UI.ACTION_W)
            for _, text in ipairs({ L.HISTORY_PAUSE, L.HISTORY_RESUME, L.HISTORY_DELETE, L.HISTORY_DELETE_CONFIRM }) do
                -- 8 px from each end for the button's caps, and 8 px more of margin.
                local need = Layout.textWidth(text, UI.CHAR_W)
                H.truthy(need <= b.width - 24 or error(locale .. ": " .. text .. " needs " .. need))
            end
        end
    end
end)

H.test("the hint under the list takes 3 lines at most in English, French and Spanish", function()
    for _, locale in ipairs({ "enUS", "frFR", "esES" }) do
        local T, UI = boot({ locale = locale })
        local lines = T.ns.Layout.wrapLines(T.ns.L.HISTORY_INFO, UI.SMALL_CHAR_W, UI.LEFT_W)
        H.truthy(lines <= UI.HINT_LINES or error(locale .. ": " .. lines .. " lines"))
    end
end)

H.test("closing the window disarms a pending delete", function()
    local T, UI = boot()
    track(T, raw(5))
    fill(T, 10)
    UI.show()
    UI.select(5)
    click(UI.parts.deleteButton)
    H.eq(UI.parts.deleteButton.text, T.ns.L.HISTORY_DELETE_CONFIRM)
    UI.frame().scripts.OnHide(UI.frame())
    UI.hide()
    UI.show()
    H.eq(UI.parts.deleteButton.text, T.ns.L.HISTORY_DELETE)
    click(UI.parts.deleteButton)
    H.eq(#T.env.CraftProfitDB.tracked, 1)
end)

H.test("without a timer the delete never arms, so it never deletes", function()
    local T, UI = boot()
    track(T, raw(5))
    fill(T, 10)
    UI.show()
    UI.select(5)
    T.env.C_Timer.After = nil
    click(UI.parts.deleteButton)
    H.eq(UI.parts.deleteButton.text, T.ns.L.HISTORY_DELETE)
    click(UI.parts.deleteButton)
    H.eq(#T.env.CraftProfitDB.tracked, 1)
end)

H.test("a paused recipe with too little data says both", function()
    local T, UI = boot()
    track(T, raw(5), false)
    fill(T, 2)
    UI.show()
    UI.select(5)
    H.eq(UI.parts.empty.text, string.format(T.ns.L.HISTORY_NODATA, 2, 2))
    H.truthy(UI.parts.status.shown)
    H.eq(UI.parts.status.text, T.ns.L.HISTORY_PAUSED)
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

H.test("the icon groups wrap: a 14 item recipe shows every item on two lines, the window fits 768 px", function()
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
    local shown = 0
    for _, b in ipairs(UI.parts.itemButtons) do
        if b.shown then
            shown = shown + 1
            local p = b.points[1]
            H.truthy(p[4] >= 0 and p[4] + UI.ICON <= UI.USE_W)
        end
    end
    H.eq(shown, #ids)
    H.truthy(UI.parts.iconLayout.lines <= UI.ICON_ROWS)
    -- Three groups, each with its caption, two separators.
    for _, key in ipairs({ "materials", "crafted", "disenchant" }) do H.truthy(UI.parts.groupCaptions[key].shown) end
    local seps = 0
    for _, sep in ipairs(UI.parts.separators) do if sep.shown then seps = seps + 1 end end
    H.eq(seps, 2)
    -- The window fits a 768 px screen at scale 1 (Native.fitToScreen keeps a 20 px margin).
    H.truthy(UI.frame().height <= 748 or error("height " .. UI.frame().height))
    ITEMS[300] = nil
end)

H.test("only the groups that exist show, with no orphan separator", function()
    local T, UI = boot()
    -- Bound on pickup, never disenchanted (class 0): materials only.
    ITEMS[200] = { quality = 2, ilvl = 15, sellPrice = 200, classID = 0, bindType = 1 }
    local bound = raw(7)
    bound.outputItemID = 200
    track(T, bound)
    track(T, raw(5))
    fill(T, 10)
    UI.show()
    UI.select(7)
    H.truthy(UI.parts.groupCaptions.materials.shown)
    H.eq(UI.parts.groupCaptions.crafted.shown, false)
    H.eq(UI.parts.groupCaptions.disenchant.shown, false)
    for _, sep in ipairs(UI.parts.separators) do H.eq(sep.shown, false) end
    -- Materials and the crafted item, no disenchant: one separator between them.
    UI.select(5)
    H.truthy(UI.parts.groupCaptions.crafted.shown)
    H.eq(UI.parts.groupCaptions.disenchant.shown, false)
    H.truthy(UI.parts.separators[1].shown)
    H.eq(UI.parts.separators[2].shown, false)
    H.eq(UI.parts.groupCaptions.materials.text, T.ns.L.HISTORY_GROUP_MATERIALS)
    ITEMS[200] = nil
end)

H.test("layoutIcons flows groups along lines, separators only between groups on a line", function()
    local _, UI = boot()
    local step = UI.ICON + UI.ICON_GAP
    local sep = 2 * UI.SEP_GAP + 1
    local out = UI.layoutIcons({ { key = "a", count = 2 }, { key = "b", count = 0 }, { key = "c", count = 1, captionW = 60 } }, 400)
    H.eq(#out.groups, 2)
    H.eq(out.lines, 1)
    H.eq(out.groups[2].key, "c")
    H.eq(out.groups[2].x, 2 * step - UI.ICON_GAP + sep)
    H.eq(out.separators, { { x = 2 * step - UI.ICON_GAP + UI.SEP_GAP, line = 1 } })
    -- The second group does not fit the rest of the line: it starts the next one, no separator.
    out = UI.layoutIcons({ { key = "a", count = 5 }, { key = "b", count = 3 } }, 6 * step)
    H.eq(out.groups[2].line, 2)
    H.eq(out.groups[2].x, 0)
    H.eq(out.separators, {})
    H.eq(out.lines, 2)
    -- A group wider than a line wraps its own icons.
    out = UI.layoutIcons({ { key = "a", count = 5 } }, 3 * step)
    H.eq(out.groups[1].icons[4], { x = 0, line = 2 })
    H.eq(UI.layoutIcons({}, 400).lines, 0)
end)

H.test("the verdict says today's amount and compares it with the usual price, coloured", function()
    local T, UI = boot()
    local L = T.ns.L
    track(T, raw(5))
    -- Ten flat days, then item 1 cheaper today: materials 250 -> 210, 16 % cheaper.
    local series = T.ns.Controller.market().series
    for id, unit in pairs(PRICES) do
        series[id] = {}
        for age = 9, 0, -1 do
            local u = (id == 1 and age == 0) and 80 or unit
            series[id][#series[id] + 1] = { NOW - age * DAY, u, 5, u, u, 1, true }
        end
    end
    UI.show()
    UI.select(5)
    click(UI.parts.tabs[1])
    H.eq(UI.parts.verdictLine.text, string.format(L.HISTORY_VERDICT_TODAY, L.HISTORY_VIEW_MATERIALS, "<210>"))
    H.eq(UI.parts.compareLine.text, string.format(L.HISTORY_VERDICT_GOOD,
        string.format(L.HISTORY_CHEAPER, 16, "<250>"), L.HISTORY_GOOD_BUY))
    -- Good news is green, bad news red, about usual grey.
    local data = T.ns.Controller.historyData(5, "materials", 30)
    H.eq(select(2, UI.compareLine(data)), T.ns.Colors.FIXED.profit)
    data.compare = { pct = 9, tone = "up", good = false }
    local text, color = UI.compareLine(data)
    H.eq(text, string.format(L.HISTORY_HIGHER, 9, "<250>"))
    H.eq(color, T.ns.Colors.FIXED.loss)
    data.compare = nil
    H.eq(UI.compareLine(data), "")
    -- Materials: the cheapest and priciest days.
    H.eq(UI.parts.figures[3].label.text, L.HISTORY_CHEAPEST_DAY)
    H.eq(UI.parts.figures[3].date.text, UI.dateText(NOW))
    -- The caption says what is drawn.
    H.eq(UI.parts.caption.text, L.HISTORY_CAPTION_MATERIALS)
    click(UI.parts.tabs[3])
    H.eq(UI.parts.caption.text, string.format(L.HISTORY_CAPTION_NET, "5"))
    -- Sale unchanged: about the usual level, no advice.
    click(UI.parts.tabs[2])
    H.eq(UI.parts.compareLine.text, string.format(L.HISTORY_ABOUT, "<950>"))
    H.eq(UI.parts.caption.text, L.HISTORY_CAPTION_SALE)
    click(UI.parts.itemButtons[1])
    H.eq(UI.parts.caption.text, string.format(L.HISTORY_CAPTION_ITEM, "Item1"))
    H.eq(UI.parts.figures[3].label.text, L.HISTORY_LOWEST)
end)

H.test("a loss never prints a minus sign", function()
    local T, UI = boot()
    local L = T.ns.L
    track(T, raw(5))
    -- The crafted item sells for 100 (95 after the cut); materials cost 250: a 155 loss.
    local series = T.ns.Controller.market().series
    for id, unit in pairs({ [1] = 100, [2] = 50, [100] = 100 }) do
        series[id] = {}
        for age = 9, 0, -1 do series[id][#series[id] + 1] = { NOW - age * DAY, unit, 5, unit, unit, 1, true } end
    end
    UI.show()
    UI.select(5)
    H.eq(UI.parts.verdictLine.text, string.format(L.HISTORY_VERDICT_TODAY, L.HISTORY_VIEW_NET, string.format(L.HISTORY_LOSS, "<155>")))
    for _, f in ipairs(UI.parts.figures) do H.falsy(f.value.text:find("-", 1, true)) end
    H.eq(UI.parts.figures[1].value.text, string.format(L.HISTORY_LOSS, "<155>"))
    -- The chart holds the zero line.
    H.truthy(UI.parts.chart.zeroLine.shown)
end)

H.test("a typical week without enough data is one muted line", function()
    local T, UI = boot()
    track(T, raw(5))
    fill(T, 5)
    UI.show()
    UI.select(5)
    H.truthy(UI.parts.week.empty)
    H.eq(UI.parts.week.note.text, T.ns.L.HISTORY_WEEK_EMPTY)
    H.truthy(UI.parts.week.note.shown)
end)

H.test("hovering a list row explains the two columns", function()
    local T, UI = boot()
    track(T, raw(5))
    UI.show()
    local row = UI.parts.rows[1]
    row.scripts.OnEnter(row)
    H.eq(T.tooltip.owner, row)
    H.eq(T.tooltip.text, T.ns.L.HISTORY_ROW_TIP)
    row.scripts.OnLeave(row)
    H.eq(T.tooltip.shown, false)
    H.eq(UI.parts.colMaterials.text, T.ns.L.HISTORY_COL_MATERIALS)
    H.eq(UI.parts.colSale.text, T.ns.L.HISTORY_COL_SALE)
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

H.test("the history window shrinks to fit a short screen", function()
    local T, UI = boot()
    T.env.UIParent.GetHeight = function() return 300 end
    UI.show()
    local f = UI.frame()
    f.SetScale = function(self, v) self.scale = v end
    UI.hide()
    UI.show()
    H.eq(f.scale, 280 / f.height)
end)
