# Native main window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the main window (`UI/Window.lua`) from the old `ns.Kit` to the native kit `ns.Native`, with the chosen look (header strip `b`, tile card `b`).

**Architecture:** `Window.lua` keeps its public API (`create`, `render`, `attach`, `relayout`, `sections`, `contentHeightOf`, `parts`, `show/hide`, `pinsHost`, `INNER_WIDTH`, `WIDTH`) and its model-driven rendering; only the widget factory changes from `Kit.*` to `Native.*`. Meaning colours move to a small `ns.Colors` table shared with old code through `Theme.FIXED`. The pinned list (`PinsUI.lua`) and the leveling window still use the old Kit and its themes until step 3; they keep working inside the native main window. The header swatch and `onThemeClick` leave the main window (the swatch cycled colour themes, which do not apply to a native frame; `/cp theme` keeps working for the pinned and leveling windows until step 5).

**Tech Stack:** Lua 5.1 (WoW Forever beta, Interface 16001), tests `sh tests/check.sh` (luajit + luacheck), fake game env `tests/fakewow.lua` (never edit).

**Spec:** `docs/superpowers/specs/2026-10-10-native-ui-design.md`. Native kit: `CraftProfit/UI/Native.lua` (read its header comment and every public function first). Blizzard source clone: `.cache/wow-ui-source/Interface/AddOns/` (git-ignored).

## Global Constraints

- Everything in the previous plan's constraints still applies (`docs/superpowers/plans/2026-10-10-native-ui-foundations.md` "Global Constraints"): no image/font files, game font objects only, game colour globals for chrome, taint rules (nil parent + `SetParent` for templated frames that may sit under Blizzard panels, no hooks on Blizzard methods, clickable things are `Button`s, `HookScript` over `SetScript` on templated widgets), guards around template internals with `type(x) == "table"` / `"function"` tests, frames start shown so hide and anchor them.
- Appearance defaults: `Native.headerVariant = "b"`, `Native.tileVariant = "b"`. Do not add a settings UI (step 4).
- Behaviour that must not change: model rendering, the Materials fold (header click -> `handlers.onCostToggle(not expanded)`), reagent row click -> `handlers.onReagentClick(itemID, qty)`, AH tile and title click -> `handlers.onOutputClick`, magnifier icons only while `ns.AH.isOpen` and a recipe is shown, crafts input applied on focus lost via `handlers.onCraftsChange`, track / per-point toggles, pin button, pinned host placement below the sections, saved-position attach logic, `Window.parts` fields used by tests (`banner`, `tiles`, `rows`, `frames`, `likely`, `age`, `craftsBox`, `track`, `perPoint`, `pin`, ...), the "empty" state text.
- Pure maths stays unit-tested. Native frames are verified in game only (checklist).
- `sh tests/check.sh`: 0 failed, 0 luacheck warnings. Docs in English. Commits: no co-author line, no "Generated with" line (`git log --format=%B main..HEAD | grep -ci co-authored` must be 0); commit locally only, the controller pushes and opens the PR. Before committing run `git status --short`; some Lua files flip to mode 755 by themselves: restore with `git checkout -- <file>` any file you did not change (never `chmod` committed files), never touch `CraftProfit/Locales/esMX.lua`.

## Review Focus

- The banner tint follows the result kind (profit / loss / incomplete / none), never an appearance setting; the long warning text must not run under the value.
- Content width: native inset edges (9 left, 6 right, 24 top) plus `Native.CONTENT_PAD` change the inner width; nothing may overflow the window (tiles, reagent rows, the per-point label vs its value).
- A reagent row hover tint must show over the panel body, and the click area must not block dragging the window from the body.
- The window height stays correct when Materials is folded, when there is no "likely" line, and with the pinned list shown.

---

### Task 1: Colors, Native.banner, Native.listRow

**Files:**
- Create: `CraftProfit/Colors.lua` (module `ns.Colors`), add before `Theme.lua` in the TOC
- Modify: `CraftProfit/Theme.lua` (`Theme.FIXED = ns.Colors.FIXED`, no duplicate table), `CraftProfit/UI/Native.lua`, `CraftProfit/CraftProfit.toc`, `.luacheckrc` if new globals
- Test: `tests/test_native.lua`, `tests/test_theme.lua` (must still pass), new `tests/test_colors.lua` if useful

**Interfaces:**
- Produces: `ns.Colors.FIXED` with exactly the keys and values of today's `Theme.FIXED` (profit, loss, incomplete, stale, best, optimal, medium, easy, trivial); `Colors.text(kind)` returning an `{r,g,b,a}` table for `"main"` (game `HIGHLIGHT_FONT_COLOR`), `"muted"` (`DISABLED_FONT_COLOR`), `"gold"` (`NORMAL_FONT_COLOR`): each reads the game global when it is a table with `GetRGBA` returning numbers, else a built-in fallback (white, 0.5 grey, 1/0.82/0).
- `Native.banner(parent, height)` -> table `{ frame, label, text, value, set(spec) }`; `set({ kind, label, warning, text, value })` applies exactly today's `setBanner` behaviour: tone from `Colors.FIXED` (`profit`, `loss`, `incomplete`, other = `trivial`), label with the optional warning appended after ` \194\183 ` in the incomplete colour, value font fitted by `Kit.fitSize` over `Native.TILE_FONTS`-style game font objects (use game font objects only; sizes from the font objects available, the value shrinks when wider than 120 px), the text drops to the small font when it would run under the value, tinted background fill (alpha 0.09) and 2 px edge (alpha 0.45) drawn on a native card (the tile's inset structure, `Native.tile` variant `b` look) so it matches the tiles. Tint colours are plain textures vertex-coloured, no theme.
- `Native.listRow(body, index, rowH, rightInset)` -> a `Button` row like `Kit.listRow` (same signature and returned fields: the button itself with `.selected` tint texture hidden by default, hover tint with the additive `Interface\QuestFrame\UI-QuestTitleHighlight`, `HookScript` for hover, `SetScript("OnClick")` left to the caller, body drag forwarded with `Native.forwardDrag` semantics left to callers as in `Kit.listRow`). Read `Kit.listRow` and its tests and keep their contract.

- [ ] **Step 1: Read** `Theme.lua`, `Kit.listRow`, `Window.lua` `setBanner`/`buildBanner`, `Native.tile`, `Native.panel`, `tests/test_native.lua` helpers (`boot`, `knownAtlases`, `recordTextures`), `tests/test_theme.lua`.
- [ ] **Step 2: Write failing tests** (Colors parity with the old table, `Colors.text` fallback when globals are no-ops, `Native.banner:set` for each kind: label/value/text set, warning appended with the incomplete colour escape, long text drops to small font, fill and edge tint colours with the right alphas; `Native.listRow` fields, selected hidden, hover on/off via the recorded HookScript, index placement `-(index-1)*rowH`).
- [ ] **Step 3: Run, see them fail; implement; make them pass.**
- [ ] **Step 4: `sh tests/check.sh`** green.
- [ ] **Step 5: Commit** `feat: Colors module, native banner and native list row`.

---

### Task 2: Window.lua on Native

**Files:**
- Modify: `CraftProfit/UI/Window.lua`, `CraftProfit/Boot.lua` (the Window.create handler table only: remove `onThemeClick`; keep `Controller.cycleTheme` and `/cp theme` working for other windows), `CraftProfit/Locales/*.lua` only if a string becomes unused (leave them if unsure)
- Test: `tests/test_window.lua`, `tests/test_boot.lua`

**Interfaces:**
- Consumes: Task 1 (`Colors`, `Native.banner`, `Native.listRow`), `Native.window/panel/tile/button/check/input/forwardDrag/searchIcon` from the foundations.
- Produces: same `Window` API as today; `Window.contentHeightOf(list)` = stacked section heights + `Native.CONTENT_PAD * 2`; `Window.INNER_WIDTH` = `WIDTH - Native.INSET_LEFT - Native.INSET_RIGHT - Native.CONTENT_PAD * 2`; `Window.sections(opts)` heights use `Native.panelHeight` if Native has it, else `Kit.panelHeight`/`Kit.stack` (pure helpers stay in Kit until step 5; the panel head height is `Native.HEAD_H`).

- [ ] **Step 1: Read** `Window.lua` fully, `tests/test_window.lua`, the Window parts of `tests/test_boot.lua`, and `Native.lua` (every public function), then list in the report every `Kit.*` / `Theme.*` / `Kit.current` use in Window.lua and what replaces it.
- [ ] **Step 2: Migrate.**
  - `Kit.window` -> `Native.window("CraftProfitWindow", L.TITLE, { width = WIDTH, onMoved, onTitleClick = searchOutput })`; no `onThemeClick`; `content` is `frame.content`; sections are placed from `content` with `Native.CONTENT_PAD` on every side.
  - banner -> `Native.banner`; `setBanner(spec)` becomes `parts.banner:set(spec)` while keeping `parts.banner` fields the tests need (keep `label`, `text`, `value`, and add `fill`/`edge` accessors as Task 1 defines).
  - tiles -> `Native.tile`; tile 1 `onClick(searchOutput)`; `Native.forwardDrag(parts.tiles[1].hit, frame)`.
  - Materials -> `Native.panel`, rows via `Native.listRow(panel.body, i, ROW_H, 0)`; fold and header click unchanged; row text colours from `Colors.text("main")` / `("muted")`.
  - age line, likely line, empty text: game font objects (`GameFontDisableSmall`, `GameFontHighlightSmall`, `GameFontDisable`), muted colour from `Colors.text("muted")`; stale age uses `Colors.FIXED.stale`.
  - Options -> `Native.panel`, `Native.input` (crafts, numeric), `Native.check` for track and per-point (per-point label stays cut before its value), `Native.button` for pin (120 px wide, 22 px high, `onClick` -> `handlers.onPinClick`); `OPTION_ROW_H` adjusted to the native widget heights (22 px button, 24 px check): derive from `Native.BUTTON_H`/`Native.CHECK_SIZE`, keep the panel height equal to the sum of its rows.
  - Remove every `Kit.onTheme`, `Kit.current` and `themed(...)` use from Window.lua; the per-point value neutral colour is `Colors.text("main")`.
  - `pinsHost` anchors inside the content margin below the sections: update `Window.relayout` with the native insets (`Native.INSET_LEFT + Native.CONTENT_PAD`). Pinned list rows from `PinsUI` stay on the old Kit.
- [ ] **Step 3: Adapt tests** in `tests/test_window.lua` and `tests/test_boot.lua`: replace Kit/theme assertions by native equivalents (sections and heights, banner tint kinds with `Colors.FIXED`, tile click and icons, fold, reagent click, crafts focus-lost, toggles, pin, relayout with and without the pinned host, empty state, saved-position attach). Delete the tests that only tested theme repainting of the main window (they no longer apply) and say so in the report; keep the meaning-colour tests.
- [ ] **Step 4: Run `sh tests/check.sh`** until green with 0 warnings. Run it once more after `git status --short` shows only intended files.
- [ ] **Step 5: Commit** `feat: main window on the native kit`.

---

### Task 3: Docs and checklist

**Files:**
- Modify: `docs/in-game-checklist.md`, `docs/technical.md`, `CHANGELOG.md`, `docs/user-guide.md`, `docs/user-guide.fr.md` (only if they describe the old look or the header colour swatch for the main window), `docs/superpowers/specs/2026-10-10-native-ui-design.md` (Delivery: mark step 2 done, note the swatch left the main window)

- [ ] **Step 1: `docs/in-game-checklist.md`:** section "Native main window (PR 6)": compare with the demo and the game's panels (screenshot to the controller); open a recipe: banner tint for profit, loss, incomplete; best tile outlined and magnifier on the AH tile and title at the AH; long amount tile does not overflow; Materials header folds, reagent rows hover and click searches the reagent; crafts box applies on focus lost; track, per-point checks, pin button; pinned list under the window still works and scrolls; drag from title bar, body, tile and reagent rows; window with no recipe shows the empty text; `/cp theme copper` no longer changes the main window (expected) and the header has no colour swatch; close with the cross and Escape.
- [ ] **Step 2: `docs/technical.md`:** module table rows for `Colors.lua` and the new Native functions; main window now on Native; coexistence note (pins and leveling still on Kit until step 3).
- [ ] **Step 3: `CHANGELOG.md`** Unreleased: "Changed: the main window now uses the game's own frame, panels, buttons and fonts. The header colour swatch is gone from it."; user guides: update any sentence about the swatch/themes of the main window (EN and FR).
- [ ] **Step 4: spec Delivery** note. `sh tests/check.sh` green; authorship check.
- [ ] **Step 5: Commit** `docs: native main window`.
