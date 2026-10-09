-- Shared UI kit: panels, buttons, tiles and the window frame, all coloured from the
-- current theme (see Theme.lua). The first half is pure layout arithmetic and is
-- unit tested; the widgets below it are thin glue over game frames.
local _, ns = ...
local Theme = ns.Theme

local Kit = {}
ns.Kit = Kit

Kit.HEAD_H = 22
Kit.BODY_PAD = 4
Kit.GAP = 8
Kit.CONTENT_TOP = 26
Kit.CONTENT_SIDE = 12
Kit.CONTENT_BOTTOM = 12
Kit.TILE_SIZES = { 19, 17, 15, 13, 11 }

-- Height of a panel holding `rows` rows of `rowH` pixels (plus `extra`).
function Kit.panelHeight(rows, rowH, extra)
    rows = math.max(0, math.floor(tonumber(rows) or 0))
    return Kit.HEAD_H + Kit.BODY_PAD * 2 + rows * rowH + (extra or 0)
end

-- Vertical offsets (negative, from the top of the content area) of panels stacked
-- with `gap` between them, and the total height without the trailing gap.
function Kit.stack(heights, gap, top)
    gap = gap or Kit.GAP
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
function Kit.fitSize(baseWidth, baseSize, boxWidth, sizes)
    if type(baseWidth) ~= "number" or type(baseSize) ~= "number" or baseSize <= 0 then return sizes[1] end
    for _, size in ipairs(sizes) do
        if baseWidth * size / baseSize <= boxWidth then return size end
    end
    return sizes[#sizes]
end

-- Vertical gradient from `top` to `bottom` ({ r, g, b, a }). The client's gradient
-- call takes the bottom colour first. Returns which form worked: "color" (colour
-- objects), "rgb" (six numbers) or "flat" (the middle colour, when neither does).
function Kit.gradient(tex, top, bottom)
    if type(CreateColor) == "function" then
        local ok = pcall(tex.SetGradient, tex, "VERTICAL",
            CreateColor(bottom[1], bottom[2], bottom[3], bottom[4]),
            CreateColor(top[1], top[2], top[3], top[4]))
        if ok then return "color" end
    end
    if pcall(tex.SetGradient, tex, "VERTICAL", bottom[1], bottom[2], bottom[3], top[1], top[2], top[3]) then
        return "rgb"
    end
    tex:SetColorTexture((top[1] + bottom[1]) / 2, (top[2] + bottom[2]) / 2,
        (top[3] + bottom[3]) / 2, (top[4] + bottom[4]) / 2)
    return "flat"
end

Kit.themeName = Theme.DEFAULT
Kit.current = Theme.get(Theme.DEFAULT)
