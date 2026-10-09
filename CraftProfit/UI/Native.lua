-- Native widget kit: the window, buttons, check boxes and inputs drawn by Blizzard's own
-- templates (ButtonFrameTemplate, UIPanelButtonTemplate, UICheckButtonTemplate,
-- InputBoxTemplate), so CraftProfit looks like a panel of the game. Lives beside the old
-- ns.Kit until the windows move over (see docs/superpowers/specs/2026-10-10-native-ui-design.md).
--
-- Rules every function here keeps:
-- * Templated frames are created with a nil parent, then SetParent: the gamepad navigation
--   hooks CreateFrame and would run tainted when the parent sits under an open Blizzard panel.
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
Native.TITLE_ICON = 14
Native.SEARCH_ATLAS = "common-search-magnifyingglass"
-- Space between a button's edge and its label, so a long label is cut before the border.
local BUTTON_TEXT_PAD = 8
-- The template anchors a check box label 2 px left of the box's right edge: its hit area
-- grows by the label width plus this margin.
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
local function paintText(fs, color)
    if type(color) ~= "table" or type(color.GetRGB) ~= "function" then return end
    local ok, r, g, b = pcall(color.GetRGB, color)
    if ok and type(r) == "number" then fs:SetTextColor(r, g, b) end
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

    -- Inset after these two: TOPLEFT (9, -60), BOTTOMRIGHT (-6, 4) (the attic above it stays).
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
function Native.check(parent, text, onToggle)
    local c = CreateFrame("CheckButton", nil, nil, "UICheckButtonTemplate")
    c:SetParent(parent)
    c:SetSize(Native.CHECK_SIZE, Native.CHECK_SIZE)
    local label = tableOf(c.Text)
    if not label then
        label = c:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        label:SetPoint("LEFT", c, "RIGHT", -2, 0)
    end
    c.label = label
    c.onToggle = onToggle
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
        self:SetHitRectInsets(0, -(width + CHECK_LABEL_GAP), 0, 0)
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
