# Audit batch 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the safe findings of the post-1.0.0 code audit (reports `.superpowers/sdd/audit-A.md` and `audit-B.md`, git-ignored but on disk: read the finding text there, it holds the file, line, reasoning and proposed fix of each ID). No visible change for the player except the fixes themselves. `v1.0.0` stays the fallback version.

**Architecture:** Three tasks, each with its own commits: (1) pure logic, history and data, (2) adapters and UI, (3) docs. Finding IDs below are prefixed by the audit letter: `A-B1` is audit A bug 1, `B-C3` is audit B cleanup 3.

**Tech Stack:** Lua 5.1 (WoW Forever beta, Interface 16001), `sh tests/check.sh`, fake env `tests/fakewow.lua` (never edit).

## Global Constraints

- Constraints of the earlier plans apply (`docs/superpowers/plans/2026-10-10-native-ui-foundations.md`, `...-pinned-window.md`): no image/font files, game fonts and `Colors`, taint rules (nil parent then `SetParent`, no hooks on Blizzard methods, guards with `type()`/`issecretvalue`), locale parity enUS/frFR/esES (never touch `esMX.lua`), pure files stay pure.
- Each fix gets a test that fails before and passes after (state in the report which). Cleanups keep behaviour identical: say how you checked (grep for dead code, test run).
- A finding you judge wrong, risky or not worth it: do NOT apply it; list it with your reason in the report.
- Out of scope (decided with the user, later): A-I1 / B-I1 evaluation context, B-B2 (main window reopening: needs an in-game measurement), B-B3 (re-evaluation on scroll), the Boot.lua / Native.lua split (B-I9), A-I2.., B-C5 and B-C7 (UI refactors that wait for the split), all nitpicks except file modes.
- Decisions taken by the user: (a) history keeps its tiers but each tier gets its own cap so a busy fortnight can never evict the daily and weekly tiers (fix A-B1 and A-B2 together in `History.compact`; existing saves must load unchanged and never lose points they currently keep, apart from the points the old cap would have dropped); (b) `/cp kitdemo` is REMOVED: delete `UI/KitDemo.lua`, its TOC entry, its slash branch, `Native` code used only by it (grep first; keep anything another file uses), its tests, its mentions in docs (technical.md, checklist, probe docs) and the `.luacheckrc` entries it alone needed; `/cp kitdemo` then prints the help line like any unknown command. Fixes B-B7.
- `sh tests/check.sh`: 0 failed, 0 luacheck warnings after every commit. Docs in English (README.fr.md and user-guide.fr.md in French). Commits: no co-author line, no "Generated with" line (`git log --format=%B main..HEAD | grep -ci co-authored` is 0); commit locally only, the controller pushes and opens the PR. The disk flips file modes by itself: `git status --short` before each commit, restore with `git checkout -- <file>` the files you did not change, never `git add -A` (add files by name), never touch `CraftProfit/Locales/esMX.lua`.

## Review Focus

- History: old saves load unchanged; a busy fortnight leaves the daily and weekly tiers intact; future-dated points are dropped or clamped as the audit proposes and `History.record`'s returned count is true; retention numbers in docs match the code.
- `"nodata"` status: a disenchant gap shows a clear "no data" state, never "PRICES MISSING"; recipes without a disenchant need keep their old behaviour; en/fr/es strings with parity.
- Deleting KitDemo leaves no dangling reference (TOC, slash help, tests, docs, luacheck globals).
- Guards: nothing that used to work now returns nil.

---

### Task 1: Logic, history, data

**Files:** per the audit: `CraftProfit/History.lua`, `Present.lua`, `Evaluate.lua`, `Core.lua`, `DB.lua`, `Recipes.lua`, `Util.lua`, `UI/Layout.lua`, `Locales/*.lua`, `Data/*.lua` comments, tests.

- [ ] Apply: A-B1 and A-B2 (with decision (a)), A-B3 (the `"nodata"` status: add the status end to end: Evaluate/Present/banner text; do NOT invent new disenchant rows), A-B4, A-B5 (Spanish label), A-B6 (amount bounds), A-C1..A-C12, plus A's test-hygiene item C11 (ordered specifiers in `test_locale` and the wrong-reason tests) and the file-mode nitpick if it needs a note in CONTRIBUTING. Skip A-C9/A-C10 if you judge the refactor too invasive for a no-behaviour-change batch, and say so.
- [ ] `sh tests/check.sh` green; commits by theme (history; nodata; locale; cleanups).

### Task 2: Adapters and UI

**Files:** per the audit: `LevelingUI.lua`, `PinsUI.lua`, `PinnedWindow.lua`, `Window.lua`, `OptionsUI.lua`, `Native.lua`, `AHAdapter.lua`, `TradeAdapter.lua`, `Boot.lua`, `UI/KitDemo.lua` (deleted), TOC, `.luacheckrc`, tests.

- [ ] Apply: B-B1 (leveling position), B-B4 (secret/pcall guards in `Controller.itemInfo` and `Trade.readA`; difficulty used as a table key must be a known string), B-B5 (quantity preset cleared when the AH closes), B-B6 (a scan read error cannot leave `reading = true`: pcall the chunk step and reset), B-B7 (KitDemo removal, decision (b)), B-C1 (skip evaluation of the hidden pins list; the list refreshes when shown), B-C2..B-C4, B-C6, B-C8..B-C12, B-C14, B-C15. Skip B-C5, B-C7, B-C13 (out of scope above).
- [ ] `sh tests/check.sh` green; commits by theme.

### Task 3: Docs

**Files:** `docs/technical.md` (history retention tiers and caps, `nodata`, KitDemo gone, drift items A-C7), `docs/in-game-checklist.md` (add: leveling window position survives close/reopen; a disenchant-gap recipe shows "no data"; `/cp kitdemo` prints the help; remove KitDemo sections), `CHANGELOG.md` (`## [Unreleased]` with Fixed / Changed / Removed), `README*.md`, user guides EN/FR and `docs/curseforge/project-page.md` only where they mention retention or kitdemo; `docs/probe-findings.md`: add the search-trace measurements of 2026-10-11 to F13 (from the probe log: events per search, results at first event, ~0.2-0.4 s from send to answer, "ready" about 0.4 s after the answer, COMMODITY events arrive twice with the same rows, one genuine empty result for an unsold item).

- [ ] Docs truth pass on what changed; `sh tests/check.sh` green; commit `docs: audit batch 1`.
