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
function Trade.hasProfession(skillLine)
    if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
        local listed = { pcall(GetProfessions) }
        if listed[1] then
            for i = 2, 8 do
                local index = listed[i]
                if type(index) == "number" and not isSecret(index) then
                    local ok, _, _, _, _, _, _, line = pcall(GetProfessionInfo, index)
                    if ok and not isSecret(line) and line == skillLine then return true end
                end
            end
        end
    end
    if skillLine == Trade.ENCHANTING_SKILL_LINE and type(IsPlayerSpell) == "function" then
        local ok, known = pcall(IsPlayerSpell, ENCHANTING_SPELL)
        if ok and not isSecret(known) and known == true then return true end
    end
    return false
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
