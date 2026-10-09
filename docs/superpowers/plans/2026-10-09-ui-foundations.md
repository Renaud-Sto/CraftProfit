# UI foundations (PR 1 of 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the theme data, the shared widget kit, a developer demo window and a client probe, so the next PRs can rebuild the real windows on them. No existing window changes.

**Architecture:** `Theme.lua` is pure data (tokens per theme, validation, fixed colours). `UI/Kit.lua` holds pure layout helpers (panel height, stacking, font fitting, gradient with fallbacks) and the widgets (window, panel, button, tile) which colour themselves from `Kit.current` and re-colour on `Kit.applyTheme`. `UI/KitDemo.lua` (`/cp kitdemo [theme]`) shows the kit in game. `/cpp skin` in the probe reports what the client supports.

**Tech Stack:** Lua 5.1 (WoW client), LuaJIT test harness (`tests/harness.lua`, `tests/fakewow.lua`), luacheck.

**Spec:** `docs/superpowers/specs/2026-10-09-ui-rework-design.md`

## Plan amendments to the spec

Decided while planning, to be mirrored in the spec by Task 6:

- A token `frameShade` is added (the dark ring inside the chiselled frame).
- Large amounts are fitted with `FontString:SetFont(STANDARD_TEXT_FONT, size, "")` and a pure size-picking rule; no `CreateFont` objects.
- `Kit.check` and `Kit.input` are built in PR 2, when the main window first needs them. This PR builds `window`, `panel`, `button`, `tile`.
- `/cp kitdemo [theme]` is a developer command (not in the help text): it is how this PR is checked in game, since no real window changes.
- The `theme` setting is added to `DB` here (sanitised) but nothing reads it until PR 4.

## Global Constraints

- Interface 16001, Lua 5.1: no `goto`, `require`, `io`, `loadfile`, `dofile`, `setfenv`, `getfenv` in addon files (enforced by `tests/test_toc.lua`).
- No literal zero divisor anywhere (enforced by `tests/test_source.lua`; the game raises "Division by zero").
- Every game global the addon reads is declared in `.luacheckrc`; `sh tests/check.sh` must end with 0 failures and 0 warnings.
- Every file listed in `CraftProfit.toc` exactly once, in load order; no file on disk unlisted.
- English only for code comments and docs (except `README.fr.md`, `docs/user-guide.fr.md`).
- Never mention a co-author in commits, pushes or PR bodies. Verify with `git log --format=%B | grep -ci co-authored` (must print 0).
- Branch `feat/ui-foundations`, one PR, merged only when the author says so.
- gh must be logged in as **Renaud-Sto**.

## Review Focus

- A theme with a missing or out-of-range token must be rejected by `Theme.validate`, and a bad saved `theme` setting (nil, number, unknown name) must become `gold` without error.
- Fixed colours (gain green, loss red, difficulty colours) and every text token must stay readable on `panelBg` in all three themes (contrast ratio at least 4.5, asserted by test).
- `Kit.applyTheme` called repeatedly, with unknown names and while windows exist, never raises.
- `Kit.gradient` must work on a client with either gradient signature, or neither (flat fallback), and never raise.
- A value string wider than its tile must pick a smaller font size, and an unmeasurable width (nil) must not raise.

## File Structure

| File | Responsibility |
| --- | --- |
| `CraftProfit/Theme.lua` (new) | Tokens, three themes, fixed colours, `get`/`exists`/`list`/`validate` |
| `CraftProfit/UI/Kit.lua` (new) | Pure helpers + widgets, theme registry |
| `CraftProfit/UI/KitDemo.lua` (new) | `/cp kitdemo` window |
| `CraftProfit/DB.lua` | `theme` setting default and sanitising |
| `CraftProfit/Boot.lua` | `kitdemo` slash branch |
| `CraftProfit/CraftProfit.toc` | three new files |
| `.luacheckrc` | `STANDARD_TEXT_FONT`, `CreateColor` |
| `probe/CraftProfitProbe/Probe.lua` | `/cpp skin` |
| `tests/test_theme.lua`, `tests/test_kit.lua` (new), `tests/test_db.lua` | tests |
| `docs/technical.md`, `docs/in-game-checklist.md`, `CHANGELOG.md`, spec | docs |

---

### Task 1: Theme data

**Files:**
- Create: `CraftProfit/Theme.lua`
- Modify: `CraftProfit/CraftProfit.toc` (add `Theme.lua` after `Format.lua`)
- Test: `tests/test_theme.lua`

**Interfaces:**
- Produces: `ns.Theme` with `DEFAULT = "gold"`, `ORDER = {"gold","copper","steel"}`, `TOKENS` (ordered list of token names), `FIXED` (table of `{r,g,b,a}`), `exists(name) -> bool`, `get(name) -> theme table` (falls back to the default), `list() -> {names}`, `validate(theme) -> ok, reason`. A theme is a table whose token values are `{r,g,b,a}` arrays in 0..1 and which also has `name`.

- [ ] **Step 1: Write the failing test** (`tests/test_theme.lua`)

```lua
local H = ...

local function load()
    return H.newNS("Theme").Theme
end

local function lin(c)
    if c <= 0.03928 then return c / 12.92 end
    return ((c + 0.055) / 1.055) ^ 2.4
end

local function luminance(c)
    return 0.2126 * lin(c[1]) + 0.7152 * lin(c[2]) + 0.0722 * lin(c[3])
end

local function contrast(a, b)
    local la, lb = luminance(a), luminance(b)
    if la < lb then la, lb = lb, la end
    return (la + 0.05) / (lb + 0.05)
end

H.test("the three themes exist, gold first and default", function()
    local Theme = load()
    H.eq(Theme.list(), { "gold", "copper", "steel" })
    H.eq(Theme.DEFAULT, "gold")
    for _, name in ipairs(Theme.list()) do H.truthy(Theme.exists(name)) end
    H.falsy(Theme.exists("nope"))
    H.falsy(Theme.exists(5))
end)

H.test("get falls back to the default theme for anything unknown", function()
    local Theme = load()
    H.eq(Theme.get("copper").name, "copper")
    H.eq(Theme.get("nope").name, "gold")
    H.eq(Theme.get(nil).name, "gold")
    H.eq(Theme.get(12).name, "gold")
end)

H.test("every theme has every token as four numbers in 0..1", function()
    local Theme = load()
    for _, name in ipairs(Theme.list()) do
        local ok, reason = Theme.validate(Theme.get(name))
        if not ok then error(name .. ": " .. tostring(reason)) end
    end
end)

H.test("validate rejects a missing token, a short colour, a value out of range and NaN", function()
    local Theme = load()
    local function copy()
        local t = {}
        for k, v in pairs(Theme.get("gold")) do t[k] = v end
        return t
    end
    local t = copy()
    t.panelBg = nil
    H.falsy((Theme.validate(t)))
    t = copy()
    t.panelBg = { 0, 0, 0 }
    H.falsy((Theme.validate(t)))
    t = copy()
    t.panelBg = { 0, 0, 2, 1 }
    H.falsy((Theme.validate(t)))
    t = copy()
    t.panelBg = { 0, 0, 0, 1 }
    t.panelBg[2] = math.huge - math.huge
    H.falsy((Theme.validate(t)))
    H.falsy((Theme.validate("x")))
    H.falsy((Theme.validate(nil)))
end)

H.test("the themes differ from each other", function()
    local Theme = load()
    H.truthy(Theme.get("gold").frameOuter[1] ~= Theme.get("copper").frameOuter[1])
    H.truthy(Theme.get("gold").frameOuter[3] ~= Theme.get("steel").frameOuter[3])
end)

H.test("fixed colours exist and are valid colours", function()
    local Theme = load()
    for _, key in ipairs({ "profit", "loss", "incomplete", "stale", "best", "optimal", "medium", "easy", "trivial" }) do
        local c = Theme.FIXED[key]
        H.truthy(c)
        H.eq(#c, 4)
    end
end)

H.test("meaningful colours and text stay readable on the panels of every theme", function()
    local Theme = load()
    for _, name in ipairs(Theme.list()) do
        local t = Theme.get(name)
        for key, c in pairs(Theme.FIXED) do
            if contrast(c, t.panelBg) < 4.5 then error(name .. ": fixed " .. key .. " on panelBg") end
            if contrast(c, t.windowBg) < 4.5 then error(name .. ": fixed " .. key .. " on windowBg") end
        end
        if contrast(t.textMain, t.panelBg) < 4.5 then error(name .. ": textMain") end
        if contrast(t.textMuted, t.panelBg) < 4.5 then error(name .. ": textMuted") end
        if contrast(t.headText, t.headBgTop) < 4.5 then error(name .. ": headText") end
        if contrast(t.buttonText, t.buttonBg) < 4.5 then error(name .. ": buttonText") end
        if contrast(t.primaryText, t.primaryBg) < 4.5 then error(name .. ": primaryText") end
    end
end)
```

- [ ] **Step 2: Run it to see it fail**

Run: `luajit tests/run.lua 2>&1 | tail -5`
Expected: `FAIL tests/test_theme.lua` (cannot load `CraftProfit/Theme.lua`).

- [ ] **Step 3: Write `CraftProfit/Theme.lua`**

```lua
-- Colour themes for the UI. Pure data, no WoW API. A window reads every colour that
-- belongs to the look from a theme; Theme.FIXED holds the colours that carry a
-- meaning (gain, loss, recipe difficulty) and never change with the theme.
local _, ns = ...

local Theme = {}
ns.Theme = Theme

Theme.DEFAULT = "gold"
Theme.ORDER = { "gold", "copper", "steel" }

Theme.TOKENS = {
    "windowBg", "frameOuter", "frameInner", "frameShade", "plaqueBg", "plaqueText",
    "panelBg", "panelEdge", "headBgTop", "headBgBottom", "headText", "headRule", "rowZebra",
    "buttonBg", "buttonEdge", "buttonText", "primaryBg", "primaryEdge", "primaryText",
    "inputBg", "inputEdge", "checkMark", "bestFill", "bestEdge", "textMain", "textMuted",
}

-- "B08D3C" -> { r, g, b, a } with each channel in 0..1.
local function hex(rgb, alpha)
    return {
        tonumber(rgb:sub(1, 2), 16) / 255,
        tonumber(rgb:sub(3, 4), 16) / 255,
        tonumber(rgb:sub(5, 6), 16) / 255,
        alpha or 1,
    }
end

Theme.FIXED = {
    profit = { 0.35, 0.90, 0.45, 1 },
    loss = { 1.00, 0.40, 0.35, 1 },
    incomplete = { 1.00, 0.82, 0.25, 1 },
    stale = { 1.00, 0.60, 0.25, 1 },
    best = { 1.00, 0.82, 0.00, 1 },
    optimal = { 1.00, 0.50, 0.25, 1 },
    medium = { 1.00, 0.82, 0.00, 1 },
    easy = { 0.25, 0.75, 0.25, 1 },
    trivial = { 0.55, 0.55, 0.55, 1 },
}

local themes = {
    gold = {
        name = "gold",
        windowBg = hex("121110"), frameOuter = hex("B08D3C"), frameInner = hex("7A5F26"), frameShade = hex("1D140A"),
        plaqueBg = hex("1E160E"), plaqueText = hex("FFD100"),
        panelBg = hex("0D0C0B"), panelEdge = hex("3B3322"),
        headBgTop = hex("2A2216"), headBgBottom = hex("17130D"), headText = hex("C9A95A"), headRule = hex("5D4A22"),
        rowZebra = hex("FFFFFF", 0.03),
        buttonBg = hex("1B1814"), buttonEdge = hex("5D4A22"), buttonText = hex("D9C48A"),
        primaryBg = hex("3B2A0C"), primaryEdge = hex("B08D3C"), primaryText = hex("FFD100"),
        inputBg = hex("0B0A09"), inputEdge = hex("3B3322"), checkMark = hex("C9A95A"),
        bestFill = hex("FFD100", 0.11), bestEdge = hex("B08D3C", 0.65),
        textMain = hex("E8E0CC"), textMuted = hex("8A8372"),
    },
    copper = {
        name = "copper",
        windowBg = hex("17100B"), frameOuter = hex("C87533"), frameInner = hex("6B4524"), frameShade = hex("1C1109"),
        plaqueBg = hex("24150A"), plaqueText = hex("F0A35A"),
        panelBg = hex("0F0A07"), panelEdge = hex("4A2F18"),
        headBgTop = hex("33200F"), headBgBottom = hex("1B1008"), headText = hex("E0A46A"), headRule = hex("6B4524"),
        rowZebra = hex("FFFFFF", 0.03),
        buttonBg = hex("26180E"), buttonEdge = hex("6B4524"), buttonText = hex("E0A46A"),
        primaryBg = hex("5A2E10"), primaryEdge = hex("C87533"), primaryText = hex("FFC58A"),
        inputBg = hex("0A0604"), inputEdge = hex("4A2F18"), checkMark = hex("E0A46A"),
        bestFill = hex("FFD100", 0.12), bestEdge = hex("FFD100", 0.70),
        textMain = hex("E8E0CC"), textMuted = hex("957757"),
    },
    steel = {
        name = "steel",
        windowBg = hex("070814"), frameOuter = hex("5F6684"), frameInner = hex("3A4160"), frameShade = hex("12162C"),
        plaqueBg = hex("0E1226"), plaqueText = hex("CFD8FF"),
        panelBg = hex("0D0F1F"), panelEdge = hex("2A3048"),
        headBgTop = hex("1A2036"), headBgBottom = hex("10142A"), headText = hex("8FA4E6"), headRule = hex("3A4260"),
        rowZebra = hex("FFFFFF", 0.03),
        buttonBg = hex("1A2036"), buttonEdge = hex("4A5272"), buttonText = hex("CFD8FF"),
        primaryBg = hex("243A78"), primaryEdge = hex("6A86E0"), primaryText = hex("FFFFFF"),
        inputBg = hex("05060D"), inputEdge = hex("3A4260"), checkMark = hex("8FA4E6"),
        bestFill = hex("FFD100", 0.12), bestEdge = hex("FFD100", 0.60),
        textMain = hex("E6E8F2"), textMuted = hex("7A82A6"),
    },
}

function Theme.exists(name)
    return type(name) == "string" and themes[name] ~= nil
end

-- The theme called `name`, or the default one for anything unknown.
function Theme.get(name)
    if Theme.exists(name) then return themes[name] end
    return themes[Theme.DEFAULT]
end

function Theme.list()
    local names = {}
    for i, name in ipairs(Theme.ORDER) do names[i] = name end
    return names
end

-- true, or false and the reason: every token must be a { r, g, b, a } of numbers in 0..1.
function Theme.validate(theme)
    if type(theme) ~= "table" then return false, "not a table" end
    for _, token in ipairs(Theme.TOKENS) do
        local c = theme[token]
        if type(c) ~= "table" then return false, "missing " .. token end
        for i = 1, 4 do
            local v = c[i]
            if type(v) ~= "number" or v ~= v or v < 0 or v > 1 then return false, "bad " .. token end
        end
    end
    return true
end
```

Also edit `CraftProfit/CraftProfit.toc`: insert the line `Theme.lua` right after `Format.lua`.

- [ ] **Step 4: Run the tests**

Run: `sh tests/check.sh 2>&1 | grep -E "passed|failed|Total|FAIL"`
Expected: the new tests pass, `0 failed`, `0 warnings`. If a contrast assertion fails, raise the lightness of the named text token in `Theme.lua`; never lower the 4.5 threshold.

- [ ] **Step 5: Commit**

```bash
git add CraftProfit/Theme.lua CraftProfit/CraftProfit.toc tests/test_theme.lua
git commit -m "feat: theme data with three colour themes and validation"
```

---

### Task 2: `theme` setting in the saved variables

**Files:**
- Modify: `CraftProfit/DB.lua` (defaults near line 14, `sanitizeSettings` near line 41)
- Test: `tests/test_db.lua`

**Interfaces:**
- Consumes: `ns.Theme.exists(name)` (may be absent: tests that load `DB` without `Theme`).
- Produces: `DB.DEFAULTS.theme == "gold"`; after `DB.initAccount`, `db.settings.theme` is always an existing theme name, `"gold"` when it was missing, not a string, unknown, or `Theme` is not loaded.

- [ ] **Step 1: Write the failing tests** (append to `tests/test_db.lua`)

```lua
H.test("the theme setting keeps a known theme and falls back to gold otherwise", function()
    local ns = H.newNS("Util", "Theme", "Data/Skillup", "Recipes", "DB")
    local DB = ns.DB
    H.eq(DB.DEFAULTS.theme, "gold")
    local function theme(value)
        local db = DB.initAccount({ settings = { theme = value } })
        return db.settings.theme
    end
    H.eq(theme("copper"), "copper")
    H.eq(theme("steel"), "steel")
    H.eq(theme("nope"), "gold")
    H.eq(theme(5), "gold")
    H.eq(theme(nil), "gold")
    H.eq(theme({}), "gold")
end)

H.test("the theme setting becomes gold when the theme module is not loaded", function()
    local ns = H.newNS("Util", "Data/Skillup", "Recipes", "DB")
    local db = ns.DB.initAccount({ settings = { theme = "copper" } })
    H.eq(db.settings.theme, "gold")
end)
```

- [ ] **Step 2: Run to see them fail**

Run: `luajit tests/run.lua 2>&1 | grep -A3 "theme setting"`
Expected: failures (`DB.DEFAULTS.theme` is nil).

- [ ] **Step 3: Implement.** In `DB.DEFAULTS` add `theme = "gold",` after `staleAfter`. In `sanitizeSettings`, after the `levelSort` line, add:

```lua
    if type(s.theme) ~= "string" or not (ns.Theme and ns.Theme.exists(s.theme)) then
        s.theme = DB.DEFAULTS.theme
    end
```

- [ ] **Step 4: Run the whole suite**

Run: `sh tests/check.sh 2>&1 | grep -E "passed|failed|Total|FAIL"`
Expected: `0 failed`, `0 warnings`. If an existing test compares a full `settings` table, add `theme = "gold"` to its expected value.

- [ ] **Step 5: Commit**

```bash
git add CraftProfit/DB.lua tests/test_db.lua
git commit -m "feat: theme setting in the saved variables, sanitised"
```

---

### Task 3: Kit pure helpers

**Files:**
- Create: `CraftProfit/UI/Kit.lua` (helpers only in this task)
- Modify: `CraftProfit/CraftProfit.toc` (add `UI/Kit.lua` before `UI/Window.lua`), `.luacheckrc` (read globals `STANDARD_TEXT_FONT`, `CreateColor`)
- Test: `tests/test_kit.lua`

**Interfaces:**
- Consumes: `ns.Theme`.
- Produces on `ns.Kit`: constants `HEAD_H = 22`, `BODY_PAD = 4`, `GAP = 8`, `CONTENT_TOP = 26`, `CONTENT_SIDE = 12`, `CONTENT_BOTTOM = 12`, `TILE_SIZES = {19, 17, 15, 13, 11}`; `panelHeight(rows, rowH, extra) -> number`; `stack(heights, gap, top) -> offsets, total` (offsets are negative y values, total excludes the trailing gap); `fitSize(baseWidth, baseSize, boxWidth, sizes) -> size`; `gradient(tex, top, bottom) -> "color" | "rgb" | "flat"`.

- [ ] **Step 1: Write the failing tests** (`tests/test_kit.lua`)

```lua
local H = ...
local W = dofile("tests/fakewow.lua")

local function load()
    return H.newNS("Theme", "UI/Kit").Kit
end

H.test("panelHeight adds the header, the body padding and the rows", function()
    local Kit = load()
    H.eq(Kit.panelHeight(3, 18), 22 + 8 + 54)
    H.eq(Kit.panelHeight(0, 18), 30)
    H.eq(Kit.panelHeight(nil, 18), 30)
    H.eq(Kit.panelHeight(-4, 18), 30)
    H.eq(Kit.panelHeight(2, 18, 10), 22 + 8 + 36 + 10)
    H.eq(Kit.panelHeight(2.9, 10), 22 + 8 + 20)
end)

H.test("stack places panels one under the other with a gap and reports the total", function()
    local Kit = load()
    local offsets, total = Kit.stack({ 30, 20 }, 8, 10)
    H.eq(offsets, { -10, -48 })
    H.eq(total, 58)
    offsets, total = Kit.stack({ 50 }, 8)
    H.eq(offsets, { 0 })
    H.eq(total, 50)
    offsets, total = Kit.stack({}, 8)
    H.eq(offsets, {})
    H.eq(total, 0)
end)

H.test("fitSize picks the largest size that fits, the smallest when none does", function()
    local Kit = load()
    local sizes = { 19, 17, 15, 13 }
    H.eq(Kit.fitSize(100, 19, 120, sizes), 19)
    H.eq(Kit.fitSize(150, 19, 120, sizes), 15)
    H.eq(Kit.fitSize(1000, 19, 120, sizes), 13)
    H.eq(Kit.fitSize(nil, 19, 120, sizes), 19)
    H.eq(Kit.fitSize("x", 19, 120, sizes), 19)
    H.eq(Kit.fitSize(150, 0, 120, sizes), 19)
end)

local function withColor(fn)
    local saved = _G.CreateColor
    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    local ok, err = pcall(fn)
    _G.CreateColor = saved
    if not ok then error(err, 0) end
end

local TOP, BOTTOM = { 1, 0, 0, 1 }, { 0, 0, 1, 1 }

H.test("gradient uses colour objects when the client takes them, bottom colour first", function()
    local Kit = load()
    withColor(function()
        local got
        local tex = { SetGradient = function(_, orientation, a, b) got = { orientation, a, b } end }
        H.eq(Kit.gradient(tex, TOP, BOTTOM), "color")
        H.eq(got[1], "VERTICAL")
        H.eq(got[2].b, 1)
        H.eq(got[3].r, 1)
    end)
end)

H.test("gradient falls back to the six-number signature, then to a flat colour", function()
    local Kit = load()
    local saved = _G.CreateColor
    _G.CreateColor = nil
    local got
    local tex = { SetGradient = function(_, orientation, r1, _, b1, r2) got = { orientation, r1, b1, r2 } end }
    H.eq(Kit.gradient(tex, TOP, BOTTOM), "rgb")
    H.eq(got, { "VERTICAL", 0, 1, 1 })
    local flat
    local failing = {
        SetGradient = function() error("bad signature") end,
        SetColorTexture = function(_, r, g, b, a) flat = { r, g, b, a } end,
    }
    H.eq(Kit.gradient(failing, TOP, BOTTOM), "flat")
    H.eq(flat, { 0.5, 0, 0.5, 1 })
    flat = nil
    local missing = { SetColorTexture = function(_, r, g, b, a) flat = { r, g, b, a } end }
    H.eq(Kit.gradient(missing, TOP, BOTTOM), "flat")
    H.eq(flat, { 0.5, 0, 0.5, 1 })
    _G.CreateColor = saved
end)

H.test("the kit file is loaded by the fake game environment", function()
    local T = W.boot(H)
    H.truthy(T.ns.Kit)
    H.truthy(T.ns.Theme)
end)
```

- [ ] **Step 2: Run to see failures**

Run: `luajit tests/run.lua 2>&1 | grep FAIL | head -3`
Expected: `FAIL tests/test_kit.lua` (no `UI/Kit.lua` yet).

- [ ] **Step 3: Write `CraftProfit/UI/Kit.lua` (helpers)**

```lua
-- Shared UI kit: panels, buttons, tiles and the window frame, all coloured from the
-- current theme (see Theme.lua). The first half is pure layout arithmetic and is
-- unit tested; the widgets below it are thin glue over game frames.
local _, ns = ...
local Theme = ns.Theme

local Kit = {}
ns.Kit = Kit

Kit.HEAD_H = 22
Kit.BODY_PAD = 4
Kit.GAP = 8
Kit.CONTENT_TOP = 26
Kit.CONTENT_SIDE = 12
Kit.CONTENT_BOTTOM = 12
Kit.TILE_SIZES = { 19, 17, 15, 13, 11 }

-- Height of a panel holding `rows` rows of `rowH` pixels (plus `extra`).
function Kit.panelHeight(rows, rowH, extra)
    rows = math.max(0, math.floor(tonumber(rows) or 0))
    return Kit.HEAD_H + Kit.BODY_PAD * 2 + rows * rowH + (extra or 0)
end

-- Vertical offsets (negative, from the top of the content area) of panels stacked
-- with `gap` between them, and the total height without the trailing gap.
function Kit.stack(heights, gap, top)
    gap = gap or Kit.GAP
    top = top or 0
    local y, offsets = top, {}
    for i, h in ipairs(heights) do
        offsets[i] = -y
        y = y + h + gap
    end
    if #heights == 0 then return offsets, 0 end
    return offsets, y - gap - top
end

-- Largest of `sizes` (descending) at which a text measured `baseWidth` wide at
-- `baseSize` fits `boxWidth`; the smallest size when none does, the first one when
-- the width cannot be measured.
function Kit.fitSize(baseWidth, baseSize, boxWidth, sizes)
    if type(baseWidth) ~= "number" or type(baseSize) ~= "number" or baseSize <= 0 then return sizes[1] end
    for _, size in ipairs(sizes) do
        if baseWidth * size / baseSize <= boxWidth then return size end
    end
    return sizes[#sizes]
end

-- Vertical gradient from `top` to `bottom` ({ r, g, b, a }). The client's gradient
-- call takes the bottom colour first. Returns which form worked: "color" (colour
-- objects), "rgb" (six numbers) or "flat" (the middle colour, when neither does).
function Kit.gradient(tex, top, bottom)
    if type(CreateColor) == "function" then
        local ok = pcall(tex.SetGradient, tex, "VERTICAL",
            CreateColor(bottom[1], bottom[2], bottom[3], bottom[4]),
            CreateColor(top[1], top[2], top[3], top[4]))
        if ok then return "color" end
    end
    if pcall(tex.SetGradient, tex, "VERTICAL", bottom[1], bottom[2], bottom[3], top[1], top[2], top[3]) then
        return "rgb"
    end
    tex:SetColorTexture((top[1] + bottom[1]) / 2, (top[2] + bottom[2]) / 2,
        (top[3] + bottom[3]) / 2, (top[4] + bottom[4]) / 2)
    return "flat"
end

Kit.themeName = Theme.DEFAULT
Kit.current = Theme.get(Theme.DEFAULT)
```

Edit `CraftProfit.toc`: add `UI/Kit.lua` on the line before `UI/Window.lua`. Edit `.luacheckrc`: in the `read_globals` list add `"STANDARD_TEXT_FONT", "CreateColor",` (next to `"Enum", "UIParent", "DEFAULT_CHAT_FRAME",`).

- [ ] **Step 4: Run the whole suite**

Run: `sh tests/check.sh 2>&1 | grep -E "passed|failed|Total|FAIL"`
Expected: `0 failed`, `0 warnings`.

- [ ] **Step 5: Commit**

```bash
git add CraftProfit/UI/Kit.lua CraftProfit/CraftProfit.toc .luacheckrc tests/test_kit.lua
git commit -m "feat: UI kit layout helpers (panel height, stacking, font fit, gradient fallback)"
```

---

### Task 4: Kit widgets and theme registry

**Files:**
- Modify: `CraftProfit/UI/Kit.lua` (append the widgets)
- Test: `tests/test_kit.lua` (append)

**Interfaces:**
- Consumes: Task 3 helpers; game API `CreateFrame`, `UIParent`, `STANDARD_TEXT_FONT`.
- Produces on `ns.Kit`: `applyTheme(name) -> theme`; `rings(frame, tokens, layer) -> refresh`; `window(name, title, opts) -> frame` with `frame.content`, `frame.plaque`, `frame:setTitle(text)`, `opts = { width, height, onMoved }`; `panel(parent, title) -> p` with `p.frame`, `p.body`, `p.right` (header-right FontString), `p:setTitle(text)`, `p:setRows(n, rowH, extra)`, `p:height()`; `button(parent, kind, text) -> button` (kind `normal`, `primary` or `small`) with `button:setText(text)`; `tile(parent, width, height) -> tile` with `tile.frame`, `tile:set({ label, value, tag, best, muted })`.

- [ ] **Step 1: Write the failing tests** (append to `tests/test_kit.lua`)

```lua
local function boot()
    local T = W.boot(H)
    return T, T.ns.Kit, T.env
end

H.test("applyTheme switches the current theme, twice in a row, and ignores unknown names", function()
    local _, Kit = boot()
    H.eq(Kit.themeName, "gold")
    for _, name in ipairs({ "copper", "steel", "steel", "gold" }) do
        Kit.applyTheme(name)
        H.eq(Kit.themeName, name)
        H.eq(Kit.current.name, name)
    end
    Kit.applyTheme("nope")
    H.eq(Kit.themeName, "gold")
end)

H.test("every widget survives every theme being applied after it was built", function()
    local _, Kit = boot()
    local win = Kit.window("KitTestWindow", "Title", { width = 372 })
    local panel = Kit.panel(win.content, "MATERIALS")
    panel:setRows(3, 18)
    local button = Kit.button(win.content, "primary", "Go")
    local small = Kit.button(win.content, "small", "x")
    local normal = Kit.button(win.content, "normal", "Ok")
    local tile = Kit.tile(win.content, 110, 52)
    tile:set({ label = "AH (NET)", value = "3g 24s", best = true })
    for _, name in ipairs({ "copper", "steel", "gold" }) do
        Kit.applyTheme(name)
    end
    H.truthy(button and small and normal)
    H.eq(panel:height(), 84)
end)
```

```lua
H.test("the window reports where it was dropped and sizes its plaque to the title", function()
    local _, Kit = boot()
    local moved
    local win = Kit.window("KitTestWindow2", "A title", { onMoved = function(...) moved = { ... } end })
    win.scripts.OnDragStop(win)
    H.eq(moved, { "TOPLEFT", 100, 700 })
    win:setTitle("Another title")
    H.truthy(win.plaque)
end)

H.test("a panel keeps its title and right-hand text", function()
    local _, Kit = boot()
    local panel = Kit.panel(nil, "MATERIALS")
    H.eq(panel.title.text, "MATERIALS")
    panel:setTitle("OPTIONS")
    H.eq(panel.title.text, "OPTIONS")
    panel.right:SetText("2g 33s")
    H.eq(panel.right.text, "2g 33s")
end)

H.test("a tile shows its label, tag and value, and remembers whether it is the best one", function()
    local _, Kit = boot()
    local tile = Kit.tile(nil, 110, 52)
    tile:set({ label = "DISENCH.", tag = "beta", value = "2g 2s" })
    H.truthy(tile.label.text:find("DISENCH.", 1, true))
    H.truthy(tile.label.text:find("beta", 1, true))
    H.eq(tile.value.text, "2g 2s")
    H.falsy(tile.best)
    tile:set({ label = "AH", value = "3g 24s", best = true })
    H.truthy(tile.best)
    tile:set({ label = "AH", value = "n/a", muted = true })
    H.falsy(tile.best)
    tile:set({})
    H.eq(tile.value.text, "")
end)

H.test("a button keeps the text it is given and runs its click handler", function()
    local _, Kit = boot()
    local clicks = 0
    local button = Kit.button(nil, "normal", "Scan")
    H.eq(button.label.text, "Scan")
    button:setText("Search")
    H.eq(button.label.text, "Search")
    button:SetScript("OnClick", function() clicks = clicks + 1 end)
    button.scripts.OnClick(button)
    H.eq(clicks, 1)
end)
```

(In `tile`/`button` tests the parent is `nil`: the fake `CreateFrame` ignores its arguments.)

- [ ] **Step 2: Run to see failures**

Run: `luajit tests/run.lua 2>&1 | grep FAIL | head`
Expected: failures: `Kit.applyTheme` etc. are nil.

- [ ] **Step 3: Append the widgets to `CraftProfit/UI/Kit.lua`**

```lua
-- Theme registry ------------------------------------------------------------

-- Every widget registers a function that paints it from a theme; applyTheme
-- repaints them all, so a theme can be switched while windows are open.
local registry = {}

local function register(paint)
    registry[#registry + 1] = paint
    paint(Kit.current)
end

function Kit.applyTheme(name)
    Kit.themeName = Theme.exists(name) and name or Theme.DEFAULT
    Kit.current = Theme.get(Kit.themeName)
    for _, paint in ipairs(registry) do paint(Kit.current) end
    return Kit.current
end

-- A token name, a function returning one, or "black".
local function colorOf(token)
    if type(token) == "function" then token = token() end
    if token == "black" then return { 0, 0, 0, 1 } end
    return Kit.current[token]
end

local function paintTexture(tex, token)
    local c = colorOf(token)
    tex:SetColorTexture(c[1], c[2], c[3], c[4])
end

local function setTextColor(fontString, token)
    local c = colorOf(token)
    fontString:SetTextColor(c[1], c[2], c[3], c[4])
end

-- Draws one-pixel rings from the outside in, one per token (solid-colour textures,
-- no Blizzard atlas needed). Returns a function that repaints them, for rings whose
-- token is a function.
function Kit.rings(frame, tokens, layer)
    local paints = {}
    for i, token in ipairs(tokens) do
        local n = i - 1
        local function line(p1, x1, y1, p2, x2, y2, width, height)
            local tex = frame:CreateTexture(nil, layer or "BORDER")
            tex:SetPoint(p1, frame, p1, x1, y1)
            tex:SetPoint(p2, frame, p2, x2, y2)
            if width then tex:SetWidth(width) end
            if height then tex:SetHeight(height) end
            paints[#paints + 1] = function() paintTexture(tex, token) end
        end
        line("TOPLEFT", n, -n, "TOPRIGHT", -n, -n, nil, 1)
        line("BOTTOMLEFT", n, n, "BOTTOMRIGHT", -n, n, nil, 1)
        line("TOPLEFT", n, -n - 1, "BOTTOMLEFT", n, n + 1, 1, nil)
        line("TOPRIGHT", -n, -n - 1, "BOTTOMRIGHT", -n, n + 1, 1, nil)
    end
    local function refresh()
        for _, paint in ipairs(paints) do paint() end
    end
    register(refresh)
    return refresh
end

-- Window ----------------------------------------------------------------------

local WINDOW_RINGS = { "black", "frameInner", "frameInner", "frameShade", "frameOuter", "black" }
local PLAQUE_MIN_WIDTH = 210

-- A movable framed window with a title plaque straddling its top edge and a close
-- button. `frame.content` is the area to fill. opts: width, height, onMoved(point, x, y).
function Kit.window(name, title, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(opts.width or 372, opts.height or 200)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    register(function(t) bg:SetColorTexture(t.windowBg[1], t.windowBg[2], t.windowBg[3], t.windowBg[4]) end)
    Kit.rings(f, WINDOW_RINGS)

    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Re-anchor to the screen's bottom-left corner so saved offsets are absolute.
        local left, top = self:GetLeft(), self:GetTop()
        if left and top then
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            if opts.onMoved then opts.onMoved("TOPLEFT", left, top) end
        end
    end)

    local plaque = CreateFrame("Frame", nil, f)
    plaque:SetPoint("TOP", f, "TOP", 0, 14)
    plaque:SetSize(PLAQUE_MIN_WIDTH, 26)
    local plaqueBg = plaque:CreateTexture(nil, "BACKGROUND")
    plaqueBg:SetAllPoints(plaque)
    register(function(t) plaqueBg:SetColorTexture(t.plaqueBg[1], t.plaqueBg[2], t.plaqueBg[3], t.plaqueBg[4]) end)
    Kit.rings(plaque, { "black", "frameOuter", "black" })
    local text = plaque:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("CENTER", plaque, "CENTER", 0, 0)
    register(function() setTextColor(text, "plaqueText") end)
    f.plaque = plaque
    f.titleText = text

    function f:setTitle(value)
        text:SetText(value or "")
        local width = text:GetStringWidth()
        if type(width) == "number" then plaque:SetWidth(math.max(PLAQUE_MIN_WIDTH, width + 44)) end
    end
    f:setTitle(title)

    local close = Kit.button(f, "small", "x")
    close:SetSize(18, 18)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() f:Hide() end)
    f.close = close

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", Kit.CONTENT_SIDE, -Kit.CONTENT_TOP)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -Kit.CONTENT_SIDE, Kit.CONTENT_BOTTOM)
    f.content = content
    return f
end

-- Panel -----------------------------------------------------------------------

-- A bordered section with a header bar. Fill `p.body`; size it with setRows.
function Kit.panel(parent, title)
    local p = {}
    local f = CreateFrame("Frame", nil, parent)
    p.frame = f
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    register(function() paintTexture(bg, "panelBg") end)
    Kit.rings(f, { "panelEdge" })

    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    head:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    head:SetHeight(Kit.HEAD_H)
    local headBg = head:CreateTexture(nil, "BACKGROUND")
    headBg:SetAllPoints(head)
    local rule = head:CreateTexture(nil, "BORDER")
    rule:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", 0, 0)
    rule:SetHeight(1)
    p.title = head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.title:SetPoint("LEFT", head, "LEFT", 8, 0)
    p.right = head:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.right:SetPoint("RIGHT", head, "RIGHT", -8, 0)
    register(function(t)
        Kit.gradient(headBg, t.headBgTop, t.headBgBottom)
        paintTexture(rule, "headRule")
        setTextColor(p.title, "headText")
    end)

    p.body = CreateFrame("Frame", nil, f)
    p.body:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -Kit.BODY_PAD)
    p.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)

    p.rowH = 18
    function p:setTitle(text) self.title:SetText(text or "") end
    function p:setRows(rows, rowH, extra)
        self.rowH = rowH or self.rowH
        f:SetHeight(Kit.panelHeight(rows, self.rowH, extra))
    end
    function p:height() return f:GetHeight() end
    p:setTitle(title)
    return p
end

-- Button ----------------------------------------------------------------------

-- kind: "normal", "primary" (gold, the one main action of a window) or "small".
function Kit.button(parent, kind, text)
    local small = kind == "small"
    local primary = kind == "primary"
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(small and 18 or 24)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    b.label = b:CreateFontString(nil, "OVERLAY", small and "GameFontNormalSmall" or "GameFontNormal")
    b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
    Kit.rings(b, { primary and "primaryEdge" or "buttonEdge" })

    local hover = false
    local function paint(t)
        local c = (primary or hover) and t.primaryBg or t.buttonBg
        bg:SetColorTexture(c[1], c[2], c[3], c[4])
        setTextColor(b.label, primary and "primaryText" or "buttonText")
    end
    register(paint)
    b:SetScript("OnEnter", function() hover = true; paint(Kit.current) end)
    b:SetScript("OnLeave", function() hover = false; paint(Kit.current) end)

    function b:setText(value) self.label:SetText(value or "") end
    b:setText(text)
    return b
end

-- Tile ------------------------------------------------------------------------

-- A small card with a label and a large value that shrinks to fit its width.
function Kit.tile(parent, width, height)
    local tile = { best = false, muted = false }
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 110, height or 52)
    tile.frame = f
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    register(function() paintTexture(bg, "panelBg") end)
    local refreshRings = Kit.rings(f, { function() return tile.best and "bestEdge" or "panelEdge" end })

    tile.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tile.label:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
    tile.value = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tile.value:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -24)

    local function paint()
        setTextColor(tile.label, "headText")
        setTextColor(tile.value, tile.muted and "textMuted" or "textMain")
        refreshRings()
    end
    register(paint)

    -- spec: { label, tag, value, best, muted }
    function tile:set(spec)
        self.best = spec.best and true or false
        self.muted = spec.muted and true or false
        local label = spec.label or ""
        if spec.tag then label = label .. " |cffffd100" .. spec.tag .. "|r" end
        self.label:SetText(label)
        local big = Kit.TILE_SIZES[1]
        self.value:SetFont(STANDARD_TEXT_FONT, big, "")
        self.value:SetText(spec.value or "")
        local room = (f:GetWidth() or width or 110) - 20
        local size = Kit.fitSize(self.value:GetStringWidth(), big, room, Kit.TILE_SIZES)
        if size ~= big then self.value:SetFont(STANDARD_TEXT_FONT, size, "") end
        paint()
    end
    return tile
end
```

Note: a tile's value is measured at the largest size, then the font is stepped down by the pure rule; `STANDARD_TEXT_FONT` is nil in the fake environment, which the fake `SetFont` accepts.

- [ ] **Step 4: Run the whole suite**

Run: `sh tests/check.sh 2>&1 | grep -E "passed|failed|Total|FAIL"`
Expected: `0 failed`, `0 warnings`.

- [ ] **Step 5: Commit**

```bash
git add CraftProfit/UI/Kit.lua tests/test_kit.lua
git commit -m "feat: UI kit widgets (window, panel, button, tile) with theme registry"
```

---

### Task 5: Demo window, slash command, probe

**Files:**
- Create: `CraftProfit/UI/KitDemo.lua`
- Modify: `CraftProfit/CraftProfit.toc` (add `UI/KitDemo.lua` after `UI/LevelingUI.lua`), `CraftProfit/Boot.lua` (branch near line 563), `probe/CraftProfitProbe/Probe.lua` (command + usage line)
- Test: `tests/test_kit.lua` (append)

**Interfaces:**
- Consumes: `ns.Kit`, `ns.Theme`.
- Produces: `ns.KitDemo.toggle(arg)`: with a theme name, applies it and shows the window (chat message for an unknown name, nothing else changes); with no argument, shows or hides the window. Slash: `/cp kitdemo [theme]`. Probe: `/cpp skin`.

- [ ] **Step 1: Write the failing tests** (append to `tests/test_kit.lua`)

```lua
H.test("kitdemo shows the demo window in the asked theme and toggles without one", function()
    local T = W.boot(H)
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    T.env.SlashCmdList.CRAFTPROFIT("kitdemo copper")
    H.eq(T.ns.Kit.themeName, "copper")
    T.env.SlashCmdList.CRAFTPROFIT("kitdemo")
    T.env.SlashCmdList.CRAFTPROFIT("kitdemo")
    T.env.SlashCmdList.CRAFTPROFIT("kitdemo steel")
    H.eq(T.ns.Kit.themeName, "steel")
end)

H.test("kitdemo with an unknown theme says so and keeps the current theme", function()
    local T = W.boot(H)
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    T.env.SlashCmdList.CRAFTPROFIT("kitdemo nope")
    H.eq(T.ns.Kit.themeName, "gold")
    local said = table.concat(T.chat, "\n")
    H.truthy(said:find("nope", 1, true))
    H.truthy(said:find("gold, copper, steel", 1, true))
end)
```

- [ ] **Step 2: Run to see failures**

Run: `luajit tests/run.lua 2>&1 | grep FAIL | head -3`
Expected: both new tests fail (no `kitdemo` command).

- [ ] **Step 3: Create `CraftProfit/UI/KitDemo.lua`**

```lua
-- Developer tool: /cp kitdemo [theme] shows the shared widgets in a theme, so a
-- theme can be judged in the game before any real window uses it. English only,
-- not part of the user-facing help.
local _, ns = ...
local Kit, Theme = ns.Kit, ns.Theme

local KitDemo = {}
ns.KitDemo = KitDemo

local WIDTH = 372
local TILE_H = 52
local frame

local function addRow(panel, index, left, right)
    local y = -(index - 1) * 18
    local a = panel.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    a:SetPoint("TOPLEFT", panel.body, "TOPLEFT", 8, y)
    a:SetText(left)
    local b = panel.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b:SetPoint("TOPRIGHT", panel.body, "TOPRIGHT", -8, y)
    b:SetText(right)
end

local function build()
    frame = Kit.window("CraftProfitKitDemo", "Kit demo", { width = WIDTH })
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    local content = frame.content

    local tileW = math.floor((WIDTH - Kit.CONTENT_SIDE * 2 - 16) / 3)
    local specs = {
        { label = "AH (NET)", value = "3g 24s", best = true },
        { label = "VENDOR", value = "1g 12s" },
        { label = "DISENCH.", tag = "beta", value = "999g 99s 99c" },
    }
    for i, spec in ipairs(specs) do
        local tile = Kit.tile(content, tileW, TILE_H)
        tile.frame:SetPoint("TOPLEFT", content, "TOPLEFT", (i - 1) * (tileW + 8), 0)
        tile:set(spec)
    end

    local materials = Kit.panel(content, "MATERIALS")
    materials:setRows(3, 18)
    materials.right:SetText("2g 33s")
    addRow(materials, 1, "3x Bronze Bar", "2g 25s")
    addRow(materials, 2, "1x Coarse Weightstone", "8s")
    addRow(materials, 3, "1x Heavy Leather", "10s")

    local options = Kit.panel(content, "OPTIONS")
    options:setRows(1, 24)
    local x = 8
    for _, spec in ipairs({ { "primary", "Search prices" }, { "normal", "Scan AH" }, { "small", "Sort" } }) do
        local button = Kit.button(options.body, spec[1], spec[2])
        button:SetWidth(spec[1] == "small" and 50 or 100)
        button:SetPoint("TOPLEFT", options.body, "TOPLEFT", x, 0)
        x = x + (spec[1] == "small" and 58 or 108)
    end

    local offsets, total = Kit.stack({ TILE_H, materials:height(), options:height() }, Kit.GAP, 0)
    for i, panel in ipairs({ materials, options }) do
        panel.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, offsets[i + 1])
        panel.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, offsets[i + 1])
    end
    frame:SetHeight(total + Kit.CONTENT_TOP + Kit.CONTENT_BOTTOM)
end

-- With a theme name: apply it and show the window. Without: show or hide it.
function KitDemo.toggle(name)
    name = (name or ""):lower()
    if name ~= "" then
        if not Theme.exists(name) then
            DEFAULT_CHAT_FRAME:AddMessage("CraftProfit: unknown theme '" .. name .. "' ("
                .. table.concat(Theme.list(), ", ") .. ")")
            return
        end
        Kit.applyTheme(name)
        if not frame then build() end
        frame:Show()
        return
    end
    if not frame then build() end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end
```

In `CraftProfit.toc` add `UI/KitDemo.lua` after `UI/LevelingUI.lua`. In `Boot.lua`, in `slash`, add before the `elseif cmd == "market"` branch:

```lua
    elseif cmd == "kitdemo" then
        if ns.KitDemo then ns.KitDemo.toggle(arg) end
```

In `probe/CraftProfitProbe/Probe.lua`, add before the `SLASH_CPP1 = "/cpp"` line:

```lua
-- What the UI rework needs from the client: fonts, solid-colour textures, gradients.
cmds.skin = function()
    out("STANDARD_TEXT_FONT:", show(STANDARD_TEXT_FONT))
    out("GameFontNormal font:", try(GameFontNormal and GameFontNormal.GetFont, GameFontNormal))
    out("GameFontNormalSmall font:", try(GameFontNormalSmall and GameFontNormalSmall.GetFont, GameFontNormalSmall))
    out("GameFontHighlightSmall font:", try(GameFontHighlightSmall and GameFontHighlightSmall.GetFont, GameFontHighlightSmall))
    local f = CreateFrame("Frame")
    local t = f:CreateTexture(nil, "BACKGROUND")
    out("Texture:SetColorTexture:", type(t.SetColorTexture))
    out("CreateColor:", type(CreateColor))
    if type(CreateColor) == "function" then
        out("SetGradient(colour objects, bottom first):", try(t.SetGradient, t, "VERTICAL",
            CreateColor(0, 0, 0, 1), CreateColor(1, 1, 1, 1)))
    end
    out("SetGradient(six numbers):", try(t.SetGradient, t, "VERTICAL", 0, 0, 0, 1, 1, 1))
    out("Texture:SetGradientAlpha:", type(t.SetGradientAlpha))
    out("BackdropTemplateMixin:", type(BackdropTemplateMixin))
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    for _, size in ipairs({ 19, 15, 11 }) do
        out("SetFont", size, try(fs.SetFont, fs, STANDARD_TEXT_FONT, size, ""))
        fs:SetText("999g 99s 99c")
        out("  width of '999g 99s 99c':", try(fs.GetStringWidth, fs))
        fs:SetText("21g 29s")
        out("  width of '21g 29s':", try(fs.GetStringWidth, fs))
    end
end
```

In the usage line of the probe (`out("commands: api | ... | known | log | clear")`) add `| skin` after `known`. Bump `VERSION` to `"0.6.0"`.

- [ ] **Step 4: Run the whole suite**

Run: `sh tests/check.sh 2>&1 | grep -E "passed|failed|Total|FAIL"`
Expected: `0 failed`, `0 warnings`.

- [ ] **Step 5: Commit**

```bash
git add CraftProfit/UI/KitDemo.lua CraftProfit/CraftProfit.toc CraftProfit/Boot.lua probe/CraftProfitProbe/Probe.lua tests/test_kit.lua
git commit -m "feat: kit demo window (/cp kitdemo) and the /cpp skin probe"
```

---

### Task 6: Docs, spec amendments, in-game check, PR

**Files:**
- Modify: `docs/technical.md` (Architecture list and Probe section), `docs/in-game-checklist.md`, `CHANGELOG.md`, `docs/superpowers/specs/2026-10-09-ui-rework-design.md`

- [ ] **Step 1: Docs.**
  - `docs/technical.md`: in *Architecture* add `Theme.lua` (colour themes, pure data) and `UI/Kit.lua` + `UI/KitDemo.lua` (shared widgets and developer demo); in *Probe addon* add `skin` to the command list.
  - `docs/in-game-checklist.md`: add a section "UI kit (PR 1)": `/cp kitdemo` opens a framed window with a title plaque, three tiles (the first outlined in gold, the last with a long amount that shrinks to fit), two panels with a header bar, three buttons; `/cp kitdemo copper` and `/cp kitdemo steel` recolour it without `/reload`, and `/cp kitdemo gold` restores it; the close button hides it; it can be dragged.
  - `CHANGELOG.md` under *Unreleased / Added*: "Developer groundwork for the UI rework: colour themes (gold, copper, steel blue) and a shared widget kit, with a `/cp kitdemo` window. No existing window changes yet."
  - Spec: change token list to include `frameShade`; replace the sentence about `CreateFont` derived font objects with "Large numbers use `FontString:SetFont(STANDARD_TEXT_FONT, size, "")` at a size picked by `Kit.fitSize`"; in *Changed files / Kit* note that `Kit.check` and `Kit.input` arrive in PR 2; in Risks, replace the `CreateFont` mention in risk 1.

- [ ] **Step 2: Run everything and verify authorship**

Run: `sh tests/check.sh 2>&1 | grep -E "passed|failed|Total"; echo "coauthor: $(git log --format=%B | grep -ci co-authored)"`
Expected: `0 failed`, `0 warnings`, `coauthor: 0`.

- [ ] **Step 3: Commit, push, open the PR**

```bash
git add docs CHANGELOG.md
git commit -m "docs: UI kit documentation and spec amendments"
git push -u origin feat/ui-foundations
gh pr create --base main --title "feat: UI foundations (themes, widget kit, demo window)" --body "PR 1 of 4 of the UI rework (spec: docs/superpowers/specs/2026-10-09-ui-rework-design.md). Adds Theme.lua (gold, copper, steel blue), UI/Kit.lua (window, panel, button, tile), a developer demo (/cp kitdemo [theme]) and the /cpp skin probe. No existing window changes."
```

- [ ] **Step 4: In-game check (the author).** Ask the author to: `/reload`, run `/cpp skin`, `/cp kitdemo`, `/cp kitdemo copper`, `/cp kitdemo steel`, `/reload` again (to write the probe log), then read `WTF/Account/<id>/SavedVariables/CraftProfitProbe.lua` for the `skin` lines. Check the demo against the checklist section and the mockup (frame, plaque, tiles, panels). Fix findings on this branch before the author merges. The probe answers three questions that later PRs depend on: which gradient form works (`color`, `rgb` or neither), the real font path, and the pixel widths of the widest amounts.
