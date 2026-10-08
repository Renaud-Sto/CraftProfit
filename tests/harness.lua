-- Minimal dependency-free test harness (LuaJIT / Lua 5.1).
-- Run from the project root: luajit tests/run.lua
local H = { passed = 0, failed = 0, failures = {} }
local currentFile = "?"

function H.setFile(name) currentFile = name end

-- `path` holds the tables currently being printed (ancestors only), so a
-- cycle prints as <cycle> while a table shared twice still prints in full.
local function dump(v, indent, path)
    indent = indent or ""
    path = path or {}
    if type(v) == "string" then return string.format("%q", v) end
    if type(v) ~= "table" then return tostring(v) end
    if path[v] then return "<cycle>" end
    path[v] = true
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts + 1] = indent .. "  " .. tostring(k) .. " = " .. dump(v[k], indent .. "  ", path)
    end
    path[v] = nil
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end
H.dump = dump

-- `seen[a][b]` marks a pair already under comparison: meeting it again means a
-- cycle, which counts as equal so far (any real difference is found elsewhere).
local function deepEqual(a, b, seen)
    if a == b then return true end
    if type(a) ~= type(b) or type(a) ~= "table" then return false end
    seen = seen or {}
    local row = seen[a]
    if not row then
        row = {}
        seen[a] = row
    end
    if row[b] then return true end
    row[b] = true
    for k, v in pairs(a) do
        if not deepEqual(v, b[k], seen) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

function H.eq(actual, expected)
    if not deepEqual(actual, expected) then
        error("expected " .. dump(expected) .. "\n     got " .. dump(actual), 2)
    end
end

function H.truthy(v)
    if not v then error("expected a truthy value, got " .. dump(v), 2) end
end

function H.falsy(v)
    if v then error("expected a falsy value, got " .. dump(v), 2) end
end

-- H.raises(fn): passes when fn() throws. Returns the error message.
function H.raises(fn)
    local ok, err = pcall(fn)
    if ok then error("expected an error, but none was raised", 2) end
    return err
end

-- Message handler for xpcall: keep the error text and append the call path.
local function withTraceback(err)
    return tostring(err) .. debug.traceback("", 2)
end

-- Indent every line after the first so a failure reads as one block.
local function indentLines(text)
    return (text:gsub("\n", "\n   "))
end

function H.test(name, fn)
    local ok, err = xpcall(fn, withTraceback)
    if ok then
        H.passed = H.passed + 1
    else
        H.failed = H.failed + 1
        local msg = currentFile .. " :: " .. name .. "\n   " .. indentLines(err)
        H.failures[#H.failures + 1] = msg
        print("FAIL " .. msg)
    end
end

-- Load addon modules in order into one fresh namespace table, exactly the way
-- WoW does it: every file receives (addonName, ns) as varargs.
function H.newNS(...)
    local ns = {}
    for _, name in ipairs({ ... }) do
        local chunk, err = loadfile("CraftProfit/" .. name .. ".lua")
        if not chunk then error(err, 2) end
        chunk("CraftProfit", ns)
    end
    return ns
end

-- Load one addon file, optionally inside a fake global environment (the way
-- tests stub the WoW API for the files that talk to the game).
function H.loadModule(name, ns, env)
    local chunk, err = loadfile("CraftProfit/" .. name .. ".lua")
    if not chunk then error(err, 2) end
    if env then setfenv(chunk, env) end
    return chunk("CraftProfit", ns)
end

return H
