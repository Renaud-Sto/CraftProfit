-- CraftProfitProbe: THROWAWAY addon measuring what the Forever client exposes.
-- Every output line starts with the version so a stale install is obvious.
local VERSION = "0.4.1"
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

-- Persistent log: SavedVariables are written to disk on /reload or logout only.
-- File: WTF/Account/<ACCOUNT>/SavedVariables/CraftProfitProbe.lua
local MAX_LOG = 3000
local lastText, lastRepeat, lastStamp
local function logLine(text)
    if type(CraftProfitProbeLog) ~= "table" then CraftProfitProbeLog = {} end
    local log = CraftProfitProbeLog
    if text == lastText then
        lastRepeat = lastRepeat + 1
        log[#log] = lastStamp .. " " .. text .. " (x" .. lastRepeat .. ")"
        return
    end
    lastText, lastRepeat, lastStamp = text, 1, date("%H:%M:%S")
    log[#log + 1] = lastStamp .. " " .. text
    if #log > MAX_LOG then table.remove(log, 1) end
end

local function plain(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function out(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = show((select(i, ...))) end
    DEFAULT_CHAT_FRAME:AddMessage(TAG .. table.concat(parts, " "))
end

-- Mirror every chat line printed by CraftProfit or this probe (selftest results included).
hooksecurefunc(DEFAULT_CHAT_FRAME, "AddMessage", function(_, text)
    if type(text) ~= "string" or isSecret(text) then return end
    if text:find("CraftProfit", 1, true) or text:find("[CPP", 1, true) then
        logLine(plain(text))
    end
end)

-- Mirror Lua errors, then hand them to the normal handler.
local previousHandler = geterrorhandler()
seterrorhandler(function(err)
    logLine("LUA ERROR: " .. show(err))
    return previousHandler(err)
end)

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

-- How to tell which professions the character has (needed: is Enchanting known?).
-- Enchanting skill line 333, apprentice spell 7411.
cmds.prof = function()
    local ids = { try(GetProfessions) }
    out("GetProfessions:", ids[1])
    for i = 1, 6 do
        local r = try(GetProfessionInfo, i)
        if r ~= "MISSING" and r ~= "(no return)" and not r:find("^ERR") then out(" GetProfessionInfo", i, r) end
    end
    out("C_TradeSkillUI.GetAllProfessionTradeSkillLines:",
        try(C_TradeSkillUI and C_TradeSkillUI.GetAllProfessionTradeSkillLines))
    out("C_TradeSkillUI.GetProfessionInfoBySkillLineID(333):",
        try(C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID, 333))
    out("IsSpellKnown(7411):", try(IsSpellKnown, 7411))
    out("IsPlayerSpell(7411):", try(IsPlayerSpell, 7411))
    out("C_SpellBook.IsSpellKnown(7411):", try(C_SpellBook and C_SpellBook.IsSpellKnown, 7411))
    out("GetNumSkillLines:", try(GetNumSkillLines))
    local lines = tonumber(try(GetNumSkillLines)) or 0
    for i = 1, math.min(lines, 40) do
        local r = try(GetSkillLineInfo, i)
        if r:find("Enchant") or r:find("Forge") or r:find("Blacksmith") or r:find("Enchantement") then
            out(" GetSkillLineInfo", i, r)
        end
    end
end

-- What the Blizzard auction house UI offers for "click a reagent, search it" (needs the
-- AH open). Prints only types and plain values, never changes anything.
cmds.ahui = function(arg)
    local f = AuctionHouseFrame
    out("AuctionHouseFrame:", type(f), "shown:", f and f:IsShown())
    if type(f) ~= "table" then return end
    for _, name in ipairs({ "SearchBar", "BrowseResultsFrame", "CommoditiesBuyFrame", "ItemBuyFrame",
        "SetDisplayMode", "GetDisplayMode", "SelectBrowseResult", "QueryAll", "ItemSellFrame" }) do
        out(" f." .. name, type(f[name]))
    end
    local bar = f.SearchBar
    if type(bar) == "table" then
        for _, name in ipairs({ "SearchBox", "SearchButton", "StartSearch", "FilterButton", "QueryBrowse" }) do
            out(" SearchBar." .. name, type(bar[name]))
        end
        out(" SearchBox text:", bar.SearchBox and bar.SearchBox.GetText and bar.SearchBox:GetText())
    end
    local buy = f.CommoditiesBuyFrame
    if type(buy) == "table" then
        out(" CommoditiesBuyFrame.BuyDisplay:", type(buy.BuyDisplay),
            "QuantityInput:", type(buy.BuyDisplay and buy.BuyDisplay.QuantityInput))
    end
    out("display modes:", type(AuctionHouseFrameDisplayMode), try(function()
        local keys = {}
        for k in pairs(AuctionHouseFrameDisplayMode or {}) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        return table.concat(keys, "/")
    end))
    out("GetDisplayMode:", try(f.GetDisplayMode, f))
    local id = tonumber(arg) or 2841
    out("C_AuctionHouse.GetItemCommodityStatus(" .. id .. "):", try(C_AuctionHouse.GetItemCommodityStatus, id))
    for _, name in ipairs({ "SendBrowseQuery", "SendSearchQuery", "StartCommoditiesPurchase",
        "GetBrowseResults", "RequestMoreBrowseResults", "MakeItemKey", "GetItemKeyInfo" }) do
        out(" C_AuctionHouse." .. name, type(C_AuctionHouse[name]))
    end
end

-- Open an item's buy view in the AH first. Lists what the quantity input is made of.
cmds.qty = function()
    local buy = AuctionHouseFrame and AuctionHouseFrame.CommoditiesBuyFrame
    local display = buy and buy.BuyDisplay
    local input = display and display.QuantityInput
    local function keys(name, t)
        if type(t) ~= "table" then out(name, "=", type(t)); return end
        local list = {}
        for k, v in pairs(t) do list[#list + 1] = tostring(k) .. ":" .. type(v) end
        table.sort(list)
        out(name, #list, "keys:", table.concat(list, " ", 1, math.min(#list, 70)))
    end
    out("buy shown:", buy and buy:IsShown(), "GetItemID:", try(buy and buy.GetItemID, buy))
    keys("CommoditiesBuyFrame", buy)
    keys("BuyDisplay", display)
    keys("QuantityInput", input)
    keys("InputBox", input and input.InputBox)
    local box = input and input.InputBox
    out("InputBox OnTextChanged script:", type(box and box.GetScript and box:GetScript("OnTextChanged")))
    out("input GetQuantity:", try(input and input.GetQuantity, input))
end

-- Forever has no realms but rulesets (Normal, PvP, RP, Hardcore). Looks for how the
-- client tells them apart: realm and faction calls, then every global whose name
-- mentions a ruleset, a game mode, hardcore, a season or a realm.
cmds.ruleset = function()
    for _, name in ipairs({ "GetRealmName", "GetNormalizedRealmName", "GetServerName", "GetCurrentRegion",
        "GetCurrentRegionName", "GetClassicExpansionLevel", "GetServerExpansionLevel", "GetAccountExpansionLevel" }) do
        out(name .. ":", try(_G[name]))
    end
    out("UnitFactionGroup(player):", try(UnitFactionGroup, "player"))
    out("GetBuildInfo:", try(GetBuildInfo))
    out("WOW_PROJECT_ID:", show(WOW_PROJECT_ID))
    -- The game mode API found by the first run (C_GameRules, Enum.GameMode).
    local rules = C_GameRules
    if type(rules) == "table" then
        out("GetActiveGameMode:", try(rules.GetActiveGameMode))
        out("GetCurrentGameModeRecordID:", try(rules.GetCurrentGameModeRecordID))
        out("IsHardcoreActive:", try(rules.IsHardcoreActive))
        local info = rules.GetCurrentGameModeDisplayInfo and select(2, pcall(rules.GetCurrentGameModeDisplayInfo))
        dumpTable("GetCurrentGameModeDisplayInfo", info)
        local record = select(2, pcall(rules.GetCurrentGameModeRecordID))
        if record ~= nil then
            out("GetGameModeGlueScreenName(record):", try(rules.GetGameModeGlueScreenName, record))
            dumpTable("GetGameModeDisplayInfoByRecordID", select(2, pcall(rules.GetGameModeDisplayInfoByRecordID, record)))
        end
        out("GetNumDisplayedGameModes:", try(rules.GetNumDisplayedGameModes))
    end
    dumpTable("Enum.GameMode", Enum and Enum.GameMode)
    out("GetRealmID:", try(GetRealmID), "GetNativeRealmID:", try(GetNativeRealmID),
        "UnitRealmRelationship:", try(UnitRealmRelationship, "player"))
    local patterns = { "[Rr]uleset", "[Gg]ameMode", "[Gg]ameRule", "[Hh]ardcore", "[Ss]eason", "[Rr]ealm", "[Ww]orldType" }
    local function matches(name)
        for _, pat in ipairs(patterns) do if name:find(pat) then return true end end
        return false
    end
    local found = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and matches(k) then found[#found + 1] = k .. ":" .. type(v) end
        if type(k) == "string" and (k:find("^C_") or k == "Enum") and type(v) == "table" then
            for k2, v2 in pairs(v) do
                if type(k2) == "string" and matches(k2) then found[#found + 1] = k .. "." .. k2 .. ":" .. type(v2) end
            end
        end
    end
    table.sort(found)
    out("matching globals:", #found)
    for i = 1, #found, 6 do
        out(" ", table.concat(found, " ", i, math.min(i + 5, #found)))
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

-- The client fires REPLICATE_ITEM_LIST_UPDATE hundreds of times per scan: count them,
-- but read the rows only once per DETAIL_EVERY seconds (reading 78k rows per event
-- tripped "insecure scripts exceeded execution limit").
local DETAIL_EVERY = 5
local replicateEvents, lastDetail = 0, nil

frame:SetScript("OnEvent", function(_, event, a1)
    if event == "ITEM_DATA_LOAD_RESULT" then return end
    if event == "REPLICATE_ITEM_LIST_UPDATE" then
        replicateEvents = replicateEvents + 1
        local now = GetTime()
        if lastDetail and now - lastDetail < DETAIL_EVERY then return end
        lastDetail = now
        out("replicate events so far:", replicateEvents)
    end
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
        for i = 1, math.min(n, 2000) do
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
    if cmd == "log" then
        out("replicate events:", replicateEvents)
        out("logged lines:", CraftProfitProbeLog and #CraftProfitProbeLog or 0,
            "- type /reload to write them to disk")
    elseif cmd == "clear" then
        CraftProfitProbeLog = {}
        out("log cleared")
    elseif fn then
        out("== " .. cmd .. " " .. arg)
        fn(arg)
    else
        out("commands: api | locale | item <id> | deposit <id> | search <id> | replicate | trade | prof | ahui | qty | ruleset | log | clear")
    end
end
out("loaded. /cpp for commands. Enable Lua errors: /console scriptErrors 1")
