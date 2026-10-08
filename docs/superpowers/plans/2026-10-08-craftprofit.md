# CraftProfit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build CraftProfit, a World of Warcraft: Forever addon that prices a known profession recipe from auction house data and tells the player whether selling the result on the AH, selling it to a vendor, or disenchanting it loses the least money (or earns the most).

**Architecture:** Pure-Lua modules (`Util`, `Format`, `Core`, `Data/*`, `Recipes`, `DB`, `Prices`, `PriceQueue`, `Evaluate`, `Present`, `Locale`) hold all logic and are unit-tested under LuaJIT with a dependency-free harness. Thin game adapters (`AHAdapter`, `TradeAdapter`) convert the Forever API into the pure modules' plain tables, and a small UI layer (`UI/Window`, `UI/PinsUI`, `Boot`) renders results. An in-game probe addon (Task 2) settles the API unknowns before the adapters are written.

**Tech Stack:** Lua 5.1 (WoW runtime), LuaJIT + luacheck for offline tests, WoW Forever Interface `16001` (Mainline 12.1.5 API set).

**Spec:** `docs/superpowers/specs/2026-10-08-craftprofit-design.md`

**Reference:** `../Target_acquired/docs/guide-addon-wow-forever.md` (measured Forever API behavior, Lua 5.1 pitfalls, LuaJIT-vs-WoW differences, test method). The sibling repo `../Target_acquired` is the source of the test harness copied in Task 1.

## Global Constraints

Every task's requirements implicitly include this section.

- `## Interface: 16001`. Client folder: `World of Warcraft\_classic_beta_\Interface\AddOns\<AddonName>\`. Restart the client after adding a new addon folder.
- Lua 5.1 only: no `goto`, no `//`, no bitwise operators, no `_ENV`, no `require`, no file I/O. `string.format("%s", nil)` raises in WoW (not in LuaJIT): normalize arguments before `format`.
- `Core`, `Data`, `Recipes`, `DB`, `Prices`, `PriceQueue`, `Evaluate`, `Present`, `Format`, `Util` and `Locale` are **pure Lua with no WoW API calls**, so they run under LuaJIT tests.
- No dependency on other addons or libraries (no Ace, no Auctionator).
- Identifiers only: no logic depends on a displayed name, and no localized text is ever parsed (tooltips included). Item and recipe names shown come from the game API.
- Locales: enUS (reference), frFR, esES, esMX. Any other client locale falls back to enUS. Every enUS key exists in frFR and esES, with identical format specifiers.
- Money is displayed with `GetCoinTextureString` (language-independent). An unknown price is displayed `?`, never `0`.
- SavedVariables are initialized only in `ADDON_LOADED` and repaired in place (WoW keeps a reference to the loaded table).
- The window is parented to `UIParent`. Never call protected functions or write secure attributes on Blizzard frames.
- Values that may be "secret" (`issecretvalue`) are checked before being compared or stored.
- AH requests are sequential and respect throttling. The full scan (`ReplicateItems`) is limited by Blizzard to once per 15 minutes account-wide.
- The price used for an item is the median of its N cheapest listed units (default N = 5), not the minimum.
- Disenchanting is shown whenever the item is disenchantable, whether or not the player has Enchanting (a BoE item can be disenchanted by another character).
- AH commission is a single adjustable constant (`DB.DEFAULTS.cut = 0.05`) until the probe confirms the real value.
- Per the user's global instructions, before styling the window (Task 15) consult the `design-inspiration` skill; keep native WoW templates and keep the window small (about 270 px wide).
- Commits follow the session's attribution rules. One commit per task, after its checks pass.

## Spec clarifications decided in this plan

The spec is silent or ambiguous on these; the plan fixes them (flag any you disagree with before execution):

1. **Disenchant value is net of the AH commission.** The materials are sold on the AH, so the commission applies to them as it does to the crafted item.
2. **A bind-on-pickup crafted item cannot be listed on the AH**: its AH option is `n/a`.
3. **Scanning is user-triggered** (a "Scan AH" button) plus passive listening to other addons' scans. The spec's "scan only if old" is implemented as an age indicator that turns to a warning colour past `staleAfter` (default 1 h), not as an automatic scan, because a full scan freezes the client for a moment.
4. **esMX reuses the esES strings** (alias). Translations were written without a native review; ask guild members to check them.
5. **The material cost detail is a hover tooltip, not a fold-out.** The spec says "détail repliable"; a tooltip on the Materials line (quantity × item, unit price, subtotal) keeps the window small and needs no extra layout. A click-to-expand section can replace it later if you prefer.
6. **The pin button reads "Pin" / "Unpin"** (localized text) instead of a ★ glyph, because the game's default font may not contain that glyph.

## Review Focus

Inputs the spec implies but its tasks would not exercise by default. Each has a test in the task that owns the code.

1. **NaN, infinite, negative or non-number prices** (corrupt SavedVariables, odd API values) must give `?`, never `0`, a crash or a negative cost. (Tasks 3, 4, 8, 9)
2. **A recipe with one unpriced reagent** must be "incomplete", never "cheap". A recipe with an invalid reagent entry is rejected entirely. (Tasks 4, 7, 11)
3. **Item data not loaded yet** (`GetItemInfo` returns nothing) must show `?` and recover when the data arrives. (Tasks 11, 15)
4. **AH closed mid-search, no recipe selected, profession window closed** must cancel or hide cleanly without Lua errors. (Tasks 10, 15, 16)
5. **Unsupported client locale (deDE, ruRU…), clock going backwards, and secret values** must fall back to enUS, show an unknown age, and be skipped respectively. (Tasks 6, 8, 9, 13)

---

### Task 1: Repository scaffold and test harness

**Files:**
- Create: `.luacheckrc`
- Create: `tests/harness.lua`, `tests/run.lua`, `tests/check.sh`, `tests/test_harness.lua` (copied from `../Target_acquired/tests/`)
- Create: `CraftProfit/CraftProfit.toc`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `H.test(name, fn)`, `H.eq(actual, expected)`, `H.truthy`, `H.falsy`, `H.raises(fn)`, `H.newNS(...)` (loads `CraftProfit/<name>.lua` files, in order, into one fresh `ns`, passing `("CraftProfit", ns)` like WoW does), `H.loadModule(name, ns, env)` (same, inside a fake global environment via `setfenv`). `sh tests/check.sh` runs the tests then luacheck.

- [ ] **Step 1: Copy the harness from the sibling repo and retarget it**

Run from the repo root (`wow_addons/CraftProfit`):

```bash
mkdir -p tests CraftProfit
cp ../Target_acquired/tests/harness.lua ../Target_acquired/tests/run.lua ../Target_acquired/tests/check.sh ../Target_acquired/tests/test_harness.lua tests/
sed -i '' 's#TargetAcquired#CraftProfit#g' tests/harness.lua tests/check.sh
grep -n "TargetAcquired" tests/* || echo "no leftover references"
```

Expected: `no leftover references`.

- [ ] **Step 2: Create `.luacheckrc`**

```lua file=.luacheckrc
max_line_length = false
exclude_files = { "probe/**" }

-- The addon runs in WoW's sandbox: no io, package/require, dofile/loadfile,
-- and os is limited to time/date/clock.
stds.wowlua = {
    read_globals = {
        "assert", "collectgarbage", "error", "getmetatable", "ipairs",
        "next", "pairs", "pcall", "print", "rawequal", "rawget", "rawset",
        "select", "setmetatable", "tonumber", "tostring", "type", "unpack",
        "xpcall",
        -- Explicit field lists: a bare library name would allow any field and
        -- hide typos such as math.flor or table.unpack (nil-calls in WoW).
        math = { fields = {
            "abs", "acos", "asin", "atan", "atan2", "ceil", "cos", "cosh", "deg",
            "exp", "floor", "fmod", "frexp", "huge", "ldexp", "log", "log10",
            "max", "min", "modf", "pi", "pow", "rad", "random", "randomseed",
            "sin", "sinh", "sqrt", "tan", "tanh",
        } },
        string = { fields = {
            "byte", "char", "find", "format", "gmatch", "gsub", "len", "lower",
            "match", "rep", "reverse", "sub", "upper",
        } },
        table = { fields = {
            "concat", "insert", "maxn", "remove", "sort", "getn", "foreach",
            "foreachi",
        } },
        os = { fields = { "time", "date", "clock" } },
    },
}

-- Tests run on LuaJIT and use io, os, loadfile, dofile and setfenv.
std = "lua51"
files["CraftProfit"] = { std = "wowlua" }

-- Globals the addon itself writes.
globals = {
    "CraftProfitDB",
    "CraftProfitCharDB",
    "SLASH_CRAFTPROFIT1",
    "SLASH_CRAFTPROFIT2",
}

-- WoW API the addon reads. SlashCmdList is read-only as a whole table; the
-- only key the addon may assign is its own slash handler.
read_globals = {
    "CreateFrame", "GetLocale", "GetTime", "time", "GetCoinTextureString",
    "issecretvalue", "C_Timer", "C_AuctionHouse", "C_TradeSkillUI", "C_Item",
    "Enum", "UIParent", "DEFAULT_CHAT_FRAME", "GameTooltip",
    "ProfessionsFrame", "TradeSkillFrame", "AuctionHouseFrame", "AuctionFrame",
    "GetTradeSkillSelectionIndex", "GetTradeSkillRecipeLink",
    "GetTradeSkillInfo", "GetTradeSkillItemLink", "GetTradeSkillNumReagents",
    "GetTradeSkillReagentInfo", "GetTradeSkillReagentItemLink",
    "GetTradeSkillNumMade",
    SlashCmdList = {
        other_fields = true,
        fields = { CRAFTPROFIT = { read_only = false } },
    },
}
```

- [ ] **Step 3: Create the TOC**

The TOC lists every file the finished addon loads, except `UI/PinsUI.lua`, which Task 16 adds. Files are created by later tasks; the TOC is only loaded in the game from Task 15 on.

```text file=CraftProfit/CraftProfit.toc
## Interface: 16001
## Title: CraftProfit
## Notes: Prices profession recipes with auction house data and shows the most profitable way to sell the result.
## Author: juliani
## Version: 0.1.0
## SavedVariables: CraftProfitDB
## SavedVariablesPerCharacter: CraftProfitCharDB

Util.lua
Format.lua
Core.lua
Data/Skillup.lua
Data/Disenchant.lua
Locale.lua
Locales/enUS.lua
Locales/frFR.lua
Locales/esES.lua
Locales/esMX.lua
Recipes.lua
DB.lua
Prices.lua
PriceQueue.lua
Evaluate.lua
Present.lua
AHAdapter.lua
TradeAdapter.lua
UI/Window.lua
Boot.lua
```

- [ ] **Step 4: Ignore local-only files**

Append to `.gitignore` (it already ignores `.DS_Store`, `.superpowers/`, `*.zip`):

```text file=.gitignore
.DS_Store
.superpowers/
*.zip
```

- [ ] **Step 5: Run the harness self-tests and luacheck**

Run: `sh tests/check.sh`
Expected: `N passed, 0 failed` from the harness, then luacheck reporting `0 warnings / 0 errors` (there are no addon files yet; luacheck only checks `tests`).

- [ ] **Step 6: Commit**

```bash
git add .luacheckrc .gitignore tests CraftProfit/CraftProfit.toc
git commit -m "chore: scaffold test harness, luacheck config and TOC"
```

---

### Task 2: In-game probe addon and findings

This task settles the unknowns the spec lists in section 9. It needs the **user** to run the game: the agent writes the probe, the user runs it on the level 30 blacksmith (skill 140+) and pastes the output, the agent records it. Later adapter tasks (13, 14) are written against the findings.

**Files:**
- Create: `probe/CraftProfitProbe/CraftProfitProbe.toc`
- Create: `probe/CraftProfitProbe/Probe.lua`
- Create: `docs/probe-findings.md`

**Interfaces:**
- Produces: `docs/probe-findings.md`, whose fields F1–F8 are read by Tasks 8, 13, 14 and 15.

- [ ] **Step 1: Create the probe TOC**

```text file=probe/CraftProfitProbe/CraftProfitProbe.toc
## Interface: 16001
## Title: CraftProfit Probe
## Notes: THROWAWAY. Prints what the Forever API really returns. Never ship.
## Author: juliani
## Version: 0.1.0

Probe.lua
```

- [ ] **Step 2: Create the probe**

```lua file=probe/CraftProfitProbe/Probe.lua
-- CraftProfitProbe: THROWAWAY addon measuring what the Forever client exposes.
-- Every output line starts with the version so a stale install is obvious.
local VERSION = "0.1.0"
local TAG = "|cff66ccff[CPP " .. VERSION .. "]|r "

local function isSecret(v)
    if issecretvalue then
        local ok, res = pcall(issecretvalue, v)
        return ok and res
    end
    return false
end

local function show(v)
    if v == nil then return "nil" end
    if isSecret(v) then return "<SECRET>" end
    return tostring(v)
end

local function out(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = show((select(i, ...))) end
    DEFAULT_CHAT_FRAME:AddMessage(TAG .. table.concat(parts, " "))
end

local function pack(...) return { n = select("#", ...), ... } end

-- Calls fn without ever raising; returns a printable summary of what it returned.
local function try(fn, ...)
    if type(fn) ~= "function" then return "MISSING" end
    local r = pack(pcall(fn, ...))
    if not r[1] then return "ERR: " .. tostring(r[2]) end
    local parts = {}
    for i = 2, r.n do parts[#parts + 1] = show(r[i]) end
    return #parts == 0 and "(no return)" or table.concat(parts, ",")
end

local function resolve(path)
    local v = _G
    for key in path:gmatch("[^%.]+") do
        if type(v) ~= "table" then return nil end
        v = v[key]
    end
    return v
end

local function dumpTable(name, t)
    if type(t) ~= "table" then out(name, "=", show(t)); return end
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. show(t[k]) end
    out(name, "{", table.concat(parts, ", "), "}")
end

local cmds = {}
local searchStart

local API = {
    "C_AuctionHouse.MakeItemKey", "C_AuctionHouse.SendSearchQuery",
    "C_AuctionHouse.IsThrottledMessageSystemReady",
    "C_AuctionHouse.GetNumCommoditySearchResults", "C_AuctionHouse.GetCommoditySearchResultInfo",
    "C_AuctionHouse.GetNumItemSearchResults", "C_AuctionHouse.GetItemSearchResultInfo",
    "C_AuctionHouse.ReplicateItems", "C_AuctionHouse.GetNumReplicateItems",
    "C_AuctionHouse.GetReplicateItemInfo", "C_AuctionHouse.CalculateCommodityDeposit",
    "C_AuctionHouse.CalculateItemDeposit",
    "C_TradeSkillUI.GetRecipeInfo", "C_TradeSkillUI.GetRecipeSchematic",
    "C_TradeSkillUI.GetAllRecipeIDs", "C_TradeSkillUI.GetBaseProfessionInfo",
    "GetTradeSkillInfo", "GetTradeSkillSelectionIndex", "GetTradeSkillRecipeLink",
    "GetTradeSkillNumReagents", "GetTradeSkillReagentInfo", "GetTradeSkillNumMade",
    "C_Item.GetItemInfo", "C_Item.RequestLoadItemDataByID", "C_Timer.NewTicker",
    "GetCoinTextureString", "issecretvalue", "Enum.AuctionHouseSortOrder",
    "Enum.TradeskillRelativeDifficulty", "Enum.CraftingReagentType",
    "ProfessionsFrame", "TradeSkillFrame", "AuctionHouseFrame", "AuctionFrame",
}

cmds.api = function()
    for _, path in ipairs(API) do out(path, "->", type(resolve(path))) end
    dumpTable("Enum.TradeskillRelativeDifficulty", resolve("Enum.TradeskillRelativeDifficulty"))
    dumpTable("Enum.CraftingReagentType", resolve("Enum.CraftingReagentType"))
end

cmds.locale = function()
    out("GetLocale:", try(GetLocale))
    out("GetBuildInfo:", try(GetBuildInfo))
    out("coins 123456 ->", try(GetCoinTextureString, 123456))
end

cmds.item = function(arg)
    local id = tonumber(arg)
    if not id then out("usage: /cpp item <itemID>   (e.g. 2772 Iron Ore)"); return end
    out("GetItemInfo(name,link,quality,ilvl,minLevel,type,subtype,stack,equipLoc,texture,sellPrice,classID,subclassID,bindType):")
    out(try(C_Item.GetItemInfo, id))
    out("RequestLoadItemDataByID:", try(C_Item.RequestLoadItemDataByID, id))
end

cmds.deposit = function(arg)
    local id = tonumber(arg)
    if not id then out("usage: /cpp deposit <itemID>"); return end
    out("commodity deposit (item,qty=1,duration=2):", try(C_AuctionHouse.CalculateCommodityDeposit, id, 2, 1))
end

cmds.search = function(arg)
    local id = tonumber(arg)
    if not id then out("usage: /cpp search <itemID>   (auction house must be open)"); return end
    local ah = C_AuctionHouse
    out("throttle ready:", try(ah.IsThrottledMessageSystemReady))
    local okKey, key = pcall(ah.MakeItemKey, id)
    if not okKey then out("MakeItemKey ERR:", key); return end
    searchStart = GetTime()
    local sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
    out("SendSearchQuery:", try(ah.SendSearchQuery, key, sorts, true))
end

cmds.replicate = function()
    out("ReplicateItems:", try(C_AuctionHouse.ReplicateItems))
    searchStart = GetTime()
end

local function dumpRecipe(recipeID)
    local info = C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(recipeID)
    if info then
        out("info: name", info.name, "learned", info.learned, "relativeDifficulty", info.relativeDifficulty,
            "recipeID", info.recipeID)
    else
        out("GetRecipeInfo returned nothing")
    end
    local s = C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic and C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
    if not s then out("GetRecipeSchematic returned nothing"); return end
    out("schematic: outputItemID", s.outputItemID, "quantityMin", s.quantityMin, "quantityMax", s.quantityMax)
    for i, slot in ipairs(s.reagentSlotSchematics or {}) do
        local first = slot.reagents and slot.reagents[1]
        out("slot", i, "reagentType", slot.reagentType, "quantityRequired", slot.quantityRequired,
            "options", slot.reagents and #slot.reagents or 0, "firstItemID", first and first.itemID,
            "firstCurrencyID", first and first.currencyID)
    end
end

cmds.trade = function()
    out("ProfessionsFrame:", type(ProfessionsFrame), "shown:", ProfessionsFrame and ProfessionsFrame:IsShown())
    out("TradeSkillFrame:", type(TradeSkillFrame), "shown:", TradeSkillFrame and TradeSkillFrame:IsShown())
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    local form = page and page.SchematicForm
    out("CraftingPage:", type(page), "SchematicForm:", type(form),
        "form.GetRecipeInfo:", type(form and form.GetRecipeInfo))
    local info = form and form.GetRecipeInfo and form:GetRecipeInfo()
    local recipeID = info and info.recipeID
    out("strategy A selected recipeID:", recipeID)
    if recipeID then dumpRecipe(recipeID) end
    if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
        out("GetAllRecipeIDs count:", #C_TradeSkillUI.GetAllRecipeIDs())
    end
    local idx = try(GetTradeSkillSelectionIndex)
    out("strategy B selection index:", idx)
    if tonumber(idx) then
        out("B GetTradeSkillInfo:", try(GetTradeSkillInfo, tonumber(idx)))
        out("B recipe link:", try(GetTradeSkillRecipeLink, tonumber(idx)))
        out("B numMade:", try(GetTradeSkillNumMade, tonumber(idx)))
        out("B numReagents:", try(GetTradeSkillNumReagents, tonumber(idx)))
    end
end

local frame = CreateFrame("Frame")
local EVENTS = {
    "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
    "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
    "REPLICATE_ITEM_LIST_UPDATE", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE",
    "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "ITEM_DATA_LOAD_RESULT",
}
for _, e in ipairs(EVENTS) do
    if not pcall(frame.RegisterEvent, frame, e) then out("event rejected by client:", e) end
end

local function latency()
    return searchStart and string.format("+%.2fs", GetTime() - searchStart) or ""
end

frame:SetScript("OnEvent", function(_, event, a1)
    if event == "ITEM_DATA_LOAD_RESULT" then return end
    out("EVENT", event, latency(), "arg1:", a1)
    local ah = C_AuctionHouse
    if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        local n = try(ah.GetNumCommoditySearchResults, a1)
        out("commodity results:", n)
        for i = 1, math.min(3, tonumber(n) or 0) do
            local info = ah.GetCommoditySearchResultInfo(a1, i)
            if info then out(" #" .. i, "unitPrice", info.unitPrice, "quantity", info.quantity) end
        end
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        local n = try(ah.GetNumItemSearchResults, a1)
        out("item results:", n, "itemKey.itemID:", a1 and a1.itemID)
        for i = 1, math.min(3, tonumber(n) or 0) do
            local info = ah.GetItemSearchResultInfo(a1, i)
            if info then out(" #" .. i, "buyoutAmount", info.buyoutAmount, "quantity", info.quantity,
                "bidAmount", info.bidAmount) end
        end
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        local n = tonumber(ah.GetNumReplicateItems()) or 0
        out("replicate rows:", n)
        if n > 0 then
            out("row1 (name,texture,count,quality,usable,level,levelType,minBid,minIncr,buyout,bid,highBidder,bidderName,owner,ownerName,saleStatus,itemID,hasAll):")
            out(try(ah.GetReplicateItemInfo, 1))
        end
        local shown = 0
        for i = 1, math.min(n, 5000) do
            local _, _, count, _, _, _, _, minBid, _, buyout, _, _, _, _, _, _, itemID = ah.GetReplicateItemInfo(i)
            if not isSecret(count) and count and count > 1 then
                out(" stack row", i, "itemID", itemID, "count", count, "minBid", minBid, "buyout", buyout)
                shown = shown + 1
                if shown >= 3 then break end
            end
        end
    end
end)

SLASH_CPP1 = "/cpp"
SlashCmdList.CPP = function(msg)
    local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)$")
    local fn = cmds[cmd]
    if fn then
        out("== " .. cmd .. " " .. arg)
        fn(arg)
    else
        out("commands: api | locale | item <id> | deposit <id> | search <id> | replicate | trade")
    end
end
out("loaded. /cpp for commands. Enable Lua errors: /console scriptErrors 1")
```

- [ ] **Step 3: Create the findings template**

```markdown file=docs/probe-findings.md
# Probe findings (WoW: Forever beta)

Filled in by hand after running `/cpp` commands in the game (Task 2). Build: ____ (from `/cpp locale`). Date: ____.
Status marks: ✅ measured in game · ⚠️ not measured · ❌ unusable.

## F1. Search type for reagents (`/cpp search 2772`, then `/cpp search <a weapon/armor itemID>`)
- Event received for a reagent: `COMMODITY_SEARCH_RESULTS_UPDATED` / `ITEM_SEARCH_RESULTS_UPDATED` (circle one) — ____
- Event received for a piece of gear: ____
- Fields on a result: ____ (commodity: `unitPrice`, `quantity`; item: `buyoutAmount`, `quantity`)
- Latency from query to event: ____ s. Zero-result search still fires the event: yes / no.

## F2. Replicate rows (`/cpp replicate`, once per 15 min)
- Row layout matches (name, texture, count, quality, usable, level, levelType, minBid, minIncrement, buyout, bid, highBidder, bidderFullName, owner, ownerFullName, saleStatus, itemID, hasAll): yes / no — ____
- For a stack row (count > 1): is `buyout` the **whole stack** or **per unit**? ____  → sets `AH.PER_UNIT_REPLICATE` in Task 13 (false = whole stack).
- Any `<SECRET>` fields: ____

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
- Deposit reported by `/cpp deposit <id>` for a 2 (24 h) listing: ____
- Real commission: list an item for a known buyout (for example 100g), buy it with another character or wait for the sale, compare the mailed amount: ____ % → sets `DB.DEFAULTS.cut`.

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
```

- [ ] **Step 4: Install the probe in the game client (user action)**

```bash
ln -s "$PWD/probe/CraftProfitProbe" "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/CraftProfitProbe"
```

(Adjust the game path if it differs.) Restart the client. In game: `/console scriptErrors 1`, then `/cpp`.
Expected: a `[CPP 0.1.0] loaded.` line. Any other version number means the symlink points at a stale copy.

- [ ] **Step 5: Run the probes in game (user action) and paste the output into the conversation**

On the blacksmith, in this order:
1. `/cpp api`, `/cpp locale`, `/cpp item 2772`
2. Open the blacksmithing window, select an orange recipe, `/cpp trade`; repeat for a yellow, green and grey recipe
3. At the auction house: `/cpp search 2772` (a reagent), `/cpp search <itemID of any weapon or armor>`, `/cpp deposit 2772`
4. `/cpp replicate` (only once; Blizzard allows one full scan per 15 minutes)

- [ ] **Step 6: Fill `docs/probe-findings.md` from the pasted output and commit**

Replace every `____` with the measured value. If a probe command printed `MISSING` or `ERR`, record that in the matching field: it is a finding. Do not guess any value that was not printed.

```bash
git add probe docs/probe-findings.md
git commit -m "docs: add in-game probe addon and recorded findings"
```

---

### Task 3: `Util` and `Format` (pure helpers)

**Files:**
- Create: `CraftProfit/Util.lua`, `CraftProfit/Format.lua`
- Test: `tests/test_util.lua`, `tests/test_format.lua`

**Interfaces:**
- Produces:
  - `Util.isFinite(n) -> boolean` (false for NaN, ±inf, non-numbers)
  - `Util.isCopper(n) -> boolean` (finite and `>= 0`)
  - `Util.count(n) -> integer|nil` (finite, `>= 1`, floored; else nil)
  - `Util.id(n) -> integer|nil` (finite positive integer exactly; else nil)
  - `Util.clamp(n, lo, hi) -> number`
  - `Util.round(n) -> integer` (halves away from zero)
  - `Format.MAX_COPPER`, `Format.money(copper, coinFn) -> string` (`"?"` for invalid, `"-"` prefix when negative), `Format.age(seconds) -> n, unit|nil` where unit is `"sec"|"min"|"hour"|"day"`

- [ ] **Step 1: Write the failing tests**

```lua file=tests/test_util.lua
local H = ...

H.test("isFinite rejects NaN, infinities and non-numbers", function()
    local ns = H.newNS("Util")
    H.truthy(ns.Util.isFinite(0))
    H.truthy(ns.Util.isFinite(-5.5))
    H.falsy(ns.Util.isFinite(0 / 0))
    H.falsy(ns.Util.isFinite(1 / 0))
    H.falsy(ns.Util.isFinite(-1 / 0))
    H.falsy(ns.Util.isFinite("1"))
    H.falsy(ns.Util.isFinite(nil))
    H.falsy(ns.Util.isFinite({}))
end)

H.test("isCopper accepts zero and positives only", function()
    local ns = H.newNS("Util")
    H.truthy(ns.Util.isCopper(0))
    H.truthy(ns.Util.isCopper(12345))
    H.falsy(ns.Util.isCopper(-1))
    H.falsy(ns.Util.isCopper(0 / 0))
    H.falsy(ns.Util.isCopper(1 / 0))
    H.falsy(ns.Util.isCopper(nil))
end)

H.test("count floors and rejects below one", function()
    local ns = H.newNS("Util")
    H.eq(ns.Util.count(3), 3)
    H.eq(ns.Util.count(2.9), 2)
    H.eq(ns.Util.count(0), nil)
    H.eq(ns.Util.count(0.5), nil)
    H.eq(ns.Util.count(-4), nil)
    H.eq(ns.Util.count(0 / 0), nil)
    H.eq(ns.Util.count(1 / 0), nil)
    H.eq(ns.Util.count("3"), nil)
end)

H.test("id accepts only exact positive integers", function()
    local ns = H.newNS("Util")
    H.eq(ns.Util.id(7), 7)
    H.eq(ns.Util.id(7.5), nil)
    H.eq(ns.Util.id(0), nil)
    H.eq(ns.Util.id(-1), nil)
    H.eq(ns.Util.id(0 / 0), nil)
    H.eq(ns.Util.id(nil), nil)
end)

H.test("clamp bounds a value", function()
    local ns = H.newNS("Util")
    H.eq(ns.Util.clamp(5, 0, 10), 5)
    H.eq(ns.Util.clamp(-5, 0, 10), 0)
    H.eq(ns.Util.clamp(50, 0, 10), 10)
end)

H.test("round goes half away from zero", function()
    local ns = H.newNS("Util")
    H.eq(ns.Util.round(2.4), 2)
    H.eq(ns.Util.round(2.5), 3)
    H.eq(ns.Util.round(-2.4), -2)
    H.eq(ns.Util.round(-2.5), -3)
    H.eq(ns.Util.round(0), 0)
end)
```

```lua file=tests/test_format.lua
local H = ...

local function load() return H.newNS("Util", "Format") end

H.test("money prints gold, silver and copper", function()
    local ns = load()
    H.eq(ns.Format.money(123456), "12g 34s 56c")
    H.eq(ns.Format.money(10000), "1g")
    H.eq(ns.Format.money(150), "1s 50c")
    H.eq(ns.Format.money(0), "0c")
end)

H.test("money shows ? for anything that is not a finite number", function()
    local ns = load()
    H.eq(ns.Format.money(nil), "?")
    H.eq(ns.Format.money(0 / 0), "?")
    H.eq(ns.Format.money(1 / 0), "?")
    H.eq(ns.Format.money("12"), "?")
end)

H.test("money prefixes negatives and never prints -0", function()
    local ns = load()
    H.eq(ns.Format.money(-150), "-1s 50c")
    H.eq(ns.Format.money(-0.4), "0c")
end)

H.test("money rounds to the nearest copper and clamps huge values", function()
    local ns = load()
    H.eq(ns.Format.money(149.5), "1s 50c")
    H.eq(ns.Format.money(1e30), ns.Format.money(ns.Format.MAX_COPPER))
end)

H.test("money delegates to the coin function when given one", function()
    local ns = load()
    local seen
    local text = ns.Format.money(-1234, function(c) seen = c; return "<" .. c .. ">" end)
    H.eq(seen, 1234)
    H.eq(text, "-<1234>")
end)

H.test("age picks the largest unit and rejects bad input", function()
    local ns = load()
    H.eq({ ns.Format.age(5) }, { 5, "sec" })
    H.eq({ ns.Format.age(59.9) }, { 59, "sec" })
    H.eq({ ns.Format.age(60) }, { 1, "min" })
    H.eq({ ns.Format.age(3600) }, { 1, "hour" })
    H.eq({ ns.Format.age(172800) }, { 2, "day" })
    H.eq({ ns.Format.age(-1) }, {})
    H.eq({ ns.Format.age(0 / 0) }, {})
    H.eq({ ns.Format.age(nil) }, {})
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `luajit tests/run.lua`
Expected: FAIL for both files (cannot open `CraftProfit/Util.lua`).

- [ ] **Step 3: Implement `Util`**

```lua file=CraftProfit/Util.lua
-- Number helpers shared by the pure modules. Pure Lua, no WoW API.
local _, ns = ...

local Util = {}
ns.Util = Util

-- NaN is the only value that differs from itself; math.huge covers +/-inf.
-- Never rely on an ordering comparison to detect NaN.
function Util.isFinite(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- A usable copper amount: finite and not negative.
function Util.isCopper(n)
    return Util.isFinite(n) and n >= 0
end

-- A quantity: finite and at least 1, floored. Anything else gives nil.
function Util.count(n)
    if not Util.isFinite(n) or n < 1 then return nil end
    return math.floor(n)
end

-- An identifier: an exact positive integer. Anything else gives nil.
function Util.id(n)
    if Util.count(n) == n then return n end
    return nil
end

function Util.clamp(n, lo, hi)
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

-- Round to the nearest whole number, halves away from zero.
function Util.round(n)
    if n >= 0 then return math.floor(n + 0.5) end
    return -math.floor(-n + 0.5)
end
```

- [ ] **Step 4: Implement `Format`**

```lua file=CraftProfit/Format.lua
-- Display helpers. Pure Lua, no WoW API.
local _, ns = ...
local Util = ns.Util

local Format = {}
ns.Format = Format

-- WoW's gold cap is 99,999,999g = 1e12 copper; stay above it, below the point
-- where tostring switches to exponent notation.
Format.MAX_COPPER = 1e13

-- "12g 3s 4c": fallback for tests and chat. The window passes
-- GetCoinTextureString instead, which draws coin icons in any language.
local function plainCoins(copper)
    local g = math.floor(copper / 10000)
    local s = math.floor(copper % 10000 / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = string.format("%dg", g) end
    if s > 0 then parts[#parts + 1] = string.format("%ds", s) end
    if c > 0 or #parts == 0 then parts[#parts + 1] = string.format("%dc", c) end
    return table.concat(parts, " ")
end

-- Unknown or invalid amounts give "?", never "0".
function Format.money(copper, coinFn)
    if not Util.isFinite(copper) then return "?" end
    local whole = Util.round(Util.clamp(math.abs(copper), 0, Format.MAX_COPPER))
    local sign = (copper < 0 and whole > 0) and "-" or ""
    local text
    if coinFn then text = coinFn(whole) else text = plainCoins(whole) end
    return sign .. text
end

-- Splits an age in seconds into a number and a unit name; the caller localizes
-- the unit. Returns nothing for an invalid or negative age.
function Format.age(seconds)
    if not Util.isFinite(seconds) or seconds < 0 then return nil end
    if seconds < 60 then return math.floor(seconds), "sec" end
    if seconds < 3600 then return math.floor(seconds / 60), "min" end
    if seconds < 86400 then return math.floor(seconds / 3600), "hour" end
    return math.floor(seconds / 86400), "day"
end
```

- [ ] **Step 5: Run the tests and luacheck**

Run: `sh tests/check.sh`
Expected: all tests pass, luacheck `0 warnings / 0 errors`.

- [ ] **Step 6: Commit**

```bash
git add CraftProfit/Util.lua CraftProfit/Format.lua tests/test_util.lua tests/test_format.lua
git commit -m "feat: add Util and Format pure helpers"
```

---

### Task 4: `Core` (profit calculations)

**Files:**
- Create: `CraftProfit/Core.lua`
- Test: `tests/test_core.lua`

**Interfaces:**
- Consumes: `Util.isFinite`, `Util.isCopper`, `Util.count`, `Util.id`, `Util.round`
- Produces (all pure; money in copper; `priceOf(itemID) -> unitCopper|nil`):
  - `Core.sumCost(reagents, priceOf) -> total` or `-> nil, missingItemIDs` — `reagents = { {itemID=, qty=}, ... }`
  - `Core.netSale(unit, qty, cut) -> copper|nil` — `qty` may be fractional (average yield)
  - `Core.vendorValue(sellPrice, qty) -> copper|nil` — nil when `sellPrice` is 0 or invalid
  - `Core.disenchantValue(entries, priceOf, cut) -> copper` or `-> nil, missingItemIDs` — `entries = { {itemID=, chance=0..1, min=, max=}, ... }`, net of `cut`
  - `Core.bestOption(options) -> key|nil, value|nil, incomplete` — `options[key] = {status="ok"|"unknown"|"na", value=copper}`, keys in `Core.OPTION_ORDER = {"ah","vendor","disenchant"}` (ties go to the earlier key)
  - `Core.costPerPoint(cost, recovered, chance) -> copper|nil`

- [ ] **Step 1: Write the failing tests**

```lua file=tests/test_core.lua
local H = ...

local function load() return H.newNS("Util", "Core") end

local function prices(map)
    return function(itemID) return map[itemID] end
end

H.test("sumCost adds quantity times unit price", function()
    local ns = load()
    local reagents = { { itemID = 1, qty = 2 }, { itemID = 2, qty = 3 } }
    H.eq({ ns.Core.sumCost(reagents, prices({ [1] = 100, [2] = 50 })) }, { 350 })
end)

H.test("sumCost reports every unpriced reagent and no total", function()
    local ns = load()
    local reagents = { { itemID = 1, qty = 2 }, { itemID = 2, qty = 3 }, { itemID = 3, qty = 1 } }
    H.eq({ ns.Core.sumCost(reagents, prices({ [1] = 100 })) }, { nil, { 2, 3 } })
end)

H.test("sumCost treats NaN, negative, infinite and non-number prices as unknown", function()
    local ns = load()
    for _, bad in ipairs({ 0 / 0, -5, 1 / 0, "12", true }) do
        local total, missing = ns.Core.sumCost({ { itemID = 9, qty = 1 } }, prices({ [9] = bad }))
        H.eq(total, nil)
        H.eq(missing, { 9 })
    end
end)

H.test("sumCost treats an invalid quantity as unknown, never as free", function()
    local ns = load()
    local total, missing = ns.Core.sumCost({ { itemID = 1, qty = 0 } }, prices({ [1] = 100 }))
    H.eq(total, nil)
    H.eq(missing, { 1 })
end)

H.test("netSale removes the commission and rounds to the copper", function()
    local ns = load()
    H.eq(ns.Core.netSale(1000, 1, 0.05), 950)
    H.eq(ns.Core.netSale(1000, 2, 0.05), 1900)
    H.eq(ns.Core.netSale(1000, 1.5, 0.05), 1425)
    H.eq(ns.Core.netSale(1000, 1, 0), 1000)
end)

H.test("netSale gives nil for invalid price, quantity or commission", function()
    local ns = load()
    H.eq(ns.Core.netSale(nil, 1, 0.05), nil)
    H.eq(ns.Core.netSale(0 / 0, 1, 0.05), nil)
    H.eq(ns.Core.netSale(-10, 1, 0.05), nil)
    H.eq(ns.Core.netSale(1000, 0, 0.05), nil)
    H.eq(ns.Core.netSale(1000, 1, 1), nil)
    H.eq(ns.Core.netSale(1000, 1, -0.1), nil)
    H.eq(ns.Core.netSale(1000, 1, 0 / 0), nil)
end)

H.test("vendorValue multiplies the sell price and rejects 0 and invalid", function()
    local ns = load()
    H.eq(ns.Core.vendorValue(100, 2), 200)
    H.eq(ns.Core.vendorValue(100, 1.5), 150)
    H.eq(ns.Core.vendorValue(0, 1), nil)
    H.eq(ns.Core.vendorValue(nil, 1), nil)
    H.eq(ns.Core.vendorValue(0 / 0, 1), nil)
end)

local DE = {
    { itemID = 10, chance = 0.8, min = 1, max = 3 },
    { itemID = 11, chance = 0.2, min = 1, max = 1 },
}

H.test("disenchantValue is the expected value of the results", function()
    local ns = load()
    -- 0.8 * 2 * 100 + 0.2 * 1 * 1000 = 360
    H.eq({ ns.Core.disenchantValue(DE, prices({ [10] = 100, [11] = 1000 }), 0) }, { 360 })
end)

H.test("disenchantValue is net of the AH commission", function()
    local ns = load()
    H.eq({ ns.Core.disenchantValue(DE, prices({ [10] = 100, [11] = 1000 }), 0.05) }, { 342 })
end)

H.test("disenchantValue reports unpriced results instead of undercounting", function()
    local ns = load()
    H.eq({ ns.Core.disenchantValue(DE, prices({ [10] = 100 }), 0.05) }, { nil, { 11 } })
end)

H.test("disenchantValue gives nil for missing, empty or corrupt data", function()
    local ns = load()
    local p = prices({ [10] = 100 })
    H.eq({ ns.Core.disenchantValue(nil, p, 0.05) }, { nil, {} })
    H.eq({ ns.Core.disenchantValue({}, p, 0.05) }, { nil, {} })
    H.eq({ ns.Core.disenchantValue({ { itemID = 10, chance = 2, min = 1, max = 1 } }, p, 0.05) }, { nil, {} })
    H.eq({ ns.Core.disenchantValue({ { itemID = 10, chance = 0.5, min = 3, max = 1 } }, p, 0.05) }, { nil, {} })
    H.eq({ ns.Core.disenchantValue(DE, p, 1) }, { nil, {} })
end)

H.test("bestOption picks the highest known value, ties go to the earlier key", function()
    local ns = load()
    local key, value, incomplete = ns.Core.bestOption({
        ah = { status = "ok", value = 100 },
        vendor = { status = "ok", value = 100 },
        disenchant = { status = "ok", value = 50 },
    })
    H.eq({ key, value, incomplete }, { "ah", 100, false })
end)

H.test("bestOption flags unknown options as incomplete but still returns the best known", function()
    local ns = load()
    local key, value, incomplete = ns.Core.bestOption({
        ah = { status = "unknown" },
        vendor = { status = "ok", value = 30 },
        disenchant = { status = "na" },
    })
    H.eq({ key, value, incomplete }, { "vendor", 30, true })
end)

H.test("bestOption with nothing sellable returns nothing", function()
    local ns = load()
    H.eq({ ns.Core.bestOption({ ah = { status = "na" }, vendor = { status = "na" } }) }, { nil, nil, false })
    H.eq({ ns.Core.bestOption({}) }, { nil, nil, false })
end)

H.test("bestOption ignores a NaN value", function()
    local ns = load()
    local key = ns.Core.bestOption({ ah = { status = "ok", value = 0 / 0 }, vendor = { status = "ok", value = 5 } })
    H.eq(key, "vendor")
end)

H.test("costPerPoint divides the net cost by the skill-up chance", function()
    local ns = load()
    H.eq(ns.Core.costPerPoint(100, 40, 0.75), 80)
    H.eq(ns.Core.costPerPoint(100, nil, 0.5), 200)
    H.eq(ns.Core.costPerPoint(100, 160, 1), -60)
end)

H.test("costPerPoint is nil when no skill point can be earned", function()
    local ns = load()
    H.eq(ns.Core.costPerPoint(100, 0, 0), nil)
    H.eq(ns.Core.costPerPoint(100, 0, 1.5), nil)
    H.eq(ns.Core.costPerPoint(100, 0, nil), nil)
    H.eq(ns.Core.costPerPoint(0 / 0, 0, 1), nil)
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `luajit tests/run.lua`
Expected: FAIL in `tests/test_core.lua` (cannot open `CraftProfit/Core.lua`).

- [ ] **Step 3: Implement `Core`**

```lua file=CraftProfit/Core.lua
-- Profit calculations. Pure Lua, no WoW API. Money is copper.
-- Convention: an unknown input gives nil (never 0) so callers can show "?".
local _, ns = ...
local Util = ns.Util

local Core = {}
ns.Core = Core

Core.OPTION_ORDER = { "ah", "vendor", "disenchant" }

local function validCut(cut)
    return Util.isFinite(cut) and cut >= 0 and cut < 1
end

-- A crafted quantity may be fractional (average of a min..max yield).
local function validQty(qty)
    return Util.isFinite(qty) and qty >= 1
end

-- Total cost of reagents { {itemID=, qty=}, ... }. priceOf(itemID) returns a
-- unit price or nil. Returns total when every price is usable, else
-- nil plus the list of unpriced itemIDs: a missing price must never look free.
function Core.sumCost(reagents, priceOf)
    local total, missing = 0, {}
    for _, r in ipairs(reagents) do
        local unit = priceOf(r.itemID)
        local qty = Util.count(r.qty)
        if not Util.isCopper(unit) or not qty then
            missing[#missing + 1] = r.itemID
        else
            total = total + unit * qty
        end
    end
    if #missing > 0 then return nil, missing end
    return total
end

-- What an AH sale of qty items at a unit price really pays out.
function Core.netSale(unit, qty, cut)
    if not Util.isCopper(unit) or not validQty(qty) or not validCut(cut) then return nil end
    return Util.round(unit * qty * (1 - cut))
end

-- What a vendor pays. A sell price of 0 means the item cannot be sold.
function Core.vendorValue(sellPrice, qty)
    if not Util.isCopper(sellPrice) or sellPrice == 0 or not validQty(qty) then return nil end
    return Util.round(sellPrice * qty)
end

local function validEntry(e)
    return type(e) == "table" and Util.id(e.itemID) ~= nil
        and Util.isFinite(e.chance) and e.chance >= 0 and e.chance <= 1
        and Util.isFinite(e.min) and e.min >= 1
        and Util.isFinite(e.max) and e.max >= e.min
end

-- Expected AH value of one disenchant. entries = { {itemID=, chance=, min=, max=} }.
-- The results are sold on the AH, so the commission applies. Returns nil plus
-- the unpriced itemIDs when any result has no price; nil plus {} when the data
-- itself is missing or corrupt.
function Core.disenchantValue(entries, priceOf, cut)
    if type(entries) ~= "table" or #entries == 0 or not validCut(cut) then return nil, {} end
    for _, e in ipairs(entries) do
        if not validEntry(e) then return nil, {} end
    end
    local total, missing = 0, {}
    for _, e in ipairs(entries) do
        local unit = priceOf(e.itemID)
        if not Util.isCopper(unit) then
            missing[#missing + 1] = e.itemID
        else
            total = total + e.chance * (e.min + e.max) / 2 * unit
        end
    end
    if #missing > 0 then return nil, missing end
    return Util.round(total * (1 - cut))
end

-- options[key] = { status = "ok"|"unknown"|"na", value = copper }.
-- Returns the best "ok" key and value, and whether any option was "unknown"
-- (so the best known one may not be the true best).
function Core.bestOption(options)
    local bestKey, bestValue, incomplete = nil, nil, false
    for _, key in ipairs(Core.OPTION_ORDER) do
        local o = options[key]
        if o then
            if o.status == "unknown" then
                incomplete = true
            elseif o.status == "ok" and Util.isFinite(o.value) then
                if bestValue == nil or o.value > bestValue then
                    bestKey, bestValue = key, o.value
                end
            end
        end
    end
    return bestKey, bestValue, incomplete
end

-- Net cost of one skill point: (cost - what the result recovers) / chance.
-- Negative means the crafts pay for themselves. Nil when no point can be earned.
function Core.costPerPoint(cost, recovered, chance)
    if not Util.isFinite(cost) or not Util.isFinite(chance) or chance <= 0 or chance > 1 then
        return nil
    end
    if not Util.isFinite(recovered) then recovered = 0 end
    return Util.round((cost - recovered) / chance)
end
```

- [ ] **Step 4: Run the tests and luacheck**

Run: `sh tests/check.sh`
Expected: all tests pass, luacheck clean.

- [ ] **Step 5: Commit**

```bash
git add CraftProfit/Core.lua tests/test_core.lua
git commit -m "feat: add Core profit calculations"
```

---

### Task 5: `Data` (skill-up chances and disenchant tables)

**Files:**
- Create: `CraftProfit/Data/Skillup.lua`, `CraftProfit/Data/Disenchant.lua`
- Test: `tests/test_skillup.lua`, `tests/test_disenchant.lua`, `tests/test_disenchant_data.lua`

**Interfaces:**
- Consumes: `Util.isFinite`
- Produces:
  - `ns.Data.Skillup.CHANCE = {optimal=1, medium=0.75, easy=0.25, trivial=0}` (**estimates**, shown as such in the UI)
  - `Skillup.name(difficulty) -> "optimal"|"medium"|"easy"|"trivial"|nil` — accepts `0..3` (`Enum.TradeskillRelativeDifficulty`) or a case-insensitive name
  - `Skillup.chance(difficulty) -> number|nil`
  - `ns.Data.Disenchant`: `kindOf(classID) -> "armor"|"weapon"|nil`, `canDisenchant(itemID, quality, classID) -> boolean`, `lookup(kind, quality, ilvl[, brackets]) -> entries|nil` where `entries = { {itemID, chance, min, max}, ... }`, `D.brackets`, `D.excluded`

- [ ] **Step 1: Write the failing skill-up tests**

```lua file=tests/test_skillup.lua
local H = ...

local function load() return H.newNS("Util", "Data/Skillup") end

H.test("name accepts Enum numbers and strings in any case", function()
    local S = load().Data.Skillup
    H.eq(S.name(0), "optimal")
    H.eq(S.name(1), "medium")
    H.eq(S.name(2), "easy")
    H.eq(S.name(3), "trivial")
    H.eq(S.name("Optimal"), "optimal")
    H.eq(S.name("TRIVIAL"), "trivial")
end)

H.test("name rejects anything else", function()
    local S = load().Data.Skillup
    H.eq(S.name(4), nil)
    H.eq(S.name(-1), nil)
    H.eq(S.name(0 / 0), nil)
    H.eq(S.name("header"), nil)
    H.eq(S.name(nil), nil)
    H.eq(S.name({}), nil)
end)

H.test("chance maps a difficulty to its estimated probability", function()
    local S = load().Data.Skillup
    H.eq(S.chance("optimal"), 1)
    H.eq(S.chance(1), 0.75)
    H.eq(S.chance("easy"), 0.25)
    H.eq(S.chance(3), 0)
    H.eq(S.chance(nil), nil)
end)
```

- [ ] **Step 2: Write the failing disenchant logic tests**

```lua file=tests/test_disenchant.lua
local H = ...

local function load() return H.newNS("Util", "Data/Disenchant").Data.Disenchant end

local FIXTURE = {
    { kind = "armor", quality = 2, minIlvl = 10, maxIlvl = 20,
      results = { { itemID = 1, chance = 1, min = 1, max = 2 } } },
    { kind = "armor", quality = 2, minIlvl = 21, maxIlvl = 30,
      results = { { itemID = 2, chance = 1, min = 1, max = 2 } } },
    { kind = "weapon", quality = 3, minIlvl = 10, maxIlvl = 20,
      results = { { itemID = 3, chance = 1, min = 1, max = 1 } } },
}

H.test("kindOf maps item classes", function()
    local D = load()
    H.eq(D.kindOf(2), "weapon")
    H.eq(D.kindOf(4), "armor")
    H.eq(D.kindOf(0), nil)
    H.eq(D.kindOf(nil), nil)
end)

H.test("canDisenchant needs weapon or armor of uncommon to epic quality", function()
    local D = load()
    H.truthy(D.canDisenchant(100, 2, 4))
    H.truthy(D.canDisenchant(100, 4, 2))
    H.falsy(D.canDisenchant(100, 1, 4))
    H.falsy(D.canDisenchant(100, 5, 4))
    H.falsy(D.canDisenchant(100, 2, 0))
    H.falsy(D.canDisenchant(100, nil, 4))
end)

H.test("canDisenchant honours the exclusion list", function()
    local D = load()
    D.excluded[555] = true
    H.falsy(D.canDisenchant(555, 2, 4))
    D.excluded[555] = nil
end)

H.test("lookup matches kind, quality and an inclusive item level range", function()
    local D = load()
    H.eq(D.lookup("armor", 2, 10, FIXTURE)[1].itemID, 1)
    H.eq(D.lookup("armor", 2, 20, FIXTURE)[1].itemID, 1)
    H.eq(D.lookup("armor", 2, 21, FIXTURE)[1].itemID, 2)
    H.eq(D.lookup("weapon", 3, 15, FIXTURE)[1].itemID, 3)
end)

H.test("lookup returns nil outside every bracket", function()
    local D = load()
    H.eq(D.lookup("armor", 2, 9, FIXTURE), nil)
    H.eq(D.lookup("armor", 2, 31, FIXTURE), nil)
    H.eq(D.lookup("armor", 3, 15, FIXTURE), nil)
    H.eq(D.lookup("weapon", 2, 15, FIXTURE), nil)
    H.eq(D.lookup(nil, 2, 15, FIXTURE), nil)
end)

H.test("lookup returns nil for a NaN or missing item level", function()
    local D = load()
    H.eq(D.lookup("armor", 2, 0 / 0, FIXTURE), nil)
    H.eq(D.lookup("armor", 2, nil, FIXTURE), nil)
end)
```

- [ ] **Step 3: Write the failing data-validation tests (they check the real table)**

```lua file=tests/test_disenchant_data.lua
local H = ...

local function brackets() return H.newNS("Util", "Data/Disenchant").Data.Disenchant.brackets end

local KINDS = { armor = true, weapon = true }

H.test("every disenchant bracket is well formed", function()
    for i, b in ipairs(brackets()) do
        local where = "bracket " .. i
        H.truthy(KINDS[b.kind] or error(where .. ": bad kind " .. tostring(b.kind)))
        H.truthy((b.quality == 2 or b.quality == 3 or b.quality == 4) or error(where .. ": bad quality"))
        H.truthy((b.minIlvl >= 1 and b.maxIlvl >= b.minIlvl) or error(where .. ": bad item level range"))
        H.truthy((#b.results > 0) or error(where .. ": no results"))
        local sum, seen = 0, {}
        for _, r in ipairs(b.results) do
            H.truthy((r.itemID == math.floor(r.itemID) and r.itemID > 0) or error(where .. ": bad itemID"))
            if seen[r.itemID] then error(where .. ": duplicate itemID " .. r.itemID) end
            seen[r.itemID] = true
            H.truthy((r.chance > 0 and r.chance <= 1) or error(where .. ": bad chance"))
            H.truthy((r.min >= 1 and r.max >= r.min) or error(where .. ": bad quantity"))
            sum = sum + r.chance
        end
        -- One disenchant yields exactly one kind of result: chances sum to 100%.
        H.truthy(math.abs(sum - 1) <= 0.01 or error(where .. ": chances sum to " .. sum))
    end
end)

H.test("disenchant brackets never overlap for a given kind and quality", function()
    local list = brackets()
    for i = 1, #list do
        for j = i + 1, #list do
            local a, b = list[i], list[j]
            if a.kind == b.kind and a.quality == b.quality then
                local overlap = a.minIlvl <= b.maxIlvl and b.minIlvl <= a.maxIlvl
                if overlap then error(string.format("brackets %d and %d overlap", i, j)) end
            end
        end
    end
end)

H.test("disenchant data covers armor and weapons of uncommon, rare and epic quality", function()
    local have = {}
    for _, b in ipairs(brackets()) do have[b.kind .. b.quality] = true end
    for kind in pairs(KINDS) do
        for quality = 2, 4 do
            H.truthy(have[kind .. quality] or error("no data for " .. kind .. " quality " .. quality))
        end
    end
end)
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `luajit tests/run.lua`
Expected: FAIL in the three new files (cannot open the Data modules).

- [ ] **Step 5: Implement `Data/Skillup`**

```lua file=CraftProfit/Data/Skillup.lua
-- Probability that crafting a recipe raises the skill, by relative difficulty.
-- Pure Lua, no WoW API.
local _, ns = ...

ns.Data = ns.Data or {}
local Skillup = {}
ns.Data.Skillup = Skillup

-- ESTIMATES, not measured values: the UI labels results built on them as
-- estimates. Replace with measured values once known.
Skillup.CHANCE = { optimal = 1, medium = 0.75, easy = 0.25, trivial = 0 }

-- Enum.TradeskillRelativeDifficulty on the Mainline API (confirm in
-- docs/probe-findings.md, F3/F7).
local BY_NUMBER = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" }

-- Accepts an Enum number or a name; returns the canonical lowercase name or nil.
function Skillup.name(difficulty)
    if type(difficulty) == "string" then
        local lower = difficulty:lower()
        if Skillup.CHANCE[lower] ~= nil then return lower end
        return nil
    end
    if type(difficulty) == "number" then return BY_NUMBER[difficulty] end
    return nil
end

function Skillup.chance(difficulty)
    local name = Skillup.name(difficulty)
    if not name then return nil end
    return Skillup.CHANCE[name]
end
```

- [ ] **Step 6: Implement `Data/Disenchant` (logic, with an empty table for now)**

```lua file=CraftProfit/Data/Disenchant.lua
-- Disenchanting: which items qualify and what they yield. Pure Lua, no WoW API.
local _, ns = ...
local Util = ns.Util

ns.Data = ns.Data or {}
local D = {}
ns.Data.Disenchant = D

-- classID values returned by C_Item.GetItemInfo.
D.CLASS_WEAPON = 2
D.CLASS_ARMOR = 4
-- Quality 2 (uncommon) to 4 (epic).
D.MIN_QUALITY = 2
D.MAX_QUALITY = 4

-- Items that never disenchant although class and quality fit: [itemID] = true.
D.excluded = {}

-- One bracket per (kind, quality, item level range), ranges inclusive:
--   { kind = "armor", quality = 2, minIlvl = 1, maxIlvl = 1, results = {
--       { itemID = 1, chance = 0.5, min = 1, max = 2 }, ... } }
-- The numbers above are a FORMAT EXAMPLE only. Real rows are added in Task 5,
-- Step 8, from a cited source. Chances of one bracket sum to 1.
D.brackets = {}

function D.kindOf(classID)
    if classID == D.CLASS_WEAPON then return "weapon" end
    if classID == D.CLASS_ARMOR then return "armor" end
    return nil
end

function D.canDisenchant(itemID, quality, classID)
    if D.excluded[itemID] then return false end
    if not D.kindOf(classID) then return false end
    return type(quality) == "number" and quality >= D.MIN_QUALITY and quality <= D.MAX_QUALITY
end

-- Entries for an item, or nil when no bracket matches (shown as "?" by the UI).
function D.lookup(kind, quality, ilvl, brackets)
    brackets = brackets or D.brackets
    if not Util.isFinite(ilvl) then return nil end
    for _, b in ipairs(brackets) do
        if b.kind == kind and b.quality == quality and ilvl >= b.minIlvl and ilvl <= b.maxIlvl then
            return b.results
        end
    end
    return nil
end
```

- [ ] **Step 7: Run the tests**

Run: `luajit tests/run.lua`
Expected: `test_skillup` and `test_disenchant` pass. In `test_disenchant_data`, the two structural tests pass (empty table) and **"covers armor and weapons…" FAILS** with `no data for …`. That failure is the work item of Step 8.

- [ ] **Step 8: Fill `D.brackets` from a cited source**

Do not type numbers from memory. Fetch the Classic disenchanting tables (item level ranges, quality, armor versus weapon, and the result chances and quantities) from one primary source, for example the Wowpedia "Disenchanting" page or the Wowhead Classic disenchanting loot tables, and replace `D.brackets = {}` with the real rows. Rules:

- Put the source URL and the date fetched in a comment directly above `D.brackets`.
- Use item IDs, never names. Common Classic results (verify each ID against the source before using it): Strange Dust 10940, Soul Dust 11083, Vision Dust 11137, Dream Dust 11176, Illusion Dust 16204; Lesser/Greater Magic Essence 10938/10939; Lesser/Greater Astral Essence 10998/11082; Lesser/Greater Mystic Essence 11134/11135; Lesser/Greater Nether Essence 11174/11175; Small/Large Glimmering Shard 10978/11084; Small/Large Glowing Shard 11138/11139; Small/Large Radiant Shard 11177/11178; Small/Large Brilliant Shard 14343/14344; Nexus Crystal 20725.
- Chances are fractions (0.80, not 80). Where the source lists rounded percentages, the sum must still be within 0.01 of 1; fix the row, not the test.
- The Forever level cap is 60, so Classic tables apply to old items. Items new to Forever have no row: leave them out (the UI shows `?`).
- Add a comment `-- UNVERIFIED IN FOREVER` above the table until the rows are spot-checked in game (Task 17, checklist item "disenchant data").

Run: `luajit tests/run.lua`
Expected: all three disenchant test files pass.

- [ ] **Step 9: Run luacheck and commit**

Run: `sh tests/check.sh`
Expected: clean.

```bash
git add CraftProfit/Data tests/test_skillup.lua tests/test_disenchant.lua tests/test_disenchant_data.lua
git commit -m "feat: add skill-up and disenchant data modules"
```

---

### Task 6: `Locale` and the four language tables

**Files:**
- Create: `CraftProfit/Locale.lua`, `CraftProfit/Locales/enUS.lua`, `CraftProfit/Locales/frFR.lua`, `CraftProfit/Locales/esES.lua`, `CraftProfit/Locales/esMX.lua`
- Test: `tests/test_locale.lua`

**Interfaces:**
- Produces:
  - `ns.Locale.register(code, tbl)`, `ns.Locale.alias(code, target)`, `ns.Locale.select(code)`, `ns.Locale.current`
  - `ns.L`: table whose reads return the selected language's string, else the enUS string, else the key itself. Never raises.
  - Keys used by later tasks: `TITLE MATERIALS LINE_AH LINE_VENDOR LINE_DISENCHANT NAME_AH NAME_VENDOR NAME_DISENCHANT PER_POINT ESTIMATE VERDICT_BEST VERDICT_PARTIAL VERDICT_INCOMPLETE VERDICT_NONE NA UNKNOWN AGE AGE_NEVER AGE_SEC AGE_MIN AGE_HOUR AGE_DAY PIN UNPIN PINS_TITLE PINS_EMPTY PINS_FULL SEARCH_PRICES SEARCHING SEARCH_DONE SEARCH_PARTIAL SEARCH_NEED_AH SEARCH_CANCELLED SCAN SCAN_STARTED SCAN_DONE SCAN_COOLDOWN OPT_PER_POINT NO_RECIPE SLASH_HELP SELFTEST_OK SELFTEST_FAIL`

- [ ] **Step 1: Write the failing tests**

```lua file=tests/test_locale.lua
local H = ...

local function load()
    return H.newNS("Locale", "Locales/enUS", "Locales/frFR", "Locales/esES", "Locales/esMX")
end

-- Sorted list of the format specifiers in a string, e.g. "%d/%s" -> "%d,%s".
local function specifiers(s)
    local found = {}
    for spec in s:gmatch("%%[%-%d%.]*[sdfxX%%]") do found[#found + 1] = spec end
    table.sort(found)
    return table.concat(found, ",")
end

local function keys(tbl)
    local list = {}
    for k in pairs(tbl) do list[#list + 1] = k end
    table.sort(list)
    return list
end

H.test("select switches the language ns.L reads", function()
    local ns = load()
    ns.Locale.select("enUS")
    H.eq(ns.L.MATERIALS, "Materials")
    ns.Locale.select("frFR")
    H.eq(ns.L.MATERIALS, "Composants")
    ns.Locale.select("esES")
    H.eq(ns.L.MATERIALS, "Materiales")
end)

H.test("an unsupported client locale falls back to enUS", function()
    local ns = load()
    ns.Locale.select("deDE")
    H.eq(ns.Locale.current, "enUS")
    H.eq(ns.L.MATERIALS, "Materials")
    ns.Locale.select(nil)
    H.eq(ns.Locale.current, "enUS")
end)

H.test("esMX reuses the esES strings", function()
    local ns = load()
    ns.Locale.select("esMX")
    H.eq(ns.Locale.current, "esES")
    H.eq(ns.L.MATERIALS, "Materiales")
end)

H.test("a key missing from the selected language falls back to enUS, then to the key", function()
    local ns = load()
    ns.Locale.register("xxXX", { MATERIALS = "X" })
    ns.Locale.select("xxXX")
    H.eq(ns.L.MATERIALS, "X")
    H.eq(ns.L.NA, "n/a")
    H.eq(ns.L.NO_SUCH_KEY, "NO_SUCH_KEY")
    H.eq(ns.L[5], "5")
end)

H.test("frFR and esES define exactly the enUS keys", function()
    local ns = load()
    local reference = keys(ns.Locale.tables.enUS)
    H.truthy(#reference > 30)
    H.eq(keys(ns.Locale.tables.frFR), reference)
    H.eq(keys(ns.Locale.tables.esES), reference)
end)

H.test("every translation keeps the enUS format specifiers", function()
    local ns = load()
    for _, code in ipairs({ "frFR", "esES" }) do
        for key, text in pairs(ns.Locale.tables.enUS) do
            H.eq(specifiers(ns.Locale.tables[code][key]), specifiers(text))
        end
    end
end)

H.test("no translation is empty", function()
    local ns = load()
    for _, code in ipairs({ "enUS", "frFR", "esES" }) do
        for key, text in pairs(ns.Locale.tables[code]) do
            H.truthy(type(text) == "string" and text ~= "" or error(code .. "." .. key .. " is empty"))
        end
    end
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `luajit tests/run.lua`
Expected: FAIL in `tests/test_locale.lua` (cannot open `CraftProfit/Locale.lua`).

- [ ] **Step 3: Implement `Locale`**

```lua file=CraftProfit/Locale.lua
-- Language selection with fallback: selected language -> enUS -> the key.
-- Pure Lua, no WoW API (the caller passes GetLocale()).
local _, ns = ...

local Locale = { tables = {}, aliases = {}, current = "enUS" }
ns.Locale = Locale

function Locale.register(code, tbl)
    Locale.tables[code] = tbl
end

-- A locale that reuses another one's strings (esMX -> esES).
function Locale.alias(code, target)
    Locale.aliases[code] = target
end

-- Unknown or non-string codes select enUS.
function Locale.select(code)
    code = Locale.aliases[code] or code
    if type(code) ~= "string" or not Locale.tables[code] then code = "enUS" end
    Locale.current = code
end

local function lookup(key)
    local selected = Locale.tables[Locale.current]
    local text = selected and selected[key]
    if text == nil then
        local reference = Locale.tables.enUS
        text = reference and reference[key]
    end
    if text == nil then return tostring(key) end
    return text
end

ns.L = setmetatable({}, { __index = function(_, key) return lookup(key) end })
```

- [ ] **Step 4: Implement the four language files**

```lua file=CraftProfit/Locales/enUS.lua
local _, ns = ...

ns.Locale.register("enUS", {
    TITLE = "CraftProfit",
    MATERIALS = "Materials",
    LINE_AH = "Auction house (net)",
    LINE_VENDOR = "Vendor",
    LINE_DISENCHANT = "Disenchant (expected)",
    NAME_AH = "Auction house",
    NAME_VENDOR = "Vendor",
    NAME_DISENCHANT = "Disenchant",
    PER_POINT = "Cost per skill point",
    ESTIMATE = "estimate",
    VERDICT_BEST = "Best: %s",
    VERDICT_PARTIAL = "Best known: %s (prices missing)",
    VERDICT_INCOMPLETE = "Incomplete: prices missing",
    VERDICT_NONE = "No way to sell this item",
    NA = "n/a",
    UNKNOWN = "?",
    AGE = "Prices: %s ago",
    AGE_NEVER = "Prices: never scanned",
    AGE_SEC = "%ds",
    AGE_MIN = "%dm",
    AGE_HOUR = "%dh",
    AGE_DAY = "%dd",
    PIN = "Pin",
    UNPIN = "Unpin",
    PINS_TITLE = "Pinned recipes",
    PINS_EMPTY = "No pinned recipe yet",
    PINS_FULL = "Too many pinned recipes",
    SEARCH_PRICES = "Search prices",
    SEARCHING = "Searching %d/%d",
    SEARCH_DONE = "Prices updated",
    SEARCH_PARTIAL = "Prices updated, %d not found",
    SEARCH_NEED_AH = "Open the auction house first",
    SEARCH_CANCELLED = "Search cancelled",
    SCAN = "Scan AH",
    SCAN_STARTED = "Scanning the auction house...",
    SCAN_DONE = "Scan complete: %d items priced",
    SCAN_COOLDOWN = "Full scan available in %s",
    OPT_PER_POINT = "Show cost per skill point",
    NO_RECIPE = "Select a recipe",
    SLASH_HELP = "Commands: /cp show | hide | reset | scan | locale <code> | selftest",
    SELFTEST_OK = "Self-test passed (%d checks)",
    SELFTEST_FAIL = "Self-test FAILED: %s",
})
```

```lua file=CraftProfit/Locales/frFR.lua
local _, ns = ...

ns.Locale.register("frFR", {
    TITLE = "CraftProfit",
    MATERIALS = "Composants",
    LINE_AH = "Hôtel des ventes (net)",
    LINE_VENDOR = "Marchand",
    LINE_DISENCHANT = "Désenchantement (espéré)",
    NAME_AH = "Hôtel des ventes",
    NAME_VENDOR = "Marchand",
    NAME_DISENCHANT = "Désenchantement",
    PER_POINT = "Coût par point de compétence",
    ESTIMATE = "estimation",
    VERDICT_BEST = "Meilleur : %s",
    VERDICT_PARTIAL = "Meilleur connu : %s (prix manquants)",
    VERDICT_INCOMPLETE = "Incomplet : prix manquants",
    VERDICT_NONE = "Aucun moyen de revendre cet objet",
    NA = "n/d",
    UNKNOWN = "?",
    AGE = "Prix : il y a %s",
    AGE_NEVER = "Prix : jamais scannés",
    AGE_SEC = "%ds",
    AGE_MIN = "%dmin",
    AGE_HOUR = "%dh",
    AGE_DAY = "%dj",
    PIN = "Épingler",
    UNPIN = "Désépingler",
    PINS_TITLE = "Recettes épinglées",
    PINS_EMPTY = "Aucune recette épinglée",
    PINS_FULL = "Trop de recettes épinglées",
    SEARCH_PRICES = "Rechercher les prix",
    SEARCHING = "Recherche %d/%d",
    SEARCH_DONE = "Prix mis à jour",
    SEARCH_PARTIAL = "Prix mis à jour, %d introuvable(s)",
    SEARCH_NEED_AH = "Ouvrez d'abord l'hôtel des ventes",
    SEARCH_CANCELLED = "Recherche annulée",
    SCAN = "Scanner l'HV",
    SCAN_STARTED = "Scan de l'hôtel des ventes...",
    SCAN_DONE = "Scan terminé : %d objets chiffrés",
    SCAN_COOLDOWN = "Scan complet disponible dans %s",
    OPT_PER_POINT = "Afficher le coût par point de compétence",
    NO_RECIPE = "Sélectionnez une recette",
    SLASH_HELP = "Commandes : /cp show | hide | reset | scan | locale <code> | selftest",
    SELFTEST_OK = "Auto-test réussi (%d vérifications)",
    SELFTEST_FAIL = "Auto-test ÉCHOUÉ : %s",
})
```

```lua file=CraftProfit/Locales/esES.lua
local _, ns = ...

ns.Locale.register("esES", {
    TITLE = "CraftProfit",
    MATERIALS = "Materiales",
    LINE_AH = "Casa de subastas (neto)",
    LINE_VENDOR = "Vendedor",
    LINE_DISENCHANT = "Desencantar (esperado)",
    NAME_AH = "Casa de subastas",
    NAME_VENDOR = "Vendedor",
    NAME_DISENCHANT = "Desencantar",
    PER_POINT = "Coste por punto de habilidad",
    ESTIMATE = "estimación",
    VERDICT_BEST = "Mejor: %s",
    VERDICT_PARTIAL = "Mejor conocido: %s (faltan precios)",
    VERDICT_INCOMPLETE = "Incompleto: faltan precios",
    VERDICT_NONE = "No hay forma de vender este objeto",
    NA = "n/d",
    UNKNOWN = "?",
    AGE = "Precios: hace %s",
    AGE_NEVER = "Precios: nunca escaneados",
    AGE_SEC = "%ds",
    AGE_MIN = "%dmin",
    AGE_HOUR = "%dh",
    AGE_DAY = "%dd",
    PIN = "Fijar",
    UNPIN = "Quitar",
    PINS_TITLE = "Recetas fijadas",
    PINS_EMPTY = "Ninguna receta fijada",
    PINS_FULL = "Demasiadas recetas fijadas",
    SEARCH_PRICES = "Buscar precios",
    SEARCHING = "Buscando %d/%d",
    SEARCH_DONE = "Precios actualizados",
    SEARCH_PARTIAL = "Precios actualizados, %d sin resultado",
    SEARCH_NEED_AH = "Abre primero la casa de subastas",
    SEARCH_CANCELLED = "Búsqueda cancelada",
    SCAN = "Escanear CS",
    SCAN_STARTED = "Escaneando la casa de subastas...",
    SCAN_DONE = "Escaneo completo: %d objetos con precio",
    SCAN_COOLDOWN = "Escaneo completo disponible en %s",
    OPT_PER_POINT = "Mostrar coste por punto de habilidad",
    NO_RECIPE = "Selecciona una receta",
    SLASH_HELP = "Comandos: /cp show | hide | reset | scan | locale <código> | selftest",
    SELFTEST_OK = "Autoprueba superada (%d comprobaciones)",
    SELFTEST_FAIL = "Autoprueba FALLIDA: %s",
})
```

```lua file=CraftProfit/Locales/esMX.lua
local _, ns = ...

-- Latin American Spanish reuses the Spain strings until a native speaker
-- supplies differences.
ns.Locale.alias("esMX", "esES")
```

- [ ] **Step 5: Run the tests and luacheck**

Run: `sh tests/check.sh`
Expected: all tests pass, luacheck clean.

- [ ] **Step 6: Commit**

```bash
git add CraftProfit/Locale.lua CraftProfit/Locales tests/test_locale.lua
git commit -m "feat: add Locale with enUS, frFR, esES and esMX strings"
```

---

### Task 7: `Recipes` (validate and normalize a recipe)

The game adapters (Task 14) hand over raw tables read from the client; every other module only ever sees the normalized form. A recipe with any invalid reagent is **rejected whole**, because dropping the bad line would make the craft look cheaper than it is.

**Files:**
- Create: `CraftProfit/Recipes.lua`
- Test: `tests/test_recipes.lua`

**Interfaces:**
- Consumes: `Util.id`, `Util.isFinite`, `Skillup.name`
- Produces: `Recipes.normalize(raw) -> recipe|nil` and `Recipes.MAX_REAGENTS = 12`.
  - Input `raw`: `{ recipeID, name, difficulty, outputItemID, qtyMin, qtyMax, reagents = { {itemID, qty}, ... } }`; or an already normalized recipe (idempotent: `outputQty` replaces `qtyMin/qtyMax`).
  - Output `recipe`: `{ recipeID, name, difficulty ("optimal"|"medium"|"easy"|"trivial"|nil), outputItemID, outputQty (number >= 1, may be fractional), reagents = { {itemID, qty}, ... } }` with duplicate reagents merged.

- [ ] **Step 1: Write the failing tests**

```lua file=tests/test_recipes.lua
local H = ...

local function load() return H.newNS("Util", "Data/Skillup", "Recipes").Recipes end

-- Overrides cannot contain nil (pairs skips it), so NIL marks "remove this field".
local NIL = {}

local function raw(over)
    local r = {
        recipeID = 5, name = "Copper Sword", difficulty = 0, outputItemID = 2845,
        qtyMin = 1, qtyMax = 1,
        reagents = { { itemID = 2840, qty = 6 } },
    }
    for k, v in pairs(over or {}) do
        if v == NIL then r[k] = nil else r[k] = v end
    end
    return r
end

H.test("normalize builds the canonical recipe", function()
    H.eq(load().normalize(raw()), {
        recipeID = 5, name = "Copper Sword", difficulty = "optimal", outputItemID = 2845,
        outputQty = 1, reagents = { { itemID = 2840, qty = 6 } },
    })
end)

H.test("normalize averages a min..max yield and defaults to 1", function()
    local R = load()
    H.eq(R.normalize(raw({ qtyMin = 1, qtyMax = 2 })).outputQty, 1.5)
    H.eq(R.normalize(raw({ qtyMin = NIL, qtyMax = NIL })).outputQty, 1)
end)

H.test("normalize is idempotent", function()
    local R = load()
    local once = R.normalize(raw({ qtyMin = 2, qtyMax = 4 }))
    H.eq(R.normalize(once), once)
end)

H.test("normalize merges duplicate reagents and keeps their order", function()
    local R = load()
    local r = R.normalize(raw({ reagents = { { itemID = 1, qty = 2 }, { itemID = 2, qty = 1 }, { itemID = 1, qty = 3 } } }))
    H.eq(r.reagents, { { itemID = 1, qty = 5 }, { itemID = 2, qty = 1 } })
end)

H.test("normalize does not modify its input", function()
    local R = load()
    local input = raw({ reagents = { { itemID = 1, qty = 2 }, { itemID = 1, qty = 3 } } })
    R.normalize(input)
    H.eq(input.reagents, { { itemID = 1, qty = 2 }, { itemID = 1, qty = 3 } })
end)

H.test("normalize rejects the whole recipe when any reagent is invalid", function()
    local R = load()
    local bads = {
        { { itemID = 1, qty = 0 } },
        { { itemID = 1, qty = 1.5 } },
        { { itemID = nil, qty = 1 } },
        { { itemID = 1.5, qty = 1 } },
        { { itemID = 1, qty = 0 / 0 } },
        { { itemID = 1, qty = 1 }, "junk" },
        { { itemID = 1, qty = 1 }, { itemID = 2 } },
        {},
    }
    for _, reagents in ipairs(bads) do
        H.eq(R.normalize(raw({ reagents = reagents })), nil)
    end
    H.eq(R.normalize(raw({ reagents = NIL })), nil)
    H.eq(R.normalize(raw({ reagents = "x" })), nil)
end)

H.test("normalize rejects more than the maximum number of reagents", function()
    local R = load()
    local reagents = {}
    for i = 1, R.MAX_REAGENTS + 1 do reagents[i] = { itemID = i, qty = 1 } end
    H.eq(R.normalize(raw({ reagents = reagents })), nil)
    table.remove(reagents)
    H.truthy(R.normalize(raw({ reagents = reagents })))
end)

H.test("normalize rejects invalid identifiers and yields", function()
    local R = load()
    H.eq(R.normalize(raw({ recipeID = NIL })), nil)
    H.eq(R.normalize(raw({ recipeID = 0 })), nil)
    H.eq(R.normalize(raw({ outputItemID = NIL })), nil)
    H.eq(R.normalize(raw({ outputItemID = 0 / 0 })), nil)
    H.eq(R.normalize(raw({ qtyMin = 0 })), nil)
    H.eq(R.normalize(raw({ qtyMin = 3, qtyMax = 1 })), nil)
    H.eq(R.normalize(raw({ qtyMin = 1, qtyMax = 0 / 0 })), nil)
    H.eq(R.normalize(raw({ qtyMin = 1, qtyMax = 5000 })), nil)
    H.eq(R.normalize(nil), nil)
    H.eq(R.normalize("recipe"), nil)
end)

H.test("normalize tolerates a missing name and an unknown difficulty", function()
    local R = load()
    H.eq(R.normalize(raw({ name = NIL })).name, "")
    H.eq(R.normalize(raw({ name = 12 })).name, "")
    H.eq(R.normalize(raw({ name = string.rep("x", 300) })).name, "")
    local r = R.normalize(raw({ difficulty = "header" }))
    H.truthy(r)
    H.eq(r.difficulty, nil)
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `luajit tests/run.lua`
Expected: FAIL in `tests/test_recipes.lua` (cannot open `CraftProfit/Recipes.lua`).

- [ ] **Step 3: Implement `Recipes`**

```lua file=CraftProfit/Recipes.lua
-- Recipe validation and normalization. Pure Lua, no WoW API.
-- Raw tables come from the game adapter or from SavedVariables; neither is trusted.
local _, ns = ...
local Util = ns.Util
local Skillup = ns.Data.Skillup

local Recipes = {}
ns.Recipes = Recipes

Recipes.MAX_REAGENTS = 12
local MAX_NAME_BYTES = 200
local MAX_YIELD = 1000

-- Average yield. Absent min/max means a single item; present but invalid means
-- the whole recipe is unusable (nil).
local function outputQty(raw)
    if raw.outputQty ~= nil then
        local q = raw.outputQty
        if Util.isFinite(q) and q >= 1 and q <= MAX_YIELD then return q end
        return nil
    end
    if raw.qtyMin == nil and raw.qtyMax == nil then return 1 end
    local lo = raw.qtyMin or raw.qtyMax
    local hi = raw.qtyMax or raw.qtyMin
    if Util.isFinite(lo) and Util.isFinite(hi) and lo >= 1 and hi >= lo and hi <= MAX_YIELD then
        return (lo + hi) / 2
    end
    return nil
end

-- One invalid reagent invalidates the list: dropping it would hide a cost.
local function reagents(list)
    if type(list) ~= "table" then return nil end
    local merged, order = {}, {}
    for _, r in ipairs(list) do
        if type(r) ~= "table" then return nil end
        local id, qty = Util.id(r.itemID), Util.id(r.qty)
        if not id or not qty then return nil end
        if merged[id] then
            merged[id] = merged[id] + qty
        else
            merged[id] = qty
            order[#order + 1] = id
        end
    end
    if #order == 0 or #order > Recipes.MAX_REAGENTS then return nil end
    local out = {}
    for i, id in ipairs(order) do out[i] = { itemID = id, qty = merged[id] } end
    return out
end

function Recipes.normalize(raw)
    if type(raw) ~= "table" then return nil end
    local recipeID, outputItemID = Util.id(raw.recipeID), Util.id(raw.outputItemID)
    if not recipeID or not outputItemID then return nil end
    local qty, list = outputQty(raw), reagents(raw.reagents)
    if not qty or not list then return nil end
    local name = raw.name
    if type(name) ~= "string" or #name > MAX_NAME_BYTES then name = "" end
    return {
        recipeID = recipeID,
        name = name,
        difficulty = Skillup.name(raw.difficulty),
        outputItemID = outputItemID,
        outputQty = qty,
        reagents = list,
    }
end
```

- [ ] **Step 4: Run the tests and luacheck**

Run: `sh tests/check.sh`
Expected: all pass, luacheck clean.

- [ ] **Step 5: Commit**

```bash
git add CraftProfit/Recipes.lua tests/test_recipes.lua
git commit -m "feat: add Recipes validation and normalization"
```

---

### Task 8: `DB` (saved variables: defaults, repair, migration, pins)

**Files:**
- Create: `CraftProfit/DB.lua`
- Test: `tests/test_db.lua`

**Interfaces:**
- Consumes: `Util.*`, `Recipes.normalize`
- Produces:
  - `DB.VERSION = 1`, `DB.MAX_PINS = 12`, `DB.PRICE_MAX_AGE = 14*86400`, `DB.DEFAULTS = {cut=0.05, medianN=5, showPerPoint=false, staleAfter=3600}`, `DB.migrations` (table, public so tests can inject a failing step)
  - `DB.initAccount(db) -> db` — repairs **in place** `{dbVersion, settings = {cut, medianN, showPerPoint, staleAfter, window = {point,x,y}|nil}, prices = {[itemID] = {unit, volume, time}}, snapshotTime}`
  - `DB.prune(db, now) -> removedCount`
  - `DB.initChar(db) -> db` — repairs in place `{pins = { recipe, ... }}`
  - `DB.pinIndex(db, recipeID) -> index|nil`, `DB.pinAdd(db, recipe) -> true` or `-> false, "exists"|"full"|"invalid"`, `DB.pinRemove(db, recipeID) -> boolean`
  - Anchor points accepted for `window.point`: `TOPLEFT TOP TOPRIGHT LEFT CENTER RIGHT BOTTOMLEFT BOTTOM BOTTOMRIGHT`

- [ ] **Step 1: Write the failing tests**

```lua file=tests/test_db.lua
local H = ...

local function load() return H.newNS("Util", "Data/Skillup", "Recipes", "DB").DB end

local function raw(id)
    return {
        recipeID = id, name = "R" .. id, difficulty = "easy", outputItemID = 1000 + id,
        qtyMin = 1, qtyMax = 1, reagents = { { itemID = 1, qty = 2 } },
    }
end

H.test("initAccount fills defaults and returns the same table", function()
    local DB = load()
    local db = {}
    H.truthy(DB.initAccount(db) == db)
    H.eq(db.dbVersion, 1)
    H.eq(db.settings, { cut = 0.05, medianN = 5, showPerPoint = false, staleAfter = 3600 })
    H.eq(db.prices, {})
end)

H.test("initAccount repairs the tables in place", function()
    local DB = load()
    local settings, prices = {}, {}
    local db = { settings = settings, prices = prices }
    DB.initAccount(db)
    H.truthy(db.settings == settings)
    H.truthy(db.prices == prices)
end)

H.test("initAccount replaces invalid settings with defaults", function()
    local DB = load()
    local db = DB.initAccount({ settings = {
        cut = 0 / 0, medianN = 99, staleAfter = -5, showPerPoint = "yes",
        window = { point = "NOPE", x = 1, y = 2 },
    } })
    H.eq(db.settings, { cut = 0.05, medianN = 5, showPerPoint = false, staleAfter = 3600 })
end)

H.test("initAccount keeps valid settings and floors medianN", function()
    local DB = load()
    local db = DB.initAccount({ settings = {
        cut = 0.5, medianN = 7.9, staleAfter = 120, showPerPoint = true,
        window = { point = "TOPLEFT", x = 100, y = -50, junk = 1 },
    } })
    H.eq(db.settings, {
        cut = 0.5, medianN = 7, staleAfter = 120, showPerPoint = true,
        window = { point = "TOPLEFT", x = 100, y = -50 },
    })
    H.eq(DB.initAccount({ settings = { cut = 0.51 } }).settings.cut, 0.05)
    H.eq(DB.initAccount({ settings = { cut = -0.01 } }).settings.cut, 0.05)
end)

H.test("initAccount survives hostile dbVersion values without looping", function()
    local DB = load()
    for _, bad in ipairs({ -1 / 0, 0 / 0, "x", -5, {} }) do
        H.eq(DB.initAccount({ dbVersion = bad }).dbVersion, 1)
    end
end)

H.test("initAccount never downgrades data written by a newer version", function()
    local DB = load()
    H.eq(DB.initAccount({ dbVersion = 99 }).dbVersion, 99)
end)

H.test("a failing migration stops at the last good version", function()
    local DB = load()
    local oldVersion = DB.VERSION
    DB.VERSION = 2
    DB.migrations[2] = function() error("boom") end
    local db = DB.initAccount({})
    DB.VERSION = oldVersion
    DB.migrations[2] = nil
    H.eq(db.dbVersion, 1)
    H.truthy(type(db.settings) == "table")
end)

H.test("initAccount removes invalid price rows", function()
    local DB = load()
    local db = DB.initAccount({ prices = {
        [100] = { 5, 2, 1000 },
        [101] = { 0 / 0, 1, 0 },
        x = { 1, 1, 1 },
        [102] = "bad",
        [103] = { 5, 0, 10 },
        [104] = { -1, 1, 0 },
        [105] = { 5, 1, 0 / 0 },
        [106.5] = { 5, 1, 0 },
    } })
    H.eq(db.prices, { [100] = { 5, 2, 1000 } })
end)

H.test("initAccount drops an invalid snapshot time", function()
    local DB = load()
    H.eq(DB.initAccount({ snapshotTime = 0 / 0 }).snapshotTime, nil)
    H.eq(DB.initAccount({ snapshotTime = -3 }).snapshotTime, nil)
    H.eq(DB.initAccount({ snapshotTime = 500 }).snapshotTime, 500)
end)

H.test("prune drops old prices but keeps future-dated ones", function()
    local DB = load()
    local now = 10 * DB.PRICE_MAX_AGE
    local db = DB.initAccount({ prices = {
        [1] = { 5, 1, now - DB.PRICE_MAX_AGE - 1 },
        [2] = { 5, 1, now - 10 },
        [3] = { 5, 1, now + 1000 },
    } })
    H.eq(DB.prune(db, now), 1)
    H.eq(db.prices[1], nil)
    H.truthy(db.prices[2])
    H.truthy(db.prices[3])
    H.eq(DB.prune(db, 0 / 0), 0)
end)

H.test("initChar keeps valid pins, drops junk and duplicates, repairs holes", function()
    local DB = load()
    local pins = { raw(1), "junk", { recipeID = 2 }, raw(1), [5] = raw(3) }
    local db = { pins = pins }
    DB.initChar(db)
    H.truthy(db.pins == pins)
    H.eq(#db.pins, 2)
    H.eq(db.pins[1].recipeID, 1)
    H.eq(db.pins[2].recipeID, 3)
    H.eq(db.pins[1].difficulty, "easy")
end)

H.test("initChar caps the number of pins", function()
    local DB = load()
    local pins = {}
    for i = 1, 20 do pins[i] = raw(i) end
    local db = DB.initChar({ pins = pins })
    H.eq(#db.pins, DB.MAX_PINS)
    H.eq(db.pins[DB.MAX_PINS].recipeID, DB.MAX_PINS)
end)

H.test("initChar creates the pins table when missing or invalid", function()
    local DB = load()
    H.eq(DB.initChar({}).pins, {})
    H.eq(DB.initChar({ pins = "x" }).pins, {})
end)

H.test("pinAdd stores a normalized copy and pinRemove deletes it", function()
    local DB = load()
    local db = DB.initChar({})
    local recipe = raw(7)
    H.eq({ DB.pinAdd(db, recipe) }, { true })
    H.truthy(db.pins[1] ~= recipe)
    H.eq(db.pins[1].outputQty, 1)
    H.eq(DB.pinIndex(db, 7), 1)
    H.eq(DB.pinRemove(db, 7), true)
    H.eq(DB.pinRemove(db, 7), false)
    H.eq(DB.pinIndex(db, 7), nil)
end)

H.test("pinAdd refuses duplicates, invalid recipes and a full list", function()
    local DB = load()
    local db = DB.initChar({})
    DB.pinAdd(db, raw(1))
    H.eq({ DB.pinAdd(db, raw(1)) }, { false, "exists" })
    H.eq({ DB.pinAdd(db, { recipeID = 2 }) }, { false, "invalid" })
    for i = 2, DB.MAX_PINS do DB.pinAdd(db, raw(i)) end
    H.eq({ DB.pinAdd(db, raw(100)) }, { false, "full" })
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `luajit tests/run.lua`
Expected: FAIL in `tests/test_db.lua` (cannot open `CraftProfit/DB.lua`).

- [ ] **Step 3: Implement `DB`**

```lua file=CraftProfit/DB.lua
-- Saved variable defaults, repair and migration. Pure Lua, no WoW API.
-- Both saved tables are repaired IN PLACE: WoW keeps a reference to the table
-- it loaded, so replacing it would silently lose the data on logout.
local _, ns = ...
local Util, Recipes = ns.Util, ns.Recipes

local DB = {}
ns.DB = DB

DB.VERSION = 1
DB.MAX_PINS = 12
DB.PRICE_MAX_AGE = 14 * 86400

DB.DEFAULTS = {
    cut = 0.05,         -- AH commission; set from docs/probe-findings.md F5
    medianN = 5,        -- cheapest units used for the median price
    showPerPoint = false,
    staleAfter = 3600,  -- seconds before prices are shown as old
}

local ANCHORS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
    RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

-- Steps that bring older saved data up to date; index = target version.
DB.migrations = {
    [1] = function(db)
        if type(db.settings) ~= "table" then db.settings = {} end
    end,
}

local function number(t, key, lo, hi, default, integer)
    local v = t[key]
    if not Util.isFinite(v) or v < lo or v > hi then v = default end
    if integer then v = math.floor(v) end
    t[key] = v
end

local function sanitizeSettings(s)
    number(s, "cut", 0, 0.5, DB.DEFAULTS.cut)
    number(s, "medianN", 1, 20, DB.DEFAULTS.medianN, true)
    number(s, "staleAfter", 60, 30 * 86400, DB.DEFAULTS.staleAfter)
    if type(s.showPerPoint) ~= "boolean" then s.showPerPoint = DB.DEFAULTS.showPerPoint end
    local w = s.window
    if type(w) == "table" and ANCHORS[w.point] and Util.isFinite(w.x) and Util.isFinite(w.y) then
        s.window = { point = w.point, x = w.x, y = w.y }
    else
        s.window = nil
    end
end

-- Rows are compact arrays { unit, volume, time } to keep the file small.
local function sanitizePrices(prices)
    for itemID, row in pairs(prices) do
        local valid = Util.id(itemID) == itemID and type(row) == "table"
            and Util.isCopper(row[1]) and row[1] > 0
            and Util.count(row[2]) ~= nil and Util.isCopper(row[3])
        -- Clearing a field while iterating with pairs is allowed in Lua.
        if not valid then prices[itemID] = nil end
    end
end

function DB.initAccount(db)
    local version = db.dbVersion
    if not Util.isFinite(version) or version < 0 then version = 0 end
    db.dbVersion = math.floor(version)
    -- Bounded by DB.VERSION: a hostile dbVersion cannot make this loop forever.
    for v = db.dbVersion + 1, DB.VERSION do
        local migrate = DB.migrations[v]
        if migrate and not pcall(migrate, db) then break end
        db.dbVersion = v
    end
    if type(db.settings) ~= "table" then db.settings = {} end
    sanitizeSettings(db.settings)
    if type(db.prices) ~= "table" then db.prices = {} end
    sanitizePrices(db.prices)
    if not Util.isCopper(db.snapshotTime) then db.snapshotTime = nil end
    return db
end

-- Removes prices older than PRICE_MAX_AGE. A price dated in the future (clock
-- moved back) is kept: its age is simply unknown. Returns how many were removed.
function DB.prune(db, now)
    if not Util.isFinite(now) then return 0 end
    local removed = 0
    for itemID, row in pairs(db.prices) do
        if now - row[3] > DB.PRICE_MAX_AGE then
            db.prices[itemID] = nil
            removed = removed + 1
        end
    end
    return removed
end

function DB.initChar(db)
    if type(db.pins) ~= "table" then db.pins = {} end
    local pins = db.pins
    -- Collect numeric keys in order so holes in the array do not hide entries.
    local keys = {}
    for k in pairs(pins) do
        if Util.isFinite(k) and k >= 1 then keys[#keys + 1] = k end
    end
    table.sort(keys)
    local keep, seen = {}, {}
    for _, k in ipairs(keys) do
        local recipe = Recipes.normalize(pins[k])
        if recipe and not seen[recipe.recipeID] and #keep < DB.MAX_PINS then
            seen[recipe.recipeID] = true
            keep[#keep + 1] = recipe
        end
    end
    for k in pairs(pins) do pins[k] = nil end
    for i, recipe in ipairs(keep) do pins[i] = recipe end
    return db
end

function DB.pinIndex(db, recipeID)
    for i, recipe in ipairs(db.pins) do
        if recipe.recipeID == recipeID then return i end
    end
    return nil
end

function DB.pinAdd(db, recipe)
    local clean = Recipes.normalize(recipe)
    if not clean then return false, "invalid" end
    if DB.pinIndex(db, clean.recipeID) then return false, "exists" end
    if #db.pins >= DB.MAX_PINS then return false, "full" end
    db.pins[#db.pins + 1] = clean
    return true
end

function DB.pinRemove(db, recipeID)
    local index = DB.pinIndex(db, recipeID)
    if not index then return false end
    table.remove(db.pins, index)
    return true
end
```

- [ ] **Step 4: Run the tests and luacheck**

Run: `sh tests/check.sh`
Expected: all pass, luacheck clean.

- [ ] **Step 5: Commit**

```bash
git add CraftProfit/DB.lua tests/test_db.lua
git commit -m "feat: add DB defaults, repair, migration and pins"
```

---

### Task 9: `Prices` (median, snapshot aggregation, storage)

**Files:**
- Create: `CraftProfit/Prices.lua`
- Test: `tests/test_prices.lua`

**Interfaces:**
- Consumes: `Util.*`
- Produces:
  - `Prices.summarize(listings, n) -> medianUnit, volume` — `listings = { {unit=copper, qty=number}, ... }`; median of the `n` cheapest **units** (quantity-weighted); `volume` = total units listed; `nil, 0` when nothing usable
  - `Prices.newAggregator() -> agg` with `agg.add(itemID, unit, qty)` and `agg.result(n) -> { [itemID] = {unit=, volume=} }` (used for the full scan, fed row by row)
  - `Prices.store(db, itemID, unit, volume, now) -> boolean`
  - `Prices.merge(db, map, now) -> count` (writes a snapshot result, sets `db.snapshotTime`)
  - `Prices.get(db, itemID, now) -> unit, age|nil, volume` (age is nil when the clock went backwards)
  - `Prices.priceOf(db, now) -> function(itemID) -> unit, age`
  - `Prices.snapshotAge(db, now) -> seconds|nil`

- [ ] **Step 1: Write the failing tests**

```lua file=tests/test_prices.lua
local H = ...

local function load() return H.newNS("Util", "Prices").Prices end

H.test("summarize takes the median of the cheapest units", function()
    local P = load()
    local listings = { { unit = 1000, qty = 1 }, { unit = 10, qty = 1 }, { unit = 20, qty = 1 } }
    H.eq({ P.summarize(listings, 5) }, { 20, 3 })
    H.eq({ P.summarize(listings, 1) }, { 10, 3 })
    H.eq({ P.summarize(listings, 2) }, { 15, 3 })
end)

H.test("summarize weights listings by quantity without looping over units", function()
    local P = load()
    H.eq({ P.summarize({ { unit = 5, qty = 100 }, { unit = 50, qty = 1 } }, 5) }, { 5, 101 })
    H.eq({ P.summarize({ { unit = 3, qty = 1e9 } }, 5) }, { 3, 1e9 })
end)

H.test("summarize ignores invalid listings", function()
    local P = load()
    local listings = {
        { unit = 0 / 0, qty = 1 }, { unit = 0, qty = 1 }, { unit = -5, qty = 1 },
        { unit = 40, qty = 0 }, { unit = 40 }, { qty = 3 }, { unit = 1 / 0, qty = 1 },
        { unit = 40, qty = 2 },
    }
    H.eq({ P.summarize(listings, 5) }, { 40, 2 })
end)

H.test("summarize with nothing usable returns nil and zero volume", function()
    local P = load()
    H.eq({ P.summarize({}, 5) }, { nil, 0 })
    H.eq({ P.summarize(nil, 5) }, { nil, 0 })
    H.eq({ P.summarize({ { unit = 0, qty = 1 } }, 5) }, { nil, 0 })
end)

H.test("summarize falls back to 5 units for an invalid n", function()
    local P = load()
    local listings = {}
    for i = 1, 9 do listings[i] = { unit = i * 10, qty = 1 } end
    H.eq(P.summarize(listings, nil), 30)
    H.eq(P.summarize(listings, 0), 30)
    H.eq(P.summarize(listings, 0 / 0), 30)
end)

H.test("the aggregator groups rows by item and skips invalid ones", function()
    local P = load()
    local agg = P.newAggregator()
    agg.add(1, 100, 1)
    agg.add(1, 300, 1)
    agg.add(1, 200, 1)
    agg.add(2, 50, 4)
    agg.add(nil, 10, 1)
    agg.add(3, 0 / 0, 1)
    agg.add(4, 10, 0)
    H.eq(agg.result(5), { [1] = { unit = 200, volume = 3 }, [2] = { unit = 50, volume = 4 } })
end)

H.test("store writes a compact row and rejects invalid input", function()
    local P = load()
    local db = { prices = {} }
    H.eq(P.store(db, 7, 123.4, 3, 1000), true)
    H.eq(db.prices[7], { 123, 3, 1000 })
    H.eq(P.store(db, 8, 0 / 0, 3, 1000), false)
    H.eq(P.store(db, 8, 0, 3, 1000), false)
    H.eq(P.store(db, 8, 10, 3, 0 / 0), false)
    H.eq(P.store(db, "x", 10, 3, 1000), false)
    H.eq(db.prices[8], nil)
end)

H.test("get returns the price and its age", function()
    local P = load()
    local db = { prices = {} }
    P.store(db, 7, 500, 4, 1000)
    H.eq({ P.get(db, 7, 1090) }, { 500, 90, 4 })
    H.eq({ P.get(db, 99, 1090) }, {})
end)

H.test("get keeps the price but reports no age when the clock went backwards", function()
    local P = load()
    local db = { prices = {} }
    P.store(db, 7, 500, 4, 1000)
    H.eq({ P.get(db, 7, 900) }, { 500, nil, 4 })
    H.eq({ P.get(db, 7, 0 / 0) }, { 500, nil, 4 })
    H.eq({ P.get(db, 7, nil) }, { 500, nil, 4 })
end)

H.test("get ignores a corrupt row", function()
    local P = load()
    local db = { prices = { [7] = { 0 / 0, 1, 10 }, [8] = "bad", [9] = { -5, 1, 10 } } }
    H.eq({ P.get(db, 7, 20) }, {})
    H.eq({ P.get(db, 8, 20) }, {})
    H.eq({ P.get(db, 9, 20) }, {})
end)

H.test("merge stores a snapshot result and remembers when", function()
    local P = load()
    local db = { prices = {} }
    local count = P.merge(db, { [1] = { unit = 10, volume = 2 }, [2] = { unit = 0 / 0, volume = 1 } }, 2000)
    H.eq(count, 1)
    H.eq(db.prices[1], { 10, 2, 2000 })
    H.eq(db.snapshotTime, 2000)
    H.eq(P.merge(db, {}, 0 / 0), 0)
    H.eq(db.snapshotTime, 2000)
end)

H.test("priceOf and snapshotAge read through the same rules", function()
    local P = load()
    local db = { prices = {} }
    P.store(db, 7, 500, 4, 1000)
    H.eq({ P.priceOf(db, 1060)(7) }, { 500, 60 })
    H.eq({ P.priceOf(db, 1060)(8) }, {})
    H.eq(P.snapshotAge(db, 1060), nil)
    db.snapshotTime = 1000
    H.eq(P.snapshotAge(db, 1060), 60)
    H.eq(P.snapshotAge(db, 900), nil)
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `luajit tests/run.lua`
Expected: FAIL in `tests/test_prices.lua` (cannot open `CraftProfit/Prices.lua`).

- [ ] **Step 3: Implement `Prices`**

```lua file=CraftProfit/Prices.lua
-- Price statistics and storage. Pure Lua, no WoW API.
local _, ns = ...
local Util = ns.Util

local Prices = {}
ns.Prices = Prices

local DEFAULT_N = 5

-- Median unit price of the n cheapest units among the listings, plus the total
-- number of units listed. A single absurdly cheap listing cannot drag the price
-- down the way a plain minimum would. Quantities are handled arithmetically:
-- a listing of 1e9 units costs the same as one of 1.
function Prices.summarize(listings, n)
    n = Util.count(n) or DEFAULT_N
    local rows, volume = {}, 0
    for _, l in ipairs(listings or {}) do
        local qty = Util.count(l.qty)
        if Util.isCopper(l.unit) and l.unit > 0 and qty then
            rows[#rows + 1] = { unit = l.unit, qty = qty }
            volume = volume + qty
        end
    end
    if #rows == 0 then return nil, 0 end
    table.sort(rows, function(a, b) return a.unit < b.unit end)
    local picked, taken = {}, 0
    for _, r in ipairs(rows) do
        if taken >= n then break end
        local take = math.min(r.qty, n - taken)
        picked[#picked + 1] = { unit = r.unit, qty = take }
        taken = taken + take
    end
    -- k-th cheapest unit (1-based) among the picked rows.
    local function kth(k)
        local seen = 0
        for _, p in ipairs(picked) do
            seen = seen + p.qty
            if seen >= k then return p.unit end
        end
    end
    local median
    if taken % 2 == 1 then
        median = kth((taken + 1) / 2)
    else
        median = (kth(taken / 2) + kth(taken / 2 + 1)) / 2
    end
    return Util.round(median), volume
end

-- Collects (itemID, unit, qty) rows one by one, so a full scan never needs a
-- giant intermediate array. result(n) returns { [itemID] = {unit, volume} }.
function Prices.newAggregator()
    local byItem = {}
    local agg = {}
    function agg.add(itemID, unit, qty)
        if not Util.id(itemID) then return end
        local list = byItem[itemID]
        if not list then
            list = {}
            byItem[itemID] = list
        end
        list[#list + 1] = { unit = unit, qty = qty }
    end
    function agg.result(n)
        local out = {}
        for itemID, list in pairs(byItem) do
            local unit, volume = Prices.summarize(list, n)
            if unit then out[itemID] = { unit = unit, volume = volume } end
        end
        return out
    end
    return agg
end

-- db.prices rows are compact arrays { unit, volume, time }.
function Prices.store(db, itemID, unit, volume, now)
    if not Util.id(itemID) or not Util.isCopper(unit) or unit <= 0 or not Util.isCopper(now) then
        return false
    end
    db.prices[itemID] = { Util.round(unit), Util.count(volume) or 1, now }
    return true
end

-- Writes the result of a full scan. Returns how many prices were stored.
function Prices.merge(db, map, now)
    if not Util.isCopper(now) then return 0 end
    local count = 0
    for itemID, row in pairs(map) do
        if Prices.store(db, itemID, row.unit, row.volume, now) then count = count + 1 end
    end
    db.snapshotTime = now
    return count
end

-- Returns unit, age, volume. The age is nil when it cannot be trusted (clock
-- moved back, invalid now): a wrong age is worse than none.
function Prices.get(db, itemID, now)
    local row = db.prices[itemID]
    if type(row) ~= "table" or not Util.isCopper(row[1]) or row[1] <= 0 then return nil end
    local age
    if Util.isFinite(now) and Util.isCopper(row[3]) and now >= row[3] then age = now - row[3] end
    return row[1], age, row[2]
end

function Prices.priceOf(db, now)
    return function(itemID)
        local unit, age = Prices.get(db, itemID, now)
        return unit, age
    end
end

function Prices.snapshotAge(db, now)
    if not Util.isCopper(db.snapshotTime) or not Util.isFinite(now) or now < db.snapshotTime then
        return nil
    end
    return now - db.snapshotTime
end
```

- [ ] **Step 4: Run the tests and luacheck**

Run: `sh tests/check.sh`
Expected: all pass, luacheck clean.

- [ ] **Step 5: Commit**

```bash
git add CraftProfit/Prices.lua tests/test_prices.lua
git commit -m "feat: add Prices median, aggregation and storage"
```

---

### Task 10: `PriceQueue` (sequential search state machine)

**Files:**
- Create: `CraftProfit/PriceQueue.lua`
- Test: `tests/test_pricequeue.lua`

**Interfaces:**
- Consumes: `Util.isFinite`, `Util.id`
- Produces: `PriceQueue.new(opts) -> q` with
  - `opts = { itemIDs = {...}, send = function(itemID) -> boolean, onItem = function(itemID, listings|nil, err|nil), onProgress = function(done, total), onDone = function(summary), timeout = 6 }`; `send` returns `false` when the AH is throttled (the queue retries on every `tick`)
  - `q:start(now)`, `q:tick(now)`, `q:results(itemID, listings, now)`, `q:cancel()`; `q.state` is `"idle"|"running"|"done"|"cancelled"`
  - `summary = { ok = n, failed = { {itemID=, err="timeout"|"throttled"}, ... }, total = n, cancelled = boolean }`
  - `now` is a monotonic clock (`GetTime()`); a non-finite `now` raises an error blaming the caller, without changing state.

- [ ] **Step 1: Write the failing tests**

```lua file=tests/test_pricequeue.lua
local H = ...

local function load() return H.newNS("Util", "PriceQueue").PriceQueue end

-- Builds a queue wired to recording callbacks. `sendResult` decides what send returns.
local function build(ids, sendResult)
    local PQ = load()
    local log = { sent = {}, items = {}, progress = {}, done = nil }
    local q
    q = PQ.new({
        itemIDs = ids,
        timeout = 6,
        send = function(id)
            log.sent[#log.sent + 1] = id
            if type(sendResult) == "function" then return sendResult(id, q) end
            return sendResult ~= false
        end,
        onItem = function(id, listings, err) log.items[#log.items + 1] = { id, listings, err } end,
        onProgress = function(done, total) log.progress[#log.progress + 1] = { done, total } end,
        onDone = function(summary) log.done = summary end,
    })
    return q, log
end

H.test("items are searched one at a time, in order", function()
    local q, log = build({ 1, 2, 3 })
    q:start(0)
    H.eq(log.sent, { 1 })
    q:results(1, { { unit = 5, qty = 1 } }, 1)
    H.eq(log.sent, { 1, 2 })
    q:results(2, {}, 2)
    q:results(3, {}, 3)
    H.eq(log.sent, { 1, 2, 3 })
    H.eq(q.state, "done")
    H.eq(log.done, { ok = 3, failed = {}, total = 3, cancelled = false })
    H.eq(log.items[1], { 1, { { unit = 5, qty = 1 } }, nil })
    H.eq(log.progress, { { 1, 3 }, { 2, 3 }, { 3, 3 } })
end)

H.test("an item that never answers times out and the queue moves on", function()
    local q, log = build({ 1, 2 })
    q:start(0)
    q:tick(5.9)
    H.eq(log.sent, { 1 })
    q:tick(6)
    H.eq(log.items[1], { 1, nil, "timeout" })
    H.eq(log.sent, { 1, 2 })
    q:results(2, {}, 7)
    H.eq(log.done, { ok = 1, failed = { { itemID = 1, err = "timeout" } }, total = 2, cancelled = false })
end)

H.test("results for an item that is not current are ignored", function()
    local q, log = build({ 1, 2 })
    q:start(0)
    q:results(2, {}, 1)
    q:results(99, {}, 1)
    H.eq(#log.items, 0)
    q:results(1, {}, 2)
    q:results(1, {}, 3)
    H.eq(#log.items, 1)
end)

H.test("a throttled AH is retried on every tick, then the item fails", function()
    local allow = false
    local q, log = build({ 1, 2 }, function() return allow end)
    q:start(0)
    q:tick(1)
    q:tick(2)
    H.eq(log.sent, { 1, 1, 1 })
    allow = true
    q:tick(3)
    H.eq(log.sent, { 1, 1, 1, 1 })
    q:tick(3.1)
    H.eq(#log.items, 0)
    q:results(1, {}, 4)
    H.eq(log.sent[#log.sent], 2)
end)

H.test("an item that is never accepted fails as throttled after three timeouts", function()
    local q, log = build({ 1, 2 }, function(id) return id == 2 end)
    q:start(0)
    q:tick(18)
    H.eq(#log.items, 0)
    q:tick(18.1)
    H.eq(log.items[1], { 1, nil, "throttled" })
    H.eq(log.sent[#log.sent], 2)
end)

H.test("cancel stops the queue and ignores late results", function()
    local q, log = build({ 1, 2, 3 })
    q:start(0)
    q:cancel()
    H.eq(q.state, "cancelled")
    H.eq(log.done, { ok = 0, failed = {}, total = 3, cancelled = true })
    q:results(1, {}, 1)
    q:tick(100)
    H.eq(#log.items, 0)
    H.eq(log.sent, { 1 })
end)

H.test("duplicate and invalid item ids are dropped", function()
    local q, log = build({ 1, 1, "x", 0, 2, 0 / 0 })
    q:start(0)
    q:results(1, {}, 1)
    q:results(2, {}, 2)
    H.eq(log.sent, { 1, 2 })
    H.eq(log.done.total, 2)
end)

H.test("an empty queue finishes immediately", function()
    local q, log = build({})
    q:start(0)
    H.eq(q.state, "done")
    H.eq(log.done, { ok = 0, failed = {}, total = 0, cancelled = false })
end)

H.test("an answer that arrives while send is still running does not double-advance", function()
    local q, log = build({ 1, 2, 3 }, function(id, queue)
        queue:results(id, {}, 0)
        return true
    end)
    q:start(0)
    H.eq(log.sent, { 1, 2, 3 })
    H.eq(q.state, "done")
    H.eq(log.done.ok, 3)
end)

H.test("an invalid clock value raises and leaves the state untouched", function()
    local q = build({ 1 })
    H.raises(function() q:start(0 / 0) end)
    H.eq(q.state, "idle")
    q:start(0)
    H.raises(function() q:tick(nil) end)
    H.raises(function() q:results(1, {}, 1 / 0) end)
    H.eq(q.state, "running")
end)

H.test("start twice, tick before start and tick after done are harmless", function()
    local q, log = build({ 1 })
    q:tick(1)
    q:start(0)
    q:start(1)
    H.eq(log.sent, { 1 })
    q:results(1, {}, 2)
    q:tick(50)
    H.eq(#log.items, 1)
end)

H.test("a callback that cancels the queue stops it cleanly", function()
    local PQ = load()
    local sent = {}
    local q
    q = PQ.new({
        itemIDs = { 1, 2 },
        send = function(id) sent[#sent + 1] = id; return true end,
        onItem = function() q:cancel() end,
    })
    q:start(0)
    q:results(1, {}, 1)
    H.eq(sent, { 1 })
    H.eq(q.state, "cancelled")
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `luajit tests/run.lua`
Expected: FAIL in `tests/test_pricequeue.lua` (cannot open `CraftProfit/PriceQueue.lua`).

- [ ] **Step 3: Implement `PriceQueue`**

```lua file=CraftProfit/PriceQueue.lua
-- Sequential price search over a list of items. Pure Lua, no WoW API: the game
-- adapter supplies `send` and feeds `results` and `tick`.
local _, ns = ...
local Util = ns.Util

local PriceQueue = {}
PriceQueue.__index = PriceQueue
ns.PriceQueue = PriceQueue

local DEFAULT_TIMEOUT = 6
-- An item the AH refuses to take for this many timeouts is abandoned.
local THROTTLE_FACTOR = 3

-- Time must be finite: NaN would silently disable every timeout. Level 3 blames
-- the caller of the public method, not this helper.
local function checkTime(now)
    if not Util.isFinite(now) then
        error("PriceQueue: invalid time " .. tostring(now), 3)
    end
end

function PriceQueue.new(opts)
    local ids, seen = {}, {}
    for _, raw in ipairs(opts.itemIDs or {}) do
        local id = Util.id(raw)
        if id and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    return setmetatable({
        opts = opts,
        ids = ids,
        total = #ids,
        index = 0,
        done = 0,
        okCount = 0,
        failed = {},
        state = "idle",
        timeout = opts.timeout or DEFAULT_TIMEOUT,
    }, PriceQueue)
end

function PriceQueue:finish(cancelled)
    self.state = cancelled and "cancelled" or "done"
    self.current = nil
    if self.opts.onDone then
        self.opts.onDone({
            ok = self.okCount, failed = self.failed, total = self.total, cancelled = cancelled,
        })
    end
end

-- Tries to send the current item. The answer may arrive before send returns
-- (tests do this); then current has already moved on and we must not touch it.
function PriceQueue:attempt(now)
    local id = self.current
    local ok = self.opts.send(id)
    if self.current ~= id or self.state ~= "running" then return end
    if ok then
        self.sent = true
        self.sentAt = now
        self.waitingSince = nil
    else
        self.sent = false
        self.waitingSince = self.waitingSince or now
    end
end

function PriceQueue:advance(now)
    self.index = self.index + 1
    local id = self.ids[self.index]
    if not id then
        self:finish(false)
        return
    end
    self.current = id
    self.sent = false
    self.waitingSince = nil
    self:attempt(now)
end

function PriceQueue:complete(listings, err, now)
    local id = self.current
    self.done = self.done + 1
    if err then
        self.failed[#self.failed + 1] = { itemID = id, err = err }
    else
        self.okCount = self.okCount + 1
    end
    if self.opts.onItem then self.opts.onItem(id, listings, err) end
    if self.opts.onProgress then self.opts.onProgress(self.done, self.total) end
    -- A callback may have cancelled the queue.
    if self.state == "running" then self:advance(now) end
end

function PriceQueue:start(now)
    checkTime(now)
    if self.state ~= "idle" then return end
    self.state = "running"
    self:advance(now)
end

-- Call regularly (about every 0.2 s) with a monotonic clock.
function PriceQueue:tick(now)
    checkTime(now)
    if self.state ~= "running" then return end
    if self.sent then
        if now - self.sentAt >= self.timeout then self:complete(nil, "timeout", now) end
        return
    end
    self:attempt(now)
    if self.state == "running" and not self.sent and self.waitingSince
        and now - self.waitingSince > self.timeout * THROTTLE_FACTOR then
        self:complete(nil, "throttled", now)
    end
end

-- Feed the listings the AH returned for itemID. Anything but the current item
-- is ignored (stale events, other addons' searches).
function PriceQueue:results(itemID, listings, now)
    checkTime(now)
    if self.state ~= "running" or itemID ~= self.current then return end
    self:complete(listings or {}, nil, now)
end

function PriceQueue:cancel()
    if self.state == "running" then self:finish(true) end
end
```

- [ ] **Step 4: Run the tests and luacheck**

Run: `sh tests/check.sh`
Expected: all pass, luacheck clean.

- [ ] **Step 5: Commit**

```bash
git add CraftProfit/PriceQueue.lua tests/test_pricequeue.lua
git commit -m "feat: add PriceQueue sequential search state machine"
```

---

### Task 11: `Evaluate` (recipe + prices → profit result)

**Files:**
- Create: `CraftProfit/Evaluate.lua`
- Test: `tests/test_evaluate.lua`

**Interfaces:**
- Consumes: `Core.*`, `Skillup.chance`, `Disenchant.kindOf`, `Disenchant.canDisenchant`, `Util.*`
- Produces:
  - `Evaluate.run(ctx) -> result` where
    `ctx = { recipe, priceOf(itemID) -> unit|nil, age|nil, itemInfo(itemID) -> {quality, ilvl, sellPrice, classID, bindType}|nil, cut, showPerPoint, lookupDisenchant(kind, quality, ilvl) -> entries|nil }`
    and
    `result = { recipe, cost = {total|nil, missing = {itemID...}, lines = { {itemID, qty, unit|nil, subtotal|nil} }}, options = { ah=, vendor=, disenchant= } (each {status="ok"|"unknown"|"na", value}), best, bestValue, net, incomplete, perPoint = {chance|nil, cost|nil, estimate=true}|nil, oldestAge|nil }`
  - `Evaluate.wantedItems(recipe, itemInfo, lookupDisenchant) -> { itemID... }` — unique ids whose prices are needed (reagents, output, disenchant results)
  - `itemInfo` returning nil means "item data not loaded yet": vendor and disenchant are then `unknown`.
  - `bindType == 1` (bind on pickup) makes the AH option `na`.

- [ ] **Step 1: Write the failing tests**

```lua file=tests/test_evaluate.lua
local H = ...

local function load()
    return H.newNS("Util", "Core", "Data/Skillup", "Data/Disenchant", "Evaluate")
end

local RECIPE = {
    recipeID = 1, name = "Sword", difficulty = "medium", outputItemID = 100, outputQty = 1,
    reagents = { { itemID = 1, qty = 2 }, { itemID = 2, qty = 1 } },
}

local DE_ENTRIES = { { itemID = 200, chance = 1, min = 1, max = 1 } }

-- unit price and age (seconds) per item
local function prices(over)
    local map = { [1] = { 100, 60 }, [2] = { 50, 120 }, [100] = { 1000, 30 }, [200] = { 400, 10 } }
    for k, v in pairs(over or {}) do map[k] = v end
    return function(id)
        local row = map[id]
        if row == nil then return nil end
        if type(row) ~= "table" then return row end
        return row[1], row[2]
    end
end

local function info(over)
    local t = { quality = 2, ilvl = 15, sellPrice = 200, classID = 2, bindType = 2 }
    for k, v in pairs(over or {}) do t[k] = v end
    return function() return t end
end

local function ctx(over)
    local c = {
        recipe = RECIPE, priceOf = prices(), itemInfo = info(), cut = 0.05, showPerPoint = false,
        lookupDisenchant = function() return DE_ENTRIES end,
    }
    for k, v in pairs(over or {}) do c[k] = v end
    return c
end

H.test("a fully priced recipe gives cost, every option, the best one and the net", function()
    local E = load().Evaluate
    local r = E.run(ctx())
    H.eq(r.cost.total, 250)
    H.eq(r.cost.missing, {})
    H.eq(r.cost.lines[1], { itemID = 1, qty = 2, unit = 100, subtotal = 200 })
    H.eq(r.options.ah, { status = "ok", value = 950 })
    H.eq(r.options.vendor, { status = "ok", value = 200 })
    H.eq(r.options.disenchant, { status = "ok", value = 380 })
    H.eq(r.best, "ah")
    H.eq(r.bestValue, 950)
    H.eq(r.net, 700)
    H.eq(r.incomplete, false)
    H.eq(r.oldestAge, 120)
    H.eq(r.perPoint, nil)
end)

H.test("one unpriced reagent makes the result incomplete, never cheap", function()
    local E = load().Evaluate
    local r = E.run(ctx({ priceOf = prices({ [2] = false }) }))
    H.eq(r.cost.total, nil)
    H.eq(r.cost.missing, { 2 })
    H.eq(r.cost.lines[2].unit, nil)
    H.eq(r.net, nil)
    H.eq(r.incomplete, true)
    H.eq(r.best, "ah")
end)

H.test("NaN, negative and string prices are treated as unknown", function()
    local E = load().Evaluate
    for _, bad in ipairs({ 0 / 0, -1, "9", 1 / 0 }) do
        local r = E.run(ctx({ priceOf = prices({ [1] = bad }) }))
        H.eq(r.cost.total, nil)
        H.eq(r.incomplete, true)
    end
end)

H.test("an invalid age is ignored when finding the oldest price", function()
    local E = load().Evaluate
    local r = E.run(ctx({ priceOf = prices({ [1] = { 100, 0 / 0 }, [2] = { 50, 5 } }) }))
    H.eq(r.oldestAge, 30)
end)

H.test("item data that is not loaded yet leaves vendor and disenchant unknown", function()
    local E = load().Evaluate
    local r = E.run(ctx({ itemInfo = function() return nil end }))
    H.eq(r.options.vendor.status, "unknown")
    H.eq(r.options.disenchant.status, "unknown")
    H.eq(r.options.ah.status, "ok")
    H.eq(r.incomplete, true)
end)

H.test("a bind-on-pickup result cannot be sold on the AH", function()
    local E = load().Evaluate
    local r = E.run(ctx({ itemInfo = info({ bindType = 1 }) }))
    H.eq(r.options.ah.status, "na")
    H.eq(r.best, "disenchant")
end)

H.test("a vendor price of 0 means the vendor will not buy it", function()
    local E = load().Evaluate
    H.eq(E.run(ctx({ itemInfo = info({ sellPrice = 0 }) })).options.vendor.status, "na")
end)

H.test("items that cannot be disenchanted have no disenchant option", function()
    local E = load().Evaluate
    H.eq(E.run(ctx({ itemInfo = info({ classID = 0 }) })).options.disenchant.status, "na")
    H.eq(E.run(ctx({ itemInfo = info({ quality = 1 }) })).options.disenchant.status, "na")
    H.eq(E.run(ctx({ itemInfo = info({ classID = 0 }) })).incomplete, false)
end)

H.test("missing disenchant data or an unpriced result is unknown, not zero", function()
    local E = load().Evaluate
    local noData = E.run(ctx({ lookupDisenchant = function() return nil end }))
    H.eq(noData.options.disenchant.status, "unknown")
    H.eq(noData.incomplete, true)
    local noPrice = E.run(ctx({ priceOf = prices({ [200] = false }) }))
    H.eq(noPrice.options.disenchant.status, "unknown")
end)

H.test("the output quantity scales every sale option", function()
    local E = load().Evaluate
    local recipe = { recipeID = 1, name = "x", outputItemID = 100, outputQty = 2, reagents = RECIPE.reagents }
    local r = E.run(ctx({ recipe = recipe }))
    H.eq(r.options.ah.value, 1900)
    H.eq(r.options.vendor.value, 400)
    H.eq(r.options.disenchant.value, 760)
end)

H.test("a loss is a negative net", function()
    local E = load().Evaluate
    local r = E.run(ctx({ priceOf = prices({ [100] = { 100, 1 } }), itemInfo = info({ sellPrice = 10, classID = 0 }) }))
    H.eq(r.best, "ah")
    H.eq(r.net, 95 - 250)
end)

H.test("nothing sellable gives no best option and no net", function()
    local E = load().Evaluate
    local r = E.run(ctx({ itemInfo = info({ bindType = 1, sellPrice = 0, classID = 0 }) }))
    H.eq(r.best, nil)
    H.eq(r.net, nil)
    H.eq(r.incomplete, false)
end)

H.test("cost per skill point uses the difficulty and recovers the best sale", function()
    local E = load().Evaluate
    local r = E.run(ctx({ showPerPoint = true }))
    -- (250 - 950) / 0.75 = -933.33
    H.eq(r.perPoint, { chance = 0.75, cost = -933, estimate = true })
end)

H.test("cost per skill point handles trivial and unknown difficulty", function()
    local E = load().Evaluate
    local function with(difficulty)
        local recipe = { recipeID = 1, name = "x", difficulty = difficulty, outputItemID = 100, outputQty = 1, reagents = RECIPE.reagents }
        return E.run(ctx({ recipe = recipe, showPerPoint = true })).perPoint
    end
    H.eq(with("trivial"), { chance = 0, cost = nil, estimate = true })
    H.eq(with(nil), { chance = nil, cost = nil, estimate = true })
end)

H.test("wantedItems lists reagents, the output and disenchant results once", function()
    local E = load().Evaluate
    H.eq(E.wantedItems(RECIPE, info(), function() return DE_ENTRIES end), { 1, 2, 100, 200 })
    H.eq(E.wantedItems(RECIPE, function() return nil end, function() return DE_ENTRIES end), { 1, 2, 100 })
    H.eq(E.wantedItems(RECIPE, info({ classID = 0 }), function() return DE_ENTRIES end), { 1, 2, 100 })
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `luajit tests/run.lua`
Expected: FAIL in `tests/test_evaluate.lua` (cannot open `CraftProfit/Evaluate.lua`).

- [ ] **Step 3: Implement `Evaluate`**

```lua file=CraftProfit/Evaluate.lua
-- Combines a recipe, prices and item facts into one profit result.
-- Pure Lua, no WoW API: the caller passes lookups as functions.
local _, ns = ...
local Util, Core = ns.Util, ns.Core
local Skillup, Disenchant = ns.Data.Skillup, ns.Data.Disenchant

local Evaluate = {}
ns.Evaluate = Evaluate

local BIND_ON_PICKUP = 1

-- Returns "ok", entries | "na" | "unknown" for the disenchant results of an item.
local function disenchantEntries(info, lookup)
    if not info then return "unknown" end
    if not Disenchant.canDisenchant(info.itemID, info.quality, info.classID) then return "na" end
    local entries = lookup(Disenchant.kindOf(info.classID), info.quality, info.ilvl)
    if not entries then return "unknown" end
    return "ok", entries
end

-- Adds the item id to the info table without mutating the caller's table.
local function withID(info, itemID)
    if not info then return nil end
    return {
        itemID = itemID, quality = info.quality, ilvl = info.ilvl,
        sellPrice = info.sellPrice, classID = info.classID, bindType = info.bindType,
    }
end

function Evaluate.run(ctx)
    local recipe, cut = ctx.recipe, ctx.cut
    local oldest

    -- Price lookup that ignores anything that is not a usable copper amount and
    -- remembers the oldest valid age seen.
    local function priceOf(itemID)
        local unit, age = ctx.priceOf(itemID)
        if not Util.isCopper(unit) then return nil end
        if Util.isFinite(age) and (oldest == nil or age > oldest) then oldest = age end
        return unit
    end

    local lines = {}
    for _, r in ipairs(recipe.reagents) do
        local unit = priceOf(r.itemID)
        lines[#lines + 1] = {
            itemID = r.itemID, qty = r.qty, unit = unit, subtotal = unit and unit * r.qty or nil,
        }
    end
    local total, missing = Core.sumCost(recipe.reagents, priceOf)

    local info = withID(ctx.itemInfo(recipe.outputItemID), recipe.outputItemID)
    local qty = recipe.outputQty
    local options = {}

    if info and info.bindType == BIND_ON_PICKUP then
        options.ah = { status = "na" }
    else
        local value = Core.netSale(priceOf(recipe.outputItemID), qty, cut)
        options.ah = value and { status = "ok", value = value } or { status = "unknown" }
    end

    if not info then
        options.vendor = { status = "unknown" }
    elseif not Util.isCopper(info.sellPrice) or info.sellPrice == 0 then
        options.vendor = { status = "na" }
    else
        options.vendor = { status = "ok", value = Core.vendorValue(info.sellPrice, qty) }
    end

    local state, entries = disenchantEntries(info, ctx.lookupDisenchant)
    if state == "ok" then
        local value = Core.disenchantValue(entries, priceOf, cut)
        if value then
            options.disenchant = { status = "ok", value = Util.round(value * qty) }
        else
            options.disenchant = { status = "unknown" }
        end
    else
        options.disenchant = { status = state }
    end

    local best, bestValue, optionsIncomplete = Core.bestOption(options)
    local net
    if total and bestValue then net = bestValue - total end

    local perPoint
    if ctx.showPerPoint then
        local chance = Skillup.chance(recipe.difficulty)
        perPoint = { chance = chance, estimate = true }
        if total and chance then
            perPoint.cost = Core.costPerPoint(total, bestValue, chance)
        end
    end

    return {
        recipe = recipe,
        cost = { total = total, missing = missing or {}, lines = lines },
        options = options,
        best = best,
        bestValue = bestValue,
        net = net,
        incomplete = optionsIncomplete or total == nil,
        perPoint = perPoint,
        oldestAge = oldest,
    }
end

-- Item ids whose prices are needed to evaluate the recipe, each listed once.
function Evaluate.wantedItems(recipe, itemInfo, lookupDisenchant)
    local ids, seen = {}, {}
    local function add(id)
        if not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    for _, r in ipairs(recipe.reagents) do add(r.itemID) end
    add(recipe.outputItemID)
    local info = withID(itemInfo(recipe.outputItemID), recipe.outputItemID)
    local state, entries = disenchantEntries(info, lookupDisenchant)
    if state == "ok" then
        for _, e in ipairs(entries) do add(e.itemID) end
    end
    return ids
end
```

- [ ] **Step 4: Run the tests and luacheck**

Run: `sh tests/check.sh`
Expected: all pass, luacheck clean.

- [ ] **Step 5: Commit**

```bash
git add CraftProfit/Evaluate.lua tests/test_evaluate.lua
git commit -m "feat: add Evaluate combining recipe, prices and item facts"
```

---

### Task 12: `Present` (result → display model)

**Files:**
- Create: `CraftProfit/Present.lua`
- Test: `tests/test_present.lua`

**Interfaces:**
- Consumes: `Evaluate` result shape, `Core.OPTION_ORDER`, `Format.age`, `Util.isFinite`, `ns.L`-shaped table, `fmt(copper) -> string`
- Produces:
  - `Present.durationText(L, seconds) -> string|nil` ("5m", "3h"; nil when invalid)
  - `Present.ageText(L, age) -> string`
  - `Present.build(result, L, fmt, opts) -> model` with `opts = {staleAfter=seconds}` and
    `model = { lines = { {label, value, key, best} }, costLines = { {itemID, qty, unitText, subtotalText} }, verdict = {kind="profit"|"loss"|"incomplete"|"none", text, value}, ageText, stale }` where `key` is `"cost"|"ah"|"vendor"|"disenchant"|"perpoint"`

- [ ] **Step 1: Write the failing tests**

```lua file=tests/test_present.lua
local H = ...

local function load()
    local ns = H.newNS("Util", "Format", "Core", "Data/Skillup", "Data/Disenchant", "Evaluate", "Present",
        "Locale", "Locales/enUS", "Locales/frFR")
    ns.Locale.select("enUS")
    return ns
end

local RECIPE = {
    recipeID = 1, name = "Sword", difficulty = "medium", outputItemID = 100, outputQty = 1,
    reagents = { { itemID = 1, qty = 2 }, { itemID = 2, qty = 1 } },
}

local function run(ns, over)
    local map = { [1] = { 100, 60 }, [2] = { 50, 120 }, [100] = { 1000, 30 }, [200] = { 400, 10 } }
    local ctx = {
        recipe = RECIPE,
        priceOf = function(id) local r = map[id]; if r then return r[1], r[2] end end,
        itemInfo = function() return { quality = 2, ilvl = 15, sellPrice = 200, classID = 2, bindType = 2 } end,
        cut = 0.05, showPerPoint = false,
        lookupDisenchant = function() return { { itemID = 200, chance = 1, min = 1, max = 1 } } end,
    }
    for k, v in pairs(over or {}) do ctx[k] = v end
    return ns.Evaluate.run(ctx)
end

local function model(ns, over, opts)
    return ns.Present.build(run(ns, over), ns.L, ns.Format.money, opts)
end

H.test("lines show cost and every option, marking the best", function()
    local ns = load()
    local m = model(ns)
    H.eq(m.lines[1], { label = "Materials", value = "2s 50c", key = "cost", best = false })
    H.eq(m.lines[2], { label = "Auction house (net)", value = "9s 50c", key = "ah", best = true })
    H.eq(m.lines[3], { label = "Vendor", value = "2s", key = "vendor", best = false })
    H.eq(m.lines[4], { label = "Disenchant (expected)", value = "3s 80c", key = "disenchant", best = false })
    H.eq(#m.lines, 4)
end)

H.test("costLines detail each reagent for the materials tooltip", function()
    local ns = load()
    H.eq(model(ns).costLines, {
        { itemID = 1, qty = 2, unitText = "1s", subtotalText = "2s" },
        { itemID = 2, qty = 1, unitText = "50c", subtotalText = "50c" },
    })
    local missing = model(ns, { priceOf = function(id) if id == 2 then return nil end return 100, 1 end })
    H.eq(missing.costLines[2], { itemID = 2, qty = 1, unitText = "?", subtotalText = "?" })
end)

H.test("a profitable best option gives a profit verdict with a plus sign", function()
    local ns = load()
    H.eq(model(ns).verdict, { kind = "profit", text = "Best: Auction house", value = "+7s" })
end)

H.test("a loss gives a loss verdict", function()
    local ns = load()
    local m = model(ns, { priceOf = function(id) if id == 100 then return 100, 1 end return 100, 1 end,
        itemInfo = function() return { quality = 1, ilvl = 1, sellPrice = 0, classID = 0, bindType = 2 } end })
    H.eq(m.verdict.kind, "loss")
    H.eq(m.verdict.text, "Best: Auction house")
    H.eq(m.verdict.value, "-2s 5c")
end)

H.test("a missing price gives an incomplete verdict without a number", function()
    local ns = load()
    local m = model(ns, { priceOf = function(id) if id == 2 then return nil end return 100, 1 end })
    H.eq(m.verdict, { kind = "incomplete", text = "Incomplete: prices missing", value = "" })
    H.eq(m.lines[1].value, "?")
end)

H.test("an unknown option with a known cost shows the best known one as partial", function()
    local ns = load()
    local m = model(ns, { itemInfo = function() return nil end })
    H.eq(m.verdict.kind, "incomplete")
    H.eq(m.verdict.text, "Best known: Auction house (prices missing)")
    H.eq(m.verdict.value, "+7s")
    H.eq(m.lines[3].value, "?")
    H.eq(m.lines[4].value, "?")
end)

H.test("nothing sellable gives the none verdict and n/a lines", function()
    local ns = load()
    local m = model(ns, { itemInfo = function() return { quality = 1, ilvl = 1, sellPrice = 0, classID = 0, bindType = 1 } end })
    H.eq(m.verdict, { kind = "none", text = "No way to sell this item", value = "" })
    H.eq(m.lines[2].value, "n/a")
    H.eq(m.lines[3].value, "n/a")
    H.eq(m.lines[4].value, "n/a")
end)

H.test("the per-point line is labelled as an estimate", function()
    local ns = load()
    local m = model(ns, { showPerPoint = true })
    H.eq(m.lines[5], { label = "Cost per skill point", value = "-9s 33c (estimate)", key = "perpoint", best = false })
end)

H.test("the per-point line shows n/a for trivial recipes and ? for unknown difficulty", function()
    local ns = load()
    local trivial = { recipeID = 1, name = "x", difficulty = "trivial", outputItemID = 100, outputQty = 1, reagents = RECIPE.reagents }
    local unknown = { recipeID = 1, name = "x", outputItemID = 100, outputQty = 1, reagents = RECIPE.reagents }
    H.eq(model(ns, { recipe = trivial, showPerPoint = true }).lines[5].value, "n/a")
    H.eq(model(ns, { recipe = unknown, showPerPoint = true }).lines[5].value, "?")
end)

H.test("ageText localizes the unit and handles a missing age", function()
    local ns = load()
    H.eq(ns.Present.ageText(ns.L, 65), "Prices: 1m ago")
    H.eq(ns.Present.ageText(ns.L, 3 * 3600), "Prices: 3h ago")
    H.eq(ns.Present.ageText(ns.L, nil), "Prices: never scanned")
    H.eq(ns.Present.ageText(ns.L, -5), "Prices: never scanned")
    ns.Locale.select("frFR")
    H.eq(ns.Present.ageText(ns.L, 65), "Prix : il y a 1min")
end)

H.test("durationText formats a duration or returns nil", function()
    local ns = load()
    H.eq(ns.Present.durationText(ns.L, 65), "1m")
    H.eq(ns.Present.durationText(ns.L, 900), "15m")
    H.eq(ns.Present.durationText(ns.L, nil), nil)
    H.eq(ns.Present.durationText(ns.L, 0 / 0), nil)
end)

H.test("prices older than staleAfter, or unknown, are flagged stale", function()
    local ns = load()
    H.eq(model(ns, nil, { staleAfter = 3600 }).stale, false)
    H.eq(model(ns, nil, { staleAfter = 100 }).stale, true)
    H.eq(model(ns, { priceOf = function() return nil end }, { staleAfter = 3600 }).stale, true)
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `luajit tests/run.lua`
Expected: FAIL in `tests/test_present.lua` (cannot open `CraftProfit/Present.lua`).

- [ ] **Step 3: Implement `Present`**

```lua file=CraftProfit/Present.lua
-- Turns an Evaluate result into text for the window. Pure Lua, no WoW API:
-- L is the locale table and fmt formats copper (both injected).
local _, ns = ...
local Util, Core, Format = ns.Util, ns.Core, ns.Format

local Present = {}
ns.Present = Present

local LINE_KEYS = { ah = "LINE_AH", vendor = "LINE_VENDOR", disenchant = "LINE_DISENCHANT" }
local NAME_KEYS = { ah = "NAME_AH", vendor = "NAME_VENDOR", disenchant = "NAME_DISENCHANT" }
local UNIT_KEYS = { sec = "AGE_SEC", min = "AGE_MIN", hour = "AGE_HOUR", day = "AGE_DAY" }

local DEFAULT_STALE = 3600

-- "5m", "3h"... in the client language; nil for an invalid duration.
function Present.durationText(L, seconds)
    local n, unit = Format.age(seconds)
    if not n then return nil end
    return string.format(L[UNIT_KEYS[unit]], n)
end

function Present.ageText(L, age)
    local text = Present.durationText(L, age)
    if not text then return L.AGE_NEVER end
    return string.format(L.AGE, text)
end

local function signed(fmt, n)
    local text = fmt(n)
    if n > 0 then return "+" .. text end
    return text
end

local function perPointValue(L, fmt, perPoint)
    if perPoint.chance == nil then return L.UNKNOWN end
    if perPoint.chance == 0 then return L.NA end
    if perPoint.cost == nil then return L.UNKNOWN end
    return fmt(perPoint.cost) .. " (" .. L.ESTIMATE .. ")"
end

local function verdictFor(result, L, fmt)
    if result.net == nil and result.best == nil and not result.incomplete then
        return { kind = "none", text = L.VERDICT_NONE, value = "" }
    end
    if result.net == nil then
        return { kind = "incomplete", text = L.VERDICT_INCOMPLETE, value = "" }
    end
    local name = L[NAME_KEYS[result.best]]
    if result.incomplete then
        return {
            kind = "incomplete",
            text = string.format(L.VERDICT_PARTIAL, name),
            value = signed(fmt, result.net),
        }
    end
    return {
        kind = result.net >= 0 and "profit" or "loss",
        text = string.format(L.VERDICT_BEST, name),
        value = signed(fmt, result.net),
    }
end

function Present.build(result, L, fmt, opts)
    local staleAfter = opts and opts.staleAfter or DEFAULT_STALE
    local lines = {}
    lines[1] = { label = L.MATERIALS, value = fmt(result.cost.total), key = "cost", best = false }
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
        lines[#lines + 1] = { label = L[LINE_KEYS[key]], value = text, key = key, best = result.best == key }
    end
    if result.perPoint then
        lines[#lines + 1] = {
            label = L.PER_POINT, value = perPointValue(L, fmt, result.perPoint),
            key = "perpoint", best = false,
        }
    end
    local costLines = {}
    for i, line in ipairs(result.cost.lines) do
        costLines[i] = {
            itemID = line.itemID, qty = line.qty,
            unitText = fmt(line.unit), subtotalText = fmt(line.subtotal),
        }
    end
    return {
        lines = lines,
        costLines = costLines,
        verdict = verdictFor(result, L, fmt),
        ageText = Present.ageText(L, result.oldestAge),
        stale = not Util.isFinite(result.oldestAge) or result.oldestAge > staleAfter,
    }
end
```

- [ ] **Step 4: Run the tests and luacheck**

Run: `sh tests/check.sh`
Expected: all pass, luacheck clean.

- [ ] **Step 5: Commit**

```bash
git add CraftProfit/Present.lua tests/test_present.lua
git commit -m "feat: add Present display model"
```

---

### Task 13: `AHAdapter` (auction house events and reads)

This is the only file that talks to `C_AuctionHouse`. It converts the game's results into plain `{unit, qty}` listings for `Prices`/`PriceQueue`, and feeds the full scan to a `Prices` aggregator in chunks so the client never freezes.

**Before writing code:** read `docs/probe-findings.md` F1, F2, F7, F8. This task's code supports **both** search styles (commodity and item results) and reads the stack-price convention from one constant. If F1 shows a different event or field name than the code below, change only the names in `readCommodity`, `readItem` and `EVENTS`, and keep the tests' structure.

**Files:**
- Create: `CraftProfit/AHAdapter.lua`
- Test: `tests/test_ahadapter.lua`

**Interfaces:**
- Consumes: `Util.*`, `Prices.newAggregator`; globals `C_AuctionHouse`, `C_Timer`, `Enum`, `CreateFrame`, `GetTime`, `issecretvalue`
- Produces (`ns.AH`):
  - `AH.isOpen` (boolean)
  - `AH.setHandlers({ onOpen = fn(open), onSearch = fn(itemID, listings), onSnapshot = fn(aggregator, totalRows) })`
  - `AH.search(itemID) -> boolean` (false when the AH is closed or throttled; result arrives later through `onSearch`)
  - `AH.requestSnapshot(now) -> true` or `-> false, "closed"|"unavailable"|"cooldown", secondsLeft`
  - `AH.cooldownLeft(now) -> seconds`
  - `AH.onEvent(event, arg1)`; constants `AH.PER_UNIT_REPLICATE` (F2), `AH.CHUNK = 1500`, `AH.REPLICATE_COOLDOWN = 900`, `AH.MAX_SEARCH_RESULTS = 100`
  - `listings = { {unit=copper, qty=number}, ... }`, sorted by the game by ascending price

- [ ] **Step 1: Write the failing tests**

```lua file=tests/test_ahadapter.lua
local H = ...

-- Loads AHAdapter in a fake game environment. Returns a table with the adapter,
-- what the handlers received, the calls the adapter made, and helpers.
local function setup(apiOver)
    local ns = H.newNS("Util", "Prices")
    local env = setmetatable({}, { __index = _G })
    local T = { clock = 100, queued = {}, calls = {}, frames = {}, opens = {}, searches = {}, snapshots = {} }
    env.GetTime = function() return T.clock end
    env.CreateFrame = function()
        local f = { events = {}, scripts = {} }
        function f.RegisterEvent(_, e) f.events[#f.events + 1] = e end
        function f.SetScript(_, name, fn) f.scripts[name] = fn end
        T.frames[#T.frames + 1] = f
        return f
    end
    env.C_Timer = { After = function(_, fn) T.queued[#T.queued + 1] = fn end }
    env.Enum = { AuctionHouseSortOrder = { Price = 4 } }
    env.C_AuctionHouse = {
        MakeItemKey = function(id) return { itemID = id } end,
        SendSearchQuery = function(key, sorts, separate)
            T.calls[#T.calls + 1] = { "search", key.itemID, sorts, separate }
        end,
        IsThrottledMessageSystemReady = function() return true end,
        ReplicateItems = function() T.calls[#T.calls + 1] = { "replicate" } end,
        GetNumReplicateItems = function() return 0 end,
        GetReplicateItemInfo = function() end,
    }
    for k, v in pairs(apiOver or {}) do env.C_AuctionHouse[k] = v end
    H.loadModule("AHAdapter", ns, env)
    local AH = ns.AH
    AH.setHandlers({
        onOpen = function(open) T.opens[#T.opens + 1] = open end,
        onSearch = function(id, listings) T.searches[#T.searches + 1] = { id, listings } end,
        onSnapshot = function(agg, total) T.snapshots[#T.snapshots + 1] = { agg, total } end,
    })
    T.AH, T.env = AH, env
    -- Runs every callback scheduled with C_Timer.After, including ones they schedule.
    function T.run()
        while #T.queued > 0 do table.remove(T.queued, 1)() end
    end
    return T
end

-- 17-value rows like GetReplicateItemInfo: only count, buyout and itemID matter.
local function replicate(rows)
    return {
        GetNumReplicateItems = function() return #rows end,
        GetReplicateItemInfo = function(i)
            local r = rows[i]
            return "name", 0, r.count, 1, true, 1, 0, 0, 0, r.buyout, 0, false, "", "o", "o", 0, r.itemID, true
        end,
    }
end

H.test("the adapter registers the events it needs on load", function()
    local T = setup()
    local seen = {}
    for _, e in ipairs(T.frames[1].events) do seen[e] = true end
    for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "COMMODITY_SEARCH_RESULTS_UPDATED",
        "ITEM_SEARCH_RESULTS_UPDATED", "REPLICATE_ITEM_LIST_UPDATE" }) do
        H.truthy(seen[e] or error("event not registered: " .. e))
    end
    H.truthy(T.frames[1].scripts.OnEvent)
end)

H.test("opening and closing the AH is tracked and reported", function()
    local T = setup()
    H.eq(T.AH.isOpen, false)
    T.AH.onEvent("AUCTION_HOUSE_SHOW")
    H.eq(T.AH.isOpen, true)
    T.AH.onEvent("AUCTION_HOUSE_CLOSED")
    H.eq(T.AH.isOpen, false)
    H.eq(T.opens, { true, false })
end)

H.test("search needs an open, unthrottled AH and sends a price-sorted query", function()
    local T = setup()
    H.eq(T.AH.search(7), false)
    T.AH.onEvent("AUCTION_HOUSE_SHOW")
    H.eq(T.AH.search(7), true)
    H.eq(T.calls[1], { "search", 7, { { sortOrder = 4, reverseSort = false } }, true })
    T.env.C_AuctionHouse.IsThrottledMessageSystemReady = function() return false end
    H.eq(T.AH.search(8), false)
    H.eq(#T.calls, 1)
end)

H.test("search reports failure instead of raising when the API errors", function()
    local T = setup({ SendSearchQuery = function() error("boom") end })
    T.AH.onEvent("AUCTION_HOUSE_SHOW")
    H.eq(T.AH.search(7), false)
end)

H.test("commodity results become unit/qty listings", function()
    local T = setup({
        GetNumCommoditySearchResults = function() return 2 end,
        GetCommoditySearchResultInfo = function(_, i)
            return ({ { unitPrice = 100, quantity = 5 }, { unitPrice = 120, quantity = 1 } })[i]
        end,
    })
    T.AH.onEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 7)
    H.eq(T.searches, { { 7, { { unit = 100, qty = 5 }, { unit = 120, qty = 1 } } } })
end)

H.test("item results use the buyout per unit and skip bid-only auctions", function()
    local T = setup({
        GetNumItemSearchResults = function() return 3 end,
        GetItemSearchResultInfo = function(_, i)
            return ({ { buyoutAmount = 100, quantity = 1 }, { buyoutAmount = 100, quantity = 2 }, { quantity = 1 } })[i]
        end,
    })
    T.AH.onEvent("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 7 })
    H.eq(T.searches, { { 7, { { unit = 100, qty = 1 }, { unit = 50, qty = 2 } } } })
end)

H.test("search results are capped and invalid events are ignored", function()
    local T = setup({
        GetNumCommoditySearchResults = function() return 250 end,
        GetCommoditySearchResultInfo = function() return { unitPrice = 1, quantity = 1 } end,
    })
    T.AH.onEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 7)
    H.eq(#T.searches[1][2], T.AH.MAX_SEARCH_RESULTS)
    T.AH.onEvent("COMMODITY_SEARCH_RESULTS_UPDATED", "x")
    T.AH.onEvent("ITEM_SEARCH_RESULTS_UPDATED", nil)
    T.AH.onEvent("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 0 / 0 })
    H.eq(#T.searches, 1)
end)

H.test("secret search values are skipped", function()
    local T = setup({
        GetNumCommoditySearchResults = function() return 2 end,
        GetCommoditySearchResultInfo = function(_, i)
            return ({ { unitPrice = "SECRET", quantity = 1 }, { unitPrice = 90, quantity = 1 } })[i]
        end,
    })
    T.env.issecretvalue = function(v) return v == "SECRET" end
    T.AH.onEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 7)
    H.eq(T.searches[1][2], { { unit = 90, qty = 1 } })
end)

H.test("a full scan is read in chunks and aggregated per item", function()
    local T = setup(replicate({
        { itemID = 1, count = 1, buyout = 100 },
        { itemID = 1, count = 1, buyout = 300 },
        { itemID = 2, count = 5, buyout = 500 },
        { itemID = 3, count = 1, buyout = 0 },
        { itemID = 4, count = 0, buyout = 10 },
    }))
    T.AH.CHUNK = 2
    T.AH.onEvent("REPLICATE_ITEM_LIST_UPDATE")
    H.eq(#T.snapshots, 0)
    T.run()
    H.eq(#T.snapshots, 1)
    H.eq(T.snapshots[1][2], 5)
    H.eq(T.snapshots[1][1].result(5), {
        [1] = { unit = 200, volume = 2 },
        [2] = { unit = 100, volume = 5 },
    })
end)

H.test("a stack buyout is divided per unit unless the client reports per-unit prices", function()
    local T = setup(replicate({ { itemID = 2, count = 5, buyout = 500 } }))
    T.AH.PER_UNIT_REPLICATE = true
    T.AH.onEvent("REPLICATE_ITEM_LIST_UPDATE")
    T.run()
    H.eq(T.snapshots[1][1].result(5)[2], { unit = 500, volume = 5 })
end)

H.test("secret scan rows are skipped", function()
    local T = setup(replicate({
        { itemID = 1, count = "SECRET", buyout = 100 },
        { itemID = 2, count = 1, buyout = 40 },
    }))
    T.env.issecretvalue = function(v) return v == "SECRET" end
    T.AH.onEvent("REPLICATE_ITEM_LIST_UPDATE")
    T.run()
    H.eq(T.snapshots[1][1].result(5), { [2] = { unit = 40, volume = 1 } })
end)

H.test("closing the AH abandons a scan in progress", function()
    local T = setup(replicate({
        { itemID = 1, count = 1, buyout = 100 }, { itemID = 2, count = 1, buyout = 100 },
        { itemID = 3, count = 1, buyout = 100 },
    }))
    T.AH.CHUNK = 1
    T.AH.onEvent("AUCTION_HOUSE_SHOW")
    T.AH.onEvent("REPLICATE_ITEM_LIST_UPDATE")
    T.AH.onEvent("AUCTION_HOUSE_CLOSED")
    T.run()
    H.eq(#T.snapshots, 0)
end)

H.test("a new scan supersedes one still being read", function()
    local T = setup(replicate({
        { itemID = 1, count = 1, buyout = 100 }, { itemID = 2, count = 1, buyout = 100 },
    }))
    T.AH.CHUNK = 1
    T.AH.onEvent("REPLICATE_ITEM_LIST_UPDATE")
    T.AH.onEvent("REPLICATE_ITEM_LIST_UPDATE")
    T.run()
    H.eq(#T.snapshots, 1)
end)

H.test("an empty scan produces no snapshot", function()
    local T = setup()
    T.AH.onEvent("REPLICATE_ITEM_LIST_UPDATE")
    T.run()
    H.eq(#T.snapshots, 0)
end)

H.test("requestSnapshot respects the AH state and the 15 minute cooldown", function()
    local T = setup()
    H.eq({ T.AH.requestSnapshot(100) }, { false, "closed" })
    T.AH.onEvent("AUCTION_HOUSE_SHOW")
    H.eq({ T.AH.requestSnapshot(100) }, { true })
    H.eq(T.calls[1], { "replicate" })
    H.eq({ T.AH.requestSnapshot(400) }, { false, "cooldown", 600 })
    H.eq({ T.AH.requestSnapshot(1000) }, { true })
end)

H.test("a scan started by another addon also starts the cooldown", function()
    local T = setup()
    T.AH.onEvent("AUCTION_HOUSE_SHOW")
    T.clock = 100
    T.AH.onEvent("REPLICATE_ITEM_LIST_UPDATE")
    H.eq({ T.AH.requestSnapshot(400) }, { false, "cooldown", 600 })
end)

H.test("requestSnapshot reports an unavailable API", function()
    local T = setup({ ReplicateItems = false })
    T.AH.onEvent("AUCTION_HOUSE_SHOW")
    H.eq({ T.AH.requestSnapshot(100) }, { false, "unavailable" })
    H.eq(T.AH.cooldownLeft(0 / 0), 0)
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `luajit tests/run.lua`
Expected: FAIL in `tests/test_ahadapter.lua` (cannot open `CraftProfit/AHAdapter.lua`).

- [ ] **Step 3: Implement `AHAdapter`**

```lua file=CraftProfit/AHAdapter.lua
-- Auction house adapter: the only file that talks to C_AuctionHouse.
-- It turns the game's results into plain { unit, qty } listings.
local _, ns = ...
local Util, Prices = ns.Util, ns.Prices

local AH = {}
ns.AH = AH

AH.isOpen = false
-- docs/probe-findings.md F2: does GetReplicateItemInfo's buyoutPrice already
-- hold the price of ONE unit? false = it is the price of the whole stack.
AH.PER_UNIT_REPLICATE = false
AH.CHUNK = 1500             -- scan rows read per frame
AH.REPLICATE_COOLDOWN = 15 * 60
AH.MAX_SEARCH_RESULTS = 100 -- results come sorted by price; the cheapest are enough

local EVENTS = {
    "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
    "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
    "REPLICATE_ITEM_LIST_UPDATE",
}

local handlers = {}
local snapshotToken = 0
local lastReplicate

function AH.setHandlers(h)
    handlers = h or {}
end

local function isSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) or false
end

-- Seconds before another full scan is allowed (Blizzard limits it account-wide).
function AH.cooldownLeft(now)
    if not lastReplicate or not Util.isFinite(now) then return 0 end
    local left = AH.REPLICATE_COOLDOWN - (now - lastReplicate)
    if left > 0 then return left end
    return 0
end

function AH.requestSnapshot(now)
    if not AH.isOpen then return false, "closed" end
    local api = C_AuctionHouse
    if not api or not api.ReplicateItems then return false, "unavailable" end
    local left = AH.cooldownLeft(now)
    if left > 0 then return false, "cooldown", left end
    if not pcall(api.ReplicateItems) then return false, "unavailable" end
    lastReplicate = now
    return true
end

-- Sends a price-sorted search. The answer arrives through handlers.onSearch.
function AH.search(itemID)
    local api = C_AuctionHouse
    if not AH.isOpen or not api or not api.SendSearchQuery or not api.MakeItemKey then return false end
    if api.IsThrottledMessageSystemReady and not api.IsThrottledMessageSystemReady() then return false end
    local sorts = {}
    local price = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price
    if price ~= nil then sorts = { { sortOrder = price, reverseSort = false } } end
    return pcall(function()
        api.SendSearchQuery(api.MakeItemKey(itemID), sorts, true)
    end)
end

local function readCommodity(itemID)
    local api = C_AuctionHouse
    local listings = {}
    local n = api.GetNumCommoditySearchResults(itemID)
    if isSecret(n) or not Util.isFinite(n) then return listings end
    for i = 1, math.min(n, AH.MAX_SEARCH_RESULTS) do
        local info = api.GetCommoditySearchResultInfo(itemID, i)
        if info and not isSecret(info.unitPrice) and not isSecret(info.quantity) then
            listings[#listings + 1] = { unit = info.unitPrice, qty = info.quantity }
        end
    end
    return listings
end

local function readItem(itemKey)
    local api = C_AuctionHouse
    local listings = {}
    local n = api.GetNumItemSearchResults(itemKey)
    if isSecret(n) or not Util.isFinite(n) then return listings end
    for i = 1, math.min(n, AH.MAX_SEARCH_RESULTS) do
        local info = api.GetItemSearchResultInfo(itemKey, i)
        if info and not isSecret(info.buyoutAmount) and not isSecret(info.quantity) then
            local qty = Util.count(info.quantity or 1)
            if qty and Util.isCopper(info.buyoutAmount) and info.buyoutAmount > 0 then
                listings[#listings + 1] = { unit = info.buyoutAmount / qty, qty = qty }
            end
        end
    end
    return listings
end

-- Reads the full scan in chunks of AH.CHUNK rows per frame so the client never
-- freezes. A newer scan, or closing the AH, abandons the one in progress.
local function readSnapshot()
    local api = C_AuctionHouse
    if not api or not api.GetNumReplicateItems or not api.GetReplicateItemInfo then return end
    local total = api.GetNumReplicateItems()
    if isSecret(total) or not Util.count(total) then return end
    snapshotToken = snapshotToken + 1
    local token = snapshotToken
    local agg = Prices.newAggregator()
    local index = 0
    local function step()
        if token ~= snapshotToken then return end
        local last = math.min(index + AH.CHUNK, total)
        for i = index + 1, last do
            local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = api.GetReplicateItemInfo(i)
            if not (isSecret(count) or isSecret(buyout) or isSecret(itemID)) then
                local qty = Util.count(count)
                if qty and Util.isCopper(buyout) and buyout > 0 then
                    agg.add(itemID, AH.PER_UNIT_REPLICATE and buyout or buyout / qty, qty)
                end
            end
        end
        index = last
        if index < total then
            C_Timer.After(0, step)
        elseif handlers.onSnapshot then
            handlers.onSnapshot(agg, total)
        end
    end
    step()
end

function AH.onEvent(event, arg1)
    if event == "AUCTION_HOUSE_SHOW" then
        AH.isOpen = true
        if handlers.onOpen then handlers.onOpen(true) end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        AH.isOpen = false
        snapshotToken = snapshotToken + 1
        if handlers.onOpen then handlers.onOpen(false) end
    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        local itemID = Util.id(arg1)
        if itemID and handlers.onSearch then handlers.onSearch(itemID, readCommodity(itemID)) end
    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        local itemID = type(arg1) == "table" and Util.id(arg1.itemID)
        if itemID and handlers.onSearch then handlers.onSearch(itemID, readItem(arg1)) end
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        -- Also fires for scans other addons started; they use the same cooldown.
        lastReplicate = GetTime()
        readSnapshot()
    end
end

local frame = CreateFrame("Frame")
for _, event in ipairs(EVENTS) do
    pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event, arg1) AH.onEvent(event, arg1) end)
```

- [ ] **Step 4: Run the tests and luacheck**

Run: `sh tests/check.sh`
Expected: all pass (apart from the disenchant data test if Task 5 Step 8 was not done yet), luacheck clean.

- [ ] **Step 5: Reconcile with the probe findings**

Open `docs/probe-findings.md`. If F2 says the replicate `buyout` is per unit, set `AH.PER_UNIT_REPLICATE = true` in `CraftProfit/AHAdapter.lua`. If F1/F8 show a different event or field name than the code uses, change the names in `EVENTS`, `readCommodity` and `readItem` and the matching fake in `tests/test_ahadapter.lua`. Re-run `sh tests/check.sh`.

- [ ] **Step 6: Commit**

```bash
git add CraftProfit/AHAdapter.lua tests/test_ahadapter.lua
git commit -m "feat: add AHAdapter for AH search and full scan"
```

---

### Task 14: `TradeAdapter` (selected recipe and raw recipe reading)

**Before writing code:** read `docs/probe-findings.md` F3, F4, F7. The code below tries the Mainline Professions UI first (strategy A) and the classic `GetTradeSkill*` API second (strategy B). Keep whichever the probe proved; keep the other only if it costs nothing (it is guarded by `pcall` and presence checks).

**Files:**
- Create: `CraftProfit/TradeAdapter.lua`
- Test: `tests/test_tradeadapter.lua`

**Interfaces:**
- Consumes: `Util.id`; globals `ProfessionsFrame`, `TradeSkillFrame`, `C_TradeSkillUI`, `Enum`, `GetTradeSkill*`, `C_Timer`, `issecretvalue`
- Produces (`ns.Trade`):
  - `Trade.idFromLink(link, ...) -> integer|nil` — first number after any of the given link kinds (`"enchant"`, `"spell"`, `"item"`)
  - `Trade.frame() -> frame|nil`, `Trade.isShown() -> boolean`
  - `Trade.selectedRecipeID() -> integer|nil`
  - `Trade.readSelected() -> raw|nil` — `raw` as accepted by `Recipes.normalize`; nil for an unlearned recipe, a header row, or no selection
  - `Trade.watch(onChange)` — polls every 0.3 s and calls `onChange(recipeID|nil)` when the selection changes; `Trade.invalidate()` forces the next poll to report again

- [ ] **Step 1: Write the failing tests**

```lua file=tests/test_tradeadapter.lua
local H = ...

local function setup()
    local ns = H.newNS("Util")
    local env = setmetatable({}, { __index = _G })
    local T = { tickers = {} }
    env.C_Timer = {
        NewTicker = function(interval, fn)
            T.tickers[#T.tickers + 1] = { interval = interval, fn = fn }
            return T.tickers[#T.tickers]
        end,
    }
    H.loadModule("TradeAdapter", ns, env)
    T.Trade, T.env = ns.Trade, env
    return T
end

-- A fake Mainline Professions window whose selected recipe is `recipeID`.
local function professions(recipeID, shown)
    return {
        IsShown = function() return shown ~= false end,
        CraftingPage = { SchematicForm = {
            GetRecipeInfo = function() return recipeID and { recipeID = recipeID } or nil end,
        } },
    }
end

local BASIC = 1

local function mainlineApi(over)
    local api = {
        GetRecipeInfo = function(id)
            return { recipeID = id, name = "Copper Sword", learned = true, relativeDifficulty = 2 }
        end,
        GetRecipeSchematic = function()
            return {
                outputItemID = 2845, quantityMin = 1, quantityMax = 2,
                reagentSlotSchematics = {
                    { reagentType = BASIC, quantityRequired = 6, reagents = { { itemID = 2840 } } },
                    { reagentType = 0, quantityRequired = 1, reagents = { { itemID = 999 } } },
                    { reagentType = BASIC, quantityRequired = 2, reagents = { { itemID = 2841 }, { itemID = 5000 } } },
                },
            }
        end,
    }
    for k, v in pairs(over or {}) do api[k] = v end
    return api
end

H.test("idFromLink reads the first number after a link kind", function()
    local T = setup()
    local link = "|cffffffff|Henchant:2018|h[Blacksmithing]|h|r"
    H.eq(T.Trade.idFromLink(link, "enchant", "spell"), 2018)
    H.eq(T.Trade.idFromLink("|Hspell:7|h[x]|h", "enchant", "spell"), 7)
    H.eq(T.Trade.idFromLink("|Hitem:2840::::|h[Copper Bar]|h", "item"), 2840)
    H.eq(T.Trade.idFromLink("|Hitem:0|h", "item"), nil)
    H.eq(T.Trade.idFromLink("no link here", "item"), nil)
    H.eq(T.Trade.idFromLink(nil, "item"), nil)
    H.eq(T.Trade.idFromLink(12, "item"), nil)
end)

H.test("the selected recipe comes from the Professions window when it is shown", function()
    local T = setup()
    T.env.ProfessionsFrame = professions(5)
    H.eq(T.Trade.selectedRecipeID(), 5)
    T.env.ProfessionsFrame = professions(5, false)
    H.eq(T.Trade.selectedRecipeID(), nil)
    T.env.ProfessionsFrame = professions(nil)
    H.eq(T.Trade.selectedRecipeID(), nil)
end)

H.test("a secret or invalid recipe id is not a selection", function()
    local T = setup()
    T.env.ProfessionsFrame = professions(0 / 0)
    H.eq(T.Trade.selectedRecipeID(), nil)
    T.env.issecretvalue = function(v) return v == "SECRET" end
    T.env.ProfessionsFrame = professions("SECRET")
    H.eq(T.Trade.selectedRecipeID(), nil)
end)

H.test("no recipe window at all means no selection and no frame", function()
    local T = setup()
    H.eq(T.Trade.frame(), nil)
    H.eq(T.Trade.isShown(), false)
    H.eq(T.Trade.selectedRecipeID(), nil)
    H.eq(T.Trade.readSelected(), nil)
end)

H.test("readSelected maps the Mainline schematic to a raw recipe", function()
    local T = setup()
    T.env.ProfessionsFrame = professions(5)
    T.env.Enum = { CraftingReagentType = { Basic = BASIC } }
    T.env.C_TradeSkillUI = mainlineApi()
    H.eq(T.Trade.readSelected(), {
        recipeID = 5, name = "Copper Sword", difficulty = 2, outputItemID = 2845,
        qtyMin = 1, qtyMax = 2,
        reagents = { { itemID = 2840, qty = 6 }, { itemID = 2841, qty = 2 } },
    })
end)

H.test("readSelected ignores recipes the player has not learned", function()
    local T = setup()
    T.env.ProfessionsFrame = professions(5)
    T.env.C_TradeSkillUI = mainlineApi({
        GetRecipeInfo = function(id) return { recipeID = id, name = "x", learned = false } end,
    })
    H.eq(T.Trade.readSelected(), nil)
end)

H.test("a currency reagent leaves an itemID-less line so the recipe is rejected later", function()
    local T = setup()
    T.env.ProfessionsFrame = professions(5)
    T.env.C_TradeSkillUI = mainlineApi({
        GetRecipeSchematic = function()
            return { outputItemID = 1, reagentSlotSchematics = {
                { reagentType = nil, quantityRequired = 1, reagents = { { currencyID = 3 } } } } }
        end,
    })
    local raw = T.Trade.readSelected()
    H.eq(raw.reagents, { { qty = 1 } })
end)

H.test("an API error while reading a recipe gives nil, not an exception", function()
    local T = setup()
    T.env.ProfessionsFrame = professions(5)
    T.env.C_TradeSkillUI = mainlineApi({ GetRecipeSchematic = function() error("boom") end })
    H.eq(T.Trade.readSelected(), nil)
end)

H.test("the classic trade skill API is used when there is no Professions window", function()
    local T = setup()
    T.env.TradeSkillFrame = { IsShown = function() return true end }
    T.env.GetTradeSkillSelectionIndex = function() return 3 end
    T.env.GetTradeSkillRecipeLink = function() return "|Henchant:2018|h[Copper Sword]|h" end
    T.env.GetTradeSkillInfo = function() return "Copper Sword", "optimal" end
    T.env.GetTradeSkillItemLink = function() return "|Hitem:2845::::|h[Copper Sword]|h" end
    T.env.GetTradeSkillNumMade = function() return 1, 1 end
    T.env.GetTradeSkillNumReagents = function() return 2 end
    T.env.GetTradeSkillReagentInfo = function(_, j) return "r", 0, j * 3, 0 end
    T.env.GetTradeSkillReagentItemLink = function(_, j) return "|Hitem:" .. (2839 + j) .. "::::|h[r]|h" end
    H.eq(T.Trade.selectedRecipeID(), 2018)
    H.eq(T.Trade.readSelected(), {
        recipeID = 2018, name = "Copper Sword", difficulty = "optimal", outputItemID = 2845,
        qtyMin = 1, qtyMax = 1,
        reagents = { { itemID = 2840, qty = 3 }, { itemID = 2841, qty = 6 } },
    })
end)

H.test("a classic header row is not a recipe", function()
    local T = setup()
    T.env.TradeSkillFrame = { IsShown = function() return true end }
    T.env.GetTradeSkillSelectionIndex = function() return 1 end
    T.env.GetTradeSkillRecipeLink = function() return "|Henchant:2018|h[x]|h" end
    T.env.GetTradeSkillInfo = function() return "Weapons", "header" end
    H.eq(T.Trade.readSelected(), nil)
end)

H.test("watch reports each selection change once, and again after invalidate", function()
    local T = setup()
    local seen = {}
    T.Trade.watch(function(id) seen[#seen + 1] = id or "none" end)
    H.eq(T.tickers[1].interval, 0.3)
    local tick = T.tickers[1].fn
    tick()
    H.eq(seen, {})
    T.env.ProfessionsFrame = professions(5)
    tick()
    tick()
    H.eq(seen, { 5 })
    T.env.ProfessionsFrame = professions(6)
    tick()
    H.eq(seen, { 5, 6 })
    T.Trade.invalidate()
    tick()
    H.eq(seen, { 5, 6, 6 })
    T.env.ProfessionsFrame = professions(6, false)
    tick()
    H.eq(seen, { 5, 6, 6, "none" })
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `luajit tests/run.lua`
Expected: FAIL in `tests/test_tradeadapter.lua` (cannot open `CraftProfit/TradeAdapter.lua`).

- [ ] **Step 3: Implement `TradeAdapter`**

```lua file=CraftProfit/TradeAdapter.lua
-- Profession window adapter: which recipe is selected, and its raw data.
-- The Professions UI exposes no selection event and its frame is created lazily,
-- so the selection is polled. Every game call is guarded: an API difference must
-- degrade to "no recipe", never to a Lua error.
local _, ns = ...
local Util = ns.Util

local Trade = {}
ns.Trade = Trade

local POLL_SECONDS = 0.3
local lastSeen

local function isSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) or false
end

-- First number following any of the given link kinds: "|Henchant:2018|h" -> 2018.
function Trade.idFromLink(link, ...)
    if type(link) ~= "string" then return nil end
    for i = 1, select("#", ...) do
        local id = link:match(select(i, ...) .. ":(%d+)")
        if id then return Util.id(tonumber(id)) end
    end
    return nil
end

function Trade.frame()
    return ProfessionsFrame or TradeSkillFrame
end

function Trade.isShown()
    local f = Trade.frame()
    return f ~= nil and f:IsShown() == true
end

-- Strategy A: the Mainline Professions window; its schematic form knows the
-- selected recipe.
local function selectedA()
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    local form = page and page.SchematicForm
    if form and form.GetRecipeInfo then
        local ok, info = pcall(form.GetRecipeInfo, form)
        if ok and type(info) == "table" and not isSecret(info.recipeID) then
            return Util.id(info.recipeID)
        end
    end
    return nil
end

-- Strategy B: the classic trade skill window; selection index -> recipe link.
local function selectedB()
    if not (GetTradeSkillSelectionIndex and GetTradeSkillRecipeLink) then return nil end
    local ok, index = pcall(GetTradeSkillSelectionIndex)
    if not ok or not Util.id(index) then return nil end
    local ok2, link = pcall(GetTradeSkillRecipeLink, index)
    if not ok2 then return nil end
    return Trade.idFromLink(link, "enchant", "spell"), index
end

function Trade.selectedRecipeID()
    if not Trade.isShown() then return nil end
    local id = selectedA()
    if id then return id end
    return (selectedB())
end

local function readA(recipeID)
    local api = C_TradeSkillUI
    if not (api and api.GetRecipeInfo and api.GetRecipeSchematic) then return nil end
    local ok, info, schematic = pcall(function()
        return api.GetRecipeInfo(recipeID), api.GetRecipeSchematic(recipeID, false)
    end)
    if not ok or type(info) ~= "table" or type(schematic) ~= "table" then return nil end
    if info.learned ~= true then return nil end
    local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
    local reagents = {}
    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        -- Only ordinary reagents; optional and finishing slots are not part of the cost.
        if basic == nil or slot.reagentType == basic then
            local first = slot.reagents and slot.reagents[1]
            reagents[#reagents + 1] = { itemID = first and first.itemID, qty = slot.quantityRequired }
        end
    end
    local name = info.name
    if isSecret(name) then name = nil end
    return {
        recipeID = recipeID, name = name, difficulty = info.relativeDifficulty,
        outputItemID = schematic.outputItemID,
        qtyMin = schematic.quantityMin, qtyMax = schematic.quantityMax,
        reagents = reagents,
    }
end

local function readB(recipeID, index)
    local ok, raw = pcall(function()
        local name, kind = GetTradeSkillInfo(index)
        if kind == "header" then return nil end
        local minMade, maxMade = GetTradeSkillNumMade(index)
        local reagents = {}
        for j = 1, GetTradeSkillNumReagents(index) do
            local _, _, count = GetTradeSkillReagentInfo(index, j)
            reagents[#reagents + 1] = {
                itemID = Trade.idFromLink(GetTradeSkillReagentItemLink(index, j), "item"),
                qty = count,
            }
        end
        return {
            recipeID = recipeID, name = name, difficulty = kind,
            outputItemID = Trade.idFromLink(GetTradeSkillItemLink(index), "item"),
            qtyMin = minMade, qtyMax = maxMade, reagents = reagents,
        }
    end)
    if ok then return raw end
    return nil
end

-- Raw data of the selected recipe for Recipes.normalize, or nil.
function Trade.readSelected()
    if not Trade.isShown() then return nil end
    local idA = selectedA()
    if idA then return readA(idA) end
    local idB, index = selectedB()
    if idB and index then return readB(idB, index) end
    return nil
end

-- Calls onChange(recipeID|nil) whenever the selection changes.
function Trade.watch(onChange)
    C_Timer.NewTicker(POLL_SECONDS, function()
        local id = Trade.selectedRecipeID()
        if id ~= lastSeen then
            lastSeen = id
            onChange(id)
        end
    end)
end

-- Forces the next poll to report the current selection again (for example
-- after the recipe list updated and the difficulty may have changed).
function Trade.invalidate()
    lastSeen = nil
end
```

- [ ] **Step 4: Run the tests and luacheck**

Run: `sh tests/check.sh`
Expected: all pass (apart from the disenchant data test if Task 5 Step 8 was not done yet), luacheck clean.

One subtlety the tests rely on: `watch` starts with `lastSeen == nil`, so the first poll with no selection reports nothing; `invalidate()` sets `lastSeen = nil`, so a still-selected recipe is reported again.

- [ ] **Step 5: Reconcile with the probe findings**

If F3/F4 show different field names (`learned`, `relativeDifficulty`, `quantityMin`…), a different way to read the selected recipe, or that only strategy B works, adjust `selectedA`/`readA` (or remove the unused strategy) and the matching fakes in `tests/test_tradeadapter.lua`. Re-run `sh tests/check.sh`.

- [ ] **Step 6: Commit**

```bash
git add CraftProfit/TradeAdapter.lua tests/test_tradeadapter.lua
git commit -m "feat: add TradeAdapter for selected recipe detection"
```

---

### Task 15: `UI/Window` and `Boot` (the floating window on profession recipes)

First user-visible milestone: select a known recipe in the profession window and the small window shows cost, resale options, the verdict and the price age.

**Before writing code:**
1. Invoke the `design-inspiration` skill (user's global rule for any visual output) and read its notes. Apply what fits a ~270 px native WoW panel (restrained palette, clear hierarchy for the verdict line). Keep Blizzard templates (`BackdropTemplate`, `UIPanelButtonTemplate`, `UICheckButtonTemplate`, `UIPanelCloseButton`). Adjust the `COLORS` table below if the notes call for it, and keep the colours readable on a dark panel.
2. Read `docs/probe-findings.md` F8 for the AH frame global name.

**Files:**
- Create: `tests/fakewow.lua` (test helper, not a test file), `CraftProfit/UI/Window.lua`, `CraftProfit/Boot.lua`
- Test: `tests/test_boot.lua`

**Interfaces:**
- Consumes: everything built so far; globals `CreateFrame`, `UIParent`, `GameTooltip`, `GetLocale`, `GetTime`, `time`, `C_Item`, `C_Timer`, `GetCoinTextureString`, `DEFAULT_CHAT_FRAME`, `SlashCmdList`, `AuctionHouseFrame`, `AuctionFrame`
- Produces:
  - `ns.Window`: `create(handlers)`, `render(model)`, `showEmpty(text)`, `attach(targetFrame|nil, saved|nil)`, `show()`, `hide()`, `isShown()`, `pinsHost() -> frame`, `relayout()`, `lastModel` (the last model rendered; used by tests). `handlers = { onPinClick(), onPerPointToggle(checked), onMoved(point, x, y) }`. `model` is `Present.build`'s result plus `pinned` and `showPerPoint`.
  - `ns.Controller`: `onEvent(event, arg1, arg2)`, `init()`, `ready`, `setRecipe(recipe, source)` (source `"profession"` or `"pin"`), `selectPin(recipeID)`, `currentRecipeID()`, `refresh()`, `requestRefresh()`, `evaluate(recipe) -> result`, `itemInfo(itemID)`, `fmt(copper)`, `recordListings(itemID, listings) -> boolean`, `onSnapshot(aggregator)`, `onAHOpen(open)`, `togglePin()`, `selftest() -> boolean`, `say(text)`
  - Slash commands `/cp` and `/craftprofit`: `show | hide | reset | scan | locale <code> | selftest`
  - `Boot` calls `ns.PinsUI.init(Controller)`, `.refresh()`, `.onAHOpen(open)`, `.setStatus(text)`, `.scan()` only when `ns.PinsUI` exists (Task 16).

- [ ] **Step 1: Create the fake game environment used by the smoke tests**

```lua file=tests/fakewow.lua
-- Fake WoW environment for smoke tests. Loads the real addon files, in the
-- order listed in CraftProfit.toc, into one namespace with stubbed game APIs.
-- Not a test file: tests/run.lua only runs tests/test_*.lua.
local W = {}

-- A permissive fake frame: known methods record state, every other method is a
-- no-op, so UI code can run without a game client.
function W.frame()
    local f = { scripts = {}, events = {}, shown = false }
    local methods = {
        SetText = function(self, t) self.text = t end,
        GetText = function(self) return self.text end,
        SetScript = function(self, name, fn) self.scripts[name] = fn end,
        HookScript = function(self, name, fn) self.scripts[name] = fn end,
        RegisterEvent = function(self, e) self.events[#self.events + 1] = e end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        SetShown = function(self, v) self.shown = v and true or false end,
        IsShown = function(self) return self.shown end,
        SetChecked = function(self, v) self.checked = v and true or false end,
        GetChecked = function(self) return self.checked end,
        GetLeft = function() return 100 end,
        GetTop = function() return 700 end,
        SetHeight = function(self, h) self.height = h end,
        GetHeight = function(self) return self.height or 0 end,
        CreateFontString = function() return W.frame() end,
        CreateTexture = function() return W.frame() end,
    }
    return setmetatable(f, { __index = function(_, k) return methods[k] or function() end end })
end

-- opts: locale, items = { [itemID] = {quality, ilvl, sellPrice, classID, bindType} }
function W.boot(H, opts)
    opts = opts or {}
    local ns = {}
    local env = setmetatable({}, { __index = _G })
    local T = { ns = ns, env = env, chat = {}, timers = {}, tickers = {}, clock = 1000, loadRequests = {} }

    env.GetTime = function() return T.clock end
    env.time = function() return 1700000000 end
    env.GetLocale = function() return opts.locale or "enUS" end
    env.UIParent = W.frame()
    env.CreateFrame = function() return W.frame() end
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) T.chat[#T.chat + 1] = m end }
    env.GetCoinTextureString = function(c) return "<" .. c .. ">" end
    env.SlashCmdList = {}
    env.Enum = {}
    env.C_Timer = {
        After = function(_, fn) T.timers[#T.timers + 1] = fn end,
        NewTicker = function(_, fn)
            local ticker = { fn = fn, cancelled = false }
            function ticker.Cancel() ticker.cancelled = true end
            T.tickers[#T.tickers + 1] = ticker
            return ticker
        end,
    }
    env.C_Item = {
        GetItemInfo = function(id)
            local i = opts.items and opts.items[id]
            if not i then return nil end
            return "Item" .. id, "link", i.quality, i.ilvl, 1, "type", "sub", 1, "", 0,
                i.sellPrice, i.classID, 0, i.bindType
        end,
        RequestLoadItemDataByID = function(id) T.loadRequests[#T.loadRequests + 1] = id end,
    }
    env.C_AuctionHouse = {}

    local toc = assert(io.open("CraftProfit/CraftProfit.toc")):read("*a")
    for line in toc:gmatch("[^\r\n]+") do
        if not line:match("^##") and line:match("%S") then
            local name = (line:gsub("%.lua%s*$", ""))
            H.loadModule(name, ns, env)
        end
    end

    -- Runs every callback scheduled with C_Timer.After.
    function T.run()
        while #T.timers > 0 do table.remove(T.timers, 1)() end
    end
    return T
end

return W
```

- [ ] **Step 2: Write the failing smoke tests**

```lua file=tests/test_boot.lua
local H = ...
local W = dofile("tests/fakewow.lua")

-- classID 0 (not weapon/armor): disenchanting never applies, so these smoke
-- tests do not depend on the contents of the disenchant table.
local ITEMS = {
    [100] = { quality = 2, ilvl = 15, sellPrice = 200, classID = 0, bindType = 2 },
}

local RAW = {
    recipeID = 5, name = "Sword", difficulty = 1, outputItemID = 100, qtyMin = 1, qtyMax = 1,
    reagents = { { itemID = 1, qty = 2 }, { itemID = 2, qty = 1 } },
}

local function boot(opts)
    local T = W.boot(H, opts or { items = ITEMS })
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    return T
end

local function stock(T)
    local P, db = T.ns.Prices, T.env.CraftProfitDB
    P.store(db, 1, 100, 10, 1699999940)
    P.store(db, 2, 50, 10, 1699999880)
    P.store(db, 100, 1000, 10, 1699999970)
end

H.test("every file listed in the TOC loads without error", function()
    local T = W.boot(H, { items = ITEMS })
    H.truthy(T.ns.Controller)
    H.truthy(T.ns.Window)
    H.truthy(T.ns.AH)
    H.truthy(T.ns.Trade)
end)

H.test("the addon only reacts to its own ADDON_LOADED", function()
    local T = W.boot(H, { items = ITEMS })
    T.ns.Controller.onEvent("ADDON_LOADED", "SomethingElse")
    H.falsy(T.ns.Controller.ready)
    T.ns.Controller.onEvent("ITEM_DATA_LOAD_RESULT", 100)
    T.ns.Controller.onEvent("TRADE_SKILL_LIST_UPDATE")
end)

H.test("ADDON_LOADED creates and repairs the saved variables", function()
    local T = boot()
    H.truthy(T.ns.Controller.ready)
    H.eq(T.env.CraftProfitDB.dbVersion, 1)
    H.eq(T.env.CraftProfitDB.settings.cut, 0.05)
    H.eq(T.env.CraftProfitCharDB.pins, {})
end)

H.test("existing saved variables are kept and repaired in place", function()
    local T = W.boot(H, { items = ITEMS })
    local db = { settings = { cut = 0 / 0, medianN = 3 }, prices = { [9] = "junk" } }
    T.env.CraftProfitDB = db
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    H.truthy(T.env.CraftProfitDB == db)
    H.eq(db.settings.cut, 0.05)
    H.eq(db.settings.medianN, 3)
    H.eq(db.prices, {})
end)

H.test("the client locale selects the language", function()
    local T = boot({ locale = "frFR", items = ITEMS })
    H.eq(T.ns.Locale.current, "frFR")
    local unsupported = boot({ locale = "deDE", items = ITEMS })
    H.eq(unsupported.ns.Locale.current, "enUS")
end)

H.test("a selected recipe is evaluated and rendered", function()
    local T = boot()
    stock(T)
    local recipe = T.ns.Recipes.normalize(RAW)
    T.ns.Controller.setRecipe(recipe, "profession")
    local model = T.ns.Window.lastModel
    H.eq(model.verdict.kind, "profit")
    H.eq(model.lines[1].value, "<250>")
    H.eq(model.pinned, false)
    H.truthy(T.ns.Window.isShown())
end)

H.test("an unloaded item shows unknown values and asks the game to load it", function()
    local T = boot({ items = {} })
    stock(T)
    T.ns.Controller.setRecipe(T.ns.Recipes.normalize(RAW), "profession")
    local model = T.ns.Window.lastModel
    H.eq(model.verdict.kind, "incomplete")
    H.eq(model.lines[3].value, "?")
    H.truthy(#T.loadRequests > 0)
    T.ns.Controller.onEvent("ITEM_DATA_LOAD_RESULT", 100)
    T.run()
end)

H.test("a recipe with no prices at all renders as incomplete without errors", function()
    local T = boot()
    T.ns.Controller.setRecipe(T.ns.Recipes.normalize(RAW), "profession")
    H.eq(T.ns.Window.lastModel.verdict.kind, "incomplete")
    H.eq(T.ns.Window.lastModel.ageText, "Prices: never scanned")
end)

H.test("pinning toggles the recipe in the character's pins", function()
    local T = boot()
    local C = T.ns.Controller
    C.setRecipe(T.ns.Recipes.normalize(RAW), "profession")
    C.togglePin()
    H.eq(#T.env.CraftProfitCharDB.pins, 1)
    H.eq(T.ns.Window.lastModel.pinned, true)
    C.togglePin()
    H.eq(#T.env.CraftProfitCharDB.pins, 0)
    H.eq(T.ns.Window.lastModel.pinned, false)
end)

H.test("togglePin with no recipe selected does nothing", function()
    local T = boot()
    T.ns.Controller.togglePin()
    H.eq(#T.env.CraftProfitCharDB.pins, 0)
end)

H.test("recordListings stores the median price and ignores empty answers", function()
    local T = boot()
    local C = T.ns.Controller
    H.eq(C.recordListings(7, { { unit = 10, qty = 1 }, { unit = 20, qty = 1 }, { unit = 1000, qty = 1 } }), true)
    H.eq(T.env.CraftProfitDB.prices[7][1], 20)
    H.eq(C.recordListings(8, {}), false)
    H.eq(T.env.CraftProfitDB.prices[8], nil)
end)

H.test("the selection watcher shows, updates and hides the window", function()
    local T = boot()
    stock(T)
    local C, ns = T.ns.Controller, T.ns
    T.env.ProfessionsFrame = {
        IsShown = function() return true end,
        CraftingPage = { SchematicForm = { GetRecipeInfo = function() return { recipeID = 5 } end } },
    }
    T.env.Enum = { CraftingReagentType = { Basic = 1 } }
    T.env.C_TradeSkillUI = {
        GetRecipeInfo = function(id) return { recipeID = id, name = "Sword", learned = true, relativeDifficulty = 1 } end,
        GetRecipeSchematic = function()
            return { outputItemID = 100, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = {
                { reagentType = 1, quantityRequired = 2, reagents = { { itemID = 1 } } },
                { reagentType = 1, quantityRequired = 1, reagents = { { itemID = 2 } } },
            } }
        end,
    }
    H.truthy(#T.tickers >= 1)
    T.tickers[#T.tickers].fn()
    H.eq(ns.Window.lastModel.verdict.kind, "profit")
    T.env.ProfessionsFrame.IsShown = function() return false end
    T.tickers[#T.tickers].fn()
    H.falsy(ns.Window.isShown())
    H.eq(C.currentRecipeID(), nil)
end)

H.test("the slash command runs the self-test and reports in chat", function()
    local T = boot()
    T.env.SlashCmdList.CRAFTPROFIT("selftest")
    H.truthy(T.chat[#T.chat]:find("Self-test passed", 1, true))
    T.env.SlashCmdList.CRAFTPROFIT("locale frFR")
    H.eq(T.ns.Locale.current, "frFR")
    T.env.SlashCmdList.CRAFTPROFIT("")
    H.truthy(T.chat[#T.chat]:find("/cp", 1, true))
end)

H.test("an unknown or malformed slash argument never raises", function()
    local T = boot()
    local slash = T.env.SlashCmdList.CRAFTPROFIT
    slash("nonsense")
    slash("locale")
    slash("locale xxXX")
    slash("show")
    slash("hide")
    slash("reset")
    slash(nil)
end)

H.test("a moved window is saved and reused", function()
    local T = boot()
    T.ns.Window.lastHandlers.onMoved("TOPLEFT", 120, 640)
    H.eq(T.env.CraftProfitDB.settings.window, { point = "TOPLEFT", x = 120, y = 640 })
end)

H.test("toggling the per-point option is saved and re-renders", function()
    local T = boot()
    stock(T)
    T.ns.Controller.setRecipe(T.ns.Recipes.normalize(RAW), "profession")
    T.ns.Window.lastHandlers.onPerPointToggle(true)
    H.eq(T.env.CraftProfitDB.settings.showPerPoint, true)
    H.eq(T.ns.Window.lastModel.lines[5].key, "perpoint")
end)

H.test("ADDON_ACTION_BLOCKED for this addon is reported", function()
    local T = boot()
    T.ns.Controller.onEvent("ADDON_ACTION_BLOCKED", "CraftProfit", "SomeProtectedFunction")
    H.truthy(T.chat[#T.chat]:find("SomeProtectedFunction", 1, true))
    local before = #T.chat
    T.ns.Controller.onEvent("ADDON_ACTION_BLOCKED", "OtherAddon", "X")
    H.eq(#T.chat, before)
end)
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `luajit tests/run.lua`
Expected: FAIL in `tests/test_boot.lua` (cannot open `CraftProfit/UI/Window.lua` while loading the TOC files).

- [ ] **Step 4: Implement `UI/Window`**

```lua file=CraftProfit/UI/Window.lua
-- The small floating window. Parented to UIParent (never to a Blizzard frame, to
-- avoid taint); anchored beside the profession or AH window until the user
-- drags it, after which the saved position wins.
local _, ns = ...
local L = ns.L

local Window = {}
ns.Window = Window

local WIDTH = 270
local PAD = 10
local ROW_H = 16
local HEADER_H = 26
local MAX_LINES = 6

local COLORS = {
    profit = { 0.35, 0.90, 0.45 },
    loss = { 1.00, 0.40, 0.35 },
    incomplete = { 1.00, 0.82, 0.25 },
    none = { 0.70, 0.70, 0.70 },
    normal = { 0.90, 0.90, 0.90 },
    best = { 0.35, 0.90, 0.45 },
    muted = { 0.65, 0.65, 0.70 },
    stale = { 1.00, 0.60, 0.25 },
}

local frame, titleText, emptyText, verdictText, verdictValue, ageText
local perPointCheck, perPointLabel, pinButton, pinsHost, costHit
local costLines = {}
local lineRows = {}
local handlers = {}
local contentHeight = 80

Window.lastModel = nil
Window.lastHandlers = nil

local function color(fontString, rgb)
    fontString:SetTextColor(rgb[1], rgb[2], rgb[3])
end

local function newText(parent, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    fs:SetWordWrap(false)
    return fs
end

local function place(region, point, x, y)
    region:ClearAllPoints()
    region:SetPoint(point, frame, point, x, y)
end

-- Item name for the tooltip; "#id" while the game has not loaded it (or when
-- the name is a secret value, which raises when concatenated).
local function reagentName(itemID)
    local ok, name = pcall(C_Item.GetItemInfo, itemID)
    if ok and type(name) == "string" then
        local fine, text = pcall(function() return name .. "" end)
        if fine then return text end
    end
    return "#" .. itemID
end

local function showCostTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(L.MATERIALS)
    for _, line in ipairs(costLines) do
        GameTooltip:AddDoubleLine(line.qty .. "x " .. reagentName(line.itemID),
            line.subtotalText .. " (" .. line.unitText .. ")", 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:Show()
end

function Window.create(h)
    if frame then return frame end
    handlers = h or {}
    Window.lastHandlers = handlers

    frame = CreateFrame("Frame", "CraftProfitWindow", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, 100)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.08, 0.92)
    frame:SetBackdropBorderColor(0.40, 0.40, 0.50, 1)
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Re-anchor to the screen's bottom-left corner so saved offsets are absolute.
        local left, top = self:GetLeft(), self:GetTop()
        if left and top then
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            if handlers.onMoved then handlers.onMoved("TOPLEFT", left, top) end
        end
    end)

    titleText = newText(frame, "GameFontNormal")
    place(titleText, "TOPLEFT", PAD, -8)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)

    emptyText = newText(frame, "GameFontDisable")
    emptyText:SetPoint("TOP", frame, "TOP", 0, -HEADER_H - 8)

    for i = 1, MAX_LINES do
        local label = newText(frame, "GameFontHighlightSmall")
        label:SetWidth(150)
        label:SetJustifyH("LEFT")
        local value = newText(frame, "GameFontHighlightSmall")
        value:SetJustifyH("RIGHT")
        lineRows[i] = { label = label, value = value }
    end

    -- Transparent hover area over the Materials line: the cost detail tooltip.
    costHit = CreateFrame("Frame", nil, frame)
    costHit:EnableMouse(true)
    costHit:SetSize(WIDTH - PAD * 2, ROW_H)
    costHit:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -HEADER_H)
    costHit:SetScript("OnEnter", showCostTooltip)
    costHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    verdictText = newText(frame, "GameFontNormal")
    verdictText:SetWidth(170)
    verdictText:SetJustifyH("LEFT")
    verdictValue = newText(frame, "GameFontNormal")
    verdictValue:SetJustifyH("RIGHT")
    ageText = newText(frame, "GameFontDisableSmall")
    ageText:SetJustifyH("LEFT")

    perPointCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    perPointCheck:SetSize(22, 22)
    perPointCheck:SetScript("OnClick", function(self)
        if handlers.onPerPointToggle then handlers.onPerPointToggle(self:GetChecked() and true or false) end
    end)
    perPointLabel = newText(frame, "GameFontHighlightSmall")

    pinButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    pinButton:SetSize(86, 20)
    pinButton:SetScript("OnClick", function()
        if handlers.onPinClick then handlers.onPinClick() end
    end)

    pinsHost = CreateFrame("Frame", nil, frame)
    pinsHost:SetWidth(WIDTH)
    pinsHost:SetHeight(0)
    pinsHost:Hide()

    frame:Hide()
    return frame
end

-- Frame height = recipe section + pinned-recipes section (when shown).
function Window.relayout()
    if not frame then return end
    pinsHost:ClearAllPoints()
    pinsHost:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -contentHeight)
    local extra = pinsHost:IsShown() and pinsHost:GetHeight() or 0
    frame:SetHeight(contentHeight + extra)
end

local function hideLines()
    for i = 1, MAX_LINES do
        lineRows[i].label:Hide()
        lineRows[i].value:Hide()
    end
    costHit:Hide()
    verdictText:Hide()
    verdictValue:Hide()
    ageText:Hide()
    perPointCheck:Hide()
    perPointLabel:Hide()
    pinButton:Hide()
end

function Window.showEmpty(text)
    if not frame then return end
    Window.lastModel = nil
    titleText:SetText(L.TITLE)
    hideLines()
    emptyText:SetText(text)
    emptyText:Show()
    contentHeight = HEADER_H + 34
    Window.relayout()
end

function Window.render(model)
    if not frame then return end
    Window.lastModel = model
    costLines = model.costLines or {}
    titleText:SetText(L.TITLE)
    emptyText:Hide()
    costHit:Show()

    local y = HEADER_H
    for i = 1, MAX_LINES do
        local row, line = lineRows[i], model.lines[i]
        if line then
            row.label:SetText(line.label)
            row.value:SetText(line.value)
            color(row.label, line.best and COLORS.best or COLORS.normal)
            color(row.value, line.best and COLORS.best or COLORS.normal)
            place(row.label, "TOPLEFT", PAD, -y)
            place(row.value, "TOPRIGHT", -PAD, -y)
            row.label:Show()
            row.value:Show()
            y = y + ROW_H
        else
            row.label:Hide()
            row.value:Hide()
        end
    end

    y = y + 6
    local verdictColor = COLORS[model.verdict.kind == "profit" and "profit"
        or model.verdict.kind == "loss" and "loss"
        or model.verdict.kind == "incomplete" and "incomplete" or "none"]
    verdictText:SetText(model.verdict.text)
    verdictValue:SetText(model.verdict.value)
    color(verdictText, verdictColor)
    color(verdictValue, verdictColor)
    place(verdictText, "TOPLEFT", PAD, -y)
    place(verdictValue, "TOPRIGHT", -PAD, -y)
    verdictText:Show()
    verdictValue:Show()
    y = y + ROW_H + 4

    ageText:SetText(model.ageText)
    color(ageText, model.stale and COLORS.stale or COLORS.muted)
    place(ageText, "TOPLEFT", PAD, -y)
    ageText:Show()
    y = y + ROW_H + 2

    perPointCheck:SetChecked(model.showPerPoint)
    perPointLabel:SetText(L.OPT_PER_POINT)
    perPointCheck:ClearAllPoints()
    perPointCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD - 4, -y)
    perPointLabel:ClearAllPoints()
    perPointLabel:SetPoint("LEFT", perPointCheck, "RIGHT", 2, 0)
    perPointLabel:SetWidth(WIDTH - PAD * 2 - 24 - 90)
    perPointCheck:Show()
    perPointLabel:Show()

    pinButton:SetText(model.pinned and L.UNPIN or L.PIN)
    pinButton:ClearAllPoints()
    pinButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -y - 1)
    pinButton:Show()

    contentHeight = y + 28
    Window.relayout()
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

function Window.show() if frame then frame:Show() end end
function Window.hide() if frame then frame:Hide() end end
function Window.isShown() return frame ~= nil and frame:IsShown() == true end
function Window.pinsHost() return pinsHost end
```

- [ ] **Step 5: Implement `Boot`**

```lua file=CraftProfit/Boot.lua
-- Entry point: wires the modules together and owns the controller.
local ADDON, ns = ...
local Util, Format, Core, Prices = ns.Util, ns.Format, ns.Core, ns.Prices
local DB, Evaluate, Present, Recipes = ns.DB, ns.Evaluate, ns.Present, ns.Recipes
local Disenchant = ns.Data.Disenchant
local L = ns.L

local Controller = {}
ns.Controller = Controller

local state = { recipe = nil, source = nil }
local requestedItems = {}
local refreshQueued = false

function Controller.say(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffCraftProfit|r " .. tostring(text))
end
local say = Controller.say

function Controller.fmt(copper)
    return Format.money(copper, GetCoinTextureString)
end

-- Item facts, or nil while the game has not loaded the item yet. The request is
-- made once per item; ITEM_DATA_LOAD_RESULT triggers the refresh.
function Controller.itemInfo(itemID)
    local _, _, quality, ilvl, _, _, _, _, _, _, sellPrice, classID, _, bindType = C_Item.GetItemInfo(itemID)
    if quality == nil then
        if not requestedItems[itemID] then
            requestedItems[itemID] = true
            C_Item.RequestLoadItemDataByID(itemID)
        end
        return nil
    end
    return { quality = quality, ilvl = ilvl, sellPrice = sellPrice, classID = classID, bindType = bindType }
end

function Controller.evaluate(recipe)
    local settings = CraftProfitDB.settings
    return Evaluate.run({
        recipe = recipe,
        priceOf = Prices.priceOf(CraftProfitDB, time()),
        itemInfo = Controller.itemInfo,
        cut = settings.cut,
        showPerPoint = settings.showPerPoint,
        lookupDisenchant = Disenchant.lookup,
    })
end

function Controller.currentRecipeID()
    return state.recipe and state.recipe.recipeID or nil
end

function Controller.refresh()
    local settings = CraftProfitDB.settings
    local recipe = state.recipe
    if recipe then
        local model = Present.build(Controller.evaluate(recipe), L, Controller.fmt,
            { staleAfter = settings.staleAfter })
        model.pinned = DB.pinIndex(CraftProfitCharDB, recipe.recipeID) ~= nil
        model.showPerPoint = settings.showPerPoint
        ns.Window.render(model)
    else
        ns.Window.showEmpty(L.NO_RECIPE)
    end
    if ns.PinsUI then ns.PinsUI.refresh() end
end

-- Coalesces bursts (many ITEM_DATA_LOAD_RESULT events, one per search result).
function Controller.requestRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.1, function()
        refreshQueued = false
        Controller.refresh()
    end)
end

function Controller.setRecipe(recipe, source)
    state.recipe, state.source = recipe, source
    local window = ns.Window
    if not window.isShown() then
        local target = ns.Trade.frame()
        if source == "pin" then target = AuctionHouseFrame or AuctionFrame end
        window.attach(target, CraftProfitDB.settings.window)
        window.show()
    end
    Controller.refresh()
end

function Controller.selectPin(recipeID)
    local index = DB.pinIndex(CraftProfitCharDB, recipeID)
    if not index then return end
    state.recipe, state.source = CraftProfitCharDB.pins[index], "pin"
    Controller.refresh()
end

function Controller.togglePin()
    local recipe = state.recipe
    if not recipe then return end
    if DB.pinIndex(CraftProfitCharDB, recipe.recipeID) then
        DB.pinRemove(CraftProfitCharDB, recipe.recipeID)
    else
        local ok, reason = DB.pinAdd(CraftProfitCharDB, recipe)
        if not ok and reason == "full" then say(L.PINS_FULL) end
    end
    Controller.refresh()
end

-- Stores the median price of an AH search result. False when nothing was listed.
function Controller.recordListings(itemID, listings)
    local unit, volume = Prices.summarize(listings, CraftProfitDB.settings.medianN)
    if unit then Prices.store(CraftProfitDB, itemID, unit, volume, time()) end
    return unit ~= nil
end

function Controller.onSnapshot(agg)
    local count = Prices.merge(CraftProfitDB, agg.result(CraftProfitDB.settings.medianN), time())
    if ns.PinsUI then ns.PinsUI.setStatus(string.format(L.SCAN_DONE, count)) end
    Controller.requestRefresh()
end

function Controller.onAHOpen(open)
    if ns.PinsUI then ns.PinsUI.onAHOpen(open) end
    local window = ns.Window
    if open then
        if not state.recipe then
            local first = CraftProfitCharDB.pins[1]
            if first then state.recipe, state.source = first, "pin" end
        end
        if not window.isShown() then
            window.attach(AuctionHouseFrame or AuctionFrame, CraftProfitDB.settings.window)
            window.show()
        end
        Controller.refresh()
    elseif state.source == "profession" then
        Controller.refresh()
    else
        state.recipe, state.source = nil, nil
        window.hide()
    end
end

-- The profession window selection changed (or the window closed).
local function onSelection(recipeID)
    if recipeID then
        local recipe = Recipes.normalize(ns.Trade.readSelected())
        if recipe then
            Controller.setRecipe(recipe, "profession")
            return
        end
    end
    if state.source == "profession" then
        state.recipe, state.source = nil, nil
        if ns.AH.isOpen then Controller.refresh() else ns.Window.hide() end
    end
end

-- Runs a few checks inside the game's own Lua 5.1, the only place that can
-- reveal a difference with the LuaJIT used by the offline tests.
function Controller.selftest()
    local checks = 0
    local function check(condition, name)
        checks = checks + 1
        if not condition then error(name, 0) end
    end
    local ok, err = pcall(function()
        check(Core.sumCost({ { itemID = 1, qty = 2 } }, function() return 100 end) == 200, "Core.sumCost")
        check(Core.netSale(1000, 1, 0.05) == 950, "Core.netSale")
        check(Prices.summarize({ { unit = 10, qty = 1 }, { unit = 20, qty = 1 }, { unit = 1000, qty = 1 } }, 5) == 20,
            "Prices.summarize")
        check(Util.isFinite(0 / 0) == false, "NaN is not finite")
        check(Util.isFinite(1 / 0) == false, "infinity is not finite")
        check(Format.money(nil) == "?", "Format.money(nil)")
        check(Format.money(0 / 0) == "?", "Format.money(NaN)")
        check(Format.money(12345, GetCoinTextureString) ~= "?", "coin string")
        check(string.format("%d", 5) == "5", "string.format")
        check(L.MATERIALS ~= "MATERIALS", "locale strings")
        check(Recipes.normalize({ recipeID = 1, outputItemID = 2, reagents = { { itemID = 3, qty = 1 } } }) ~= nil,
            "Recipes.normalize")
    end)
    if ok then
        say(string.format(L.SELFTEST_OK, checks))
    else
        say(string.format(L.SELFTEST_FAIL, tostring(err)))
    end
    return ok
end

function Controller.init()
    CraftProfitDB = CraftProfitDB or {}
    CraftProfitCharDB = CraftProfitCharDB or {}
    DB.initAccount(CraftProfitDB)
    DB.prune(CraftProfitDB, time())
    DB.initChar(CraftProfitCharDB)
    ns.Locale.select(GetLocale())

    ns.Window.create({
        onPinClick = Controller.togglePin,
        onPerPointToggle = function(checked)
            CraftProfitDB.settings.showPerPoint = checked and true or false
            Controller.refresh()
        end,
        onMoved = function(point, x, y)
            CraftProfitDB.settings.window = { point = point, x = x, y = y }
        end,
    })
    if ns.PinsUI then ns.PinsUI.init(Controller) end
    ns.AH.setHandlers({
        onOpen = Controller.onAHOpen,
        onSearch = function(itemID, listings)
            if ns.PinsUI then ns.PinsUI.onSearchResults(itemID, listings) end
        end,
        onSnapshot = Controller.onSnapshot,
    })
    ns.Trade.watch(onSelection)
    Controller.ready = true
end

function Controller.onEvent(event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then Controller.init() end
        return
    end
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if arg1 == ADDON then say(event .. ": " .. tostring(arg2)) end
        return
    end
    if not Controller.ready then return end
    if event == "ITEM_DATA_LOAD_RESULT" then
        if requestedItems[arg1] then
            requestedItems[arg1] = nil
            Controller.requestRefresh()
        end
    elseif event == "TRADE_SKILL_LIST_UPDATE" then
        ns.Trade.invalidate()
    end
end

local function slash(msg)
    if not Controller.ready then return end
    local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    local window = ns.Window
    local anchor = ns.Trade.frame() or AuctionHouseFrame or AuctionFrame
    if cmd == "show" then
        if not window.isShown() then
            window.attach(anchor, CraftProfitDB.settings.window)
            window.show()
        end
        Controller.refresh()
    elseif cmd == "hide" then
        window.hide()
    elseif cmd == "reset" then
        CraftProfitDB.settings.window = nil
        window.attach(anchor, nil)
    elseif cmd == "scan" then
        if ns.PinsUI then ns.PinsUI.scan() end
    elseif cmd == "locale" then
        ns.Locale.select(arg ~= "" and arg or GetLocale())
        Controller.refresh()
    elseif cmd == "selftest" then
        Controller.selftest()
    else
        say(L.SLASH_HELP)
    end
end

SLASH_CRAFTPROFIT1 = "/craftprofit"
SLASH_CRAFTPROFIT2 = "/cp"
SlashCmdList.CRAFTPROFIT = slash

local frame = CreateFrame("Frame")
for _, event in ipairs({
    "ADDON_LOADED", "ITEM_DATA_LOAD_RESULT", "TRADE_SKILL_LIST_UPDATE",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
}) do
    pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event, ...) Controller.onEvent(event, ...) end)
```

- [ ] **Step 6: Run the tests and luacheck**

Run: `sh tests/check.sh`
Expected: all pass (apart from the disenchant data test if Task 5 Step 8 was not done yet), luacheck clean.

- [ ] **Step 7: Install and try it in the game (user action)**

Link the addon folder (not the repo) into the client:

```bash
ln -s "$PWD/CraftProfit" "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/CraftProfit"
```

Restart the client, then `/console scriptErrors 1` and run `/cp selftest`.
Expected: `CraftProfit Self-test passed (11 checks)`.
Then open the blacksmithing window and click a known recipe.
Expected: the window appears to the right of the profession window with Materials, AH, Vendor, Disenchant lines, a verdict and `Prices: never scanned` (no prices stored yet; they appear after Task 16). Drag it, `/reload`, confirm it keeps its position; `/cp reset` puts it back.

- [ ] **Step 8: Commit**

```bash
git add tests/fakewow.lua tests/test_boot.lua CraftProfit/UI/Window.lua CraftProfit/Boot.lua
git commit -m "feat: add floating window and boot wiring for profession recipes"
```

---

### Task 16: `UI/PinsUI` (pinned recipes, price search and scan at the AH)

**Files:**
- Create: `CraftProfit/UI/PinsUI.lua`
- Modify: `CraftProfit/CraftProfit.toc` (add the file)
- Test: `tests/test_pinsui.lua`

**Interfaces:**
- Consumes: `ns.Controller` (passed to `init`): `evaluate`, `fmt`, `itemInfo`, `recordListings`, `requestRefresh`, `selectPin`, `currentRecipeID`; `ns.AH.search`, `ns.AH.requestSnapshot`, `ns.AH.isOpen`; `ns.PriceQueue`; `ns.Evaluate.wantedItems`; `ns.Present.durationText`
- Produces (`ns.PinsUI`): `init(controller)`, `refresh()`, `setStatus(text)`, `startSearch()`, `scan()`, `onAHOpen(open)`, `onSearchResults(itemID, listings)`, `wantedFor(pins, itemInfo, lookup) -> { itemID... }`, `state` (`"idle"|"running"|"done"|"cancelled"`), `status` (last status text; used by tests)

- [ ] **Step 1: Write the failing tests**

```lua file=tests/test_pinsui.lua
local H = ...
local W = dofile("tests/fakewow.lua")

-- classID 0 on both outputs: disenchanting never applies, so the expected
-- item lists do not depend on the contents of the disenchant table.
local ITEMS = {
    [100] = { quality = 2, ilvl = 15, sellPrice = 200, classID = 0, bindType = 2 },
    [101] = { quality = 1, ilvl = 1, sellPrice = 10, classID = 0, bindType = 2 },
}

local function raw(id, output, reagents)
    return { recipeID = id, name = "R" .. id, difficulty = 1, outputItemID = output, reagents = reagents }
end

local function boot()
    local T = W.boot(H, { items = ITEMS })
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    local pins = T.env.CraftProfitCharDB.pins
    T.ns.DB.pinAdd(T.env.CraftProfitCharDB, raw(1, 100, { { itemID = 1, qty = 2 }, { itemID = 2, qty = 1 } }))
    T.ns.DB.pinAdd(T.env.CraftProfitCharDB, raw(2, 101, { { itemID = 2, qty = 3 }, { itemID = 3, qty = 1 } }))
    -- The AH adapter is replaced by a recorder: the queue's `send` goes through it.
    T.sent = {}
    T.ns.AH.search = function(id) T.sent[#T.sent + 1] = id; return true end
    return T, pins
end

local listing = { { unit = 10, qty = 1 }, { unit = 30, qty = 1 }, { unit = 20, qty = 1 } }

H.test("wantedFor lists each needed item once across all pins", function()
    local T = boot()
    local ids = T.ns.PinsUI.wantedFor(T.env.CraftProfitCharDB.pins, T.ns.Controller.itemInfo, T.ns.Data.Disenchant.lookup)
    H.eq(ids, { 1, 2, 100, 3, 101 })
end)

H.test("searching with the AH closed only reports it", function()
    local T = boot()
    T.ns.PinsUI.startSearch()
    H.eq(T.ns.PinsUI.status, "Open the auction house first")
    H.eq(T.sent, {})
    H.eq(T.ns.PinsUI.state, "idle")
end)

H.test("a search walks every item and stores the median prices", function()
    local T = boot()
    local P = T.ns.PinsUI
    T.ns.AH.isOpen = true
    P.startSearch()
    H.eq(P.state, "running")
    H.eq(T.sent, { 1 })
    for _, id in ipairs({ 1, 2, 100, 3, 101 }) do
        P.onSearchResults(id, listing)
    end
    H.eq(T.sent, { 1, 2, 100, 3, 101 })
    H.eq(P.state, "done")
    H.eq(P.status, "Prices updated")
    H.eq(T.env.CraftProfitDB.prices[1][1], 20)
    H.eq(T.env.CraftProfitDB.prices[101][1], 20)
    H.truthy(T.tickers[#T.tickers].cancelled)
end)

H.test("an item that never answers is reported at the end", function()
    local T = boot()
    local P = T.ns.PinsUI
    T.ns.AH.isOpen = true
    P.startSearch()
    P.onSearchResults(1, listing)
    -- 100 never answers; the ticker times it out after 6 s.
    for _, id in ipairs({ 2 }) do P.onSearchResults(id, listing) end
    T.clock = T.clock + 7
    T.tickers[#T.tickers].fn()
    P.onSearchResults(3, listing)
    P.onSearchResults(101, listing)
    H.eq(P.state, "done")
    H.eq(P.status, "Prices updated, 1 not found")
    H.eq(T.env.CraftProfitDB.prices[100], nil)
end)

H.test("closing the AH cancels a running search", function()
    local T = boot()
    local P = T.ns.PinsUI
    T.ns.AH.isOpen = true
    P.startSearch()
    P.onAHOpen(false)
    H.eq(P.state, "cancelled")
    H.eq(P.status, "Search cancelled")
    P.onSearchResults(1, listing)
    H.eq(T.env.CraftProfitDB.prices[1], nil)
end)

H.test("a second search does not start while one is running", function()
    local T = boot()
    local P = T.ns.PinsUI
    T.ns.AH.isOpen = true
    P.startSearch()
    P.startSearch()
    H.eq(T.sent, { 1 })
end)

H.test("results for items nobody asked about are ignored", function()
    local T = boot()
    T.ns.PinsUI.onSearchResults(1, listing)
    H.eq(T.env.CraftProfitDB.prices[1], nil)
end)

H.test("searching with no pins does nothing", function()
    local T = W.boot(H, { items = ITEMS })
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    T.ns.AH.isOpen = true
    T.ns.PinsUI.startSearch()
    H.eq(T.ns.PinsUI.state, "idle")
end)

H.test("scan reports a closed AH, a cooldown and a started scan", function()
    local T = boot()
    local P = T.ns.PinsUI
    P.scan()
    H.eq(P.status, "Open the auction house first")
    T.ns.AH.isOpen = true
    T.ns.AH.requestSnapshot = function() return false, "cooldown", 600 end
    P.scan()
    H.eq(P.status, "Full scan available in 10m")
    T.ns.AH.requestSnapshot = function() return true end
    P.scan()
    H.eq(P.status, "Scanning the auction house...")
end)

H.test("a finished scan stores prices and reports the count", function()
    local T = boot()
    local agg = T.ns.Prices.newAggregator()
    agg.add(1, 100, 1)
    agg.add(2, 50, 1)
    T.ns.Controller.onSnapshot(agg)
    H.eq(T.ns.PinsUI.status, "Scan complete: 2 items priced")
    H.eq(T.env.CraftProfitDB.prices[1][1], 100)
    H.truthy(T.env.CraftProfitDB.snapshotTime)
end)

H.test("opening the AH shows the pins and selects the first one", function()
    local T = boot()
    T.ns.AH.isOpen = true
    T.ns.Controller.onAHOpen(true)
    H.eq(T.ns.Controller.currentRecipeID(), 1)
    H.truthy(T.ns.Window.isShown())
    H.truthy(T.ns.Window.pinsHost():IsShown())
    T.ns.Controller.onAHOpen(false)
    H.falsy(T.ns.Window.isShown())
end)

H.test("selecting a pinned recipe shows it in the window", function()
    local T = boot()
    T.ns.AH.isOpen = true
    T.ns.Controller.onAHOpen(true)
    T.ns.Controller.selectPin(2)
    H.eq(T.ns.Controller.currentRecipeID(), 2)
    T.ns.Controller.selectPin(999)
    H.eq(T.ns.Controller.currentRecipeID(), 2)
end)

H.test("the pins list refreshes without errors when empty or large", function()
    local T = W.boot(H, { items = ITEMS })
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    T.ns.PinsUI.refresh()
    for i = 1, 12 do
        T.ns.DB.pinAdd(T.env.CraftProfitCharDB, raw(i, 100, { { itemID = 1, qty = 1 } }))
    end
    T.ns.PinsUI.refresh()
end)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `luajit tests/run.lua`
Expected: FAIL in `tests/test_pinsui.lua` (`ns.PinsUI` is nil).

- [ ] **Step 3: Implement `UI/PinsUI`**

```lua file=CraftProfit/UI/PinsUI.lua
-- The pinned-recipes section of the window, shown while the AH is open, with
-- the "Search prices" and "Scan AH" buttons.
local _, ns = ...
local L = ns.L

local PinsUI = {}
ns.PinsUI = PinsUI

local PAD = 10
local ROW_H = 18
local VISIBLE = 6
local TOP = 26
local FOOTER_H = 50
local SEARCH_TIMEOUT = 6
local TICK_SECONDS = 0.2

local COLORS = {
    profit = { 0.35, 0.90, 0.45 },
    loss = { 1.00, 0.40, 0.35 },
    muted = { 0.65, 0.65, 0.70 },
}

local ctl
local host, header, emptyText, statusText, searchButton, scanButton
local rows = {}
local offset = 0
local queue, ticker

PinsUI.state = "idle"
PinsUI.status = ""

function PinsUI.setStatus(text)
    PinsUI.status = text
    if statusText then statusText:SetText(text) end
end
local setStatus = PinsUI.setStatus

-- Item ids whose prices all the pinned recipes need, each listed once.
function PinsUI.wantedFor(pins, itemInfo, lookup)
    local ids, seen = {}, {}
    for _, recipe in ipairs(pins) do
        for _, id in ipairs(ns.Evaluate.wantedItems(recipe, itemInfo, lookup)) do
            if not seen[id] then
                seen[id] = true
                ids[#ids + 1] = id
            end
        end
    end
    return ids
end

function PinsUI.refresh()
    if not host then return end
    local pins = CraftProfitCharDB.pins
    offset = math.max(0, math.min(offset, #pins - VISIBLE))
    local currentID = ctl.currentRecipeID()

    header:SetText(L.PINS_TITLE)
    searchButton:SetText(L.SEARCH_PRICES)
    scanButton:SetText(L.SCAN)
    emptyText:SetText(L.PINS_EMPTY)
    emptyText:SetShown(#pins == 0)

    for i = 1, VISIBLE do
        local row, recipe = rows[i], pins[offset + i]
        if recipe then
            local result = ctl.evaluate(recipe)
            row.recipeID = recipe.recipeID
            row.name:SetText(recipe.name ~= "" and recipe.name or ("#" .. recipe.recipeID))
            if result.net ~= nil then
                row.value:SetText(ctl.fmt(result.net))
                local c = result.net >= 0 and COLORS.profit or COLORS.loss
                row.value:SetTextColor(c[1], c[2], c[3])
            else
                row.value:SetText("?")
                row.value:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3])
            end
            row.selected:SetShown(recipe.recipeID == currentID)
            row:Show()
        else
            row.recipeID = nil
            row:Hide()
        end
    end

    local shown = math.max(1, math.min(#pins, VISIBLE))
    local top = TOP + shown * ROW_H + 6
    searchButton:ClearAllPoints()
    searchButton:SetPoint("TOPLEFT", host, "TOPLEFT", PAD, -top)
    scanButton:ClearAllPoints()
    scanButton:SetPoint("TOPRIGHT", host, "TOPRIGHT", -PAD, -top)
    statusText:ClearAllPoints()
    statusText:SetPoint("TOPLEFT", host, "TOPLEFT", PAD, -top - 26)
    host:SetHeight(top + FOOTER_H)
    ns.Window.relayout()
end

local function finishSearch(summary)
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    if summary.cancelled then
        PinsUI.state = "cancelled"
        setStatus(L.SEARCH_CANCELLED)
    else
        PinsUI.state = "done"
        if #summary.failed > 0 then
            setStatus(string.format(L.SEARCH_PARTIAL, #summary.failed))
        else
            setStatus(L.SEARCH_DONE)
        end
    end
    ctl.requestRefresh()
end

-- Searches the AH, one item at a time, for everything the pinned recipes need.
function PinsUI.startSearch()
    if not ns.AH.isOpen then
        setStatus(L.SEARCH_NEED_AH)
        return
    end
    if queue and queue.state == "running" then return end
    local ids = PinsUI.wantedFor(CraftProfitCharDB.pins, ctl.itemInfo, ns.Data.Disenchant.lookup)
    if #ids == 0 then return end
    queue = ns.PriceQueue.new({
        itemIDs = ids,
        timeout = SEARCH_TIMEOUT,
        send = ns.AH.search,
        onItem = function(itemID, listings, err)
            if not err then ctl.recordListings(itemID, listings) end
        end,
        onProgress = function(done, total)
            setStatus(string.format(L.SEARCHING, done, total))
            ctl.requestRefresh()
        end,
        onDone = finishSearch,
    })
    PinsUI.state = "running"
    setStatus(string.format(L.SEARCHING, 0, #ids))
    queue:start(GetTime())
    if queue.state == "running" then
        ticker = C_Timer.NewTicker(TICK_SECONDS, function() queue:tick(GetTime()) end)
    end
end

function PinsUI.scan()
    local ok, reason, left = ns.AH.requestSnapshot(GetTime())
    if ok then
        setStatus(L.SCAN_STARTED)
    elseif reason == "cooldown" then
        setStatus(string.format(L.SCAN_COOLDOWN, ns.Present.durationText(L, left) or "?"))
    else
        setStatus(L.SEARCH_NEED_AH)
    end
end

function PinsUI.onAHOpen(open)
    if not host then return end
    host:SetShown(open)
    if not open and queue and queue.state == "running" then queue:cancel() end
    PinsUI.refresh()
end

function PinsUI.onSearchResults(itemID, listings)
    if queue and queue.state == "running" then queue:results(itemID, listings, GetTime()) end
end

function PinsUI.init(controller)
    ctl = controller
    host = ns.Window.pinsHost()

    header = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", host, "TOPLEFT", PAD, -6)
    emptyText = host:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyText:SetPoint("TOPLEFT", host, "TOPLEFT", PAD, -TOP - 2)

    for i = 1, VISIBLE do
        local row = CreateFrame("Button", nil, host)
        row:SetSize(270 - PAD * 2, ROW_H)
        row:SetPoint("TOPLEFT", host, "TOPLEFT", PAD, -(TOP + (i - 1) * ROW_H))
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.selected = row:CreateTexture(nil, "BACKGROUND")
        row.selected:SetAllPoints()
        row.selected:SetColorTexture(1, 1, 1, 0.08)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.name:SetWidth(150)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.value:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.value:SetJustifyH("RIGHT")
        row:SetScript("OnClick", function(self)
            if self.recipeID then ctl.selectPin(self.recipeID) end
        end)
        rows[i] = row
    end

    searchButton = CreateFrame("Button", nil, host, "UIPanelButtonTemplate")
    searchButton:SetSize(120, 22)
    searchButton:SetScript("OnClick", PinsUI.startSearch)
    scanButton = CreateFrame("Button", nil, host, "UIPanelButtonTemplate")
    scanButton:SetSize(90, 22)
    scanButton:SetScript("OnClick", PinsUI.scan)
    statusText = host:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    statusText:SetWidth(270 - PAD * 2)
    statusText:SetJustifyH("LEFT")

    host:EnableMouseWheel(true)
    host:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta)
        PinsUI.refresh()
    end)
    host:Hide()
end
```

- [ ] **Step 4: Add the file to the TOC**

```text file=CraftProfit/CraftProfit.toc
## Interface: 16001
## Title: CraftProfit
## Notes: Prices profession recipes with auction house data and shows the most profitable way to sell the result.
## Author: juliani
## Version: 0.1.0
## SavedVariables: CraftProfitDB
## SavedVariablesPerCharacter: CraftProfitCharDB

Util.lua
Format.lua
Core.lua
Data/Skillup.lua
Data/Disenchant.lua
Locale.lua
Locales/enUS.lua
Locales/frFR.lua
Locales/esES.lua
Locales/esMX.lua
Recipes.lua
DB.lua
Prices.lua
PriceQueue.lua
Evaluate.lua
Present.lua
AHAdapter.lua
TradeAdapter.lua
UI/Window.lua
UI/PinsUI.lua
Boot.lua
```

- [ ] **Step 5: Run the tests and luacheck**

Run: `sh tests/check.sh`
Expected: all pass (apart from the disenchant data test if Task 5 Step 8 was not done yet), luacheck clean. `tests/test_boot.lua` now also loads `UI/PinsUI.lua` because it reads the TOC.

- [ ] **Step 6: Try it at the auction house (user action)**

In game: pin two recipes from the profession window (click **Pin**). Open the auction house.
Expected: the window shows the recipe plus a "Pinned recipes" list. Click **Search prices**: the status counts `Searching 1/N … N/N`, then `Prices updated`; recipe values and the verdict fill in and `Prices: 0s ago` appears. Close the AH during a search: status `Search cancelled`, no Lua error.

- [ ] **Step 7: Commit**

```bash
git add CraftProfit/UI/PinsUI.lua CraftProfit/CraftProfit.toc tests/test_pinsui.lua
git commit -m "feat: add pinned recipes list with AH price search and scan"
```

---

### Task 17: Final verification, TOC consistency check and in-game checklist

**Files:**
- Create: `tests/test_toc.lua`, `docs/in-game-checklist.md`
- Modify: `CraftProfit/Data/Disenchant.lua` (only if the checklist shows the data differs in Forever)

- [ ] **Step 1: Write the TOC consistency test**

```lua file=tests/test_toc.lua
local H = ...

local function tocFiles()
    local files = {}
    local f = assert(io.open("CraftProfit/CraftProfit.toc"))
    for line in f:lines() do
        if not line:match("^##") and line:match("%S") then files[#files + 1] = line:match("^%s*(.-)%s*$") end
    end
    f:close()
    return files
end

local function lua_files_on_disk()
    local found = {}
    local p = io.popen("cd CraftProfit && find . -name '*.lua' | sed 's#^\\./##' | sort")
    for line in p:lines() do found[#found + 1] = line end
    p:close()
    return found
end

H.test("every file listed in the TOC exists", function()
    for _, name in ipairs(tocFiles()) do
        local f = io.open("CraftProfit/" .. name)
        H.truthy(f or error("TOC lists a missing file: " .. name))
        f:close()
    end
end)

H.test("every addon Lua file is listed in the TOC exactly once", function()
    local listed = {}
    for _, name in ipairs(tocFiles()) do
        if listed[name] then error("listed twice: " .. name) end
        listed[name] = true
    end
    for _, name in ipairs(lua_files_on_disk()) do
        if not listed[name] then error("not in the TOC: " .. name) end
    end
end)

H.test("the TOC declares the Forever interface and both saved variables", function()
    local f = assert(io.open("CraftProfit/CraftProfit.toc"))
    local text = f:read("*a")
    f:close()
    H.truthy(text:find("## Interface: 16001", 1, true))
    H.truthy(text:find("## SavedVariables: CraftProfitDB", 1, true))
    H.truthy(text:find("## SavedVariablesPerCharacter: CraftProfitCharDB", 1, true))
end)

H.test("no addon file uses syntax or APIs missing from WoW's Lua 5.1", function()
    for _, name in ipairs(lua_files_on_disk()) do
        local f = assert(io.open("CraftProfit/" .. name))
        local text = f:read("*a")
        f:close()
        for _, banned in ipairs({ "goto ", "require%(", "io%.", "loadfile", "dofile", "setfenv", "getfenv" }) do
            if text:find(banned) then error(name .. " uses " .. banned) end
        end
    end
end)
```

- [ ] **Step 2: Run the whole suite**

Run: `sh tests/check.sh`
Expected: every test passes (including the three disenchant data tests, which require Task 5 Step 8 to be complete) and luacheck reports `0 warnings / 0 errors`.
If `test_toc` reports a file not in the TOC, add it to `CraftProfit/CraftProfit.toc`; if it reports a missing file, fix the TOC line.

- [ ] **Step 3: Write the in-game checklist**

```markdown file=docs/in-game-checklist.md
# CraftProfit in-game checklist (WoW: Forever beta)

Run on the blacksmith (level 30, skill 140+) with `/console scriptErrors 1`. Mark each line ✅ / ❌ and note the build number from `/cpp locale`-style output or the login screen. Retest on the launch build (4 November 2026).

## Load and self-test
- [ ] Client starts with no Lua error popup. `/cp` prints the command list.
- [ ] `/cp selftest` prints `Self-test passed (11 checks)`.

## Profession window
- [ ] Selecting an orange recipe shows Materials, AH, Vendor, Disenchant (when the product is armor or a weapon of uncommon quality or better) and a verdict.
- [ ] Selecting a recipe whose product cannot be sold on the AH (bind on pickup) shows `n/a` on the AH line.
- [ ] A recipe you have not learned shows nothing (window hides or keeps the empty text).
- [ ] The window opens on the right of the profession window; dragging it and `/reload` keeps the position; `/cp reset` puts it back.
- [ ] Closing the profession window hides the window (outside the AH).
- [ ] Ticking "Show cost per skill point" adds a line marked `(estimate)`; a grey recipe shows `n/a`.
- [ ] The Pin button toggles to Unpin and back.

## Auction house
- [ ] Opening the AH shows the window with the Pinned recipes section (first pin selected).
- [ ] **Search prices** counts `1/N … N/N` and ends with `Prices updated`; prices and the verdict fill in; the age reads a few seconds.
- [ ] Closing the AH during a search shows `Search cancelled` with no error.
- [ ] **Scan AH** starts a scan, the client does not freeze, the status ends `Scan complete: N items priced`. A second press inside 15 minutes shows the cooldown message.
- [ ] A scan started by another addon (if installed) is picked up (prices refresh) without pressing Scan.
- [ ] After a scan, a recipe unpriced by the targeted search gets its price from the scan.

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
```

- [ ] **Step 4: Run the in-game checklist (user action)**

Work through `docs/in-game-checklist.md` in the game. For every ❌, write a short note under the line and fix the cause with a new failing test where the failure is reproducible offline.

- [ ] **Step 5: Commit**

```bash
git add tests/test_toc.lua docs/in-game-checklist.md
git commit -m "test: add TOC consistency checks and in-game checklist"
```
