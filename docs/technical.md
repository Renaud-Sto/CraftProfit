# CraftProfit technical documentation

[Back to the README](../README.md) · [User guide](user-guide.md) · [Contributing](../CONTRIBUTING.md)

Target: **World of Warcraft: Forever** beta, build 1.60.1, `## Interface: 16001`. The client uses the Mainline (Midnight-style) UI and API set on a Classic base, Lua 5.1, and the *secret values* restrictions. The addon is about 3,000 lines of Lua and has no library dependency.

Contents: [Design principles](#design-principles) · [Architecture](#architecture) · [Data flow](#data-flow) · [Price model](#price-model) · [Price history](#price-history) · [Evaluation](#evaluation) · [Saved variables](#saved-variables) · [Game API used](#game-api-used) · [Measured behaviour of the beta](#measured-behaviour-of-the-beta) · [Constraints that shape the code](#constraints-that-shape-the-code) · [Localization](#localization) · [Testing](#testing) · [Probe addon](#probe-addon) · [Packaging](#packaging)

## Design principles

1. **Pure logic apart from the game.** Everything that decides a number is plain Lua with no WoW API, tested offline. Game calls live in thin adapters.
2. **An unknown is never a zero.** A missing price is `nil`, shown as `?`. A recipe with any unpriced reagent has no total and no verdict (*Incomplete*), never a cheap-looking one.
3. **Identifiers, not names.** Items, recipes and professions are handled by id. No logic depends on a displayed (localized) text, and tooltips are never parsed.
4. **Defensive at the boundary.** Every game call that may differ between builds is guarded (`pcall`, type checks, `issecretvalue`); a missing API degrades a feature, it never raises a Lua error.
5. **No taint.** The window is parented to `UIParent`, never to a Blizzard frame. The only Blizzard UI touched is the auction house search box and quantity input, defensively, and the addon never presses Buy.
6. **Saved data is repaired in place.** WoW keeps a reference to the table it loaded, so replacing it would silently lose the data at logout.

## Architecture

Files load in the order of `CraftProfit/CraftProfit.toc`. Each file receives the addon name and a shared namespace table (`local _, ns = ...`) and registers its module on it.

| File | Module | Role | Uses the game API |
| --- | --- | --- | --- |
| `Util.lua` | `ns.Util` | Number guards (`isFinite`, `isCopper`, `count`, `id`), `clamp`, `round` | no |
| `Format.lua` | `ns.Format` | Money and duration formatting | no (the coin formatter is passed in) |
| `Core.lua` | `ns.Core` | Cost sum, net sale, vendor value, expected and likely disenchant, cost per point, best option, ranking helpers | no |
| `Data/Skillup.lua` | `ns.Data.Skillup` | Skill-up chance by recipe colour (estimates) | no |
| `Data/Disenchant.lua` | `ns.Data.Disenchant` | Disenchant eligibility and result tables | no |
| `Locale.lua`, `Locales/*.lua` | `ns.Locale`, `ns.L` | Language selection with fallback; strings for enUS, frFR, esES, esMX (alias) | no |
| `Recipes.lua` | `ns.Recipes` | Validation and normalisation of a recipe read from the game | no |
| `DB.lua` | `ns.DB` | Saved variable defaults, repair, migration, pins, sort mode | no |
| `Prices.lua` | `ns.Prices` | Median price, scan aggregation, price storage and ageing | no |
| `History.lua` | `ns.History` | Tracked recipes (cap 15), price history points per item, retention (raw, daily, weekly) | no |
| `PriceQueue.lua` | `ns.PriceQueue` | Sequential search queue with timeouts | no (a `send` function is injected) |
| `Evaluate.lua` | `ns.Evaluate` | Combines recipe, prices and item facts into one result | no (lookups injected) |
| `Present.lua` | `ns.Present` | Turns a result into display lines (text only) | no |
| `AHAdapter.lua` | `ns.AH` | Auction house: scan, targeted search, search box helper | `C_AuctionHouse`, auction house frame |
| `TradeAdapter.lua` | `ns.Trade` | Profession window: selected recipe, raw recipe data, difficulty, known professions | `C_TradeSkillUI`, professions API |
| `UI/Window.lua` | `ns.Window` | The floating window | frames |
| `UI/PinsUI.lua` | `ns.PinsUI` | Pinned list, sort button, Search prices and Scan AH buttons | frames |
| `Boot.lua` | `ns.Controller` | Wires everything, owns the selection state, slash commands, self-test | events, slash commands |

Dependencies point one way: `Core`, `Data`, `Util`, `Format` know nothing of the rest; `Evaluate` and `Present` use them; adapters and UI use everything; `Boot` is the only file that connects the adapters to the UI.

## Data flow

**Selecting a recipe.** `Trade.watch` polls the profession window every 0.3 s (the Professions UI has no selection event and is created lazily). A new selection id makes `Trade.readSelected()` return a raw recipe, `Recipes.normalize` validates it, and `Controller.setRecipe` renders it. Item data that is not cached yet is requested once (`C_Item.RequestLoadItemDataByID`) and `ITEM_DATA_LOAD_RESULT` triggers a coalesced refresh.

**Rendering.** `Controller.refresh()` calls `Evaluate.run` with the recipe, a price lookup (`Prices.priceOf`), item facts (`Controller.itemInfo`), the commission, the per-point option, the disenchant lookup, whether the character knows Enchanting, and the number of crafts. `Present.build` turns the result into a model (lines, cost lines, verdict, age) and `Window.render` draws it. The pinned list evaluates each pin the same way, always for one craft.

**Searching prices.** `PinsUI.startSearch` builds the list of items the pins need (`Evaluate.wantedItems`) and runs a `PriceQueue`: one `SendSearchQuery` at a time, advanced by `COMMODITY_SEARCH_RESULTS_UPDATED` or `ITEM_SEARCH_RESULTS_UPDATED` or a timeout. `AHAdapter` reads the listings into `{ unit, qty }` rows; `Controller.recordListings` stores the median.

**Scanning.** `AH.requestSnapshot` calls `ReplicateItems` (once per 15 minutes per account). The client then fires `REPLICATE_ITEM_LIST_UPDATE` hundreds of times for one scan, so the adapter schedules **one** read one second after the first event and ignores the rest until 10 seconds after that read. The read walks the rows in chunks of 1,500 per frame (no freeze) into a `Prices.newAggregator()`; `Controller.onSnapshot` merges the result into the saved prices. A scan started by another addon is handled the same way.

**Clicking a reagent.** `AH.browse` switches the auction house to its Buy view, writes the name in `SearchBar.SearchBox` and calls `SearchBar:StartSearch()`. A hook on `CommoditiesBuyFrame`'s `OnShow` then sets the quantity input (`SetQuantity`) and calls the input's own `OnTextChanged` handler with `userInput = true`, which makes the client recompute the quote, as typing would.

## Price model

- A listing becomes `{ unit, qty }`. A stack row of the scan has its stack price divided by the stack size (`AH.PER_UNIT_REPLICATE = false`, measured).
- `Prices.summarize(listings, n)` sorts by unit price and takes the **median unit price of the n cheapest units** (`n = 5` by default, `settings.medianN`), plus the total volume. Quantities are handled arithmetically, so a listing of one billion units costs the same as one of one unit.
- `Prices.store` and `Prices.merge` write compact rows `{ unit, volume, time }` into `CraftProfitDB.prices`; `Prices.get` returns the unit price and its age, and `nil` for the age when the clock cannot be trusted.
- `DB.prune` removes prices older than 14 days at load.
- Selling uses a commission of 5 % (`settings.cut`, measured). The deposit is ignored: it is refunded when an item sells.

## Price history

A recipe is *tracked* with the "Track history" box (account wide, 15 at most; unticking pauses recording and keeps the history, `/cp history remove <n>` deletes it). After every full scan and every price search, `History.record` writes one point per item of each active tracked recipe **touched by that update**, provided every required item has a price (the output of a bind-on-pickup recipe is never required). A point is `{ t, unit, volume, low, high, n }` with `t` the time of the operation, so the items of one recipe share a timestamp and the recipe's cost and net can be rebuilt for that date.

Retention (`History.compact`): all points for 14 days, then one point per day up to 90 days, then one per week up to a year, each merged point keeping the weighted average, the low, the high and the number of measurements. A rough bound is 12 KB per tracked recipe, under 200 KB for 15. The search button still only prices the pinned recipes; tracked recipes are fed by scans and by any search that touches their items. The history is recorded; there is no view of it yet.

## Evaluation

`Evaluate.run(ctx)` returns `{ recipe, crafts, cost, options, best, bestValue, net, incomplete, perPoint, oldestAge }`.

- **Cost** = sum of quantity × unit price of the reagents (`Core.sumCost`); `nil` when any price is missing.
- **Options**: `ah` (net sale, `n/a` for bind-on-pickup), `vendor` (sell price × quantity), `disenchant` (expected value net of the commission, plus `likely`: the most probable outcome). Each has a status `ok`, `unknown` or `na`.
- **Disenchant rules**: armor or weapon of quality 2 to 4 only; a bind-on-pickup item only when the character knows Enchanting (`Trade.hasProfession(333)`: the skill line id, language independent); no table gives `unknown`.
- **Best** = the `ok` option with the highest value (`Core.bestOption`); **net** = best value − cost.
- **Per point** (when enabled) = `(cost − bestValue) / chance`, with the chance from `Data/Skillup` by recipe colour. Computed before the multiplier is applied, so it is always per point.
- **Crafts** (1 to 9999, `Evaluate.craftCount`): after computing for one craft, quantities, cost, option values, best value and net are multiplied; per point and `likely` are not.

## Saved variables

`CraftProfitDB` (account), repaired by `DB.initAccount` and `History.sanitize`:

| Key | Content |
| --- | --- |
| `dbVersion` | Schema version (1) |
| `settings.cut` | AH commission, 0 to 0.5 (0.05) |
| `settings.medianN` | Units in the median, 1 to 20 (5) |
| `settings.staleAfter` | Seconds before prices show as old (3600) |
| `settings.showPerPoint` | Cost per point enabled |
| `settings.costExpanded` | Material detail unfolded |
| `settings.window` | `{ point, x, y }` once dragged |
| `markets["<realm>-<faction>"]` | One price table per market (see below) |
| `tracked` | Up to 15 tracked recipes `{ recipe, active }` |

`CraftProfitCharDB` (per character), repaired by `DB.initChar`:

| Key | Content |
| --- | --- |
| `pins` | Up to 12 normalised recipes `{ recipeID, name, difficulty, outputItemID, outputQty, reagents = { { itemID, qty } } }` |
| `sortMode` | `"net"` or `"point"` |

A market holds `prices[itemID] = { unit, volume, time }`, `snapshotTime` (the last full scan) and `series[itemID]`, the history points `{ t, unit, volume, low, high, n }` of the items of tracked recipes. The market key is the realm id plus the player's faction (`Controller.marketKey`, for example `4613-Horde`), with the normalised realm name as fallback. Forever has rulesets (Normal, PvP, RP, Hardcore) instead of realms; in the beta each ruleset is a "realm" such as *Classic Beta PvP 2* (id 4613), measured with `/cpp ruleset`. `C_GameRules.GetActiveGameMode()` only returns the client's game mode (1, Standard), not the ruleset. The neutral auction house is not told apart from the faction one yet. Prices saved before markets existed (`prices` and `snapshotTime` at the top level) are adopted by the first market used.

Every field is validated on load (finite numbers, ranges, anchor names, array holes); anything invalid falls back to the default.

## Game API used

| Area | Calls |
| --- | --- |
| Auction house | `C_AuctionHouse.ReplicateItems`, `GetNumReplicateItems`, `GetReplicateItemInfo`, `SendSearchQuery`, `MakeItemKey`, `GetNumCommoditySearchResults`, `GetCommoditySearchResultInfo`, `GetNumItemSearchResults`, `GetItemSearchResultInfo`, `IsThrottledMessageSystemReady`; `Enum.AuctionHouseSortOrder`; `AuctionHouseFrame` (`SearchBar`, `CommoditiesBuyFrame`, `SetDisplayMode`) and `AuctionHouseFrameDisplayMode` |
| Professions | `C_TradeSkillUI.GetRecipeInfo`, `GetRecipeSchematic`; `ProfessionsFrame.CraftingPage.SchematicForm:GetRecipeInfo`; `GetProfessions`, `GetProfessionInfo`, `IsPlayerSpell`; classic fallbacks `GetTradeSkill*` |
| Items | `C_Item.GetItemInfo`, `C_Item.RequestLoadItemDataByID` |
| Misc | `GetLocale`, `GetTime`, `time`, `GetCoinTextureString`, `issecretvalue`, `C_Timer` |

Events: `ADDON_LOADED`, `ITEM_DATA_LOAD_RESULT`, `TRADE_SKILL_LIST_UPDATE`, `ADDON_ACTION_BLOCKED`, `ADDON_ACTION_FORBIDDEN`, `AUCTION_HOUSE_SHOW`, `AUCTION_HOUSE_CLOSED`, `COMMODITY_SEARCH_RESULTS_UPDATED`, `ITEM_SEARCH_RESULTS_UPDATED`, `REPLICATE_ITEM_LIST_UPDATE`.

## Measured behaviour of the beta

Measured in game on build 1.60.1, French client (details in [probe-findings.md](probe-findings.md)):

- Reagents are commodities: `COMMODITY_SEARCH_RESULTS_UPDATED` with the item id, fields `unitPrice` and `quantity`. Gear uses `ITEM_SEARCH_RESULTS_UPDATED` with an item key table, fields `buyoutAmount` and `quantity`. Each event arrives twice, harmlessly. A search with no result still fires its event.
- A full scan returns about 79,000 rows of 17 values; `buyout` is the price of the **whole stack**. `REPLICATE_ITEM_LIST_UPDATE` fires hundreds of times per scan. A scan inside the 15 minute window is ignored silently, no event.
- The AH commission is 5 % of the sale price, the deposit is refunded on sale.
- `GetProfessionInfo` returns the skill line id as its 7th value (164 for Blacksmithing, 129 for First Aid); `GetNumSkillLines` does not exist.
- The Mainline auction house frames exist with their usual members. Setting the quantity input alone leaves the quote on one unit; its `OnTextChanged` handler must run with `userInput = true`.

## Constraints that shape the code

- **Secret values.** Some game values are secret: comparing, concatenating or doing arithmetic on them raises. Every value read from the game is checked with `issecretvalue` before use; item names are read inside `pcall`.
- **Division by zero raises.** The client rejects a literal zero divisor (`0 / 0`, `1 / 0`). Every divisor is guarded, NaN and infinity are built from `math.huge`, and a test refuses a literal zero divisor anywhere in the addon.
- **Lua 5.1 only**, no `table.unpack`, `//`, goto or integer division; the offline tests run on LuaJIT, so `/cp selftest` re-checks a few behaviours inside the game's own Lua.
- **The full scan is limited** to one per 15 minutes per account, shared with every addon.
- **No API for sales history**: CraftProfit does not know how fast an item sells.

## Localization

`Locale.select(GetLocale())` picks the table; a missing key falls back to enUS, then to the key itself. `esMX` is an alias of `esES`. There is no hard-coded user-facing string in the UI modules. Tests check that frFR and esES define exactly the enUS keys, keep its format specifiers (`%d`, `%s`) and are never empty. See [CONTRIBUTING.md](../CONTRIBUTING.md#adding-or-fixing-a-language).

## Testing

`sh tests/check.sh` runs both:

- `luajit tests/run.lua`: every `tests/test_*.lua`, with a dependency-free harness (`tests/harness.lua`). Modules are loaded with `H.newNS` or, for the whole addon, `tests/fakewow.lua` which loads the real files in TOC order into a fake game environment (frames, timers, item data, chat).
- `luacheck CraftProfit tests --config .luacheckrc`: zero warnings is required; every game global the addon reads is declared in `.luacheckrc`.

The suite covers the pure modules, the adapters with faked game APIs, saved variable repair, localization, the TOC, and the boot sequence. What it cannot cover is the real client: see [in-game-checklist.md](in-game-checklist.md).

## Probe addon

`probe/CraftProfitProbe` is a throwaway addon (not shipped) that prints what the real client returns: `/cpp api | locale | item | deposit | search | replicate | trade | prof | ahui | qty | log | clear`. It mirrors its output, CraftProfit's chat lines and Lua errors into the `CraftProfitProbeLog` saved variable, written on `/reload`, so results can be read from `WTF/Account/<id>/SavedVariables/CraftProfitProbe.lua`. Use it to settle an API question before coding against it.

## Packaging

The repository contains the addon in `CraftProfit/`, so release tooling must treat that folder as the top level. `CraftProfit/.pkgmeta` configures the BigWigs packager. See [curseforge/submission-checklist.md](curseforge/submission-checklist.md) for the release procedure.

The design history is in [superpowers/](superpowers/): the [design spec](superpowers/specs/2026-10-08-craftprofit-design.md) (in French) and the [implementation plan](superpowers/plans/2026-10-08-craftprofit.md).
