local H = ...

local function load()
    return H.newNS("Util", "Core", "Leveling")
end

local function recipe(id) return { recipeID = id, name = "R" .. id } end

local function evaluator(map)
    return function(r) return { perPoint = map[r.recipeID] } end
end

H.test("rank orders by cost per point, then recipes without a cost, and counts the grey ones it hides", function()
    local Leveling = load().Leveling
    local recipes = { recipe(1), recipe(2), recipe(3), recipe(4), recipe(5), recipe(6) }
    local ranked = Leveling.rank(recipes, evaluator({
        [1] = { cost = 900, chance = 0.25 },
        [2] = { cost = -50, chance = 1 },
        [3] = { chance = 0 },
        [4] = { cost = nil, chance = 0.75 },
        [5] = { cost = 100, chance = 0.75 },
        [6] = nil,
    }), {})
    local ids = {}
    for i, item in ipairs(ranked.items) do ids[i] = item.recipe.recipeID end
    H.eq(ids, { 2, 5, 1, 4, 6 })
    H.eq(ranked.hiddenGrey, 1)
end)

H.test("showGrey keeps the recipes that can no longer give a point, after the ranked ones", function()
    local Leveling = load().Leveling
    local ranked = Leveling.rank({ recipe(1), recipe(2), recipe(3) }, evaluator({
        [1] = { chance = 0 }, [2] = { cost = 500, chance = 0.25 }, [3] = { cost = 9, chance = 1 },
    }), { showGrey = true })
    local ids = {}
    for i, item in ipairs(ranked.items) do ids[i] = item.recipe.recipeID end
    H.eq(ids, { 3, 2, 1 })
    H.eq(ranked.hiddenGrey, 0)
    H.eq(ranked.items[1].result.perPoint.cost, 9)
end)

H.test("rank of nothing is empty", function()
    local Leveling = load().Leveling
    H.eq(Leveling.rank({}, evaluator({}), {}), { items = {}, hiddenGrey = 0 })
end)

H.test("the speed sort lists the likeliest points first and keeps the grey ones for the end", function()
    local Leveling = load().Leveling
    local ranked = Leveling.rank({ recipe(1), recipe(2), recipe(3), recipe(4) }, evaluator({
        [1] = { cost = -900, chance = 0.25 }, [2] = { cost = 400, chance = 1 },
        [3] = { cost = 100, chance = 0.75 }, [4] = { chance = 0 },
    }), { sort = "speed", showGrey = true })
    local ids = {}
    for i, item in ipairs(ranked.items) do ids[i] = item.recipe.recipeID end
    H.eq(ids, { 2, 3, 1, 4 })
    -- the default is the cost sort
    local byCost = Leveling.rank({ recipe(1), recipe(2), recipe(3) }, evaluator({
        [1] = { cost = -900, chance = 0.25 }, [2] = { cost = 400, chance = 1 }, [3] = { cost = 100, chance = 0.75 },
    }), {})
    H.eq(byCost.items[1].recipe.recipeID, 1)
end)
