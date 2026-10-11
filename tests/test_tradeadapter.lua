local H = ...

local function setup()
    local env = setmetatable({}, { __index = _G })
    -- Util in the same environment: Util.isSecret reads the test's issecretvalue.
    local ns = {}
    for _, name in ipairs({ "Util", "Data/Skillup" }) do H.loadModule(name, ns, env) end
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
        recipeID = 5, name = "Copper Sword", difficulty = "easy", outputItemID = 2845,
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

H.test("hasProfession reads the skill line of each profession, in any language", function()
    local T = setup()
    T.env.GetProfessions = function() return 6, 8, nil, nil, 7 end
    local lines = { [6] = 164, [8] = 186, [7] = 185 }
    T.env.GetProfessionInfo = function(i) return "Forge", 1, 144, 150, 1, 48, lines[i] end
    H.truthy(T.Trade.hasProfession(164))
    H.truthy(T.Trade.hasProfession(185))
    H.falsy(T.Trade.hasProfession(T.Trade.ENCHANTING_SKILL_LINE))
    lines[8] = 333
    H.truthy(T.Trade.hasProfession(T.Trade.ENCHANTING_SKILL_LINE))
end)

H.test("hasProfession falls back to the Enchanting spell and never raises", function()
    local T = setup()
    H.falsy(T.Trade.hasProfession(T.Trade.ENCHANTING_SKILL_LINE))
    T.env.IsPlayerSpell = function(id) return id == 7411 end
    H.truthy(T.Trade.hasProfession(T.Trade.ENCHANTING_SKILL_LINE))
    H.falsy(T.Trade.hasProfession(164))
    T.env.GetProfessions = function() error("boom") end
    T.env.GetProfessionInfo = function() error("boom") end
    H.falsy(T.Trade.hasProfession(164))
end)

H.test("difficultyOf names the recipe's current difficulty, nil when unreadable", function()
    local T = setup()
    H.eq(T.Trade.difficultyOf(1), nil)
    T.env.C_TradeSkillUI = { GetRecipeInfo = function(id)
        return ({ [1] = { learned = true, relativeDifficulty = 0 }, [2] = { learned = true, relativeDifficulty = 3 },
            [3] = { learned = false, relativeDifficulty = 1 }, [4] = { learned = true, relativeDifficulty = 9 } })[id]
    end }
    H.eq(T.Trade.difficultyOf(1), "optimal")
    H.eq(T.Trade.difficultyOf(2), "trivial")
    H.eq(T.Trade.difficultyOf(3), nil)
    H.eq(T.Trade.difficultyOf(4), nil)
    H.eq(T.Trade.difficultyOf(5), nil)
end)

-- Known recipes of the open profession
local function openProfession(T, api)
    T.env.ProfessionsFrame = professions(1)
    T.env.Enum = { CraftingReagentType = { Basic = BASIC } }
    T.env.C_TradeSkillUI = api
    T.env.C_Timer.After = function(_, fn) T.later[#T.later + 1] = fn end
    T.later = {}
    T.drain = function()
        while #T.later > 0 do table.remove(T.later, 1)() end
    end
end

H.test("scanKnown reads every learned recipe, grey ones included, in chunks and reports them", function()
    local T = setup()
    local api = mainlineApi({
        GetAllRecipeIDs = function() return { 10, 11, 12, 13, 14 } end,
        GetRecipeInfo = function(id)
            local learned = id ~= 11
            local difficulty = id == 12 and 3 or 1       -- 12 is grey
            return { recipeID = id, name = "R" .. id, learned = learned, relativeDifficulty = difficulty }
        end,
    })
    openProfession(T, api)
    T.Trade.KNOWN_CHUNK = 2
    local got
    H.truthy(T.Trade.scanKnown(function(list) got = list end))
    H.eq(got, nil)
    T.drain()
    local ids = {}
    for i, raw in ipairs(got) do ids[i] = raw.recipeID end
    H.eq(ids, { 10, 12, 13, 14 })
    H.eq(got[2].difficulty, "trivial")
    H.eq(T.Trade.difficultyOf(12), "trivial")
    H.eq(got[1].reagents[1], { itemID = 2840, qty = 6 })
end)

H.test("scanKnown needs the open window and the API, and a newer scan replaces the older one", function()
    local T = setup()
    H.eq(T.Trade.scanKnown(function() end), false)
    local api = mainlineApi({ GetAllRecipeIDs = function() return { 10, 11 } end })
    openProfession(T, api)
    T.Trade.KNOWN_CHUNK = 1
    local first, second = 0, 0
    T.Trade.scanKnown(function() first = first + 1 end)
    T.Trade.scanKnown(function() second = second + 1 end)
    T.drain()
    H.eq({ first, second }, { 0, 1 })
    api.GetAllRecipeIDs = nil
    H.eq(T.Trade.scanKnown(function() end), false)
end)

H.test("scanKnown gives up quietly when the window closes, and never reports a partial list", function()
    local T = setup()
    local api = mainlineApi({ GetAllRecipeIDs = function() return { 10, 11, 12 } end })
    openProfession(T, api)
    T.Trade.KNOWN_CHUNK = 1
    local done, aborted = false, false
    T.Trade.scanKnown(function() done = true end, function() aborted = true end)
    T.env.ProfessionsFrame = professions(1, false)
    T.drain()
    H.eq({ done, aborted }, { false, true })
end)

H.test("professionInfo names the open profession from the info table or the classic line", function()
    local T = setup()
    H.eq({ T.Trade.professionInfo() }, {})
    T.env.C_TradeSkillUI = { GetBaseProfessionInfo = function() return { professionID = 164, professionName = "Forge" } end }
    H.eq({ T.Trade.professionInfo() }, { "164", "Forge" })
    T.env.C_TradeSkillUI = { GetBaseProfessionInfo = function() return { professionName = "Forge" } end }
    H.eq({ T.Trade.professionInfo() }, { "Forge", "Forge" })
    T.env.C_TradeSkillUI = nil
    T.env.GetTradeSkillLine = function() return "Blacksmithing", 140, 150 end
    H.eq({ T.Trade.professionInfo() }, { "Blacksmithing", "Blacksmithing" })
    T.env.GetTradeSkillLine = function() error("boom") end
    H.eq({ T.Trade.professionInfo() }, {})
end)

-- Names in the client's current language
H.test("a recipe read from the window carries the client's language", function()
    local T = setup()
    T.env.ProfessionsFrame = professions(5)
    T.env.Enum = { CraftingReagentType = { Basic = BASIC } }
    T.env.C_TradeSkillUI = mainlineApi()
    H.eq(T.Trade.readSelected().locale, nil)
    T.env.GetLocale = function() return "frFR" end
    H.eq(T.Trade.readSelected().locale, "frFR")
    H.eq(T.Trade.locale(), "frFR")
    T.env.GetLocale = function() error("boom") end
    H.eq(T.Trade.locale(), nil)
    T.env.issecretvalue = function(v) return v == "SECRET" end
    T.env.GetLocale = function() return "SECRET" end
    H.eq(T.Trade.locale(), nil)
end)

H.test("recipeName reads the client's recipe name, nil when missing, empty, secret or raising", function()
    local T = setup()
    H.eq(T.Trade.recipeName(3398), nil)
    local name = "Hot Lion Chops"
    T.env.C_TradeSkillUI = { GetRecipeInfo = function(id)
        if id == 3398 then return { recipeID = id, name = name } end
        return nil
    end }
    H.eq(T.Trade.recipeName(3398), "Hot Lion Chops")
    H.eq(T.Trade.recipeName(7), nil)
    H.eq(T.Trade.recipeName(nil), nil)
    for _, bad in ipairs({ "", 12, "SECRET" }) do
        name = bad
        T.env.issecretvalue = function(v) return v == "SECRET" end
        H.eq(T.Trade.recipeName(3398), nil)
    end
    T.env.C_TradeSkillUI = { GetRecipeInfo = function() error("boom") end }
    H.eq(T.Trade.recipeName(3398), nil)
end)

H.test("professionName reads the character's profession list, then the trade skill display name", function()
    local T = setup()
    H.eq(T.Trade.professionName("185"), nil)
    T.env.GetProfessions = function() return 3, nil, 7 end
    T.env.GetProfessionInfo = function(index)
        if index == 3 then return "Blacksmithing", "icon", 140, 150, 0, 0, 164 end
        return "Cooking", "icon", 60, 75, 0, 0, 185
    end
    H.eq(T.Trade.professionName("185"), "Cooking")
    H.eq(T.Trade.professionName("164"), "Blacksmithing")
    -- Not a skill line id (an old key made of the name), or not one of the character's.
    H.eq(T.Trade.professionName("Forge"), nil)
    H.eq(T.Trade.professionName(nil), nil)
    H.eq(T.Trade.professionName("129"), nil)
    T.env.C_TradeSkillUI = { GetTradeSkillDisplayName = function(id) return id == 129 and "First Aid" or "" end }
    H.eq(T.Trade.professionName("129"), "First Aid")
    H.eq(T.Trade.professionName("333"), nil)
    T.env.C_TradeSkillUI = { GetTradeSkillDisplayName = function() error("boom") end }
    H.eq(T.Trade.professionName("129"), nil)
    -- A secret name in the list is skipped.
    T.env.issecretvalue = function(v) return v == "Cooking" end
    H.eq(T.Trade.professionName("185"), nil)
end)

H.test("isDataSourceChanging asks the client, false when it cannot", function()
    local T = setup()
    H.eq(T.Trade.isDataSourceChanging(), false)
    T.env.C_TradeSkillUI = { IsDataSourceChanging = function() return true end }
    H.eq(T.Trade.isDataSourceChanging(), true)
    T.env.C_TradeSkillUI = { IsDataSourceChanging = function() return false end }
    H.eq(T.Trade.isDataSourceChanging(), false)
    T.env.C_TradeSkillUI = { IsDataSourceChanging = function() error("boom") end }
    H.eq(T.Trade.isDataSourceChanging(), false)
end)

H.test("cancelScan drops the scan in progress without calling it back", function()
    local T = setup()
    local api = mainlineApi({ GetAllRecipeIDs = function() return { 10, 11, 12 } end })
    openProfession(T, api)
    T.Trade.KNOWN_CHUNK = 1
    local done, aborted = false, false
    T.Trade.scanKnown(function() done = true end, function() aborted = true end)
    T.Trade.cancelScan()
    T.drain()
    H.eq({ done, aborted }, { false, false })
    -- A new scan afterwards runs normally.
    T.Trade.scanKnown(function() done = true end)
    T.drain()
    H.truthy(done)
end)

H.test("readSelected drops secret fields and turns the difficulty into a known name", function()
    local T = setup()
    T.env.ProfessionsFrame = professions(5)
    T.env.Enum = { CraftingReagentType = { Basic = BASIC } }
    local SECRET = setmetatable({}, { __index = function() error("secret indexed") end })
    T.env.issecretvalue = function(v) return v == SECRET end
    T.env.C_TradeSkillUI = mainlineApi({
        GetRecipeInfo = function(id)
            return { recipeID = id, name = "Copper Sword", learned = true, relativeDifficulty = SECRET }
        end,
        GetRecipeSchematic = function()
            return { outputItemID = SECRET, quantityMin = SECRET, quantityMax = 2, reagentSlotSchematics = {
                { reagentType = BASIC, quantityRequired = SECRET, reagents = { { itemID = SECRET } } } } }
        end,
    })
    local raw = T.Trade.readSelected()
    H.eq(raw.difficulty, nil)
    H.eq(raw.outputItemID, nil)
    H.eq(raw.qtyMin, nil)
    H.eq(raw.reagents, { {} })
    -- An unknown difficulty number is no difficulty either (never an arbitrary table key).
    T.env.issecretvalue = nil
    T.env.C_TradeSkillUI = mainlineApi({
        GetRecipeInfo = function(id) return { recipeID = id, learned = true, relativeDifficulty = 42 } end,
    })
    H.eq(T.Trade.readSelected().difficulty, nil)
end)

H.test("a secret learned flag is not learned", function()
    local T = setup()
    T.env.ProfessionsFrame = professions(5)
    T.env.issecretvalue = function(v) return v == "SECRET" end
    T.env.C_TradeSkillUI = mainlineApi({
        GetRecipeInfo = function(id) return { recipeID = id, learned = "SECRET" } end,
    })
    H.eq(T.Trade.readSelected(), nil)
end)

H.test("scanKnown asks GetRecipeInfo once per recipe", function()
    local T = setup()
    T.env.ProfessionsFrame = professions(5)
    local asked = 0
    T.env.C_TradeSkillUI = mainlineApi({
        GetAllRecipeIDs = function() return { 1, 2, 3 } end,
        GetRecipeInfo = function(id)
            asked = asked + 1
            return { recipeID = id, name = "x", learned = true, relativeDifficulty = 0 }
        end,
    })
    T.env.C_Timer.After = function(_, fn) fn() end
    local got
    T.Trade.scanKnown(function(list) got = list end)
    H.eq(#got, 3)
    H.eq(asked, 3)
end)
