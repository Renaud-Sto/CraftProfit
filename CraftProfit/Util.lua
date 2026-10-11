-- Number helpers shared by the pure modules. Pure Lua, no WoW API.
local _, ns = ...

local Util = {}
ns.Util = Util

-- NaN is the only value that differs from itself; math.huge covers +/-inf.
-- Never rely on an ordering comparison to detect NaN.
function Util.isFinite(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- The largest copper amount the addon handles. WoW's gold cap is 99,999,999g = 1e12
-- copper; this stays above it and below the point where tostring switches to exponent
-- notation. A saved or measured unit price above it is corrupt (see Prices.store).
Util.MAX_COPPER = 1e13

-- A usable copper amount: finite and not negative.
function Util.isCopper(n)
    return Util.isFinite(n) and n >= 0
end

-- A quantity: finite and at least 1, floored. Anything else gives nil.
function Util.count(n)
    if not Util.isFinite(n) or n < 1 then return nil end
    return math.floor(n)
end

-- An identifier: an exact positive integer. Anything else gives nil.
function Util.id(n)
    if Util.count(n) == n then return n end
    return nil
end

-- True for a "secret" value of the game (issecretvalue): it raises when compared, used as
-- a table key or concatenated. Outside the game (no issecretvalue) nothing is secret.
function Util.isSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) or false
end

-- A non-empty plain string, or nil. The game may hand out "secret" strings that raise
-- when used: `isSecret` (the caller's issecretvalue guard, optional) rejects them, and the
-- copy is made under pcall as a second line, so a secret or a non-string gives nil.
function Util.text(v, isSecret)
    if type(v) ~= "string" then return nil end
    if isSecret then
        local ok, secret = pcall(isSecret, v)
        if not ok or secret then return nil end
    end
    local ok, copy = pcall(function() return v .. "" end)
    if ok and type(copy) == "string" and copy ~= "" then return copy end
    return nil
end

function Util.clamp(n, lo, hi)
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

-- Round to the nearest whole number, halves away from zero.
function Util.round(n)
    if n >= 0 then return math.floor(n + 0.5) end
    return -math.floor(-n + 0.5)
end
