# Remove the old Kit and the colour themes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete `ns.Kit` (`UI/Kit.lua`), `ns.Theme` (`Theme.lua`) and everything that only served colour themes, now that every window is on `ns.Native`. Keep the pure layout helpers in a new `ns.Layout` (`UI/Layout.lua`). No visible change for the player except that `/cp theme` is gone.

**Architecture:** Final step of `docs/superpowers/specs/2026-10-10-native-ui-design.md` ("Cleanup and docs"). Behaviour of every window must stay identical.

**Tech Stack:** Lua 5.1 (WoW Forever beta, Interface 16001), `sh tests/check.sh`, fake env `tests/fakewow.lua` (never edit).

## Global Constraints

- Same rules as the previous native plans (no image/font files, game fonts, taint rules, guards). No behaviour change in `Window`, `PinsUI`, `LevelingUI`, `OptionsUI`, `MinimapButton`, `Native`.
- Saved data: `settings.theme` of old saves must be ignored and dropped by `DB.lua` (the sanitiser deletes the key); nothing else in saves changes.
- `sh tests/check.sh`: 0 failed, 0 luacheck warnings; the number of tests will go down because tests of deleted code go away: for every deleted test say in the report whether its behaviour is covered elsewhere (pure helpers must keep their tests, moved to `tests/test_layout.lua`).
- Commits: no co-author line, no "Generated with" line (`git log --format=%B main..HEAD | grep -ci co-authored` is 0); commit locally only, the controller pushes and opens the PR. `git status --short` before committing: restore stray mode flips with `git checkout -- <file>` for files you did not change, never touch `CraftProfit/Locales/esMX.lua`. Docs in English (README.fr.md and docs/user-guide.fr.md in French).

## Review Focus

- Nothing in the TOC loads a deleted file; load order still valid (`Colors.lua` before anything using it, `UI/Layout.lua` before `UI/Native.lua`).
- No dangling reference to `ns.Kit`, `ns.Theme`, `Kit.`, `Theme.`, `L.THEME_*`, `themeLabel`, `cycleTheme`, `/cp theme` anywhere in code, tests, docs (grep).
- The pure helpers moved verbatim with their tests.
- Locale files stay in parity (enUS / frFR / esES) after removing the THEME_* keys.

---

### Task 1: Code and tests

**Files:** Create `CraftProfit/UI/Layout.lua`, `tests/test_layout.lua`; delete `CraftProfit/UI/Kit.lua`, `CraftProfit/Theme.lua`, `tests/test_kit.lua`, `tests/test_theme.lua`; modify `CraftProfit/CraftProfit.toc`, `CraftProfit/Boot.lua`, `CraftProfit/DB.lua`, `CraftProfit/Colors.lua`, `CraftProfit/UI/Native.lua`, `Window.lua`, `PinsUI.lua`, `LevelingUI.lua`, `OptionsUI.lua`, `KitDemo.lua`, `CraftProfit/Locales/*.lua` (not esMX), `.luacheckrc`, and the tests that mention them (`tests/test_boot.lua`, `test_colors.lua`, `test_db.lua`, `test_levelingui.lua`, `test_native.lua`, `test_pinsui.lua`, `test_window.lua`, others found by grep).

**Interfaces:**
- Produces: `ns.Layout` with the pure helpers still used by native code, same names and behaviour as in `Kit`: whichever of `panelHeight`, `stack`, `fitSize`, `scrollThumb`, `scrollOffsetAt`, `scrollGrab`, `colorEscape`, `mix`, `naturalWidth`, `gradient`... are still referenced after the migration (grep `Kit\.` first; move only what is used, delete the rest) plus the constants still referenced (`GAP`, `BODY_PAD`, `CONTENT_*`, `SCROLL_W`, `HEAD_H`, `TILE_SIZES`...). Native/Window/PinsUI/LevelingUI call `ns.Layout.x` where they called `ns.Kit.x`. `Colors.FIXED` replaces `Theme.FIXED` everywhere (colour values unchanged).
- Removed: `/cp theme`, `Controller.themeLabel/setTheme/cycleTheme/themeCommand`, the `Kit.applyTheme` call in `Controller.init`, `L.THEME_*` keys in all locales, `THEME_*` in `SLASH_HELP`, `DB.DEFAULTS.theme` and its sanitising (the sanitiser deletes a stale `theme` key), `KitDemo.showOld` and the `old` argument (the native demo stays), the `ns.Theme` references in `.luacheckrc`.

- [ ] **Step 1: Read** `Kit.lua` (what is pure vs. widgets), grep every use (`grep -rn "Kit\|Theme" CraftProfit tests`), the TOC, `Boot.lua` theme code, `DB.lua` sanitiser, `KitDemo.lua`.
- [ ] **Step 2:** create `UI/Layout.lua` + `tests/test_layout.lua` by moving the used pure helpers and their existing tests (rename the module in the tests; keep every assertion).
- [ ] **Step 3:** repoint callers, delete the files and dead code listed above, fix the TOC and `.luacheckrc`, update the tests that referenced removed things (delete only tests of removed behaviour; state each in the report).
- [ ] **Step 4:** `grep -rn "ns.Kit\|ns.Theme\|Kit\.\|Theme\.\|THEME_\|cycleTheme\|themeLabel" CraftProfit tests` returns nothing (report the output); `sh tests/check.sh` green.
- [ ] **Step 5: Commit** `refactor: remove the old Kit and the colour themes`.

---

### Task 2: Docs

**Files:** `README.md`, `README.fr.md` (commands tables: remove `/cp theme`), `docs/user-guide.md`, `docs/user-guide.fr.md` (remove the Themes sections/mentions; the options window replaces them), `docs/technical.md` (module table: remove Kit and Theme rows, add `Layout.lua`; remove the Kit/swatch/theme paragraphs; keep the native kit ones), `docs/in-game-checklist.md` (delete the obsolete "Themes (PR 4)" and old-look sections that no longer apply; keep the native ones), `CHANGELOG.md` (Unreleased: "Removed: `/cp theme` and the colour themes (replaced by the options window's look choices)"; drop the earlier Unreleased bullets that describe themes as a feature), `docs/superpowers/specs/2026-10-10-native-ui-design.md` (Delivery step 5 done), `docs/probe-findings.md` only if it mentions theme tooling.

- [ ] **Step 1:** grep docs for `theme`, `Theme`, `Kit`, `swatch`, `Copper`, `Steel` and fix each hit (history files under docs/superpowers/plans and old specs are left as they are).
- [ ] **Step 2:** `sh tests/check.sh` green; authorship check; commit `docs: remove the colour themes and the old kit`.
