local H = ...

-- Loads MerchantAdapter in a fake game with `items` on sale: { itemID, price, stack,
-- numAvailable, extended, purchasable }. `modern` false hides C_MerchantFrame.
local function setup(items, modern)
    local env = setmetatable({}, { __index = _G })
    local ns = {}
    H.loadModule("Util", ns, env)
    local T = { queued = {}, frames = {}, received = {} }
    env.CreateFrame = function()
        local f = { events = {}, scripts = {} }
        function f.RegisterEvent(_, e) f.events[#f.events + 1] = e end
        function f.SetScript(_, name, fn) f.scripts[name] = fn end
        T.frames[#T.frames + 1] = f
        return f
    end
    env.C_Timer = { After = function(_, fn) T.queued[#T.queued + 1] = fn end }
    env.GetMerchantNumItems = function() return #items end
    env.GetMerchantItemID = function(i) return items[i] and items[i].itemID end
    if modern ~= false then
        env.C_MerchantFrame = {
            GetItemInfo = function(i)
                local it = items[i]
                return {
                    name = "x", texture = 1, price = it.price, stackCount = it.stack or 1,
                    numAvailable = it.numAvailable or -1, isPurchasable = it.purchasable ~= false,
                    isUsable = true, hasExtendedCost = it.extended == true,
                }
            end,
        }
    end
    env.GetMerchantItemInfo = function(i)
        local it = items[i]
        return "x", 1, it.price, it.stack or 1, it.numAvailable or -1, it.purchasable ~= false, true,
            it.extended == true
    end
    H.loadModule("MerchantAdapter", ns, env)
    ns.Merchant.setHandlers({ onItems = function(entries) T.received[#T.received + 1] = entries end })
    T.M, T.env = ns.Merchant, env
    function T.run()
        while #T.queued > 0 do table.remove(T.queued, 1)() end
    end
    return T
end

local SALE = {
    { itemID = 3372, price = 40 },
    { itemID = 2320, price = 50, stack = 5 },
    { itemID = 999, price = 100, numAvailable = 2 },
}

H.test("the adapter listens to the merchant window events", function()
    local T = setup(SALE)
    local seen = {}
    for _, e in ipairs(T.frames[1].events) do seen[e] = true end
    H.truthy(seen.MERCHANT_SHOW and seen.MERCHANT_UPDATE and seen.MERCHANT_CLOSED)
end)

H.test("opening a merchant reads every slot once, after the burst", function()
    local T = setup(SALE)
    T.M.onEvent("MERCHANT_SHOW")
    T.M.onEvent("MERCHANT_UPDATE")
    T.M.onEvent("MERCHANT_UPDATE")
    T.run()
    H.eq(#T.received, 1)
    local e = T.received[1]
    H.eq(#e, 3)
    H.eq(e[1], { itemID = 3372, price = 40, stack = 1, numAvailable = -1, extendedCost = false, purchasable = true })
    H.eq(e[2].stack, 5)
    H.eq(e[3].numAvailable, 2)
end)

H.test("the older GetMerchantItemInfo is used when C_MerchantFrame is missing", function()
    local T = setup(SALE, false)
    T.M.onEvent("MERCHANT_SHOW")
    T.run()
    H.eq(T.received[1][2], { itemID = 2320, price = 50, stack = 5, numAvailable = -1, extendedCost = false, purchasable = true })
end)

H.test("closing the merchant drops a pending read; updates while closed do nothing", function()
    local T = setup(SALE)
    T.M.onEvent("MERCHANT_SHOW")
    T.M.onEvent("MERCHANT_CLOSED")
    T.run()
    T.M.onEvent("MERCHANT_UPDATE")
    T.run()
    H.eq(#T.received, 0)
    H.eq(T.M.isOpen, false)
end)

H.test("unreadable slots are skipped and a raising API is survived", function()
    local T = setup({ { itemID = 3372, price = 40 }, { itemID = nil, price = 5 } })
    T.M.onEvent("MERCHANT_SHOW")
    T.run()
    H.eq(#T.received[1], 1)
    T.env.GetMerchantNumItems = function() error("boom") end
    T.M.onEvent("MERCHANT_UPDATE")
    T.run()
    H.eq(#T.received, 1)
end)

H.test("secret values are dropped, never compared", function()
    local T = setup({ { itemID = 3372, price = 40 } })
    local secret = {}
    T.env.issecretvalue = function(v) return v == secret end
    T.env.C_MerchantFrame.GetItemInfo = function()
        return { price = secret, stackCount = 1, numAvailable = -1, isPurchasable = true, hasExtendedCost = false }
    end
    T.M.onEvent("MERCHANT_SHOW")
    T.run()
    H.eq(T.received[1][1].price, nil)
end)

H.test("end to end: a merchant visit fills the vendor table through Vendor.record", function()
    local T = setup(SALE)
    local ns = H.newNS("Util", "Data/VendorPrices", "Vendor")
    local store = {}
    T.M.setHandlers({ onItems = function(entries) ns.Vendor.record(store, entries, 100) end })
    T.M.onEvent("MERCHANT_SHOW")
    T.run()
    H.eq(store, { [3372] = { 40, 100 }, [2320] = { 10, 100 } })
end)
