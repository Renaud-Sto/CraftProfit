# Changelog

All notable changes to CraftProfit are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/). The game version tested is given for each release.

## [Unreleased]

### Added
- Profession window: at the right of each recipe row of the list, what one craft earns or loses (`+12` silver `23` copper coin icons in green, `-2` silver in red, grey at break even, amber when a price is missing), the same figure as the result banner and the pinned list. Only learned recipes CraftProfit has read, with prices, get a tag; it follows scrolling, filters and profession tabs, and updates with the prices. A new *Profession window* panel in the options window turns it off ("Show the profit on each recipe of the list", on by default). Built on the recipe list's own row callback, with no hook on the Blizzard UI.
- Main window: for a tracked recipe with fresh data, a small coloured percentage beside the Materials total and on the AH (NET) tile compares today's materials cost and sale price with their usual level (green good for you, red bad, grey about usual or at a loss), with a tooltip of today's, usual, lowest and highest prices and the measurements behind them. Nothing is shown for untracked, paused or stale recipes.
- History window: the tracked recipes with green or red percentages when their newest prices are better or worse than usual (fresh data only), and for the chosen recipe a chart of the profit, the materials cost, the sale price or one item over 7, 30 or 60 days (a bar per day, a line through the values, the usual price, lighter bars for prices carried from an earlier day), key figures and a typical week. Opened by the **History** button under the pinned list, the options window, or `/cp history`.
- History window rework after the first in-game test: every part in its own panel (tracked recipes, a verdict that says today's price and how it compares with the usual one in a plain sentence, the chart, key figures, typical week); tabs *Materials cost*, *Sale price*, *Profit* ("Result" is gone); item icons grouped as materials, crafted item and disenchant; labelled list columns with a tooltip; a loss reads "loss 9s 40c", never with a minus sign; the chart starts at the first day of data (at least 7 days), shows dates under the plot, a zero line for the profit, the usual price as a dashed line, and a bubble on hover; the list scrolls smoothly (no data work per scroll step).
- Pause or resume tracking, and delete a recipe's history, from the History window (delete asks for a second click within 4 seconds; items another tracked recipe uses keep their history; current prices are never deleted).

### Fixed
- History window: the verdict now starts with what crafting and selling at the auction house earns today (profit in green, loss in red, break even in grey), whatever tab or item is shown, then the shown figure (left out on the Profit tab), then the comparison with the usual level. While the craft is at a loss, a cheaper material or a higher sale is no longer shown as green "good time to buy/sell": it is grey, and the list's percentage columns turn grey with a tooltip that says why. On the Profit tab the comparison is in money and no longer vanishes when the usual result is a loss ("34s less loss than usual (loss 37s)").
- Deleting a tracked recipe's history while another tracked recipe's crafted item is not loaded yet no longer deletes a reagent that this item may disenchant into (an enchanting recipe's Lesser Magic Essence, say).
- History window: a profit is never computed from a sale price carried from an earlier day, so the profit "today", the loss flag and the list's sale arrow no longer come from an old sale price; freshness reads only the recipe's reagents and crafted item (a disenchant material measured today no longer makes old figures look current).
- History window: when nothing of the recipe was measured in the last 24 hours, the verdict keeps its dated figures but the comparison is grey and never says "good time to buy/sell/craft".
- History window: the typical week always reads the last 30 days, so it no longer stays empty on the 7-day period.
- History window: the typical week on the Profit tab shows the gap from the usual profit in money, so a recipe usually at a loss (or at 0) no longer shows an empty week that claims to need two weeks of data; percentages from a tiny usual price are bounded.
- History window: a period with no measurement (newest prices older than 7 days, on the 7-day period) says so and asks to refresh, instead of a blank chart and dashes.
- History window: with too little data the verdict panel is no longer blank ("Not enough measurements yet to judge this recipe.", or "No measurement in the last 7 days." for an empty period, and "Tracking is paused." when paused), and the message names the items that lack data: "Least measured: Copper Bar (8 measurements over 2 days)."
- History window: "1 measurement over 1 day" instead of "1 measurements over 1 days" (French and Spanish too).
- History window: the list's grey-row tooltip says "at a loss or break even", since a craft that earns exactly nothing is greyed too.
- History window: its figures are cached until a price is recorded, a recipe is paused, resumed or deleted, the commission or the day changes, so the window no longer recomputes every tracked recipe at each refresh of the addon.
- Price history: each tier now has its own cap, so a busy week can no longer erase the daily history. Points or prices dated more than a day in the future no longer freeze an item's series (a point is dropped only when a newer one is recorded, so a clock set back never erases history), and the count of recorded recipes is exact.
- A recipe whose disenchant materials have no data in the tables (for example epic items above item level 60) shows *no data* instead of a permanent *PRICES MISSING* that no search could clear.
- The leveling window reopens where it was dragged during the same session.
- A scan that fails while being read no longer blocks the following scans, a pending quantity for the auction house search is cleared when the auction house closes, and values returned by the game are checked (secret values, failing calls) before use.
- The Spanish materials label is consistent, and the translation test now compares format specifiers in order, so a translation that swaps them is caught.
- Reagent quantities and unit prices have an upper bound, so a corrupt save cannot produce absurd amounts.
- The main window no longer reopens by itself after you close it while the profession window is open (a craft, a skill-up or a filter change re-reported the same recipe), and a recipe picked from the pinned list, the pinned window or the leveling window is no longer replaced by the profession window's recipe; picking a new recipe in the profession window still opens it.
- A cost per point counted while a resale price is missing (the crafted item or a disenchant material) shows in the amber of the "prices missing" warning instead of passing for a real cost.
- A history percentage in the main window or the History list disappears by itself once its data are a day old, without waiting for another refresh.

### Changed
- Price history retention: every point is kept for 7 days, then one point a day for 60 days (at most 212 points, about 35 KB in the saved file, per item); the weekly tier is gone. Existing history is compacted at load: points between 7 and 60 days old become daily points, weekly points and anything older than 60 days are dropped.
- Up to 30 recipes can be tracked (was 15).
- `/cp history` opens the History window (`/cp history <n>` on the n-th tracked recipe); the chat list moved to `/cp history list`. `/cp history remove <n>` also cleans the history of the other rulesets and factions.
- The options window's Windows panel has two rows of two buttons (History added).
- Prices and history points record whether their volume counts every unit on offer (a full scan, or a search whose results were not cut at 100 rows), for a later estimate of sales per day; nothing visible changes.
- The pinned list under the main window is no longer evaluated while it is hidden.
- Scrolling the pinned list, the pinned window or the leveling list no longer recalculates every recipe: the rows are redrawn from the last refresh.
- One refresh looks up the market, Enchanting and each item once, and evaluates a recipe shown in two lists once.
- During **Refresh pinned** the values update about once a second instead of after every item.
- `UI/Native.lua` split into `UI/Native.lua` (window, button, check box, input and shared helpers), `UI/NativeCards.lua` (panel, tile, banner and the appearance variants) and `UI/NativeLists.lua` (list row, scroll bar); no behaviour change.
- `Boot.lua` split into `Controller/Facts.lua` (item facts, market, refresh pass, evaluations), `Controller/Main.lua` (selection, refresh, placement, the main window), `Controller/Settings.lua`, `Controller/Leveling.lua`, `Controller/Pins.lua` (pinned recipes, stored prices) and `Controller/History.lua` (price history); `Boot.lua` keeps init, events, slash commands and the self-test; no behaviour change.

### Removed
- The `/cp kitdemo` developer window (it prints the command list like any unknown command).

## [1.0.0] - 2026-10-11

First public release, for the WoW: Forever beta, build 1.60.1, Interface 16001.

### Added
- Price evaluation of the selected recipe, in a window beside the profession window: reagent cost at auction house prices (median of the 5 cheapest units), with a foldable reagent detail; auction house value net of the 5 % commission, vendor value and expected disenchant value, with the most probable disenchant outcome; the best way to sell and the net result in a coloured banner; the age of the prices. An unknown price shows `?`, never zero.
- Cost (or gain) per skill point, optional, from the recipe colour, with the chance used shown.
- Crafts multiplier, 1 to 9999, for the selected recipe.
- Pinned recipes: 20 per character by default, sorted by profit or by cost per point; their difficulty colour follows the profession window. Shown under the main window at the auction house, and anywhere in the pinned recipes window (`/cp pins`), with the last known prices and an "x" to unpin.
- Auction house tools: **Refresh recipe** (the recipe on screen, a few seconds), **Refresh pinned** (every pinned recipe, about a minute for 20) and **Scan AH** (the whole auction house, once per 15 minutes; scans started by other addons are used too). A missed price is asked a second time before the summary, and the status says what was updated, what has no listing and what did not answer. A crafted item bound on pickup is never searched.
- Click a reagent to search it at the auction house with the quantity filled in, or the AH tile or recipe title to search the crafted item. CraftProfit never buys anything.
- Leveling window (`/cp level`): every known recipe of a profession ranked by the cost of the next skill point, or by speed, with the crafts each point takes; grey recipes hidden unless asked. Stored per character, so it works at the auction house with the profession window closed.
- Options window (`/cp options`): look of every window (header strip and tile card), pinned recipes limit (12, 20, 30 or 40), minimap button, shortcuts to the other windows and the list of every command.
- Minimap button (left click options, right click pinned recipes window, drag to move) and addon compartment entry.
- Price history, recording only: *Track history* keeps the prices of up to 15 recipes after every scan and search (all points for 14 days, then daily, then weekly up to a year). `/cp history` lists them, `/cp history remove <n>` deletes one.
- Prices kept per market: ruleset (the game "realm" in the beta) and faction, hardcore apart. `/cp market` shows the market in use.
- Every window uses the game's own frames, buttons, fonts, scroll bars and coin icons. A window that was never dragged opens beside the others, never on top of them; dragged windows reopen where they were left.
- English, French and Spanish, following the game language, recipe and profession names included; `/cp locale` forces one.
- Slash commands `/cp` and `/craftprofit`: `show`, `hide`, `reset`, `options`, `pins`, `level`, `minimap`, `scan`, `history`, `market`, `locale`, `selftest`.
- Documentation in English and French, offline test suite, continuous integration and an in-game probe addon for developers (not shipped).

### Known limitations
- Disenchant tables are Classic data, tagged *beta*, with no table for epic items above item level 60.
- Skill-up chances are estimates by recipe colour (100 / 75 / 25 / 0 %).
- Known recipes only.
- Price history is recorded but there is no history view or graph yet.
- No sales speed: the game gives no sales history.

[Unreleased]: https://github.com/Renaud-Sto/CraftProfit/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Renaud-Sto/CraftProfit/releases/tag/v1.0.0
