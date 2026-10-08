-- Combines a recipe, prices and item facts into one profit result.
-- Pure Lua, no WoW API: the caller passes lookups as functions.
local _, ns = ...
local Util, Core = ns.Util, ns.Core
local Skillup, Disenchant = ns.Data.Skillup, ns.Data.Disenchant

local Evaluate = {}
ns.Evaluate = Evaluate

local BIND_ON_PICKUP = 1

-- Returns "ok", entries | "na" | "unknown" for the disenchant results of an item.
-- A bind-on-pickup item cannot change hands, so only a character who knows
-- Enchanting can disenchant it; a tradable item can be disenchanted by anyone.
local function disenchantEntries(info, lookup, knowsEnchanting)
    if not info then return "unknown" end
    if info.bindType == BIND_ON_PICKUP and not knowsEnchanting then return "na" end
    if not Disenchant.canDisenchant(info.itemID, info.quality, info.classID) then return "na" end
    local entries = lookup(Disenchant.kindOf(info.classID), info.quality, info.ilvl)
    if not entries then return "unknown" end
    return "ok", entries
end

-- Adds the item id to the info table without mutating the caller's table.
local function withID(info, itemID)
    if not info then return nil end
    return {
        itemID = itemID, quality = info.quality, ilvl = info.ilvl,
        sellPrice = info.sellPrice, classID = info.classID, bindType = info.bindType,
    }
end

function Evaluate.run(ctx)
    local recipe, cut = ctx.recipe, ctx.cut
    local oldest

    -- Price lookup that ignores anything that is not a usable copper amount and
    -- remembers the oldest valid age seen.
    local function priceOf(itemID)
        local unit, age = ctx.priceOf(itemID)
        if not Util.isCopper(unit) then return nil end
        if Util.isFinite(age) and (oldest == nil or age > oldest) then oldest = age end
        return unit
    end

    local lines = {}
    for _, r in ipairs(recipe.reagents) do
        local unit = priceOf(r.itemID)
        lines[#lines + 1] = {
            itemID = r.itemID, qty = r.qty, unit = unit, subtotal = unit and unit * r.qty or nil,
        }
    end
    local total, missing = Core.sumCost(recipe.reagents, priceOf)

    local info = withID(ctx.itemInfo(recipe.outputItemID), recipe.outputItemID)
    local qty = recipe.outputQty
    local options = {}

    if info and info.bindType == BIND_ON_PICKUP then
        options.ah = { status = "na" }
    else
        local value = Core.netSale(priceOf(recipe.outputItemID), qty, cut)
        options.ah = value and { status = "ok", value = value } or { status = "unknown" }
    end

    if not info then
        options.vendor = { status = "unknown" }
    elseif not Util.isCopper(info.sellPrice) or info.sellPrice == 0 then
        options.vendor = { status = "na" }
    else
        options.vendor = { status = "ok", value = Core.vendorValue(info.sellPrice, qty) }
    end

    local state, entries = disenchantEntries(info, ctx.lookupDisenchant, ctx.knowsEnchanting)
    if state == "ok" then
        local value = Core.disenchantValue(entries, priceOf, cut)
        if value then
            options.disenchant = { status = "ok", value = Util.round(value * qty) }
        else
            options.disenchant = { status = "unknown" }
        end
    else
        options.disenchant = { status = state }
    end

    local best, bestValue, optionsIncomplete = Core.bestOption(options)
    local net
    if total and bestValue then net = bestValue - total end

    local perPoint
    if ctx.showPerPoint then
        local chance = Skillup.chance(recipe.difficulty)
        perPoint = { chance = chance, estimate = true }
        if total and chance then
            perPoint.cost = Core.costPerPoint(total, bestValue, chance)
        end
    end

    return {
        recipe = recipe,
        cost = { total = total, missing = missing or {}, lines = lines },
        options = options,
        best = best,
        bestValue = bestValue,
        net = net,
        incomplete = optionsIncomplete or total == nil,
        perPoint = perPoint,
        oldestAge = oldest,
    }
end

-- Item ids whose prices are needed to evaluate the recipe, each listed once.
function Evaluate.wantedItems(recipe, itemInfo, lookupDisenchant, knowsEnchanting)
    local ids, seen = {}, {}
    local function add(id)
        if not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    for _, r in ipairs(recipe.reagents) do add(r.itemID) end
    add(recipe.outputItemID)
    local info = withID(itemInfo(recipe.outputItemID), recipe.outputItemID)
    local state, entries = disenchantEntries(info, lookupDisenchant, knowsEnchanting)
    if state == "ok" then
        for _, e in ipairs(entries) do add(e.itemID) end
    end
    return ids
end
