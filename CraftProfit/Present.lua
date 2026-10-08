-- Turns an Evaluate result into text for the window. Pure Lua, no WoW API:
-- L is the locale table and fmt formats copper (both injected).
local _, ns = ...
local Util, Core, Format = ns.Util, ns.Core, ns.Format

local Present = {}
ns.Present = Present

-- A certain outcome (100%) would only repeat the average above it.
local LIKELY_MIN = 0.999
local LINE_KEYS = { ah = "LINE_AH", vendor = "LINE_VENDOR", disenchant = "LINE_DISENCHANT" }
local NAME_KEYS = { ah = "NAME_AH", vendor = "NAME_VENDOR", disenchant = "NAME_DISENCHANT" }
local UNIT_KEYS = { sec = "AGE_SEC", min = "AGE_MIN", hour = "AGE_HOUR", day = "AGE_DAY" }

local DEFAULT_STALE = 3600

-- "5m", "3h"... in the client language; nil for an invalid duration.
function Present.durationText(L, seconds)
    local n, unit = Format.age(seconds)
    if not n then return nil end
    return string.format(L[UNIT_KEYS[unit]], n)
end

function Present.ageText(L, age)
    local text = Present.durationText(L, age)
    if not text then return L.AGE_NEVER end
    return string.format(L.AGE, text)
end

local function signed(fmt, n)
    local text = fmt(n)
    if n > 0 then return "+" .. text end
    return text
end

-- Label, value and tone of the cost per point line. A negative cost means each
-- point pays for itself, which reads better as a gain than as a negative cost.
local function perPointLine(L, fmt, perPoint)
    local line = { label = L.PER_POINT, key = "perpoint", best = false }
    if perPoint.chance == nil then line.value = L.UNKNOWN; return line end
    if perPoint.chance == 0 then line.value = L.NA; return line end
    if perPoint.cost == nil then line.value = L.UNKNOWN; return line end
    local percent = math.floor(perPoint.chance * 100 + 0.5)
    local suffix = " (" .. percent .. "%, " .. L.ESTIMATE .. ")"
    if perPoint.cost < 0 then
        line.label, line.value, line.tone = L.PER_POINT_GAIN, fmt(-perPoint.cost) .. suffix, "profit"
    else
        line.value = fmt(perPoint.cost) .. suffix
        if perPoint.cost > 0 then line.tone = "loss" end
    end
    return line
end

local function verdictFor(result, L, fmt)
    if result.net == nil and result.best == nil and not result.incomplete then
        return { kind = "none", text = L.VERDICT_NONE, value = "" }
    end
    if result.net == nil then
        return { kind = "incomplete", text = L.VERDICT_INCOMPLETE, value = "" }
    end
    local name = L[NAME_KEYS[result.best]]
    if result.incomplete then
        return {
            kind = "incomplete",
            text = string.format(L.VERDICT_PARTIAL, name),
            value = signed(fmt, result.net),
        }
    end
    return {
        kind = result.net >= 0 and "profit" or "loss",
        text = string.format(L.VERDICT_BEST, name),
        value = signed(fmt, result.net),
    }
end

-- Grey sub-line under the disenchant value: the most probable outcome, so the
-- player sees the gamble behind the average ("75%: 1-2x Soul Dust = 7s 30c").
local function likelyLine(likely, fmt, itemName)
    local name = itemName and itemName(likely.itemID) or ("#" .. likely.itemID)
    local qty = likely.min == likely.max and tostring(likely.min) or (likely.min .. "-" .. likely.max)
    local percent = math.floor(likely.chance * 100 + 0.5)
    return {
        label = string.format("%d%%: %sx %s = %s", percent, qty, name, fmt(likely.value)),
        value = "", key = "likely", best = false, muted = true,
    }
end

function Present.build(result, L, fmt, opts)
    local staleAfter = opts and opts.staleAfter or DEFAULT_STALE
    local lines = {}
    lines[1] = { label = L.MATERIALS, value = fmt(result.cost.total), key = "cost", best = false }
    for _, key in ipairs(Core.OPTION_ORDER) do
        local option = result.options[key]
        local text
        if option.status == "ok" then
            text = fmt(option.value)
        elseif option.status == "na" then
            text = L.NA
        else
            text = L.UNKNOWN
        end
        lines[#lines + 1] = { label = L[LINE_KEYS[key]], value = text, key = key, best = result.best == key }
        if key == "disenchant" and option.status == "ok" and option.likely and option.likely.chance < LIKELY_MIN then
            lines[#lines + 1] = likelyLine(option.likely, fmt, opts and opts.itemName)
        end
    end
    if result.perPoint then lines[#lines + 1] = perPointLine(L, fmt, result.perPoint) end
    local costLines = {}
    for i, line in ipairs(result.cost.lines) do
        costLines[i] = {
            itemID = line.itemID, qty = line.qty,
            unitText = fmt(line.unit), subtotalText = fmt(line.subtotal),
        }
    end
    return {
        lines = lines,
        costLines = costLines,
        verdict = verdictFor(result, L, fmt),
        ageText = Present.ageText(L, result.oldestAge),
        stale = not Util.isFinite(result.oldestAge) or result.oldestAge > staleAfter,
    }
end
