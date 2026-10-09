local H = ...
local W = dofile("tests/fakewow.lua")

-- classID 0 on both outputs: disenchanting never applies, so the expected
-- item lists do not depend on the contents of the disenchant table.
local ITEMS = {
    [100] = { quality = 2, ilvl = 15, sellPrice = 200, classID = 0, bindType = 2 },
    [101] = { quality = 1, ilvl = 1, sellPrice = 10, classID = 0, bindType = 2 },
}

local function raw(id, output, reagents)
    return { recipeID = id, name = "R" .. id, difficulty = 1, outputItemID = output, reagents = reagents }
end

local function boot()
    local T = W.boot(H, { items = ITEMS })
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    local pins = T.env.CraftProfitCharDB.pins
    T.ns.DB.pinAdd(T.env.CraftProfitCharDB, raw(1, 100, { { itemID = 1, qty = 2 }, { itemID = 2, qty = 1 } }))
    T.ns.DB.pinAdd(T.env.CraftProfitCharDB, raw(2, 101, { { itemID = 2, qty = 3 }, { itemID = 3, qty = 1 } }))
    -- The AH adapter is replaced by a recorder: the queue's `send` goes through it.
    T.sent = {}
    T.ns.AH.search = function(id) T.sent[#T.sent + 1] = id; return true end
    return T, pins
end

local listing = { { unit = 10, qty = 1 }, { unit = 30, qty = 1 }, { unit = 20, qty = 1 } }

H.test("wantedFor lists each needed item once across all pins", function()
    local T = boot()
    local ids = T.ns.PinsUI.wantedFor(T.env.CraftProfitCharDB.pins, T.ns.Controller.itemInfo, T.ns.Data.Disenchant.lookup)
    H.eq(ids, { 1, 2, 100, 3, 101 })
end)

H.test("searching with the AH closed only reports it", function()
    local T = boot()
    T.ns.PinsUI.startSearch()
    H.eq(T.ns.PinsUI.status, "Open the auction house first")
    H.eq(T.sent, {})
    H.eq(T.ns.PinsUI.state, "idle")
end)

H.test("a search walks every item and stores the median prices", function()
    local T = boot()
    local P = T.ns.PinsUI
    T.ns.AH.isOpen = true
    P.startSearch()
    H.eq(P.state, "running")
    H.eq(T.sent, { 1 })
    for _, id in ipairs({ 1, 2, 100, 3, 101 }) do
        P.onSearchResults(id, listing)
    end
    H.eq(T.sent, { 1, 2, 100, 3, 101 })
    H.eq(P.state, "done")
    H.eq(P.status, "Prices updated")
    H.eq(T.ns.Controller.market().prices[1][1], 20)
    H.eq(T.ns.Controller.market().prices[101][1], 20)
    H.truthy(T.tickers[#T.tickers].cancelled)
end)

H.test("an item that never answers is reported at the end", function()
    local T = boot()
    local P = T.ns.PinsUI
    T.ns.AH.isOpen = true
    P.startSearch()
    P.onSearchResults(1, listing)
    -- 100 never answers; the ticker times it out after 6 s.
    for _, id in ipairs({ 2 }) do P.onSearchResults(id, listing) end
    T.clock = T.clock + 7
    T.tickers[#T.tickers].fn()
    P.onSearchResults(3, listing)
    P.onSearchResults(101, listing)
    H.eq(P.state, "done")
    H.eq(P.status, "Prices updated, 1 not found")
    H.eq(T.ns.Controller.market().prices[100], nil)
end)

H.test("closing the AH cancels a running search", function()
    local T = boot()
    local P = T.ns.PinsUI
    T.ns.AH.isOpen = true
    P.startSearch()
    P.onAHOpen(false)
    H.eq(P.state, "cancelled")
    H.eq(P.status, "Search cancelled")
    P.onSearchResults(1, listing)
    H.eq(T.ns.Controller.market().prices[1], nil)
end)

H.test("a second search does not start while one is running", function()
    local T = boot()
    local P = T.ns.PinsUI
    T.ns.AH.isOpen = true
    P.startSearch()
    P.startSearch()
    H.eq(T.sent, { 1 })
end)

H.test("results for items nobody asked about are ignored", function()
    local T = boot()
    T.ns.PinsUI.onSearchResults(1, listing)
    H.eq(T.ns.Controller.market().prices[1], nil)
end)

H.test("searching with no pins does nothing", function()
    local T = W.boot(H, { items = ITEMS })
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    T.ns.AH.isOpen = true
    T.ns.PinsUI.startSearch()
    H.eq(T.ns.PinsUI.state, "idle")
end)

H.test("scan reports a closed AH, a cooldown and a started scan", function()
    local T = boot()
    local P = T.ns.PinsUI
    P.scan()
    H.eq(P.status, "Open the auction house first")
    T.ns.AH.isOpen = true
    T.ns.AH.requestSnapshot = function() return false, "cooldown", 600 end
    P.scan()
    H.eq(P.status, "Full scan available in 10m")
    T.ns.AH.requestSnapshot = function() return true end
    P.scan()
    H.eq(P.status, "Scanning the auction house...")
end)

H.test("a finished scan stores prices and reports the count", function()
    local T = boot()
    local agg = T.ns.Prices.newAggregator()
    agg.add(1, 100, 1)
    agg.add(2, 50, 1)
    T.ns.Controller.onSnapshot(agg)
    H.eq(T.ns.PinsUI.status, "Scan complete: 2 items priced")
    H.eq(T.ns.Controller.market().prices[1][1], 100)
    H.truthy(T.ns.Controller.market().snapshotTime)
end)

H.test("opening the AH shows the pins and selects the first one", function()
    local T = boot()
    T.ns.AH.isOpen = true
    T.ns.Controller.onAHOpen(true)
    H.eq(T.ns.Controller.currentRecipeID(), 1)
    H.truthy(T.ns.Window.isShown())
    H.truthy(T.ns.Window.pinsHost():IsShown())
    T.ns.Controller.onAHOpen(false)
    H.falsy(T.ns.Window.isShown())
end)

H.test("selecting a pinned recipe shows it in the window", function()
    local T = boot()
    T.ns.AH.isOpen = true
    T.ns.Controller.onAHOpen(true)
    T.ns.Controller.selectPin(2)
    H.eq(T.ns.Controller.currentRecipeID(), 2)
    T.ns.Controller.selectPin(999)
    H.eq(T.ns.Controller.currentRecipeID(), 2)
end)

H.test("the pins list refreshes without errors when empty or large", function()
    local T = W.boot(H, { items = ITEMS })
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    T.ns.PinsUI.refresh()
    for i = 1, 12 do
        T.ns.DB.pinAdd(T.env.CraftProfitCharDB, raw(i, 100, { { itemID = 1, qty = 1 } }))
    end
    T.ns.PinsUI.refresh()
end)

-- Fix wave item 5
H.test("an empty AH listing counts as not found", function()
    local T = boot()
    local P = T.ns.PinsUI
    T.ns.AH.isOpen = true
    P.startSearch()
    P.onSearchResults(1, {})
    for _, id in ipairs({ 2, 100, 3, 101 }) do P.onSearchResults(id, listing) end
    H.eq(P.state, "done")
    H.eq(P.status, "Prices updated, 1 not found")
    P.startSearch()
    for _, id in ipairs({ 1, 2, 100, 3, 101 }) do P.onSearchResults(id, listing) end
    H.eq(P.status, "Prices updated")
end)

H.test("a scan the server never answers reports it, a scan it answers does not", function()
    local T = boot()
    local P = T.ns.PinsUI
    T.ns.AH.isOpen = true
    T.ns.AH.requestSnapshot = function() return true end
    P.scan()
    T.run()
    H.eq(P.status, "No reply from the server. A scan may be on its 15 minute cooldown")
    P.scan()
    T.ns.AH.onEvent("REPLICATE_ITEM_LIST_UPDATE")
    T.run()
    H.eq(P.status, "Scanning the auction house...")
end)

H.test("orderedPins sorts by net (most profitable first) or by cost per point (cheapest first)", function()
    local T = boot()
    local P = T.ns.PinsUI
    local pins = { { recipeID = 1 }, { recipeID = 2 }, { recipeID = 3 }, { recipeID = 4 }, { recipeID = 5 } }
    local results = {
        [1] = { net = -500, perPoint = { cost = 900, chance = 0.25 } },
        [2] = { net = 40, perPoint = { cost = nil, chance = 0 } },
        [3] = { net = -20, perPoint = { cost = 100, chance = 1 } },
        [4] = { perPoint = {} },
        [5] = { net = 40, perPoint = { cost = -50, chance = 1 } },
    }
    local function evaluate(recipe) return results[recipe.recipeID] end
    local function ids(list)
        local out = {}
        for i, item in ipairs(list) do out[i] = item.recipe.recipeID end
        return out
    end
    H.eq(ids(P.orderedPins(pins, "net", evaluate)), { 2, 5, 3, 1, 4 })
    H.eq(ids(P.orderedPins(pins, "point", evaluate)), { 5, 3, 1, 2, 4 })
    H.eq(P.orderedPins(pins, "point", evaluate)[1].result, results[5])
end)

H.test("the pins list refreshes in both sort modes without errors", function()
    local T = boot()
    T.ns.AH.isOpen = true
    T.ns.Controller.onAHOpen(true)
    T.ns.Controller.toggleSort()
    T.ns.PinsUI.refresh()
    T.ns.Controller.toggleSort()
    T.ns.PinsUI.refresh()
end)
