# CraftProfit in-game checklist (WoW: Forever beta)

Run on the blacksmith (level 30, skill 140+) with `/console scriptErrors 1`. Mark each line ✅ / ❌ and note the build number from `/cpp locale`-style output or the login screen. Retest on the launch build (4 November 2026).

## Capturing results to a file
The probe (v0.2.0+) mirrors everything CraftProfit and the probe print (including `/cp selftest`) and Lua errors into the `CraftProfitProbeLog` saved variable. Run the commands, then `/reload` (or log out) to flush it to `WTF/Account/<ACCOUNT>/SavedVariables/CraftProfitProbe.lua`. `/cpp log` shows how many lines are pending, `/cpp clear` empties the log. Only the probe needs to be enabled for this.

## Load and self-test
- [ ] Client starts with no Lua error popup. `/cp` prints the command list.
- [ ] `/cp selftest` prints `Self-test passed (11 checks)`.

## Profession window
- [ ] Selecting an orange recipe shows the result banner, the AH, Vendor and Disenchant tiles (Disenchant has a value when the product is armor or a weapon of uncommon quality or better) and the Materials panel.
- [ ] When the disenchant has several possible results, a grey line below it shows the most probable one (`75%: 1-2x Soul Dust = 7s 30c`); a certain result shows no such line.
- [ ] Selecting a recipe whose product cannot be sold on the AH (bind on pickup) shows `n/a` on the AH tile.
- [ ] A recipe you have not learned shows nothing (window hides or keeps the empty text).
- [ ] The window opens on the right of the profession window; dragging it and `/reload` keeps the position; `/cp reset` puts it back.
- [ ] Closing the profession window hides the window (outside the AH).
- [ ] Ticking "Cost per skill point" shows its value beside the box, with the chance used, marked `(75%, estimate)`; a grey recipe shows `n/a`.
- [ ] The Pin button toggles to Unpin and back.
- [ ] Clicking the Materials header folds the reagent detail in (`+`) and out (`-`); the choice survives `/reload`. With 5+ reagents the window grows and nothing overlaps.

## Pinned recipes by cost per point
- [ ] At the AH, the Sort button in the header of the Pinned recipes panel reads "Tri : gain"; clicking it switches to "Tri : coût/point", ticks "Coût par point" and reorders the list, cheapest first. Rows show `21g 29s 84c/pt` (red), a recipe that pays for itself shows `+9s 33c/pt` (green), a grey recipe `n/d` and an unpriced one `?`, both at the bottom.
- [ ] The value beside "Coût par point" is green with a `+` when each point pays for itself and red otherwise; the best tile is outlined in gold; "Tri : gain" lists the most profitable pin first.
- [ ] Unticking "Coût par point" returns the sort to "Tri : gain". The choice survives `/reload`.
- [ ] Level the skill until a pinned recipe changes colour: after the profession window is opened again, its cost per point follows the new colour (pins no longer keep the colour they had when pinned).

## Auction house
- [ ] Opening the AH shows the window with the Pinned recipes section (first pin selected).
- [ ] **Search prices** counts `1/N … N/N` and ends with `Prices updated`; prices and the verdict fill in; the age reads a few seconds.
- [ ] Closing the AH during a search shows `Search cancelled` with no error.
- [ ] **Scan AH** starts a scan, the client does not freeze, the status ends `Scan complete: N items priced`. A second press inside 15 minutes shows the cooldown message.
- [ ] A scan started by another addon (if installed) is picked up (prices refresh) without pressing Scan.
- [ ] After a scan, a recipe unpriced by the targeted search gets its price from the scan.

## UI kit (PR 1)
- [ ] `/cp kitdemo` opens a framed window with a title plaque, three tiles (the first outlined in gold, the last with a long amount that shrinks to fit), two panels with a header bar, and three buttons. Running it again toggles the window.
- [ ] `/cp kitdemo copper` and `/cp kitdemo steel` recolour it without `/reload` (and show it); `/cp kitdemo gold` restores it. An unknown name prints the valid names and changes nothing. The theme is not saved.
- [ ] The close button hides the window; the window can be dragged.
- [ ] Run `/cpp skin`, then `/reload` and read the `skin` lines in the probe log: gradient form, font path, widest amount widths.
- [ ] In all three themes the panel header bars show a visible vertical gradient (lighter at the top is expected); they are not white, invisible or flat.
- [ ] `/cpp skin` passes if at least one SetGradient line reports success and the font path is not nil. The probe only proves the call is accepted; `/cp kitdemo` proves it renders.
- [ ] The 1-pixel frame rings are continuous and of even thickness at the current UI scale; repeat at one other UI scale.
- [ ] The amount `999g 99s 99c` in the third tile stays inside its border.
- [ ] Hovering a normal button changes its background; moving off restores it.
- [ ] Switching theme (`/cp kitdemo copper`) repaints everything, including a button that was being hovered.
- [ ] Dragging the window by its body works. Author to report: does dragging by the upper half of the title plaque work (known gap), is the bright gold ring at the outer edge or inside it, and does the close button touch the third tile.

## Main window (PR 2)
Use a recipe with at least 5 reagents; `/console scriptErrors 1` on.
- [ ] Selecting a recipe shows the result banner, the three tiles (Auction house, Vendor, Disenchant with its beta tag), the Materials panel, the prices age line and the Options panel.
- [ ] A recipe that makes money tints the banner green; one that loses money tints it red (value shown with a minus sign); a recipe with an unpriced reagent shows the amber *Incomplete* banner. The tint stays the same through `/cp kitdemo copper`, `steel` and `gold` (it follows the result, not the theme).
- [ ] The best tile has a 2 px bright gold outline and a faint gold tint (clearly different from the other tiles, in each theme); an impossible way shows `n/a` muted, an unknown price `?`.
- [ ] Amounts: `999g 99s 99c` (use a stack of expensive reagents, or a pin with huge prices) shrinks in the banner and the tiles without running into the verdict text or leaving its box; the "RÉSULTAT" label does not touch the value.
- [ ] French client: a partial result shows "RÉSULTAT · PRIX MANQUANTS" (warning in amber) on the label line and "Meilleur connu : Hôtel des ventes" on the main line; neither is cut off or drawn over the value, including with a very large value.
- [ ] French client, "Coût par point" ticked and a gold-range cost: the label is not truncated and does not overlap the value.
- [ ] Accents render in the French titles: RÉSULTAT, DÉSENCH., COMPOSANTS, OPTIONS.
- [ ] Materials: clicking the header folds and unfolds the panel and flips the marker (`-` / `+`); the choice survives `/reload`. Unfolded with 12 reagents, the 12th row is not clipped.
- [ ] Hovering a reagent row shows a highlight above the panel background and under the text; clicking a row starts the AH search with the quantity (see *Click a reagent* below). With the AH closed it prints "Open the auction house first".
- [ ] Crafts box: type a number and wait for a price update (a search or scan) to re-render while the box still has focus: the text stays as typed. Enter, Escape or a click elsewhere applies it. 0, empty or text goes back to 1.
- [ ] Track history and Cost per skill point: both check boxes toggle and the state survives `/reload`. The per-point value shows to the right of its box: red for a cost, green with a `+` for a gain.
- [ ] Pin turns into Unpin and back; the pinned list (at the AH) follows.
- [ ] A very long recipe title is set in a smaller font, cut off inside the plaque, and stays clear of the close button.
- [ ] Drag the window by its body and by the title plaque; `/reload`; the position is restored. `/cp reset` puts it back beside the profession window.
- [ ] `/cp level` opens the leveling window beside the main window, not over it.
- [ ] At the AH with pinned recipes, the window grows by the pinned list and the list starts just below the Options panel. The pinned list now follows the same rules as the other panels (see *Pinned list and leveling window (PR 3)*).
- [ ] Closing the profession window hides the window (outside the AH); closing the AH hides it when it was opened from there.
- [ ] `/cp kitdemo`: the check box and the input box look right (box, mark, label; the input is centred, takes focus on click) in all three themes.

## Pinned list and leveling window (PR 3)
Pinned list (open the AH with pinned recipes):
- [ ] With more than 6 pins a scroll bar shows at the right edge of the list. The thumb moves with the mouse wheel over the rows, over the bar and over the empty space of the list. Dragging the thumb scrolls; clicking the track jumps there. Dragging far outside the bar and releasing stops the scrolling.
- [ ] With 6 pins or fewer there is no bar. Unpin recipes while scrolled down to the end: the list clamps back and the bar disappears when 6 or fewer are left.
- [ ] The thumb is bright enough to see against the track (known: the track itself is almost invisible on purpose).
- [ ] Pinned names are orange, yellow, green or grey, matching the profession window. The colour is the one known when the profession window was last open: gain skill points, open the profession window, and the colours follow (with the profession closed they can lag). A pin without a known difficulty shows the plain text colour.
- [ ] The selected row is tinted gold, the row under the mouse is highlighted, and a hovered selected row still looks right. Values are green for a gain, red for a loss, muted when unknown.
- [ ] The Sort button in the panel header takes clicks (profit and cost/point alternate) and does not overlap the title "RECETTES ÉPINGLÉES" under `/cp locale frFR`.
- [ ] Search prices, Scan AH and Leveling work. The status line below them: the longest French and Spanish messages (for example the "no reply from the server ... 15 minute cooldown" one) stay inside the window. Known: a status wrapping to three lines still overruns the bottom margin by about 14 px.
- [ ] The pinned block sits inside the 12 px margin like the other panels and nothing overlaps the frame border. The window grows when the AH opens and shrinks when it closes.
- [ ] `/cp kitdemo copper`, `steel`, `gold`: the pinned list, its scroll bar and its buttons repaint at once.

Leveling window (`/cp level`):
- [ ] It opens beside the main window, with the kit look; the profession button cycles through the professions read; the sort button toggles cost/point and speed.
- [ ] The grey-recipes check box shows or hides grey recipes, and the hidden count follows. Clicking the words next to the square toggles it too (every kit check box: the label is part of the click area), and the scroll bar and the row count change when the grey recipes appear.
- [ ] With more than 12 recipes the scroll bar appears and the wheel and the bar scroll. With 12 or fewer there is no bar. The window height never changes.
- [ ] A long French recipe name is cut with "..." and does not wrap; no text runs under the scroll bar.
- [ ] With no profession read, the French empty message stays inside the panel and wraps.
- [ ] Drag the window, `/reload`: the position is remembered. The x closes it. Clicking a row shows that recipe in the main window.
- [ ] `/cp kitdemo copper` (then `steel`, `gold`) repaints the leveling window.
- [ ] Known small limits of the scroll bar, not to be reported: grabbing the thumb off-centre makes it jump to centre on the pointer; any mouse button can scroll it; a lost mouse-up (alt-tab while dragging) is not recovered.

## Several crafts
- [ ] The "Crafts : [ 1 ]" box in the Options panel takes a number from 1 to 9999. Type 5 and press Enter (or click elsewhere): reagent quantities, the Materials total, the AH / vendor / disenchant values and the verdict all become five times larger, and the Materials header reads "COMPOSANTS x5 (ESTIMATION)". Cost or gain per point is unchanged.
- [ ] 0, an empty box or text goes back to 1. Selecting another recipe resets the box to 1; the pinned list always shows one craft.
- [ ] With 5 crafts, clicking "Barre de bronze" searches the AH and presets the multiplied quantity (for example 100 instead of 20), and the buy view shows the matching total.

## Leveling window
- [ ] Opening a profession window and then `/cp level` lists the learned recipes of that profession, coloured by difficulty, cheapest skill point first (use **Scan AH** beforehand; the top line shows the age of the prices). Run `/cpp known` in the profession window: the count of learned recipes must match the list plus the hidden grey ones.
- [ ] Grey recipes are hidden ("N grises masquées") and appear when *Afficher les recettes grises* is ticked; the tick survives `/reload`.
- [ ] Grey recipes only appear after the profession window has been opened once (the stored list is read when the window opens): open the profession window, then tick "Show grey recipes": the list grows and the "N grey hidden" count disappears.
- [ ] Each row shows `x1`, `x1.3` or `x4` before the amount (crafts per point); the top right button switches between *Tri : coût/point* and *Tri : vitesse* (orange first, then yellow, then green) and the choice survives `/reload`.
- [ ] The leveling window opens to the right of the main window, not over it.
- [ ] Unpriced recipes show `?` at the bottom. A recipe whose crafts pay for themselves shows `+…/pt` in green and comes first.
- [ ] Clicking a row shows the recipe in the main window; the row is highlighted.
- [ ] The list is still there at the auction house with the profession window closed, and the button under the pinned list opens it. With two professions read, the top button cycles between them.
- [ ] Opening the profession window does not hitch the client (the read is spread over a few frames).
- [ ] Leveling up until a recipe changes colour: after the profession window updates, the ranking and the colour follow.

## Price history
- [ ] The "Suivre l'historique" box sits to the right of the Crafts box in the Options panel. Ticking it on a recipe, then pressing **Scan AH** (or **Search prices** with that recipe or one sharing its reagents pinned) and `/reload`, leaves `series` entries for its items in `CraftProfit.lua` under `markets`.
- [ ] A recipe whose output is bind-on-pickup still records (its output is never priced).
- [ ] Unticking pauses recording; `/cp history` lists it as paused; `/cp history remove 1` deletes it and its series.
- [ ] A 16th tracked recipe is refused with "Trop de recettes suivies (15 maximum)".
- [ ] After an update from an earlier build, prices are still shown (adopted by the current ruleset and faction) and a character on another ruleset or faction starts with no prices.
- [ ] `/cp market` prints the ruleset name and the key the prices are saved under (for example `4613-Horde`). **At launch, and as soon as another ruleset can be created**, run it with `/cpp ruleset` on a character of each ruleset and faction: the keys must differ, or the key logic has to be revisited (see docs/technical.md, Price history).
- [ ] The saved file stays small: note the size of `CraftProfit.lua` after a few scans with 15 tracked recipes.

## Click a reagent to search it (quality of life, never buys)
- [ ] With the materials detail unfolded at the AH, hovering a reagent row highlights it. Clicking "20x Barre de bronze" opens the AH's Buy view, types the item name in the AH search box and starts the search.
- [ ] Clicking the matching result opens its buy view with the quantity already set to 20. (Best effort: if the quantity stays at 1, note the AH view; the search itself is the part that must work.)
- [ ] With the AH closed, clicking a reagent prints "Open the auction house first". No Lua error and no `ADDON_ACTION_BLOCKED` in any case. CraftProfit never presses Buy.

## Search the crafted item
Probe 0.7.0 or later. Open the AH once first (the magnifier is copied from its search box).
- [ ] Run `/cpp icon`, then `/reload`, and read the `icon` lines in the probe log: the keys of the AH search box that contain "icon", `searchIcon` / `SearchIcon` with `GetAtlas`, `GetTexture`, `GetTexCoord`, and `C_Texture.GetAtlasInfo` for `common-search-magnifyingglass`, `search-icon` and `auctionhouse-icon-search`.
- [ ] With the AH open and a recipe shown, a small magnifier shows at the top right of the AH tile and at the right of the title plaque. When the AH closes both are gone (and with no recipe shown); they come back when it reopens.
- [ ] Hovering the AH tile tints it (under the text); moving off restores it. The title lights up on hover.
- [ ] Clicking the AH tile opens the AH Buy view on the crafted item's name, in the search box (compare with clicking a reagent: same view, but no quantity preset). Same for clicking the title. No Lua error, nothing is bought.
- [ ] Drag the window by the title and by the AH tile (press and move), once with the AH open and once with it closed: the window moves, NOTHING is searched and no chat line appears. A plain click searches. A sloppy click that moves a few pixels drags instead of searching: expected.
- [ ] AH closed: clicking the tile or the title prints "Open the auction house first".
- [ ] A recipe whose product is bind on pickup: clicking prints "This item cannot be sold at the auction house" and the search box is unchanged.
- [ ] After `/cp kitdemo copper` (then `steel`, `gold`): no Lua error and the AH tile's tint still shows on hover.
- [ ] If no magnifier appears, report the `/cpp icon` lines. Known: the icon is optional, the click works without it.

## Numbers
- [ ] For one recipe, compare each reagent price with the AH listing prices: the stored price is the median of the 5 cheapest units (not the minimum).
- [ ] Sell one crafted item (or use `docs/probe-findings.md` F5): the mailed amount matches `price × (1 − cut)`. If not, change `DB.DEFAULTS.cut` and the test expectations.
- [ ] Disenchant data: disenchant three items of the same bracket several times each; the materials received are plausible against the table (`UNVERIFIED IN FOREVER` comment in `Data/Disenchant.lua` removed only when this passes).

## Languages
- [ ] `/cp locale frFR`, `/cp locale esES`, `/cp locale esMX`, `/cp locale deDE`: every label is translated or falls back to English; no raw key (`LINE_AH`…) appears; `/cp locale` returns to the client language.
- [ ] A French-client and a Spanish-client friend each run the checklist's Profession window and Auction house sections and report any untranslated or truncated text.

## Robustness
- [ ] Pin 13 recipes: the 13th is refused with `Too many pinned recipes`.
- [ ] Select a recipe while item data is not cached (first login): the Vendor and Disenchant lines show `?` and fill in on their own within a second.
- [ ] `/reload` with the AH open does not raise an error.
