local H = ...

-- Loads AHAdapter in a fake game environment. Returns a table with the adapter,
-- what the handlers received, the calls the adapter made, and helpers.
local function setup(apiOver)
    local ns = H.newNS("Util", "Prices")
    local env = setmetatable({}, { __index = _G })
    local T = { clock = 100, queued = {}, calls = {}, frames = {}, opens = {}, searches = {}, snapshots = {} }
    env.GetTime = function() return T.clock end
    env.CreateFrame = function()
        local f = { events = {}, scripts = {} }
        function f.RegisterEvent(_, e) f.events[#f.events + 1] = e end
        function f.SetScript(_, name, fn) f.scripts[name] = fn end
        T.frames[#T.frames + 1] = f
        return f
    end
    env.C_Timer = { After = function(_, fn) T.queued[#T.queued + 1] = fn end }
    env.Enum = { AuctionHouseSortOrder = { Price = 4 } }
    env.C_AuctionHouse = {
        MakeItemKey = function(id) return { itemID = id } end,
        SendSearchQuery = function(key, sorts, separate)
            T.calls[#T.calls + 1] = { "search", key.itemID, sorts, separate }
        end,
        IsThrottledMessageSystemReady = function() return true end,
        ReplicateItems = function() T.calls[#T.calls + 1] = { "replicate" } end,
        GetNumReplicateItems = function() return 0 end,
        GetReplicateItemInfo = function() end,
    }
    for k, v in pairs(apiOver or {}) do env.C_AuctionHouse[k] = v end
    H.loadModule("AHAdapter", ns, env)
    local AH = ns.AH
    AH.setHandlers({
        onOpen = function(open) T.opens[#T.opens + 1] = open end,
        onSearch = function(id, listings) T.searches[#T.searches + 1] = { id, listings } end,
        onSnapshot = function(agg, total) T.snapshots[#T.snapshots + 1] = { agg, total } end,
    })
    T.AH, T.env = AH, env
    -- Runs every callback scheduled with C_Timer.After, including ones they schedule.
    function T.run()
        while #T.queued > 0 do table.remove(T.queued, 1)() end
    end
    return T
end

-- 17-value rows like GetReplicateItemInfo: only count, buyout and itemID matter.
local function replicate(rows)
    return {
        GetNumReplicateItems = function() return #rows end,
        GetReplicateItemInfo = function(i)
            local r = rows[i]
            return "name", 0, r.count, 1, true, 1, 0, 0, 0, r.buyout, 0, false, "", "o", "o", 0, r.itemID, true
        end,
    }
end

H.test("the adapter registers the events it needs on load", function()
    local T = setup()
    local seen = {}
    for _, e in ipairs(T.frames[1].events) do seen[e] = true end
    for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "COMMODITY_SEARCH_RESULTS_UPDATED",
        "ITEM_SEARCH_RESULTS_UPDATED", "REPLICATE_ITEM_LIST_UPDATE" }) do
        H.truthy(seen[e] or error("event not registered: " .. e))
    end
    H.truthy(T.frames[1].scripts.OnEvent)
end)

H.test("opening and closing the AH is tracked and reported", function()
    local T = setup()
    H.eq(T.AH.isOpen, false)
    T.AH.onEvent("AUCTION_HOUSE_SHOW")
    H.eq(T.AH.isOpen, true)
    T.AH.onEvent("AUCTION_HOUSE_CLOSED")
    H.eq(T.AH.isOpen, false)
    H.eq(T.opens, { true, false })
end)

H.test("search needs an open, unthrottled AH and sends a price-sorted query", function()
    local T = setup()
    H.eq(T.AH.search(7), false)
    T.AH.onEvent("AUCTION_HOUSE_SHOW")
    H.eq(T.AH.search(7), true)
    H.eq(T.calls[1], { "search", 7, { { sortOrder = 4, reverseSort = false } }, true })
    T.env.C_AuctionHouse.IsThrottledMessageSystemReady = function() return false end
    H.eq(T.AH.search(8), false)
    H.eq(#T.calls, 1)
end)

H.test("search reports failure instead of raising when the API errors", function()
    local T = setup({ SendSearchQuery = function() error("boom") end })
    T.AH.onEvent("AUCTION_HOUSE_SHOW")
    H.eq(T.AH.search(7), false)
end)

H.test("commodity results become unit/qty listings", function()
    local T = setup({
        GetNumCommoditySearchResults = function() return 2 end,
        GetCommoditySearchResultInfo = function(_, i)
            return ({ { unitPrice = 100, quantity = 5 }, { unitPrice = 120, quantity = 1 } })[i]
        end,
    })
    T.AH.onEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 7)
    H.eq(T.searches, { { 7, { { unit = 100, qty = 5 }, { unit = 120, qty = 1 } } } })
end)

H.test("item results use the buyout per unit and skip bid-only auctions", function()
    local T = setup({
        GetNumItemSearchResults = function() return 3 end,
        GetItemSearchResultInfo = function(_, i)
            return ({ { buyoutAmount = 100, quantity = 1 }, { buyoutAmount = 100, quantity = 2 }, { quantity = 1 } })[i]
        end,
    })
    T.AH.onEvent("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 7 })
    H.eq(T.searches, { { 7, { { unit = 100, qty = 1 }, { unit = 50, qty = 2 } } } })
end)

H.test("search results are capped and invalid events are ignored", function()
    local T = setup({
        GetNumCommoditySearchResults = function() return 250 end,
        GetCommoditySearchResultInfo = function() return { unitPrice = 1, quantity = 1 } end,
    })
    T.AH.onEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 7)
    H.eq(#T.searches[1][2], T.AH.MAX_SEARCH_RESULTS)
    T.AH.onEvent("COMMODITY_SEARCH_RESULTS_UPDATED", "x")
    T.AH.onEvent("ITEM_SEARCH_RESULTS_UPDATED", nil)
    T.AH.onEvent("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 0 / 0 })
    H.eq(#T.searches, 1)
end)

H.test("secret search values are skipped", function()
    local T = setup({
        GetNumCommoditySearchResults = function() return 2 end,
        GetCommoditySearchResultInfo = function(_, i)
            return ({ { unitPrice = "SECRET", quantity = 1 }, { unitPrice = 90, quantity = 1 } })[i]
        end,
    })
    T.env.issecretvalue = function(v) return v == "SECRET" end
    T.AH.onEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 7)
    H.eq(T.searches[1][2], { { unit = 90, qty = 1 } })
end)

H.test("a full scan is read in chunks and aggregated per item", function()
    local T = setup(replicate({
        { itemID = 1, count = 1, buyout = 100 },
        { itemID = 1, count = 1, buyout = 300 },
        { itemID = 2, count = 5, buyout = 500 },
        { itemID = 3, count = 1, buyout = 0 },
        { itemID = 4, count = 0, buyout = 10 },
    }))
    T.AH.CHUNK = 2
    T.AH.onEvent("REPLICATE_ITEM_LIST_UPDATE")
    H.eq(#T.snapshots, 0)
    T.run()
    H.eq(#T.snapshots, 1)
    H.eq(T.snapshots[1][2], 5)
    H.eq(T.snapshots[1][1].result(5), {
        [1] = { unit = 200, volume = 2 },
        [2] = { unit = 100, volume = 5 },
    })
end)

H.test("a stack buyout is divided per unit unless the client reports per-unit prices", function()
    local T = setup(replicate({ { itemID = 2, count = 5, buyout = 500 } }))
    T.AH.PER_UNIT_REPLICATE = true
    T.AH.onEvent("REPLICATE_ITEM_LIST_UPDATE")
    T.run()
    H.eq(T.snapshots[1][1].result(5)[2], { unit = 500, volume = 5 })
end)

H.test("secret scan rows are skipped", function()
    local T = setup(replicate({
        { itemID = 1, count = "SECRET", buyout = 100 },
        { itemID = 2, count = 1, buyout = 40 },
    }))
    T.env.issecretvalue = function(v) return v == "SECRET" end
    T.AH.onEvent("REPLICATE_ITEM_LIST_UPDATE")
    T.run()
    H.eq(T.snapshots[1][1].result(5), { [2] = { unit = 40, volume = 1 } })
end)

H.test("closing the AH abandons a scan in progress", function()
    local T = setup(replicate({
        { itemID = 1, count = 1, buyout = 100 }, { itemID = 2, count = 1, buyout = 100 },
        { itemID = 3, count = 1, buyout = 100 },
    }))
    T.AH.CHUNK = 1
    T.AH.onEvent("AUCTION_HOUSE_SHOW")
    T.AH.onEvent("REPLICATE_ITEM_LIST_UPDATE")
    T.AH.onEvent("AUCTION_HOUSE_CLOSED")
    T.run()
    H.eq(#T.snapshots, 0)
end)

H.test("a new scan supersedes one still being read", function()
    local T = setup(replicate({
        { itemID = 1, count = 1, buyout = 100 }, { itemID = 2, count = 1, buyout = 100 },
    }))
    T.AH.CHUNK = 1
    T.AH.onEvent("REPLICATE_ITEM_LIST_UPDATE")
    T.AH.onEvent("REPLICATE_ITEM_LIST_UPDATE")
    T.run()
    H.eq(#T.snapshots, 1)
end)

H.test("an empty scan produces no snapshot", function()
    local T = setup()
    T.AH.onEvent("REPLICATE_ITEM_LIST_UPDATE")
    T.run()
    H.eq(#T.snapshots, 0)
end)

H.test("requestSnapshot respects the AH state and the 15 minute cooldown", function()
    local T = setup()
    H.eq({ T.AH.requestSnapshot(100) }, { false, "closed" })
    T.AH.onEvent("AUCTION_HOUSE_SHOW")
    H.eq({ T.AH.requestSnapshot(100) }, { true })
    H.eq(T.calls[1], { "replicate" })
    H.eq({ T.AH.requestSnapshot(400) }, { false, "cooldown", 600 })
    H.eq({ T.AH.requestSnapshot(1000) }, { true })
end)

H.test("a scan started by another addon also starts the cooldown", function()
    local T = setup()
    T.AH.onEvent("AUCTION_HOUSE_SHOW")
    T.clock = 100
    T.AH.onEvent("REPLICATE_ITEM_LIST_UPDATE")
    H.eq({ T.AH.requestSnapshot(400) }, { false, "cooldown", 600 })
end)

H.test("requestSnapshot reports an unavailable API", function()
    local T = setup({ ReplicateItems = false })
    T.AH.onEvent("AUCTION_HOUSE_SHOW")
    H.eq({ T.AH.requestSnapshot(100) }, { false, "unavailable" })
    H.eq(T.AH.cooldownLeft(0 / 0), 0)
end)

-- Field report: the client fires REPLICATE_ITEM_LIST_UPDATE hundreds of times per scan.
H.test("a burst of replicate events produces one read, after the debounce delay", function()
    local reads = 0
    local api = replicate({ { itemID = 1, count = 1, buyout = 100 } })
    local info = api.GetNumReplicateItems
    api.GetNumReplicateItems = function() reads = reads + 1; return info() end
    local T = setup(api)
    for _ = 1, 500 do T.AH.onEvent("REPLICATE_ITEM_LIST_UPDATE") end
    H.eq(#T.queued, 1)
    T.run()
    H.eq(reads, 1)
    H.eq(#T.snapshots, 1)
end)

H.test("replicate events during a read and just after it do not restart it", function()
    local T = setup(replicate({
        { itemID = 1, count = 1, buyout = 100 }, { itemID = 2, count = 1, buyout = 100 },
        { itemID = 3, count = 1, buyout = 100 },
    }))
    T.AH.CHUNK = 1
    T.AH.onEvent("REPLICATE_ITEM_LIST_UPDATE")
    table.remove(T.queued, 1)()
    T.AH.onEvent("REPLICATE_ITEM_LIST_UPDATE")
    T.run()
    H.eq(#T.snapshots, 1)
    T.clock = T.clock + 3
    T.AH.onEvent("REPLICATE_ITEM_LIST_UPDATE")
    T.run()
    H.eq(#T.snapshots, 1)
end)

H.test("a later scan is read once the quiet period has passed", function()
    local T = setup(replicate({ { itemID = 1, count = 1, buyout = 100 } }))
    T.AH.onEvent("REPLICATE_ITEM_LIST_UPDATE")
    T.run()
    T.clock = T.clock + T.AH.REREAD_QUIET + 1
    T.AH.onEvent("REPLICATE_ITEM_LIST_UPDATE")
    T.run()
    H.eq(#T.snapshots, 2)
end)

-- Click a reagent: search it in the AH's own search bar, never buy
local function fakeAHFrame(T)
    local f = { calls = {} }
    f.SearchBar = {
        SearchBox = { SetText = function(_, t) f.calls[#f.calls + 1] = { "text", t } end },
        StartSearch = function() f.calls[#f.calls + 1] = { "search" } end,
    }
    f.SetDisplayMode = function(_, mode) f.calls[#f.calls + 1] = { "mode", mode } end
    f.quantity = {}
    f.CommoditiesBuyFrame = {
        BuyDisplay = { QuantityInput = { SetQuantity = function(_, n) f.quantity[#f.quantity + 1] = n end } },
        HookScript = function(_, name, fn) f.onShow = name == "OnShow" and fn or f.onShow end,
    }
    T.env.AuctionHouseFrame = f
    T.env.AuctionHouseFrameDisplayMode = { Buy = 7 }
    return f
end

H.test("browse needs the AH open and the AH search bar", function()
    local T = setup()
    H.eq({ T.AH.browse("Bronze Bar", 2841, 20) }, { false, "closed" })
    T.AH.onEvent("AUCTION_HOUSE_SHOW")
    H.eq({ T.AH.browse("Bronze Bar", 2841, 20) }, { false, "unavailable" })
    T.env.AuctionHouseFrame = {}
    H.eq({ T.AH.browse("Bronze Bar", 2841, 20) }, { false, "unavailable" })
end)

H.test("browse switches to the buy view, fills the search box and starts the search", function()
    local T = setup()
    local f = fakeAHFrame(T)
    T.AH.onEvent("AUCTION_HOUSE_SHOW")
    H.eq({ T.AH.browse("Bronze Bar", 2841, 20) }, { true })
    H.eq(f.calls, { { "mode", 7 }, { "text", "Bronze Bar" }, { "search" } })
end)

H.test("the wanted quantity is preset once, when the commodity buy view opens", function()
    local T = setup()
    local f = fakeAHFrame(T)
    T.AH.onEvent("AUCTION_HOUSE_SHOW")
    T.AH.browse("Bronze Bar", 2841, 20)
    H.truthy(f.onShow)
    f.onShow()
    T.run()
    H.eq(f.quantity, { 20 })
    f.onShow()
    T.run()
    H.eq(f.quantity, { 20 })
end)

H.test("the quantity is not preset for another item, nor after it expired", function()
    local T = setup()
    local f = fakeAHFrame(T)
    T.AH.onEvent("AUCTION_HOUSE_SHOW")
    T.AH.browse("Bronze Bar", 2841, 20)
    f.CommoditiesBuyFrame.GetItemID = function() return 999 end
    f.onShow()
    T.run()
    H.eq(f.quantity, {})
    T.AH.browse("Bronze Bar", 2841, 20)
    f.CommoditiesBuyFrame.GetItemID = function() return 2841 end
    T.clock = T.clock + 61
    f.onShow()
    T.run()
    H.eq(f.quantity, {})
end)

H.test("a failing Blizzard frame never raises", function()
    local T = setup()
    local f = fakeAHFrame(T)
    f.SearchBar.StartSearch = function() error("boom") end
    T.AH.onEvent("AUCTION_HOUSE_SHOW")
    H.eq({ T.AH.browse("Bronze Bar", 2841, 20) }, { false, "unavailable" })
end)

H.test("the preset quantity is announced to the buy view like typed input", function()
    local T = setup()
    local f = fakeAHFrame(T)
    local typed = {}
    f.CommoditiesBuyFrame.BuyDisplay.QuantityInput.InputBox = {
        GetScript = function(_, name)
            if name == "OnTextChanged" then return function(_, userInput) typed[#typed + 1] = userInput end end
        end,
    }
    T.AH.onEvent("AUCTION_HOUSE_SHOW")
    T.AH.browse("Bronze Bar", 2841, 20)
    f.onShow()
    T.run()
    H.eq(f.quantity, { 20 })
    H.eq(typed, { true })
end)
