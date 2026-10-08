local H = ...

local function load() return H.newNS("Util", "Data/Skillup") end

H.test("name accepts Enum numbers and strings in any case", function()
    local S = load().Data.Skillup
    H.eq(S.name(0), "optimal")
    H.eq(S.name(1), "medium")
    H.eq(S.name(2), "easy")
    H.eq(S.name(3), "trivial")
    H.eq(S.name("Optimal"), "optimal")
    H.eq(S.name("TRIVIAL"), "trivial")
end)

H.test("name rejects anything else", function()
    local S = load().Data.Skillup
    H.eq(S.name(4), nil)
    H.eq(S.name(-1), nil)
    H.eq(S.name(0 / 0), nil)
    H.eq(S.name("header"), nil)
    H.eq(S.name(nil), nil)
    H.eq(S.name({}), nil)
end)

H.test("chance maps a difficulty to its estimated probability", function()
    local S = load().Data.Skillup
    H.eq(S.chance("optimal"), 1)
    H.eq(S.chance(1), 0.75)
    H.eq(S.chance("easy"), 0.25)
    H.eq(S.chance(3), 0)
    H.eq(S.chance(nil), nil)
end)
