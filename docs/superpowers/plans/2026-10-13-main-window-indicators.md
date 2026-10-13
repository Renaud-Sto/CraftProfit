# Main window history indicators Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans.

**Goal:** Price history step 4: small coloured "today vs usual" percentages in the main window, next to the Materials total and on the AH (net) tile, for tracked recipes only.

**Spec:** `docs/superpowers/specs/2026-10-11-price-history-design.md`, decision 4 (the wording "arrow" there: see Decision 1 below).

## Global Constraints

- Branch `feat/main-window-indicators`; PR to `main`; **never merge**. **No co-author line, no "Generated with" line, ever.** Add files by name: `git -c core.fileMode=false add <files> &&`; chain with `&&` (never `;`).
- Never touch `CraftProfit/Locales/esMX.lua` or `tests/fakewow.lua` (stub inside your own test if the fake lacks something).
- Native game look; no StaticPopup, no Menu/dropdown API, no hooks on Blizzard methods, no chat messages. Docs in English (README.fr.md, docs/user-guide.fr.md in French). Locale keys en/fr/es with parity, native-quality FR/ES.
- `sh tests/check.sh` green, 0 luacheck warnings. Tests first for pure code. Window must not get taller or wider; nothing may overlap in fr/es.
- Reuse, do not duplicate: `Controller.historyList()` entries (`indicator`, `atLoss`, `fresh`, `active`), `HistoryWindow`'s `paintColumn` semantics (same colours: green good, red bad, grey flat, grey when `atLoss`; stale data never shown). Extract the shared colour/percent formatting into one small helper (e.g. in `HistoryView` or `Present`) used by both windows instead of copying it.

## Decisions

1. **Percent text, no arrow glyph.** The game fonts may lack arrow glyphs: show the signed percentage ("-18%", "+12%", "0%") in colour, as the History list does. Colours as the list: materials lower = green, sale/net higher = green, opposite red, flat (±3 %) grey; grey for both when the recipe is at a loss (`atLoss`).
2. **Where.** Materials: right end of the Materials panel header (beside the total). AH tile (the tile that is the net result of selling at the auction house): small text in the tile, on the sale percentage (`indicator.sale`). Other tiles (vendor, disenchant) get nothing. Only for tracked, **active** recipes with `indicator` present (fresh, <24 h, enough data); otherwise nothing is drawn (no placeholder, no layout change).
3. **Tooltip** on hover over each indicator (own small hit frame, forwards drag to the window with `Native.forwardDrag`, never swallows the tile/header click): Materials: "Materials today: X, usual: Y, lowest: Z, highest: W, N measurements over D days" (money formatted like the rest of the addon); Sale likewise for the crafted item's price. Data from `Controller.historyData(recipeID, "materials"|"sale", 30)` (cached). Lines in locale keys en/fr/es. A tooltip line "at a loss or break even: shown in grey" when `atLoss`.
4. **Wiring.** `Controller` builds `model.history = { materials = ind.materials, sale = ind.sale, atLoss = ... , recipeID = ... }` (or nil) in the path that renders the main window (find how `Present`/`Window.render` get their model) from the `historyList` cache; the main window repaints when history changes (`Controller.historyChanged` bumps already invalidate the cache; make sure a new measurement or a track/untrack/pause redraws the indicators without an extra refresh storm).
5. **Failure safety.** A bad/missing indicator table, NaN, or a missing Native API must never raise: indicators silently absent.

## Task 1: Data + shared formatting (tests first)

Files: `CraftProfit/Boot.lua`, `CraftProfit/Present.lua` or `CraftProfit/HistoryView.lua`, tests (`tests/test_present.lua`, `tests/test_historydata.lua` or the file that covers the model). Produce `model.history` and the shared percent/colour helper; refactor `HistoryWindow.paintColumn` to use the helper without changing its output (its tests must stay green).

## Task 2: Main window widgets + tooltips + locales

Files: `CraftProfit/UI/Window.lua`, `Locales/enUS.lua|frFR.lua|esES.lua`, `tests/test_window.lua`. Indicators in the Materials header and the AH tile, tooltip, repaint on render. Tests: shown only when tracked+active+fresh, hidden otherwise (paused, stale, untracked, no data), grey at a loss, tooltip text, drag still forwarded, click on the tile/header unchanged.

## Task 3: Docs

`docs/technical.md`, `docs/user-guide.md` and `.fr.md`, `docs/in-game-checklist.md` (new items to check in game), `CHANGELOG.md` (Unreleased), README(.fr) if the feature list mentions history, `docs/curseforge/project-page.md` wording, spec: mark decision 4 as "percentages without arrow glyphs". Finish: `sh tests/check.sh`, commit, `git push -u origin feat/main-window-indicators`, open PR (title "Price history step 4: indicators in the main window", no attribution lines in the body).

Report back by message: status, commits, one-line test summary, concerns (you cannot write report files).
