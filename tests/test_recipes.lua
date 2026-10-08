local H = ...

local function load() return H.newNS("Util", "Data/Skillup", "Recipes").Recipes end

-- Overrides cannot contain nil (pairs skips it), so NIL marks "remove this field".
local NIL = {}

local function raw(over)
    local r = {
        recipeID = 5, name = "Copper Sword", difficulty = 0, outputItemID = 2845,
        qtyMin = 1, qtyMax = 1,
        reagents = { { itemID = 2840, qty = 6 } },
    }
    for k, v in pairs(over or {}) do
        if v == NIL then r[k] = nil else r[k] = v end
    end
    return r
end

H.test("normalize builds the canonical recipe", function()
    H.eq(load().normalize(raw()), {
        recipeID = 5, name = "Copper Sword", difficulty = "optimal", outputItemID = 2845,
        outputQty = 1, reagents = { { itemID = 2840, qty = 6 } },
    })
end)

H.test("normalize averages a min..max yield and defaults to 1", function()
    local R = load()
    H.eq(R.normalize(raw({ qtyMin = 1, qtyMax = 2 })).outputQty, 1.5)
    H.eq(R.normalize(raw({ qtyMin = NIL, qtyMax = NIL })).outputQty, 1)
end)

H.test("normalize is idempotent", function()
    local R = load()
    local once = R.normalize(raw({ qtyMin = 2, qtyMax = 4 }))
    H.eq(R.normalize(once), once)
end)

H.test("normalize merges duplicate reagents and keeps their order", function()
    local R = load()
    local r = R.normalize(raw({ reagents = { { itemID = 1, qty = 2 }, { itemID = 2, qty = 1 }, { itemID = 1, qty = 3 } } }))
    H.eq(r.reagents, { { itemID = 1, qty = 5 }, { itemID = 2, qty = 1 } })
end)

H.test("normalize does not modify its input", function()
    local R = load()
    local input = raw({ reagents = { { itemID = 1, qty = 2 }, { itemID = 1, qty = 3 } } })
    R.normalize(input)
    H.eq(input.reagents, { { itemID = 1, qty = 2 }, { itemID = 1, qty = 3 } })
end)

H.test("normalize rejects the whole recipe when any reagent is invalid", function()
    local R = load()
    local bads = {
        { { itemID = 1, qty = 0 } },
        { { itemID = 1, qty = 1.5 } },
        { { itemID = nil, qty = 1 } },
        { { itemID = 1.5, qty = 1 } },
        { { itemID = 1, qty = 0 / 0 } },
        { { itemID = 1, qty = 1 }, "junk" },
        { { itemID = 1, qty = 1 }, { itemID = 2 } },
        {},
    }
    for _, reagents in ipairs(bads) do
        H.eq(R.normalize(raw({ reagents = reagents })), nil)
    end
    H.eq(R.normalize(raw({ reagents = NIL })), nil)
    H.eq(R.normalize(raw({ reagents = "x" })), nil)
end)

H.test("normalize rejects more than the maximum number of reagents", function()
    local R = load()
    local reagents = {}
    for i = 1, R.MAX_REAGENTS + 1 do reagents[i] = { itemID = i, qty = 1 } end
    H.eq(R.normalize(raw({ reagents = reagents })), nil)
    table.remove(reagents)
    H.truthy(R.normalize(raw({ reagents = reagents })))
end)

H.test("normalize rejects invalid identifiers and yields", function()
    local R = load()
    H.eq(R.normalize(raw({ recipeID = NIL })), nil)
    H.eq(R.normalize(raw({ recipeID = 0 })), nil)
    H.eq(R.normalize(raw({ outputItemID = NIL })), nil)
    H.eq(R.normalize(raw({ outputItemID = 0 / 0 })), nil)
    H.eq(R.normalize(raw({ qtyMin = 0 })), nil)
    H.eq(R.normalize(raw({ qtyMin = 3, qtyMax = 1 })), nil)
    H.eq(R.normalize(raw({ qtyMin = 1, qtyMax = 0 / 0 })), nil)
    H.eq(R.normalize(raw({ qtyMin = 1, qtyMax = 5000 })), nil)
    H.eq(R.normalize(nil), nil)
    H.eq(R.normalize("recipe"), nil)
end)

H.test("normalize tolerates a missing name and an unknown difficulty", function()
    local R = load()
    H.eq(R.normalize(raw({ name = NIL })).name, "")
    H.eq(R.normalize(raw({ name = 12 })).name, "")
    H.eq(R.normalize(raw({ name = string.rep("x", 300) })).name, "")
    local r = R.normalize(raw({ difficulty = "header" }))
    H.truthy(r)
    H.eq(r.difficulty, nil)
end)

H.test("normalize rejects reagent lists with holes", function()
    local R = load()
    local holey = { [1] = { itemID = 1, qty = 1 }, [3] = { itemID = 2, qty = 9 } }
    H.eq(R.normalize(raw({ reagents = holey })), nil)
end)

H.test("normalize rejects reagent lists with extra string keys", function()
    local R = load()
    local extraKey = { { itemID = 1, qty = 1 }, x = { itemID = 2, qty = 9 } }
    H.eq(R.normalize(raw({ reagents = extraKey })), nil)
end)

H.test("normalize accepts ordinary contiguous reagent lists", function()
    local R = load()
    local contiguous = { { itemID = 1, qty = 1 }, { itemID = 2, qty = 9 } }
    local r = R.normalize(raw({ reagents = contiguous }))
    H.truthy(r)
    H.eq(#r.reagents, 2)
end)
