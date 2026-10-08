-- Saved variable defaults, repair and migration. Pure Lua, no WoW API.
-- Both saved tables are repaired IN PLACE: WoW keeps a reference to the table
-- it loaded, so replacing it would silently lose the data on logout.
local _, ns = ...
local Util, Recipes = ns.Util, ns.Recipes

local DB = {}
ns.DB = DB

DB.VERSION = 1
DB.MAX_PINS = 12
DB.PRICE_MAX_AGE = 14 * 86400

DB.DEFAULTS = {
    cut = 0.05,         -- AH commission: 5% measured in the beta (docs/probe-findings.md F5)
    medianN = 5,        -- cheapest units used for the median price
    showPerPoint = false,
    costExpanded = true, -- material detail shown under the Materials line
    staleAfter = 3600,  -- seconds before prices are shown as old
}

local ANCHORS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
    RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

-- Steps that bring older saved data up to date; index = target version.
DB.migrations = {
    [1] = function(db)
        if type(db.settings) ~= "table" then db.settings = {} end
    end,
}

local function number(t, key, lo, hi, default, integer)
    local v = t[key]
    if not Util.isFinite(v) or v < lo or v > hi then v = default end
    if integer then v = math.floor(v) end
    t[key] = v
end

local function sanitizeSettings(s)
    number(s, "cut", 0, 0.5, DB.DEFAULTS.cut)
    number(s, "medianN", 1, 20, DB.DEFAULTS.medianN, true)
    number(s, "staleAfter", 60, 30 * 86400, DB.DEFAULTS.staleAfter)
    if type(s.showPerPoint) ~= "boolean" then s.showPerPoint = DB.DEFAULTS.showPerPoint end
    if type(s.costExpanded) ~= "boolean" then s.costExpanded = DB.DEFAULTS.costExpanded end
    local w = s.window
    if type(w) == "table" and ANCHORS[w.point] and Util.isFinite(w.x) and Util.isFinite(w.y) then
        s.window = { point = w.point, x = w.x, y = w.y }
    else
        s.window = nil
    end
end

-- Rows are compact arrays { unit, volume, time } to keep the file small.
local function sanitizePrices(prices)
    for itemID, row in pairs(prices) do
        local valid = Util.id(itemID) == itemID and type(row) == "table"
            and Util.isCopper(row[1]) and row[1] > 0
            and Util.count(row[2]) ~= nil and Util.isCopper(row[3])
        -- Clearing a field while iterating with pairs is allowed in Lua.
        if not valid then prices[itemID] = nil end
    end
end

function DB.initAccount(db)
    local version = db.dbVersion
    if not Util.isFinite(version) or version < 0 then version = 0 end
    db.dbVersion = math.floor(version)
    -- Bounded by DB.VERSION: a hostile dbVersion cannot make this loop forever.
    for v = db.dbVersion + 1, DB.VERSION do
        local migrate = DB.migrations[v]
        if migrate and not pcall(migrate, db) then break end
        db.dbVersion = v
    end
    if type(db.settings) ~= "table" then db.settings = {} end
    sanitizeSettings(db.settings)
    if type(db.prices) ~= "table" then db.prices = {} end
    sanitizePrices(db.prices)
    if not Util.isCopper(db.snapshotTime) then db.snapshotTime = nil end
    return db
end

-- Removes prices older than PRICE_MAX_AGE. A price dated in the future (clock
-- moved back) is kept: its age is simply unknown. Returns how many were removed.
function DB.prune(db, now)
    if not Util.isFinite(now) then return 0 end
    local removed = 0
    for itemID, row in pairs(db.prices) do
        if now - row[3] > DB.PRICE_MAX_AGE then
            db.prices[itemID] = nil
            removed = removed + 1
        end
    end
    return removed
end

DB.SORT_NET, DB.SORT_POINT = "net", "point"

function DB.setSortMode(db, mode)
    db.sortMode = mode == DB.SORT_POINT and DB.SORT_POINT or DB.SORT_NET
    return db.sortMode
end

function DB.initChar(db)
    DB.setSortMode(db, db.sortMode)
    if type(db.pins) ~= "table" then db.pins = {} end
    local pins = db.pins
    -- Collect numeric keys in order so holes in the array do not hide entries.
    local keys = {}
    for k in pairs(pins) do
        if Util.isFinite(k) and k >= 1 then keys[#keys + 1] = k end
    end
    table.sort(keys)
    local keep, seen = {}, {}
    for _, k in ipairs(keys) do
        local recipe = Recipes.normalize(pins[k])
        if recipe and not seen[recipe.recipeID] and #keep < DB.MAX_PINS then
            seen[recipe.recipeID] = true
            keep[#keep + 1] = recipe
        end
    end
    for k in pairs(pins) do pins[k] = nil end
    for i, recipe in ipairs(keep) do pins[i] = recipe end
    return db
end

function DB.pinIndex(db, recipeID)
    for i, recipe in ipairs(db.pins) do
        if recipe.recipeID == recipeID then return i end
    end
    return nil
end

function DB.pinAdd(db, recipe)
    local clean = Recipes.normalize(recipe)
    if not clean then return false, "invalid" end
    if DB.pinIndex(db, clean.recipeID) then return false, "exists" end
    if #db.pins >= DB.MAX_PINS then return false, "full" end
    db.pins[#db.pins + 1] = clean
    return true
end

function DB.pinRemove(db, recipeID)
    local index = DB.pinIndex(db, recipeID)
    if not index then return false end
    table.remove(db.pins, index)
    return true
end
