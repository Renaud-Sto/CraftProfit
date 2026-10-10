-- The pinned-recipes window: the pinned recipes with their last known prices, anywhere
-- (no auction house or profession window needed), on the native kit. Built on first open,
-- never at login. Escape closes it. Each row has an "x" that unpins it; a click elsewhere
-- on a row opens the main window on that recipe. It never searches the AH: the age line
-- says how old the prices are.
local _, ns = ...
local L = ns.L
local Native, Colors = ns.Native, ns.Colors
-- Pure layout maths (panelHeight, stack).
local Layout = ns.Layout

local PinnedWindow = {}
ns.PinnedWindow = PinnedWindow

local NAME = "CraftProfitPinnedWindow"
-- As wide as the leveling window (LevelingUI.WIDTH): the same rows and value column.
local WIDTH = 396
local ROW_H = 18
local VISIBLE = 12
local STRIP_H = Native.BUTTON_H
local AGE_H = 14
local GAP = 8
local PAD = Native.CONTENT_PAD
local CHROME_H = Native.INSET_TOP + Native.INSET_BOTTOM
local INNER_WIDTH = WIDTH - Native.INSET_LEFT - Native.INSET_RIGHT - PAD * 2
local EMPTY_WIDTH = INNER_WIDTH - Native.PANEL_EDGE * 2 - 16
-- Room for an amount with the game's coin icons, as in the leveling window.
local VALUE_W = 130
-- The unpin "x": a small button at the right end of the row, left of the scroll bar.
local UNPIN_SIZE = 16
local UNPIN_RIGHT = 2
local UNPIN_GAP = 6
-- Left of the main window, which opens at +300 from the centre.
local DEFAULT_X = -260

local ctl, handlers
local frame, content, savedPosition
local origin = { left = 0, right = 0, top = 0 }
local offset = 0
-- The widgets, exposed for tests.
local parts = { rows = {}, frames = {} }

PinnedWindow.parts = parts
PinnedWindow.WIDTH = WIDTH
PinnedWindow.INNER_WIDTH = INNER_WIDTH
PinnedWindow.VALUE_W = VALUE_W

local function name(recipe)
    return recipe.name ~= "" and recipe.name or ("#" .. recipe.recipeID)
end

-- Repaints the list from the controller; does nothing while the window is closed or not
-- built yet (evaluating the pins opens the market).
function PinnedWindow.refresh()
    if not frame or not frame:IsShown() then return end
    local data = ctl.pinsData()
    frame:setTitle(L.PINNED_TITLE)
    parts.panel:setTitle(L.PANEL_PINS)
    parts.sort:setText(data.byPoint and L.SORT_POINT or L.SORT_NET)
    parts.age:SetText(data.ageText)
    parts.ageStale = data.stale and true or false
    parts.paintAge()
    local items = data.items
    parts.empty:SetText(L.PINNED_EMPTY)
    parts.empty:SetShown(#items == 0)
    -- Clamped here: an unpin at the bottom of a scrolled list pulls the rows down.
    offset = math.max(0, math.min(offset, #items - VISIBLE))
    local currentID = ctl.currentRecipeID()
    for i = 1, VISIBLE do
        local row, item = parts.rows[i], items[offset + i]
        if item then
            local recipe = item.recipe
            row.recipeID = recipe.recipeID
            row.unpin.recipeID = recipe.recipeID
            row.name:SetText(name(recipe))
            local nc = Colors.FIXED[recipe.difficulty] or Colors.text("main")
            row.name:SetTextColor(nc[1], nc[2], nc[3], nc[4])
            local text, c = ns.PinsUI.rowValue(item, data.byPoint)
            row.value:SetText(text)
            row.value:SetTextColor(c[1], c[2], c[3], c[4])
            row.selected:SetShown(recipe.recipeID == currentID)
            row:Show()
        else
            row.recipeID, row.unpin.recipeID = nil, nil
            row:Hide()
        end
    end
    parts.bar:update(#items, VISIBLE, offset)
end

function PinnedWindow.frame() return frame end

function PinnedWindow.isShown()
    return frame ~= nil and frame:IsShown() == true
end

function PinnedWindow.hide()
    if frame then frame:Hide() end
end

local function section(key, height)
    local f = CreateFrame("Frame", nil, content)
    f:SetHeight(height)
    parts.frames[key] = f
    return f
end

local function showTip(self)
    if type(GameTooltip) ~= "table" then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L.UNPIN)
    GameTooltip:Show()
end

local function hideTip()
    if type(GameTooltip) == "table" then GameTooltip:Hide() end
end

-- The "x": a plain Button (no template, so its scripts are ours), the game's grey small
-- font lit to white on hover.
local function buildUnpin(row)
    local x = CreateFrame("Button", nil, row)
    x:SetSize(UNPIN_SIZE, UNPIN_SIZE)
    x:SetPoint("RIGHT", row, "RIGHT", -UNPIN_RIGHT, 0)
    x:SetNormalFontObject("GameFontDisableSmall")
    x:SetHighlightFontObject("GameFontHighlightSmall")
    x:SetText("x")
    Native.forwardDrag(x, frame)
    x:SetScript("OnClick", function(self)
        if self.dragged == true then return end
        if self.recipeID then ctl.unpin(self.recipeID) end
    end)
    x:SetScript("OnEnter", showTip)
    x:SetScript("OnLeave", hideTip)
    return x
end

local function buildRow(body, i)
    local row = Native.listRow(body, i, ROW_H, Native.SCROLL_W + 6)
    row.unpin = buildUnpin(row)
    row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.value:SetPoint("RIGHT", row.unpin, "LEFT", -UNPIN_GAP, 0)
    row.value:SetWidth(VALUE_W)
    row.value:SetJustifyH("RIGHT")
    row.value:SetWordWrap(false)
    -- A long name is cut before the value, which stays before the "x".
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.name:SetPoint("RIGHT", row.value, "LEFT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    -- The rows cover the window's body: a drag on them still moves the window, and the
    -- click that ends it selects nothing.
    Native.forwardDrag(row, frame)
    row:SetScript("OnClick", function(self)
        if self.dragged == true then return end
        if not self.recipeID then return end
        ctl.selectPin(self.recipeID)
        ctl.showMainWindow()
    end)
    return row
end

local function build()
    local panelH = Layout.panelHeight(VISIBLE, ROW_H)
    local offsets, total = Layout.stack({ STRIP_H, AGE_H, panelH }, GAP, PAD)

    frame = Native.window(NAME, L.PINNED_TITLE, {
        width = WIDTH,
        height = CHROME_H + PAD + total + PAD,
        onMoved = function(point, x, y)
            savedPosition = { x = x, y = y }
            if handlers.onMoved then handlers.onMoved(point, x, y) end
        end,
    })
    content = frame.content
    if content == frame then
        origin = { left = Native.INSET_LEFT, right = Native.INSET_RIGHT, top = Native.INSET_TOP }
    end
    -- Escape closes it, the game's way for a plain named frame (never UIPanelWindows).
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, NAME) end
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta)
        PinnedWindow.refresh()
    end)

    -- Strip: the sort order, as in the list under the main window, across the window.
    local strip = section("strip", STRIP_H)
    parts.sort = Native.button(strip, "", { width = INNER_WIDTH, onClick = function() ctl.toggleSort() end })
    parts.sort:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, 0)
    parts.sort:SetPoint("TOPRIGHT", strip, "TOPRIGHT", 0, 0)

    local ageRow = section("age", AGE_H)
    parts.age = ageRow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    parts.age:SetPoint("LEFT", ageRow, "LEFT", 4, 0)
    parts.ageStale = false
    parts.paintAge = function()
        local c = parts.ageStale and Colors.FIXED.stale or Colors.text("muted")
        parts.age:SetTextColor(c[1], c[2], c[3], c[4])
    end

    parts.panel = Native.panel(content, L.PANEL_PINS)
    parts.frames.panel = parts.panel.frame
    -- Fixed list height: the window keeps its size whatever the number of pins.
    parts.panel.frame:SetHeight(panelH)
    for i = 1, VISIBLE do parts.rows[i] = buildRow(parts.panel.body, i) end
    parts.bar = Native.scrollbar(parts.panel.body, VISIBLE * ROW_H)
    parts.bar.frame:SetPoint("TOPRIGHT", parts.panel.body, "TOPRIGHT", -2, 0)
    parts.bar.onScroll = function(newOffset)
        offset = newOffset
        PinnedWindow.refresh()
    end
    -- At the top of the list, where no row shows while it is displayed.
    parts.empty = parts.panel.body:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    parts.empty:SetPoint("TOP", parts.panel.body, "TOP", 0, -20)
    parts.empty:SetWidth(EMPTY_WIDTH)
    parts.empty:SetJustifyH("CENTER")
    parts.empty:SetWordWrap(true)

    for i, key in ipairs({ "strip", "age", "panel" }) do
        local f = parts.frames[key]
        f:SetPoint("TOPLEFT", content, "TOPLEFT", origin.left + PAD, offsets[i] - origin.top)
        f:SetPoint("TOPRIGHT", content, "TOPRIGHT", -origin.right - PAD, offsets[i] - origin.top)
    end
    -- Native.window returns it hidden; the caller shows it.
    frame:Hide()
end

function PinnedWindow.show()
    if not ctl then return end
    if not frame then build() end
    PinnedWindow.place()
    frame:Show()
    PinnedWindow.refresh()
end

function PinnedWindow.toggle()
    if PinnedWindow.isShown() then PinnedWindow.hide() else PinnedWindow.show() end
end

-- Builds nothing: the window is made on first open. handlers: onMoved(point, x, y).
function PinnedWindow.init(controller, h)
    ctl, handlers = controller, h or {}
end

-- Position: the saved one once the window has been dragged, else left of the middle of
-- the screen (the main window opens right of it).
function PinnedWindow.place()
    if not frame then return end
    frame:ClearAllPoints()
    if savedPosition then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", savedPosition.x, savedPosition.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", DEFAULT_X, 0)
    end
end

-- The saved position ({ x, y } or nil); applied now when the window exists, else on open.
function PinnedWindow.attach(saved)
    savedPosition = saved
    PinnedWindow.place()
end
