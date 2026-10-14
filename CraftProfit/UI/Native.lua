-- Native widget kit: the window, buttons, check boxes and inputs drawn by Blizzard's own
-- templates (ButtonFrameTemplate, UIPanelButtonTemplate, UICheckButtonTemplate,
-- InputBoxTemplate), plus the panels, tiles, result banner, list rows and scroll bar built
-- on the game's atlases, so CraftProfit looks like a panel of the game (see
-- docs/superpowers/specs/2026-10-10-native-ui-design.md). Layout maths: UI/Layout.lua.
-- The kit spans three files, in TOC order: UI/Native.lua (namespace, constants, shared
-- helpers, magnifier, drag, window, button, check box, input), UI/NativeCards.lua (panel,
-- tile and their appearance variants and registry, result banner), UI/NativeLists.lua (list
-- row, scroll bar).
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

-- Width of a string at its natural size (an anchored font string can report a capped one);
-- 0 when it cannot be measured. Shared by the windows (Window, LevelingUI).
function Native.naturalWidth(fs)
    local width
    if type(fs.GetUnboundedStringWidth) == "function" then width = fs:GetUnboundedStringWidth() end
    if type(width) ~= "number" then width = fs:GetStringWidth() end
    return type(width) == "number" and width or 0
end
local naturalWidth = Native.naturalWidth

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
    -- A leading underscore marks an atlas made to tile horizontally, a leading "!" one made
    -- to tile vertically (as the templates use them). A texture gets one atlas for its whole
    -- life: SetAtlas again with another atlas keeps tiling and coordinates of the old one
    -- (a live look switch drew a cut strip, sheet fragments or nothing), so nothing here
    -- is ever reset; switches show another texture instead.
    local mark = name:sub(1, 1)
    if mark == "_" and type(tex.SetHorizTile) == "function" then tex:SetHorizTile(true) end
    if mark == "!" and type(tex.SetVertTile) == "function" then tex:SetVertTile(true) end
    return info
end

-- Magnifier ---------------------------------------------------------------------

-- The icon texture of the AH search box, when the auction house frame has one.
local function searchBoxIcon()
    local frame = AuctionHouseFrame
    local bar = type(frame) == "table" and frame.SearchBar
    local box = type(bar) == "table" and bar.SearchBox
    if type(box) ~= "table" then return nil end
    return box.searchIcon or box.SearchIcon
end

-- Gives `texture` the game's magnifier: the atlas when the client knows it, else the icon of
-- the AH search box (its atlas, or its texture and coordinates). Never guesses a file path
-- (a missing file draws a green square). Returns true when an icon was applied.
function Native.searchIcon(texture)
    local ok, applied = pcall(function()
        local api = C_Texture
        if type(api) == "table" and type(api.GetAtlasInfo) == "function"
            and type(api.GetAtlasInfo(Native.SEARCH_ATLAS)) == "table" then
            texture:SetAtlas(Native.SEARCH_ATLAS)
            return true
        end
        local source = searchBoxIcon()
        if type(source) == "table" then
            local atlas = type(source.GetAtlas) == "function" and source:GetAtlas()
            if type(atlas) == "string" and atlas ~= "" then
                texture:SetAtlas(atlas)
                return true
            end
            local file = type(source.GetTexture) == "function" and source:GetTexture()
            if file and file ~= "" then
                texture:SetTexture(file)
                if type(source.GetTexCoord) == "function" then texture:SetTexCoord(source:GetTexCoord()) end
                return true
            end
        end
        return false
    end)
    return ok and applied == true
end

-- Front -----------------------------------------------------------------------------

-- Brings the Native.window holding `widget` (or `widget` itself) to the front of its strata,
-- children included. Walks up the parents; does nothing outside one of our windows.
function Native.raiseWindow(widget)
    local f = widget
    for _ = 1, 30 do
        if type(f) ~= "table" then return end
        if rawget(f, "isNativeWindow") == true then
            if type(f.Raise) == "function" then f:Raise() end
            return
        end
        if type(f.GetParent) ~= "function" then return end
        f = f:GetParent()
    end
end

-- Drag ----------------------------------------------------------------------------

-- A button takes the mouse, so a press on it no longer reaches the window under it: make a
-- left drag on `button` move `window` (a Native.window) like a drag on its body. The
-- mouse-up that ends a drag can still fire OnClick: `button.dragged` is true from the start
-- of a drag to the next press, and click handlers return early while it is.
function Native.forwardDrag(button, window)
    button:RegisterForDrag("LeftButton")
    button:HookScript("OnMouseDown", function()
        button.dragged = false
        Native.raiseWindow(window)
    end)
    button:SetScript("OnDragStart", function()
        button.dragged = true
        window:StartMoving()
    end)
    button:SetScript("OnDragStop", function() window.stopDrag(window) end)
end

-- Scales `window` down so it fits the screen's height with FIT_MARGIN px to spare
-- (UIParent is 768 px high at UI scale 1.0, about 668 at 1.15), and back to 1 when it fits.
-- Returns the scale set, or nil (nothing changed) when a height is unknown, not a positive
-- number, or reading it raises.
Native.FIT_MARGIN = 20
function Native.fitToScreen(window)
    if type(window) ~= "table" or type(UIParent) ~= "table" then return nil end
    local okScreen, screen = pcall(UIParent.GetHeight, UIParent)
    local okWindow, height = pcall(window.GetHeight, window)
    if not okScreen or not okWindow or not ns.Util.isFinite(screen) or not ns.Util.isFinite(height)
        or screen <= Native.FIT_MARGIN or height <= 0 then
        return nil
    end
    local room = screen - Native.FIT_MARGIN
    local scale = height > room and room / height or 1
    if not pcall(window.SetScale, window, scale) then return nil end
    return scale
end

-- Window --------------------------------------------------------------------------

-- ButtonFrameTemplate's border is the NineSlice layout PortraitFrameTemplate
-- (Blizzard_SharedXML/Mainline/NineSliceLayouts.lua): its top corners start 16 px above the
-- frame, its bottom corners end 3 px below it (8 with the Camelot override; 3 is the larger
-- need). The side edges fill the gap between them: a frame shorter than both corners less
-- those overhangs has no room for them and the corners stick out above and below.
Native.CORNER_TOP_ATLASES = { "UI-Frame-PortraitMetal-CornerTopLeft", "UI-Frame-Metal-CornerTopRight" }
Native.CORNER_BOTTOM_ATLASES = { "UI-Frame-Metal-CornerBottomLeft", "UI-Frame-Metal-CornerBottomRight" }
Native.CORNER_TOP_OVERHANG = 16
Native.CORNER_BOTTOM_OVERHANG = 3
-- Used when the client does not give the corner sizes.
Native.MIN_WINDOW_H = 140

local function tallest(names)
    local best
    for _, name in ipairs(names) do
        local info = atlasInfo(name)
        local h = info and info.height
        if type(h) ~= "number" or h ~= h or h <= 0 then return nil end
        if not best or h > best then best = h end
    end
    return best
end

-- The least height a Native.window may have: the corners' own need when the client knows
-- their atlases, else Native.MIN_WINDOW_H.
function Native.minWindowHeight()
    local top, bottom = tallest(Native.CORNER_TOP_ATLASES), tallest(Native.CORNER_BOTTOM_ATLASES)
    if not top or not bottom then return Native.MIN_WINDOW_H end
    return math.max(0, top - Native.CORNER_TOP_OVERHANG) + math.max(0, bottom - Native.CORNER_BOTTOM_OVERHANG)
end

-- `h` raised to the least window height; every window height goes through it.
function Native.windowHeight(h)
    local least = Native.minWindowHeight()
    if type(h) ~= "number" or h ~= h or h < least then return least end
    return h
end

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
    f:SetSize(opts.width or 372, Native.windowHeight(opts.height or 200))
    -- HIGH: above the game's HUD panels (the Cooldown Manager sits in MEDIUM). Toplevel and
    -- raised on show and on any press inside it, so the window clicked last is drawn whole
    -- above the others (the template's border pieces use high fixed frame levels).
    f:SetFrameStrata("HIGH")
    if type(f.SetToplevel) == "function" then f:SetToplevel(true) end
    f.isNativeWindow = true
    f:HookScript("OnShow", function(self) Native.raiseWindow(self) end)
    f:HookScript("OnMouseDown", function(self) Native.raiseWindow(self) end)
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
        -- auction house open.
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
    b:HookScript("OnMouseDown", function(self) Native.raiseWindow(self) end)
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
    -- The template has no Enter handler. Escape is the template's own (InputBoxScriptTemplate:
    -- OnEscapePressed = EditBox_ClearFocus), left alone.
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return box
end

-- Shared helpers ------------------------------------------------------------------

-- Private helpers of the kit, for UI/NativeCards.lua and UI/NativeLists.lua (which take them
-- into locals at load); not part of the widget API.
Native._rgbOf = rgbOf
Native._paintText = paintText
Native._atlasInfo = atlasInfo
Native._applyAtlas = applyAtlas
