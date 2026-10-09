-- The main window, built on the shared UI kit (UI/Kit.lua): a result banner, three
-- tiles for the ways to sell the item, a Materials panel and an Options panel; at the
-- auction house the pinned list (UI/PinsUI.lua) hangs below. Parented to UIParent
-- (never to a Blizzard frame, to avoid taint); anchored beside the profession or AH
-- window until the user drags it, after which the saved position wins.
local _, ns = ...
local L = ns.L
local Kit, Theme = ns.Kit, ns.Theme

local Window = {}
ns.Window = Window

local WIDTH = 372
local ROW_H = 18
local BANNER_H = 52
local TILE_H = 52
local LIKELY_H = 16
local AGE_H = 14
local OPTION_ROWS = 3
local OPTION_ROW_H = 26
local EMPTY_H = 24
local MAX_DETAIL = 12 -- Recipes.MAX_REAGENTS
local BANNER_SIZES = { 22, 19, 16, 13 }
local BANNER_VALUE_ROOM = 120 -- widest the value may be before it shrinks
local BANNER_FILL, BANNER_EDGE = 0.09, 0.45

local TONES = {
    profit = Theme.FIXED.profit,
    loss = Theme.FIXED.loss,
    incomplete = Theme.FIXED.incomplete,
    none = Theme.FIXED.trivial,
}

local frame, content, pinsHost
local handlers = {}
local expanded = true
local contentHeight = 80
-- The widgets, exposed for tests: `frames` maps a section key to its frame.
local parts = { frames = {}, tiles = {}, rows = {} }

Window.WIDTH = WIDTH
Window.parts = parts
Window.lastModel = nil
Window.lastHandlers = nil

-- Blocks of the recipe view, top to bottom, with their heights. Pure.
-- opts: hasLikely (a "likely outcome" line), expanded (Materials unfolded), reagents.
function Window.sections(opts)
    local list = { { key = "banner", height = BANNER_H }, { key = "tiles", height = TILE_H } }
    if opts.hasLikely then list[#list + 1] = { key = "likely", height = LIKELY_H } end
    list[#list + 1] = {
        key = "materials",
        height = opts.expanded and Kit.panelHeight(opts.reagents, ROW_H) or Kit.FOLDED_H,
    }
    list[#list + 1] = { key = "age", height = AGE_H }
    list[#list + 1] = { key = "options", height = Kit.panelHeight(OPTION_ROWS, OPTION_ROW_H) }
    return list
end

local function heightsOf(list)
    local heights = {}
    for i, section in ipairs(list) do heights[i] = section.height end
    return heights
end

-- Window height needed for these sections (without the pinned list).
function Window.contentHeightOf(list)
    local _, total = Kit.stack(heightsOf(list), Kit.GAP, 0)
    return total + Kit.CONTENT_TOP + Kit.CONTENT_BOTTOM
end

local function themed(fontString, token)
    Kit.onTheme(function(t)
        local c = t[token]
        fontString:SetTextColor(c[1], c[2], c[3], c[4])
    end)
end

-- Item name for the fold-out; "#id" while the game has not loaded it (or when
-- the name is a secret value, which raises when concatenated).
local function reagentName(itemID)
    local ok, name = pcall(C_Item.GetItemInfo, itemID)
    if ok and type(name) == "string" then
        local fine, text = pcall(function() return name .. "" end)
        if fine then return text end
    end
    return "#" .. itemID
end

local function findLine(lines, key)
    for _, line in ipairs(lines or {}) do
        if line.key == key then return line end
    end
    return nil
end

local function newSection(key, height)
    local f = CreateFrame("Frame", nil, content)
    f:SetHeight(height)
    parts.frames[key] = f
    return f
end

-- Banner: the label, the best way to sell and the net result in large type; its tint
-- follows the kind of result (gain, loss, incomplete) and not the theme.
local function buildBanner()
    local f = newSection("banner", BANNER_H)
    local fill = { 0, 0, 0, 0 }
    local edge = { 0, 0, 0, 0 }
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    local function paintFill() bg:SetColorTexture(fill[1], fill[2], fill[3], fill[4]) end
    paintFill()
    local refreshEdge = Kit.rings(f, { function() return edge end })

    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    themed(label, "headText")
    local value = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    value:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    value:SetJustifyH("RIGHT")
    -- The label stops before the value too, so a long warning cannot run under it.
    label:SetPoint("RIGHT", value, "LEFT", -8, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    -- The text runs up to the value, so a short or empty value leaves it more room.
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
    text:SetPoint("RIGHT", value, "LEFT", -8, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    local best = Theme.FIXED.best
    text:SetTextColor(best[1], best[2], best[3], best[4])
    parts.banner = {
        label = label, text = text, value = value,
        fill = fill, edge = edge, paintFill = paintFill, refreshEdge = refreshEdge,
    }
end

local function setBanner(spec)
    local b = parts.banner
    local tone = TONES[spec.kind] or TONES.none
    local label = spec.label or ""
    if spec.warning then
        label = label .. " \194\183 " .. Kit.colorEscape(Theme.FIXED.incomplete) .. spec.warning .. "|r"
    end
    b.label:SetText(label)
    b.text:SetText(spec.text or "")
    b.value:SetFont(STANDARD_TEXT_FONT, BANNER_SIZES[1], "")
    b.value:SetText(spec.value or "")
    local size = Kit.fitSize(Kit.naturalWidth(b.value), BANNER_SIZES[1], BANNER_VALUE_ROOM, BANNER_SIZES)
    if size ~= BANNER_SIZES[1] then b.value:SetFont(STANDARD_TEXT_FONT, size, "") end
    b.value:SetTextColor(tone[1], tone[2], tone[3], tone[4])
    -- A text too long for the room left by the value (a partial result, say) drops to
    -- the small font rather than losing its end; kept normal when it cannot be measured.
    b.text:SetFontObject("GameFontNormal")
    local valueWidth, textWidth = Kit.naturalWidth(b.value), Kit.naturalWidth(b.text)
    if type(valueWidth) == "number" and type(textWidth) == "number"
        and textWidth > WIDTH - Kit.CONTENT_SIDE * 2 - 24 - valueWidth - 8 then
        b.text:SetFontObject("GameFontNormalSmall")
    end
    -- SetFontObject resets the colour to the font object's own.
    local best = Theme.FIXED.best
    b.text:SetTextColor(best[1], best[2], best[3], best[4])
    b.fill[1], b.fill[2], b.fill[3], b.fill[4] = tone[1], tone[2], tone[3], BANNER_FILL
    b.edge[1], b.edge[2], b.edge[3], b.edge[4] = tone[1], tone[2], tone[3], BANNER_EDGE
    b.paintFill()
    b.refreshEdge()
end

local function buildTiles()
    local f = newSection("tiles", TILE_H)
    local width = math.floor((WIDTH - Kit.CONTENT_SIDE * 2 - Kit.GAP * 2) / 3)
    for i = 1, 3 do
        local tile = Kit.tile(f, width, TILE_H)
        tile.frame:SetPoint("TOPLEFT", f, "TOPLEFT", (i - 1) * (width + Kit.GAP), 0)
        parts.tiles[i] = tile
    end
end

-- One grey line under the tiles: the most probable disenchant outcome.
local function buildLikely()
    local f = newSection("likely", LIKELY_H)
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", f, "LEFT", 4, 0)
    text:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    themed(text, "textMuted")
    parts.likely = text
end

-- Materials: the header folds the detail; each row searches its reagent at the AH.
local function buildMaterials()
    local panel = Kit.panel(content, "")
    parts.frames.materials = panel.frame
    parts.materials = panel
    panel:onHeaderClick(function()
        if handlers.onCostToggle then handlers.onCostToggle(not expanded) end
    end)
    for i = 1, MAX_DETAIL do
        local y = -(i - 1) * ROW_H
        local hit = CreateFrame("Button", nil, panel.body)
        hit:SetHeight(ROW_H)
        hit:SetPoint("TOPLEFT", panel.body, "TOPLEFT", 0, y)
        hit:SetPoint("TOPRIGHT", panel.body, "TOPRIGHT", 0, y)
        local hover = hit:CreateTexture(nil, "BACKGROUND")
        hover:SetAllPoints(hit)
        Kit.onTheme(function(t)
            local c = t.rowHover
            hover:SetColorTexture(c[1], c[2], c[3], c[4])
        end)
        hover:Hide()
        hit:HookScript("OnEnter", function() hover:Show() end)
        hit:HookScript("OnLeave", function() hover:Hide() end)
        local name = hit:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        name:SetPoint("LEFT", hit, "LEFT", 8, 0)
        name:SetPoint("RIGHT", hit, "RIGHT", -80, 0)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        themed(name, "textMain")
        local value = hit:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        value:SetPoint("RIGHT", hit, "RIGHT", -8, 0)
        value:SetJustifyH("RIGHT")
        themed(value, "textMuted")
        local row = { hit = hit, name = name, value = value }
        hit:SetScript("OnClick", function()
            if row.itemID and handlers.onReagentClick then handlers.onReagentClick(row.itemID, row.qty) end
        end)
        parts.rows[i] = row
    end
end

local function buildAge()
    local f = newSection("age", AGE_H)
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    text:SetPoint("LEFT", f, "LEFT", 4, 0)
    parts.age = text
    parts.ageStale = false
    parts.paintAge = function()
        local c = parts.ageStale and Theme.FIXED.stale or Kit.current.textMuted
        text:SetTextColor(c[1], c[2], c[3], c[4])
    end
    Kit.onTheme(function() parts.paintAge() end)
end

-- Options: the crafts multiplier, history tracking, the cost-per-point option and the
-- pin button.
local function buildOptions()
    local panel = Kit.panel(content, L.PANEL_OPTIONS)
    parts.frames.options = panel.frame
    parts.options = panel
    local body = panel.body

    parts.craftsLabel = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    parts.craftsLabel:SetPoint("TOPLEFT", body, "TOPLEFT", 8, -6)
    themed(parts.craftsLabel, "textMain")
    local box = Kit.input(body, 52, 4)
    box:SetNumeric(true)
    box:SetPoint("TOPLEFT", body, "TOPLEFT", 70, -2)
    -- Applied when the box loses focus (Enter, Escape or a click elsewhere).
    box:SetScript("OnEditFocusLost", function(self)
        if handlers.onCraftsChange then handlers.onCraftsChange(self:GetText()) end
    end)
    parts.craftsBox = box

    local track = Kit.check(body, "")
    track:SetPoint("TOPLEFT", body, "TOPLEFT", 160, -4)
    track.onToggle = function(checked)
        if handlers.onTrackToggle then handlers.onTrackToggle(checked) end
    end
    parts.track = track

    local perPoint = Kit.check(body, "")
    perPoint:SetPoint("TOPLEFT", body, "TOPLEFT", 8, -OPTION_ROW_H - 4)
    perPoint.onToggle = function(checked)
        if handlers.onPerPointToggle then handlers.onPerPointToggle(checked) end
    end
    parts.perPoint = perPoint
    parts.perPointValue = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    parts.perPointValue:SetPoint("TOPRIGHT", body, "TOPRIGHT", -8, -OPTION_ROW_H - 7)
    parts.perPointValue:SetJustifyH("RIGHT")
    -- The value wins: a long (translated) label is cut short before it runs under it.
    perPoint.label:SetPoint("RIGHT", parts.perPointValue, "LEFT", -8, 0)
    perPoint.label:SetWordWrap(false)
    perPoint.label:SetJustifyH("LEFT")
    parts.perPointTone = nil
    -- A gain or a cost keeps its fixed colour; a neutral value follows the theme.
    parts.paintPerPoint = function()
        local tone = parts.perPointTone
        local c = tone == "profit" and Theme.FIXED.profit or tone == "loss" and Theme.FIXED.loss
            or Kit.current.textMain
        parts.perPointValue:SetTextColor(c[1], c[2], c[3], c[4])
    end
    Kit.onTheme(function() parts.paintPerPoint() end)

    local pin = Kit.button(body, "normal", "")
    pin:SetWidth(120)
    pin:SetPoint("TOPLEFT", body, "TOPLEFT", 8, -OPTION_ROW_H * 2 - 2)
    pin:SetScript("OnClick", function()
        if handlers.onPinClick then handlers.onPinClick() end
    end)
    parts.pin = pin
end

function Window.create(h)
    if frame then return frame end
    handlers = h or {}
    Window.lastHandlers = handlers

    frame = Kit.window("CraftProfitWindow", L.TITLE, {
        width = WIDTH,
        onMoved = function(point, x, y)
            if handlers.onMoved then handlers.onMoved(point, x, y) end
        end,
    })
    content = frame.content
    buildBanner()
    buildTiles()
    buildLikely()
    buildMaterials()
    buildAge()
    buildOptions()

    parts.empty = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    parts.empty:SetPoint("TOP", content, "TOP", 0, -4)

    pinsHost = CreateFrame("Frame", nil, frame)
    pinsHost:SetWidth(WIDTH)
    pinsHost:SetHeight(0)
    pinsHost:Hide()

    -- A new frame starts shown: the controller decides when the window appears.
    frame:Hide()
    return frame
end

function Window.setTitle(text)
    if frame then frame:setTitle(text) end
end

-- Frame height = recipe sections + pinned-recipes section (when shown).
function Window.relayout()
    if not frame then return end
    pinsHost:ClearAllPoints()
    pinsHost:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -contentHeight)
    local extra = pinsHost:IsShown() and pinsHost:GetHeight() or 0
    frame:SetHeight(contentHeight + extra)
end

local function hideSections()
    for _, f in pairs(parts.frames) do f:Hide() end
end

function Window.showEmpty(text)
    if not frame then return end
    Window.lastModel = nil
    frame:setTitle(L.TITLE)
    hideSections()
    parts.empty:SetText(text)
    parts.empty:Show()
    contentHeight = Kit.CONTENT_TOP + EMPTY_H + Kit.CONTENT_BOTTOM
    Window.relayout()
end

-- Stacks the sections of `list` under each other and sizes the frame.
local function layout(list)
    hideSections()
    local offsets = Kit.stack(heightsOf(list), Kit.GAP, 0)
    for i, section in ipairs(list) do
        local f = parts.frames[section.key]
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", content, "TOPLEFT", 0, offsets[i])
        f:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, offsets[i])
        f:SetHeight(section.height)
        f:Show()
    end
    contentHeight = Window.contentHeightOf(list)
    Window.relayout()
end

local function setPerPoint(line)
    local value = parts.perPointValue
    if not line then
        -- Emptied too: the label is anchored to it and would stay cut short.
        value:SetText("")
        value:Hide()
        return
    end
    parts.perPointTone = line.tone
    value:SetText((line.tone == "profit" and "+" or "") .. (line.value or ""))
    parts.paintPerPoint()
    value:Show()
end

function Window.render(model)
    if not frame then return end
    Window.lastModel = model
    local costLines = model.costLines or {}
    expanded = model.costExpanded ~= false
    frame:setTitle(model.title or L.TITLE)
    parts.empty:Hide()

    setBanner(model.banner or { kind = "none", text = "", value = "" })
    for i, tile in ipairs(parts.tiles) do tile:set((model.tiles or {})[i] or {}) end

    local likely = findLine(model.lines, "likely")
    parts.likely:SetText(likely and likely.label or "")

    local materials = model.materials or { title = L.PANEL_MATERIALS, total = "" }
    parts.materials:setTitle((expanded and "- " or "+ ") .. materials.title)
    parts.materials.right:SetText(materials.total)
    parts.materials.body:SetShown(expanded)
    for i = 1, MAX_DETAIL do
        local row, cost = parts.rows[i], expanded and costLines[i] or nil
        if cost then
            row.itemID, row.qty = cost.itemID, cost.qty
            row.name:SetText(cost.qty .. "x " .. reagentName(cost.itemID))
            row.value:SetText(cost.subtotalText)
            row.hit:Show()
        else
            row.itemID = nil
            row.hit:Hide()
        end
    end

    parts.age:SetText(model.ageText or "")
    parts.ageStale = model.stale and true or false
    parts.paintAge()

    parts.craftsLabel:SetText(L.CRAFTS_LABEL)
    -- Never rewrite the box while the player is typing in it.
    if not parts.craftsBox:HasFocus() then parts.craftsBox:SetText(tostring(model.crafts or 1)) end
    parts.track:setText(L.TRACK_LABEL)
    parts.track:SetChecked(model.tracked)
    parts.perPoint:setText(L.OPT_PER_POINT)
    parts.perPoint:SetChecked(model.showPerPoint)
    setPerPoint(findLine(model.lines, "perpoint"))
    parts.pin:setText(model.pinned and L.UNPIN or L.PIN)

    layout(Window.sections({
        hasLikely = likely ~= nil,
        expanded = expanded,
        reagents = math.min(#costLines, MAX_DETAIL),
    }))
end

-- Position: the saved one if there is one, else beside the target window.
function Window.attach(target, saved)
    if not frame then return end
    frame:ClearAllPoints()
    if saved then
        if saved.point == "TOPLEFT" then
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.x, saved.y)
        else
            frame:SetPoint(saved.point, UIParent, saved.point, saved.x, saved.y)
        end
    elseif target then
        frame:SetPoint("TOPLEFT", target, "TOPRIGHT", 6, 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
    end
end

function Window.frame() return frame end
function Window.show() if frame then frame:Show() end end
function Window.hide() if frame then frame:Hide() end end
function Window.isShown() return frame ~= nil and frame:IsShown() == true end
function Window.pinsHost() return pinsHost end
