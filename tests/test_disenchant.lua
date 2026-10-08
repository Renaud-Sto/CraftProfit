local H = ...

local function load() return H.newNS("Util", "Data/Disenchant").Data.Disenchant end

local FIXTURE = {
    { kind = "armor", quality = 2, minIlvl = 10, maxIlvl = 20,
      results = { { itemID = 1, chance = 1, min = 1, max = 2 } } },
    { kind = "armor", quality = 2, minIlvl = 21, maxIlvl = 30,
      results = { { itemID = 2, chance = 1, min = 1, max = 2 } } },
    { kind = "weapon", quality = 3, minIlvl = 10, maxIlvl = 20,
      results = { { itemID = 3, chance = 1, min = 1, max = 1 } } },
}

H.test("kindOf maps item classes", function()
    local D = load()
    H.eq(D.kindOf(2), "weapon")
    H.eq(D.kindOf(4), "armor")
    H.eq(D.kindOf(0), nil)
    H.eq(D.kindOf(nil), nil)
end)

H.test("canDisenchant needs weapon or armor of uncommon to epic quality", function()
    local D = load()
    H.truthy(D.canDisenchant(100, 2, 4))
    H.truthy(D.canDisenchant(100, 4, 2))
    H.falsy(D.canDisenchant(100, 1, 4))
    H.falsy(D.canDisenchant(100, 5, 4))
    H.falsy(D.canDisenchant(100, 2, 0))
    H.falsy(D.canDisenchant(100, nil, 4))
end)

H.test("canDisenchant honours the exclusion list", function()
    local D = load()
    D.excluded[555] = true
    H.falsy(D.canDisenchant(555, 2, 4))
    D.excluded[555] = nil
end)

H.test("lookup matches kind, quality and an inclusive item level range", function()
    local D = load()
    H.eq(D.lookup("armor", 2, 10, FIXTURE)[1].itemID, 1)
    H.eq(D.lookup("armor", 2, 20, FIXTURE)[1].itemID, 1)
    H.eq(D.lookup("armor", 2, 21, FIXTURE)[1].itemID, 2)
    H.eq(D.lookup("weapon", 3, 15, FIXTURE)[1].itemID, 3)
end)

H.test("lookup returns nil outside every bracket", function()
    local D = load()
    H.eq(D.lookup("armor", 2, 9, FIXTURE), nil)
    H.eq(D.lookup("armor", 2, 31, FIXTURE), nil)
    H.eq(D.lookup("armor", 3, 15, FIXTURE), nil)
    H.eq(D.lookup("weapon", 2, 15, FIXTURE), nil)
    H.eq(D.lookup(nil, 2, 15, FIXTURE), nil)
end)

H.test("lookup returns nil for a NaN or missing item level", function()
    local D = load()
    H.eq(D.lookup("armor", 2, 0 / 0, FIXTURE), nil)
    H.eq(D.lookup("armor", 2, nil, FIXTURE), nil)
end)
