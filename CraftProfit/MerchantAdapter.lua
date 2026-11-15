-- Merchant adapter: the only file that reads a merchant window. While one is open it turns
-- the merchant's list into plain entries { itemID, price, stack, numAvailable,
-- extendedCost, purchasable } for Vendor.record. The game has no way to ask a vendor's
-- price with its window closed, so this is how vendor prices are learnt.
-- API (C): Blizzard_UIPanels_Game/Mainline/MerchantFrame.lua and
-- MerchantFrameDocumentation.lua of the Forever 1.60.1 source: GetMerchantNumItems,
-- GetMerchantItemID, C_MerchantFrame.GetItemInfo (a MerchantItemInfo table); the older
-- GetMerchantItemInfo is the fallback. price is for `stackCount` units; numAvailable is
-- -1 for an unlimited supply.
local _, ns = ...
local Util = ns.Util

local Merchant = {}
ns.Merchant = Merchant

Merchant.isOpen = false
-- MERCHANT_SHOW and MERCHANT_UPDATE come in bursts (item data loading, purchases): one
-- read DEBOUNCE seconds after the last of them.
Merchant.DEBOUNCE = 0.5
-- A merchant never lists more; bounds a broken answer.
Merchant.MAX_ITEMS = 500

local EVENTS = { "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED" }

local handlers = {}
local token = 0

function Merchant.setHandlers(h)
    handlers = h or {}
end

local isSecret = Util.isSecret

local function plain(v)
    if isSecret(v) then return nil end
    return v
end

local function call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

-- One merchant slot as an entry, or nil when it cannot be read.
local function readSlot(index)
    local okID, itemID = call(GetMerchantItemID, index)
    itemID = okID and Util.id(plain(itemID)) or nil
    if not itemID then return nil end
    local price, stack, available, extended, purchasable
    local api = C_MerchantFrame
    local ok, info = call(type(api) == "table" and api.GetItemInfo or nil, index)
    if ok and type(info) == "table" then
        price, stack, available = info.price, info.stackCount, info.numAvailable
        extended, purchasable = info.hasExtendedCost, info.isPurchasable
    else
        local legacy, _, _, p, s, a, buyable, _, ext = call(GetMerchantItemInfo, index)
        if not legacy then return nil end
        price, stack, available, extended, purchasable = p, s, a, ext, buyable
    end
    return {
        itemID = itemID, price = plain(price), stack = plain(stack), numAvailable = plain(available),
        extendedCost = plain(extended) == true, purchasable = plain(purchasable) ~= false,
    }
end

-- Every readable entry of the open merchant (an empty list when none can be read).
function Merchant.read()
    local ok, n = call(GetMerchantNumItems)
    n = ok and Util.count(plain(n)) or 0
    local entries = {}
    for i = 1, math.min(n, Merchant.MAX_ITEMS) do
        local entry = readSlot(i)
        if entry then entries[#entries + 1] = entry end
    end
    return entries
end

local function schedule()
    token = token + 1
    local mine = token
    C_Timer.After(Merchant.DEBOUNCE, function()
        if mine ~= token or not Merchant.isOpen then return end
        local entries = Merchant.read()
        if #entries > 0 and handlers.onItems then handlers.onItems(entries) end
    end)
end

function Merchant.onEvent(event)
    if event == "MERCHANT_SHOW" then
        Merchant.isOpen = true
        schedule()
    elseif event == "MERCHANT_UPDATE" then
        if Merchant.isOpen then schedule() end
    elseif event == "MERCHANT_CLOSED" then
        Merchant.isOpen = false
        token = token + 1
    end
end

local frame = CreateFrame("Frame")
for _, event in ipairs(EVENTS) do
    pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event) Merchant.onEvent(event) end)
