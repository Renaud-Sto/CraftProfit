# CraftProfit technical documentation

[Back to the README](../README.md) · [User guide](user-guide.md) · [Contributing](../CONTRIBUTING.md)

Target: **World of Warcraft: Forever** beta, build 1.60.1, `## Interface: 16001`. The client uses the Mainline (Midnight-style) UI and API set on a Classic base, Lua 5.1, and the *secret values* restrictions. The addon is about 3,000 lines of Lua and has no library dependency.

Contents: [Design principles](#design-principles) · [Architecture](#architecture) · [Data flow](#data-flow) · [Price model](#price-model) · [Price history](#price-history) · [Evaluation](#evaluation) · [Saved variables](#saved-variables) · [Game API used](#game-api-used) · [Measured behaviour of the beta](#measured-behaviour-of-the-beta) · [Constraints that shape the code](#constraints-that-shape-the-code) · [Localization](#localization) · [Testing](#testing) · [Probe addon](#probe-addon) · [Packaging](#packaging)

## Design principles

1. **Pure logic apart from the game.** Everything that decides a number is plain Lua with no WoW API, tested offline. Game calls live in thin adapters.
2. **An unknown is never a zero.** A missing price is `nil`, shown as `?`. A recipe with any unpriced reagent has no total and no verdict (*Incomplete*), never a cheap-looking one.
3. **Identifiers, not names.** Items, recipes and professions are handled by id. No logic depends on a displayed (localized) text, and tooltips are never parsed.
4. **Defensive at the boundary.** Every game call that may differ between builds is guarded (`pcall`, type checks, `issecretvalue`); a missing API degrades a feature, it never raises a Lua error.
5. **No taint.** The window is parented to `UIParent`, never to a Blizzard frame. The only Blizzard UI touched is the auction house search box and quantity input, defensively, and the addon never presses Buy.
6. **Saved data is repaired in place.** WoW keeps a reference to the table it loaded, so replacing it would silently lose the data at logout.

## Architecture

Files load in the order of `CraftProfit/CraftProfit.toc`. Each file receives the addon name and a shared namespace table (`local _, ns = ...`) and registers its module on it.

| File | Module | Role | Uses the game API |
| --- | --- | --- | --- |
| `Util.lua` | `ns.Util` | Number guards (`isFinite`, `isCopper`, `count`, `id`), `clamp`, `round` | no |
| `Format.lua` | `ns.Format` | Money (copper dropped from 100 gold up, `Format.ROUND_FROM`) and duration formatting | no (the coin formatter is passed in) |
| `Colors.lua` | `ns.Colors` | Meaning colours `FIXED` (profit, loss, incomplete, stale, best, optimal, medium, easy, trivial); `text(kind)` reads the game's `HIGHLIGHT_FONT_COLOR` (`main`), `DISABLED_FONT_COLOR` (`muted`) or `NORMAL_FONT_COLOR` (`gold`) with a fallback; `escape(c)` builds a `\|c` colour escape | no (game colour globals read under `pcall`) |
| `Core.lua` | `ns.Core` | Cost sum, net sale, vendor value, expected and likely disenchant, cost per point, best option, ranking helpers | no |
| `Data/Skillup.lua` | `ns.Data.Skillup` | Skill-up chance by recipe colour (estimates) | no |
| `Data/Disenchant.lua` | `ns.Data.Disenchant` | Disenchant eligibility and result tables | no |
| `Locale.lua`, `Locales/*.lua` | `ns.Locale`, `ns.L` | Language selection with fallback; strings for enUS, frFR, esES, esMX (alias) | no |
| `Recipes.lua` | `ns.Recipes` | Validation and normalisation of a recipe read from the game | no |
| `DB.lua` | `ns.DB` | Saved variable defaults, repair, migration, pins, sort mode | no |
| `Prices.lua` | `ns.Prices` | Median price, scan aggregation, price storage and ageing | no |
| `History.lua` | `ns.History` | Tracked recipes (cap 15), price history points per item, retention (raw, daily, weekly) | no |
| `PriceQueue.lua` | `ns.PriceQueue` | Sequential search queue with timeouts | no (a `send` function is injected) |
| `Evaluate.lua` | `ns.Evaluate` | Combines recipe, prices and item facts into one result | no (lookups injected) |
| `Leveling.lua` | `ns.Leveling` | Ranks the known recipes of a profession by cost per point | no |
| `Present.lua` | `ns.Present` | Turns a result into display text only: the `banner`, the three `tiles`, the `materials` panel, the cost lines and the older `lines`/`verdict` | no |
| `AHAdapter.lua` | `ns.AH` | Auction house: scan, targeted search, search box helper | `C_AuctionHouse`, auction house frame |
| `TradeAdapter.lua` | `ns.Trade` | Profession window: selected recipe, raw recipe data, difficulty, known professions | `C_TradeSkillUI`, professions API |
| `UI/Window.lua` | `ns.Window` | The main window, on the native kit (`ns.Native`): banner, tiles, Materials and Options panels, and the host of the pinned list | frames |
| `UI/LevelingUI.lua` | `ns.LevelingUI` | The leveling window, on the native kit (`Native.window`, 396 px): strip (profession and sort buttons), prices age line, a `NEXT POINT` panel of 12 `Native.listRow` rows with a `Native.scrollbar`, grey-recipes `Native.check` | frames |
| `UI/PinnedWindow.lua` | `ns.PinnedWindow` | The pinned recipes window (`CraftProfitPinnedWindow`, `Native.window`, 396 px like the leveling window, in `UISpecialFrames`), built on first open: full-width sort button, age line, a `PINNED RECIPES` panel of 12 `Native.listRow` rows with a `Native.scrollbar` and an unpin "x" (plain `Button` 16x16) per row, empty text. Fed by `Controller.pinsData()`; values from `PinsUI.rowValue`. `refresh` does nothing while hidden or unbuilt | frames, `GameTooltip` |
| `UI/PinsUI.lua` | `ns.PinsUI` | Pinned list, on the native kit: a `Native.panel` `Pinned recipes` with the sort button (`Native.button`, 20 px) in its header, 6 visible `Native.listRow` rows with a `Native.scrollbar`, the Search prices, Scan AH and Leveling buttons (`Native.button`) and the status line. Exports `orderedPins` and `rowValue(item, byPoint)` (value text and colour), shared with the pinned window | frames |
| `UI/Layout.lua` | `ns.Layout` | Pure layout maths shared by the native windows: `panelHeight`, `stack`, `fitSize`, `scrollThumb`, `scrollOffsetAt`, `scrollGrab`, and the constants `HEAD_H` (22), `BODY_PAD` (4), `GAP` (8), `SCROLL_MIN_THUMB` (16). Loaded before `UI/Native.lua` | no |
| `UI/Native.lua` | `ns.Native` | Widgets on Blizzard's own templates and atlases: `window` (`ButtonFrameTemplate`), `panel`, `tile`, `button`, `check`, `input`, `searchIcon`, `forwardDrag`, `banner` (result banner tinted by the result kind), `listRow` (clickable list row), `scrollbar` (the game's thin scroll bar atlases), with switchable header strip and tile variants: `Native.registry` holds every panel and tile built, and `setHeaderVariant` / `setTileVariant` repaint them live (a tile builds both cards and shows one); `appearance()` gives the keys in use. Every window is on it (main window, pinned list, leveling window) | frames |
| `UI/OptionsUI.lua` | `ns.OptionsUI` | The options window (`CraftProfitOptionsWindow`, 420 px so the segmented header buttons fit their Spanish and French labels, in `UISpecialFrames`), built on first open: APPEARANCE (segmented `Native.button` rows, the chosen one lit with `LockHighlight`, calling `Controller.setAppearance`), MINIMAP (`Native.check`, `Controller.setMinimapHidden`), WINDOWS (two rows of half-width `Native.button`s: main and leveling, then pinned recipes centred), CONTROLS (`OptionsUI.LINE_COUNT` = 14 lines of `GameFontHighlightSmall`, 14 px each, never wrapped: the two minimap clicks and each command, gold head and white description via `Colors.escape`, locale keys `OPTIONS_CLICK_*` and `CMD_*`; the panel is `Layout.panelHeight(14, 14)`). Labels are checked in the tests against `Layout.textWidth` at `OptionsUI.CHAR_W` = 7 px per letter for buttons (calibrated in game: "Montée de métier" did not fit 107 px) and `SMALL_CHAR_W` = 6 px for the list. No dropdown, `Menu` or `Settings` API | frames |
| `UI/MinimapButton.lua` | `ns.MinimapButton` | The minimap button without a library (LibDBIcon convention: 31x31, MEDIUM, level 8, nil parent then `SetParent(Minimap)`): pure `angleFromCursor`, `offset` (round and square minimaps), `radius`; `create` (never while hidden), `apply`; `OnUpdate` only during a drag; left click toggles the options window, right click the pinned recipes window | frames, `Minimap`, `GetCursorPosition`, `GameTooltip` |
| `UI/KitDemo.lua` | `ns.KitDemo` | Developer demo window (not in the user help): `/cp kitdemo [header [tile]]` shows the native widgets with a choice of header strip and tile card | frames |
| `Boot.lua` | `ns.Controller` | Wires everything, owns the selection state, slash commands, self-test, `setAppearance`, `setMinimapHidden`, main window show/hide/toggle, `pinsData` / `unpin` / `savePinsPosition` for the pinned window, and the global `CraftProfit_OnCompartmentClick` (TOC `AddonCompartmentFunc`; left options, right pinned recipes window) | events, slash commands |

Dependencies point one way: `Core`, `Data`, `Util`, `Format` know nothing of the rest; `Evaluate` and `Present` use them; adapters and UI use everything; `Boot` is the only file that connects the adapters to the UI.

## Data flow

**Selecting a recipe.** `Trade.watch` polls the profession window every 0.3 s (the Professions UI has no selection event and is created lazily). A new selection id makes `Trade.readSelected()` return a raw recipe, `Recipes.normalize` validates it, and `Controller.setRecipe` renders it. Item data that is not cached yet is requested once (`C_Item.RequestLoadItemDataByID`) and `ITEM_DATA_LOAD_RESULT` triggers a coalesced refresh.

**Rendering.** `Controller.refresh()` calls `Evaluate.run` with the recipe, a price lookup (`Prices.priceOf`), item facts (`Controller.itemInfo`), the commission, the per-point option, the disenchant lookup, whether the character knows Enchanting, and the number of crafts. `Present.build` turns the result into a model (`banner`, `tiles`, `materials`, plus the older `lines`, cost lines, `verdict` and age) and `Window.render` draws it. The window draws the banner (label, best way to sell, net result with its tone), the three tiles and the Materials panel from the new fields, and reads `lines` only for the `likely` (grey disenchant line) and `perpoint` (Cost per skill point value) entries. `lines` and `verdict` are kept in the model for the pinned list and for tests. The pinned list evaluates each pin the same way, always for one craft.

**Searching prices.** `PinsUI.startSearch` builds the list of items the pins need (`Evaluate.wantedItems`) and runs a `PriceQueue`: one `SendSearchQuery` at a time, advanced by `COMMODITY_SEARCH_RESULTS_UPDATED` or `ITEM_SEARCH_RESULTS_UPDATED` or a timeout. `AHAdapter` reads the listings into `{ unit, qty }` rows; `Controller.recordListings` stores the median.

**Scanning.** `AH.requestSnapshot` calls `ReplicateItems` (once per 15 minutes per account). The client then fires `REPLICATE_ITEM_LIST_UPDATE` hundreds of times for one scan, so the adapter schedules **one** read one second after the first event and ignores the rest until 10 seconds after that read. The read walks the rows in chunks of 1,500 per frame (no freeze) into a `Prices.newAggregator()`; `Controller.onSnapshot` merges the result into the saved prices. A scan started by another addon is handled the same way.

**Clicking a reagent.** `AH.browse` switches the auction house to its Buy view, writes the name in `SearchBar.SearchBox` and calls `SearchBar:StartSearch()`. A hook on `CommoditiesBuyFrame`'s `OnShow` then sets the quantity input (`SetQuantity`) and calls the input's own `OnTextChanged` handler with `userInput = true`, which makes the client recompute the quote, as typing would.

**Clicking the crafted item.** `Controller.onOutputClick` (wired to the AH tile and the window title) does nothing without a recipe; with the AH closed it says `SEARCH_NEED_AH`; an output with `bindType == 1` (bound when picked up, the rule `Evaluate` uses) says `SEARCH_UNSELLABLE` and searches nothing; an item whose name is not loaded says `ITEM_NOT_LOADED`; otherwise it calls `AH.browse(name, itemID, nil)`, the same path as a reagent click with no quantity preset, so the quantity hook is not armed.

**The search icon.** `Native.searchIcon(texture)` puts the game's magnifier on a texture and returns whether it did: first the atlas `Native.SEARCH_ATLAS` (`common-search-magnifyingglass`) when `C_Texture.GetAtlasInfo` knows it, else the icon of the AH search box (`AuctionHouseFrame.SearchBar.SearchBox.searchIcon` or `SearchIcon`, by `GetAtlas`, else `GetTexture` with `GetTexCoord`). It never guesses a file path (a missing file draws a green square) and draws nothing when no source exists, so the icon is optional; everything runs in `pcall`. `Native.forwardDrag(button, window)` lets a button that covers a drag handle start and stop the window move. `Window` shows the title and AH tile icons only while the AH is open and a recipe is displayed.

**Native templates.** `UI/Native.lua` draws with the game's own templates instead of hand-painted textures: `Native.window` is a `ButtonFrameTemplate` with `ButtonFrameTemplate_HideAttic`, `_HidePortrait` and `_HideButtonBar` applied in that order (HideAttic resets the inset's left edge, HidePortrait then moves it), so its content area, `frame.Inset`, runs from TOPLEFT (9, -24) to BOTTOMRIGHT (-6, 4); the title bar is 20 px, the close button 24 px at TOPRIGHT (-2, 1). Buttons are `UIPanelButtonTemplate` (22 px, label cut instead of wrapping), check boxes `UICheckButtonTemplate` (24 px, the label widens the hit area), inputs `InputBoxTemplate` (22 px, its border reaches 5 px left of the box), panels and tiles sit on `InsetFrameTemplate` with header strips and cards from atlases (`Native.HEADER_VARIANTS`, `Native.TILE_VARIANTS`); fonts are game font objects only. Rules the module keeps: every template internal (`Inset`, `TitleContainer`, `CloseButton`, `Text`, the `ButtonFrameTemplate_*` helpers, colour objects, `C_Texture.GetAtlasInfo`) is tested with `type(...)` before use and has a plain fallback, so a changed client build never raises; a templated frame that could sit under a Blizzard panel is created with a nil parent and then `SetParent`, because the gamepad navigation hooks `CreateFrame` and runs tainted under an open Blizzard panel (the exception is a frame made directly from `NineSlicePanelTemplate`: it reads its parent's `layoutType` in `OnLoad` and errors without a parent; a template that holds a `NineSlice` child, such as `ButtonFrameTemplate` or `InsetFrameTemplate`, is fine either way. Panels and tiles create their inset with their own frame as parent, which is never a Blizzard panel); no dropdown or `Menu` API (crashes the Forever client), no `StaticPopup_Show`, no `UIPanelWindows` (Escape goes through `UISpecialFrames`), no hook on Blizzard methods and no write into Blizzard tables other than adding a name to `UISpecialFrames`; anything that takes a click is a `Button`, `CheckButton` or `EditBox`.

**The main window on Native.** `Window.create` builds a `Native.window("CraftProfitWindow", L.TITLE, { width = 372, onMoved, onTitleClick })`: sections are children of `frame.content` (the inset), anchored `Native.CONTENT_PAD` (4 px) from every inset edge (on a build without the inset, `content` is the frame and the sections start at the inset's edges, 9 / 6 / 24 px, so the height maths still hold) and stacked 8 px apart (`Window.GAP`, `Layout.stack`). `Window.INNER_WIDTH` = 372 - `INSET_LEFT` 9 - `INSET_RIGHT` 6 - 2 x 4 = 349 px; the three tiles are 111 px each. `Window.contentHeightOf(list)` is the inset height (stacked sections + 2 x `CONTENT_PAD`); the frame height adds `INSET_TOP` 24 and `INSET_BOTTOM` 4, plus 8 px and the pinned host when it shows. Section heights: panel heights from `Layout.panelHeight` (same geometry as `Native.panel`: 2 px edge, 22 px header, 4 px body pad, rows, 2 px edge); a folded Materials panel is `Window.FOLDED_H` = `Native.HEAD_H` + 4 = 26 px (the header keeps its 2 px inside the inset border at the top and the bottom); option rows are `max(CHECK_SIZE, BUTTON_H, INPUT_H) + 2` = 26 px and the Options body is exactly three of them. The banner is `Native.banner(content, 52, Window.INNER_WIDTH)` (the width lets it measure its text before layout): fill and 2 px edge tinted with `Colors.FIXED` by result kind (profit, loss, incomplete, else trivial); its value steps down the game font ladder from `GameFontNormalHuge` (20 px, the largest shadowed `GameFontNormal*`; the old banner started at 22 px) to `GameFontNormal` (12 px) when wider than 120 px. Reagent rows are `Native.listRow` rows with `Colors.text("main")` names and `Colors.text("muted")` values. Drag forwarding (`Native.forwardDrag`): the AH tile, every reagent row and the Materials header move the window like its body, and the click that ends a drag does nothing (no search, no fold). Texts use game font objects (`GameFontDisableSmall` age, `GameFontHighlightSmall` likely line, `GameFontDisable` empty text) painted with `Colors.text("muted")`, a stale age with `Colors.FIXED.stale`; the per-point value is `Colors.FIXED.profit`/`loss` or `Colors.text("main")`. Widgets: `Native.input` for crafts (applied on `OnEditFocusLost`, hooked because the template has its own handler), `Native.check` for track (label capped so it stays in the body) and per-point (label cut before its value; after each render `Window` caps the check with `check:setMaxWidth` to the room left of the value, so the hit area widened over the label never reaches under the value), `Native.button` 120 x 22 for Pin. The main window is not in `UISpecialFrames` (Escape does not close it). The pinned list inside it and the leveling window are on Native too (see below).

**Known small limits of the main window.** The partial verdict no longer competes with the value: its warning sits on the label line (`banner.warning`) and the main line keeps only the best way to sell. A main line that still does not fit beside the value (a very long item option name in some language) drops to the small font instead of wrapping, and could in theory be cut off next to a very large value.

**The scroll bar maths.** The geometry of the scroll bars is pure and unit tested, in `UI/Layout.lua`: `Layout.scrollThumb(total, visible, offset, trackH)` gives the thumb height and top (never shorter than `SCROLL_MIN_THUMB`, 16 px; `nil` when the list fits), `Layout.scrollOffsetAt(total, visible, trackH, y)` turns a pointer position on the track into a row offset, and `Layout.scrollGrab(total, visible, offset, trackH, y)` gives where on the thumb the pointer holds it: the distance from the thumb top when the pointer is on the thumb, half the thumb height when it is elsewhere on the track (the thumb centres on the pointer), `nil` when the list fits; a drag keeps that grab, so the thumb does not jump when grabbed off-centre. Clicking the track jumps there; dragging the thumb follows the pointer, read each frame with the `GetCursorPosition` global (declared in `.luacheckrc`) and divided by the bar's effective scale. The mouse wheel is handled by the list owners (rows, bar and the empty space of the list).

**The native scroll bar.** `Native.scrollbar(parent, trackH)` returns a bar driven by its owner: `bar.frame`, a plain `Button` `Native.SCROLL_W` = 8 px wide and `trackH` high, hidden at creation; `bar.thumb`; `bar:update(total, visible, offset)` returning whether it shows; `bar.onScroll(offset)`, asked for the offset a click or a drag wants; it uses the pure maths of `UI/Layout.lua` (`Layout.scrollThumb`, `Layout.scrollOffsetAt`, `Layout.scrollGrab`, minimum thumb 16 px). Blizzard's `MinimalScrollBar` template needs a `ScrollBox`, so the bar draws its atlases itself (`Blizzard_SharedXML/Shared/Scroll/MinimalScrollBar.xml`): the track is `minimal-scrollbar-track-top`, `!minimal-scrollbar-track-middle` (the `!` marks a vertically tiling atlas: `SetVertTile(true)`) and `minimal-scrollbar-track-bottom`; the thumb is `minimal-scrollbar-small-thumb-top|middle|bottom` (there is no `minimal-scrollbar-thumb-*`), with the `-over` set while the pointer is over the bar and the `-down` set while dragging, when the client knows them. The caps keep their atlas height (`C_Texture.GetAtlasInfo`; the UI source does not give the sizes), and share the thumb when it is shorter than both. When one piece of the track (or of the thumb) is unknown, that part is a flat texture: track `Colors.text("muted")` at alpha `SCROLL_TRACK_ALPHA` 0.3, thumb `Colors.text("gold")`. The thumb is a plain frame without mouse, so presses land on the track, which knows where the thumb is. Behaviour: left button only (nil accepted), grab kept for the whole drag, a lost mouse-up (alt-tab, a cinematic) ends the drag through `IsMouseButtonDown("LeftButton")` (declared in `.luacheckrc`, guarded by a type check), `OnHide` ends a drag. `OnUpdate` is set on the press and removed when the drag ends, so an idle bar costs nothing per frame. No arrows; the owners handle the wheel. Fields for tests: `trackAtlases`, `thumbAtlases`, `trackPieces` / `thumbPieces` or `trackFill` / `thumbFill`.

**The list row.** `Native.listRow(body, index, rowH, rightInset)` returns a `Button` of `rowH` px in slot `index` of `body`, anchored left and right (the right edge `rightInset` px in, to clear a scroll bar), with a hidden `row.selected` texture for the gold selected tint (`Native.ROW_SELECTED_ALPHA`) and the game's quest highlight on hover above it. The Materials rows of `Window`, and the rows of `PinsUI` and `LevelingUI` (inset `Native.SCROLL_W + 6`), use it.

**The pinned list and the leveling window** are on the native kit, with no colour literal. Texts use game font objects; names are `Colors.FIXED[difficulty]` or `Colors.text("main")`, values `Colors.FIXED.profit`/`loss` or `Colors.text("muted")`, read at each refresh. Their rows are `Native.listRow` (right inset `Native.SCROLL_W + 6`) and forward drags to their window (`Native.forwardDrag`; the click that ends a drag selects nothing). Their layout maths are `Layout.panelHeight` and `Layout.stack`. `Window.INNER_WIDTH` (see the main window, 349 px) is the width of the pinned host, which `Window.relayout` places below the Options panel with an 8 px gap and counts in the window height, so the pinned block (a `Native.panel`) sits inside the native inset, in the same margin as the other panels. Pinned footer: `PinsUI.FOOTER_H` = two 22 px `Native.button` rows with 6 px gaps plus 28 px of status = 84 px; the sort button is a `Native.button` 120 x 20 at the header's right, two levels above the panel frame (above the header and any header hit area), and the panel title stops 8 px before it. `PinsUI` shows 6 rows; the name of each is coloured by the recipe difficulty stored with the pin (orange, yellow, green, grey; a pin without a known difficulty uses the plain text colour). That difficulty is refreshed when the profession window updates, so with the profession closed it can lag behind the character's skill. Values keep the gain, loss and muted colours; the selected row is tinted gold (`Native.ROW_SELECTED_ALPHA`) and the hovered row lights up with the game's quest highlight (`Interface\QuestFrame\UI-QuestTitleHighlight`, additive), both from `Native.listRow`. The leveling value column is `LevelingUI.VALUE_W` = 130 px, wide enough for an amount with coin icons such as 999g 99s 99c/pt; the name column gives up the room. The status line has room for two lines; a message that wraps to three still overruns the bottom margin by about 14 px (known). `LevelingUI` is a `Native.window("CraftProfitLevelWindow")` 396 px wide (inner width 373 px: inset 9 / 6 and `CONTENT_PAD` 4 on each side) of fixed height (`INSET_TOP` 24 + `INSET_BOTTOM` 4 + 2 x 4 pad + strip 22 + age 14 + panel + check 24 + 3 x 8 gaps), hidden at creation, not in `UISpecialFrames` (Escape does not close it, as before), with 12 visible rows in a `NEXT POINT` panel (`LEVEL_PANEL`) and a row name cut with `...` instead of wrapping. `LevelingUI.EMPTY_WIDTH` = inner width - 2 x `PANEL_EDGE` - 16 = 353 px. The grey-recipes check box is capped with `setMaxWidth` at each refresh to the room left of the hidden-count text, so a long translated label is cut instead of running under it.

**Default placement.** A window without a saved position opens with its top left corner 6 px right of the shown CraftProfit window (main, leveling, pinned recipes, options; itself excluded) whose right edge is the largest: `Layout.rightmost(entries)` picks it from `{ shown, right }` entries (pure, only measured finite edges count) and `Controller.besidePosition(except)` returns `x, y` for `SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)`. The position is absolute, never anchored to the other window, so two windows can never depend on each other's anchors. With none shown or measured, each keeps its own default: the main window beside the profession or AH window (`Window.attach`), the leveling window beside the main window or `CENTER (-200, 0)`, the pinned window `CENTER (-260, 0)`, the options window `CENTER`. `SetClampedToScreen` keeps it on screen. A saved position always wins.

**The pinned recipes window.** `PinnedWindow` is built on the first `show` (`/cp pins`, the minimap or compartment right click, the options button), never at login, and is added to `UISpecialFrames` once. Its height is fixed (`INSET_TOP` 24 + `INSET_BOTTOM` 4 + 2 x 4 pad + strip 22 + age 14 + `Layout.panelHeight(12, 18)` + 2 x 8 gaps). `Controller.pinsData()` returns `{ items, byPoint, ageText, stale }`: `items` is `PinsUI.orderedPins(CraftProfitCharDB.pins, sortMode, Controller.evaluate)`, and the age is the largest `result.oldestAge` of those evaluations, the same value as the main window's age line (the oldest price actually used, from a scan or a search; never the scan time alone), `Present.ageText`, stale when missing or past `settings.staleAfter`. The window never searches. Row layout from the right: the "x" (16 px, 2 px from the row's right edge, which stops `Native.SCROLL_W + 6` before the panel edge), 6 px, the value (`VALUE_W` 130 px, no wrap), 8 px, the name (cut, no wrap). The "x" calls `Controller.unpin` (`DB.pinRemove` then `Controller.refresh`, which refreshes the main window, the list at the AH and this window; the selection is unchanged); a row click calls `Controller.selectPin` then `Controller.showMainWindow`. The offset is clamped at every refresh, so an unpin at the bottom of a scrolled list moves the rows and the bar. Position: `settings.pinsWindow`, else beside the rightmost shown window (see Default placement), else `CENTER` (-260, 0) (the main window's default is +300). Pins are capped at 12 per character (`DB.MAX_PINS`); the window was also tested with 40 pins written straight into the saved table.

## Price model

- A listing becomes `{ unit, qty }`. A stack row of the scan has its stack price divided by the stack size (`AH.PER_UNIT_REPLICATE = false`, measured).
- `Prices.summarize(listings, n)` sorts by unit price and takes the **median unit price of the n cheapest units** (`n = 5` by default, `settings.medianN`), plus the total volume. Quantities are handled arithmetically, so a listing of one billion units costs the same as one of one unit.
- `Prices.store` and `Prices.merge` write compact rows `{ unit, volume, time }` into `CraftProfitDB.prices`; `Prices.get` returns the unit price and its age, and `nil` for the age when the clock cannot be trusted.
- `DB.prune` removes prices older than 14 days at load.
- Selling uses a commission of 5 % (`settings.cut`, measured). The deposit is ignored: it is refunded when an item sells.

## Leveling list

`Trade.scanKnown` reads every learned recipe of the open profession, grey ones included so the "show grey recipes" option has something to show (`C_TradeSkillUI.GetAllRecipeIDs`, `GetRecipeInfo`, then the usual schematic read), 40 recipes per frame so the client never hitches, and abandons the read if the window closes (a partial list never replaces a good one). `Controller.refreshKnown` runs it on `TRADE_SKILL_LIST_UPDATE`, at most every 5 seconds, and stores the result with `DB.setKnown` in `CraftProfitCharDB.known = { { key, name, updated, recipes } }` (8 professions, 400 recipes each at most). The profession key is the id of `C_TradeSkillUI.GetBaseProfessionInfo()` when it has one, else the profession name. `Leveling.rank` evaluates each stored recipe with the per point figures forced on, hides the ones with a chance of 0 unless asked, and orders them with `Core.rankByPointCost`. Prices come from the last scan, so no search is needed.

A recipe whose cost per point is negative (it pays for itself) ranks first in the cost order, and the more so the rarer the point, because the figure is the money made per point: that order is about money, not speed. The speed order (`Core.rankBySpeed`, setting `levelSort`) puts the highest chance first and breaks ties by cost; the window also shows the crafts per point (`Present.craftsPerPoint`, 1 / chance) so the amount can be read as the loss of one craft times that figure.

## Price history

A recipe is *tracked* with the "Track history" box (account wide, 15 at most; unticking pauses recording and keeps the history, `/cp history remove <n>` deletes it). After every full scan and every price search, `History.record` writes one point per item of each active tracked recipe **touched by that update**, provided every required item has a price (the output of a bind-on-pickup recipe is never required). A point is `{ t, unit, volume, low, high, n }` with `t` the time of the operation, so the items of one recipe share a timestamp and the recipe's cost and net can be rebuilt for that date.

Retention (`History.compact`): all points for 14 days, then one point per day up to 90 days, then one per week up to a year, each merged point keeping the weighted average, the low, the high and the number of measurements. A rough bound is 12 KB per tracked recipe, under 200 KB for 15. The search button still only prices the pinned recipes; tracked recipes are fed by scans and by any search that touches their items. The history is recorded; there is no view of it yet.

## Evaluation

`Evaluate.run(ctx)` returns `{ recipe, crafts, cost, options, best, bestValue, net, incomplete, perPoint, oldestAge }`.

- **Cost** = sum of quantity × unit price of the reagents (`Core.sumCost`); `nil` when any price is missing.
- **Options**: `ah` (net sale, `n/a` for bind-on-pickup), `vendor` (sell price × quantity), `disenchant` (expected value net of the commission, plus `likely`: the most probable outcome). Each has a status `ok`, `unknown` or `na`.
- **Disenchant rules**: armor or weapon of quality 2 to 4 only; a bind-on-pickup item only when the character knows Enchanting (`Trade.hasProfession(333)`: the skill line id, language independent); no table gives `unknown`.
- **Best** = the `ok` option with the highest value (`Core.bestOption`); **net** = best value − cost.
- **Per point** (when enabled) = `(cost − bestValue) / chance`, with the chance from `Data/Skillup` by recipe colour. Computed before the multiplier is applied, so it is always per point.
- **Crafts** (1 to 9999, `Evaluate.craftCount`): after computing for one craft, quantities, cost, option values, best value and net are multiplied; per point and `likely` are not.

## Saved variables

`CraftProfitDB` (account), repaired by `DB.initAccount` and `History.sanitize`:

| Key | Content |
| --- | --- |
| `dbVersion` | Schema version (1) |
| `settings.cut` | AH commission, 0 to 0.5 (0.05) |
| `settings.medianN` | Units in the median, 1 to 20 (5) |
| `settings.staleAfter` | Seconds before prices show as old (3600) |
| `settings.showPerPoint` | Cost per point enabled |
| `settings.costExpanded` | Material detail unfolded |
| `settings.theme` | Removed with the colour themes: `DB.initAccount` deletes it from old saves |
| `settings.window` | `{ point, x, y }` once dragged |
| `settings.levelWindow`, `settings.optionsWindow`, `settings.pinsWindow` | `{ x, y }` of the leveling, options and pinned recipes windows once dragged; anything but two finite numbers is dropped |
| `settings.appearance` | `{ header = "a"|"b"|"c", tile = "a"|"b" }`, default `b`/`b`; each key checked against `DB.HEADER_KEYS` / `DB.TILE_KEYS` (the same sets as `Native.HEADER_VARIANTS` / `TILE_VARIANTS`, a test keeps them equal); applied by `Controller.init` before any window is built |
| `settings.minimap` | `{ hide = false, angle = 225 }`; `angle` in degrees, wrapped into [0, 360) by `DB.angle`, anything not finite becomes 225 |
| `markets["<realm>-<faction>"]` | One price table per market (see below) |
| `tracked` | Up to 15 tracked recipes `{ recipe, active }` |

`CraftProfitCharDB` (per character), repaired by `DB.initChar`:

| Key | Content |
| --- | --- |
| `known` | Learned recipes per profession for the leveling list |
| `pins` | Up to 12 normalised recipes `{ recipeID, name, difficulty, outputItemID, outputQty, reagents = { { itemID, qty } } }` |
| `sortMode` | `"net"` or `"point"` |

A market holds `prices[itemID] = { unit, volume, time }`, `snapshotTime` (the last full scan) and `series[itemID]`, the history points `{ t, unit, volume, low, high, n }` of the items of tracked recipes. The market key is the realm id plus the player's faction (`Controller.marketKey`, for example `4613-Horde`), with the normalised realm name as fallback. Forever has rulesets (Normal, PvP, RP, Hardcore) instead of realms; in the beta each ruleset is a "realm" such as *Classic Beta PvP 2* (id 4613), measured with `/cpp ruleset`. `C_GameRules.GetActiveGameMode()` only returns the client's game mode (1, Standard), not the ruleset. A hardcore character gets a `-HC` suffix (`C_GameRules.IsHardcoreActive`). Not measured yet: whether the other rulesets have their own realm id, because they could not be created in the beta; verify with `/cp market` at launch. The neutral auction house is not told apart from the faction one yet. Prices saved before markets existed (`prices` and `snapshotTime` at the top level) are adopted by the first market used.

Every field is validated on load (finite numbers, ranges, anchor names, array holes); anything invalid falls back to the default.

## Game API used

| Area | Calls |
| --- | --- |
| Auction house | `C_AuctionHouse.ReplicateItems`, `GetNumReplicateItems`, `GetReplicateItemInfo`, `SendSearchQuery`, `MakeItemKey`, `GetNumCommoditySearchResults`, `GetCommoditySearchResultInfo`, `GetNumItemSearchResults`, `GetItemSearchResultInfo`, `IsThrottledMessageSystemReady`; `Enum.AuctionHouseSortOrder`; `AuctionHouseFrame` (`SearchBar`, `CommoditiesBuyFrame`, `SetDisplayMode`) and `AuctionHouseFrameDisplayMode` |
| Professions | `C_TradeSkillUI.GetRecipeInfo`, `GetRecipeSchematic`; `ProfessionsFrame.CraftingPage.SchematicForm:GetRecipeInfo`; `GetProfessions`, `GetProfessionInfo`, `IsPlayerSpell`; classic fallbacks `GetTradeSkill*` |
| Items | `C_Item.GetItemInfo`, `C_Item.RequestLoadItemDataByID` |
| Misc | `GetLocale`, `GetTime`, `time`, `GetCoinTextureString`, `issecretvalue`, `C_Timer` |

Events: `ADDON_LOADED`, `ITEM_DATA_LOAD_RESULT`, `TRADE_SKILL_LIST_UPDATE`, `ADDON_ACTION_BLOCKED`, `ADDON_ACTION_FORBIDDEN`, `AUCTION_HOUSE_SHOW`, `AUCTION_HOUSE_CLOSED`, `COMMODITY_SEARCH_RESULTS_UPDATED`, `ITEM_SEARCH_RESULTS_UPDATED`, `REPLICATE_ITEM_LIST_UPDATE`.

## Measured behaviour of the beta

Measured in game on build 1.60.1, French client (details in [probe-findings.md](probe-findings.md)):

- Reagents are commodities: `COMMODITY_SEARCH_RESULTS_UPDATED` with the item id, fields `unitPrice` and `quantity`. Gear uses `ITEM_SEARCH_RESULTS_UPDATED` with an item key table, fields `buyoutAmount` and `quantity`. Each event arrives twice, harmlessly. A search with no result still fires its event.
- A full scan returns about 79,000 rows of 17 values; `buyout` is the price of the **whole stack**. `REPLICATE_ITEM_LIST_UPDATE` fires hundreds of times per scan. A scan inside the 15 minute window is ignored silently, no event.
- The AH commission is 5 % of the sale price, the deposit is refunded on sale.
- `GetProfessionInfo` returns the skill line id as its 7th value (164 for Blacksmithing, 129 for First Aid); `GetNumSkillLines` does not exist.
- The Mainline auction house frames exist with their usual members. Setting the quantity input alone leaves the quote on one unit; its `OnTextChanged` handler must run with `userInput = true`.

## Constraints that shape the code

- **Secret values.** Some game values are secret: comparing, concatenating or doing arithmetic on them raises. Every value read from the game is checked with `issecretvalue` before use; item names are read inside `pcall`.
- **Division by zero raises.** The client rejects a literal zero divisor (`0 / 0`, `1 / 0`). Every divisor is guarded, NaN and infinity are built from `math.huge`, and a test refuses a literal zero divisor anywhere in the addon.
- **Lua 5.1 only**, no `table.unpack`, `//`, goto or integer division; the offline tests run on LuaJIT, so `/cp selftest` re-checks a few behaviours inside the game's own Lua.
- **The full scan is limited** to one per 15 minutes per account, shared with every addon.
- **No API for sales history**: CraftProfit does not know how fast an item sells.

## Localization

`Locale.select(GetLocale())` picks the table; a missing key falls back to enUS, then to the key itself. `esMX` is an alias of `esES`. There is no hard-coded user-facing string in the UI modules. Tests check that frFR and esES define exactly the enUS keys, keep its format specifiers (`%d`, `%s`) and are never empty. See [CONTRIBUTING.md](../CONTRIBUTING.md#adding-or-fixing-a-language).

## Testing

`sh tests/check.sh` runs both:

- `luajit tests/run.lua`: every `tests/test_*.lua`, with a dependency-free harness (`tests/harness.lua`). Modules are loaded with `H.newNS` or, for the whole addon, `tests/fakewow.lua` which loads the real files in TOC order into a fake game environment (frames, timers, item data, chat).
- `luacheck CraftProfit tests --config .luacheckrc`: zero warnings is required; every game global the addon reads is declared in `.luacheckrc`.

The suite covers the pure modules, the adapters with faked game APIs, saved variable repair, localization, the TOC, and the boot sequence. What it cannot cover is the real client: see [in-game-checklist.md](in-game-checklist.md).

## Probe addon

`probe/CraftProfitProbe` is a throwaway addon (not shipped) that prints what the real client returns: `/cpp api | locale | item | deposit | search | replicate | trade | prof | ahui | qty | skin | icon | log | clear`. It mirrors its output, CraftProfit's chat lines and Lua errors into the `CraftProfitProbeLog` saved variable, written on `/reload`, so results can be read from `WTF/Account/<id>/SavedVariables/CraftProfitProbe.lua`. `/cpp skin` reports what the first, hand-painted UI kit (since removed) depended on: which gradient form works (`color`, `rgb` or neither), the real font path, and the pixel widths of the widest amounts. `/cpp icon` reports where the game's search magnifier comes from: the keys of the AH search box that mention an icon, the `GetAtlas`, `GetTexture` and `GetTexCoord` of `searchIcon` / `SearchIcon`, and `C_Texture.GetAtlasInfo` for `common-search-magnifyingglass`, `search-icon` and `auctionhouse-icon-search` (open the AH once first). Use it to settle an API question before coding against it.

## Packaging

The repository contains the addon in `CraftProfit/`, so release tooling must treat that folder as the top level. `CraftProfit/.pkgmeta` configures the BigWigs packager. See [curseforge/submission-checklist.md](curseforge/submission-checklist.md) for the release procedure.

The design history is in [superpowers/](superpowers/): the [design spec](superpowers/specs/2026-10-08-craftprofit-design.md) (in French) and the [implementation plan](superpowers/plans/2026-10-08-craftprofit.md).
