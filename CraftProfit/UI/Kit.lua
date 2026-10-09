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

-- Theme registry ------------------------------------------------------------

-- Every widget registers a function that paints it from a theme; applyTheme
-- repaints them all, so a theme can be switched while windows are open.
local registry = {}

local function register(paint)
    registry[#registry + 1] = paint
    paint(Kit.current)
end

function Kit.applyTheme(name)
    Kit.themeName = Theme.exists(name) and name or Theme.DEFAULT
    Kit.current = Theme.get(Kit.themeName)
    for _, paint in ipairs(registry) do paint(Kit.current) end
    return Kit.current
end

-- A token name, a function returning one, or "black".
local function colorOf(token)
    if type(token) == "function" then token = token() end
    if token == "black" then return { 0, 0, 0, 1 } end
    return Kit.current[token]
end

local function paintTexture(tex, token)
    local c = colorOf(token)
    tex:SetColorTexture(c[1], c[2], c[3], c[4])
end

local function setTextColor(fontString, token)
    local c = colorOf(token)
    fontString:SetTextColor(c[1], c[2], c[3], c[4])
end

-- Draws one-pixel rings from the outside in, one per token (solid-colour textures,
-- no Blizzard atlas needed). Returns a function that repaints them, for rings whose
-- token is a function.
function Kit.rings(frame, tokens, layer)
    local paints = {}
    for i, token in ipairs(tokens) do
        local n = i - 1
        local function line(p1, x1, y1, p2, x2, y2, width, height)
            local tex = frame:CreateTexture(nil, layer or "BORDER")
            tex:SetPoint(p1, frame, p1, x1, y1)
            tex:SetPoint(p2, frame, p2, x2, y2)
            if width then tex:SetWidth(width) end
            if height then tex:SetHeight(height) end
            paints[#paints + 1] = function() paintTexture(tex, token) end
        end
        line("TOPLEFT", n, -n, "TOPRIGHT", -n, -n, nil, 1)
        line("BOTTOMLEFT", n, n, "BOTTOMRIGHT", -n, n, nil, 1)
        line("TOPLEFT", n, -n - 1, "BOTTOMLEFT", n, n + 1, 1, nil)
        line("TOPRIGHT", -n, -n - 1, "BOTTOMRIGHT", -n, n + 1, 1, nil)
    end
    local function refresh()
        for _, paint in ipairs(paints) do paint() end
    end
    register(refresh)
    return refresh
end

-- Window ----------------------------------------------------------------------

local WINDOW_RINGS = { "black", "frameInner", "frameInner", "frameShade", "frameOuter", "black" }
local PLAQUE_MIN_WIDTH = 210

-- A movable framed window with a title plaque straddling its top edge and a close
-- button. `frame.content` is the area to fill. opts: width, height, onMoved(point, x, y).
function Kit.window(name, title, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(opts.width or 372, opts.height or 200)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    register(function(t) bg:SetColorTexture(t.windowBg[1], t.windowBg[2], t.windowBg[3], t.windowBg[4]) end)
    Kit.rings(f, WINDOW_RINGS)

    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Re-anchor to the screen's bottom-left corner so saved offsets are absolute.
        local left, top = self:GetLeft(), self:GetTop()
        if left and top then
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            if opts.onMoved then opts.onMoved("TOPLEFT", left, top) end
        end
    end)

    local plaque = CreateFrame("Frame", nil, f)
    plaque:SetPoint("TOP", f, "TOP", 0, 14)
    plaque:SetSize(PLAQUE_MIN_WIDTH, 26)
    local plaqueBg = plaque:CreateTexture(nil, "BACKGROUND")
    plaqueBg:SetAllPoints(plaque)
    register(function(t) plaqueBg:SetColorTexture(t.plaqueBg[1], t.plaqueBg[2], t.plaqueBg[3], t.plaqueBg[4]) end)
    Kit.rings(plaque, { "black", "frameOuter", "black" })
    local text = plaque:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER", plaque, "CENTER", 0, 0)
    register(function() setTextColor(text, "plaqueText") end)
    f.plaque = plaque
    f.titleText = text

    f.setTitle = function(_, value)
        text:SetText(value or "")
        local width = text:GetStringWidth()
        if type(width) == "number" then plaque:SetWidth(math.max(PLAQUE_MIN_WIDTH, width + 44)) end
    end
    f:setTitle(title)

    local close = Kit.button(f, "small", "x")
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() f:Hide() end)
    f.close = close

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", Kit.CONTENT_SIDE, -Kit.CONTENT_TOP)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -Kit.CONTENT_SIDE, Kit.CONTENT_BOTTOM)
    f.content = content
    return f
end

-- Panel -----------------------------------------------------------------------

-- A bordered section with a header bar. Fill `p.body`; size it with setRows.
function Kit.panel(parent, title)
    local p = {}
    local f = CreateFrame("Frame", nil, parent)
    p.frame = f
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    register(function() paintTexture(bg, "panelBg") end)
    Kit.rings(f, { "panelEdge" })

    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    head:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    head:SetHeight(Kit.HEAD_H)
    local headBg = head:CreateTexture(nil, "BACKGROUND")
    headBg:SetAllPoints(head)
    local rule = head:CreateTexture(nil, "BORDER")
    rule:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", 0, 0)
    rule:SetHeight(1)
    p.title = head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.title:SetPoint("LEFT", head, "LEFT", 8, 0)
    p.right = head:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.right:SetPoint("RIGHT", head, "RIGHT", -8, 0)
    register(function(t)
        Kit.gradient(headBg, t.headBgTop, t.headBgBottom)
        paintTexture(rule, "headRule")
        setTextColor(p.title, "headText")
    end)

    p.body = CreateFrame("Frame", nil, f)
    p.body:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -Kit.BODY_PAD)
    p.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)

    p.rowH = 18
    function p:setTitle(text) self.title:SetText(text or "") end
    function p:setRows(rows, rowH, extra)
        self.rowH = rowH or self.rowH
        f:SetHeight(Kit.panelHeight(rows, self.rowH, extra))
    end
    p.height = function() return f:GetHeight() end
    p:setTitle(title)
    return p
end

-- Button ----------------------------------------------------------------------

-- kind: "normal", "primary" (gold, the one main action of a window) or "small".
function Kit.button(parent, kind, text)
    local small = kind == "small"
    local primary = kind == "primary"
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(small and 18 or 24)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    b.label = b:CreateFontString(nil, "OVERLAY", small and "GameFontNormalSmall" or "GameFontNormal")
    b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
    Kit.rings(b, { primary and "primaryEdge" or "buttonEdge" })

    local hover = false
    local function paint(t)
        local c = (primary or hover) and t.primaryBg or t.buttonBg
        bg:SetColorTexture(c[1], c[2], c[3], c[4])
        setTextColor(b.label, primary and "primaryText" or "buttonText")
    end
    register(paint)
    b:SetScript("OnEnter", function() hover = true; paint(Kit.current) end)
    b:SetScript("OnLeave", function() hover = false; paint(Kit.current) end)

    function b:setText(value) self.label:SetText(value or "") end
    b:setText(text)
    return b
end

-- Tile ------------------------------------------------------------------------

-- A small card with a label and a large value that shrinks to fit its width.
function Kit.tile(parent, width, height)
    local tile = { best = false, muted = false }
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 110, height or 52)
    tile.frame = f
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    register(function() paintTexture(bg, "panelBg") end)
    local refreshRings = Kit.rings(f, { function() return tile.best and "bestEdge" or "panelEdge" end })

    tile.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tile.label:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
    tile.value = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tile.value:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -24)

    local function paint()
        setTextColor(tile.label, "headText")
        setTextColor(tile.value, tile.muted and "textMuted" or "textMain")
        refreshRings()
    end
    register(paint)

    -- spec: { label, tag, value, best, muted }
    function tile:set(spec)
        self.best = spec.best and true or false
        self.muted = spec.muted and true or false
        local label = spec.label or ""
        if spec.tag then label = label .. " |cffffd100" .. spec.tag .. "|r" end
        self.label:SetText(label)
        local big = Kit.TILE_SIZES[1]
        self.value:SetFont(STANDARD_TEXT_FONT, big, "")
        self.value:SetText(spec.value or "")
        local room = (f:GetWidth() or width or 110) - 20
        local size = Kit.fitSize(self.value:GetStringWidth(), big, room, Kit.TILE_SIZES)
        if size ~= big then self.value:SetFont(STANDARD_TEXT_FONT, size, "") end
        paint()
    end
    return tile
end
