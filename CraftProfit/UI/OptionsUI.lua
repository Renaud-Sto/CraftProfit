-- The options window: the look (header strip and tile card, applied at once to every
-- window), the pinned recipes limit, the minimap button, shortcuts to the other windows and
-- the list of the controls. Built on first open, never at login. Opened by /cp options, the minimap button and the
-- addon compartment. Escape closes it.
--
-- Choices are rows of native buttons, the chosen one lit (LockHighlight): never a dropdown
-- or the Menu API, which crash or taint the Forever client.
local _, ns = ...
local L = ns.L
local Native, Colors = ns.Native, ns.Colors
-- Pure layout maths (stack).
local Layout = ns.Layout

local OptionsUI = {}
ns.OptionsUI = OptionsUI

local NAME = "CraftProfitOptionsWindow"
-- Wide enough for the three segmented header buttons with their Spanish and French labels
-- ("Madera tallada", "Bois sculpté") at CHAR_W per letter.
local WIDTH = 420
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
-- Width of one letter of the game's button font (GameFontNormal, 12 px), estimated from the
-- client: "Montée de métier" (16 letters) did not fit a 107 px label. The tests check every
-- button label of every language against it.
local CHAR_W = 7
-- The controls list: one line per click or command, in the small font.
local LINE_H = 14
-- Air under the last line, so it does not touch the panel's bottom edge.
local LIST_BOTTOM = 8
-- Width of one letter of the small font (GameFontHighlightSmall, 10 px), estimated; the tests
-- keep every line of every language within the panel with it.
local SMALL_CHAR_W = 6
-- Each line: the gesture or command in gold (a locale key, or the literal command), then the
-- locale key of its description in white.
local CONTROL_LINES = {
    { "OPTIONS_CLICK_LEFT", "CMD_OPTIONS" },
    { "OPTIONS_CLICK_RIGHT", "CMD_PINS" },
    { "/cp show", "CMD_SHOW" },
    { "/cp hide", "CMD_HIDE" },
    { "/cp reset", "CMD_RESET" },
    { "/cp options", "CMD_OPTIONS" },
    { "/cp pins", "CMD_PINS" },
    { "/cp level", "CMD_LEVEL" },
    { "/cp minimap", "CMD_MINIMAP" },
    { "/cp history", "CMD_HISTORY" },
    { "/cp scan", "CMD_SCAN" },
    { "/cp market", "CMD_MARKET" },
    { "/cp locale <code>", "CMD_LOCALE" },
    { "/cp selftest", "CMD_SELFTEST" },
}

-- The variants in button order, with their label keys (the order of the rulings).
local HEADER_CHOICES = { { "a", "OPTIONS_HEADER_A" }, { "b", "OPTIONS_HEADER_B" }, { "c", "OPTIONS_HEADER_C" } }
local TILE_CHOICES = { { "a", "OPTIONS_TILE_A" }, { "b", "OPTIONS_TILE_B" } }
-- The pin limits, labelled with their number (no locale key).
local PIN_CHOICES = {}
for i, n in ipairs(ns.DB.PIN_LIMITS) do PIN_CHOICES[i] = { n } end
-- The note under the pin limits: at most two lines of the small font.
local NOTE_LINES = 2

local ctl
local frame, content, savedPosition
local origin = { left = 0, right = 0, top = 0 }
-- The widgets, exposed for tests: panels, headerButtons / tileButtons (by key), minimap,
-- pinButtons (by limit), pinLabel, pinNote, mainButton, levelButton, pinsButton, headerLabel,
-- tileLabel, lines (the controls list).
local parts = { panels = {}, headerButtons = {}, tileButtons = {}, pinButtons = {}, lines = {} }
OptionsUI.parts = parts
OptionsUI.ROOM = ROOM
OptionsUI.CHAR_W = CHAR_W
OptionsUI.SMALL_CHAR_W = SMALL_CHAR_W
OptionsUI.LINE_COUNT = #CONTROL_LINES
OptionsUI.LIST_BOTTOM = LIST_BOTTOM

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

-- Stacks the five panels and sizes the window from them (the controls list has a fixed line
-- count, the note a fixed number of lines).
local function layout()
    local p = parts.panels
    p.appearance:setRows(2, CHOICE_ROW_H)
    p.pins:setRows(1, CHOICE_ROW_H, NOTE_LINES * LINE_H + LIST_BOTTOM)
    p.minimap:setRows(1, LINE_ROW_H)
    p.windows:setRows(2, LINE_ROW_H)
    p.controls:setRows(#CONTROL_LINES, LINE_H, LIST_BOTTOM)
    local order = { p.appearance, p.pins, p.minimap, p.windows, p.controls }
    local heights = {}
    for i, panel in ipairs(order) do heights[i] = panel:height() end
    local offsets, total = Layout.stack(heights, GAP, PAD)
    for i, panel in ipairs(order) do
        local f = panel.frame
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", content, "TOPLEFT", origin.left + PAD, offsets[i] - origin.top)
        f:SetPoint("TOPRIGHT", content, "TOPRIGHT", -origin.right - PAD, offsets[i] - origin.top)
    end
    frame:SetHeight(Native.windowHeight(CHROME_H + PAD + total + PAD))
end

local function pickHeader(key)
    ctl.setAppearance(key, nil)
    OptionsUI.refresh()
end

local function pickTile(key)
    ctl.setAppearance(nil, key)
    OptionsUI.refresh()
end

-- Saved at once and used by the next pin attempt; the controller refreshes every view,
-- this window included.
local function pickPinLimit(n)
    ctl.setPinLimit(n)
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

    panels.pins = Native.panel(content, L.OPTIONS_PINS)
    local pinBody = panels.pins.body
    parts.pinLabel = choiceRow(pinBody, 1, PIN_CHOICES, parts.pinButtons, pickPinLimit)
    -- Why a higher limit costs something, under the buttons: wrapped, two lines at most (the
    -- tests keep every language within them).
    parts.pinNote = pinBody:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    parts.pinNote:SetPoint("TOPLEFT", pinBody, "TOPLEFT", 8, -CHOICE_ROW_H)
    parts.pinNote:SetWidth(ROOM)
    parts.pinNote:SetHeight(NOTE_LINES * LINE_H)
    parts.pinNote:SetJustifyH("LEFT")
    parts.pinNote:SetJustifyV("TOP")
    parts.pinNote:SetWordWrap(true)

    panels.minimap = Native.panel(content, L.OPTIONS_MINIMAP)
    parts.minimap = Native.check(panels.minimap.body, "", function(checked)
        ctl.setMinimapHidden(not checked)
    end, ROOM - Native.CHECK_SIZE - Native.CHECK_LABEL_X)
    parts.minimap:SetPoint("TOPLEFT", panels.minimap.body, "TOPLEFT", 4, -1)

    panels.windows = Native.panel(content, L.OPTIONS_WINDOWS)
    -- Two rows: main and leveling side by side, pinned recipes centred under them, all three
    -- half the room wide so a French label is never cut.
    local half = math.floor((ROOM - SEG_GAP) / 2)
    local winBody = panels.windows.body
    parts.mainButton = Native.button(winBody, "", { width = half,
        onClick = function() ctl.toggleMainWindow() end })
    parts.mainButton:SetPoint("TOPLEFT", winBody, "TOPLEFT", 8, -2)
    parts.levelButton = Native.button(winBody, "", { width = half,
        onClick = function() if ns.LevelingUI then ns.LevelingUI.toggle() end end })
    parts.levelButton:SetPoint("LEFT", parts.mainButton, "RIGHT", SEG_GAP, 0)
    parts.pinsButton = Native.button(winBody, "", { width = half,
        onClick = function() if ns.PinnedWindow then ns.PinnedWindow.toggle() end end })
    parts.pinsButton:SetPoint("TOP", winBody, "TOP", 0, -2 - LINE_ROW_H)
    for _, button in ipairs({ parts.mainButton, parts.levelButton, parts.pinsButton }) do
        Native.forwardDrag(button, frame)
    end

    panels.controls = Native.panel(content, L.OPTIONS_CONTROLS)
    -- One line each, never wrapped: a line too long for the panel is cut with "...".
    for i = 1, #CONTROL_LINES do
        local line = panels.controls.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line:SetPoint("TOPLEFT", panels.controls.body, "TOPLEFT", 8, -(i - 1) * LINE_H)
        line:SetWidth(ROOM)
        line:SetHeight(LINE_H)
        line:SetJustifyH("LEFT")
        line:SetWordWrap(false)
        parts.lines[i] = line
    end

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
    panels.pins:setTitle(L.OPTIONS_PINS)
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
    parts.pinLabel:SetText(L.OPTIONS_PIN_LIMIT)
    local limit = ctl.pinLimit()
    for n, button in pairs(parts.pinButtons) do
        button:setText(tostring(n))
        setLit(button, n == limit)
    end
    parts.pinNote:SetText(L.OPTIONS_PIN_NOTE)
    parts.minimap:setText(L.OPTIONS_SHOW_MINIMAP)
    parts.minimap:SetChecked(not ctl.minimapHidden())
    parts.mainButton:setText(L.OPTIONS_MAIN_WINDOW)
    parts.levelButton:setText(L.LEVEL_BUTTON)
    parts.pinsButton:setText(L.PINNED_TITLE)
    local gold, white = Colors.escape(Colors.text("gold")), Colors.escape(Colors.text("main"))
    for i, entry in ipairs(CONTROL_LINES) do
        local head = entry[1]:sub(1, 1) == "/" and entry[1] or L[entry[1]]
        parts.lines[i]:SetText(gold .. head .. "|r" .. white .. " - " .. L[entry[2]] .. "|r")
    end
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

-- Position: the saved one once the window has been dragged, else beside the rightmost
-- shown CraftProfit window (Controller.besidePosition), else the middle of the screen.
function OptionsUI.place()
    if not frame then return end
    frame:ClearAllPoints()
    local x, y
    if not savedPosition and ctl and ctl.besidePosition then x, y = ctl.besidePosition(frame) end
    if savedPosition then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", savedPosition.x, savedPosition.y)
    elseif x then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

-- The saved position ({ x, y } or nil); applied now when the window exists, else on open.
function OptionsUI.attach(saved)
    savedPosition = saved
    OptionsUI.place()
end
