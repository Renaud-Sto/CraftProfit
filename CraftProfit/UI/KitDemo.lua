-- Developer tool: /cp kitdemo [theme] shows the shared widgets in a theme, so a
-- theme can be judged in the game before any real window uses it. English only,
-- not part of the user-facing help.
local _, ns = ...
local Kit, Theme = ns.Kit, ns.Theme

local KitDemo = {}
ns.KitDemo = KitDemo

local WIDTH = 372
local TILE_H = 52
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

    local offsets, total = Kit.stack({ TILE_H, materials:height(), options:height() }, Kit.GAP, 0)
    for i, panel in ipairs({ materials, options }) do
        panel.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, offsets[i + 1])
        panel.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, offsets[i + 1])
    end
    frame:SetHeight(total + Kit.CONTENT_TOP + Kit.CONTENT_BOTTOM)
end

-- With a theme name: apply it and show the window. Without: show or hide it.
function KitDemo.toggle(name)
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
