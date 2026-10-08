-- The small floating window. Parented to UIParent (never to a Blizzard frame, to
-- avoid taint); anchored beside the profession or AH window until the user
-- drags it, after which the saved position wins.
local _, ns = ...
local L = ns.L

local Window = {}
ns.Window = Window

local WIDTH = 270
local PAD = 10
local ROW_H = 16
local HEADER_H = 26
local MAX_LINES = 6
local MAX_DETAIL = 12 -- Recipes.MAX_REAGENTS

local COLORS = {
    profit = { 0.35, 0.90, 0.45 },
    loss = { 1.00, 0.40, 0.35 },
    incomplete = { 1.00, 0.82, 0.25 },
    none = { 0.70, 0.70, 0.70 },
    normal = { 0.90, 0.90, 0.90 },
    best = { 0.35, 0.90, 0.45 },
    muted = { 0.65, 0.65, 0.70 },
    stale = { 1.00, 0.60, 0.25 },
}

local frame, titleText, emptyText, verdictText, verdictValue, ageText
local perPointCheck, perPointLabel, pinButton, pinsHost, costHit
local detailRows = {}
local costLines = {}
local expanded = true
local lineRows = {}
local handlers = {}
local contentHeight = 80

Window.lastModel = nil
Window.lastHandlers = nil

local function color(fontString, rgb)
    fontString:SetTextColor(rgb[1], rgb[2], rgb[3])
end

local function newText(parent, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    fs:SetWordWrap(false)
    return fs
end

local function place(region, point, x, y)
    region:ClearAllPoints()
    region:SetPoint(point, frame, point, x, y)
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

function Window.create(h)
    if frame then return frame end
    handlers = h or {}
    Window.lastHandlers = handlers

    frame = CreateFrame("Frame", "CraftProfitWindow", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, 100)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
    frame:SetBackdropBorderColor(0.40, 0.40, 0.50, 1)
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Re-anchor to the screen's bottom-left corner so saved offsets are absolute.
        local left, top = self:GetLeft(), self:GetTop()
        if left and top then
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            if handlers.onMoved then handlers.onMoved("TOPLEFT", left, top) end
        end
    end)

    titleText = newText(frame, "GameFontNormal")
    place(titleText, "TOPLEFT", PAD, -8)
    titleText:SetWidth(230)
    titleText:SetJustifyH("LEFT")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)

    emptyText = newText(frame, "GameFontDisable")
    emptyText:SetPoint("TOP", frame, "TOP", 0, -HEADER_H - 8)

    for i = 1, MAX_LINES do
        local label = newText(frame, "GameFontHighlightSmall")
        label:SetWidth(150)
        label:SetJustifyH("LEFT")
        local value = newText(frame, "GameFontHighlightSmall")
        value:SetJustifyH("RIGHT")
        lineRows[i] = { label = label, value = value }
    end

    -- Click area over the Materials line: folds the reagent detail in and out.
    costHit = CreateFrame("Button", nil, frame)
    costHit:SetScript("OnClick", function()
        if handlers.onCostToggle then handlers.onCostToggle(not expanded) end
    end)
    for i = 1, MAX_DETAIL do
        local label = newText(frame, "GameFontDisableSmall")
        label:SetWidth(170)
        label:SetJustifyH("LEFT")
        local value = newText(frame, "GameFontDisableSmall")
        value:SetJustifyH("RIGHT")
        detailRows[i] = { label = label, value = value }
    end

    verdictText = newText(frame, "GameFontNormal")
    verdictText:SetWidth(WIDTH - PAD * 2)
    verdictText:SetWordWrap(true)
    verdictText:SetJustifyH("LEFT")
    verdictValue = newText(frame, "GameFontNormal")
    verdictValue:SetJustifyH("RIGHT")
    ageText = newText(frame, "GameFontDisableSmall")
    ageText:SetJustifyH("LEFT")

    perPointCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    perPointCheck:SetSize(22, 22)
    perPointCheck:SetScript("OnClick", function(self)
        if handlers.onPerPointToggle then handlers.onPerPointToggle(self:GetChecked() and true or false) end
    end)
    perPointLabel = newText(frame, "GameFontHighlightSmall")

    pinButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    pinButton:SetSize(86, 20)
    pinButton:SetScript("OnClick", function()
        if handlers.onPinClick then handlers.onPinClick() end
    end)

    pinsHost = CreateFrame("Frame", nil, frame)
    pinsHost:SetWidth(WIDTH)
    pinsHost:SetHeight(0)
    pinsHost:Hide()

    frame:Hide()
    return frame
end

-- Frame height = recipe section + pinned-recipes section (when shown).
function Window.relayout()
    if not frame then return end
    pinsHost:ClearAllPoints()
    pinsHost:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -contentHeight)
    local extra = pinsHost:IsShown() and pinsHost:GetHeight() or 0
    frame:SetHeight(contentHeight + extra)
end

local function hideLines()
    for i = 1, MAX_LINES do
        lineRows[i].label:Hide()
        lineRows[i].value:Hide()
    end
    costHit:Hide()
    for i = 1, MAX_DETAIL do
        detailRows[i].label:Hide()
        detailRows[i].value:Hide()
    end
    verdictText:Hide()
    verdictValue:Hide()
    ageText:Hide()
    perPointCheck:Hide()
    perPointLabel:Hide()
    pinButton:Hide()
end

function Window.showEmpty(text)
    if not frame then return end
    Window.lastModel = nil
    titleText:SetText(L.TITLE)
    hideLines()
    emptyText:SetText(text)
    emptyText:Show()
    contentHeight = HEADER_H + 34
    Window.relayout()
end

-- Reagent rows under the Materials line; returns the y below them.
local function placeDetails(y)
    for i = 1, MAX_DETAIL do
        local row, cost = detailRows[i], expanded and costLines[i] or nil
        if cost then
            row.label:SetText(cost.qty .. "x " .. reagentName(cost.itemID))
            row.value:SetText(cost.subtotalText)
            row.label:ClearAllPoints()
            row.label:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + 12, -y)
            row.value:ClearAllPoints()
            row.value:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -y)
            row.label:Show()
            row.value:Show()
            y = y + ROW_H - 2
        else
            row.label:Hide()
            row.value:Hide()
        end
    end
    return y
end

function Window.render(model)
    if not frame then return end
    Window.lastModel = model
    costLines = model.costLines or {}
    expanded = model.costExpanded ~= false
    titleText:SetText(model.title or L.TITLE)
    emptyText:Hide()

    local y = HEADER_H
    for i = 1, MAX_LINES do
        local row, line = lineRows[i], model.lines[i]
        if line then
            row.label:SetText(line.label)
            row.value:SetText(line.value)
            color(row.label, line.best and COLORS.best or COLORS.normal)
            color(row.value, line.best and COLORS.best or COLORS.normal)
            place(row.label, "TOPLEFT", PAD, -y)
            place(row.value, "TOPRIGHT", -PAD, -y)
            row.label:Show()
            row.value:Show()
            if line.key == "cost" then
                -- "-" folded in, "+" folded out: plain characters every font has.
                row.label:SetText((expanded and "- " or "+ ") .. line.label)
                costHit:ClearAllPoints()
                costHit:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
                costHit:SetSize(WIDTH - PAD * 2, ROW_H)
                costHit:Show()
            end
            y = y + ROW_H
            if line.key == "cost" then y = placeDetails(y) end
        else
            row.label:Hide()
            row.value:Hide()
        end
    end

    y = y + 6
    local verdictColor = COLORS[model.verdict.kind == "profit" and "profit"
        or model.verdict.kind == "loss" and "loss"
        or model.verdict.kind == "incomplete" and "incomplete" or "none"]
    verdictText:SetText(model.verdict.text)
    verdictValue:SetText(model.verdict.value)
    color(verdictText, verdictColor)
    color(verdictValue, verdictColor)
    place(verdictText, "TOPLEFT", PAD, -y)
    verdictText:Show()
    -- The qualifier can wrap onto several lines; the value sits on its own row below.
    y = y + math.max(ROW_H, verdictText:GetStringHeight() or ROW_H)
    place(verdictValue, "TOPRIGHT", -PAD, -y)
    verdictValue:Show()
    y = y + ROW_H + 4

    ageText:SetText(model.ageText)
    color(ageText, model.stale and COLORS.stale or COLORS.muted)
    place(ageText, "TOPLEFT", PAD, -y)
    ageText:Show()
    y = y + ROW_H + 2

    perPointCheck:SetChecked(model.showPerPoint)
    perPointLabel:SetText(L.OPT_PER_POINT)
    perPointCheck:ClearAllPoints()
    perPointCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD - 4, -y)
    perPointLabel:ClearAllPoints()
    perPointLabel:SetPoint("LEFT", perPointCheck, "RIGHT", 2, 0)
    perPointLabel:SetWidth(WIDTH - PAD * 2 - 24 - 90)
    perPointCheck:Show()
    perPointLabel:Show()

    pinButton:SetText(model.pinned and L.UNPIN or L.PIN)
    pinButton:ClearAllPoints()
    pinButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -y - 1)
    pinButton:Show()

    contentHeight = y + 28
    Window.relayout()
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

function Window.show() if frame then frame:Show() end end
function Window.hide() if frame then frame:Hide() end end
function Window.isShown() return frame ~= nil and frame:IsShown() == true end
function Window.pinsHost() return pinsHost end
