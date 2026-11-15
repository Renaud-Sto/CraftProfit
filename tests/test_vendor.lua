local H = ...

local function load() return H.newNS("Util", "Data/VendorPrices", "Vendor").Vendor end

local function entry(over)
    local e = { itemID = 3372, price = 40, stack = 1, numAvailable = -1, extendedCost = false, purchasable = true }
    for k, v in pairs(over or {}) do e[k] = v end
    return e
end

H.test("unitOf divides the price by the stack sold", function()
    local V = load()
    H.eq(V.unitOf(entry()), 40)
    H.eq(V.unitOf(entry({ price = 50, stack = 5 })), 10)
    H.eq(V.unitOf(entry({ price = 10, stack = 4 })), 3)
    -- A unit never rounds down to free.
    H.eq(V.unitOf(entry({ price = 1, stack = 5 })), 1)
    -- A missing or broken stack counts as one.
    H.eq(V.unitOf(entry({ stack = 0 })), 40)
end)

H.test("unitOf refuses limited stock, token costs, unpurchasable items and bad prices", function()
    local V = load()
    H.eq(V.unitOf(entry({ numAvailable = 3 })), nil)
    H.eq(V.unitOf(entry({ numAvailable = 0 })), nil)
    H.eq(V.unitOf(entry({ numAvailable = "x" })), nil)
    H.eq(V.unitOf(entry({ extendedCost = true })), nil)
    H.eq(V.unitOf(entry({ purchasable = false })), nil)
    for _, bad in ipairs({ 0, -1, 0 / 0, 1 / 0, "40", 1e14 }) do
        H.eq(V.unitOf(entry({ price = bad })), nil)
    end
    H.eq(V.unitOf(entry({ itemID = 0 })), nil)
    H.eq(V.unitOf(entry({ itemID = 1.5 })), nil)
    H.eq(V.unitOf(nil), nil)
end)

H.test("record stores new prices and counts only real changes", function()
    local V = load()
    local store = {}
    H.eq(V.record(store, { entry(), entry({ itemID = 2320, price = 10 }) }, 1000), 2)
    H.eq(store[3372], { 40, 1000 })
    -- Same price again: no change, the time moves on.
    H.eq(V.record(store, { entry() }, 2000), 0)
    H.eq(store[3372], { 40, 2000 })
    -- A new price (another character's reputation discount, a patch) replaces it.
    H.eq(V.record(store, { entry({ price = 36 }) }, 3000), 1)
    H.eq(store[3372], { 36, 3000 })
end)

H.test("record skips entries it cannot use and keeps an older usable price", function()
    local V = load()
    local store = { [3372] = { 40, 1000 } }
    H.eq(V.record(store, { entry({ numAvailable = 2, price = 5 }), entry({ extendedCost = true, itemID = 9 }) }, 2000), 0)
    H.eq(store[3372], { 40, 1000 })
    H.eq(store[9], nil)
end)

H.test("record refuses bad arguments", function()
    local V = load()
    H.eq(V.record(nil, { entry() }, 1), 0)
    H.eq(V.record({}, nil, 1), 0)
    H.eq(V.record({}, { entry() }, 0 / 0), 0)
end)

H.test("record stops adding items at MAX_ITEMS but still updates known ones", function()
    local V = load()
    local store = {}
    for i = 1, V.MAX_ITEMS do store[i] = { 5, 1 } end
    H.eq(V.record(store, { entry({ itemID = V.MAX_ITEMS + 1 }) }, 2), 0)
    H.eq(store[V.MAX_ITEMS + 1], nil)
    H.eq(V.record(store, { entry({ itemID = 1, price = 7 }) }, 2), 1)
    H.eq(store[1], { 7, 2 })
end)

H.test("get prefers a price seen at a merchant over the listed one", function()
    local V = load()
    H.eq({ V.get({}, 3372, 5000) }, { 40, "listed", nil })
    H.eq({ V.get({ [3372] = { 36, 1000 } }, 3372, 5000) }, { 36, "seen", 4000 })
    H.eq({ V.get({}, 123456, 5000) }, {})
    -- A time in the future: the price stays, its age is unknown.
    H.eq({ V.get({ [3372] = { 36, 9000 } }, 3372, 5000) }, { 36, "seen", nil })
    -- A broken row falls back to the list.
    H.eq({ V.get({ [3372] = { 0, 1000 } }, 3372, 5000) }, { 40, "listed", nil })
    H.eq({ V.get(nil, 3372, 5000) }, { 40, "listed", nil })
end)

H.test("cheapest picks the lower price and gives ties to the vendor", function()
    local V = load()
    H.eq({ V.cheapest(488, 40) }, { 40, "vendor" })
    H.eq({ V.cheapest(30, 40) }, { 30, "ah" })
    H.eq({ V.cheapest(40, 40) }, { 40, "vendor" })
    H.eq({ V.cheapest(nil, 40) }, { 40, "vendor" })
    H.eq({ V.cheapest(30, nil) }, { 30, "ah" })
    H.eq({ V.cheapest(nil, nil) }, {})
    H.eq({ V.cheapest(30, 0) }, { 30, "ah" })
    H.eq({ V.cheapest(0 / 0, 40) }, { 40, "vendor" })
end)

H.test("sanitize keeps valid rows and drops the rest in place", function()
    local V = load()
    local store = {
        [3372] = { 40, 1000, "junk" }, [2320] = { 10.4, 5 },
        [1] = { 0, 1 }, [2] = { 5 }, [3] = "x", [4] = { 1 / 0, 1 }, ["5"] = { 5, 1 }, [6.5] = { 5, 1 },
    }
    local same = V.sanitize(store)
    H.truthy(same == store)
    H.eq(store, { [3372] = { 40, 1000 }, [2320] = { 10, 5 } })
    H.eq(V.sanitize(nil), {})
    H.eq(V.sanitize("x"), {})
end)

H.test("the listed prices are valid copper amounts on item ids", function()
    local ns = H.newNS("Util", "Data/VendorPrices", "Vendor")
    local count = 0
    for id, unit in pairs(ns.Data.VendorPrices) do
        H.truthy(ns.Util.id(id) == id)
        H.truthy(ns.Util.isCopper(unit) and unit > 0)
        count = count + 1
    end
    H.truthy(count > 20)
    -- The reported case.
    H.eq(ns.Data.VendorPrices[3372], 40)
end)
