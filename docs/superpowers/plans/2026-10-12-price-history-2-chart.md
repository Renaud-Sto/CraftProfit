# Price history, step 2: probes, chart geometry and the chart widget

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two in-game probes (are `CreateLine` and `time(table)` usable on Forever?), the pure geometry of the history chart and the weekday strip, and the chart widget built on it. The widget is hosted by the History window in step 3, so its look is verified in game only then; this step is verified by unit tests (geometry, fields, wiring) and the probe results.

**Architecture:** `ChartModel.lua` (pure, `ns.ChartModel`): turns the day rows of `HistoryView` into abstract geometry (scale, ticks, bars, usual line, weekday bars) and axis labels. `UI/Chart.lua` (`ns.Chart`): frames and textures that draw that geometry (no template, no atlas dependency), with an optional connecting line through the daily averages (`Chart.USE_LINES`, default false until the probe says `CreateLine` works). Probes live in `probe/CraftProfitProbe/Native.lua` (`/cppn line`, `/cppn time`).

**Spec:** `docs/superpowers/specs/2026-10-11-price-history-design.md` (decisions 8 and 9, error handling). Existing: `CraftProfit/HistoryView.lua`, `History.lua` (dayOf, date and time injection), `UI/Layout.lua`, `UI/Native.lua` (fonts, colours via `Colors`), `Format.money`.

## Global Constraints

- Constraints of the earlier plans apply (`docs/superpowers/plans/2026-10-10-native-ui-foundations.md`, `...-pinned-window.md`): no image/font files, game fonts and `Colors`, taint rules (nil parent then `SetParent` where needed, no hooks on Blizzard methods, guards with `type()`/`issecretvalue`), pure files stay pure, frames start shown (hide and anchor them).
- Probes: log lines start with `[CPP` and go to the log (the main probe mirrors them); a probe never changes saved data; `/cppn line` and `/cppn time` print a one-line verdict in chat and the details to the log.
- Chart: no division by a zero or tiny range (when low equals high, pad the scale), missing days are gaps (never zeros), carried days are drawn with a lighter tint, no per-frame work (redraw on data change only), at most 62 bars (60 days) plus the weekday strip: reuse textures from a pool, never create per redraw; amounts on the axis are plain text `12g 40s` (no coin icons); never raise on empty or hostile input (empty series, one point, NaN, inf).
- `sh tests/check.sh`: 0 failed, 0 luacheck warnings. Docs English (README.fr.md and user-guide.fr.md French only if user-visible). Commits: no co-author line, no "Generated with" line (`git log --format=%B main..HEAD | grep -ci co-authored` is 0); local commits only, the controller pushes and opens the PR. The disk flips file modes by itself: `git status --short` before each commit, add files by name (never `git add -A`), restore other files with `git checkout -- <file>` (use `&&`, never `;`, between an add and a checkout), never touch `CraftProfit/Locales/esMX.lua`.

## Review Focus

- Scale arithmetic: range 0, one day, huge amounts (1e9 copper), negative net results (a loss: the zero line must appear when the range crosses it), tick values rounded to readable steps.
- Bars: low-high span, average tick, carried tint, gaps, the usual line within the visible range or clamped at the border with an indicator.
- Weekday strip: Monday first, empty bars for fewer than 2 days, scale symmetric around 0 %.
- Pool reuse: redrawing 60 then 7 days hides the extra bars; no texture leak.

---

### Task 1: Probes

**Files:** `probe/CraftProfitProbe/Native.lua` (and its TOC only if needed), `docs/probe-findings.md` (F14 entry "Chart primitives (to measure in game)" with how to run and what to look for).

- [ ] `/cppn line`: create a frame `CPPLineProbe` (movable, Escape closes) and test, each in `pcall`: `frame:CreateLine`, `SetStartPoint/SetEndPoint`, `SetThickness`, `SetColorTexture`; draw a small fan of 5 coloured lines and a polyline of 7 points on a dark background; also draw 7 vertical bars from textures for comparison; print the verdict `lines: ok` or the error; log the object type `line:GetObjectType()`, and whether `SetThickness` accepts 1 and 2.
- [ ] `/cppn time`: for fixed test timestamps (a mid-June noon, a late-October noon, a late-March noon of the current and previous year) print `date("*t", ts)` fields, `time{year,month,day,hour=0}` of that date, whether `time(table)` returns a number, `GetServerTime()`, `GetTime()`, and the local UTC offset deduced as `os.time`-free: `time(date("*t", ts)) - ts` (or the `date("!*t")` comparison); log everything; verdict line `time(table): ok` when `time{...}` of midnight is within 24 h before the noon timestamps and a multiple of... (just check it returns a number and that `date("*t", time(t))` round-trips the same day).
- [ ] `luajit -bl` syntax check of the probe, commit `probe: chart primitives (CreateLine, time(table))`.

### Task 2: Pure chart geometry

**Files:** `CraftProfit/ChartModel.lua` (new, TOC after `HistoryView.lua`), `tests/test_chartmodel.lua` (new).

**Interfaces (names fixed):**
- `ChartModel.scale(lo, hi, steps)` -> `{ min, max, step, ticks = { values } }`: a readable range around [lo, hi] (padding, nice steps of 1, 2, 5 x 10^k copper units with a minimum step of 1), always `max > min`, includes 0 as a tick when the range crosses it.
- `ChartModel.priceLabel(copper)` -> plain text `12g 40s`, `40s`, `5c`, `-3g 10s`, `1.2k g` for large values (state the rule in a comment; never icons).
- `ChartModel.bars(days, scale, width, height)` -> per day `{ x, w, yLow, yHigh, yAvg, carried }` in pixel units inside a `width` x `height` area (y from the top), days without data are skipped but keep their slot (x from the day index in the period, `days` = the output of `HistoryView.recipeDays` or `History.dailySeries` rows for one field, with a `field` argument naming which value to chart: `net`, `materials`, `sale` or an item series); `ChartModel.usualY(usual, scale, height)` -> y clamped into the area plus `outside` = `"above"`/`"below"`/nil.
- `ChartModel.weekdayBars(profile, width, height)` -> 7 entries `{ x, w, y, h, pct, n, empty }` around a zero line at mid-height, symmetric scale from the largest |pct| (minimum +-10 %).
- `ChartModel.slots(period)` -> the day index/slot arithmetic for a 7, 30 or 60 day period ending at the newest day.

- [ ] Failing tests with synthetic data (flat month, a rising weekend, a loss crossing zero, one day, range 0, 1e9, NaN and inf points ignored, empty input), then implement; `sh tests/check.sh` green; commit `feat: pure chart geometry (scale, bars, weekday strip)`.

### Task 3: Chart widget and docs

**Files:** `CraftProfit/UI/Chart.lua` (new, TOC after `UI/Native.lua`), `tests/test_chart.lua` (new), `.luacheckrc` if needed, `docs/technical.md` (chart and geometry), `docs/in-game-checklist.md` (section "History chart" listing what to check in step 3), `CHANGELOG.md` is NOT touched (no visible change yet), spec (mark step 2 done).

**Interfaces:** `Chart.new(parent, width, height)` -> object with `frame`, `:set(model)` (model = `{ days, field, scale, usual, period, carriedTint }`, nil clears), `:clear()`, `:setWeekday(profile)`, `:hover` support: `object.onHover(day)` callback invoked with the day row under the pointer via invisible slot buttons (Buttons, never plain frames), pooled bars (`texture` per bar, reused), gridlines at ticks with `priceLabel` font strings (`GameFontHighlightSmall`, pooled), the usual line, gaps, `Chart.USE_LINES` + `:drawLine` fallback to bars when `CreateLine` is absent or errors.

- [ ] Tests in the fake env: pool reuse (60 then 7 days), clear, empty and hostile models do not raise, hover slot wiring, label count equals tick count, `USE_LINES` false by default, line path guarded; docs; `sh tests/check.sh` green; commits `feat: history chart widget` and `docs: history chart and probes`.
