# Audit batch 2 Implementation Plan (behaviour fixes and refresh cost)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans.

**Goal:** Apply the audit findings left for batch 2, except the Boot.lua / Native.lua split (its own plan and PR afterwards). The audit reports are `.superpowers/sdd/audit-A.md` and `audit-B.md` (git-ignored, on disk): **read the full text of each ID below there** (file, lines, reasoning, proposed fix). Line numbers are from before the price history work: re-find the code by name.

## Global Constraints

- Branch `fix/audit-batch-2`; PR to `main`; **never merge**. **No co-author line, no "Generated with" line, ever** (`git log --format=%B main..HEAD | grep -ci "co-authored\|generated with"` must be 0). Add files by name: `git -c core.fileMode=false add <files> &&`; chain with `&&`, never `;`.
- Never touch `CraftProfit/Locales/esMX.lua` or `tests/fakewow.lua` (stub inside your own test if needed). Native game look only; no StaticPopup, no Menu API, no hooks on Blizzard methods, no chat messages at login. Locale keys with en/fr/es parity, native FR/ES. Docs English (README.fr.md and docs/user-guide.fr.md French).
- Each fix gets a test that fails before and passes after (say which in your report). `sh tests/check.sh`: 0 failed, 0 luacheck warnings after every commit. Behaviour that is not the finding must not change; a finding you judge wrong or risky: do NOT apply it, say why.
- Never evaluate less than before for a *visible* list: only hidden lists and unchanged scroll positions skip work. The History window, its cache (`Controller.historyChanged`, keyed caches) and the new main window indicators (`Controller.windowHistory`) must keep working.

## Decisions (taken)

1. **B2** exactly as the audit proposes (refresh data only when the profession window re-reports the id that is already current with source "profession"; a "pin" source selection stays unless the *profession* id differs from `lastProfessionID`; a window the player closed stays closed; a *new* selection still opens it). In-game check goes to the checklist.
2. **B3** (list scroll re-evaluation): in `LevelingUI`, `PinnedWindow`, `PinsUI` keep the last data; scroll repaints rows only; no work when the offset did not change. (History window already does this: reuse its pattern.)
3. **C1** (hidden `PinsUI` list is not evaluated; relayout kept in `onAHOpen`).
4. **I1** one evaluation context per refresh pass (market, priceOf, knowsEnchanting, settings, itemInfo memo), plus memoised `evaluate(recipe, crafts)` per pass. The context is built at the start of `Controller.refresh` / `levelData` / `pinsData` and dropped at the end; nothing is cached across passes (no invalidation risk).
5. **I2**: while a price search runs (`PinsUI.state == "running"` or the equivalent for any queue), coalesce `requestRefresh` to about 1 s instead of 0.1 s; the final refresh at the end of the search is immediate. The live value still updates, less often.
6. **A-I2** (cost per point with an unknown resale): carry `perPoint.incomplete = result.incomplete` and show it in the leveling list with the addon's existing "incomplete" marking (look at how incomplete totals are shown elsewhere; add a locale key only if needed).
7. **Stale indicator** (found after step 4): the main window's history percentages and the History list can stay shown past 24 h until some refresh. Schedule one `requestRefresh` at the cache's `expires` time (one timer, replaced when the cache recomputes, none when nothing expires), so a stale percentage disappears by itself. Test with the fake clock.

## Tasks

### Task 1: B2, A-I2, stale indicator (behaviour)
Files: `CraftProfit/Boot.lua`, `TradeAdapter.lua`, `Evaluate.lua`/`Core.lua`, `UI/LevelingUI.lua`, locales if needed, tests.

### Task 2: B3, C1, I1, I2 (refresh cost)
Files: `Boot.lua`, `UI/LevelingUI.lua`, `UI/PinnedWindow.lua`, `UI/PinsUI.lua`, tests. Add tests that count evaluations: scroll = 0 evaluations; hidden pins list = 0; one refresh with N pins calls the market/enchanting lookups once, not N times.

### Task 3: Docs
`docs/technical.md` (refresh pass context, scroll, search coalescing, B2 rule), `docs/in-game-checklist.md` (B2: close the main window with X, craft or change filter in the profession window: it stays closed; pick a pin, then craft: the pin stays; pick a new recipe in the profession window: it opens; scrolling the leveling/pinned lists is smooth; a percentage disappears 24 h after the last measurement), `CHANGELOG.md` (Unreleased: Fixed/Changed), docs/superpowers/specs if they describe these behaviours. Finish: `sh tests/check.sh`, commit per theme, `git push -u origin fix/audit-batch-2`, do not open the PR (the controller does).

Report back by message (you cannot write report files): status, commits, one-line test summary, findings not applied with reasons, concerns.
