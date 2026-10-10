-- Colour themes for the UI. Pure data, no WoW API. A window reads every colour that
-- belongs to the look from a theme; Theme.FIXED (the same table as ns.Colors.FIXED) holds
-- the colours that carry a meaning (gain, loss, recipe difficulty) and never change with
-- the theme.
local _, ns = ...

local Theme = {}
ns.Theme = Theme

Theme.DEFAULT = "gold"
Theme.ORDER = { "gold", "copper", "steel" }

Theme.TOKENS = {
    "windowBg", "frameOuter", "frameInner", "frameShade", "plaqueBg", "plaqueText",
    "panelBg", "panelEdge", "headBgTop", "headBgBottom", "headText", "headRule", "rowZebra", "rowHover",
    "buttonBg", "buttonEdge", "buttonText", "primaryBg", "primaryEdge", "primaryText",
    "inputBg", "inputEdge", "checkMark", "bestFill", "bestEdge", "textMain", "textMuted",
}

-- "B08D3C" -> { r, g, b, a } with each channel in 0..1.
local function hex(rgb, alpha)
    return {
        tonumber(rgb:sub(1, 2), 16) / 255,
        tonumber(rgb:sub(3, 4), 16) / 255,
        tonumber(rgb:sub(5, 6), 16) / 255,
        alpha or 1,
    }
end

-- The meaning colours live in Colors.lua (loaded first); the old kit reads them here.
Theme.FIXED = ns.Colors.FIXED

local themes = {
    gold = {
        name = "gold",
        windowBg = hex("121110"), frameOuter = hex("B08D3C"), frameInner = hex("7A5F26"), frameShade = hex("1D140A"),
        plaqueBg = hex("1E160E"), plaqueText = hex("FFD100"),
        panelBg = hex("0D0C0B"), panelEdge = hex("3B3322"),
        headBgTop = hex("2A2216"), headBgBottom = hex("17130D"), headText = hex("C9A95A"), headRule = hex("5D4A22"),
        rowZebra = hex("FFFFFF", 0.03),
        rowHover = hex("FFFFFF", 0.08),
        buttonBg = hex("1B1814"), buttonEdge = hex("5D4A22"), buttonText = hex("D9C48A"),
        primaryBg = hex("3B2A0C"), primaryEdge = hex("B08D3C"), primaryText = hex("FFD100"),
        inputBg = hex("0B0A09"), inputEdge = hex("3B3322"), checkMark = hex("C9A95A"),
        bestFill = hex("FFD100", 0.16), bestEdge = hex("FFD100"),
        textMain = hex("E8E0CC"), textMuted = hex("8A8372"),
    },
    copper = {
        name = "copper",
        windowBg = hex("17100B"), frameOuter = hex("C87533"), frameInner = hex("6B4524"), frameShade = hex("1C1109"),
        plaqueBg = hex("24150A"), plaqueText = hex("F0A35A"),
        panelBg = hex("0F0A07"), panelEdge = hex("4A2F18"),
        headBgTop = hex("33200F"), headBgBottom = hex("1B1008"), headText = hex("E0A46A"), headRule = hex("6B4524"),
        rowZebra = hex("FFFFFF", 0.03),
        rowHover = hex("FFFFFF", 0.08),
        buttonBg = hex("26180E"), buttonEdge = hex("6B4524"), buttonText = hex("E0A46A"),
        primaryBg = hex("5A2E10"), primaryEdge = hex("C87533"), primaryText = hex("FFC58A"),
        inputBg = hex("0A0604"), inputEdge = hex("4A2F18"), checkMark = hex("E0A46A"),
        bestFill = hex("FFD100", 0.16), bestEdge = hex("FFD100"),
        textMain = hex("E8E0CC"), textMuted = hex("957757"),
    },
    steel = {
        name = "steel",
        windowBg = hex("070814"), frameOuter = hex("5F6684"), frameInner = hex("3A4160"), frameShade = hex("12162C"),
        plaqueBg = hex("0E1226"), plaqueText = hex("CFD8FF"),
        panelBg = hex("0D0F1F"), panelEdge = hex("2A3048"),
        headBgTop = hex("1A2036"), headBgBottom = hex("10142A"), headText = hex("8FA4E6"), headRule = hex("3A4260"),
        rowZebra = hex("FFFFFF", 0.03),
        rowHover = hex("FFFFFF", 0.08),
        buttonBg = hex("1A2036"), buttonEdge = hex("4A5272"), buttonText = hex("CFD8FF"),
        primaryBg = hex("243A78"), primaryEdge = hex("6A86E0"), primaryText = hex("FFFFFF"),
        inputBg = hex("05060D"), inputEdge = hex("3A4260"), checkMark = hex("8FA4E6"),
        bestFill = hex("FFD100", 0.16), bestEdge = hex("FFD100"),
        textMain = hex("E6E8F2"), textMuted = hex("7A82A6"),
    },
}

function Theme.exists(name)
    return type(name) == "string" and themes[name] ~= nil
end

-- The theme called `name`, or the default one for anything unknown.
function Theme.get(name)
    if Theme.exists(name) then return themes[name] end
    return themes[Theme.DEFAULT]
end

function Theme.list()
    local names = {}
    for i, name in ipairs(Theme.ORDER) do names[i] = name end
    return names
end

-- true, or false and the reason: every token must be a { r, g, b, a } of numbers in 0..1.
function Theme.validate(theme)
    if type(theme) ~= "table" then return false, "not a table" end
    for _, token in ipairs(Theme.TOKENS) do
        local c = theme[token]
        if type(c) ~= "table" then return false, "missing " .. token end
        for i = 1, 4 do
            local v = c[i]
            if type(v) ~= "number" or v ~= v or v < 0 or v > 1 then return false, "bad " .. token end
        end
    end
    return true
end
