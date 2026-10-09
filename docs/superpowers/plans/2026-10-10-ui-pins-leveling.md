# UI pinned list and leveling window (PR 3 of 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the pinned-recipes list (shown under the main window at the auction house) and the leveling window on the shared UI kit, add a scroll bar to both lists, and colour the pinned recipe names by difficulty (orange, yellow, green, grey) like the leveling list.

**Architecture:** A new kit widget `Kit.scrollbar` (pure thumb arithmetic + a thin drag/click widget) serves both lists. `Window` places the pinned host inside its content inset (12 px) instead of full width. `PinsUI.lua` keeps all its logic (search queue, scan, sorting) and only its widgets change: a kit panel with a small Sort button in its header, themed rows, a scroll bar, kit buttons. `LevelingUI.lua` becomes a kit window with a profession/sort strip, a prices-age line, a "Next point" panel and the grey-recipes check box. Public interfaces of `PinsUI` and `LevelingUI` are unchanged, so `Boot.lua` does not change.

**Tech Stack:** Lua 5.1 (WoW client), LuaJIT test harness (`tests/harness.lua`, `tests/fakewow.lua`), luacheck.

**Spec:** `docs/superpowers/specs/2026-10-09-ui-rework-design.md`. Previous PRs: `docs/superpowers/plans/2026-10-09-ui-foundations.md`, `docs/superpowers/plans/2026-10-09-ui-main-window.md`.

## Plan amendments to the spec

- New kit widget `Kit.scrollbar(parent, trackH)` (not in the spec), with pure helpers `Kit.scrollThumb` and `Kit.scrollOffsetAt`. The mouse wheel keeps working; the bar shows that a list scrolls and where it is, can be clicked and dragged, and hides itself when the whole list fits.
- Pinned recipe names take the difficulty colour (`Theme.FIXED` keys `optimal`, `medium`, `easy`, `trivial`) from `recipe.difficulty`. The colour is the one stored with the pin, refreshed whenever the profession window is open (`Controller.refreshPinDifficulties`): with the profession closed it can be a few skill points behind. Documented, not hidden.
- The selected pinned row is tinted with `bestFill`, hovered rows with `rowHover` (theme tokens).
- New locale key `LEVEL_PANEL` (title of the leveling list panel) in en, fr, es.
- `Window.INNER_WIDTH` (= `WIDTH - 2 * Kit.CONTENT_SIDE`) is exported; the pinned host is as wide as that and starts `Kit.GAP` below the Options panel; `Window.relayout` adds `Kit.GAP + host height` when the host is shown (it added the host height only).
- PR 2 polish folded in: the empty-state text follows the theme, the tile row fills the content width exactly, `panel:onHeaderClick` reuses its hit button on a second call.

## Global Constraints

- Interface 16001, Lua 5.1: no `goto`, `require`, `io`, `loadfile`, `dofile`, `setfenv`, `getfenv` in addon files, comments included (`tests/test_toc.lua` scans the text; a word ending in "io." matches `io%.`).
- No literal zero divisor anywhere in `CraftProfit/` (`tests/test_source.lua`; the game raises "Division by zero").
- Every game global the addon reads is declared in `.luacheckrc`; `sh tests/check.sh` must end with 0 failures and 0 warnings.
- Every file listed in `CraftProfit.toc` exactly once; no file on disk unlisted.
- English only for code comments and docs, except the French texts in `Locales/frFR.lua`, `docs/user-guide.fr.md`, `README.fr.md` and the Spanish ones in `Locales/esES.lua`.
- Panel titles and tile labels are written already in capitals in the locale files (`string.upper` does not handle UTF-8 accents in Lua 5.1).
- Never mention a co-author in commits, pushes or PR bodies. Verify with `git log --format=%B | grep -ci co-authored` (must print 0).
- Branch `feat/ui-pins-leveling`, one PR, merged only when the author says so. gh must be logged in as **Renaud-Sto**.
- Several Lua files flip to mode 755 in the working tree by themselves: run `git status --short` before every commit and `chmod 644` any Lua file listed as modified that you did not edit.
- Kit rules learned in the two previous PRs, binding here: texts measured to fit use `Kit.naturalWidth`; behaviour on OnEnter/OnLeave uses `HookScript`, never `SetScript`; `SetFontObject` resets a text colour, so repaint the colour after calling it; a real frame is created SHOWN and unanchored (hide it, anchor it); a panel header hit button sits at the panel frame's level, header buttons parented to the panel frame sit above it; widgets paint themselves through `Kit.onTheme` so a theme switch repaints them.
- Behaviour that must not change: price search and scan logic and their status texts; sort modes and the `Tri : ...` button; selecting a pinned recipe shows it in the main window; the pinned list appears only while the auction house is open; Search prices is cancelled when the AH closes; the leveling window opens beside the main window, is movable and remembers its position (`CraftProfitDB.settings.levelWindow`), cycles professions, sorts by cost or speed, shows grey recipes only when asked, clicking a row shows that recipe in the main window.

## Review Focus

- Scroll bar: the thumb size and position follow the offset; it hides when the list fits; a click or drag on the track scrolls; the mouse wheel still scrolls and updates the bar; the offset is always clamped (0 .. total - visible) after a pin is added or removed.
- Pinned colours: a pin with a known difficulty is coloured by it, one without (nil) keeps the main text colour; grey (trivial) is grey; value colours (gain, loss, unknown) are unchanged.
- Window height with the pinned list shown always equals `contentHeight + Kit.GAP + host height`; hiding the host (AH closes) restores `contentHeight`; no clipped or overlapping block.
- The leveling window keeps one fixed height whatever the number of recipes; its rows never run under the scroll bar; long French recipe names are truncated, not wrapped.
- Theme switch repaints both lists (rows, scroll bar, buttons).

## File Structure

| File | Responsibility |
| --- | --- |
| `.luacheckrc` | `GetCursorPosition` |
| `CraftProfit/UI/Kit.lua` | `scrollThumb`, `scrollOffsetAt`, `scrollbar`; `onHeaderClick` guard |
| `CraftProfit/UI/Window.lua` | pinned host placement, empty-state theme, tile row |
| `CraftProfit/UI/PinsUI.lua` | widgets rebuilt on the kit, difficulty colours, scroll bar |
| `CraftProfit/UI/LevelingUI.lua` | rebuilt on the kit |
| `CraftProfit/Locales/*.lua` | `LEVEL_PANEL` |
| `tests/test_kit.lua`, `test_window.lua`, `test_pinsui.lua`, `test_levelingui.lua` (new) | tests |
| docs | technical, checklist, guides EN/FR, changelog, spec |

---

### Task 1: Kit scroll bar and header-click guard

**Files:**
- Modify: `CraftProfit/UI/Kit.lua`, `.luacheckrc`
- Test: `tests/test_kit.lua`

**Interfaces:**
- Produces on `ns.Kit`: constants `SCROLL_W = 8`, `SCROLL_MIN_THUMB = 16`; `scrollThumb(total, visible, offset, trackH) -> thumbH, top` (both numbers, `top` is the distance in pixels from the track top; returns `nil` when everything fits or an argument is unusable); `scrollOffsetAt(total, visible, trackH, y) -> offset` (integer in `0 .. total - visible`; `y` is the pointer distance below the track top); `scrollbar(parent, trackH) -> bar` with `bar.frame` (the track, a Button, hidden while the list fits), `bar.thumb` (texture), `bar:update(total, visible, offset) -> shown`, `bar.onScroll` (optional callback `fn(offset)` called when a click or drag asks for another offset).
- `panel:onHeaderClick(fn)` called a second time reuses the existing hit button and replaces its click handler (returns the same button).
- New game global `GetCursorPosition` (declared in `.luacheckrc` `read_globals`).

- [ ] **Step 1: Write the failing tests** (append to `tests/test_kit.lua`; `W`, `load()`, `boot()`, `recordingFrames` exist)

```lua
H.test("scrollThumb sizes and places the thumb, nil when the list fits", function()
    local Kit = load()
    local h, top = Kit.scrollThumb(12, 6, 0, 100)
    H.eq({ h, top }, { 50, 0 })
    h, top = Kit.scrollThumb(12, 6, 6, 100)
    H.eq({ h, top }, { 50, 50 })
    h, top = Kit.scrollThumb(12, 6, 3, 100)
    H.eq({ h, top }, { 50, 25 })
    h, top = Kit.scrollThumb(1000, 6, 0, 100)
    H.eq(h, Kit.SCROLL_MIN_THUMB)
    H.eq(Kit.scrollThumb(6, 6, 0, 100), nil)
    H.eq(Kit.scrollThumb(3, 6, 0, 100), nil)
    H.eq(Kit.scrollThumb(12, 0, 0, 100), nil)
    H.eq(Kit.scrollThumb(12, 6, 0, 0), nil)
    H.eq(Kit.scrollThumb(nil, 6, 0, 100), nil)
    h, top = Kit.scrollThumb(12, 6, 99, 100)
    H.eq(top, 50)
    h, top = Kit.scrollThumb(12, 6, -4, 100)
    H.eq(top, 0)
end)

H.test("scrollOffsetAt maps a pointer position to a row offset and clamps it", function()
    local Kit = load()
    H.eq(Kit.scrollOffsetAt(12, 6, 100, 0), 0)
    H.eq(Kit.scrollOffsetAt(12, 6, 100, 100), 6)
    H.eq(Kit.scrollOffsetAt(12, 6, 100, 50), 3)
    H.eq(Kit.scrollOffsetAt(12, 6, 100, -30), 0)
    H.eq(Kit.scrollOffsetAt(12, 6, 100, 400), 6)
    H.eq(Kit.scrollOffsetAt(5, 6, 100, 50), 0)
    H.eq(Kit.scrollOffsetAt(nil, 6, 100, 50), 0)
end)

local function withCursor(y, fn)
    local saved = _G.GetCursorPosition
    _G.GetCursorPosition = function() return 0, y end
    local ok, err = pcall(fn)
    _G.GetCursorPosition = saved
    if not ok then error(err, 0) end
end

H.test("the scroll bar hides when the list fits and shows a thumb of the right size otherwise", function()
    local _, Kit = boot()
    local bar = Kit.scrollbar(nil, 100)
    H.falsy(bar:update(6, 6, 0))
    H.falsy(bar.frame.shown)
    local heights = {}
    bar.thumb.SetHeight = function(_, h) heights[#heights + 1] = h end
    H.truthy(bar:update(12, 6, 3))
    H.truthy(bar.frame.shown)
    H.eq(heights[#heights], 50)
    H.falsy(bar:update(4, 6, 0))
    H.falsy(bar.frame.shown)
end)

H.test("clicking the scroll bar track asks for the matching offset and dragging follows the pointer", function()
    local _, Kit = boot()
    local bar = Kit.scrollbar(nil, 100)
    local asked = {}
    bar.onScroll = function(offset) asked[#asked + 1] = offset end
    bar:update(12, 6, 0)
    bar.frame.GetTop = function() return 700 end
    bar.frame.GetEffectiveScale = function() return 1 end
    -- pointer 100 px below the top of the track: bottom of the track, last offset
    withCursor(600, function() bar.frame.scripts.OnMouseDown(bar.frame) end)
    H.eq(asked, { 6 })
    bar:update(12, 6, 6)
    -- still pressed: moving to the middle follows it
    withCursor(650, function() bar.frame.scripts.OnUpdate(bar.frame) end)
    H.eq(asked, { 6, 3 })
    -- released: no more following
    bar.frame.scripts.OnMouseUp(bar.frame)
    withCursor(700, function() bar.frame.scripts.OnUpdate(bar.frame) end)
    H.eq(asked, { 6, 3 })
end)

H.test("the scroll bar ignores a pointer it cannot measure and works without a callback", function()
    local _, Kit = boot()
    local bar = Kit.scrollbar(nil, 100)
    bar:update(12, 6, 0)
    bar.frame.scripts.OnMouseDown(bar.frame)
    bar.frame.scripts.OnUpdate(bar.frame)
    bar.frame.GetTop = function() return 700 end
    bar.frame.GetEffectiveScale = function() return 1 end
    withCursor(600, function() bar.frame.scripts.OnMouseDown(bar.frame) end)
    bar.frame.scripts.OnMouseUp(bar.frame)
end)

H.test("the scroll bar is painted from the theme and survives theme switches", function()
    local T, Kit = boot()
    local rec = recordingFrames(T)
    local Theme = T.ns.Theme
    local bar = Kit.scrollbar(nil, 100)
    H.eq(rec[1].color, Theme.get("gold").inputBg)
    H.eq(rec[2].color, Theme.get("gold").frameInner)
    Kit.applyTheme("steel")
    H.eq(rec[1].color, Theme.get("steel").inputBg)
    H.eq(rec[2].color, Theme.get("steel").frameInner)
    H.truthy(bar)
end)

H.test("onHeaderClick called twice reuses the hit button and replaces its handler", function()
    local _, Kit = boot()
    local panel = Kit.panel(nil, "X")
    local hits = {}
    local first = panel:onHeaderClick(function() hits[#hits + 1] = "a" end)
    local second = panel:onHeaderClick(function() hits[#hits + 1] = "b" end)
    H.eq(first, second)
    first.scripts.OnClick(first)
    H.eq(hits, { "b" })
end)
```

- [ ] **Step 2: Run to see failures**

Run: `luajit tests/run.lua 2>&1 | grep FAIL | head`
Expected: failures (functions missing).

- [ ] **Step 3: Implement.** Append to `CraftProfit/UI/Kit.lua` (after `Kit.input`):

```lua
-- Scroll bar ------------------------------------------------------------------

Kit.SCROLL_W = 8
Kit.SCROLL_MIN_THUMB = 16

-- Thumb height and its distance from the top of the track, for a list of `total` rows
-- of which `visible` show from row `offset` (0-based). nil when everything fits.
function Kit.scrollThumb(total, visible, offset, trackH)
    if type(total) ~= "number" or type(visible) ~= "number" or type(trackH) ~= "number" then return nil end
    if visible <= 0 or total <= visible or trackH <= 0 then return nil end
    local thumbH = math.max(Kit.SCROLL_MIN_THUMB, math.floor(trackH * visible / total + 0.5))
    thumbH = math.min(thumbH, trackH)
    local range = total - visible
    local at = math.max(0, math.min(offset or 0, range))
    return thumbH, math.floor((trackH - thumbH) * at / range + 0.5)
end

-- Row offset for a pointer `y` pixels below the top of the track, the thumb centred on
-- it; always inside 0 .. total - visible.
function Kit.scrollOffsetAt(total, visible, trackH, y)
    local thumbH = Kit.scrollThumb(total, visible, 0, trackH)
    if not thumbH or type(y) ~= "number" then return 0 end
    local free = trackH - thumbH
    if free <= 0 then return 0 end
    local fraction = math.max(0, math.min(1, (y - thumbH / 2) / free))
    return math.floor(fraction * (total - visible) + 0.5)
end

-- A slim scroll bar for a list that shows `visible` of `total` rows. The track takes
-- clicks and drags; `bar.onScroll(offset)` is asked for the matching row offset and
-- the owner calls `bar:update(total, visible, offset)` after it has scrolled. Hidden
-- while the whole list fits.
function Kit.scrollbar(parent, trackH)
    local bar = { trackH = trackH, total = 0, visible = 0, offset = 0 }
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(Kit.SCROLL_W, trackH)
    bar.frame = f
    local track = f:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(f)
    bar.thumb = f:CreateTexture(nil, "ARTWORK")
    register(function()
        paintTexture(track, "inputBg")
        paintTexture(bar.thumb, "frameInner")
    end)

    function bar:update(total, visible, offset)
        self.total, self.visible, self.offset = total, visible, offset
        local thumbH, top = Kit.scrollThumb(total, visible, offset, self.trackH)
        if not thumbH then
            f:Hide()
            return false
        end
        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -top)
        self.thumb:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -top)
        self.thumb:SetHeight(thumbH)
        f:Show()
        return true
    end

    local dragging = false
    local function follow()
        local _, cursorY = GetCursorPosition()
        local top, scale = f:GetTop(), f:GetEffectiveScale()
        if type(cursorY) ~= "number" or type(top) ~= "number" or type(scale) ~= "number" or scale <= 0 then
            return
        end
        local offset = Kit.scrollOffsetAt(bar.total, bar.visible, bar.trackH, top - cursorY / scale)
        if offset ~= bar.offset and bar.onScroll then bar.onScroll(offset) end
    end
    f:SetScript("OnMouseDown", function() dragging = true; follow() end)
    f:SetScript("OnMouseUp", function() dragging = false end)
    f:SetScript("OnHide", function() dragging = false end)
    f:SetScript("OnUpdate", function() if dragging then follow() end end)
    f:Hide()
    return bar
end
```

In `Kit.panel`, replace `p:onHeaderClick`:

```lua
    -- A button covering the header, e.g. to fold the panel. Returns it (also p.headerHit);
    -- calling it again replaces the handler of the same button. The hit button sits at
    -- the panel frame's level, below the header's own buttons.
    function p:onHeaderClick(fn)
        if not self.headerHit then
            local hit = CreateFrame("Button", nil, head)
            hit:SetAllPoints(head)
            hit:SetFrameLevel(f:GetFrameLevel())
            self.headerHit = hit
        end
        self.headerHit:SetScript("OnClick", fn)
        return self.headerHit
    end
```
(keep whatever comment lines about the level the current code has; the behaviour of the first call is unchanged.) Add `"GetCursorPosition"` to the `read_globals` list in `.luacheckrc`.

- [ ] **Step 4: Run the whole suite**

Run: `sh tests/check.sh 2>&1 | grep -E "passed|failed|Total|FAIL"`
Expected: `0 failed`, `0 warnings`.

- [ ] **Step 5: Commit**

```bash
git status --short   # chmod 644 any Lua file you did not edit
git add CraftProfit/UI/Kit.lua .luacheckrc tests/test_kit.lua
git commit -m "feat: kit scroll bar with pure thumb arithmetic; header click guard"
```

---

### Task 2: Window: pinned host placement and PR 2 polish

**Files:**
- Modify: `CraftProfit/UI/Window.lua`
- Test: `tests/test_window.lua`

**Interfaces:**
- Consumes: `Kit.GAP`, `Kit.CONTENT_SIDE`, `Kit.CONTENT_BOTTOM`.
- Produces: `Window.INNER_WIDTH` (348 for the 372 window); `Window.pinsHost()` returns a frame `INNER_WIDTH` wide anchored `Kit.CONTENT_SIDE` from the left and `Kit.GAP` below the last section; `Window.relayout()`: frame height = `contentHeight` plus, when the host is shown, `Kit.GAP + host height`. The empty-state text (`Window.parts.empty`) follows the theme (`textMuted`). The three tiles together span exactly `INNER_WIDTH` (the last one takes the remainder).

- [ ] **Step 1: Write the failing tests** (in `tests/test_window.lua`: update, then add; `boot()`, `model()` exist there)

Update the existing test "the frame height is the sum of the visible sections plus the insets, and the pinned list adds its own": the last assertion becomes `H.eq(Window.frame().height, expected + Kit.GAP + 100)`.

Add:

```lua
H.test("the pinned host is as wide as the content and hangs a gap below the last section", function()
    local T, Window = boot()
    local Kit = T.ns.Kit
    H.eq(Window.INNER_WIDTH, 372 - Kit.CONTENT_SIDE * 2)
    local widths = {}
    local points = {}
    local host = Window.pinsHost()
    host.SetWidth = function(_, w) widths[#widths + 1] = w end
    host.SetPoint = function(_, ...) points[#points + 1] = { ... } end
    Window.render(model())
    host:Show()
    host:SetHeight(100)
    Window.relayout()
    local list = Window.sections({ hasLikely = false, expanded = true, reagents = 2 })
    local top = Window.contentHeightOf(list) - Kit.CONTENT_BOTTOM + Kit.GAP
    local last = points[#points]
    H.eq(last[1], "TOPLEFT")
    H.eq(last[3], "TOPLEFT")
    H.eq(last[4], Kit.CONTENT_SIDE)
    H.eq(last[5], -top)
end)

H.test("the pinned host is created INNER_WIDTH wide", function()
    local T = W.boot(H)
    local widths = {}
    local create = T.env.CreateFrame
    T.env.CreateFrame = function(...)
        local f = create(...)
        f.SetWidth = function(_, w) widths[#widths + 1] = w end
        return f
    end
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    local found = false
    for _, w in ipairs(widths) do if w == T.ns.Window.INNER_WIDTH then found = true end end
    H.truthy(found)
end)

H.test("the tiles together fill the content width exactly", function()
    local T, Window = boot()
    local Kit = T.ns.Kit
    local sizes = {}
    -- the tile frames are created before the test can wrap them: read their widths back
    for i, tile in ipairs(Window.parts.tiles) do sizes[i] = tile.width end
    H.eq(sizes[1] + sizes[2] + sizes[3] + Kit.GAP * 2, Window.INNER_WIDTH)
end)

H.test("the empty-state text follows the theme", function()
    local T, Window = boot()
    local colour
    Window.parts.empty.SetTextColor = function(_, r, g, b, a) colour = { r, g, b, a } end
    T.ns.Kit.applyTheme("steel")
    H.eq(colour, T.ns.Theme.get("steel").textMuted)
end)
```
(The tile test reads `tile.width`: `Kit.tile` must therefore record `tile.width = width` — add that one line in `Kit.tile` (`local tile = { best = false, muted = false, width = width }`) as part of this task, and test it through this assertion.)

- [ ] **Step 2: Run to see failures**

Run: `luajit tests/run.lua 2>&1 | grep FAIL | head`
Expected: failures.

- [ ] **Step 3: Implement.** In `CraftProfit/UI/Window.lua`:

```lua
Window.INNER_WIDTH = WIDTH - Kit.CONTENT_SIDE * 2
```
(next to `Window.WIDTH = WIDTH`). `buildTiles`: widths so that they fill the row:

```lua
local function buildTiles()
    local f = newSection("tiles", TILE_H)
    local width = math.floor((Window.INNER_WIDTH - Kit.GAP * 2) / 3)
    local x = 0
    for i = 1, 3 do
        local w = i < 3 and width or Window.INNER_WIDTH - x
        local tile = Kit.tile(f, w, TILE_H)
        tile.frame:SetPoint("TOPLEFT", f, "TOPLEFT", x, 0)
        parts.tiles[i] = tile
        x = x + w + Kit.GAP
    end
end
```
`Window.create`: `pinsHost:SetWidth(Window.INNER_WIDTH)` and `themed(parts.empty, "textMuted")` right after `parts.empty` is created. `Window.relayout`:

```lua
function Window.relayout()
    if not frame then return end
    pinsHost:ClearAllPoints()
    pinsHost:SetPoint("TOPLEFT", frame, "TOPLEFT", Kit.CONTENT_SIDE, -(contentHeight - Kit.CONTENT_BOTTOM + Kit.GAP))
    local extra = pinsHost:IsShown() and (Kit.GAP + pinsHost:GetHeight()) or 0
    frame:SetHeight(contentHeight + extra)
end
```
In `Kit.tile` record the width: `local tile = { best = false, muted = false, width = width }`. Update the "Frame height" comment above `relayout`.

- [ ] **Step 4: Run the whole suite**

Run: `sh tests/check.sh 2>&1 | grep -E "passed|failed|Total|FAIL"`
Expected: `0 failed`, `0 warnings`. `tests/test_pinsui.lua` and `tests/test_boot.lua` must still pass unchanged.

- [ ] **Step 5: Commit**

```bash
git status --short
git add CraftProfit/UI/Window.lua CraftProfit/UI/Kit.lua tests/test_window.lua
git commit -m "feat: pinned host inside the window content inset; tiles fill the row; themed empty text"
```

---

### Task 3: Pinned list on the kit

**Files:**
- Modify: `CraftProfit/UI/PinsUI.lua`
- Test: `tests/test_pinsui.lua`

**Interfaces:**
- Consumes: Task 1 (`Kit.scrollbar`, `panel`, `button`), Task 2 (`Window.INNER_WIDTH`, host placement), `Theme.FIXED`, `Kit.onTheme`, the controller (`ctl.evaluate`, `ctl.fmt`, `ctl.currentRecipeID`, `ctl.selectPin`, `ctl.toggleSort`, `ctl.itemInfo`, `ctl.recordListings`, `ctl.commitSearch`, `ctl.requestRefresh`, `ctl.knowsEnchanting`).
- Produces: `PinsUI.parts = { panel, rows, bar, sort, search, scan, level, empty }` (for tests); all existing public functions unchanged: `PinsUI.state`, `PinsUI.status`, `setStatus`, `wantedFor`, `orderedPins`, `refresh`, `startSearch`, `scan`, `onAHOpen`, `onSearchResults`, `init`.
- Behaviour: the list lives in a kit panel titled `L.PINS_TITLE`; the Sort button is a small kit button in the panel header; rows (6 visible) show the recipe name coloured by its stored difficulty and the value (gain green, loss red, `?`/n/a muted); the selected row is tinted `bestFill`, a hovered row `rowHover`; a `Kit.scrollbar` sits on the right of the rows and shows only when there are more pins than rows; the mouse wheel on the host still scrolls and updates the bar; the three buttons are kit buttons (Search prices primary); status text below.

- [ ] **Step 1: Write the failing tests** (append to `tests/test_pinsui.lua`; its `boot()` returns `T, pins` with 2 pins `recipeID` 1 and 2; `raw(id, output, reagents)` builds a pin; pins from `raw` have `difficulty = 1`, which `Skillup.name` maps to a name: read `CraftProfit/Data/Skillup.lua` and `Recipes.lua` to see what `DB.pinAdd` stores, and set `difficulty` explicitly on the pins in the tests below to `"optimal"`, `"easy"`, `"trivial"` or nil)

```lua
local function openList(T)
    T.ns.AH.isOpen = true
    T.ns.Controller.onAHOpen(true)
    return T.ns.PinsUI.parts
end

H.test("pinned names take the colour of their difficulty, a missing difficulty keeps the text colour", function()
    local T = boot()
    local Theme = T.ns.Theme
    local pins = T.env.CraftProfitCharDB.pins
    pins[1].difficulty = "optimal"
    pins[2].difficulty = nil
    local parts = openList(T)
    local colours = {}
    for i = 1, 2 do
        parts.rows[i].name.SetTextColor = function(_, r, g, b, a) colours[i] = { r, g, b, a } end
    end
    T.ns.PinsUI.refresh()
    local byID = {}
    for i = 1, 2 do byID[parts.rows[i].recipeID] = colours[i] end
    H.eq(byID[1], Theme.FIXED.optimal)
    H.eq(byID[2], T.ns.Kit.current.textMain)
end)

H.test("each difficulty has its colour in the pinned list", function()
    local T = boot()
    local Theme = T.ns.Theme
    local pins = T.env.CraftProfitCharDB.pins
    local parts = openList(T)
    local last
    parts.rows[1].name.SetTextColor = function(_, r, g, b, a) last = { r, g, b, a } end
    for _, name in ipairs({ "optimal", "medium", "easy", "trivial" }) do
        for _, pin in ipairs(pins) do pin.difficulty = name end
        T.ns.PinsUI.refresh()
        H.eq(last, Theme.FIXED[name])
    end
end)

H.test("the scroll bar shows only when there are more pins than rows and follows the offset", function()
    local T = boot()
    local parts = openList(T)
    H.falsy(parts.bar.frame.shown)
    for i = 3, 12 do
        T.ns.DB.pinAdd(T.env.CraftProfitCharDB, raw(i, 100, { { itemID = 1, qty = 1 } }))
    end
    T.ns.PinsUI.refresh()
    H.truthy(parts.bar.frame.shown)
    H.eq(parts.bar.total, 12)
    H.eq(parts.bar.visible, 6)
    H.eq(parts.bar.offset, 0)
    parts.bar.onScroll(4)
    H.eq(parts.bar.offset, 4)
    parts.bar.onScroll(99)
    H.eq(parts.bar.offset, 6)
end)

H.test("the mouse wheel scrolls the list and the bar, and removing pins clamps the offset", function()
    local T = boot()
    local parts = openList(T)
    for i = 3, 12 do
        T.ns.DB.pinAdd(T.env.CraftProfitCharDB, raw(i, 100, { { itemID = 1, qty = 1 } }))
    end
    T.ns.PinsUI.refresh()
    local host = T.ns.Window.pinsHost()
    host.scripts.OnMouseWheel(host, -1)
    host.scripts.OnMouseWheel(host, -1)
    H.eq(parts.bar.offset, 2)
    host.scripts.OnMouseWheel(host, 1)
    H.eq(parts.bar.offset, 1)
    for _ = 1, 7 do table.remove(T.env.CraftProfitCharDB.pins) end
    T.ns.PinsUI.refresh()
    H.eq(parts.bar.offset, 0)
    H.falsy(parts.bar.frame.shown)
end)

H.test("the panel height follows the number of pinned rows shown and the host height follows the panel", function()
    local T = boot()
    local Kit = T.ns.Kit
    local parts = openList(T)
    H.eq(parts.panel.frame.height, Kit.panelHeight(2, 18))
    for i = 3, 12 do
        T.ns.DB.pinAdd(T.env.CraftProfitCharDB, raw(i, 100, { { itemID = 1, qty = 1 } }))
    end
    T.ns.PinsUI.refresh()
    H.eq(parts.panel.frame.height, Kit.panelHeight(6, 18))
    local host = T.ns.Window.pinsHost()
    H.truthy(host.height > Kit.panelHeight(6, 18))
end)

H.test("the sort button reads the sort mode and toggles it", function()
    local T = boot()
    local parts = openList(T)
    H.eq(parts.sort.label.text, "Sort: profit")
    parts.sort.scripts.OnClick(parts.sort)
    H.eq(parts.sort.label.text, "Sort: cost/point")
end)

H.test("the three buttons read their text and keep their actions", function()
    local T = boot()
    local parts = openList(T)
    H.eq(parts.search.label.text, "Search prices")
    H.eq(parts.scan.label.text, "Scan AH")
    H.eq(parts.level.label.text, "Leveling")
    parts.search.scripts.OnClick(parts.search)
    H.eq(T.ns.PinsUI.state, "running")
    parts.level.scripts.OnClick(parts.level)
    H.truthy(T.ns.LevelingUI.isShown())
end)

H.test("clicking a pinned row selects that recipe", function()
    local T = boot()
    local parts = openList(T)
    local id2
    for i = 1, 2 do if parts.rows[i].recipeID == 2 then id2 = parts.rows[i] end end
    id2.scripts.OnClick(id2)
    H.eq(T.ns.Controller.currentRecipeID(), 2)
end)

H.test("a theme switch repaints the pinned list without error", function()
    local T = boot()
    openList(T)
    for _, name in ipairs({ "copper", "steel", "gold" }) do T.ns.Kit.applyTheme(name) end
    H.truthy(T.ns.PinsUI.parts.panel)
end)
```
(Check the exact English texts in `CraftProfit/Locales/enUS.lua`: `SORT_NET`, `SORT_POINT`, `SEARCH_PRICES`, `SCAN`, `LEVEL_BUTTON`; use the real values in the assertions.)

- [ ] **Step 2: Run to see failures**

Run: `luajit tests/run.lua 2>&1 | grep FAIL | head`
Expected: failures (`PinsUI.parts` nil).

- [ ] **Step 3: Rewrite the widget parts of `CraftProfit/UI/PinsUI.lua`.** Keep unchanged: `PinsUI.state`, `PinsUI.status`, `setStatus` (it writes `statusText`), `PinsUI.wantedFor`, `PinsUI.orderedPins`, `finishSearch`, `PinsUI.startSearch`, `PinsUI.scan`, `PinsUI.onAHOpen`, `PinsUI.onSearchResults`, the search/scan constants. Replace the file header, locals, `pointValue`, `PinsUI.refresh` and `PinsUI.init` as follows.

Header and locals (replace the `local PAD ... local COLORS ... local ctl` block; keep `SEARCH_TIMEOUT`, `TICK_SECONDS`, `SCAN_REPLY_TIMEOUT`):

```lua
local _, ns = ...
local L = ns.L
local Kit, Theme = ns.Kit, ns.Theme

local PinsUI = {}
ns.PinsUI = PinsUI

local ROW_H = 18
local VISIBLE = 6
local BUTTON_H = 24
local STATUS_H = 14
local FOOTER_H = BUTTON_H + 6 + BUTTON_H + 6 + STATUS_H
local SEARCH_TIMEOUT = 6
local TICK_SECONDS = 0.2
local SCAN_REPLY_TIMEOUT = 15

local ctl
local host, panel, statusText
local parts = { rows = {} }
local rows = parts.rows
local offset = 0
local queue, ticker
local notFound = 0

PinsUI.parts = parts
PinsUI.state = "idle"
PinsUI.status = ""
```
(keep the original comment on the file's first lines, updated: "on the shared UI kit".)

`pointValue` returns a colour table:

```lua
-- Text and colour of a row's value in the cost-per-point view.
local function pointValue(perPoint)
    local text, tone = ns.Present.pointRow(L, ctl.fmt, perPoint)
    local colour = tone == "profit" and Theme.FIXED.profit or tone == "loss" and Theme.FIXED.loss
        or Kit.current.textMuted
    return text, colour
end
```

`PinsUI.refresh`:

```lua
function PinsUI.refresh()
    if not host then return end
    local pins = CraftProfitCharDB.pins
    local byPoint = CraftProfitCharDB.sortMode == ns.DB.SORT_POINT
    local ordered = PinsUI.orderedPins(pins, CraftProfitCharDB.sortMode, ctl.evaluate)
    offset = math.max(0, math.min(offset, #pins - VISIBLE))
    local currentID = ctl.currentRecipeID()

    panel:setTitle(L.PINS_TITLE)
    parts.sort:setText(byPoint and L.SORT_POINT or L.SORT_NET)
    parts.search:setText(L.SEARCH_PRICES)
    parts.scan:setText(L.SCAN)
    parts.level:setText(L.LEVEL_BUTTON)
    parts.empty:SetText(L.PINS_EMPTY)
    parts.empty:SetShown(#pins == 0)

    for i = 1, VISIBLE do
        local row, item = rows[i], ordered[offset + i]
        if item then
            local recipe, result = item.recipe, item.result
            row.recipeID = recipe.recipeID
            row.name:SetText(recipe.name ~= "" and recipe.name or ("#" .. recipe.recipeID))
            -- The difficulty stored with the pin, kept up to date while the profession
            -- window is open; a pin without one keeps the plain text colour.
            local nc = Theme.FIXED[recipe.difficulty] or Kit.current.textMain
            row.name:SetTextColor(nc[1], nc[2], nc[3], nc[4])
            local text, c
            if byPoint then
                text, c = pointValue(result.perPoint)
            elseif result.net ~= nil then
                text = ctl.fmt(result.net)
                c = result.net >= 0 and Theme.FIXED.profit or Theme.FIXED.loss
            else
                text, c = L.UNKNOWN, Kit.current.textMuted
            end
            row.value:SetText(text)
            row.value:SetTextColor(c[1], c[2], c[3], c[4])
            row.selected:SetShown(recipe.recipeID == currentID)
            row:Show()
        else
            row.recipeID = nil
            row:Hide()
        end
    end

    local shownRows = math.max(1, math.min(#pins, VISIBLE))
    local panelH = Kit.panelHeight(shownRows, ROW_H)
    panel.frame:SetHeight(panelH)
    parts.bar:update(#pins, VISIBLE, offset)
    local top = panelH + Kit.GAP
    parts.search:ClearAllPoints()
    parts.search:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -top)
    parts.scan:ClearAllPoints()
    parts.scan:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, -top)
    parts.level:ClearAllPoints()
    parts.level:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -top - BUTTON_H - 6)
    statusText:ClearAllPoints()
    statusText:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -top - (BUTTON_H + 6) * 2)
    host:SetHeight(top + FOOTER_H)
    ns.Window.relayout()
end
```
The buttons' widths are set once in `init` (`half`).

`PinsUI.init` (replace entirely):

```lua
function PinsUI.init(controller)
    ctl = controller
    host = ns.Window.pinsHost()
    local inner = ns.Window.INNER_WIDTH
    local half = math.floor((inner - Kit.GAP) / 2)

    panel = Kit.panel(host, L.PINS_TITLE)
    parts.panel = panel
    panel.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    panel.frame:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
    panel.frame:SetHeight(Kit.panelHeight(1, ROW_H))

    -- The sort button lives in the panel header, above the header's own hit area.
    parts.sort = Kit.button(panel.frame, "small", "")
    parts.sort:SetWidth(120)
    parts.sort:SetPoint("TOPRIGHT", panel.frame, "TOPRIGHT", -6, -3)
    parts.sort:SetScript("OnClick", function() ctl.toggleSort() end)

    local body = panel.body
    parts.empty = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    parts.empty:SetPoint("TOPLEFT", body, "TOPLEFT", 8, -2)
    Kit.onTheme(function(t)
        local c = t.textMuted
        parts.empty:SetTextColor(c[1], c[2], c[3], c[4])
    end)

    local rightInset = Kit.SCROLL_W + 6
    for i = 1, VISIBLE do
        local y = -(i - 1) * ROW_H
        local row = CreateFrame("Button", nil, body)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", body, "TOPRIGHT", -rightInset, y)
        row.selected = row:CreateTexture(nil, "BACKGROUND")
        row.selected:SetAllPoints(row)
        local hover = row:CreateTexture(nil, "BACKGROUND")
        hover:SetAllPoints(row)
        Kit.onTheme(function(t)
            local s, h = t.bestFill, t.rowHover
            row.selected:SetColorTexture(s[1], s[2], s[3], s[4])
            hover:SetColorTexture(h[1], h[2], h[3], h[4])
        end)
        hover:Hide()
        row:HookScript("OnEnter", function() hover:Show() end)
        row:HookScript("OnLeave", function() hover:Hide() end)
        row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.value:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.value:SetJustifyH("RIGHT")
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.name:SetPoint("RIGHT", row.value, "LEFT", -8, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row:SetScript("OnClick", function(self)
            if self.recipeID then ctl.selectPin(self.recipeID) end
        end)
        rows[i] = row
    end

    parts.bar = Kit.scrollbar(body, VISIBLE * ROW_H)
    parts.bar.frame:SetPoint("TOPRIGHT", body, "TOPRIGHT", -2, 0)
    parts.bar.onScroll = function(newOffset)
        offset = newOffset
        PinsUI.refresh()
    end

    parts.search = Kit.button(host, "primary", "")
    parts.search:SetWidth(half)
    parts.search:SetScript("OnClick", PinsUI.startSearch)
    parts.scan = Kit.button(host, "normal", "")
    parts.scan:SetWidth(half)
    parts.scan:SetScript("OnClick", PinsUI.scan)
    parts.level = Kit.button(host, "normal", "")
    parts.level:SetWidth(half)
    parts.level:SetScript("OnClick", function() if ns.LevelingUI then ns.LevelingUI.toggle() end end)
    statusText = host:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    statusText:SetWidth(inner)
    statusText:SetJustifyH("LEFT")
    Kit.onTheme(function(t)
        local c = t.textMuted
        statusText:SetTextColor(c[1], c[2], c[3], c[4])
    end)

    host:EnableMouseWheel(true)
    host:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta)
        PinsUI.refresh()
    end)
    -- Muted values and the plain name colour come from the theme: redraw on a switch.
    Kit.onTheme(function() PinsUI.refresh() end)
    host:Hide()
end
```
Notes: `PinsUI.refresh()` is guarded by `if not host`, and the registration at the end calls it once immediately, which must not fail while `ctl`, rows etc. exist (they do at that point because `init` finished building before). If the immediate call proves awkward, register it with a closure that checks `host` and `parts.bar`. `setStatus` keeps writing `statusText:SetText(text)`. Remove now-unused locals (`header`, `emptyText`, `levelButton`, ...) so luacheck stays at 0 warnings. `ns.Window.WIDTH` is no longer used in this file.

- [ ] **Step 4: Run the whole suite**

Run: `sh tests/check.sh 2>&1 | grep -E "passed|failed|Total|FAIL"`
Expected: `0 failed`, `0 warnings`. All the existing `tests/test_pinsui.lua` and `tests/test_boot.lua` tests must pass unchanged; if one reads a removed internal, adapt the PinsUI code, not the test, unless the test asserts a removed widget detail (then update it and say so in the report).

- [ ] **Step 5: Commit**

```bash
git status --short
git add CraftProfit/UI/PinsUI.lua tests/test_pinsui.lua
git commit -m "feat: pinned list on the UI kit with difficulty colours and a scroll bar"
```

---

### Task 4: Leveling window on the kit

**Files:**
- Rewrite: `CraftProfit/UI/LevelingUI.lua`
- Modify: `CraftProfit/Locales/enUS.lua`, `frFR.lua`, `esES.lua` (key `LEVEL_PANEL`)
- Test: `tests/test_levelingui.lua` (new); existing tests in `tests/test_boot.lua` must keep passing

**Interfaces:**
- Consumes: `Kit` (window, panel, button, check, scrollbar, stack, panelHeight, onTheme), `Theme.FIXED`, the controller: `ctl.levelData()` returning `{ sort, showGrey, profession = { name } | nil, ageText, stale, hiddenGrey, items = { { recipe, result = { perPoint } } } }`, `ctl.nextLevelProfession()`, `ctl.toggleLevelSort()`, `ctl.setLevelShowGrey(bool)`, `ctl.selectKnown(recipe)`, `ctl.currentRecipeID()`, `ctl.fmt`; `ns.Present.pointRow`, `ns.Present.craftsPerPoint`; `ns.Window.frame()`, `ns.Window.isShown()`.
- Produces: `LevelingUI.parts` (`panel`, `rows`, `bar`, `profession`, `sort`, `age`, `grey`, `hidden`, `empty`, `frames`), `LevelingUI.WIDTH` (396); public functions unchanged: `isShown`, `hide`, `refresh`, `frame`, `show`, `toggle`, `init(controller, handlers)`, `place`, `attach(saved)`.
- Locale: `LEVEL_PANEL` = "NEXT POINT" / "PROCHAIN POINT" / "PRÓXIMO PUNTO".
- Layout (content width 372): strip 24 (profession button 150 left, sort button 160 right), age line 14, panel with 12 rows of 18 px and a scroll bar, grey-recipes check box row 18 with the hidden-count text on its right; fixed height.

- [ ] **Step 1: Locale keys.** Add `LEVEL_PANEL` to the three locale files next to the other `LEVEL_*` keys (values above, already in capitals).

- [ ] **Step 2: Write the failing tests** — create `tests/test_levelingui.lua`:

```lua
local H = ...
local W = dofile("tests/fakewow.lua")

-- Real frames start shown (the fake ones do not): the window must hide itself.
local function boot()
    local T = W.boot(H)
    local create = T.env.CreateFrame
    T.env.CreateFrame = function(...)
        local f = create(...)
        f.shown = true
        return f
    end
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    local calls = {}
    local C = T.ns.Controller
    C.nextLevelProfession = function() calls[#calls + 1] = { "next" } end
    C.toggleLevelSort = function() calls[#calls + 1] = { "sort" } end
    C.setLevelShowGrey = function(v) calls[#calls + 1] = { "grey", v } end
    C.selectKnown = function(recipe) calls[#calls + 1] = { "select", recipe.recipeID } end
    return T, T.ns.LevelingUI, calls
end

local function item(id, name, difficulty, chance, cost)
    return {
        recipe = { recipeID = id, name = name, difficulty = difficulty },
        result = { perPoint = { chance = chance, cost = cost } },
    }
end

local function data(over)
    local d = {
        sort = "cost", showGrey = false, profession = { name = "Forge" },
        ageText = "Prices: 5m ago", stale = false, hiddenGrey = 0,
        items = { item(1, "Bronze Sword", "optimal", 1, 100), item(2, "Copper Helm", "easy", 0.25, 900) },
    }
    for k, v in pairs(over or {}) do d[k] = v end
    return d
end

local function feed(T, d) T.ns.Controller.levelData = function() return d end end

H.test("the leveling window is created hidden although real frames start shown", function()
    local _, UI = boot()
    H.falsy(UI.isShown())
    H.truthy(UI.frame())
end)

H.test("showing it lists the recipes with their difficulty colours, crafts per point and cost", function()
    local T, UI = boot()
    local Theme = T.ns.Theme
    feed(T, data())
    UI.show()
    H.truthy(UI.isShown())
    local p = UI.parts
    H.eq(p.profession.label.text, "Forge")
    H.eq(p.age.text, "Prices: 5m ago")
    H.eq(p.rows[1].name.text, "Bronze Sword")
    H.eq(p.rows[1].crafts.text, "x1")
    H.eq(p.rows[2].name.text, "Copper Helm")
    H.eq(p.rows[2].crafts.text, "x4")
    H.truthy(p.rows[1].shown)
    H.falsy(p.rows[3].shown)
    local colour
    p.rows[1].name.SetTextColor = function(_, r, g, b, a) colour = { r, g, b, a } end
    UI.refresh()
    H.eq(colour, Theme.FIXED.optimal)
end)

H.test("the sort button reads the sort mode and the controls call the controller", function()
    local T, UI, calls = boot()
    feed(T, data({ sort = "speed" }))
    UI.show()
    H.eq(UI.parts.sort.label.text, "Sort: speed")
    UI.parts.sort.scripts.OnClick(UI.parts.sort)
    UI.parts.profession.scripts.OnClick(UI.parts.profession)
    UI.parts.grey.scripts.OnClick(UI.parts.grey)
    H.eq(calls[1], { "sort" })
    H.eq(calls[2], { "next" })
    H.eq(calls[3], { "grey", true })
end)

H.test("clicking a row shows that recipe in the main window", function()
    local T, UI, calls = boot()
    feed(T, data())
    UI.show()
    UI.parts.rows[2].scripts.OnClick(UI.parts.rows[2])
    H.eq(calls[#calls], { "select", 2 })
end)

H.test("the hidden grey count and the empty messages", function()
    local T, UI = boot()
    feed(T, data({ hiddenGrey = 3 }))
    UI.show()
    H.truthy(UI.parts.hidden.text:find("3", 1, true))
    feed(T, data({ items = {} }))
    UI.refresh()
    H.truthy(UI.parts.empty.shown)
    H.eq(UI.parts.empty.text, "No recipe can give a point")
    feed(T, data({ profession = nil, items = {} }))
    UI.refresh()
    H.eq(UI.parts.profession.label.text, "-")
    H.truthy(UI.parts.empty.shown)
    for i = 1, 12 do H.falsy(UI.parts.rows[i].shown) end
end)

H.test("the scroll bar appears with more than twelve recipes and the wheel and bar scroll the list", function()
    local T, UI = boot()
    local items = {}
    for i = 1, 20 do items[i] = item(i, "R" .. i, "medium", 0.75, i * 10) end
    feed(T, data({ items = items }))
    UI.show()
    local p = UI.parts
    H.truthy(p.bar.frame.shown)
    H.eq(p.rows[1].name.text, "R1")
    UI.frame().scripts.OnMouseWheel(UI.frame(), -1)
    H.eq(p.rows[1].name.text, "R2")
    p.bar.onScroll(8)
    H.eq(p.rows[1].name.text, "R9")
    p.bar.onScroll(500)
    H.eq(p.rows[1].name.text, "R9")
    feed(T, data({ items = { item(1, "A", "easy", 1, 5) } }))
    UI.refresh()
    H.eq(p.rows[1].name.text, "A")
    H.falsy(p.bar.frame.shown)
end)

H.test("the window has a fixed height whatever the number of recipes", function()
    local T, UI = boot()
    feed(T, data())
    UI.show()
    local h1 = UI.frame().height
    local items = {}
    for i = 1, 30 do items[i] = item(i, "R" .. i, "easy", 0.25, i) end
    feed(T, data({ items = items }))
    UI.refresh()
    H.eq(UI.frame().height, h1)
    H.truthy(h1 > 0)
end)

H.test("the window sits beside the main window, or in the middle of the screen, and a saved position wins", function()
    local T, UI = boot()
    local points = {}
    UI.frame().SetPoint = function(_, ...) points[#points + 1] = { ... } end
    UI.place()
    H.eq(points[#points][1], "CENTER")
    T.ns.Window.show()
    UI.place()
    H.eq(points[#points][1], "TOPLEFT")
    H.eq(points[#points][3], "TOPRIGHT")
    UI.attach({ x = 40, y = 500 })
    H.eq(points[#points], { "TOPLEFT", T.env.UIParent, "BOTTOMLEFT", 40, 500 })
end)

H.test("dropping the window reports its position", function()
    local T, UI = boot()
    local moved
    UI.frame().scripts.OnDragStop(UI.frame())
    -- handlers belong to Boot: check the call does not raise and Boot stored a position
    moved = T.env.CraftProfitDB.settings.levelWindow
    H.eq(moved, { x = 100, y = 700 })
end)

H.test("toggle and hide work and a theme switch repaints without error", function()
    local T, UI = boot()
    feed(T, data())
    UI.toggle()
    H.truthy(UI.isShown())
    for _, name in ipairs({ "copper", "steel", "gold" }) do T.ns.Kit.applyTheme(name) end
    UI.toggle()
    H.falsy(UI.isShown())
    UI.hide()
end)
```
(The exact English texts: `SORT_SPEED` is "Sort: speed" and `LEVEL_NONE` "No recipe can give a point": read `CraftProfit/Locales/enUS.lua` and use the real values; the position-saving test assumes Boot's `onMoved` for the leveling window stores `{ x, y }` in `CraftProfitDB.settings.levelWindow`: confirm in `CraftProfit/Boot.lua`.)

- [ ] **Step 3: Run to see failures**

Run: `luajit tests/run.lua 2>&1 | grep FAIL | head`
Expected: failures (`UI.parts` nil, etc.).

- [ ] **Step 4: Rewrite `CraftProfit/UI/LevelingUI.lua`**

```lua
-- The leveling window: the known recipes of one profession, cheapest skill point first,
-- on the shared UI kit. A separate, movable window opened by /cp level or the Leveling
-- button; it sits beside the main window until it has been dragged.
local _, ns = ...
local L = ns.L
local Kit, Theme = ns.Kit, ns.Theme

local LevelingUI = {}
ns.LevelingUI = LevelingUI

local WIDTH = 396
local ROW_H = 18
local VISIBLE = 12
local STRIP_H = 24
local AGE_H = 14
local CHECK_H = 18
local VALUE_W = 112
local CRAFTS_W = 36

local ctl, handlers
local frame, content, savedPosition
local offset = 0
local parts = { rows = {}, frames = {} }

LevelingUI.parts = parts
LevelingUI.WIDTH = WIDTH

local function themed(fontString, token)
    Kit.onTheme(function(t)
        local c = t[token]
        fontString:SetTextColor(c[1], c[2], c[3], c[4])
    end)
end

function LevelingUI.isShown()
    return frame ~= nil and frame:IsShown() == true
end

function LevelingUI.hide()
    if frame then frame:Hide() end
end

local function name(recipe)
    return recipe.name ~= "" and recipe.name or ("#" .. recipe.recipeID)
end

function LevelingUI.refresh()
    if not frame or not frame:IsShown() then return end
    local data = ctl.levelData()
    frame:setTitle(L.LEVEL_TITLE)
    parts.panel:setTitle(L.LEVEL_PANEL)
    parts.sort:setText(data.sort == "speed" and L.SORT_SPEED or L.SORT_POINT)
    parts.grey:setText(L.LEVEL_SHOW_GREY)
    parts.grey:SetChecked(data.showGrey)
    if not data.profession then
        parts.profession:setText("-")
        parts.age:SetText("")
        parts.hidden:SetText("")
        parts.empty:SetText(L.LEVEL_EMPTY)
        parts.empty:Show()
        parts.bar:update(0, VISIBLE, 0)
        for i = 1, VISIBLE do parts.rows[i].recipeID = nil; parts.rows[i]:Hide() end
        return
    end
    parts.profession:setText(data.profession.name)
    parts.age:SetText(data.ageText)
    parts.ageStale = data.stale and true or false
    parts.paintAge()
    parts.hidden:SetText(data.hiddenGrey > 0 and string.format(L.LEVEL_HIDDEN, data.hiddenGrey) or "")
    local items = data.items
    parts.empty:SetText(L.LEVEL_NONE)
    parts.empty:SetShown(#items == 0)
    offset = math.max(0, math.min(offset, #items - VISIBLE))
    local currentID = ctl.currentRecipeID()
    for i = 1, VISIBLE do
        local row, item = parts.rows[i], items[offset + i]
        if item then
            local recipe = item.recipe
            row.recipeID, row.recipe = recipe.recipeID, recipe
            row.name:SetText(name(recipe))
            local c = Theme.FIXED[recipe.difficulty] or Kit.current.textMain
            row.name:SetTextColor(c[1], c[2], c[3], c[4])
            local perPoint = item.result.perPoint
            row.crafts:SetText(ns.Present.craftsPerPoint(perPoint and perPoint.chance) or "")
            local text, tone = ns.Present.pointRow(L, ctl.fmt, perPoint)
            row.value:SetText(text)
            local tc = tone == "profit" and Theme.FIXED.profit or tone == "loss" and Theme.FIXED.loss
                or Kit.current.textMuted
            row.value:SetTextColor(tc[1], tc[2], tc[3], tc[4])
            row.selected:SetShown(recipe.recipeID == currentID)
            row:Show()
        else
            row.recipeID, row.recipe = nil, nil
            row:Hide()
        end
    end
    parts.bar:update(#items, VISIBLE, offset)
end

function LevelingUI.frame() return frame end

function LevelingUI.show()
    if not frame then return end
    LevelingUI.place()
    frame:Show()
    LevelingUI.refresh()
end

function LevelingUI.toggle()
    if LevelingUI.isShown() then LevelingUI.hide() else LevelingUI.show() end
end

local function section(key, height)
    local f = CreateFrame("Frame", nil, content)
    f:SetHeight(height)
    parts.frames[key] = f
    return f
end

local function buildRow(body, i)
    local y = -(i - 1) * ROW_H
    local row = CreateFrame("Button", nil, body)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", body, "TOPRIGHT", -(Kit.SCROLL_W + 6), y)
    row.selected = row:CreateTexture(nil, "BACKGROUND")
    row.selected:SetAllPoints(row)
    local hover = row:CreateTexture(nil, "BACKGROUND")
    hover:SetAllPoints(row)
    Kit.onTheme(function(t)
        local s, h = t.bestFill, t.rowHover
        row.selected:SetColorTexture(s[1], s[2], s[3], s[4])
        hover:SetColorTexture(h[1], h[2], h[3], h[4])
    end)
    hover:Hide()
    row:HookScript("OnEnter", function() hover:Show() end)
    row:HookScript("OnLeave", function() hover:Hide() end)
    row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.value:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.value:SetWidth(VALUE_W)
    row.value:SetJustifyH("RIGHT")
    row.value:SetWordWrap(false)
    -- Crafts per point: a column of its own so the cost reads as loss x crafts.
    row.crafts = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.crafts:SetPoint("RIGHT", row, "RIGHT", -(8 + VALUE_W + 8), 0)
    row.crafts:SetWidth(CRAFTS_W)
    row.crafts:SetJustifyH("RIGHT")
    themed(row.crafts, "textMuted")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.name:SetPoint("RIGHT", row.crafts, "LEFT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row:SetScript("OnClick", function(self)
        if self.recipe then ctl.selectKnown(self.recipe) end
    end)
    return row
end

function LevelingUI.init(controller, h)
    if frame then return frame end
    ctl, handlers = controller, h or {}
    local inner = WIDTH - Kit.CONTENT_SIDE * 2
    local panelH = Kit.panelHeight(VISIBLE, ROW_H)
    local heights = { STRIP_H, AGE_H, panelH, CHECK_H }
    local offsets, total = Kit.stack(heights, Kit.GAP, 0)

    frame = Kit.window("CraftProfitLevelWindow", L.LEVEL_TITLE, {
        width = WIDTH,
        height = total + Kit.CONTENT_TOP + Kit.CONTENT_BOTTOM,
        onMoved = function(point, x, y)
            if handlers.onMoved then handlers.onMoved(point, x, y) end
        end,
    })
    content = frame.content
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta)
        LevelingUI.refresh()
    end)

    -- Strip: the profession (click to cycle) and the sort order.
    local strip = section("strip", STRIP_H)
    parts.profession = Kit.button(strip, "normal", "")
    parts.profession:SetWidth(150)
    parts.profession:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, 0)
    parts.profession:SetScript("OnClick", function() ctl.nextLevelProfession() end)
    parts.sort = Kit.button(strip, "normal", "")
    parts.sort:SetWidth(160)
    parts.sort:SetPoint("TOPRIGHT", strip, "TOPRIGHT", 0, 0)
    parts.sort:SetScript("OnClick", function() ctl.toggleLevelSort() end)

    local ageRow = section("age", AGE_H)
    parts.age = ageRow:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    parts.age:SetPoint("LEFT", ageRow, "LEFT", 4, 0)
    parts.ageStale = false
    parts.paintAge = function()
        local c = parts.ageStale and Theme.FIXED.stale or Kit.current.textMuted
        parts.age:SetTextColor(c[1], c[2], c[3], c[4])
    end
    Kit.onTheme(function() parts.paintAge() end)

    parts.panel = Kit.panel(content, L.LEVEL_PANEL)
    parts.frames.panel = parts.panel.frame
    parts.panel.frame:SetHeight(panelH)
    for i = 1, VISIBLE do parts.rows[i] = buildRow(parts.panel.body, i) end
    parts.bar = Kit.scrollbar(parts.panel.body, VISIBLE * ROW_H)
    parts.bar.frame:SetPoint("TOPRIGHT", parts.panel.body, "TOPRIGHT", -2, 0)
    parts.bar.onScroll = function(newOffset)
        offset = newOffset
        LevelingUI.refresh()
    end
    parts.empty = parts.panel.body:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    parts.empty:SetPoint("TOP", parts.panel.body, "TOP", 0, -20)
    themed(parts.empty, "textMuted")

    local footer = section("footer", CHECK_H)
    parts.grey = Kit.check(footer, "")
    parts.grey:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
    parts.grey.onToggle = function(checked) ctl.setLevelShowGrey(checked and true or false) end
    parts.hidden = footer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    parts.hidden:SetPoint("RIGHT", footer, "RIGHT", -4, 0)
    parts.hidden:SetJustifyH("RIGHT")
    themed(parts.hidden, "textMuted")

    local order = { "strip", "age", "panel", "footer" }
    for i, key in ipairs(order) do
        local f = parts.frames[key]
        f:SetPoint("TOPLEFT", content, "TOPLEFT", 0, offsets[i])
        f:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, offsets[i])
    end
    LevelingUI.attach(nil)
    -- A new frame starts shown: the controller decides when the window appears.
    frame:Hide()
    return frame
end

-- Position: the saved one once the window has been dragged; otherwise right beside the
-- main window when it is on screen, else the middle of the screen.
function LevelingUI.place()
    if not frame then return end
    frame:ClearAllPoints()
    local main = ns.Window.frame()
    if savedPosition then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", savedPosition.x, savedPosition.y)
    elseif main and ns.Window.isShown() then
        frame:SetPoint("TOPLEFT", main, "TOPRIGHT", 6, 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", -200, 0)
    end
end

function LevelingUI.attach(saved)
    savedPosition = saved
    LevelingUI.place()
end
```
Notes: `parts.panel.frame` height is set to `panelH` once (fixed list height); the unused `inner` local must be removed if luacheck flags it; `LevelingUI.place` is called inside `init` through `attach` before `frame:Hide()` which is fine; the empty text must show at the panel top, make sure it is not under a row (rows hidden when empty). If a test of the fake environment needs `Window.frame()`/`Window.isShown()` to be called before init, they are the same as before.

- [ ] **Step 5: Run the whole suite**

Run: `sh tests/check.sh 2>&1 | grep -E "passed|failed|Total|FAIL"`
Expected: `0 failed`, `0 warnings`. The existing leveling tests in `tests/test_boot.lua` (about lines 689-780) must pass; fix the window, not the test, unless the test asserts a removed internal.

- [ ] **Step 6: Commit**

```bash
git status --short
git add CraftProfit/UI/LevelingUI.lua CraftProfit/Locales tests/test_levelingui.lua
git commit -m "feat: leveling window rebuilt on the UI kit with a scroll bar"
```

---

### Task 5: Docs, spec, user guide

**Files:**
- Modify: `docs/technical.md`, `docs/in-game-checklist.md`, `docs/user-guide.md`, `docs/user-guide.fr.md`, `CHANGELOG.md`, `docs/superpowers/specs/2026-10-09-ui-rework-design.md`

- [ ] **Step 1: Docs.** Document what the code does now:
  - `docs/technical.md`: Kit gains `scrollbar` (`scrollThumb`, `scrollOffsetAt`); `PinsUI` and `LevelingUI` rows now say "on the UI kit"; `Window.INNER_WIDTH` and the pinned host placement; the `GetCursorPosition` global; remove the "pinned list keeps the old look" sentences.
  - `docs/user-guide.md` and `.fr.md`, sections *Sorting the pinned list*, *The leveling window*, *At the auction house*: pinned names are coloured by recipe difficulty (orange, yellow, green, grey) with the limit (the colour is the one known when the profession window was last open; open it to refresh); the list shows 6 recipes and has a scroll bar when there are more (also the mouse wheel; click or drag the bar); the leveling list has the same scroll bar; the Sort button sits in the panel header. The French text must read naturally.
  - `docs/in-game-checklist.md`: add a section "Pinned list and leveling window (PR 3)": pinned list at the AH with more than 6 pins shows a scroll bar whose thumb moves with the wheel and can be dragged and clicked; with 6 or fewer no bar; names coloured orange/yellow/green/grey following the profession window (check after skill points are gained); selected row tinted gold, hovered row highlighted; Sort button in the panel header toggles profit and cost/point; Search prices, Scan AH, Leveling buttons work, the status text below; the list sits inside the window margin like the other panels (12 px), nothing overlaps the frame border; window grows and shrinks when the AH opens and closes; the leveling window: opens beside the main window, kit look, profession button cycles, sort button cycles, grey-recipes check box and the hidden count, scroll bar with more than 12 recipes, fixed height, a long French recipe name is truncated not wrapped, position remembered after `/reload`, closing with the x; a theme switch (`/cp kitdemo copper`) repaints both.
  - `CHANGELOG.md`: *Changed*: the pinned list and the leveling window have the new look; pinned recipe names are coloured by difficulty; *Added*: scroll bars on both lists.
  - Spec: mark PR 3 as done in *Delivery* with these items; add `Kit.scrollbar(parent, trackH)` and its helpers to the Kit section, and the difficulty colour decision.
- [ ] **Step 2: Run everything and verify authorship**

Run: `sh tests/check.sh 2>&1 | grep -E "passed|failed|Total"; echo "coauthor: $(git log --format=%B main..HEAD | grep -ci co-authored)"`
Expected: `0 failed`, `0 warnings`, `coauthor: 0`.

- [ ] **Step 3: Commit** (do NOT push, do NOT open a PR: the controller does)

```bash
git status --short
git add docs CHANGELOG.md
git commit -m "docs: pinned list and leveling window on the UI kit, scroll bars, difficulty colours"
```
