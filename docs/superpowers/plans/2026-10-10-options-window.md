# Options window, appearance and minimap button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the player choose the look (header strip a/b/c and tile card a/b, independently, default b b) in a native options window that is opened by `/cp options`, by an optional minimap button (shown by default, hideable) and by the addon compartment entry; the choice applies immediately to every window and is saved.

**Architecture:** `Native` keeps registries of its panels and tiles and re-applies the chosen variants when they change (`Native.setHeaderVariant` / `Native.setTileVariant` already exist for windows built later; they now also repaint live ones). The choice is saved in `CraftProfitDB.settings.appearance = { header = "b", tile = "b" }` (sanitised by `DB.lua`) and applied in `Controller.init` before any window is built. A new `UI/OptionsUI.lua` (`ns.OptionsUI`) is the window; a new `UI/MinimapButton.lua` (`ns.MinimapButton`) is the button; the compartment entry is a TOC field plus one global function. Colour themes (`/cp theme`, `settings.theme`, `Kit.applyTheme`) are NOT touched here: they have no visible effect any more and are removed in step 5.

**Tech Stack:** Lua 5.1 (WoW Forever beta, Interface 16001), `sh tests/check.sh`, fake game env `tests/fakewow.lua` (never edit).

**Spec:** `docs/superpowers/specs/2026-10-10-native-ui-design.md` decisions 2 and 2b (read them). Native kit: `CraftProfit/UI/Native.lua` (read all of it). Reference for minimap button convention and pitfalls: `elyes_SO6/SO-6-develop/.claude/skills/interface-wow/reference.md` ("Bouton de minicarte", "Compartiment d'addons") and `pieges.md` (git-ignored folder, read-only reference, do not copy code). Blizzard source clone: `.cache/wow-ui-source/Interface/AddOns/` (git-ignored).

## Global Constraints

- All constraints of the three previous native plans still apply (`docs/superpowers/plans/2026-10-10-native-ui-foundations.md`, `2026-10-10-native-main-window.md`, `2026-10-10-native-lists.md`): no image/font files, game fonts and colours, taint rules (nil parent then `SetParent` for templated frames, no hooks on Blizzard methods, clickable things are `Button`s, `HookScript` over `SetScript` on templated widgets), guards with `type(x)` tests, frames start shown so hide and anchor them, atlas checked with `C_Texture.GetAtlasInfo` with a fallback.
- **No dropdown, no `Menu` API, no `StaticPopup_Show`, no `Settings` API panel** (Forever crashes or taints). Choices are rows of `Native.button`s (segmented control: the chosen one stays lit with `LockHighlight`, the others `UnlockHighlight`).
- Minimap button: no library (no LibDBIcon), 31x31, strata MEDIUM, frame level 8, dragged with the left button only, angle saved, never shown or created at login if `settings.minimap.hide` is true, no chat message at login, `OnUpdate` only while dragging. Icon: an `Interface\Icons\...` texture from the list the game serves (use `INV_Misc_Coin_01`-style gold coin, check with `GetFileIDFromPath` in a guard; fall back to `INV_Misc_QuestionMark`), cropped with `SetTexCoord(0.05, 0.95, 0.05, 0.95)`; ring `Interface\Minimap\MiniMap-TrackingBorder` 50x50 TOPLEFT, highlight `Interface\Minimap\UI-Minimap-ZoomButton-Highlight`, background `Interface\Minimap\UI-Minimap-Background` 24x24 (the paths SO-6 uses and that work on Forever).
- Strings: every user-visible string goes through `ns.L` in `Locales/enUS.lua`, `frFR.lua`, `esES.lua` (esMX is an alias: do not touch `esMX.lua`). French and Spanish natural, short (labels sit on 22 px buttons).
- Behaviour that must not change: everything the three native windows do today. Saved settings of old versions load (a missing or bad `appearance` falls back to `b`/`b`).
- `sh tests/check.sh`: 0 failed, 0 luacheck warnings. Docs in English (README.fr.md and user-guide.fr.md in French). Commits: no co-author line, no "Generated with" line (`git log --format=%B main..HEAD | grep -ci co-authored` is 0); commit locally only, the controller pushes and opens the PR. `git status --short` before committing: restore stray mode flips with `git checkout -- <file>` for files you did not change (never chmod committed files), never touch `CraftProfit/Locales/esMX.lua`.

## Review Focus

- Live switch: panels and tiles that already exist change look at once, hidden ones too (they are shown later); no leak (registry holds only frames we created; a panel is registered once).
- The tile variants differ in structure: switching must keep the best-tile outline, muted value colour, hover tint, click and magnifier icon working in both.
- Saved data: bad, missing or hostile `appearance` / `minimap` values (wrong types, NaN angle, unknown keys) never raise and fall back to defaults.
- The minimap button: position at any angle, square minimaps, dragging does not fire a click on release, hiding and showing at runtime, it survives `/reload`, left and right click do what the spec says, nothing is created when hidden at login.
- The options window: Escape closes it (named frame in `UISpecialFrames`), position kept, segmented buttons reflect the saved choice every time it opens, long French labels do not overflow.

## Rulings (controller)

- The pinned list exists only inside the main window while the auction house is open. The minimap right click therefore toggles the main window (`show`/`hide` as `/cp show` and `/cp hide`); its pinned list appears below it at the AH. The options window "Controls" recap says so.
- Variant labels: header a "Quest bar", b "Wood", c "Streaks"; tile a "Loot card", b "Inset" (translate in FR/ES).

---

### Task 1: Live appearance in Native

**Files:** Modify `CraftProfit/UI/Native.lua`; test `tests/test_native.lua`.

**Interfaces:**
- Produces: `Native.setHeaderVariant(key)` and `Native.setTileVariant(key)` (existing; now also re-apply to every registered panel / tile, return the key in use); `Native.appearance()` -> `header, tile` keys; registries filled by `Native.panel` and `Native.tile` (each registers once); a panel's header atlas, divider and fallback re-applied by one local function used by both construction and the live switch; a tile builds both structures (loot-card textures and inset) and `tile.variant` shows one, hiding the other, keeping outline, tint, muted colour, click and icon behaviour in both.

- [ ] **Step 1: Read** `Native.panel`, `Native.tile`, their tests, the `/cp kitdemo` variant code in `KitDemo.lua`.
- [ ] **Step 2: Failing tests** for: switching header variant changes `headerAtlas` of existing panels (and of one built after); unknown key ignored; switching tile variant on an existing tile swaps which structure is shown, best outline and muted colour intact in both; a panel registers once; both switches with the fallback (atlas unknown) do not raise.
- [ ] **Step 3: Implement**; keep `KitDemo` working (its rebuild logic can stay).
- [ ] **Step 4:** `sh tests/check.sh` green. **Step 5: Commit** `feat: native panels and tiles switch their look live`.

---

### Task 2: Saved appearance

**Files:** Modify `CraftProfit/DB.lua`, `CraftProfit/Boot.lua`; tests `tests/test_db.lua`, `tests/test_boot.lua`.

**Interfaces:**
- Produces: `DB.DEFAULTS.appearance = { header = "b", tile = "b" }` and `DB.DEFAULTS.minimap = { hide = false, angle = 225 }`; `sanitizeSettings` validates `appearance.header` in `{a,b,c}`, `appearance.tile` in `{a,b}`, `minimap.hide` boolean, `minimap.angle` a finite number normalised into [0, 360) (anything else -> defaults); `Controller.setAppearance(header, tile)` (either may be nil = keep): validates, calls `Native.setHeaderVariant` / `Native.setTileVariant`, saves, returns true when something changed; `Controller.init` applies the saved appearance before `ns.Window.create`.

- [ ] **Step 1: Read** `DB.lua`, `Controller.init`, existing settings tests. **Step 2: failing tests** (defaults for old saves, hostile values, `setAppearance` persists and applies, init applies the saved choice before the window is built: record the variant seen at `Window.create`). **Step 3: implement. Step 4: check. Step 5: commit** `feat: saved appearance and minimap settings`.

---

### Task 3: Options window

**Files:** Create `CraftProfit/UI/OptionsUI.lua`; modify `CraftProfit/CraftProfit.toc`, `CraftProfit/Boot.lua` (`/cp options`, SLASH_HELP), `Locales/enUS.lua`, `frFR.lua`, `esES.lua`; tests `tests/test_optionsui.lua` (new), `tests/test_boot.lua`, `tests/test_locale.lua` if it checks key parity.

**Interfaces:**
- Consumes: Tasks 1-2, `Native.window/panel/button/check`, `Controller.setAppearance`.
- Produces: `ns.OptionsUI` with `toggle()`, `show()`, `hide()`, `isShown()`, `refresh()`, `frame()`; window `CraftProfitOptionsWindow` (title `L.OPTIONS_TITLE`, width 372, Escape closes via `UISpecialFrames`, position saved in `settings.optionsWindow` like the leveling window and sanitised in `DB.lua`); panels: **Appearance** (rows "Header strip" with three segmented buttons, "Tile card" with two; clicking calls `Controller.setAppearance`; the lit button follows the saved choice at every `refresh`), **Minimap** (check "Show the minimap button" -> `Controller.setMinimapHidden(not checked)`, a function you add in Boot that saves and calls `ns.MinimapButton.apply()` when present), **Windows** (buttons "Main window" -> same as `/cp show`/`/cp hide` toggle, "Leveling" -> `ns.LevelingUI.toggle()`), **Controls** (recap text, wrapped lines in `GameFontHighlightSmall`: "Minimap button: left click options, right click main window (the pinned list shows below it at the auction house). Commands: /cp show, hide, options, level, minimap, history, scan, market, locale <code>, selftest."; in FR and ES translated). `/cp options` toggles it; `SLASH_HELP` lists `options` and `minimap`.
- The window is built on first open (not at login). Its widgets use only game fonts and the native kit.

- [ ] **Step 1: Read** `LevelingUI.lua` (a migrated window with saved position and attach/place), `Native.lua`, `Boot.lua` slash handler and `Controller.refresh`, locale files. **Step 2: failing tests** (built lazily, toggle, Escape registration, segmented buttons reflect and set the choice, minimap check calls the setter, windows buttons, position saved and restored, all locales have the new keys). **Step 3: implement. Step 4: check. Step 5: commit** `feat: options window with appearance choice`.

---

### Task 4: Minimap button and compartment entry

**Files:** Create `CraftProfit/UI/MinimapButton.lua`; modify `CraftProfit/CraftProfit.toc` (file + `## AddonCompartmentFunc: CraftProfit_OnCompartmentClick`, `## IconTexture:` same icon), `Boot.lua` (`/cp minimap`, `Controller.setMinimapHidden`, compartment global), locales; tests `tests/test_minimapbutton.lua`, `tests/test_boot.lua`.

**Interfaces:**
- Produces: pure helpers (unit tested): `MinimapButton.angleFromCursor(cx, cy, mx, my)` degrees in [0, 360) from the minimap centre, `MinimapButton.offset(angle, radius, square)` returning x, y relative to the minimap centre for round and square minimaps (square: clamp the point of the circle to the square's half-size, as LibDBIcon does), `MinimapButton.radius(minimapWidth)` = half width + 5. Widget: `MinimapButton.create()` (idempotent, nothing created when `settings.minimap.hide`), `MinimapButton.apply()` (show or hide per the saved setting, creating on first show, repositioning from the saved angle), left click -> `ns.OptionsUI.toggle()`, right click -> toggles the main window (`Controller` show/hide as `/cp show` / `/cp hide`), drag with the left button: `OnUpdate` only while dragging reads `GetCursorPosition` / `Minimap:GetCenter`, saves the angle on drag stop, a drag end does not fire a click (flag), tooltip (`GameTooltip`, `GameTooltip_SetTitle` + instruction lines: left click options, right click main window, drag to move). `CraftProfit_OnCompartmentClick(addonName, button)` global: left toggles options, right toggles the main window. `/cp minimap` toggles hidden and says so in chat (one short localized line each way). `Controller.init` calls `MinimapButton.apply()` after the windows exist.
- Created with the minimap as a plain parent frame of ours? NO: parent is `Minimap` (a Blizzard frame): create with a nil parent, then `SetParent(Minimap)`, strata `MEDIUM`, level 8, as in the SO-6 notes.

- [ ] **Step 1: Read** the SO-6 reference notes, `Controller` show/hide code, `Boot.lua` slash and init. **Step 2: failing tests** (pure helpers at 0/90/180/270/225 degrees round and square, hostile angles, apply shows/hides per setting and creates nothing when hidden at login, clicks route to the right action, drag does not click, `/cp minimap` toggles and saves, compartment function routes left/right, TOC contains the fields). **Step 3: implement. Step 4: check. Step 5: commit** `feat: minimap button, compartment entry and /cp minimap`.

---

### Task 5: Docs and checklist

**Files:** `docs/in-game-checklist.md`, `docs/technical.md`, `CHANGELOG.md`, `README.md`, `README.fr.md` (commands tables: add `/cp options`, `/cp minimap`), `docs/user-guide.md`, `docs/user-guide.fr.md` (a short "Options window" section: choose the look, minimap button, compartment, controls recap), spec Delivery (step 4 done), `docs/probe-findings.md` (compartment visibility to verify in game).

- [ ] **Step 1: Checklist** "Options window (PR 8)": `/cp options` opens it, Escape closes it; choosing each header strip and tile card applies at once to the main window, pinned list, leveling window and the options window itself; all 6 combinations look right; `/reload` keeps the choice; the minimap button appears by default at the saved angle, left click toggles options, right click toggles the main window, dragging moves it around the minimap without clicking, it keeps its place after `/reload`; unticking the check hides it and `/cp minimap` brings it back; the compartment entry (does it show on Forever's minimap? note the answer); French labels do not overflow; no Lua error; screenshots.
- [ ] **Step 2:** technical.md module rows (`OptionsUI`, `MinimapButton`, appearance settings), CHANGELOG Unreleased "Added: options window ...", README tables and both user guides (FR in French).
- [ ] **Step 3:** `sh tests/check.sh` green; authorship check; commit `docs: options window and minimap button`.
