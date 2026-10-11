# Refresh actions and a clearer search status Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three clear ways to update prices at the auction house: **Refresh recipe** (only the items of the recipe on screen, about 10-15 s), **Refresh pinned** (what "Search prices" does today for all pinned recipes) and **Scan AH** (unchanged), plus a search status line that says what happened instead of "15 not found".

**Architecture:** `PinsUI.startSearch(recipes)` takes an optional list of recipes (nil = every pinned recipe, as now); `Controller.refreshRecipe()` calls it with the displayed recipe. The same `PriceQueue`, `ctl.recordListings`, `ctl.commitSearch` and history recording are used. The summary text comes from one pure function `PinsUI.searchSummary(L, counts)` fed by the queue summary (`ok`, `failed`) and the count of items that answered with no listing.

**Tech Stack:** Lua 5.1 (WoW Forever beta, Interface 16001), `sh tests/check.sh`, fake env `tests/fakewow.lua` (never edit).

## Global Constraints

- All constraints of the earlier native plans apply (`docs/superpowers/plans/2026-10-10-native-ui-foundations.md`, `...-options-window.md`, `...-pinned-window.md`, `...-pin-limit.md`): no image/font files, game fonts and `Colors`, taint rules, guards with `type(x)`, buttons are `Native.button` (22 px), strings through `ns.L` in `Locales/enUS.lua`, `frFR.lua`, `esES.lua` with parity (never touch `esMX.lua`), every label measured against its button width with `Layout.textWidth` (the existing width tests), no dropdown/Menu API.
- Behaviour that must not change: the queue (sequential, 6 s timeout, throttle abandon), cancelling when the AH closes, `commitSearch`, history recording, Scan AH and its cooldown messages, the status line position (under the pinned list, in `pinsHost`).
- Names (en / fr / es): `SEARCH_PRICES` "Search prices" becomes **"Refresh pinned"** / "Actualiser les épinglées" / "Actualizar fijadas" (shorten if the width test says it does not fit the half-width footer button, e.g. FR "Actualiser épinglées", and say so in the report); new `REFRESH_RECIPE` **"Refresh recipe"** / "Actualiser la recette" / "Actualizar receta". Docs and tooltips use the new names everywhere ("Search prices" must not remain in user-facing text; history docs/plans keep theirs).
- The "Refresh recipe" button sits in the Options panel of the main window on the row of the Pin/Unpin button (both buttons share the row width equally, gap 6; adjust `OPTION` row maths and the window height if needed). It is enabled only while the AH is open (`ns.AH.isOpen`) and a recipe is displayed, disabled (greyed, no click) otherwise; it updates when the AH opens or closes and on every render. A click while a search runs is ignored (as `startSearch` does today); a click with the AH closed prints `L.SEARCH_NEED_AH` in chat.
- Search items of one recipe: `PinsUI.wantedFor({ recipe }, ...)` (same items as for pins: reagents, output, disenchant materials when relevant).
- Status texts (replace `SEARCH_DONE` / `SEARCH_PARTIAL`): when everything answered with listings: "Updated %d items" ; otherwise "Updated %d of %d items" followed by " · %d have no listing (nobody is selling them now)" when n>0 and " · %d did not answer, try again" when m>0 (middle dot like the banner's separator, exact characters through one format key per fragment so FR/ES can be translated naturally; plural handled by wording that works for 1 too: "no listing" / "did not answer"). A cancelled search keeps `SEARCH_CANCELLED`. The count "ok" = items whose search returned (with or without listings); "no listing" = answered with an empty list; "did not answer" = `summary.failed` items.
- `sh tests/check.sh`: 0 failed, 0 luacheck warnings. Docs in English (README.fr.md and user-guide.fr.md in French). Commits: no co-author line, no "Generated with" line (`git log --format=%B main..HEAD | grep -ci co-authored` is 0); commit locally only, the controller pushes and opens the PR. `git status --short` before committing: restore stray mode flips with `git checkout -- <file>`; never touch `Locales/esMX.lua`.

## Review Focus

- A recipe refresh never cancels or corrupts a running pinned refresh (ignored while running), and a pinned refresh started right after a recipe refresh starts clean (notFound counter reset).
- The Refresh recipe button state is right in every case: AH closed, no recipe (empty window), search running, AH closed mid-search.
- The status line counts add up (ok + no answer = total) in every combination, including 0 items to search.
- Button labels fit in en/fr/es; the Options panel row and the window height are consistent.

---

### Task 1: Search with an optional recipe list, the summary, the new button

**Files:** `CraftProfit/UI/PinsUI.lua`, `CraftProfit/UI/Window.lua`, `CraftProfit/Boot.lua`, `Locales/enUS.lua`, `frFR.lua`, `esES.lua`; tests `tests/test_pinsui.lua`, `tests/test_window.lua`, `tests/test_boot.lua`.

- [ ] **Step 1: Read** `PinsUI.lua` (`wantedFor`, `startSearch`, `finishSearch`, status), `Window.lua` (Options panel, pin button, `handlers`, `showSearchIcons` for AH-open handling), `Boot.lua` (`Controller.init` handler table, `refresh`, `togglePin`, AH open/close events), the locale files, the tests of these modules.
- [ ] **Step 2: Failing tests**, then implement per the constraints.
- [ ] **Step 3: `sh tests/check.sh`** green. **Step 4: Commit** `feat: refresh recipe, refresh pinned and a clearer search status`.

### Task 2: Docs

**Files:** `docs/in-game-checklist.md`, `docs/technical.md`, `CHANGELOG.md` (Unreleased), `README.md`, `README.fr.md`, `docs/user-guide.md`, `docs/user-guide.fr.md`, `docs/curseforge/project-page.md`, the options note mentioning "Search prices" in the three locales if it still says so (and its test).

- [ ] **Step 1:** replace the old name everywhere user-facing, document the three levels (recipe: seconds; pinned: about a minute for 20 recipes; scan: one full scan, server cooldown) and the new status texts; checklist section "Refresh actions" (button enabled only at the AH; recipe refresh updates only that recipe's prices; pinned refresh; summary lines with 0, some, and all-missing items; AH closed mid-search).
- [ ] **Step 2:** `sh tests/check.sh` green; authorship check; commit `docs: refresh actions and search status`.
