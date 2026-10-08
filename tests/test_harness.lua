local H = ...

H.test("eq compares nested tables", function()
    H.eq({ a = 1, b = { 2, 3 } }, { a = 1, b = { 2, 3 } })
end)

H.test("eq fails on a difference", function()
    H.raises(function() H.eq({ a = 1 }, { a = 2 }) end)
end)

H.test("eq fails on an extra key", function()
    H.raises(function() H.eq({ a = 1, b = 2 }, { a = 1 }) end)
end)

H.test("truthy and falsy", function()
    H.truthy(1)
    H.falsy(nil)
    H.raises(function() H.truthy(false) end)
    H.raises(function() H.falsy(1) end)
end)

H.test("raises passes only when fn throws", function()
    H.raises(function() error("boom") end)
    H.raises(function() H.raises(function() end) end)
end)

H.test("eq fails when expected has a key actual lacks", function()
    H.raises(function() H.eq({ a = 1 }, { a = 1, b = 2 }) end)
end)

H.test("eq tells false from nil in both directions", function()
    H.raises(function() H.eq({ a = false }, {}) end)
    H.raises(function() H.eq({}, { a = false }) end)
    H.eq({ a = false }, { a = false })
end)

local function cyclic(leaf)
    local t = { leaf = leaf, child = {} }
    t.self = t
    t.child.parent = t
    return t
end

H.test("eq accepts the same cyclic table", function()
    local t = {}
    t.self = t
    H.eq(t, t)
end)

H.test("eq compares separately built identical cyclic tables", function()
    H.eq(cyclic(1), cyclic(1))
end)

H.test("eq reports differing cyclic tables without overflowing", function()
    local err = H.raises(function() H.eq(cyclic(1), cyclic(2)) end)
    H.truthy(tostring(err):find("expected", 1, true))
    H.truthy(tostring(err):find("got", 1, true))
    H.falsy(tostring(err):find("overflow", 1, true))
end)

H.test("dump marks a cycle", function()
    H.truthy(H.dump(cyclic(1)):find("<cycle>", 1, true))
end)

H.test("dump prints a shared non-cyclic table twice", function()
    local shared = { 1 }
    H.falsy(H.dump({ a = shared, b = shared }):find("<cycle>", 1, true))
end)
