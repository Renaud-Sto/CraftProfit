local H = ...
local W = dofile("tests/fakewow.lua")

-- Real frames start shown (the fake ones do not): the window must hide itself.
-- `onFrame(f)`, when given, sees every frame created from ADDON_LOADED on, before use.
local function boot(onFrame)
    local T = W.boot(H)
    local create = T.env.CreateFrame
    T.env.CreateFrame = function(...)
        local f = create(...)
        f.shown = true
        -- The fake SetSize is a no-op: record the height like SetHeight does.
        f.SetSize = function(self, _, h) self.height = h end
        if onFrame then onFrame(f) end
        return f
    end
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    local calls = {}
    local C = T.ns.Controller
    C.nextLevelProfession = function() calls[#calls + 1] = { "next" } end
    C.toggleLevelSort = function() calls[#calls + 1] = { "sort" } end
    C.setLevelShowGrey = function(v) calls[#calls + 1] = { "grey", v } end
    C.selectKnown = function(recipe) calls[#calls + 1] = { "select", recipe.recipeID } end
    return T, T.ns.LevelingUI, calls
end

local function item(id, name, difficulty, chance, cost)
    return {
        recipe = { recipeID = id, name = name, difficulty = difficulty },
        result = { perPoint = { chance = chance, cost = cost } },
    }
end

local function data(over)
    local d = {
        sort = "cost", showGrey = false, profession = { name = "Forge" },
        ageText = "Prices: 5m ago", stale = false, hiddenGrey = 0,
        items = { item(1, "Bronze Sword", "optimal", 1, 100), item(2, "Copper Helm", "easy", 0.25, 900) },
    }
    for k, v in pairs(over or {}) do d[k] = v end
    return d
end

local function feed(T, d) T.ns.Controller.levelData = function() return d end end

H.test("the leveling window is created hidden although real frames start shown", function()
    local _, UI = boot()
    H.falsy(UI.isShown())
    H.truthy(UI.frame())
end)

H.test("showing it lists the recipes with their difficulty colours, crafts per point and cost", function()
    local T, UI = boot()
    local Colors = T.ns.Colors
    feed(T, data())
    UI.show()
    H.truthy(UI.isShown())
    local p = UI.parts
    H.eq(p.profession.text, "Forge")
    H.eq(p.age.text, "Prices: 5m ago")
    H.eq(p.rows[1].name.text, "Bronze Sword")
    H.eq(p.rows[1].crafts.text, "x1")
    H.eq(p.rows[2].name.text, "Copper Helm")
    H.eq(p.rows[2].crafts.text, "x4")
    H.truthy(p.rows[1].shown)
    H.falsy(p.rows[3].shown)
    local colour
    p.rows[1].name.SetTextColor = function(_, r, g, b, a) colour = { r, g, b, a } end
    UI.refresh()
    H.eq(colour, Colors.FIXED.optimal)
end)

H.test("a cost per point counted without a missing resale price shows in the incomplete colour", function()
    local T, UI = boot()
    local Colors = T.ns.Colors
    local partial = item(3, "Iron Buckle", "medium", 0.75, 400)
    partial.result.perPoint.incomplete = true
    feed(T, data({ items = { item(1, "Bronze Sword", "optimal", 1, 100), partial } }))
    local colours = {}
    for i = 1, 2 do
        UI.parts.rows[i].value.SetTextColor = function(_, r, g, b, a) colours[i] = { r, g, b, a } end
    end
    UI.show()
    H.eq(colours[1], Colors.FIXED.loss)
    H.eq(colours[2], Colors.FIXED.incomplete)
    H.eq(UI.parts.rows[2].value.text, "4s/pt")
end)

H.test("the sort button reads the sort mode and the controls call the controller", function()
    local T, UI, calls = boot()
    feed(T, data({ sort = "speed" }))
    UI.show()
    H.eq(UI.parts.sort.text, "Sort: speed")
    UI.parts.sort.scripts.OnClick(UI.parts.sort)
    UI.parts.profession.scripts.OnClick(UI.parts.profession)
    -- A CheckButton flips its own state before OnClick; the fake does not, so flip it here.
    UI.parts.grey:SetChecked(true)
    UI.parts.grey.scripts.OnClick(UI.parts.grey)
    H.eq(calls[1], { "sort" })
    H.eq(calls[2], { "next" })
    H.eq(calls[3], { "grey", true })
end)

H.test("clicking a row shows that recipe in the main window", function()
    local T, UI, calls = boot()
    feed(T, data())
    UI.show()
    UI.parts.rows[2].scripts.OnClick(UI.parts.rows[2])
    H.eq(calls[#calls], { "select", 2 })
end)

H.test("the hidden grey count and the empty messages", function()
    local T, UI = boot()
    feed(T, data({ hiddenGrey = 3 }))
    UI.show()
    H.truthy(UI.parts.hidden.text:find("3", 1, true))
    feed(T, data({ items = {} }))
    UI.refresh()
    H.truthy(UI.parts.empty.shown)
    H.eq(UI.parts.empty.text, "No recipe can give a skill point")
    -- data() cannot clear a key through `over` (pairs skips nil values).
    local none = data({ items = {} })
    none.profession = nil
    feed(T, none)
    UI.refresh()
    H.eq(UI.parts.profession.text, "-")
    H.truthy(UI.parts.empty.shown)
    for i = 1, 12 do H.falsy(UI.parts.rows[i].shown) end
end)

H.test("the scroll bar appears with more than twelve recipes and the wheel and bar scroll the list", function()
    local T, UI = boot()
    local items = {}
    for i = 1, 20 do items[i] = item(i, "R" .. i, "medium", 0.75, i * 10) end
    feed(T, data({ items = items }))
    UI.show()
    local p = UI.parts
    H.truthy(p.bar.frame.shown)
    H.eq(p.rows[1].name.text, "R1")
    UI.frame().scripts.OnMouseWheel(UI.frame(), -1)
    H.eq(p.rows[1].name.text, "R2")
    p.bar.onScroll(8)
    H.eq(p.rows[1].name.text, "R9")
    p.bar.onScroll(500)
    H.eq(p.rows[1].name.text, "R9")
    feed(T, data({ items = { item(1, "A", "easy", 1, 5) } }))
    UI.refresh()
    H.eq(p.rows[1].name.text, "A")
    H.falsy(p.bar.frame.shown)
end)

H.test("scrolling repaints the rows from the last data, and does nothing when the offset stays", function()
    local T, UI = boot()
    local C = T.ns.Controller
    local items = {}
    for i = 1, 20 do items[i] = item(i, "R" .. i, "medium", 0.75, i * 10) end
    local d, fetched = data({ items = items }), 0
    C.levelData = function() fetched = fetched + 1; return d end
    UI.show()
    H.eq(fetched, 1)
    local p = UI.parts
    UI.frame().scripts.OnMouseWheel(UI.frame(), -1)
    H.eq(p.rows[1].name.text, "R2")
    p.bar.onScroll(8)
    H.eq(p.rows[1].name.text, "R9")
    H.eq(p.bar.offset, 8)
    -- No recipe evaluated again while scrolling.
    H.eq(fetched, 1)
    -- At the end of the list (8 of 20, twelve rows): no row is painted again.
    local named, recipeName = 0, C.recipeName
    C.recipeName = function(recipe) named = named + 1; return recipeName(recipe) end
    p.bar.onScroll(8)
    p.bar.onScroll(500)
    UI.frame().scripts.OnMouseWheel(UI.frame(), -1)
    H.eq(named, 0)
    H.eq(p.bar.offset, 8)
    -- A refresh still reads the data again.
    UI.refresh()
    H.eq(fetched, 2)
end)

H.test("the window has a fixed height whatever the number of recipes", function()
    local T, UI = boot()
    feed(T, data())
    UI.show()
    local h1 = UI.frame().height
    local items = {}
    for i = 1, 30 do items[i] = item(i, "R" .. i, "easy", 0.25, i) end
    feed(T, data({ items = items }))
    UI.refresh()
    H.eq(UI.frame().height, h1)
    H.truthy(h1 > 0)
end)

H.test("the window sits beside the main window, or in the middle of the screen, and a saved position wins", function()
    local T, UI = boot()
    local points = {}
    UI.frame().SetPoint = function(_, ...) points[#points + 1] = { ... } end
    UI.place()
    H.eq(points[#points][1], "CENTER")
    T.ns.Window.show()
    UI.place()
    H.eq(points[#points][1], "TOPLEFT")
    H.eq(points[#points][3], "TOPRIGHT")
    UI.attach({ x = 40, y = 500 })
    H.eq(points[#points], { "TOPLEFT", T.env.UIParent, "BOTTOMLEFT", 40, 500 })
end)

H.test("dropping the window reports its position", function()
    local T, UI = boot()
    local moved
    UI.frame().scripts.OnDragStop(UI.frame())
    -- handlers belong to Boot: check the call does not raise and Boot stored a position
    moved = T.env.CraftProfitDB.settings.levelWindow
    H.eq(moved, { x = 100, y = 700 })
end)

H.test("the empty message wraps, centred, inside the panel body", function()
    -- Font strings record their width and justification from creation on.
    local T, UI = boot(function(f)
        f.CreateFontString = function()
            local fs = W.frame()
            fs.widths = {}
            fs.SetWidth = function(self, w) self.widths[#self.widths + 1] = w end
            fs.SetJustifyH = function(self, v) self.justify = v end
            return fs
        end
    end)
    local Native = T.ns.Native
    -- The native inset, the content pad, the panel's edges, then 8 px of air each side.
    H.eq(UI.INNER_WIDTH, UI.WIDTH - Native.INSET_LEFT - Native.INSET_RIGHT - Native.CONTENT_PAD * 2)
    H.eq(UI.EMPTY_WIDTH, UI.INNER_WIDTH - Native.PANEL_EDGE * 2 - 16)
    H.eq(UI.parts.empty.widths, { UI.EMPTY_WIDTH })
    H.eq(UI.parts.empty.justify, "CENTER")
end)

H.test("toggle and hide work; a plain name and an unknown value take the game's text colours", function()
    local T, UI = boot()
    local Colors = T.ns.Colors
    -- No difficulty: the name takes the game's plain text colour; no cost: the value is
    -- "?" in the muted colour.
    feed(T, data({ items = { item(1, "Plain", nil, 1, nil) } }))
    UI.toggle()
    H.truthy(UI.isShown())
    local p = UI.parts
    H.eq(p.rows[1].value.text, "?")
    local nameColour, valueColour
    p.rows[1].name.SetTextColor = function(_, r, g, b, a) nameColour = { r, g, b, a } end
    p.rows[1].value.SetTextColor = function(_, r, g, b, a) valueColour = { r, g, b, a } end
    UI.refresh()
    H.eq(nameColour, Colors.text("main"))
    H.eq(valueColour, Colors.text("muted"))
    UI.toggle()
    H.falsy(UI.isShown())
    UI.hide()
end)

H.test("the age line is muted, or in the stale colour when prices are old", function()
    local T, UI = boot()
    local Colors = T.ns.Colors
    local colour
    UI.parts.age.SetTextColor = function(_, r, g, b, a) colour = { r, g, b, a } end
    feed(T, data())
    UI.show()
    H.eq(colour, Colors.text("muted"))
    feed(T, data({ stale = true }))
    UI.refresh()
    H.eq(colour, Colors.FIXED.stale)
end)

H.test("the leveling window is built from the native kit", function()
    local made = {}
    local _, UI = boot(function(f) made[#made + 1] = f end)
    local p = UI.parts
    -- Native.window made it (its drag and title helpers), with a native bar, check and rows.
    H.eq(type(rawget(UI.frame(), "setTitle")), "function")
    H.eq(type(rawget(UI.frame(), "stopDrag")), "function")
    H.truthy(rawget(p.bar, "trackAtlases") ~= nil)
    H.eq(p.bar.frame.scripts.OnUpdate, nil)
    H.eq(type(rawget(p.grey, "setMaxWidth")), "function")
    H.eq(type(p.rows[1].scripts.OnDragStart), "function")
    H.truthy(#made > 0)
end)

H.test("the window height is the native chrome, the pads and the four sections", function()
    local T, UI = boot()
    local Native, Layout = T.ns.Native, T.ns.Layout
    local sections = Native.BUTTON_H + 14 + Layout.panelHeight(12, 18) + Native.CHECK_SIZE + 8 * 3
    H.eq(UI.frame().height,
        Native.INSET_TOP + Native.INSET_BOTTOM + Native.CONTENT_PAD * 2 + sections)
end)

H.test("the grey-recipes label stops before the hidden count", function()
    local T, UI = boot()
    local Native = T.ns.Native
    local caps = {}
    UI.parts.grey.setMaxWidth = function(_, w) caps[#caps + 1] = w end
    UI.parts.hidden.GetUnboundedStringWidth = function(self) return self.text == "" and 0 or 60 end
    local full = UI.INNER_WIDTH - (Native.CHECK_SIZE + Native.CHECK_LABEL_X) - 4
    feed(T, data())
    UI.show()
    H.eq(caps[#caps], full)
    feed(T, data({ hiddenGrey = 3 }))
    UI.refresh()
    H.eq(caps[#caps], full - 60 - 8)
end)

H.test("dragging a leveling row moves the window and the click that ends it selects nothing", function()
    local T, UI, calls = boot()
    feed(T, data())
    UI.show()
    local moved = false
    UI.frame().StartMoving = function() moved = true end
    local row = UI.parts.rows[2]
    row.scripts.OnMouseDown(row, "LeftButton")
    row.scripts.OnDragStart(row)
    H.truthy(moved)
    row.scripts.OnClick(row)
    H.eq(#calls, 0)
    row.scripts.OnMouseDown(row, "LeftButton")
    row.scripts.OnClick(row)
    H.eq(calls[#calls], { "select", 2 })
end)

H.test("the value column is wide enough for an amount with coin icons, the crafts column sits before it", function()
    local _, UI = boot(function(f)
        f.CreateFontString = function()
            local fs = W.frame()
            fs.SetWidth = function(self, w) self.width = w end
            fs.points = {}
            fs.SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end
            return fs
        end
    end)
    H.eq(UI.VALUE_W, 130)
    local row = UI.parts.rows[1]
    H.eq(row.value.width, UI.VALUE_W)
    H.eq(row.crafts.width, UI.CRAFTS_W)
    H.eq(row.crafts.points[1], { "RIGHT", row, "RIGHT", -(8 + UI.VALUE_W + 8), 0 })
    -- The name runs from the left edge to the crafts column and gives up the extra room.
    H.eq(row.name.points[2], { "RIGHT", row.crafts, "LEFT", -8, 0 })
end)

H.test("the profession and recipe names come from the controller's current-language names", function()
    local T, UI = boot()
    local d = data()
    d.items[1].recipe.outputItemID = 100
    d.profession = { key = "185", name = "Cuisine" }
    feed(T, d)
    T.env.GetProfessions = function() return 1 end
    T.env.GetProfessionInfo = function() return "Cooking", "icon", 60, 75, 0, 0, 185 end
    T.env.C_TradeSkillUI = { GetRecipeInfo = function(id) return id == 1 and { name = "Hot Lion Chops" } or nil end }
    UI.show()
    H.eq(UI.parts.profession.text, "Cooking")
    H.eq(d.profession.name, "Cooking")
    H.eq(UI.parts.rows[1].name.text, "Hot Lion Chops")
    H.eq(UI.parts.rows[2].name.text, "Copper Helm")
end)

H.test("a dragged window reopens where it was left, in the same session", function()
    local T, UI = boot()
    feed(T, data())
    UI.show()
    UI.frame().scripts.OnDragStop(UI.frame())
    local points = {}
    UI.frame().SetPoint = function(_, ...) points[#points + 1] = { ... } end
    UI.hide()
    T.ns.Window.show()
    UI.show()
    H.eq(points[#points], { "TOPLEFT", T.env.UIParent, "BOTTOMLEFT", 100, 700 })
end)

H.test("a non-finite leveling position is never saved", function()
    local T = boot()
    local C = T.ns.Controller
    T.env.CraftProfitDB.settings.levelWindow = nil
    C.saveLevelPosition(0 / 0, 5)
    C.saveLevelPosition(5, math.huge)
    H.eq(T.env.CraftProfitDB.settings.levelWindow, nil)
    C.saveLevelPosition(5, 6)
    H.eq(T.env.CraftProfitDB.settings.levelWindow, { x = 5, y = 6 })
end)

H.test("a recipe only a disenchant without data could sell reads no data, not ?", function()
    local T, UI = boot()
    local it = item(1, "Reaper", "optimal", 1, nil)
    it.result.options = { disenchant = { status = "nodata" } }
    it.result.incomplete = false
    feed(T, data({ items = { it, item(2, "Other", "easy", 0.25, nil) } }))
    UI.show()
    H.eq(UI.parts.rows[1].value.text, "no data")
    H.eq(UI.parts.rows[2].value.text, "?")
end)

H.test("a drop at a non-finite position is not kept for the next open", function()
    local T, UI = boot()
    feed(T, data())
    UI.show()
    local frame = UI.frame()
    frame.GetLeft = function() return 0 / 0 end
    frame.scripts.OnDragStop(frame)
    local points = {}
    frame.SetPoint = function(_, ...) points[#points + 1] = { ... } end
    UI.hide()
    UI.show()
    -- Reopened at its default place, never at a NaN offset.
    H.truthy(#points > 0)
    for _, p in ipairs(points) do
        for i = 4, 5 do H.truthy(p[i] == nil or p[i] == p[i]) end
    end
end)
