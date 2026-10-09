local H = ...

local function load()
    return H.newNS("Theme").Theme
end

local function lin(c)
    if c <= 0.03928 then return c / 12.92 end
    return ((c + 0.055) / 1.055) ^ 2.4
end

local function luminance(c)
    return 0.2126 * lin(c[1]) + 0.7152 * lin(c[2]) + 0.0722 * lin(c[3])
end

local function contrast(a, b)
    local la, lb = luminance(a), luminance(b)
    if la < lb then la, lb = lb, la end
    return (la + 0.05) / (lb + 0.05)
end

H.test("the three themes exist, gold first and default", function()
    local Theme = load()
    H.eq(Theme.list(), { "gold", "copper", "steel" })
    H.eq(Theme.DEFAULT, "gold")
    for _, name in ipairs(Theme.list()) do H.truthy(Theme.exists(name)) end
    H.falsy(Theme.exists("nope"))
    H.falsy(Theme.exists(5))
end)

H.test("get falls back to the default theme for anything unknown", function()
    local Theme = load()
    H.eq(Theme.get("copper").name, "copper")
    H.eq(Theme.get("nope").name, "gold")
    H.eq(Theme.get(nil).name, "gold")
    H.eq(Theme.get(12).name, "gold")
end)

H.test("every theme has every token as four numbers in 0..1", function()
    local Theme = load()
    for _, name in ipairs(Theme.list()) do
        local ok, reason = Theme.validate(Theme.get(name))
        if not ok then error(name .. ": " .. tostring(reason)) end
    end
end)

H.test("validate rejects a missing token, a short colour, a value out of range and NaN", function()
    local Theme = load()
    local function copy()
        local t = {}
        for k, v in pairs(Theme.get("gold")) do t[k] = v end
        return t
    end
    local t = copy()
    t.panelBg = nil
    H.falsy((Theme.validate(t)))
    t = copy()
    t.panelBg = { 0, 0, 0 }
    H.falsy((Theme.validate(t)))
    t = copy()
    t.panelBg = { 0, 0, 2, 1 }
    H.falsy((Theme.validate(t)))
    t = copy()
    t.panelBg = { 0, 0, 0, 1 }
    t.panelBg[2] = math.huge - math.huge
    H.falsy((Theme.validate(t)))
    H.falsy((Theme.validate("x")))
    H.falsy((Theme.validate(nil)))
end)

H.test("the themes differ from each other", function()
    local Theme = load()
    H.truthy(Theme.get("gold").frameOuter[1] ~= Theme.get("copper").frameOuter[1])
    H.truthy(Theme.get("gold").frameOuter[3] ~= Theme.get("steel").frameOuter[3])
end)

H.test("fixed colours exist and are valid colours", function()
    local Theme = load()
    for _, key in ipairs({ "profit", "loss", "incomplete", "stale", "best", "optimal", "medium", "easy", "trivial" }) do
        local c = Theme.FIXED[key]
        H.truthy(c)
        H.eq(#c, 4)
    end
end)

H.test("meaningful colours and text stay readable on the panels of every theme", function()
    local Theme = load()
    for _, name in ipairs(Theme.list()) do
        local t = Theme.get(name)
        for key, c in pairs(Theme.FIXED) do
            if contrast(c, t.panelBg) < 4.5 then error(name .. ": fixed " .. key .. " on panelBg") end
            if contrast(c, t.windowBg) < 4.5 then error(name .. ": fixed " .. key .. " on windowBg") end
        end
        if contrast(t.textMain, t.panelBg) < 4.5 then error(name .. ": textMain") end
        if contrast(t.textMuted, t.panelBg) < 4.5 then error(name .. ": textMuted") end
        if contrast(t.headText, t.headBgTop) < 4.5 then error(name .. ": headText") end
        if contrast(t.buttonText, t.buttonBg) < 4.5 then error(name .. ": buttonText") end
        if contrast(t.primaryText, t.primaryBg) < 4.5 then error(name .. ": primaryText") end
    end
end)

H.test("the hover fill token exists in every theme", function()
    local Theme = load()
    for _, name in ipairs(Theme.list()) do H.truthy(Theme.get(name).rowHover) end
end)

H.test("the text drawn on inputs, check marks and the title plaque stays readable in every theme", function()
    local Theme = load()
    for _, name in ipairs(Theme.list()) do
        local t = Theme.get(name)
        if contrast(t.textMain, t.inputBg) < 4.5 then error(name .. ": textMain on inputBg") end
        if contrast(t.checkMark, t.inputBg) < 4.5 then error(name .. ": checkMark on inputBg") end
        if contrast(t.plaqueText, t.plaqueBg) < 4.5 then error(name .. ": plaqueText on plaqueBg") end
    end
end)
