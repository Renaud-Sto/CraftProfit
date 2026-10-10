-- Pure layout arithmetic shared by the native windows: panel heights, stacking, font
-- fitting and scroll bar maths. No WoW API, unit tested in tests/test_layout.lua.
local _, ns = ...

local Layout = {}
ns.Layout = Layout

Layout.HEAD_H = 22
Layout.BODY_PAD = 4
Layout.GAP = 8
Layout.SCROLL_MIN_THUMB = 16

-- Height of a panel holding `rows` rows of `rowH` pixels (plus `extra`).
function Layout.panelHeight(rows, rowH, extra)
    rows = math.max(0, math.floor(tonumber(rows) or 0))
    return Layout.HEAD_H + Layout.BODY_PAD * 2 + rows * rowH + (extra or 0)
end

-- Vertical offsets (negative, from the top of the content area) of panels stacked
-- with `gap` between them, and the total height without the trailing gap.
function Layout.stack(heights, gap, top)
    gap = gap or Layout.GAP
    top = top or 0
    local y, offsets = top, {}
    for i, h in ipairs(heights) do
        offsets[i] = -y
        y = y + h + gap
    end
    if #heights == 0 then return offsets, 0 end
    return offsets, y - gap - top
end

-- Largest of `sizes` (descending) at which a text measured `baseWidth` wide at
-- `baseSize` fits `boxWidth`; the smallest size when none does, the first one when
-- the width cannot be measured.
function Layout.fitSize(baseWidth, baseSize, boxWidth, sizes)
    if type(baseWidth) ~= "number" or type(baseSize) ~= "number" or baseSize <= 0 then return sizes[1] end
    for _, size in ipairs(sizes) do
        if baseWidth * size / baseSize <= boxWidth then return size end
    end
    return sizes[#sizes]
end

-- Thumb height and its distance from the top of the track, for a list of `total` rows
-- of which `visible` show from row `offset` (0-based). nil when everything fits.
function Layout.scrollThumb(total, visible, offset, trackH)
    if type(total) ~= "number" or type(visible) ~= "number" or type(trackH) ~= "number" then return nil end
    if visible <= 0 or total <= visible or trackH <= 0 then return nil end
    local thumbH = math.max(Layout.SCROLL_MIN_THUMB, math.floor(trackH * visible / total + 0.5))
    thumbH = math.min(thumbH, trackH)
    local range = total - visible
    local at = math.max(0, math.min(offset or 0, range))
    return thumbH, math.floor((trackH - thumbH) * at / range + 0.5)
end

-- Row offset for a pointer `y` pixels below the top of the track, the thumb centred on
-- it; always inside 0 .. total - visible.
function Layout.scrollOffsetAt(total, visible, trackH, y)
    local thumbH = Layout.scrollThumb(total, visible, 0, trackH)
    if not thumbH or type(y) ~= "number" then return 0 end
    local free = trackH - thumbH
    if free <= 0 then return 0 end
    local fraction = math.max(0, math.min(1, (y - thumbH / 2) / free))
    return math.floor(fraction * (total - visible) + 0.5)
end

-- Where on the thumb the pointer holds it: `y` pixels below the top of the track. Returns
-- the distance from the thumb top when the pointer is on the thumb, else half the thumb
-- height (the thumb then centres on the pointer); nil when the list fits.
function Layout.scrollGrab(total, visible, offset, trackH, y)
    local thumbH, top = Layout.scrollThumb(total, visible, offset, trackH)
    if not thumbH or type(y) ~= "number" then return nil end
    if y >= top and y <= top + thumbH then return y - top end
    return thumbH / 2
end
