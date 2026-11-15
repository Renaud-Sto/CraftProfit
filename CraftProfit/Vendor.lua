-- Vendor buy prices: what a merchant asks for one unit of a material. Pure Lua, no WoW API.
--
-- Two sources, the first that knows the item wins:
--   "seen"   - recorded from an open merchant window (MerchantAdapter.lua), saved account
--              wide in CraftProfitDB.vendor = { [itemID] = { unit, time } };
--   "listed" - the built-in list of common materials (Data/VendorPrices.lua), not measured.
-- A merchant's price is the same on every realm and faction, hence one account-wide table.
-- What is recorded is the price the character was asked, reputation discount included.
local _, ns = ...
local Util = ns.Util

local Vendor = {}
ns.Vendor = Vendor

-- A merchant sells a few hundred items at most; this bounds a save that keeps growing.
Vendor.MAX_ITEMS = 5000

local function listed()
    return ns.Data and ns.Data.VendorPrices or {}
end

local function validUnit(unit)
    return Util.isCopper(unit) and unit > 0 and unit <= Util.MAX_COPPER
end

-- Repairs the saved table in place: rows are { unit, time }; anything else goes. Returns
-- the table (a new one when `store` is not a table).
function Vendor.sanitize(store)
    if type(store) ~= "table" then return {} end
    for itemID, row in pairs(store) do
        if Util.id(itemID) ~= itemID or type(row) ~= "table" or not validUnit(row[1])
            or not Util.isCopper(row[2]) then
            store[itemID] = nil
        else
            row[1] = Util.round(row[1])
            for k in pairs(row) do
                if k ~= 1 and k ~= 2 then row[k] = nil end
            end
        end
    end
    return store
end

local function size(store)
    local n = 0
    for _ in pairs(store) do n = n + 1 end
    return n
end

-- Whether a merchant entry gives a usable unit price: bought with money only (no token,
-- item or honour cost), in unlimited supply (a limited stock cannot feed many crafts and
-- is often a special offer), purchasable by this character, with a positive price.
-- entry = { itemID, price, stack, numAvailable, extendedCost, purchasable }.
-- Returns the unit price (price / stack, rounded) or nil.
function Vendor.unitOf(entry)
    if type(entry) ~= "table" or not Util.id(entry.itemID) then return nil end
    if entry.extendedCost == true or entry.purchasable == false then return nil end
    if entry.numAvailable ~= -1 then return nil end
    local stack = Util.count(entry.stack) or 1
    if not validUnit(entry.price) then return nil end
    local unit = Util.round(entry.price / stack)
    if unit < 1 then unit = 1 end
    return unit
end

-- Records a merchant's entries. Returns how many prices changed (new item or new price).
-- A changed price replaces the old one; an unchanged one only has its time refreshed.
function Vendor.record(store, entries, now)
    if type(store) ~= "table" or type(entries) ~= "table" or not Util.isCopper(now) then return 0 end
    local changed, count = 0, nil
    for _, entry in ipairs(entries) do
        local unit = Vendor.unitOf(entry)
        if unit then
            local row = store[entry.itemID]
            if row then
                if row[1] ~= unit then changed = changed + 1 end
                row[1], row[2] = unit, now
            else
                count = count or size(store)
                if count < Vendor.MAX_ITEMS then
                    store[entry.itemID] = { unit, now }
                    count = count + 1
                    changed = changed + 1
                end
            end
        end
    end
    return changed
end

-- unit, kind ("seen" or "listed"), age (seconds since seen; nil for a listed price or a
-- time that cannot be trusted). nil when no vendor is known to sell the item.
function Vendor.get(store, itemID, now)
    local row = type(store) == "table" and store[itemID] or nil
    if type(row) == "table" and validUnit(row[1]) then
        local age
        if Util.isFinite(now) and Util.isCopper(row[2]) and now >= row[2] then age = now - row[2] end
        return row[1], "seen", age
    end
    local unit = listed()[itemID]
    if validUnit(unit) then return unit, "listed", nil end
    return nil
end

function Vendor.priceOf(store, now)
    return function(itemID)
        return Vendor.get(store, itemID, now)
    end
end

-- The price a material is counted at: the cheaper of the auction house and a vendor.
-- A tie goes to the vendor (always in stock, no deposit). Returns unit, source ("ah" or
-- "vendor"), or nil when neither is known.
function Vendor.cheapest(ahUnit, vendorUnit)
    local ah = Util.isCopper(ahUnit) and ahUnit or nil
    local vendor = validUnit(vendorUnit) and vendorUnit or nil
    if vendor and (not ah or vendor <= ah) then return vendor, "vendor" end
    if ah then return ah, "ah" end
    return nil
end
