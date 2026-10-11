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
- [ ] **Refresh pinned** counts `1/N … N/N` and ends with `Updated N prices` (or the longer summary, see Refresh actions); prices and the verdict fill in; the age reads a few seconds.
- [ ] Closing the AH during a search shows `Search cancelled` with no error.
- [ ] **Scan AH** starts a scan, the client does not freeze, the status ends `Scan complete: N items priced`. A second press inside 15 minutes shows the cooldown message.
- [ ] A scan started by another addon (if installed) is picked up (prices refresh) without pressing Scan.
- [ ] After a scan, a recipe unpriced by the targeted search gets its price from the scan.

## Main window (PR 2)
Use a recipe with at least 5 reagents; `/console scriptErrors 1` on.
- [ ] Selecting a recipe shows the result banner, the three tiles (Auction house, Vendor, Disenchant with its beta tag), the Materials panel, the prices age line and the Options panel.
- [ ] A recipe that makes money tints the banner green; one that loses money tints it red (value shown with a minus sign); a recipe with an unpriced reagent shows the amber *Incomplete* banner.
- [ ] The best tile has a 2 px bright gold outline and a faint gold tint (clearly different from the other tiles); an impossible way shows `n/a` muted, an unknown price `?`.
- [ ] Amounts: `999g 99s 99c` (use a stack of expensive reagents, or a pin with huge prices) shrinks in the banner and the tiles without running into the verdict text or leaving its box; the "RÉSULTAT" label does not touch the value.
- [ ] French client: a partial result shows "RÉSULTAT · PRIX MANQUANTS" (warning in amber) on the label line and "Meilleur connu : Hôtel des ventes" on the main line; neither is cut off or drawn over the value, including with a very large value.
- [ ] French client, "Coût par point" ticked and a gold-range cost: the label is not truncated and does not overlap the value.
- [ ] Accents render in the French titles: RÉSULTAT, DÉSENCH., COMPOSANTS, OPTIONS.
- [ ] Materials: clicking the header folds and unfolds the panel and flips the marker (`-` / `+`); the choice survives `/reload`. Unfolded with 12 reagents, the 12th row is not clipped.
- [ ] Hovering a reagent row shows a highlight above the panel background and under the text; clicking a row starts the AH search with the quantity (see *Click a reagent* below). With the AH closed it prints "Open the auction house first".
- [ ] Crafts box: type a number and wait for a price update (a search or scan) to re-render while the box still has focus: the text stays as typed. Enter, Escape or a click elsewhere applies it. 0, empty or text goes back to 1.
- [ ] Track history and Cost per skill point: both check boxes toggle and the state survives `/reload`. The per-point value shows to the right of its box: red for a cost, green with a `+` for a gain.
- [ ] Pin turns into Unpin and back; the pinned list (at the AH) follows.
- [ ] A very long recipe title is set in a smaller font, cut off inside the title bar, and stays clear of the close button.
- [ ] Drag the window by its body and by the title bar; `/reload`; the position is restored. `/cp reset` puts it back beside the profession window.
- [ ] `/cp level` opens the leveling window beside the main window, not over it.
- [ ] At the AH with pinned recipes, the window grows by the pinned list and the list starts just below the Options panel. The pinned list now follows the same rules as the other panels (see *Pinned list and leveling window (PR 3)*).
- [ ] Closing the profession window hides the window (outside the AH); closing the AH hides it when it was opened from there.

## Pinned list and leveling window (PR 3)
Pinned list (open the AH with pinned recipes):
- [ ] With more than 6 pins a scroll bar shows at the right edge of the list. The thumb moves with the mouse wheel over the rows, over the bar and over the empty space of the list. Dragging the thumb scrolls; clicking the track jumps there. Dragging far outside the bar and releasing stops the scrolling.
- [ ] With 6 pins or fewer there is no bar. Unpin recipes while scrolled down to the end: the list clamps back and the bar disappears when 6 or fewer are left.
- [ ] Pinned names are orange, yellow, green or grey, matching the profession window. The colour is the one known when the profession window was last open: gain skill points, open the profession window, and the colours follow (with the profession closed they can lag). A pin without a known difficulty shows the plain text colour.
- [ ] The selected row is tinted gold, the row under the mouse is highlighted, and a hovered selected row still looks right. Values are green for a gain, red for a loss, muted when unknown.
- [ ] The Sort button in the panel header takes clicks (profit and cost/point alternate) and does not overlap the title "RECETTES ÉPINGLÉES" under `/cp locale frFR`.
- [ ] Refresh pinned, Scan AH and Leveling work. The status line below them: the longest French and Spanish messages (for example the "no reply from the server ... 15 minute cooldown" one) stay inside the window. Known: a status wrapping to three lines still overruns the bottom margin by about 14 px.

Leveling window (`/cp level`):
- [ ] It opens beside the main window, with the native look; the profession button cycles through the professions read; the sort button toggles cost/point and speed.
- [ ] The grey-recipes check box shows or hides grey recipes, and the hidden count follows. Clicking the words next to the square toggles it too (every check box: the label is part of the click area), and the scroll bar and the row count change when the grey recipes appear.
- [ ] With more than 12 recipes the scroll bar appears and the wheel and the bar scroll. With 12 or fewer there is no bar. The window height never changes.
- [ ] A long French recipe name is cut with "..." and does not wrap; no text runs under the scroll bar.
- [ ] With no profession read, the French empty message stays inside the panel and wraps.
- [ ] Drag the window, `/reload`: the position is remembered. The x closes it. Clicking a row shows that recipe in the main window.

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
- [ ] The "Suivre l'historique" box sits to the right of the Crafts box in the Options panel. Ticking it on a recipe, then pressing **Scan AH** (or **Refresh pinned** with that recipe or one sharing its reagents pinned) and `/reload`, leaves `series` entries for its items in `CraftProfit.lua` under `markets`.
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
- [ ] With the AH open and a recipe shown, a small magnifier shows at the top right of the AH tile and at the right of the title. When the AH closes both are gone (and with no recipe shown); they come back when it reopens.
- [ ] Hovering the AH tile tints it (under the text); moving off restores it. The title lights up on hover.
- [ ] Clicking the AH tile opens the AH Buy view on the crafted item's name, in the search box (compare with clicking a reagent: same view, but no quantity preset). Same for clicking the title. No Lua error, nothing is bought.
- [ ] Drag the window by the title and by the AH tile (press and move), once with the AH open and once with it closed: the window moves, NOTHING is searched and no chat line appears. A plain click searches. A sloppy click that moves a few pixels drags instead of searching: expected.
- [ ] AH closed: clicking the tile or the title prints "Open the auction house first".
- [ ] A recipe whose product is bind on pickup: clicking prints "This item cannot be sold at the auction house" and the search box is unchanged.
- [ ] If no magnifier appears, report the `/cpp icon` lines. Known: the icon is optional, the click works without it.

## Native foundations (PR 5)
- [ ] `/cp kitdemo` opens a window that looks like the game's own panels (rock background, metal border, title bar, red close button, dark inset): three tiles (the first marked as best, the third greyed with a long amount that shrinks to fit), a MATERIALS panel with 3 rows and a right-hand total, an OPTIONS panel with a crafts box, a check box, two buttons (the second disabled) and a Sort button in its header, and a money line with coin icons. Chat prints the header and tile variants in use. Running it again hides it.
- [ ] Clicking the title prints `title clicked`; hovering it lights the title up. Clicking the first tile prints `tile clicked`.
- [ ] The window drags from the title bar and from the body (also from the first tile); a drag that ends on the title or the tile prints nothing.
- [ ] The red cross closes it, and so does Escape (a second Escape does not touch other windows). With the cursor in the crafts box, Escape or Enter first releases the box.
- [ ] In combat, click the red cross of the demo window and note what happens (it may do nothing in combat; report it either way, and whether Escape works then).
- [ ] Clicking the words of the check box toggles it like the box itself, with the game's click sound; the disabled button does nothing.
- [ ] The content starts right under the title bar (no empty band of rock between the title and the inset) and nothing covers the close button.
- [ ] `/cp kitdemo b a` and `/cp kitdemo c b` rebuild the window with another header strip and tile background, without `/reload`; `/cp kitdemo` alone reopens the last choice; `/cp kitdemo x` prints one line and changes nothing.
- [ ] No Lua error with any variant (`/console scriptErrors 1`).
- [ ] Send a screenshot of each variant (`a a`, `b a`, `c b`, and `a b`) next to the game's character panel (`C`), so the header strip and the tile can be picked.

## Native main window (PR 6)
- [ ] Open a recipe and compare the main window with `/cp kitdemo` and with the game's own panels (`C`, the profession window): rock background, metal border, title bar, red close button, dark inset, native header strips and tiles. Send a screenshot to the controller.
- [ ] Banner tint follows the result: green for a profit, red for a loss, amber for an incomplete result (prices missing, with the amber warning after a dot on the label line). A long warning or a long "Best: ..." text never runs under the value. The value is at most 20 px (one step smaller than before) and shrinks for a long amount.
- [ ] The best tile is outlined in gold. A long amount on a tile shrinks and never overflows its tile. With the AH open, the magnifier shows on the AH tile and after the title; with it closed, neither shows.
- [ ] Materials: the header folds and unfolds the detail (folded, the panel is just its header strip, nothing sticks out under it). Reagent rows highlight on hover over the panel body, and a click searches the reagent at the AH.
- [ ] Crafts box: type a number, then press Enter, Escape or click elsewhere: the value applies (on focus lost) and the window recomputes. It is not overwritten while you type.
- [ ] Track history and Cost per skill point check boxes toggle from the box and from their label, with the game's click sound; the per-point value shows beside its label, which is cut before it in every language. The Pin button reads Pin / Unpin and works.
- [ ] Pinned list under the window (at the AH): it still works, scrolls, and sits inside the window with the same margin; the window grows to hold it and shrinks back when it hides. The window height is right with Materials folded, with and without the "likely" line.
- [ ] Drag the window from the title bar, the body, the AH tile, a reagent row and the Materials header: it moves, and the click that ends a drag neither searches nor folds.
- [ ] With no recipe selected the window shows the empty text and nothing else.
- [ ] Close the window with the red cross. (Escape does not close it, as before.)
- [ ] No Lua error (`/console scriptErrors 1`), no `ADDON_ACTION_BLOCKED`, with the profession window and with the AH.

## Native lists (PR 7)
- [ ] Pinned list (at the AH): the Pinned recipes panel, its rows and buttons look like the game's own (dark inset, header strip, red panel buttons). Names take their difficulty colour (orange, yellow, green, grey; plain white without a known difficulty); values are green (gain), red (loss) or grey (`?`, `n/a`).
- [ ] The row of the recipe shown in the main window has the gold selected tint; the row under the mouse lights up (the game's quest highlight), visible over the panel body, also over the selected row.
- [ ] With more than 6 pins the thin game scroll bar shows at the right of the rows and never covers a value; with 6 or fewer it is hidden. The mouse wheel scrolls over the rows, over the bar and over the empty part of the list.
- [ ] Scroll bar: click the track to jump; grab the thumb near its top or bottom edge: the list does not jump, then follows the pointer; a right click on the bar does nothing; start a drag, alt-tab out, release, come back: the drag has stopped (moving the mouse does not scroll). Hovering the bar lights the thumb, dragging darkens it.
- [ ] The sort button in the panel header toggles Sort: profit / Sort: cost/point and the order changes; clicking the rest of the header does nothing else; the header has the same height as before; a long title (French) is cut before the button.
- [ ] Refresh pinned, Scan AH and Leveling work as before and the status line shows their messages (two lines for a long French message).
- [ ] Drag the main window from a pinned row: it moves, and the click that ends the drag selects nothing.
- [ ] Leveling window: opens from the Leveling button and with `/cp level`; native frame with its title and red close button (Escape does not close it, as before); the rows scroll with the wheel and the bar (more than 12 recipes); clicking a row shows the recipe in the main window; a row drag moves the window.
- [ ] Leveling window: the grey-recipes check box toggles from the box and from its label (game click sound); with grey recipes hidden, the "N hidden" text at the right never sits under the label. The profession button cycles professions; the sort button switches cost/point and speed; long labels are cut, not overflowing.
- [ ] Drag the leveling window, `/reload`, reopen it: it is where you left it. Without a saved position it opens beside the main window.
- [ ] `/cp locale frFR`: no label of the pinned list or the leveling window overflows its button, panel or window.
- [ ] `/cp theme` is gone: it prints the command list like any unknown command, and `/cp kitdemo old` prints the unknown-variant line.
- [ ] Amounts show gold, silver and copper coin icons in the tiles, the banner, the reagent rows, the pinned list and the leveling window.
- [ ] A large amount (for example 999g 99s 99c, on a costly recipe or with `/cp kitdemo`) shrinks and does not overflow its tile.
- [ ] A large per-point value (for example 999g 99s 99c/pt) in the leveling window is not cut, and the crafts figure (`x4`) stays beside it.
- [ ] `/cp kitdemo`: the money line shows coin icons.
- [ ] No Lua error (`/console scriptErrors 1`), no `ADDON_ACTION_BLOCKED`, with the profession window and with the AH.
- [ ] Screenshots of the pinned list and the leveling window next to the game's own panels (`C`, the profession window), sent to the controller.

## Options window (PR 8)
- [ ] `/cp options` opens the options window (native frame, title "CraftProfit options"); Escape closes it; `/cp options` again toggles it.
- [ ] Appearance: each header strip (Carved wood, Shade, Streaks) and each tile card (Loot card, Inset) applies at once to the main window, the pinned list (at the AH), the leveling window and the options window itself, also to a window that was closed at the time (open it after).
- [ ] All 6 combinations look right (screenshot each); the best tile keeps its outline, a muted value stays grey, hover, click and magnifier on the AH tile still work after a switch.
- [ ] The lit button always shows the saved choice when the window reopens; `/reload` keeps the choice.
- [ ] Minimap button: shown by default, bottom left of the minimap (225 degrees); left click toggles the options window, right click toggles the pinned recipes window.
- [ ] The button's icon is the gold coin (if it is a question mark, the coin file is not served: note it in probe-findings F12); the ring and the hover highlight are centred on the icon.
- [ ] Drag the button with the left button: it moves around the minimap and the release does not open anything; after `/reload` it is where you left it. With a square minimap addon, it follows the edges.
- [ ] Tooltip on hover: "CraftProfit" and three green lines (left click, right click, drag).
- [ ] Untick "Show the minimap button": it disappears; `/cp minimap` brings it back (one chat line each way); after `/reload` while hidden, no button and no chat line at login.
- [ ] Addon compartment: does the CraftProfit entry show on Forever's minimap? Note the answer in probe-findings F12; if it shows, left click toggles the options and right click the pinned recipes window.
- [ ] Windows panel: "Main window", "Leveling" and "Pinned recipes" toggle their windows.
- [ ] `/cp locale frFR` and `esES`: every button label (Bois sculpté, Madera tallada, Carte de butin...) shows in full, no `...`.
- [ ] Controls panel: the two minimap clicks then one command per line (`/cp show` ... `/cp selftest`), the command in gold and its description in white; no line wraps or overlaps the next; in French and Spanish no line is cut; about 8 px of space under the last line before the panel's bottom edge.
- [ ] No Lua error (`/console scriptErrors 1`), no `ADDON_ACTION_BLOCKED`, while switching, dragging and with the AH open.
- [ ] Screenshots of the options window (English and French) and of the minimap button, sent to the controller.

## Pinned window (PR 11)
- [ ] With the profession window and the AH closed, `/cp pins` opens the "Pinned recipes" window (native frame; the first time, left of the middle of the screen when no other CraftProfit window is open); `/cp pins` again closes it; Escape closes it.
- [ ] Rows: names in their difficulty colours, values with coin icons (green gain, red loss, grey `?` for a pin with a missing price, never an error).
- [ ] Age line: the age of the oldest price the pins use; orange when older than an hour or never priced. After **Refresh pinned** at the AH (no full scan), the line shows a recent age, not "never scanned".
- [ ] Sort button: switches profit and cost/point and relabels; the list under the main window at the AH follows the same choice.
- [ ] The "x" of a row: tooltip "Unpin"; a click unpins the recipe, the rows below move up, the main window does not open and the selection does not change.
- [ ] A click elsewhere on a row opens the main window on that recipe with its stored prices (with the profession window and the AH closed too); a row drag moves the window and selects nothing.
- [ ] With 12 pins everything shows; scroll with the mouse wheel and the bar after unpinning and re-pinning (the bar hides while everything fits); unpinning the last row while scrolled to the bottom moves the list, no gap.
- [ ] Empty state: with no pin, the window says "No pinned recipes. Pin a recipe from its window."
- [ ] Drag the window, `/reload`, reopen it: it is where you left it.
- [ ] Minimap right click and addon compartment right click open and close it; the tooltip says "Right click: pinned recipes".
- [ ] At the AH, the list under the main window still works; pin or unpin from the main window and from the "x": both lists stay in sync.
- [ ] Options window Windows panel: "Main window" and "Leveling" on the first row, "Pinned recipes" centred on the second; in English, `/cp locale frFR` and `/cp locale esES` ("Fenêtre principale", "Montée de métier", "Recettes épinglées"; "Ventana principal", "Subida", "Recetas fijadas") no label is cut; the Controls list has `/cp pins` and the right click.
- [ ] `/cp locale frFR`: no label of the pinned window overflows (title, sort button, empty text, long recipe names cut before the value and the "x").
- [ ] No Lua error (`/console scriptErrors 1`), no `ADDON_ACTION_BLOCKED`, with and without the AH open.

## Pinned recipes limit
- [ ] A fresh save: `/cp options` shows the PINNED RECIPES panel with 20 lit. Pin recipes up to 20: the 21st is refused with `Pinned recipes limit reached (20). Raise it in /cp options.`; nothing is added.
- [ ] Click 30 in `/cp options` (window left open): the next pin works at once, up to 30; close and reopen the options window, `/reload`: 30 is still lit.
- [ ] Lower the limit to 12 with more than 12 pins: no pin is deleted (count them in `/cp pins`, also after `/reload`), a new pin is refused with the message, unpinning still works from the main window and from the "x".
- [ ] Set 40 and pin 40 recipes (or as many as you can): the list under the main window at the AH and the pinned recipes window both scroll with the wheel and the bar to the last pin; the "x" of the bottom row while scrolled to the end unpins it and the list moves up with no gap.
- [ ] **Refresh pinned** with many pins still completes. 20 pinned recipes: about a minute (measured 2026-10-11 on the beta); **Scan AH** as the faster option.
- [ ] The options window is now about 676 px tall (the note on three lines): at your usual UI scale it fits on screen whole (title bar to the bottom of CONTROLS), and again at a smaller resolution if you can.
- [ ] The note under the limit buttons (search time, Scan AH) fits in three lines, nothing cut, the panel exactly as tall as its lines, in English, `/cp locale frFR` and `/cp locale esES`; the "Limit per character" label and the 12 / 20 / 30 / 40 buttons are not cut either.
- [ ] The panel title of the list at the AH and of the pinned recipes window reads `PINNED RECIPES (n/limit)` and follows a pin, an unpin (main window and "x") and a limit change at once; in French and Spanish too; at the AH the title is cut before the sort button, never under it (check `RECETTES ÉPINGLÉES (40/40)`).
- [ ] No Lua error, no `ADDON_ACTION_BLOCKED`.

## Refresh actions
- [ ] Main window Options panel: **Pin** and **Refresh recipe** share the last row, same width, nothing cut in English, `/cp locale frFR` ("Épingler" / "Actualiser recette") and `/cp locale esES` ("Fijar" / "Actualizar receta"); the window height is the same as before.
- [ ] Away from the AH (profession window open, a recipe shown): Refresh recipe is greyed and a click does nothing. At the AH with a recipe shown: enabled. At the AH with the empty window ("Select a recipe"): greyed.
- [ ] At the AH, pick a recipe with old prices, press **Refresh recipe**: the status counts `1/N … N/N` over that recipe's items only (reagents, output, disenchant materials when shown), ends within seconds (note how many), and only that recipe's prices and age change (another pin keeps its old age in the pinned window).
- [ ] While any search runs (recipe or pinned), Refresh recipe is greyed; it comes back at the end. Pressing **Refresh pinned** during a recipe refresh does nothing; the recipe refresh finishes normally.
- [ ] **Refresh pinned** right after a recipe refresh: counts all the pinned items and its summary does not carry the previous misses.
- [ ] Summary lines: everything found shows `Updated N prices`; an item nobody sells (search a rare reagent) shows `Updated N-1 of N prices · no listing: <its name> (nobody is selling them now)` (the three numbers add up to N; a recipe nobody sells anything of shows `Updated 0 of N prices · no listing: N ...`); a slow server or a throttled search shows `· no answer: <name>, try again` (one or two names, a number from three on); both can show together; the line never goes past two lines (long names cut with `...`), also in French (`sans réponse : Barre d'argent, réessayez`, non-breaking space before the colon) and Spanish.
- [ ] For a recipe with 5 materials whose item can be disenchanted, Refresh recipe counts 7 prices (5 materials, the crafted item, a disenchant material): note the counts and that the named missing item is one of these.
- [ ] Close the AH mid-search (recipe or pinned): `Search cancelled`, no Lua error; reopen the AH: Refresh recipe is enabled again.
- [ ] The options window note names **Refresh pinned** (and its French and Spanish names), still on three lines at most.

## Default placement (PR 19 fixes)
- [ ] Delete the saved positions (`/run CraftProfitDB.settings.pinsWindow=nil CraftProfitDB.settings.levelWindow=nil CraftProfitDB.settings.optionsWindow=nil CraftProfitDB.settings.window=nil` then `/reload`).
- [ ] Open the profession window and select a recipe: the main window opens beside it. Then `/cp level`, `/cp pins` and `/cp options` one after the other: each opens just right of the rightmost window already open, none on top of another; near the screen edge it stays on screen.
- [ ] Close all, `/cp pins` alone: left of the middle of the screen; `/cp options` alone: in the middle; then `/cp show`: the main window opens right of the open one.
- [ ] Drag one window, close and reopen it: it is where you left it, whatever else is open; same after `/reload`.
- [ ] With no profession or AH window: `/cp pins`, then `/cp show`: the main window opens right of the pinned window, not over it.
- [ ] No Lua error, no window jumping when another one closes.

## Window front and height (PR 19 fixes)
- [ ] Empty main window ("Select a recipe", `/cp show` without a recipe): the metal border is whole, no corner or side piece sticks out above the title bar or below the bottom.
- [ ] With the Cooldown Manager (or another HUD panel) on screen, our windows draw fully above it.
- [ ] Open the main, leveling, pinned and options windows overlapping: click the body, a row, a button or the title of each in turn: the clicked window comes fully to the front, its border and content above the others, never mixed with another window's border.
- [ ] A window opened last shows in front of the ones already open.

## Numbers
- [ ] For one recipe, compare each reagent price with the AH listing prices: the stored price is the median of the 5 cheapest units (not the minimum).
- [ ] Sell one crafted item (or use `docs/probe-findings.md` F5): the mailed amount matches `price × (1 − cut)`. If not, change `DB.DEFAULTS.cut` and the test expectations.
- [ ] Disenchant data: disenchant three items of the same bracket several times each; the materials received are plausible against the table (`UNVERIFIED IN FOREVER` comment in `Data/Disenchant.lua` removed only when this passes).

## Languages
- [ ] `/cp locale frFR`, `/cp locale esES`, `/cp locale esMX`, `/cp locale deDE`: every label is translated or falls back to English; no raw key (`LINE_AH`…) appears; `/cp locale` returns to the client language.
- [ ] A French-client and a Spanish-client friend each run the checklist's Profession window and Auction house sections and report any untranslated or truncated text.

## Robustness
- [ ] With the limit at 12 (`/cp options`), pin 13 recipes: the 13th is refused with `Pinned recipes limit reached (12). Raise it in /cp options.`
- [ ] Select a recipe while item data is not cached (first login): the Vendor and Disenchant lines show `?` and fill in on their own within a second.
- [ ] `/reload` with the AH open does not raise an error.
