local H = ...

local function load() return H.newNS("Util", "Data/VendorPrices", "Vendor", "Shopping").Shopping end
local function listed()
    local V = H.newNS("Util", "Data/VendorPrices", "Vendor").Vendor
    return function(id) return (V.get({}, id, 0)) end
end

local BAG = {
    recipeID = 1, name = "Woolen Bag", difficulty = "medium", outputItemID = 4240, outputQty = 1,
    reagents = { { itemID = 2997, qty = 3 }, { itemID = 2321, qty = 1 } },
}
local CAPE = {
    recipeID = 2, name = "Woolen Cape", difficulty = "medium", outputItemID = 2580, outputQty = 1,
    reagents = { { itemID = 2997, qty = 1 }, { itemID = 2321, qty = 1 }, { itemID = 2320, qty = 2 } },
}

H.test("adding a recipe adds its reagents x the crafts; a second recipe merges into them", function()
    local S = load()
    local list = {}
    H.eq(S.addRecipe(list, BAG, 4), 2)
    H.eq(list, { { itemID = 2997, qty = 12 }, { itemID = 2321, qty = 4 } })
    H.eq(S.addRecipe(list, CAPE, 2), 3)
    H.eq(list, { { itemID = 2997, qty = 14 }, { itemID = 2321, qty = 6 }, { itemID = 2320, qty = 4 } })
end)

H.test("bad crafts count as one; bad recipes and reagents add nothing", function()
    local S = load()
    local list = {}
    S.addRecipe(list, BAG, 0 / 0)
    H.eq(list[1].qty, 3)
    H.eq(S.addRecipe(list, nil, 2), 0)
    H.eq(S.addRecipe(list, { reagents = { { itemID = -1, qty = 2 }, { itemID = 5, qty = 0 } } }, 1), 0)
    H.eq(#list, 2)
end)

H.test("remove and clear", function()
    local S = load()
    local list = {}
    S.addRecipe(list, CAPE, 1)
    H.truthy(S.remove(list, 2321))
    H.falsy(S.remove(list, 2321))
    H.eq(list, { { itemID = 2997, qty = 1 }, { itemID = 2320, qty = 2 } })
    S.clear(list)
    H.eq(list, {})
end)

H.test("the list is bounded in items and quantity", function()
    local S = load()
    local list = {}
    for i = 1, S.MAX_ITEMS do H.truthy(S.add(list, i, 1)) end
    H.falsy(S.add(list, S.MAX_ITEMS + 1, 1))
    H.truthy(S.add(list, 1, 1e9))
    H.eq(list[1].qty, S.MAX_QTY)
end)

H.test("sanitize keeps valid rows in order, merges duplicates, drops junk", function()
    local S = load()
    local saved = { { itemID = 5, qty = 2 }, "x", { itemID = 5, qty = 3 }, { itemID = 6, qty = 0 },
        { itemID = 1.5, qty = 1 }, { itemID = 7, qty = 2.9 } }
    H.eq(S.sanitize(saved), { { itemID = 5, qty = 5 }, { itemID = 7, qty = 2 } })
    H.eq(S.sanitize(nil), {})
end)

H.test("rows: in bags, missing, cheapest price and the total left to pay", function()
    local S = load()
    local list = { { itemID = 2997, qty = 12 }, { itemID = 2321, qty = 4 }, { itemID = 99, qty = 1 } }
    local rows, total, unpriced = S.rows(list, {
        ownedOf = function(id) return ({ [2997] = 5, [2321] = 10 })[id] end,
        priceOf = function(id) return ({ [2997] = 200, [2321] = 500, [99] = 1000 })[id] end,
        -- Fine Thread is listed at 1s at vendors: cheaper than the AH, but already in the bags.
        vendorOf = listed(),
    })
    H.eq(rows[1], { itemID = 2997, need = 12, have = 5, buy = 7, unit = 200, source = "ah", cost = 1400, done = false })
    H.eq(rows[2].done, true)
    H.eq(rows[2].cost, 0)
    H.eq(rows[2].source, "vendor")
    H.eq(rows[3].cost, 1000)
    H.eq(total, 2400)
    H.eq(unpriced, {})
end)

H.test("rows: a missing item without any price leaves the total unknown and is named", function()
    local S = load()
    local rows, total, unpriced = S.rows({ { itemID = 99, qty = 2 }, { itemID = 3372, qty = 5 } }, { vendorOf = listed() })
    H.eq(rows[1].cost, nil)
    -- Leaded Vial: the listed vendor price.
    H.eq(rows[2].cost, 200)
    H.eq(total, nil)
    H.eq(unpriced, { 99 })
end)
