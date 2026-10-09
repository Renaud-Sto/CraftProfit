local H = ...
local W = dofile("tests/fakewow.lua")

-- Real frames start shown (the fake ones do not): the window must hide itself.
local function boot()
    local T = W.boot(H)
    local create = T.env.CreateFrame
    T.env.CreateFrame = function(...)
        local f = create(...)
        f.shown = true
        return f
    end
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    local calls = {}
    for _, name in ipairs({ "onPinClick", "onReagentClick", "onCraftsChange", "onTrackToggle",
        "onPerPointToggle", "onCostToggle", "onMoved" }) do
        T.ns.Window.lastHandlers[name] = function(...) calls[#calls + 1] = { name, ... } end
    end
    return T, T.ns.Window, calls
end

local function model(over)
    local m = {
        title = "Bronze Sword", crafts = 1, costExpanded = true, showPerPoint = false,
        pinned = false, tracked = false, ageText = "Prices: 5m ago", stale = false,
        verdict = { kind = "profit", text = "Best: Auction house", value = "+7s" },
        banner = { label = "RESULT", text = "Best: Auction house", value = "+7s", kind = "profit" },
        tiles = {
            { key = "ah", label = "AH (NET)", value = "9s 50c", best = true, muted = false },
            { key = "vendor", label = "VENDOR", value = "2s", best = false, muted = false },
            { key = "disenchant", label = "DISENCH.", value = "3s 80c", best = false, muted = false, tag = "beta" },
        },
        materials = { title = "MATERIALS", total = "2s 50c" },
        lines = { { label = "Materials", value = "2s 50c", key = "cost", best = false } },
        costLines = {
            { itemID = 11, qty = 3, unitText = "50c", subtotalText = "1s 50c" },
            { itemID = 12, qty = 1, unitText = "1s", subtotalText = "1s" },
        },
    }
    for k, v in pairs(over or {}) do m[k] = v end
    return m
end

H.test("the window is created hidden although real frames start shown", function()
    local _, Window = boot()
    H.falsy(Window.isShown())
end)

H.test("render shows the title, the banner and the three tiles", function()
    local _, Window = boot()
    Window.render(model())
    local p = Window.parts
    H.eq(Window.frame().titleText.text, "Bronze Sword")
    H.eq(p.banner.label.text, "RESULT")
    H.eq(p.banner.text.text, "Best: Auction house")
    H.eq(p.banner.value.text, "+7s")
    H.eq(p.tiles[1].value.text, "9s 50c")
    H.truthy(p.tiles[1].best)
    H.falsy(p.tiles[2].best)
    H.truthy(p.tiles[3].label.text:find("beta", 1, true))
end)

H.test("the banner tint follows the kind of result and not the theme", function()
    local T, Window = boot()
    local Theme = T.ns.Theme
    Window.render(model({ banner = { label = "RESULT", text = "Best: Auction house", value = "-2s", kind = "loss" } }))
    local b = Window.parts.banner
    H.eq({ b.edge[1], b.edge[2], b.edge[3] }, { Theme.FIXED.loss[1], Theme.FIXED.loss[2], Theme.FIXED.loss[3] })
    T.ns.Kit.applyTheme("steel")
    H.eq({ b.edge[1], b.edge[2], b.edge[3] }, { Theme.FIXED.loss[1], Theme.FIXED.loss[2], Theme.FIXED.loss[3] })
end)

H.test("an unfolded materials panel lists one row per cost line and hides the rest", function()
    local _, Window = boot()
    Window.render(model())
    local p = Window.parts
    H.eq(p.materials.title.text, "- MATERIALS")
    H.eq(p.materials.right.text, "2s 50c")
    H.eq(p.rows[1].name.text, "3x #11")
    H.eq(p.rows[1].value.text, "1s 50c")
    H.eq(p.rows[2].name.text, "1x #12")
    H.truthy(p.rows[1].hit.shown)
    H.truthy(p.rows[2].hit.shown)
    H.falsy(p.rows[3].hit.shown)
    H.truthy(p.materials.body.shown)
end)

H.test("a folded materials panel shows only its header", function()
    local T, Window = boot()
    Window.render(model({ costExpanded = false }))
    local p = Window.parts
    H.eq(p.materials.title.text, "+ MATERIALS")
    H.falsy(p.materials.body.shown)
    H.eq(p.frames.materials.height, T.ns.Kit.FOLDED_H)
    for i = 1, 12 do H.falsy(p.rows[i].hit.shown) end
end)

H.test("clicking the materials header asks to fold or unfold, clicking a reagent row asks for its search", function()
    local _, Window, calls = boot()
    Window.render(model())
    Window.parts.materials.headerHit.scripts.OnClick()
    H.eq(calls[1], { "onCostToggle", false })
    Window.render(model({ costExpanded = false }))
    Window.parts.materials.headerHit.scripts.OnClick()
    H.eq(calls[2], { "onCostToggle", true })
    Window.render(model())
    Window.parts.rows[1].hit.scripts.OnClick()
    H.eq(calls[3], { "onReagentClick", 11, 3 })
end)

H.test("the crafts box shows the count, is never rewritten while focused and reports on focus loss", function()
    local _, Window, calls = boot()
    Window.render(model({ crafts = 5 }))
    local box = Window.parts.craftsBox
    H.eq(box.text, "5")
    box.HasFocus = function() return true end
    Window.render(model({ crafts = 7 }))
    H.eq(box.text, "5")
    box.scripts.OnEditFocusLost(box)
    H.eq(calls[#calls], { "onCraftsChange", "5" })
end)

H.test("the track and per-point check boxes show the model and report clicks", function()
    local _, Window, calls = boot()
    Window.render(model({ tracked = true, showPerPoint = false }))
    local p = Window.parts
    H.truthy(p.track:GetChecked())
    H.falsy(p.perPoint:GetChecked())
    p.track.scripts.OnClick(p.track)
    H.eq(calls[#calls], { "onTrackToggle", false })
    p.perPoint.scripts.OnClick(p.perPoint)
    H.eq(calls[#calls], { "onPerPointToggle", true })
end)

H.test("the per-point value follows the model line: hidden, a cost, or a gain with a plus", function()
    local T, Window = boot()
    local Theme = T.ns.Theme
    local p = Window.parts
    Window.render(model())
    H.falsy(p.perPointValue.shown)
    local colour
    p.perPointValue.SetTextColor = function(_, r, g, b) colour = { r, g, b } end
    Window.render(model({ showPerPoint = true, lines = { { label = "Cost per point", value = "12s (25%, estimate)", key = "perpoint", tone = "loss" } } }))
    H.truthy(p.perPointValue.shown)
    H.eq(p.perPointValue.text, "12s (25%, estimate)")
    H.eq(colour, { Theme.FIXED.loss[1], Theme.FIXED.loss[2], Theme.FIXED.loss[3] })
    Window.render(model({ showPerPoint = true, lines = { { label = "Gain per point", value = "9s (75%, estimate)", key = "perpoint", tone = "profit" } } }))
    H.eq(p.perPointValue.text, "+9s (75%, estimate)")
    H.eq(colour, { Theme.FIXED.profit[1], Theme.FIXED.profit[2], Theme.FIXED.profit[3] })
end)

H.test("the pin button reads Pin or Unpin and reports its click", function()
    local _, Window, calls = boot()
    Window.render(model({ pinned = false }))
    H.eq(Window.parts.pin.label.text, "Pin")
    Window.render(model({ pinned = true }))
    H.eq(Window.parts.pin.label.text, "Unpin")
    Window.parts.pin.scripts.OnClick(Window.parts.pin)
    H.eq(calls[#calls], { "onPinClick" })
end)

H.test("the likely-outcome line appears only when the model has one", function()
    local _, Window = boot()
    local p = Window.parts
    Window.render(model())
    H.falsy(p.frames.likely.shown)
    local lines = { { label = "Materials", value = "2s 50c", key = "cost", best = false },
        { label = "75%: 1-2x Dust = 5s", value = "", key = "likely", best = false, muted = true } }
    Window.render(model({ lines = lines }))
    H.truthy(p.frames.likely.shown)
    H.eq(p.likely.text, "75%: 1-2x Dust = 5s")
end)

H.test("sections lists the visible blocks top to bottom with their heights", function()
    local T, Window = boot()
    local Kit = T.ns.Kit
    local function keys(list) local k = {} for i, s in ipairs(list) do k[i] = s.key end return k end
    local list = Window.sections({ hasLikely = false, expanded = true, reagents = 2 })
    H.eq(keys(list), { "banner", "tiles", "materials", "age", "options" })
    H.eq(list[3].height, Kit.panelHeight(2, 18))
    H.eq(list[5].height, Kit.panelHeight(3, 26))
    H.eq(keys(Window.sections({ hasLikely = true, expanded = true, reagents = 0 })),
        { "banner", "tiles", "likely", "materials", "age", "options" })
    H.eq(Window.sections({ hasLikely = false, expanded = false, reagents = 9 })[3].height, Kit.FOLDED_H)
end)

H.test("the frame height is the sum of the visible sections plus the insets, and the pinned list adds its own", function()
    local T, Window = boot()
    local Kit = T.ns.Kit
    Window.render(model())
    local list = Window.sections({ hasLikely = false, expanded = true, reagents = 2 })
    local _, total = Kit.stack((function() local h = {} for i, s in ipairs(list) do h[i] = s.height end return h end)(), Kit.GAP, 0)
    local expected = total + Kit.CONTENT_TOP + Kit.CONTENT_BOTTOM
    H.eq(Window.contentHeightOf(list), expected)
    H.eq(Window.frame().height, expected)
    Window.pinsHost():Show()
    Window.pinsHost():SetHeight(100)
    Window.relayout()
    H.eq(Window.frame().height, expected + 100)
end)

H.test("an empty window shows the message and hides every section", function()
    local T, Window = boot()
    local Kit = T.ns.Kit
    Window.render(model())
    Window.showEmpty("Select a recipe")
    local p = Window.parts
    H.eq(p.empty.text, "Select a recipe")
    H.truthy(p.empty.shown)
    for key, f in pairs(p.frames) do
        if f.shown then error("section still shown: " .. key) end
    end
    H.eq(Window.frame().titleText.text, "CraftProfit")
    H.eq(Window.frame().height, Kit.CONTENT_TOP + 24 + Kit.CONTENT_BOTTOM)
    H.eq(Window.lastModel, nil)
end)

H.test("dropping the window reports its position", function()
    local _, Window, calls = boot()
    Window.frame().scripts.OnDragStop(Window.frame())
    H.eq(calls[#calls], { "onMoved", "TOPLEFT", 100, 700 })
end)

H.test("switching theme after a render repaints without error", function()
    local T, Window = boot()
    Window.render(model({ showPerPoint = true, lines = { { label = "Cost per point", value = "1s", key = "perpoint", tone = "loss" } } }))
    for _, name in ipairs({ "copper", "steel", "gold" }) do T.ns.Kit.applyTheme(name) end
    H.truthy(Window.frame())
end)

H.test("a neutral per-point value follows the theme, a cost keeps its fixed colour", function()
    local T, Window = boot()
    local Kit, Theme = T.ns.Kit, T.ns.Theme
    local p = Window.parts
    local colour
    p.perPointValue.SetTextColor = function(_, r, g, b) colour = { r, g, b } end
    Window.render(model({ showPerPoint = true, lines = { { label = "Cost per point", value = "?", key = "perpoint" } } }))
    Kit.applyTheme("steel")
    local main = Theme.get("steel").textMain
    H.eq(colour, { main[1], main[2], main[3] })
    Window.render(model({ showPerPoint = true, lines = { { label = "Cost per point", value = "1s", key = "perpoint", tone = "loss" } } }))
    Kit.applyTheme("gold")
    H.eq(colour, { Theme.FIXED.loss[1], Theme.FIXED.loss[2], Theme.FIXED.loss[3] })
end)
