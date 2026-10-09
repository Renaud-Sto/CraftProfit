-- The leveling window: the known recipes of one profession, cheapest skill point
-- first. A separate, movable window opened by /cp level or the Leveling button.
local _, ns = ...
local L = ns.L

local LevelingUI = {}
ns.LevelingUI = LevelingUI

local WIDTH = 380
local PAD = 10
local ROW_H = 18
local VISIBLE = 12
local TOP = 92

local COLORS = {
    profit = { 0.35, 0.90, 0.45 },
    loss = { 1.00, 0.40, 0.35 },
    muted = { 0.65, 0.65, 0.70 },
    optimal = { 1.00, 0.50, 0.25 },
    medium = { 1.00, 0.82, 0.00 },
    easy = { 0.25, 0.75, 0.25 },
    trivial = { 0.55, 0.55, 0.55 },
    normal = { 0.90, 0.90, 0.90 },
}

local ctl, handlers
local frame, titleText, professionButton, sortButton, ageText, greyCheck, greyLabel, hiddenText, emptyText
local rows = {}
local offset = 0

local function newText(parent, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    fs:SetWordWrap(false)
    return fs
end

function LevelingUI.isShown()
    return frame ~= nil and frame:IsShown() == true
end

function LevelingUI.hide()
    if frame then frame:Hide() end
end

function LevelingUI.refresh()
    if not frame or not frame:IsShown() then return end
    local data = ctl.levelData()
    titleText:SetText(L.LEVEL_TITLE)
    greyLabel:SetText(L.LEVEL_SHOW_GREY)
    sortButton:SetText(data.sort == "speed" and L.SORT_SPEED or L.SORT_POINT)
    greyCheck:SetChecked(data.showGrey)
    if not data.profession then
        professionButton:SetText("-")
        ageText:SetText("")
        hiddenText:SetText("")
        emptyText:SetText(L.LEVEL_EMPTY)
        emptyText:Show()
        for i = 1, VISIBLE do rows[i].recipeID = nil; rows[i]:Hide() end
        return
    end
    professionButton:SetText(data.profession.name)
    ageText:SetText(data.ageText)
    ageText:SetTextColor(unpack(data.stale and { 1.00, 0.60, 0.25 } or COLORS.muted))
    hiddenText:SetText(data.hiddenGrey > 0 and string.format(L.LEVEL_HIDDEN, data.hiddenGrey) or "")
    local items = data.items
    emptyText:SetText(L.LEVEL_NONE)
    emptyText:SetShown(#items == 0)
    offset = math.max(0, math.min(offset, #items - VISIBLE))
    for i = 1, VISIBLE do
        local row, item = rows[i], items[offset + i]
        if item then
            local recipe = item.recipe
            row.recipeID = recipe.recipeID
            row.recipe = recipe
            row.name:SetText(recipe.name ~= "" and recipe.name or ("#" .. recipe.recipeID))
            local c = COLORS[recipe.difficulty or "normal"] or COLORS.normal
            row.name:SetTextColor(c[1], c[2], c[3])
            row.crafts:SetText(ns.Present.craftsPerPoint(item.result.perPoint and item.result.perPoint.chance) or "")
            local text, tone = ns.Present.pointRow(L, ctl.fmt, item.result.perPoint)
            row.value:SetText(text)
            local tc = COLORS[tone] or COLORS.normal
            row.value:SetTextColor(tc[1], tc[2], tc[3])
            row.selected:SetShown(recipe.recipeID == ctl.currentRecipeID())
            row:Show()
        else
            row.recipeID, row.recipe = nil, nil
            row:Hide()
        end
    end
end

function LevelingUI.frame() return frame end

function LevelingUI.show()
    if not frame then return end
    LevelingUI.place()
    frame:Show()
    LevelingUI.refresh()
end

function LevelingUI.toggle()
    if LevelingUI.isShown() then LevelingUI.hide() else LevelingUI.show() end
end

function LevelingUI.init(controller, h)
    if frame then return frame end
    ctl, handlers = controller, h or {}
    frame = CreateFrame("Frame", "CraftProfitLevelWindow", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, TOP + VISIBLE * ROW_H + 30)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
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
        local left, top = self:GetLeft(), self:GetTop()
        if left and top then
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            if handlers.onMoved then handlers.onMoved("TOPLEFT", left, top) end
        end
    end)
    frame:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta)
        LevelingUI.refresh()
    end)
    frame:Hide()

    titleText = newText(frame, "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -10)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)

    -- Cycles through the professions stored for this character.
    professionButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    professionButton:SetSize(120, 20)
    professionButton:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -34)
    professionButton:SetScript("OnClick", function() ctl.nextLevelProfession() end)

    sortButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    sortButton:SetSize(130, 20)
    sortButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD - 18, -34)
    sortButton:SetScript("OnClick", function() ctl.toggleLevelSort() end)

    ageText = newText(frame, "GameFontDisableSmall")
    ageText:SetPoint("LEFT", professionButton, "RIGHT", 8, 0)

    greyCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    greyCheck:SetSize(22, 22)
    greyCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD - 4, -60)
    greyCheck:SetScript("OnClick", function(self) ctl.setLevelShowGrey(self:GetChecked() and true or false) end)
    greyLabel = newText(frame, "GameFontHighlightSmall")
    greyLabel:SetPoint("LEFT", greyCheck, "RIGHT", 2, 0)
    hiddenText = newText(frame, "GameFontDisableSmall")
    hiddenText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -66)
    hiddenText:SetJustifyH("RIGHT")

    emptyText = newText(frame, "GameFontDisable")
    emptyText:SetPoint("TOP", frame, "TOP", 0, -TOP - 20)

    for i = 1, VISIBLE do
        local row = CreateFrame("Button", nil, frame)
        row:SetSize(WIDTH - PAD * 2, ROW_H)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(TOP + (i - 1) * ROW_H))
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.selected = row:CreateTexture(nil, "BACKGROUND")
        row.selected:SetAllPoints()
        row.selected:SetColorTexture(1, 1, 1, 0.08)
        row.name = newText(row, "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.name:SetWidth(WIDTH - PAD * 2 - 170)
        row.name:SetJustifyH("LEFT")
        -- Crafts per point, a column of its own so the cost reads as loss x crafts.
        row.crafts = newText(row, "GameFontDisableSmall")
        row.crafts:SetPoint("RIGHT", row, "RIGHT", -112, 0)
        row.crafts:SetJustifyH("RIGHT")
        row.value = newText(row, "GameFontHighlightSmall")
        row.value:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.value:SetJustifyH("RIGHT")
        row:SetScript("OnClick", function(self)
            if self.recipe then ctl.selectKnown(self.recipe) end
        end)
        rows[i] = row
    end
    LevelingUI.attach(nil)
    return frame
end

local savedPosition

-- Position: the saved one once the window has been dragged; otherwise right beside the
-- main window when it is on screen (they used to overlap), else the middle of the screen.
function LevelingUI.place()
    if not frame then return end
    frame:ClearAllPoints()
    local main = ns.Window.frame()
    if savedPosition then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", savedPosition.x, savedPosition.y)
    elseif main and ns.Window.isShown() then
        frame:SetPoint("TOPLEFT", main, "TOPRIGHT", 6, 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", -200, 0)
    end
end

function LevelingUI.attach(saved)
    savedPosition = saved
    LevelingUI.place()
end
