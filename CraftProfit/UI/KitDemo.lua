-- Developer tool: /cp kitdemo [header [tile]] shows the native widgets (UI/Native.lua) with
-- a choice of header strip (a|b|c) and tile background (a|b), to pick them in the game;
-- /cp kitdemo old [theme] shows the themed Kit widgets as before. English only, not part of
-- the user-facing help.
local _, ns = ...
local Kit, Theme, Native = ns.Kit, ns.Theme, ns.Native

local KitDemo = {}
ns.KitDemo = KitDemo

local WIDTH = 372
local TILE_H = 52
-- The themed demo (/cp kitdemo old).
local frame

local function addRow(panel, index, left, right)
    local y = -(index - 1) * 18
    local a = panel.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    a:SetPoint("TOPLEFT", panel.body, "TOPLEFT", 8, y)
    a:SetText(left)
    local b = panel.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b:SetPoint("TOPRIGHT", panel.body, "TOPRIGHT", -8, y)
    b:SetText(right)
end

local function build()
    frame = Kit.window("CraftProfitKitDemo", "Kit demo", { width = WIDTH })
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    local content = frame.content

    local tileW = math.floor((WIDTH - Kit.CONTENT_SIDE * 2 - 16) / 3)
    local specs = {
        { label = "AH (NET)", value = "3g 24s", best = true },
        { label = "VENDOR", value = "1g 12s" },
        { label = "DISENCH.", tag = "beta", value = "999g 99s 99c" },
    }
    for i, spec in ipairs(specs) do
        local tile = Kit.tile(content, tileW, TILE_H)
        tile.frame:SetPoint("TOPLEFT", content, "TOPLEFT", (i - 1) * (tileW + 8), 0)
        tile:set(spec)
    end

    local materials = Kit.panel(content, "MATERIALS")
    materials:setRows(3, 18)
    materials.right:SetText("2g 33s")
    addRow(materials, 1, "3x Bronze Bar", "2g 25s")
    addRow(materials, 2, "1x Coarse Weightstone", "8s")
    addRow(materials, 3, "1x Heavy Leather", "10s")

    -- Three buttons of one size, centred in the body; the small kind lives in the
    -- header, where a sort button belongs.
    local options = Kit.panel(content, "OPTIONS")
    options:setRows(1, 24, 12)
    local x = 8
    for _, spec in ipairs({ { "primary", "Search prices" }, { "normal", "Scan AH" }, { "normal", "Reset" } }) do
        local button = Kit.button(options.body, spec[1], spec[2])
        button:SetWidth(104)
        button:SetPoint("TOPLEFT", options.body, "TOPLEFT", x, -6)
        x = x + 112
    end
    local sort = Kit.button(options.frame, "small", "Sort")
    sort:SetWidth(50)
    sort:SetPoint("TOPRIGHT", options.frame, "TOPRIGHT", -6, -3)

    local controls = Kit.panel(content, "CONTROLS")
    controls:setRows(1, 26)
    local box = Kit.input(controls.body, 52, 4)
    box:SetPoint("TOPLEFT", controls.body, "TOPLEFT", 8, -2)
    box:SetText("1")
    local checkA = Kit.check(controls.body, "Track history")
    checkA:SetPoint("TOPLEFT", controls.body, "TOPLEFT", 90, -4)
    checkA:SetChecked(true)
    local checkB = Kit.check(controls.body, "Per point")
    checkB:SetPoint("TOPLEFT", controls.body, "TOPLEFT", 230, -4)

    local offsets, total = Kit.stack({ TILE_H, materials:height(), options:height(), controls:height() }, Kit.GAP, 0)
    for i, panel in ipairs({ materials, options, controls }) do
        panel.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, offsets[i + 1])
        panel.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, offsets[i + 1])
    end
    frame:SetHeight(total + Kit.CONTENT_TOP + Kit.CONTENT_BOTTOM)
end

-- The themed demo. With a theme name: apply it and show the window. Without: show or hide it.
function KitDemo.showOld(name)
    name = (name or ""):lower()
    if name ~= "" then
        if not Theme.exists(name) then
            DEFAULT_CHAT_FRAME:AddMessage("CraftProfit: unknown theme '" .. name .. "' ("
                .. table.concat(Theme.list(), ", ") .. ")")
            return
        end
        Kit.applyTheme(name)
        if not frame then build() end
        frame:Show()
        return
    end
    if not frame then
        build()
        frame:Show() -- a new client frame is already shown, but do not rely on it
        return
    end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

-- Native demo ---------------------------------------------------------------------

local NATIVE_NAME = "CraftProfitNativeDemo"
local SORT_H = 20
local LINE_H = 16
local DEMO_MONEY = 21 * 10000 + 29 * 100
-- The variants the native demo was last asked for.
KitDemo.header, KitDemo.tile = "a", "a"

local native      -- the window, built once
local page        -- the frame holding the current widgets, rebuilt for each variant
local builtWith   -- "header tile" of `page`

local function say(text)
    DEFAULT_CHAT_FRAME:AddMessage("CraftProfit: " .. text)
end

-- An amount with the game's coin icons when the client formats it, else plain text.
local function moneyText(copper)
    for _, format in ipairs({ GetCoinTextureString, GetMoneyString }) do
        if type(format) == "function" then
            local ok, text = pcall(format, copper)
            if ok and type(text) == "string" then return text end
        end
    end
    return "21g 29s"
end

local function nativeRow(panel, index, left, right)
    local y = -(index - 1) * 18
    local a = panel.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    a:SetPoint("TOPLEFT", panel.body, "TOPLEFT", 8, y)
    a:SetText(left)
    local b = panel.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b:SetPoint("TOPRIGHT", panel.body, "TOPRIGHT", -8, y)
    b:SetText(right)
end

local function buildWindow()
    native = Native.window(NATIVE_NAME, "Native demo", {
        width = WIDTH,
        onTitleClick = function() say("title clicked") end,
    })
    native:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    -- Escape closes it, the game's way for a plain named frame (never UIPanelWindows).
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, NATIVE_NAME) end
end

-- Fills a fresh page with the widgets, drawn with the current variants. Frames cannot be
-- destroyed: the previous page is only hidden.
local function buildPage()
    if page then page:Hide() end
    Native.setHeaderVariant(KitDemo.header)
    Native.setTileVariant(KitDemo.tile)
    local content = native.content
    local pad = Native.CONTENT_PAD
    page = CreateFrame("Frame", nil, content)
    page:SetPoint("TOPLEFT", content, "TOPLEFT", pad, -pad)
    page:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -pad, pad)
    builtWith = KitDemo.header .. " " .. KitDemo.tile

    local inner = WIDTH - Native.INSET_LEFT - Native.INSET_RIGHT - pad * 2
    local tileW = math.floor((inner - 16) / 3)
    local specs = {
        { label = "AH (NET)", value = "3g 24s", best = true },
        { label = "VENDOR", value = "1g 12s" },
        { label = "DISENCH.", tag = "beta", value = "999g 99s 99c", muted = true },
    }
    for i, spec in ipairs(specs) do
        local tile = Native.tile(page, tileW, TILE_H)
        tile.frame:SetPoint("TOPLEFT", page, "TOPLEFT", (i - 1) * (tileW + 8), 0)
        tile:set(spec)
        if i == 1 then
            tile:onClick(function() say("tile clicked") end)
            Native.forwardDrag(tile.hit, native)
            tile:showIcon(true)
        end
    end

    local materials = Native.panel(page, "MATERIALS")
    materials:setRows(3, 18)
    materials.right:SetText("2g 33s")
    nativeRow(materials, 1, "3x Bronze Bar", "2g 25s")
    nativeRow(materials, 2, "1x Coarse Weightstone", "8s")
    nativeRow(materials, 3, "1x Heavy Leather", "10s")

    -- Row 1: the crafts input and a check box; row 2: two buttons, the second disabled.
    -- The sort button sits in the header, 20 px high, centred in its 22 px.
    local options = Native.panel(page, "OPTIONS")
    options:setRows(2, 28)
    local crafts = Native.input(options.body, 40, 4)
    -- The input's border reaches 5 px left of the box.
    crafts:SetPoint("TOPLEFT", options.body, "TOPLEFT", 13, -3)
    crafts:SetText("1")
    local check = Native.check(options.body, "Track history", function(checked)
        say("track history " .. (checked and "on" or "off"))
    end)
    check:SetPoint("TOPLEFT", options.body, "TOPLEFT", 70, -2)
    check:SetChecked(true)
    local search = Native.button(options.body, "Search prices", { width = 120,
        onClick = function() say("search clicked") end })
    search:SetPoint("TOPLEFT", options.body, "TOPLEFT", 8, -31)
    local scan = Native.button(options.body, "Scan AH", { width = 120 })
    scan:SetPoint("LEFT", search, "RIGHT", 6, 0)
    scan:Disable()
    local sort = Native.button(options.frame, "Sort", { width = 50 })
    sort:SetHeight(SORT_H)
    sort:SetPoint("TOPRIGHT", options.frame, "TOPRIGHT", -4, -3)

    local line = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    line:SetText("Best price: " .. moneyText(DEMO_MONEY))

    local offsets, total = Kit.stack({ TILE_H, materials:height(), options:height(), LINE_H }, Kit.GAP, 0)
    for i, panel in ipairs({ materials, options }) do
        panel.frame:SetPoint("TOPLEFT", page, "TOPLEFT", 0, offsets[i + 1])
        panel.frame:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, offsets[i + 1])
    end
    line:SetPoint("TOPLEFT", page, "TOPLEFT", 4, offsets[4])
    -- Window = what lies above the inset + page + its padding + what lies below the inset.
    native:SetHeight(Native.INSET_TOP + total + pad * 2 + Native.INSET_BOTTOM)
end

local function describe()
    say(string.format("kitdemo header %s (%s), tile %s (%s)", KitDemo.header,
        Native.HEADER_VARIANTS[KitDemo.header], KitDemo.tile, Native.TILE_VARIANTS[KitDemo.tile]))
end

-- Shows the native demo with the last variants (rebuilding it when they changed), or hides
-- it when it is shown and `force` is not set.
function KitDemo.showNative(force)
    if not native then buildWindow() end
    if native:IsShown() and not force then
        native:Hide()
        return
    end
    if builtWith ~= KitDemo.header .. " " .. KitDemo.tile then buildPage() end
    native:Show()
    describe()
end

-- /cp kitdemo [header [tile]] | /cp kitdemo old [theme]
function KitDemo.command(arg)
    local words = {}
    for word in (arg or ""):lower():gmatch("%S+") do words[#words + 1] = word end
    if words[1] == "old" then
        KitDemo.showOld(words[2])
        return
    end
    if #words == 0 then
        KitDemo.showNative(false)
        return
    end
    local header, tile = words[1], words[2] or KitDemo.tile
    if #words > 2 or not Native.HEADER_VARIANTS[header] or not Native.TILE_VARIANTS[tile] then
        say("kitdemo: unknown variant '" .. table.concat(words, " ")
            .. "' (header a|b|c, tile a|b, or old [theme])")
        return
    end
    KitDemo.header, KitDemo.tile = header, tile
    KitDemo.showNative(true)
end
