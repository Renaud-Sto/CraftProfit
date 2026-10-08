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
