-- The shopping list window: every material of the planned crafts with how many the bags
-- hold, how many are needed and what the missing ones cost (Shopping.rows), the total to
-- pay, a "x" per row and a "Clear list" button. A click on a row searches the missing
-- quantity at the auction house (the main window's reagent click). Built on first open,
-- never at login; Escape closes it. Opens over the main window until it is dragged.
local _, ns = ...
local L = ns.L
local Native, Colors = ns.Native, ns.Colors
local Layout = ns.Layout

local ShoppingWindow = {}
ns.ShoppingWindow = ShoppingWindow

local NAME = "CraftProfitShoppingWindow"
local WIDTH = 396
local ROW_H = 18
local VISIBLE = 12
local LABELS_H = 14
local TOTAL_H = 16
local STRIP_H = Native.BUTTON_H
local GAP = 8
local PAD = Native.CONTENT_PAD
local CHROME_H = Native.INSET_TOP + Native.INSET_BOTTOM
local INNER_WIDTH = WIDTH - Native.INSET_LEFT - Native.INSET_RIGHT - PAD * 2
local EMPTY_WIDTH = INNER_WIDTH - Native.PANEL_EDGE * 2 - 16
-- Columns from the right of a row: the "x", the cost, the needed and in-bags counts.
local X_SIZE = 16
local X_RIGHT = 2
local COST_W = 104
local COUNT_W = 46
local COL_GAP = 6
-- The column labels sit over the row columns: the panel's edge plus the scroll bar room.
local ROW_RIGHT = Native.SCROLL_W + 6

local ctl, handlers
local frame, content, savedPosition
local origin = { left = 0, right = 0, top = 0 }
local offset = 0
local parts = { rows = {}, frames = {} }
local lastData = { rows = {} }

ShoppingWindow.parts = parts
ShoppingWindow.WIDTH = WIDTH
ShoppingWindow.VISIBLE = VISIBLE

local function paint(fs, c)
    fs:SetTextColor(c[1], c[2], c[3], c[4])
end

local function paintRows()
    local rows = lastData.rows
    offset = math.max(0, math.min(offset, #rows - VISIBLE))
    local main, muted = Colors.text("main"), Colors.text("muted")
    for i = 1, VISIBLE do
        local row, data = parts.rows[i], rows[offset + i]
        if data then
            row.itemID, row.remove.itemID = data.itemID, data.itemID
            row.qty = data.buy > 0 and data.buy or data.need
            row.name:SetText(data.nameText)
            row.have:SetText(data.haveText)
            row.need:SetText(data.needText)
            row.cost:SetText(data.costText)
            -- Gathered: the whole row greys out. Still to buy: white, the bag count grey.
            paint(row.name, data.done and muted or main)
            paint(row.have, muted)
            paint(row.need, data.done and muted or main)
            paint(row.cost, data.done and muted or main)
            row:Show()
        else
            row.itemID, row.remove.itemID, row.qty = nil, nil, nil
            row:Hide()
        end
    end
    parts.bar:update(#rows, VISIBLE, offset)
end

local function scrollTo(newOffset)
    newOffset = math.max(0, math.min(newOffset, #lastData.rows - VISIBLE))
    if newOffset == offset then return end
    offset = newOffset
    paintRows()
end

-- Repaints from the controller (ctl.shoppingData); nothing while closed or not built.
function ShoppingWindow.refresh()
    if not frame or not frame:IsShown() then return end
    local data = ctl.shoppingData()
    lastData = data
    frame:setTitle(L.SHOP_TITLE)
    parts.panel:setTitle(data.title)
    parts.labelName:SetText(L.SHOP_COL_ITEM)
    parts.labelHave:SetText(L.SHOP_COL_HAVE)
    parts.labelNeed:SetText(L.SHOP_COL_NEED)
    parts.labelCost:SetText(L.SHOP_COL_COST)
    parts.total:SetText(data.totalText)
    paint(parts.total, data.incomplete and Colors.FIXED.incomplete or Colors.text("main"))
    parts.clear:setText(L.SHOP_CLEAR)
    parts.clear:SetEnabled(#data.rows > 0)
    parts.empty:SetText(L.SHOP_EMPTY)
    parts.empty:SetShown(#data.rows == 0)
    paintRows()
end

function ShoppingWindow.frame() return frame end

function ShoppingWindow.isShown()
    return frame ~= nil and frame:IsShown() == true
end

function ShoppingWindow.hide()
    if frame then frame:Hide() end
end

local function section(key, height)
    local f = CreateFrame("Frame", nil, content)
    f:SetHeight(height)
    parts.frames[key] = f
    return f
end

local function hideTip()
    if type(GameTooltip) == "table" then GameTooltip:Hide() end
end

-- The "x" removing a row, as the pinned window's unpin: a plain button, grey lit white.
local function buildRemove(row)
    local x = CreateFrame("Button", nil, row)
    x:SetSize(X_SIZE, X_SIZE)
    x:SetPoint("RIGHT", row, "RIGHT", -X_RIGHT, 0)
    x:SetNormalFontObject("GameFontDisableSmall")
    x:SetHighlightFontObject("GameFontHighlightSmall")
    x:SetText("x")
    Native.forwardDrag(x, frame)
    x:SetScript("OnClick", function(self)
        if self.dragged == true then return end
        if self.itemID then ctl.shoppingRemove(self.itemID) end
    end)
    x:SetScript("OnEnter", function(self)
        row.hover:Show()
        if type(GameTooltip) ~= "table" then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.SHOP_REMOVE)
        GameTooltip:Show()
    end)
    x:SetScript("OnLeave", function()
        row.hover:Hide()
        hideTip()
    end)
    return x
end

local function column(row, width, anchor, anchorPoint, x)
    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("RIGHT", anchor, anchorPoint, x, 0)
    fs:SetWidth(width)
    fs:SetJustifyH("RIGHT")
    fs:SetWordWrap(false)
    return fs
end

local function buildRow(body, i)
    local row = Native.listRow(body, i, ROW_H, ROW_RIGHT)
    row.remove = buildRemove(row)
    row.cost = column(row, COST_W, row.remove, "LEFT", -COL_GAP)
    row.need = column(row, COUNT_W, row.cost, "LEFT", -COL_GAP)
    row.have = column(row, COUNT_W, row.need, "LEFT", -COL_GAP)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.name:SetPoint("RIGHT", row.have, "LEFT", -COL_GAP, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    Native.forwardDrag(row, frame)
    -- A click searches what is missing at the auction house (needs it open).
    row:SetScript("OnClick", function(self)
        if self.dragged == true then return end
        if self.itemID then ctl.onReagentClick(self.itemID, self.qty) end
    end)
    return row
end

-- The column labels, right-aligned over the row columns (same widths and gaps).
local function buildLabels()
    local f = section("labels", LABELS_H)
    local right = ROW_RIGHT + Native.PANEL_EDGE + X_RIGHT + X_SIZE + COL_GAP
    local function label(width, x)
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        fs:SetPoint("RIGHT", f, "RIGHT", -x, 0)
        fs:SetWidth(width)
        fs:SetJustifyH("RIGHT")
        fs:SetWordWrap(false)
        return fs
    end
    parts.labelCost = label(COST_W, right)
    parts.labelNeed = label(COUNT_W, right + COST_W + COL_GAP)
    parts.labelHave = label(COUNT_W, right + COST_W + COUNT_W + COL_GAP * 2)
    parts.labelName = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    parts.labelName:SetPoint("LEFT", f, "LEFT", Native.PANEL_EDGE + 8, 0)
    parts.labelName:SetJustifyH("LEFT")
end

local function build()
    local panelH = Layout.panelHeight(VISIBLE, ROW_H)
    local offsets, total = Layout.stack({ LABELS_H, panelH, TOTAL_H, STRIP_H }, GAP, PAD)

    frame = Native.window(NAME, L.SHOP_TITLE, {
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
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, NAME) end
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta) scrollTo(offset - delta) end)

    buildLabels()

    parts.panel = Native.panel(content, "")
    parts.frames.panel = parts.panel.frame
    parts.panel.frame:SetHeight(panelH)
    for i = 1, VISIBLE do parts.rows[i] = buildRow(parts.panel.body, i) end
    parts.bar = Native.scrollbar(parts.panel.body, VISIBLE * ROW_H)
    parts.bar.frame:SetPoint("TOPRIGHT", parts.panel.body, "TOPRIGHT", -2, 0)
    parts.bar.onScroll = scrollTo
    parts.empty = parts.panel.body:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    parts.empty:SetPoint("TOP", parts.panel.body, "TOP", 0, -20)
    parts.empty:SetWidth(EMPTY_WIDTH)
    parts.empty:SetJustifyH("CENTER")
    parts.empty:SetWordWrap(true)

    local totalRow = section("total", TOTAL_H)
    parts.total = totalRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    parts.total:SetPoint("RIGHT", totalRow, "RIGHT", -(ROW_RIGHT + Native.PANEL_EDGE + X_RIGHT + X_SIZE + COL_GAP), 0)
    parts.total:SetJustifyH("RIGHT")

    local strip = section("strip", STRIP_H)
    parts.clear = Native.button(strip, "", { width = math.floor(INNER_WIDTH / 2), onClick = function()
        ctl.shoppingClear()
    end })
    parts.clear:SetPoint("TOPRIGHT", strip, "TOPRIGHT", 0, 0)

    for i, key in ipairs({ "labels", "panel", "total", "strip" }) do
        local f = parts.frames[key]
        f:SetPoint("TOPLEFT", content, "TOPLEFT", origin.left + PAD, offsets[i] - origin.top)
        f:SetPoint("TOPRIGHT", content, "TOPRIGHT", -origin.right - PAD, offsets[i] - origin.top)
    end
    frame:Hide()
end

function ShoppingWindow.show()
    if not ctl then return end
    if not frame then build() end
    ShoppingWindow.place()
    frame:Show()
    if type(frame.Raise) == "function" then frame:Raise() end
    ShoppingWindow.refresh()
end

function ShoppingWindow.toggle()
    if ShoppingWindow.isShown() then ShoppingWindow.hide() else ShoppingWindow.show() end
end

-- Builds nothing: the window is made on first open. handlers: onMoved(point, x, y).
function ShoppingWindow.init(controller, h)
    ctl, handlers = controller, h or {}
end

-- Position: the saved one once dragged, else over the main window (its top left corner on
-- the main window's), else the middle of the screen.
function ShoppingWindow.place()
    if not frame then return end
    frame:ClearAllPoints()
    local main = ns.Window.frame()
    if savedPosition then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", savedPosition.x, savedPosition.y)
    elseif main and ns.Window.isShown() and type(main.GetLeft) == "function" and main:GetLeft() and main:GetTop() then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", main:GetLeft(), main:GetTop())
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

function ShoppingWindow.attach(saved)
    savedPosition = saved
    ShoppingWindow.place()
end
