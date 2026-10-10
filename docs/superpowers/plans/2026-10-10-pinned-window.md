# Standalone pinned-recipes window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A movable window "Pinned recipes" that works anywhere (no auction house, no profession window needed): the pinned recipes with their last known prices, a sort button, an unpin "x" on each row, and a click on a row that opens the main window on that recipe. Opened by `/cp pins`, by the right click on the minimap button and on the compartment entry.

**Architecture:** New `UI/PinnedWindow.lua` (`ns.PinnedWindow`) built like `LevelingUI` (a `Native.window` with a native panel, rows, scroll bar and strip), fed by one Controller function `Controller.pinsData()` (like `Controller.levelData()`), reusing the row ordering and value text of `PinsUI` (`PinsUI.orderedPins`, a new exported `PinsUI.rowValue`). The list under the main window at the auction house (`PinsUI`) does not change. Everything is on `ns.Native`, `ns.Colors`, `ns.Layout`.

**Tech Stack:** Lua 5.1 (WoW Forever beta, Interface 16001), `sh tests/check.sh`, fake env `tests/fakewow.lua` (never edit).

**Spec:** `docs/superpowers/specs/2026-10-10-native-ui-design.md`. Models to follow: `CraftProfit/UI/LevelingUI.lua` (window, saved position, strip, age line, panel, rows, scroll bar, `place`/`attach`), `CraftProfit/UI/PinsUI.lua` (row text and colours, ordering, unpin handling in `Controller.togglePin`), `CraftProfit/Boot.lua` (`Controller.levelData`, `selectPin`, `selectKnown`, `toggleMainWindow`, slash handler, `saveOptionsPosition`), `CraftProfit/UI/OptionsUI.lua` (Windows panel, recap), `CraftProfit/UI/MinimapButton.lua` (click routing, tooltip, compartment function).

## Global Constraints

- All constraints of the earlier native plans still apply (`docs/superpowers/plans/2026-10-10-native-ui-foundations.md`, `...-main-window.md`, `...-lists.md`, `...-options-window.md`): no image/font files, game fonts and colours (`Colors`), taint rules (nil parent then `SetParent` for templated frames, no hooks on Blizzard methods, clickable things are `Button`s, `HookScript` over `SetScript` on templated widgets), guards with `type(x)`, frames start shown so hide and anchor them, no dropdown/Menu API, no `StaticPopup_Show`.
- The window is built on first open (not at login), Escape closes it (named frame in `UISpecialFrames`), its position is saved in `CraftProfitDB.settings.pinsWindow = { x, y }` (sanitised in `DB.lua` like `levelWindow` and `optionsWindow`; hostile values dropped).
- Prices shown are the last known ones (this window never searches the AH): the age line says how old they are (`Present.ageText`, stale colour past `settings.staleAfter`, exactly like the leveling window's line).
- Unpin "x": a `Button` 16x16 at the right of each row, left of the scroll bar, its tooltip says "Unpin" (localized), it removes the pin through `DB.pinRemove` like `Controller.togglePin` does, refreshes every view (main window, pins list under it, this window) and never selects the row. Clicking anywhere else on a row: `Controller.selectPin(recipeID)` then `Controller.showMainWindow()`.
- Sort button in the strip: same behaviour as the list under the main window (`Controller.toggleSort`, label `L.SORT_NET` / `L.SORT_POINT`).
- Amounts use `Controller.fmt` (coin icons); gain green and loss red from `Colors.FIXED`; difficulty colours from `Colors.FIXED[recipe.difficulty]`.
- Empty state (no pinned recipe): a line of text "No pinned recipes. Pin a recipe from its window." (localized EN/FR/ES) where the rows would be.
- Locales: every string through `ns.L` in `Locales/enUS.lua`, `frFR.lua`, `esES.lua` (never touch `esMX.lua`); natural, short.
- `sh tests/check.sh`: 0 failed, 0 luacheck warnings. Docs in English (README.fr.md and user-guide.fr.md in French). Commits: no co-author line, no "Generated with" line (`git log --format=%B main..HEAD | grep -ci co-authored` is 0); commit locally only, the controller pushes and opens the PR. `git status --short` before committing: restore stray mode flips with `git checkout -- <file>` for files you did not change (never chmod committed files), never touch `Locales/esMX.lua`.

## Review Focus

- Unpinning from the "x" while the list is scrolled to the bottom: offset is clamped, the bar updates, nothing selects.
- The row click opens the main window even when the profession window and the AH are closed; the main window shows that recipe with its stored prices (no nil error when a price is missing).
- A pin whose prices are all missing shows "?" (as `PinsUI` does), never an error.
- The window stays in sync when a recipe is pinned or unpinned elsewhere (`Controller.refresh` path) while it is open; hidden, it does nothing.
- 40 pins (the maximum) scroll with the native bar; long names are cut before the value and the "x".

---

### Task 1: PinnedWindow, Controller data and saved position

**Files:** Create `CraftProfit/UI/PinnedWindow.lua`, `tests/test_pinnedwindow.lua`; modify `CraftProfit/CraftProfit.toc` (after `UI/LevelingUI.lua`), `CraftProfit/UI/PinsUI.lua` (export `PinsUI.rowValue`), `CraftProfit/Boot.lua`, `CraftProfit/DB.lua`, `CraftProfit/Locales/enUS.lua`, `frFR.lua`, `esES.lua`; tests `tests/test_db.lua`, `tests/test_boot.lua`.

**Interfaces:**
- `PinsUI.rowValue(item, byPoint)` -> `text, colour` (`{r,g,b,a}`) for one ordered pin (`item.recipe`, `item.result`), exactly the text and colour `PinsUI.refresh` computes today (move that logic into this function and call it from `refresh`; behaviour unchanged, its tests keep passing).
- `Controller.pinsData()` -> `{ items = <PinsUI.orderedPins(CraftProfitCharDB.pins, sortMode, Controller.evaluate)>, byPoint = bool, ageText, stale }` with age from `Prices.snapshotAge(Controller.market(), time())` like `levelData`.
- `Controller.unpin(recipeID)`: `DB.pinRemove` then `Controller.refresh()` (no selection change).
- `Controller.savePinsPosition(x, y)` (finite check, as `saveOptionsPosition`).
- `ns.PinnedWindow`: `toggle()`, `show()`, `hide()`, `isShown()`, `refresh()` (does nothing while hidden or unbuilt), `frame()`, `parts` (exposed for tests), `init(controller, handlers)` called from `Controller.init` like `LevelingUI.init`. `Controller.refresh` also calls `ns.PinnedWindow.refresh()`.
- Window `CraftProfitPinnedWindow`: title `L.PINNED_TITLE` ("Pinned recipes"), width like `LevelingUI.WIDTH`, strip with the sort button (full width), age line, panel `L.PANEL_PINS` with up to 12 visible rows (18 px) and `Native.scrollbar`, empty text. Default position when nothing saved: `CENTER` offset (-260, 0) (the main window defaults to +300).
- New locale keys: `PINNED_TITLE`, `PINNED_EMPTY`, `UNPIN_TIP` (EN "Unpin", FR "Désépingler", ES "Desfijar"/consistent with existing UNPIN text: reuse `L.UNPIN` if it already exists and fits).

- [ ] **Step 1: Read** `LevelingUI.lua`, `PinsUI.lua`, `Boot.lua` (levelData, refresh, init, saveOptionsPosition, togglePin), `DB.lua` sanitiser for `levelWindow`/`optionsWindow`, the locales, `tests/test_levelingui.lua`, `tests/test_pinsui.lua` as test models.
- [ ] **Step 2: Write failing tests** (`rowValue` parity with the old refresh output; `pinsData` ordering and age; `unpin` removes and refreshes; saved position sanitising incl. NaN/inf/wrong types; window built lazily, Escape registered once, rows for each pin with difficulty colour and value, "x" removes the pin and does not select, row click calls selectPin then showMainWindow, sort button toggles and relabels, empty text, scroll clamp after unpin at the bottom, `refresh` no-op while hidden, 40 pins, locales parity).
- [ ] **Step 3: Implement.** **Step 4:** `sh tests/check.sh` green. **Step 5: Commit** `feat: standalone pinned-recipes window`.

---

### Task 2: Entry points

**Files:** Modify `CraftProfit/Boot.lua` (`/cp pins`, SLASH_HELP), `CraftProfit/UI/MinimapButton.lua` (right click, tooltip, compartment function), `CraftProfit/UI/OptionsUI.lua` (Windows panel button "Pinned recipes", recap text), `Locales/enUS.lua`, `frFR.lua`, `esES.lua`; tests `tests/test_minimapbutton.lua`, `tests/test_optionsui.lua`, `tests/test_boot.lua`.

**Interfaces:**
- `/cp pins` toggles `ns.PinnedWindow`; `SLASH_HELP` (3 locales) lists `pins`.
- Minimap right click and compartment right click: `ns.PinnedWindow.toggle()` (they used `Controller.toggleMainWindow`; keep that function, `/cp show` and `/cp hide` still use it). Tooltip line: "Right click: pinned recipes". Left click unchanged (options).
- Options window: the Windows panel gets a third button "Pinned recipes" next to "Main window" and "Leveling" (resize the three to fit; French labels must not overflow), and the Controls recap says: "Minimap button: left click options, right click pinned recipes. Commands: /cp show, hide, options, pins, level, minimap, ..." (FR/ES translated, window height recomputed).

- [ ] **Step 1: Read** the three files and their tests. **Step 2: Failing tests** for each routing and text (including the old right-click-main-window test updated). **Step 3: Implement. Step 4: check. Step 5: Commit** `feat: open the pinned window from /cp pins and the minimap button`.

---

### Task 3: Docs

**Files:** `docs/in-game-checklist.md`, `docs/technical.md`, `CHANGELOG.md`, `README.md`, `README.fr.md` (commands table: `/cp pins`), `docs/user-guide.md`, `docs/user-guide.fr.md` (a short "Pinned recipes window" section; the options window recap and minimap sentences updated to right click = pinned recipes), `docs/superpowers/specs/2026-10-10-native-ui-design.md` (decision 2b: right click now opens the pinned window).

- [ ] **Step 1: Checklist** "Pinned window (PR 11)": `/cp pins` opens it with the profession window and the AH closed; rows with difficulty colours and values with coin icons; stale age line; sort button; "x" unpins (rows below move up, no main window opens); click on a row opens the main window on that recipe with stored prices; scrolling with many pins; empty state; Escape; drag and position kept after `/reload`; minimap right click and compartment right click open it; the list under the main window at the AH still works and both stay in sync; French labels do not overflow; no Lua error.
- [ ] **Step 2:** technical.md (module row, `Controller.pinsData`, `settings.pinsWindow`), CHANGELOG Unreleased "Added: pinned recipes window ...", README tables, user guides EN/FR, spec 2b.
- [ ] **Step 3:** `sh tests/check.sh` green; authorship check; commit `docs: pinned window`.
