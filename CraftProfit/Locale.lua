-- Language selection with fallback: selected language -> enUS -> the key.
-- Pure Lua, no WoW API (the caller passes GetLocale()).
local _, ns = ...

local Locale = { tables = {}, aliases = {}, current = "enUS" }
ns.Locale = Locale

function Locale.register(code, tbl)
    Locale.tables[code] = tbl
end

-- A locale that reuses another one's strings (esMX -> esES).
function Locale.alias(code, target)
    Locale.aliases[code] = target
end

-- Unknown or non-string codes select enUS.
function Locale.select(code)
    code = Locale.aliases[code] or code
    if type(code) ~= "string" or not Locale.tables[code] then code = "enUS" end
    Locale.current = code
end

local function lookup(key)
    local selected = Locale.tables[Locale.current]
    local text = selected and selected[key]
    if text == nil then
        local reference = Locale.tables.enUS
        text = reference and reference[key]
    end
    if text == nil then return tostring(key) end
    return text
end

ns.L = setmetatable({}, { __index = function(_, key) return lookup(key) end })
