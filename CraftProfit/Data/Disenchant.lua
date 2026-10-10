-- Disenchanting: which items qualify and what they yield. Pure Lua, no WoW API.
local _, ns = ...
local Util = ns.Util

ns.Data = ns.Data or {}
local D = {}
ns.Data.Disenchant = D

-- classID values returned by C_Item.GetItemInfo.
D.CLASS_WEAPON = 2
D.CLASS_ARMOR = 4
-- Quality 2 (uncommon) to 4 (epic).
D.MIN_QUALITY = 2
D.MAX_QUALITY = 4

-- Items that never disenchant although class and quality fit: [itemID] = true.
D.excluded = {}

-- One bracket per (kind, quality, item level range), ranges inclusive. Chances
-- of one bracket sum to 1; entries are { itemID, chance, min, max }.
-- Source: Classic (vanilla) disenchanting tables, "Disenchanting tables",
--   https://warcraft.wiki.gg/wiki/Disenchanting_tables (wikitext, fetched 2026-10-08)
-- Item IDs checked against the item pages on warcraft.wiki.gg (fetched 2026-10-08).
-- The source gives no quantity for shards and Nexus Crystal from uncommon/rare
-- items: they are recorded as 1 (assumption, to confirm in game). Epic items below
-- item level 40 have no row (the UI shows "?").
-- UNVERIFIED IN FOREVER
D.brackets = {
    { kind = "armor", quality = 2, minIlvl = 5, maxIlvl = 15, results = {
        { itemID = 10940, chance = 0.8, min = 1, max = 2 }, -- strange
        { itemID = 10938, chance = 0.2, min = 1, max = 2 }, -- lmagic
    } },
    { kind = "armor", quality = 2, minIlvl = 16, maxIlvl = 20, results = {
        { itemID = 10940, chance = 0.75, min = 2, max = 3 }, -- strange
        { itemID = 10939, chance = 0.2, min = 1, max = 2 }, -- gmagic
        { itemID = 10978, chance = 0.05, min = 1, max = 1 }, -- sglim
    } },
    { kind = "armor", quality = 2, minIlvl = 21, maxIlvl = 25, results = {
        { itemID = 10940, chance = 0.75, min = 4, max = 6 }, -- strange
        { itemID = 10998, chance = 0.15, min = 1, max = 2 }, -- lastral
        { itemID = 10978, chance = 0.1, min = 1, max = 1 }, -- sglim
    } },
    { kind = "armor", quality = 2, minIlvl = 26, maxIlvl = 30, results = {
        { itemID = 11083, chance = 0.75, min = 1, max = 2 }, -- soul
        { itemID = 11082, chance = 0.2, min = 1, max = 2 }, -- gastral
        { itemID = 11084, chance = 0.05, min = 1, max = 1 }, -- lglim
    } },
    { kind = "armor", quality = 2, minIlvl = 31, maxIlvl = 35, results = {
        { itemID = 11083, chance = 0.75, min = 2, max = 5 }, -- soul
        { itemID = 11134, chance = 0.2, min = 1, max = 2 }, -- lmystic
        { itemID = 11138, chance = 0.05, min = 1, max = 1 }, -- sglow
    } },
    { kind = "armor", quality = 2, minIlvl = 36, maxIlvl = 40, results = {
        { itemID = 11137, chance = 0.75, min = 1, max = 2 }, -- vision
        { itemID = 11135, chance = 0.2, min = 1, max = 2 }, -- gmystic
        { itemID = 11139, chance = 0.05, min = 1, max = 1 }, -- lglow
    } },
    { kind = "armor", quality = 2, minIlvl = 41, maxIlvl = 45, results = {
        { itemID = 11137, chance = 0.75, min = 2, max = 5 }, -- vision
        { itemID = 11174, chance = 0.2, min = 1, max = 2 }, -- lnether
        { itemID = 11177, chance = 0.05, min = 1, max = 1 }, -- srad
    } },
    { kind = "armor", quality = 2, minIlvl = 46, maxIlvl = 50, results = {
        { itemID = 11176, chance = 0.75, min = 1, max = 2 }, -- dream
        { itemID = 11175, chance = 0.2, min = 1, max = 2 }, -- gnether
        { itemID = 11178, chance = 0.05, min = 1, max = 1 }, -- lrad
    } },
    { kind = "armor", quality = 2, minIlvl = 51, maxIlvl = 55, results = {
        { itemID = 11176, chance = 0.75, min = 2, max = 5 }, -- dream
        { itemID = 16202, chance = 0.2, min = 1, max = 2 }, -- leternal
        { itemID = 14343, chance = 0.05, min = 1, max = 1 }, -- sbril
    } },
    { kind = "armor", quality = 2, minIlvl = 56, maxIlvl = 60, results = {
        { itemID = 16204, chance = 0.75, min = 1, max = 2 }, -- illusion
        { itemID = 16203, chance = 0.2, min = 1, max = 2 }, -- geternal
        { itemID = 14344, chance = 0.05, min = 1, max = 1 }, -- lbril
    } },
    { kind = "weapon", quality = 2, minIlvl = 6, maxIlvl = 15, results = {
        { itemID = 10940, chance = 0.2, min = 1, max = 2 }, -- strange
        { itemID = 10938, chance = 0.8, min = 1, max = 2 }, -- lmagic
    } },
    { kind = "weapon", quality = 2, minIlvl = 16, maxIlvl = 20, results = {
        { itemID = 10940, chance = 0.2, min = 2, max = 3 }, -- strange
        { itemID = 10939, chance = 0.75, min = 1, max = 2 }, -- gmagic
        { itemID = 10978, chance = 0.05, min = 1, max = 1 }, -- sglim
    } },
    { kind = "weapon", quality = 2, minIlvl = 21, maxIlvl = 25, results = {
        { itemID = 10940, chance = 0.15, min = 4, max = 6 }, -- strange
        { itemID = 10998, chance = 0.75, min = 1, max = 2 }, -- lastral
        { itemID = 10978, chance = 0.1, min = 1, max = 1 }, -- sglim
    } },
    { kind = "weapon", quality = 2, minIlvl = 26, maxIlvl = 30, results = {
        { itemID = 11083, chance = 0.2, min = 1, max = 2 }, -- soul
        { itemID = 11082, chance = 0.75, min = 1, max = 2 }, -- gastral
        { itemID = 11084, chance = 0.05, min = 1, max = 1 }, -- lglim
    } },
    { kind = "weapon", quality = 2, minIlvl = 31, maxIlvl = 35, results = {
        { itemID = 11083, chance = 0.2, min = 2, max = 5 }, -- soul
        { itemID = 11134, chance = 0.75, min = 1, max = 2 }, -- lmystic
        { itemID = 11138, chance = 0.05, min = 1, max = 1 }, -- sglow
    } },
    { kind = "weapon", quality = 2, minIlvl = 36, maxIlvl = 40, results = {
        { itemID = 11137, chance = 0.2, min = 1, max = 2 }, -- vision
        { itemID = 11135, chance = 0.75, min = 1, max = 2 }, -- gmystic
        { itemID = 11139, chance = 0.05, min = 1, max = 1 }, -- lglow
    } },
    { kind = "weapon", quality = 2, minIlvl = 41, maxIlvl = 45, results = {
        { itemID = 11137, chance = 0.2, min = 2, max = 5 }, -- vision
        { itemID = 11174, chance = 0.75, min = 1, max = 2 }, -- lnether
        { itemID = 11177, chance = 0.05, min = 1, max = 1 }, -- srad
    } },
    { kind = "weapon", quality = 2, minIlvl = 46, maxIlvl = 50, results = {
        { itemID = 11176, chance = 0.2, min = 1, max = 2 }, -- dream
        { itemID = 11175, chance = 0.75, min = 1, max = 2 }, -- gnether
        { itemID = 11178, chance = 0.05, min = 1, max = 1 }, -- lrad
    } },
    { kind = "weapon", quality = 2, minIlvl = 51, maxIlvl = 55, results = {
        { itemID = 11176, chance = 0.22, min = 2, max = 5 }, -- dream
        { itemID = 16202, chance = 0.75, min = 1, max = 2 }, -- leternal
        { itemID = 14343, chance = 0.03, min = 1, max = 1 }, -- sbril
    } },
    { kind = "weapon", quality = 2, minIlvl = 56, maxIlvl = 60, results = {
        { itemID = 16204, chance = 0.22, min = 1, max = 2 }, -- illusion
        { itemID = 16203, chance = 0.75, min = 1, max = 2 }, -- geternal
        { itemID = 14344, chance = 0.03, min = 1, max = 1 }, -- lbril
    } },
    { kind = "armor", quality = 3, minIlvl = 1, maxIlvl = 25, results = {
        { itemID = 10978, chance = 1, min = 1, max = 1 }, -- sglim
    } },
    { kind = "armor", quality = 3, minIlvl = 26, maxIlvl = 30, results = {
        { itemID = 11084, chance = 1, min = 1, max = 1 }, -- lglim
    } },
    { kind = "armor", quality = 3, minIlvl = 31, maxIlvl = 35, results = {
        { itemID = 11138, chance = 1, min = 1, max = 1 }, -- sglow
    } },
    { kind = "armor", quality = 3, minIlvl = 36, maxIlvl = 40, results = {
        { itemID = 11139, chance = 1, min = 1, max = 1 }, -- lglow
    } },
    { kind = "armor", quality = 3, minIlvl = 41, maxIlvl = 45, results = {
        { itemID = 11177, chance = 1, min = 1, max = 1 }, -- srad
    } },
    { kind = "armor", quality = 3, minIlvl = 46, maxIlvl = 50, results = {
        { itemID = 11178, chance = 1, min = 1, max = 1 }, -- lrad
    } },
    { kind = "armor", quality = 3, minIlvl = 51, maxIlvl = 55, results = {
        { itemID = 14343, chance = 1, min = 1, max = 1 }, -- sbril
    } },
    { kind = "armor", quality = 3, minIlvl = 56, maxIlvl = 65, results = {
        { itemID = 14344, chance = 0.995, min = 1, max = 1 }, -- lbril
        { itemID = 20725, chance = 0.005, min = 1, max = 1 }, -- nexus
    } },
    { kind = "armor", quality = 4, minIlvl = 40, maxIlvl = 45, results = {
        { itemID = 11177, chance = 1, min = 2, max = 4 }, -- srad
    } },
    { kind = "armor", quality = 4, minIlvl = 46, maxIlvl = 50, results = {
        { itemID = 11178, chance = 1, min = 2, max = 4 }, -- lrad
    } },
    { kind = "armor", quality = 4, minIlvl = 51, maxIlvl = 55, results = {
        { itemID = 14343, chance = 1, min = 2, max = 4 }, -- sbril
    } },
    { kind = "armor", quality = 4, minIlvl = 56, maxIlvl = 60, results = {
        { itemID = 20725, chance = 1, min = 1, max = 1 }, -- nexus
    } },
    { kind = "weapon", quality = 3, minIlvl = 1, maxIlvl = 25, results = {
        { itemID = 10978, chance = 1, min = 1, max = 1 }, -- sglim
    } },
    { kind = "weapon", quality = 3, minIlvl = 26, maxIlvl = 30, results = {
        { itemID = 11084, chance = 1, min = 1, max = 1 }, -- lglim
    } },
    { kind = "weapon", quality = 3, minIlvl = 31, maxIlvl = 35, results = {
        { itemID = 11138, chance = 1, min = 1, max = 1 }, -- sglow
    } },
    { kind = "weapon", quality = 3, minIlvl = 36, maxIlvl = 40, results = {
        { itemID = 11139, chance = 1, min = 1, max = 1 }, -- lglow
    } },
    { kind = "weapon", quality = 3, minIlvl = 41, maxIlvl = 45, results = {
        { itemID = 11177, chance = 1, min = 1, max = 1 }, -- srad
    } },
    { kind = "weapon", quality = 3, minIlvl = 46, maxIlvl = 50, results = {
        { itemID = 11178, chance = 1, min = 1, max = 1 }, -- lrad
    } },
    { kind = "weapon", quality = 3, minIlvl = 51, maxIlvl = 55, results = {
        { itemID = 14343, chance = 1, min = 1, max = 1 }, -- sbril
    } },
    { kind = "weapon", quality = 3, minIlvl = 56, maxIlvl = 65, results = {
        { itemID = 14344, chance = 0.995, min = 1, max = 1 }, -- lbril
        { itemID = 20725, chance = 0.005, min = 1, max = 1 }, -- nexus
    } },
    { kind = "weapon", quality = 4, minIlvl = 40, maxIlvl = 45, results = {
        { itemID = 11177, chance = 1, min = 2, max = 4 }, -- srad
    } },
    { kind = "weapon", quality = 4, minIlvl = 46, maxIlvl = 50, results = {
        { itemID = 11178, chance = 1, min = 2, max = 4 }, -- lrad
    } },
    { kind = "weapon", quality = 4, minIlvl = 51, maxIlvl = 55, results = {
        { itemID = 14343, chance = 1, min = 2, max = 4 }, -- sbril
    } },
    { kind = "weapon", quality = 4, minIlvl = 56, maxIlvl = 60, results = {
        { itemID = 20725, chance = 1, min = 1, max = 1 }, -- nexus
    } },
}

function D.kindOf(classID)
    if classID == D.CLASS_WEAPON then return "weapon" end
    if classID == D.CLASS_ARMOR then return "armor" end
    return nil
end

function D.canDisenchant(itemID, quality, classID)
    if D.excluded[itemID] then return false end
    if not D.kindOf(classID) then return false end
    return type(quality) == "number" and quality >= D.MIN_QUALITY and quality <= D.MAX_QUALITY
end

-- Entries for an item, or nil when no bracket matches (shown as "?" by the UI).
function D.lookup(kind, quality, ilvl, brackets)
    brackets = brackets or D.brackets
    if not Util.isFinite(ilvl) then return nil end
    for _, b in ipairs(brackets) do
        if b.kind == kind and b.quality == quality and ilvl >= b.minIlvl and ilvl <= b.maxIlvl then
            return b.results
        end
    end
    return nil
end
