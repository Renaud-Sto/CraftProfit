# Search the crafted item at the auction house Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the player click the AH tile ("HV (NET)") or the recipe title of the main window to search the crafted item at the auction house, so the number of items for sale can be checked next to the displayed price. A small magnifier icon on both shows that they are clickable while the auction house is open.

**Architecture:** `Controller.onOutputClick` reuses the reagent search (`AH.browse`). `Kit.tile` gets an optional click area with a hover tint and a magnifier icon; `Kit.window` gets an optional title click area (which forwards drags to the window) with the same icon. The icon is the game's own: `Kit.searchIcon` copies the texture of the AH search box, with a verified atlas as a fallback and no icon at all when neither is found. The window shows the icons only while the AH is open and a recipe is displayed.

**Tech Stack:** Lua 5.1 (WoW client), LuaJIT test harness (`tests/harness.lua`, `tests/fakewow.lua`), luacheck.

**Spec:** `docs/superpowers/specs/2026-10-09-ui-rework-design.md` (amended in Task 3). Not part of the four-PR rework: a small feature requested after in-game tests.

## Global Constraints

- Interface 16001, Lua 5.1: no `goto`, `require`, `io`, `loadfile`, `dofile`, `setfenv`, `getfenv` in addon files, comments included (`tests/test_toc.lua` scans the text; a word ending in "io." matches `io%.`).
- No literal zero divisor anywhere in `CraftProfit/`.
- Every game global the addon reads is declared in `.luacheckrc`; `sh tests/check.sh` must end with 0 failures and 0 warnings.
- English only for code comments and docs, except `Locales/frFR.lua`, `Locales/esES.lua`, `docs/user-guide.fr.md`.
- Never mention a co-author in commits, pushes or PR bodies. Verify with `git log --format=%B | grep -ci co-authored` (must print 0).
- Branch `feat/search-crafted-item`, one PR, merged only when the author says so. gh must be logged in as **Renaud-Sto**.
- Several Lua files flip to mode 755 in the working tree by themselves: run `git status --short` before every commit and `chmod 644` any Lua file listed as modified that you did not edit (a file that is committed 755 in the repo and that you edit keeps its mode in the commit: do not include a mode change).
- Kit rules from earlier PRs: texts measured to fit use `Kit.naturalWidth`; behaviour on OnEnter/OnLeave uses `HookScript`, never `SetScript`; `SetFontObject` resets a colour; real frames start SHOWN; a button covering part of a frame that is a drag handle must forward the drag; widgets paint through `Kit.onTheme`.
- Behaviour that must not change: dragging the window by its title plaque and by its body; the reagent search; the AH tile showing its value and best outline; the window closing with the profession/AH window.

## Review Focus

- Clicking works only on a displayed recipe; with the AH closed it says "Open the auction house first"; a bind-on-pickup output says it cannot be sold instead of searching; an item whose name is not loaded says so.
- The title click area must not break dragging the window from the title (press and move drags; press and release clicks).
- The magnifier appears only while the AH is open and a recipe is shown; if no icon source is found, nothing breaks and no empty box or green square is drawn.
- The tile click area must not hide or block the tile's text, and the best tile's outline and tint stay as they are.
- Theme switch repaints the hover tint.

## File Structure

| File | Responsibility |
| --- | --- |
| `.luacheckrc` | `C_Texture` |
| `CraftProfit/Boot.lua` | `Controller.onOutputClick`, handler passed to `Window.create` |
| `CraftProfit/Locales/*.lua` | `SEARCH_UNSELLABLE` |
| `CraftProfit/UI/Kit.lua` | `Kit.searchIcon`, `tile:onClick`, window `onTitleClick` |
| `CraftProfit/UI/Window.lua` | wiring, icon visibility |
| `probe/CraftProfitProbe/Probe.lua` | `/cpp icon` |
| `tests/test_boot.lua`, `test_kit.lua`, `test_window.lua` | tests |
| docs | checklist, guides EN/FR, technical, changelog |

---

### Task 1: Controller action and message

**Files:**
- Modify: `CraftProfit/Boot.lua`, `CraftProfit/Locales/enUS.lua`, `frFR.lua`, `esES.lua`
- Test: `tests/test_boot.lua`

**Interfaces:**
- Produces: `Controller.onOutputClick()`; locale key `SEARCH_UNSELLABLE` ("This item cannot be sold at the auction house" / "Cet objet ne peut pas être vendu à l'hôtel des ventes" / "Este objeto no se puede vender en la casa de subastas"); the handler `onOutputClick = Controller.onOutputClick` in the table passed to `ns.Window.create`.
- Behaviour of `Controller.onOutputClick()`: no displayed recipe (`state.recipe` nil) or no `outputItemID`: nothing; AH closed (`ns.AH.isOpen` false): `say(L.SEARCH_NEED_AH)`; output item info says it is bound when picked up (read how `Evaluate` decides that an item cannot be auctioned: `bindType == 1` from `Controller.itemInfo`; reuse the same rule, do not invent another): `say(L.SEARCH_UNSELLABLE)`; item name not loaded (`Controller.itemName(id)` nil): `say(L.ITEM_NOT_LOADED)`; else `ns.AH.browse(name, itemID, nil)` (no quantity preset), and `say(L.BROWSE_UNAVAILABLE)` when it returns false.

- [ ] **Step 1: Write the failing tests** (append to `tests/test_boot.lua`; its helpers `boot()`, `ITEMS`, `RAW`, `stock` exist; the fake `T.chat` collects `say` lines; look at the existing reagent-click tests to see how `T.ns.AH.browse` is stubbed and how a recipe is selected with `Controller.setRecipe`)

```lua
H.test("clicking the crafted item searches it at the AH without a quantity preset", function()
    local T = boot()
    local C = T.ns.Controller
    local calls = {}
    T.ns.AH.isOpen = true
    T.ns.AH.browse = function(name, itemID, qty) calls[#calls + 1] = { name, itemID, qty }; return true end
    C.setRecipe(T.ns.Recipes.normalize(RAW), "pin")
    C.onOutputClick()
    H.eq(calls, { { "Item100", 100, nil } })
end)

H.test("clicking the crafted item with the AH closed says so and searches nothing", function()
    local T = boot()
    local C = T.ns.Controller
    local calls = 0
    T.ns.AH.browse = function() calls = calls + 1; return true end
    C.setRecipe(T.ns.Recipes.normalize(RAW), "pin")
    C.onOutputClick()
    H.eq(calls, 0)
    H.truthy(table.concat(T.chat, "\n"):find("Open the auction house first", 1, true))
end)

H.test("clicking a bind-on-pickup crafted item says it cannot be sold", function()
    local T = boot({ items = { [100] = { quality = 2, ilvl = 15, sellPrice = 200, classID = 0, bindType = 1 } } })
    local C = T.ns.Controller
    local calls = 0
    T.ns.AH.isOpen = true
    T.ns.AH.browse = function() calls = calls + 1; return true end
    C.setRecipe(T.ns.Recipes.normalize(RAW), "pin")
    C.onOutputClick()
    H.eq(calls, 0)
    H.truthy(table.concat(T.chat, "\n"):find("cannot be sold at the auction house", 1, true))
end)

H.test("clicking with no recipe shown, or when the AH cannot browse, does not raise and says what is wrong", function()
    local T = boot()
    local C = T.ns.Controller
    T.ns.AH.isOpen = true
    C.onOutputClick()
    T.ns.AH.browse = function() return false, "unavailable" end
    C.setRecipe(T.ns.Recipes.normalize(RAW), "pin")
    C.onOutputClick()
    H.truthy(#T.chat > 0)
end)

H.test("the window is given the output click handler", function()
    local T = boot()
    H.eq(T.ns.Window.lastHandlers.onOutputClick, T.ns.Controller.onOutputClick)
end)
```
(Adapt the helper names to the file: `RAW` has `outputItemID = 100`, `T.chat` is the list of chat lines; if the recipe must be built differently, copy what the existing reagent-click test does. A test for an item whose name is not loaded: use an `items` table without item 100 and assert `ITEM_NOT_LOADED`'s English text is said.)

- [ ] **Step 2: Run to see failures** — `luajit tests/run.lua 2>&1 | grep FAIL | head`; expect failures (`onOutputClick` nil).

- [ ] **Step 3: Implement.** In `Boot.lua`, after `Controller.onReagentClick`:

```lua
-- The AH tile or the title of the window was clicked: search the crafted item at the AH
-- (no quantity preset), to see how many are for sale next to the price shown.
function Controller.onOutputClick()
    local recipe = state.recipe
    if not recipe or not recipe.outputItemID then return end
    if not ns.AH.isOpen then
        say(L.SEARCH_NEED_AH)
        return
    end
    local itemID = recipe.outputItemID
    local info = Controller.itemInfo(itemID)
    if info and info.bindType == 1 then
        say(L.SEARCH_UNSELLABLE)
        return
    end
    local name = Controller.itemName(itemID)
    if not name then
        say(L.ITEM_NOT_LOADED)
        return
    end
    if not ns.AH.browse(name, itemID, nil) then say(L.BROWSE_UNAVAILABLE) end
end
```
(check that `bindType == 1` really is the rule used by `Evaluate`/`Core` for "cannot be auctioned"; if the rule lives in a helper, call the helper.) Add `onOutputClick = Controller.onOutputClick,` to the handler table given to `ns.Window.create` in `Controller.init`. Add the three locale lines next to `SEARCH_NEED_AH`.

- [ ] **Step 4: Run the whole suite** — `sh tests/check.sh 2>&1 | grep -E "passed|failed|Total|FAIL"`; expect `0 failed`, `0 warnings`.

- [ ] **Step 5: Commit**

```bash
git status --short
git add CraftProfit/Boot.lua CraftProfit/Locales tests/test_boot.lua
git commit -m "feat: search the crafted item at the AH (controller action and messages)"
```

---

### Task 2: Clickable tile and title with a magnifier

**Files:**
- Modify: `CraftProfit/UI/Kit.lua`, `CraftProfit/UI/Window.lua`, `.luacheckrc`, `probe/CraftProfitProbe/Probe.lua`
- Test: `tests/test_kit.lua`, `tests/test_window.lua`

**Interfaces:**
- Consumes: `handlers.onOutputClick` (Task 1), `ns.AH.isOpen`, `Kit.onTheme`, `Kit.rings`, `Theme` tokens `rowHover`, `textMain`.
- Produces on `ns.Kit`:
  - `Kit.searchIcon(texture) -> boolean`: gives `texture` the game's magnifier. First tries the AH search box icon: `AuctionHouseFrame.SearchBar.SearchBox.searchIcon` (also `SearchIcon`): if it has `GetAtlas()` returning a non-empty string use `texture:SetAtlas(atlas)`; else if it has `GetTexture()` returning a path or id use `texture:SetTexture(...)` and copy `GetTexCoord()` with `SetTexCoord`. Then tries `Kit.SEARCH_ATLASES` (`{ "common-search-magnifyingglass" }`) each verified with `C_Texture.GetAtlasInfo(name)` returning a table before `SetAtlas`. Everything inside `pcall`; returns `true` when an icon was applied, `false` (texture hidden by the caller) otherwise. No file path is ever guessed (a missing file would draw a green square).
  - `tile:onClick(fn)`: adds a Button over the whole tile (level above the texts is not needed: it has no visuals except a hover tint texture painted with `rowHover`, shown on hover through `HookScript`), stored as `tile.hit`; clicking runs `fn`; creates `tile.icon` (a 12x12 texture at the top right, `TOPRIGHT -6, -6`, drawn above the tint, hidden until `tile:showIcon(true)`); `tile:showIcon(show)` shows the icon only if `Kit.searchIcon(tile.icon)` succeeded, hides it otherwise. Calling `onClick` twice replaces the handler of the same button.
  - `Kit.window(name, title, opts)` accepts `opts.onTitleClick` (function): the plaque gets a Button `frame.titleHit` covering it (`SetAllPoints(plaque)`), which runs `onTitleClick` on a plain click, forwards a drag to the window (`RegisterForDrag("LeftButton")`, `OnDragStart` -> `f:StartMoving()`, `OnDragStop` -> the same stop function as the window), tints the title text with `Kit.current.textMain` on hover (and restores `plaqueText` on leave, through `HookScript`), and has `frame.titleIcon` (12x12 texture at the plaque's right padding, `RIGHT -8, 0`, hidden until `frame:showTitleIcon(true)` which applies `Kit.searchIcon` like the tile).
- `Window.create` passes `onTitleClick` to `Kit.window` and calls `tile:onClick` on the first tile (the AH one), both calling `handlers.onOutputClick` looked up when clicked. `Window.render` shows the icons only when `ns.AH.isOpen` is true and a recipe is displayed (`showEmpty` hides them): `parts.tiles[1]:showIcon(enabled)`, `frame:showTitleIcon(enabled)`.
- Probe: `/cpp icon` prints, for the AH search box icon (`AuctionHouseFrame.SearchBar.SearchBox`): the keys of the box whose name contains "icon" or "Icon" with their type, and for `searchIcon`/`SearchIcon` the values of `GetAtlas()`, `GetTexture()` and `GetTexCoord()`; then for each of `{ "common-search-magnifyingglass", "search-icon", "auctionhouse-icon-search" }` the result of `C_Texture.GetAtlasInfo`. It must not raise when the AH has never been opened (print that `AuctionHouseFrame` is missing). Add `icon` to the command list line and bump the version to 0.7.0.
- `.luacheckrc`: add `C_Texture` to `read_globals`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_kit.lua` (`W`, `boot()`, `recordingFrames`, `load()` exist):

```lua
local function withGlobals(values, fn)
    local saved = {}
    for k, v in pairs(values) do saved[k] = _G[k]; _G[k] = v end
    local ok, err = pcall(fn)
    for k in pairs(values) do _G[k] = saved[k] end
    if not ok then error(err, 0) end
end

local function fakeTexture()
    local t = W.frame()
    t.calls = {}
    t.SetAtlas = function(_, a) t.calls[#t.calls + 1] = { "atlas", a } end
    t.SetTexture = function(_, p) t.calls[#t.calls + 1] = { "texture", p } end
    t.SetTexCoord = function(_, ...) t.calls[#t.calls + 1] = { "coord", ... } end
    return t
end

H.test("searchIcon copies the AH search box icon (atlas first, then texture and coordinates)", function()
    local _, Kit = boot()
    local source = { GetAtlas = function() return "common-search-magnifyingglass" end }
    withGlobals({ AuctionHouseFrame = { SearchBar = { SearchBox = { searchIcon = source } } } }, function()
        local tex = fakeTexture()
        H.truthy(Kit.searchIcon(tex))
        H.eq(tex.calls, { { "atlas", "common-search-magnifyingglass" } })
    end)
    local plain = { GetAtlas = function() return nil end, GetTexture = function() return "Interface\\X" end,
        GetTexCoord = function() return 0, 1, 0, 1 end }
    withGlobals({ AuctionHouseFrame = { SearchBar = { SearchBox = { SearchIcon = plain } } } }, function()
        local tex = fakeTexture()
        H.truthy(Kit.searchIcon(tex))
        H.eq(tex.calls, { { "texture", "Interface\\X" }, { "coord", 0, 1, 0, 1 } })
    end)
end)

H.test("searchIcon falls back to a verified atlas and gives up without drawing anything", function()
    local _, Kit = boot()
    withGlobals({ AuctionHouseFrame = false, C_Texture = { GetAtlasInfo = function(name)
        if name == "common-search-magnifyingglass" then return { width = 14 } end
    end } }, function()
        local tex = fakeTexture()
        H.truthy(Kit.searchIcon(tex))
        H.eq(tex.calls, { { "atlas", "common-search-magnifyingglass" } })
    end)
    withGlobals({ AuctionHouseFrame = false, C_Texture = { GetAtlasInfo = function() return nil end } }, function()
        local tex = fakeTexture()
        H.falsy(Kit.searchIcon(tex))
        H.eq(tex.calls, {})
    end)
    withGlobals({ AuctionHouseFrame = false, C_Texture = false }, function()
        H.falsy(Kit.searchIcon(fakeTexture()))
    end)
    withGlobals({ AuctionHouseFrame = { SearchBar = { SearchBox = { searchIcon = { GetAtlas = function() error("x") end } } } },
        C_Texture = false }, function()
        H.falsy(Kit.searchIcon(fakeTexture()))
    end)
end)

H.test("a tile can be made clickable, with a hover tint and a magnifier that shows on request", function()
    local T, Kit = boot()
    local rec = recordingFrames(T)
    local clicks = 0
    local tile = Kit.tile(nil, 110, 52)
    local hit = tile:onClick(function() clicks = clicks + 1 end)
    H.eq(tile.hit, hit)
    hit.scripts.OnClick(hit)
    H.eq(clicks, 1)
    local again = tile:onClick(function() clicks = clicks + 10 end)
    H.eq(again, hit)
    hit.scripts.OnClick(hit)
    H.eq(clicks, 11)
    withGlobals({ AuctionHouseFrame = { SearchBar = { SearchBox = { searchIcon = { GetAtlas = function() return "a" end } } } } }, function()
        tile.icon.SetAtlas = function() end
        tile:showIcon(true)
        H.truthy(tile.icon.shown)
        tile:showIcon(false)
        H.falsy(tile.icon.shown)
    end)
    withGlobals({ AuctionHouseFrame = false, C_Texture = false }, function()
        tile:showIcon(true)
        H.falsy(tile.icon.shown)
    end)
    hit.scripts.OnEnter(hit)
    hit.scripts.OnLeave(hit)
    Kit.applyTheme("steel")
    H.truthy(rec)
end)

H.test("the window title can be clicked, drags the window and lights up on hover", function()
    local _, Kit = boot()
    local moved, clicked = nil, 0
    local win = Kit.window("KitTitleClick", "Recipe", { onMoved = function(...) moved = { ... } end,
        onTitleClick = function() clicked = clicked + 1 end })
    local hit = win.titleHit
    H.truthy(hit)
    hit.scripts.OnClick(hit)
    H.eq(clicked, 1)
    H.truthy(hit.scripts.OnDragStart)
    hit.scripts.OnDragStop(hit)
    H.eq(moved, { "TOPLEFT", 100, 700 })
    local colours = {}
    win.titleText.SetTextColor = function(_, r, g, b, a) colours[#colours + 1] = { r, g, b, a } end
    hit.scripts.OnEnter(hit)
    H.eq(colours[#colours], Kit.current.textMain)
    hit.scripts.OnLeave(hit)
    H.eq(colours[#colours], Kit.current.plaqueText)
    H.truthy(win.titleIcon)
    win:showTitleIcon(false)
    H.falsy(win.titleIcon.shown)
end)

H.test("a window without a title click has no title button", function()
    local _, Kit = boot()
    local win = Kit.window("KitPlain", "Plain", {})
    H.falsy(win.titleHit)
end)
```

Append to `tests/test_window.lua` (`boot()` returns `T, Window, calls`; the handlers table is `Window.lastHandlers`; add `"onOutputClick"` to the list of handler names it replaces at the top of `boot()`):

```lua
H.test("clicking the AH tile or the title asks to search the crafted item", function()
    local _, Window, calls = boot()
    Window.render(model())
    local tile = Window.parts.tiles[1]
    tile.hit.scripts.OnClick(tile.hit)
    H.eq(calls[#calls], { "onOutputClick" })
    local title = Window.frame().titleHit
    title.scripts.OnClick(title)
    H.eq(calls[#calls], { "onOutputClick" })
    H.falsy(Window.parts.tiles[2].hit)
end)

H.test("the magnifier icons show only while the AH is open and a recipe is displayed", function()
    local T, Window = boot()
    local function icons(want)
        H.eq(Window.parts.tiles[1].icon.shown == true, want)
        H.eq(Window.frame().titleIcon.shown == true, want)
    end
    local saved = _G.AuctionHouseFrame
    _G.AuctionHouseFrame = { SearchBar = { SearchBox = { searchIcon = { GetAtlas = function() return "a" end } } } }
    local ok, err = pcall(function()
        T.ns.AH.isOpen = false
        Window.render(model())
        icons(false)
        T.ns.AH.isOpen = true
        Window.render(model())
        icons(true)
        Window.showEmpty("Select a recipe")
        icons(false)
    end)
    _G.AuctionHouseFrame = saved
    if not ok then error(err, 0) end
end)
```
(`SetAtlas` on the fake texture is a no-op method so the icon applies.)

- [ ] **Step 2: Run to see failures** — expect failures for the new functions.

- [ ] **Step 3: Implement.**

`Kit.lua`, after the `Kit.scrollbar` section or next to the tile code (keep the `naturalWidth` etc. local helpers where they are):

```lua
-- Magnifier icon -------------------------------------------------------------

Kit.SEARCH_ATLASES = { "common-search-magnifyingglass" }

local function searchBoxIcon()
    local frame = AuctionHouseFrame
    local bar = type(frame) == "table" and frame.SearchBar
    local box = type(bar) == "table" and bar.SearchBox
    if type(box) ~= "table" then return nil end
    return box.searchIcon or box.SearchIcon
end

-- Gives `texture` the game's magnifier: the icon of the AH search box if it can be read,
-- else a known atlas that exists. Never guesses a file path (a missing file would draw a
-- green square). Returns true when an icon was applied.
function Kit.searchIcon(texture)
    local ok, applied = pcall(function()
        local source = searchBoxIcon()
        if type(source) == "table" then
            local atlas = type(source.GetAtlas) == "function" and source:GetAtlas()
            if type(atlas) == "string" and atlas ~= "" then
                texture:SetAtlas(atlas)
                return true
            end
            local file = type(source.GetTexture) == "function" and source:GetTexture()
            if file ~= nil and file ~= "" then
                texture:SetTexture(file)
                if type(source.GetTexCoord) == "function" then texture:SetTexCoord(source:GetTexCoord()) end
                return true
            end
        end
        local api = C_Texture
        if type(api) == "table" and type(api.GetAtlasInfo) == "function" then
            for _, name in ipairs(Kit.SEARCH_ATLASES) do
                if type(api.GetAtlasInfo(name)) == "table" then
                    texture:SetAtlas(name)
                    return true
                end
            end
        end
        return false
    end)
    return ok and applied == true
end
```

`Kit.tile`: add inside the function (after `tile:set`):

```lua
    -- Makes the whole tile a button (e.g. to search the item at the AH): a hover tint and a
    -- small icon at the top right that `tile:showIcon(true)` reveals when the game's
    -- magnifier can be found. Calling it again replaces the handler.
    function tile:onClick(fn)
        if not self.hit then
            local hit = CreateFrame("Button", nil, f)
            hit:SetAllPoints(f)
            local tint = hit:CreateTexture(nil, "BACKGROUND")
            tint:SetAllPoints(hit)
            Kit.onTheme(function(t)
                local c = t.rowHover
                tint:SetColorTexture(c[1], c[2], c[3], c[4])
            end)
            tint:Hide()
            hit:HookScript("OnEnter", function() tint:Show() end)
            hit:HookScript("OnLeave", function() tint:Hide() end)
            self.icon = hit:CreateTexture(nil, "OVERLAY")
            self.icon:SetSize(12, 12)
            self.icon:SetPoint("TOPRIGHT", hit, "TOPRIGHT", -6, -6)
            self.icon:Hide()
            self.hit = hit
        end
        self.hit:SetScript("OnClick", fn)
        return self.hit
    end

    function tile:showIcon(show)
        if not self.icon then return end
        if show and Kit.searchIcon(self.icon) then self.icon:Show() else self.icon:Hide() end
    end
```
(The hit Button created after the labels sits above them; it has no text and does not hide them. The tint's drawing layer is BACKGROUND of the hit button: it draws over the tile's own background and ring but under the texts, which belong to the tile frame: if the tint covers the texts in the client, set `hit:SetFrameLevel(f:GetFrameLevel())` so the button sits at the tile's level; the implementer decides from the Kit facts, keep the click working.)

`Kit.window`: after the plaque and title text exist, when `opts.onTitleClick`:

```lua
    if opts.onTitleClick then
        local hit = CreateFrame("Button", nil, plaque)
        hit:SetAllPoints(plaque)
        hit:RegisterForDrag("LeftButton")
        hit:SetScript("OnClick", function() opts.onTitleClick() end)
        hit:SetScript("OnDragStart", function() f:StartMoving() end)
        hit:SetScript("OnDragStop", function() stopDrag(f) end)
        hit:HookScript("OnEnter", function() setTextColor(text, "textMain") end)
        hit:HookScript("OnLeave", function() setTextColor(text, "plaqueText") end)
        f.titleHit = hit
        f.titleIcon = hit:CreateTexture(nil, "OVERLAY")
        f.titleIcon:SetSize(12, 12)
        f.titleIcon:SetPoint("RIGHT", plaque, "RIGHT", -8, 0)
        f.titleIcon:Hide()
        f.showTitleIcon = function(_, show)
            if show and Kit.searchIcon(f.titleIcon) then f.titleIcon:Show() else f.titleIcon:Hide() end
        end
    end
```
Note: `f.showTitleIcon` must exist for windows with `onTitleClick` only; `Window.render`/`showEmpty` call it through a nil-safe helper. `setTitle` re-sets the text colour with `setTextColor(text, "plaqueText")`, which also ends a hover tint: acceptable.

`Window.lua`: in `Window.create` pass `onTitleClick = function() if handlers.onOutputClick then handlers.onOutputClick() end end` to `Kit.window`, and after `buildTiles()` call `parts.tiles[1]:onClick(function() if handlers.onOutputClick then handlers.onOutputClick() end end)`. In `Window.render` after the tiles are set: `local searchable = ns.AH and ns.AH.isOpen == true; parts.tiles[1]:showIcon(searchable); frame:showTitleIcon(searchable)`; in `showEmpty`: `parts.tiles[1]:showIcon(false); frame:showTitleIcon(false)`.

Probe (`probe/CraftProfitProbe/Probe.lua`, not linted): add `cmds.icon` as specified, update the usage line and `VERSION = "0.7.0"`. `.luacheckrc`: `"C_Texture"`.

- [ ] **Step 4: Run the whole suite** — `sh tests/check.sh 2>&1 | grep -E "passed|failed|Total|FAIL"`; expect `0 failed`, `0 warnings`; the existing Window tests that count textures or tiles must pass unchanged.

- [ ] **Step 5: Commit**

```bash
git status --short
git add CraftProfit/UI/Kit.lua CraftProfit/UI/Window.lua .luacheckrc probe/CraftProfitProbe/Probe.lua tests/test_kit.lua tests/test_window.lua
git commit -m "feat: clickable AH tile and title with the game's magnifier icon"
```

---

### Task 3: Docs

**Files:** `docs/in-game-checklist.md`, `docs/user-guide.md`, `docs/user-guide.fr.md`, `docs/technical.md`, `CHANGELOG.md`, `docs/superpowers/specs/2026-10-09-ui-rework-design.md`

- [ ] **Step 1: Docs** (document what the code does):
  - Guides (EN and FR, natural French): in *The window* and *At the auction house*: with the auction house open, click the **AH (NET)** / **HV (NET)** tile or the recipe title to search the crafted item there (to see how many are for sale next to the price); a small magnifier shows on both while the auction house is open; with the auction house closed it says to open it; a bind-on-pickup item cannot be sold so nothing is searched; the title still drags the window.
  - Checklist: new section "Search the crafted item": run `/cpp icon` and read the lines in the probe log; magnifier on the tile and the title while the AH is open and gone when it closes; the tile tints on hover; click the tile and the title: the AH Buy view opens on the item name (compare with a reagent click); drag the window by the title (press and move) still works and a plain click searches; AH closed: message; a bind-on-pickup recipe: message; theme switch repaints the hover tint; if no magnifier appears, report the `/cpp icon` lines (known: the icon is optional, the click works without it).
  - technical.md: `Kit.searchIcon` (sources, never guesses a path), `tile:onClick`/`showIcon`, `Kit.window` `onTitleClick`/`titleHit`/`titleIcon`, `Controller.onOutputClick`, the probe command.
  - CHANGELOG: Added: click the AH tile or the recipe title to search the crafted item at the auction house (with a magnifier icon).
  - Spec: add a short "Search the crafted item (post PR 3)" note in the Kit section: `Kit.searchIcon`, `tile:onClick`, window `onTitleClick`.
- [ ] **Step 2: Run everything and verify authorship** — `sh tests/check.sh 2>&1 | grep -E "passed|failed|Total"; echo "coauthor: $(git log --format=%B main..HEAD | grep -ci co-authored)"`; expect `0 failed`, `0 warnings`, `coauthor: 0`.
- [ ] **Step 3: Commit** (do NOT push, do NOT open a PR: the controller does)

```bash
git status --short
git add docs CHANGELOG.md
git commit -m "docs: search the crafted item at the auction house"
```
