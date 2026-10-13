# CurseForge project page

Text to paste into the CurseForge project, in the order CurseForge shows it. CurseForge requires **English** for the name, summary and description; translations go *after* the English text.

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
- **Leveling window**: every recipe you know in a profession, ranked by the cost of the next skill point (or by speed).
- **Pinned recipes** (20 per character by default; 12, 20, 30 or 40 in the options window), sorted by profit or by cost per point, to decide what to craft next (with many pinned, **Scan AH** is usually faster than **Refresh pinned**); at the auction house and anywhere in their own window, with the last known prices.
- **Auction house tools**: *Refresh recipe* prices the recipe on screen in a few seconds; *Refresh pinned* prices every pinned recipe; *Scan AH* reads the whole auction house; click a reagent to search it with the quantity already filled in, or the crafted item to see how many are for sale. CraftProfit never buys anything for you.
- **Price history**: tick *Track history* on up to 30 recipes to keep their prices scan after scan (every point for 7 days, one a day for 60 days). The **History** window charts them over 7, 30 or 60 days: materials cost, sale price or profit, a bar per day, the usual price and a typical week, with a plain sentence saying whether today is a good time to buy, sell or craft.
- **Options window and minimap button**: pick the look of the windows and the pinned recipes limit, open the other windows, see every command.
- **Standalone**: no Auctionator or other addon needed.
- **English, French and Spanish**, following the game language (saved recipe names follow it too).

### Usage

1. Open a profession window and select a recipe you know.
2. Go to the auction house and press **Refresh recipe** (the recipe on screen), **Refresh pinned** (pinned recipes) or **Scan AH** (everything, one scan per 15 minutes allowed by the game).
3. Pin recipes with **Pin**, tick *Cost per skill point* if you are levelling, and compare from the list.

### Slash commands

`/cp` or `/craftprofit`: `show`, `hide`, `reset`, `options`, `pins`, `level`, `minimap`, `scan`, `history`, `market`, `locale <code>`, `selftest`. The minimap button opens the options (left click) and the pinned recipes (right click).

### Compatibility

Made for **World of Warcraft: Forever** (beta build 1.60.1, Interface 16001). Not for Retail or Classic Era.

### Good to know

- Prices are snapshots from your last search or scan; the window shows their age.
- Disenchant values come from the Classic tables and are marked *beta* until verified in Forever. Epic items above item level 60 have no table yet.
- Skill-up chances are estimates based on recipe colour.
- CraftProfit works with known recipes only and has no sales history: the game does not provide it.

### FAQ

**The window does not appear.** Select a recipe you know in the profession window, or type `/cp show`.
**Prices show `?`.** Press *Refresh recipe*, *Refresh pinned* or *Scan AH* at the auction house.
**The scan never finishes.** The game allows one full scan per 15 minutes per account, including those of other addons. Wait and try once.
**Does it buy for me?** No. It searches; you press Buy.

### Links and support

- Source code and issue tracker: https://github.com/Renaud-Sto/CraftProfit
- User guide: https://github.com/Renaud-Sto/CraftProfit/blob/main/docs/user-guide.md
- Guide d'utilisation en français : https://github.com/Renaud-Sto/CraftProfit/blob/main/docs/user-guide.fr.md

*CraftProfit is a fan-made addon, not affiliated with or endorsed by Blizzard Entertainment.*

## Gallery

The screenshots are in [docs/screenshots](../screenshots/README.md) (English client, real game images): `01-main-window.png`, `02-pinned-window.png`, `03-leveling.png`, `04-options.png`, `05-all-windows.png` and `06-main-window-loss.png`. Upload them in the CurseForge gallery with these titles: the main window at the auction house, the pinned recipes window, the leveling window, the options window, all windows together, and a recipe that loses money (best option: disenchant).

## Project icon

[icon.png](icon.png): 512 × 512 px, square PNG, original artwork (CurseForge asks for 400 × 400 px minimum, not a solid colour, not a Blizzard asset). See the [submission checklist](submission-checklist.md).
