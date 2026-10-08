# Probe findings (WoW: Forever beta)

Filled in by hand after running `/cpp` commands in the game (Task 2). Build: ____ (from `/cpp locale`). Date: ____.
Status marks: ✅ measured in game · ⚠️ not measured · ❌ unusable.

## F1. Search type for reagents (`/cpp search 2772`, then `/cpp search <a weapon/armor itemID>`)
- Event received for a reagent: `COMMODITY_SEARCH_RESULTS_UPDATED` (arg1 = itemID) ✅ 2026-10-08, French client
- Event received for a piece of gear: `ITEM_SEARCH_RESULTS_UPDATED` (arg1 = itemKey table) ✅
- Fields on a result: commodity `unitPrice`, `quantity`; item `buyoutAmount`, `quantity` (`bidAmount` nil) ✅
- Latency from query to event: about 1 s per item in a queue. Zero-result search still fires the event: yes ✅ (`item results: 0`).
- Each search event arrives twice in a row (harmless; results identical).

## F2. Replicate rows (`/cpp replicate`, once per 15 min)
- Row layout matches (17 values then hasAll): yes ✅. 79,078 rows at 15:05:21, one scan.
- The event fires hundreds of times per scan (427 seen in one tail), so reads are debounced.
- For a stack row (count > 1): `buyout` is the **whole stack** ✅ → `AH.PER_UNIT_REPLICATE = false`. Evidence: spring water count 7 buyout 105 (15 each), linen bolt count 18 buyout 1476 (82 each); the scan median per unit matches the targeted search (bronze bar 323 vs 322, coarse grindstone 524 vs 524, item 11083 512 vs 512).
- Any `<SECRET>` fields: none ✅

## F3. Recipe API (`/cpp trade` with the blacksmithing window open and a recipe selected)
- Strategy A (`C_TradeSkillUI`) usable: yes / no — fields seen: ____
- Strategy B (classic `GetTradeSkill*`) usable: yes / no
- `relativeDifficulty` values for a known orange / yellow / green / grey recipe: ____ (expected 0 / 1 / 2 / 3)
- Reagent slot `reagentType` for ordinary reagents: ____ (expected `Enum.CraftingReagentType.Basic`)
- `quantityMin` / `quantityMax` / `outputItemID` present: ____

## F4. Selected recipe detection
- Which expression returns the selected recipeID while a recipe is highlighted: ____
- Does the profession window global exist before first opening (lazy-loaded)? ____

## F5. AH commission and deposit
- Deposit reported by `/cpp deposit <id>` for a 2 (24 h) listing: ____
- Real commission: list an item for a known buyout (for example 100g), buy it with another character or wait for the sale, compare the mailed amount: ____ % → sets `DB.DEFAULTS.cut`.

## F6. Secret values
- `/cpp api` prints `issecretvalue` as `function`: yes / no
- Item names, recipe names and AH row fields that printed `<SECRET>`: ____

## F7. Enum values (printed by `/cpp api`)
- `Enum.TradeskillRelativeDifficulty`: ____
- `Enum.CraftingReagentType`: ____
- `Enum.AuctionHouseSortOrder` present: ____

## F8. Frames and locale
- AH frame global: `AuctionHouseFrame` / `AuctionFrame` — ____
- `GetLocale()`: ____ · `GetCoinTextureString(123456)`: ____
- `C_Item.GetItemInfo(2772)` fields (sellPrice, classID, bindType): ____
