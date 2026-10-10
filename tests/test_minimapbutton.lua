local H = ...
local W = dofile("tests/fakewow.lua")

local function near(a, b) return math.abs(a - b) < 1e-9 end

local function nearPair(x, y, ex, ey)
    H.truthy(near(x, ex) or error(("x %s, want %s"):format(x, ex)))
    H.truthy(near(y, ey) or error(("y %s, want %s"):format(y, ey)))
end

local function pure()
    return H.newNS("Util", "UI/MinimapButton").MinimapButton
end

-- Pure helpers -------------------------------------------------------------------

H.test("the angle from the minimap centre to the cursor is in degrees, in [0, 360)", function()
    local M = pure()
    H.truthy(near(M.angleFromCursor(110, 50, 100, 50), 0))
    H.truthy(near(M.angleFromCursor(100, 60, 100, 50), 90))
    H.truthy(near(M.angleFromCursor(90, 50, 100, 50), 180))
    H.truthy(near(M.angleFromCursor(100, 40, 100, 50), 270))
    H.truthy(near(M.angleFromCursor(90, 40, 100, 50), 225))
    -- The cursor on the centre: no direction, 0 rather than NaN.
    H.eq(M.angleFromCursor(100, 50, 100, 50), 0)
    for _, bad in ipairs({ { 0 / 0, 1, 1, 1 }, { 1, math.huge, 1, 1 }, { 1, 1, nil, 1 }, { "1", 1, 1, 1 } }) do
        H.eq(M.angleFromCursor(bad[1], bad[2], bad[3], bad[4]), nil)
    end
end)

H.test("on a round minimap the button sits on the circle", function()
    local M = pure()
    local r = 75
    local x, y = M.offset(0, r, false)
    nearPair(x, y, 75, 0)
    x, y = M.offset(90, r, false)
    nearPair(x, y, 0, 75)
    x, y = M.offset(180, r, false)
    nearPair(x, y, -75, 0)
    x, y = M.offset(270, r, false)
    nearPair(x, y, 0, -75)
    x, y = M.offset(225, r, false)
    local d = 75 * math.sqrt(2) / 2
    nearPair(x, y, -d, -d)
end)

H.test("on a square minimap the point is pushed to the square's edge and clamped", function()
    local M = pure()
    local r = 75
    local x, y = M.offset(0, r, true)
    nearPair(x, y, 75, 0)
    x, y = M.offset(90, r, true)
    nearPair(x, y, 0, 75)
    x, y = M.offset(180, r, true)
    nearPair(x, y, -75, 0)
    x, y = M.offset(270, r, true)
    nearPair(x, y, 0, -75)
    -- The diagonal reaches the corner region (further than the circle), never past r.
    x, y = M.offset(225, r, true)
    local diag = math.sqrt(2 * r * r) - 10
    local d = diag * math.sqrt(2) / 2
    nearPair(x, y, -d, -d)
    H.truthy(-x > 75 * math.sqrt(2) / 2 and -x <= 75)
    x, y = M.offset(30, r, true)
    H.truthy(x <= 75 and y <= 75)
end)

H.test("hostile angles and radii give a finite place", function()
    local M = pure()
    for _, angle in ipairs({ 0 / 0, math.huge, -math.huge, "90", {} }) do
        local x, y = M.offset(angle, 75, false)
        local dx, dy = M.offset(225, 75, false)
        nearPair(x, y, dx, dy)
    end
    for _, radius in ipairs({ 0 / 0, math.huge, -5, "75" }) do
        local x, y = M.offset(90, radius, true)
        nearPair(x, y, 0, 0)
    end
    -- A negative or huge angle wraps.
    local x, y = M.offset(-90, 75, false)
    nearPair(x, y, 0, -75)
    x, y = M.offset(450, 75, false)
    nearPair(x, y, 0, 75)
end)

H.test("the radius is half the minimap width plus 5, with a default for a bad width", function()
    local M = pure()
    H.eq(M.radius(140), 75)
    H.eq(M.radius(200), 105)
    for _, bad in ipairs({ 0 / 0, -1, math.huge, nil, "140" }) do H.eq(M.radius(bad), M.radius(140)) end
end)

-- Widget -------------------------------------------------------------------------

-- Boots with a minimap, a tooltip and frames that start shown; records what is created.
local function boot(saved, opts)
    opts = opts or {}
    local T = W.boot(H)
    T.env.CraftProfitDB = saved
    T.env.UISpecialFrames = {}
    local made = {}
    T.textures = {}
    local minimap = W.frame()
    minimap.GetWidth = function() return 140 end
    minimap.GetCenter = function() return 1000, 600 end
    minimap.GetEffectiveScale = function() return 1 end
    T.env.Minimap = minimap
    T.cursor = { 1000, 700 }
    T.env.GetCursorPosition = function() return T.cursor[1], T.cursor[2] end
    T.env.IsMouseButtonDown = function() return true end
    T.files = { ["Interface\\Icons\\INV_Misc_Coin_01"] = 133784 }
    T.env.GetFileIDFromPath = function(path) return T.files[path] end
    T.tooltip = { lines = {} }
    local tip = T.tooltip
    T.env.GameTooltip = {
        SetOwner = function(_, owner) tip.owner = owner end,
        Show = function() tip.shown = true end,
        Hide = function() tip.shown = false end,
    }
    T.env.GameTooltip_SetTitle = function(_, text) tip.title = text end
    T.env.GameTooltip_AddInstructionLine = function(_, text) tip.lines[#tip.lines + 1] = text end
    local create = T.env.CreateFrame
    T.env.CreateFrame = function(kind, name, parent, template)
        local f = create(kind, name, parent, template)
        f.shown = true
        f.kind, f.name, f.createParent = kind, name, parent or false
        f.SetParent = function(self, p) self.parent = p end
        f.SetPoint = function(self, ...) self.point = { ... } end
        f.SetSize = function(self, w, h) self.size = { w, h } end
        f.SetFrameStrata = function(self, s) self.strata = s end
        f.SetFrameLevel = function(self, l) self.level = l end
        f.CreateTexture = function()
            local tex = W.frame()
            tex.SetTexture = function(self, path) self.path = path end
            tex.SetTexCoord = function(self, ...) self.coords = { ... } end
            tex.SetSize = function(self, w, h) self.size = { w, h } end
            tex.SetPoint = function(self, ...) self.point = { ... } end
            T.textures[#T.textures + 1] = tex
            return tex
        end
        made[#made + 1] = f
        return f
    end
    T.made = made
    T.textures = T.textures or {}
    if not opts.noLogin then T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit") end
    return T
end

local function button(T)
    for _, f in ipairs(T.made) do
        if f.name == "CraftProfitMinimapButton" then return f end
    end
    return nil
end

H.test("at login the button is made on the minimap, 31x31, MEDIUM, level 8, at the saved angle", function()
    local T = boot({ settings = { minimap = { hide = false, angle = 90 } } })
    local b = button(T)
    H.truthy(b)
    H.eq(b.kind, "Button")
    H.eq(b.createParent, false)
    H.eq(b.parent, T.env.Minimap)
    H.eq(b.size, { 31, 31 })
    H.eq(b.strata, "MEDIUM")
    H.eq(b.level, 8)
    H.eq(b.shown, true)
    H.eq(b.point[1], "CENTER")
    H.eq(b.point[2], T.env.Minimap)
    nearPair(b.point[4], b.point[5], 0, 75)
    -- The gold coin, its border cropped.
    H.eq(b.icon.path, "Interface\\Icons\\INV_Misc_Coin_01")
    H.eq(b.icon.coords, { 0.05, 0.95, 0.05, 0.95 })
    -- No OnUpdate while idle.
    H.eq(b.scripts.OnUpdate, nil)
    -- No chat line at login.
    H.eq(#T.chat, 0)
end)

H.test("the icon falls back to the question mark when the coin is not served", function()
    local T = boot(nil, { noLogin = true })
    T.files = {}
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    H.eq(button(T).icon.path, "Interface\\Icons\\INV_Misc_QuestionMark")
end)

H.test("nothing is created at login when the button is hidden, and create does nothing either", function()
    local T = boot({ settings = { minimap = { hide = true, angle = 90 } } })
    H.eq(button(T), nil)
    H.eq(T.ns.MinimapButton.create(), nil)
    T.ns.MinimapButton.apply()
    H.eq(button(T), nil)
end)

H.test("create is idempotent and apply shows, hides and shows again", function()
    local T = boot()
    local M = T.ns.MinimapButton
    local b = button(T)
    H.eq(M.create(), b)
    T.ns.Controller.setMinimapHidden(true)
    H.eq(b.shown, false)
    T.ns.Controller.setMinimapHidden(false)
    H.eq(b.shown, true)
    local count = 0
    for _, f in ipairs(T.made) do if f.name == "CraftProfitMinimapButton" then count = count + 1 end end
    H.eq(count, 1)
end)

H.test("a button hidden at login is created the first time it is shown", function()
    local T = boot({ settings = { minimap = { hide = true, angle = 180 } } })
    T.ns.Controller.setMinimapHidden(false)
    local b = button(T)
    H.truthy(b)
    H.eq(b.shown, true)
    nearPair(b.point[4], b.point[5], -75, 0)
end)

H.test("without a minimap nothing is created and nothing raises", function()
    local T = boot(nil, { noLogin = true })
    T.env.Minimap = nil
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    H.eq(button(T), nil)
    T.ns.Controller.setMinimapHidden(false)
    H.eq(button(T), nil)
end)

H.test("left click toggles the options window, right click the main window", function()
    local T = boot()
    local b = button(T)
    b.scripts.OnMouseDown(b, "LeftButton")
    b.scripts.OnClick(b, "LeftButton")
    H.truthy(T.ns.OptionsUI.isShown())
    b.scripts.OnClick(b, "LeftButton")
    H.falsy(T.ns.OptionsUI.isShown())
    b.scripts.OnClick(b, "RightButton")
    H.truthy(T.ns.Window.isShown())
    b.scripts.OnClick(b, "RightButton")
    H.falsy(T.ns.Window.isShown())
end)

H.test("a drag moves the button with the cursor, saves the angle, and its release does not click", function()
    local T = boot()
    local b = button(T)
    b.scripts.OnMouseDown(b, "LeftButton")
    b.scripts.OnDragStart(b)
    H.eq(type(b.scripts.OnUpdate), "function")
    -- Cursor to the left of the minimap centre (1000, 600).
    T.cursor = { 900, 600 }
    b.scripts.OnUpdate(b)
    nearPair(b.point[4], b.point[5], -75, 0)
    b.scripts.OnDragStop(b)
    H.eq(b.scripts.OnUpdate, nil)
    H.eq(T.env.CraftProfitDB.settings.minimap.angle, 180)
    b.scripts.OnClick(b, "LeftButton")
    H.falsy(T.ns.OptionsUI.isShown())
    -- The next press clicks again.
    b.scripts.OnMouseDown(b, "LeftButton")
    b.scripts.OnClick(b, "LeftButton")
    H.truthy(T.ns.OptionsUI.isShown())
end)

H.test("a drag whose mouse-up never arrives stops on the next frame", function()
    local T = boot()
    local b = button(T)
    b.scripts.OnDragStart(b)
    T.env.IsMouseButtonDown = function() return false end
    T.cursor = { 1000, 500 }
    b.scripts.OnUpdate(b)
    H.eq(b.scripts.OnUpdate, nil)
    H.eq(T.env.CraftProfitDB.settings.minimap.angle, 270)
end)

H.test("hiding the button mid-drag ends the drag", function()
    local T = boot()
    local b = button(T)
    b.scripts.OnDragStart(b)
    H.eq(type(b.scripts.OnUpdate), "function")
    T.cursor = { 1100, 600 }
    b.scripts.OnUpdate(b)
    T.ns.Controller.setMinimapHidden(true)
    -- The fake Hide does not run OnHide: the client does.
    b.scripts.OnHide(b)
    H.eq(b.scripts.OnUpdate, nil)
    H.eq(b.dragging, false)
    H.eq(T.env.CraftProfitDB.settings.minimap.angle, 0)
    -- A later hide (no drag running) changes nothing.
    T.env.CraftProfitDB.settings.minimap.angle = 90
    b.scripts.OnHide(b)
    H.eq(T.env.CraftProfitDB.settings.minimap.angle, 90)
end)

H.test("the background and the icon sit in the middle of the button, as LibDBIcon does", function()
    local T = boot()
    local b = button(T)
    local byPath = {}
    for _, tex in ipairs(T.textures) do
        if rawget(tex, "path") then byPath[tex.path] = tex end
    end
    local background = byPath["Interface\\Minimap\\UI-Minimap-Background"]
    local ring = byPath["Interface\\Minimap\\MiniMap-TrackingBorder"]
    H.eq(background.size, { 24, 24 })
    H.eq(background.point, { "CENTER", b, "CENTER", 0, 1 })
    H.eq(b.icon.size, { 18, 18 })
    H.eq(b.icon.point, { "CENTER", b, "CENTER", 0, 1 })
    H.eq(ring.size, { 50, 50 })
    H.eq(ring.point, { "TOPLEFT", b, "TOPLEFT", 0, 0 })
end)

H.test("the tooltip names the addon and the three gestures, and hides on leave", function()
    local T = boot()
    local b = button(T)
    b.scripts.OnEnter(b)
    H.eq(T.tooltip.owner, b)
    H.eq(T.tooltip.title, "CraftProfit")
    H.eq(T.tooltip.lines, { "Left click: options", "Right click: main window", "Drag: move this button" })
    H.eq(T.tooltip.shown, true)
    b.scripts.OnLeave(b)
    H.eq(T.tooltip.shown, false)
    -- No tooltip helpers: no error.
    T.env.GameTooltip = nil
    b.scripts.OnEnter(b)
    b.scripts.OnLeave(b)
end)

-- Slash command and compartment ------------------------------------------------------

H.test("/cp minimap hides and shows the button, saves it and says so in one line", function()
    local T = boot()
    local slash = T.env.SlashCmdList.CRAFTPROFIT
    local b = button(T)
    slash("minimap")
    H.eq(b.shown, false)
    H.eq(T.env.CraftProfitDB.settings.minimap.hide, true)
    H.eq(#T.chat, 1)
    H.truthy(T.chat[1]:find("hidden", 1, true))
    slash("MINIMAP")
    H.eq(b.shown, true)
    H.eq(T.env.CraftProfitDB.settings.minimap.hide, false)
    H.eq(#T.chat, 2)
    H.truthy(T.chat[2]:find("shown", 1, true))
end)

H.test("/cp minimap answers in French", function()
    local T = W.boot(H, { locale = "frFR" })
    T.env.Minimap = nil
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    T.env.SlashCmdList.CRAFTPROFIT("minimap")
    H.truthy(T.chat[#T.chat]:find("minicarte", 1, true))
end)

H.test("the compartment entry toggles options on left click and the main window on right click", function()
    local T = boot()
    local click = T.env.CraftProfit_OnCompartmentClick
    H.eq(type(click), "function")
    click("CraftProfit", "LeftButton")
    H.truthy(T.ns.OptionsUI.isShown())
    click("CraftProfit", "LeftButton")
    H.falsy(T.ns.OptionsUI.isShown())
    click("CraftProfit", "RightButton")
    H.truthy(T.ns.Window.isShown())
    click("CraftProfit", "RightButton")
    H.falsy(T.ns.Window.isShown())
end)

H.test("the compartment entry does nothing before the addon is loaded", function()
    local T = boot(nil, { noLogin = true })
    T.env.CraftProfit_OnCompartmentClick("CraftProfit", "LeftButton")
    H.eq(T.ns.OptionsUI.frame(), nil)
end)

H.test("the TOC declares the compartment function and the coin icon, and loads the button", function()
    local f = assert(io.open("CraftProfit/CraftProfit.toc"))
    local text = f:read("*a")
    f:close()
    H.truthy(text:find("## AddonCompartmentFunc: CraftProfit_OnCompartmentClick", 1, true))
    H.truthy(text:find("## IconTexture: Interface\\Icons\\INV_Misc_Coin_01", 1, true))
    H.truthy(text:find("UI/MinimapButton.lua", 1, true))
end)
