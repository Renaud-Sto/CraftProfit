# UI rework: design

Status: draft for review, 2026-10-09. Mockups: the "CraftProfit - refonte graphique" design canvas (private, owner only); the decisions it led to are written here, so this file is self-contained.

## Goal

Make the three windows (main, pinned list inside it, leveling) readable at a glance and look like part of the game, with a theme the player can switch. Success: each number has an obvious place, the best option and the net result are visible without reading, and nothing is drawn with a colour or font chosen outside the theme layer.

Out of scope: addon icon, screenshots, the history window with graphs, any change to prices, scoring or saved data other than one new setting.

## Decisions already made with the author

| Decision | Choice |
| --- | --- |
| Visual direction | In-game look: gold chiselled outer frame, title plaque, flat dark interior ("hybrid"), each section in its own panel with a header bar ("segmented") |
| Web references (BitcoinOS, Lightdash, ...) | Not used for this addon |
| Top of the main window | A result banner (`RESULT`, best option, net value in large type) and three tiles: auction house (net), vendor, disenchant (beta) |
| Themes | Three, switchable: **Gold** (default), **Copper**, **Steel blue**. A theme changes colours and edges only, never the layout |
| Amount font | The game font, not a custom one |

## Architecture

### New: `Theme.lua` (pure data, testable offline)

A table of named themes. Each theme gives every colour the UI uses as a token; windows never hold a colour literal except the fixed ones below.

Tokens (RGBA): `windowBg`, `frameOuter`, `frameInner`, `frameShade`, `plaqueBg`, `plaqueText`, `panelBg`, `panelEdge`, `headBgTop`, `headBgBottom`, `headText`, `headRule`, `rowZebra`, `buttonBg`, `buttonEdge`, `buttonText`, `primaryBg`, `primaryEdge`, `primaryText`, `inputBg`, `inputEdge`, `checkMark`, `bestFill`, `bestEdge`, `textMain`, `textMuted`.

Fixed colours, identical in every theme because they carry meaning: gain green, loss red, incomplete amber, stale orange, recipe difficulty (orange, yellow, green, grey), best-option gold.

API: `Theme.list()`, `Theme.exists(name)`, `Theme.get(name)` (falls back to `gold`), `Theme.validate(theme)` (every token present, four numbers in 0..1), used by a unit test over all themes.

### New: `UI/Kit.lua` (shared widgets)

Today each UI file creates its own text, buttons and colour table. Kit owns them:

- `Kit.window(name, title, opts)` (opts: `width`, `height`, `onMoved(point, x, y)`): frame, gold edge, plaque, close button, drag handling (moved from `Window.create`). Returns the frame with fields `.content` (the area to fill), `.plaque`, `.titleText`, `.close` and method `:setTitle(text)`. The caller must `SetPoint` it and decide whether it is shown: a new frame starts shown and unanchored.
- `Kit.panel(parent, title)`: bordered panel with a header bar; returns a table with fields `.frame`, `.body` (a frame field to fill, not a method), `.title`, `.right` (small text at the right of the header) and methods `:setTitle(text)`, `:setRows(rows, rowH, extra)`, `:height()`; panels stack with an 8 px gap.
- `Kit.button(parent, kind, text)` (kind: `normal`, `primary`, `small`): a `Button` with field `.label` and method `:setText(text)`.
- `Kit.tile(parent, width, height)`: table with fields `.frame`, `.label`, `.value` and method `:set(spec)`, spec = `{ label, tag, value, best, muted }`.
- `Kit.check(parent, text)`: themed check box with its label on the right; `SetChecked`, `GetChecked`, `setText`, and `onToggle(checked)` called after a click. `Kit.input(parent, width, maxLetters)`: themed single-line edit box, 22 px high, text centred; Enter and Escape release the focus. `panel:onHeaderClick(fn)`: makes the header bar clickable (used to fold Materials). Both widgets exist since PR 2.
- Also added in PR 2: colour and layout helpers `Kit.mix(a, b, t)`, `Kit.colorEscape(c)`, `Kit.plaqueWidth(textWidth, maxWidth)`, `Kit.onTheme(paint)`, `Kit.naturalWidth(fontString)`; constants `PLAQUE_MIN`, `PLAQUE_PAD`, `CLOSE_ROOM`, `TILE_PAD`, `FOLDED_H`; and the theme token `rowHover` (hover highlight of a reagent row).
- Pure helpers, unit tested: `Kit.panelHeight(rows, rowH, extra)`, `Kit.stack(heights, gap, top)` (offsets of stacked panels and total height), `Kit.fitSize(baseWidth, baseSize, boxWidth, sizes)` (largest size that fits), `Kit.gradient(tex, top, bottom)` (returns the form that worked: `color`, `rgb` or `flat`).
- `Kit.applyTheme(name)`: re-colours every registered widget (each widget registers a `skin` function); no `/reload` needed.

Edges and fills use solid-colour textures (`SetColorTexture`) layered to draw the chiselled frame, not Blizzard atlases or backdrop files: atlas names are not verified in this beta and would tie the look to the client build. The header bar uses a vertical gradient if `Texture:SetGradient` exists in this client, a flat colour otherwise (checked by a probe, see Risks).

### Changed files

- `UI/Window.lua`: rebuilt on Kit; panels instead of a counted `y` offset. Order: result banner, tiles, one line under them for the disenchant detail, **Materials** panel (folded or not, click the header to toggle), prices age line, **Options** panel (crafts, track history, cost per point, pin), **Pinned recipes** panel (when the AH is open).
- `UI/PinsUI.lua`: the list and its three buttons become the Pinned recipes panel; sort button in the panel header; logic untouched.
- `UI/LevelingUI.lua`: same Kit window; the list is a **Next point** panel; profession, sort and age sit in a strip above it; grey-recipes checkbox below.
- `Present.lua`: builds new `banner`, `tiles` and `materials` fields in the model (see below). Amendment 1 (PR 2): the existing `lines` and `verdict` are kept in the model rather than removed, because the pinned list and the tests still use them; the main window reads `lines` only for the `likely` and `perpoint` entries. Existing text builders (`perPointLine`, `pointRow`, `likelyLine`) are kept.
- `DB.lua`: one setting, `theme` (string, default `gold`), sanitised (unknown name becomes `gold`), account-wide. PR 1 adds it; nothing reads it until PR 4.
- `Boot.lua`: `/cp theme [name]` (no name lists them); calls `Kit.applyTheme`. Arrives in PR 4. In PR 1 only the developer command `/cp kitdemo [theme]` exists (not in the user help text); it applies a theme without saving it and shows the demo window, which is how PR 1 is checked in game.
- Locales: panel titles are separate keys written already in capitals (`PANEL_MATERIALS = "COMPOSANTS"`): `string.upper` in Lua 5.1 does not handle UTF-8 accents (`É` would stay lower case). New keys also for `RESULT`, tile labels and theme names, in en, fr, es.

### Model changes (testable)

```
model.banner = { label = L.RESULT, best = "Auction house (net)", value = "+91s", kind = "profit" }
model.tiles  = {
  { key = "ah",      label = ..., value = "3g 24s", best = true },
  { key = "vendor",  label = ..., value = "1g 12s" },
  { key = "disench", label = ..., value = "2g 2s",  tag = L.BETA },
}
```

Rules: always three tiles (stable layout). `n/a` shows muted, an unknown price shows `?`, the best tile gets the gold outline, the banner is amber with `Incomplete: prices missing` when a price is missing, as today. The disenchant detail (`75%: 1-2x Soul Dust = 7s 30c`) stays a small grey line under the tiles.

## Fonts and numbers

- All text uses the game's font objects (the client supplies them, so there is no licence question and no file to ship). Large numbers use `FontString:SetFont(STANDARD_TEXT_FONT, size, "")` at a size picked by `Kit.fitSize`.
- Letter spacing does not exist on game font strings; the mockup's spaced capitals are rendered as plain small capitals with the header bar and rule carrying the separation.
- Tile values must fit about 100 px: when the string is wider than its box, the font drops one size, as `Window.setTitle` already does for long recipe names (`21g 29s` is the widest realistic case; test with `999g 99s 99c`).
- Money text keeps the `Ng Ns Nc` format. Proposal inside this spec: colour the unit letters like the game's coins (gold, silver, copper) in the tiles and the banner only. Coin icons are a later option, not part of this work.

## Themes

| Token role | Gold (default) | Copper | Steel blue |
| --- | --- | --- | --- |
| Window | near-black `#121110` | brown `#17100B` | blue-black `#070814` |
| Outer edge | gold `#B08D3C` | copper `#C87533` | grey-blue `#5F6684` |
| Header text | `#C9A95A` | `#E0A46A` | `#8FA4E6` |
| Primary button | dark gold | dark copper | royal blue |

Exact values live in `Theme.lua` and follow the mockups. Steel blue uses square edges like the others (rounded corners from the mockup are dropped: textures cannot round cheaply). A theme is accepted only if its gain, loss and difficulty colours keep readable contrast against `panelBg` (manual check in game, listed in the checklist).

## Testing

- Unit (offline): every theme passes `Theme.validate`; `theme` setting sanitised; `banner` and `tiles` built correctly for profit, loss, incomplete, unsellable, no-disenchant and BoP cases; widest amount string fits the tile after the font step-down logic (the pure width rule); locale keys exist in all three locales (existing locale test).
- Kit is thin glue over game widgets and is exercised through the fake game environment in `tests/fakewow.lua` (creation, `applyTheme` called twice, no error with every theme).
- In game (added to `docs/in-game-checklist.md`): each theme in the three windows, `/cp theme` while windows are open, long names and the widest amounts, reagent click-search still works, folding Materials, drag and saved positions, French client accents.

## Risks and open checks

1. **`Texture:SetGradient` and the font path in this build are unverified.** A probe command (`/cpp skin`) reports what the client supports; Kit already has the flat fallback for the gradient.
2. **Click targets.** Reagent rows and the Materials toggle are `Button`s over the panels; the rework must keep `onReagentClick` and `onCostToggle` working (covered by the in-game checklist, not by unit tests).
3. **Every theme multiplies the visual checking.** Hence three themes, palette only. Adding a fourth later costs one table plus a contrast check.
4. **Window height.** The main window with pins is about 760 px tall in the mockup; on small screens it may not fit. Kit clamps to the screen and the Pinned panel scrolls as the list does today (visible rows 6).

## Delivery (one PR each, merged only on the author's go)

1. `Theme.lua`, `UI/Kit.lua`, `/cpp skin` probe, tests, the `theme` setting in `DB.lua` (sanitised, not yet read), the `/cp kitdemo [theme]` developer command. No visible change.
2. Main window on Kit (this PR): result banner, three tiles, the grey likely line, Materials panel (fold by the header, clickable reagents), prices age line, Options panel (Crafts box, Track history, Cost per skill point with its value, Pin/Unpin); `Kit.check`, `Kit.input`, `panel:onHeaderClick`, the `rowHover` token; `Present.build` adds `banner`, `tiles`, `materials`. The pinned list keeps its old look until PR 3. Docs, checklist and CHANGELOG updated.
3. Pinned panel and leveling window on Kit.
4. Reading the `theme` setting, `/cp theme`, a theme button in the window header, Copper and Steel blue, docs, checklist, CHANGELOG.
