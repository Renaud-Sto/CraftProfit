local H = ...

local function load()
    local ns = H.newNS("Util", "Format", "Core", "Data/Skillup", "Data/Disenchant", "Evaluate", "Present",
        "Locale", "Locales/enUS", "Locales/frFR")
    ns.Locale.select("enUS")
    return ns
end

local RECIPE = {
    recipeID = 1, name = "Sword", difficulty = "medium", outputItemID = 100, outputQty = 1,
    reagents = { { itemID = 1, qty = 2 }, { itemID = 2, qty = 1 } },
}

local function run(ns, over)
    local map = { [1] = { 100, 60 }, [2] = { 50, 120 }, [100] = { 1000, 30 }, [200] = { 400, 10 } }
    local ctx = {
        recipe = RECIPE,
        priceOf = function(id) local r = map[id]; if r then return r[1], r[2] end end,
        itemInfo = function() return { quality = 2, ilvl = 15, sellPrice = 200, classID = 2, bindType = 2 } end,
        cut = 0.05, showPerPoint = false,
        lookupDisenchant = function() return { { itemID = 200, chance = 1, min = 1, max = 1 } } end,
    }
    for k, v in pairs(over or {}) do ctx[k] = v end
    return ns.Evaluate.run(ctx)
end

local function model(ns, over, opts)
    return ns.Present.build(run(ns, over), ns.L, ns.Format.money, opts)
end

H.test("lines show cost and every option, marking the best", function()
    local ns = load()
    local m = model(ns)
    H.eq(m.lines[1], { label = "Materials", value = "2s 50c", key = "cost", best = false })
    H.eq(m.lines[2], { label = "Auction house (net)", value = "9s 50c", key = "ah", best = true })
    H.eq(m.lines[3], { label = "Vendor", value = "2s", key = "vendor", best = false })
    H.eq(m.lines[4], { label = "Disenchant (beta)", value = "3s 80c", key = "disenchant", best = false })
    H.eq(#m.lines, 4)
end)

H.test("costLines detail each reagent for the fold-out under Materials", function()
    local ns = load()
    H.eq(model(ns).costLines, {
        { itemID = 1, qty = 2, unitText = "1s", subtotalText = "2s" },
        { itemID = 2, qty = 1, unitText = "50c", subtotalText = "50c" },
    })
    local missing = model(ns, { priceOf = function(id) if id == 2 then return nil end return 100, 1 end })
    H.eq(missing.costLines[2], { itemID = 2, qty = 1, unitText = "?", subtotalText = "?" })
end)

H.test("a profitable best option gives a profit verdict with a plus sign", function()
    local ns = load()
    H.eq(model(ns).verdict, { kind = "profit", text = "Best: Auction house", value = "+7s" })
end)

H.test("a loss gives a loss verdict", function()
    local ns = load()
    local m = model(ns, { priceOf = function(id) if id == 100 then return 100, 1 end return 100, 1 end,
        itemInfo = function() return { quality = 1, ilvl = 1, sellPrice = 0, classID = 0, bindType = 2 } end })
    H.eq(m.verdict.kind, "loss")
    H.eq(m.verdict.text, "Best: Auction house")
    H.eq(m.verdict.value, "-2s 5c")
end)

H.test("a missing price gives an incomplete verdict without a number", function()
    local ns = load()
    local m = model(ns, { priceOf = function(id) if id == 2 then return nil end return 100, 1 end })
    H.eq(m.verdict, { kind = "incomplete", text = "Incomplete: prices missing", value = "" })
    H.eq(m.lines[1].value, "?")
end)

H.test("an unknown option with a known cost shows the best known one as partial", function()
    local ns = load()
    local m = model(ns, { itemInfo = function() return nil end })
    H.eq(m.verdict.kind, "incomplete")
    H.eq(m.verdict.text, "Best known: Auction house (prices missing)")
    H.eq(m.verdict.value, "+7s")
    H.eq(m.lines[3].value, "?")
    H.eq(m.lines[4].value, "?")
end)

H.test("nothing sellable gives the none verdict and n/a lines", function()
    local ns = load()
    local m = model(ns, { itemInfo = function() return { quality = 1, ilvl = 1, sellPrice = 0, classID = 0, bindType = 1 } end })
    H.eq(m.verdict, { kind = "none", text = "No way to sell this item", value = "" })
    H.eq(m.lines[2].value, "n/a")
    H.eq(m.lines[3].value, "n/a")
    H.eq(m.lines[4].value, "n/a")
end)

H.test("the per-point line is labelled as an estimate", function()
    local ns = load()
    local m = model(ns, { showPerPoint = true })
    H.eq(m.lines[5], { label = "Cost per point", value = "-9s 33c (75%, estimate)", key = "perpoint", best = false })
end)

H.test("the per-point line shows n/a for trivial recipes and ? for unknown difficulty", function()
    local ns = load()
    local trivial = { recipeID = 1, name = "x", difficulty = "trivial", outputItemID = 100, outputQty = 1, reagents = RECIPE.reagents }
    local unknown = { recipeID = 1, name = "x", outputItemID = 100, outputQty = 1, reagents = RECIPE.reagents }
    H.eq(model(ns, { recipe = trivial, showPerPoint = true }).lines[5].value, "n/a")
    H.eq(model(ns, { recipe = unknown, showPerPoint = true }).lines[5].value, "?")
end)

H.test("ageText localizes the unit and handles a missing age", function()
    local ns = load()
    H.eq(ns.Present.ageText(ns.L, 65), "Prices: 1m ago")
    H.eq(ns.Present.ageText(ns.L, 3 * 3600), "Prices: 3h ago")
    H.eq(ns.Present.ageText(ns.L, nil), "Prices: never scanned")
    H.eq(ns.Present.ageText(ns.L, -5), "Prices: never scanned")
    ns.Locale.select("frFR")
    H.eq(ns.Present.ageText(ns.L, 65), "Prix : il y a 1min")
end)

H.test("durationText formats a duration or returns nil", function()
    local ns = load()
    H.eq(ns.Present.durationText(ns.L, 65), "1m")
    H.eq(ns.Present.durationText(ns.L, 900), "15m")
    H.eq(ns.Present.durationText(ns.L, nil), nil)
    H.eq(ns.Present.durationText(ns.L, 0 / 0), nil)
end)

H.test("prices older than staleAfter, or unknown, are flagged stale", function()
    local ns = load()
    H.eq(model(ns, nil, { staleAfter = 3600 }).stale, false)
    H.eq(model(ns, nil, { staleAfter = 100 }).stale, true)
    H.eq(model(ns, { priceOf = function() return nil end }, { staleAfter = 3600 }).stale, true)
end)
