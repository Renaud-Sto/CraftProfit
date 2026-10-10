-- Native widget kit: the window, buttons, check boxes and inputs drawn by Blizzard's own
-- templates (ButtonFrameTemplate, UIPanelButtonTemplate, UICheckButtonTemplate,
-- InputBoxTemplate), so CraftProfit looks like a panel of the game. Lives beside the old
-- ns.Kit until the windows move over (see docs/superpowers/specs/2026-10-10-native-ui-design.md).
--
-- Rules every function here keeps:
-- * A templated frame that could sit under a Blizzard panel (the window, buttons, check
--   boxes, inputs: callers may parent them anywhere) is created with a nil parent, then
--   SetParent: the gamepad navigation hooks CreateFrame and would run tainted when the
--   parent sits under an open Blizzard panel. The insets of panels and tiles are created
--   with their own frame as parent, which is never a Blizzard panel.
-- * Frames made from a template start shown and unanchored: the window is hidden here and
--   every caller anchors what it gets.
-- * Template internals (Inset, TitleContainer, CloseButton, Text, the ButtonFrameTemplate_*
--   helpers) can change between builds: each use is guarded with a plain fallback, so a
--   changed client never raises. A guard tests `type(x) == "table"` / `"function"`, not just
--   `x`, because the test fake answers any missing key with a no-op function.
-- * No hook on Blizzard methods, no write into Blizzard tables: only scripts of our own
--   frames, and HookScript (never SetScript) where the template already has a handler.
local _, ns = ...

local Native = {}
ns.Native = Native

-- Gap between the edge of `window.content` and what callers place in it.
Native.CONTENT_PAD = 4
Native.BUTTON_H = 22
Native.INPUT_H = 22
-- The game's own small check box (RaidFrame "all assist", settings rows): 24 px, not the
-- template's 32 px default.
Native.CHECK_SIZE = 24
-- Height of the template's title bar (PortraitFrameBaseTemplate.TitleContainer).
Native.TITLE_H = 20
-- Room kept on each side of the title: the close button is 24 px wide at TOPRIGHT (-2, 1)
-- (Camelot override), plus a 2 px gap. Kept on both sides so the title stays centred.
Native.CLOSE_ROOM = 28
-- Edges of the window's inset (`window.content`) once attic, portrait and button bar are
-- hidden: TOPLEFT (INSET_LEFT, -INSET_TOP), BOTTOMRIGHT (-INSET_RIGHT, INSET_BOTTOM).
Native.INSET_LEFT = 9
Native.INSET_RIGHT = 6
Native.INSET_TOP = 24
Native.INSET_BOTTOM = 4
Native.TITLE_ICON = 14
Native.SEARCH_ATLAS = "common-search-magnifyingglass"
-- Space between a button's edge and its label, so a long label is cut before the border.
local BUTTON_TEXT_PAD = 8
-- The template anchors a check box label this far from the box's right edge (LEFT to RIGHT,
-- x = -2, UICheckButtonTemplate); its hit area grows by the label width plus CHECK_LABEL_GAP.
Native.CHECK_LABEL_X = -2
local CHECK_LABEL_GAP = 4

-- `v` when it is a real table (a frame, a region), nil otherwise.
local function tableOf(v)
    if type(v) == "table" then return v end
    return nil
end

-- Calls a game helper that may be missing or may raise on a changed build. Returns true
-- when it ran without error.
local function try(fn, ...)
    if type(fn) ~= "function" then return false end
    return (pcall(fn, ...))
end

-- Width of a string at its natural size (an anchored font string can report a capped one).
local function naturalWidth(fs)
    local width
    if type(fs.GetUnboundedStringWidth) == "function" then width = fs:GetUnboundedStringWidth() end
    if type(width) ~= "number" then width = fs:GetStringWidth() end
    return width
end

-- Paints a font string with one of the game's colour objects (NORMAL_FONT_COLOR...);
-- does nothing when the object is missing or not a colour.
local function rgbOf(color)
    if type(color) ~= "table" or type(color.GetRGB) ~= "function" then return nil end
    local ok, r, g, b = pcall(color.GetRGB, color)
    if ok and type(r) == "number" then return r, g, b end
    return nil
end

local function paintText(fs, color)
    local r, g, b = rgbOf(color)
    if r then fs:SetTextColor(r, g, b) end
end

-- The client's description of an atlas, or nil when it does not know the name (or cannot
-- say): an unknown atlas would draw nothing, or a green square.
local function atlasInfo(name)
    local api = C_Texture
    if type(api) ~= "table" or type(api.GetAtlasInfo) ~= "function" then return nil end
    local ok, info = pcall(api.GetAtlasInfo, name)
    if ok and type(info) == "table" then return info end
    return nil
end

-- Puts atlas `name` on `tex`, stretched to the texture's anchors. Returns the atlas info
-- when it was applied, nil otherwise (the caller draws its fallback).
local function applyAtlas(tex, name)
    local info = atlasInfo(name)
    if not info or not pcall(tex.SetAtlas, tex, name) then return nil end
    -- A leading underscore marks an atlas made to tile horizontally (as the templates use it).
    if name:sub(1, 1) == "_" and type(tex.SetHorizTile) == "function" then tex:SetHorizTile(true) end
    return info
end

-- Magnifier ---------------------------------------------------------------------

-- Gives `texture` the game's magnifier: the atlas when the client knows it, else whatever
-- Kit.searchIcon finds (the AH search box's own icon). Never guesses a file path (a missing
-- file draws a green square). Returns true when an icon was applied.
function Native.searchIcon(texture)
    local ok, applied = pcall(function()
        local api = C_Texture
        if type(api) == "table" and type(api.GetAtlasInfo) == "function"
            and type(api.GetAtlasInfo(Native.SEARCH_ATLAS)) == "table" then
            texture:SetAtlas(Native.SEARCH_ATLAS)
            return true
        end
        local Kit = ns.Kit
        if type(Kit) == "table" and type(Kit.searchIcon) == "function" then
            return Kit.searchIcon(texture) == true
        end
        return false
    end)
    return ok and applied == true
end

-- Drag ----------------------------------------------------------------------------

-- A button takes the mouse, so a press on it no longer reaches the window under it: make a
-- left drag on `button` move `window` (a Native.window) like a drag on its body. The
-- mouse-up that ends a drag can still fire OnClick: `button.dragged` is true from the start
-- of a drag to the next press, and click handlers return early while it is.
function Native.forwardDrag(button, window)
    button:RegisterForDrag("LeftButton")
    button:HookScript("OnMouseDown", function() button.dragged = false end)
    button:SetScript("OnDragStart", function()
        button.dragged = true
        window:StartMoving()
    end)
    button:SetScript("OnDragStop", function() window.stopDrag(window) end)
end

-- Window --------------------------------------------------------------------------

-- A movable game panel (ButtonFrameTemplate: rock background, metal border, title bar,
-- close button) without portrait and without button bar. Returned hidden and unanchored;
-- Escape is not registered (callers add the name to UISpecialFrames when they want it).
-- opts: width, height, onMoved(point, x, y), onTitleClick().
-- Fields: content (the dark inset, or the frame itself on a build without it), titleText,
-- setTitle(self, text), stopDrag(self); with onTitleClick: titleHit, titleIcon,
-- showTitleIcon(self, show).
function Native.window(name, title, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", name, nil, "ButtonFrameTemplate")
    f:SetParent(UIParent)
    f:Hide()
    f:SetSize(opts.width or 372, opts.height or 200)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")

    -- No portrait, no attic (the 36 px band under the title bar meant for tabs or a search
    -- box), no button bar. HideAttic puts the inset's left edge back to x = 4, so it runs
    -- before HidePortrait, which moves it to x = 9 and keeps the y. Inset after the three:
    -- TOPLEFT (9, -24), BOTTOMRIGHT (-6, 4).
    try(ButtonFrameTemplate_HideAttic, f)
    try(ButtonFrameTemplate_HidePortrait, f)
    try(ButtonFrameTemplate_HideButtonBar, f)

    local function stopDrag(self)
        self:StopMovingOrSizing()
        -- Re-anchor to the screen's bottom-left corner so saved offsets are absolute.
        local left, top = self:GetLeft(), self:GetTop()
        if left and top then
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            if opts.onMoved then opts.onMoved("TOPLEFT", left, top) end
        end
    end
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", stopDrag)
    -- For Native.forwardDrag: buttons covering the window drag it like its body.
    f.stopDrag = stopDrag

    -- Title: the template's bar when it is there, else our own string at the same place.
    -- HidePortrait stretches the bar over the close button; pull both ends in so a long
    -- title is cut (the string does not wrap) before the button, and stays centred.
    local container = tableOf(f.TitleContainer)
    local titleText = container and tableOf(container.TitleText)
    local nativeTitle = titleText ~= nil and type(f.SetTitle) == "function"
    if container and titleText then
        container:ClearAllPoints()
        container:SetPoint("TOPLEFT", f, "TOPLEFT", Native.CLOSE_ROOM, -1)
        container:SetPoint("TOPRIGHT", f, "TOPRIGHT", -Native.CLOSE_ROOM, -1)
    else
        container = nil
        titleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleText:SetPoint("TOPLEFT", f, "TOPLEFT", Native.CLOSE_ROOM, -6)
        titleText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -Native.CLOSE_ROOM, -6)
        titleText:SetWordWrap(false)
    end
    f.titleText = titleText

    local placeIcon = function() end
    f.setTitle = function(self, value)
        value = value or ""
        if nativeTitle then self:SetTitle(value) else titleText:SetText(value) end
        placeIcon()
    end

    -- opts.onTitleClick: a transparent button over the title bar (e.g. to search the item),
    -- with the game's magnifier after the text. It still drags the window. It sits above
    -- the border art and below the close button, and never covers it (CLOSE_ROOM).
    if opts.onTitleClick then
        local hit = CreateFrame("Button", nil, f)
        if container then
            hit:SetAllPoints(container)
        else
            hit:SetPoint("TOPLEFT", f, "TOPLEFT", Native.CLOSE_ROOM, -1)
            hit:SetPoint("TOPRIGHT", f, "TOPRIGHT", -Native.CLOSE_ROOM, -1)
            hit:SetHeight(Native.TITLE_H)
        end
        local base = f:GetFrameLevel()
        if type(base) == "number" then
            -- NineSlice (the border) is a child at base + 1.
            hit:SetFrameLevel(base + 2)
            local close = tableOf(f.CloseButton)
            local closeLevel = close and close:GetFrameLevel()
            if type(closeLevel) == "number" and closeLevel <= base + 2 then
                close:SetFrameLevel(base + 3)
            end
        end
        hit:SetScript("OnClick", function()
            if hit.dragged == true then return end
            opts.onTitleClick()
        end)
        Native.forwardDrag(hit, f)
        hit:HookScript("OnEnter", function() paintText(titleText, HIGHLIGHT_FONT_COLOR) end)
        hit:HookScript("OnLeave", function() paintText(titleText, NORMAL_FONT_COLOR) end)
        f.titleHit = hit

        local icon = hit:CreateTexture(nil, "OVERLAY")
        icon:SetSize(Native.TITLE_ICON, Native.TITLE_ICON)
        icon:Hide()
        f.titleIcon = icon
        -- Right after the centred text; at the right end of the bar when the text cannot
        -- be measured; never past the bar.
        placeIcon = function()
            icon:ClearAllPoints()
            local width = naturalWidth(titleText)
            if type(width) ~= "number" or width <= 0 then
                icon:SetPoint("RIGHT", hit, "RIGHT", -2, 0)
                return
            end
            local half = width / 2
            local room = hit:GetWidth()
            if type(room) == "number" and room > 0 then
                half = math.min(half, room / 2 - Native.TITLE_ICON - 2)
            end
            icon:SetPoint("LEFT", hit, "CENTER", half + 4, 0)
        end
        -- Hidden until asked: the magnifier promises a search, which only works with the
        -- auction house open (same contract as Kit.window).
        f.showTitleIcon = function(_, show)
            if show and Native.searchIcon(icon) then
                placeIcon()
                icon:Show()
            else
                icon:Hide()
            end
        end
    end

    f:setTitle(title)
    f.content = tableOf(f.Inset) or f
    return f
end

-- Button ------------------------------------------------------------------------

-- The game's red-gold panel button, 22 px high. opts: width, onClick. A disabled button
-- runs nothing. The label is cut with an ellipsis when it is wider than the button.
function Native.button(parent, text, opts)
    opts = opts or {}
    local b = CreateFrame("Button", nil, nil, "UIPanelButtonTemplate")
    b:SetParent(parent)
    b:SetSize(opts.width or 80, Native.BUTTON_H)
    local label = tableOf(b.Text)
    if not label and type(b.GetFontString) == "function" then label = tableOf(b:GetFontString()) end
    if label then
        -- The template centres the label without a width: a long one would spill over the
        -- border. Two anchors give it the button's width minus the end caps.
        label:ClearAllPoints()
        label:SetPoint("LEFT", b, "LEFT", BUTTON_TEXT_PAD, 0)
        label:SetPoint("RIGHT", b, "RIGHT", -BUTTON_TEXT_PAD, 0)
        label:SetWordWrap(false)
    end
    b.onClick = opts.onClick
    -- The template has no OnClick of its own, so SetScript replaces nothing of Blizzard's.
    b:SetScript("OnClick", function(self, ...)
        if type(self.IsEnabled) == "function" and self:IsEnabled() == false then return end
        if type(self.onClick) == "function" then self.onClick(self, ...) end
    end)
    function b:setText(value) self:SetText(value or "") end
    b:setText(text)
    return b
end

-- Check box ---------------------------------------------------------------------

-- The game's check box with its label on the right. Clicking the label toggles it (the hit
-- area is widened over the label, as the game's own options do). `onToggle(checked)` (also
-- settable later as `check.onToggle`) runs after a player's click, with the game's sound.
-- `maxWidth` (optional): the label never gets wider (cut, not wrapped), nor does the hit area;
-- `check:setMaxWidth(w)` changes it later (e.g. when a value beside the label changes width).
function Native.check(parent, text, onToggle, maxWidth)
    local c = CreateFrame("CheckButton", nil, nil, "UICheckButtonTemplate")
    c:SetParent(parent)
    c:SetSize(Native.CHECK_SIZE, Native.CHECK_SIZE)
    local label = tableOf(c.Text)
    if not label then
        label = c:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        label:SetPoint("LEFT", c, "RIGHT", Native.CHECK_LABEL_X, 0)
    end
    c.label = label
    c.onToggle = onToggle
    -- A font string with a set width centres its text: keep the label against the box.
    label:SetJustifyH("LEFT")
    local function capLabel()
        if type(maxWidth) == "number" then
            label:SetWidth(maxWidth)
            label:SetWordWrap(false)
        end
    end
    capLabel()
    -- A CheckButton flips its own state before OnClick: read it, never flip it again.
    c:SetScript("OnClick", function(self)
        local checked = self:GetChecked() and true or false
        if type(PlaySound) == "function" and type(SOUNDKIT) == "table" then
            local sound = checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
            if sound then PlaySound(sound) end
        end
        if type(self.onToggle) == "function" then self.onToggle(checked) end
    end)
    function c:setText(value)
        label:SetText(value or "")
        local width = naturalWidth(label)
        width = type(width) == "number" and width or 0
        if type(maxWidth) == "number" then width = math.min(width, maxWidth) end
        self:SetHitRectInsets(0, -(width + CHECK_LABEL_GAP), 0, 0)
    end
    function c:setMaxWidth(w)
        maxWidth = type(w) == "number" and math.max(0, w) or nil
        capLabel()
        self:setText(label:GetText())
    end
    c:SetChecked(false)
    c:setText(text)
    return c
end

-- Input box ---------------------------------------------------------------------

-- The game's single-line edit box, 22 px high, without auto focus (it would grab the
-- keyboard whenever the window shows). Enter and Escape give the keyboard back. Its border
-- art reaches 5 px left of the frame: leave that room when anchoring it.
function Native.input(parent, width, maxLetters)
    local box = CreateFrame("EditBox", nil, nil, "InputBoxTemplate")
    box:SetParent(parent)
    box:SetSize(width or 52, Native.INPUT_H)
    box:SetAutoFocus(false)
    if maxLetters then box:SetMaxLetters(maxLetters) end
    -- The template has no Enter handler; it already clears the focus on Escape, so that
    -- one is hooked, not replaced (a second ClearFocus is harmless).
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

-- Panel ---------------------------------------------------------------------------

Native.HEAD_H = 22
-- Header strip candidates, chosen at the /cp kitdemo checkpoint. Switching applies to
-- panels built afterwards (the demo rebuilds its window).
Native.HEADER_VARIANTS = {
    a = "questlog-reward-header-top",
    b = "friends-frame-toptexbg",
    c = "_UI-Frame-TopTileStreaks",
}
Native.headerVariant = "b"
Native.DIVIDER_ATLAS = "perks-divider-short"
-- The header sits this far inside the panel's inset border, on every side but the bottom;
-- the body keeps the same margin at the bottom. 2 + 22 + 4 + rows + 2 = Kit.panelHeight.
Native.PANEL_EDGE = 2
local PANEL_EDGE = Native.PANEL_EDGE

-- Picks the header strip for panels built from now on; an unknown key keeps the current
-- one. Returns the key in use.
function Native.setHeaderVariant(key)
    if Native.HEADER_VARIANTS[key] then Native.headerVariant = key end
    return Native.headerVariant
end

-- A section of a window: the game's dark inset as background, a header strip with a title
-- (and an optional right-hand text in p.right), a divider under it, and a body to fill.
-- Same fields and methods as Kit.panel: frame, body, title, right, setTitle, setRows,
-- height, onHeaderClick. Also: inset, headerBg, headerAtlas (nil when the fallback was
-- drawn), divider (nil when its atlas is missing).
function Native.panel(parent, title)
    local Kit = ns.Kit
    local p = {}
    local f = CreateFrame("Frame", nil, parent)
    p.frame = f
    -- InsetFrameTemplate shares its parent's level (useParentLevel): everything else here is
    -- in child frames, one level up, so it always draws over it.
    p.inset = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
    p.inset:SetAllPoints(f)

    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT", f, "TOPLEFT", PANEL_EDGE, -PANEL_EDGE)
    head:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PANEL_EDGE, -PANEL_EDGE)
    head:SetHeight(Native.HEAD_H)
    p.head = head
    local headBg = head:CreateTexture(nil, "BACKGROUND")
    headBg:SetAllPoints(head)
    p.headerBg = headBg
    local atlas = Native.HEADER_VARIANTS[Native.headerVariant]
    if applyAtlas(headBg, atlas) then
        p.headerAtlas = atlas
    else
        -- A faint gold strip, the colour of the game's header text.
        local r, g, b = rgbOf(NORMAL_FONT_COLOR)
        if r then headBg:SetColorTexture(r, g, b, 0.15) end
    end
    local divider = head:CreateTexture(nil, "ARTWORK")
    local info = applyAtlas(divider, Native.DIVIDER_ATLAS)
    if info then
        -- Centred on the header's bottom edge, at most 6 px tall whatever the atlas size.
        divider:SetPoint("LEFT", head, "BOTTOMLEFT", 0, 0)
        divider:SetPoint("RIGHT", head, "BOTTOMRIGHT", 0, 0)
        divider:SetHeight(math.min(type(info.height) == "number" and info.height or 2, 6))
        p.divider = divider
    else
        divider:Hide()
    end

    p.right = head:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.right:SetPoint("RIGHT", head, "RIGHT", -8, 0)
    p.right:SetWordWrap(false)
    p.title = head:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.title:SetPoint("LEFT", head, "LEFT", 8, 0)
    -- Stops before the right-hand text: a long title is cut, never drawn under it.
    p.title:SetPoint("RIGHT", p.right, "LEFT", -8, 0)
    p.title:SetJustifyH("LEFT")
    p.title:SetWordWrap(false)

    p.body = CreateFrame("Frame", nil, f)
    p.body:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -Kit.BODY_PAD)
    p.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PANEL_EDGE, PANEL_EDGE)

    p.rowH = 18
    function p:setTitle(text) self.title:SetText(text or "") end
    function p:setRows(rows, rowH, extra)
        self.rowH = rowH or self.rowH
        f:SetHeight(Kit.panelHeight(rows, self.rowH, extra))
    end
    p.height = function() return f:GetHeight() end
    -- A button covering the header, e.g. to fold the panel. Returns it (also p.headerHit);
    -- calling it again replaces the handler of the same button.
    function p:onHeaderClick(fn)
        if not self.headerHit then
            local hit = CreateFrame("Button", nil, head)
            hit:SetAllPoints(head)
            -- A child of the header would sit above buttons parented to the panel frame
            -- (a sort button, say) and swallow their clicks, so stay at the panel's level.
            local level = f:GetFrameLevel()
            if type(level) == "number" then hit:SetFrameLevel(level) end
            self.headerHit = hit
        end
        self.headerHit:SetScript("OnClick", fn)
        return self.headerHit
    end
    p:setTitle(title)
    return p
end

-- Tile ----------------------------------------------------------------------------

-- Tile background candidates, chosen at the /cp kitdemo checkpoint; applies to tiles built
-- afterwards. "a": the loot card atlas, its stroke as the best-tile outline. "b": a nested
-- game inset with a 2 px gold outline for the best tile.
Native.TILE_VARIANTS = { a = "looting_itemcard_bg", b = "inset" }
Native.tileVariant = "b"
Native.TILE_STROKE_ATLAS = "looting_itemcard_stroke_normal"
Native.TILE_PAD = 10
Native.TILE_ICON = 12
-- The value font steps down this ladder of game fonts (never SetFont with a file) until it
-- fits; the sizes are the fonts' heights, for Kit.fitSize.
Native.TILE_FONTS = {
    { "GameFontNormalHuge", 20 },
    { "GameFontNormalLarge2", 18 },
    { "GameFontNormalLarge", 16 },
    { "GameFontNormalMed2", 14 },
    { "GameFontNormal", 12 },
}
local TILE_OUTLINE = 2
local HOVER_FILE = "Interface\\QuestFrame\\UI-QuestTitleHighlight"

function Native.setTileVariant(key)
    if Native.TILE_VARIANTS[key] then Native.tileVariant = key end
    return Native.tileVariant
end

-- Four lines of `thickness` px along the inside edges of `frame` (top, bottom, left,
-- right), uncoloured. Returns the textures.
local function edgeLines(frame, thickness)
    local lines = {}
    local function line(p1, p2, width, height)
        local tex = frame:CreateTexture(nil, "BORDER")
        tex:SetPoint(p1, frame, p1, 0, 0)
        tex:SetPoint(p2, frame, p2, 0, 0)
        if width then tex:SetWidth(width) end
        if height then tex:SetHeight(height) end
        lines[#lines + 1] = tex
    end
    line("TOPLEFT", "TOPRIGHT", nil, thickness)
    line("BOTTOMLEFT", "BOTTOMRIGHT", nil, thickness)
    line("TOPLEFT", "BOTTOMLEFT", thickness, nil)
    line("TOPRIGHT", "BOTTOMRIGHT", thickness, nil)
    return lines
end

-- A 2 px outline inside `frame`, in the game's gold; hidden. Returns its four textures.
local function goldOutline(frame)
    local r, g, b = rgbOf(NORMAL_FONT_COLOR)
    local lines = edgeLines(frame, TILE_OUTLINE)
    for _, tex in ipairs(lines) do
        if r then tex:SetColorTexture(r, g, b, 1) end
        tex:Hide()
    end
    return lines
end

-- A small card with a label and a large value that shrinks to fit its width. Same fields
-- and methods as Kit.tile: frame, label, value, set(spec), onClick(fn), showIcon(show),
-- hit, icon, best, muted. Also: variant (the one it was built with), bgAtlas (nil when the
-- card atlas was missing and the inset was drawn instead), outline (the best-tile marks).
function Native.tile(parent, width, height)
    local Kit = ns.Kit
    local tile = { best = false, muted = false, width = width, variant = Native.tileVariant }
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 110, height or 52)
    tile.frame = f
    -- Texts, outline and hover live on `face`, a child one level above the background
    -- (the nested inset shares the tile's level).
    local face = CreateFrame("Frame", nil, f)
    face:SetAllPoints(f)
    tile.face = face

    local cardAtlas = Native.TILE_VARIANTS.a
    if tile.variant == "a" then
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(f)
        if applyAtlas(bg, cardAtlas) then
            tile.bgAtlas = cardAtlas
        else
            bg:Hide()
        end
    end
    if not tile.bgAtlas then
        tile.inset = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
        tile.inset:SetAllPoints(f)
    end
    -- The best mark: the card's own stroke when the card and its stroke exist, else gold.
    local stroke
    if tile.bgAtlas then
        stroke = face:CreateTexture(nil, "BORDER")
        stroke:SetAllPoints(face)
        if applyAtlas(stroke, Native.TILE_STROKE_ATLAS) then
            stroke:Hide()
            tile.outline = { stroke }
        end
    end
    if not tile.outline then
        if stroke then stroke:Hide() end
        tile.outline = goldOutline(face)
    end

    -- White, so a gold tag ("beta") stands out from it.
    tile.label = face:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tile.label:SetPoint("TOPLEFT", f, "TOPLEFT", Native.TILE_PAD, -8)
    tile.label:SetPoint("TOPRIGHT", f, "TOPRIGHT", -Native.TILE_PAD, -8)
    tile.label:SetJustifyH("LEFT")
    tile.label:SetWordWrap(false)
    tile.value = face:CreateFontString(nil, "OVERLAY", Native.TILE_FONTS[1][1])
    tile.value:SetPoint("TOPLEFT", f, "TOPLEFT", Native.TILE_PAD, -24)
    tile.value:SetPoint("TOPRIGHT", f, "TOPRIGHT", -Native.TILE_PAD, -24)
    tile.value:SetJustifyH("LEFT")
    tile.value:SetWordWrap(false)

    local function paint()
        for _, mark in ipairs(tile.outline) do mark:SetShown(tile.best) end
        -- SetFontObject resets the colour to the font's own: paint after every font change.
        paintText(tile.value, tile.muted and DISABLED_FONT_COLOR or HIGHLIGHT_FONT_COLOR)
    end

    -- spec: { label, tag, value, best, muted }
    function tile:set(spec)
        self.best = spec.best and true or false
        self.muted = spec.muted and true or false
        local label = spec.label or ""
        if spec.tag then
            local tag = spec.tag
            local color = NORMAL_FONT_COLOR
            if type(color) == "table" and type(color.WrapTextInColorCode) == "function" then
                local ok, wrapped = pcall(color.WrapTextInColorCode, color, tag)
                if ok and type(wrapped) == "string" then tag = wrapped end
            end
            label = label .. " " .. tag
        end
        self.label:SetText(label)
        local fonts = Native.TILE_FONTS
        local sizes = {}
        for i, font in ipairs(fonts) do sizes[i] = font[2] end
        self.value:SetFontObject(fonts[1][1])
        self.value:SetText(spec.value or "")
        local room = (f:GetWidth() or width or 110) - Native.TILE_PAD * 2
        local size = Kit.fitSize(naturalWidth(self.value), sizes[1], room, sizes)
        if size ~= sizes[1] then
            for _, font in ipairs(fonts) do
                if font[2] == size then self.value:SetFontObject(font[1]) end
            end
        end
        paint()
    end

    -- Makes the whole tile a button (e.g. to search the item at the AH): the game's quest
    -- highlight on hover and a magnifier at the top right that `tile:showIcon(true)`
    -- reveals. Calling it again replaces the handler. The button takes the mouse: the owner
    -- forwards drags to its window with Native.forwardDrag(tile.hit, window).
    function tile:onClick(fn)
        if not self.hit then
            local hit = CreateFrame("Button", nil, f)
            hit:SetAllPoints(f)
            -- Above `face`, so the magnifier draws over the texts, never under them.
            local level = face:GetFrameLevel()
            if type(level) == "number" then hit:SetFrameLevel(level + 1) end
            local hover = face:CreateTexture(nil, "BACKGROUND")
            hover:SetAllPoints(face)
            hover:SetTexture(HOVER_FILE)
            hover:SetBlendMode("ADD")
            hover:Hide()
            hit:HookScript("OnEnter", function() hover:Show() end)
            hit:HookScript("OnLeave", function() hover:Hide() end)
            self.hover = hover
            self.icon = hit:CreateTexture(nil, "OVERLAY")
            self.icon:SetSize(Native.TILE_ICON, Native.TILE_ICON)
            self.icon:SetPoint("TOPRIGHT", hit, "TOPRIGHT", -6, -6)
            self.icon:Hide()
            self.hit = hit
        end
        -- A click that ends a drag (see Native.forwardDrag) runs nothing.
        local hit = self.hit
        hit:SetScript("OnClick", function(...)
            if hit.dragged == true then return end
            fn(...)
        end)
        return hit
    end

    function tile:showIcon(show)
        if not self.icon then return end
        local shown = show and Native.searchIcon(self.icon)
        self.icon:SetShown(shown and true or false)
        -- While the magnifier shows, the label stops short of it (cut, not drawn under it).
        local right = shown and (6 + Native.TILE_ICON + 4) or Native.TILE_PAD
        self.label:SetPoint("TOPRIGHT", f, "TOPRIGHT", -right, -8)
    end
    return tile
end

-- Banner --------------------------------------------------------------------------

-- The result banner: a card like the tiles (variant b, a nested game inset) tinted by the
-- kind of result. The tint is a meaning colour (Colors.FIXED), never an appearance choice:
-- plain white textures vertex-coloured, a faint fill and a 2 px edge.
Native.BANNER_PAD = 12
Native.BANNER_FILL = 0.09
Native.BANNER_EDGE = 0.45
Native.BANNER_EDGE_PX = 2
-- Widest the value may be before it steps down the font ladder.
Native.BANNER_VALUE_ROOM = 120
-- Same game fonts as the tile values (never SetFont with a file).
Native.BANNER_FONTS = Native.TILE_FONTS
local BANNER_GAP = 8
local BANNER_TONES = { profit = "profit", loss = "loss", incomplete = "incomplete" }

-- parent, height; `width` (optional) is the width the caller will anchor it to, used to
-- measure the text while the frame has no laid-out width yet (its own width wins once it
-- has one). Fields: frame, inset, face, label, text, value, fillTexture, edges (4 lines),
-- fill and edge (the { r, g, b, a } applied), set(spec).
function Native.banner(parent, height, width)
    local Kit, Colors = ns.Kit, ns.Colors
    local banner = { width = width }
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(height or 52)
    banner.frame = f
    -- The tile's structure: the inset shares the frame's level, `face` sits one above.
    banner.inset = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
    banner.inset:SetAllPoints(f)
    local face = CreateFrame("Frame", nil, f)
    face:SetAllPoints(f)
    banner.face = face

    local fill = face:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(face)
    fill:SetColorTexture(1, 1, 1, 1)
    banner.fillTexture = fill
    banner.edges = edgeLines(face, Native.BANNER_EDGE_PX)
    for _, line in ipairs(banner.edges) do line:SetColorTexture(1, 1, 1, 1) end
    banner.fill, banner.edge = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }

    local pad = Native.BANNER_PAD
    local label = face:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", f, "TOPLEFT", pad, -10)
    local value = face:CreateFontString(nil, "OVERLAY", Native.BANNER_FONTS[1][1])
    value:SetPoint("RIGHT", f, "RIGHT", -pad, 0)
    value:SetJustifyH("RIGHT")
    value:SetWordWrap(false)
    -- The label stops before the value too, so a long warning cannot run under it.
    label:SetPoint("RIGHT", value, "LEFT", -BANNER_GAP, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    -- The text runs up to the value, so a short or empty value leaves it more room.
    local text = face:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", pad, 10)
    text:SetPoint("RIGHT", value, "LEFT", -BANNER_GAP, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    banner.label, banner.value, banner.text = label, value, text

    local function tint(tone)
        local r, g, b = tone[1], tone[2], tone[3]
        banner.fill = { r, g, b, Native.BANNER_FILL }
        banner.edge = { r, g, b, Native.BANNER_EDGE }
        fill:SetVertexColor(r, g, b, Native.BANNER_FILL)
        for _, line in ipairs(banner.edges) do line:SetVertexColor(r, g, b, Native.BANNER_EDGE) end
    end

    -- spec: { kind = "profit"|"loss"|"incomplete"|other, label, warning, text, value }
    function banner:set(spec)
        spec = spec or {}
        local FIXED = Colors.FIXED
        local tone = FIXED[BANNER_TONES[spec.kind] or "trivial"]
        local labelText = spec.label or ""
        if spec.warning then
            labelText = labelText .. " \194\183 " .. Colors.escape(FIXED.incomplete) .. spec.warning .. "|r"
        end
        self.label:SetText(labelText)
        self.text:SetText(spec.text or "")

        local fonts = Native.BANNER_FONTS
        local sizes = {}
        for i, font in ipairs(fonts) do sizes[i] = font[2] end
        self.value:SetFontObject(fonts[1][1])
        self.value:SetText(spec.value or "")
        local size = Kit.fitSize(naturalWidth(self.value), sizes[1], Native.BANNER_VALUE_ROOM, sizes)
        if size ~= sizes[1] then
            for _, font in ipairs(fonts) do
                if font[2] == size then self.value:SetFontObject(font[1]) end
            end
        end
        -- SetFontObject resets the colour to the font's own: paint after every font change.
        self.value:SetTextColor(tone[1], tone[2], tone[3], tone[4])

        -- A text too long for the room left by the value (a partial result, say) drops to
        -- the small font rather than losing its end; kept normal when it cannot be measured.
        self.text:SetFontObject("GameFontNormal")
        local frameWidth = f:GetWidth()
        if type(frameWidth) ~= "number" or frameWidth <= 0 then frameWidth = self.width end
        local valueWidth, textWidth = naturalWidth(self.value), naturalWidth(self.text)
        if type(frameWidth) == "number" and type(valueWidth) == "number" and type(textWidth) == "number"
            and textWidth > frameWidth - pad * 2 - valueWidth - BANNER_GAP then
            self.text:SetFontObject("GameFontNormalSmall")
        end
        local best = FIXED.best
        self.text:SetTextColor(best[1], best[2], best[3], best[4])
        tint(tone)
    end

    tint(Colors.FIXED.trivial)
    return banner
end

-- List row ------------------------------------------------------------------------

Native.ROW_SELECTED_ALPHA = 0.16

-- A clickable list row, same contract as Kit.listRow: a Button of `rowH` pixels in slot
-- `index` of `body`, with a hidden gold "selected" tint (`row.selected`) and the game's
-- quest highlight on hover (`row.hover`), both under whatever the caller adds. `rightInset`
-- keeps the row clear of a scroll bar. The caller sets OnClick, and forwards drags to its
-- window (Native.forwardDrag) when the rows cover the window's body.
function Native.listRow(body, index, rowH, rightInset)
    local y = -(index - 1) * rowH
    local row = CreateFrame("Button", nil, body)
    row:SetHeight(rowH)
    row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", body, "TOPRIGHT", -(rightInset or 0), y)
    row.selected = row:CreateTexture(nil, "BACKGROUND")
    row.selected:SetAllPoints(row)
    local gold = ns.Colors.text("gold")
    row.selected:SetColorTexture(gold[1], gold[2], gold[3], Native.ROW_SELECTED_ALPHA)
    row.selected:Hide()
    -- Sublevel 1: the hover shows over the selected tint.
    local hover = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    hover:SetAllPoints(row)
    hover:SetTexture(HOVER_FILE)
    hover:SetBlendMode("ADD")
    hover:Hide()
    row:HookScript("OnEnter", function() hover:Show() end)
    row:HookScript("OnLeave", function() hover:Hide() end)
    row.hover = hover
    return row
end
