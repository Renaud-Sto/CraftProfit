local H = ...
local W = dofile("tests/fakewow.lua")

-- Boots the addon with frames that start shown (as on the client), records named frames
-- and the anchors given to them. `saved`: CraftProfitDB before login.
local function boot(saved, locale)
    local T = W.boot(H, { locale = locale })
    T.env.CraftProfitDB = saved
    T.env.UISpecialFrames = {}
    local named = {}
    local create = T.env.CreateFrame
    T.env.CreateFrame = function(kind, name, parent, template)
        local f = create(kind, name, parent, template)
        f.shown = true
        f.SetPoint = function(self, ...) self.point = { ... } end
        f.LockHighlight = function(self) self.locked = true end
        f.UnlockHighlight = function(self) self.locked = false end
        if name then named[name] = f end
        return f
    end
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    return T, named, T.env.SlashCmdList.CRAFTPROFIT
end

local function click(button) button.scripts.OnClick(button) end

local function lit(buttons)
    local keys = {}
    for key, button in pairs(buttons) do
        H.eq(button.locked, button.lit)
        if button.lit then keys[#keys + 1] = key end
    end
    table.sort(keys)
    return table.concat(keys, ",")
end

H.test("the options window is not built at login, only on first open", function()
    local T, named, slash = boot()
    H.eq(named.CraftProfitOptionsWindow, nil)
    H.eq(T.ns.OptionsUI.frame(), nil)
    H.falsy(T.ns.OptionsUI.isShown())
    slash("options")
    local f = named.CraftProfitOptionsWindow
    H.truthy(f)
    H.eq(T.ns.OptionsUI.frame(), f)
    H.truthy(T.ns.OptionsUI.isShown())
    H.eq(f.titleText.text, "CraftProfit options")
end)

H.test("/cp options toggles the window and Escape is registered once", function()
    local T, named, slash = boot()
    slash("options")
    slash("OPTIONS")
    H.eq(named.CraftProfitOptionsWindow.shown, false)
    slash("options")
    H.eq(named.CraftProfitOptionsWindow.shown, true)
    T.ns.OptionsUI.toggle()
    H.falsy(T.ns.OptionsUI.isShown())
    T.ns.OptionsUI.show()
    H.truthy(T.ns.OptionsUI.isShown())
    T.ns.OptionsUI.hide()
    H.falsy(T.ns.OptionsUI.isShown())
    H.eq(T.env.UISpecialFrames, { "CraftProfitOptionsWindow" })
end)

H.test("the segmented buttons light the saved choice and set it on a click", function()
    local T, _, slash = boot({ settings = { appearance = { header = "c", tile = "a" } } })
    T.env.C_Texture = { GetAtlasInfo = function() return { width = 100, height = 4 } end }
    slash("options")
    local parts = T.ns.OptionsUI.parts
    H.eq(parts.panels.appearance.headerAtlas, T.ns.Native.HEADER_VARIANTS.c)
    H.eq(lit(parts.headerButtons), "c")
    H.eq(lit(parts.tileButtons), "a")
    H.eq(parts.headerButtons.a.text, "Carved wood")
    H.eq(parts.headerButtons.b.text, "Shade")
    H.eq(parts.headerButtons.c.text, "Streaks")
    H.eq(parts.tileButtons.a.text, "Loot card")
    H.eq(parts.tileButtons.b.text, "Inset")
    click(parts.headerButtons.a)
    H.eq(lit(parts.headerButtons), "a")
    H.eq(T.env.CraftProfitDB.settings.appearance, { header = "a", tile = "a" })
    H.eq({ T.ns.Native.appearance() }, { "a", "a" })
    click(parts.tileButtons.b)
    H.eq(lit(parts.tileButtons), "b")
    H.eq(T.env.CraftProfitDB.settings.appearance, { header = "a", tile = "b" })
    -- The options window's own panels follow the switch.
    H.eq(parts.panels.appearance.headerAtlas, T.ns.Native.HEADER_VARIANTS.a)
    H.eq(parts.panels.controls.headerAtlas, T.ns.Native.HEADER_VARIANTS.a)
end)

H.test("the lit buttons follow a choice made while the window was closed", function()
    local T, _, slash = boot()
    slash("options")
    slash("options")
    T.ns.Controller.setAppearance("b", "a")
    slash("options")
    local parts = T.ns.OptionsUI.parts
    H.eq(lit(parts.headerButtons), "b")
    H.eq(lit(parts.tileButtons), "a")
end)

H.test("the minimap check shows the saved state and saves the change through the controller", function()
    local T, _, slash = boot({ settings = { minimap = { hide = true, angle = 10 } } })
    local applied = 0
    T.ns.MinimapButton = { apply = function() applied = applied + 1 end }
    slash("options")
    local check = T.ns.OptionsUI.parts.minimap
    H.eq(check.checked, false)
    H.eq(check.label.text, "Show the minimap button")
    check:SetChecked(true)
    click(check)
    H.eq(T.env.CraftProfitDB.settings.minimap, { hide = false, angle = 10 })
    H.eq(applied, 1)
    check:SetChecked(false)
    click(check)
    H.eq(T.env.CraftProfitDB.settings.minimap.hide, true)
    H.eq(applied, 2)
    -- Without the button module: saved, no error.
    T.ns.MinimapButton = nil
    check:SetChecked(true)
    click(check)
    H.eq(T.env.CraftProfitDB.settings.minimap.hide, false)
end)

H.test("the window buttons toggle the main window, the leveling window and the pinned window", function()
    local T, _, slash = boot()
    slash("options")
    local parts = T.ns.OptionsUI.parts
    H.eq(parts.mainButton.text, "Main window")
    H.eq(parts.levelButton.text, "Leveling")
    H.falsy(T.ns.Window.isShown())
    click(parts.mainButton)
    H.truthy(T.ns.Window.isShown())
    click(parts.mainButton)
    H.falsy(T.ns.Window.isShown())
    local toggles = 0
    T.ns.LevelingUI.toggle = function() toggles = toggles + 1 end
    click(parts.levelButton)
    H.eq(toggles, 1)
    H.eq(parts.pinsButton.text, "Pinned recipes")
    H.falsy(T.ns.PinnedWindow.isShown())
    click(parts.pinsButton)
    H.truthy(T.ns.PinnedWindow.isShown())
    click(parts.pinsButton)
    H.falsy(T.ns.PinnedWindow.isShown())
end)

-- Boots in `locale`, opens the options window and records every button's size.
local function sized(locale)
    local T, _, slash = boot(nil, locale)
    local sizes = {}
    local create = T.env.CreateFrame
    T.env.CreateFrame = function(...)
        local f = create(...)
        f.SetSize = function(self, w, h) sizes[self] = { w, h } end
        return f
    end
    slash("options")
    return T, sizes
end

H.test("the window buttons: main and leveling on a first row, pinned recipes centred under them", function()
    local T, sizes = sized("frFR")
    local O = T.ns.OptionsUI
    local parts = O.parts
    local main, level, pins = parts.mainButton, parts.levelButton, parts.pinsButton
    H.eq(main.text, "Fenêtre principale")
    H.eq(level.text, "Montée de métier")
    H.eq(pins.text, "Recettes épinglées")
    local half = math.floor((O.ROOM - 4) / 2)
    for _, b in ipairs({ main, level, pins }) do H.eq(sizes[b], { half, 22 }) end
    H.eq(main.point, { "TOPLEFT", parts.panels.windows.body, "TOPLEFT", 8, -2 })
    H.eq(level.point, { "LEFT", main, "RIGHT", 4, 0 })
    H.eq(pins.point, { "TOP", parts.panels.windows.body, "TOP", 0, -2 - 26 })
    -- Two rows of 26 px in the panel.
    H.eq(parts.panels.windows.frame.height, T.ns.Layout.panelHeight(2, 26))
end)

H.test("every options button label fits its button in English, French and Spanish", function()
    for _, locale in ipairs({ "enUS", "frFR", "esES" }) do
        local T, sizes = sized(locale)
        local O, Layout = T.ns.OptionsUI, T.ns.Layout
        local parts = O.parts
        local buttons = { parts.mainButton, parts.levelButton, parts.pinsButton }
        for _, b in pairs(parts.headerButtons) do buttons[#buttons + 1] = b end
        for _, b in pairs(parts.tileButtons) do buttons[#buttons + 1] = b end
        for _, b in ipairs(buttons) do
            -- The label keeps 8 px from each end of the button.
            local need = Layout.textWidth(b.text, O.CHAR_W)
            H.truthy(need <= sizes[b][1] - 16 or error(locale .. ": " .. b.text .. " needs " .. need
                .. " px, has " .. (sizes[b][1] - 16)))
        end
    end
end)

H.test("the controls recap names the clicks and the commands, wrapped in the small font", function()
    local T, _, slash = boot()
    slash("options")
    local recap = T.ns.OptionsUI.parts.recap
    H.truthy(recap.text:find("left click options, right click pinned recipes", 1, true))
    H.truthy(recap.text:find("/cp show, hide, options, pins, level, minimap", 1, true))
    H.falsy(recap.text:find("main window", 1, true))
    -- The window grows with the recap (measured by the client; a fallback here).
    H.truthy(T.ns.OptionsUI.frame():GetHeight() > 200)
end)

H.test("a drag saves the position and the next login opens it there", function()
    local T, named, slash = boot()
    slash("options")
    local f = named.CraftProfitOptionsWindow
    H.eq(f.point, { "CENTER", T.env.UIParent, "CENTER", 0, 0 })
    f.scripts.OnDragStop(f)
    H.eq(T.env.CraftProfitDB.settings.optionsWindow, { x = 100, y = 700 })
    slash("options")
    slash("options")
    H.eq(f.point, { "TOPLEFT", T.env.UIParent, "BOTTOMLEFT", 100, 700 })

    local T2, named2, slash2 = boot({ settings = { optionsWindow = { x = 40, y = 500 } } })
    slash2("options")
    H.eq(named2.CraftProfitOptionsWindow.point, { "TOPLEFT", T2.env.UIParent, "BOTTOMLEFT", 40, 500 })
end)

H.test("a language switch relabels the open options window", function()
    local T, named, slash = boot(nil, "frFR")
    slash("options")
    H.eq(named.CraftProfitOptionsWindow.titleText.text, "Options de CraftProfit")
    H.eq(T.ns.OptionsUI.parts.headerButtons.a.text, "Bois sculpté")
    slash("locale enUS")
    H.eq(named.CraftProfitOptionsWindow.titleText.text, "CraftProfit options")
    H.eq(T.ns.OptionsUI.parts.panels.controls.title.text, "CONTROLS")
end)

H.test("the minimap check follows /cp minimap while the window is open", function()
    local T, _, slash = boot()
    slash("options")
    local check = T.ns.OptionsUI.parts.minimap
    H.eq(check.checked, true)
    slash("minimap")
    H.eq(check.checked, false)
    slash("minimap")
    H.eq(check.checked, true)
end)

