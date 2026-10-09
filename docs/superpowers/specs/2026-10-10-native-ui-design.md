# Native UI: rebuild the Kit on Blizzard's own templates

Status: draft for review. Branch `feat/native-probe` (the probe in `probe/CraftProfitProbe/Native.lua` produced the findings below).

## Goal

CraftProfit's windows should look like they ship with WoW: Forever. Today the Kit draws everything by hand (rings, gradients, themed colours). The result is close but not native. We replace the Kit's internals with the game's own frame templates, atlases, fonts and sounds. No texture or font file is added to the addon (a `.tga`, `.blp` or `.ttf` in the folder is a defect).

## Findings (measured in game 2026-10-09, build 1.60.1.70291, probe `/cppn`)

- All of these create and render correctly: `ButtonFrameTemplate`, `PortraitFrameTemplate`, `DefaultPanelTemplate`, `DefaultPanelFlatTemplate`, `BasicFrameTemplateWithInset`, `InsetFrameTemplate`, `NineSlicePanelTemplate`, `UIPanelButtonTemplate`, `UICheckButtonTemplate`, `InputBoxTemplate`, `SearchBoxTemplate`, `ScrollFrameTemplate`, `MinimalScrollBar`, `WowScrollBoxList`, `PanelTabButtonTemplate`, `MagicButtonTemplate`, `UIPanelCloseButton`, `TooltipBackdropTemplate`, `QuestLogBorderFrameTemplate`.
- Atlases that exist: `questlog-reward-top-frame` (307x51), `questlog-reward-header-top`, `questlog-reward-bottom`, `questlog-frame`, `friends-frame-toptexbg/bottomtexbg/infobg`, `common-framedivider`, `perks-divider-short`, `looting_itemcard_bg` and `_stroke_normal` (298x76), `common-search-magnifyingglass` (24x24), `_UI-Frame-TopTileStreaks` (with the leading underscore), `auctionhouse-rowstripe-1`, `auctionhouse-background-index`, `RedButton-Exit`, `common-dropdown-a-button`, `Options_ListExpand_Right`.
- Files served to addons: `Interface\FrameGeneral\UI-Background-Rock` and `UI-Background-Marble`, `Interface\QuestFrame\UI-QuestTitleHighlight`.
- `NineSlicePanelTemplate` reads its parent's `layoutType` in `OnLoad`: it must be created with a parent.
- Forever is the Retail Mainline client with a `Camelot/` art layer. Blizzard's source for it: `Gethe/wow-ui-source`, branch `forever` (cloned in `.cache/`, git-ignored).
- Reference: a guild member's addon (SO-6, used with permission, kept out of git in `elyes_SO6/`) follows the same approach; its notes list the traps below.

## Decisions

1. **Replace the Kit's internals, keep its API.** `Kit.window`, `panel`, `button`, `tile`, `check`, `input`, `listRow`, `scrollbar` keep their names, signatures and returned fields as far as possible, so `Window.lua`, `PinsUI.lua` and `LevelingUI.lua` change little and their tests keep most of their shape. Where a native template cannot honour a field, the field is dropped and the callers and tests are adjusted in the same task.
2. **Themes go.** The look is Blizzard's fixed gold and rock; recolouring it would look fake. Removed: the Copper and Steel themes, `/cp theme`, the header swatch, `Kit.applyTheme`, `Kit.onTheme` registry, the theme token set. Kept: the meaning colours (gain, loss, difficulty orange/yellow/green/grey, best, stale, incomplete) as a small `ns.Colors` table, drawn from the game's global colours where one exists (`NORMAL_FONT_COLOR`, `HIGHLIGHT_FONT_COLOR`, `DISABLED_FONT_COLOR`, `GREEN_FONT_COLOR`, `RED_FONT_COLOR`, `ITEM_QUALITY_COLORS`). A saved `settings.theme` from an older version is ignored and dropped by `DB.lua`. This supersedes PR 4 (#13) in the user guides, README commands tables, changelog and checklist.
3. **Window = `ButtonFrameTemplate` without portrait and without button bar** (`ButtonFrameTemplate_HidePortrait`, `_HideButtonBar`), the same frame the game uses for its panels: rock background, gold border, title bar, native close button. The title is set with `SetTitle`; the hand-measured plaque, `PLAQUE_*` constants and `setTitle` width cache are removed (the title bar is native; a title too long for the bar is shortened with an ellipsis by the font string). Content goes in `frame.Inset` (the native dark inset). The title stays clickable (search the crafted item) through a transparent hit button over the title bar with the game's magnifier next to the text.
4. **Panels** are sections inside the inset: a header strip (atlas, chosen at the demo checkpoint among `questlog-reward-header-top`, `friends-frame-toptexbg`, `_UI-Frame-TopTileStreaks`) with a `GameFontNormal` title and an optional right-hand text, and a body with a thin native divider (`common-framedivider` or `perks-divider-short`). Fold and header-click behaviour is unchanged.
5. **Result banner and tiles** use native boxes: tiles are `looting_itemcard_bg` + `_stroke_normal` style cards (the best tile gets the game's highlight stroke atlas, with the old opaque gold outline as fallback if the atlas is missing); the banner is a native box with a coloured text (the meaning colour), the tinted fill kept as a vertex colour on a native background texture.
6. **Widgets**: buttons `UIPanelButtonTemplate` (22 px high; the header sort button and small buttons use the same template at 20 px), check box `UICheckButtonTemplate`, input `InputBoxTemplate`, sounds from `SOUNDKIT` (`IG_MAINMENU_OPTION_CHECKBOX_ON/_OFF`, `IG_CHARACTER_INFO_OPEN/_CLOSE`), tooltips `GameTooltip` with `GameTooltip_SetTitle` / `AddNormalLine` / `AddInstructionLine`. Fonts: only `GameFont*`, `NumberFont*` and `QuestFont*` objects. Amounts: `Format.money` with the coin-icon function (`GetCoinTextureString` or `GetMoneyString` when present, a string result is required, the plain `21g 29s` text stays as fallback).
7. **Lists**: rows keep the `Kit.listRow` API (hover = additive `UI-QuestTitleHighlight`, selected tint). The scroll bar becomes the native thin bar (`MinimalScrollBar` atlases). Preferred: drive it from a `ScrollFrame`-style offset without moving to `WowScrollBoxList` (our lists are 6 to 12 rows with fixed height; the data-provider rewrite is not worth it). If the native bar cannot be driven without a ScrollBox, the fallback is our own bar drawn with the `minimal-scrollbar-*` atlases and the existing grab logic (`Kit.scrollGrab`, lost mouse-up recovery stay and stay tested).
8. **The leveling window and the pinned host** use the same window factory. Placement logic (pinned list beside the profession window, saved positions, clamp) is unchanged.

## Traps from the field (must hold; each gets a test or a checklist line)

- Create Blizzard-templated frames with a nil parent then `SetParent` when they would be created under an open Blizzard panel (the gamepad smart-navigation hooks `CreateFrame`): the pinned host sits beside the profession window, so it applies there. Plain parents (UIParent, our own frames) are fine.
- No hook on methods of Blizzard objects, no write into Blizzard tables, no `UIPanelWindows` (Escape closes through `UISpecialFrames` with a named frame), no `StaticPopup_Show`, no dropdown or `Menu` API (crashes the Forever client), no `Secure*` template.
- Anything that takes a click and is not a `Button`/`EditBox` is read by the gamepad code through `GetScript`: clickable areas over Blizzard panels stay `Button`s (ours already are).
- `OnUpdate` only while the window is shown and only for the drag; stays light (Forever profiles addons).
- Frames start shown and unanchored: hide and anchor them.

## Out of scope

Price history view and graphs (designed separately afterwards, on the native kit), addon icon and screenshots, translation review.

## Delivery

One branch, one PR per step so each can be reverted alone:

1. **Demo and base**: `Kit.window` on `ButtonFrameTemplate`, `Kit.panel` header strip, `Kit.button`, `check`, `input`, rewritten `/cp kitdemo` as a visual checkpoint (the user compares with the game's panels and picks the header strip and tile atlas); remove themes (Theme.lua to Colors.lua, `/cp theme`, swatch, `settings.theme`).
2. **Main window** on the native kit (banner, tiles, materials, options), money icons.
3. **Pinned list and leveling window**, native rows and scroll bar.
4. **Docs and cleanup**: README, both user guides, technical notes, checklist, changelog; delete dead Kit code and tests; probe findings F10 (native templates).

Each step: `sh tests/check.sh` green, in-game checklist lines, and a screenshot comparison with the game's own panel.

## Risks

- The fake game environment cannot draw: native templates are checked in game only. Mitigation: the demo checkpoint in step 1, and unit tests on layout maths, fields and click wiring only.
- Template internals (`frame.Inset`, `frame.TitleContainer`, `SetTitle`) differ across builds; every use is guarded (`if frame.SetTitle then ... else fallback to our own font string`) and listed in `docs/probe-findings.md`.
- Layout sizes of native chrome (title bar 20 px, inset from (4, -60) to (-6, 26) unless the bar is hidden) change the usable height; step 2 recomputes `Window.contentHeightOf`.
