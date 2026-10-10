-- The main window, built on the native kit (UI/Native.lua): a game panel with a result
-- banner, three tiles for the ways to sell the item, a Materials panel and an Options
-- panel inside its dark inset; at the auction house the pinned list (UI/PinsUI.lua, still
-- on the old Kit) hangs below. Parented to UIParent (never to a Blizzard frame, to avoid
-- taint); anchored beside the profession or AH window until the user drags it, after
-- which the saved position wins. Colours are meaning colours (ns.Colors) or the game's
-- own text colours: no colour theme applies to this window.
local _, ns = ...
local L = ns.L
local Kit, Native, Colors = ns.Kit, ns.Native, ns.Colors

local Window = {}
ns.Window = Window

local WIDTH = 372
local GAP = 8
local ROW_H = 18
local BANNER_H = 52
local TILE_H = 52
local LIKELY_H = 16
local AGE_H = 14
local OPTION_ROWS = 3
-- The tallest native widget of an option row (the 24 px check box; the button and the
-- input are 22) plus 2 px, so two rows never touch. The options body is exactly
-- OPTION_ROWS of these.
local OPTION_ROW_H = math.max(Native.CHECK_SIZE, Native.BUTTON_H, Native.INPUT_H) + 2
local TRACK_X = 160
local EMPTY_H = 24
local MAX_DETAIL = 12 -- Recipes.MAX_REAGENTS
-- A folded native panel: its header strip, 2 px inside the inset border at the top and
-- at the bottom (Native.panel's edge).
local FOLDED_H = Native.HEAD_H + 2 * 2
local PAD = Native.CONTENT_PAD
-- The window's own chrome above and below its inset (title bar, bottom border).
local CHROME_H = Native.INSET_TOP + Native.INSET_BOTTOM

local frame, content, pinsHost
local handlers = {}
local expanded = true
local contentHeight = 80
-- The widgets, exposed for tests: `frames` maps a section key to its frame.
local parts = { frames = {}, tiles = {}, rows = {} }

Window.WIDTH = WIDTH
Window.GAP = GAP
Window.FOLDED_H = FOLDED_H
Window.INNER_WIDTH = WIDTH - Native.INSET_LEFT - Native.INSET_RIGHT - PAD * 2
Window.parts = parts
Window.lastModel = nil
Window.lastHandlers = nil

-- Height of a panel with `rows` rows of `rowH`: Native's when it has its own helper,
-- else the Kit's pure one (same geometry: edge, header, body pad, rows, edge).
local function panelHeight(rows, rowH)
    if type(Native.panelHeight) == "function" then return Native.panelHeight(rows, rowH) end
    return Kit.panelHeight(rows, rowH)
end

-- Blocks of the recipe view, top to bottom, with their heights. Pure.
-- opts: hasLikely (a "likely outcome" line), expanded (Materials unfolded), reagents.
function Window.sections(opts)
    local list = { { key = "banner", height = BANNER_H }, { key = "tiles", height = TILE_H } }
    if opts.hasLikely then list[#list + 1] = { key = "likely", height = LIKELY_H } end
    list[#list + 1] = {
        key = "materials",
        height = opts.expanded and panelHeight(opts.reagents, ROW_H) or FOLDED_H,
    }
    list[#list + 1] = { key = "age", height = AGE_H }
    list[#list + 1] = { key = "options", height = panelHeight(OPTION_ROWS, OPTION_ROW_H) }
    return list
end

local function heightsOf(list)
    local heights = {}
    for i, section in ipairs(list) do heights[i] = section.height end
    return heights
end

-- Height of the window's inset needed for these sections (without the pinned list): the
-- stacked sections and the content margin above and below them.
function Window.contentHeightOf(list)
    local _, total = Kit.stack(heightsOf(list), GAP, 0)
    return total + PAD * 2
end

local function paint(fontString, c)
    fontString:SetTextColor(c[1], c[2], c[3], c[4])
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
-- follows the kind of result (gain, loss, incomplete), never an appearance choice.
-- Given the content width, so it can measure its text before it is laid out.
local function buildBanner()
    local banner = Native.banner(content, BANNER_H, Window.INNER_WIDTH)
    parts.frames.banner = banner.frame
    parts.banner = banner
end

local function buildTiles()
    local f = newSection("tiles", TILE_H)
    local width = math.floor((Window.INNER_WIDTH - GAP * 2) / 3)
    local x = 0
    for i = 1, 3 do
        -- The last tile takes the remainder, so the row fills the content width.
        local w = i < 3 and width or Window.INNER_WIDTH - x
        local tile = Native.tile(f, w, TILE_H)
        tile.frame:SetPoint("TOPLEFT", f, "TOPLEFT", x, 0)
        parts.tiles[i] = tile
        x = x + w + GAP
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
    paint(text, Colors.text("muted"))
    parts.likely = text
end

-- Materials: the header folds the detail; each row searches its reagent at the AH.
-- Rows and header are buttons covering the window's body: they forward drags to it, and
-- the click that ends a drag does nothing.
local function buildMaterials()
    local panel = Native.panel(content, "")
    parts.frames.materials = panel.frame
    parts.materials = panel
    local header = panel:onHeaderClick(function(self)
        if self and self.dragged == true then return end
        if handlers.onCostToggle then handlers.onCostToggle(not expanded) end
    end)
    Native.forwardDrag(header, frame)
    local main, muted = Colors.text("main"), Colors.text("muted")
    for i = 1, MAX_DETAIL do
        -- A reagent row is never selected: its selected tint stays hidden.
        local hit = Native.listRow(panel.body, i, ROW_H, 0)
        local name = hit:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        name:SetPoint("LEFT", hit, "LEFT", 8, 0)
        name:SetPoint("RIGHT", hit, "RIGHT", -80, 0)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        paint(name, main)
        local value = hit:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        value:SetPoint("RIGHT", hit, "RIGHT", -8, 0)
        value:SetJustifyH("RIGHT")
        paint(value, muted)
        local row = { hit = hit, name = name, value = value }
        hit:SetScript("OnClick", function()
            if hit.dragged == true then return end
            if row.itemID and handlers.onReagentClick then handlers.onReagentClick(row.itemID, row.qty) end
        end)
        Native.forwardDrag(hit, frame)
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
        paint(text, parts.ageStale and Colors.FIXED.stale or Colors.text("muted"))
    end
    parts.paintAge()
end

-- Top offset that centres a widget of `height` in option row `row` (1-based).
local function rowY(row, height)
    return -((row - 1) * OPTION_ROW_H + math.floor((OPTION_ROW_H - height) / 2))
end

-- Options: the crafts multiplier, history tracking, the cost-per-point option and the
-- pin button, one row each but the first, which also holds the track box.
local function buildOptions()
    local panel = Native.panel(content, L.PANEL_OPTIONS)
    parts.frames.options = panel.frame
    parts.options = panel
    local body = panel.body

    parts.craftsLabel = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    parts.craftsLabel:SetPoint("LEFT", body, "TOPLEFT", 8, -OPTION_ROW_H / 2)
    paint(parts.craftsLabel, Colors.text("main"))
    -- x = 70 leaves the 5 px the input's border art draws left of its frame.
    local box = Native.input(body, 52, 4)
    box:SetNumeric(true)
    box:SetPoint("TOPLEFT", body, "TOPLEFT", 70, rowY(1, Native.INPUT_H))
    -- Applied when the box loses focus (Enter, Escape or a click elsewhere). Hooked: the
    -- template clears its highlight on focus loss.
    box:HookScript("OnEditFocusLost", function(self)
        if handlers.onCraftsChange then handlers.onCraftsChange(self:GetText()) end
    end)
    parts.craftsBox = box

    -- The track label is cut before the body's right margin (a long translation).
    local bodyWidth = Window.INNER_WIDTH - 2 * 2
    local trackRoom = bodyWidth - TRACK_X - Native.CHECK_SIZE - 8
    local track = Native.check(body, "", function(checked)
        if handlers.onTrackToggle then handlers.onTrackToggle(checked) end
    end, trackRoom)
    track:SetPoint("TOPLEFT", body, "TOPLEFT", TRACK_X, rowY(1, Native.CHECK_SIZE))
    parts.track = track

    local perPoint = Native.check(body, "", function(checked)
        if handlers.onPerPointToggle then handlers.onPerPointToggle(checked) end
    end)
    perPoint:SetPoint("TOPLEFT", body, "TOPLEFT", 8, rowY(2, Native.CHECK_SIZE))
    parts.perPoint = perPoint
    parts.perPointValue = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    parts.perPointValue:SetPoint("RIGHT", body, "TOPRIGHT", -8, -OPTION_ROW_H * 1.5)
    parts.perPointValue:SetJustifyH("RIGHT")
    -- The value wins: a long (translated) label is cut short before it runs under it.
    perPoint.label:SetPoint("RIGHT", parts.perPointValue, "LEFT", -8, 0)
    perPoint.label:SetWordWrap(false)
    perPoint.label:SetJustifyH("LEFT")
    parts.perPointTone = nil
    -- A gain or a cost keeps its meaning colour; a neutral value is the game's white.
    parts.paintPerPoint = function()
        local tone = parts.perPointTone
        local c = tone == "profit" and Colors.FIXED.profit or tone == "loss" and Colors.FIXED.loss
            or Colors.text("main")
        paint(parts.perPointValue, c)
    end

    local pin = Native.button(body, "", {
        width = 120,
        onClick = function()
            if handlers.onPinClick then handlers.onPinClick() end
        end,
    })
    pin:SetPoint("TOPLEFT", body, "TOPLEFT", 8, rowY(3, Native.BUTTON_H))
    parts.pin = pin
end

-- The AH tile and the title search the crafted item; the handler is looked up when
-- clicked.
local function searchOutput()
    if handlers.onOutputClick then handlers.onOutputClick() end
end

-- The magnifiers on the AH tile and the title: only while the AH is open and a recipe
-- is displayed.
local function showSearchIcons(show)
    parts.tiles[1]:showIcon(show)
    if frame.showTitleIcon then frame:showTitleIcon(show) end
end

function Window.create(h)
    if frame then return frame end
    handlers = h or {}
    Window.lastHandlers = handlers

    frame = Native.window("CraftProfitWindow", L.TITLE, {
        width = WIDTH,
        onMoved = function(point, x, y)
            if handlers.onMoved then handlers.onMoved(point, x, y) end
        end,
        onTitleClick = searchOutput,
    })
    content = frame.content
    buildBanner()
    buildTiles()
    parts.tiles[1]:onClick(searchOutput)
    Native.forwardDrag(parts.tiles[1].hit, frame)
    buildLikely()
    buildMaterials()
    buildAge()
    buildOptions()

    parts.empty = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    parts.empty:SetPoint("TOP", content, "TOP", 0, -PAD - 6)
    paint(parts.empty, Colors.text("muted"))

    pinsHost = CreateFrame("Frame", nil, frame)
    pinsHost:SetWidth(Window.INNER_WIDTH)
    pinsHost:SetHeight(0)
    pinsHost:Hide()

    -- A new frame starts shown: the controller decides when the window appears.
    frame:Hide()
    return frame
end

function Window.setTitle(text)
    if frame then frame:setTitle(text) end
end

-- Frame height = title bar + recipe sections (with the content margin) + bottom border,
-- plus a gap and the pinned-recipes section when shown. The host sits inside the inset,
-- at the content margin, a gap below the last section; the inset grows with the frame.
function Window.relayout()
    if not frame then return end
    pinsHost:ClearAllPoints()
    pinsHost:SetPoint("TOPLEFT", frame, "TOPLEFT", Native.INSET_LEFT + PAD,
        -(Native.INSET_TOP + contentHeight - PAD + GAP))
    local extra = pinsHost:IsShown() and (GAP + pinsHost:GetHeight()) or 0
    frame:SetHeight(CHROME_H + contentHeight + extra)
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
    showSearchIcons(false)
    contentHeight = PAD + EMPTY_H + PAD
    Window.relayout()
end

-- Stacks the sections of `list` under each other, inside the content margin, and sizes
-- the frame.
local function layout(list)
    hideSections()
    local offsets = Kit.stack(heightsOf(list), GAP, PAD)
    for i, section in ipairs(list) do
        local f = parts.frames[section.key]
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, offsets[i])
        f:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, offsets[i])
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

    parts.banner:set(model.banner or { kind = "none", text = "", value = "" })
    for i, tile in ipairs(parts.tiles) do tile:set((model.tiles or {})[i] or {}) end
    showSearchIcons(ns.AH ~= nil and ns.AH.isOpen == true)

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
