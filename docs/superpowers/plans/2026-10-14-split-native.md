# Split UI/Native.lua (pure move, no behaviour change)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans.

**Goal:** Split `CraftProfit/UI/Native.lua` (about 1,250 lines) into focused files, as audit item B-I9 proposes (read it in `.superpowers/sdd/audit-B.md`, section I9, "Native.lua"). Every function stays reachable as `ns.Native.<name>`; callers, tests and behaviour do not change.

## Global Constraints

- Branch `refactor/split-native`; PR to `main`; **never merge**; the controller opens the PR. **No co-author line, no "Generated with" line** (`git log --format=%B main..HEAD | grep -ci "co-authored\|generated with"` = 0). Add files by name: `git -c core.fileMode=false add <files> &&`; chain with `&&`, never `;`. Never touch `Locales/esMX.lua` or `tests/fakewow.lua`.
- **Pure moves.** Do not rewrite, rename, reformat or "improve" any moved code or comment. The diff must be explainable as cut and paste plus the glue below. Verify: concatenating the new files' function bodies equals the old (e.g. compare `git diff --color-moved` / a script that checks each old top-level function appears unchanged in exactly one new file), and say how you checked.
- Files stay in TOC order (`CraftProfit.toc`, and wherever `tests/` or `.luacheckrc` list files: grep for `Native.lua`, update all, including docs: `docs/technical.md` file map, `README`/`CONTRIBUTING` if they list files). `tests/test_toc.lua` must pass.
- Private helpers shared across the new files (`applyAtlas`, `atlasInfo`, `rgbOf`, `try`, `tableOf`, `edgeLines`, …) are exposed as `Native._<name>` and the later files take them into locals at load (`local applyAtlas = ns.Native._applyAtlas`). Shared private state (registry, variants, constants) likewise through `Native.<name>` fields that already exist, or `Native._<name>`.
- Suggested cut (adjust to the real structure, keep each file under about 500 lines): `UI/NativeBase.lua` (helpers, window, button, check, input, listRow, forwardDrag, fitToScreen…), `UI/NativeCards.lua` (appearance variants and registry, panel, tile, banner), `UI/NativeScroll.lua` (scroll bar). `UI/Native.lua` may remain as the first file holding the namespace table and the shared helpers; choose the cleanest cut and say why.
- `sh tests/check.sh`: 866 passed, 0 failed, 0 luacheck warnings, before and after (the test count must not change). Docs English.

## Tasks

1. Split, update TOC / luacheck / tests lists, run the checks, commit ("Split Native.lua: ..."). One commit per new file is welcome.
2. Docs: `docs/technical.md` (file map and where each Native piece lives), CHANGELOG `Unreleased` > Changed ("UI/Native.lua split into ..., no behaviour change"). Commit, `git push -u origin refactor/split-native`. Do not open the PR.

Report back by message (no report files): status, commits, how you verified the move is pure, one-line test summary, concerns.
