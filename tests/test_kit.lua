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
    local _, Kit = boot()
    local panel = Kit.panel(nil, "MATERIALS")
    local clicks = 0
    local hit = panel:onHeaderClick(function() clicks = clicks + 1 end)
    H.eq(panel.headerHit, hit)
    hit.scripts.OnClick(hit)
    H.eq(clicks, 1)
end)

H.test("the new widgets survive every theme switch", function()
    local _, Kit = boot()
    local check = Kit.check(nil, "x")
    local box = Kit.input(nil, 52, 4)
    for _, name in ipairs({ "copper", "steel", "gold" }) do Kit.applyTheme(name) end
    H.truthy(check and box)
end)
