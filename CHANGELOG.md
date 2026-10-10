# Changelog

All notable changes to CraftProfit are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/). The game version tested is given for each release.

## [Unreleased]

### Added
- Native UI foundations and `/cp kitdemo` variants (developer tool): widgets built on the game's own frame templates, shown by `/cp kitdemo [header [tile]]` with a choice of header strip and tile background; the previous themed demo moved to `/cp kitdemo old [theme]`.
- Choose the colour theme: `/cp theme` lists Gold, Copper and Steel blue and `/cp theme copper` switches at once, with no `/reload`, for the pinned list, the leveling window and the scroll bars. The choice is saved for the account. Colours with a meaning (gain, loss, recipe difficulty, banner tint) do not change.
- Click the AH (NET) tile or the recipe title of the main window to search the crafted item at the auction house, to see how many are for sale next to its price. A small magnifier icon marks both while the auction house is open. With the auction house closed it says to open it, and an item bound when picked up says it cannot be sold there.
- Developer groundwork for the UI rework: colour themes (gold, copper, steel blue) and a shared widget kit, with a `/cp kitdemo` window.
- Leveling window (`/cp level`, or the Leveling button under the pinned list): every learned recipe of a profession (grey ones hidden unless asked) ranked by the cost of a skill point from the last scan, stored per character so it works at the auction house. Grey recipes are hidden unless asked.
- The leveling window shows the crafts per point and can be sorted by cost per point or by speed (likeliest point first).
- Scroll bars on the pinned list (6 rows visible) and on the leveling list (12 rows visible): mouse wheel, drag the bar or click it; hidden while everything fits.
- `/cp market` shows the market the prices are saved under.
- Prices are kept per ruleset (the game "realm" in the beta) and faction. Prices saved by earlier builds are adopted by the first market used.
- Price history: the *Track history* box records the prices of up to 15 recipes after every scan and price search (retention: all points for 14 days, then daily, then weekly averages up to a year); `/cp history` lists and removes tracked recipes. Recording only, the graphs are planned.
- Project documentation: README (English and French), user guide (English and French), technical documentation, contributing guide, CurseForge page text and submission checklist, issue and pull request templates, continuous integration.

### Changed
- The pinned list and the leveling window now use the game's own frames, rows and scroll bar, like the main window. The colour themes (`/cp theme`) no longer change any window.
- Amounts now show the game's gold, silver and copper icons (the old text letters were a fallback that was always taken on Forever).
- The main window now uses the game's own frame, panels, buttons and fonts. The header colour swatch is gone from it.
- Scroll bars: grabbing the thumb off-centre no longer makes it jump, only the left mouse button scrolls, and a drag stops when the button is no longer down (for example after alt-tab). The pinned list, the leveling list and the Materials rows share one row widget, and the window title is measured only when it changes.
- The pinned list and the leveling window have the new look: a Pinned recipes panel with the sort button in its header, a Next point panel, themed buttons, and both follow the colour themes.
- Pinned recipe names are coloured by difficulty (orange, yellow, green, grey), as in the profession window.
- The main window has a new look: a result banner with the best way to sell and the net result, three tiles for the auction house, vendor and disenchant values, and separate Materials and Options panels. Its functions are unchanged; what you see differs: the best option is outlined on its tile instead of marked with ">", the per-point result is a coloured value beside its option instead of a "Gain per point" line, and the banner shows the verdict on one line.
- The best tile of the main window is outlined in the game's gold (2 px), so it stands out from the other tiles.
- The partial-result warning ("PRICES MISSING") now sits in amber on the banner label line so it is never cut off; the French and Spanish "cost per point" option labels are shorter.

### Fixed
- Show grey recipes in the leveling window now works: grey recipes are stored when the profession window is read (open it once after updating).

## [0.1.0] - not yet released

First version, developed against the WoW: Forever beta (build 1.60.1, Interface 16001).

### Added
- Floating window next to the profession window: reagent cost with a foldable detail, auction house net value (5 % commission), vendor value, expected disenchant value, best option and net result, age of the prices.
- Optional cost (or gain) per skill point, from the recipe colour, with the chance used shown.
- Crafts multiplier (1 to 9999) for the selected recipe.
- Pinned recipes (12 per character), sortable by profit or by cost per point; pinned difficulties follow the recipe's current colour.
- Auction house: **Search prices** for the pinned recipes, **Scan AH** for a full scan (also picks up scans started by other addons), click a reagent to search it with the quantity filled in.
- Most probable disenchant outcome shown under the expected value; bind-on-pickup items only when the character knows Enchanting.
- English, French and Spanish interface, following the game language; `/cp locale` to force one.
- Slash commands `/cp` and `/craftprofit`: `show`, `hide`, `reset`, `scan`, `locale`, `selftest`.
- In-game probe addon (`probe/CraftProfitProbe`, not shipped) and an offline test suite.

### Known limitations
- Disenchant tables are Classic data, tagged *beta*, with no table for epic items above item level 60.
- Skill-up chances are estimates by recipe colour (100 / 75 / 25 / 0 %).
- Known recipes only; no sales history.

[Unreleased]: https://github.com/Renaud-Sto/CraftProfit/compare/main...HEAD
