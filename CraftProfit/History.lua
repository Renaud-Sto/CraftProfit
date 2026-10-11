-- Price history of the tracked recipes. Pure Lua, no WoW API.
--
-- A tracked recipe is a copy of a recipe plus an `active` flag, kept account wide in
-- db.tracked (at most MAX_TRACKED, paused ones included). Each price measurement of
-- an item of an active tracked recipe becomes a point in market.series[itemID]:
-- { t, unit, volume, low, high, n }. A raw point has low = high = unit and n = 1.
-- Older points are merged into one point per day, then one per week. Each of the three
-- tiers has its own cap, so a busy fortnight can only drop raw points, never the daily
-- and weekly history.
local _, ns = ...
local Util, Recipes = ns.Util, ns.Recipes

local History = {}
ns.History = History

History.MAX_TRACKED = 15
local DAY, WEEK = 86400, 7 * 86400
History.RAW_SECONDS = 14 * DAY
History.DAILY_SECONDS = 90 * DAY
History.WEEKLY_SECONDS = 365 * DAY
-- Points kept per item in each tier. Raw points have no natural bound (one per operation
-- that touches the item); 600 is the old cap on the whole series, so no save it kept loses
-- a point. The daily tier spans 76 days (77 buckets at most) and the weekly one 275 days
-- (41 buckets at most): their caps never bind on sane data. At most 725 points an item.
History.MAX_RAW = 600
History.MAX_DAILY = 80
History.MAX_WEEKLY = 45
-- A point dated further ahead than this was written with a wrong clock (or edited by hand):
-- it is dropped, or it would block recording until real time caught up.
History.FUTURE_SLACK = DAY

-- Tracked list ----------------------------------------------------------------

function History.find(db, recipeID)
    for i, entry in ipairs(db.tracked) do
        if entry.recipe.recipeID == recipeID then return i, entry end
    end
    return nil
end

function History.isActive(db, recipeID)
    local _, entry = History.find(db, recipeID)
    return entry ~= nil and entry.active == true
end

-- Starts (or resumes) tracking. Returns true, or false and "invalid" / "full".
function History.track(db, recipe)
    local clean = Recipes.normalize(recipe)
    if not clean then return false, "invalid" end
    local _, entry = History.find(db, clean.recipeID)
    if entry then
        entry.active = true
        entry.recipe = clean
        return true
    end
    if #db.tracked >= History.MAX_TRACKED then return false, "full" end
    db.tracked[#db.tracked + 1] = { recipe = clean, active = true }
    return true
end

-- Stops recording but keeps the entry and its history.
function History.pause(db, recipeID)
    local _, entry = History.find(db, recipeID)
    if not entry then return false end
    entry.active = false
    return true
end

-- Deletes the entry. Series are not touched here (see History.prune).
function History.remove(db, index)
    if type(index) ~= "number" or not db.tracked[index] then return false end
    table.remove(db.tracked, index)
    return true
end

-- Points -----------------------------------------------------------------------

local function validPoint(p)
    return type(p) == "table"
        and Util.isCopper(p[1]) and Util.isCopper(p[2]) and p[2] > 0
        and Util.isCopper(p[3]) and Util.isCopper(p[4]) and Util.isCopper(p[5])
        and Util.count(p[6]) ~= nil
end

local function bucketOf(t, size)
    return math.floor(t / size) * size
end

-- The newest `max` points of a time-ordered array, in order.
local function newest(points, max)
    if #points <= max then return points end
    local out = {}
    for i = #points - max + 1, #points do out[#out + 1] = points[i] end
    return out
end

local function byTime(a, c) return a[1] < c[1] end

-- Merges the points older than RAW_SECONDS into daily, then weekly points, drops what is
-- older than a year or dated more than FUTURE_SLACK ahead, and caps each tier to its newest
-- points. Returns a new, time-ordered array. Safe to run again.
function History.compact(series, now)
    local raw, buckets, order = {}, {}, {}
    for _, p in ipairs(series) do
        if validPoint(p) and p[1] <= now + History.FUTURE_SLACK then
            local age = now - p[1]
            local size
            if age > History.WEEKLY_SECONDS then
                size = false
            elseif age > History.DAILY_SECONDS then
                size = WEEK
            elseif age > History.RAW_SECONDS then
                size = DAY
            end
            if size == nil then
                raw[#raw + 1] = p
            elseif size then
                local t = bucketOf(p[1], size)
                local key = size .. ":" .. t
                local b = buckets[key]
                if not b then
                    b = { t, 0, 0, p[4], p[5], 0, size }
                    buckets[key] = b
                    order[#order + 1] = key
                end
                -- Weighted by the number of measurements merged into each point.
                b[2] = b[2] + p[2] * p[6]
                b[3] = b[3] + p[3] * p[6]
                b[4] = math.min(b[4], p[4])
                b[5] = math.max(b[5], p[5])
                b[6] = b[6] + p[6]
            end
        end
    end
    local daily, weekly = {}, {}
    for _, key in ipairs(order) do
        local b = buckets[key]
        local tier = b[7] == DAY and daily or weekly
        tier[#tier + 1] = { b[1], Util.round(b[2] / b[6]), Util.round(b[3] / b[6]), b[4], b[5], b[6] }
    end
    -- Each tier is sorted on its own so its cap keeps its newest points.
    table.sort(raw, byTime)
    table.sort(daily, byTime)
    table.sort(weekly, byTime)
    local keep = {}
    for _, tier in ipairs({
        newest(weekly, History.MAX_WEEKLY), newest(daily, History.MAX_DAILY), newest(raw, History.MAX_RAW),
    }) do
        for _, p in ipairs(tier) do keep[#keep + 1] = p end
    end
    -- A bucket is dated at the start of its day or week, before its own points, so two
    -- tiers may interleave at their edge: the joined array is sorted once more.
    table.sort(keep, byTime)
    return keep
end

local function addPoint(market, itemID, now, unit, volume)
    local series = market.series[itemID]
    if not series then
        series = {}
        market.series[itemID] = series
    end
    local last = series[#series]
    if last and last[1] >= now then
        -- A point from a clock that ran ahead blocks the series: compacting drops it when it
        -- is more than FUTURE_SLACK ahead. A point of this very second (or within the slack)
        -- still wins, so the same instant is never recorded twice.
        series = History.compact(series, now)
        market.series[itemID] = series
        last = series[#series]
        if last and last[1] >= now then return false end
    end
    series[#series + 1] = { now, unit, volume, unit, unit, 1 }
    market.series[itemID] = History.compact(series, now)
    return true
end

-- Records one point for each item of every active tracked recipe touched by this
-- operation. `updated` is the set of itemIDs whose price was just written;
-- itemsOf(recipe) returns the item ids to record and the ones that must have a
-- price (the output of a bind-on-pickup recipe, for example, is never priced).
-- A recipe is recorded only when every required item has a price. Returns how
-- many recipes got at least one new point.
function History.record(db, market, now, updated, itemsOf)
    if not Util.isCopper(now) or type(updated) ~= "table" then return 0 end
    local recorded = 0
    for _, entry in ipairs(db.tracked) do
        if entry.active then
            local items, required = itemsOf(entry.recipe)
            local touched, complete = false, true
            for _, id in ipairs(items) do
                if updated[id] then touched = true end
            end
            for _, id in ipairs(required) do
                local row = market.prices[id]
                if type(row) ~= "table" or not Util.isCopper(row[1]) or row[1] <= 0 then complete = false end
            end
            if touched and complete then
                local added = false
                for _, id in ipairs(items) do
                    local row = market.prices[id]
                    if type(row) == "table" and Util.isCopper(row[1]) and row[1] > 0
                        and addPoint(market, id, now, row[1], row[2]) then
                        added = true
                    end
                end
                if added then recorded = recorded + 1 end
            end
        end
    end
    return recorded
end

-- Drops the series of items no tracked recipe (active or paused) needs any more.
-- Needs the same itemsOf as record. Returns how many series were removed.
function History.prune(db, market, itemsOf)
    local needed = {}
    for _, entry in ipairs(db.tracked) do
        for _, id in ipairs((itemsOf(entry.recipe))) do needed[id] = true end
    end
    local removed = 0
    for id in pairs(market.series) do
        if not needed[id] then
            market.series[id] = nil
            removed = removed + 1
        end
    end
    return removed
end

-- Repairs db.tracked and every market's series in place. Called after DB.initAccount.
function History.sanitize(db, now)
    if type(db.tracked) ~= "table" then db.tracked = {} end
    local keep, seen = {}, {}
    local keys = {}
    for k in pairs(db.tracked) do
        if Util.isFinite(k) and k >= 1 then keys[#keys + 1] = k end
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local entry = db.tracked[k]
        local recipe = type(entry) == "table" and Recipes.normalize(entry.recipe) or nil
        if recipe and not seen[recipe.recipeID] and #keep < History.MAX_TRACKED then
            seen[recipe.recipeID] = true
            keep[#keep + 1] = { recipe = recipe, active = entry.active == true }
        end
    end
    for k in pairs(db.tracked) do db.tracked[k] = nil end
    for i, entry in ipairs(keep) do db.tracked[i] = entry end
    if type(db.markets) ~= "table" then db.markets = {} end
    for _, market in pairs(db.markets) do
        if type(market.series) ~= "table" then market.series = {} end
        for itemID, series in pairs(market.series) do
            if Util.id(itemID) ~= itemID or type(series) ~= "table" then
                market.series[itemID] = nil
            else
                market.series[itemID] = History.compact(series, now)
            end
        end
    end
end
