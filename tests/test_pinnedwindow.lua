local H = ...
local W = dofile("tests/fakewow.lua")

-- classID 0 on both outputs: disenchanting never applies.
local ITEMS = {
    [100] = { quality = 2, ilvl = 15, sellPrice = 200, classID = 0, bindType = 2 },
    [101] = { quality = 1, ilvl = 1, sellPrice = 10, classID = 0, bindType = 2 },
}

local function raw(id, output, difficulty, name)
    return { recipeID = id, name = name or ("R" .. id), locale = "enUS", difficulty = difficulty, outputItemID = output or 100,
        reagents = { { itemID = 1, qty = 2 }, { itemID = 2, qty = 1 } } }
end

-- Boots with frames that start shown (as on the client), records named frames, their
-- anchors and sizes. `saved`: CraftProfitDB before login. `pins`: raw recipes pinned
-- after login.
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
        if opts.onFrame then opts.onFrame(f) end
        if name then named[name] = f end
        return f
    end
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    -- Written straight into the saved table: more than DB.MAX_PINS when a test asks.
    for _, r in ipairs(opts.pins or {}) do
        local pins = T.env.CraftProfitCharDB.pins
        pins[#pins + 1] = T.ns.Recipes.normalize(r)
    end
    return T, T.ns.PinnedWindow, named
end

local function stock(T)
    local P, market = T.ns.Prices, T.ns.Controller.market()
    P.store(market, 1, 100, 10, 1699999940)
    P.store(market, 2, 50, 10, 1699999880)
    P.store(market, 100, 1000, 10, 1699999970)
end

local function click(button) button.scripts.OnClick(button) end

-- The rows on screen, top to bottom: recipe ids of the shown rows.
local function shownIDs(UI)
    local ids = {}
    for _, row in ipairs(UI.parts.rows) do
        if row.shown then ids[#ids + 1] = row.recipeID end
    end
    return ids
end

local function manyPins(n)
    local list = {}
    for i = 1, n do list[i] = raw(i, 101, "easy") end
    return list
end

H.test("the pinned window is not built at login, only on first open", function()
    local T, UI, named = boot({ pins = { raw(1) } })
    H.eq(named.CraftProfitPinnedWindow, nil)
    H.eq(UI.frame(), nil)
    H.falsy(UI.isShown())
    -- Nothing evaluated the pins at login (the market is not opened early).
    H.eq(next(T.env.CraftProfitDB.markets), nil)
    UI.refresh()
    UI.hide()
    UI.show()
    local f = named.CraftProfitPinnedWindow
    H.truthy(f)
    H.eq(UI.frame(), f)
    H.truthy(UI.isShown())
    H.eq(f.titleText.text, "Pinned recipes")
    H.eq(UI.parts.panel.title.text, "PINNED RECIPES")
end)

H.test("toggle opens and closes it and Escape is registered once", function()
    local T, UI = boot()
    UI.toggle()
    H.truthy(UI.isShown())
    UI.toggle()
    H.falsy(UI.isShown())
    UI.toggle()
    UI.hide()
    H.falsy(UI.isShown())
    UI.show()
    H.eq(T.env.UISpecialFrames, { "CraftProfitPinnedWindow" })
end)

H.test("each pin is a row with its difficulty colour and its value, most profitable first", function()
    -- Item 999 is not known to the game: recipe 2 has no value.
    local T, UI = boot({ pins = { raw(2, 999, "easy"), raw(1, 100, "optimal") } })
    local Colors, C = T.ns.Colors, T.ns.Controller
    stock(T)
    UI.show()
    local rows = UI.parts.rows
    H.eq(shownIDs(UI), { 1, 2 })
    H.eq(rows[1].name.text, "R1")
    local net = C.evaluate(T.env.CraftProfitCharDB.pins[2]).net
    H.truthy(net > 0)
    H.eq(rows[1].value.text, C.fmt(net))
    -- No value for item 999: unknown, never an error.
    H.eq(rows[2].value.text, "?")
    local names, values = {}, {}
    for i = 1, 2 do
        rows[i].name.SetTextColor = function(_, r, g, b, a) names[i] = { r, g, b, a } end
        rows[i].value.SetTextColor = function(_, r, g, b, a) values[i] = { r, g, b, a } end
    end
    UI.refresh()
    H.eq(names[1], Colors.FIXED.optimal)
    H.eq(names[2], Colors.FIXED.easy)
    H.eq(values[1], Colors.FIXED.profit)
    H.eq(values[2], Colors.text("muted"))
    H.falsy(rows[3].shown)
    H.eq(UI.parts.empty.shown, false)
end)

H.test("the row values are the pinned list's own (PinsUI.rowValue)", function()
    local T, UI = boot({ pins = { raw(1, 100, "optimal"), raw(2, 101, "easy") } })
    stock(T)
    UI.show()
    local P = T.ns.PinsUI
    for _, byPoint in ipairs({ false, true }) do
        if byPoint then T.ns.Controller.toggleSort() end
        local data = T.ns.Controller.pinsData()
        H.eq(data.byPoint, byPoint)
        for i, item in ipairs(data.items) do
            local text = P.rowValue(item, byPoint)
            H.eq(UI.parts.rows[i].value.text, text)
            H.eq(UI.parts.rows[i].recipeID, item.recipe.recipeID)
        end
    end
end)

H.test("the x unpins the recipe, refreshes every view and selects nothing", function()
    local T, UI = boot({ pins = { raw(1, 100, "optimal"), raw(2, 101, "easy") } })
    local C = T.ns.Controller
    UI.show()
    local x = UI.parts.rows[1].unpin
    H.eq(x.kind, "Button")
    H.eq(x.recipeID, 1)
    click(x)
    H.eq(#T.env.CraftProfitCharDB.pins, 1)
    H.eq(T.env.CraftProfitCharDB.pins[1].recipeID, 2)
    H.eq(shownIDs(UI), { 2 })
    H.eq(C.currentRecipeID(), nil)
    H.falsy(T.ns.Window.isShown())
    -- The main window's pin button follows: recipe 2 selected elsewhere, then unpinned here.
    C.selectPin(2)
    H.eq(T.ns.Window.lastModel.pinned, true)
    click(UI.parts.rows[1].unpin)
    H.eq(T.ns.Window.lastModel.pinned, false)
    H.eq(C.currentRecipeID(), 2)
    H.truthy(UI.parts.empty.shown)
    H.eq(UI.parts.empty.text, "No pinned recipes. Pin a recipe from its window.")
end)

H.test("the x says Unpin in its tooltip and keeps its row lit", function()
    local T, UI = boot({ pins = { raw(1) } })
    UI.show()
    local row = UI.parts.rows[1]
    local x = row.unpin
    H.eq(x.text, "x")
    -- Without the game's title helper: plain text.
    x.scripts.OnEnter(x)
    H.truthy(T.tooltip.owner == x)
    H.eq(T.tooltip.text, "Unpin")
    H.truthy(T.tooltip.shown)
    H.truthy(row.hover.shown)
    x.scripts.OnLeave(x)
    H.falsy(T.tooltip.shown)
    H.falsy(row.hover.shown)
    -- With it: the game's tooltip title, as the minimap button.
    local titled
    T.env.GameTooltip_SetTitle = function(tip, text) titled = { tip, text } end
    T.tooltip.text = nil
    x.scripts.OnEnter(x)
    H.truthy(titled[1] == T.env.GameTooltip)
    H.eq(titled[2], "Unpin")
    H.eq(T.tooltip.text, nil)
    H.truthy(row.hover.shown)
    x.scripts.OnLeave(x)
    H.falsy(row.hover.shown)
    -- Without a tooltip object: nothing raises.
    T.env.GameTooltip = nil
    x.scripts.OnEnter(x)
    H.truthy(row.hover.shown)
    x.scripts.OnLeave(x)
end)

H.test("clicking a row selects that pin, then opens the main window on it", function()
    local T, UI = boot({ pins = { raw(1, 100), raw(2, 101) } })
    local C = T.ns.Controller
    UI.show()
    local calls = {}
    local selectPin, showMain = C.selectPin, C.showMainWindow
    C.selectPin = function(id) calls[#calls + 1] = { "select", id }; selectPin(id) end
    C.showMainWindow = function() calls[#calls + 1] = { "show" }; showMain() end
    local row = UI.parts.rows[2]
    local id = row.recipeID
    click(row)
    H.eq(calls, { { "select", id }, { "show" } })
    H.eq(C.currentRecipeID(), id)
    H.truthy(T.ns.Window.isShown())
    -- The selected pin is lit in the list.
    H.truthy(row.selected.shown)
    H.falsy(UI.parts.rows[1].selected.shown)
end)

H.test("a row click opens the main window with the AH and profession window closed, prices missing", function()
    local T, UI = boot({ pins = { raw(1, 101) } })
    UI.show()
    H.falsy(T.ns.AH.isOpen)
    click(UI.parts.rows[1])
    H.truthy(T.ns.Window.isShown())
    H.eq(T.ns.Controller.currentRecipeID(), 1)
    H.eq(T.ns.Window.lastModel.title, "R1")
end)

H.test("dragging a row or its x moves the window and the click that ends it does nothing", function()
    local T, UI = boot({ pins = { raw(1), raw(2) } })
    UI.show()
    local moved = 0
    UI.frame().StartMoving = function() moved = moved + 1 end
    for _, button in ipairs({ UI.parts.rows[1], UI.parts.rows[1].unpin }) do
        button.scripts.OnMouseDown(button, "LeftButton")
        button.scripts.OnDragStart(button)
        click(button)
    end
    H.eq(moved, 2)
    H.eq(#T.env.CraftProfitCharDB.pins, 2)
    H.eq(T.ns.Controller.currentRecipeID(), nil)
    H.falsy(T.ns.Window.isShown())
end)

H.test("the sort button toggles the sort and relabels itself", function()
    local T, UI = boot({ pins = { raw(1) } })
    UI.show()
    local sort = UI.parts.sort
    H.eq(sort.text, "Sort: profit")
    click(sort)
    H.eq(T.env.CraftProfitCharDB.sortMode, "point")
    H.eq(sort.text, "Sort: cost/point")
    click(sort)
    H.eq(T.env.CraftProfitCharDB.sortMode, "net")
    H.eq(sort.text, "Sort: profit")
end)

H.test("the sort button spans the strip, the window is as wide as the leveling window", function()
    local T, UI = boot()
    UI.show()
    local Native, Layout = T.ns.Native, T.ns.Layout
    H.eq(UI.WIDTH, T.ns.LevelingUI.WIDTH)
    H.eq(UI.frame().width, UI.WIDTH)
    local sort = UI.parts.sort
    H.eq(sort.width, UI.INNER_WIDTH)
    H.eq(sort.points[1][1], "TOPLEFT")
    H.eq(sort.points[2][1], "TOPRIGHT")
    local sections = Native.BUTTON_H + 14 + Layout.panelHeight(12, 18) + 8 * 2
    H.eq(UI.frame().height, Native.INSET_TOP + Native.INSET_BOTTOM + Native.CONTENT_PAD * 2 + sections)
end)

H.test("with no pin the window says how to pin one and shows no row", function()
    local _, UI = boot()
    UI.show()
    H.truthy(UI.parts.empty.shown)
    H.eq(UI.parts.empty.text, "No pinned recipes. Pin a recipe from its window.")
    H.eq(shownIDs(UI), {})
    H.falsy(UI.parts.bar.frame.shown)
end)

H.test("unpinning at the bottom of a scrolled list clamps the offset and moves the bar", function()
    local T, UI = boot({ pins = manyPins(20) })
    UI.show()
    local p = UI.parts
    p.bar.onScroll(8)
    H.eq(p.bar.offset, 8)
    H.eq(p.rows[12].shown, true)
    local last = p.rows[12].recipeID
    click(p.rows[12].unpin)
    H.eq(#T.env.CraftProfitCharDB.pins, 19)
    H.eq(T.ns.DB.pinIndex(T.env.CraftProfitCharDB, last), nil)
    H.eq(p.bar.offset, 7)
    H.eq(p.bar.total, 19)
    H.truthy(p.rows[12].shown)
    H.eq(T.ns.Controller.currentRecipeID(), nil)
    H.falsy(T.ns.Window.isShown())
    -- Down to the twelve that fit: the bar goes away, the list starts at the top.
    for _ = 1, 7 do click(p.rows[1].unpin) end
    H.eq(p.bar.offset, 0)
    H.falsy(p.bar.frame.shown)
end)

H.test("forty pins scroll with the wheel and the native bar", function()
    local T, UI = boot({ pins = manyPins(40) })
    H.eq(#T.env.CraftProfitCharDB.pins, 40)
    UI.show()
    local p = UI.parts
    H.truthy(p.bar.frame.shown)
    H.eq(p.bar.total, 40)
    H.eq(p.bar.visible, 12)
    H.eq(#shownIDs(UI), 12)
    local first = p.rows[1].recipeID
    UI.frame().scripts.OnMouseWheel(UI.frame(), -1)
    H.eq(p.bar.offset, 1)
    H.eq(p.rows[1].recipeID ~= first, true)
    p.bar.onScroll(999)
    H.eq(p.bar.offset, 28)
    UI.frame().scripts.OnMouseWheel(UI.frame(), 1)
    H.eq(p.bar.offset, 27)
    for _ = 1, 50 do UI.frame().scripts.OnMouseWheel(UI.frame(), 1) end
    H.eq(p.bar.offset, 0)
end)

H.test("refresh does nothing while the window is hidden and follows pins changed elsewhere", function()
    local T, UI = boot({ pins = { raw(1) } })
    local C = T.ns.Controller
    local calls = 0
    local pinsData = C.pinsData
    C.pinsData = function() calls = calls + 1; return pinsData() end
    C.refresh()
    H.eq(calls, 0)
    UI.show()
    UI.hide()
    calls = 0
    C.refresh()
    H.eq(calls, 0)
    UI.show()
    H.eq(shownIDs(UI), { 1 })
    -- Pinned from the main window while this one is open.
    C.setRecipe(T.ns.Recipes.normalize(raw(7)), "profession")
    C.togglePin()
    H.eq(#shownIDs(UI), 2)
    C.togglePin()
    H.eq(shownIDs(UI), { 1 })
end)

H.test("the age line follows the prices of the pins: muted when fresh, stale when none or old", function()
    local T, UI = boot({ pins = { raw(1) } })
    local Colors = T.ns.Colors
    UI.show()
    local colour
    UI.parts.age.SetTextColor = function(_, r, g, b, a) colour = { r, g, b, a } end
    UI.refresh()
    H.eq(UI.parts.age.text, "Prices: never scanned")
    H.eq(colour, Colors.FIXED.stale)
    -- Searched prices (no full scan): the oldest one the pin uses gives the age.
    stock(T)
    T.ns.Prices.store(T.ns.Controller.market(), 2, 50, 10, 1700000000 - 300)
    UI.refresh()
    H.eq(UI.parts.age.text, "Prices: 5m ago")
    H.eq(colour, Colors.text("muted"))
    -- A recent full scan does not make an old price of the pin look fresh.
    T.ns.Controller.market().snapshotTime = 1700000000 - 10
    T.ns.Prices.store(T.ns.Controller.market(), 1, 100, 10, 1700000000 - 7200)
    UI.refresh()
    H.eq(UI.parts.age.text, "Prices: 2h ago")
    H.eq(colour, Colors.FIXED.stale)
end)

H.test("long names are cut before the value, the value before the x", function()
    local made = {}
    local _, UI = boot({ pins = { raw(1) }, onFrame = function(f)
        f.CreateFontString = function()
            local fs = W.frame()
            fs.points = {}
            fs.SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end
            fs.SetWidth = function(self, w) self.width = w end
            fs.SetWordWrap = function(self, v) self.wrap = v end
            made[#made + 1] = fs
            return fs
        end
    end })
    UI.show()
    local row = UI.parts.rows[1]
    local x = row.unpin
    H.eq({ x.width, x.height }, { 16, 16 })
    H.eq(x.points[1], { "RIGHT", row, "RIGHT", -2, 0 })
    H.eq(row.value.points[1], { "RIGHT", x, "LEFT", -6, 0 })
    H.eq(row.value.width, UI.VALUE_W)
    H.eq(row.value.wrap, false)
    H.eq(row.name.points[2], { "RIGHT", row.value, "LEFT", -8, 0 })
    H.eq(row.name.wrap, false)
end)

H.test("the window opens left of centre, a drag saves its place and the next login reopens it there", function()
    local T, UI, named = boot()
    UI.show()
    local f = named.CraftProfitPinnedWindow
    H.eq(f.points[#f.points], { "CENTER", T.env.UIParent, "CENTER", -260, 0 })
    f.scripts.OnDragStop(f)
    H.eq(T.env.CraftProfitDB.settings.pinsWindow, { x = 100, y = 700 })
    UI.hide()
    UI.show()
    H.eq(f.points[#f.points], { "TOPLEFT", T.env.UIParent, "BOTTOMLEFT", 100, 700 })

    local T2, UI2, named2 = boot({ saved = { settings = { pinsWindow = { x = 40, y = 500 } } } })
    UI2.show()
    local f2 = named2.CraftProfitPinnedWindow
    H.eq(f2.points[#f2.points], { "TOPLEFT", T2.env.UIParent, "BOTTOMLEFT", 40, 500 })
    -- A hostile save is dropped: back to the default place.
    local T3, UI3, named3 = boot({ saved = { settings = { pinsWindow = { x = 0 / 0, y = 500 } } } })
    UI3.show()
    local f3 = named3.CraftProfitPinnedWindow
    H.eq(f3.points[#f3.points], { "CENTER", T3.env.UIParent, "CENTER", -260, 0 })
end)

H.test("the pinned window is built from the native kit", function()
    local _, UI = boot({ pins = { raw(1) } })
    UI.show()
    local p = UI.parts
    H.eq(type(rawget(UI.frame(), "setTitle")), "function")
    H.eq(UI.frame().template, "ButtonFrameTemplate")
    H.eq(p.sort.template, "UIPanelButtonTemplate")
    H.eq(p.panel.inset.template, "InsetFrameTemplate")
    H.eq(p.rows[1].kind, "Button")
    H.truthy(rawget(p.bar, "trackAtlases") ~= nil)
    H.eq(p.bar.frame.scripts.OnUpdate, nil)
end)

H.test("the window reads in French", function()
    local _, UI, named = boot({ locale = "frFR", pins = { raw(1) } })
    UI.show()
    H.eq(named.CraftProfitPinnedWindow.titleText.text, "Recettes épinglées")
    H.eq(UI.parts.panel.title.text, "RECETTES ÉPINGLÉES")
    H.eq(UI.parts.sort.text, "Tri : gain")
end)

H.test("pinned window rows follow the game's language: the client's recipe name, else the item's", function()
    local pin = raw(1, 100, "optimal", "Epee")
    pin.locale = "frFR"
    local T, UI = boot({ pins = { pin } })
    UI.show()
    H.eq(UI.parts.rows[1].name.text, "Item100")
    T.env.C_TradeSkillUI = { GetRecipeInfo = function(id) return { recipeID = id, name = "Sword of R" .. id } end }
    UI.refresh()
    H.eq(UI.parts.rows[1].name.text, "Sword of R1")
    H.eq(T.env.CraftProfitCharDB.pins[1].name, "Sword of R1")
end)
