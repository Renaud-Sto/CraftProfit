local H = ...

local function ns() return H.newNS("Util", "Data/Skillup", "Data/VendorPrices", "Vendor", "Recipes", "Shopping") end
local function load() return ns().Shopping end
local function listed()
    local V = ns().Vendor
    return function(id) return (V.get({}, id, 0)) end
end

local BAG = {
    recipeID = 1, name = "Woolen Bag", difficulty = "medium", outputItemID = 4240, qtyMin = 1, qtyMax = 1,
    reagents = { { itemID = 2997, qty = 3 }, { itemID = 2321, qty = 1 } },
}
local CAPE = {
    recipeID = 2, name = "Woolen Cape", difficulty = "medium", outputItemID = 2580, qtyMin = 1, qtyMax = 1,
    reagents = { { itemID = 2997, qty = 1 }, { itemID = 2321, qty = 1 }, { itemID = 2320, qty = 2 } },
}

local function newList(S)
    local db = {}
    return S.list(db, "Sto-Greyson", "Sto", "Greyson"), db
end

H.test("recipes are kept with their crafts; the materials add up over them", function()
    local S = load()
    local list = newList(S)
    H.eq(S.addRecipe(list, BAG, 4, 100), 4)
    H.eq(S.addRecipe(list, CAPE, 2, 100), 2)
    H.eq(#list.recipes, 2)
    H.eq(list.recipes[1].crafts, 4)
    H.eq(S.items(list), { { itemID = 2997, qty = 14 }, { itemID = 2321, qty = 6 }, { itemID = 2320, qty = 4 } })
    -- The same recipe again adds up its crafts.
    H.eq(S.addRecipe(list, BAG, 1, 100), 5)
    H.eq(#list.recipes, 2)
    H.eq(S.items(list)[1].qty, 17)
end)

H.test("a recipe added by mistake is removed with its materials", function()
    local S = load()
    local list = newList(S)
    S.addRecipe(list, BAG, 4)
    S.addRecipe(list, CAPE, 2)
    H.truthy(S.removeRecipe(list, 2))
    H.falsy(S.removeRecipe(list, 2))
    H.eq(S.items(list), { { itemID = 2997, qty = 12 }, { itemID = 2321, qty = 4 } })
    S.clear(list)
    H.eq(S.items(list), {})
end)

H.test("bad inputs add nothing; crafts and recipes are bounded", function()
    local S = load()
    local list = newList(S)
    H.eq(S.addRecipe(list, nil, 2), nil)
    H.eq(S.addRecipe(list, { recipeID = 9 }, 2), nil)
    H.eq(S.addRecipe(list, BAG, 0 / 0), 1)
    H.eq(S.addRecipe(list, BAG, 1e9), S.MAX_CRAFTS)
    for i = 1, S.MAX_RECIPES - 1 do
        local r = { recipeID = 100 + i, name = "R", difficulty = "easy", outputItemID = 5, qtyMin = 1, qtyMax = 1,
            reagents = { { itemID = 7, qty = 1 } } }
        H.truthy(S.addRecipe(list, r, 1))
    end
    H.eq(S.addRecipe(list, CAPE, 1), nil)
end)

H.test("one list per character; owners lists the own one first, then others with recipes", function()
    local S = load()
    local db = {}
    local war = S.list(db, "Grom-Greyson", "Grom", "Greyson")
    S.addRecipe(war, BAG, 2)
    S.list(db, "Empty-Greyson", "Empty", "Greyson")
    local mage = S.list(db, "Aya-Greyson", "Aya", "Greyson")
    H.truthy(mage ~= war)
    H.truthy(S.list(db, "Grom-Greyson") == war)
    H.eq(S.owners(db, "Aya-Greyson"), { "Aya-Greyson", "Grom-Greyson" })
end)

H.test("snapshotBags remembers what the owner carries of its materials", function()
    local S = load()
    local list = newList(S)
    S.addRecipe(list, BAG, 1)
    local function count(id) return ({ [2997] = 5 })[id] or 0 end
    H.truthy(S.snapshotBags(list, count))
    -- Nothing held is not stored.
    H.eq(list.bags, { [2997] = 5 })
    H.falsy(S.snapshotBags(list, count))
end)

H.test("sanitize rebuilds lists, merges duplicate recipes and drops junk", function()
    local S = load()
    local saved = {
        ["Sto-Greyson"] = { name = "Sto", realm = "Greyson", recipes = {
            { recipe = BAG, crafts = 2 }, { recipe = BAG, crafts = 3 }, { recipe = "x", crafts = 1 },
            { recipe = CAPE, crafts = 0 },
        }, bags = { [2997] = 4, x = 1, [5] = -1 } },
        [5] = { recipes = {} }, Bad = "x",
    }
    local clean = S.sanitize(saved)
    H.eq(#clean["Sto-Greyson"].recipes, 1)
    H.eq(clean["Sto-Greyson"].recipes[1].crafts, 5)
    H.eq(clean["Sto-Greyson"].bags, { [2997] = 4 })
    H.eq(clean[5], nil)
    H.eq(clean.Bad, nil)
    H.eq(S.sanitize(nil), {})
end)

H.test("rows: held, missing, cheapest price and the total left to pay", function()
    local S = load()
    local list = newList(S)
    S.addRecipe(list, BAG, 4)
    local rows, total, unpriced = S.rows(list, {
        ownedOf = function(id) return ({ [2997] = 5, [2321] = 10 })[id] end,
        priceOf = function(id) return ({ [2997] = 200, [2321] = 500 })[id] end,
        vendorOf = listed(),
    })
    H.eq(rows[1], { itemID = 2997, need = 12, have = 5, buy = 7, unit = 200, source = "ah", cost = 1400, done = false })
    H.eq(rows[2].done, true)
    H.eq(rows[2].source, "vendor")
    H.eq(total, 1400)
    H.eq(unpriced, {})
    local _, none, missing = S.rows(list, { vendorOf = listed() })
    H.eq(none, nil)
    H.eq(missing, { 2997 })
end)
