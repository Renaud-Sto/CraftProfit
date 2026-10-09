local H = ...
local W = dofile("tests/fakewow.lua")

-- A fake texture that records the colour painted on it.
local function recordingTexture()
    local tex = W.frame()
    tex.SetColorTexture = function(self, r, g, b, a) self.color = { r, g, b, a } end
    return tex
end

-- A fake font string that records its anchors, word wrap, justification, widths, and
-- in `log` its font object and colour calls in order.
local function recordingFontString()
    local fs = W.frame()
    fs.points, fs.widths, fs.log = {}, {}, {}
    fs.SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end
    fs.SetWordWrap = function(self, v) self.wordWrap = v end
    fs.SetJustifyH = function(self, v) self.justify = v end
    fs.SetWidth = function(self, w) self.widths[#self.widths + 1] = w end
    fs.SetFontObject = function(self, name)
        self.font = name
        self.log[#self.log + 1] = { "font", name }
    end
    fs.SetTextColor = function(self, r, g, b) self.log[#self.log + 1] = { "colour", r, g, b } end
    return fs
end

local function anchoredTo(fs, point, target, relPoint)
    for _, p in ipairs(fs.points) do
        if p[1] == point and p[2] == target and p[3] == relPoint then return true end
    end
    return false
end

-- Real frames start shown (the fake ones do not): the window must hide itself.
-- opts.record: every frame keeps its textures in `f.textures` (recording their colour)
-- and its font strings record anchors and word wrap.
local function boot(opts)
    local T = W.boot(H)
    local create = T.env.CreateFrame
    T.env.CreateFrame = function(...)
        local f = create(...)
        f.shown = true
        if opts and opts.record then
            f.textures = {}
            f.CreateTexture = function(self)
                local tex = recordingTexture()
                self.textures[#self.textures + 1] = tex
                return tex
            end
            f.CreateFontString = function() return recordingFontString() end
        end
        return f
    end
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    local calls = {}
    for _, name in ipairs({ "onPinClick", "onReagentClick", "onCraftsChange", "onTrackToggle",
        "onPerPointToggle", "onCostToggle", "onMoved", "onOutputClick", "onThemeClick" }) do
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
    local T, Window = boot({ record = true })
    local Theme = T.ns.Theme
    -- The banner frame's first texture is its fill, the next four its ring.
    local textures = Window.parts.frames.banner.textures
    local function ringColours()
        local list = {}
        for i = 2, 5 do list[#list + 1] = textures[i].color end
        return list
    end
    local function expected(c)
        local want = { c[1], c[2], c[3], 0.45 }
        return { want, want, want, want }
    end
    H.eq(#textures, 5)
    Window.render(model({ banner = { label = "RESULT", text = "Best: Auction house", value = "-2s", kind = "loss" } }))
    H.eq(ringColours(), expected(Theme.FIXED.loss))
    T.ns.Kit.applyTheme("steel")
    H.eq(ringColours(), expected(Theme.FIXED.loss))
    Window.render(model())
    H.eq(ringColours(), expected(Theme.FIXED.profit))
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
    H.eq(Window.frame().height, expected + Kit.GAP + 100)
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

H.test("switching theme after a render repaints the window's texts", function()
    local T, Window = boot()
    local Theme = T.ns.Theme
    Window.render(model({ showPerPoint = true, lines = { { label = "Cost per point", value = "1s", key = "perpoint", tone = "loss" } } }))
    local p = Window.parts
    local watched = {
        { Window.frame().titleText, "plaqueText" },
        { p.banner.label, "headText" },
        { p.tiles[1].label, "headText" },
        { p.rows[1].name, "textMain" },
    }
    for _, w in ipairs(watched) do
        w[1].SetTextColor = function(self, r, g, b) self.colour = { r, g, b } end
    end
    T.ns.Kit.applyTheme("steel")
    local steel, gold = Theme.get("steel"), Theme.get("gold")
    for _, w in ipairs(watched) do
        local token = w[2]
        H.eq(w[1].colour, { steel[token][1], steel[token][2], steel[token][3] })
        H.truthy(w[1].colour[1] ~= gold[token][1] or w[1].colour[2] ~= gold[token][2]
            or w[1].colour[3] ~= gold[token][3])
    end
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

H.test("the per-point label stops before its value, never wraps and reads from the left", function()
    local _, Window = boot({ record = true })
    local p = Window.parts
    local label = p.perPoint.label
    H.truthy(anchoredTo(label, "RIGHT", p.perPointValue, "LEFT"))
    H.eq(label.wordWrap, false)
    H.eq(label.justify, "LEFT")
end)

H.test("turning the per-point option off empties and hides its value", function()
    local _, Window = boot()
    local p = Window.parts
    Window.render(model({ showPerPoint = true, lines = { { label = "Cost per point", value = "1s", key = "perpoint", tone = "loss" } } }))
    H.eq(p.perPointValue.text, "1s")
    Window.render(model())
    H.eq(p.perPointValue.text, "")
    H.falsy(p.perPointValue.shown)
end)

H.test("the banner text runs up to the value and has no fixed width", function()
    local _, Window = boot({ record = true })
    local b = Window.parts.banner
    H.truthy(anchoredTo(b.text, "RIGHT", b.value, "LEFT"))
    H.eq(b.text.justify, "LEFT")
    H.eq(b.text.wordWrap, false)
    Window.render(model())
    H.eq(b.text.widths, {})
end)

H.test("a banner text too long for the room beside the value drops to the small font, in gold", function()
    local T, Window = boot({ record = true })
    local best = T.ns.Theme.FIXED.best
    local b = Window.parts.banner
    -- 240 px in the normal font, 190 in the small one; room = 372 - 24 - 24 - value - 8.
    b.text.GetUnboundedStringWidth = function(self) return self.font == "GameFontNormalSmall" and 190 or 240 end
    local valueWidth = 40
    b.value.GetUnboundedStringWidth = function() return valueWidth end
    local long = { label = "RESULT", text = "Best known: Auction house (prices missing)", value = "+7s", kind = "incomplete" }
    Window.render(model({ banner = long }))
    H.eq(b.text.font, "GameFontNormal")
    valueWidth = 100
    Window.render(model({ banner = long }))
    H.eq(b.text.font, "GameFontNormalSmall")
    H.eq(b.text.log[#b.text.log], { "colour", best[1], best[2], best[3] })
    valueWidth = 40
    Window.render(model({ banner = long }))
    H.eq(b.text.font, "GameFontNormal")
    H.eq(b.text.log[#b.text.log], { "colour", best[1], best[2], best[3] })
end)

H.test("the banner label carries the amber warning after a middle dot, when there is one", function()
    local T, Window = boot({ record = true })
    local b = Window.parts.banner
    local esc = T.ns.Kit.colorEscape(T.ns.Theme.FIXED.incomplete)
    Window.render(model({ banner = { label = "RESULT", text = "Best known: Auction house", value = "+7s",
        kind = "incomplete", warning = "PRICES MISSING" } }))
    H.eq(b.label.text, "RESULT \194\183 " .. esc .. "PRICES MISSING|r")
    Window.render(model())
    H.eq(b.label.text, "RESULT")
end)

H.test("the banner label stops before the value and does not wrap", function()
    local _, Window = boot({ record = true })
    local b = Window.parts.banner
    local found = false
    for _, p in ipairs(b.label.points) do
        if p[1] == "RIGHT" and p[2] == b.value and p[3] == "LEFT" and p[4] == -8 and p[5] == 0 then found = true end
    end
    H.truthy(found)
    H.eq(b.label.wordWrap, false)
    H.eq(b.label.justify, "LEFT")
end)

H.test("the pinned host is as wide as the content and hangs a gap below the last section", function()
    local T, Window = boot()
    local Kit = T.ns.Kit
    H.eq(Window.INNER_WIDTH, 372 - Kit.CONTENT_SIDE * 2)
    local widths = {}
    local points = {}
    local host = Window.pinsHost()
    host.SetWidth = function(_, w) widths[#widths + 1] = w end
    host.SetPoint = function(_, ...) points[#points + 1] = { ... } end
    Window.render(model())
    host:Show()
    host:SetHeight(100)
    Window.relayout()
    local list = Window.sections({ hasLikely = false, expanded = true, reagents = 2 })
    local top = Window.contentHeightOf(list) - Kit.CONTENT_BOTTOM + Kit.GAP
    local last = points[#points]
    H.eq(last[1], "TOPLEFT")
    H.eq(last[3], "TOPLEFT")
    H.eq(last[4], Kit.CONTENT_SIDE)
    H.eq(last[5], -top)
end)

H.test("the pinned host is created INNER_WIDTH wide", function()
    local T = W.boot(H)
    local widths = {}
    local create = T.env.CreateFrame
    T.env.CreateFrame = function(...)
        local f = create(...)
        f.SetWidth = function(_, w) widths[#widths + 1] = w end
        return f
    end
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    local found = false
    for _, w in ipairs(widths) do if w == T.ns.Window.INNER_WIDTH then found = true end end
    H.truthy(found)
end)

H.test("the tiles together fill the content width exactly", function()
    local T, Window = boot()
    local Kit = T.ns.Kit
    local sizes = {}
    -- the tile frames are created before the test can wrap them: read their widths back
    for i, tile in ipairs(Window.parts.tiles) do sizes[i] = tile.width end
    H.eq(sizes[1] + sizes[2] + sizes[3] + Kit.GAP * 2, Window.INNER_WIDTH)
end)

H.test("the empty-state text follows the theme", function()
    local T, Window = boot()
    local colour
    Window.parts.empty.SetTextColor = function(_, r, g, b, a) colour = { r, g, b, a } end
    T.ns.Kit.applyTheme("steel")
    H.eq(colour, T.ns.Theme.get("steel").textMuted)
end)

H.test("clicking the AH tile or the title asks to search the crafted item", function()
    local _, Window, calls = boot()
    Window.render(model())
    local tile = Window.parts.tiles[1]
    tile.hit.scripts.OnClick(tile.hit)
    H.eq(calls[#calls], { "onOutputClick" })
    local title = Window.frame().titleHit
    title.scripts.OnClick(title)
    H.eq(calls[#calls], { "onOutputClick" })
    H.falsy(Window.parts.tiles[2].hit)
end)

H.test("the magnifier icons show only while the AH is open and a recipe is displayed", function()
    local T, Window = boot()
    local function icons(want)
        H.eq(Window.parts.tiles[1].icon.shown == true, want)
        H.eq(Window.frame().titleIcon.shown == true, want)
    end
    local saved = _G.AuctionHouseFrame
    _G.AuctionHouseFrame = { SearchBar = { SearchBox = { searchIcon = { GetAtlas = function() return "a" end } } } }
    local ok, err = pcall(function()
        T.ns.AH.isOpen = false
        Window.render(model())
        icons(false)
        T.ns.AH.isOpen = true
        Window.render(model())
        icons(true)
        Window.showEmpty("Select a recipe")
        icons(false)
    end)
    _G.AuctionHouseFrame = saved
    if not ok then error(err, 0) end
end)

H.test("dragging the AH tile moves the window and reports where it was dropped", function()
    local _, Window, calls = boot()
    Window.render(model())
    local hit = Window.parts.tiles[1].hit
    local starts = 0
    Window.frame().StartMoving = function() starts = starts + 1 end
    H.truthy(hit.scripts.OnDragStart)
    hit.scripts.OnDragStart(hit)
    H.eq(starts, 1)
    hit.scripts.OnDragStop(hit)
    H.eq(calls[#calls], { "onMoved", "TOPLEFT", 100, 700 })
end)

H.test("a click that ends a drag of the AH tile or the title searches nothing", function()
    local _, Window, calls = boot()
    Window.render(model())
    for _, button in ipairs({ Window.parts.tiles[1].hit, Window.frame().titleHit }) do
        button.scripts.OnDragStart(button)
        button.scripts.OnClick(button)
        H.eq(#calls, 0)
    end
    for i, button in ipairs({ Window.parts.tiles[1].hit, Window.frame().titleHit }) do
        button.scripts.OnMouseDown(button)
        button.scripts.OnClick(button)
        H.eq(#calls, i)
        H.eq(calls[i], { "onOutputClick" })
    end
end)

H.test("the header swatch asks to switch the theme", function()
    local _, Window, calls = boot()
    local hit = rawget(Window.frame(), "themeHit")
    H.truthy(hit)
    hit.scripts.OnClick(hit)
    H.eq(calls[#calls], { "onThemeClick" })
end)
