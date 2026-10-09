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
| `Leveling.lua` | `ns.Leveling` | Ranks the known recipes of a profession by cost per point | no |
| `Present.lua` | `ns.Present` | Turns a result into display text only: the `banner`, the three `tiles`, the `materials` panel, the cost lines and the older `lines`/`verdict` | no |
| `AHAdapter.lua` | `ns.AH` | Auction house: scan, targeted search, search box helper | `C_AuctionHouse`, auction house frame |
| `TradeAdapter.lua` | `ns.Trade` | Profession window: selected recipe, raw recipe data, difficulty, known professions | `C_TradeSkillUI`, professions API |
| `UI/Window.lua` | `ns.Window` | The main window, on the UI kit | frames |
| `UI/LevelingUI.lua` | `ns.LevelingUI` | The leveling window, on the UI kit: strip (profession and sort buttons), prices age line, a `NEXT POINT` panel of 12 rows with a scroll bar, grey-recipes check box | frames |
| `UI/PinsUI.lua` | `ns.PinsUI` | Pinned list, on the UI kit: a `Pinned recipes` panel with the sort button in its header, 6 visible rows with a scroll bar, the Search prices, Scan AH and Leveling buttons and the status line | frames |
| `Theme.lua` | `ns.Theme` | Colour themes (gold, copper, steel blue) as pure data: `get`, `exists`, `list`, `validate`, and the fixed colours shared by all themes | no |
| `UI/Kit.lua` | `ns.Kit` | Shared layout helpers (`panelHeight`, `stack`, `fitSize`, `gradient`) and widgets (`window`, `panel`, `button`, `tile`, `check`, `input`, `scrollbar`; `panel:onHeaderClick`) and colour helpers (`mix`, `colorEscape`, `onTheme`) and `plaqueWidth`; `applyTheme` repaints every widget without `/reload`. `gradient` gives the texture a white base, then tries the colour-object form, the six-number form, then a flat colour | frames |
| `UI/KitDemo.lua` | `ns.KitDemo` | Developer demo window, `/cp kitdemo [theme]` (not in the user help) | frames |
| `Boot.lua` | `ns.Controller` | Wires everything, owns the selection state, slash commands, self-test | events, slash commands |

Dependencies point one way: `Core`, `Data`, `Util`, `Format` know nothing of the rest; `Evaluate` and `Present` use them; adapters and UI use everything; `Boot` is the only file that connects the adapters to the UI.

## Data flow

**Selecting a recipe.** `Trade.watch` polls the profession window every 0.3 s (the Professions UI has no selection event and is created lazily). A new selection id makes `Trade.readSelected()` return a raw recipe, `Recipes.normalize` validates it, and `Controller.setRecipe` renders it. Item data that is not cached yet is requested once (`C_Item.RequestLoadItemDataByID`) and `ITEM_DATA_LOAD_RESULT` triggers a coalesced refresh.

**Rendering.** `Controller.refresh()` calls `Evaluate.run` with the recipe, a price lookup (`Prices.priceOf`), item facts (`Controller.itemInfo`), the commission, the per-point option, the disenchant lookup, whether the character knows Enchanting, and the number of crafts. `Present.build` turns the result into a model (`banner`, `tiles`, `materials`, plus the older `lines`, cost lines, `verdict` and age) and `Window.render` draws it. The window draws the banner (label, best way to sell, net result with its tone), the three tiles and the Materials panel from the new fields, and reads `lines` only for the `likely` (grey disenchant line) and `perpoint` (Cost per skill point value) entries. `lines` and `verdict` are kept in the model for the pinned list and for tests. The pinned list evaluates each pin the same way, always for one craft.

**Searching prices.** `PinsUI.startSearch` builds the list of items the pins need (`Evaluate.wantedItems`) and runs a `PriceQueue`: one `SendSearchQuery` at a time, advanced by `COMMODITY_SEARCH_RESULTS_UPDATED` or `ITEM_SEARCH_RESULTS_UPDATED` or a timeout. `AHAdapter` reads the listings into `{ unit, qty }` rows; `Controller.recordListings` stores the median.

**Scanning.** `AH.requestSnapshot` calls `ReplicateItems` (once per 15 minutes per account). The client then fires `REPLICATE_ITEM_LIST_UPDATE` hundreds of times for one scan, so the adapter schedules **one** read one second after the first event and ignores the rest until 10 seconds after that read. The read walks the rows in chunks of 1,500 per frame (no freeze) into a `Prices.newAggregator()`; `Controller.onSnapshot` merges the result into the saved prices. A scan started by another addon is handled the same way.

**Clicking a reagent.** `AH.browse` switches the auction house to its Buy view, writes the name in `SearchBar.SearchBox` and calls `SearchBar:StartSearch()`. A hook on `CommoditiesBuyFrame`'s `OnShow` then sets the quantity input (`SetQuantity`) and calls the input's own `OnTextChanged` handler with `userInput = true`, which makes the client recompute the quote, as typing would.

**Clicking the crafted item.** `Controller.onOutputClick` (wired to the AH tile and the window title) does nothing without a recipe; with the AH closed it says `SEARCH_NEED_AH`; an output with `bindType == 1` (bound when picked up, the rule `Evaluate` uses) says `SEARCH_UNSELLABLE` and searches nothing; an item whose name is not loaded says `ITEM_NOT_LOADED`; otherwise it calls `AH.browse(name, itemID, nil)`, the same path as a reagent click with no quantity preset, so the quantity hook is not armed.

**The UI kit.** `UI/Kit.lua` holds the layout rules and the widgets; the main window contains no colour literal. Widgets added for the main window: `Kit.check(parent, text)` (check box with a label), `Kit.input(parent, width, maxLetters)` (themed single-line edit box, 22 px high, text centred; Enter and Escape release the focus, the caller applies the value in `OnEditFocusLost`, as the Crafts box of the window does, and the window does not overwrite the text while the box has focus) and `panel:onHeaderClick(fn)` (the header bar becomes a button, used to fold Materials). Helpers: `Kit.mix(a, b, t)` (blend two colours), `Kit.colorEscape(c)` (a `|cAARRGGBB` escape for a colour), `Kit.plaqueWidth(textWidth, maxWidth)` (title plaque width: at least `PLAQUE_MIN` 210, text plus `PLAQUE_PAD` 44, capped), `Kit.onTheme(paint)` (register a repaint function called by `applyTheme`) and `Kit.naturalWidth(fontString)`. Constants: `PLAQUE_MIN`, `PLAQUE_PAD`, `CLOSE_ROOM` (room kept for the close button), `TILE_PAD`, `FOLDED_H` (height of a folded panel). Search-the-item additions: `Kit.searchIcon(texture)` copies the game's own magnifier onto a texture and returns whether it did: first the icon of the AH search box (`AuctionHouseFrame.SearchBar.SearchBox.searchIcon` or `SearchIcon`, by `GetAtlas`, else `GetTexture` with `GetTexCoord`), then the first atlas of `Kit.SEARCH_ATLASES` (`common-search-magnifyingglass`) that `C_Texture.GetAtlasInfo` knows. It never guesses a file path (a missing file draws a green square) and draws nothing when no source exists, so the icon is optional; everything runs in `pcall`. `tile:onClick(fn)` turns the tile into a button (`tile.hit`) with a hover tint (`tile.tint`, the `rowHover` colour, a texture of the tile frame at sublevel 1 so it sits under the text) and a 12 px icon (`tile.icon`, top right) that `tile:showIcon(show)` reveals; calling `onClick` again replaces the handler. `Kit.forwardDrag(button, window)` lets a button that covers a drag handle start and stop the window move. `Kit.window` takes `opts.onTitleClick`: the plaque gets a button (`frame.titleHit`) that forwards drags, lights the title on hover and calls the handler on a click, plus `frame.titleIcon` and `frame:showTitleIcon(show)`. `Window` shows both icons only while the AH is open and a recipe is displayed. The theme gained the `rowHover` token (hover highlight of a reagent row, drawn above the panel background and below the text). The banner tint comes from the fixed tone colours (gain green, loss red, incomplete amber), not from the theme, so it stays the same through `/cp kitdemo copper`, `steel` and `gold`.

**Known small limits of the main window.** The partial verdict no longer competes with the value: its warning sits on the label line (`banner.warning`) and the main line keeps only the best way to sell. A main line that still does not fit beside the value (a very long item option name in some language) drops to the small font instead of wrapping, and could in theory be cut off next to a very large value.

**The scroll bar.** `Kit.scrollbar(parent, trackH)` returns a bar `SCROLL_W` (8 px) wide that the list owner drives with `:update(total, visible, offset)` and by setting its `onScroll(offset)` callback; it hides itself while everything fits. The geometry is pure and unit tested: `Kit.scrollThumb(total, visible, offset, trackH)` gives the thumb top and height (never shorter than `SCROLL_MIN_THUMB`, 16 px) and `Kit.scrollOffsetAt(total, visible, trackH, y)` turns a pointer position on the track into a row offset. Clicking the track jumps there; dragging the thumb follows the pointer, read each frame with the `GetCursorPosition` global (declared in `.luacheckrc`) and divided by the bar's effective scale. The mouse wheel is handled by the list owners (rows, bar and the empty space of the list). The track is nearly invisible on purpose. Known small limits: grabbing the thumb off-centre makes it jump to centre on the pointer; any mouse button can scroll it; a lost mouse-up (alt-tab while dragging) is not recovered.

**The pinned list and the leveling window** are built on the kit like the main window, with no colour literal. `Window.INNER_WIDTH` (window width minus the two 12 px content margins) is the width of the pinned host, which `Window.relayout` places below the Options panel with a `Kit.GAP` and counts in the window height, so the pinned block sits inside the same margin as the other panels. `PinsUI` shows 6 rows; the name of each is coloured by the recipe difficulty stored with the pin (orange, yellow, green, grey; a pin without a known difficulty uses the plain text colour). That difficulty is refreshed when the profession window updates, so with the profession closed it can lag behind the character's skill. Values keep the gain, loss and muted colours; the selected row is tinted gold and the hovered row uses the `rowHover` token. The status line has room for two lines; a message that wraps to three still overruns the bottom margin by about 14 px (known). `LevelingUI` is a 396 px wide window of fixed height, hidden at creation, with 12 visible rows in a `NEXT POINT` panel (`LEVEL_PANEL`), a row name cut with `...` instead of wrapping, and a repaint on theme switch.

## Price model

- A listing becomes `{ unit, qty }`. A stack row of the scan has its stack price divided by the stack size (`AH.PER_UNIT_REPLICATE = false`, measured).
- `Prices.summarize(listings, n)` sorts by unit price and takes the **median unit price of the n cheapest units** (`n = 5` by default, `settings.medianN`), plus the total volume. Quantities are handled arithmetically, so a listing of one billion units costs the same as one of one unit.
- `Prices.store` and `Prices.merge` write compact rows `{ unit, volume, time }` into `CraftProfitDB.prices`; `Prices.get` returns the unit price and its age, and `nil` for the age when the clock cannot be trusted.
- `DB.prune` removes prices older than 14 days at load.
- Selling uses a commission of 5 % (`settings.cut`, measured). The deposit is ignored: it is refunded when an item sells.

## Leveling list

`Trade.scanKnown` reads every learned recipe of the open profession, grey ones included so the "show grey recipes" option has something to show (`C_TradeSkillUI.GetAllRecipeIDs`, `GetRecipeInfo`, then the usual schematic read), 40 recipes per frame so the client never hitches, and abandons the read if the window closes (a partial list never replaces a good one). `Controller.refreshKnown` runs it on `TRADE_SKILL_LIST_UPDATE`, at most every 5 seconds, and stores the result with `DB.setKnown` in `CraftProfitCharDB.known = { { key, name, updated, recipes } }` (8 professions, 400 recipes each at most). The profession key is the id of `C_TradeSkillUI.GetBaseProfessionInfo()` when it has one, else the profession name. `Leveling.rank` evaluates each stored recipe with the per point figures forced on, hides the ones with a chance of 0 unless asked, and orders them with `Core.rankByPointCost`. Prices come from the last scan, so no search is needed.

A recipe whose cost per point is negative (it pays for itself) ranks first in the cost order, and the more so the rarer the point, because the figure is the money made per point: that order is about money, not speed. The speed order (`Core.rankBySpeed`, setting `levelSort`) puts the highest chance first and breaks ties by cost; the window also shows the crafts per point (`Present.craftsPerPoint`, 1 / chance) so the amount can be read as the loss of one craft times that figure.

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
| `known` | Learned recipes per profession for the leveling list |
| `pins` | Up to 12 normalised recipes `{ recipeID, name, difficulty, outputItemID, outputQty, reagents = { { itemID, qty } } }` |
| `sortMode` | `"net"` or `"point"` |

A market holds `prices[itemID] = { unit, volume, time }`, `snapshotTime` (the last full scan) and `series[itemID]`, the history points `{ t, unit, volume, low, high, n }` of the items of tracked recipes. The market key is the realm id plus the player's faction (`Controller.marketKey`, for example `4613-Horde`), with the normalised realm name as fallback. Forever has rulesets (Normal, PvP, RP, Hardcore) instead of realms; in the beta each ruleset is a "realm" such as *Classic Beta PvP 2* (id 4613), measured with `/cpp ruleset`. `C_GameRules.GetActiveGameMode()` only returns the client's game mode (1, Standard), not the ruleset. A hardcore character gets a `-HC` suffix (`C_GameRules.IsHardcoreActive`). Not measured yet: whether the other rulesets have their own realm id, because they could not be created in the beta; verify with `/cp market` at launch. The neutral auction house is not told apart from the faction one yet. Prices saved before markets existed (`prices` and `snapshotTime` at the top level) are adopted by the first market used.

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

`probe/CraftProfitProbe` is a throwaway addon (not shipped) that prints what the real client returns: `/cpp api | locale | item | deposit | search | replicate | trade | prof | ahui | qty | skin | icon | log | clear`. It mirrors its output, CraftProfit's chat lines and Lua errors into the `CraftProfitProbeLog` saved variable, written on `/reload`, so results can be read from `WTF/Account/<id>/SavedVariables/CraftProfitProbe.lua`. `/cpp skin` reports what the UI kit depends on: which gradient form works (`color`, `rgb` or neither), the real font path, and the pixel widths of the widest amounts. `/cpp icon` reports where the game's search magnifier comes from: the keys of the AH search box that mention an icon, the `GetAtlas`, `GetTexture` and `GetTexCoord` of `searchIcon` / `SearchIcon`, and `C_Texture.GetAtlasInfo` for `common-search-magnifyingglass`, `search-icon` and `auctionhouse-icon-search` (open the AH once first). Use it to settle an API question before coding against it.

## Packaging

The repository contains the addon in `CraftProfit/`, so release tooling must treat that folder as the top level. `CraftProfit/.pkgmeta` configures the BigWigs packager. See [curseforge/submission-checklist.md](curseforge/submission-checklist.md) for the release procedure.

The design history is in [superpowers/](superpowers/): the [design spec](superpowers/specs/2026-10-08-craftprofit-design.md) (in French) and the [implementation plan](superpowers/plans/2026-10-08-craftprofit.md).
