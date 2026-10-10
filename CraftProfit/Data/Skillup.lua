-- Probability that crafting a recipe raises the skill, by relative difficulty.
-- Pure Lua, no WoW API.
local _, ns = ...

ns.Data = ns.Data or {}
local Skillup = {}
ns.Data.Skillup = Skillup

-- ESTIMATES, not measured values: the UI labels results built on them as
-- estimates. Replace with measured values once known.
Skillup.CHANCE = { optimal = 1, medium = 0.75, easy = 0.25, trivial = 0 }

-- Enum.TradeskillRelativeDifficulty on the Mainline API (confirm in
-- docs/probe-findings.md, F3/F7).
local BY_NUMBER = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" }

-- Accepts an Enum number or a name; returns the canonical lowercase name or nil.
function Skillup.name(difficulty)
    if type(difficulty) == "string" then
        local lower = difficulty:lower()
        if Skillup.CHANCE[lower] ~= nil then return lower end
        return nil
    end
    if type(difficulty) == "number" then return BY_NUMBER[difficulty] end
    return nil
end

function Skillup.chance(difficulty)
    local name = Skillup.name(difficulty)
    if not name then return nil end
    return Skillup.CHANCE[name]
end
