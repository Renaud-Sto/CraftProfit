-- Colours that carry a meaning (gain, loss, recipe difficulty, best, stale, incomplete) and
-- the game's text colours. The meaning colours never follow an appearance choice; the text
-- colours come from the game's own colour objects so native frames match Blizzard's.
-- Loaded before Theme.lua, which shares FIXED with the old themed kit.
local _, ns = ...

local Colors = {}
ns.Colors = Colors

Colors.FIXED = {
    profit = { 0.35, 0.90, 0.45, 1 },
    loss = { 1.00, 0.40, 0.35, 1 },
    incomplete = { 1.00, 0.82, 0.25, 1 },
    stale = { 1.00, 0.60, 0.25, 1 },
    best = { 1.00, 0.82, 0.00, 1 },
    optimal = { 1.00, 0.50, 0.25, 1 },
    medium = { 1.00, 0.82, 0.00, 1 },
    easy = { 0.25, 0.75, 0.25, 1 },
    trivial = { 0.55, 0.55, 0.55, 1 },
}

-- The game global each text kind reads (looked up at each call: named globals, not _G,
-- so a sandboxed environment answers), and the value used when the global is missing or
-- not a colour object (the test fake, a changed build).
local TEXT = {
    main = { read = function() return HIGHLIGHT_FONT_COLOR end, fallback = { 1, 1, 1, 1 } },
    muted = { read = function() return DISABLED_FONT_COLOR end, fallback = { 0.5, 0.5, 0.5, 1 } },
    gold = { read = function() return NORMAL_FONT_COLOR end, fallback = { 1, 0.82, 0, 1 } },
}

-- { r, g, b, a } from a game colour object, or nil when it is not one or answers nothing.
local function rgbaOf(color)
    if type(color) ~= "table" or type(color.GetRGBA) ~= "function" then return nil end
    local ok, r, g, b, a = pcall(color.GetRGBA, color)
    if not ok or type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
    return { r, g, b, type(a) == "number" and a or 1 }
end

-- The game's text colour for `kind` ("main", "muted", "gold"), read now (a fresh table the
-- caller may keep). An unknown kind answers "main".
function Colors.text(kind)
    local entry = TEXT[kind] or TEXT.main
    local found = rgbaOf(entry.read())
    if found then return found end
    local f = entry.fallback
    return { f[1], f[2], f[3], f[4] }
end

-- "|cffRRGGBB" for a { r, g, b } colour, to colour part of a string (close with "|r").
function Colors.escape(c)
    local function byte(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
    return string.format("|cff%02x%02x%02x", byte(c[1]), byte(c[2]), byte(c[3]))
end
