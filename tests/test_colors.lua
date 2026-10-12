local H = ...

-- Loads Colors.lua in its own environment, with `globals` as the game's globals.
local function load(globals)
    local env = setmetatable(globals or {}, { __index = _G })
    local ns = {}
    H.loadModule("Colors", ns, env)
    return ns.Colors, env
end

local function colour(r, g, b, a)
    return { GetRGBA = function() return r, g, b, a end }
end

H.test("the meaning colours keep their values", function()
    local Colors = load()
    H.eq(Colors.FIXED, {
        profit = { 0.35, 0.90, 0.45, 1 },
        loss = { 1.00, 0.40, 0.35, 1 },
        incomplete = { 1.00, 0.82, 0.25, 1 },
        stale = { 1.00, 0.60, 0.25, 1 },
        best = { 1.00, 0.82, 0.00, 1 },
        optimal = { 1.00, 0.50, 0.25, 1 },
        medium = { 1.00, 0.82, 0.00, 1 },
        easy = { 0.25, 0.75, 0.25, 1 },
        trivial = { 0.55, 0.55, 0.55, 1 },
    })
end)

H.test("the chart's line colours keep their values", function()
    local Colors = load()
    H.eq(Colors.CHART, {
        grid = { 0.5, 0.5, 0.5, 0.25 },
        zero = { 0.8, 0.8, 0.8, 0.6 },
        usual = { 1, 1, 1, 0.7 },
    })
end)

H.test("text colours fall back to white, grey and gold without the game's globals", function()
    local Colors = load()
    H.eq(Colors.text("main"), { 1, 1, 1, 1 })
    H.eq(Colors.text("muted"), { 0.5, 0.5, 0.5, 1 })
    H.eq(Colors.text("gold"), { 1, 0.82, 0, 1 })
    H.eq(Colors.text("nope"), { 1, 1, 1, 1 })
end)

H.test("text colours fall back when the globals are no-ops, answer nothing or raise", function()
    local noop = function() end
    local Colors, env = load({
        HIGHLIGHT_FONT_COLOR = noop,
        DISABLED_FONT_COLOR = { GetRGBA = noop },
        NORMAL_FONT_COLOR = { GetRGBA = function() error("changed build") end },
    })
    H.eq(Colors.text("main"), { 1, 1, 1, 1 })
    H.eq(Colors.text("muted"), { 0.5, 0.5, 0.5, 1 })
    H.eq(Colors.text("gold"), { 1, 0.82, 0, 1 })
    env.NORMAL_FONT_COLOR = { GetRGBA = function() return "1", 0, 0 end }
    H.eq(Colors.text("gold"), { 1, 0.82, 0, 1 })
end)

H.test("text colours read the game's colour objects at each call, alpha 1 when not given", function()
    local Colors, env = load({
        HIGHLIGHT_FONT_COLOR = colour(0.9, 0.9, 0.9, 0.8),
        DISABLED_FONT_COLOR = colour(0.4, 0.4, 0.4),
        NORMAL_FONT_COLOR = colour(1, 0.8, 0.1, 1),
    })
    H.eq(Colors.text("main"), { 0.9, 0.9, 0.9, 0.8 })
    H.eq(Colors.text("muted"), { 0.4, 0.4, 0.4, 1 })
    H.eq(Colors.text("gold"), { 1, 0.8, 0.1, 1 })
    env.HIGHLIGHT_FONT_COLOR = colour(0.7, 0.7, 0.7, 1)
    H.eq(Colors.text("main"), { 0.7, 0.7, 0.7, 1 })
    -- A fresh table each time: the caller may keep or change it.
    local a = Colors.text("muted")
    a[1] = 0
    H.eq(Colors.text("muted")[1], 0.4)
end)

H.test("escape turns a colour into a chat colour escape and clamps out-of-range channels", function()
    local Colors = load()
    H.eq(Colors.escape({ 1, 0.82, 0, 1 }), "|cffffd100")
    H.eq(Colors.escape({ 0, 0, 0, 1 }), "|cff000000")
    H.eq(Colors.escape({ 2, -1, 0.5, 1 }), "|cffff0080")
    H.eq(Colors.escape({ 2, -1, 0.5 }), "|cffff0080")
    H.eq(Colors.escape(Colors.FIXED.best), "|cffffd100")
end)

H.test("tone gives the meaning colour of a gain or a loss, else the asked text colour", function()
    local C = load()
    H.eq(C.tone("profit", "muted"), C.FIXED.profit)
    H.eq(C.tone("loss", "main"), C.FIXED.loss)
    H.eq(C.tone("muted", "muted"), C.text("muted"))
    H.eq(C.tone(nil, "main"), C.text("main"))
end)
