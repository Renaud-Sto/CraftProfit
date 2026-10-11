# Changelog

All notable changes to CraftProfit are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/). The game version tested is given for each release.

## [Unreleased]

### Added
- Pinned recipes limit in the options window: 12, 20, 30 or 40 recipes per character (account-wide setting), chosen with four buttons in the new **Pinned recipes** panel. A note under them says that a higher limit makes **Search prices** take longer, because the auction house is searched one item at a time. The change applies at once. When the list is full, pinning says "Pinned recipes limit reached (n). Raise it in /cp options." Lowering the limit never deletes a pin: the ones over the limit stay, and new pins are refused until the list is under the limit again.

### Changed
- The default pinned recipes limit is now 20 per character (it was 12 in 1.0.0). Saves from 1.0.0 load unchanged.

### Fixed
- Recipe and profession names follow the game language after a language change: pinned recipes, the leveling window, the main window title and `/cp history` no longer keep the names of the language they were saved in. Switching profession with the tabs of the open profession window now refreshes the leveling list and the pinned difficulties too.

## [1.0.0] - 2026-10-10

First public release, for the WoW: Forever beta, build 1.60.1, Interface 16001.

### Added
- Floating window next to the profession window: reagent cost with a foldable detail, auction house net value (5 % commission), vendor value, expected disenchant value, best option and net result, age of the prices.
- Optional cost (or gain) per skill point, from the recipe colour, with the chance used shown.
- Crafts multiplier (1 to 9999) for the selected recipe.
- Pinned recipes (12 per character), sortable by profit or by cost per point; pinned difficulties follow the recipe's current colour.
- Auction house: **Search prices** for the pinned recipes, **Scan AH** for a full scan (also picks up scans started by other addons), click a reagent to search it with the quantity filled in.
- Most probable disenchant outcome shown under the expected value; bind-on-pickup items only when the character knows Enchanting.
- English, French and Spanish interface, following the game language; `/cp locale` to force one.
- Slash commands `/cp` and `/craftprofit`: `show`, `hide`, `reset`, `scan`, `locale`, `selftest`, `level`, `pins`, `options`, `minimap`, `history`, `market`.
- In-game probe addon (`probe/CraftProfitProbe`, not shipped) and an offline test suite.
- Leveling window (`/cp level`, or the Leveling button under the pinned list): every learned recipe of a profession ranked by the cost of the next skill point from the last scan, with the crafts each point takes on average. Sort by cost per point or by speed (likeliest point first); grey recipes hidden unless asked. The recipes are stored per character, so the window works at the auction house with the profession window closed.
- Pinned recipes window (`/cp pins`, a right click on the minimap button or the addon compartment entry, or the button in the options window): the pinned recipes with their last known prices, anywhere, without the auction house or the profession window. It shows how old the oldest price used is, shares the sort (profit or cost per point) with the list at the auction house, has an "x" on each row to unpin it, and a click on a row opens the main window on that recipe. It never searches prices. Escape closes it.
- Options window (`/cp options`, a left click on the minimap button or the addon compartment entry): choose the look of every window at once, the header strip (Carved wood, Shade, Streaks) and the tile card (Loot card, Inset), default Shade and Inset, applied immediately and saved for the account. It also shows or hides the minimap button, opens the main, leveling and pinned recipes windows, and lists the minimap clicks and every command. No label is cut in English, French or Spanish. Escape closes it.
- Minimap button (shown by default): left click opens the options, right click opens or closes the pinned recipes window, a left drag moves it around the minimap (round or square), and its place is saved. `/cp minimap` or the options window hides it or brings it back.
- Addon compartment entry (when the client shows the addon list button): left click options, right click pinned recipes window.
- Click the AH (NET) tile or the recipe title of the main window to search the crafted item at the auction house and see how many are for sale. A small magnifier marks both while the auction house is open. With the auction house closed it says to open it; an item bound when picked up says it cannot be sold there.
- Price history: the *Track history* box records the prices of up to 15 recipes after every scan and price search (all points for 14 days, then daily, then weekly averages up to a year). `/cp history` lists the tracked recipes and `/cp history remove <n>` deletes one. Recording only: graphs are planned.
- Prices are kept per market: ruleset (the game "realm" in the beta) and faction, hardcore apart. `/cp market` shows the market in use. Prices saved by earlier builds are adopted by the first market used.
- Scroll bars on the pinned list (6 rows visible) and the leveling and pinned recipes windows (12 rows visible): mouse wheel, drag the bar or click it; hidden while everything fits.
- Window placement: a window that was never dragged opens just right of the rightmost CraftProfit window on screen instead of on top of it; a dragged window always reopens where it was left. The window opened or clicked last comes to the front, above the game's HUD panels.
- Every window uses the game's own frames, panels, buttons, check boxes, fonts and scroll bars. The main window shows a result banner (best way to sell and net result), three tiles for the auction house, vendor and disenchant values (the best one outlined in gold), and separate Materials and Options panels. When some prices are missing, the "PRICES MISSING" warning sits on the banner's label line so it is never cut off.
- Amounts show the game's gold, silver and copper icons. From 100 gold up, copper is dropped (rounded to the nearest silver) so a large amount fits its tile.
- Project documentation: README (English and French), user guide (English and French), technical documentation, contributing guide, CurseForge page text and submission checklist, issue and pull request templates, continuous integration.

### Known limitations
- Disenchant tables are Classic data, tagged *beta*, with no table for epic items above item level 60.
- Skill-up chances are estimates by recipe colour (100 / 75 / 25 / 0 %).
- Known recipes only. Prices are recorded for up to 15 tracked recipes, but there is no history view or graph yet.

[Unreleased]: https://github.com/Renaud-Sto/CraftProfit/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Renaud-Sto/CraftProfit/releases/tag/v1.0.0
