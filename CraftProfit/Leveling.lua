-- Ranks the known recipes of a profession by what one skill point costs. Pure Lua,
-- no WoW API: the caller supplies the evaluation of a recipe.
local _, ns = ...
local Core = ns.Core

local Leveling = {}
ns.Leveling = Leveling

-- recipes: normalised recipes; evaluate(recipe) returns an Evaluate result with the
-- per point figures. opts.showGrey keeps recipes that can no longer give a point
-- (chance 0); by default they are left out. Recipes whose cost is unknown stay in,
-- after the ones that can be ranked.
-- Returns { items = { { recipe, result } ... } in display order, hiddenGrey = count }.
function Leveling.rank(recipes, evaluate, opts)
    local showGrey = opts and opts.showGrey
    local items, entries, hidden = {}, {}, 0
    for _, recipe in ipairs(recipes) do
        local result = evaluate(recipe)
        local pp = result and result.perPoint
        if pp and pp.chance == 0 and not showGrey then
            hidden = hidden + 1
        else
            items[#items + 1] = { recipe = recipe, result = result }
            entries[#entries + 1] = { cost = pp and pp.cost, chance = pp and pp.chance }
        end
    end
    local sorted = {}
    for i, index in ipairs(Core.rankByPointCost(entries)) do sorted[i] = items[index] end
    return { items = sorted, hiddenGrey = hidden }
end
