# Probe findings (WoW: Forever beta)

Filled in by hand after running `/cpp` commands in the game (Task 2). Build: ____ (from `/cpp locale`). Date: ____.
Status marks: ✅ measured in game · ⚠️ not measured · ❌ unusable.

## F1. Search type for reagents (`/cpp search 2772`, then `/cpp search <a weapon/armor itemID>`)
- Event received for a reagent: `COMMODITY_SEARCH_RESULTS_UPDATED` (arg1 = itemID) ✅ 2026-10-08, French client
- Event received for a piece of gear: `ITEM_SEARCH_RESULTS_UPDATED` (arg1 = itemKey table) ✅
- Fields on a result: commodity `unitPrice`, `quantity`; item `buyoutAmount`, `quantity` (`bidAmount` nil) ✅
- Latency from query to event: about 1 s per item in a queue. Zero-result search still fires the event: yes ✅ (`item results: 0`).
- Each search event arrives twice in a row (harmless; results identical).

## F2. Replicate rows (`/cpp replicate`, once per 15 min)
- Row layout matches (17 values then hasAll): yes ✅. 79,078 rows at 15:05:21, one scan.
- The event fires hundreds of times per scan (427 seen in one tail), so reads are debounced.
- For a stack row (count > 1): `buyout` is the **whole stack** ✅ → `AH.PER_UNIT_REPLICATE = false`. Evidence: spring water count 7 buyout 105 (15 each), linen bolt count 18 buyout 1476 (82 each); the scan median per unit matches the targeted search (bronze bar 323 vs 322, coarse grindstone 524 vs 524, item 11083 512 vs 512).
- Any `<SECRET>` fields: none ✅

## F3. Recipe API (`/cpp trade` with the blacksmithing window open and a recipe selected)
- Strategy A (`C_TradeSkillUI`) usable: yes / no — fields seen: ____
- Strategy B (classic `GetTradeSkill*`) usable: yes / no
- `relativeDifficulty` values for a known orange / yellow / green / grey recipe: ____ (expected 0 / 1 / 2 / 3)
- Reagent slot `reagentType` for ordinary reagents: ____ (expected `Enum.CraftingReagentType.Basic`)
- `quantityMin` / `quantityMax` / `outputItemID` present: ____

## F4. Selected recipe detection
- Which expression returns the selected recipeID while a recipe is highlighted: ____
- Does the profession window global exist before first opening (lazy-loaded)? ____

## F5. AH commission and deposit
- Measured 2026-10-08 from a sale mail (French client): 20 Wool Cloth at 1s each = 20s 00c "Prix de vente"; deposit returned +1s 32c; "Commission de l'HV" -1s 00c; received 20s 32c (2000 + 132 - 100 = 2032).
- Commission = 100 / 2000 = **5 %** of the total sale price, on top of which the deposit is refunded when the item sells. ✅ → `DB.DEFAULTS.cut = 0.05` stands.
- One data point, at a round amount: the rounding of the commission on other prices (floor / ceil / nearest) is not measured. The 8 hour deposit for 20 Wool Cloth was 1s 32c (not used by the addon: it is refunded on a sale).

## F6. Secret values
- `/cpp api` prints `issecretvalue` as `function`: yes / no
- Item names, recipe names and AH row fields that printed `<SECRET>`: ____

## F7. Enum values (printed by `/cpp api`)
- `Enum.TradeskillRelativeDifficulty`: ____
- `Enum.CraftingReagentType`: ____
- `Enum.AuctionHouseSortOrder` present: ____

## F8. Frames and locale
- AH frame global: `AuctionHouseFrame` / `AuctionFrame` — ____
- `GetLocale()`: ____ · `GetCoinTextureString(123456)`: ____
- `C_Item.GetItemInfo(2772)` fields (sellPrice, classID, bindType): ____

## F9. Magnifier icon of the AH search box (`/cpp icon`, auction house open, 2026-10)
- `AuctionHouseFrame.SearchBar.SearchBox.searchIcon` exists (the key is `searchIcon`; `SearchIcon` is nil).
- `searchIcon:GetAtlas()`: `common-search-magnifyingglass`; `GetTexture()`: `6725697` (a file id); `GetTexCoord()`: `0,0,0,1,1,0,1,1`.
- `C_Texture.GetAtlasInfo("common-search-magnifyingglass")`: found, 24 x 24 (file 6725697). `search-icon` and `auctionhouse-icon-search`: nil.
- Used by `Kit.searchIcon` (`CraftProfit/UI/Kit.lua`): the first source it tries is the one measured here.

## F10. Native templates and atlases (`/cppn`, `/cppn list`, 2026-10-09, build 1.60.1.70291)
- Templates that create and render: `ButtonFrameTemplate`, `PortraitFrameTemplate`, `DefaultPanelTemplate`, `DefaultPanelFlatTemplate`, `BasicFrameTemplateWithInset`, `InsetFrameTemplate`, `NineSlicePanelTemplate`, `UIPanelButtonTemplate`, `UICheckButtonTemplate`, `InputBoxTemplate`, `SearchBoxTemplate`, `ScrollFrameTemplate`, `MinimalScrollBar`, `WowScrollBoxList`, `PanelTabButtonTemplate`, `MagicButtonTemplate`, `UIPanelCloseButton`, `TooltipBackdropTemplate`, `QuestLogBorderFrameTemplate`.
- Atlases that exist: `questlog-reward-top-frame` (307 x 51), `questlog-reward-header-top`, `questlog-reward-bottom`, `questlog-frame`, `friends-frame-toptexbg`, `friends-frame-bottomtexbg`, `friends-frame-infobg`, `common-framedivider`, `perks-divider-short`, `looting_itemcard_bg` and `looting_itemcard_stroke_normal` (298 x 76), `common-search-magnifyingglass` (24 x 24), `_UI-Frame-TopTileStreaks` (only with the leading underscore), `auctionhouse-rowstripe-1`, `auctionhouse-background-index`, `RedButton-Exit`, `common-dropdown-a-button`, `Options_ListExpand_Right`.
- Files served to addons: `Interface\FrameGeneral\UI-Background-Rock`, `Interface\FrameGeneral\UI-Background-Marble`, `Interface\QuestFrame\UI-QuestTitleHighlight`.
- `NineSlicePanelTemplate` created without a parent raises in its `OnLoad`: it reads the parent's `layoutType`. Create it with a parent (a template that holds a `NineSlice` child, such as `ButtonFrameTemplate`, is fine with a nil parent). A templated frame that could sit under a Blizzard panel is created with a nil parent, then `SetParent` (gamepad navigation trap); the insets of our own panels and tiles are created with their own frame as parent.
- From the client source (`Gethe/wow-ui-source`, branch `forever`): after `ButtonFrameTemplate_HideAttic`, `_HidePortrait` and `_HideButtonBar` (in that order) the inset runs from (9, -24) to (-6, 4); the title bar is 20 px; the close button is 24 px at TOPRIGHT (-2, 1) (Camelot override).
- Used by `CraftProfit/UI/Native.lua`. To re-run: enable `probe/CraftProfitProbe`, `/cppn` toggles the showcase window, `/cppn list` prints every atlas, file and template above with `ok`, its size or `MISSING`; `/reload` writes the log to `CraftProfitProbe.lua` in the SavedVariables folder.

## F11: Money strings (measured 2026-10-10, `/cppn money`)

- `GetCoinTextureString` and `GetCoinText` do not exist on Forever. `GetMoneyString(copper)` does and returns the coin icons as texture escapes: `21|TInterface\MoneyFrame\UI-GoldIcon:0:0:2:0|t 29|T...UI-SilverIcon...|t 5|T...UI-CopperIcon...|t` (height 0 = the font height). `Controller.fmt` uses it and falls back to the plain `21g 29s 5c` text when it answers nothing.

## F12. Options window, minimap button and compartment (to measure in game) ⚠️

- Addon compartment: does the CraftProfit entry (TOC `AddonCompartmentFunc: CraftProfit_OnCompartmentClick`, `IconTexture: Interface\Icons\INV_Misc_Coin_01`) show on Forever's minimap? Does left click open the options and right click the main window? ⚠️
- Minimap button icon: does `GetFileIDFromPath("Interface\Icons\INV_Misc_Coin_01")` return an id (the coin draws), or does the button fall back to `INV_Misc_QuestionMark`? ⚠️
- Minimap art: `Interface\Minimap\MiniMap-TrackingBorder` (ring), `UI-Minimap-Background`, `UI-Minimap-ZoomButton-Highlight` draw and line up with the 18 px icon at TOPLEFT (7, -5)? ⚠️
