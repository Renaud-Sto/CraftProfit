# Price history view: design

Status: draft for review (2026-10-11). Target: version 1.1.0, after 1.0.0 passes CurseForge moderation. No hurry: quality first.

## Goal

Tell a crafter, at a glance and in detail, whether now is a good time to craft or to sell, from the prices CraftProfit has recorded. Two uses, decided with the author:

- **A. Quick answer.** In the main window: is the cost of the materials, and the auction house value of the crafted item, above or below its usual level?
- **B. Understand a trend.** A window with the history of a tracked recipe, to see for example that prices rise at the weekend and fall at the start of the week.

Not a goal: sales speed (the game gives no sales history), alerts, prices of recipes that are not tracked, cross-realm comparison.

## Facts the design rests on

- History exists only for recipes ticked *Track history* (account wide), per market (ruleset/realm and faction), per item: `market.series[itemID]` holds points `{ t, unit, volume, low, high, n }` (`History.lua`).
- Points are written only when the player runs a search or scan at the auction house (`Refresh recipe`, `Refresh pinned`, `Scan AH`): the data is as regular as the player's habits. The view must say so and show how many measurements are behind each comparison.
- A recipe is recorded only when every required item has a price; the crafted item of a bind-on-pickup recipe is optional.
- Each measurement is already a median of the 5 cheapest units (the price model), so a point is a robust price, not a single listing.

## Decisions

1. **Retention (changes `History.lua`, DB sanitising and docs).** Raw points for 7 days, at most 150 per item; daily points (merged weighted average, low, high, count) for 60 days, at most 62 per item; no weekly tier. At most 212 points per item, under a third of the earlier worst case (725); a point takes about 150 to 180 bytes in the saved file, so the worst case is about 35 KB per item (2 to 3 MB for 30 recipes), rarely reached. Days are local calendar days. Existing saves load and compact down to the new tiers (weekly points older than 60 days are dropped; points between 7 and 60 days become daily). `History.WEEKLY_SECONDS`, `MAX_WEEKLY`, the weekly bucket code and their tests go.
2. **Tracked recipes limit: 15 becomes 30.** Not tied to pins: a pin may be temporary, the author ticks *Track history* only on recipes that matter for gold. The tracked list stays account wide. The message "too many tracked recipes" mentions the limit.
3. **Usual price = median of the daily points of the last 30 days** (raw points of the last 7 days count as today's). Needs at least 3 distinct days; below that: no indicator, and the window says what is missing.
4. **Quick indicators in the main window (option 1, only for tracked recipes).** A small coloured arrow and percentage next to the Materials total and on the AH (NET) tile: `-18 %` green when the materials are cheaper than usual, `+12 %` green when the sale value is higher, red for the opposite, grey when within ±3 %. Tooltip on hover (today's price, usual price, lowest, highest, number of measurements, days covered). No click: the tile click searches the item and the Materials header folds the detail, so neither can open the history.
5. **History window (new, native).** Opened by a **History** button in the pinned footer beside Leveling (visible with the auction house), by a button in the Windows panel of the options window (that panel becomes 2 x 2), by `/cp history` (the existing list moves to `/cp history list`; `remove <n>` stays), and by the compartment/minimap menu only if trivial (not required). Not tied to the auction house.
6. **Window layout** (about 720 x 430, movable, position saved as `settings.historyWindow`, Escape closes, built on first open):
   - Left column (about 210 px): the tracked recipes (up to 30), each row with its name coloured by difficulty and the arrows of decision 4; a scroll bar beyond 12 rows; an information line on top: *Data comes from the auction house searches you run yourself. Without regular refreshes there is nothing reliable to show.*
   - Right column: a row of item icon buttons (first: **Net result**, then the recipe's items: reagents, crafted item, disenchant materials when they count) with tooltips; period buttons **7 / 30 / 60 days**; the chart; the key figures (today, usual, lowest, highest, measurements, days covered); the **day of the week** strip.
   - Empty right side: *Select a recipe.* Not enough data: *N measurements over D days. At least 3 days are needed: refresh prices at the auction house.* A recipe with a paused tracking says it.
7. **Net result per day** = (AH value of the crafted item after the 5 % commission) minus the cost of the materials, from the daily medians of each item; an item with no point on a day takes its last known price, marked as carried (lighter tint, counted in the key figures). If the crafted item is bound on pickup or has no history, the net result is the cost of the materials only and says so. The first icon offers two views: **Result** and **Materials cost** (see 8).
8. **Chart: bars, not lines.** For each day a vertical bar from the lowest to the highest price of that day with a tick at the average; the usual price as a horizontal line; carried days drawn lighter; missing days left empty. Built from coloured textures on a plain frame (no template, no atlas dependency). The `Line` object (smooth curves) is **not** assumed: a probe checks `CreateLine` on Forever first; if it works, a connecting line through the daily averages is added, otherwise bars stay. Vertical scale: min and max of the shown period with a margin, never a zero divisor when low equals high; gold/silver/copper axis labels with the coin formatting (no icons on the axis: plain `12g 40s`). The icon row for Net result offers two views, **Result** and **Materials cost**.
9. **Day of the week strip.** Seven bars Monday to Sunday: the average of the daily averages of that weekday over the period divided by the period's usual price, as a percentage (`+8 %`); number of days behind each bar; weekdays with fewer than 2 days are drawn empty. Day of week comes from `date("*t", t)` in the player's local time.
10. **Indicators for pins and leveling are out of scope** (history is per tracked recipe).

## Architecture

- `History.lua` (pure): retention changes, plus new pure functions: `History.dailySeries(series, now, days)` (daily points of the period, raw points folded into days), `History.usual(series, now)` (median of 30 days, count, days), `History.compare(today, usual)`, `History.weekdayProfile(points, usual)`, `HistoryView.recipeDays(recipe, itemSeriesOf, now, days, cut, itemsOf)` for the per-day net result, all unit tested with hand-made series.
- `HistoryView.lua` (pure, new): turns a tracked recipe into what the window shows (figures, bars geometry in abstract units, the strip), no widgets.
- `UI/Chart.lua` (new, widget): the bar chart and the weekday strip, on frames and textures, with `Layout`-style pure helpers for scale and ticks (tested).
- `UI/HistoryWindow.lua` (new): the window on `ns.Native` (window, list rows, buttons, scroll bar); refreshes on `Controller.refresh` while shown.
- `Window.lua`/`Present.lua`: the arrows next to the Materials total and on the AH tile, fed by `Controller.historyIndicators(recipe)`.
- `Boot.lua`: `Controller.historyData(recipeID)`, `Controller.openHistory(recipeID)`, `/cp history` routing, button wiring; tracked limit 30.
- Locale keys for en/fr/es with parity; docs; checklist; changelog; probe finding F14 (CreateLine) and the skill update.

## Error handling and edge cases

No division by a zero or tiny range; a tracked recipe whose items have partial history still shows the items that have data; markets: data is the current market's only, the header names it; hostile saved points are already sanitised by `History.sanitize`; a recipe removed while the window shows it clears the selection; 30 recipes and 60 days draw in under a few milliseconds (no per-frame work, redraw on selection or refresh only); window never evaluates the whole pinned list; carried prices never invent a point in the saved data.

## Testing

Pure modules under the fake environment with synthetic series (busy fortnight, gaps, a rising weekend, a single day, hostile values, DST-free local time via a stubbed `date`). Widgets: fields, geometry arithmetic, scroll and selection wiring, empty and low-data states; the look is checked in game by the author (checklist section) with screenshots. Probe `/cppn line` for `CreateLine` before the chart is built.

## Delivery

1. Retention and limit 30 (History, DB, docs, tests) plus pure computations (usual, compare, weekday, net result). **Done** (branch `feat/price-history`): `History.lua`, `HistoryView.lua`, docs.
2. Chart widget and probe.
3. History window and entry points.
4. Quick indicators in the main window.
5. Docs, checklist, changelog, skill and probe findings; one PR per step; in-game checks after 3 and 4.

## Open points

- Whether the arrows also help in the pinned list (not now).
- Whether the weekday strip should split weekend hours (not possible: points are daily after 7 days).
- Possible later: export, alerts, graph per market.
