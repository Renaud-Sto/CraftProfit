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
    theme = "gold",
    -- The look chosen in the options window: header strip and tile card (UI/Native.lua).
    appearance = { header = "b", tile = "b" },
    -- The minimap button: hidden or not, and its place around the minimap in degrees.
    minimap = { hide = false, angle = 225 },
}

-- The appearance keys a save may hold; the same as Native.HEADER_VARIANTS and
-- Native.TILE_VARIANTS (this file is pure Lua and loads before the UI; a test checks both
-- agree).
DB.HEADER_KEYS = { a = true, b = true, c = true }
DB.TILE_KEYS = { a = true, b = true }

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

-- `key` when it is one of `keys`, else `default`. Only strings are looked up: a table or NaN
-- key would be a valid index but never a variant.
local function oneOf(key, keys, default)
    if type(key) == "string" and keys[key] then return key end
    return default
end

-- An angle in degrees brought into [0, 360); nil when it is not a finite number, or when
-- it is too large for the modulo to stay exact.
function DB.angle(v)
    if not Util.isFinite(v) then return nil end
    v = v % 360
    if not (v >= 0 and v < 360) then return nil end
    return v
end

-- Rebuilt as fresh tables: unknown fields go, and a save never shares a table with the
-- defaults.
local function sanitizeAppearance(s)
    local a = type(s.appearance) == "table" and s.appearance or {}
    local defaults = DB.DEFAULTS.appearance
    s.appearance = {
        header = oneOf(a.header, DB.HEADER_KEYS, defaults.header),
        tile = oneOf(a.tile, DB.TILE_KEYS, defaults.tile),
    }
    local m = type(s.minimap) == "table" and s.minimap or {}
    local mapDefaults = DB.DEFAULTS.minimap
    local hide = m.hide
    if type(hide) ~= "boolean" then hide = mapDefaults.hide end
    s.minimap = { hide = hide, angle = DB.angle(m.angle) or mapDefaults.angle }
end

local function sanitizeSettings(s)
    number(s, "cut", 0, 0.5, DB.DEFAULTS.cut)
    number(s, "medianN", 1, 20, DB.DEFAULTS.medianN, true)
    number(s, "staleAfter", 60, 30 * 86400, DB.DEFAULTS.staleAfter)
    if type(s.showPerPoint) ~= "boolean" then s.showPerPoint = DB.DEFAULTS.showPerPoint end
    if type(s.costExpanded) ~= "boolean" then s.costExpanded = DB.DEFAULTS.costExpanded end
    if type(s.levelShowGrey) ~= "boolean" then s.levelShowGrey = false end
    if s.levelSort ~= "speed" then s.levelSort = "cost" end
    if type(s.theme) ~= "string" or not (ns.Theme and ns.Theme.exists(s.theme)) then
        s.theme = DB.DEFAULTS.theme
    end
    sanitizeAppearance(s)
    -- Saved positions of the leveling and options windows: { x, y } or nothing.
    for _, key in ipairs({ "levelWindow", "optionsWindow" }) do
        local pos = s[key]
        if type(pos) == "table" and Util.isFinite(pos.x) and Util.isFinite(pos.y) then
            s[key] = { x = pos.x, y = pos.y }
        else
            s[key] = nil
        end
    end
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
    -- One price table per market (realm and auction house faction); see DB.market.
    if type(db.markets) ~= "table" then db.markets = {} end
    for key, market in pairs(db.markets) do
        if type(key) ~= "string" or type(market) ~= "table" then
            db.markets[key] = nil
        else
            if type(market.prices) ~= "table" then market.prices = {} end
            sanitizePrices(market.prices)
            if not Util.isCopper(market.snapshotTime) then market.snapshotTime = nil end
            if type(market.series) ~= "table" then market.series = {} end
        end
    end
    return db
end

-- The price table of one market, created on first use: { prices, snapshotTime, series }.
-- Prices from before markets existed (db.prices) belong to the first market used.
function DB.market(db, key)
    if type(key) ~= "string" then key = "unknown" end
    local market = db.markets[key]
    if not market then
        market = { prices = {}, series = {} }
        if next(db.markets) == nil and next(db.prices) ~= nil then
            market.prices, market.snapshotTime = db.prices, db.snapshotTime
            db.prices, db.snapshotTime = {}, nil
        end
        db.markets[key] = market
    end
    return market
end

-- Removes prices older than PRICE_MAX_AGE. A price dated in the future (clock
-- moved back) is kept: its age is simply unknown. Returns how many were removed.
function DB.prune(db, now)
    if not Util.isFinite(now) then return 0 end
    local removed = 0
    local function prune(prices)
        for itemID, row in pairs(prices) do
            if now - row[3] > DB.PRICE_MAX_AGE then
                prices[itemID] = nil
                removed = removed + 1
            end
        end
    end
    prune(db.prices)
    for _, market in pairs(db.markets) do prune(market.prices) end
    return removed
end

DB.SORT_NET, DB.SORT_POINT = "net", "point"

function DB.setSortMode(db, mode)
    db.sortMode = mode == DB.SORT_POINT and DB.SORT_POINT or DB.SORT_NET
    return db.sortMode
end

DB.MAX_PROFESSIONS = 8
DB.MAX_KNOWN = 400

-- Known recipes of each profession, kept per character so the leveling list works
-- at the auction house with the profession window closed:
-- db.known = { { key, name, updated, recipes = { normalised recipes } } }.
local function sanitizeKnown(db)
    local keep, seen = {}, {}
    if type(db.known) == "table" then
        for _, prof in ipairs(db.known) do
            if type(prof) == "table" and type(prof.key) == "string" and prof.key ~= "" and not seen[prof.key]
                and #keep < DB.MAX_PROFESSIONS then
                seen[prof.key] = true
                local recipes, ids = {}, {}
                for _, raw in ipairs(type(prof.recipes) == "table" and prof.recipes or {}) do
                    local recipe = Recipes.normalize(raw)
                    if recipe and not ids[recipe.recipeID] and #recipes < DB.MAX_KNOWN then
                        ids[recipe.recipeID] = true
                        recipes[#recipes + 1] = recipe
                    end
                end
                keep[#keep + 1] = {
                    key = prof.key,
                    name = type(prof.name) == "string" and #prof.name <= 64 and prof.name or prof.key,
                    updated = Util.isCopper(prof.updated) and prof.updated or 0,
                    recipes = recipes,
                }
            end
        end
    end
    db.known = keep
    if type(db.knownCurrent) ~= "string" then db.knownCurrent = nil end
end

-- Stores the recipes read from a profession window (replacing the previous list of
-- that profession). The profession becomes the current one. Returns true or false.
function DB.setKnown(db, key, name, recipes, now)
    if type(key) ~= "string" or key == "" or type(recipes) ~= "table" then return false end
    local clean, ids = {}, {}
    for _, raw in ipairs(recipes) do
        local recipe = Recipes.normalize(raw)
        if recipe and not ids[recipe.recipeID] and #clean < DB.MAX_KNOWN then
            ids[recipe.recipeID] = true
            clean[#clean + 1] = recipe
        end
    end
    local entry
    for _, prof in ipairs(db.known) do
        if prof.key == key then entry = prof end
    end
    if not entry then
        if #db.known >= DB.MAX_PROFESSIONS then table.remove(db.known, 1) end
        entry = { key = key }
        db.known[#db.known + 1] = entry
    end
    entry.name = type(name) == "string" and #name <= 64 and name or key
    entry.updated = Util.isCopper(now) and now or 0
    entry.recipes = clean
    db.knownCurrent = key
    return true
end

-- The profession shown by the leveling list: the current one, else the first.
function DB.currentKnown(db)
    for _, prof in ipairs(db.known) do
        if prof.key == db.knownCurrent then return prof end
    end
    return db.known[1]
end

-- Switches to the next stored profession. Returns it, or nil when there is none.
function DB.nextKnown(db)
    if #db.known == 0 then return nil end
    local current = DB.currentKnown(db)
    local index = 1
    for i, prof in ipairs(db.known) do
        if prof == current then index = i end
    end
    local nextProf = db.known[index % #db.known + 1]
    db.knownCurrent = nextProf.key
    return nextProf
end

function DB.initChar(db)
    DB.setSortMode(db, db.sortMode)
    sanitizeKnown(db)
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
