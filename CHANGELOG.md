# Changelog

All notable changes to CraftProfit are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/). The game version tested is given for each release.

## [Unreleased]

### Added
- Prices are kept per ruleset (the game "realm" in the beta) and faction. Prices saved by earlier builds are adopted by the first market used.
- Price history: the *Track history* box records the prices of up to 15 recipes after every scan and price search (retention: all points for 14 days, then daily, then weekly averages up to a year); `/cp history` lists and removes tracked recipes. Recording only, the graphs are planned.
- Project documentation: README (English and French), user guide (English and French), technical documentation, contributing guide, CurseForge page text and submission checklist, issue and pull request templates, continuous integration.

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
