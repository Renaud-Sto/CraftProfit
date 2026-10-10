local H = ...

local function load() return H.newNS("Util", "Format") end

H.test("money prints gold, silver and copper", function()
    local ns = load()
    H.eq(ns.Format.money(123456), "12g 34s 56c")
    H.eq(ns.Format.money(10000), "1g")
    H.eq(ns.Format.money(150), "1s 50c")
    H.eq(ns.Format.money(0), "0c")
end)

H.test("money drops the copper from 100 gold up, rounding to the nearest silver", function()
    local ns = load()
    H.eq(ns.Format.money(999 * 10000 + 99 * 100 + 99), "1000g")
    H.eq(ns.Format.money(100 * 10000 + 150), "100g 2s")
    H.eq(ns.Format.money(100 * 10000 + 49), "100g")
    H.eq(ns.Format.money(100 * 10000 - 1), "99g 99s 99c")
    H.eq(ns.Format.money(-(150 * 10000 + 5050)), "-150g 51s")
    local seen
    ns.Format.money(250 * 10000 + 99, function(c) seen = c return "x" end)
    H.eq(seen, 250 * 10000 + 100)
end)

H.test("money shows ? for anything that is not a finite number", function()
    local ns = load()
    H.eq(ns.Format.money(nil), "?")
    H.eq(ns.Format.money(0 / 0), "?")
    H.eq(ns.Format.money(1 / 0), "?")
    H.eq(ns.Format.money("12"), "?")
end)

H.test("money prefixes negatives and never prints -0", function()
    local ns = load()
    H.eq(ns.Format.money(-150), "-1s 50c")
    H.eq(ns.Format.money(-0.4), "0c")
end)

H.test("money rounds to the nearest copper and clamps huge values", function()
    local ns = load()
    H.eq(ns.Format.money(149.5), "1s 50c")
    H.eq(ns.Format.money(1e30), ns.Format.money(ns.Format.MAX_COPPER))
end)

H.test("money delegates to the coin function when given one", function()
    local ns = load()
    local seen
    local text = ns.Format.money(-1234, function(c) seen = c; return "<" .. c .. ">" end)
    H.eq(seen, 1234)
    H.eq(text, "-<1234>")
end)

H.test("age picks the largest unit and rejects bad input", function()
    local ns = load()
    H.eq({ ns.Format.age(5) }, { 5, "sec" })
    H.eq({ ns.Format.age(59.9) }, { 59, "sec" })
    H.eq({ ns.Format.age(60) }, { 1, "min" })
    H.eq({ ns.Format.age(3600) }, { 1, "hour" })
    H.eq({ ns.Format.age(172800) }, { 2, "day" })
    H.eq({ ns.Format.age(-1) }, {})
    H.eq({ ns.Format.age(0 / 0) }, {})
    H.eq({ ns.Format.age(nil) }, {})
end)
