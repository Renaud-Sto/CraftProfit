local H = ...

local function load() return H.newNS("Util", "Core") end

local function prices(map)
    return function(itemID) return map[itemID] end
end

H.test("sumCost adds quantity times unit price", function()
    local ns = load()
    local reagents = { { itemID = 1, qty = 2 }, { itemID = 2, qty = 3 } }
    H.eq({ ns.Core.sumCost(reagents, prices({ [1] = 100, [2] = 50 })) }, { 350 })
end)

H.test("sumCost reports every unpriced reagent and no total", function()
    local ns = load()
    local reagents = { { itemID = 1, qty = 2 }, { itemID = 2, qty = 3 }, { itemID = 3, qty = 1 } }
    H.eq({ ns.Core.sumCost(reagents, prices({ [1] = 100 })) }, { nil, { 2, 3 } })
end)

H.test("sumCost treats NaN, negative, infinite and non-number prices as unknown", function()
    local ns = load()
    for _, bad in ipairs({ 0 / 0, -5, 1 / 0, "12", true }) do
        local total, missing = ns.Core.sumCost({ { itemID = 9, qty = 1 } }, prices({ [9] = bad }))
        H.eq(total, nil)
        H.eq(missing, { 9 })
    end
end)

H.test("sumCost treats an invalid quantity as unknown, never as free", function()
    local ns = load()
    local total, missing = ns.Core.sumCost({ { itemID = 1, qty = 0 } }, prices({ [1] = 100 }))
    H.eq(total, nil)
    H.eq(missing, { 1 })
end)

H.test("netSale removes the commission and rounds to the copper", function()
    local ns = load()
    H.eq(ns.Core.netSale(1000, 1, 0.05), 950)
    H.eq(ns.Core.netSale(1000, 2, 0.05), 1900)
    H.eq(ns.Core.netSale(1000, 1.5, 0.05), 1425)
    H.eq(ns.Core.netSale(1000, 1, 0), 1000)
end)

H.test("netSale gives nil for invalid price, quantity or commission", function()
    local ns = load()
    H.eq(ns.Core.netSale(nil, 1, 0.05), nil)
    H.eq(ns.Core.netSale(0 / 0, 1, 0.05), nil)
    H.eq(ns.Core.netSale(-10, 1, 0.05), nil)
    H.eq(ns.Core.netSale(1000, 0, 0.05), nil)
    H.eq(ns.Core.netSale(1000, 1, 1), nil)
    H.eq(ns.Core.netSale(1000, 1, -0.1), nil)
    H.eq(ns.Core.netSale(1000, 1, 0 / 0), nil)
end)

H.test("vendorValue multiplies the sell price and rejects 0 and invalid", function()
    local ns = load()
    H.eq(ns.Core.vendorValue(100, 2), 200)
    H.eq(ns.Core.vendorValue(100, 1.5), 150)
    H.eq(ns.Core.vendorValue(0, 1), nil)
    H.eq(ns.Core.vendorValue(nil, 1), nil)
    H.eq(ns.Core.vendorValue(0 / 0, 1), nil)
end)

local DE = {
    { itemID = 10, chance = 0.8, min = 1, max = 3 },
    { itemID = 11, chance = 0.2, min = 1, max = 1 },
}

H.test("disenchantValue is the expected value of the results", function()
    local ns = load()
    -- 0.8 * 2 * 100 + 0.2 * 1 * 1000 = 360
    H.eq({ ns.Core.disenchantValue(DE, prices({ [10] = 100, [11] = 1000 }), 0) }, { 360 })
end)

H.test("disenchantValue is net of the AH commission", function()
    local ns = load()
    H.eq({ ns.Core.disenchantValue(DE, prices({ [10] = 100, [11] = 1000 }), 0.05) }, { 342 })
end)

H.test("disenchantValue reports unpriced results instead of undercounting", function()
    local ns = load()
    H.eq({ ns.Core.disenchantValue(DE, prices({ [10] = 100 }), 0.05) }, { nil, { 11 } })
end)

H.test("disenchantValue gives nil for missing, empty or corrupt data", function()
    local ns = load()
    local p = prices({ [10] = 100 })
    H.eq({ ns.Core.disenchantValue(nil, p, 0.05) }, { nil, {} })
    H.eq({ ns.Core.disenchantValue({}, p, 0.05) }, { nil, {} })
    H.eq({ ns.Core.disenchantValue({ { itemID = 10, chance = 2, min = 1, max = 1 } }, p, 0.05) }, { nil, {} })
    H.eq({ ns.Core.disenchantValue({ { itemID = 10, chance = 0.5, min = 3, max = 1 } }, p, 0.05) }, { nil, {} })
    H.eq({ ns.Core.disenchantValue(DE, p, 1) }, { nil, {} })
end)

H.test("bestOption picks the highest known value, ties go to the earlier key", function()
    local ns = load()
    local key, value, incomplete = ns.Core.bestOption({
        ah = { status = "ok", value = 100 },
        vendor = { status = "ok", value = 100 },
        disenchant = { status = "ok", value = 50 },
    })
    H.eq({ key, value, incomplete }, { "ah", 100, false })
end)

H.test("bestOption flags unknown options as incomplete but still returns the best known", function()
    local ns = load()
    local key, value, incomplete = ns.Core.bestOption({
        ah = { status = "unknown" },
        vendor = { status = "ok", value = 30 },
        disenchant = { status = "na" },
    })
    H.eq({ key, value, incomplete }, { "vendor", 30, true })
end)

H.test("bestOption with nothing sellable returns nothing", function()
    local ns = load()
    H.eq({ ns.Core.bestOption({ ah = { status = "na" }, vendor = { status = "na" } }) }, { nil, nil, false })
    H.eq({ ns.Core.bestOption({}) }, { nil, nil, false })
end)

H.test("bestOption ignores a NaN value", function()
    local ns = load()
    local key = ns.Core.bestOption({ ah = { status = "ok", value = 0 / 0 }, vendor = { status = "ok", value = 5 } })
    H.eq(key, "vendor")
end)

H.test("costPerPoint divides the net cost by the skill-up chance", function()
    local ns = load()
    H.eq(ns.Core.costPerPoint(100, 40, 0.75), 80)
    H.eq(ns.Core.costPerPoint(100, nil, 0.5), 200)
    H.eq(ns.Core.costPerPoint(100, 160, 1), -60)
end)

H.test("costPerPoint is nil when no skill point can be earned", function()
    local ns = load()
    H.eq(ns.Core.costPerPoint(100, 0, 0), nil)
    H.eq(ns.Core.costPerPoint(100, 0, 1.5), nil)
    H.eq(ns.Core.costPerPoint(100, 0, nil), nil)
    H.eq(ns.Core.costPerPoint(0 / 0, 0, 1), nil)
end)

H.test("likelyDisenchant picks the most probable result, valued at its mean quantity net of the cut", function()
    local Core = H.newNS("Util", "Core").Core
    local entries = {
        { itemID = 1, chance = 0.2, min = 1, max = 2 },
        { itemID = 2, chance = 0.75, min = 2, max = 3 },
        { itemID = 3, chance = 0.05, min = 1, max = 1 },
    }
    local price = function(id) return ({ [1] = 1000, [2] = 400, [3] = 6000 })[id] end
    H.eq(Core.likelyDisenchant(entries, price, 0.05), { chance = 0.75, itemID = 2, min = 2, max = 3, value = 950 })
end)

H.test("likelyDisenchant breaks ties by value, and is nil for unpriced or corrupt data", function()
    local Core = H.newNS("Util", "Core").Core
    local tie = { { itemID = 1, chance = 0.5, min = 1, max = 1 }, { itemID = 2, chance = 0.5, min = 1, max = 1 } }
    local price = function(id) return id == 1 and 100 or 300 end
    H.eq(Core.likelyDisenchant(tie, price, 0).itemID, 2)
    H.eq(Core.likelyDisenchant(tie, function() return nil end, 0), nil)
    H.eq(Core.likelyDisenchant({}, price, 0), nil)
    H.eq(Core.likelyDisenchant({ { itemID = 1, chance = 2, min = 1, max = 1 } }, price, 0), nil)
    H.eq(Core.likelyDisenchant(tie, price, 5), nil)
end)

H.test("rankByPointCost orders cheapest first, then no-point recipes, then unknown costs", function()
    local Core = H.newNS("Util", "Core").Core
    local order = Core.rankByPointCost({
        { cost = 5000, chance = 0.25 },   -- 1
        { cost = nil, chance = nil },     -- 2 unknown
        { cost = -300, chance = 1 },      -- 3 pays for itself
        { cost = nil, chance = 0 },       -- 4 grey
        { cost = 5000, chance = 0.75 },   -- 5 ties with 1
        { cost = math.huge - math.huge, chance = 0.25 },  -- 6 NaN: not rankable
        { cost = 20, chance = 1 },        -- 7
    })
    H.eq(order, { 3, 7, 1, 5, 4, 2, 6 })
    H.eq(Core.rankByPointCost({}), {})
end)

H.test("rankByNet puts the most profitable first, unknown results last, ties in original order", function()
    local Core = H.newNS("Util", "Core").Core
    H.eq(Core.rankByNet({ { net = -500 }, {}, { net = 40 }, { net = -20 }, { net = 40 }, { net = math.huge - math.huge } }),
        { 3, 5, 4, 1, 2, 6 })
    H.eq(Core.rankByNet({}), {})
end)

H.test("rankBySpeed puts the likeliest point first, the cheapest among equals, no-point and unknown last", function()
    local Core = H.newNS("Util", "Core").Core
    H.eq(Core.rankBySpeed({
        { chance = 0.25, cost = -500 },       -- 1
        { chance = 1, cost = 900 },           -- 2
        { chance = 0 },                       -- 3
        { chance = 0.75, cost = 100 },        -- 4
        {},                                   -- 5
        { chance = 1, cost = 300 },           -- 6 same chance as 2, cheaper
        { chance = 0.75 },                    -- 7 same chance as 4, cost unknown
    }), { 6, 2, 4, 7, 1, 3, 5 })
    H.eq(Core.rankBySpeed({}), {})
end)
