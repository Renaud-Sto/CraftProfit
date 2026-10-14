-- Turns an Evaluate result into text for the window. Pure Lua, no WoW API:
-- L is the locale table and fmt formats copper (both injected); colours come from ns.Colors.
local _, ns = ...
local Util, Core, Format, Colors = ns.Util, ns.Core, ns.Format, ns.Colors

local Present = {}
ns.Present = Present

-- A certain outcome (100%) would only repeat the average above it.
local LIKELY_MIN = 0.999
local LINE_KEYS = { ah = "LINE_AH", vendor = "LINE_VENDOR", disenchant = "LINE_DISENCHANT" }
local NAME_KEYS = { ah = "NAME_AH", vendor = "NAME_VENDOR", disenchant = "NAME_DISENCHANT" }
local TILE_KEYS = { ah = "TILE_AH", vendor = "TILE_VENDOR", disenchant = "TILE_DISENCHANT" }
local UNIT_KEYS = { sec = "AGE_SEC", min = "AGE_MIN", hour = "AGE_HOUR", day = "AGE_DAY" }

-- The saved default (DB loads first), for a caller that passes no staleAfter.
local DEFAULT_STALE = ns.DB.DEFAULTS.staleAfter

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

-- The text of an unknown value in a list row: "no data" when nothing is missing but the
-- only way left to sell the item is a disenchant the data does not cover (a search would
-- not change it), else "?". `result` is the Evaluate result, optional.
function Present.unknownText(L, result)
    if type(result) == "table" and result.net == nil and not result.incomplete then
        local de = result.options and result.options.disenchant
        if de and de.status == "nodata" then return L.NO_DATA end
    end
    return L.UNKNOWN
end

-- Short text and tone for a list row: "21g 29s/pt" (loss), "+9s 33c/pt" (profit),
-- n/a for a recipe that cannot give a point, ? (or "no data", see unknownText) when the
-- cost is unknown. A cost counted without a missing resale price (perPoint.incomplete) keeps
-- its text in the "incomplete" tone, as the main window's missing prices warning.
-- `result` (optional) is the evaluation the per-point figures come from.
function Present.pointRow(L, fmt, perPoint, result)
    if not perPoint or perPoint.chance == nil then return Present.unknownText(L, result), "muted" end
    if perPoint.chance == 0 then return L.NA, "muted" end
    local cost = perPoint.cost
    if cost == nil then return Present.unknownText(L, result), "muted" end
    local text, tone
    if cost > 0 then
        text, tone = fmt(cost) .. L.PER_POINT_SHORT, "loss"
    else
        text, tone = "+" .. fmt(-cost) .. L.PER_POINT_SHORT, "profit"
    end
    if perPoint.incomplete then tone = "incomplete" end
    return text, tone
end

-- Text and tone of the tag on a recipe row of the profession window: the net of one craft,
-- the figure of the main window's banner and the pinned list ("+12s 23c" profit, "-2s" loss,
-- grey at break even), in the "incomplete" tone when a missing price leaves it partial.
-- Nothing (no tag) without a figure. `fmt` formats copper (Format.short).
function Present.rowTag(result, fmt)
    if type(result) ~= "table" or not Util.isFinite(result.net) then return nil end
    local net = Util.round(result.net)
    local text, tone = fmt(net), "muted"
    if net > 0 then
        text, tone = "+" .. text, "profit"
    elseif net < 0 then
        tone = "loss"
    end
    if result.incomplete then tone = "incomplete" end
    return text, tone
end

-- How many crafts a skill point takes on average ("x4", "x1.3"), nil when no point is
-- possible or the chance is unknown.
function Present.craftsPerPoint(chance)
    if not Util.isFinite(chance) or chance <= 0 or chance > 1 then return nil end
    local n = 1 / chance
    if math.abs(n - math.floor(n + 0.5)) < 0.05 then return string.format("x%d", math.floor(n + 0.5)) end
    return string.format("x%.1f", n)
end

-- Label, value and tone of the cost per point line. A negative cost means each
-- point pays for itself, which reads better as a gain than as a negative cost.
local function perPointLine(L, fmt, perPoint)
    local line = { label = L.PER_POINT, key = "perpoint", best = false }
    if perPoint.chance == nil then line.value = L.UNKNOWN; return line end
    if perPoint.chance == 0 then line.value = L.NA; return line end
    if perPoint.cost == nil then line.value = L.UNKNOWN; return line end
    -- Present.percent: a chance that is not whole keeps a decimal (99.5%, never 100%).
    local suffix = " (" .. Present.percent(perPoint.chance) .. "%, " .. L.ESTIMATE .. ")"
    if perPoint.cost < 0 then
        line.label, line.value, line.tone = L.PER_POINT_GAIN, fmt(-perPoint.cost) .. suffix, "profit"
    else
        line.value = fmt(perPoint.cost) .. suffix
        if perPoint.cost > 0 then line.tone = "loss" end
    end
    return line
end

-- The partial case: a best way to sell is known but some price is missing.
local function isPartial(result)
    return result.net ~= nil and result.incomplete and true or false
end

local function verdictFor(result, L, fmt)
    if result.net == nil and result.best == nil and not result.incomplete then
        -- Nothing known, nothing missing: either no way to sell at all, or the only way left
        -- is a disenchant the data does not cover.
        local de = result.options and result.options.disenchant
        local text = de and de.status == "nodata" and L.VERDICT_NO_DATA or L.VERDICT_NONE
        return { kind = "none", text = text, value = "" }
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

-- A chance as a percentage: whole when it is ("75"), else one decimal ("99.5"), so an
-- outcome that is not certain never reads as 100.
function Present.percent(chance)
    local p = chance * 100
    local whole = math.floor(p + 0.5)
    if math.abs(p - whole) < 0.05 then return tostring(whole) end
    return string.format("%.1f", p)
end

-- The colour of a move against the usual price: green when it is good news (`good` true),
-- red when bad (false), the game's grey when flat or unknown (nil).
function Present.goodColor(good)
    if good == true then return Colors.FIXED.profit end
    if good == false then return Colors.FIXED.loss end
    return Colors.text("muted")
end

-- A HistoryView comparison ({ pct, good }) as "-18%", "+12%" or "0%" in its goodColor; all
-- grey when `muted` (the recipe is crafted at a loss: no move is good news yet). "" without
-- a comparison or with a pct that is not a finite number. Shared by the History window's
-- list and the main window's indicators.
function Present.changeText(c, muted)
    if type(c) ~= "table" or not Util.isFinite(c.pct) then return "" end
    local pct = Util.round(c.pct)
    local text = pct == 0 and "0%" or string.format("%+d%%", pct)
    return Colors.escape(muted and Colors.text("muted") or Present.goodColor(c.good)) .. text .. "|r"
end

-- "1 measurement over 1 day", "12 measurements over 5 days": each count agrees in number
-- (ns.Locale.plural: French counts 0 as singular). Shared by the History window and the
-- main window's indicator tooltips.
local function counted(L, n, key)
    n = type(n) == "number" and n or 0
    return string.format(L[key .. (ns.Locale.plural(n) == "one" and "_ONE" or "_OTHER")], n)
end

function Present.coverageText(L, measures, days)
    return string.format(L.HISTORY_COVERAGE, counted(L, measures, "HISTORY_MEASURES"), counted(L, days, "HISTORY_DAYS"))
end

function Present.daysText(L, days)
    return counted(L, days, "HISTORY_DAYS")
end

-- Grey sub-line under the disenchant value: the most probable outcome, so the
-- player sees the gamble behind the average ("75%: 1-2x Soul Dust = 7s 30c").
local function likelyLine(likely, fmt, itemName)
    local name = itemName and itemName(likely.itemID) or ("#" .. likely.itemID)
    local qty = likely.min == likely.max and tostring(likely.min) or (likely.min .. "-" .. likely.max)
    return {
        label = string.format("%s%%: %sx %s = %s", Present.percent(likely.chance), qty, name, fmt(likely.value)),
        value = "", key = "likely", best = false, muted = true,
    }
end

-- Text shown for an option amount: the price, "n/a", "no data" or "?".
local function optionText(option, L, fmt)
    if option.status == "ok" then
        return fmt(option.value)
    elseif option.status == "na" then
        return L.NA
    elseif option.status == "nodata" then
        return L.NO_DATA
    end
    return L.UNKNOWN
end

function Present.build(result, L, fmt, opts)
    local staleAfter = opts and opts.staleAfter or DEFAULT_STALE
    local lines = {}
    local crafts = result.crafts or 1
    local materials = crafts > 1 and string.format(L.MATERIALS_MULTI, crafts) or L.MATERIALS
    lines[1] = { label = materials, value = fmt(result.cost.total), key = "cost", best = false }
    for _, key in ipairs(Core.OPTION_ORDER) do
        local option = result.options[key]
        local text = optionText(option, L, fmt)
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
    local verdict = verdictFor(result, L, fmt)
    local tiles = {}
    for _, key in ipairs(Core.OPTION_ORDER) do
        local option = result.options[key]
        local text = optionText(option, L, fmt)
        tiles[#tiles + 1] = {
            key = key, label = L[TILE_KEYS[key]], value = text,
            best = result.best == key, muted = option.status ~= "ok",
            tag = key == "disenchant" and L.BETA_TAG or nil,
        }
    end
    -- The partial verdict is too long beside the large value, so its warning moves to
    -- the label line and the main line keeps only the best way to sell.
    local banner = { label = L.RESULT, text = verdict.text, value = verdict.value, kind = verdict.kind }
    if isPartial(result) then
        banner.text = string.format(L.VERDICT_KNOWN, L[NAME_KEYS[result.best]])
        banner.warning = L.WARN_PRICES
    end
    return {
        lines = lines,
        crafts = crafts,
        costLines = costLines,
        verdict = verdict,
        banner = banner,
        tiles = tiles,
        materials = {
            title = crafts > 1 and string.format(L.PANEL_MATERIALS_MULTI, crafts) or L.PANEL_MATERIALS,
            total = fmt(result.cost.total),
        },
        ageText = Present.ageText(L, result.oldestAge),
        stale = not Util.isFinite(result.oldestAge) or result.oldestAge > staleAfter,
    }
end
