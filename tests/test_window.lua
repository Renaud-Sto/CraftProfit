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
        "onPerPointToggle", "onCostToggle", "onMoved", "onOutputClick" }) do
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

H.test("the banner is the native banner, built at the content width", function()
    local T, Window = boot()
    local b = Window.parts.banner
    H.eq(Window.parts.frames.banner, b.frame)
    H.eq(b.width, Window.INNER_WIDTH)
    H.eq(type(b.set), "function")
    H.eq(b.fill, { T.ns.Colors.FIXED.trivial[1], T.ns.Colors.FIXED.trivial[2], T.ns.Colors.FIXED.trivial[3], 0.09 })
end)

H.test("the banner tint follows the kind of result and not the theme", function()
    local T, Window = boot()
    local FIXED = T.ns.Colors.FIXED
    local b = Window.parts.banner
    local function check(kind, tone)
        Window.render(model({ banner = { label = "RESULT", text = "Best", value = "1s", kind = kind } }))
        H.eq(b.fill, { tone[1], tone[2], tone[3], 0.09 })
        H.eq(b.edge, { tone[1], tone[2], tone[3], 0.45 })
    end
    check("profit", FIXED.profit)
    check("loss", FIXED.loss)
    check("incomplete", FIXED.incomplete)
    check("none", FIXED.trivial)
    check("loss", FIXED.loss)
    -- An old-Kit theme switch (still used by the pinned list) leaves the tint alone.
    T.ns.Kit.applyTheme("steel")
    H.eq(b.edge, { FIXED.loss[1], FIXED.loss[2], FIXED.loss[3], 0.45 })
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
    H.eq(Window.FOLDED_H, T.ns.Native.HEAD_H + 4)
    H.eq(p.frames.materials.height, Window.FOLDED_H)
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

H.test("reagent rows are native list rows that drag the window, and a click ending a drag searches nothing", function()
    local _, Window, calls = boot()
    Window.render(model())
    local hit = Window.parts.rows[1].hit
    H.truthy(hit.selected)
    H.truthy(hit.hover)
    H.falsy(hit.selected.shown)
    hit.scripts.OnEnter(hit)
    H.truthy(hit.hover.shown)
    hit.scripts.OnLeave(hit)
    H.falsy(hit.hover.shown)
    local starts = 0
    Window.frame().StartMoving = function() starts = starts + 1 end
    hit.scripts.OnDragStart(hit)
    H.eq(starts, 1)
    hit.scripts.OnDragStop(hit)
    H.eq(calls[#calls], { "onMoved", "TOPLEFT", 100, 700 })
    local before = #calls
    hit.scripts.OnClick(hit)
    H.eq(#calls, before)
    hit.scripts.OnMouseDown(hit)
    hit.scripts.OnClick(hit)
    H.eq(calls[#calls], { "onReagentClick", 11, 3 })
end)

H.test("the materials header drags the window too, and the click ending a drag does not fold", function()
    local _, Window, calls = boot()
    Window.render(model())
    local header = Window.parts.materials.headerHit
    header.scripts.OnDragStart(header)
    header.scripts.OnDragStop(header)
    H.eq(calls[#calls], { "onMoved", "TOPLEFT", 100, 700 })
    header.scripts.OnClick(header)
    H.eq(#calls, 1)
    header.scripts.OnMouseDown(header)
    header.scripts.OnClick(header)
    H.eq(calls[#calls], { "onCostToggle", false })
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
    -- A game check button flips itself before OnClick; the fake does not, so flip here.
    p.track:SetChecked(false)
    p.track.scripts.OnClick(p.track)
    H.eq(calls[#calls], { "onTrackToggle", false })
    p.perPoint:SetChecked(true)
    p.perPoint.scripts.OnClick(p.perPoint)
    H.eq(calls[#calls], { "onPerPointToggle", true })
end)

H.test("the per-point value follows the model line: hidden, a cost, or a gain with a plus", function()
    local T, Window = boot()
    local FIXED = T.ns.Colors.FIXED
    local p = Window.parts
    Window.render(model())
    H.falsy(p.perPointValue.shown)
    local colour
    p.perPointValue.SetTextColor = function(_, r, g, b) colour = { r, g, b } end
    Window.render(model({ showPerPoint = true, lines = { { label = "Cost per point", value = "12s (25%, estimate)", key = "perpoint", tone = "loss" } } }))
    H.truthy(p.perPointValue.shown)
    H.eq(p.perPointValue.text, "12s (25%, estimate)")
    H.eq(colour, { FIXED.loss[1], FIXED.loss[2], FIXED.loss[3] })
    Window.render(model({ showPerPoint = true, lines = { { label = "Gain per point", value = "9s (75%, estimate)", key = "perpoint", tone = "profit" } } }))
    H.eq(p.perPointValue.text, "+9s (75%, estimate)")
    H.eq(colour, { FIXED.profit[1], FIXED.profit[2], FIXED.profit[3] })
end)

H.test("the pin button reads Pin or Unpin and reports its click", function()
    local _, Window, calls = boot()
    Window.render(model({ pinned = false }))
    H.eq(Window.parts.pin.text, "Pin")
    Window.render(model({ pinned = true }))
    H.eq(Window.parts.pin.text, "Unpin")
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
    local Kit, Native = T.ns.Kit, T.ns.Native
    local function keys(list) local k = {} for i, s in ipairs(list) do k[i] = s.key end return k end
    local list = Window.sections({ hasLikely = false, expanded = true, reagents = 2 })
    H.eq(keys(list), { "banner", "tiles", "materials", "age", "options" })
    -- Native.panel: 2 px edge + header + body pad + rows + 2 px edge, as Kit.panelHeight.
    H.eq(Native.HEAD_H, Kit.HEAD_H)
    H.eq(list[3].height, Kit.panelHeight(2, 18))
    -- An option row holds the 24 px check box (button and input are 22) and 2 px of air.
    H.eq(Native.CHECK_SIZE + 2, 26)
    H.eq(list[5].height, Kit.panelHeight(3, 26))
    H.eq(keys(Window.sections({ hasLikely = true, expanded = true, reagents = 0 })),
        { "banner", "tiles", "likely", "materials", "age", "options" })
    H.eq(Window.sections({ hasLikely = false, expanded = false, reagents = 9 })[3].height, Window.FOLDED_H)
end)

H.test("the options body is exactly three option rows", function()
    local T, Window = boot()
    local list = Window.sections({ hasLikely = false, expanded = true, reagents = 0 })
    -- Height of the panel minus its header, body pads and edges (Kit.panelHeight(0, x)).
    H.eq(list[5].height - T.ns.Kit.panelHeight(0, 26), 3 * 26)
end)

H.test("the frame height is the sum of the visible sections plus the insets, and the pinned list adds its own", function()
    local T, Window = boot()
    local Native = T.ns.Native
    local chrome = Native.INSET_TOP + Native.INSET_BOTTOM
    local function sum(list)
        local total = 0
        for _, s in ipairs(list) do total = total + s.height end
        return total + Window.GAP * (#list - 1)
    end
    Window.render(model())
    local list = Window.sections({ hasLikely = false, expanded = true, reagents = 2 })
    local inner = sum(list) + Native.CONTENT_PAD * 2
    H.eq(Window.contentHeightOf(list), inner)
    H.eq(Window.frame().height, chrome + inner)
    Window.pinsHost():Show()
    Window.pinsHost():SetHeight(100)
    Window.relayout()
    H.eq(Window.frame().height, chrome + inner + Window.GAP + 100)
    Window.pinsHost():Hide()
    Window.relayout()
    H.eq(Window.frame().height, chrome + inner)
end)

H.test("the frame height follows a folded Materials panel and a likely line", function()
    local T, Window = boot()
    local Native = T.ns.Native
    local chrome = Native.INSET_TOP + Native.INSET_BOTTOM
    Window.render(model({ costExpanded = false }))
    local folded = Window.sections({ hasLikely = false, expanded = false, reagents = 2 })
    H.eq(Window.frame().height, chrome + Window.contentHeightOf(folded))
    local lines = { { label = "75%: 1-2x Dust = 5s", value = "", key = "likely" } }
    Window.render(model({ lines = lines }))
    local withLikely = Window.sections({ hasLikely = true, expanded = true, reagents = 2 })
    H.eq(Window.frame().height, chrome + Window.contentHeightOf(withLikely))
    H.eq(Window.contentHeightOf(withLikely) - Window.contentHeightOf(
        Window.sections({ hasLikely = false, expanded = true, reagents = 2 })), 16 + Window.GAP)
end)

-- Records the anchors of every section frame (reset by ClearAllPoints).
local function sectionPoints(Window)
    local points = {}
    for key, f in pairs(Window.parts.frames) do
        f.SetPoint = function(_, ...) points[key] = points[key] or {}; table.insert(points[key], { ... }) end
        f.ClearAllPoints = function() points[key] = {} end
    end
    return points
end

H.test("sections are stacked inside the inset's content margin, a gap apart", function()
    -- A client whose ButtonFrameTemplate has its Inset: content is the inset.
    local T = W.boot(H)
    local create = T.env.CreateFrame
    T.env.CreateFrame = function(kind, name, parent, template)
        local f = create(kind, name, parent, template)
        if template == "ButtonFrameTemplate" then f.Inset = W.frame() end
        return f
    end
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    local Window = T.ns.Window
    local content = Window.frame().content
    H.truthy(content ~= Window.frame())
    local points = sectionPoints(Window)
    Window.render(model())
    local pad = 4
    H.eq(points.banner[1], { "TOPLEFT", content, "TOPLEFT", pad, -pad })
    H.eq(points.banner[2], { "TOPRIGHT", content, "TOPRIGHT", -pad, -pad })
    H.eq(points.tiles[1], { "TOPLEFT", content, "TOPLEFT", pad, -(pad + 52 + Window.GAP) })
end)

H.test("without an inset (changed build) the sections start at the inset's edges of the frame", function()
    local T, Window = boot()
    local Native = T.ns.Native
    local frame = Window.frame()
    H.eq(frame.content, frame)
    local points = sectionPoints(Window)
    Window.render(model())
    local pad = Native.CONTENT_PAD
    H.eq(points.banner[1], { "TOPLEFT", frame, "TOPLEFT", Native.INSET_LEFT + pad, -Native.INSET_TOP - pad })
    H.eq(points.banner[2], { "TOPRIGHT", frame, "TOPRIGHT", -Native.INSET_RIGHT - pad, -Native.INSET_TOP - pad })
    H.eq(points.tiles[1][5], -Native.INSET_TOP - pad - 52 - Window.GAP)
end)

H.test("the per-point check's hit area never reaches under its value", function()
    local T, Window = boot()
    local Native = T.ns.Native
    local p = Window.parts
    local inset
    p.perPoint.SetHitRectInsets = function(_, _, right) inset = right end
    -- A label far wider than the row, a value 60 px wide.
    p.perPoint.label.GetUnboundedStringWidth = function() return 400 end
    p.perPointValue.GetUnboundedStringWidth = function() return 60 end
    local bodyWidth = Window.INNER_WIDTH - Native.PANEL_EDGE * 2
    local checkLeft = 8
    local function hitRight() return checkLeft + Native.CHECK_SIZE - inset end
    Window.render(model({ showPerPoint = true, lines = { { label = "Cost per point", value = "12s (25%, estimate)", key = "perpoint", tone = "loss" } } }))
    local valueLeft = bodyWidth - 8 - 60
    H.truthy(hitRight() <= valueLeft)
    H.truthy(hitRight() > valueLeft - 8)
    -- Value hidden: the label may use the room up to the body's margin, never past it.
    Window.render(model())
    H.truthy(hitRight() <= bodyWidth - 8)
    H.truthy(hitRight() > valueLeft)
    -- A short label keeps a hit area just over its own width.
    p.perPoint.label.GetUnboundedStringWidth = function() return 50 end
    Window.render(model())
    H.eq(inset, -(50 + 4))
end)

H.test("an empty window shows the message and hides every section", function()
    local T, Window = boot()
    local Native = T.ns.Native
    Window.render(model())
    Window.showEmpty("Select a recipe")
    local p = Window.parts
    H.eq(p.empty.text, "Select a recipe")
    H.truthy(p.empty.shown)
    for key, f in pairs(p.frames) do
        if f.shown then error("section still shown: " .. key) end
    end
    H.eq(Window.frame().titleText.text, "CraftProfit")
    H.eq(Window.frame().height, Native.INSET_TOP + Native.CONTENT_PAD * 2 + 24 + Native.INSET_BOTTOM)
    H.eq(Window.lastModel, nil)
end)

H.test("dropping the window reports its position", function()
    local _, Window, calls = boot()
    Window.frame().scripts.OnDragStop(Window.frame())
    H.eq(calls[#calls], { "onMoved", "TOPLEFT", 100, 700 })
end)

H.test("a neutral per-point value is the game's main text colour, a cost keeps its meaning colour", function()
    local T, Window = boot()
    local Kit, Colors = T.ns.Kit, T.ns.Colors
    local p = Window.parts
    local colour
    p.perPointValue.SetTextColor = function(_, r, g, b) colour = { r, g, b } end
    Window.render(model({ showPerPoint = true, lines = { { label = "Cost per point", value = "?", key = "perpoint" } } }))
    local main = Colors.text("main")
    H.eq(colour, { main[1], main[2], main[3] })
    Window.render(model({ showPerPoint = true, lines = { { label = "Cost per point", value = "1s", key = "perpoint", tone = "loss" } } }))
    colour = nil
    -- The old Kit's theme switch no longer repaints the main window.
    Kit.applyTheme("steel")
    H.eq(colour, nil)
    Window.render(model({ showPerPoint = true, lines = { { label = "Cost per point", value = "1s", key = "perpoint", tone = "loss" } } }))
    H.eq(colour, { Colors.FIXED.loss[1], Colors.FIXED.loss[2], Colors.FIXED.loss[3] })
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
    local best = T.ns.Colors.FIXED.best
    local b = Window.parts.banner
    -- 240 px in the normal font, 190 in the small one; the fake frame has no width, so the
    -- room is measured on INNER_WIDTH: 349 - 24 - value - 8.
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
    local esc = T.ns.Colors.escape(T.ns.Colors.FIXED.incomplete)
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
    local Native = T.ns.Native
    H.eq(Window.INNER_WIDTH, 372 - Native.INSET_LEFT - Native.INSET_RIGHT - Native.CONTENT_PAD * 2)
    H.eq(Window.INNER_WIDTH, 349)
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
    -- The last section ends one content margin above the inset's bottom.
    local top = Native.INSET_TOP + Window.contentHeightOf(list) - Native.CONTENT_PAD + Window.GAP
    local last = points[#points]
    H.eq(last[1], "TOPLEFT")
    H.eq(last[2], Window.frame())
    H.eq(last[3], "TOPLEFT")
    H.eq(last[4], Native.INSET_LEFT + Native.CONTENT_PAD)
    H.eq(last[5], -top)
    -- Without the pinned list the host keeps its place but adds nothing to the height.
    host:Hide()
    Window.relayout()
    H.eq(points[#points][5], -top)
    H.eq(Window.frame().height, Native.INSET_TOP + Window.contentHeightOf(list) + Native.INSET_BOTTOM)
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
    local _, Window = boot()
    local sizes = {}
    -- the tile frames are created before the test can wrap them: read their widths back
    for i, tile in ipairs(Window.parts.tiles) do sizes[i] = tile.width end
    H.eq(sizes[1] + sizes[2] + sizes[3] + Window.GAP * 2, Window.INNER_WIDTH)
    H.truthy(Window.parts.tiles[1].variant)
end)

H.test("the empty-state, likely and age texts are muted game grey, a stale age is amber", function()
    local T, Window = boot({ record = true })
    local Colors = T.ns.Colors
    local muted, stale = Colors.text("muted"), Colors.FIXED.stale
    local p = Window.parts
    local function last(fs) return fs.log[#fs.log] end
    H.eq(last(p.empty), { "colour", muted[1], muted[2], muted[3] })
    H.eq(last(p.likely), { "colour", muted[1], muted[2], muted[3] })
    Window.render(model())
    H.eq(last(p.age), { "colour", muted[1], muted[2], muted[3] })
    Window.render(model({ stale = true }))
    H.eq(last(p.age), { "colour", stale[1], stale[2], stale[3] })
    local count = #p.empty.log
    T.ns.Kit.applyTheme("steel")
    H.eq(#p.empty.log, count)
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

H.test("the main window has no theme swatch and is given no theme handler", function()
    local T = W.boot(H)
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    local Window = T.ns.Window
    H.eq(rawget(Window.frame(), "themeHit"), nil)
    H.eq(rawget(Window.lastHandlers, "onThemeClick"), nil)
end)

H.test("the window is a native panel: named, with its title button and the pin button 120 px wide", function()
    local T = W.boot(H)
    local made = {}
    local create = T.env.CreateFrame
    T.env.CreateFrame = function(kind, name, parent, template)
        local f = create(kind, name, parent, template)
        f.template, f.frameName = template or false, name or false
        f.SetSize = function(self, w, h) self.size = { w, h } end
        made[#made + 1] = f
        return f
    end
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    local Window = T.ns.Window
    H.eq(Window.frame().template, "ButtonFrameTemplate")
    H.eq(Window.frame().frameName, "CraftProfitWindow")
    H.truthy(rawget(Window.frame(), "titleHit"))
    H.eq(Window.parts.pin.template, "UIPanelButtonTemplate")
    H.eq(Window.parts.pin.size, { 120, 22 })
    H.eq(Window.parts.craftsBox.template, "InputBoxTemplate")
    H.eq(Window.parts.track.template, "UICheckButtonTemplate")
    H.eq(Window.parts.perPoint.template, "UICheckButtonTemplate")
end)

H.test("attach uses the saved position, else sits beside the target, else near the centre", function()
    local T, Window = boot()
    local frame = Window.frame()
    local points
    frame.ClearAllPoints = function() points = {} end
    frame.SetPoint = function(_, ...) points[#points + 1] = { ... } end
    local target = W.frame()
    Window.attach(target, { point = "TOPLEFT", x = 120, y = 640 })
    H.eq(points, { { "TOPLEFT", T.env.UIParent, "BOTTOMLEFT", 120, 640 } })
    Window.attach(target, { point = "CENTER", x = 5, y = 6 })
    H.eq(points, { { "CENTER", T.env.UIParent, "CENTER", 5, 6 } })
    Window.attach(target, nil)
    H.eq(points, { { "TOPLEFT", target, "TOPRIGHT", 6, 0 } })
    Window.attach(nil, nil)
    H.eq(points, { { "CENTER", T.env.UIParent, "CENTER", 300, 0 } })
end)
