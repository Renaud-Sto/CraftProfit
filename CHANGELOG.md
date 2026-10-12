# Changelog

All notable changes to CraftProfit are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/). The game version tested is given for each release.

## [Unreleased]

### Fixed
- Price history: each tier now has its own cap, so a busy week can no longer erase the daily history. Points or prices dated more than a day in the future no longer freeze an item's series (a point is dropped only when a newer one is recorded, so a clock set back never erases history), and the count of recorded recipes is exact.
- A recipe whose disenchant materials have no data in the tables (for example epic items above item level 60) shows *no data* instead of a permanent *PRICES MISSING* that no search could clear.
- The leveling window reopens where it was dragged during the same session.
- A scan that fails while being read no longer blocks the following scans, a pending quantity for the auction house search is cleared when the auction house closes, and values returned by the game are checked (secret values, failing calls) before use.
- The Spanish materials label is consistent, and the translation test now compares format specifiers in order, so a translation that swaps them is caught.
- Reagent quantities and unit prices have an upper bound, so a corrupt save cannot produce absurd amounts.

### Changed
- Price history retention: every point is kept for 7 days, then one point a day for 60 days (at most 212 points, about 35 KB in the saved file, per item); the weekly tier is gone. Existing history is compacted at load: points between 7 and 60 days old become daily points, weekly points and anything older than 60 days are dropped.
- Up to 30 recipes can be tracked (was 15).
- Prices and history points record whether their volume counts every unit on offer (a full scan, or a search whose results were not cut at 100 rows), for a later estimate of sales per day; nothing visible changes.
- The pinned list under the main window is no longer evaluated while it is hidden.

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
