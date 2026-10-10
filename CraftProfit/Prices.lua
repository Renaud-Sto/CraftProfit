-- Price statistics and storage. Pure Lua, no WoW API.
local _, ns = ...
local Util = ns.Util

local Prices = {}
ns.Prices = Prices

local DEFAULT_N = 5

-- Median unit price of the n cheapest units among the listings, plus the total
-- number of units listed. A single absurdly cheap listing cannot drag the price
-- down the way a plain minimum would. Quantities are handled arithmetically:
-- a listing of 1e9 units costs the same as one of 1.
function Prices.summarize(listings, n)
    n = Util.count(n) or DEFAULT_N
    local rows, volume = {}, 0
    for _, l in ipairs(listings or {}) do
        local qty = Util.count(l.qty)
        if Util.isCopper(l.unit) and l.unit > 0 and qty then
            rows[#rows + 1] = { unit = l.unit, qty = qty }
            volume = volume + qty
        end
    end
    if #rows == 0 then return nil, 0 end
    table.sort(rows, function(a, b) return a.unit < b.unit end)
    local picked, taken = {}, 0
    for _, r in ipairs(rows) do
        if taken >= n then break end
        local take = math.min(r.qty, n - taken)
        picked[#picked + 1] = { unit = r.unit, qty = take }
        taken = taken + take
    end
    -- k-th cheapest unit (1-based) among the picked rows.
    local function kth(k)
        local seen = 0
        for _, p in ipairs(picked) do
            seen = seen + p.qty
            if seen >= k then return p.unit end
        end
    end
    local median
    if taken % 2 == 1 then
        median = kth((taken + 1) / 2)
    else
        median = (kth(taken / 2) + kth(taken / 2 + 1)) / 2
    end
    return Util.round(median), volume
end

-- Collects (itemID, unit, qty) rows one by one, so a full scan never needs a
-- giant intermediate array. result(n) returns { [itemID] = {unit, volume} }.
function Prices.newAggregator()
    local byItem = {}
    local agg = {}
    function agg.add(itemID, unit, qty)
        if not Util.id(itemID) then return end
        local list = byItem[itemID]
        if not list then
            list = {}
            byItem[itemID] = list
        end
        list[#list + 1] = { unit = unit, qty = qty }
    end
    function agg.result(n)
        local out = {}
        for itemID, list in pairs(byItem) do
            local unit, volume = Prices.summarize(list, n)
            if unit then out[itemID] = { unit = unit, volume = volume } end
        end
        return out
    end
    return agg
end

-- db.prices rows are compact arrays { unit, volume, time }.
function Prices.store(db, itemID, unit, volume, now)
    if not Util.id(itemID) or not Util.isCopper(unit) or unit <= 0 or not Util.isCopper(now) then
        return false
    end
    db.prices[itemID] = { Util.round(unit), Util.count(volume) or 1, now }
    return true
end

-- Writes the result of a full scan. Returns how many prices were stored.
function Prices.merge(db, map, now)
    if not Util.isCopper(now) then return 0 end
    local count = 0
    for itemID, row in pairs(map) do
        if Prices.store(db, itemID, row.unit, row.volume, now) then count = count + 1 end
    end
    db.snapshotTime = now
    return count
end

-- Returns unit, age, volume. The age is nil when it cannot be trusted (clock
-- moved back, invalid now): a wrong age is worse than none.
function Prices.get(db, itemID, now)
    local row = db.prices[itemID]
    if type(row) ~= "table" or not Util.isCopper(row[1]) or row[1] <= 0 then return nil end
    local age
    if Util.isFinite(now) and Util.isCopper(row[3]) and now >= row[3] then age = now - row[3] end
    return row[1], age, row[2]
end

function Prices.priceOf(db, now)
    return function(itemID)
        local unit, age = Prices.get(db, itemID, now)
        return unit, age
    end
end

function Prices.snapshotAge(db, now)
    if not Util.isCopper(db.snapshotTime) or not Util.isFinite(now) or now < db.snapshotTime then
        return nil
    end
    return now - db.snapshotTime
end
