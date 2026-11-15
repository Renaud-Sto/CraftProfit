-- Known vendor buy prices of common crafting materials, in copper per unit. Pure Lua.
--
-- There is no game API for a vendor's price while its window is closed, so this list
-- covers the usual materials before the player has opened a merchant that sells them
-- (MerchantAdapter.lua records what a merchant really asks, and that always wins).
--
-- Source (R): the vendor price table kept by another addon in renaud's Forever save
-- (build 1.60.1, read 2026-11-15); Leaded Vial = 40c also reported by a CurseForge user.
-- Only round amounts were kept: an odd one (35c, 40s 50c...) was a price seen with a
-- reputation discount, not the base price. Not measured by us: shown as "listed price".
local _, ns = ...

ns.Data = ns.Data or {}

ns.Data.VendorPrices = {
    -- Vials (Alchemy, Poisons)
    [3371] = 4,       -- Empty Vial
    [3372] = 40,      -- Leaded Vial
    [8925] = 500,     -- Crystal Vial
    [18256] = 6000,   -- Imbued Vial
    -- Threads (Tailoring, Leatherworking)
    [2320] = 10,      -- Coarse Thread
    [2321] = 100,     -- Fine Thread
    [4291] = 500,     -- Silken Thread
    [8343] = 2000,    -- Heavy Silken Thread
    [14341] = 5000,   -- Rune Thread
    -- Dyes and bleach (Tailoring, Leatherworking)
    [2324] = 25,      -- Bleach
    [2604] = 50,      -- Red Dye
    [2605] = 100,     -- Green Dye
    [6260] = 50,      -- Blue Dye
    [6261] = 1000,    -- Orange Dye
    [4340] = 350,     -- Gray Dye
    [4341] = 500,     -- Yellow Dye
    [4342] = 2500,    -- Purple Dye
    [2325] = 1000,    -- Black Dye
    [10290] = 2500,   -- Pink Dye
    -- Blacksmithing, Mining, Engineering
    [2880] = 100,     -- Weak Flux
    [3466] = 2000,    -- Strong Flux
    [3857] = 500,     -- Coal
    [4399] = 200,     -- Wooden Stock
    [4400] = 2000,    -- Heavy Stock
    [10647] = 2000,   -- Engineer's Ink
    -- Leatherworking
    [4289] = 50,      -- Salt
    -- Cooking
    [2678] = 10,      -- Mild Spices
    [159] = 5,        -- Refreshing Spring Water
    -- Poisons
    [2928] = 20,      -- Dust of Decay
    [2930] = 50,      -- Essence of Pain
    [5173] = 100,     -- Deathweed
    [8923] = 200,     -- Essence of Agony
    [8924] = 100,     -- Dust of Deterioration
}
