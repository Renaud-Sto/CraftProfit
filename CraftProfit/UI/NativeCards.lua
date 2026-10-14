-- Native widget kit, part 2 of 3 (the rules every widget keeps: UI/Native.lua): the panel
-- and the tile with their switchable appearance variants and registry, and the result
-- banner.
local _, ns = ...

local Native = ns.Native
local rgbOf, paintText, applyAtlas = Native._rgbOf, Native._paintText, Native._applyAtlas
local naturalWidth = Native.naturalWidth

-- Panel ---------------------------------------------------------------------------

Native.HEAD_H = 22
-- Header strip choices (the player's appearance setting). Switching repaints every panel
-- already built and applies to the ones built afterwards.
Native.HEADER_VARIANTS = {
    a = "questlog-reward-header-top",
    b = "friends-frame-toptexbg",
    c = "_UI-Frame-TopTileStreaks",
}
-- The part of an atlas that holds the art, when the atlas has shadow around it: the quest bar
-- (307 x 55.5) has a dark rim above and below its wood (measured with /cppn atlas, about
-- 20% on top and 3% at the bottom); stretched whole into a 22 px header, the wood was only
-- 17 px tall and the title and the sort button stuck out of it.
Native.HEADER_CROP = { a = { 0, 1, 0.2, 0.97 } }
Native.headerVariant = "b"
Native.DIVIDER_ATLAS = "perks-divider-short"
-- The header sits this far inside the panel's inset border, on every side but the bottom;
-- the body keeps the same margin at the bottom. 2 + 22 + 4 + rows + 2 = Layout.panelHeight.
Native.PANEL_EDGE = 2
local PANEL_EDGE = Native.PANEL_EDGE
local PANEL_SIDE = PANEL_EDGE + 2

-- Every panel and tile built by this module, in creation order, so a change of look
-- reaches the live ones (shown or hidden). Each is added once, by its constructor; only
-- tables made here go in. Frames are never destroyed by the game, so nothing is removed.
Native.registry = { panels = {}, tiles = {} }

-- The header strip and tile card in use: header, tile keys. Read by the tests only (the
-- addon keeps the saved choice in CraftProfitDB.settings.appearance).
function Native.appearance()
    return Native.headerVariant, Native.tileVariant
end

-- Makes the strip texture of header variant `key` on `head`, hidden: its atlas set once,
-- for good, or the fallback (a faint gold strip, the colour of the game's header text;
-- nothing when the game gives no colour). Returns the texture and the atlas name (nil on
-- fallback).
local function headerTexture(head, key)
    local tex = head:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints(head)
    local atlas = Native.HEADER_VARIANTS[key]
    if applyAtlas(tex, atlas) then
        -- Coordinates after SetAtlas are read inside the atlas, as the game does it.
        local crop = Native.HEADER_CROP[key]
        if crop then tex:SetTexCoord(crop[1], crop[2], crop[3], crop[4]) end
    else
        atlas = nil
        local r, g, b = rgbOf(NORMAL_FONT_COLOR)
        if r then tex:SetColorTexture(r, g, b, 0.15) end
    end
    tex:Hide()
    return tex, atlas
end

-- Shows the strip of the current variant on panel `p` and hides the others. Used at
-- construction and by a live switch; never sets an atlas.
local function paintHeader(p)
    local key = Native.headerVariant
    for k, tex in pairs(p.headerTextures) do tex:SetShown(k == key) end
    p.headerBg = p.headerTextures[key]
    p.headerAtlas = p.headerAtlases[key]
end

-- Picks the header strip; repaints every registered panel when it changes. An unknown key
-- keeps the current one. Returns the key in use.
function Native.setHeaderVariant(key)
    if key ~= nil and Native.HEADER_VARIANTS[key] and key ~= Native.headerVariant then
        Native.headerVariant = key
        for _, p in ipairs(Native.registry.panels) do paintHeader(p) end
    end
    return Native.headerVariant
end

-- A section of a window: the game's dark inset as background, a header strip with a title
-- (and an optional right-hand text in p.right), a divider under it, and a body to fill.
-- Fields and methods: frame, body, title, right, setTitle, setRows,
-- height, onHeaderClick. Also: inset, head, headerTextures (one per variant, each with its
-- own atlas for good), headerBg (the one shown), headerAtlas (nil when the fallback is
-- drawn), divider (nil when its atlas is missing). Registered for
-- live appearance switches (Native.setHeaderVariant).
function Native.panel(parent, title)
    local Layout = ns.Layout
    local p = {}
    local f = CreateFrame("Frame", nil, parent)
    p.frame = f
    -- InsetFrameTemplate shares its parent's level (useParentLevel): everything else here is
    -- in child frames, one level up, so it always draws over it.
    p.inset = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
    p.inset:SetAllPoints(f)

    local head = CreateFrame("Frame", nil, f)
    -- The strip stops short of the inset's bevel on both sides (4 px, not PANEL_EDGE): the
    -- wood reached over the border there.
    head:SetPoint("TOPLEFT", f, "TOPLEFT", PANEL_SIDE, -PANEL_EDGE)
    head:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PANEL_SIDE, -PANEL_EDGE)
    head:SetHeight(Native.HEAD_H)
    p.head = head
    -- One texture per variant: a live switch only shows another.
    p.headerTextures, p.headerAtlases = {}, {}
    for key in pairs(Native.HEADER_VARIANTS) do
        p.headerTextures[key], p.headerAtlases[key] = headerTexture(head, key)
    end
    paintHeader(p)
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
    local panels = Native.registry.panels
    panels[#panels + 1] = p

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
    p.body:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -Layout.BODY_PAD)
    p.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PANEL_EDGE, PANEL_EDGE)

    p.rowH = 18
    function p:setTitle(text) self.title:SetText(text or "") end
    function p:setRows(rows, rowH, extra)
        self.rowH = rowH or self.rowH
        f:SetHeight(Layout.panelHeight(rows, self.rowH, extra))
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

-- Tile card choices (the player's appearance setting). "a": the loot card atlas, its stroke
-- as the best-tile outline. "b": a nested game inset with a 2 px gold outline for the best
-- tile. Every tile builds both and shows one; switching repaints the live tiles.
Native.TILE_VARIANTS = { a = "looting_itemcard_bg", b = "inset" }
Native.tileVariant = "b"
Native.TILE_STROKE_ATLAS = "looting_itemcard_stroke_normal"
Native.TILE_PAD = 10
Native.TILE_ICON = 12
-- The value font steps down this ladder of game fonts (never SetFont with a file) until it
-- fits; the sizes are the fonts' heights, for Layout.fitSize.
Native.TILE_FONTS = {
    { "GameFontNormalHuge", 20 },
    { "GameFontNormalLarge2", 18 },
    { "GameFontNormalLarge", 16 },
    { "GameFontNormalMed2", 14 },
    { "GameFontNormal", 12 },
}
-- The heights of a font ladder, for Layout.fitSize; built once, not at every render.
local function sizesOf(fonts)
    local sizes = {}
    for i, font in ipairs(fonts) do sizes[i] = font[2] end
    return sizes
end
local TILE_SIZES = sizesOf(Native.TILE_FONTS)
local TILE_OUTLINE = 2
local HOVER_FILE = "Interface\\QuestFrame\\UI-QuestTitleHighlight"

-- Picks the tile card; repaints every registered tile when it changes. An unknown key keeps
-- the current one. Returns the key in use.
function Native.setTileVariant(key)
    if key ~= nil and Native.TILE_VARIANTS[key] and key ~= Native.tileVariant then
        Native.tileVariant = key
        for _, tile in ipairs(Native.registry.tiles) do tile:applyVariant() end
    end
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

-- A small card with a label and a large value that shrinks to fit its width. Fields
-- and methods: frame, label, value, set(spec), onClick(fn), showIcon(show),
-- hit, icon, best, muted. Also: variant (the one asked for), bgAtlas (nil when the inset is
-- drawn: variant b, or the card atlas missing), outline (the best-tile marks in use), and
-- both structures: cardBg and cardStroke (the loot card textures), inset and goldOutline
-- (the nested inset and its 4 gold lines). applyVariant() shows the current variant's;
-- Native.setTileVariant calls it on every registered tile.
function Native.tile(parent, width, height)
    local Layout = ns.Layout
    local tile = { best = false, muted = false, width = width }
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 110, height or 52)
    tile.frame = f
    -- Texts, outline and hover live on `face`, a child one level above the background
    -- (the nested inset shares the tile's level).
    local face = CreateFrame("Frame", nil, f)
    face:SetAllPoints(f)
    tile.face = face

    -- Variant a: the loot card and its stroke. Their atlases are applied when first shown
    -- and retried until the client knows them.
    local cardAtlas = Native.TILE_VARIANTS.a
    local cardBg = f:CreateTexture(nil, "BACKGROUND")
    cardBg:SetAllPoints(f)
    cardBg:Hide()
    tile.cardBg = cardBg
    local cardStroke = face:CreateTexture(nil, "BORDER")
    cardStroke:SetAllPoints(face)
    cardStroke:Hide()
    tile.cardStroke = cardStroke
    local cardOk, strokeOk = false, false
    -- Variant b (and the fallback of a): the nested inset and a gold outline.
    tile.inset = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
    tile.inset:SetAllPoints(f)
    tile.goldOutline = goldOutline(face)

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
        -- Only the marks of the structure in use; the other structure's stay hidden.
        cardStroke:SetShown(tile.best and tile.outline[1] == cardStroke)
        for _, line in ipairs(tile.goldOutline) do line:SetShown(tile.best and tile.outline == tile.goldOutline) end
        -- SetFontObject resets the colour to the font's own: paint after every font change.
        paintText(tile.value, tile.muted and DISABLED_FONT_COLOR or HIGHLIGHT_FONT_COLOR)
    end

    -- Shows the structure of the current variant and hides the other. The best mark: the
    -- card's own stroke when the card and its stroke exist, else gold.
    function tile:applyVariant()
        self.variant = Native.tileVariant
        local card = false
        if self.variant == "a" then
            if not cardOk then cardOk = applyAtlas(cardBg, cardAtlas) ~= nil end
            card = cardOk
        end
        cardBg:SetShown(card)
        self.inset:SetShown(not card)
        self.bgAtlas = card and cardAtlas or nil
        if card and not strokeOk then strokeOk = applyAtlas(cardStroke, Native.TILE_STROKE_ATLAS) ~= nil end
        self.outline = (card and strokeOk) and { cardStroke } or self.goldOutline
        paint()
    end

    -- spec: { label, tag, value, best, muted }.
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
        local fonts, sizes = Native.TILE_FONTS, TILE_SIZES
        self.value:SetFontObject(fonts[1][1])
        self.value:SetText(spec.value or "")
        local room = (f:GetWidth() or width or 110) - Native.TILE_PAD * 2
        local size = Layout.fitSize(naturalWidth(self.value), sizes[1], room, sizes)
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
        self:anchorLabel()
    end

    -- The label's right end: before the owner's mark (tile.mark, a fontstring it places at
    -- the top right) when there is one, else before the magnifier or the tile's padding.
    function tile:anchorLabel()
        if self.mark then
            self.label:SetPoint("TOPRIGHT", self.mark, "TOPLEFT", -4, 0)
            return
        end
        local shown = self.icon and self.icon:IsShown()
        local right = shown and (6 + Native.TILE_ICON + 4) or Native.TILE_PAD
        self.label:SetPoint("TOPRIGHT", f, "TOPRIGHT", -right, -8)
    end

    tile:applyVariant()
    local tiles = Native.registry.tiles
    tiles[#tiles + 1] = tile
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
local BANNER_SIZES = sizesOf(Native.BANNER_FONTS)
local BANNER_GAP = 8
local BANNER_TONES = { profit = "profit", loss = "loss", incomplete = "incomplete" }

-- parent, height; `width` (optional) is the width the caller will anchor it to, used to
-- measure the text while the frame has no laid-out width yet (its own width wins once it
-- has one). Fields: frame, inset, face, label, text, value, fillTexture, edges (4 lines),
-- fill and edge (the { r, g, b, a } applied), set(spec).
function Native.banner(parent, height, width)
    local Layout, Colors = ns.Layout, ns.Colors
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

        local fonts, sizes = Native.BANNER_FONTS, BANNER_SIZES
        self.value:SetFontObject(fonts[1][1])
        self.value:SetText(spec.value or "")
        local size = Layout.fitSize(naturalWidth(self.value), sizes[1], Native.BANNER_VALUE_ROOM, sizes)
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
        if type(frameWidth) == "number" and textWidth > 0
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

-- Shared with UI/NativeLists.lua (the list row's hover); not part of the widget API.
Native._HOVER_FILE = HOVER_FILE
