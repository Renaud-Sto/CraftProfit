local H = ...

local function load()
    return H.newNS("Util", "Core", "Data/Skillup", "Data/Disenchant", "Evaluate")
end

local RECIPE = {
    recipeID = 1, name = "Sword", difficulty = "medium", outputItemID = 100, outputQty = 1,
    reagents = { { itemID = 1, qty = 2 }, { itemID = 2, qty = 1 } },
}

local DE_ENTRIES = { { itemID = 200, chance = 1, min = 1, max = 1 } }

-- unit price and age (seconds) per item
local function prices(over)
    local map = { [1] = { 100, 60 }, [2] = { 50, 120 }, [100] = { 1000, 30 }, [200] = { 400, 10 } }
    for k, v in pairs(over or {}) do map[k] = v end
    return function(id)
        local row = map[id]
        if row == nil then return nil end
        if type(row) ~= "table" then return row end
        return row[1], row[2]
    end
end

local function info(over)
    local t = { quality = 2, ilvl = 15, sellPrice = 200, classID = 2, bindType = 2 }
    for k, v in pairs(over or {}) do t[k] = v end
    return function() return t end
end

local function ctx(over)
    local c = {
        recipe = RECIPE, priceOf = prices(), itemInfo = info(), cut = 0.05, showPerPoint = false,
        lookupDisenchant = function() return DE_ENTRIES end,
    }
    for k, v in pairs(over or {}) do c[k] = v end
    return c
end

H.test("a fully priced recipe gives cost, every option, the best one and the net", function()
    local E = load().Evaluate
    local r = E.run(ctx())
    H.eq(r.cost.total, 250)
    H.eq(r.cost.missing, {})
    H.eq(r.cost.lines[1], { itemID = 1, qty = 2, unit = 100, subtotal = 200 })
    H.eq(r.options.ah, { status = "ok", value = 950 })
    H.eq(r.options.vendor, { status = "ok", value = 200 })
    H.eq(r.options.disenchant, { status = "ok", value = 380 })
    H.eq(r.best, "ah")
    H.eq(r.bestValue, 950)
    H.eq(r.net, 700)
    H.eq(r.incomplete, false)
    H.eq(r.oldestAge, 120)
    H.eq(r.perPoint, nil)
end)

H.test("one unpriced reagent makes the result incomplete, never cheap", function()
    local E = load().Evaluate
    local r = E.run(ctx({ priceOf = prices({ [2] = false }) }))
    H.eq(r.cost.total, nil)
    H.eq(r.cost.missing, { 2 })
    H.eq(r.cost.lines[2].unit, nil)
    H.eq(r.net, nil)
    H.eq(r.incomplete, true)
    H.eq(r.best, "ah")
end)

H.test("NaN, negative and string prices are treated as unknown", function()
    local E = load().Evaluate
    for _, bad in ipairs({ 0 / 0, -1, "9", 1 / 0 }) do
        local r = E.run(ctx({ priceOf = prices({ [1] = bad }) }))
        H.eq(r.cost.total, nil)
        H.eq(r.incomplete, true)
    end
end)

H.test("an invalid age is ignored when finding the oldest price", function()
    local E = load().Evaluate
    local r = E.run(ctx({ priceOf = prices({ [1] = { 100, 0 / 0 }, [2] = { 50, 5 } }) }))
    H.eq(r.oldestAge, 30)
end)

H.test("item data that is not loaded yet leaves vendor and disenchant unknown", function()
    local E = load().Evaluate
    local r = E.run(ctx({ itemInfo = function() return nil end }))
    H.eq(r.options.vendor.status, "unknown")
    H.eq(r.options.disenchant.status, "unknown")
    H.eq(r.options.ah.status, "ok")
    H.eq(r.incomplete, true)
end)

H.test("a bind-on-pickup result cannot be sold on the AH", function()
    local E = load().Evaluate
    local r = E.run(ctx({ itemInfo = info({ bindType = 1 }) }))
    H.eq(r.options.ah.status, "na")
    H.eq(r.best, "disenchant")
end)

H.test("a vendor price of 0 means the vendor will not buy it", function()
    local E = load().Evaluate
    H.eq(E.run(ctx({ itemInfo = info({ sellPrice = 0 }) })).options.vendor.status, "na")
end)

H.test("items that cannot be disenchanted have no disenchant option", function()
    local E = load().Evaluate
    H.eq(E.run(ctx({ itemInfo = info({ classID = 0 }) })).options.disenchant.status, "na")
    H.eq(E.run(ctx({ itemInfo = info({ quality = 1 }) })).options.disenchant.status, "na")
    H.eq(E.run(ctx({ itemInfo = info({ classID = 0 }) })).incomplete, false)
end)

H.test("missing disenchant data or an unpriced result is unknown, not zero", function()
    local E = load().Evaluate
    local noData = E.run(ctx({ lookupDisenchant = function() return nil end }))
    H.eq(noData.options.disenchant.status, "unknown")
    H.eq(noData.incomplete, true)
    local noPrice = E.run(ctx({ priceOf = prices({ [200] = false }) }))
    H.eq(noPrice.options.disenchant.status, "unknown")
end)

H.test("the output quantity scales every sale option", function()
    local E = load().Evaluate
    local recipe = { recipeID = 1, name = "x", outputItemID = 100, outputQty = 2, reagents = RECIPE.reagents }
    local r = E.run(ctx({ recipe = recipe }))
    H.eq(r.options.ah.value, 1900)
    H.eq(r.options.vendor.value, 400)
    H.eq(r.options.disenchant.value, 760)
end)

H.test("a loss is a negative net", function()
    local E = load().Evaluate
    local r = E.run(ctx({ priceOf = prices({ [100] = { 100, 1 } }), itemInfo = info({ sellPrice = 10, classID = 0 }) }))
    H.eq(r.best, "ah")
    H.eq(r.net, 95 - 250)
end)

H.test("nothing sellable gives no best option and no net", function()
    local E = load().Evaluate
    local r = E.run(ctx({ itemInfo = info({ bindType = 1, sellPrice = 0, classID = 0 }) }))
    H.eq(r.best, nil)
    H.eq(r.net, nil)
    H.eq(r.incomplete, false)
end)

H.test("cost per skill point uses the difficulty and recovers the best sale", function()
    local E = load().Evaluate
    local r = E.run(ctx({ showPerPoint = true }))
    -- (250 - 950) / 0.75 = -933.33
    H.eq(r.perPoint, { chance = 0.75, cost = -933, estimate = true })
end)

H.test("cost per skill point handles trivial and unknown difficulty", function()
    local E = load().Evaluate
    local function with(difficulty)
        local recipe = { recipeID = 1, name = "x", difficulty = difficulty, outputItemID = 100, outputQty = 1, reagents = RECIPE.reagents }
        return E.run(ctx({ recipe = recipe, showPerPoint = true })).perPoint
    end
    H.eq(with("trivial"), { chance = 0, cost = nil, estimate = true })
    H.eq(with(nil), { chance = nil, cost = nil, estimate = true })
end)

H.test("wantedItems lists reagents, the output and disenchant results once", function()
    local E = load().Evaluate
    H.eq(E.wantedItems(RECIPE, info(), function() return DE_ENTRIES end), { 1, 2, 100, 200 })
    H.eq(E.wantedItems(RECIPE, function() return nil end, function() return DE_ENTRIES end), { 1, 2, 100 })
    H.eq(E.wantedItems(RECIPE, info({ classID = 0 }), function() return DE_ENTRIES end), { 1, 2, 100 })
end)
