# UI main window (PR 2 of 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the main window (`UI/Window.lua`) on the shared UI kit: a result banner, three tiles for the ways to sell the item, a Materials panel and an Options panel. The pinned list keeps its current look for now (PR 3).

**Architecture:** `Present.build` adds three fields to the model (`banner`, `tiles`, `materials`) and keeps `lines` and `verdict`. The kit gains the widgets the window needs (check box, input box, clickable panel header) and fixes found in PR 1's review. `Window.lua` is rewritten on the kit; its public interface (create, render, showEmpty, attach, show/hide/isShown, pinsHost, relayout, frame, WIDTH, lastModel, lastHandlers) is unchanged, so `Boot.lua`, `PinsUI.lua` and `LevelingUI.lua` need no change.

**Tech Stack:** Lua 5.1 (WoW client), LuaJIT test harness (`tests/harness.lua`, `tests/fakewow.lua`), luacheck.

**Spec:** `docs/superpowers/specs/2026-10-09-ui-rework-design.md`. Foundations done in PR 1: `docs/superpowers/plans/2026-10-09-ui-foundations.md`.

## Plan amendments to the spec

- `Present.build` keeps `model.lines` and `model.verdict` (tests and the leveling code read them) and ADDS `banner`, `tiles` and `materials`. The spec said the old lines would be removed; keeping them costs nothing and avoids rewriting about forty tests. The window reads `lines` only for the `likely` and `perpoint` entries.
- A theme token `rowHover` is added (hover fill of clickable rows), in all three themes.
- `Kit.panel` gets `:onHeaderClick(fn)`; folding the Materials panel is done by the window (hide the body, set the section height to `Kit.FOLDED_H`), not by a kit method.
- The per-point result is shown on the right of the "Cost per point" row of the Options panel (value only, coloured by gain or loss), not as a separate line.
- Kit review follow-ups folded in here: hover through `HookScript`, hover feedback on primary buttons, plaque draggable like the window, `panel.right` and the tile tag painted from the theme, tile value and label anchored on both sides, `Kit.TILE_PAD`, contrast checks for the new text pairs, window title fitted to the window width. Not done (kept for later): `SetClampRectInsets` for the plaque overhang, registry pruning (this window builds its widgets once and reuses its rows, so the registry does not grow), Escape-to-close.

## Global Constraints

- Interface 16001, Lua 5.1: no `goto`, `require`, `io`, `loadfile`, `dofile`, `setfenv`, `getfenv` in addon files, comments included (`tests/test_toc.lua` scans the text; a word ending in "io." matches `io%.`).
- No literal zero divisor anywhere in `CraftProfit/` (`tests/test_source.lua`; the game raises "Division by zero").
- Every game global the addon reads is declared in `.luacheckrc`; `sh tests/check.sh` must end with 0 failures and 0 warnings.
- Every file listed in `CraftProfit.toc` exactly once; no file on disk unlisted.
- English only for code comments and docs, except the French texts in `Locales/frFR.lua`, `README.fr.md`, `docs/user-guide.fr.md` and the Spanish ones in `Locales/esES.lua`.
- Panel titles and tile labels are written already in capitals in the locale files (`string.upper` does not handle UTF-8 accents in Lua 5.1).
- Never mention a co-author in commits, pushes or PR bodies. Verify with `git log --format=%B | grep -ci co-authored` (must print 0).
- Branch `feat/ui-main-window`, one PR, merged only when the author says so. gh must be logged in as **Renaud-Sto**.
- Several Lua files flip to mode 755 in the working tree by themselves: run `git status --short` before every commit and `chmod 644` any Lua file listed as modified that you did not edit.
- Behaviour that must not change: clicking a reagent row searches it at the auction house with the quantity; clicking the Materials header folds or unfolds the detail (setting `costExpanded`); the crafts box applies on focus loss and is never rewritten while it has focus; window position is saved on drag; the window closes with the profession or auction house window (Boot logic, untouched).

## Review Focus

- A real frame is created SHOWN and unanchored: `Window.create` must leave the window hidden (the fake test frames start hidden, so tests must simulate shown frames).
- Fold state: folded Materials shows only the header (`+` prefix), hides all reagent rows and their click areas; unfolded shows exactly as many rows as the model has cost lines (at most 12).
- A very long recipe name must not overflow the plaque; a very long amount (`999g 99s 99c`) must not overflow its tile or the banner value.
- The crafts box must never be rewritten while it has focus, and must send its text to `onCraftsChange` on focus loss.
- With no per-point line in the model, the per-point value is hidden; with a gain, it is shown with a `+` and the profit colour.
- Window height always equals the sum of the visible sections plus the content insets (plus the pinned list when it is shown): no clipped or overlapping panel.
- Switching theme (`Kit.applyTheme`) repaints every part of the window, including the banner tint, which depends on the result kind and not on the theme.

## File Structure

| File | Responsibility |
| --- | --- |
| `CraftProfit/Locales/enUS.lua`, `frFR.lua`, `esES.lua` | new keys: RESULT, TILE_*, BETA_TAG, PANEL_* |
| `CraftProfit/Present.lua` | `banner`, `tiles`, `materials` in the model |
| `CraftProfit/Theme.lua` | token `rowHover` |
| `CraftProfit/UI/Kit.lua` | helpers `mix`, `colorEscape`, `plaqueWidth`, `onTheme`; fixes; `check`, `input`, `panel:onHeaderClick` |
| `CraftProfit/UI/KitDemo.lua` | shows the new widgets |
| `CraftProfit/UI/Window.lua` | rewritten on the kit |
| `tests/test_present.lua`, `test_theme.lua`, `test_kit.lua`, `test_window.lua` (new) | tests |
| `docs/technical.md`, `docs/in-game-checklist.md`, `docs/user-guide.md`, `docs/user-guide.fr.md`, `CHANGELOG.md`, spec | docs |

---

### Task 1: Locale keys and the presentation model

**Files:**
- Modify: `CraftProfit/Locales/enUS.lua`, `CraftProfit/Locales/frFR.lua`, `CraftProfit/Locales/esES.lua`, `CraftProfit/Present.lua`
- Test: `tests/test_present.lua`, `tests/test_locale.lua` (existing parity tests must keep passing)

**Interfaces:**
- Produces: `L.RESULT`, `L.TILE_AH`, `L.TILE_VENDOR`, `L.TILE_DISENCHANT`, `L.BETA_TAG`, `L.PANEL_MATERIALS`, `L.PANEL_MATERIALS_MULTI` (takes the number of crafts), `L.PANEL_OPTIONS`. `Present.build(...)` returns, in addition to its current fields:
  - `banner = { label, text, value, kind }` with `text`/`value`/`kind` taken from `verdict` and `label = L.RESULT`;
  - `tiles = { { key, label, value, best, muted, tag }, ... }` in `Core.OPTION_ORDER` order (`ah`, `vendor`, `disenchant`); `value` is the formatted amount, `L.NA` or `L.UNKNOWN`; `muted` is true unless the option status is `ok`; `best` is true for the best option; `tag = L.BETA_TAG` on the disenchant tile only;
  - `materials = { title, total }`: `L.PANEL_MATERIALS`, or `string.format(L.PANEL_MATERIALS_MULTI, crafts)` when `crafts > 1`; `total` is the formatted cost total.

- [ ] **Step 1: Write the failing tests** (append to `tests/test_present.lua`)

`load()` and `model(ns, over, opts)` already exist in that file (the default recipe gives: AH `9s 50c` best, vendor `2s`, disenchant `3s 80c`, materials `2s 50c`, verdict profit `Best: Auction house` / `+7s`).

```lua
H.test("the model carries a banner copied from the verdict", function()
    local m = model(load())
    H.eq(m.banner, { label = "RESULT", text = "Best: Auction house", value = "+7s", kind = "profit" })
end)

H.test("the model carries one tile per way to sell, the best one flagged and the disenchant one tagged", function()
    local m = model(load())
    H.eq(m.tiles[1], { key = "ah", label = "AH (NET)", value = "9s 50c", best = true, muted = false })
    H.eq(m.tiles[2], { key = "vendor", label = "VENDOR", value = "2s", best = false, muted = false })
    H.eq(m.tiles[3], { key = "disenchant", label = "DISENCH.", value = "3s 80c", best = false, muted = false, tag = "beta" })
    H.eq(#m.tiles, 3)
end)

H.test("tiles of options that cannot be sold or have no price are muted with n/a or ?", function()
    local ns = load()
    local none = model(ns, { itemInfo = function() return { quality = 1, ilvl = 1, sellPrice = 0, classID = 0, bindType = 1 } end })
    H.eq(none.tiles[2].value, "n/a")
    H.truthy(none.tiles[2].muted)
    local partial = model(ns, { priceOf = function(id) if id == 100 then return nil end return 50, 120 end })
    H.eq(partial.tiles[1].value, "?")
    H.truthy(partial.tiles[1].muted)
end)

H.test("the materials panel text follows the number of crafts", function()
    local ns = load()
    H.eq(model(ns).materials, { title = "MATERIALS", total = "2s 50c" })
    H.eq(model(ns, { crafts = 3 }).materials, { title = "MATERIALS x3 (ESTIMATE)", total = "7s 50c" })
end)

H.test("the French and Spanish models use their own panel and tile texts", function()
    local ns = load()
    ns.Locale.select("frFR")
    local m = model(ns)
    H.eq(m.banner.label, "RÉSULTAT")
    H.eq(m.materials.title, "COMPOSANTS")
    H.eq(m.tiles[1].label, "HV (NET)")
    H.eq(m.tiles[3].tag, "bêta")
end)
```

If the "n/a" or "?" fixtures above do not reproduce those statuses with the file's existing helpers, adapt the fixture (look at the existing tests "nothing sellable gives the none verdict and n/a lines" and "a missing price gives an incomplete verdict" for the working overrides), keep the assertions.

- [ ] **Step 2: Run to see failures**

Run: `luajit tests/run.lua 2>&1 | grep FAIL | head`
Expected: the new tests fail (`banner` is nil).

- [ ] **Step 3: Add the locale keys.** In each locale file add, next to the other panel and label keys (match the file's style):

`enUS`:
```lua
    RESULT = "RESULT",
    TILE_AH = "AH (NET)",
    TILE_VENDOR = "VENDOR",
    TILE_DISENCHANT = "DISENCH.",
    BETA_TAG = "beta",
    PANEL_MATERIALS = "MATERIALS",
    PANEL_MATERIALS_MULTI = "MATERIALS x%d (ESTIMATE)",
    PANEL_OPTIONS = "OPTIONS",
```
`frFR`:
```lua
    RESULT = "RÉSULTAT",
    TILE_AH = "HV (NET)",
    TILE_VENDOR = "MARCHAND",
    TILE_DISENCHANT = "DÉSENCH.",
    BETA_TAG = "bêta",
    PANEL_MATERIALS = "COMPOSANTS",
    PANEL_MATERIALS_MULTI = "COMPOSANTS x%d (ESTIMATION)",
    PANEL_OPTIONS = "OPTIONS",
```
`esES`:
```lua
    RESULT = "RESULTADO",
    TILE_AH = "CASA (NETO)",
    TILE_VENDOR = "VENDEDOR",
    TILE_DISENCHANT = "DESENC.",
    BETA_TAG = "beta",
    PANEL_MATERIALS = "MATERIALES",
    PANEL_MATERIALS_MULTI = "MATERIALES x%d (ESTIMADO)",
    PANEL_OPTIONS = "OPCIONES",
```

- [ ] **Step 4: Extend `Present.build`.** In `CraftProfit/Present.lua` add near the other key tables:

```lua
local TILE_KEYS = { ah = "TILE_AH", vendor = "TILE_VENDOR", disenchant = "TILE_DISENCHANT" }
```

and, inside `Present.build`, replace the final `return { ... }` so that the verdict is computed once and the new fields are added:

```lua
    local verdict = verdictFor(result, L, fmt)
    local tiles = {}
    for _, key in ipairs(Core.OPTION_ORDER) do
        local option = result.options[key]
        local text
        if option.status == "ok" then
            text = fmt(option.value)
        elseif option.status == "na" then
            text = L.NA
        else
            text = L.UNKNOWN
        end
        tiles[#tiles + 1] = {
            key = key, label = L[TILE_KEYS[key]], value = text,
            best = result.best == key, muted = option.status ~= "ok",
            tag = key == "disenchant" and L.BETA_TAG or nil,
        }
    end
    return {
        lines = lines,
        crafts = crafts,
        costLines = costLines,
        verdict = verdict,
        banner = { label = L.RESULT, text = verdict.text, value = verdict.value, kind = verdict.kind },
        tiles = tiles,
        materials = {
            title = crafts > 1 and string.format(L.PANEL_MATERIALS_MULTI, crafts) or L.PANEL_MATERIALS,
            total = fmt(result.cost.total),
        },
        ageText = Present.ageText(L, result.oldestAge),
        stale = not Util.isFinite(result.oldestAge) or result.oldestAge > staleAfter,
    }
```

- [ ] **Step 5: Run the whole suite**

Run: `sh tests/check.sh 2>&1 | grep -E "passed|failed|Total|FAIL"`
Expected: `0 failed`, `0 warnings`. The locale parity tests prove the three languages define the same keys.

- [ ] **Step 6: Commit**

```bash
git status --short   # chmod 644 any Lua file you did not edit
git add CraftProfit/Locales CraftProfit/Present.lua tests/test_present.lua
git commit -m "feat: banner, tiles and materials panel text in the presentation model"
```

---

### Task 2: Kit helpers and fixes to the existing widgets

**Files:**
- Modify: `CraftProfit/Theme.lua`, `CraftProfit/UI/Kit.lua`
- Test: `tests/test_theme.lua`, `tests/test_kit.lua`

**Interfaces:**
- Produces on `ns.Kit`: constants `PLAQUE_MIN = 210`, `PLAQUE_PAD = 44`, `TILE_PAD = 10`, `FOLDED_H = Kit.HEAD_H + 2`; `mix(a, b, t) -> colour`; `colorEscape(colour) -> "|cffRRGGBB"`; `plaqueWidth(textWidth, maxWidth) -> number`; `onTheme(paint)` (registers `paint(theme)` and calls it now). `Kit.rings` also accepts, as a token, a function returning a colour table `{r,g,b,a}`.
- Theme: new token `rowHover` (fill of a hovered clickable row) in `Theme.TOKENS` and in the three themes.
- Behaviour changes: button hover through `HookScript` (so a later `SetScript` cannot erase it) and visible hover feedback on primary buttons; the plaque drags the window like the window body; `panel.right` is painted `textMain`; the tile tag colour comes from `Theme.FIXED.best`; tile label and value are anchored on both sides (long text truncates inside the tile); the window title uses the small font when it would not fit, and the plaque never exceeds the window content width.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_theme.lua`:

```lua
H.test("the hover fill token exists in every theme", function()
    local Theme = load()
    for _, name in ipairs(Theme.list()) do H.truthy(Theme.get(name).rowHover) end
end)
```

Append to `tests/test_kit.lua` (`W`, `boot()` and `load()` exist; `recordingFrames` is new):

```lua
-- Frames whose textures record the last colour they were given, so a repaint is observable.
local function recordingFrames(T)
    local rec = {}
    local create = T.env.CreateFrame
    T.env.CreateFrame = function(...)
        local f = create(...)
        f.CreateTexture = function()
            local tex = W.frame()
            tex.SetColorTexture = function(self, r, g, b, a) self.color = { r, g, b, a } end
            rec[#rec + 1] = tex
            return tex
        end
        return f
    end
    return rec
end

H.test("mix moves a colour toward another by a fraction, channel by channel", function()
    local Kit = load()
    H.eq(Kit.mix({ 0, 0, 0, 1 }, { 1, 0.5, 1, 0 }, 0.5), { 0.5, 0.25, 0.5, 0.5 })
    H.eq(Kit.mix({ 0.2, 0.2, 0.2, 1 }, { 1, 1, 1, 1 }, 0), { 0.2, 0.2, 0.2, 1 })
end)

H.test("colorEscape turns a colour into a chat colour escape and clamps out-of-range channels", function()
    local Kit = load()
    H.eq(Kit.colorEscape({ 1, 0.82, 0, 1 }), "|cffffd100")
    H.eq(Kit.colorEscape({ 0, 0, 0, 1 }), "|cff000000")
    H.eq(Kit.colorEscape({ 2, -1, 0.5, 1 }), "|cffff0080")
end)

H.test("plaqueWidth keeps the minimum, grows with the title and stops at the window width", function()
    local Kit = load()
    H.eq(Kit.plaqueWidth(50, 348), 210)
    H.eq(Kit.plaqueWidth(200, 348), 244)
    H.eq(Kit.plaqueWidth(400, 348), 348)
    H.eq(Kit.plaqueWidth(nil, 348), 210)
    H.eq(Kit.plaqueWidth(300, nil), 344)
end)

H.test("onTheme paints now and again on every theme switch", function()
    local _, Kit = boot()
    local seen = {}
    Kit.onTheme(function(t) seen[#seen + 1] = t.name end)
    Kit.applyTheme("steel")
    H.eq(seen, { "gold", "steel" })
end)

H.test("rings accept a function returning a colour table", function()
    local T, Kit = boot()
    local rec = recordingFrames(T)
    local frame = T.env.CreateFrame("Frame")
    local edge = { 1, 0, 0, 0.5 }
    local refresh = Kit.rings(frame, { function() return edge end })
    H.eq(rec[1].color, { 1, 0, 0, 0.5 })
    edge[1] = 0.25
    refresh()
    H.eq(rec[1].color, { 0.25, 0, 0, 0.5 })
end)

H.test("a normal button lights up on hover and a primary one gets a lighter fill", function()
    local T, Kit = boot()
    local rec = recordingFrames(T)
    local Theme = T.ns.Theme
    local gold = Theme.get("gold")
    local normal = Kit.button(nil, "normal", "Ok")
    H.eq(rec[1].color, gold.buttonBg)
    normal.scripts.OnEnter(normal)
    H.eq(rec[1].color, gold.primaryBg)
    normal.scripts.OnLeave(normal)
    H.eq(rec[1].color, gold.buttonBg)
    local before = #rec
    local primary = Kit.button(nil, "primary", "Go")
    local bg = rec[before + 1]
    H.eq(bg.color, gold.primaryBg)
    primary.scripts.OnEnter(primary)
    H.eq(bg.color, Kit.mix(gold.primaryBg, gold.primaryEdge, 0.35))
end)

H.test("the plaque drags the window", function()
    local _, Kit = boot()
    local moved
    local win = Kit.window("KitTestPlaque", "T", { onMoved = function(...) moved = { ... } end })
    H.truthy(win.plaque.scripts.OnDragStart)
    win.plaque.scripts.OnDragStop(win.plaque)
    H.eq(moved, { "TOPLEFT", 100, 700 })
end)

H.test("a long title uses the small font and the plaque stops at the content width", function()
    local _, Kit = boot()
    local win = Kit.window("KitTestTitle", "T", { width = 372 })
    local fonts, widths = {}, {}
    win.GetWidth = function() return 372 end
    win.titleText.SetFontObject = function(_, name) fonts[#fonts + 1] = name end
    win.titleText.GetStringWidth = function() return 500 end
    win.plaque.SetWidth = function(_, w) widths[#widths + 1] = w end
    win:setTitle("A very long recipe name")
    H.eq(fonts, { "GameFontNormal", "GameFontNormalSmall" })
    H.eq(widths[#widths], 348)
end)

H.test("panel.right and the tile tag are painted from the theme, not a literal colour", function()
    local T, Kit = boot()
    local Theme = T.ns.Theme
    local panel = Kit.panel(nil, "X")
    local last
    panel.right.SetTextColor = function(_, r, g, b, a) last = { r, g, b, a } end
    Kit.applyTheme("steel")
    H.eq(last, Theme.get("steel").textMain)
    local tile = Kit.tile(nil, 110, 52)
    tile:set({ label = "DISENCH.", tag = "beta", value = "1g" })
    H.truthy(tile.label.text:find(Kit.colorEscape(Theme.FIXED.best) .. "beta", 1, true))
end)
```

- [ ] **Step 2: Run to see failures**

Run: `luajit tests/run.lua 2>&1 | grep FAIL | head -12`
Expected: failures for the missing helpers and behaviours.

- [ ] **Step 3: Implement.**

`CraftProfit/Theme.lua`: add `"rowHover"` to `Theme.TOKENS` (after `"rowZebra"`) and to each theme: `rowHover = hex("FFFFFF", 0.08),` right after its `rowZebra` line.

`CraftProfit/UI/Kit.lua`:

1. Constants (replace the `PLAQUE_MIN_WIDTH` local and add the others, near the other `Kit.*` constants):

```lua
Kit.PLAQUE_MIN = 210
Kit.PLAQUE_PAD = 44
Kit.TILE_PAD = 10
Kit.FOLDED_H = Kit.HEAD_H + 2
```
and remove `local PLAQUE_MIN_WIDTH = 210` (use `Kit.PLAQUE_MIN` in `Kit.window`).

2. New pure helpers, after `Kit.gradient`:

```lua
-- Colour `a` moved toward colour `b` by the fraction `t` (0..1), channel by channel.
function Kit.mix(a, b, t)
    return {
        a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t,
        a[3] + (b[3] - a[3]) * t, a[4] + (b[4] - a[4]) * t,
    }
end

-- "|cffRRGGBB" chat colour escape for a colour (alpha is ignored).
function Kit.colorEscape(c)
    local function byte(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
    return string.format("|cff%02x%02x%02x", byte(c[1]), byte(c[2]), byte(c[3]))
end

-- Width of a title plaque: wide enough for the text, never below the minimum, never
-- above `maxWidth`; the minimum when the text cannot be measured.
function Kit.plaqueWidth(textWidth, maxWidth)
    local width = Kit.PLAQUE_MIN
    if type(textWidth) == "number" then width = math.max(width, textWidth + Kit.PLAQUE_PAD) end
    if type(maxWidth) == "number" then width = math.min(width, maxWidth) end
    return width
end
```

3. After `Kit.applyTheme`, add the public registration:

```lua
-- For code outside the kit that paints itself from the theme: `paint(theme)` is called
-- now and on every theme switch.
function Kit.onTheme(paint) register(paint) end
```

4. `colorOf`: accept a colour table:

```lua
local function colorOf(token)
    if type(token) == "function" then token = token() end
    if type(token) == "table" then return token end
    if token == "black" then return { 0, 0, 0, 1 } end
    return Kit.current[token]
end
```
and update its comment to "A token name, a colour table, a function returning either, or "black"".

5. `Kit.window`: replace the two drag handlers and the plaque/title code:

```lua
    local function stopDrag(self)
        self:StopMovingOrSizing()
        -- Re-anchor to the screen's bottom-left corner so saved offsets are absolute.
        local left, top = self:GetLeft(), self:GetTop()
        if left and top then
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            if opts.onMoved then opts.onMoved("TOPLEFT", left, top) end
        end
    end
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", stopDrag)
```
After the plaque frame is created (`plaque:SetSize(Kit.PLAQUE_MIN, 26)`), make it a drag handle too:

```lua
    plaque:EnableMouse(true)
    plaque:RegisterForDrag("LeftButton")
    plaque:SetScript("OnDragStart", function() f:StartMoving() end)
    plaque:SetScript("OnDragStop", function() stopDrag(f) end)
```
and replace `f.setTitle`:

```lua
    text:SetWordWrap(false)
    f.setTitle = function(_, value)
        text:SetFontObject("GameFontNormal")
        text:SetText(value or "")
        local frameWidth = f:GetWidth()
        local maxWidth = type(frameWidth) == "number" and frameWidth - Kit.CONTENT_SIDE * 2 or nil
        local width = text:GetStringWidth()
        if maxWidth and type(width) == "number" and width + Kit.PLAQUE_PAD > maxWidth then
            text:SetFontObject("GameFontNormalSmall")
            width = text:GetStringWidth()
        end
        local plaqueW = Kit.plaqueWidth(width, maxWidth)
        plaque:SetWidth(plaqueW)
        text:SetWidth(plaqueW - 16)
    end
```
(the `text:SetPoint("CENTER", ...)` stays).

6. `Kit.panel`: in the theme paint function add `setTextColor(p.right, "textMain")`.

7. `Kit.button`: replace the two `SetScript` hover lines with `HookScript` and give primary buttons a hover fill:

```lua
    local function paint(t)
        local c
        if primary then
            c = hover and Kit.mix(t.primaryBg, t.primaryEdge, 0.35) or t.primaryBg
        else
            c = hover and t.primaryBg or t.buttonBg
        end
        bg:SetColorTexture(c[1], c[2], c[3], c[4])
        setTextColor(b.label, primary and "primaryText" or "buttonText")
    end
    register(paint)
    b:HookScript("OnEnter", function() hover = true; paint(Kit.current) end)
    b:HookScript("OnLeave", function() hover = false; paint(Kit.current) end)
```

8. `Kit.tile`: anchor both sides, use `Kit.TILE_PAD`, theme the tag colour:

```lua
    tile.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tile.label:SetPoint("TOPLEFT", f, "TOPLEFT", Kit.TILE_PAD, -8)
    tile.label:SetPoint("TOPRIGHT", f, "TOPRIGHT", -Kit.TILE_PAD, -8)
    tile.label:SetJustifyH("LEFT")
    tile.label:SetWordWrap(false)
    tile.value = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tile.value:SetPoint("TOPLEFT", f, "TOPLEFT", Kit.TILE_PAD, -24)
    tile.value:SetPoint("TOPRIGHT", f, "TOPRIGHT", -Kit.TILE_PAD, -24)
    tile.value:SetJustifyH("LEFT")
    tile.value:SetWordWrap(false)
```
In `tile:set`: `if spec.tag then label = label .. " " .. Kit.colorEscape(Theme.FIXED.best) .. spec.tag .. "|r" end` and `local room = (f:GetWidth() or width or 110) - Kit.TILE_PAD * 2`.

Update the existing tile test (the one that stubs `SetFont` and asserts `Kit.fitSize(200, 19, 90, Kit.TILE_SIZES)`) to compute the box as `110 - Kit.TILE_PAD * 2` instead of the literal 90.

- [ ] **Step 4: Run the whole suite**

Run: `sh tests/check.sh 2>&1 | grep -E "passed|failed|Total|FAIL"`
Expected: `0 failed`, `0 warnings`.

- [ ] **Step 5: Commit**

```bash
git status --short
git add CraftProfit/Theme.lua CraftProfit/UI/Kit.lua tests/test_theme.lua tests/test_kit.lua
git commit -m "feat: kit helpers (mix, colour escape, plaque width, onTheme) and widget fixes from the PR 1 review"
```

---

### Task 3: Kit check box, input box and clickable panel header

**Files:**
- Modify: `CraftProfit/UI/Kit.lua`, `CraftProfit/UI/KitDemo.lua`
- Test: `tests/test_kit.lua`, `tests/test_theme.lua`

**Interfaces:**
- Produces on `ns.Kit`:
  - `Kit.check(parent, text) -> button` a themed check box: `button:SetChecked(bool)`, `button:GetChecked() -> bool`, `button:setText(text)`, `button.label` (FontString to the right), `button.mark` (the check mark texture), `button.onToggle` (optional callback `fn(checked)` called after a click toggled it). Clicking toggles the state.
  - `Kit.input(parent, width, maxLetters) -> editBox` a themed single-line box, 22 px high, text centred, `OnEscapePressed` and `OnEnterPressed` clear its focus.
  - `panel:onHeaderClick(fn) -> hit` on a panel: a button covering the header, `hit` is also stored as `panel.headerHit`; its `OnClick` runs `fn`.
- Theme contrast: text on the input box and check mark must be readable.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_theme.lua`:

```lua
H.test("the text drawn on inputs, check marks and the title plaque stays readable in every theme", function()
    local Theme = load()
    for _, name in ipairs(Theme.list()) do
        local t = Theme.get(name)
        if contrast(t.textMain, t.inputBg) < 4.5 then error(name .. ": textMain on inputBg") end
        if contrast(t.checkMark, t.inputBg) < 4.5 then error(name .. ": checkMark on inputBg") end
        if contrast(t.plaqueText, t.plaqueBg) < 4.5 then error(name .. ": plaqueText on plaqueBg") end
    end
end)
```
(If an assertion fails, raise the lightness of the named text token in `Theme.lua`; never lower 4.5.)

Append to `tests/test_kit.lua`:

```lua
H.test("a check box toggles on click, reports the new state and keeps its text", function()
    local _, Kit = boot()
    local seen = {}
    local check = Kit.check(nil, "Track history")
    H.eq(check.label.text, "Track history")
    H.falsy(check:GetChecked())
    H.falsy(check.mark.shown)
    check.onToggle = function(checked) seen[#seen + 1] = checked end
    check.scripts.OnClick(check)
    H.truthy(check:GetChecked())
    H.truthy(check.mark.shown)
    check.scripts.OnClick(check)
    H.falsy(check:GetChecked())
    H.eq(seen, { true, false })
    check:SetChecked(true)
    H.truthy(check:GetChecked())
    check:SetChecked(nil)
    H.falsy(check:GetChecked())
    check:setText("Cost per point")
    H.eq(check.label.text, "Cost per point")
end)

H.test("clicking a check box without a callback does not raise", function()
    local _, Kit = boot()
    local check = Kit.check(nil, "x")
    check.scripts.OnClick(check)
    H.truthy(check:GetChecked())
end)

H.test("an input box gives up its focus on Enter and Escape", function()
    local _, Kit = boot()
    local box = Kit.input(nil, 52, 4)
    local cleared = 0
    box.ClearFocus = function() cleared = cleared + 1 end
    box.scripts.OnEnterPressed(box)
    box.scripts.OnEscapePressed(box)
    H.eq(cleared, 2)
end)

H.test("a panel header can be made clickable", function()
    local _, Kit = boot()
    local panel = Kit.panel(nil, "MATERIALS")
    local clicks = 0
    local hit = panel:onHeaderClick(function() clicks = clicks + 1 end)
    H.eq(panel.headerHit, hit)
    hit.scripts.OnClick(hit)
    H.eq(clicks, 1)
end)

H.test("the new widgets survive every theme switch", function()
    local _, Kit = boot()
    local check = Kit.check(nil, "x")
    local box = Kit.input(nil, 52, 4)
    for _, name in ipairs({ "copper", "steel", "gold" }) do Kit.applyTheme(name) end
    H.truthy(check and box)
end)
```

- [ ] **Step 2: Run to see failures**

Run: `luajit tests/run.lua 2>&1 | grep FAIL | head`
Expected: failures (functions missing).

- [ ] **Step 3: Implement** — append to `CraftProfit/UI/Kit.lua`, after `Kit.tile`:

```lua
-- Check box -------------------------------------------------------------------

-- A themed check box with its label on the right. Same calls as a game check button:
-- SetChecked / GetChecked; `onToggle(checked)` runs after a click.
function Kit.check(parent, text)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(18, 18)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    Kit.rings(b, { "inputEdge" })
    b.mark = b:CreateTexture(nil, "OVERLAY")
    b.mark:SetPoint("TOPLEFT", b, "TOPLEFT", 5, -5)
    b.mark:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -5, 5)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("LEFT", b, "RIGHT", 6, 0)
    b.checked = false
    register(function()
        paintTexture(bg, "inputBg")
        paintTexture(b.mark, "checkMark")
        setTextColor(b.label, "textMain")
    end)

    b.SetChecked = function(self, value)
        self.checked = value and true or false
        self.mark:SetShown(self.checked)
    end
    b.GetChecked = function(self) return self.checked end
    b:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        if self.onToggle then self.onToggle(self.checked) end
    end)
    b.setText = function(self, value) self.label:SetText(value or "") end
    b:SetChecked(false)
    b:setText(text)
    return b
end

-- Input box ---------------------------------------------------------------------

-- A themed single-line edit box, 22 px high, text centred.
function Kit.input(parent, width, maxLetters)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(width or 52, 22)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetJustifyH("CENTER")
    box:SetTextInsets(4, 4, 0, 0)
    if maxLetters then box:SetMaxLetters(maxLetters) end
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(box)
    Kit.rings(box, { "inputEdge" })
    register(function()
        paintTexture(bg, "inputBg")
        setTextColor(box, "textMain")
    end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end
```

In `Kit.panel`, after `p.height = ...`:

```lua
    -- A button covering the header, e.g. to fold the panel. Returns it (also p.headerHit).
    function p:onHeaderClick(fn)
        local hit = CreateFrame("Button", nil, head)
        hit:SetAllPoints(head)
        hit:SetScript("OnClick", fn)
        self.headerHit = hit
        return hit
    end
```

`setTextColor(box, "textMain")` works on an EditBox (`SetTextColor` exists on edit boxes).

In `CraftProfit/UI/KitDemo.lua`, add a third panel "CONTROLS" to the demo so the widgets can be checked in game: build it after the OPTIONS panel and add it to the stack.

```lua
    local controls = Kit.panel(content, "CONTROLS")
    controls:setRows(1, 26)
    local box = Kit.input(controls.body, 52, 4)
    box:SetPoint("TOPLEFT", controls.body, "TOPLEFT", 8, -2)
    box:SetText("1")
    local checkA = Kit.check(controls.body, "Track history")
    checkA:SetPoint("TOPLEFT", controls.body, "TOPLEFT", 90, -4)
    checkA:SetChecked(true)
    local checkB = Kit.check(controls.body, "Per point")
    checkB:SetPoint("TOPLEFT", controls.body, "TOPLEFT", 230, -4)
```
and change the stack/placement code to `Kit.stack({ TILE_H, materials:height(), options:height(), controls:height() }, ...)` placing `{ materials, options, controls }` at `offsets[i + 1]`.

- [ ] **Step 4: Run the whole suite**

Run: `sh tests/check.sh 2>&1 | grep -E "passed|failed|Total|FAIL"`
Expected: `0 failed`, `0 warnings`.

- [ ] **Step 5: Commit**

```bash
git status --short
git add CraftProfit/UI/Kit.lua CraftProfit/UI/KitDemo.lua tests/test_kit.lua tests/test_theme.lua
git commit -m "feat: kit check box, input box and clickable panel header"
```

---

### Task 4: The main window on the kit

**Files:**
- Rewrite: `CraftProfit/UI/Window.lua`
- Test: `tests/test_window.lua` (new)

**Interfaces:**
- Consumes: `ns.Kit` (window, panel, button, tile, check, input, stack, panelHeight, fitSize, onTheme, rings, constants), `ns.Theme.FIXED`, the model from Task 1 (`banner`, `tiles`, `materials`, `lines`, `costLines`, `costExpanded`, `crafts`, `tracked`, `showPerPoint`, `pinned`, `title`, `ageText`, `stale`), game globals `CreateFrame`, `C_Item`, `UIParent`, `STANDARD_TEXT_FONT`.
- Produces on `ns.Window` (unchanged public interface): `create(handlers)`, `render(model)`, `showEmpty(text)`, `relayout()`, `attach(target, saved)`, `frame()`, `show()`, `hide()`, `isShown()`, `pinsHost()`, `setTitle(text)`, `WIDTH` (372), `lastModel`, `lastHandlers`. New: `Window.parts` (the widgets, for tests: `banner`, `tiles`, `likely`, `materials` (a kit panel), `rows`, `age`, `craftsBox`, `track`, `perPoint`, `perPointValue`, `pin`, `empty`, `frames` by section key), `Window.sections(opts) -> list of { key, height }`, `Window.contentHeightOf(list) -> number`.
- Handlers the window calls (as today): `onPinClick()`, `onReagentClick(itemID, qty)`, `onCraftsChange(text)`, `onTrackToggle(checked)`, `onPerPointToggle(checked)`, `onCostToggle(isExpanded)`, `onMoved(point, x, y)`; each looked up when it is needed.

- [ ] **Step 1: Write the failing tests** — create `tests/test_window.lua`:

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
    for _, name in ipairs({ "onPinClick", "onReagentClick", "onCraftsChange", "onTrackToggle",
        "onPerPointToggle", "onCostToggle", "onMoved" }) do
        T.ns.Window.lastHandlers[name] = function(...) calls[#calls + 1] = { name, ... } end
    end
    return T, T.ns.Window, calls
end

local function model(over)
    local m = {
        title = "Bronze Sword", crafts = 1, costExpanded = true, showPerPoint = false,
        pinned = false, tracked = false, ageText = "Prices: 5m ago", stale = false,
        verdict = { kind = "profit", text = "Best: Auction house", value = "+7s" },
        banner = { label = "RESULT", text = "Best: Auction house", value = "+7s", kind = "profit" },
        tiles = {
            { key = "ah", label = "AH (NET)", value = "9s 50c", best = true, muted = false },
            { key = "vendor", label = "VENDOR", value = "2s", best = false, muted = false },
            { key = "disenchant", label = "DISENCH.", value = "3s 80c", best = false, muted = false, tag = "beta" },
        },
        materials = { title = "MATERIALS", total = "2s 50c" },
        lines = { { label = "Materials", value = "2s 50c", key = "cost", best = false } },
        costLines = {
            { itemID = 11, qty = 3, unitText = "50c", subtotalText = "1s 50c" },
            { itemID = 12, qty = 1, unitText = "1s", subtotalText = "1s" },
        },
    }
    for k, v in pairs(over or {}) do m[k] = v end
    return m
end

H.test("the window is created hidden although real frames start shown", function()
    local _, Window = boot()
    H.falsy(Window.isShown())
end)

H.test("render shows the title, the banner and the three tiles", function()
    local _, Window = boot()
    Window.render(model())
    local p = Window.parts
    H.eq(Window.frame().titleText.text, "Bronze Sword")
    H.eq(p.banner.label.text, "RESULT")
    H.eq(p.banner.text.text, "Best: Auction house")
    H.eq(p.banner.value.text, "+7s")
    H.eq(p.tiles[1].value.text, "9s 50c")
    H.truthy(p.tiles[1].best)
    H.falsy(p.tiles[2].best)
    H.truthy(p.tiles[3].label.text:find("beta", 1, true))
end)

H.test("the banner tint follows the kind of result and not the theme", function()
    local T, Window = boot()
    local Theme = T.ns.Theme
    Window.render(model({ banner = { label = "RESULT", text = "Best: Auction house", value = "-2s", kind = "loss" } }))
    local b = Window.parts.banner
    H.eq({ b.edge[1], b.edge[2], b.edge[3] }, { Theme.FIXED.loss[1], Theme.FIXED.loss[2], Theme.FIXED.loss[3] })
    T.ns.Kit.applyTheme("steel")
    H.eq({ b.edge[1], b.edge[2], b.edge[3] }, { Theme.FIXED.loss[1], Theme.FIXED.loss[2], Theme.FIXED.loss[3] })
end)

H.test("an unfolded materials panel lists one row per cost line and hides the rest", function()
    local _, Window = boot()
    Window.render(model())
    local p = Window.parts
    H.eq(p.materials.title.text, "- MATERIALS")
    H.eq(p.materials.right.text, "2s 50c")
    H.eq(p.rows[1].name.text, "3x #11")
    H.eq(p.rows[1].value.text, "1s 50c")
    H.eq(p.rows[2].name.text, "1x #12")
    H.truthy(p.rows[1].hit.shown)
    H.truthy(p.rows[2].hit.shown)
    H.falsy(p.rows[3].hit.shown)
    H.truthy(p.materials.body.shown)
end)

H.test("a folded materials panel shows only its header", function()
    local T, Window = boot()
    Window.render(model({ costExpanded = false }))
    local p = Window.parts
    H.eq(p.materials.title.text, "+ MATERIALS")
    H.falsy(p.materials.body.shown)
    H.eq(p.frames.materials.height, T.ns.Kit.FOLDED_H)
    for i = 1, 12 do H.falsy(p.rows[i].hit.shown) end
end)

H.test("clicking the materials header asks to fold or unfold, clicking a reagent row asks for its search", function()
    local _, Window, calls = boot()
    Window.render(model())
    Window.parts.materials.headerHit.scripts.OnClick()
    H.eq(calls[1], { "onCostToggle", false })
    Window.render(model({ costExpanded = false }))
    Window.parts.materials.headerHit.scripts.OnClick()
    H.eq(calls[2], { "onCostToggle", true })
    Window.render(model())
    Window.parts.rows[1].hit.scripts.OnClick()
    H.eq(calls[3], { "onReagentClick", 11, 3 })
end)

H.test("the crafts box shows the count, is never rewritten while focused and reports on focus loss", function()
    local _, Window, calls = boot()
    Window.render(model({ crafts = 5 }))
    local box = Window.parts.craftsBox
    H.eq(box.text, "5")
    box.HasFocus = function() return true end
    Window.render(model({ crafts = 7 }))
    H.eq(box.text, "5")
    box.scripts.OnEditFocusLost(box)
    H.eq(calls[#calls], { "onCraftsChange", "5" })
end)

H.test("the track and per-point check boxes show the model and report clicks", function()
    local _, Window, calls = boot()
    Window.render(model({ tracked = true, showPerPoint = false }))
    local p = Window.parts
    H.truthy(p.track:GetChecked())
    H.falsy(p.perPoint:GetChecked())
    p.track.scripts.OnClick(p.track)
    H.eq(calls[#calls], { "onTrackToggle", false })
    p.perPoint.scripts.OnClick(p.perPoint)
    H.eq(calls[#calls], { "onPerPointToggle", true })
end)

H.test("the per-point value follows the model line: hidden, a cost, or a gain with a plus", function()
    local T, Window = boot()
    local Theme = T.ns.Theme
    local p = Window.parts
    Window.render(model())
    H.falsy(p.perPointValue.shown)
    local colour
    p.perPointValue.SetTextColor = function(_, r, g, b) colour = { r, g, b } end
    Window.render(model({ showPerPoint = true, lines = { { label = "Cost per point", value = "12s (25%, estimate)", key = "perpoint", tone = "loss" } } }))
    H.truthy(p.perPointValue.shown)
    H.eq(p.perPointValue.text, "12s (25%, estimate)")
    H.eq(colour, { Theme.FIXED.loss[1], Theme.FIXED.loss[2], Theme.FIXED.loss[3] })
    Window.render(model({ showPerPoint = true, lines = { { label = "Gain per point", value = "9s (75%, estimate)", key = "perpoint", tone = "profit" } } }))
    H.eq(p.perPointValue.text, "+9s (75%, estimate)")
    H.eq(colour, { Theme.FIXED.profit[1], Theme.FIXED.profit[2], Theme.FIXED.profit[3] })
end)

H.test("the pin button reads Pin or Unpin and reports its click", function()
    local _, Window, calls = boot()
    Window.render(model({ pinned = false }))
    H.eq(Window.parts.pin.label.text, "Pin")
    Window.render(model({ pinned = true }))
    H.eq(Window.parts.pin.label.text, "Unpin")
    Window.parts.pin.scripts.OnClick(Window.parts.pin)
    H.eq(calls[#calls], { "onPinClick" })
end)

H.test("the likely-outcome line appears only when the model has one", function()
    local _, Window = boot()
    local p = Window.parts
    Window.render(model())
    H.falsy(p.frames.likely.shown)
    local lines = { { label = "Materials", value = "2s 50c", key = "cost", best = false },
        { label = "75%: 1-2x Dust = 5s", value = "", key = "likely", best = false, muted = true } }
    Window.render(model({ lines = lines }))
    H.truthy(p.frames.likely.shown)
    H.eq(p.likely.text, "75%: 1-2x Dust = 5s")
end)

H.test("sections lists the visible blocks top to bottom with their heights", function()
    local T, Window = boot()
    local Kit = T.ns.Kit
    local function keys(list) local k = {} for i, s in ipairs(list) do k[i] = s.key end return k end
    local list = Window.sections({ hasLikely = false, expanded = true, reagents = 2 })
    H.eq(keys(list), { "banner", "tiles", "materials", "age", "options" })
    H.eq(list[3].height, Kit.panelHeight(2, 18))
    H.eq(list[5].height, Kit.panelHeight(3, 26))
    H.eq(keys(Window.sections({ hasLikely = true, expanded = true, reagents = 0 })),
        { "banner", "tiles", "likely", "materials", "age", "options" })
    H.eq(Window.sections({ hasLikely = false, expanded = false, reagents = 9 })[3].height, Kit.FOLDED_H)
end)

H.test("the frame height is the sum of the visible sections plus the insets, and the pinned list adds its own", function()
    local T, Window = boot()
    local Kit = T.ns.Kit
    Window.render(model())
    local list = Window.sections({ hasLikely = false, expanded = true, reagents = 2 })
    local _, total = Kit.stack((function() local h = {} for i, s in ipairs(list) do h[i] = s.height end return h end)(), Kit.GAP, 0)
    local expected = total + Kit.CONTENT_TOP + Kit.CONTENT_BOTTOM
    H.eq(Window.contentHeightOf(list), expected)
    H.eq(Window.frame().height, expected)
    Window.pinsHost():Show()
    Window.pinsHost():SetHeight(100)
    Window.relayout()
    H.eq(Window.frame().height, expected + 100)
end)

H.test("an empty window shows the message and hides every section", function()
    local T, Window = boot()
    local Kit = T.ns.Kit
    Window.render(model())
    Window.showEmpty("Select a recipe")
    local p = Window.parts
    H.eq(p.empty.text, "Select a recipe")
    H.truthy(p.empty.shown)
    for key, f in pairs(p.frames) do
        if f.shown then error("section still shown: " .. key) end
    end
    H.eq(Window.frame().titleText.text, "CraftProfit")
    H.eq(Window.frame().height, Kit.CONTENT_TOP + 24 + Kit.CONTENT_BOTTOM)
    H.eq(Window.lastModel, nil)
end)

H.test("dropping the window reports its position", function()
    local _, Window, calls = boot()
    Window.frame().scripts.OnDragStop(Window.frame())
    H.eq(calls[#calls], { "onMoved", "TOPLEFT", 100, 700 })
end)

H.test("switching theme after a render repaints without error", function()
    local T, Window = boot()
    Window.render(model({ showPerPoint = true, lines = { { label = "Cost per point", value = "1s", key = "perpoint", tone = "loss" } } }))
    for _, name in ipairs({ "copper", "steel", "gold" }) do T.ns.Kit.applyTheme(name) end
    H.truthy(Window.frame())
end)
```

Notes for the implementer: `Window.parts.banner.edge` is the colour table the banner's rings read (see the code below); `p.empty` is the empty-state FontString. If a fake-frame method used by a test is missing (the fake records `text`, `shown`, `height`, `scripts`; everything else is a no-op), stub it on that object inside the test, as the Kit tests do; do not edit `tests/fakewow.lua`.

- [ ] **Step 2: Run to see failures**

Run: `luajit tests/run.lua 2>&1 | grep FAIL | head -5`
Expected: failures (`Window.parts` is nil, etc.).

- [ ] **Step 3: Rewrite `CraftProfit/UI/Window.lua`**

```lua
-- The main window, built on the shared UI kit (UI/Kit.lua): a result banner, three
-- tiles for the ways to sell the item, a Materials panel and an Options panel; at the
-- auction house the pinned list (UI/PinsUI.lua) hangs below. Parented to UIParent
-- (never to a Blizzard frame, to avoid taint); anchored beside the profession or AH
-- window until the user drags it, after which the saved position wins.
local _, ns = ...
local L = ns.L
local Kit, Theme = ns.Kit, ns.Theme

local Window = {}
ns.Window = Window

local WIDTH = 372
local ROW_H = 18
local BANNER_H = 52
local TILE_H = 52
local LIKELY_H = 16
local AGE_H = 14
local OPTION_ROWS = 3
local OPTION_ROW_H = 26
local EMPTY_H = 24
local MAX_DETAIL = 12 -- Recipes.MAX_REAGENTS
local BANNER_SIZES = { 22, 19, 16, 13 }
local BANNER_VALUE_ROOM = 120
local BANNER_FILL, BANNER_EDGE = 0.09, 0.45

local TONES = {
    profit = Theme.FIXED.profit,
    loss = Theme.FIXED.loss,
    incomplete = Theme.FIXED.incomplete,
    none = Theme.FIXED.trivial,
}

local frame, content, pinsHost
local handlers = {}
local expanded = true
local contentHeight = 80
-- The widgets, exposed for tests: `frames` maps a section key to its frame.
local parts = { frames = {}, tiles = {}, rows = {} }

Window.WIDTH = WIDTH
Window.parts = parts
Window.lastModel = nil
Window.lastHandlers = nil

-- Blocks of the recipe view, top to bottom, with their heights. Pure.
-- opts: hasLikely (a "likely outcome" line), expanded (Materials unfolded), reagents.
function Window.sections(opts)
    local list = { { key = "banner", height = BANNER_H }, { key = "tiles", height = TILE_H } }
    if opts.hasLikely then list[#list + 1] = { key = "likely", height = LIKELY_H } end
    list[#list + 1] = {
        key = "materials",
        height = opts.expanded and Kit.panelHeight(opts.reagents, ROW_H) or Kit.FOLDED_H,
    }
    list[#list + 1] = { key = "age", height = AGE_H }
    list[#list + 1] = { key = "options", height = Kit.panelHeight(OPTION_ROWS, OPTION_ROW_H) }
    return list
end

local function heightsOf(list)
    local heights = {}
    for i, section in ipairs(list) do heights[i] = section.height end
    return heights
end

-- Window height needed for these sections (without the pinned list).
function Window.contentHeightOf(list)
    local _, total = Kit.stack(heightsOf(list), Kit.GAP, 0)
    return total + Kit.CONTENT_TOP + Kit.CONTENT_BOTTOM
end

local function themed(fontString, token)
    Kit.onTheme(function(t)
        local c = t[token]
        fontString:SetTextColor(c[1], c[2], c[3], c[4])
    end)
end

-- Item name for the fold-out; "#id" while the game has not loaded it (or when
-- the name is a secret value, which raises when concatenated).
local function reagentName(itemID)
    local ok, name = pcall(C_Item.GetItemInfo, itemID)
    if ok and type(name) == "string" then
        local fine, text = pcall(function() return name .. "" end)
        if fine then return text end
    end
    return "#" .. itemID
end

local function findLine(lines, key)
    for _, line in ipairs(lines or {}) do
        if line.key == key then return line end
    end
    return nil
end

local function newSection(key, height)
    local f = CreateFrame("Frame", nil, content)
    f:SetHeight(height)
    parts.frames[key] = f
    return f
end

-- Banner: the label, the best way to sell and the net result in large type; its tint
-- follows the kind of result (gain, loss, incomplete) and not the theme.
local function buildBanner()
    local f = newSection("banner", BANNER_H)
    local fill = { 0, 0, 0, 0 }
    local edge = { 0, 0, 0, 0 }
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    local function paintFill() bg:SetColorTexture(fill[1], fill[2], fill[3], fill[4]) end
    paintFill()
    local refreshEdge = Kit.rings(f, { function() return edge end })

    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    themed(label, "headText")
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
    text:SetWidth(WIDTH - Kit.CONTENT_SIDE * 2 - 24 - BANNER_VALUE_ROOM - 8)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    local best = Theme.FIXED.best
    text:SetTextColor(best[1], best[2], best[3], best[4])
    local value = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    value:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    value:SetJustifyH("RIGHT")
    parts.banner = {
        label = label, text = text, value = value,
        fill = fill, edge = edge, paintFill = paintFill, refreshEdge = refreshEdge,
    }
end

local function setBanner(spec)
    local b = parts.banner
    local tone = TONES[spec.kind] or TONES.none
    b.label:SetText(spec.label or "")
    b.text:SetText(spec.text or "")
    b.value:SetFont(STANDARD_TEXT_FONT, BANNER_SIZES[1], "")
    b.value:SetText(spec.value or "")
    local size = Kit.fitSize(b.value:GetStringWidth(), BANNER_SIZES[1], BANNER_VALUE_ROOM, BANNER_SIZES)
    if size ~= BANNER_SIZES[1] then b.value:SetFont(STANDARD_TEXT_FONT, size, "") end
    b.value:SetTextColor(tone[1], tone[2], tone[3], tone[4])
    b.fill[1], b.fill[2], b.fill[3], b.fill[4] = tone[1], tone[2], tone[3], BANNER_FILL
    b.edge[1], b.edge[2], b.edge[3], b.edge[4] = tone[1], tone[2], tone[3], BANNER_EDGE
    b.paintFill()
    b.refreshEdge()
end

local function buildTiles()
    local f = newSection("tiles", TILE_H)
    local width = math.floor((WIDTH - Kit.CONTENT_SIDE * 2 - Kit.GAP * 2) / 3)
    for i = 1, 3 do
        local tile = Kit.tile(f, width, TILE_H)
        tile.frame:SetPoint("TOPLEFT", f, "TOPLEFT", (i - 1) * (width + Kit.GAP), 0)
        parts.tiles[i] = tile
    end
end

-- One grey line under the tiles: the most probable disenchant outcome.
local function buildLikely()
    local f = newSection("likely", LIKELY_H)
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", f, "LEFT", 4, 0)
    text:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    themed(text, "textMuted")
    parts.likely = text
end

-- Materials: the header folds the detail; each row searches its reagent at the AH.
local function buildMaterials()
    local panel = Kit.panel(content, "")
    parts.frames.materials = panel.frame
    parts.materials = panel
    panel:onHeaderClick(function()
        if handlers.onCostToggle then handlers.onCostToggle(not expanded) end
    end)
    for i = 1, MAX_DETAIL do
        local y = -(i - 1) * ROW_H
        local hit = CreateFrame("Button", nil, panel.body)
        hit:SetHeight(ROW_H)
        hit:SetPoint("TOPLEFT", panel.body, "TOPLEFT", 0, y)
        hit:SetPoint("TOPRIGHT", panel.body, "TOPRIGHT", 0, y)
        local hover = hit:CreateTexture(nil, "BACKGROUND")
        hover:SetAllPoints(hit)
        Kit.onTheme(function(t)
            local c = t.rowHover
            hover:SetColorTexture(c[1], c[2], c[3], c[4])
        end)
        hover:Hide()
        hit:HookScript("OnEnter", function() hover:Show() end)
        hit:HookScript("OnLeave", function() hover:Hide() end)
        local name = hit:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        name:SetPoint("LEFT", hit, "LEFT", 8, 0)
        name:SetPoint("RIGHT", hit, "RIGHT", -80, 0)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        themed(name, "textMain")
        local value = hit:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        value:SetPoint("RIGHT", hit, "RIGHT", -8, 0)
        value:SetJustifyH("RIGHT")
        themed(value, "textMuted")
        local row = { hit = hit, name = name, value = value }
        hit:SetScript("OnClick", function()
            if row.itemID and handlers.onReagentClick then handlers.onReagentClick(row.itemID, row.qty) end
        end)
        parts.rows[i] = row
    end
end

local function buildAge()
    local f = newSection("age", AGE_H)
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    text:SetPoint("LEFT", f, "LEFT", 4, 0)
    parts.age = text
    parts.ageStale = false
    parts.paintAge = function()
        local c = parts.ageStale and Theme.FIXED.stale or Kit.current.textMuted
        text:SetTextColor(c[1], c[2], c[3], c[4])
    end
    Kit.onTheme(function() parts.paintAge() end)
end

-- Options: the crafts multiplier, history tracking, the cost-per-point option and the
-- pin button.
local function buildOptions()
    local panel = Kit.panel(content, L.PANEL_OPTIONS)
    parts.frames.options = panel.frame
    parts.options = panel
    local body = panel.body

    parts.craftsLabel = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    parts.craftsLabel:SetPoint("TOPLEFT", body, "TOPLEFT", 8, -6)
    themed(parts.craftsLabel, "textMain")
    local box = Kit.input(body, 52, 4)
    box:SetNumeric(true)
    box:SetPoint("TOPLEFT", body, "TOPLEFT", 70, -2)
    -- Applied when the box loses focus (Enter, Escape or a click elsewhere).
    box:SetScript("OnEditFocusLost", function(self)
        if handlers.onCraftsChange then handlers.onCraftsChange(self:GetText()) end
    end)
    parts.craftsBox = box

    local track = Kit.check(body, "")
    track:SetPoint("TOPLEFT", body, "TOPLEFT", 160, -4)
    track.onToggle = function(checked)
        if handlers.onTrackToggle then handlers.onTrackToggle(checked) end
    end
    parts.track = track

    local perPoint = Kit.check(body, "")
    perPoint:SetPoint("TOPLEFT", body, "TOPLEFT", 8, -OPTION_ROW_H - 4)
    perPoint.onToggle = function(checked)
        if handlers.onPerPointToggle then handlers.onPerPointToggle(checked) end
    end
    parts.perPoint = perPoint
    parts.perPointValue = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    parts.perPointValue:SetPoint("TOPRIGHT", body, "TOPRIGHT", -8, -OPTION_ROW_H - 7)
    parts.perPointValue:SetJustifyH("RIGHT")

    local pin = Kit.button(body, "normal", "")
    pin:SetWidth(120)
    pin:SetPoint("TOPLEFT", body, "TOPLEFT", 8, -OPTION_ROW_H * 2 - 2)
    pin:SetScript("OnClick", function()
        if handlers.onPinClick then handlers.onPinClick() end
    end)
    parts.pin = pin
end

function Window.create(h)
    if frame then return frame end
    handlers = h or {}
    Window.lastHandlers = handlers

    frame = Kit.window("CraftProfitWindow", L.TITLE, {
        width = WIDTH,
        onMoved = function(point, x, y)
            if handlers.onMoved then handlers.onMoved(point, x, y) end
        end,
    })
    content = frame.content
    buildBanner()
    buildTiles()
    buildLikely()
    buildMaterials()
    buildAge()
    buildOptions()

    parts.empty = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    parts.empty:SetPoint("TOP", content, "TOP", 0, -4)

    pinsHost = CreateFrame("Frame", nil, frame)
    pinsHost:SetWidth(WIDTH)
    pinsHost:SetHeight(0)
    pinsHost:Hide()

    -- A new frame starts shown: the controller decides when the window appears.
    frame:Hide()
    return frame
end

function Window.setTitle(text)
    if frame then frame:setTitle(text) end
end

-- Frame height = recipe sections + pinned-recipes section (when shown).
function Window.relayout()
    if not frame then return end
    pinsHost:ClearAllPoints()
    pinsHost:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -contentHeight)
    local extra = pinsHost:IsShown() and pinsHost:GetHeight() or 0
    frame:SetHeight(contentHeight + extra)
end

local function hideSections()
    for _, f in pairs(parts.frames) do f:Hide() end
end

function Window.showEmpty(text)
    if not frame then return end
    Window.lastModel = nil
    frame:setTitle(L.TITLE)
    hideSections()
    parts.empty:SetText(text)
    parts.empty:Show()
    contentHeight = Kit.CONTENT_TOP + EMPTY_H + Kit.CONTENT_BOTTOM
    Window.relayout()
end

-- Stacks the sections of `list` under each other and sizes the frame.
local function layout(list)
    hideSections()
    local offsets = Kit.stack(heightsOf(list), Kit.GAP, 0)
    for i, section in ipairs(list) do
        local f = parts.frames[section.key]
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", content, "TOPLEFT", 0, offsets[i])
        f:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, offsets[i])
        f:SetHeight(section.height)
        f:Show()
    end
    contentHeight = Window.contentHeightOf(list)
    Window.relayout()
end

local function setPerPoint(line)
    local value = parts.perPointValue
    if not line then
        value:Hide()
        return
    end
    local c = line.tone == "profit" and Theme.FIXED.profit or line.tone == "loss" and Theme.FIXED.loss
        or Kit.current.textMain
    value:SetText((line.tone == "profit" and "+" or "") .. line.value)
    value:SetTextColor(c[1], c[2], c[3], c[4])
    value:Show()
end

function Window.render(model)
    if not frame then return end
    Window.lastModel = model
    local costLines = model.costLines or {}
    expanded = model.costExpanded ~= false
    frame:setTitle(model.title or L.TITLE)
    parts.empty:Hide()

    setBanner(model.banner or { kind = "none", text = "", value = "" })
    for i, tile in ipairs(parts.tiles) do tile:set((model.tiles or {})[i] or {}) end

    local likely = findLine(model.lines, "likely")
    parts.likely:SetText(likely and likely.label or "")

    local materials = model.materials or { title = L.PANEL_MATERIALS, total = "" }
    parts.materials:setTitle((expanded and "- " or "+ ") .. materials.title)
    parts.materials.right:SetText(materials.total)
    parts.materials.body:SetShown(expanded)
    for i = 1, MAX_DETAIL do
        local row, cost = parts.rows[i], expanded and costLines[i] or nil
        if cost then
            row.itemID, row.qty = cost.itemID, cost.qty
            row.name:SetText(cost.qty .. "x " .. reagentName(cost.itemID))
            row.value:SetText(cost.subtotalText)
            row.hit:Show()
        else
            row.itemID = nil
            row.hit:Hide()
        end
    end

    parts.age:SetText(model.ageText or "")
    parts.ageStale = model.stale and true or false
    parts.paintAge()

    parts.craftsLabel:SetText(L.CRAFTS_LABEL)
    -- Never rewrite the box while the player is typing in it.
    if not parts.craftsBox:HasFocus() then parts.craftsBox:SetText(tostring(model.crafts or 1)) end
    parts.track:setText(L.TRACK_LABEL)
    parts.track:SetChecked(model.tracked)
    parts.perPoint:setText(L.OPT_PER_POINT)
    parts.perPoint:SetChecked(model.showPerPoint)
    setPerPoint(findLine(model.lines, "perpoint"))
    parts.pin:setText(model.pinned and L.UNPIN or L.PIN)

    layout(Window.sections({
        hasLikely = likely ~= nil,
        expanded = expanded,
        reagents = math.min(#costLines, MAX_DETAIL),
    }))
end

-- Position: the saved one if there is one, else beside the target window.
function Window.attach(target, saved)
    if not frame then return end
    frame:ClearAllPoints()
    if saved then
        if saved.point == "TOPLEFT" then
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.x, saved.y)
        else
            frame:SetPoint(saved.point, UIParent, saved.point, saved.x, saved.y)
        end
    elseif target then
        frame:SetPoint("TOPLEFT", target, "TOPRIGHT", 6, 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
    end
end

function Window.frame() return frame end
function Window.show() if frame then frame:Show() end end
function Window.hide() if frame then frame:Hide() end end
function Window.isShown() return frame ~= nil and frame:IsShown() == true end
function Window.pinsHost() return pinsHost end
```

Details to respect: the likely-line section is hidden (not just empty) when the model has no `likely` entry (the layout only shows sections returned by `Window.sections`); `Window.parts.craftsBox` is the `Kit.input`; `STANDARD_TEXT_FONT` is already declared for luacheck.

- [ ] **Step 4: Run the whole suite**

Run: `sh tests/check.sh 2>&1 | grep -E "passed|failed|Total|FAIL"`
Expected: `0 failed`, `0 warnings`. If an existing test in `tests/test_boot.lua` or `tests/test_pinsui.lua` fails, read it: those tests use `Window.lastModel`, `Window.lastHandlers`, `Window.isShown`, `Window.pinsHost`; fix the window, not the test, unless the test asserts a removed internal.

- [ ] **Step 5: Commit**

```bash
git status --short
git add CraftProfit/UI/Window.lua tests/test_window.lua
git commit -m "feat: main window rebuilt on the UI kit (result banner, tiles, materials and options panels)"
```

---

### Task 5: Docs, spec amendments, user guide

**Files:**
- Modify: `docs/technical.md`, `docs/in-game-checklist.md`, `docs/user-guide.md`, `docs/user-guide.fr.md`, `CHANGELOG.md`, `docs/superpowers/specs/2026-10-09-ui-rework-design.md`

- [ ] **Step 1: Docs.**
  - `docs/technical.md`: the `UI/Window.lua` row now says "The main window, on the UI kit"; in *Rendering* add that `Present.build` also returns `banner`, `tiles` and `materials`, and that the window reads `lines` only for the `likely` and `perpoint` entries; list the new kit widgets (`check`, `input`, `panel:onHeaderClick`, `onTheme`, `mix`, `colorEscape`, `plaqueWidth`).
  - `docs/user-guide.md` and `docs/user-guide.fr.md`, section *The window* / *La fenêtre*: replace the line table by the new layout: the **Result** banner (best way to sell and the net result, green for a gain, red for a loss, amber when incomplete); the three **tiles** (auction house net, vendor, disenchant beta; the best one outlined in gold; `n/a` or `?` when not possible or unknown); the grey line under the tiles (most probable disenchant outcome); the **Materials** panel (click the header to fold, click a reagent to search it); the prices age line (orange when old); the **Options** panel (Crafts, Track history, Cost per skill point with its value on the right, Pin/Unpin). Keep the other sections; fix any sentence that mentions the removed lines (for example "gold `>` in front of its line", "Best: ..." line) so they describe the banner and tiles instead. The French text must read naturally (this is the player-facing guide).
  - `docs/in-game-checklist.md`: add a section "Main window (PR 2)": recipe selected shows banner, three tiles and the panels; gain and loss tint the banner green and red; `999g 99s 99c` and a very long recipe name fit; folding and unfolding Materials via the header (and the `+`/`-` marker); clicking a reagent starts the AH search with the quantity; the crafts box applies on Enter/Escape/click away and is not overwritten while typing; Track history and Cost per skill point check boxes work and persist; the per-point value shows beside its box (red cost, green gain with `+`); Pin/Unpin; the window moves by its body and by the title plaque and its position is saved; the leveling window still opens beside it; at the auction house the pinned list appears below (still in the old style until PR 3); the window closes with the profession or auction house window; `/cp kitdemo` check box and input box look right; French client: accents in the tile and panel titles.
  - `CHANGELOG.md`, *Unreleased*: **Changed**: "The main window has a new look: a result banner with the best way to sell and the net result, three tiles for the auction house, vendor and disenchant values, and separate Materials and Options panels. Behaviour is unchanged." Mention that the pinned list and the leveling window follow in the next versions.
  - Spec: in *Changed files* note that `lines` and `verdict` are kept in the model and `banner`, `tiles`, `materials` are added (amendment 1), the `rowHover` token, `Kit.check`/`Kit.input`/`panel:onHeaderClick` now exist (signatures from `Kit.lua`), and in *Delivery* mark PR 2 as the main window with these items; fix the Kit bullet signatures (`check(parent, text)`, `input(parent, width, maxLetters)`).

- [ ] **Step 2: Run everything and verify authorship**

Run: `sh tests/check.sh 2>&1 | grep -E "passed|failed|Total"; echo "coauthor: $(git log --format=%B main..HEAD | grep -ci co-authored)"`
Expected: `0 failed`, `0 warnings`, `coauthor: 0`.

- [ ] **Step 3: Commit** (do NOT push, do NOT open a PR: the controller does)

```bash
git status --short
git add docs CHANGELOG.md
git commit -m "docs: main window on the UI kit (guide, checklist, technical notes, spec)"
```
