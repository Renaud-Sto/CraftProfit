local H = ...
local W = dofile("tests/fakewow.lua")

-- Real frames start shown (the fake ones do not): the window must hide itself.
local function boot()
    local T = W.boot(H)
    local create = T.env.CreateFrame
    T.env.CreateFrame = function(...)
        local f = create(...)
        f.shown = true
        -- The fake SetSize is a no-op: record the height like SetHeight does.
        f.SetSize = function(self, _, h) self.height = h end
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
    local Theme = T.ns.Theme
    feed(T, data())
    UI.show()
    H.truthy(UI.isShown())
    local p = UI.parts
    H.eq(p.profession.label.text, "Forge")
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
    H.eq(colour, Theme.FIXED.optimal)
end)

H.test("the sort button reads the sort mode and the controls call the controller", function()
    local T, UI, calls = boot()
    feed(T, data({ sort = "speed" }))
    UI.show()
    H.eq(UI.parts.sort.label.text, "Sort: speed")
    UI.parts.sort.scripts.OnClick(UI.parts.sort)
    UI.parts.profession.scripts.OnClick(UI.parts.profession)
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
    H.eq(UI.parts.profession.label.text, "-")
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

H.test("toggle and hide work and a theme switch repaints without error", function()
    local T, UI = boot()
    feed(T, data())
    UI.toggle()
    H.truthy(UI.isShown())
    for _, name in ipairs({ "copper", "steel", "gold" }) do T.ns.Kit.applyTheme(name) end
    UI.toggle()
    H.falsy(UI.isShown())
    UI.hide()
end)
