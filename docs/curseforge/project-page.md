# CurseForge project page (first draft)

Text to paste into the CurseForge project, in the order CurseForge shows it. CurseForge requires **English** for the name, summary and description; translations go *after* the English text. Replace the bracketed items before publishing.

## Name

CraftProfit

## Summary (one line)

See what a profession recipe really costs at the auction house, and whether to sell, vendor or disenchant the result.

Alternatives, if the first is too long: *Compare a recipe's cost with what the crafted item sells, vendors or disenchants for.* / *Level your professions at the smallest loss, or find the profitable crafts.*

## Categories and tags

- Main category: **Professions**
- Additional: **Auction & Economy** (the two categories used by comparable addons)
- Game flavour and version: **Forever**, game version **1.60.1** (check the current value in the upload form)

## Description

> Copy from here down. CurseForge accepts Markdown or HTML in the editor.

**CraftProfit tells you what a profession recipe really costs at the auction house, and what to do with the result.**

Select a recipe you know and a small window appears next to your profession window. It adds up the reagents at auction house prices, then compares the three ways to get rid of the crafted item: **auction house** (after the 5 % commission), **vendor** and **disenchant**. It marks the best one and shows the net result, so you can level a profession at the smallest loss, or look for a profit.

### Features

- **Recipe cost** from live auction house prices, with the reagent detail one click away.
- **Auction house, vendor and disenchant compared**, best option highlighted, net result of the craft.
- **Cost per skill point** (optional): what each point really costs, from the recipe colour; shown as a gain when the crafts pay for themselves.
- **Several crafts at once**: multiply a recipe by 1 to 9999.
- **Pinned recipes** (12 per character), sorted by profit or by cost per point, to decide what to craft next.
- **Auction house tools**: *Search prices* prices every pinned recipe; *Scan AH* reads the whole auction house; click a reagent to search it with the quantity already filled in. CraftProfit never buys anything for you.
- **Standalone**: no Auctionator or other addon needed.
- **English, French and Spanish**, following the game language.

### Usage

1. Open a profession window and select a recipe you know.
2. Go to the auction house and press **Search prices** (pinned recipes) or **Scan AH** (everything, one scan per 15 minutes allowed by the game).
3. Pin recipes with **Pin**, tick *Cost per skill point* if you are levelling, and compare from the list.

### Slash commands

`/cp` or `/craftprofit`: `show`, `hide`, `reset`, `scan`, `history`, `market`, `level`, `locale <code>`, `theme [name]`, `selftest`.

### Compatibility

Made for **World of Warcraft: Forever** (beta build 1.60.1, Interface 16001). Not for Retail or Classic Era.

### Good to know

- Prices are snapshots from your last search or scan; the window shows their age.
- Disenchant values come from the Classic tables and are marked *beta* until verified in Forever. Epic items above item level 60 have no table yet.
- Skill-up chances are estimates based on recipe colour.
- CraftProfit works with known recipes only and has no sales history: the game does not provide it.

### FAQ

**The window does not appear.** Select a recipe you know in the profession window, or type `/cp show`.
**Prices show `?`.** Press *Search prices* or *Scan AH* at the auction house.
**The scan never finishes.** The game allows one full scan per 15 minutes per account, including those of other addons. Wait and try once.
**Does it buy for me?** No. It searches; you press Buy.

### Links and support

- Source code and issue tracker: https://github.com/Renaud-Sto/CraftProfit
- User guide: https://github.com/Renaud-Sto/CraftProfit/blob/main/docs/user-guide.md
- Guide d'utilisation en français : https://github.com/Renaud-Sto/CraftProfit/blob/main/docs/user-guide.fr.md

*CraftProfit is a fan-made addon, not affiliated with or endorsed by Blizzard Entertainment.*

## Gallery (needed before submission)

Prepare 3 to 5 screenshots of the real client, after the interface rework:

1. A recipe selected in the profession window with the CraftProfit window beside it.
2. The material detail unfolded and the best option highlighted.
3. The pinned list at the auction house, sorted by cost per point.
4. Clicking a reagent: the auction house search with the quantity filled in.
5. The same window in French or Spanish.

Avoid other players' names in the shot (crop or choose a quiet spot).

## Project icon

400 × 400 px minimum, square, PNG (avoid WebP), original artwork, not a solid colour and not a Blizzard asset. See the [submission checklist](submission-checklist.md).
