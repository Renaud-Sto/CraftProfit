# History window rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the History window readable at first sight after the author's first in-game test (screenshots 2026-10-12): every part in its own native panel, plain wording, a clearer chart, smooth list scrolling.

**Architecture:** Same modules (`Boot.lua` data functions, `HistoryView.lua`, `UI/Chart.lua`, `UI/HistoryWindow.lua`, `Locales/*`). Data additions are pure and tested; the window is rebuilt on `Native.panel` frames; the list is cached so scrolling never recomputes data.

**Spec:** `docs/superpowers/specs/2026-10-11-price-history-design.md` (add a short "Rework after the first in-game test" section at the end of it describing this plan's decisions).

## Global Constraints

- Branch `feat/history-window` (PR #28 open). Commit there. **No co-author line, no "Generated with" line, ever.** Add files by name; chain git commands with `&&` (never `;`); the disk flips file modes by itself: restore with `git checkout -- <file> &&` only for files you did not edit.
- Never touch `CraftProfit/Locales/esMX.lua` or `tests/fakewow.lua` (if the fake lacks an API you need, stub it inside your own test file, or stop and report).
- Native game look only (Blizzard templates/atlases through `ns.Native`), no StaticPopup, no Menu API, no hooks on Blizzard methods, no chat messages. One texture per atlas for life.
- Docs in English (README.fr.md and docs/user-guide.fr.md in French). Locale keys with en/fr/es parity (tests check it). Write French and Spanish as a native speaker would for WoW.
- `sh tests/check.sh` (luajit tests + luacheck) must pass with 0 warnings. Tests first for pure code.
- Window must fit a 768 px high screen at scale 1 if possible (`Native.fitToScreen` stays as the safety net).

## Review Focus

- Net view with negative values: never print `-9s40c`; a loss reads "loss 9s40" (en), "perte de 9s40" (fr), "pérdida de 9s40" (es); a zero line exists in the chart.
- Fewer than 7 days of data on a 60-day period: the plot spans only from the first data day (minimum 7 slots), never 90 % empty.
- A recipe with no disenchant materials, or a bound-on-pickup output: item groups show only the groups that exist, no orphan separator.
- Scroll with 30 tracked recipes: wheel and scroll bar repaint rows from a cached list only; no `historyList()`/`historyData()` call per scroll step (test it with a counter).
- Weekday panel with no data: a one-line muted note, not seven empty labels.

## Decisions (already approved by the author)

1. **Panels.** Left: the tracked recipes in a `Native.panel` titled "Tracked recipes", with a column header row ("Materials" / "Sale", muted, right aligned over two fixed-width columns; each row has two separate fontstrings, one per column, so columns line up). The information sentence moves under the list panel as a small muted hint (3 lines max). Right, top to bottom, each in its own `Native.panel` (same look as the options window panels): (a) **verdict panel**, no title bar needed beyond the recipe name as panel title: line 1 "<What> today: <money>", line 2 coloured sentence "12 % cheaper than usual (3s55): good time to buy" / "8 % higher than usual (…)" / "about the usual price (…)" (flat band ±3 %, `History.compare`; good = green, bad = red, flat = grey; nothing on line 2 without enough data); (b) **chart panel**: the tabs row, the item icon groups, the period buttons, a caption line saying what is drawn, then the chart; (c) **figures panel**: four cells "Now", "Usual", "Lowest"/"Highest" (for Profit: "Worst day"/"Best day"; for Materials: "Cheapest day"/"Priciest day"), each with its date under the amount in muted small text; "N measurements over D days" as a single muted line; (d) **typical week panel**: titled "Typical week", seven bars with the weekday name under each bar and the percentage above, one muted line "Shows after about two weeks of data." when the profile is empty; (e) the status line (paused) and the Pause/Delete buttons at the bottom, as now.
2. **Tabs**: three buttons "Materials cost" | "Sale price" | "Profit" (view keys `materials`, `sale`, `net`); lit (gold line) on the active one; none lit when an item icon is active. Captions: Profit "Profit if sold at the auction house, after the 5 % commission" (use the real commission from settings, as Controller does), Materials "Cost of all the materials", Sale "Auction house price of the crafted item, after the commission", item view "<item name>: auction house price". Default view stays `net`.
3. **Icon groups**: `Controller.historyData` marks each item with `group` = `"materials"` (reagents), `"crafted"` (the crafted item when sold) or `"disenchant"`. The window draws the groups side by side in one row, each with a tiny muted caption above ("Materials", "Crafted item", "Disenchant"), a thin vertical separator (`SetColorTexture`, muted, 1 px) between non-empty groups. Icons 24 px; if a group does not fit in the row, wrap the whole icon area to a second line (two rows maximum, as now).
4. **Chart look**: the plot sits on its own darker inset background (`Native` inset/`InsetFrameTemplate` or a colour texture bordered like other panels), horizontal grid lines faint, axis amounts at the left, **dates under the plot** (first, middle, last day of the drawn range, short date) instead of weekday names; bars with a lighter top edge and semi-transparent body (low to high of the day), the daily average as a small bright dash plus a dot on the line; the connecting line a little thicker; the usual price as a dashed-looking line (alternating short segments) in the gold tone with a small label chip "Usual" at the right end; the net view draws a clear zero line labelled `0` and colours days above zero green, below zero red (`Colors.FIXED.profit` / `loss`); carried days lighter as now; on hover the column is highlighted and a readable bubble (a small panel inside the chart, normal-size font) shows: date, average, low-high, number of measurements, and for Profit the day's sale value and materials cost on two more lines; the old tiny hover line under the chart is removed. The x range spans from the first day with data to the newest day, at least 7 slots, at most the period; the number of slots drives bar width.
5. **Wording** (en; fr/es translated natively): replace "Result" with "Profit", add "Sale price", "Materials cost"; figures labels per Decision 1; "Today" becomes "Now"; keep existing keys that are still used, delete the unused ones, keep parity.
6. **Scroll lag**: `HistoryWindow` keeps the last `historyList()` result in a local `cachedList`. `refresh()` (called by the controller, selection, view, period, pause, delete) recomputes it; the mouse wheel and the scroll bar call only `repaintList()` (rows + bar from the cache, no data work, no right-side repaint). `parts.bar.onScroll` and the wheel handler must not call `HistoryWindow.refresh`.
7. **Row hover tooltip** on the list rows: "Materials: today vs usual. Sale: today vs usual. Green is good for you (cheaper materials, higher sale)." (one key per language) via `GameTooltip`, hidden on leave.

## Task 1: Data additions (pure, tests first)

**Files:** `CraftProfit/HistoryView.lua`, `CraftProfit/Boot.lua` (`Controller.historyData`), `tests/test_historyview.lua` (and the existing Boot/controller test file that covers `historyData`; find it with grep).

- `HistoryView.summary` additionally returns `lowDay`, `highDay` (the day of the row holding the minimum / maximum; `low`/`high` semantics unchanged) and `todayDay`.
- `Controller.historyData` returns `items[i].group`, `compare` (= `History.compare(summary.today, summary.usual)` with `good` set by view: materials lower is good, sale/net/item higher is good; nil when not enough data), `commission` (the `cut` percentage as number) and per-day `sale`/`materials` stay available in `chart.days` rows (already there for recipe views).
- Tests: group assignment (reagents, crafted, disenchant, bound-on-pickup output without the crafted group), `lowDay`/`highDay`, compare good/bad per view, nil compare under 3 days.

## Task 2: Chart rework

**Files:** `CraftProfit/ChartModel.lua`, `CraftProfit/UI/Chart.lua`, tests `tests/test_chartmodel.lua`, `tests/test_chart.lua` (names may differ: grep).

Implement Decision 4. `ChartModel` gains the pure helpers: `range(days, period, newest)` → first/last day and slot count (min 7, max period), `dateTicks(first, last)` (first, middle, last), `zeroY` handling when the scale spans zero, dashed-segments geometry for the usual line. `Chart:set(model)` keeps its public contract used by the window (`model.days`, `field`, `usual`, `period`, `newest`) and gains `onHover(row, anchor)` carrying the row so the window can build the bubble text, or the chart draws the bubble itself from a `bubbleText(row)` callback supplied by the window (choose one, document it in the file header). `Chart:setWeekday` moves to a separate small widget in the same file (own frame, weekday names under bars, percentage above) so the window can place it in its panel. Tests: range with 4 data days on a 60-day period, slots minimum, zero line position for negative nets, dash geometry, date ticks, bubble content.

## Task 3: Window rebuild

**Files:** `CraftProfit/UI/HistoryWindow.lua`, `CraftProfit/Locales/enUS.lua`, `frFR.lua`, `esES.lua`, tests `tests/test_historywindow.lua` (name may differ), docs.

Implement Decisions 1, 2, 3, 5, 6, 7. Keep the public API (`show`, `hide`, `toggle`, `refresh`, `select`, `state`, `init`, `attach`, `frame`, `isShown`, `dateText`, `parts` fields used by tests: update tests to the new fields). Pause/Delete behaviour (two-click, 4 s, disarm on hide) is unchanged and must keep its tests. Add the scroll tests (counter on `historyList`/`historyData`). Update `docs/user-guide.md`, `docs/user-guide.fr.md`, `docs/technical.md`, `docs/in-game-checklist.md` (History section: new things to check), `docs/curseforge/project-page.md` wording only if it mentions "Result"/"Today", `CHANGELOG.md` (Unreleased). Add the spec section. Finish with `sh tests/check.sh` green and a final commit; push the branch (`git push`).

Report: write the full report to `.superpowers/sdd/2026-10-12-history-window-rework/report.md`; return only status, commits, one-line test summary, concerns.
