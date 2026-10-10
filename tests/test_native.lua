local H = ...
local W = dofile("tests/fakewow.lua")

-- The fake frame answers every unknown key with a no-op function, so template internals
-- (Inset, TitleContainer, Text...) look present but are not tables: the module must treat
-- them as missing. `rawget` reads what the module really stored on a frame.

local function boot()
    local T = W.boot(H)
    return T, T.ns.Native, T.env
end

-- Records every CreateFrame call and makes frames start shown, as on the real client.
local function recordFrames(env)
    local made = {}
    local create = env.CreateFrame
    env.CreateFrame = function(kind, name, parent, template)
        local f = create(kind, name, parent, template)
        f.shown = true
        -- false, not nil: a nil field would read as the fake's no-op function.
        f.kind, f.template, f.createParent = kind, template, parent or false
        f.SetParent = function(self, p) self.parent = p end
        f.SetSize = function(self, w, h) self.size = { w, h } end
        made[#made + 1] = f
        return f
    end
    return made
end

H.test("the native module loads beside the kit without game globals", function()
    local ns = H.newNS("Colors", "Theme", "UI/Kit", "UI/Native")
    H.truthy(ns.Native)
    H.eq(ns.Native.CONTENT_PAD, 4)
end)

H.test("the native file is loaded by the fake game environment, after the kit", function()
    local T = W.boot(H)
    H.truthy(T.ns.Native)
    H.truthy(T.ns.Kit)
end)

H.test("a window is a ButtonFrameTemplate made without a parent, then put under UIParent, hidden", function()
    local _, Native, env = boot()
    local made = recordFrames(env)
    local win = Native.window("NativeTestWindow", "Title", { width = 400, height = 300 })
    H.eq(made[1], win)
    H.eq(win.kind, "Frame")
    H.eq(win.template, "ButtonFrameTemplate")
    H.eq(win.createParent, false)
    H.eq(win.parent, env.UIParent)
    H.eq(win.shown, false)
    H.truthy(rawget(win, "content"))
    H.eq(type(rawget(win, "setTitle")), "function")
    H.eq(type(rawget(win, "stopDrag")), "function")
end)

H.test("a window does not raise when the template helpers and internals are missing", function()
    local _, Native, env = boot()
    H.eq(env.ButtonFrameTemplate_HidePortrait, nil)
    H.eq(env.ButtonFrameTemplate_HideButtonBar, nil)
    H.eq(env.ButtonFrameTemplate_HideAttic, nil)
    local win = Native.window("NativeTestBare", "Title")
    -- No real Inset: the frame itself is the content area, with its own title string.
    H.eq(win.content, win)
    win:setTitle("Another")
    H.eq(rawget(win, "titleText").text, "Another")
end)

H.test("a window hides the portrait and the button bar and uses the inset when the client has them", function()
    local _, Native, env = boot()
    local calls = {}
    env.ButtonFrameTemplate_HideAttic = function(f) calls[#calls + 1] = { "attic", f } end
    env.ButtonFrameTemplate_HidePortrait = function(f) calls[#calls + 1] = { "portrait", f } end
    env.ButtonFrameTemplate_HideButtonBar = function(f) calls[#calls + 1] = { "bar", f } end
    local inset = W.frame()
    local titleText = W.frame()
    local container = W.frame()
    container.TitleText = titleText
    local create = env.CreateFrame
    env.CreateFrame = function(kind, name, parent, template)
        local f = create(kind, name, parent, template)
        if template == "ButtonFrameTemplate" then
            f.Inset = inset
            f.TitleContainer = container
            f.SetTitle = function(self, text) self.TitleContainer.TitleText:SetText(text) end
        end
        return f
    end
    local win = Native.window("NativeTestFull", "Hello")
    -- The attic goes first: HideAttic resets the inset's x, HidePortrait then sets it.
    H.eq(calls, { { "attic", win }, { "portrait", win }, { "bar", win } })
    H.eq(win.content, inset)
    H.eq(titleText.text, "Hello")
    win:setTitle("Changed")
    H.eq(titleText.text, "Changed")
end)

H.test("a helper that raises on a changed build does not break the window", function()
    local _, Native, env = boot()
    env.ButtonFrameTemplate_HidePortrait = function() error("SetBorder is gone") end
    local win = Native.window("NativeTestRaise", "T")
    H.truthy(win.content)
end)

H.test("a window drags from its body and reports where it was dropped", function()
    local _, Native = boot()
    local moved
    local win = Native.window("NativeTestDrag", "T", { onMoved = function(...) moved = { ... } end })
    H.truthy(win.scripts.OnDragStart)
    win.scripts.OnDragStop(win)
    H.eq(moved, { "TOPLEFT", 100, 700 })
end)

H.test("the title hit button exists only with onTitleClick", function()
    local _, Native = boot()
    local plain = Native.window("NativeTestNoHit", "T")
    H.eq(rawget(plain, "titleHit"), nil)
    H.eq(rawget(plain, "titleIcon"), nil)
    local win = Native.window("NativeTestHit", "T", { onTitleClick = function() end })
    H.truthy(rawget(win, "titleHit"))
    H.truthy(rawget(win, "titleIcon"))
end)

H.test("the title hit button is a Button, fires on click and not on the click that ends a drag", function()
    local _, Native, env = boot()
    local made = recordFrames(env)
    local clicks, moved = 0, 0
    local win = Native.window("NativeTestTitleClick", "T", {
        onTitleClick = function() clicks = clicks + 1 end,
        onMoved = function() moved = moved + 1 end,
    })
    local hit = win.titleHit
    local found
    for _, f in ipairs(made) do if f == hit then found = f end end
    H.eq(found.kind, "Button")
    hit.scripts.OnMouseDown(hit)
    hit.scripts.OnClick(hit)
    H.eq(clicks, 1)
    hit.scripts.OnMouseDown(hit)
    hit.scripts.OnDragStart(hit)
    hit.scripts.OnDragStop(hit)
    hit.scripts.OnClick(hit)
    H.eq(clicks, 1)
    H.eq(moved, 1)
    -- The next press clears the flag.
    hit.scripts.OnMouseDown(hit)
    hit.scripts.OnClick(hit)
    H.eq(clicks, 2)
end)

H.test("the title hit button stays under the close button", function()
    local _, Native, env = boot()
    local close = W.frame()
    close.level = 510
    close.GetFrameLevel = function(self) return rawget(self, "level") end
    close.SetFrameLevel = function(self, l) self.level = l end
    local create = env.CreateFrame
    env.CreateFrame = function(kind, name, parent, template)
        local f = create(kind, name, parent, template)
        f.GetFrameLevel = function(self) return rawget(self, "level") or 1 end
        f.SetFrameLevel = function(self, l) self.level = l end
        if template == "ButtonFrameTemplate" then f.CloseButton = close end
        return f
    end
    local win = Native.window("NativeTestLevels", "T", { onTitleClick = function() end })
    H.truthy(win.titleHit:GetFrameLevel() < close:GetFrameLevel())
    -- Even when the close button sits low, it is raised over the hit.
    close.level = 1
    local win2 = Native.window("NativeTestLevels2", "T", { onTitleClick = function() end })
    H.truthy(win2.titleHit:GetFrameLevel() < close:GetFrameLevel())
end)

H.test("a button is a UIPanelButtonTemplate 22 px high that fires onClick, not when disabled", function()
    local _, Native, env = boot()
    local made = recordFrames(env)
    local clicks = 0
    local b = Native.button(nil, "Scan", { width = 90, onClick = function() clicks = clicks + 1 end })
    H.eq(made[1], b)
    H.eq(b.kind, "Button")
    H.eq(b.template, "UIPanelButtonTemplate")
    H.eq(b.createParent, false)
    H.eq(b.size, { 90, 22 })
    H.eq(b.text, "Scan")
    b.scripts.OnClick(b)
    H.eq(clicks, 1)
    b.IsEnabled = function() return false end
    b.scripts.OnClick(b)
    H.eq(clicks, 1)
    b:setText("Search")
    H.eq(b.text, "Search")
end)

H.test("a button label never wraps and spans the button minus 8 px on each side", function()
    local _, Native, env = boot()
    local label = W.frame()
    local wrap
    local points = {}
    label.SetWordWrap = function(_, v) wrap = v end
    label.SetPoint = function(_, point, rel, relPoint, x, y) points[#points + 1] = { point, rel, relPoint, x, y } end
    local create = env.CreateFrame
    env.CreateFrame = function(kind, name, parent, template)
        local f = create(kind, name, parent, template)
        if template == "UIPanelButtonTemplate" then f.Text = label end
        return f
    end
    local b = Native.button(nil, "A label far too long for a small button", { width = 40 })
    H.eq(wrap, false)
    H.eq(points, { { "LEFT", b, "LEFT", 8, 0 }, { "RIGHT", b, "RIGHT", -8, 0 } })
end)

H.test("a check box is a UICheckButtonTemplate whose click reports the state the client set", function()
    local _, Native, env = boot()
    local made = recordFrames(env)
    local seen = {}
    local check = Native.check(nil, "Track history", function(v) seen[#seen + 1] = v end)
    H.eq(made[1], check)
    H.eq(check.kind, "CheckButton")
    H.eq(check.template, "UICheckButtonTemplate")
    H.falsy(check:GetChecked())
    -- The client flips a CheckButton before OnClick runs: mimic it.
    check:SetChecked(true)
    check.scripts.OnClick(check)
    check:SetChecked(false)
    check.scripts.OnClick(check)
    H.eq(seen, { true, false })
end)

H.test("clicking a check box label toggles it: the hit area covers the label", function()
    local _, Native, env = boot()
    local label = W.frame()
    label.GetStringWidth = function() return 80 end
    local insets
    local create = env.CreateFrame
    env.CreateFrame = function(kind, name, parent, template)
        local f = create(kind, name, parent, template)
        if template == "UICheckButtonTemplate" then
            f.Text = label
            f.SetHitRectInsets = function(_, l, r, t, b) insets = { l, r, t, b } end
        end
        return f
    end
    local check = Native.check(nil, "Cost per point")
    H.eq(label.text, "Cost per point")
    H.truthy(insets[2] <= -80)
    H.eq({ insets[1], insets[3], insets[4] }, { 0, 0, 0 })
    label.GetStringWidth = function() return 150 end
    check:setText("A much longer label")
    H.eq(label.text, "A much longer label")
    H.truthy(insets[2] <= -150)
end)

H.test("a check box without the template label falls back to its own and plays the toggle sounds", function()
    local _, Native, env = boot()
    local sounds = {}
    env.SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 856, IG_MAINMENU_OPTION_CHECKBOX_OFF = 857 }
    env.PlaySound = function(id) sounds[#sounds + 1] = id end
    local check = Native.check(nil, "x")
    H.eq(rawget(check, "label").text, "x")
    check:SetChecked(true)
    check.scripts.OnClick(check)
    check:SetChecked(false)
    check.scripts.OnClick(check)
    H.eq(sounds, { 856, 857 })
    check:setText("y")
    H.eq(rawget(check, "label").text, "y")
end)

H.test("clicking a check box without a callback or sounds does not raise", function()
    local _, Native = boot()
    local check = Native.check(nil, "x")
    check:SetChecked(true)
    check.scripts.OnClick(check)
    H.truthy(check:GetChecked())
end)

H.test("an input is an InputBoxTemplate without auto focus that gives up its focus on Enter and Escape", function()
    local _, Native, env = boot()
    local made = recordFrames(env)
    local auto, letters
    local create = env.CreateFrame
    env.CreateFrame = function(...)
        local f = create(...)
        f.SetAutoFocus = function(_, v) auto = v end
        f.SetMaxLetters = function(_, n) letters = n end
        return f
    end
    local box = Native.input(nil, 52, 4)
    H.eq(made[1], box)
    H.eq(box.kind, "EditBox")
    H.eq(box.template, "InputBoxTemplate")
    H.eq(box.createParent, false)
    H.eq(box.size, { 52, 22 })
    H.eq(auto, false)
    H.eq(letters, 4)
    local cleared = 0
    box.ClearFocus = function() cleared = cleared + 1 end
    box.scripts.OnEnterPressed(box)
    box.scripts.OnEscapePressed(box)
    H.eq(cleared, 2)
end)

H.test("searchIcon uses the game's magnifier atlas when the client knows it", function()
    local _, Native, env = boot()
    local tex = W.frame()
    local atlas
    tex.SetAtlas = function(_, name) atlas = name end
    env.C_Texture = { GetAtlasInfo = function(name)
        if name == "common-search-magnifyingglass" then return { width = 24, height = 24 } end
    end }
    H.eq(Native.searchIcon(tex), true)
    H.eq(atlas, "common-search-magnifyingglass")
end)

H.test("searchIcon falls back to the kit's lookup and reports when nothing was found", function()
    local _, Native, env = boot()
    local tex = W.frame()
    env.C_Texture = nil
    H.eq(Native.searchIcon(tex), false)
    local file
    tex.SetTexture = function(_, f) file = f end
    env.AuctionHouseFrame = { SearchBar = { SearchBox = { searchIcon = {
        GetTexture = function() return 12345 end,
    } } } }
    H.eq(Native.searchIcon(tex), true)
    H.eq(file, 12345)
end)

-- Panel and tile ------------------------------------------------------------------

-- A colour object like the game's (NORMAL_FONT_COLOR...): GetRGB and WrapTextInColorCode.
local function color(r, g, b)
    return {
        GetRGB = function() return r, g, b end,
        WrapTextInColorCode = function(_, text) return "|c" .. r .. g .. b .. text .. "|r" end,
    }
end

-- Makes the client know every atlas.
local function knownAtlases(env)
    env.C_Texture = { GetAtlasInfo = function() return { width = 100, height = 4 } end }
end

-- Records every texture made by a frame: what atlas and colour it got, in creation order.
local function recordTextures(env)
    local textures = {}
    local create = env.CreateFrame
    env.CreateFrame = function(kind, name, parent, template)
        local f = create(kind, name, parent, template)
        f.kind, f.template = kind, template
        f.CreateTexture = function()
            local tex = W.frame()
            tex.SetAtlas = function(self, atlas) self.atlas = atlas end
            tex.SetColorTexture = function(self, r, g, b, a) self.color = { r, g, b, a } end
            textures[#textures + 1] = tex
            return tex
        end
        return f
    end
    return textures
end

local function withAtlas(textures, atlas)
    for _, tex in ipairs(textures) do
        if rawget(tex, "atlas") == atlas then return tex end
    end
    return nil
end

H.test("a panel is as tall as a kit panel with the same rows", function()
    local T, Native = boot()
    local Kit = T.ns.Kit
    local p = Native.panel(nil, "MATERIALS")
    p:setRows(3, 18)
    H.eq(p:height(), Kit.panelHeight(3, 18))
    p:setRows(2, 18, 10)
    H.eq(p:height(), Kit.panelHeight(2, 18, 10))
    -- rowH is kept when not given.
    p:setRows(4)
    H.eq(p:height(), Kit.panelHeight(4, 18))
    H.eq(Native.HEAD_H, Kit.HEAD_H)
end)

H.test("a panel keeps its title and right-hand text and sits on a game inset", function()
    local _, Native, env = boot()
    local made = recordFrames(env)
    local p = Native.panel(nil, "MATERIALS")
    H.eq(p.title.text, "MATERIALS")
    p:setTitle("OPTIONS")
    H.eq(p.title.text, "OPTIONS")
    p.right:SetText("2g 33s")
    H.eq(p.right.text, "2g 33s")
    H.eq(p.inset.template, "InsetFrameTemplate")
    H.eq(p.inset.createParent, p.frame)
    H.truthy(made[1] == p.frame)
end)

H.test("a panel header can be made clickable with one Button at the panel's level", function()
    local _, Native, env = boot()
    recordFrames(env)
    local create = env.CreateFrame
    env.CreateFrame = function(...)
        local f = create(...)
        f.GetFrameLevel = function() return 5 end
        f.SetFrameLevel = function(self, level) self.level = level end
        return f
    end
    local p = Native.panel(nil, "MATERIALS")
    local clicks = 0
    local hit = p:onHeaderClick(function() clicks = clicks + 1 end)
    H.eq(p.headerHit, hit)
    H.eq(hit.kind, "Button")
    H.eq(hit.level, 5)
    hit.scripts.OnClick(hit)
    H.eq(clicks, 1)
    local again = p:onHeaderClick(function() clicks = clicks + 10 end)
    H.eq(again, hit)
    hit.scripts.OnClick(hit)
    H.eq(clicks, 11)
    H.eq(hit.createParent, p.head)
end)

H.test("the header strip uses the variant chosen before the panel was built", function()
    local _, Native, env = boot()
    knownAtlases(env)
    local textures = recordTextures(env)
    H.eq(Native.headerVariant, "b")
    Native.setHeaderVariant("a")
    local a = Native.panel(nil, "A")
    H.eq(a.headerAtlas, "questlog-reward-header-top")
    H.eq(a.headerBg.atlas, "questlog-reward-header-top")
    H.eq(Native.setHeaderVariant("b"), "b")
    local b = Native.panel(nil, "B")
    H.eq(b.headerAtlas, "friends-frame-toptexbg")
    H.truthy(withAtlas(textures, "friends-frame-toptexbg"))
    -- An unknown key keeps the current variant.
    H.eq(Native.setHeaderVariant("zz"), "b")
    H.eq(Native.headerVariant, "b")
    Native.setHeaderVariant("c")
    H.eq(Native.panel(nil, "C").headerAtlas, "_UI-Frame-TopTileStreaks")
    -- The panel built earlier keeps its strip.
    H.eq(a.headerAtlas, "questlog-reward-header-top")
    H.truthy(a.divider)
    H.eq(a.divider.atlas, "perks-divider-short")
end)

H.test("a panel without the header and divider atlases draws a faint gold strip and does not raise", function()
    local _, Native, env = boot()
    env.C_Texture = nil
    env.NORMAL_FONT_COLOR = color(1, 0.82, 0)
    recordTextures(env)
    local p = Native.panel(nil, "X")
    H.eq(p.headerAtlas, nil)
    H.eq(p.divider, nil)
    H.eq(p.headerBg.color, { 1, 0.82, 0, 0.15 })
    -- No colour object either: still no error.
    env.NORMAL_FONT_COLOR = nil
    H.truthy(Native.panel(nil, "Y").frame)
end)

H.test("a tile shows its label, tag and value, and remembers whether it is the best one", function()
    local _, Native, env = boot()
    env.NORMAL_FONT_COLOR = color(1, 0.82, 0)
    local tile = Native.tile(nil, 110, 52)
    tile:set({ label = "DISENCH.", tag = "beta", value = "2g 2s" })
    H.truthy(tile.label.text:find("DISENCH.", 1, true))
    -- The tag in the game's gold, like the Kit's.
    H.truthy(tile.label.text:find("|c10.820beta|r", 1, true))
    H.eq(tile.value.text, "2g 2s")
    H.falsy(tile.best)
    tile:set({ label = "AH", value = "3g 24s", best = true })
    H.truthy(tile.best)
    tile:set({ label = "AH", value = "n/a", muted = true })
    H.falsy(tile.best)
    H.truthy(tile.muted)
    tile:set({})
    H.eq(tile.value.text, "")
    H.eq(tile.label.text, "")
end)

H.test("a muted tile greys its value with the game's disabled colour, otherwise the highlight one", function()
    local _, Native, env = boot()
    env.DISABLED_FONT_COLOR = color(0.5, 0.5, 0.5)
    env.HIGHLIGHT_FONT_COLOR = color(1, 1, 1)
    local tile = Native.tile(nil, 110, 52)
    local last
    tile.value.SetTextColor = function(_, r, g, b) last = { r, g, b } end
    tile:set({ label = "AH", value = "n/a", muted = true })
    H.eq(last, { 0.5, 0.5, 0.5 })
    tile:set({ label = "AH", value = "1g" })
    H.eq(last, { 1, 1, 1 })
end)

H.test("variant a draws the loot card and shows its stroke on the best tile only", function()
    local _, Native, env = boot()
    knownAtlases(env)
    local textures = recordTextures(env)
    H.eq(Native.tileVariant, "b")
    Native.setTileVariant("a")
    local tile = Native.tile(nil, 110, 52)
    H.eq(tile.variant, "a")
    H.eq(tile.bgAtlas, "looting_itemcard_bg")
    local stroke = withAtlas(textures, "looting_itemcard_stroke_normal")
    H.truthy(stroke)
    H.eq(tile.outline, { stroke })
    tile:set({ label = "AH", value = "1g", best = true })
    H.eq(stroke.shown, true)
    tile:set({ label = "AH", value = "1g" })
    H.eq(stroke.shown, false)
end)

H.test("variant b, or a missing card atlas, draws a nested inset with a 2 px gold outline for the best", function()
    local _, Native, env = boot()
    env.NORMAL_FONT_COLOR = color(1, 0.82, 0)
    recordTextures(env)
    env.C_Texture = nil
    local fallback = Native.tile(nil, 110, 52)
    H.eq(fallback.bgAtlas, nil)
    H.eq(fallback.inset.template, "InsetFrameTemplate")
    H.eq(#fallback.outline, 4)
    knownAtlases(env)
    H.eq(Native.setTileVariant("b"), "b")
    H.eq(Native.setTileVariant("nope"), "b")
    local tile = Native.tile(nil, 110, 52)
    H.eq(tile.variant, "b")
    H.eq(tile.bgAtlas, nil)
    H.eq(tile.inset.template, "InsetFrameTemplate")
    H.eq(#tile.outline, 4)
    for _, line in ipairs(tile.outline) do H.eq(line.color, { 1, 0.82, 0, 1 }) end
    tile:set({ label = "AH", value = "1g", best = true })
    for _, line in ipairs(tile.outline) do H.eq(line.shown, true) end
    tile:set({ label = "AH", value = "1g" })
    for _, line in ipairs(tile.outline) do H.eq(line.shown, false) end
end)

H.test("a tile steps its value down the game fonts until it fits, measured unbounded", function()
    local T, Native = boot()
    local Kit = T.ns.Kit
    local tile = Native.tile(nil, 110, 52)
    local fonts = {}
    tile.value.SetFontObject = function(_, name) fonts[#fonts + 1] = name end
    tile.value.GetStringWidth = function() return 50 end
    tile.value.GetUnboundedStringWidth = function() return 200 end
    tile:set({ label = "AH", value = "123456g 12s" })
    local sizes = {}
    for i, font in ipairs(Native.TILE_FONTS) do sizes[i] = font[2] end
    local want = Kit.fitSize(200, sizes[1], 110 - Native.TILE_PAD * 2, sizes)
    H.truthy(want < sizes[1])
    local expected
    for _, font in ipairs(Native.TILE_FONTS) do if font[2] == want then expected = font[1] end end
    H.eq(fonts[#fonts], expected)
    fonts = {}
    tile.value.GetUnboundedStringWidth = function() return 40 end
    tile:set({ label = "AH", value = "1g" })
    H.eq(fonts, { "GameFontNormalHuge" })
end)

H.test("a clickable tile is a Button that fires, not on the click that ends a drag", function()
    local _, Native, env = boot()
    recordFrames(env)
    local tile = Native.tile(nil, 110, 52)
    H.eq(tile.hit, nil)
    local clicks = 0
    local hit = tile:onClick(function() clicks = clicks + 1 end)
    H.eq(tile.hit, hit)
    H.eq(hit.kind, "Button")
    hit.scripts.OnClick(hit)
    H.eq(clicks, 1)
    local win = Native.window("NativeTestTileDrag", "T")
    Native.forwardDrag(hit, win)
    hit.scripts.OnMouseDown(hit)
    hit.scripts.OnDragStart(hit)
    hit.scripts.OnDragStop(hit)
    hit.scripts.OnClick(hit)
    H.eq(clicks, 1)
    H.eq(hit.createParent, tile.frame)
end)

H.test("a tile hover lights it up and showIcon shows the magnifier only when one was found", function()
    local _, Native, env = boot()
    local tile = Native.tile(nil, 110, 52)
    tile:showIcon(true)  -- no hit yet: nothing to show, no error
    local hit = tile:onClick(function() end)
    hit.scripts.OnEnter(hit)
    H.eq(tile.hover.shown, true)
    hit.scripts.OnLeave(hit)
    H.eq(tile.hover.shown, false)
    env.C_Texture = nil
    tile:showIcon(true)
    H.eq(tile.icon.shown, false)
    knownAtlases(env)
    tile:showIcon(true)
    H.eq(tile.icon.shown, true)
    tile:showIcon(false)
    H.eq(tile.icon.shown, false)
end)

-- Native demo (/cp kitdemo) ------------------------------------------------------

-- Boots the addon, makes frames start shown as on the client and records the named ones.
local function demoBoot()
    local T = W.boot(H)
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    local named = {}
    local create = T.env.CreateFrame
    T.env.CreateFrame = function(kind, name, parent, template)
        local f = create(kind, name, parent, template)
        f.shown = true
        if name then named[name] = f end
        return f
    end
    T.env.UISpecialFrames = {}
    return T, named, T.env.SlashCmdList.CRAFTPROFIT
end

local function lastChat(T) return T.chat[#T.chat] end

H.test("kitdemo opens the native demo with the default variants, closes it, and Escape can close it", function()
    local T, named, slash = demoBoot()
    slash("kitdemo")
    local demo = named.CraftProfitNativeDemo
    H.truthy(demo)
    H.eq(demo.shown, true)
    H.eq(T.env.UISpecialFrames, { "CraftProfitNativeDemo" })
    H.truthy(lastChat(T):find("header b (friends-frame-toptexbg), tile b (inset)", 1, true))
    slash("kitdemo")
    H.eq(demo.shown, false)
    slash("kitdemo")
    H.eq(demo.shown, true)
    H.eq(named.CraftProfitKitDemo, nil)
    -- Registered for Escape once, however often it is shown.
    H.eq(#T.env.UISpecialFrames, 1)
end)

H.test("kitdemo b a rebuilds the demo with those variants and keeps them for the next call", function()
    local T, named, slash = demoBoot()
    slash("kitdemo b a")
    local demo = named.CraftProfitNativeDemo
    H.eq(demo.shown, true)
    H.eq(T.ns.Native.headerVariant, "b")
    H.eq(T.ns.Native.tileVariant, "a")
    H.truthy(lastChat(T):find("header b (friends-frame-toptexbg), tile a", 1, true))
    -- Asked again while shown: it stays shown with the new choice.
    slash("kitdemo C B")
    H.eq(demo.shown, true)
    H.eq(T.ns.KitDemo.header, "c")
    H.eq(T.ns.KitDemo.tile, "b")
    slash("kitdemo")
    H.eq(demo.shown, false)
    slash("kitdemo")
    H.eq(demo.shown, true)
    H.eq(T.ns.Native.headerVariant, "c")
    H.eq(T.ns.Native.tileVariant, "b")
    -- One word changes the header and keeps the tile.
    slash("kitdemo a")
    H.eq(T.ns.KitDemo.header, "a")
    H.eq(T.ns.KitDemo.tile, "b")
end)

H.test("kitdemo with an unknown variant prints one line and changes nothing", function()
    local T, named, slash = demoBoot()
    for _, arg in ipairs({ "kitdemo z", "kitdemo a q", "kitdemo a a a" }) do
        local before = #T.chat
        slash(arg)
        H.eq(#T.chat, before + 1)
        H.truthy(lastChat(T):find("unknown variant", 1, true))
    end
    H.eq(named.CraftProfitNativeDemo, nil)
    H.eq(T.ns.KitDemo.header, "b")
    H.eq(T.ns.KitDemo.tile, "b")
end)

H.test("kitdemo old still shows the themed demo", function()
    local T, named, slash = demoBoot()
    slash("kitdemo old steel")
    H.truthy(named.CraftProfitKitDemo)
    H.eq(named.CraftProfitKitDemo.shown, true)
    H.eq(T.ns.Kit.themeName, "steel")
    H.eq(named.CraftProfitNativeDemo, nil)
end)

H.test("the demo title click and the money line work, with plain money when the client gives none", function()
    local T, named, slash = demoBoot()
    local lines = {}
    local create = T.env.CreateFrame
    T.env.CreateFrame = function(...)
        local f = create(...)
        f.CreateFontString = function()
            local fs = W.frame()
            lines[#lines + 1] = fs
            return fs
        end
        return f
    end
    T.env.GetCoinTextureString = function() return nil end
    T.env.GetMoneyString = function() return {} end
    slash("kitdemo")
    local demo = named.CraftProfitNativeDemo
    demo.titleHit.scripts.OnClick(demo.titleHit)
    H.truthy(lastChat(T):find("title clicked", 1, true))
    local found
    for _, fs in ipairs(lines) do
        if type(rawget(fs, "text")) == "string" and fs.text:find("Best price", 1, true) then found = fs.text end
    end
    H.eq(found, "Best price: 21g 29s")
end)

H.test("the demo money line uses the client's coin string when it has one", function()
    local T, _, slash = demoBoot()
    local texts = {}
    local create = T.env.CreateFrame
    T.env.CreateFrame = function(...)
        local f = create(...)
        f.CreateFontString = function()
            local fs = W.frame()
            texts[#texts + 1] = fs
            return fs
        end
        return f
    end
    slash("kitdemo")
    local found
    for _, fs in ipairs(texts) do
        if type(rawget(fs, "text")) == "string" and fs.text:find("Best price", 1, true) then found = fs.text end
    end
    H.eq(found, "Best price: <212900>")
end)

H.test("a check box label is left-justified so a capped width does not centre it", function()
    local _, Native, env = boot()
    local label = W.frame()
    local justify
    label.SetJustifyH = function(_, v) justify = v end
    local create = env.CreateFrame
    env.CreateFrame = function(kind, name, parent, template)
        local f = create(kind, name, parent, template)
        if template == "UICheckButtonTemplate" then f.Text = label end
        return f
    end
    Native.check(nil, "Track", nil, 120)
    H.eq(justify, "LEFT")
end)

H.test("a check box with maxWidth caps its label and its hit area", function()
    local _, Native, env = boot()
    local label = W.frame()
    label.GetStringWidth = function() return 300 end
    local width, wrap, insets
    label.SetWidth = function(_, w) width = w end
    label.SetWordWrap = function(_, v) wrap = v end
    local create = env.CreateFrame
    env.CreateFrame = function(kind, name, parent, template)
        local f = create(kind, name, parent, template)
        if template == "UICheckButtonTemplate" then
            f.Text = label
            f.SetHitRectInsets = function(_, l, r, t, b) insets = { l, r, t, b } end
        end
        return f
    end
    Native.check(nil, "A very long label that would run off the panel", nil, 120)
    H.eq(width, 120)
    H.eq(wrap, false)
    H.truthy(insets[2] <= -120)
    H.truthy(insets[2] > -300)
    -- Without maxWidth the label keeps its natural width.
    width = nil
    Native.check(nil, "x")
    H.eq(width, nil)
end)

H.test("the tile magnifier sits above the texts and the label stops short of it while shown", function()
    local _, Native, env = boot()
    local levels = 0
    local create = env.CreateFrame
    env.CreateFrame = function(...)
        local f = create(...)
        levels = levels + 1
        f.level = 10 + levels
        f.GetFrameLevel = function(self) return rawget(self, "level") end
        f.SetFrameLevel = function(self, l) self.level = l end
        return f
    end
    local tile = Native.tile(nil, 110, 52)
    local rights = {}
    tile.label.SetPoint = function(_, point, _, _, x) if point == "TOPRIGHT" then rights[#rights + 1] = x end end
    local hit = tile:onClick(function() end)
    H.eq(hit:GetFrameLevel(), tile.face:GetFrameLevel() + 1)
    knownAtlases(env)
    tile:showIcon(true)
    H.eq(rights[#rights], -(6 + Native.TILE_ICON + 4))
    tile:showIcon(false)
    H.eq(rights[#rights], -Native.TILE_PAD)
end)

H.test("the window inset constants match the template anchors once everything is hidden", function()
    local _, Native = boot()
    H.eq({ Native.INSET_LEFT, Native.INSET_TOP, Native.INSET_RIGHT, Native.INSET_BOTTOM }, { 9, 24, 6, 4 })
end)

-- Banner --------------------------------------------------------------------------

-- Records the textures and font strings of every frame made from now on, with the calls a
-- banner or a list row makes on them.
local function recordRegions(env)
    local textures, strings, made = {}, {}, {}
    local create = env.CreateFrame
    env.CreateFrame = function(kind, name, parent, template)
        local f = create(kind, name, parent, template)
        f.kind, f.template, f.createParent = kind, template, parent or false
        f.SetPoint = function(self, ...)
            local points = rawget(self, "points") or {}
            points[#points + 1] = { ... }
            self.points = points
        end
        f.CreateTexture = function(_, _, layer, _, sublevel)
            local tex = W.frame()
            tex.layer, tex.sublevel = layer, sublevel
            tex.SetColorTexture = function(self, r, g, b, a) self.color = { r, g, b, a } end
            tex.SetVertexColor = function(self, r, g, b, a) self.vertex = { r, g, b, a } end
            tex.SetTexture = function(self, file) self.file = file end
            tex.SetBlendMode = function(self, mode) self.blend = mode end
            tex.SetWidth = function(self, w) self.width = w end
            textures[#textures + 1] = tex
            return tex
        end
        f.CreateFontString = function(_, _, _, font)
            local fs = W.frame()
            fs.fonts = { font }
            fs.SetFontObject = function(self, fontName) self.fonts[#self.fonts + 1] = fontName end
            fs.SetTextColor = function(self, r, g, b, a) self.textColor = { r, g, b, a } end
            strings[#strings + 1] = fs
            return fs
        end
        made[#made + 1] = f
        return f
    end
    return textures, strings, made
end

local function lastFont(fs) return fs.fonts[#fs.fonts] end

H.test("a banner is a frame on a game inset with a label, a text and a value", function()
    local T, Native, env = boot()
    recordRegions(env)
    local parent = W.frame()
    local banner = Native.banner(parent, 52)
    H.eq(banner.frame.createParent, parent)
    H.eq(banner.frame.height, 52)
    H.eq(banner.inset.template, "InsetFrameTemplate")
    H.eq(banner.inset.createParent, banner.frame)
    H.truthy(banner.label and banner.text and banner.value)
    H.eq(type(banner.set), "function")
    H.eq(#banner.edges, 4)
    -- Built neutral: the trivial grey, before any result.
    local grey = T.ns.Colors.FIXED.trivial
    H.eq(banner.fill, { grey[1], grey[2], grey[3], 0.09 })
end)

H.test("a banner takes its tint from the result kind: fill at 0.09, 2 px edge at 0.45, value in the tone", function()
    local T, Native, env = boot()
    recordRegions(env)
    local FIXED = T.ns.Colors.FIXED
    local banner = Native.banner(nil, 52, 354)
    local cases = {
        { "profit", FIXED.profit }, { "loss", FIXED.loss }, { "incomplete", FIXED.incomplete },
        { "none", FIXED.trivial }, { "weird", FIXED.trivial }, { nil, FIXED.trivial },
    }
    for _, case in ipairs(cases) do
        local tone = case[2]
        banner:set({ kind = case[1], label = "BEST", text = "Sell at the AH", value = "1g" })
        H.eq(banner.fill, { tone[1], tone[2], tone[3], 0.09 })
        H.eq(banner.edge, { tone[1], tone[2], tone[3], 0.45 })
        H.eq(banner.fillTexture.vertex, { tone[1], tone[2], tone[3], 0.09 })
        for _, line in ipairs(banner.edges) do H.eq(line.vertex, { tone[1], tone[2], tone[3], 0.45 }) end
        H.eq(banner.value.textColor, { tone[1], tone[2], tone[3], tone[4] })
    end
    -- Plain white textures tinted by vertex colour, never a theme colour.
    H.eq(banner.fillTexture.color, { 1, 1, 1, 1 })
    for _, line in ipairs(banner.edges) do H.eq(line.color, { 1, 1, 1, 1 }) end
end)

H.test("the banner edge is 2 px on each side of the card", function()
    local _, Native, env = boot()
    recordRegions(env)
    local banner = Native.banner(nil, 52)
    local across, down = 0, 0
    for _, line in ipairs(banner.edges) do
        if rawget(line, "height") == 2 and rawget(line, "width") == nil then across = across + 1 end
        if rawget(line, "width") == 2 and rawget(line, "height") == nil then down = down + 1 end
    end
    H.eq({ across, down }, { 2, 2 })
end)

H.test("a banner sets its label, text and value, and appends the warning in the incomplete colour", function()
    local T, Native, env = boot()
    recordRegions(env)
    local banner = Native.banner(nil, 52, 354)
    banner:set({ kind = "profit", label = "BEST WAY", text = "Sell at the AH", value = "3g 24s" })
    H.eq(banner.label.text, "BEST WAY")
    H.eq(banner.text.text, "Sell at the AH")
    H.eq(banner.value.text, "3g 24s")
    local esc = T.ns.Colors.escape(T.ns.Colors.FIXED.incomplete)
    banner:set({ kind = "incomplete", label = "BEST WAY", warning = "2 prices missing", text = "x", value = "?" })
    H.eq(banner.label.text, "BEST WAY \194\183 " .. esc .. "2 prices missing|r")
    banner:set({})
    H.eq(banner.label.text, "")
    H.eq(banner.text.text, "")
    H.eq(banner.value.text, "")
    -- The text keeps the best colour after its font is reset.
    local best = T.ns.Colors.FIXED.best
    H.eq(banner.text.textColor, { best[1], best[2], best[3], best[4] })
end)

H.test("the banner value steps down the game fonts when wider than 120 px", function()
    local T, Native, env = boot()
    recordRegions(env)
    local Kit = T.ns.Kit
    local banner = Native.banner(nil, 52, 354)
    banner.value.GetUnboundedStringWidth = function() return 200 end
    banner:set({ kind = "profit", label = "L", text = "t", value = "123456g 12s 12c" })
    local sizes = {}
    for i, font in ipairs(Native.BANNER_FONTS) do sizes[i] = font[2] end
    local want = Kit.fitSize(200, sizes[1], 120, sizes)
    H.truthy(want < sizes[1])
    local expected
    for _, font in ipairs(Native.BANNER_FONTS) do if font[2] == want then expected = font[1] end end
    H.eq(lastFont(banner.value), expected)
    banner.value.GetUnboundedStringWidth = function() return 100 end
    banner:set({ kind = "profit", label = "L", text = "t", value = "3g" })
    H.eq(lastFont(banner.value), Native.BANNER_FONTS[1][1])
    -- Game font objects only.
    for _, font in ipairs(Native.BANNER_FONTS) do H.truthy(font[1]:find("^GameFont")) end
end)

H.test("a banner text that would run under the value drops to the small font", function()
    local _, Native, env = boot()
    recordRegions(env)
    local banner = Native.banner(nil, 52, 354)
    banner.value.GetUnboundedStringWidth = function() return 60 end
    -- Room: 354 - 2 * 12 - 60 - 8 = 262.
    banner.text.GetUnboundedStringWidth = function() return 263 end
    banner:set({ kind = "incomplete", label = "L", text = "A long partial result text", value = "1g" })
    H.eq(lastFont(banner.text), "GameFontNormalSmall")
    banner.text.GetUnboundedStringWidth = function() return 262 end
    banner:set({ kind = "profit", label = "L", text = "Short", value = "1g" })
    H.eq(lastFont(banner.text), "GameFontNormal")
    -- The frame's own width wins once it is laid out.
    banner.frame.GetWidth = function() return 300 end
    banner:set({ kind = "profit", label = "L", text = "Short", value = "1g" })
    H.eq(lastFont(banner.text), "GameFontNormalSmall")
end)

H.test("a banner text stays in the normal font when nothing can be measured", function()
    local _, Native, env = boot()
    recordRegions(env)
    local banner = Native.banner(nil, 52)
    banner.text.GetUnboundedStringWidth = function() return 900 end
    banner:set({ kind = "profit", label = "L", text = "Text", value = "1g" })
    H.eq(lastFont(banner.text), "GameFontNormal")
end)

-- List row ------------------------------------------------------------------------

H.test("a native list row is a Button in its slot with a hidden gold selected tint", function()
    local _, Native, env = boot()
    local textures, _, made = recordRegions(env)
    env.NORMAL_FONT_COLOR = { GetRGBA = function() return 1, 0.8, 0.1, 1 end }
    local body = W.frame()
    local row = Native.listRow(body, 3, 18, 14)
    H.eq(made[#made], row)
    H.eq(row.kind, "Button")
    H.eq(row.createParent, body)
    H.eq(row.height, 18)
    H.eq(row.points[1], { "TOPLEFT", body, "TOPLEFT", 0, -36 })
    H.eq(row.points[2], { "TOPRIGHT", body, "TOPRIGHT", -14, -36 })
    H.eq(row.selected, textures[1])
    H.falsy(row.selected.shown)
    H.eq(row.selected.color, { 1, 0.8, 0.1, 0.16 })
    -- No click handler: the caller sets it.
    H.eq(row.scripts.OnClick, nil)
    local first = Native.listRow(body, 1, 18)
    H.eq(first.points[1], { "TOPLEFT", body, "TOPLEFT", 0, 0 })
    H.eq(first.points[2], { "TOPRIGHT", body, "TOPRIGHT", 0, 0 })
end)

H.test("a native list row lights up with the game's quest highlight on hover", function()
    local _, Native, env = boot()
    recordRegions(env)
    local row = Native.listRow(W.frame(), 2, 18, 0)
    local hover = row.hover
    H.eq(hover.file, "Interface\\QuestFrame\\UI-QuestTitleHighlight")
    H.eq(hover.blend, "ADD")
    -- Over the selected tint.
    H.eq(hover.layer, row.selected.layer)
    H.truthy(rawget(hover, "sublevel") > (rawget(row.selected, "sublevel") or 0))
    H.falsy(hover.shown)
    row.scripts.OnEnter(row)
    H.truthy(hover.shown)
    row.scripts.OnLeave(row)
    H.falsy(hover.shown)
end)

H.test("a native list row selected tint falls back to gold without the game colour", function()
    local _, Native, env = boot()
    recordRegions(env)
    local row = Native.listRow(W.frame(), 1, 18)
    H.eq(row.selected.color, { 1, 0.82, 0, 0.16 })
end)

H.test("setMaxWidth changes a check box's cap later: label and hit area, never negative", function()
    local _, Native, env = boot()
    local label = W.frame()
    label.GetStringWidth = function() return 300 end
    local width, insets
    label.SetWidth = function(_, w) width = w end
    local create = env.CreateFrame
    env.CreateFrame = function(kind, name, parent, template)
        local f = create(kind, name, parent, template)
        if template == "UICheckButtonTemplate" then
            f.Text = label
            f.SetHitRectInsets = function(_, l, r, t, b) insets = { l, r, t, b } end
        end
        return f
    end
    local c = Native.check(nil, "A long label")
    H.eq(insets[2], -304)
    c:setMaxWidth(100)
    H.eq(width, 100)
    H.eq(insets[2], -104)
    H.eq(label.text, "A long label")
    c:setMaxWidth(-20)
    H.eq(width, 0)
    H.eq(insets[2], -4)
    H.eq(Native.CHECK_LABEL_X, -2)
    H.eq(Native.PANEL_EDGE, 2)
end)
