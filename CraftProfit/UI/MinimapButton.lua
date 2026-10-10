-- The minimap button: left click opens the options window, right click the main window,
-- a left drag moves it around the minimap. The LibDBIcon convention without the library:
-- 31x31, strata MEDIUM, level 8, radius from the minimap's size, square minimaps handled.
-- Never created while the player keeps it hidden (settings.minimap.hide), not even at
-- login; no chat line at login. OnUpdate runs only during a drag.
local _, ns = ...
local Util = ns.Util

local MinimapButton = {}
ns.MinimapButton = MinimapButton

MinimapButton.NAME = "CraftProfitMinimapButton"
MinimapButton.SIZE = 31
MinimapButton.LEVEL = 8
MinimapButton.DEFAULT_ANGLE = 225
-- The default minimap is 140 px wide.
MinimapButton.DEFAULT_WIDTH = 140
-- Game files the client serves to addons (the ones SO-6 uses on Forever).
MinimapButton.ICON = "Interface\\Icons\\INV_Misc_Coin_01"
MinimapButton.ICON_FALLBACK = "Interface\\Icons\\INV_Misc_QuestionMark"
local BORDER = "Interface\\Minimap\\MiniMap-TrackingBorder"
local BACKGROUND = "Interface\\Minimap\\UI-Minimap-Background"
local HIGHLIGHT = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"

-- Pure helpers ---------------------------------------------------------------------

-- Direction from the minimap centre (mx, my) to the cursor (cx, cy), in degrees in
-- [0, 360), 0 to the right, counter-clockwise. nil when a coordinate is not a finite number.
function MinimapButton.angleFromCursor(cx, cy, mx, my)
    if not (Util.isFinite(cx) and Util.isFinite(cy) and Util.isFinite(mx) and Util.isFinite(my)) then
        return nil
    end
    local angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    if not (angle >= 0 and angle < 360) then return 0 end
    return angle
end

-- Distance of the button's centre from the minimap's centre.
function MinimapButton.radius(minimapWidth)
    if not Util.isFinite(minimapWidth) or minimapWidth <= 0 then minimapWidth = MinimapButton.DEFAULT_WIDTH end
    return minimapWidth / 2 + 5
end

-- Where the button's centre goes, relative to the minimap's centre, for `angle` degrees.
-- Round minimap: on the circle of `radius`. Square one: the point of a circle as wide as
-- the square's diagonal, clamped to the square's half-size, so the button follows the
-- edges and fills the corners (as LibDBIcon does). A bad angle uses the default one; a
-- bad radius puts the button on the centre.
function MinimapButton.offset(angle, radius, square)
    if not Util.isFinite(angle) then angle = MinimapButton.DEFAULT_ANGLE end
    if not Util.isFinite(radius) or radius < 0 then radius = 0 end
    local rad = math.rad(angle % 360)
    local x, y = math.cos(rad), math.sin(rad)
    if not square then return x * radius, y * radius end
    local diag = math.max(0, math.sqrt(2 * radius * radius) - 10)
    return math.max(-radius, math.min(x * diag, radius)), math.max(-radius, math.min(y * diag, radius))
end

-- Widget ----------------------------------------------------------------------------

local button

local function controller() return ns.Controller end

local function minimapFrame()
    if type(Minimap) == "table" then return Minimap end
    return nil
end

-- A minimap addon (SexyMap and others) that squares the minimap says so through the
-- global GetMinimapShape, the convention LibDBIcon reads.
local function isSquare()
    if type(GetMinimapShape) ~= "function" then return false end
    local ok, shape = pcall(GetMinimapShape)
    return ok and shape == "SQUARE"
end

local function place(angle)
    local map = minimapFrame()
    if not button or not map then return end
    local width = type(map.GetWidth) == "function" and map:GetWidth() or nil
    local x, y = MinimapButton.offset(angle, MinimapButton.radius(width), isSquare())
    button:ClearAllPoints()
    button:SetPoint("CENTER", map, "CENTER", x, y)
end

-- The coin when the client serves it, else the question mark (never a guessed path that
-- would draw a green square).
local function iconPath()
    if type(GetFileIDFromPath) == "function" then
        local ok, id = pcall(GetFileIDFromPath, MinimapButton.ICON)
        if ok and id then return MinimapButton.ICON end
    end
    return MinimapButton.ICON_FALLBACK
end

-- The cursor's angle around the minimap, nil when it cannot be read.
local function cursorAngle()
    local map = minimapFrame()
    if not map or type(GetCursorPosition) ~= "function" then return nil end
    local cx, cy = GetCursorPosition()
    local scale = type(map.GetEffectiveScale) == "function" and map:GetEffectiveScale() or 1
    if not Util.isFinite(scale) or scale <= 0 then scale = 1 end
    local mx, my = map:GetCenter()
    if not Util.isFinite(cx) or not Util.isFinite(cy) then return nil end
    return MinimapButton.angleFromCursor(cx / scale, cy / scale, mx, my)
end

local function follow()
    local angle = cursorAngle()
    if angle then
        button.dragAngle = angle
        place(angle)
    end
end

local function stopDrag()
    if button.dragging ~= true then return end
    button.dragging = false
    button:SetScript("OnUpdate", nil)
    if type(button.dragAngle) == "number" then controller().setMinimapAngle(button.dragAngle) end
end

local function onUpdate()
    -- A mouse-up that never arrives (alt-tab) must not leave the drag running.
    if type(IsMouseButtonDown) == "function" and not IsMouseButtonDown("LeftButton") then
        follow()
        stopDrag()
        return
    end
    follow()
end

local function showTooltip(self)
    if button.dragging == true or type(GameTooltip) ~= "table" then return end
    local L = ns.L
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    if type(GameTooltip_SetTitle) == "function" then GameTooltip_SetTitle(GameTooltip, L.TITLE) end
    if type(GameTooltip_AddInstructionLine) == "function" then
        for _, key in ipairs({ "MINIMAP_TIP_LEFT", "MINIMAP_TIP_RIGHT", "MINIMAP_TIP_DRAG" }) do
            GameTooltip_AddInstructionLine(GameTooltip, L[key])
        end
    end
    GameTooltip:Show()
end

local function hideTooltip()
    if type(GameTooltip) == "table" then GameTooltip:Hide() end
end

local function texture(layer, path, width, height)
    local tex = button:CreateTexture(nil, layer)
    tex:SetTexture(path)
    tex:SetSize(width, height)
    return tex
end

-- Makes the button once; nil (and nothing made) while it is hidden or without a minimap.
function MinimapButton.create()
    if button then return button end
    local ctl = controller()
    if not ctl or ctl.minimapHidden() then return nil end
    local map = minimapFrame()
    if not map then return nil end
    -- Nil parent then SetParent: the minimap is a Blizzard frame (gamepad CreateFrame hook).
    button = CreateFrame("Button", MinimapButton.NAME, nil)
    button:SetParent(map)
    button:SetSize(MinimapButton.SIZE, MinimapButton.SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(MinimapButton.LEVEL)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture(HIGHLIGHT)
    -- Set, never left missing: state flags read with explicit comparisons.
    button.dragged, button.dragging, button.dragAngle = false, false, nil

    local background = texture("BACKGROUND", BACKGROUND, 24, 24)
    background:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -5)
    local icon = texture("ARTWORK", iconPath(), 18, 18)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -5)
    button.icon = icon
    local border = texture("OVERLAY", BORDER, 50, 50)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

    -- The release that ends a drag still fires OnClick: `dragged` stays true from the
    -- start of a drag to the next press, and the click handler returns early while it is.
    button:SetScript("OnMouseDown", function(self) self.dragged = false end)
    button:SetScript("OnClick", function(self, which)
        if self.dragged == true then return end
        if which == "RightButton" then
            controller().toggleMainWindow()
        elseif ns.OptionsUI then
            ns.OptionsUI.toggle()
        end
    end)
    button:SetScript("OnDragStart", function(self)
        self.dragged, self.dragging, self.dragAngle = true, true, nil
        hideTooltip()
        self:SetScript("OnUpdate", onUpdate)
    end)
    button:SetScript("OnDragStop", stopDrag)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", hideTooltip)
    return button
end

-- Shows or hides the button as saved, making it on its first show and putting it at the
-- saved angle.
function MinimapButton.apply()
    local ctl = controller()
    if not ctl then return end
    if ctl.minimapHidden() then
        if button then button:Hide() end
        return
    end
    if not MinimapButton.create() then return end
    place(ctl.minimapAngle())
    button:Show()
end

function MinimapButton.frame() return button end
