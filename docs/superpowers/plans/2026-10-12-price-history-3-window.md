# Price history, step 3: the History window and its entry points

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The History window of the spec: tracked recipes on the left (with the arrows of decision 4), on the right the chart of the chosen view (Result / Materials cost / one item) over 7, 30 or 60 days, the key figures, the weekday strip and the honest messages (nothing selected, not enough data, where the data comes from). Opened by a button next to Leveling in the pinned footer, by the Windows panel of the options window (now 2 x 2), and by `/cp history`.

**Architecture:** `Controller.historyList()` and `Controller.historyData(recipeID, view, period)` (Boot.lua) assemble everything from `History`/`HistoryView`/`ChartModel` and the live market; `UI/HistoryWindow.lua` (`ns.HistoryWindow`) is only widgets (a `Native.window`, rows like `PinnedWindow`, `ns.Chart`, buttons), with `toggle/show/hide/isShown/refresh/frame/init/place/attach` like `PinnedWindow`. The quick arrows of the main window are step 4: here the arrows exist only in the window's list, computed by the same `HistoryView.indicators` with the 24 h freshness rule (grey or hidden when the newest measurement is older than 24 h).

**Spec:** `docs/superpowers/specs/2026-10-11-price-history-design.md` (decisions 4, 5, 6, 8, 9, error handling) and `docs/superpowers/specs/ideas-after-1.0.md`. Models to follow: `CraftProfit/UI/PinnedWindow.lua` (window, rows, scroll bar, saved position, `place`/`attach`, rightmost placement), `UI/OptionsUI.lua` (Windows panel), `UI/PinsUI.lua` (footer buttons), `UI/Chart.lua` (read its header: `Chart.new(parent, w, h, window)`, `set(model)`, `setWeekday`, `onHover`), `ChartModel.lua`, `HistoryView.lua`, `Boot.lua` (`historyCommand`, `historyItems`, `levelData` as the model of a data function, `Controller.market`).

## Global Constraints

- Constraints of the earlier plans apply (`docs/superpowers/plans/2026-10-10-native-ui-foundations.md`, `...-pinned-window.md`, `...-price-history-2-chart.md`): no image/font files, game fonts and `Colors`, taint rules (nil parent then `SetParent`, no hooks on Blizzard methods, guards with `type()`/`issecretvalue`), no dropdown/Menu API, frames start shown (hide and anchor them), `Native.window` for the window, buttons are `Native.button`, built on first open, Escape closes (named frame in `UISpecialFrames`), position saved as `settings.historyWindow = { x, y }` (sanitised in `DB.lua` like the other windows), rightmost placement helper for the default position.
- Locale keys en/fr/es with parity (never touch `esMX.lua`): window title, `HISTORY_INFO` (data comes from the searches you run yourself: without regular refreshes there is nothing reliable to show), the empty states (`Select a recipe`, `N measurements over D days. At least 3 days are needed: refresh prices at the auction house.`, paused tracking, no tracked recipe: `Tick Track history on a recipe to follow its prices.`), view names (`Result`, `Materials cost`), periods (`7 days`...), key figures (`Today`, `Usual`, `Lowest`, `Highest`, `Measurements`, `Days covered`), weekday names Monday to Sunday (short), `carried` tooltip text, the button label, and the changed `/cp history` help strings. All label widths checked with the existing width helpers for en/fr/es.
- Window size about 720 x 430 (check it fits: the options window precedent is 420 x 676; do not exceed the screen at scale 1.0 in height: 500 max), the left column about 210 px, scroll bar beyond 12 rows (30 tracked recipes at most).
- Data rules: the market is the current market only; the header names it (`Controller.marketKey` readable name via the existing `/cp market` helper); nothing is evaluated while the window is hidden (refresh only when shown); no per-frame work; the chart redraws on selection, view, period or refresh; carried days drawn lighter (the chart already does it); the 24 h freshness rule for the arrows.
- `Chart.USE_LINES`: switch it on for this window ONLY IF it is trivially a constant flip (the probe showed `CreateLine` works, docs/probe-findings.md F14); the author will judge the look in game: so make it a single named constant in `Chart.lua` with a comment, default `true` in this step, and list in the checklist the line on/off comparison.
- `/cp history`: opens the window (`/cp history <n>` opens it on the n-th tracked recipe); the old chat list becomes `/cp history list`; `remove <n>` stays; update `SLASH_HELP`, the options window Controls recap and their tests in all 3 locales.
- `sh tests/check.sh`: 0 failed, 0 luacheck warnings. Docs English (README.fr.md and user-guide.fr.md French). Commits: no co-author line, no "Generated with" line (`git log --format=%B main..HEAD | grep -ci co-authored` is 0); local commits only, the controller pushes and opens the PR. Tests first for every behaviour (watch them fail). The disk flips file modes by itself: `git status --short` before each commit, add files by name (never `git add -A`), restore other files with `git checkout -- <file>` (use `&&`, never `;`, between an add and a checkout), never touch `CraftProfit/Locales/esMX.lua`.

## Review Focus

- The window never raises with 0 tracked recipes, a paused recipe, a recipe whose items have no history, a recipe with 1 day, 2 days, 3 days, 60 days; switching view and period redraws without leaks (chart pool); selection survives a refresh; removing the selected recipe clears the selection.
- Left list rows: arrows with the 24 h rule, difficulty colours, scroll, selection tint, click selects (never opens the main window).
- Entry points: footer button placement (does the footer height change? the main window height must stay right), Windows panel 2 x 2 fits in en/fr/es and the options window height is recomputed; `/cp history` routing and help in the 3 locales.
- Drag works from the title bar, the body and the chart (forwarding); Escape closes; position saved and clamped.

---

### Task 1: Data layer in the Controller

**Files:** `CraftProfit/Boot.lua`, `Locales/*.lua` (only keys used by the data layer: view names, messages), tests `tests/test_boot.lua` (or a new `tests/test_historydata.lua`).

**Interfaces (names fixed):**
- `Controller.historyList()` -> `{ { recipe, active, indicator = { materials = { pct, tone, good } or nil, sale = ... } or nil, fresh = bool }, ... }` for `CraftProfitDB.tracked` in saved order; `indicator` nil when not enough data or the newest measurement is older than 24 h (`fresh = false`).
- `Controller.historyData(recipeID, view, period)` with `view` = `"net"`, `"materials"`, `"sale"` or `"item:<itemID>"` and `period` 7, 30 or 60 -> `{ recipe, items = { { key = "net", ... }, { key = "item:ID", itemID, name, icon }, ... }, view, period, chart = <the model for Chart:set>, summary = HistoryView.summary result, weekday = History.weekdayProfile output, status = "ok" | "paused" | "nodata", measures, days, market = readable market name }`; for an item view the days come from `History.dailySeries(series, now, period)`; the usual price comes from `History.usual` (30 days); `status = "nodata"` when `summary.enough` is false, with the numbers for the message.
- `Controller.historyItemsOf(recipe)` -> ordered list of the recipe's item ids for the icon row (reagents in order, then the crafted item unless bound, then disenchant materials when they count): reuse `Controller.historyItems`.
- `Controller.openHistory(recipeID)` -> shows the window (Task 2 provides it; stub guarded until then) and selects the recipe.
- [ ] Tests first with a fake market and series (rising weekend, gaps, paused recipe, no history, bound crafted item, 1/2/3/60 days, stale newest point -> `fresh = false`), then implement. `sh tests/check.sh` green. Commit `feat: history data for the window (list, chart model, summary, weekday profile)`.

### Task 2: The window

**Files:** `CraftProfit/UI/HistoryWindow.lua` (new, TOC after `UI/PinnedWindow.lua`), `CraftProfit/DB.lua` (`historyWindow` sanitising), `Locales/*.lua`, `.luacheckrc` if needed, tests `tests/test_historywindow.lua` (new), `tests/test_db.lua`.

**Layout:** as spec decision 6 and the global constraints; elements and fields exposed in `HistoryWindow.parts` for tests: `list` rows, `bar`, `info` text, `itemButtons` (icon buttons from `Controller.historyData(...).items`, with item textures via `C_Item.GetItemIconByID` or the existing icon helper, tooltips via the game tooltip helpers), `periodButtons` (7/30/60, lit one), `chart` (a `Chart.new(body, w, h, window)`), figures (font strings), weekday labels (names + percentages), `empty` message, `title` with the market.
Behaviour: first open selects nothing (right side shows `Select a recipe`) unless opened on a recipe; selecting a recipe resets the view to `net` and keeps the period; the period buttons and item icons redraw the chart through `Controller.historyData`; hover over a day shows its figures in a small line under the chart (or tooltip) with the `carried` note; `refresh()` is a no-op while hidden; refresh keeps selection, view and period; Escape registered once.

- [ ] Tests first for build-on-first-open, states (nothing selected, no tracked recipe, paused, nodata with counts, ok), selection/view/period wiring, hover line, refresh keeps state, removal of the selected recipe clears, position saved and sanitised (NaN, strings), label fits. Implement. Commit `feat: history window`.

### Task 3: Entry points

**Files:** `CraftProfit/UI/PinsUI.lua` (footer button), `CraftProfit/UI/OptionsUI.lua` (Windows panel 2 x 2 and window height), `CraftProfit/Boot.lua` (`/cp history`, `SLASH_HELP`, `Controller.init` wiring, `Controller.refresh` calls `HistoryWindow.refresh`), `Locales/*.lua`, tests `tests/test_pinsui.lua`, `tests/test_optionsui.lua`, `tests/test_boot.lua`.

- [ ] Footer: a **History** button to the right of Leveling (same width as the others, footer height unchanged), always enabled; Windows panel: four buttons in two rows of two (Main window, Leveling / Pinned recipes, History), widths and window height recomputed and tested for en/fr/es; `/cp history`, `/cp history <n>`, `/cp history list`, `remove <n>`; Controls recap lines updated (the recap line count and the window height formula). Tests first. Commit `feat: open the history window from the footer, the options and /cp history`.

### Task 4: Docs

**Files:** `docs/technical.md` (history window, data functions, entry points, freshness rule, `settings.historyWindow`), `docs/user-guide.md`, `docs/user-guide.fr.md` (a "Price history" section: what it shows, how to read the bars, the weekday strip, why data depends on the player's refreshes, how to open it), `README.md`, `README.fr.md` and `docs/curseforge/project-page.md` (feature line: price history view), `docs/in-game-checklist.md` (section "History window": states, selection, views, periods, hover, weekday strip, lines on/off comparison, drag from the chart, entry points, FR/ES label fit, and a note to take screenshots), `CHANGELOG.md` `[Unreleased]` Added (History window, `/cp history` now opens it, list moved to `/cp history list`) and Changed (limit 30, retention 7/60 days, from step 1 if not yet listed), spec step 3 marked done.

- [ ] Docs truth pass on exactly these changes; `sh tests/check.sh` green; commit `docs: price history window`.
