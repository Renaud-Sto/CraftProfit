local H = ...
local W = dofile("tests/fakewow.lua")

-- classID 0 on both outputs: disenchanting never applies, so the expected
-- item lists do not depend on the contents of the disenchant table.
local ITEMS = {
    [100] = { quality = 2, ilvl = 15, sellPrice = 200, classID = 0, bindType = 2 },
    [101] = { quality = 1, ilvl = 1, sellPrice = 10, classID = 0, bindType = 2 },
}

local function raw(id, output, reagents)
    return { recipeID = id, name = "R" .. id, difficulty = 1, outputItemID = output, reagents = reagents }
end

local function boot()
    local T = W.boot(H, { items = ITEMS })
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    local pins = T.env.CraftProfitCharDB.pins
    T.ns.DB.pinAdd(T.env.CraftProfitCharDB, raw(1, 100, { { itemID = 1, qty = 2 }, { itemID = 2, qty = 1 } }))
    T.ns.DB.pinAdd(T.env.CraftProfitCharDB, raw(2, 101, { { itemID = 2, qty = 3 }, { itemID = 3, qty = 1 } }))
    -- The AH adapter is replaced by a recorder: the queue's `send` goes through it.
    T.sent = {}
    T.ns.AH.search = function(id) T.sent[#T.sent + 1] = id; return true end
    return T, pins
end

local listing = { { unit = 10, qty = 1 }, { unit = 30, qty = 1 }, { unit = 20, qty = 1 } }

H.test("wantedFor lists each needed item once across all pins", function()
    local T = boot()
    local ids = T.ns.PinsUI.wantedFor(T.env.CraftProfitCharDB.pins, T.ns.Controller.itemInfo, T.ns.Data.Disenchant.lookup)
    H.eq(ids, { 1, 2, 100, 3, 101 })
end)

H.test("searching with the AH closed only reports it", function()
    local T = boot()
    T.ns.PinsUI.startSearch()
    H.eq(T.ns.PinsUI.status, "Open the auction house first")
    H.eq(T.sent, {})
    H.eq(T.ns.PinsUI.state, "idle")
end)

H.test("a search walks every item and stores the median prices", function()
    local T = boot()
    local P = T.ns.PinsUI
    T.ns.AH.isOpen = true
    P.startSearch()
    H.eq(P.state, "running")
    H.eq(T.sent, { 1 })
    for _, id in ipairs({ 1, 2, 100, 3, 101 }) do
        P.onSearchResults(id, listing)
    end
    H.eq(T.sent, { 1, 2, 100, 3, 101 })
    H.eq(P.state, "done")
    H.eq(P.status, "Updated 5 prices")
    H.eq(T.ns.Controller.market().prices[1][1], 20)
    H.eq(T.ns.Controller.market().prices[101][1], 20)
    H.truthy(T.tickers[#T.tickers].cancelled)
end)

H.test("an item that never answers is reported at the end", function()
    local T = boot()
    local P = T.ns.PinsUI
    T.ns.AH.isOpen = true
    P.startSearch()
    P.onSearchResults(1, listing)
    -- 100 never answers; the ticker times it out after 6 s.
    for _, id in ipairs({ 2 }) do P.onSearchResults(id, listing) end
    T.clock = T.clock + 7
    T.tickers[#T.tickers].fn()
    P.onSearchResults(3, listing)
    P.onSearchResults(101, listing)
    -- Asked a second time, and silent again.
    H.eq(P.state, "running")
    H.eq(P.status, "Retrying 0/1")
    H.eq(T.sent, { 1, 2, 100, 3, 101, 100 })
    T.clock = T.clock + 7
    T.tickers[#T.tickers].fn()
    H.eq(P.state, "done")
    H.eq(P.status, "Updated 4 of 5 prices · no answer: Item100, try again")
    H.eq(T.ns.Controller.market().prices[100], nil)
end)

H.test("closing the AH cancels a running search", function()
    local T = boot()
    local P = T.ns.PinsUI
    T.ns.AH.isOpen = true
    P.startSearch()
    P.onAHOpen(false)
    H.eq(P.state, "cancelled")
    H.eq(P.status, "Search cancelled")
    P.onSearchResults(1, listing)
    H.eq(T.ns.Controller.market().prices[1], nil)
end)

H.test("a second search does not start while one is running", function()
    local T = boot()
    local P = T.ns.PinsUI
    T.ns.AH.isOpen = true
    P.startSearch()
    P.startSearch()
    H.eq(T.sent, { 1 })
end)

H.test("results for items nobody asked about are ignored", function()
    local T = boot()
    T.ns.PinsUI.onSearchResults(1, listing)
    H.eq(T.ns.Controller.market().prices[1], nil)
end)

H.test("searching with no pins does nothing", function()
    local T = W.boot(H, { items = ITEMS })
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    T.ns.AH.isOpen = true
    T.ns.PinsUI.startSearch()
    H.eq(T.ns.PinsUI.state, "idle")
end)

H.test("scan reports a closed AH, a cooldown and a started scan", function()
    local T = boot()
    local P = T.ns.PinsUI
    P.scan()
    H.eq(P.status, "Open the auction house first")
    T.ns.AH.isOpen = true
    T.ns.AH.requestSnapshot = function() return false, "cooldown", 600 end
    P.scan()
    H.eq(P.status, "Full scan available in 10m")
    T.ns.AH.requestSnapshot = function() return true end
    P.scan()
    H.eq(P.status, "Scanning the auction house...")
end)

H.test("a finished scan stores prices and reports the count", function()
    local T = boot()
    local agg = T.ns.Prices.newAggregator()
    agg.add(1, 100, 1)
    agg.add(2, 50, 1)
    T.ns.Controller.onSnapshot(agg)
    H.eq(T.ns.PinsUI.status, "Scan complete: 2 items priced")
    H.eq(T.ns.Controller.market().prices[1][1], 100)
    H.truthy(T.ns.Controller.market().snapshotTime)
end)

H.test("opening the AH shows the pins and selects the first one", function()
    local T = boot()
    T.ns.AH.isOpen = true
    T.ns.Controller.onAHOpen(true)
    H.eq(T.ns.Controller.currentRecipeID(), 1)
    H.truthy(T.ns.Window.isShown())
    H.truthy(T.ns.Window.pinsHost():IsShown())
    T.ns.Controller.onAHOpen(false)
    H.falsy(T.ns.Window.isShown())
end)

H.test("selecting a pinned recipe shows it in the window", function()
    local T = boot()
    T.ns.AH.isOpen = true
    T.ns.Controller.onAHOpen(true)
    T.ns.Controller.selectPin(2)
    H.eq(T.ns.Controller.currentRecipeID(), 2)
    T.ns.Controller.selectPin(999)
    H.eq(T.ns.Controller.currentRecipeID(), 2)
end)

H.test("the pins list refreshes without errors when empty or large", function()
    local T = W.boot(H, { items = ITEMS })
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    T.ns.PinsUI.refresh()
    for i = 1, 12 do
        T.ns.DB.pinAdd(T.env.CraftProfitCharDB, raw(i, 100, { { itemID = 1, qty = 1 } }))
    end
    T.ns.PinsUI.refresh()
end)

-- Fix wave item 5
H.test("an empty AH listing counts as answered with no listing", function()
    local T = boot()
    local P = T.ns.PinsUI
    T.ns.AH.isOpen = true
    P.startSearch()
    P.onSearchResults(1, {})
    for _, id in ipairs({ 2, 100, 3, 101 }) do P.onSearchResults(id, listing) end
    -- The retry finds no listing either.
    P.onSearchResults(1, {})
    H.eq(P.state, "done")
    H.eq(P.status, "Updated 4 of 5 prices · no listing: #1 (nobody is selling them now)")
    P.startSearch()
    for _, id in ipairs({ 1, 2, 100, 3, 101 }) do P.onSearchResults(id, listing) end
    H.eq(P.status, "Updated 5 prices")
end)

H.test("a scan the server never answers reports it, a scan it answers does not", function()
    local T = boot()
    local P = T.ns.PinsUI
    T.ns.AH.isOpen = true
    T.ns.AH.requestSnapshot = function() return true end
    P.scan()
    T.run()
    H.eq(P.status, "No reply from the server. A scan may be on its 15 minute cooldown")
    P.scan()
    T.ns.AH.onEvent("REPLICATE_ITEM_LIST_UPDATE")
    T.run()
    H.eq(P.status, "Scanning the auction house...")
end)

H.test("orderedPins sorts by net (most profitable first) or by cost per point (cheapest first)", function()
    local T = boot()
    local P = T.ns.PinsUI
    local pins = { { recipeID = 1 }, { recipeID = 2 }, { recipeID = 3 }, { recipeID = 4 }, { recipeID = 5 } }
    local results = {
        [1] = { net = -500, perPoint = { cost = 900, chance = 0.25 } },
        [2] = { net = 40, perPoint = { cost = nil, chance = 0 } },
        [3] = { net = -20, perPoint = { cost = 100, chance = 1 } },
        [4] = { perPoint = {} },
        [5] = { net = 40, perPoint = { cost = -50, chance = 1 } },
    }
    local function evaluate(recipe) return results[recipe.recipeID] end
    local function ids(list)
        local out = {}
        for i, item in ipairs(list) do out[i] = item.recipe.recipeID end
        return out
    end
    H.eq(ids(P.orderedPins(pins, "net", evaluate)), { 2, 5, 3, 1, 4 })
    H.eq(ids(P.orderedPins(pins, "point", evaluate)), { 5, 3, 1, 2, 4 })
    H.eq(P.orderedPins(pins, "point", evaluate)[1].result, results[5])
end)

H.test("the pins list refreshes in both sort modes without errors", function()
    local T = boot()
    T.ns.AH.isOpen = true
    T.ns.Controller.onAHOpen(true)
    T.ns.Controller.toggleSort()
    T.ns.PinsUI.refresh()
    T.ns.Controller.toggleSort()
    T.ns.PinsUI.refresh()
end)

local function openList(T)
    T.ns.AH.isOpen = true
    T.ns.Controller.onAHOpen(true)
    return T.ns.PinsUI.parts
end

H.test("pinned names take the colour of their difficulty, a missing difficulty keeps the text colour", function()
    local T = boot()
    local Colors = T.ns.Colors
    local pins = T.env.CraftProfitCharDB.pins
    pins[1].difficulty = "optimal"
    pins[2].difficulty = nil
    local parts = openList(T)
    local colours = {}
    for i = 1, 2 do
        parts.rows[i].name.SetTextColor = function(_, r, g, b, a) colours[i] = { r, g, b, a } end
    end
    T.ns.PinsUI.refresh()
    local byID = {}
    for i = 1, 2 do byID[parts.rows[i].recipeID] = colours[i] end
    H.eq(byID[1], Colors.FIXED.optimal)
    -- The game's plain text colour (white in the fake, which has no colour objects).
    H.eq(byID[2], Colors.text("main"))
end)

H.test("each difficulty has its colour in the pinned list", function()
    local T = boot()
    local Colors = T.ns.Colors
    local pins = T.env.CraftProfitCharDB.pins
    local parts = openList(T)
    local last
    parts.rows[1].name.SetTextColor = function(_, r, g, b, a) last = { r, g, b, a } end
    for _, name in ipairs({ "optimal", "medium", "easy", "trivial" }) do
        for _, pin in ipairs(pins) do pin.difficulty = name end
        T.ns.PinsUI.refresh()
        H.eq(last, Colors.FIXED[name])
    end
end)

H.test("the scroll bar shows only when there are more pins than rows and follows the offset", function()
    local T = boot()
    local parts = openList(T)
    H.falsy(parts.bar.frame.shown)
    for i = 3, 12 do
        T.ns.DB.pinAdd(T.env.CraftProfitCharDB, raw(i, 100, { { itemID = 1, qty = 1 } }))
    end
    T.ns.PinsUI.refresh()
    H.truthy(parts.bar.frame.shown)
    H.eq(parts.bar.total, 12)
    H.eq(parts.bar.visible, 6)
    H.eq(parts.bar.offset, 0)
    parts.bar.onScroll(4)
    H.eq(parts.bar.offset, 4)
    parts.bar.onScroll(99)
    H.eq(parts.bar.offset, 6)
end)

H.test("the mouse wheel scrolls the list and the bar, and removing pins clamps the offset", function()
    local T = boot()
    local parts = openList(T)
    for i = 3, 12 do
        T.ns.DB.pinAdd(T.env.CraftProfitCharDB, raw(i, 100, { { itemID = 1, qty = 1 } }))
    end
    T.ns.PinsUI.refresh()
    local host = T.ns.Window.pinsHost()
    host.scripts.OnMouseWheel(host, -1)
    host.scripts.OnMouseWheel(host, -1)
    H.eq(parts.bar.offset, 2)
    host.scripts.OnMouseWheel(host, 1)
    H.eq(parts.bar.offset, 1)
    for _ = 1, 7 do table.remove(T.env.CraftProfitCharDB.pins) end
    T.ns.PinsUI.refresh()
    H.eq(parts.bar.offset, 0)
    H.falsy(parts.bar.frame.shown)
end)

H.test("the panel height follows the number of pinned rows shown and the host height follows the panel", function()
    local T = boot()
    local Layout, Window = T.ns.Layout, T.ns.Window
    local parts = openList(T)
    H.eq(parts.panel.frame.height, Layout.panelHeight(2, 18))
    for i = 3, 12 do
        T.ns.DB.pinAdd(T.env.CraftProfitCharDB, raw(i, 100, { { itemID = 1, qty = 1 } }))
    end
    T.ns.PinsUI.refresh()
    H.eq(parts.panel.frame.height, Layout.panelHeight(6, 18))
    local host = T.ns.Window.pinsHost()
    H.eq(host.height, Layout.panelHeight(6, 18) + Window.GAP + T.ns.PinsUI.FOOTER_H)
end)

H.test("the host is the panel, a gap and a footer with two lines of status, and the window grows by it", function()
    local T = boot()
    local Layout, P, Window = T.ns.Layout, T.ns.PinsUI, T.ns.Window
    -- Two native buttons with their 6 px gaps, then two lines of the small font.
    H.eq(T.ns.Native.BUTTON_H, 22)
    H.eq(P.FOOTER_H, 22 * 2 + 6 * 2 + 28)
    openList(T)
    local host = T.ns.Window.pinsHost()
    H.eq(host.height, Layout.panelHeight(2, 18) + Window.GAP + P.FOOTER_H)
    local frame = T.ns.Window.frame()
    H.truthy(host:IsShown())
    local shownHeight = frame.height
    P.onAHOpen(false)
    H.falsy(host:IsShown())
    local hiddenHeight = frame.height
    H.eq(shownHeight - hiddenHeight, Window.GAP + host.height)
end)

H.test("the sort button reads the sort mode and toggles it", function()
    local T = boot()
    local parts = openList(T)
    H.eq(parts.sort.text, "Sort: profit")
    parts.sort.scripts.OnClick(parts.sort)
    H.eq(parts.sort.text, "Sort: cost/point")
end)

H.test("the three buttons read their text and keep their actions", function()
    local T = boot()
    local parts = openList(T)
    H.eq(parts.search.text, "Refresh pinned")
    H.eq(parts.scan.text, "Scan AH")
    H.eq(parts.level.text, "Leveling")
    parts.search.scripts.OnClick(parts.search)
    H.eq(T.ns.PinsUI.state, "running")
    parts.level.scripts.OnClick(parts.level)
    H.truthy(T.ns.LevelingUI.isShown())
end)

H.test("clicking a pinned row selects that recipe", function()
    local T = boot()
    local parts = openList(T)
    local id2
    for i = 1, 2 do if parts.rows[i].recipeID == 2 then id2 = parts.rows[i] end end
    id2.scripts.OnClick(id2)
    H.eq(T.ns.Controller.currentRecipeID(), 2)
end)

H.test("an unknown value is drawn in the game's muted colour, a gain and a loss in theirs", function()
    local T = boot()
    local Colors = T.ns.Colors
    for _, pin in ipairs(T.env.CraftProfitCharDB.pins) do pin.difficulty = nil end
    local parts = openList(T)
    local row = parts.rows[1]
    -- No listing was recorded, so the value is unknown.
    H.eq(row.value.text, "?")
    local value
    row.value.SetTextColor = function(_, r, g, b, a) value = { r, g, b, a } end
    T.ns.PinsUI.refresh()
    H.eq(value, Colors.text("muted"))
    T.env.DISABLED_FONT_COLOR = { GetRGBA = function() return 0.4, 0.4, 0.4, 1 end }
    T.ns.PinsUI.refresh()
    H.eq(value, { 0.4, 0.4, 0.4, 1 })
end)

-- A boot whose character already has a pin when the addon loads, as in the game.
local function bootWithSavedPin()
    local T = W.boot(H, { items = ITEMS })
    T.env.CraftProfitCharDB = {}
    T.ns.DB.initChar(T.env.CraftProfitCharDB)
    T.ns.DB.pinAdd(T.env.CraftProfitCharDB, raw(1, 100, { { itemID = 1, qty = 2 } }))
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    return T
end

H.test("loading the addon with a pin does not touch the market until the AH opens", function()
    local T = bootWithSavedPin()
    -- Never refreshed: the row has no recipe yet (rawget, fake frames answer any field).
    H.eq(rawget(T.ns.PinsUI.parts.rows[1], "recipeID"), nil)
    H.eq(next(T.env.CraftProfitDB.markets), nil)
    openList(T)
    H.eq(T.ns.PinsUI.parts.rows[1].recipeID, 1)
    H.truthy(next(T.env.CraftProfitDB.markets) ~= nil)
end)

H.test("pins are not evaluated while the list is hidden", function()
    -- Pins stored before the addon loads, as in the game: nothing evaluates them (which
    -- would open the market too early) until the AH shows the list.
    local T = W.boot(H, { items = ITEMS })
    T.env.CraftProfitCharDB = {}
    T.ns.DB.initChar(T.env.CraftProfitCharDB)
    T.ns.DB.pinAdd(T.env.CraftProfitCharDB, raw(1, 100, { { itemID = 1, qty = 2 } }))
    local Controller = T.ns.Controller
    local evaluate, calls = Controller.evaluate, 0
    Controller.evaluate = function(...) calls = calls + 1; return evaluate(...) end
    Controller.onEvent("ADDON_LOADED", "CraftProfit")
    H.eq(calls, 0)
    openList(T)
    H.truthy(calls > 0)
end)

H.test("the pinned panel title is the capitalised panel key with the count over the limit", function()
    local T = boot()
    local parts = openList(T)
    H.eq(parts.panel.title.text, "PINNED RECIPES (2/20)")
    local F = W.boot(H, { items = ITEMS, locale = "frFR" })
    F.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    H.eq(F.ns.PinsUI.parts.panel.title.text, "RECETTES ÉPINGLÉES (0/20)")
    local E = W.boot(H, { items = ITEMS, locale = "esES" })
    E.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    H.eq(E.ns.PinsUI.parts.panel.title.text, "RECETAS FIJADAS (0/20)")
end)

H.test("the pinned list title counts 0, 1 and 21 pins and follows pin, unpin and a limit change", function()
    local T = W.boot(H, { items = ITEMS })
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    local C = T.ns.Controller
    local parts = openList(T)
    H.eq(parts.panel.title.text, "PINNED RECIPES (0/20)")
    -- Pinned from the main window.
    C.setRecipe(T.ns.Recipes.normalize(raw(1, 100, { { itemID = 1, qty = 1 } })), "profession")
    C.togglePin()
    H.eq(parts.panel.title.text, "PINNED RECIPES (1/20)")
    C.setPinLimit(30)
    H.eq(parts.panel.title.text, "PINNED RECIPES (1/30)")
    for i = 2, 21 do T.ns.DB.pinAdd(T.env.CraftProfitCharDB, raw(i, 100, { { itemID = 1, qty = 1 } }), 30) end
    C.refresh()
    H.eq(parts.panel.title.text, "PINNED RECIPES (21/30)")
    -- Lowered below the count: the pins stay, the title says so.
    C.setPinLimit(12)
    H.eq(parts.panel.title.text, "PINNED RECIPES (21/12)")
    C.unpin(21)
    H.eq(parts.panel.title.text, "PINNED RECIPES (20/12)")
    C.togglePin()
    H.eq(parts.panel.title.text, "PINNED RECIPES (19/12)")
end)

H.test("the sort button sits two levels above the pinned panel frame", function()
    local T = W.boot(H, { items = ITEMS })
    local made = T.env.CreateFrame
    T.env.CreateFrame = function(...)
        local f = made(...)
        f.GetFrameLevel = function() return 5 end
        f.SetFrameLevel = function(self, level) self.level = level end
        return f
    end
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    H.eq(T.ns.PinsUI.parts.sort.level, 7)
end)

H.test("the pinned list is built from the native kit", function()
    local T = W.boot(H, { items = ITEMS })
    local made = {}
    local create = T.env.CreateFrame
    T.env.CreateFrame = function(kind, name, parent, template)
        local f = create(kind, name, parent, template)
        f.kind, f.template = kind, template
        made[#made + 1] = f
        return f
    end
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    local parts = T.ns.PinsUI.parts
    -- Native panel (a game inset), game buttons, native rows and scroll bar.
    H.eq(parts.panel.inset.template, "InsetFrameTemplate")
    for _, key in ipairs({ "sort", "search", "scan", "level" }) do
        H.eq(parts[key].template, "UIPanelButtonTemplate")
    end
    H.eq(parts.sort.height, 18)
    H.eq(parts.rows[1].kind, "Button")
    -- Native rows keep the window's drag (Native.forwardDrag registers it).
    H.eq(type(parts.rows[1].scripts.OnDragStart), "function")
    H.truthy(rawget(parts.bar, "trackAtlases") ~= nil)
    -- No per-frame work while nobody drags the bar.
    H.eq(parts.bar.frame.scripts.OnUpdate, nil)
end)

H.test("dragging a pinned row moves the window and the click that ends it selects nothing", function()
    local T = boot()
    local parts = openList(T)
    local frame = T.ns.Window.frame()
    local moved = false
    frame.StartMoving = function() moved = true end
    local row
    for i = 1, 2 do if parts.rows[i].recipeID == 2 then row = parts.rows[i] end end
    row.scripts.OnMouseDown(row, "LeftButton")
    row.scripts.OnDragStart(row)
    H.truthy(moved)
    row.scripts.OnClick(row)
    H.eq(T.ns.Controller.currentRecipeID(), 1)
    row.scripts.OnMouseDown(row, "LeftButton")
    row.scripts.OnClick(row)
    H.eq(T.ns.Controller.currentRecipeID(), 2)
end)

H.test("rowValue gives the text and colour each pinned row shows, in both sort modes", function()
    local T = boot()
    T.env.GetMoneyString = function(c) return "<" .. c .. ">" end
    local P, Colors, C = T.ns.PinsUI, T.ns.Colors, T.ns.Controller
    local market = C.market()
    T.ns.Prices.store(market, 1, 100, 10, 1699999940)
    T.ns.Prices.store(market, 2, 50, 10, 1699999940)
    T.ns.Prices.store(market, 100, 1000, 10, 1699999940)
    local parts = openList(T)
    local function shown()
        local out = {}
        for i = 1, 2 do
            local row, colour = parts.rows[i], nil
            row.value.SetTextColor = function(_, r, g, b, a) colour = { r, g, b, a } end
            out[i] = row
            row.colourOf = function() return colour end
        end
        P.refresh()
        local list = {}
        for i, row in ipairs(out) do list[i] = { row.recipeID, row.value.text, row.colourOf() } end
        return list
    end
    -- Recipe 1: reagents 2 x 100 + 50 = 250, sold 1000 less 5 % = 950: net +700. Recipe 2
    -- needs item 3, never priced: unknown, last.
    H.eq(shown(), {
        { 1, "<700>", Colors.FIXED.profit },
        { 2, "?", Colors.text("muted") },
    })
    -- Cost per point: medium (difficulty 1) is 75 %, (250 - 950) / 0.75 = -933: a gain.
    C.toggleSort()
    H.eq(shown(), {
        { 1, "+<933>/pt", Colors.FIXED.profit },
        { 2, "?", Colors.text("muted") },
    })
    -- rowValue gives the same text and colour for those pins.
    local ordered = P.orderedPins(T.env.CraftProfitCharDB.pins, "point", C.evaluate)
    H.eq({ P.rowValue(ordered[1], true) }, { "+<933>/pt", Colors.FIXED.profit })
    H.eq({ P.rowValue(ordered[2], true) }, { "?", Colors.text("muted") })
    -- The three cases of the profit view, and the point view's own text.
    local fmt = C.fmt
    H.eq({ P.rowValue({ result = { net = 700 } }, false) }, { fmt(700), Colors.FIXED.profit })
    H.eq({ P.rowValue({ result = { net = 0 } }, false) }, { fmt(0), Colors.FIXED.profit })
    H.eq({ P.rowValue({ result = { net = -5 } }, false) }, { fmt(-5), Colors.FIXED.loss })
    H.eq({ P.rowValue({ result = {} }, false) }, { "?", Colors.text("muted") })
    H.eq({ P.rowValue({ result = { perPoint = { chance = 1, cost = 40 } } }, true) },
        { fmt(40) .. "/pt", Colors.FIXED.loss })
    H.eq({ P.rowValue({ result = { perPoint = { chance = 1, cost = -40 } } }, true) },
        { "+" .. fmt(40) .. "/pt", Colors.FIXED.profit })
    H.eq({ P.rowValue({ result = { net = 700 } }, true) }, { "?", Colors.text("muted") })
end)

H.test("pinned rows show the name in the game's current language and update the stored one", function()
    local T = boot()
    local pins = T.env.CraftProfitCharDB.pins
    -- Pinned in a French client; the fake client is English and knows the items.
    pins[1].name, pins[1].locale = "Epee", "frFR"
    local parts = openList(T)
    T.ns.PinsUI.refresh()
    local byID = {}
    for i = 1, 2 do byID[parts.rows[i].recipeID] = parts.rows[i].name.text end
    H.eq(byID[1], "Item100")
    H.eq(pins[1].name, "Item100")
    H.eq(pins[1].locale, "enUS")
    -- Pinned without a language tag (an older save) in the same way.
    H.eq(byID[2], "Item101")
end)

H.test("forty pins saved before login load whole and scroll in the list under the main window", function()
    local T = W.boot(H, { items = ITEMS })
    T.env.CraftProfitDB = { settings = { maxPins = 40 } }
    local saved = {}
    for i = 1, 40 do saved[i] = raw(i, 100, { { itemID = 1, qty = 1 } }) end
    T.env.CraftProfitCharDB = { pins = saved }
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    H.eq(#T.env.CraftProfitCharDB.pins, 40)
    local parts = openList(T)
    H.truthy(parts.bar.frame.shown)
    H.eq(parts.bar.total, 40)
    H.eq(parts.bar.visible, 6)
    local host = T.ns.Window.pinsHost()
    host.scripts.OnMouseWheel(host, -1)
    H.eq(parts.bar.offset, 1)
    -- Past the end: clamped to the last six rows.
    parts.bar.onScroll(999)
    H.eq(parts.bar.offset, 34)
    for _ = 1, 50 do host.scripts.OnMouseWheel(host, -1) end
    H.eq(parts.bar.offset, 34)
    H.truthy(parts.rows[6].shown)
    H.truthy(parts.rows[6].recipeID ~= nil)
    -- Unpinning from the bottom of the scrolled list clamps the offset.
    T.ns.Controller.unpin(parts.rows[6].recipeID)
    H.eq(#T.env.CraftProfitCharDB.pins, 39)
    H.eq(parts.bar.offset, 33)
    for _ = 1, 50 do host.scripts.OnMouseWheel(host, 1) end
    H.eq(parts.bar.offset, 0)
end)

H.test("searchSummary: every combination of answers, the counts adding up, reading right for 1 and many", function()
    local T = boot()
    local P, L = T.ns.PinsUI, T.ns.L
    local function s(ok, total, noListing, failed)
        return P.searchSummary(L, { ok = ok, total = total, noListing = noListing, failed = failed })
    end
    H.eq(s(0, 0, 0, 0), "Updated 0 prices")
    H.eq(s(5, 5, 0, 0), "Updated 5 prices")
    H.eq(s(5, 5, 2, 0), "Updated 3 of 5 prices · no listing: 2 (nobody is selling them now)")
    H.eq(s(3, 5, 0, 2), "Updated 3 of 5 prices · no answer: 2, try again")
    H.eq(s(3, 5, 1, 2), "Updated 2 of 5 prices · no listing: 1 (nobody is selling them now)"
        .. " · no answer: 2, try again")
    H.eq(s(5, 5, 5, 0), "Updated 0 of 5 prices · no listing: 5 (nobody is selling them now)")
    H.eq(s(0, 4, 0, 4), "Updated 0 of 4 prices · no answer: 4, try again")
    -- Missing counts read as 0.
    H.eq(P.searchSummary(L, {}), "Updated 0 prices")
    -- Updated + no listing + no answer = total, in every case above.
    for _, c in ipairs({ { 5, 5, 2, 0 }, { 3, 5, 1, 2 }, { 5, 5, 5, 0 }, { 0, 4, 0, 4 }, { 5, 5, 0, 0 } }) do
        local text = s(c[1], c[2], c[3], c[4])
        local updated = tonumber(text:match("^Updated (%d+)"))
        H.eq(updated + c[3] + c[4], c[2])
    end
end)

H.test("the summary reads in French and Spanish and fits the two status lines", function()
    for _, locale in ipairs({ "enUS", "frFR", "esES" }) do
        local T = W.boot(H, { items = ITEMS, locale = locale })
        T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
        local P, L, Layout = T.ns.PinsUI, T.ns.L, T.ns.Layout
        local longest = P.searchSummary(L, { ok = 38, total = 40, noListing = 12, failed = 2 })
        local lines = Layout.wrapLines(longest, 6, T.ns.Window.INNER_WIDTH)
        H.truthy(lines <= 2 or error(locale .. ": " .. longest .. " takes " .. lines .. " lines"))
        if locale == "frFR" then
            H.eq(longest, "26 prix sur 40 mis à jour · sans offre\194\160: 12 (personne n'en vend)"
                .. " · sans réponse\194\160: 2, réessayez")
            H.eq(P.searchSummary(L, { ok = 5, total = 5 }), "5 prix mis à jour")
        elseif locale == "esES" then
            H.eq(longest, "26 de 40 precios actualizados · sin ofertas: 12 (nadie las vende)"
                .. " · sin respuesta: 2, reintenta")
            H.eq(P.searchSummary(L, { ok = 5, total = 5 }), "5 precios actualizados")
        end
    end
end)

H.test("startSearch with a recipe list searches only those recipes' items", function()
    local T = boot()
    local P = T.ns.PinsUI
    T.ns.AH.isOpen = true
    local recipe = T.ns.Recipes.normalize(raw(9, 101, { { itemID = 3, qty = 1 }, { itemID = 4, qty = 2 } }))
    P.startSearch({ recipe })
    H.eq(P.state, "running")
    for _, id in ipairs({ 3, 4, 101 }) do P.onSearchResults(id, listing) end
    H.eq(T.sent, { 3, 4, 101 })
    H.eq(P.state, "done")
    H.eq(P.status, "Updated 3 prices")
    H.eq(T.ns.Controller.market().prices[1], nil)
    H.eq(T.ns.Controller.market().prices[4][1], 20)
end)

H.test("a recipe search is ignored while a pinned search runs, which carries on intact", function()
    local T = boot()
    local P = T.ns.PinsUI
    T.ns.AH.isOpen = true
    P.startSearch()
    P.onSearchResults(1, {})
    local recipe = T.ns.Recipes.normalize(raw(9, 101, { { itemID = 4, qty = 1 } }))
    P.startSearch({ recipe })
    H.eq(P.state, "running")
    for _, id in ipairs({ 2, 100, 3, 101 }) do P.onSearchResults(id, listing) end
    -- The retry of item 1 belongs to the pinned search; the recipe's item 4 is never sent.
    P.onSearchResults(1, {})
    H.eq(T.sent, { 1, 2, 100, 3, 101, 1 })
    H.eq(P.status, "Updated 4 of 5 prices · no listing: #1 (nobody is selling them now)")
end)

H.test("a pinned search right after a recipe search starts clean", function()
    local T = boot()
    local P = T.ns.PinsUI
    T.ns.AH.isOpen = true
    local recipe = T.ns.Recipes.normalize(raw(9, 101, { { itemID = 4, qty = 1 } }))
    P.startSearch({ recipe })
    P.onSearchResults(4, {})
    P.onSearchResults(101, {})
    P.onSearchResults(4, {})
    P.onSearchResults(101, {})
    H.eq(P.status, "Updated 0 of 2 prices · no listing: #4, Item101 (nobody is selling them now)")
    P.startSearch()
    H.eq(P.status, "Searching 0/5")
    for _, id in ipairs({ 1, 2, 100, 3, 101 }) do P.onSearchResults(id, listing) end
    H.eq(P.status, "Updated 5 prices")
end)

H.test("an empty recipe list or one with nothing to search starts nothing and says so", function()
    local T = boot()
    local P = T.ns.PinsUI
    T.ns.AH.isOpen = true
    P.startSearch({})
    H.eq(P.state, "idle")
    H.eq(T.sent, {})
    H.eq(P.status, "Nothing to search")
    for locale, text in pairs({ frFR = "Rien à rechercher", esES = "Nada que buscar" }) do
        local F = W.boot(H, { items = ITEMS, locale = locale })
        F.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
        F.ns.AH.isOpen = true
        F.ns.PinsUI.startSearch({})
        H.eq(F.ns.PinsUI.status, text)
    end
end)

H.test("the footer button labels fit their half-width buttons in English, French and Spanish", function()
    for _, locale in ipairs({ "enUS", "frFR", "esES" }) do
        local T = W.boot(H, { items = ITEMS, locale = locale })
        T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
        local parts = openList(T)
        local half = math.floor((T.ns.Window.INNER_WIDTH - T.ns.Window.GAP) / 2)
        for _, b in ipairs({ parts.search, parts.scan, parts.level }) do
            local need = T.ns.Layout.textWidth(b.text, T.ns.OptionsUI.CHAR_W)
            H.truthy(need <= half - 16 or error(locale .. ": " .. b.text .. " needs " .. need .. " px"))
        end
        if locale == "frFR" then H.eq(parts.search.text, "Actualiser épinglées") end
        if locale == "esES" then H.eq(parts.search.text, "Actualizar fijadas") end
    end
end)

H.test("the main window's Refresh recipe button is off while any search runs, back on at done or cancel", function()
    local T = boot()
    local P, C = T.ns.PinsUI, T.ns.Controller
    local b = T.ns.Window.parts.refresh
    C.setRecipe(T.ns.Recipes.normalize(raw(9, 101, { { itemID = 4, qty = 1 } })), "profession")
    T.ns.AH.isOpen = true
    C.onAHOpen(true)
    H.eq(b.enabled, true)
    -- A pinned search: off until it is done.
    P.startSearch()
    H.eq(b.enabled, false)
    -- A render meanwhile (prices arriving) keeps it off.
    C.refresh()
    H.eq(b.enabled, false)
    for _, id in ipairs({ 1, 2, 100, 3, 101 }) do P.onSearchResults(id, listing) end
    H.eq(P.state, "done")
    H.eq(b.enabled, true)
    -- A recipe search: off; the AH closing cancels it and the button stays off (AH closed),
    -- then comes back when the AH opens again.
    C.refreshRecipe()
    H.eq(b.enabled, false)
    T.ns.AH.isOpen = false
    C.onAHOpen(false)
    H.eq(P.state, "cancelled")
    H.eq(b.enabled, false)
    T.ns.AH.isOpen = true
    C.onAHOpen(true)
    H.eq(b.enabled, true)
end)

H.test("one or two missing items of a kind are named, more are counted, each kind on its own", function()
    local T = boot()
    local P, L = T.ns.PinsUI, T.ns.L
    local names = { [10] = "Silver Bar", [11] = "Copper Bar" }
    local function nameOf(id) return names[id] end
    local function s(counts) return P.searchSummary(L, counts, nameOf) end
    -- One named.
    H.eq(s({ ok = 6, total = 7, failed = 1, failedIDs = { 10 } }), "Updated 6 of 7 prices · no answer: Silver Bar, try again")
    -- Two named, an unknown one by its id.
    H.eq(s({ ok = 7, total = 7, noListing = 2, noListingIDs = { 11, 12 } }),
        "Updated 5 of 7 prices · no listing: Copper Bar, #12 (nobody is selling them now)")
    -- Three: counted.
    H.eq(s({ ok = 4, total = 7, failed = 3, failedIDs = { 10, 11, 12 } }), "Updated 4 of 7 prices · no answer: 3, try again")
    -- Mixed: two named for one kind, three counted for the other.
    H.eq(s({ ok = 7, total = 10, noListing = 2, noListingIDs = { 10, 11 }, failed = 3, failedIDs = { 1, 2, 3 } }),
        "Updated 5 of 10 prices · no listing: Silver Bar, Copper Bar (nobody is selling them now) · no answer: 3, try again")
    -- No name function: ids; no id list: the count.
    H.eq(P.searchSummary(L, { ok = 1, total = 2, failed = 1, failedIDs = { 10 } }), "Updated 1 of 2 prices · no answer: #10, try again")
    H.eq(s({ ok = 1, total = 2, failed = 1 }), "Updated 1 of 2 prices · no answer: 1, try again")
end)

H.test("the names read in French and Spanish", function()
    for locale, text in pairs({
        frFR = "6 prix sur 7 mis à jour · sans réponse\194\160: Barre d'argent, réessayez",
        esES = "6 de 7 precios actualizados · sin respuesta: Barra de plata, reintenta",
    }) do
        local T = W.boot(H, { items = ITEMS, locale = locale })
        T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
        local name = locale == "frFR" and "Barre d'argent" or "Barra de plata"
        H.eq(T.ns.PinsUI.searchSummary(T.ns.L, { ok = 6, total = 7, failed = 1, failedIDs = { 10 } },
            function() return name end), text)
    end
end)

H.test("the status is a fixed two-line box under the buttons: a long one is cut, never overflows", function()
    local T = W.boot(H, { items = ITEMS })
    local create = T.env.CreateFrame
    T.env.CreateFrame = function(...)
        local f = create(...)
        f.CreateFontString = function()
            local fs = W.frame()
            fs.SetWidth = function(self, w) self.width = w end
            fs.SetMaxLines = function(self, n) self.maxLines = n end
            fs.SetWordWrap = function(self, v) self.wrap = v end
            return fs
        end
        return f
    end
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    local status = T.ns.PinsUI.parts.status
    H.eq(status.width, T.ns.Window.INNER_WIDTH)
    H.eq(status.height, 28)
    H.eq(status.maxLines, 2)
    H.eq(status.wrap, true)
    -- The footer keeps room for exactly that box.
    H.eq(T.ns.PinsUI.FOOTER_H, 22 + 6 + 22 + 6 + 28)
end)

-- Records commitSearch calls (one history batch per search).
local function countCommits(T)
    local C = T.ns.Controller
    local commit, n = C.commitSearch, { 0 }
    C.commitSearch = function(...) n[1] = n[1] + 1; return commit(...) end
    return n
end

H.test("the second pass searches only the prices the first one missed, once, and counts what it finds", function()
    local T = boot()
    local P = T.ns.PinsUI
    local commits = countCommits(T)
    T.ns.AH.isOpen = true
    P.startSearch()
    -- First pass: 1 has no listing, 100 does not answer, the rest are found.
    P.onSearchResults(1, {})
    P.onSearchResults(2, listing)
    T.clock = T.clock + 7
    T.tickers[#T.tickers].fn()
    P.onSearchResults(3, listing)
    P.onSearchResults(101, listing)
    H.eq(T.sent, { 1, 2, 100, 3, 101, 1 })
    H.eq(P.status, "Retrying 0/2")
    H.eq(commits[1], 0)
    -- The refresh button stays off across both passes.
    H.eq(T.ns.Window.parts.refresh.enabled, false)
    -- Second pass: 1 is found now, 100 still has no listing.
    P.onSearchResults(1, listing)
    H.eq(P.status, "Retrying 1/2")
    P.onSearchResults(100, {})
    H.eq(T.sent, { 1, 2, 100, 3, 101, 1, 100 })
    H.eq(P.state, "done")
    H.eq(P.status, "Updated 4 of 5 prices · no listing: Item100 (nobody is selling them now)")
    H.eq(T.ns.Controller.market().prices[1][1], 20)
    -- History and the commit run once, at the very end; no third pass.
    H.eq(commits[1], 1)
    T.clock = T.clock + 30
    T.tickers[#T.tickers].fn()
    H.eq(#T.sent, 7)
end)

H.test("everything found in the second pass reads as all updated", function()
    local T = boot()
    local P = T.ns.PinsUI
    T.ns.AH.isOpen = true
    P.startSearch()
    P.onSearchResults(1, {})
    for _, id in ipairs({ 2, 100, 3, 101 }) do P.onSearchResults(id, listing) end
    P.onSearchResults(1, listing)
    H.eq(P.status, "Updated 5 prices")
end)

H.test("no second pass when the first one found everything", function()
    local T = boot()
    local P = T.ns.PinsUI
    local commits = countCommits(T)
    T.ns.AH.isOpen = true
    P.startSearch()
    for _, id in ipairs({ 1, 2, 100, 3, 101 }) do P.onSearchResults(id, listing) end
    H.eq(#T.sent, 5)
    H.eq(P.state, "done")
    H.eq(P.status, "Updated 5 prices")
    H.eq(commits[1], 1)
end)

H.test("closing the AH during the second pass cancels it, commits once, and the button follows", function()
    local T = boot()
    local P, C = T.ns.PinsUI, T.ns.Controller
    local commits = countCommits(T)
    C.setRecipe(T.ns.Recipes.normalize(raw(9, 101, { { itemID = 4, qty = 1 } })), "profession")
    T.ns.AH.isOpen = true
    C.onAHOpen(true)
    C.refreshRecipe()
    P.onSearchResults(4, {})
    P.onSearchResults(101, listing)
    H.eq(P.status, "Retrying 0/1")
    H.eq(T.ns.Window.parts.refresh.enabled, false)
    T.ns.AH.isOpen = false
    C.onAHOpen(false)
    H.eq(P.state, "cancelled")
    H.eq(P.status, "Search cancelled")
    H.eq(commits[1], 1)
    -- A late answer for the retried item is ignored.
    P.onSearchResults(4, listing)
    H.eq(T.ns.Controller.market().prices[4], nil)
    T.ns.AH.isOpen = true
    C.onAHOpen(true)
    H.eq(T.ns.Window.parts.refresh.enabled, true)
end)

H.test("the retry status reads in French and Spanish", function()
    for locale, text in pairs({ frFR = "Nouvel essai 0/1", esES = "Reintentando 0/1" }) do
        local F = W.boot(H, { items = ITEMS, locale = locale })
        F.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
        F.ns.AH.search = function() return true end
        F.ns.AH.isOpen = true
        local recipe = F.ns.Recipes.normalize(raw(9, 101, { { itemID = 4, qty = 1 } }))
        F.ns.PinsUI.startSearch({ recipe })
        F.ns.PinsUI.onSearchResults(4, {})
        F.ns.PinsUI.onSearchResults(101, listing)
        H.eq(F.ns.PinsUI.status, text)
    end
end)
