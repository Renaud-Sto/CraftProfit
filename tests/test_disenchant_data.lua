local H = ...

local function brackets() return H.newNS("Util", "Data/Disenchant").Data.Disenchant.brackets end

local KINDS = { armor = true, weapon = true }

H.test("every disenchant bracket is well formed", function()
    for i, b in ipairs(brackets()) do
        local where = "bracket " .. i
        H.truthy(KINDS[b.kind] or error(where .. ": bad kind " .. tostring(b.kind)))
        H.truthy((b.quality == 2 or b.quality == 3 or b.quality == 4) or error(where .. ": bad quality"))
        H.truthy((b.minIlvl >= 1 and b.maxIlvl >= b.minIlvl) or error(where .. ": bad item level range"))
        H.truthy((#b.results > 0) or error(where .. ": no results"))
        local sum, seen = 0, {}
        for _, r in ipairs(b.results) do
            H.truthy((r.itemID == math.floor(r.itemID) and r.itemID > 0) or error(where .. ": bad itemID"))
            if seen[r.itemID] then error(where .. ": duplicate itemID " .. r.itemID) end
            seen[r.itemID] = true
            H.truthy((r.chance > 0 and r.chance <= 1) or error(where .. ": bad chance"))
            H.truthy((r.min >= 1 and r.max >= r.min) or error(where .. ": bad quantity"))
            sum = sum + r.chance
        end
        -- One disenchant yields exactly one kind of result: chances sum to 100%.
        H.truthy(math.abs(sum - 1) <= 0.01 or error(where .. ": chances sum to " .. sum))
    end
end)

H.test("disenchant brackets never overlap for a given kind and quality", function()
    local list = brackets()
    for i = 1, #list do
        for j = i + 1, #list do
            local a, b = list[i], list[j]
            if a.kind == b.kind and a.quality == b.quality then
                local overlap = a.minIlvl <= b.maxIlvl and b.minIlvl <= a.maxIlvl
                if overlap then error(string.format("brackets %d and %d overlap", i, j)) end
            end
        end
    end
end)

H.test("disenchant data covers armor and weapons of uncommon, rare and epic quality", function()
    local have = {}
    for _, b in ipairs(brackets()) do have[b.kind .. b.quality] = true end
    for kind in pairs(KINDS) do
        for quality = 2, 4 do
            H.truthy(have[kind .. quality] or error("no data for " .. kind .. " quality " .. quality))
        end
    end
end)

-- The item levels (1 to 100) with no row, per kind and quality. A gap shows "no data" in
-- the window, never a missing price; this list makes every gap a deliberate choice.
H.test("the disenchant gaps are the known ones", function()
    local list, gaps = brackets(), {}
    for _, kind in ipairs({ "armor", "weapon" }) do
        for quality = 2, 4 do
            local start
            for ilvl = 1, 101 do
                local covered = ilvl == 101
                for _, b in ipairs(list) do
                    if b.kind == kind and b.quality == quality and ilvl >= b.minIlvl and ilvl <= b.maxIlvl then
                        covered = true
                    end
                end
                if not covered and not start then start = ilvl end
                if covered and start then
                    gaps[#gaps + 1] = string.format("%s %d: %d-%d", kind, quality, start, ilvl - 1)
                    start = nil
                end
            end
        end
    end
    H.eq(gaps, {
        "armor 2: 1-4", "armor 2: 61-100", "armor 3: 66-100", "armor 4: 1-39", "armor 4: 61-100",
        "weapon 2: 1-5", "weapon 2: 61-100", "weapon 3: 66-100", "weapon 4: 1-39", "weapon 4: 61-100",
    })
end)
