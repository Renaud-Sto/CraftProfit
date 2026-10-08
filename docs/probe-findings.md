# Probe findings (WoW: Forever beta)

Filled in by hand after running `/cpp` commands in the game (Task 2). Build: ____ (from `/cpp locale`). Date: ____.
Status marks: ✅ measured in game · ⚠️ not measured · ❌ unusable.

## F1. Search type for reagents (`/cpp search 2772`, then `/cpp search <a weapon/armor itemID>`)
- Event received for a reagent: `COMMODITY_SEARCH_RESULTS_UPDATED` / `ITEM_SEARCH_RESULTS_UPDATED` (circle one) — ____
- Event received for a piece of gear: ____
- Fields on a result: ____ (commodity: `unitPrice`, `quantity`; item: `buyoutAmount`, `quantity`)
- Latency from query to event: ____ s. Zero-result search still fires the event: yes / no.

## F2. Replicate rows (`/cpp replicate`, once per 15 min)
- Row layout matches (name, texture, count, quality, usable, level, levelType, minBid, minIncrement, buyout, bid, highBidder, bidderFullName, owner, ownerFullName, saleStatus, itemID, hasAll): yes / no — ____
- For a stack row (count > 1): is `buyout` the **whole stack** or **per unit**? ____  → sets `AH.PER_UNIT_REPLICATE` in Task 13 (false = whole stack).
- Any `<SECRET>` fields: ____

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
