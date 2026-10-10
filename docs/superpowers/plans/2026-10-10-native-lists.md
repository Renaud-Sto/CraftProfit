# Native lists Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the pinned list (`UI/PinsUI.lua`) and the leveling window (`UI/LevelingUI.lua`) from the old `ns.Kit` to the native kit `ns.Native`, with a native-looking scroll bar, so no window uses the old Kit any more.

**Architecture:** Same public APIs and model-driven refresh in both files; only the widget factory changes. Add `Native.scrollbar(parent, trackH)` with the same contract as `Kit.scrollbar` (`bar.frame`, `bar:update(total, visible, offset)`, `bar.onScroll(offset)`, `bar.thumb`) and the same grab/offset maths (`Kit.scrollThumb`, `Kit.scrollOffsetAt`, `Kit.scrollGrab`, left button only, lost mouse-up recovery through `IsMouseButtonDown`, `OnUpdate` only while dragging), but drawn from the game's own `minimal-scrollbar-*` atlases. Blizzard's `MinimalScrollBar` needs a `ScrollBox`; our lists are 6 to 12 fixed rows, so we keep our row logic and do not move to `WowScrollBoxList`. After this step nothing consumes colour themes (the pinned and leveling windows were the last consumers): `/cp theme`, `settings.theme` and `Kit.applyTheme` stay in place, harmless, until step 4 (appearance options) and step 5 (cleanup).

**Tech Stack:** Lua 5.1 (WoW Forever beta, Interface 16001), `sh tests/check.sh`, fake game env `tests/fakewow.lua` (never edit).

**Spec:** `docs/superpowers/specs/2026-10-10-native-ui-design.md`. Native kit: `CraftProfit/UI/Native.lua` (read all of it, including `Native.listRow`, `Native.panel`, `Native.window`, `Native.check`, `Native.button`). Colours: `CraftProfit/Colors.lua`. Blizzard source clone: `.cache/wow-ui-source/Interface/AddOns/` (git-ignored; find the real atlas names and anchors of `MinimalScrollBar` in `Blizzard_SharedXML`, search for `minimal-scrollbar`).

## Global Constraints

- All constraints of `docs/superpowers/plans/2026-10-10-native-ui-foundations.md` and `docs/superpowers/plans/2026-10-10-native-main-window.md` still apply (no image/font files, game fonts and colours, taint rules: nil parent then `SetParent` for templated frames, no hooks on Blizzard methods, clickable things are `Button`s, guards around template internals with `type(x)` tests, frames start shown, atlases checked with `C_Texture.GetAtlasInfo` with a flat-colour fallback).
- Behaviour that must not change: pin ordering, sort toggle, difficulty colours (`Colors.FIXED[recipe.difficulty]`), selected row tint for the current recipe, scrolling by wheel and bar, search queue, scan, status line, host show/hide with the AH, `PinsUI.parts` and `LevelingUI.parts` fields used by tests, the leveling window's profession/sort strip, age line, 12-row NEXT POINT panel, grey-recipes check, saved position, EMPTY text wrap, `LevelingUI.show/hide/toggle/isShown/place/attach/frame`.
- The pinned list lives inside the main window's `pinsHost` (a plain frame of ours): keep its width `Window.INNER_WIDTH`.
- `sh tests/check.sh`: 0 failed, 0 luacheck warnings. Docs in English. Commits: no co-author line, no "Generated with" line (`git log --format=%B main..HEAD | grep -ci co-authored` is 0); commit locally only, the controller pushes and opens the PR. `git status --short` before committing: restore stray mode flips with `git checkout -- <file>` for files you did not change (never chmod committed files), never touch `CraftProfit/Locales/esMX.lua`.

## Review Focus

- Scroll bar: grabbing the thumb off-centre does not jump, right click ignored, a drag stops when the button is released outside the game window (`IsMouseButtonDown`), no `OnUpdate` work while idle, thumb never shorter than a usable minimum, bar hidden when everything fits.
- Row hover and selected tints visible over the native panel body; the scroll bar never covers row values (right inset); wheel scrolling still works over rows and the bar.
- The sort button in the pinned panel header sits above the header's click area; header height unchanged.
- The leveling window: title, close, drag, attach beside the profession window, long translated labels do not overflow.
- Nothing in either file still touches `Kit.current`, `Kit.onTheme` or `Theme.*`.

---

### Task 1: Native.scrollbar

**Files:**
- Modify: `CraftProfit/UI/Native.lua`
- Test: `tests/test_native.lua`

**Interfaces:**
- Consumes: `Kit.scrollThumb`, `Kit.scrollOffsetAt`, `Kit.scrollGrab`, `Kit.SCROLL_W` (pure helpers stay in Kit until step 5); read `Kit.scrollbar` and its tests in `tests/test_kit.lua` first and port the behaviours and their tests.
- Produces: `Native.SCROLL_W` (8 unless the atlases say otherwise; document the number you pick) and `Native.scrollbar(parent, trackH)` -> `bar` with `bar.frame` (a `Button`, `SCROLL_W` wide, `trackH` high, hidden initially), `bar.thumb`, `bar:update(total, visible, offset)` returning true when shown, `bar.onScroll(newOffset)`. Track and thumb from `minimal-scrollbar-track-*` / `minimal-scrollbar-thumb-*` atlases (top/middle/bottom pieces, or the single atlases that exist: read the Blizzard source and report which) with a flat-colour fallback (`DISABLED_FONT_COLOR` track at low alpha, `NORMAL_FONT_COLOR` thumb) when an atlas is unknown.

- [ ] **Step 1: Read** `Kit.scrollbar`, `tests/test_kit.lua` scroll tests, Blizzard's `MinimalScrollBar` template and atlas names (`.cache/wow-ui-source`), `Native.lua`.
- [ ] **Step 2: Write failing tests** (port the Kit scrollbar tests: update shows/hides, thumb size and top, OnMouseDown left only, grab offset keeps the thumb still, drag via OnUpdate, lost mouse-up recovery, OnHide ends a drag; plus atlas-known and atlas-unknown paths).
- [ ] **Step 3: Run, see them fail; implement; make them pass.**
- [ ] **Step 4: `sh tests/check.sh`** green.
- [ ] **Step 5: Commit** `feat: native scroll bar drawn from the game's atlases`.

---

### Task 2: PinsUI on Native

**Files:**
- Modify: `CraftProfit/UI/PinsUI.lua`
- Test: `tests/test_pinsui.lua`, and the PinsUI parts of `tests/test_boot.lua` / `tests/test_window.lua` if they reference Kit

**Interfaces:**
- Consumes: Task 1 (`Native.scrollbar`), `Native.panel`, `Native.listRow`, `Native.button`, `Colors`.
- Produces: the same `PinsUI` API. `PinsUI.FOOTER_H` recomputed from `Native.BUTTON_H` (22 px buttons, 6 px gaps, status 28 px).

- [ ] **Step 1: Read** `PinsUI.lua`, `tests/test_pinsui.lua`, `Window.lua` (how `pinsHost` is placed and sized), `Native.lua`. List every `Kit.*` / `Theme.*` / `Kit.current` use and its replacement in the report.
- [ ] **Step 2: Migrate.** `Kit.panel` -> `Native.panel`; rows via `Native.listRow(body, i, ROW_H, Native.SCROLL_W + 6)`; the sort button is a `Native.button` 20 px high at the header's right (lifted above the header hit area like today); search/scan/level buttons `Native.button` (search is the red primary look the template gives; all three keep their widths); scroll bar `Native.scrollbar`; texts with game font objects; muted/plain colours from `Colors.text(...)`, difficulty and gain/loss from `Colors.FIXED`; remove the `Kit.onTheme` registrations and the `host:IsShown()` refresh guard that existed only for them (keep `onAHOpen` refreshing); panel height from `Native`'s panel height helper (or `Kit.panelHeight` with `Native.HEAD_H`, as `Window.lua` does).
- [ ] **Step 3: Adapt tests**: replace Kit/theme assertions by native ones; delete only tests that covered theme repainting of these rows (say so in the report); keep ordering, sort, selection, scrolling, search/scan status tests.
- [ ] **Step 4: `sh tests/check.sh`** green.
- [ ] **Step 5: Commit** `feat: pinned list on the native kit`.

---

### Task 3: LevelingUI on Native

**Files:**
- Modify: `CraftProfit/UI/LevelingUI.lua`
- Test: `tests/test_levelingui.lua` (+ boot test parts)

**Interfaces:**
- Consumes: Tasks 1-2 patterns, `Native.window` (with `UISpecialFrames` registration as today if the old window had it: check, keep behaviour), `Native.panel`, `Native.listRow`, `Native.button`, `Native.check`, `Native.scrollbar`, `Colors`.
- Produces: the same `LevelingUI` API.

- [ ] **Step 1: Read** `LevelingUI.lua`, `tests/test_levelingui.lua`, `Window.lua` as a model of a migrated window. List every `Kit.*` / `Theme.*` use and replacement in the report.
- [ ] **Step 2: Migrate** exactly as in Task 2: `Native.window("CraftProfitLevelWindow", L.LEVEL_TITLE, { width, height, onMoved })`, strip buttons `Native.button`, age line, `Native.panel` NEXT POINT with 12 rows, `Native.scrollbar`, grey-recipes `Native.check` (with a `maxWidth` so a long label stays inside), content width/height from native insets (`Native.INSET_*`, `Native.CONTENT_PAD`), `EMPTY_WIDTH` recomputed. Remove all theme registrations.
- [ ] **Step 3: Adapt tests**, delete only theme-repaint tests (say so).
- [ ] **Step 4: `sh tests/check.sh`** green; `grep -n "Kit\.\|Theme\." CraftProfit/UI/PinsUI.lua CraftProfit/UI/LevelingUI.lua CraftProfit/UI/Window.lua` shows only the pure helpers (`Kit.panelHeight`, `Kit.stack`, `Kit.fitSize`, `Kit.scrollThumb/OffsetAt/Grab`, `Kit.GAP`...) and nothing about colours or themes: report the output.
- [ ] **Step 5: Commit** `feat: leveling window on the native kit`.

---

### Task 4: Docs and checklist

**Files:**
- Modify: `docs/in-game-checklist.md`, `docs/technical.md`, `CHANGELOG.md`, `docs/user-guide.md`, `docs/user-guide.fr.md` (only if they describe the old look of these windows), `docs/superpowers/specs/2026-10-10-native-ui-design.md` (Delivery: mark step 3 done)

- [ ] **Step 1: Checklist** "Native lists (PR 7)": pinned list rows with difficulty colours, selected row for the open recipe, hover; scroll with wheel and bar (grab the thumb off-centre: no jump; right click does nothing; drag then alt-tab: the drag stops); sort button in the header toggles; Search prices / Scan AH / Leveling buttons and status line; leveling window: open from the pinned list button and `/cp level`, rows scroll, grey-recipes check (click box and label), profession and sort buttons, drag, close, position kept after `/reload`; long French labels do not overflow; no Lua error; screenshots compared with the game's own panel.
- [ ] **Step 2: technical.md**: module table (`PinsUI`, `LevelingUI`, `Native.scrollbar`), note that all windows are native and the old Kit now only supplies pure layout helpers until step 5. **CHANGELOG** Unreleased "Changed: the pinned list and the leveling window now use the game's own frames, rows and scroll bar".
- [ ] **Step 3:** `sh tests/check.sh` green; authorship check; commit `docs: native lists`.
