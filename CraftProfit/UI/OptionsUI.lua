-- The options window: the look (header strip and tile card, applied at once to every
-- window), the minimap button, shortcuts to the other windows and a recap of the controls.
-- Built on first open, never at login. Opened by /cp options (and, later, the minimap
-- button and the addon compartment). Escape closes it.
--
-- Choices are rows of native buttons, the chosen one lit (LockHighlight): never a dropdown
-- or the Menu API, which crash or taint the Forever client.
local _, ns = ...
local L = ns.L
local Native = ns.Native
-- Only the kit's pure layout maths (panelHeight, stack) until it moves out of Kit.
local Kit = ns.Kit

local OptionsUI = {}
ns.OptionsUI = OptionsUI

local NAME = "CraftProfitOptionsWindow"
local WIDTH = 372
local PAD = Native.CONTENT_PAD
local GAP = 8
local CHROME_H = Native.INSET_TOP + Native.INSET_BOTTOM
local INNER_WIDTH = WIDTH - Native.INSET_LEFT - Native.INSET_RIGHT - PAD * 2
-- A panel body is the section less the panel's edges; widgets keep 8 px from its sides.
local BODY_WIDTH = INNER_WIDTH - Native.PANEL_EDGE * 2
local ROOM = BODY_WIDTH - 16
-- An appearance row: its label on one line, the segmented buttons under it.
local LABEL_H = 14
local CHOICE_ROW_H = LABEL_H + 2 + Native.BUTTON_H + 4
local SEG_GAP = 4
local LINE_ROW_H = 26
-- The controls recap's height when the client cannot measure the wrapped text.
local RECAP_FALLBACK_H = 64

-- The variants in button order, with their label keys (the order of the rulings).
local HEADER_CHOICES = { { "a", "OPTIONS_HEADER_A" }, { "b", "OPTIONS_HEADER_B" }, { "c", "OPTIONS_HEADER_C" } }
local TILE_CHOICES = { { "a", "OPTIONS_TILE_A" }, { "b", "OPTIONS_TILE_B" } }

OptionsUI.NAME = NAME
OptionsUI.WIDTH = WIDTH
OptionsUI.INNER_WIDTH = INNER_WIDTH

local ctl
local frame, content, savedPosition
local origin = { left = 0, right = 0, top = 0 }
-- The widgets, exposed for tests: panels, headerButtons / tileButtons (by key), minimap,
-- mainButton, levelButton, headerLabel, tileLabel, recap.
local parts = { panels = {}, headerButtons = {}, tileButtons = {} }
OptionsUI.parts = parts

-- Lights `button` (the chosen segment) or puts it out; `button.lit` mirrors the state.
local function setLit(button, lit)
    button.lit = lit and true or false
    if lit then
        if type(button.LockHighlight) == "function" then button:LockHighlight() end
    elseif type(button.UnlockHighlight) == "function" then
        button:UnlockHighlight()
    end
end

-- A label and a row of equal buttons, one per choice, under it; `onPick(key)` on a click.
local function choiceRow(body, index, choices, buttons, onPick)
    local y = -(index - 1) * CHOICE_ROW_H
    local label = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", body, "TOPLEFT", 8, y)
    label:SetPoint("TOPRIGHT", body, "TOPRIGHT", -8, y)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    local count = #choices
    local width = math.floor((ROOM - SEG_GAP * (count - 1)) / count)
    for i, choice in ipairs(choices) do
        local key = choice[1]
        local button = Native.button(body, "", { width = width, onClick = function() onPick(key) end })
        button:SetPoint("TOPLEFT", body, "TOPLEFT", 8 + (i - 1) * (width + SEG_GAP), y - LABEL_H - 2)
        button.labelKey = choice[2]
        Native.forwardDrag(button, frame)
        buttons[key] = button
    end
    return label
end

-- Height of the wrapped recap text, measured when the client can.
local function recapHeight()
    local h = parts.recap:GetStringHeight()
    if type(h) ~= "number" or h <= 0 then return RECAP_FALLBACK_H end
    return math.ceil(h)
end

-- Stacks the four panels and sizes the window: the recap's height changes with the
-- language.
local function layout()
    local p = parts.panels
    p.appearance:setRows(2, CHOICE_ROW_H)
    p.minimap:setRows(1, LINE_ROW_H)
    p.windows:setRows(1, LINE_ROW_H)
    p.controls:setRows(0, 0, recapHeight())
    local order = { p.appearance, p.minimap, p.windows, p.controls }
    local heights = {}
    for i, panel in ipairs(order) do heights[i] = panel:height() end
    local offsets, total = Kit.stack(heights, GAP, PAD)
    for i, panel in ipairs(order) do
        local f = panel.frame
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", content, "TOPLEFT", origin.left + PAD, offsets[i] - origin.top)
        f:SetPoint("TOPRIGHT", content, "TOPRIGHT", -origin.right - PAD, offsets[i] - origin.top)
    end
    frame:SetHeight(CHROME_H + PAD + total + PAD)
end

local function pickHeader(key)
    ctl.setAppearance(key, nil)
    OptionsUI.refresh()
end

local function pickTile(key)
    ctl.setAppearance(nil, key)
    OptionsUI.refresh()
end

local function build()
    frame = Native.window(NAME, L.OPTIONS_TITLE, {
        width = WIDTH,
        onMoved = function(_, x, y) savedPosition = { x = x, y = y }; ctl.saveOptionsPosition(x, y) end,
    })
    content = frame.content
    if content == frame then
        origin = { left = Native.INSET_LEFT, right = Native.INSET_RIGHT, top = Native.INSET_TOP }
    end
    -- Escape closes it, the game's way for a plain named frame (never UIPanelWindows).
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, NAME) end

    local panels = parts.panels
    panels.appearance = Native.panel(content, L.OPTIONS_APPEARANCE)
    local body = panels.appearance.body
    parts.headerLabel = choiceRow(body, 1, HEADER_CHOICES, parts.headerButtons, pickHeader)
    parts.tileLabel = choiceRow(body, 2, TILE_CHOICES, parts.tileButtons, pickTile)

    panels.minimap = Native.panel(content, L.OPTIONS_MINIMAP)
    parts.minimap = Native.check(panels.minimap.body, "", function(checked)
        ctl.setMinimapHidden(not checked)
    end, ROOM - Native.CHECK_SIZE - Native.CHECK_LABEL_X)
    parts.minimap:SetPoint("TOPLEFT", panels.minimap.body, "TOPLEFT", 4, -1)

    panels.windows = Native.panel(content, L.OPTIONS_WINDOWS)
    local half = math.floor((ROOM - SEG_GAP) / 2)
    parts.mainButton = Native.button(panels.windows.body, "", { width = half,
        onClick = function() ctl.toggleMainWindow() end })
    parts.mainButton:SetPoint("TOPLEFT", panels.windows.body, "TOPLEFT", 8, -2)
    parts.levelButton = Native.button(panels.windows.body, "", { width = half,
        onClick = function() if ns.LevelingUI then ns.LevelingUI.toggle() end end })
    parts.levelButton:SetPoint("LEFT", parts.mainButton, "RIGHT", SEG_GAP, 0)
    for _, button in ipairs({ parts.mainButton, parts.levelButton }) do Native.forwardDrag(button, frame) end

    panels.controls = Native.panel(content, L.OPTIONS_CONTROLS)
    parts.recap = panels.controls.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    parts.recap:SetPoint("TOPLEFT", panels.controls.body, "TOPLEFT", 8, 0)
    parts.recap:SetWidth(ROOM)
    parts.recap:SetJustifyH("LEFT")
    parts.recap:SetWordWrap(true)

    -- Native.window returns it hidden; the caller shows it.
    frame:Hide()
end

-- Repaints texts and choices from the saved settings (and the current language); does
-- nothing while the window is closed.
function OptionsUI.refresh()
    if not frame or not frame:IsShown() then return end
    frame:setTitle(L.OPTIONS_TITLE)
    local panels = parts.panels
    panels.appearance:setTitle(L.OPTIONS_APPEARANCE)
    panels.minimap:setTitle(L.OPTIONS_MINIMAP)
    panels.windows:setTitle(L.OPTIONS_WINDOWS)
    panels.controls:setTitle(L.OPTIONS_CONTROLS)
    parts.headerLabel:SetText(L.OPTIONS_HEADER)
    parts.tileLabel:SetText(L.OPTIONS_TILE)
    local header, tile = ctl.appearance()
    for key, button in pairs(parts.headerButtons) do
        button:setText(L[button.labelKey])
        setLit(button, key == header)
    end
    for key, button in pairs(parts.tileButtons) do
        button:setText(L[button.labelKey])
        setLit(button, key == tile)
    end
    parts.minimap:setText(L.OPTIONS_SHOW_MINIMAP)
    parts.minimap:SetChecked(not ctl.minimapHidden())
    parts.mainButton:setText(L.OPTIONS_MAIN_WINDOW)
    parts.levelButton:setText(L.LEVEL_BUTTON)
    parts.recap:SetText(L.OPTIONS_RECAP)
    layout()
end

function OptionsUI.frame() return frame end

function OptionsUI.isShown()
    return frame ~= nil and frame:IsShown() == true
end

function OptionsUI.show()
    if not ctl then return end
    if not frame then build() end
    OptionsUI.place()
    frame:Show()
    OptionsUI.refresh()
end

function OptionsUI.hide()
    if frame then frame:Hide() end
end

function OptionsUI.toggle()
    if OptionsUI.isShown() then OptionsUI.hide() else OptionsUI.show() end
end

-- Builds nothing: the window is made on first open.
function OptionsUI.init(controller)
    ctl = controller
end

-- Position: the saved one once the window has been dragged, else the middle of the screen.
function OptionsUI.place()
    if not frame then return end
    frame:ClearAllPoints()
    if savedPosition then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", savedPosition.x, savedPosition.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

-- The saved position ({ x, y } or nil); applied now when the window exists, else on open.
function OptionsUI.attach(saved)
    savedPosition = saved
    OptionsUI.place()
end
