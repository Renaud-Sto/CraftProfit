-- Native widget kit, part 3 of 3 (the rules every widget keeps: UI/Native.lua): the list
-- row and the scroll bar.
local _, ns = ...

local Native = ns.Native
local atlasInfo, applyAtlas = Native._atlasInfo, Native._applyAtlas
local HOVER_FILE = Native._HOVER_FILE

-- List row ------------------------------------------------------------------------

Native.ROW_SELECTED_ALPHA = 0.16

-- A clickable list row: a Button of `rowH` pixels in slot
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

-- Scroll bar ----------------------------------------------------------------------

-- The game's thin scroll bar (MinimalScrollBar, Blizzard_SharedXML): 8 px wide, track and
-- thumb each a top cap, a middle and a bottom cap. The template itself needs a ScrollBox;
-- our lists are a few fixed rows, so we draw its atlases on our own bar and use the layout
-- thumb maths (Layout.scrollThumb / scrollOffsetAt / scrollGrab). No arrows: the wheel and the
-- track do the stepping.
Native.SCROLL_W = 8
Native.SCROLL_TRACK_ATLASES = {
    top = "minimal-scrollbar-track-top",
    middle = "!minimal-scrollbar-track-middle",
    bottom = "minimal-scrollbar-track-bottom",
}
-- The template's thumb, per state; "" is at rest, "-over" hovered, "-down" pressed.
local THUMB_ATLAS = "minimal-scrollbar-small-thumb-%s%s"
-- Flat fallback when an atlas is unknown: a faint grey track, a gold thumb.
Native.SCROLL_TRACK_ALPHA = 0.3

local PIECES = { "top", "middle", "bottom" }

local function thumbAtlases(state)
    local names = {}
    for _, piece in ipairs(PIECES) do names[piece] = THUMB_ATLAS:format(piece, state) end
    return names
end

-- Heights of the atlases in `names` when the client knows all three, nil otherwise.
local function knownPieces(names)
    local heights = {}
    for _, piece in ipairs(PIECES) do
        local info = atlasInfo(names[piece])
        if not info then return nil end
        heights[piece] = type(info.height) == "number" and info.height or 0
    end
    return heights
end

-- Three textures on `frame` stacked top to bottom, the middle between the caps. The caps
-- keep their atlas height (`heights`); placed by layoutPieces.
local function makePieces(frame, layer, names)
    local pieces = {}
    for _, piece in ipairs(PIECES) do
        local tex = frame:CreateTexture(nil, layer)
        applyAtlas(tex, names[piece])
        pieces[piece] = tex
    end
    pieces.top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    pieces.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    pieces.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    pieces.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    pieces.middle:SetPoint("TOPLEFT", pieces.top, "BOTTOMLEFT", 0, 0)
    pieces.middle:SetPoint("BOTTOMRIGHT", pieces.bottom, "TOPRIGHT", 0, 0)
    return pieces
end

-- Cap heights for a stack `height` px tall: the atlas heights, or half the height each
-- when both caps would not fit (the middle then has no room, never a negative one).
local function layoutPieces(pieces, heights, height)
    local top, bottom = heights.top, heights.bottom
    if top + bottom > height then
        top = math.floor(height / 2)
        bottom = top
    end
    pieces.top:SetHeight(top)
    pieces.bottom:SetHeight(bottom)
end

local function flatFill(frame, layer, color, alpha)
    local tex = frame:CreateTexture(nil, layer)
    tex:SetAllPoints(frame)
    tex:SetColorTexture(color[1], color[2], color[3], alpha)
    return tex
end

-- A slim scroll bar for a list that shows `visible` of `total` rows:
-- `bar.frame` (a Button, the track, hidden while the list fits), `bar.thumb`,
-- `bar:update(total, visible, offset)` -> shown, `bar.onScroll(offset)` asked for the offset
-- a click or a drag wants (the owner scrolls, then calls update). The owner handles the
-- wheel. Also: trackAtlases / thumbAtlases (true when drawn from the game's atlases),
-- trackPieces / thumbPieces ({ top, middle, bottom } textures) or trackFill / thumbFill (the
-- flat fallback).
function Native.scrollbar(parent, trackH)
    local Layout, Colors = ns.Layout, ns.Colors
    local bar = { trackH = trackH, total = 0, visible = 0, offset = 0 }
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(Native.SCROLL_W, trackH)
    bar.frame = f

    local trackHeights = knownPieces(Native.SCROLL_TRACK_ATLASES)
    if trackHeights then
        bar.trackAtlases = true
        bar.trackPieces = makePieces(f, "BACKGROUND", Native.SCROLL_TRACK_ATLASES)
        layoutPieces(bar.trackPieces, trackHeights, trackH)
    else
        bar.trackAtlases = false
        bar.trackFill = flatFill(f, "BACKGROUND", Colors.text("muted"), Native.SCROLL_TRACK_ALPHA)
    end

    -- A plain frame, mouse off: presses go to the track, which knows where the thumb is.
    local thumb = CreateFrame("Frame", nil, f)
    bar.thumb = thumb
    local rest = thumbAtlases("")
    local thumbHeights = knownPieces(rest)
    if thumbHeights then
        bar.thumbAtlases = true
        bar.thumbPieces = makePieces(thumb, "ARTWORK", rest)
    else
        bar.thumbAtlases = false
        bar.thumbFill = flatFill(thumb, "ARTWORK", Colors.text("gold"), 1)
    end

    -- Hover and press looks, as the template's thumb has; a state the client lacks keeps
    -- the thumb at rest.
    local states = { [""] = rest }
    for _, state in ipairs({ "-over", "-down" }) do
        local names = thumbAtlases(state)
        if bar.thumbAtlases and knownPieces(names) then states[state] = names end
    end
    local hovered, dragging = false, false
    local function paintThumb()
        if not bar.thumbAtlases then return end
        local names = (dragging and states["-down"]) or (hovered and states["-over"]) or rest
        for _, piece in ipairs(PIECES) do pcall(bar.thumbPieces[piece].SetAtlas, bar.thumbPieces[piece], names[piece]) end
    end

    function bar:update(total, visible, offset)
        self.total, self.visible, self.offset = total, visible, offset
        local thumbH, top = Layout.scrollThumb(total, visible, offset, self.trackH)
        if not thumbH then
            f:Hide()
            return false
        end
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top)
        thumb:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -top)
        thumb:SetHeight(thumbH)
        if self.thumbPieces then layoutPieces(self.thumbPieces, thumbHeights, thumbH) end
        f:Show()
        return true
    end

    -- `grab`: where on the thumb the pointer holds it, kept for the whole drag.
    local grab = 0
    -- Pointer distance below the top of the track; nil when it cannot be measured.
    local function pointerY()
        if type(GetCursorPosition) ~= "function" then return nil end
        local _, cursorY = GetCursorPosition()
        local top, scale = f:GetTop(), f:GetEffectiveScale()
        if type(cursorY) ~= "number" or type(top) ~= "number" or type(scale) ~= "number" or scale <= 0 then
            return nil
        end
        return top - cursorY / scale
    end
    local function follow()
        local y = pointerY()
        if not y then return end
        local thumbH = Layout.scrollThumb(bar.total, bar.visible, bar.offset, bar.trackH)
        if not thumbH then return end
        local offset = Layout.scrollOffsetAt(bar.total, bar.visible, bar.trackH, y - grab + thumbH / 2)
        if offset ~= bar.offset and bar.onScroll then bar.onScroll(offset) end
    end
    -- OnUpdate exists only while a drag runs: no per-frame work while the bar is idle.
    local function stopDrag()
        if not dragging then return end
        dragging = false
        f:SetScript("OnUpdate", nil)
        hovered = type(f.IsMouseOver) == "function" and f:IsMouseOver() == true
        paintThumb()
    end
    local function onUpdate()
        -- A mouse-up that never arrives (alt-tab, a cinematic) must not leave a drag stuck.
        if type(IsMouseButtonDown) == "function" and not IsMouseButtonDown("LeftButton") then
            stopDrag()
            return
        end
        follow()
    end
    f:SetScript("OnMouseDown", function(_, button)
        if button ~= nil and button ~= "LeftButton" then return end
        local y = pointerY()
        if not y then return end
        grab = Layout.scrollGrab(bar.total, bar.visible, bar.offset, bar.trackH, y) or 0
        dragging = true
        f:SetScript("OnUpdate", onUpdate)
        paintThumb()
        follow()
    end)
    -- Only the left button's release ends a drag: releasing a right click pressed during
    -- a drag must not drop it while the left button is still held.
    f:SetScript("OnMouseUp", function(_, button)
        if button ~= nil and button ~= "LeftButton" then return end
        stopDrag()
    end)
    f:SetScript("OnHide", stopDrag)
    f:HookScript("OnEnter", function()
        hovered = true
        paintThumb()
    end)
    f:HookScript("OnLeave", function()
        hovered = false
        paintThumb()
    end)
    f:Hide()
    return bar
end
