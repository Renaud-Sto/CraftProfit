-- Display helpers. Pure Lua, no WoW API.
local _, ns = ...
local Util = ns.Util

local Format = {}
ns.Format = Format

-- Amounts above this are shown clamped (Util.MAX_COPPER explains the value).
Format.MAX_COPPER = Util.MAX_COPPER

-- "12g 3s 4c": fallback for tests and chat. The window passes
-- GetMoneyString instead, which draws coin icons in any language.
local function plainCoins(copper)
    local g = math.floor(copper / 10000)
    local s = math.floor(copper % 10000 / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = string.format("%dg", g) end
    if s > 0 then parts[#parts + 1] = string.format("%ds", s) end
    if c > 0 or #parts == 0 then parts[#parts + 1] = string.format("%dc", c) end
    return table.concat(parts, " ")
end

-- From 100 gold up the copper is dropped (rounded to the nearest silver): the coin icons
-- make a full amount too wide for a tile or a column, and a cut-off "9..." reads as a
-- wrong number. The error is under 1 silver in 100 gold.
Format.ROUND_FROM = 100 * 10000

-- Unknown or invalid amounts give "?", never "0".
function Format.money(copper, coinFn)
    if not Util.isFinite(copper) then return "?" end
    local whole = Util.round(Util.clamp(math.abs(copper), 0, Format.MAX_COPPER))
    if whole >= Format.ROUND_FROM then whole = Util.round(whole / 100) * 100 end
    local sign = (copper < 0 and whole > 0) and "-" or ""
    local text
    if coinFn then text = coinFn(whole) end
    -- A coin function that answers nothing (or not a string) falls back to the plain text.
    if type(text) ~= "string" then text = plainCoins(whole) end
    return sign .. text
end

-- Plain coins for a narrow column (the tags on the profession window's recipe rows), never
-- the coin icons: the copper is dropped from 1 gold up and the silver from 1000 gold up (both
-- rounded to the nearest), so a tag stays two units long at most. "?" as Format.money.
Format.SHORT_SILVER_FROM = 10000
Format.SHORT_GOLD_FROM = 1000 * 10000

function Format.short(copper)
    if not Util.isFinite(copper) then return "?" end
    local whole = Util.round(Util.clamp(math.abs(copper), 0, Format.MAX_COPPER))
    if whole >= Format.SHORT_GOLD_FROM then
        whole = Util.round(whole / 10000) * 10000
    elseif whole >= Format.SHORT_SILVER_FROM then
        whole = Util.round(whole / 100) * 100
    end
    local sign = (copper < 0 and whole > 0) and "-" or ""
    return sign .. plainCoins(whole)
end

-- Splits an age in seconds into a number and a unit name; the caller localizes
-- the unit. Returns nothing for an invalid or negative age.
function Format.age(seconds)
    if not Util.isFinite(seconds) or seconds < 0 then return nil end
    if seconds < 60 then return math.floor(seconds), "sec" end
    if seconds < 3600 then return math.floor(seconds / 60), "min" end
    if seconds < 86400 then return math.floor(seconds / 3600), "hour" end
    return math.floor(seconds / 86400), "day"
end
