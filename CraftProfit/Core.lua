-- Profit calculations. Pure Lua, no WoW API. Money is copper.
-- Convention: an unknown input gives nil (never 0) so callers can show "?".
local _, ns = ...
local Util = ns.Util

local Core = {}
ns.Core = Core

Core.OPTION_ORDER = { "ah", "vendor", "disenchant" }

local function validCut(cut)
    return Util.isFinite(cut) and cut >= 0 and cut < 1
end

-- A crafted quantity may be fractional (average of a min..max yield).
local function validQty(qty)
    return Util.isFinite(qty) and qty >= 1
end

-- Total cost of reagents { {itemID=, qty=}, ... }. priceOf(itemID) returns a
-- unit price or nil. Returns total when every price is usable, else
-- nil plus the list of unpriced itemIDs: a missing price must never look free.
function Core.sumCost(reagents, priceOf)
    local total, missing = 0, {}
    for _, r in ipairs(reagents) do
        local unit = priceOf(r.itemID)
        local qty = Util.count(r.qty)
        if not Util.isCopper(unit) or not qty then
            missing[#missing + 1] = r.itemID
        else
            total = total + unit * qty
        end
    end
    if #missing > 0 then return nil, missing end
    return total
end

-- What an AH sale of qty items at a unit price really pays out.
function Core.netSale(unit, qty, cut)
    if not Util.isCopper(unit) or not validQty(qty) or not validCut(cut) then return nil end
    return Util.round(unit * qty * (1 - cut))
end

-- What a vendor pays. A sell price of 0 means the item cannot be sold.
function Core.vendorValue(sellPrice, qty)
    if not Util.isCopper(sellPrice) or sellPrice == 0 or not validQty(qty) then return nil end
    return Util.round(sellPrice * qty)
end

local function validEntry(e)
    return type(e) == "table" and Util.id(e.itemID) ~= nil
        and Util.isFinite(e.chance) and e.chance >= 0 and e.chance <= 1
        and Util.isFinite(e.min) and e.min >= 1
        and Util.isFinite(e.max) and e.max >= e.min
end

-- Expected AH value of one disenchant. entries = { {itemID=, chance=, min=, max=} }.
-- The results are sold on the AH, so the commission applies. Returns nil plus
-- the unpriced itemIDs when any result has no price; nil plus {} when the data
-- itself is missing or corrupt.
function Core.disenchantValue(entries, priceOf, cut)
    if type(entries) ~= "table" or #entries == 0 or not validCut(cut) then return nil, {} end
    for _, e in ipairs(entries) do
        if not validEntry(e) then return nil, {} end
    end
    local total, missing = 0, {}
    for _, e in ipairs(entries) do
        local unit = priceOf(e.itemID)
        if not Util.isCopper(unit) then
            missing[#missing + 1] = e.itemID
        else
            total = total + e.chance * (e.min + e.max) / 2 * unit
        end
    end
    if #missing > 0 then return nil, missing end
    return Util.round(total * (1 - cut))
end

-- options[key] = { status = "ok"|"unknown"|"na", value = copper }.
-- Returns the best "ok" key and value, and whether any option was "unknown"
-- (so the best known one may not be the true best).
function Core.bestOption(options)
    local bestKey, bestValue, incomplete = nil, nil, false
    for _, key in ipairs(Core.OPTION_ORDER) do
        local o = options[key]
        if o then
            if o.status == "unknown" then
                incomplete = true
            elseif o.status == "ok" and Util.isFinite(o.value) then
                if bestValue == nil or o.value > bestValue then
                    bestKey, bestValue = key, o.value
                end
            end
        end
    end
    return bestKey, bestValue, incomplete
end

-- Net cost of one skill point: (cost - what the result recovers) / chance.
-- Negative means the crafts pay for themselves. Nil when no point can be earned.
function Core.costPerPoint(cost, recovered, chance)
    if not Util.isFinite(cost) or not Util.isFinite(chance) or chance <= 0 or chance > 1 then
        return nil
    end
    if not Util.isFinite(recovered) then recovered = 0 end
    return Util.round((cost - recovered) / chance)
end
