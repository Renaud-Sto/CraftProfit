# CraftProfit user guide

*[Version française](user-guide.fr.md)* · [Back to the README](../README.md)

CraftProfit tells you what a profession recipe really costs at the auction house and what to do with the result. This guide explains every part of the window, how each number is computed, and what the addon cannot know.

Contents: [The window](#the-window) · [At the auction house](#at-the-auction-house) · [How the numbers are computed](#how-the-numbers-are-computed) · [Options and commands](#options-and-commands) · [Languages](#languages) · [Known limitations](#known-limitations) · [FAQ and troubleshooting](#faq-and-troubleshooting)

## The window

Open a profession window and select a recipe you know. A small window appears to the right of the profession window and follows your selection. You can drag it anywhere; the position is remembered (`/cp reset` puts it back). It closes with the profession window, and with the auction house window when you opened it from there, so it never clutters the screen.

From top to bottom:

| Part | Meaning |
| --- | --- |
| **Result** banner | The best way to sell the item and the net result of the craft (best resale minus materials) in large type. Green for a gain, red for a loss, amber when the result is incomplete (a price is missing). |
| **Three tiles** | **AH (NET)**: the price the crafted item would fetch at the auction house, after the 5 % commission. **VENDOR**: what a vendor pays for the item. **DISENCH.** with a *beta* tag: the *expected* value of disenchanting the item, net of the auction house commission on the materials (see [Disenchanting](#disenchanting)). The best one is outlined in gold. A tile reads `n/a` when that way is not possible (bound when picked up, cannot be vendored or disenchanted) and `?` when it is possible but a price is unknown. |
| *grey line* | Under the tiles: the most probable disenchant outcome, for example `75%: 1-2x Soul Dust = 7s 30c`. Only shown when the disenchant has several possible results. |
| **Materials** panel | The cost of all reagents at auction house prices. Click the header to fold or unfold the detail (`-` unfolded, `+` folded); the choice is saved. Click a reagent to search it at the auction house (see [Searching a reagent](#searching-a-reagent)). |
| **Prices: 5m ago** | How old the oldest price used is. It turns orange when prices are more than an hour old. |
| **Options** panel | **Crafts**, **Track history**, **Cost per skill point** with its value on the right (see [Cost per skill point](#cost-per-skill-point)), and the **Pin** / **Unpin** button. |

A price that is not known is shown as `?`, never as zero. The banner has three special cases:

- *No way to sell this item*: none of the three tiles can be used (all `n/a`).
- *Incomplete: prices missing* (amber, no value): a price needed for the result is missing, so no net result can be given rather than a flattering number.
- *Best known: Auction house* (with the net result, in amber): some prices are known, so a best way to sell and its net result are shown. The warning sits in amber on the label line above, "RESULT · PRICES MISSING", so the figure may change once the missing prices are known and the warning is never cut off.

### Crafts

The **Crafts** box multiplies the selected recipe by a number of crafts (1 to 9999): reagent quantities, the materials total, every resale value and the net result in the result banner. The cost or gain **per point** and the grey disenchant line stay per point and per disenchant. The pinned list always shows one craft, and selecting another recipe puts the box back to 1.

For large quantities the total is an estimate: the price of a reagent is the median of the cheapest listings, but buying 100 units goes through more expensive listings. The real price appears in the auction house when you search.

### Track history

The **Track history** box (next to Crafts) makes CraftProfit keep the prices of this recipe's reagents and result over time. Up to 15 recipes can be tracked, independently of the pinned list. A point is recorded after every scan and every price search that touches one of the recipe's items, as long as all the needed prices are known. Unticking the box pauses recording and keeps what was recorded. `/cp history` lists the tracked recipes and `/cp history remove <n>` deletes one with its history. Prices are kept per ruleset (the game "realm" in the beta) and faction, so the history of one market never mixes with another. A view of the history (graphs, "cheaper than usual") is planned; for now the data is only being gathered.

### Pin button

**Pin** keeps the recipe in your pinned list (up to 12 per character), usable even with the profession window closed. **Unpin** removes it.

## At the auction house

When the auction house opens, the window shows the **Pinned recipes** list under the recipe, with two buttons.

- **Search prices** prices every reagent and every output of the pinned recipes, one item at a time, with a progress count. Prices are saved with their date. If you close the auction house meanwhile, the search is cancelled and the prices already received are kept.
- **Scan AH** reads the entire auction house in one go (the game allows one full scan per 15 minutes per account). It prices thousands of items, so every recipe can be evaluated afterwards. If another addon starts a scan, CraftProfit uses its result without a second request. If the server does not answer, the status says so: the 15 minute cooldown is probably running.

### Sorting the pinned list

The button at the top right of the list switches between:

- **Sort: profit**: the most profitable craft first (the least lossy first when all lose money); recipes without a price last.
- **Sort: cost/point**: the cheapest skill point first. A recipe whose crafts pay for themselves comes first (green `+…/pt`), then costs in red (`…/pt`), then grey recipes (`n/a`, no point possible), then unpriced ones (`?`). This mode switches the cost per point option on, and unticking that option brings the sort back to profit.

Click a recipe in the list to show it in the window above.

### The leveling window

**Leveling** (button under the pinned list, or `/cp level`) opens a separate, movable window with **every recipe you know** in a profession, cheapest skill point first, so you can see at a glance what to craft next to level at the smallest loss.

- Each row shows the recipe (coloured by difficulty), then the cost per point, with the same wording as the pinned list: `21g 29s/pt` in red, `+9s 33c/pt` in green when the crafts pay for themselves, `?` when a price is missing (those stay at the bottom).
- The small grey figure before the amount, such as `x4`, is how many crafts a point takes on average (100 % = `x1`, 75 % = `x1.3`, 25 % = `x4`). The amount is the loss (or gain) of one craft times that figure, which makes it easy to read: a craft that loses 5s and needs 4 crafts per point shows about `20s/pt`.
- The button at the top right switches the order: **Sort: cost/point** (cheapest point first, the default) or **Sort: speed** (the likeliest point first, the fewest crafts; among equal chances the cheapest first). Use speed when you need the last points quickly, cost when you want to spend the least. The choice is saved.
- **Grey recipes** cannot give a skill point any more, so they are hidden by default; tick *Show grey recipes* to see them.
- The profession button cycles through the professions CraftProfit has read for this character. The list is saved when you open a profession window, so it is available at the auction house with the profession window closed. It is read again whenever the profession window updates, so the colours follow your skill.
- The age of the prices (the last scan) is shown at the top: the whole list depends on it, so run **Scan AH** first.
- Click a row to show that recipe in the main window (crafts multiplier, material detail, click a reagent to search it).

The ranking is as reliable as the skill-up chances behind it, which are still estimates by recipe colour. It ranks the *next point*; it is not a full plan from your current skill to the maximum. A recipe whose output is not an item (an enchantment, for example) is left out.

### Searching a reagent

With the material detail unfolded, click a reagent line, for example `20x Bronze Bar`. CraftProfit opens the auction house *Buy* view, types the item name in the search box and starts the search. When you open the item's buy view, the quantity is already set to 20 (multiplied by the number of crafts). You still choose the listing and press **Buy** yourself: CraftProfit never buys anything.

## How the numbers are computed

### Prices

A price comes from auction house listings. The price kept for an item is the **median unit price of the five cheapest units**. One absurdly cheap listing cannot drag the price down the way a plain minimum would, and quantities are handled properly (a listing of 20 units counts 20 times).

Two sources feed it: the targeted search of **Search prices** and the full **Scan AH**. The most recent write wins; each price keeps its date. Prices older than two weeks are discarded.

### Auction house net

`price × (1 − 0.05)`. The 5 % commission was measured in the beta from a sale mail (20 Wool Cloth at 1 silver each: 1 silver commission, deposit refunded). The deposit is refunded when the item sells and is not counted.

### Disenchanting

Expected value = the sum over the possible results of *chance × average quantity × price*, net of the 5 % commission. It is shown for any item that can be disenchanted, **whether or not you have Enchanting**: an item that is bound when equipped can be disenchanted by another player or another character of yours.

The exception is an item that is **bound when picked up**: it cannot change hands, so the tile only shows a value (`n/a` otherwise) if your character knows Enchanting.

The tables come from Classic and are not yet checked in Forever, hence the *beta* tag. Epic items above item level 60 have no table yet and show `?`. Disenchanting is a gamble: over many items the average is reached, for one item the grey line tells you the most likely result.

### Cost per skill point

`(materials − value of the best exit) ÷ chance of gaining a point`

A craft that loses 16s 50c with a 25 % chance of a point costs 66s per point on average. If the crafts pay for themselves, the value beside the box turns green and starts with `+` (a gain per point); a cost is shown in red, with the percentage used and *estimate*.

The chance of a point depends on the colour of the recipe and is an **estimate**, not a measured value: orange 100 %, yellow 75 %, green 25 %, grey 0 % (shown `n/a`). The percentage used is displayed beside the check box, next to the value. The colour of pinned recipes is refreshed whenever the profession window updates, so it follows your skill.

## Options and commands

| Setting | Where | Default |
| --- | --- | --- |
| Cost per skill point | Check box in the Options panel | Off |
| Material detail folded or unfolded | Click the Materials header | Unfolded |
| Window position | Drag it; `/cp reset` to undo | Beside the profession or auction house window |
| Sort of the pinned list | Button above the list | Profit |

Commands: `/cp` (or `/craftprofit`) with `show`, `hide`, `reset`, `scan`, `history`, `market`, `level`, `locale <code>` and `selftest`. See the [README](../README.md#commands).

## Languages

The window follows the game language: English, French and Spanish (Latin American Spanish uses the Spanish texts). Any other language falls back to English. `/cp locale frFR` forces a language for testing and `/cp locale` returns to the game language. Item and recipe names always come from the game, in your client language.

## Known limitations

- **Known recipes only.** Recipes you have not learned are not shown.
- **Prices are snapshots.** They are as fresh as your last search or scan; the window shows their age.
- **Large quantities are estimated.** See [Crafts](#crafts).
- **Disenchant data is Classic data**, tagged *beta*, with no table for epic items above item level 60.
- **Skill-up chances are estimates** based on recipe colour.
- **No sales history or frequency.** The game gives no such data, so CraftProfit cannot say how fast an item sells.
- **Auction house only for prices.** Vendor prices come from the game.

## FAQ and troubleshooting

**The window does not appear.** Select a recipe in the profession window (a recipe you know). Try `/cp show`. Check the addon is enabled and run `/cp selftest`.

**Every price shows `?`.** No price has been fetched yet. At the auction house, press **Search prices** for the pinned recipes or **Scan AH** for everything.

**The scan never finishes ("No reply from the server").** The game limits full scans to one per 15 minutes per account, and any addon's scan counts. Wait and try once.

**"Item not loaded yet, try again".** The game has not cached the item name yet; click again after a moment.

**The quantity is not filled in after clicking a reagent.** The preset is best-effort. The search itself still works; type the quantity by hand.

**The DISENCH. tile shows `n/a` for an item I just crafted.** The item is bound when picked up and your character does not know Enchanting, or the item cannot be disenchanted (not armor or a weapon, or poor quality).

**Text is in the wrong language.** Run `/cp locale` to return to the game language. Missing translations fall back to English; please report them.

**I found a bug.** Open an issue with the *Bug report* template and include the build number (`/dump select(4, GetBuildInfo())`) and any Lua error text. Enable error messages with `/console scriptErrors 1`.
