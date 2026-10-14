# Split Boot.lua (pure moves, no behaviour change)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans.

**Goal:** Split `CraftProfit/Boot.lua` (about 1,470 lines, eight responsibilities) into focused files, audit item B-I9 ("Boot.lua" table in `.superpowers/sdd/audit-B.md`, section I9; line numbers there are outdated, the price history work added about 600 lines). Functions stay on `ns.Controller` under the same names; callers, tests and behaviour do not change. The `Native.lua` split (done, PR #31, see `docs/superpowers/plans/2026-10-14-split-native.md` and how it handled shared private helpers) is the model: pure cut and paste plus minimal glue.

## Global Constraints

- Branch `refactor/split-boot`; PR to `main`; **never merge**; the controller opens the PR. **No co-author line, no "Generated with" line** (`git log --format=%B main..HEAD | grep -ci "co-authored\|generated with"` = 0). Add files by name: `git -c core.fileMode=false add <files> &&`; chain with `&&`, never `;`. Never touch `Locales/esMX.lua` or `tests/fakewow.lua`.
- **Pure moves.** Do not rewrite, rename, reformat or improve moved code or comments. Verify with a script: every top-level block (function, local function, constant) of the old `Boot.lua` appears byte-identical in exactly one new file, and nothing else is in the new files except glue (headers, `local x = Controller._x` imports, exports). Say how you checked.
- **Load order and shared locals.** Files load in TOC order before the event frame is created. `Controller` is created by the first file (`ns.Controller = ns.Controller or {}`; check how tests and `ns.Controller` get it today) and every file starts `local Controller = ns.Controller`. All cross-file calls happen at runtime (inside functions), never at load, except constants. A `local function` that is used by two files (`choose`, `refreshAll`, `mainPosition`, `seriesReader`, `freshness`, `onSelection`, `state`, `requestedItems`, `isSecret`, `plain`...) is exposed as `Controller._<name>` (state through `Controller._state` table, which is the same table, not a copy) and imported with a local at the top of the other file **only if it is not reassigned**; otherwise call through `Controller._<name>` at use. Prefer a cut that minimises shared locals.
- Suggested cut (adjust to the real dependencies, files under about 500 lines): `Controller/Facts.lua` (say, fmt, marketKey, market, inPass, itemInfo/itemIcon/itemName, recipeName, professionName, knowsEnchanting, requestedItems), `Controller/Core.lua` (state, evaluate, choose, setCrafts, refresh/requestRefresh, setRecipe, selectPin, show/hide/toggle main window, besidePosition/mainPosition, onSelection, onAHOpen, reagent/output clicks), `Controller/Settings.lua` (appearance, pin limit, minimap, saved positions, sort modes), `Controller/Leveling.lua`, `Controller/Pins.lua` (togglePin, unpin, pinsData, refreshRecipe, searches, recordListings, commitSearch, recordHistory, onSnapshot), `Controller/History.lua` (historyItems.., freshness, caches, historyList/historyData/windowHistory, delete/pause/tracking, historyCommand), and `Boot.lua` keeps selftest, init, onEvent, slash, compartment function, event frame. If a different cut is cleaner, say why.
- Update every list of files: `CraftProfit.toc` (new files before `Boot.lua`, after the UI files only if they need none at load; check), `.luacheckrc` if it lists files, tests that load files by name (grep `Boot.lua`), `.pkgmeta`, docs (`docs/technical.md` file map, README/CONTRIBUTING), CHANGELOG Unreleased > Changed.
- `sh tests/check.sh`: 866 passed, 0 failed, 0 luacheck warnings, before and after; test count unchanged. Commit per extracted file, tests green at each commit. Docs English.

## Tasks

1. Extract files one by one (Facts, then History, then Settings, Leveling, Pins, Core), committing each.
2. Docs and CHANGELOG, `git push -u origin refactor/split-boot`. Do not open the PR.

Report back by message (no report files): status, commits, how purity was verified, test summary, concerns (especially anything only the real client can show: load order).
