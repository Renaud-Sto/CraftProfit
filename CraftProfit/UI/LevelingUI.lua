-- The leveling window: the known recipes of one profession, cheapest skill point first,
-- on the native kit. A separate, movable window opened by /cp level or the Leveling
-- button; it sits beside the main window until it has been dragged.
local _, ns = ...
local L = ns.L
local Native, Colors = ns.Native, ns.Colors
-- Only the kit's pure layout maths (panelHeight, stack) until it moves out of Kit.
local Kit = ns.Kit

local LevelingUI = {}
ns.LevelingUI = LevelingUI

local WIDTH = 396
local ROW_H = 18
local VISIBLE = 12
local STRIP_H = Native.BUTTON_H
local AGE_H = 14
local CHECK_H = Native.CHECK_SIZE
local GAP = 8
local PAD = Native.CONTENT_PAD
-- The window's own chrome above and below its inset (title bar, bottom border).
local CHROME_H = Native.INSET_TOP + Native.INSET_BOTTOM
-- Width the sections get inside the native inset.
local INNER_WIDTH = WIDTH - Native.INSET_LEFT - Native.INSET_RIGHT - PAD * 2
-- The grey-recipes label starts this far from the footer's left edge (box, then the
-- template's label offset); the hidden-count text keeps HIDDEN_RIGHT px from the right.
local GREY_LABEL_X = Native.CHECK_SIZE + Native.CHECK_LABEL_X
local HIDDEN_RIGHT = 4
local HIDDEN_GAP = 8
local VALUE_W = 112
local CRAFTS_W = 36

local ctl, handlers
local frame, content, savedPosition
-- Where the sections start inside `content`: 0 inside the native inset; the inset's own
-- edges when a build has no inset and `content` is the frame itself.
local origin = { left = 0, right = 0, top = 0 }
local offset = 0
-- The widgets, exposed for tests.
local parts = { rows = {}, frames = {} }

-- The empty-list message wraps inside the panel body (inner width less the panel's
-- edges) with 8 px of air on each side.
local EMPTY_WIDTH = INNER_WIDTH - Native.PANEL_EDGE * 2 - 16

LevelingUI.parts = parts
LevelingUI.WIDTH = WIDTH
LevelingUI.INNER_WIDTH = INNER_WIDTH
LevelingUI.EMPTY_WIDTH = EMPTY_WIDTH

-- Width of a string at its natural size; 0 when it cannot be measured.
local function textWidth(fs)
    local width
    if type(fs.GetUnboundedStringWidth) == "function" then width = fs:GetUnboundedStringWidth() end
    if type(width) ~= "number" then width = fs:GetStringWidth() end
    return type(width) == "number" and width or 0
end

-- The grey-recipes label stops before the hidden count beside it: cut, never under it.
local function fitGreyLabel()
    local hiddenW = textWidth(parts.hidden)
    local room = INNER_WIDTH - GREY_LABEL_X - HIDDEN_RIGHT
    if hiddenW > 0 then room = room - hiddenW - HIDDEN_GAP end
    parts.grey:setMaxWidth(room)
end

function LevelingUI.isShown()
    return frame ~= nil and frame:IsShown() == true
end

function LevelingUI.hide()
    if frame then frame:Hide() end
end

local function name(recipe)
    return recipe.name ~= "" and recipe.name or ("#" .. recipe.recipeID)
end

function LevelingUI.refresh()
    if not frame or not frame:IsShown() then return end
    local data = ctl.levelData()
    frame:setTitle(L.LEVEL_TITLE)
    parts.panel:setTitle(L.LEVEL_PANEL)
    parts.sort:setText(data.sort == "speed" and L.SORT_SPEED or L.SORT_POINT)
    parts.grey:setText(L.LEVEL_SHOW_GREY)
    parts.grey:SetChecked(data.showGrey)
    if not data.profession then
        parts.profession:setText("-")
        parts.age:SetText("")
        parts.hidden:SetText("")
        fitGreyLabel()
        parts.empty:SetText(L.LEVEL_EMPTY)
        parts.empty:Show()
        parts.bar:update(0, VISIBLE, 0)
        for i = 1, VISIBLE do
            parts.rows[i].recipeID, parts.rows[i].recipe = nil, nil
            parts.rows[i]:Hide()
        end
        return
    end
    parts.profession:setText(data.profession.name)
    parts.age:SetText(data.ageText)
    parts.ageStale = data.stale and true or false
    parts.paintAge()
    parts.hidden:SetText(data.hiddenGrey > 0 and string.format(L.LEVEL_HIDDEN, data.hiddenGrey) or "")
    fitGreyLabel()
    local items = data.items
    parts.empty:SetText(L.LEVEL_NONE)
    parts.empty:SetShown(#items == 0)
    offset = math.max(0, math.min(offset, #items - VISIBLE))
    local currentID = ctl.currentRecipeID()
    for i = 1, VISIBLE do
        local row, item = parts.rows[i], items[offset + i]
        if item then
            local recipe = item.recipe
            row.recipeID, row.recipe = recipe.recipeID, recipe
            row.name:SetText(name(recipe))
            local c = Colors.FIXED[recipe.difficulty] or Colors.text("main")
            row.name:SetTextColor(c[1], c[2], c[3], c[4])
            local perPoint = item.result.perPoint
            row.crafts:SetText(ns.Present.craftsPerPoint(perPoint and perPoint.chance) or "")
            local text, tone = ns.Present.pointRow(L, ctl.fmt, perPoint)
            row.value:SetText(text)
            local tc = tone == "profit" and Colors.FIXED.profit or tone == "loss" and Colors.FIXED.loss
                or Colors.text("muted")
            row.value:SetTextColor(tc[1], tc[2], tc[3], tc[4])
            row.selected:SetShown(recipe.recipeID == currentID)
            row:Show()
        else
            row.recipeID, row.recipe = nil, nil
            row:Hide()
        end
    end
    parts.bar:update(#items, VISIBLE, offset)
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

local function section(key, height)
    local f = CreateFrame("Frame", nil, content)
    f:SetHeight(height)
    parts.frames[key] = f
    return f
end

local function buildRow(body, i)
    local row = Native.listRow(body, i, ROW_H, Native.SCROLL_W + 6)
    row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.value:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.value:SetWidth(VALUE_W)
    row.value:SetJustifyH("RIGHT")
    row.value:SetWordWrap(false)
    -- Crafts per point: a column of its own so the cost reads as loss x crafts.
    row.crafts = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.crafts:SetPoint("RIGHT", row, "RIGHT", -(8 + VALUE_W + 8), 0)
    row.crafts:SetWidth(CRAFTS_W)
    row.crafts:SetJustifyH("RIGHT")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.name:SetPoint("RIGHT", row.crafts, "LEFT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    -- The rows cover the window's body: a drag on them still moves the window, and the
    -- click that ends it selects nothing.
    Native.forwardDrag(row, frame)
    row:SetScript("OnClick", function(self)
        if self.dragged == true then return end
        if self.recipe then ctl.selectKnown(self.recipe) end
    end)
    return row
end

function LevelingUI.init(controller, h)
    if frame then return frame end
    ctl, handlers = controller, h or {}
    local panelH = Kit.panelHeight(VISIBLE, ROW_H)
    local heights = { STRIP_H, AGE_H, panelH, CHECK_H }
    local offsets, total = Kit.stack(heights, GAP, PAD)

    -- Escape does not close it (not in UISpecialFrames), as before.
    frame = Native.window("CraftProfitLevelWindow", L.LEVEL_TITLE, {
        width = WIDTH,
        height = CHROME_H + PAD + total + PAD,
        onMoved = function(point, x, y)
            if handlers.onMoved then handlers.onMoved(point, x, y) end
        end,
    })
    content = frame.content
    if content == frame then
        origin = { left = Native.INSET_LEFT, right = Native.INSET_RIGHT, top = Native.INSET_TOP }
    end
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta)
        LevelingUI.refresh()
    end)

    -- Strip: the profession (click to cycle) and the sort order.
    local strip = section("strip", STRIP_H)
    parts.profession = Native.button(strip, "", { width = 150, onClick = function() ctl.nextLevelProfession() end })
    parts.profession:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, 0)
    parts.sort = Native.button(strip, "", { width = 160, onClick = function() ctl.toggleLevelSort() end })
    parts.sort:SetPoint("TOPRIGHT", strip, "TOPRIGHT", 0, 0)

    local ageRow = section("age", AGE_H)
    parts.age = ageRow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    parts.age:SetPoint("LEFT", ageRow, "LEFT", 4, 0)
    parts.ageStale = false
    parts.paintAge = function()
        local c = parts.ageStale and Colors.FIXED.stale or Colors.text("muted")
        parts.age:SetTextColor(c[1], c[2], c[3], c[4])
    end

    parts.panel = Native.panel(content, L.LEVEL_PANEL)
    parts.frames.panel = parts.panel.frame
    -- Fixed list height: the window keeps its size whatever the number of recipes.
    parts.panel.frame:SetHeight(panelH)
    for i = 1, VISIBLE do parts.rows[i] = buildRow(parts.panel.body, i) end
    parts.bar = Native.scrollbar(parts.panel.body, VISIBLE * ROW_H)
    parts.bar.frame:SetPoint("TOPRIGHT", parts.panel.body, "TOPRIGHT", -2, 0)
    parts.bar.onScroll = function(newOffset)
        offset = newOffset
        LevelingUI.refresh()
    end
    -- At the top of the list, where no row shows while it is displayed.
    parts.empty = parts.panel.body:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    parts.empty:SetPoint("TOP", parts.panel.body, "TOP", 0, -20)
    parts.empty:SetWidth(EMPTY_WIDTH)
    parts.empty:SetJustifyH("CENTER")
    parts.empty:SetWordWrap(true)

    local footer = section("footer", CHECK_H)
    parts.grey = Native.check(footer, "", function(checked) ctl.setLevelShowGrey(checked and true or false) end,
        INNER_WIDTH - GREY_LABEL_X - HIDDEN_RIGHT)
    parts.grey:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
    parts.hidden = footer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    parts.hidden:SetPoint("RIGHT", footer, "RIGHT", -HIDDEN_RIGHT, 0)
    parts.hidden:SetJustifyH("RIGHT")
    parts.hidden:SetWordWrap(false)

    local order = { "strip", "age", "panel", "footer" }
    for i, key in ipairs(order) do
        local f = parts.frames[key]
        f:SetPoint("TOPLEFT", content, "TOPLEFT", origin.left + PAD, offsets[i] - origin.top)
        f:SetPoint("TOPRIGHT", content, "TOPRIGHT", -origin.right - PAD, offsets[i] - origin.top)
    end
    LevelingUI.attach(nil)
    -- Native.window returns it hidden; kept explicit: the controller decides when it shows.
    frame:Hide()
    return frame
end

-- Position: the saved one once the window has been dragged; otherwise right beside the
-- main window when it is on screen, else the middle of the screen.
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
