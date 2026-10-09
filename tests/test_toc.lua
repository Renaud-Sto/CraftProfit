local H = ...

local function tocFiles()
    local files = {}
    local f = assert(io.open("CraftProfit/CraftProfit.toc"))
    for line in f:lines() do
        if not line:match("^##") and line:match("%S") then files[#files + 1] = line:match("^%s*(.-)%s*$") end
    end
    f:close()
    return files
end

local function lua_files_on_disk()
    local found = {}
    local p = io.popen("cd CraftProfit && find . -name '*.lua' | sed 's#^\\./##' | sort")
    for line in p:lines() do found[#found + 1] = line end
    p:close()
    return found
end

H.test("every file listed in the TOC exists", function()
    for _, name in ipairs(tocFiles()) do
        local f = io.open("CraftProfit/" .. name)
        H.truthy(f or error("TOC lists a missing file: " .. name))
        f:close()
    end
end)

H.test("every addon Lua file is listed in the TOC exactly once", function()
    local listed = {}
    for _, name in ipairs(tocFiles()) do
        if listed[name] then error("listed twice: " .. name) end
        listed[name] = true
    end
    for _, name in ipairs(lua_files_on_disk()) do
        if not listed[name] then error("not in the TOC: " .. name) end
    end
end)

H.test("the TOC declares the Forever interface and both saved variables", function()
    local f = assert(io.open("CraftProfit/CraftProfit.toc"))
    local text = f:read("*a")
    f:close()
    H.truthy(text:find("## Interface: 16001", 1, true))
    H.truthy(text:find("## SavedVariables: CraftProfitDB", 1, true))
    H.truthy(text:find("## SavedVariablesPerCharacter: CraftProfitCharDB", 1, true))
end)

H.test("no addon file uses syntax or APIs missing from WoW's Lua 5.1", function()
    for _, name in ipairs(lua_files_on_disk()) do
        local f = assert(io.open("CraftProfit/" .. name))
        local text = f:read("*a")
        f:close()
        for _, banned in ipairs({ "goto ", "require%(", "io%.", "loadfile", "dofile", "setfenv", "getfenv" }) do
            if text:find(banned) then error(name .. " uses " .. banned) end
        end
    end
end)

H.test("the probe TOC is not empty and declares its interface, saved variable and file", function()
    local f = assert(io.open("probe/CraftProfitProbe/CraftProfitProbe.toc"))
    local text = f:read("*a")
    f:close()
    H.truthy(text:find("## Interface: 16001", 1, true))
    H.truthy(text:find("## SavedVariables: CraftProfitProbeLog", 1, true))
    H.truthy(text:find("Probe.lua", 1, true))
    local lua = assert(io.open("probe/CraftProfitProbe/Probe.lua"))
    H.truthy(#lua:read("*a") > 0)
    lua:close()
end)
