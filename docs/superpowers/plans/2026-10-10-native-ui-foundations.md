# Native UI foundations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `ns.Native` (`UI/Native.lua`), a widget kit built on Blizzard's own templates and atlases, plus a native `/cp kitdemo [a|b|c]` window used as the visual checkpoint. Nothing existing changes behaviour.

**Architecture:** A new module beside the old `ns.Kit`; same shape of API (`window`, `panel`, `tile`, `button`, `check`, `input`) so steps 2-3 migrate the real windows with few edits. Pure layout maths stays in `ns.Kit` for now (`Kit.panelHeight`, `Kit.stack`, `Kit.fitSize`); `Native` may call them. Native frames are checked in game only; unit tests cover layout arithmetic, fields, guards and click wiring in the fake game environment (`tests/fakewow.lua`, never edit it).

**Tech Stack:** Lua 5.1 (WoW Forever beta, Interface 16001, Retail Mainline 12.1.5 base), tests `sh tests/check.sh` (luajit + luacheck).

**Spec:** `docs/superpowers/specs/2026-10-10-native-ui-design.md` (read it first). Blizzard's source for the client is cloned at `.cache/wow-ui-source/Interface/AddOns/` (branch `forever`, build 70291; git-ignored): read the template XML and the `Camelot/` overrides there instead of guessing. Reference of what works in game: `probe/CraftProfitProbe/Native.lua` (the `/cppn` showcase) and `docs/superpowers/specs/2026-10-10-native-ui-design.md` "Findings".

## Global Constraints

- No file other than Lua/TOC/docs is added; never a `.tga`, `.blp`, `.ttf`, `.png` in `CraftProfit/`. Images only through atlas names (`SetAtlas(name, true)` after testing `C_Texture.GetAtlasInfo(name)`) or the game files `Interface\FrameGeneral\UI-Background-Rock|Marble`, `Interface\QuestFrame\UI-QuestTitleHighlight`.
- Fonts: only `GameFont*`, `NumberFont*`, `QuestFont*` objects, never `SetFont` with a path. Colours: use the game's globals (`NORMAL_FONT_COLOR`, `HIGHLIGHT_FONT_COLOR`, `DISABLED_FONT_COLOR`, `GREEN_FONT_COLOR`, `RED_FONT_COLOR`) with `:GetRGBA()` / `:GetRGB()` wrapped in a guard (the fake env returns no-ops), no hand-written hex for chrome.
- Taint rules (SO-6 field notes): never hook methods of Blizzard objects (`hooksecurefunc` on a frame method), never write into Blizzard tables or globals, no `UIPanelWindows` (Escape = a named frame in `UISpecialFrames`), no `StaticPopup_Show`, no dropdown/`Menu` API, no `Secure*` template. A Blizzard-templated frame that would be created under an open Blizzard panel is created with a nil parent then `SetParent`.
- A click area that is not a `Button`/`EditBox` is read by the gamepad code through `GetScript`: every clickable thing is a `Button`.
- Frames created from XML templates start shown and unanchored: hide them, anchor them. Use `HookScript` for OnEnter/OnLeave on templated widgets, never replace their scripts (`SetScript`) unless the plan says so.
- Every use of a template internal (`frame.Inset`, `frame.TitleContainer`, `frame.CloseButton`, `frame:SetTitle`, `ButtonFrameTemplate_HidePortrait`, `_HideButtonBar`, `button.Text`, `check.Text`) is guarded (`if x then`) with a plain fallback, so a changed build never raises.
- Test files: `tests/test_native.lua` (new). Lua style of the surrounding code (4 spaces, comments explain why). `sh tests/check.sh` must end with 0 failed and 0 luacheck warnings. Docs in English. Commits: no co-author line, no "Generated with" line; verify `git log --format=%B main..HEAD | grep -ci co-authored` is 0. Commit locally only: the controller pushes and opens the PR.
- Some Lua files flip to mode 755 by themselves: before committing run `git status --short`; `chmod 644` any Lua file you did not mean to change and do not commit it; never touch `CraftProfit/Locales/esMX.lua`.

## Review Focus

- A template whose internals are missing in the fake env or on a changed build: window creation must not raise (guards, fallbacks).
- `Native.window` frame levels: title hit button above the title bar but below the close button; inset content never covers the close button.
- A button label too long for its fixed width: the font string must not overflow (truncate, no wrap).
- Clicking a check box label toggles it; Enter/Escape in the input release the focus; a disabled button does not fire `onClick`.
- Drag: the window moves from its title bar and body; a click on the title hit button that ended a drag does not fire `onTitleClick`.

---

### Task 1: Native window, button, check, input

**Files:**
- Create: `CraftProfit/UI/Native.lua` (module `ns.Native`)
- Create: `tests/test_native.lua`
- Modify: `CraftProfit/CraftProfit.toc` (add `UI/Native.lua` after `UI/Kit.lua`)

**Interfaces:**
- Consumes: `ns.Kit` pure helpers (optional), `ns.Colors` does not exist yet (do not create it).
- Produces (used by Task 2, Task 3 and steps 2-3):
  - `Native.window(name, title, opts)` -> frame. `opts`: `width`, `height`, `onMoved(point, x, y)`, `onTitleClick()`. Frame fields: `.content` (the usable area: `frame.Inset` when it exists, else the frame itself), `.titleHit` (a `Button` over the title bar, present only when `opts.onTitleClick` is set), `.titleIcon` (texture, magnifier, present with `titleHit`), `:setTitle(text)`, `.stopDrag(frame)`. The frame is created with `CreateFrame("Frame", name, nil, "ButtonFrameTemplate")` then `SetParent(UIParent)`; portrait hidden (`ButtonFrameTemplate_HidePortrait`), button bar hidden (`ButtonFrameTemplate_HideButtonBar`), strata `MEDIUM`, clamped, movable, drag from the whole frame, `Escape` NOT registered here (callers decide), starts hidden and unanchored (caller anchors and shows). `Native.CONTENT_PAD = 4` (gap between `.content` edge and what callers place).
  - `Native.button(parent, text, opts)` -> `UIPanelButtonTemplate` button, 22 px high, `opts.width`, `opts.onClick`; label never wraps; `:setText(text)`.
  - `Native.check(parent, text, onToggle)` -> `UICheckButtonTemplate`, label to the right, clicking the label toggles, `onToggle(checked)` after a user click, plays `SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON/_OFF` when `PlaySound` and `SOUNDKIT` exist; methods `SetChecked`, `GetChecked`, `setText`.
  - `Native.input(parent, width, maxLetters)` -> `InputBoxTemplate` edit box, 22 px high, no auto focus, Enter and Escape clear focus.
  - `Native.searchIcon(texture)`: atlas `common-search-magnifyingglass` when `C_Texture.GetAtlasInfo` knows it, else the file icon used by `Kit.searchIcon` (read it in `Kit.lua` and reuse its fallback).

- [ ] **Step 1: Read first.** `CraftProfit/UI/Kit.lua` (window, button, check, input, forwardDrag, searchIcon: the behaviours to keep), `tests/fakewow.lua`, `tests/harness.lua`, `tests/test_kit.lua` (test style), `.cache/wow-ui-source/Interface/AddOns/Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml` and `.lua` plus `Camelot/SharedUIPanelTemplates.lua` (what `ButtonFrameTemplate_HidePortrait` / `_HideButtonBar` do, where `Inset`, `TitleContainer`, `CloseButton` are, the title bar height), `UIPanelButtonTemplate` and `UICheckButtonTemplate` (`.Text` key), `InputBoxTemplate`. Write down in the report the exact inset anchors after hiding the button bar and portrait.

- [ ] **Step 2: Write failing tests** in `tests/test_native.lua` (load with `H.newNS("Theme", "UI/Kit", "UI/Native")` like `test_kit.lua`). Cover with the fake env: `Native.window` returns a frame with `content`, `setTitle` and `stopDrag`, is hidden and does not raise when `ButtonFrameTemplate_HidePortrait` is absent; `titleHit` exists only with `onTitleClick`, a click fires it, a click right after a drag does not (`dragged` flag like `Kit.forwardDrag`); `Native.button` fires `onClick`, not when disabled, `setText` updates; `Native.check` toggles on label click and calls `onToggle` with the new state; `Native.input` Enter/Escape call `ClearFocus`. Use `rawget` / `== true` checks where the fake returns no-ops for missing keys.

- [ ] **Step 3: Run them to see them fail** (`luajit tests/run.lua`), then implement `UI/Native.lua` to make them pass. Keep it small and commented with the why (taint, shown-by-default, guards).

- [ ] **Step 4: Full check.** `sh tests/check.sh` -> 0 failed, 0 warnings.

- [ ] **Step 5: Commit** `git add CraftProfit/UI/Native.lua CraftProfit/CraftProfit.toc tests/test_native.lua && git commit -m "feat: native window, button, check box and input on Blizzard templates"`.

---

### Task 2: Native panel and tile

**Files:**
- Modify: `CraftProfit/UI/Native.lua`
- Modify: `tests/test_native.lua`

**Interfaces:**
- Consumes: Task 1 (`Native.window` content area, `Native.CONTENT_PAD`), `Kit.panelHeight`, `Kit.stack`.
- Produces:
  - `Native.HEADER_VARIANTS = { a = "questlog-reward-header-top", b = "friends-frame-toptexbg", c = "_UI-Frame-TopTileStreaks" }` and `Native.setHeaderVariant(key)` / `Native.headerVariant` (default `"a"`): the atlas used for panel header strips; unknown key keeps the current one. A panel built after a switch uses the new atlas (the demo rebuilds).
  - `Native.TILE_VARIANTS = { a = "looting_itemcard_bg", b = "inset" }`, `Native.setTileVariant(key)` / `Native.tileVariant` (default `"a"`): `a` draws the tile on the `looting_itemcard_bg` atlas with `looting_itemcard_stroke_normal` as the best-tile outline; `b` draws it on a nested `InsetFrameTemplate` with a gold (`NORMAL_FONT_COLOR`) 2 px outline for best.
  - `Native.panel(parent, title)` -> table `p` with the same fields as `Kit.panel`: `.frame`, `.body`, `.title`, `.right`, methods `:setTitle`, `:setRows(rows, rowH, extra)`, `:height()`, `:onHeaderClick(fn)`. Header strip from the current header atlas (when the atlas is unknown to the client: a flat `DefaultPanel`-like dark strip via `SetColorTexture` of `NORMAL_FONT_COLOR` at alpha 0.15 is the fallback); title `GameFontNormal`, right text `GameFontHighlightSmall`; a divider (`perks-divider-short` atlas, fallback none) under the header; header height `Native.HEAD_H = 22`; panel background: a nested `InsetFrameTemplate` (created with the panel frame as parent).
  - `Native.tile(parent, width, height)` -> table with `.frame`, `.label`, `.value`, `:set(spec)` with spec `{ label, tag, value, best, muted }` (same as `Kit.tile`), `onClick(fn)` making the tile a `Button` hit area, `showIcon(bool)` showing the magnifier (`Native.searchIcon`) at the top right, `.hit`, `.icon`. Value font fitted with `Kit.fitSize` and `Kit.TILE_SIZES` over the natural width (measure with an unbounded font string like `Kit.naturalWidth`, read it in `Kit.lua`). `muted` greys the value with `DISABLED_FONT_COLOR`.

- [ ] **Step 1: Read** `Kit.panel`, `Kit.tile` and `tests/test_kit.lua`'s panel/tile tests to keep their semantics (row heights, stack gap 8, header click reusing the hit, tile click, icon visibility).
- [ ] **Step 2: Write failing tests** for: `panelHeight` parity (`p:height()` equals `Kit.panelHeight(rows,rowH,extra)` when expanded), `setRows`, `onHeaderClick` fires and the header hit is a `Button`, header variant switching (a panel built after `setHeaderVariant("b")` asked the texture for atlas `friends-frame-toptexbg`: record it by wrapping `C_Texture`/texture `SetAtlas` in the fake test env, or by exposing `p.headerAtlas` for the test), unknown key ignored, atlas missing -> fallback does not raise, tile `set` fills label/value/tag, `best` flips the outline, `muted`, `onClick`, `showIcon`.
- [ ] **Step 3: Run, see failing, implement, make pass.**
- [ ] **Step 4: `sh tests/check.sh`** 0 failed, 0 warnings.
- [ ] **Step 5: Commit** `feat: native panel and tile with switchable header and tile variants`.

---

### Task 3: Native `/cp kitdemo` and docs

**Files:**
- Modify: `CraftProfit/UI/KitDemo.lua`, `CraftProfit/Boot.lua` (only the `kitdemo` branch of the slash handler), `docs/technical.md`, `docs/in-game-checklist.md`, `docs/probe-findings.md`, `CHANGELOG.md`
- Test: `tests/test_boot.lua` (the existing kitdemo test, adapt) and `tests/test_native.lua` if useful

**Interfaces:**
- Consumes: Tasks 1-2.
- Produces: `/cp kitdemo [header [tile]]` where `header` is `a|b|c` and `tile` is `a|b` (`/cp kitdemo b a`); no argument = the last used, default `a a`. The demo rebuilds its window with those variants and prints the current choice to chat in English. `/cp kitdemo old [theme]` keeps the previous themed demo (move the existing build into `KitDemo.showOld(theme)`). The native demo window shows, on `Native.window("CraftProfitNativeDemo", "Native demo", { width = 372, onTitleClick = function() print("title clicked") end })`: three tiles (best, plain, muted/beta with a long amount like `999g 99s 99c`), a MATERIALS panel with 3 rows and a right-hand total, an OPTIONS panel with a crafts input, a check box and two buttons (one disabled), a sort button in a panel header (native button 20 px), and one line of text in `GameFontHighlight` with `GetCoinTextureString`/`GetMoneyString` money (guard: result must be a string, else plain `21g 29s`). Escape closes it (name in `UISpecialFrames` inside KitDemo only).

- [ ] **Step 1:** implement the demo; keep it English-only and out of the user help (as today).
- [ ] **Step 2:** adapt the boot test for `/cp kitdemo` (shows a window, argument parsing `a b`, unknown argument keeps defaults and prints one line, `old` still works).
- [ ] **Step 3:** docs. `docs/technical.md`: add `UI/Native.lua` to the module table (what it is, that it coexists with Kit until the cleanup step) and a short "Native templates" paragraph (the guards, nil-parent rule for `NineSlicePanelTemplate`, no menus/popups/hooks). `docs/in-game-checklist.md`: section "Native foundations (PR 5)" with: `/cp kitdemo` opens a window that looks like the game's panels, title click prints, drag from title bar and body, close with the cross and Escape, `/cp kitdemo b a`, `/cp kitdemo c b` change header strip and tile, no Lua error, the old windows are unchanged; tell the user to send a screenshot of each variant next to the game's character panel. `docs/probe-findings.md`: F10 "Native templates and atlases" (the measured list from the spec Findings, the nil-parent `NineSlicePanelTemplate` error, how to re-run `/cppn list`). `CHANGELOG.md`: Unreleased entry "Added: native UI foundations and `/cp kitdemo` variants (developer tool)".
- [ ] **Step 4: `sh tests/check.sh`** 0 failed, 0 warnings; verify authorship (0 co-author lines); `git status --short` clean of stray mode changes.
- [ ] **Step 5: Commit** `feat: native kit demo with header and tile variants, docs`.
