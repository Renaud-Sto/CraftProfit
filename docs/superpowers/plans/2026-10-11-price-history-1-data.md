# Price history, step 1: retention, limit and pure computations

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** New retention (7 days raw, 60 days daily, no weekly tier), tracked recipes limit 30, and the pure computations the history view needs (daily series, usual price, comparison, weekday profile, recipe net result per day). No UI in this step. The addon behaves as today except for the retention and the limit.

**Architecture:** `History.lua` (pure) changes its tiers and gains `dailySeries`, `usual`, `compare`, `weekdayProfile`; a new pure file `HistoryView.lua` (`ns.HistoryView`) turns a tracked recipe and its items' series into the figures the window and the arrows show (`recipeDays`, `summary`, `indicators`). Loaded after `History.lua`, before UI files.

**Tech Stack:** Lua 5.1, `sh tests/check.sh`, fake env `tests/fakewow.lua` (never edit). Pure files use no WoW API.

**Spec:** `docs/superpowers/specs/2026-10-11-price-history-design.md` (read it first, decisions 1, 3, 7, 9 and the testing section). Existing code: `CraftProfit/History.lua` (read it fully), `tests/test_history.lua`, `DB.lua` (series sanitising), `Boot.lua` (`Controller.historyItems`, `setTracking`, `/cp history`), `Evaluate.lua` / `Core.lua` (how AH net value is computed from a unit price: 5 % commission, `settings.cut`; do not duplicate the formula: call the existing function or read it to reproduce it exactly and test against it).

## Global Constraints

- Pure Lua, no WoW API; times in seconds, copper amounts finite integers; unknown is `nil`, never 0; no division by a zero or near-zero range; never raise on hostile series (non-tables, NaN, negatives).
- Locale keys (en/fr/es parity, never touch `esMX.lua`) only where Boot messages change (`TRACK_FULL` already takes the limit).
- Old saves load: points between 7 and 60 days stay (merged to daily), weekly points and points older than 60 days are dropped by `compact`; `History.sanitize` keeps its guarantees. No data a still-valid tier would keep may be lost.
- `sh tests/check.sh`: 0 failed, 0 luacheck warnings. Docs English (README.fr.md and user-guide.fr.md French). Commits: no co-author line, no "Generated with" line (`git log --format=%B main..HEAD | grep -ci co-authored` is 0); local commits only, the controller pushes and opens the PR. The disk flips file modes by itself: `git status --short` before each commit, add files by name (never `git add -A`), restore other files with `git checkout -- <file>`, never touch `CraftProfit/Locales/esMX.lua`.

## Review Focus

- `compact` on a real old save shape (raw 14 days, daily 90, weekly 365) gives the new tiers without loss inside the new windows and is idempotent.
- `usual` and `weekdayProfile` handle: one day, gaps, all-equal prices (range 0), an item with no points, 60 days of data, hostile points; `compare` never divides by 0 and returns nil when the usual price is unknown.
- `recipeDays` carries the last known price over a missing day, marks it as carried, never invents a point before an item's first point (that day is incomplete: no result), and never mutates saved series.
- Net result equals today's `Evaluate` value for the same prices (a test builds one recipe both ways).

---

### Task 1: Retention and limit

**Files:** `CraftProfit/History.lua`, `CraftProfit/DB.lua` (only if it references the weekly tier or the limit), `tests/test_history.lua`, `tests/test_db.lua`, `tests/test_boot.lua`.

**Interfaces:** `History.RAW_SECONDS = 7 * DAY`, `History.DAILY_SECONDS = 60 * DAY`, `History.MAX_RAW = 150`, `History.MAX_DAILY = 62`, `History.MAX_TRACKED = 30`; removed: `WEEKLY_SECONDS`, `MAX_WEEKLY`, the weekly bucket code. `compact(series, now)` signature unchanged.

- [ ] **Step 1: Read** `History.lua`, `tests/test_history.lua`; list the tests that mention weekly or the old numbers.
- [ ] **Step 2: Failing tests** for the new tiers (7 days raw, daily buckets to 60 days, older dropped, caps per tier 150 / 62, a busy week cannot evict daily points, old-shape series compacts correctly and idempotently, weekly points gone), and the limit 30 (`track` accepts 30, refuses the 31st with "full"; `sanitize` keeps 30).
- [ ] **Step 3: Implement**, update the tests of removed behaviour (say which in the report), `Controller` messages use `History.MAX_TRACKED` already.
- [ ] **Step 4: `sh tests/check.sh`** green. **Step 5: Commit** `feat: history keeps 7 days raw and 60 days daily, 30 tracked recipes`.

### Task 2: Pure computations

**Files:** `CraftProfit/History.lua` (new functions), `CraftProfit/HistoryView.lua` (new, add to the TOC after `History.lua`), `tests/test_history.lua`, `tests/test_historyview.lua` (new).

**Interfaces (names fixed; signatures documented in a header comment):**
- `History.dailySeries(series, now, days)` -> array of `{ day = <start of local day, epoch>, avg, low, high, n }` ascending, covering the last `days` days; raw points folded per local calendar day (use a `History.dayOf(t)` helper built on `date("*t", t)` with an injectable function for tests: `History.setDateFn(fn)` or a parameter), merged points kept as they are; days without data are simply absent.
- `History.usual(series, now)` -> `{ price, days, measures }` or nil: median of the daily averages of the last 30 days, nil under 3 distinct days.
- `History.compare(today, usual)` -> `{ pct, tone }` where `pct` is a rounded percent difference `(today - usual) / usual` and `tone` is `"flat"` within +-3 %, `"up"` or `"down"`; nil when either is nil or usual <= 0.
- `History.weekdayProfile(days, usual)` -> 7 entries Monday to Sunday `{ pct, n }` (`pct` nil when fewer than 2 days) from `dailySeries` output and the usual price.
- `HistoryView.recipeDays(recipe, itemSeriesOf, now, days, cut)` -> per day `{ day, materials, sale, net, carried }` (any field nil when unknown, `carried` true when any item's price was carried from an earlier day); items come from the recipe via the same item list the recording uses (take the function `itemsOf` as a parameter, as `History.record` does: `Controller.historyItems`), materials = sum of qty x reagent day price, sale = output day price after the commission (reuse the Evaluate formula), net = sale - materials.
- `HistoryView.summary(days)` -> `{ today, usual, low, high, measures, daysCovered, enough }` for one view (net, materials or one item).
- `HistoryView.indicators(recipe, itemSeriesOf, now, itemsOf, cut)` -> `{ materials = compare-result or nil, sale = compare-result or nil }` for the arrows (decision 4: materials cheaper is good, sale higher is good; the result also carries `good` true/false/nil so the UI colours it without logic).

- [ ] **Step 1: Read** the spec decisions 3, 4, 7, 9 and `Evaluate.lua` (commission formula).
- [ ] **Step 2: Failing tests** with synthetic series (a flat month, a rising weekend and falling Monday pattern, gaps, a single day, all-equal prices, hostile points, carried prices, recipe with a bound output) and a stubbed local date function (no dependence on the test machine's time zone).
- [ ] **Step 3: Implement.** **Step 4: `sh tests/check.sh`** green. **Step 5: Commit** `feat: pure price history computations (usual price, comparison, weekday profile, recipe net result)`.

### Task 3: Docs

**Files:** `docs/technical.md` (price history section: new tiers and caps, limit 30, the pure functions, size estimate about 10 KB per item), `docs/user-guide.md`, `docs/user-guide.fr.md`, `README.md`, `README.fr.md`, `docs/curseforge/project-page.md` (every "15 recipes" / weekly retention mention becomes 30 recipes / 7 days + 60 days), `docs/in-game-checklist.md` (section "History retention": track 30 recipes, the 31st is refused with the message; old history still shows after update; `/cp history` list still works), `CHANGELOG.md` `[Unreleased]` (Changed: retention, limit 30), `docs/superpowers/specs/2026-10-11-price-history-design.md` (mark step 1 done).

- [ ] Docs truth pass for exactly these changes; `sh tests/check.sh` green; commit `docs: history retention and tracked recipes limit`.
