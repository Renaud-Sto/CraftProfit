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

-- Skill line ids are language independent (measured in the beta: Blacksmithing
-- is 164 in a French client). Enchanting is 333, its apprentice spell 7411.
Trade.ENCHANTING_SKILL_LINE = 333
local ENCHANTING_SPELL = 7411

-- True when the character has the profession. GetProfessions lists the
-- professions' indices; GetProfessionInfo returns the skill line as 7th value.
-- The character's professions as { name, line } (the name in the client's current
-- language; works with every profession window closed), possibly empty.
local function professions()
    local list = {}
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then return list end
    local listed = { pcall(GetProfessions) }
    if not listed[1] then return list end
    for i = 2, 8 do
        local index = listed[i]
        if type(index) == "number" and not isSecret(index) then
            local ok, name, _, _, _, _, _, line = pcall(GetProfessionInfo, index)
            if ok and not isSecret(line) then list[#list + 1] = { name = name, line = line } end
        end
    end
    return list
end

function Trade.hasProfession(skillLine)
    for _, prof in ipairs(professions()) do
        if prof.line == skillLine then return true end
    end
    if skillLine == Trade.ENCHANTING_SKILL_LINE and type(IsPlayerSpell) == "function" then
        local ok, known = pcall(IsPlayerSpell, ENCHANTING_SPELL)
        if ok and not isSecret(known) and known == true then return true end
    end
    return false
end

-- The recipe's current difficulty name ("optimal", "medium", "easy", "trivial") from
-- the open profession window, or nil when it cannot be read.
function Trade.difficultyOf(recipeID)
    local api = C_TradeSkillUI
    if not (api and api.GetRecipeInfo) then return nil end
    local ok, info = pcall(api.GetRecipeInfo, recipeID)
    if not ok or type(info) ~= "table" or info.learned ~= true then return nil end
    local difficulty = info.relativeDifficulty
    if isSecret(difficulty) then return nil end
    return ns.Data.Skillup.name(difficulty)
end

-- The client's language code ("frFR"), or nil.
function Trade.locale()
    if type(GetLocale) ~= "function" then return nil end
    local ok, locale = pcall(GetLocale)
    return ok and Util.text(locale, isSecret) or nil
end

-- The recipe's name in the client's current language, from the game's recipe data, or nil.
-- The game answers with the profession window closed too (measured: a table either way;
-- whether its name is filled then is not measured yet, `/cpp rname` shows it). A missing,
-- empty or secret name gives nil and the caller falls back to the crafted item's name.
function Trade.recipeName(recipeID)
    local api = C_TradeSkillUI
    if not (api and api.GetRecipeInfo) or not Util.id(recipeID) then return nil end
    local ok, info = pcall(api.GetRecipeInfo, recipeID)
    if not ok or type(info) ~= "table" then return nil end
    return Util.text(info.name, isSecret)
end

-- The name of a stored profession (its key, the skill line id as a string: "185") in the
-- client's current language, or nil. The character's profession list first (it needs no
-- open window), then the trade skill API's display name.
function Trade.professionName(key)
    local line = Util.id(tonumber(key))
    if not line then return nil end
    for _, prof in ipairs(professions()) do
        if prof.line == line then
            local name = Util.text(prof.name, isSecret)
            if name then return name end
        end
    end
    local api = C_TradeSkillUI
    if api and api.GetTradeSkillDisplayName then
        local ok, name = pcall(api.GetTradeSkillDisplayName, line)
        if ok then return Util.text(name, isSecret) end
    end
    return nil
end

-- True while the game is switching the window to another profession (the list is not
-- rebuilt yet: the Blizzard window waits too). False when the client cannot tell.
function Trade.isDataSourceChanging()
    local api = C_TradeSkillUI
    if not (api and api.IsDataSourceChanging) then return false end
    local ok, changing = pcall(api.IsDataSourceChanging)
    return ok and not isSecret(changing) and changing == true
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
        recipeID = recipeID, name = name, locale = Trade.locale(), difficulty = info.relativeDifficulty,
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
            recipeID = recipeID, name = name, locale = Trade.locale(), difficulty = kind,
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

-- Which profession the open window is about: key (a stable id when the client gives
-- one, else the name) and display name, or nil. Tries the usual info table fields
-- and the classic trade skill line.
function Trade.professionInfo()
    local api = C_TradeSkillUI
    local name, id
    if api and api.GetBaseProfessionInfo then
        local ok, info = pcall(api.GetBaseProfessionInfo)
        if ok and type(info) == "table" then
            for _, field in ipairs({ "professionID", "skillLineID", "parentProfessionID" }) do
                if not isSecret(info[field]) and Util.id(info[field]) then id = info[field]; break end
            end
            local n = info.professionName or info.name
            if type(n) == "string" and not isSecret(n) and n ~= "" then name = n end
        end
    end
    if not name and type(GetTradeSkillLine) == "function" then
        local ok, n = pcall(GetTradeSkillLine)
        if ok and type(n) == "string" and not isSecret(n) and n ~= "" then name = n end
    end
    if not id and not name then return nil end
    return id and tostring(id) or name, name or tostring(id)
end

-- Reads every learned recipe of the open profession (grey ones included, so the leveling
-- window can show them on request), a chunk per frame so the client never hitches. Calls
-- onDone(list) with raw recipes for Recipes.normalize. A newer scan abandons the one in progress.
local knownToken = 0
Trade.KNOWN_CHUNK = 40

function Trade.scanKnown(onDone, onAbort)
    local api = C_TradeSkillUI
    if not Trade.isShown() or not (api and api.GetAllRecipeIDs and api.GetRecipeInfo) then return false end
    local ok, ids = pcall(api.GetAllRecipeIDs)
    if not ok or type(ids) ~= "table" then return false end
    knownToken = knownToken + 1
    local token = knownToken
    local found, index = {}, 0
    local function step()
        if token ~= knownToken then return end
        if not Trade.isShown() then
            -- The window closed: a partial list must never replace a good one.
            knownToken = knownToken + 1
            if onAbort then onAbort() end
            return
        end
        local last = math.min(index + Trade.KNOWN_CHUNK, #ids)
        for i = index + 1, last do
            local id = Util.id(ids[i])
            local okInfo, info = pcall(api.GetRecipeInfo, id)
            if id and okInfo and type(info) == "table" and info.learned == true then
                local difficulty = info.relativeDifficulty
                if not isSecret(difficulty) then
                    local raw = readA(id)
                    if raw then found[#found + 1] = raw end
                end
            end
        end
        index = last
        if index < #ids then
            C_Timer.After(0, step)
        elseif onDone then
            onDone(found)
        end
    end
    step()
    return true
end

-- Abandons the scan in progress (its callbacks are never called): the window switched to
-- another profession, the list it was reading is gone.
function Trade.cancelScan()
    knownToken = knownToken + 1
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
