local H = ...

local function load() return H.newNS("Util", "Data/Skillup", "Recipes", "DB").DB end

local function raw(id)
    return {
        recipeID = id, name = "R" .. id, difficulty = "easy", outputItemID = 1000 + id,
        qtyMin = 1, qtyMax = 1, reagents = { { itemID = 1, qty = 2 } },
    }
end

H.test("initAccount fills defaults and returns the same table", function()
    local DB = load()
    local db = {}
    H.truthy(DB.initAccount(db) == db)
    H.eq(db.dbVersion, 1)
    H.eq(db.settings, { cut = 0.05, medianN = 5, showPerPoint = false, costExpanded = true, staleAfter = 3600, levelShowGrey = false, levelSort = "cost", theme = "gold",
        appearance = { header = "b", tile = "b" }, minimap = { hide = false, angle = 225 } })
    H.eq(db.prices, {})
end)

H.test("initAccount repairs the tables in place", function()
    local DB = load()
    local settings, prices = {}, {}
    local db = { settings = settings, prices = prices }
    DB.initAccount(db)
    H.truthy(db.settings == settings)
    H.truthy(db.prices == prices)
end)

H.test("initAccount replaces invalid settings with defaults", function()
    local DB = load()
    local db = DB.initAccount({ settings = {
        cut = 0 / 0, medianN = 99, staleAfter = -5, showPerPoint = "yes", costExpanded = "no",
        window = { point = "NOPE", x = 1, y = 2 },
    } })
    H.eq(db.settings, { cut = 0.05, medianN = 5, showPerPoint = false, costExpanded = true, staleAfter = 3600, levelShowGrey = false, levelSort = "cost", theme = "gold",
        appearance = { header = "b", tile = "b" }, minimap = { hide = false, angle = 225 } })
end)

H.test("initAccount keeps valid settings and floors medianN", function()
    local DB = load()
    local db = DB.initAccount({ settings = {
        cut = 0.5, medianN = 7.9, staleAfter = 120, showPerPoint = true, costExpanded = false,
        window = { point = "TOPLEFT", x = 100, y = -50, junk = 1 },
    } })
    H.eq(db.settings, {
        cut = 0.5, medianN = 7, staleAfter = 120, showPerPoint = true, costExpanded = false, levelShowGrey = false, levelSort = "cost", theme = "gold",
        window = { point = "TOPLEFT", x = 100, y = -50 },
        appearance = { header = "b", tile = "b" }, minimap = { hide = false, angle = 225 },
    })
    H.eq(DB.initAccount({ settings = { cut = 0.51 } }).settings.cut, 0.05)
    H.eq(DB.initAccount({ settings = { cut = -0.01 } }).settings.cut, 0.05)
end)

H.test("initAccount survives hostile dbVersion values without looping", function()
    local DB = load()
    for _, bad in ipairs({ -1 / 0, 0 / 0, "x", -5, {} }) do
        H.eq(DB.initAccount({ dbVersion = bad }).dbVersion, 1)
    end
end)

H.test("initAccount never downgrades data written by a newer version", function()
    local DB = load()
    H.eq(DB.initAccount({ dbVersion = 99 }).dbVersion, 99)
end)

H.test("a failing migration stops at the last good version", function()
    local DB = load()
    local oldVersion = DB.VERSION
    DB.VERSION = 2
    DB.migrations[2] = function() error("boom") end
    local db = DB.initAccount({})
    DB.VERSION = oldVersion
    DB.migrations[2] = nil
    H.eq(db.dbVersion, 1)
    H.truthy(type(db.settings) == "table")
end)

H.test("initAccount removes invalid price rows", function()
    local DB = load()
    local db = DB.initAccount({ prices = {
        [100] = { 5, 2, 1000 },
        [101] = { 0 / 0, 1, 0 },
        x = { 1, 1, 1 },
        [102] = "bad",
        [103] = { 5, 0, 10 },
        [104] = { -1, 1, 0 },
        [105] = { 5, 1, 0 / 0 },
        [106.5] = { 5, 1, 0 },
    } })
    H.eq(db.prices, { [100] = { 5, 2, 1000 } })
end)

H.test("initAccount drops an invalid snapshot time", function()
    local DB = load()
    H.eq(DB.initAccount({ snapshotTime = 0 / 0 }).snapshotTime, nil)
    H.eq(DB.initAccount({ snapshotTime = -3 }).snapshotTime, nil)
    H.eq(DB.initAccount({ snapshotTime = 500 }).snapshotTime, 500)
end)

H.test("prune drops old prices but keeps future-dated ones", function()
    local DB = load()
    local now = 10 * DB.PRICE_MAX_AGE
    local db = DB.initAccount({ prices = {
        [1] = { 5, 1, now - DB.PRICE_MAX_AGE - 1 },
        [2] = { 5, 1, now - 10 },
        [3] = { 5, 1, now + 1000 },
    } })
    H.eq(DB.prune(db, now), 1)
    H.eq(db.prices[1], nil)
    H.truthy(db.prices[2])
    H.truthy(db.prices[3])
    H.eq(DB.prune(db, 0 / 0), 0)
end)

H.test("initChar keeps valid pins, drops junk and duplicates, repairs holes", function()
    local DB = load()
    local pins = { raw(1), "junk", { recipeID = 2 }, raw(1), [5] = raw(3) }
    local db = { pins = pins }
    DB.initChar(db)
    H.truthy(db.pins == pins)
    H.eq(#db.pins, 2)
    H.eq(db.pins[1].recipeID, 1)
    H.eq(db.pins[2].recipeID, 3)
    H.eq(db.pins[1].difficulty, "easy")
end)

H.test("initChar caps the number of pins", function()
    local DB = load()
    local pins = {}
    for i = 1, 20 do pins[i] = raw(i) end
    local db = DB.initChar({ pins = pins })
    H.eq(#db.pins, DB.MAX_PINS)
    H.eq(db.pins[DB.MAX_PINS].recipeID, DB.MAX_PINS)
end)

H.test("initChar creates the pins table when missing or invalid", function()
    local DB = load()
    H.eq(DB.initChar({}).pins, {})
    H.eq(DB.initChar({ pins = "x" }).pins, {})
end)

H.test("pinAdd stores a normalized copy and pinRemove deletes it", function()
    local DB = load()
    local db = DB.initChar({})
    local recipe = raw(7)
    H.eq({ DB.pinAdd(db, recipe) }, { true })
    H.truthy(db.pins[1] ~= recipe)
    H.eq(db.pins[1].outputQty, 1)
    H.eq(DB.pinIndex(db, 7), 1)
    H.eq(DB.pinRemove(db, 7), true)
    H.eq(DB.pinRemove(db, 7), false)
    H.eq(DB.pinIndex(db, 7), nil)
end)

H.test("pinAdd refuses duplicates, invalid recipes and a full list", function()
    local DB = load()
    local db = DB.initChar({})
    DB.pinAdd(db, raw(1))
    H.eq({ DB.pinAdd(db, raw(1)) }, { false, "exists" })
    H.eq({ DB.pinAdd(db, { recipeID = 2 }) }, { false, "invalid" })
    for i = 2, DB.MAX_PINS do DB.pinAdd(db, raw(i)) end
    H.eq({ DB.pinAdd(db, raw(100)) }, { false, "full" })
end)

H.test("known recipes are stored per profession, repaired, and cycled", function()
    local ns = H.newNS("Util", "Data/Skillup", "Recipes", "DB")
    local DB = ns.DB
    local function rawRecipe(id) return { recipeID = id, name = "R" .. id, difficulty = 1, outputItemID = 100, qtyMin = 1, qtyMax = 1,
        reagents = { { itemID = 1, qty = 2 } } } end
    local db = DB.initChar({})
    H.eq(db.known, {})
    H.eq(DB.currentKnown(db), nil)
    H.eq(DB.nextKnown(db), nil)
    H.truthy(DB.setKnown(db, "164", "Forge", { rawRecipe(1), rawRecipe(2), rawRecipe(1), "junk", { recipeID = 0 } }, 1700000000))
    H.eq(#db.known[1].recipes, 2)
    H.eq(db.known[1].name, "Forge")
    H.eq(db.knownCurrent, "164")
    H.truthy(DB.setKnown(db, "185", "Cuisine", { rawRecipe(7) }, 1700000100))
    H.eq(DB.currentKnown(db).key, "185")
    H.eq(DB.nextKnown(db).key, "164")
    H.eq(DB.nextKnown(db).key, "185")
    -- replaced, not duplicated
    H.truthy(DB.setKnown(db, "164", "Forge", { rawRecipe(3) }, 1700000200))
    H.eq(#db.known, 2)
    H.eq(db.known[1].recipes[1].recipeID, 3)
    H.eq(DB.setKnown(db, "", "x", {}, 1), false)
    H.eq(DB.setKnown(db, "x", "x", "junk", 1), false)
    for i = 1, DB.MAX_PROFESSIONS + 2 do DB.setKnown(db, "k" .. i, "P", { rawRecipe(i) }, 1700000300) end
    H.eq(#db.known, DB.MAX_PROFESSIONS)
    -- saved data is repaired on load
    local bad = { known = { { key = "a", name = 5, updated = -1, recipes = { rawRecipe(1), "junk" } }, "junk",
        { key = "a", recipes = {} }, { key = "", recipes = {} } }, knownCurrent = 7 }
    DB.initChar(bad)
    H.eq(#bad.known, 1)
    H.eq(bad.known[1].name, "a")
    H.eq(bad.known[1].updated, 0)
    H.eq(#bad.known[1].recipes, 1)
    H.eq(bad.knownCurrent, nil)
end)

H.test("the theme setting keeps a known theme and falls back to gold otherwise", function()
    local ns = H.newNS("Util", "Colors", "Theme", "Data/Skillup", "Recipes", "DB")
    local DB = ns.DB
    H.eq(DB.DEFAULTS.theme, "gold")
    local function theme(value)
        local db = DB.initAccount({ settings = { theme = value } })
        return db.settings.theme
    end
    H.eq(theme("copper"), "copper")
    H.eq(theme("steel"), "steel")
    H.eq(theme("nope"), "gold")
    H.eq(theme(5), "gold")
    H.eq(theme(nil), "gold")
    H.eq(theme({}), "gold")
end)

H.test("the theme setting becomes gold when the theme module is not loaded", function()
    local ns = H.newNS("Util", "Data/Skillup", "Recipes", "DB")
    local db = ns.DB.initAccount({ settings = { theme = "copper" } })
    H.eq(db.settings.theme, "gold")
end)

H.test("old saves without appearance or minimap get the defaults", function()
    local DB = load()
    H.eq(DB.DEFAULTS.appearance, { header = "b", tile = "b" })
    H.eq(DB.DEFAULTS.minimap, { hide = false, angle = 225 })
    local db = DB.initAccount({ settings = { cut = 0.1, theme = "gold" } })
    H.eq(db.settings.appearance, { header = "b", tile = "b" })
    H.eq(db.settings.minimap, { hide = false, angle = 225 })
    -- Copies: changing a save never changes the defaults.
    db.settings.appearance.header = "a"
    db.settings.minimap.angle = 10
    H.eq(DB.DEFAULTS.appearance.header, "b")
    H.eq(DB.DEFAULTS.minimap.angle, 225)
end)

H.test("the appearance keeps known keys, each falling back alone, and drops unknown fields", function()
    local DB = load()
    local function appearance(value)
        return DB.initAccount({ settings = { appearance = value } }).settings.appearance
    end
    H.eq(appearance({ header = "a", tile = "a" }), { header = "a", tile = "a" })
    H.eq(appearance({ header = "c", tile = "b", junk = 1 }), { header = "c", tile = "b" })
    H.eq(appearance({ header = "c", tile = "c" }), { header = "c", tile = "b" })
    H.eq(appearance({ header = "z", tile = "a" }), { header = "b", tile = "a" })
    H.eq(appearance({ header = "A", tile = 1 }), { header = "b", tile = "b" })
    H.eq(appearance({ header = {}, tile = 0 / 0 }), { header = "b", tile = "b" })
    for _, bad in ipairs({ "a", 5, true, 0 / 0 }) do
        H.eq(appearance(bad), { header = "b", tile = "b" })
    end
    H.eq(appearance(nil), { header = "b", tile = "b" })
    -- The keys match the variants the native kit can draw.
    H.eq(DB.HEADER_KEYS, { a = true, b = true, c = true })
    H.eq(DB.TILE_KEYS, { a = true, b = true })
end)

H.test("the minimap setting keeps a boolean hide and a finite angle brought into [0, 360)", function()
    local DB = load()
    local function minimap(value)
        return DB.initAccount({ settings = { minimap = value } }).settings.minimap
    end
    H.eq(minimap({ hide = true, angle = 90 }), { hide = true, angle = 90 })
    H.eq(minimap({ hide = false, angle = 0, junk = "x" }), { hide = false, angle = 0 })
    H.eq(minimap({ angle = 360 }), { hide = false, angle = 0 })
    H.eq(minimap({ angle = 450 }), { hide = false, angle = 90 })
    H.eq(minimap({ angle = -90 }), { hide = false, angle = 270 })
    H.eq(minimap({ angle = 359.5 }), { hide = false, angle = 359.5 })
    H.eq(minimap({ hide = "yes", angle = "90" }), { hide = false, angle = 225 })
    H.eq(minimap({ hide = 1, angle = 0 / 0 }), { hide = false, angle = 225 })
    H.eq(minimap({ angle = math.huge }).angle, 225)
    H.eq(minimap({ angle = -math.huge }).angle, 225)
    for _, big in ipairs({ 1e300, -1e300, 2 ^ 60 + 0.5 }) do
        local angle = minimap({ angle = big }).angle
        H.truthy(angle >= 0 and angle < 360)
    end
    for _, bad in ipairs({ "x", 5, false }) do
        H.eq(minimap(bad), { hide = false, angle = 225 })
    end
end)
