local H = ...
local W = dofile("tests/fakewow.lua")

local function load()
    return H.newNS("Theme", "UI/Kit").Kit
end

H.test("panelHeight adds the header, the body padding and the rows", function()
    local Kit = load()
    H.eq(Kit.panelHeight(3, 18), 22 + 8 + 54)
    H.eq(Kit.panelHeight(0, 18), 30)
    H.eq(Kit.panelHeight(nil, 18), 30)
    H.eq(Kit.panelHeight(-4, 18), 30)
    H.eq(Kit.panelHeight(2, 18, 10), 22 + 8 + 36 + 10)
    H.eq(Kit.panelHeight(2.9, 10), 22 + 8 + 20)
end)

H.test("stack places panels one under the other with a gap and reports the total", function()
    local Kit = load()
    local offsets, total = Kit.stack({ 30, 20 }, 8, 10)
    H.eq(offsets, { -10, -48 })
    H.eq(total, 58)
    offsets, total = Kit.stack({ 50 }, 8)
    H.eq(offsets, { 0 })
    H.eq(total, 50)
    offsets, total = Kit.stack({}, 8)
    H.eq(offsets, {})
    H.eq(total, 0)
end)

H.test("fitSize picks the largest size that fits, the smallest when none does", function()
    local Kit = load()
    local sizes = { 19, 17, 15, 13 }
    H.eq(Kit.fitSize(100, 19, 120, sizes), 19)
    H.eq(Kit.fitSize(150, 19, 120, sizes), 15)
    H.eq(Kit.fitSize(1000, 19, 120, sizes), 13)
    H.eq(Kit.fitSize(nil, 19, 120, sizes), 19)
    H.eq(Kit.fitSize("x", 19, 120, sizes), 19)
    H.eq(Kit.fitSize(150, 0, 120, sizes), 19)
end)

local function withColor(fn)
    local saved = _G.CreateColor
    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    local ok, err = pcall(fn)
    _G.CreateColor = saved
    if not ok then error(err, 0) end
end

local TOP, BOTTOM = { 1, 0, 0, 1 }, { 0, 0, 1, 1 }

H.test("gradient uses colour objects when the client takes them, bottom colour first", function()
    local Kit = load()
    withColor(function()
        local got
        local tex = { SetGradient = function(_, orientation, a, b) got = { orientation, a, b } end }
        H.eq(Kit.gradient(tex, TOP, BOTTOM), "color")
        H.eq(got[1], "VERTICAL")
        H.eq(got[2].b, 1)
        H.eq(got[3].r, 1)
    end)
end)

H.test("gradient falls back to the six-number signature, then to a flat colour", function()
    local Kit = load()
    local saved = _G.CreateColor
    _G.CreateColor = nil
    local got
    local tex = { SetGradient = function(_, orientation, r1, _, b1, r2) got = { orientation, r1, b1, r2 } end }
    H.eq(Kit.gradient(tex, TOP, BOTTOM), "rgb")
    H.eq(got, { "VERTICAL", 0, 1, 1 })
    local flat
    local failing = {
        SetGradient = function() error("bad signature") end,
        SetColorTexture = function(_, r, g, b, a) flat = { r, g, b, a } end,
    }
    H.eq(Kit.gradient(failing, TOP, BOTTOM), "flat")
    H.eq(flat, { 0.5, 0, 0.5, 1 })
    flat = nil
    local missing = { SetColorTexture = function(_, r, g, b, a) flat = { r, g, b, a } end }
    H.eq(Kit.gradient(missing, TOP, BOTTOM), "flat")
    H.eq(flat, { 0.5, 0, 0.5, 1 })
    _G.CreateColor = saved
end)

H.test("gradient gives the texture a white base before tinting it", function()
    local Kit = load()
    local calls = {}
    local tex = {
        SetColorTexture = function(_, r, g, b, a) calls[#calls + 1] = { "base", r, g, b, a } end,
        SetGradient = function() calls[#calls + 1] = { "gradient" } end,
    }
    Kit.gradient(tex, TOP, BOTTOM)
    H.eq(calls[1], { "base", 1, 1, 1, 1 })
    H.eq(calls[2], { "gradient" })
end)

H.test("the kit file is loaded by the fake game environment", function()
    local T = W.boot(H)
    H.truthy(T.ns.Kit)
    H.truthy(T.ns.Theme)
end)

local function boot()
    local T = W.boot(H)
    return T, T.ns.Kit, T.env
end

H.test("applyTheme switches the current theme, twice in a row, and ignores unknown names", function()
    local _, Kit = boot()
    H.eq(Kit.themeName, "gold")
    for _, name in ipairs({ "copper", "steel", "steel", "gold" }) do
        Kit.applyTheme(name)
        H.eq(Kit.themeName, name)
        H.eq(Kit.current.name, name)
    end
    Kit.applyTheme("nope")
    H.eq(Kit.themeName, "gold")
end)

H.test("every widget survives every theme being applied after it was built", function()
    local _, Kit = boot()
    local win = Kit.window("KitTestWindow", "Title", { width = 372 })
    local panel = Kit.panel(win.content, "MATERIALS")
    panel:setRows(3, 18)
    local button = Kit.button(win.content, "primary", "Go")
    local small = Kit.button(win.content, "small", "x")
    local normal = Kit.button(win.content, "normal", "Ok")
    local tile = Kit.tile(win.content, 110, 52)
    tile:set({ label = "AH (NET)", value = "3g 24s", best = true })
    for _, name in ipairs({ "copper", "steel", "gold" }) do
        Kit.applyTheme(name)
    end
    H.truthy(button and small and normal)
    H.eq(panel:height(), 84)
end)

H.test("applying a theme repaints existing widgets with that theme's colours", function()
    local T, Kit = boot()
    local panel = Kit.panel(nil, "MATERIALS")
    local last
    panel.title.SetTextColor = function(_, r, g, b, a) last = { r, g, b, a } end
    Kit.applyTheme("steel")
    local steel = T.ns.Theme.get("steel").headText
    local gold = T.ns.Theme.get("gold").headText
    H.eq(last, { steel[1], steel[2], steel[3], steel[4] })
    H.truthy(steel[1] ~= gold[1] or steel[2] ~= gold[2] or steel[3] ~= gold[3])
end)

H.test("the window reports where it was dropped and sizes its plaque to the title", function()
    local _, Kit = boot()
    local moved
    local win = Kit.window("KitTestWindow2", "A title", { onMoved = function(...) moved = { ... } end })
    win.scripts.OnDragStop(win)
    H.eq(moved, { "TOPLEFT", 100, 700 })
    local plaqueWidth
    win.plaque.SetWidth = function(_, w) plaqueWidth = w end
    local measured = 300
    win.titleText.GetStringWidth = function() return measured end
    win:setTitle("Another title")
    H.eq(plaqueWidth, 344)
    measured = 50
    win:setTitle("X")
    H.eq(plaqueWidth, 210)
end)

H.test("a panel keeps its title and right-hand text", function()
    local _, Kit = boot()
    local panel = Kit.panel(nil, "MATERIALS")
    H.eq(panel.title.text, "MATERIALS")
    panel:setTitle("OPTIONS")
    H.eq(panel.title.text, "OPTIONS")
    panel.right:SetText("2g 33s")
    H.eq(panel.right.text, "2g 33s")
end)

H.test("a tile shows its label, tag and value, and remembers whether it is the best one", function()
    local _, Kit = boot()
    local tile = Kit.tile(nil, 110, 52)
    tile:set({ label = "DISENCH.", tag = "beta", value = "2g 2s" })
    H.truthy(tile.label.text:find("DISENCH.", 1, true))
    H.truthy(tile.label.text:find("beta", 1, true))
    H.eq(tile.value.text, "2g 2s")
    H.falsy(tile.best)
    tile:set({ label = "AH", value = "3g 24s", best = true })
    H.truthy(tile.best)
    tile:set({ label = "AH", value = "n/a", muted = true })
    H.falsy(tile.best)
    tile:set({})
    H.eq(tile.value.text, "")
end)

H.test("a tile steps its value font down until the text fits, and keeps the big size when it does", function()
    local _, Kit = boot()
    local tile = Kit.tile(nil, 110, 52)
    local sizes = {}
    local measured = 200
    tile.value.SetFont = function(_, _, size) sizes[#sizes + 1] = size end
    tile.value.GetStringWidth = function() return measured end
    tile:set({ label = "AH", value = "123456g 12s" })
    local expected = Kit.fitSize(200, 19, 110 - Kit.TILE_PAD * 2, Kit.TILE_SIZES)
    H.truthy(expected < Kit.TILE_SIZES[1])
    H.eq(sizes[#sizes], expected)
    sizes = {}
    measured = 60
    tile:set({ label = "AH", value = "1g" })
    H.eq(sizes[#sizes], 19)
end)

H.test("a button keeps the text it is given and runs its click handler", function()
    local _, Kit = boot()
    local clicks = 0
    local button = Kit.button(nil, "normal", "Scan")
    H.eq(button.label.text, "Scan")
    button:setText("Search")
    H.eq(button.label.text, "Search")
    button:SetScript("OnClick", function() clicks = clicks + 1 end)
    button.scripts.OnClick(button)
    H.eq(clicks, 1)
end)

-- Wrap CreateFrame so frames start shown, as on the real client.
local function realisticFrames(T)
    local made = { count = 0 }
    local orig = T.env.CreateFrame
    T.env.CreateFrame = function(kind, name, ...)
        local f = orig(kind, name, ...)
        f.shown = true
        made.count = made.count + 1
        if name == "CraftProfitKitDemo" then made.demo = f end
        return f
    end
    return made
end

H.test("kitdemo shows the demo window in the asked theme and toggles without one", function()
    local T = W.boot(H)
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    local made = realisticFrames(T)
    local slash = T.env.SlashCmdList.CRAFTPROFIT
    slash("kitdemo")
    H.truthy(made.demo)
    H.eq(made.demo.shown, true)
    slash("kitdemo")
    H.eq(made.demo.shown, false)
    slash("kitdemo")
    H.eq(made.demo.shown, true)
    slash("kitdemo copper")
    H.eq(T.ns.Kit.themeName, "copper")
    slash("kitdemo")
    H.eq(made.demo.shown, false)
    slash("kitdemo steel")
    H.eq(made.demo.shown, true)
    H.eq(T.ns.Kit.themeName, "steel")
end)

H.test("kitdemo with an unknown theme says so and keeps the current theme", function()
    local T = W.boot(H)
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    local made = realisticFrames(T)
    T.env.SlashCmdList.CRAFTPROFIT("kitdemo nope")
    H.eq(made.count, 0)
    H.eq(made.demo, nil)
    H.eq(T.ns.Kit.themeName, "gold")
    local said = table.concat(T.chat, "\n")
    H.truthy(said:find("nope", 1, true))
    H.truthy(said:find("gold, copper, steel", 1, true))
end)

H.test("a small button fits the usable height of a panel header with equal margins", function()
    local Kit = load()
    -- 1 px panel ring above, 1 px header rule below: HEAD_H - 1 pixels are usable.
    local usable = Kit.HEAD_H - 1
    H.eq((usable - Kit.SMALL_BUTTON_H) % 2, 0)
    H.truthy(Kit.SMALL_BUTTON_H <= usable - 2)
end)

-- Frames whose textures record the last colour they were given, so a repaint is observable.
local function recordingFrames(T)
    local rec = {}
    local create = T.env.CreateFrame
    T.env.CreateFrame = function(...)
        local f = create(...)
        f.CreateTexture = function()
            local tex = W.frame()
            tex.SetColorTexture = function(self, r, g, b, a) self.color = { r, g, b, a } end
            rec[#rec + 1] = tex
            return tex
        end
        return f
    end
    return rec
end

H.test("mix moves a colour toward another by a fraction, channel by channel", function()
    local Kit = load()
    H.eq(Kit.mix({ 0, 0, 0, 1 }, { 1, 0.5, 1, 0 }, 0.5), { 0.5, 0.25, 0.5, 0.5 })
    H.eq(Kit.mix({ 0.2, 0.2, 0.2, 1 }, { 1, 1, 1, 1 }, 0), { 0.2, 0.2, 0.2, 1 })
end)

H.test("colorEscape turns a colour into a chat colour escape and clamps out-of-range channels", function()
    local Kit = load()
    H.eq(Kit.colorEscape({ 1, 0.82, 0, 1 }), "|cffffd100")
    H.eq(Kit.colorEscape({ 0, 0, 0, 1 }), "|cff000000")
    H.eq(Kit.colorEscape({ 2, -1, 0.5, 1 }), "|cffff0080")
end)

H.test("plaqueWidth keeps the minimum, grows with the title and stops at the window width", function()
    local Kit = load()
    H.eq(Kit.plaqueWidth(50, 348), 210)
    H.eq(Kit.plaqueWidth(200, 348), 244)
    H.eq(Kit.plaqueWidth(400, 348), 348)
    H.eq(Kit.plaqueWidth(nil, 348), 210)
    H.eq(Kit.plaqueWidth(300, nil), 344)
end)

H.test("onTheme paints now and again on every theme switch", function()
    local _, Kit = boot()
    local seen = {}
    Kit.onTheme(function(t) seen[#seen + 1] = t.name end)
    Kit.applyTheme("steel")
    H.eq(seen, { "gold", "steel" })
end)

H.test("rings accept a function returning a colour table", function()
    local T, Kit = boot()
    local rec = recordingFrames(T)
    local frame = T.env.CreateFrame("Frame")
    local edge = { 1, 0, 0, 0.5 }
    local refresh = Kit.rings(frame, { function() return edge end })
    H.eq(rec[1].color, { 1, 0, 0, 0.5 })
    edge[1] = 0.25
    refresh()
    H.eq(rec[1].color, { 0.25, 0, 0, 0.5 })
end)

H.test("the best tile gets a 2 px bright outline and a gold tint, the others a 1 px dark ring and no fill", function()
    local T, Kit = boot()
    local rec = recordingFrames(T)
    local Theme = T.ns.Theme
    local gold = Theme.get("gold")
    local tile = Kit.tile(nil, 110, 52)
    -- creation order: background, fill, outer ring (4 textures), second ring (4 textures)
    local fill = rec[2]
    local function ring(first) local r = {} for i = first, first + 3 do r[#r + 1] = rec[i].color end return r end
    local function all(list, want)
        for _, c in ipairs(list) do H.eq(c, want) end
    end
    tile:set({ label = "AH", value = "1g", best = true })
    H.eq(fill.color, gold.bestFill)
    all(ring(3), gold.bestEdge)
    all(ring(7), gold.bestEdge)
    tile:set({ label = "AH", value = "1g", best = false })
    H.eq(fill.color[4], 0)
    all(ring(3), gold.panelEdge)
    all(ring(7), gold.panelBg)
    tile:set({ label = "AH", value = "1g", best = true })
    Kit.applyTheme("steel")
    local steel = Theme.get("steel")
    H.eq(fill.color, steel.bestFill)
    all(ring(3), steel.bestEdge)
    all(ring(7), steel.bestEdge)
end)

H.test("a normal button lights up on hover and a primary one gets a lighter fill", function()
    local T, Kit = boot()
    local rec = recordingFrames(T)
    local Theme = T.ns.Theme
    local gold = Theme.get("gold")
    local normal = Kit.button(nil, "normal", "Ok")
    H.eq(rec[1].color, gold.buttonBg)
    normal.scripts.OnEnter(normal)
    H.eq(rec[1].color, gold.primaryBg)
    normal.scripts.OnLeave(normal)
    H.eq(rec[1].color, gold.buttonBg)
    local before = #rec
    local primary = Kit.button(nil, "primary", "Go")
    local bg = rec[before + 1]
    H.eq(bg.color, gold.primaryBg)
    primary.scripts.OnEnter(primary)
    H.eq(bg.color, Kit.mix(gold.primaryBg, gold.primaryEdge, 0.35))
end)

H.test("the plaque drags the window", function()
    local _, Kit = boot()
    local moved
    local win = Kit.window("KitTestPlaque", "T", { onMoved = function(...) moved = { ... } end })
    H.truthy(win.plaque.scripts.OnDragStart)
    win.plaque.scripts.OnDragStop(win.plaque)
    H.eq(moved, { "TOPLEFT", 100, 700 })
end)

H.test("a long title uses the small font and the plaque stops short of the close button", function()
    local _, Kit = boot()
    H.eq(Kit.CLOSE_ROOM, 30)
    local win = Kit.window("KitTestTitle", "T", { width = 372 })
    local fonts, widths = {}, {}
    win.GetWidth = function() return 372 end
    win.titleText.SetFontObject = function(_, name) fonts[#fonts + 1] = name end
    win.titleText.GetStringWidth = function() return 500 end
    win.plaque.SetWidth = function(_, w) widths[#widths + 1] = w end
    win:setTitle("A very long recipe name")
    H.eq(fonts, { "GameFontNormal", "GameFontNormalSmall" })
    H.eq(widths[#widths], 372 - Kit.CLOSE_ROOM * 2)
    H.eq(widths[#widths], 312)
end)

H.test("the title is measured unbounded when the client can, and normally otherwise", function()
    local _, Kit = boot()
    local win = Kit.window("KitTestTitle2", "T", { width = 372 })
    local fonts, widths = {}, {}
    win.GetWidth = function() return 372 end
    win.titleText.SetFontObject = function(_, name) fonts[#fonts + 1] = name end
    win.titleText.GetStringWidth = function() return 100 end
    win.titleText.GetUnboundedStringWidth = function() return 500 end
    win.plaque.SetWidth = function(_, w) widths[#widths + 1] = w end
    win:setTitle("A very long recipe name")
    H.eq(fonts, { "GameFontNormal", "GameFontNormalSmall" })
    H.eq(widths[#widths], 312)
    fonts = {}
    win.titleText.GetUnboundedStringWidth = function() return 100 end
    win.titleText.GetStringWidth = function() return 500 end
    win:setTitle("Short")
    H.eq(fonts, { "GameFontNormal" })
    H.eq(widths[#widths], 210)
    win.titleText.GetUnboundedStringWidth = nil
    fonts = {}
    win:setTitle("Long again")
    H.eq(fonts, { "GameFontNormal", "GameFontNormalSmall" })
    H.eq(widths[#widths], 312)
end)

H.test("setTitle repaints the title colour and so does a theme switch", function()
    local T, Kit = boot()
    local Theme = T.ns.Theme
    local win = Kit.window("KitTestTitle3", "T")
    local last
    win.titleText.SetTextColor = function(_, r, g, b, a) last = { r, g, b, a } end
    win:setTitle("x")
    H.eq(last, Theme.get("gold").plaqueText)
    Kit.applyTheme("steel")
    H.eq(last, Theme.get("steel").plaqueText)
end)

H.test("a tile shrinks its value by the unbounded width, not the capped one", function()
    local _, Kit = boot()
    local tile = Kit.tile(nil, 110, 52)
    local sizes = {}
    tile.value.SetFont = function(_, _, size) sizes[#sizes + 1] = size end
    tile.value.GetStringWidth = function() return 50 end
    tile.value.GetUnboundedStringWidth = function() return 200 end
    tile:set({ label = "AH", value = "123456g 12s" })
    local expected = Kit.fitSize(200, 19, 110 - Kit.TILE_PAD * 2, Kit.TILE_SIZES)
    H.truthy(expected < Kit.TILE_SIZES[1])
    H.eq(sizes[#sizes], expected)
end)

H.test("panel.right and the tile tag are painted from the theme, not a literal colour", function()
    local T, Kit = boot()
    local Theme = T.ns.Theme
    local panel = Kit.panel(nil, "X")
    local last
    panel.right.SetTextColor = function(_, r, g, b, a) last = { r, g, b, a } end
    Kit.applyTheme("steel")
    H.eq(last, Theme.get("steel").textMain)
    local tile = Kit.tile(nil, 110, 52)
    tile:set({ label = "DISENCH.", tag = "beta", value = "1g" })
    H.truthy(tile.label.text:find(Kit.colorEscape(Theme.FIXED.best) .. "beta", 1, true))
end)

H.test("a check box toggles on click, reports the new state and keeps its text", function()
    local _, Kit = boot()
    local seen = {}
    local check = Kit.check(nil, "Track history")
    H.eq(check.label.text, "Track history")
    H.falsy(check:GetChecked())
    H.falsy(check.mark.shown)
    check.onToggle = function(checked) seen[#seen + 1] = checked end
    check.scripts.OnClick(check)
    H.truthy(check:GetChecked())
    H.truthy(check.mark.shown)
    check.scripts.OnClick(check)
    H.falsy(check:GetChecked())
    H.eq(seen, { true, false })
    check:SetChecked(true)
    H.truthy(check:GetChecked())
    check:SetChecked(nil)
    H.falsy(check:GetChecked())
    check:setText("Cost per point")
    H.eq(check.label.text, "Cost per point")
end)

H.test("clicking a check box without a callback does not raise", function()
    local _, Kit = boot()
    local check = Kit.check(nil, "x")
    check.scripts.OnClick(check)
    H.truthy(check:GetChecked())
end)

H.test("an input box gives up its focus on Enter and Escape", function()
    local _, Kit = boot()
    local box = Kit.input(nil, 52, 4)
    local cleared = 0
    box.ClearFocus = function() cleared = cleared + 1 end
    box.scripts.OnEnterPressed(box)
    box.scripts.OnEscapePressed(box)
    H.eq(cleared, 2)
end)

H.test("a panel header can be made clickable", function()
    local _, Kit, env = boot()
    local made = env.CreateFrame
    env.CreateFrame = function(...)
        local f = made(...)
        f.GetFrameLevel = function() return 5 end
        f.SetFrameLevel = function(self, level) self.level = level end
        return f
    end
    local panel = Kit.panel(nil, "MATERIALS")
    local clicks = 0
    local hit = panel:onHeaderClick(function() clicks = clicks + 1 end)
    H.eq(panel.headerHit, hit)
    H.eq(hit.level, 5)
    hit.scripts.OnClick(hit)
    H.eq(clicks, 1)
end)

H.test("the new widgets survive every theme switch and repaint with the new colours", function()
    local T, Kit = boot()
    local Theme = T.ns.Theme
    local check = Kit.check(nil, "x")
    local box = Kit.input(nil, 52, 4)
    local got = {}
    box.SetTextColor = function(_, r, g, b, a) got.input = { r, g, b, a } end
    check.label.SetTextColor = function(_, r, g, b, a) got.label = { r, g, b, a } end
    check.mark.SetColorTexture = function(_, r, g, b, a) got.mark = { r, g, b, a } end
    for _, name in ipairs({ "copper", "steel", "gold" }) do Kit.applyTheme(name) end
    local steel, gold = Theme.get("steel"), Theme.get("gold")
    Kit.applyTheme("steel")
    H.eq(got.input, steel.textMain)
    H.eq(got.label, steel.textMain)
    H.eq(got.mark, steel.checkMark)
    H.falsy(gold.textMain[1] == steel.textMain[1] and gold.textMain[2] == steel.textMain[2]
        and gold.textMain[3] == steel.textMain[3])
    H.falsy(gold.checkMark[1] == steel.checkMark[1] and gold.checkMark[2] == steel.checkMark[2]
        and gold.checkMark[3] == steel.checkMark[3])
end)

H.test("naturalWidth prefers the unbounded width and falls back to the string width", function()
    local Kit = load()
    local fs = W.frame()
    fs.GetStringWidth = function() return 40 end
    H.eq(Kit.naturalWidth(fs), 40)
    fs.GetUnboundedStringWidth = function() return 90 end
    H.eq(Kit.naturalWidth(fs), 90)
end)

H.test("scrollThumb sizes and places the thumb, nil when the list fits", function()
    local Kit = load()
    local h, top = Kit.scrollThumb(12, 6, 0, 100)
    H.eq({ h, top }, { 50, 0 })
    h, top = Kit.scrollThumb(12, 6, 6, 100)
    H.eq({ h, top }, { 50, 50 })
    h, top = Kit.scrollThumb(12, 6, 3, 100)
    H.eq({ h, top }, { 50, 25 })
    h = Kit.scrollThumb(1000, 6, 0, 100)
    H.eq(h, Kit.SCROLL_MIN_THUMB)
    H.eq(Kit.scrollThumb(6, 6, 0, 100), nil)
    H.eq(Kit.scrollThumb(3, 6, 0, 100), nil)
    H.eq(Kit.scrollThumb(12, 0, 0, 100), nil)
    H.eq(Kit.scrollThumb(12, 6, 0, 0), nil)
    H.eq(Kit.scrollThumb(nil, 6, 0, 100), nil)
    top = select(2, Kit.scrollThumb(12, 6, 99, 100))
    H.eq(top, 50)
    top = select(2, Kit.scrollThumb(12, 6, -4, 100))
    H.eq(top, 0)
end)

H.test("scrollOffsetAt maps a pointer position to a row offset and clamps it", function()
    local Kit = load()
    H.eq(Kit.scrollOffsetAt(12, 6, 100, 0), 0)
    H.eq(Kit.scrollOffsetAt(12, 6, 100, 100), 6)
    H.eq(Kit.scrollOffsetAt(12, 6, 100, 50), 3)
    H.eq(Kit.scrollOffsetAt(12, 6, 100, -30), 0)
    H.eq(Kit.scrollOffsetAt(12, 6, 100, 400), 6)
    H.eq(Kit.scrollOffsetAt(5, 6, 100, 50), 0)
    H.eq(Kit.scrollOffsetAt(nil, 6, 100, 50), 0)
end)

local function withCursor(y, fn)
    local saved = _G.GetCursorPosition
    _G.GetCursorPosition = function() return 0, y end
    local ok, err = pcall(fn)
    _G.GetCursorPosition = saved
    if not ok then error(err, 0) end
end

H.test("the scroll bar hides when the list fits and shows a thumb of the right size otherwise", function()
    local _, Kit = boot()
    local bar = Kit.scrollbar(nil, 100)
    H.falsy(bar:update(6, 6, 0))
    H.falsy(bar.frame.shown)
    local heights = {}
    bar.thumb.SetHeight = function(_, h) heights[#heights + 1] = h end
    H.truthy(bar:update(12, 6, 3))
    H.truthy(bar.frame.shown)
    H.eq(heights[#heights], 50)
    H.falsy(bar:update(4, 6, 0))
    H.falsy(bar.frame.shown)
end)

H.test("clicking the scroll bar track asks for the matching offset and dragging follows the pointer", function()
    local _, Kit = boot()
    local bar = Kit.scrollbar(nil, 100)
    local asked = {}
    bar.onScroll = function(offset) asked[#asked + 1] = offset end
    bar:update(12, 6, 0)
    bar.frame.GetTop = function() return 700 end
    bar.frame.GetEffectiveScale = function() return 1 end
    -- pointer 100 px below the top of the track: bottom of the track, last offset
    withCursor(600, function() bar.frame.scripts.OnMouseDown(bar.frame) end)
    H.eq(asked, { 6 })
    bar:update(12, 6, 6)
    -- still pressed: moving to the middle follows it
    withCursor(650, function() bar.frame.scripts.OnUpdate(bar.frame) end)
    H.eq(asked, { 6, 3 })
    -- released: no more following
    bar.frame.scripts.OnMouseUp(bar.frame)
    withCursor(700, function() bar.frame.scripts.OnUpdate(bar.frame) end)
    H.eq(asked, { 6, 3 })
end)

H.test("the scroll bar ignores a pointer it cannot measure and works without a callback", function()
    local _, Kit = boot()
    local bar = Kit.scrollbar(nil, 100)
    bar:update(12, 6, 0)
    -- the fake environment has no GetCursorPosition; a client that cannot say answers nil
    local saved = _G.GetCursorPosition
    _G.GetCursorPosition = function() end
    bar.frame.scripts.OnMouseDown(bar.frame)
    bar.frame.scripts.OnUpdate(bar.frame)
    _G.GetCursorPosition = saved
    bar.frame.GetTop = function() return 700 end
    bar.frame.GetEffectiveScale = function() return 1 end
    withCursor(600, function() bar.frame.scripts.OnMouseDown(bar.frame) end)
    bar.frame.scripts.OnMouseUp(bar.frame)
end)

H.test("the scroll bar is painted from the theme and survives theme switches", function()
    local T, Kit = boot()
    local rec = recordingFrames(T)
    local Theme = T.ns.Theme
    local bar = Kit.scrollbar(nil, 100)
    H.eq(rec[1].color, Theme.get("gold").inputBg)
    H.eq(rec[2].color, Theme.get("gold").frameInner)
    Kit.applyTheme("steel")
    H.eq(rec[1].color, Theme.get("steel").inputBg)
    H.eq(rec[2].color, Theme.get("steel").frameInner)
    H.truthy(bar)
end)

H.test("onHeaderClick called twice reuses the hit button and replaces its handler", function()
    local _, Kit = boot()
    local panel = Kit.panel(nil, "X")
    local hits = {}
    local first = panel:onHeaderClick(function() hits[#hits + 1] = "a" end)
    local second = panel:onHeaderClick(function() hits[#hits + 1] = "b" end)
    H.eq(first, second)
    first.scripts.OnClick(first)
    H.eq(hits, { "b" })
end)

H.test("the label of a check box is part of its click area", function()
    local _, Kit = boot()
    local check = Kit.check(nil, "")
    local insets
    check.SetHitRectInsets = function(_, l, r, t, b) insets = { l, r, t, b } end
    check.label.GetUnboundedStringWidth = function() return 100 end
    check:setText("Show grey recipes")
    H.eq(insets, { 0, -106, 0, 0 })
    -- a width that cannot be measured leaves only the square clickable
    check.label.GetUnboundedStringWidth = function() return nil end
    check.label.GetStringWidth = function() return nil end
    check:setText("x")
    H.eq(insets, { 0, 0, 0, 0 })
end)

local function withGlobals(values, fn)
    local saved = {}
    for k, v in pairs(values) do saved[k] = _G[k]; _G[k] = v end
    local ok, err = pcall(fn)
    for k in pairs(values) do _G[k] = saved[k] end
    if not ok then error(err, 0) end
end

local function fakeTexture()
    local t = W.frame()
    t.calls = {}
    t.SetAtlas = function(_, a) t.calls[#t.calls + 1] = { "atlas", a } end
    t.SetTexture = function(_, p) t.calls[#t.calls + 1] = { "texture", p } end
    t.SetTexCoord = function(_, ...) t.calls[#t.calls + 1] = { "coord", ... } end
    return t
end

H.test("searchIcon copies the AH search box icon (atlas first, then texture and coordinates)", function()
    local _, Kit = boot()
    local source = { GetAtlas = function() return "common-search-magnifyingglass" end }
    withGlobals({ AuctionHouseFrame = { SearchBar = { SearchBox = { searchIcon = source } } } }, function()
        local tex = fakeTexture()
        H.truthy(Kit.searchIcon(tex))
        H.eq(tex.calls, { { "atlas", "common-search-magnifyingglass" } })
    end)
    local plain = { GetAtlas = function() return nil end, GetTexture = function() return "Interface\\X" end,
        GetTexCoord = function() return 0, 1, 0, 1 end }
    withGlobals({ AuctionHouseFrame = { SearchBar = { SearchBox = { SearchIcon = plain } } } }, function()
        local tex = fakeTexture()
        H.truthy(Kit.searchIcon(tex))
        H.eq(tex.calls, { { "texture", "Interface\\X" }, { "coord", 0, 1, 0, 1 } })
    end)
end)

H.test("searchIcon falls back to a verified atlas and gives up without drawing anything", function()
    local _, Kit = boot()
    withGlobals({ AuctionHouseFrame = false, C_Texture = { GetAtlasInfo = function(name)
        if name == "common-search-magnifyingglass" then return { width = 14 } end
    end } }, function()
        local tex = fakeTexture()
        H.truthy(Kit.searchIcon(tex))
        H.eq(tex.calls, { { "atlas", "common-search-magnifyingglass" } })
    end)
    withGlobals({ AuctionHouseFrame = false, C_Texture = { GetAtlasInfo = function() return nil end } }, function()
        local tex = fakeTexture()
        H.falsy(Kit.searchIcon(tex))
        H.eq(tex.calls, {})
    end)
    withGlobals({ AuctionHouseFrame = false, C_Texture = false }, function()
        H.falsy(Kit.searchIcon(fakeTexture()))
    end)
    withGlobals({ AuctionHouseFrame = { SearchBar = { SearchBox = { searchIcon = { GetAtlas = function() error("x") end } } } },
        C_Texture = false }, function()
        H.falsy(Kit.searchIcon(fakeTexture()))
    end)
end)

H.test("a tile can be made clickable, with a hover tint and a magnifier that shows on request", function()
    local T, Kit = boot()
    recordingFrames(T)
    local clicks = 0
    local tile = Kit.tile(nil, 110, 52)
    local hit = tile:onClick(function() clicks = clicks + 1 end)
    H.eq(tile.hit, hit)
    hit.scripts.OnClick(hit)
    H.eq(clicks, 1)
    local again = tile:onClick(function() clicks = clicks + 10 end)
    H.eq(again, hit)
    hit.scripts.OnClick(hit)
    H.eq(clicks, 11)
    withGlobals({ AuctionHouseFrame = { SearchBar = { SearchBox = { searchIcon = { GetAtlas = function() return "a" end } } } } }, function()
        tile.icon.SetAtlas = function() end
        tile:showIcon(true)
        H.truthy(tile.icon.shown)
        tile:showIcon(false)
        H.falsy(tile.icon.shown)
    end)
    withGlobals({ AuctionHouseFrame = false, C_Texture = false }, function()
        tile:showIcon(true)
        H.falsy(tile.icon.shown)
    end)
    -- The tint belongs to the tile frame (under its fill, outline and texts), not to the button.
    H.falsy(tile.tint.shown)
    hit.scripts.OnEnter(hit)
    H.truthy(tile.tint.shown)
    hit.scripts.OnLeave(hit)
    H.falsy(tile.tint.shown)
    -- Every theme uses the same rowHover today, so check that a repaint happens and
    -- gives the steel colour.
    local painted
    tile.tint.SetColorTexture = function(_, r, g, b, a) painted = { r, g, b, a } end
    Kit.applyTheme("steel")
    H.eq(painted, T.ns.Theme.get("steel").rowHover)
end)

H.test("the window title can be clicked, drags the window and lights up on hover", function()
    local _, Kit = boot()
    local moved, clicked = nil, 0
    local win = Kit.window("KitTitleClick", "Recipe", { onMoved = function(...) moved = { ... } end,
        onTitleClick = function() clicked = clicked + 1 end })
    local hit = win.titleHit
    H.truthy(hit)
    hit.scripts.OnClick(hit)
    H.eq(clicked, 1)
    local starts = 0
    win.StartMoving = function() starts = starts + 1 end
    hit.scripts.OnDragStart(hit)
    H.eq(starts, 1)
    hit.scripts.OnDragStop(hit)
    H.eq(moved, { "TOPLEFT", 100, 700 })
    local colours = {}
    win.titleText.SetTextColor = function(_, r, g, b, a) colours[#colours + 1] = { r, g, b, a } end
    hit.scripts.OnEnter(hit)
    H.eq(colours[#colours], Kit.current.textMain)
    hit.scripts.OnLeave(hit)
    H.eq(colours[#colours], Kit.current.plaqueText)
    H.truthy(win.titleIcon)
    win:showTitleIcon(false)
    H.falsy(win.titleIcon.shown)
end)

H.test("a window without a title click has no title button", function()
    local _, Kit = boot()
    local win = Kit.window("KitPlain", "Plain", {})
    -- rawget: a fake frame answers any missing key with a no-op method
    H.falsy(rawget(win, "titleHit"))
end)

H.test("a click that ends a drag runs no handler, on the tile and on the title", function()
    local _, Kit = boot()
    local clicks = {}
    local win = Kit.window("KitDragClick", "Recipe", { onTitleClick = function() clicks[#clicks + 1] = "title" end })
    local tile = Kit.tile(win.content, 110, 52)
    local hit = tile:onClick(function() clicks[#clicks + 1] = "tile" end)
    Kit.forwardDrag(hit, win)
    local title = win.titleHit
    for _, button in ipairs({ hit, title }) do
        button.scripts.OnDragStart(button)
        button.scripts.OnClick(button)
    end
    H.eq(clicks, {})
    for _, button in ipairs({ hit, title }) do
        button.scripts.OnMouseDown(button)
        button.scripts.OnClick(button)
    end
    H.eq(clicks, { "tile", "title" })
    -- a replaced tile handler keeps the guard
    tile:onClick(function() clicks[#clicks + 1] = "tile2" end)
    hit.scripts.OnDragStart(hit)
    hit.scripts.OnClick(hit)
    hit.scripts.OnMouseDown(hit)
    hit.scripts.OnClick(hit)
    H.eq(clicks, { "tile", "title", "tile2" })
end)

H.test("scrollGrab keeps the place of a thumb grabbed anywhere and centres a pointer off the thumb", function()
    local Kit = load()
    -- 12 rows, 6 visible, track 100: the thumb is 50 high; at offset 0 it covers y 0..50
    H.eq(Kit.scrollGrab(12, 6, 0, 100, 10), 10)
    H.eq(Kit.scrollGrab(12, 6, 0, 100, 50), 50)
    H.eq(Kit.scrollGrab(12, 6, 0, 100, 80), 25)
    -- at offset 6 it covers y 50..100
    H.eq(Kit.scrollGrab(12, 6, 6, 100, 60), 10)
    H.eq(Kit.scrollGrab(12, 6, 6, 100, 20), 25)
    H.eq(Kit.scrollGrab(6, 6, 0, 100, 10), nil)
    H.eq(Kit.scrollGrab(nil, 6, 0, 100, 10), nil)
end)

H.test("grabbing the thumb off-centre does not move the list, then dragging follows the pointer", function()
    local _, Kit = boot()
    local bar = Kit.scrollbar(nil, 100)
    local asked = {}
    bar.onScroll = function(offset) asked[#asked + 1] = offset end
    bar:update(12, 6, 3)             -- thumb at y 25..75
    bar.frame.GetTop = function() return 700 end
    bar.frame.GetEffectiveScale = function() return 1 end
    -- press near the top edge of the thumb (y = 28): the list must not jump
    withCursor(672, function() bar.frame.scripts.OnMouseDown(bar.frame, "LeftButton") end)
    H.eq(asked, {})
    -- move 22 px down: the thumb follows (50 free px for 6 rows: 3 + 2.64, rounded to 6)
    withCursor(650, function() bar.frame.scripts.OnUpdate(bar.frame) end)
    H.eq(asked, { 6 })
end)

H.test("only the left button starts a drag and a lost mouse-up ends it", function()
    local _, Kit = boot()
    local bar = Kit.scrollbar(nil, 100)
    local asked = {}
    bar.onScroll = function(offset) asked[#asked + 1] = offset end
    bar:update(12, 6, 0)
    bar.frame.GetTop = function() return 700 end
    bar.frame.GetEffectiveScale = function() return 1 end
    withCursor(600, function() bar.frame.scripts.OnMouseDown(bar.frame, "RightButton") end)
    H.eq(asked, {})
    withCursor(600, function() bar.frame.scripts.OnUpdate(bar.frame) end)
    H.eq(asked, {})
    local saved = _G.IsMouseButtonDown
    _G.IsMouseButtonDown = function() return true end
    withCursor(600, function() bar.frame.scripts.OnMouseDown(bar.frame, "LeftButton") end)
    H.eq(asked, { 6 })
    bar:update(12, 6, 6)
    -- the button is no longer down although no mouse-up arrived: the drag stops
    _G.IsMouseButtonDown = function() return false end
    withCursor(650, function() bar.frame.scripts.OnUpdate(bar.frame) end)
    H.eq(asked, { 6 })
    _G.IsMouseButtonDown = saved
end)

H.test("a list row has a hidden selected tint, a hover tint and the anchors of its slot", function()
    local T, Kit = boot()
    local points, textures = {}, {}
    local create = T.env.CreateFrame
    T.env.CreateFrame = function(...)
        local f = create(...)
        f.SetPoint = function(_, ...) points[#points + 1] = { ... } end
        f.CreateTexture = function()
            local t = W.frame()
            t.SetColorTexture = function(self, r, g, b, a) self.color = { r, g, b, a } end
            textures[#textures + 1] = t
            return t
        end
        return f
    end
    local body = {}
    local row = Kit.listRow(body, 3, 18, 14)
    H.eq(points[1], { "TOPLEFT", body, "TOPLEFT", 0, -36 })
    H.eq(points[2], { "TOPRIGHT", body, "TOPRIGHT", -14, -36 })
    local selected, hover = textures[1], textures[2]
    H.eq(row.selected, selected)
    H.falsy(selected.shown)
    H.falsy(hover.shown)
    H.eq(selected.color, T.ns.Theme.get("gold").bestFill)
    H.eq(hover.color, T.ns.Theme.get("gold").rowHover)
    row.scripts.OnEnter(row)
    H.truthy(hover.shown)
    row.scripts.OnLeave(row)
    H.falsy(hover.shown)
    Kit.applyTheme("steel")
    H.eq(selected.color, T.ns.Theme.get("steel").bestFill)
end)

H.test("the window title is measured and painted only when it changes", function()
    local _, Kit = boot()
    local win = Kit.window("KitTitleOnce", "Recipe", {})
    local measures = 0
    win.titleText.GetUnboundedStringWidth = function() measures = measures + 1; return 100 end
    win.titleText.GetStringWidth = function() measures = measures + 1; return 100 end
    win:setTitle("Another")
    local first = measures
    H.truthy(first > 0)
    win:setTitle("Another")
    win:setTitle("Another")
    H.eq(measures, first)
    win:setTitle("Yet another")
    H.truthy(measures > first)
end)

H.test("a window can have a theme swatch that runs its handler and shows the theme colour", function()
    local T, Kit = boot()
    recordingFrames(T)
    local clicks = 0
    local win = Kit.window("KitSwatch", "T", { onThemeClick = function() clicks = clicks + 1 end })
    local hit = win.themeHit
    H.truthy(hit)
    hit.scripts.OnClick(hit)
    H.eq(clicks, 1)
    H.eq(win.themeSwatch.color, T.ns.Theme.get("gold").frameOuter)
    Kit.applyTheme("copper")
    H.eq(win.themeSwatch.color, T.ns.Theme.get("copper").frameOuter)
    Kit.applyTheme("steel")
    H.eq(win.themeSwatch.color, T.ns.Theme.get("steel").frameOuter)
end)

H.test("a window without a theme handler has no swatch", function()
    local _, Kit = boot()
    H.falsy(rawget(Kit.window("KitNoSwatch", "T", {}), "themeHit"))
end)
