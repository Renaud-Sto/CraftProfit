local H = ...

local function load() return H.newNS("Util", "Prices").Prices end

H.test("summarize takes the median of the cheapest units", function()
    local P = load()
    local listings = { { unit = 1000, qty = 1 }, { unit = 10, qty = 1 }, { unit = 20, qty = 1 } }
    H.eq({ P.summarize(listings, 5) }, { 20, 3 })
    H.eq({ P.summarize(listings, 1) }, { 10, 3 })
    H.eq({ P.summarize(listings, 2) }, { 15, 3 })
end)

H.test("summarize weights listings by quantity without looping over units", function()
    local P = load()
    H.eq({ P.summarize({ { unit = 5, qty = 100 }, { unit = 50, qty = 1 } }, 5) }, { 5, 101 })
    H.eq({ P.summarize({ { unit = 3, qty = 1e9 } }, 5) }, { 3, 1e9 })
end)

H.test("summarize ignores invalid listings", function()
    local P = load()
    local listings = {
        { unit = 0 / 0, qty = 1 }, { unit = 0, qty = 1 }, { unit = -5, qty = 1 },
        { unit = 40, qty = 0 }, { unit = 40 }, { qty = 3 }, { unit = 1 / 0, qty = 1 },
        { unit = 40, qty = 2 },
    }
    H.eq({ P.summarize(listings, 5) }, { 40, 2 })
end)

H.test("summarize with nothing usable returns nil and zero volume", function()
    local P = load()
    H.eq({ P.summarize({}, 5) }, { nil, 0 })
    H.eq({ P.summarize(nil, 5) }, { nil, 0 })
    H.eq({ P.summarize({ { unit = 0, qty = 1 } }, 5) }, { nil, 0 })
end)

H.test("summarize falls back to 5 units for an invalid n", function()
    local P = load()
    local listings = {}
    for i = 1, 9 do listings[i] = { unit = i * 10, qty = 1 } end
    H.eq(P.summarize(listings, nil), 30)
    H.eq(P.summarize(listings, 0), 30)
    H.eq(P.summarize(listings, 0 / 0), 30)
end)

H.test("the aggregator groups rows by item and skips invalid ones", function()
    local P = load()
    local agg = P.newAggregator()
    agg.add(1, 100, 1)
    agg.add(1, 300, 1)
    agg.add(1, 200, 1)
    agg.add(2, 50, 4)
    agg.add(nil, 10, 1)
    agg.add(3, 0 / 0, 1)
    agg.add(4, 10, 0)
    H.eq(agg.result(5), { [1] = { unit = 200, volume = 3 }, [2] = { unit = 50, volume = 4 } })
end)

H.test("store writes a compact row and rejects invalid input", function()
    local P = load()
    local db = { prices = {} }
    H.eq(P.store(db, 7, 123.4, 3, 1000), true)
    H.eq(db.prices[7], { 123, 3, 1000 })
    H.eq(P.store(db, 8, 0 / 0, 3, 1000), false)
    H.eq(P.store(db, 8, 0, 3, 1000), false)
    H.eq(P.store(db, 8, 10, 3, 0 / 0), false)
    H.eq(P.store(db, "x", 10, 3, 1000), false)
    H.eq(db.prices[8], nil)
end)

H.test("get returns the price and its age", function()
    local P = load()
    local db = { prices = {} }
    P.store(db, 7, 500, 4, 1000)
    H.eq({ P.get(db, 7, 1090) }, { 500, 90, 4 })
    H.eq({ P.get(db, 99, 1090) }, {})
end)

H.test("get keeps the price but reports no age when the clock went backwards", function()
    local P = load()
    local db = { prices = {} }
    P.store(db, 7, 500, 4, 1000)
    H.eq({ P.get(db, 7, 900) }, { 500, nil, 4 })
    H.eq({ P.get(db, 7, 0 / 0) }, { 500, nil, 4 })
    H.eq({ P.get(db, 7, nil) }, { 500, nil, 4 })
end)

H.test("get ignores a corrupt row", function()
    local P = load()
    local db = { prices = { [7] = { 0 / 0, 1, 10 }, [8] = "bad", [9] = { -5, 1, 10 } } }
    H.eq({ P.get(db, 7, 20) }, {})
    H.eq({ P.get(db, 8, 20) }, {})
    H.eq({ P.get(db, 9, 20) }, {})
end)

H.test("merge stores a snapshot result and remembers when", function()
    local P = load()
    local db = { prices = {} }
    local count = P.merge(db, { [1] = { unit = 10, volume = 2 }, [2] = { unit = 0 / 0, volume = 1 } }, 2000)
    H.eq(count, 1)
    H.eq(db.prices[1], { 10, 2, 2000 })
    H.eq(db.snapshotTime, 2000)
    H.eq(P.merge(db, {}, 0 / 0), 0)
    H.eq(db.snapshotTime, 2000)
end)

H.test("priceOf and snapshotAge read through the same rules", function()
    local P = load()
    local db = { prices = {} }
    P.store(db, 7, 500, 4, 1000)
    H.eq({ P.priceOf(db, 1060)(7) }, { 500, 60 })
    H.eq({ P.priceOf(db, 1060)(8) }, {})
    H.eq(P.snapshotAge(db, 1060), nil)
    db.snapshotTime = 1000
    H.eq(P.snapshotAge(db, 1060), 60)
    H.eq(P.snapshotAge(db, 900), nil)
end)
