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

H.test("the profession window check shows the saved row tags setting and saves the change at once", function()
    local T, _, slash = boot({ settings = { showRowTags = false } })
    local repaints = 0
    T.ns.RecipeRows = { refresh = function() repaints = repaints + 1 end }
    slash("options")
    local parts = T.ns.OptionsUI.parts
    local check = parts.rowTags
    H.eq(parts.panels.profession.title.text, "PROFESSION WINDOW")
    H.eq(check.checked, false)
    H.eq(check.label.text, "Show the profit on each recipe of the list")
    H.eq(check.point, { "TOPLEFT", parts.panels.profession.body, "TOPLEFT", 4, -1 })
    H.eq(parts.panels.profession.frame.height, T.ns.Layout.panelHeight(1, 26))
    check:SetChecked(true)
    click(check)
    H.eq(T.env.CraftProfitDB.settings.showRowTags, true)
    H.truthy(T.ns.Controller.showRowTags())
    H.truthy(repaints >= 1)
    local before = repaints
    check:SetChecked(false)
    click(check)
    H.eq(T.env.CraftProfitDB.settings.showRowTags, false)
    H.falsy(T.ns.Controller.showRowTags())
    H.truthy(repaints > before)
    -- A change made elsewhere shows at the next refresh.
    T.ns.Controller.setShowRowTags(true)
    H.eq(check.checked, true)
end)

H.test("the check box labels fit the panel in English, French and Spanish", function()
    local expected = {
        enUS = { "PROFESSION WINDOW", "Show the profit on each recipe of the list" },
        frFR = { "FENÊTRE DE MÉTIER", "Afficher le profit de chaque recette de la liste" },
        esES = { "VENTANA DE PROFESIÓN", "Mostrar el beneficio de cada receta de la lista" },
    }
    for _, locale in ipairs({ "enUS", "frFR", "esES" }) do
        local T, _, slash = boot(nil, locale)
        slash("options")
        local O, Layout, Native = T.ns.OptionsUI, T.ns.Layout, T.ns.Native
        local parts = O.parts
        H.eq(parts.panels.profession.title.text, expected[locale][1])
        H.eq(parts.rowTags.label.text, expected[locale][2])
        local room = O.ROOM - Native.CHECK_SIZE - Native.CHECK_LABEL_X
        for _, check in ipairs({ parts.rowTags, parts.minimap }) do
            local need = Layout.textWidth(check.label.text, O.SMALL_CHAR_W)
            H.truthy(need <= room or error(locale .. ": " .. check.label.text .. " needs " .. need .. " px"))
        end
    end
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
    H.eq(parts.historyButton.text, "History")
    H.falsy(T.ns.HistoryWindow.isShown())
    click(parts.historyButton)
    H.truthy(T.ns.HistoryWindow.isShown())
    click(parts.historyButton)
    H.falsy(T.ns.HistoryWindow.isShown())
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

H.test("the window buttons: two rows of two, main and leveling, then pinned recipes and history", function()
    local T, sizes = sized("frFR")
    local O = T.ns.OptionsUI
    local parts = O.parts
    local main, level, pins, history = parts.mainButton, parts.levelButton, parts.pinsButton, parts.historyButton
    H.eq(main.text, "Fenêtre principale")
    H.eq(level.text, "Montée de métier")
    H.eq(pins.text, "Recettes épinglées")
    H.eq(history.text, "Historique")
    local half = math.floor((O.ROOM - 4) / 2)
    for _, b in ipairs({ main, level, pins, history }) do H.eq(sizes[b], { half, 22 }) end
    H.eq(main.point, { "TOPLEFT", parts.panels.windows.body, "TOPLEFT", 8, -2 })
    H.eq(level.point, { "LEFT", main, "RIGHT", 4, 0 })
    H.eq(pins.point, { "TOPLEFT", parts.panels.windows.body, "TOPLEFT", 8, -2 - 26 })
    H.eq(history.point, { "LEFT", pins, "RIGHT", 4, 0 })
    -- Two rows of 26 px in the panel.
    H.eq(parts.panels.windows.frame.height, T.ns.Layout.panelHeight(2, 26))
end)

H.test("every options button label fits its button in English, French and Spanish", function()
    for _, locale in ipairs({ "enUS", "frFR", "esES" }) do
        local T, sizes = sized(locale)
        local O, Layout = T.ns.OptionsUI, T.ns.Layout
        local parts = O.parts
        local buttons = { parts.mainButton, parts.levelButton, parts.pinsButton, parts.historyButton }
        for _, b in pairs(parts.headerButtons) do buttons[#buttons + 1] = b end
        for _, b in pairs(parts.tileButtons) do buttons[#buttons + 1] = b end
        for _, b in pairs(parts.pinButtons) do buttons[#buttons + 1] = b end
        for _, b in ipairs(buttons) do
            -- The label keeps 8 px from each end of the button.
            local need = Layout.textWidth(b.text, O.CHAR_W)
            H.truthy(need <= sizes[b][1] - 16 or error(locale .. ": " .. b.text .. " needs " .. need
                .. " px, has " .. (sizes[b][1] - 16)))
        end
    end
end)

-- A line's text without its colour escapes.
local function plain(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local EXPECTED_LINES = {
    "Minimap left click - this window",
    "Minimap right click - pinned recipes",
    "/cp show - open the main window",
    "/cp hide - close the main window",
    "/cp reset - put the main window back",
    "/cp options - this window",
    "/cp pins - pinned recipes",
    "/cp level - leveling window",
    "/cp minimap - show or hide the minimap button",
    "/cp history [n | list | remove <n>] - price history window",
    "/cp scan - scan the auction house",
    "/cp market - which market is in use",
    "/cp locale <code> - change the language",
    "/cp selftest - run the self-test",
}

H.test("the controls panel lists the clicks and the commands, one per line, command in gold", function()
    local T, _, slash = boot()
    slash("options")
    local O, Colors = T.ns.OptionsUI, T.ns.Colors
    local lines = O.parts.lines
    H.eq(#lines, #EXPECTED_LINES)
    H.eq(O.LINE_COUNT, #EXPECTED_LINES)
    for i, fs in ipairs(lines) do
        H.eq(plain(fs.text), EXPECTED_LINES[i])
        -- The command (or click) in the game's gold, the description in white.
        local gold, white = Colors.escape(Colors.text("gold")), Colors.escape(Colors.text("main"))
        H.eq(fs.text:sub(1, #gold), gold)
        H.truthy(fs.text:find("|r" .. white .. " - ", 1, true))
    end
end)

H.test("each command line is one line of 14 px across the panel, cut rather than wrapped", function()
    local T = W.boot(H, {})
    T.env.UISpecialFrames = {}
    local create = T.env.CreateFrame
    T.env.CreateFrame = function(...)
        local f = create(...)
        f.CreateFontString = function()
            local fs = W.frame()
            fs.SetWidth = function(self, w) self.width = w end
            fs.SetHeight = function(self, h) self.height = h end
            fs.SetWordWrap = function(self, v) self.wrap = v end
            fs.SetPoint = function(self, ...) self.point = { ... } end
            return fs
        end
        return f
    end
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    T.env.SlashCmdList.CRAFTPROFIT("options")
    local O = T.ns.OptionsUI
    local body = O.parts.panels.controls.body
    for i, fs in ipairs(O.parts.lines) do
        H.eq(fs.width, O.ROOM)
        H.eq(fs.height, 14)
        H.eq(fs.wrap, false)
        H.eq(fs.point, { "TOPLEFT", body, "TOPLEFT", 8, -(i - 1) * 14 })
    end
end)

H.test("the controls panel and the window heights follow the line count", function()
    local T, _, slash = boot()
    slash("options")
    local O, Layout, Native = T.ns.OptionsUI, T.ns.Layout, T.ns.Native
    local p = O.parts.panels
    -- 8 px of air under the last line.
    H.eq(O.LIST_BOTTOM, 8)
    H.eq(p.controls.frame.height, Layout.panelHeight(O.LINE_COUNT, 14, 8))
    local heights = p.appearance.frame.height + p.pins.frame.height + p.minimap.frame.height
        + p.profession.frame.height + p.windows.frame.height + p.controls.frame.height
    H.eq(O.frame():GetHeight(), Native.INSET_TOP + Native.INSET_BOTTOM + Native.CONTENT_PAD * 2 + heights + 8 * 5)
end)

H.test("the command lines are translated and fit the panel in English, French and Spanish", function()
    for _, locale in ipairs({ "enUS", "frFR", "esES" }) do
        local T, _, slash = boot(nil, locale)
        slash("options")
        local O, Layout = T.ns.OptionsUI, T.ns.Layout
        for _, fs in ipairs(O.parts.lines) do
            local text = plain(fs.text)
            H.truthy(text ~= "" and not text:find("CMD_", 1, true))
            local need = Layout.textWidth(text, O.SMALL_CHAR_W)
            H.truthy(need <= O.ROOM or error(locale .. ": " .. text .. " needs " .. need .. " px"))
        end
        if locale == "frFR" then
            H.eq(plain(O.parts.lines[7].text), "/cp pins - recettes épinglées")
            H.eq(plain(O.parts.lines[10].text), "/cp history [n | list | remove <n>] - historique des prix")
        end
    end
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


H.test("the pinned recipes panel lights the saved limit and saves a click at once", function()
    local T, _, slash = boot({ settings = { maxPins = 30 } })
    slash("options")
    local parts = T.ns.OptionsUI.parts
    H.eq(parts.panels.pins.title.text, "PINNED RECIPES")
    H.eq(parts.pinLabel.text, "Limit per character")
    H.eq(lit(parts.pinButtons), "30")
    for _, n in ipairs({ 12, 20, 30, 40 }) do H.eq(parts.pinButtons[n].text, tostring(n)) end
    click(parts.pinButtons[12])
    H.eq(lit(parts.pinButtons), "12")
    H.eq(T.env.CraftProfitDB.settings.maxPins, 12)
    H.eq(T.ns.Controller.pinLimit(), 12)
    click(parts.pinButtons[40])
    H.eq(lit(parts.pinButtons), "40")
    H.eq(T.env.CraftProfitDB.settings.maxPins, 40)
    -- The four buttons share the row like the appearance choices.
    local width = math.floor((T.ns.OptionsUI.ROOM - 4 * 3) / 4)
    H.eq(parts.pinButtons[12].point, { "TOPLEFT", parts.panels.pins.body, "TOPLEFT", 8, -16 })
    H.eq(parts.pinButtons[40].point, { "TOPLEFT", parts.panels.pins.body, "TOPLEFT", 8 + 3 * (width + 4), -16 })
end)

H.test("the lit limit follows a change made while the window was closed, at each open", function()
    local T, _, slash = boot()
    slash("options")
    local parts = T.ns.OptionsUI.parts
    H.eq(lit(parts.pinButtons), "20")
    slash("options")
    T.ns.Controller.setPinLimit(40)
    slash("options")
    H.eq(lit(parts.pinButtons), "40")
    -- And while it is open.
    T.ns.Controller.setPinLimit(12)
    H.eq(lit(parts.pinButtons), "12")
end)

-- Lines of `text` wrapped greedily at word boundaries into `width` px at `charW` per letter.
local function wrappedLines(Layout, text, charW, width)
    local lines, line = 0, nil
    for word in text:gmatch("%S+") do
        local candidate = line and (line .. " " .. word) or word
        if line and Layout.textWidth(candidate, charW) > width then
            lines, line = lines + 1, word
        else
            line = candidate
        end
    end
    if line then lines = lines + 1 end
    return lines
end

H.test("the note under the limits says how slow a search gets and points to Scan AH, in three lines at most", function()
    local expected = {
        enUS = "A higher limit makes Refresh pinned slower: it searches the auction house one item at a time "
            .. "(about a minute for 20 recipes). With many recipes, Scan AH is usually faster.",
        frFR = "Plus la limite est haute, plus Actualiser épinglées est long : un objet à la fois (environ une "
            .. "minute pour 20 recettes). Avec beaucoup de recettes, Scanner l'HV va souvent plus vite.",
        esES = "Un límite más alto ralentiza Actualizar fijadas, que consulta objeto por objeto (cerca de un minuto "
            .. "para 20 recetas). Con muchas recetas, Escanear CS suele ser más rápido.",
    }
    for _, locale in ipairs({ "enUS", "frFR", "esES" }) do
        local T, _, slash = boot(nil, locale)
        slash("options")
        local O, Layout = T.ns.OptionsUI, T.ns.Layout
        local note = O.parts.pinNote
        H.eq(note.text, expected[locale])
        local lines = wrappedLines(Layout, note.text, O.SMALL_CHAR_W, O.ROOM)
        H.truthy(lines <= O.NOTE_MAX_LINES or error(locale .. ": the note takes " .. lines .. " lines"))
        H.eq(O.NOTE_MAX_LINES, 3)
        -- The note names the two buttons as they read in that language.
        H.truthy(note.text:find(T.ns.L.SEARCH_PRICES, 1, true))
        H.truthy(note.text:find(T.ns.L.SCAN, 1, true))
        -- Without a measure from the client, the panel is sized from the estimate.
        H.eq(O.noteLines(), lines)
        H.eq(O.parts.panels.pins.frame.height,
            Layout.panelHeight(1, 14 + 2 + T.ns.Native.BUTTON_H + 4, lines * 14 + O.LIST_BOTTOM))
        -- The label above the buttons fits on its line too.
        local need = Layout.textWidth(O.parts.pinLabel.text, O.SMALL_CHAR_W)
        H.truthy(need <= O.ROOM or error(locale .. ": " .. O.parts.pinLabel.text .. " needs " .. need .. " px"))
    end
end)

H.test("the note is the small font across the panel, under the buttons, as tall as its measured lines", function()
    local measured
    local T = W.boot(H, {})
    T.env.UISpecialFrames = {}
    local create = T.env.CreateFrame
    T.env.CreateFrame = function(...)
        local f = create(...)
        f.CreateFontString = function(_, _, _, font)
            local fs = W.frame()
            fs.font = font
            fs.SetWidth = function(self, w) self.width = w end
            fs.SetHeight = function(self, h) self.height = h end
            fs.SetWordWrap = function(self, v) self.wrap = v end
            fs.SetPoint = function(self, ...) self.point = { ... } end
            fs.SetMaxLines = function(self, n) self.maxLines = n end
            fs.GetNumLines = function() return measured end
            return fs
        end
        return f
    end
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    measured = 2
    T.env.SlashCmdList.CRAFTPROFIT("options")
    local O, Layout, Native = T.ns.OptionsUI, T.ns.Layout, T.ns.Native
    local note, panel = O.parts.pinNote, O.parts.panels.pins
    local rowH = 14 + 2 + Native.BUTTON_H + 4
    H.eq(note.font, "GameFontHighlightSmall")
    H.eq(note.width, O.ROOM)
    H.eq(note.wrap, true)
    H.eq(note.maxLines, 3)
    -- Under the label (14), its gap (2), the buttons and their gap (4).
    H.eq(note.point, { "TOPLEFT", panel.body, "TOPLEFT", 8, -rowH })
    -- The client's measure wins: two lines.
    H.eq(note.height, 2 * 14)
    H.eq(panel.frame.height, Layout.panelHeight(1, rowH, 2 * 14 + O.LIST_BOTTOM))
    local function windowHeight()
        local p = O.parts.panels
        local sum = 0
        for _, k in ipairs({ "appearance", "pins", "minimap", "profession", "windows", "controls" }) do
            sum = sum + p[k].frame.height
        end
        return Native.INSET_TOP + Native.INSET_BOTTOM + Native.CONTENT_PAD * 2 + sum + 8 * 5
    end
    H.eq(O.frame():GetHeight(), windowHeight())
    local twoLines = O.frame():GetHeight()
    -- Three measured lines: the panel and the window grow by one line.
    measured = 3
    O.refresh()
    H.eq(note.height, 3 * 14)
    H.eq(panel.frame.height, Layout.panelHeight(1, rowH, 3 * 14 + O.LIST_BOTTOM))
    H.eq(O.frame():GetHeight(), twoLines + 14)
    -- More than three is capped (the text is cut by SetMaxLines); 0 or junk falls back to the
    -- estimate.
    measured = 5
    O.refresh()
    H.eq(note.height, 3 * 14)
    measured = 0
    O.refresh()
    H.eq(O.noteLines(), Layout.wrapLines(note.text, O.SMALL_CHAR_W, O.ROOM))
    measured = 0 / 0
    O.refresh()
    H.eq(O.noteLines(), Layout.wrapLines(note.text, O.SMALL_CHAR_W, O.ROOM))
end)

H.test("the options window shrinks to fit a short screen, and stays at full size otherwise", function()
    local T, _, slash = boot()
    local scales = {}
    local create = T.env.CreateFrame
    T.env.CreateFrame = function(...)
        local f = create(...)
        f.SetScale = function(self, v) scales[#scales + 1] = v; self.scale = v end
        return f
    end
    T.env.UIParent.GetHeight = function() return 400 end
    slash("options")
    local f = T.ns.OptionsUI.frame()
    local h = f:GetHeight()
    H.truthy(h > 380)
    H.eq(f.scale, 380 / h)
    T.env.UIParent.GetHeight = function() return 2000 end
    slash("options")
    slash("options")
    H.eq(f.scale, 1)
end)
