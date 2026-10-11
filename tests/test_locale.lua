local H = ...

local function load()
    return H.newNS("Locale", "Locales/enUS", "Locales/frFR", "Locales/esES", "Locales/esMX")
end

-- The format specifiers of a string in order, e.g. "%d/%s" -> "%d,%s". Never sorted: Lua 5.1
-- has no positional arguments, so a translation that swaps "%s" and "%d" raises in
-- string.format.
local function specifiers(s)
    local found = {}
    for spec in s:gmatch("%%[%-%d%.]*[sdfxX%%]") do found[#found + 1] = spec end
    return table.concat(found, ",")
end

local function keys(tbl)
    local list = {}
    for k in pairs(tbl) do list[#list + 1] = k end
    table.sort(list)
    return list
end

H.test("select switches the language ns.L reads", function()
    local ns = load()
    ns.Locale.select("enUS")
    H.eq(ns.L.MATERIALS, "Materials")
    ns.Locale.select("frFR")
    H.eq(ns.L.MATERIALS, "Composants")
    ns.Locale.select("esES")
    H.eq(ns.L.MATERIALS, "Materiales")
end)

H.test("an unsupported client locale falls back to enUS", function()
    local ns = load()
    ns.Locale.select("deDE")
    H.eq(ns.Locale.current, "enUS")
    H.eq(ns.L.MATERIALS, "Materials")
    ns.Locale.select(nil)
    H.eq(ns.Locale.current, "enUS")
end)

H.test("esMX reuses the esES strings", function()
    local ns = load()
    ns.Locale.select("esMX")
    H.eq(ns.Locale.current, "esES")
    H.eq(ns.L.MATERIALS, "Materiales")
end)

H.test("a key missing from the selected language falls back to enUS, then to the key", function()
    local ns = load()
    ns.Locale.register("xxXX", { MATERIALS = "X" })
    ns.Locale.select("xxXX")
    H.eq(ns.L.MATERIALS, "X")
    H.eq(ns.L.NA, "n/a")
    H.eq(ns.L.NO_SUCH_KEY, "NO_SUCH_KEY")
    H.eq(ns.L[5], "5")
end)

H.test("frFR and esES define exactly the enUS keys", function()
    local ns = load()
    local reference = keys(ns.Locale.tables.enUS)
    H.truthy(#reference > 30)
    H.eq(keys(ns.Locale.tables.frFR), reference)
    H.eq(keys(ns.Locale.tables.esES), reference)
end)

H.test("every translation keeps the enUS format specifiers", function()
    local ns = load()
    for _, code in ipairs({ "frFR", "esES" }) do
        for key, text in pairs(ns.Locale.tables.enUS) do
            H.eq(specifiers(ns.Locale.tables[code][key]), specifiers(text))
        end
    end
end)

H.test("the specifier check catches swapped arguments", function()
    H.eq(specifiers("%d of %s"), "%d,%s")
    H.falsy(specifiers("%s of %d") == specifiers("%d of %s"))
end)

H.test("the materials label keeps its noun when a craft count is typed", function()
    local ns = load()
    for _, code in ipairs({ "enUS", "frFR", "esES" }) do
        local t = ns.Locale.tables[code]
        H.eq(string.format(t.MATERIALS_MULTI, 3):sub(1, #t.MATERIALS + 1), t.MATERIALS .. " ")
        H.eq(string.format(t.PANEL_MATERIALS_MULTI, 3):sub(1, #t.PANEL_MATERIALS + 1), t.PANEL_MATERIALS .. " ")
    end
end)

H.test("no translation is empty", function()
    local ns = load()
    for _, code in ipairs({ "enUS", "frFR", "esES" }) do
        for key, text in pairs(ns.Locale.tables[code]) do
            H.truthy(type(text) == "string" and text ~= "" or error(code .. "." .. key .. " is empty"))
        end
    end
end)
