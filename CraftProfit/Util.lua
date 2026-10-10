-- Number helpers shared by the pure modules. Pure Lua, no WoW API.
local _, ns = ...

local Util = {}
ns.Util = Util

-- NaN is the only value that differs from itself; math.huge covers +/-inf.
-- Never rely on an ordering comparison to detect NaN.
function Util.isFinite(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

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
