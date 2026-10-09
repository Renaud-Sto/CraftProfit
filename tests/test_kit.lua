local H = ...
local W = dofile("tests/fakewow.lua")

local function load()
    return H.newNS("Theme", "UI/Kit").Kit
end

H.test("panelHeight adds the header, the body padding and the rows", function()
    local Kit = load()
    H.eq(Kit.panelHeight(3, 18), 22 + 8 + 54)
    H.eq(Kit.panelHeight(0, 18), 30)
    H.eq(Kit.panelHeight(nil, 18), 30)
    H.eq(Kit.panelHeight(-4, 18), 30)
    H.eq(Kit.panelHeight(2, 18, 10), 22 + 8 + 36 + 10)
    H.eq(Kit.panelHeight(2.9, 10), 22 + 8 + 20)
end)

H.test("stack places panels one under the other with a gap and reports the total", function()
    local Kit = load()
    local offsets, total = Kit.stack({ 30, 20 }, 8, 10)
    H.eq(offsets, { -10, -48 })
    H.eq(total, 58)
    offsets, total = Kit.stack({ 50 }, 8)
    H.eq(offsets, { 0 })
    H.eq(total, 50)
    offsets, total = Kit.stack({}, 8)
    H.eq(offsets, {})
    H.eq(total, 0)
end)

H.test("fitSize picks the largest size that fits, the smallest when none does", function()
    local Kit = load()
    local sizes = { 19, 17, 15, 13 }
    H.eq(Kit.fitSize(100, 19, 120, sizes), 19)
    H.eq(Kit.fitSize(150, 19, 120, sizes), 15)
    H.eq(Kit.fitSize(1000, 19, 120, sizes), 13)
    H.eq(Kit.fitSize(nil, 19, 120, sizes), 19)
    H.eq(Kit.fitSize("x", 19, 120, sizes), 19)
    H.eq(Kit.fitSize(150, 0, 120, sizes), 19)
end)

local function withColor(fn)
    local saved = _G.CreateColor
    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    local ok, err = pcall(fn)
    _G.CreateColor = saved
    if not ok then error(err, 0) end
end

local TOP, BOTTOM = { 1, 0, 0, 1 }, { 0, 0, 1, 1 }

H.test("gradient uses colour objects when the client takes them, bottom colour first", function()
    local Kit = load()
    withColor(function()
        local got
        local tex = { SetGradient = function(_, orientation, a, b) got = { orientation, a, b } end }
        H.eq(Kit.gradient(tex, TOP, BOTTOM), "color")
        H.eq(got[1], "VERTICAL")
        H.eq(got[2].b, 1)
        H.eq(got[3].r, 1)
    end)
end)

H.test("gradient falls back to the six-number signature, then to a flat colour", function()
    local Kit = load()
    local saved = _G.CreateColor
    _G.CreateColor = nil
    local got
    local tex = { SetGradient = function(_, orientation, r1, _, b1, r2) got = { orientation, r1, b1, r2 } end }
    H.eq(Kit.gradient(tex, TOP, BOTTOM), "rgb")
    H.eq(got, { "VERTICAL", 0, 1, 1 })
    local flat
    local failing = {
        SetGradient = function() error("bad signature") end,
        SetColorTexture = function(_, r, g, b, a) flat = { r, g, b, a } end,
    }
    H.eq(Kit.gradient(failing, TOP, BOTTOM), "flat")
    H.eq(flat, { 0.5, 0, 0.5, 1 })
    flat = nil
    local missing = { SetColorTexture = function(_, r, g, b, a) flat = { r, g, b, a } end }
    H.eq(Kit.gradient(missing, TOP, BOTTOM), "flat")
    H.eq(flat, { 0.5, 0, 0.5, 1 })
    _G.CreateColor = saved
end)

H.test("the kit file is loaded by the fake game environment", function()
    local T = W.boot(H)
    H.truthy(T.ns.Kit)
    H.truthy(T.ns.Theme)
end)
