# Changelog

All notable changes to CraftProfit are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/). The game version tested is given for each release.

## [Unreleased]

## [1.1.0] - 2026-10-14

### Added
- **Price history window.** The History button (under the pinned list, in the options window, or `/cp history`) opens a window with the tracked recipes (up to 30) and, for the chosen one, a verdict that says in plain words what crafting and selling at the auction house earns today and how today's prices compare with the usual ones, a chart over 7, 30 or 60 days (Materials cost, Sale price, Profit, or one item: a bar per day, a line through the values, the usual price dashed, a zero line for the profit, a bubble on hover), key figures with their dates, and a typical week. Item icons are grouped as materials, crafted item and disenchant. With too little data the window says how many measurements it has, why that is not enough and which items lack them. Pause tracking or delete a recipe's history from there (delete asks for a second click; items another tracked recipe uses keep their history).
- **Profit on every recipe of the profession window.** At the right of each recipe row, what one craft earns or loses, with the gold, silver and copper coin icons (green gain, red loss, grey at break even, amber when a price is missing): the same figure as the result banner and the pinned list. Only learned recipes CraftProfit has read, with prices, get one; it follows scrolling, filters and profession tabs, and a long recipe name is cut before it. A *Profession window* panel in the options window turns it off. Built on the recipe list's own row callback, with no hook on the Blizzard UI.
- **History percentages in the main window.** For a tracked recipe with fresh data, a small coloured percentage beside the Materials total and on the AH (NET) tile compares today's materials cost and sale price with their usual level (green good for you, red bad, grey about usual or when the craft is at a loss), with a tooltip of the figures behind it. The History list shows the same percentages. Nothing is shown for untracked, paused or stale (over 24 hours) recipes.

### Fixed
- A recipe whose disenchant materials have no data in the tables (for example epic items above item level 60) shows *no data* instead of a permanent *PRICES MISSING* that no search could clear.
- The main window no longer reopens by itself after you close it while the profession window is open (a craft, a skill-up or a filter change re-reported the same recipe), and a recipe picked from the pinned list, the pinned window or the leveling window is no longer replaced by the profession window's recipe; picking a new recipe in the profession window still opens it.
- The leveling window reopens where it was dragged during the same session.
- A cost per point counted while a resale price is missing (the crafted item or a disenchant material) shows in the amber of the "prices missing" warning instead of passing for a real cost.
- Price history: each retention tier has its own cap, so a busy week can no longer erase the daily history. Points or prices dated more than a day in the future no longer freeze an item's series, and the count of recorded recipes is exact.
- A scan that fails while being read no longer blocks the following scans, a pending quantity for the auction house search is cleared when the auction house closes, and values returned by the game are checked (secret values, failing calls) before use.
- The Spanish materials label is consistent, and reagent quantities and unit prices have an upper bound, so a corrupt save cannot produce absurd amounts.

### Changed
- Price history retention: every point is kept for 7 days, then one point a day for 60 days (at most 212 points, about 35 KB in the saved file, per item); the weekly tier is gone. Existing history is compacted at load: points between 7 and 60 days old become daily points, weekly points and anything older than 60 days are dropped.
- Up to 30 recipes can be tracked (was 15).
- `/cp history` opens the History window (`/cp history <n>` on the n-th tracked recipe); the chat list moved to `/cp history list`. `/cp history remove <n>` also cleans the history of the other rulesets and factions.
- The options window's Windows panel has two rows of two buttons (History added), and a new Profession window panel.
- Prices and history points record whether their volume counts every unit on offer, for a later estimate of sales per day; nothing visible changes.
- Faster: scrolling the pinned list, the pinned window or the leveling list redraws the rows without recalculating every recipe; the hidden pinned list is not evaluated; one refresh looks up the market, Enchanting and each item once; during **Refresh pinned** the values update about once a second instead of after every item.
- Internal: `UI/Native.lua` and `Boot.lua` split into smaller files (`UI/NativeCards.lua`, `UI/NativeLists.lua`, `Controller/*.lua`); no behaviour change.

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

[Unreleased]: https://github.com/Renaud-Sto/CraftProfit/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/Renaud-Sto/CraftProfit/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/Renaud-Sto/CraftProfit/releases/tag/v1.0.0
