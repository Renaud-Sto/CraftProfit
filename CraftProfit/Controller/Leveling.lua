-- Controller: the leveling window (the known recipes of the open profession, ranked by cost
-- per point) and the profit tags of the profession window's recipe rows.
local _, ns = ...
local Prices, DB, Present, Leveling = ns.Prices, ns.DB, ns.Present, ns.Leveling
local Util, Format, Colors = ns.Util, ns.Format, ns.Colors
local L = ns.L

local Controller = ns.Controller

-- Known recipes ------------------------------------------------------------------

local knownBusy, knownLast = false, nil

-- Reads the learned recipes of the open profession for the leveling list. Bursts of
-- TRADE_SKILL_LIST_UPDATE are coalesced: one read at most every few seconds. Nothing is
-- read while the game is switching profession (the list is the old one or empty).
function Controller.refreshKnown()
    if knownBusy or not ns.Trade.isShown() or ns.Trade.isDataSourceChanging() then return false end
    local now = GetTime()
    if knownLast and now - knownLast < 5 then return false end
    local key, name = ns.Trade.professionInfo()
    if not key then return false end
    knownBusy, knownLast = true, now
    local started = ns.Trade.scanKnown(function(raws)
        knownBusy = false
        -- An empty read (the list was not built yet) never replaces a stored list, and the
        -- next list update may read again at once.
        if #raws == 0 then
            knownLast = nil
            return
        end
        DB.setKnown(CraftProfitCharDB, key, name, raws, time())
        if ns.LevelingUI then ns.LevelingUI.refresh() end
    end, function() knownBusy = false end)
    if not started then knownBusy = false end
    return started
end

-- recipeID -> recipe of a stored known list, built once per list (a new scan stores a new
-- table, so its index is rebuilt; the old one goes with it).
local knownIndex = setmetatable({}, { __mode = "k" })

-- The stored recipe `recipeID` of the open profession, or nil: not learned, not scanned yet,
-- or the client cannot say which profession is open.
local function knownRecipe(recipeID)
    if not Util.id(recipeID) then return nil end
    local prof = DB.findKnown(CraftProfitCharDB, (ns.Trade.professionInfo()))
    if not prof then return nil end
    local index = knownIndex[prof.recipes]
    if not index then
        index = {}
        for _, recipe in ipairs(prof.recipes) do index[recipe.recipeID] = recipe end
        knownIndex[prof.recipes] = index
    end
    return index[recipeID]
end

-- The tag of a recipe row of the profession window: text and colour ({ r, g, b, a }) of the
-- net of one craft (Present.rowTag), or nil when the recipe is not a stored known one or
-- has no figure. The caller runs it in a refresh pass (Controller.inPass).
function Controller.rowTag(recipeID)
    local recipe = knownRecipe(recipeID)
    if not recipe then return nil end
    local text, tone = Present.rowTag(Controller.evaluate(recipe, 1), Format.short)
    if not text then return nil end
    return text, Colors.tone(tone, "muted")
end

-- The profession window opened or switched profession (Forever's profession tabs switch
-- inside the open window, firing TRADE_SKILL_SHOW and TRADE_SKILL_DATA_SOURCE_CHANGED but
-- no close): the scan in progress reads the previous profession and is dropped, and the
-- few seconds of coalescing, which belonged to the previous profession, start again.
function Controller.onProfessionChanged()
    ns.Trade.cancelScan()
    knownBusy, knownLast = false, nil
    Controller.refreshPinDifficulties()
    Controller.refreshKnown()
    ns.Trade.invalidate()
end

-- What the leveling window shows: the current profession, its known recipes ranked
-- by cost per point from the last scan's prices, and how old those prices are.
local function levelData()
    local settings = CraftProfitDB.settings
    local prof = DB.currentKnown(CraftProfitCharDB)
    local age = Prices.snapshotAge(Controller.market(), time())
    local data = {
        showGrey = settings.levelShowGrey == true, sort = settings.levelSort, profession = prof,
        items = {}, hiddenGrey = 0,
        ageText = Present.ageText(L, age), stale = age == nil or age > settings.staleAfter,
    }
    if prof then
        local ranked = Leveling.rank(prof.recipes, function(recipe)
            return Controller.evaluate(recipe, 1, true)
        end, { showGrey = data.showGrey, sort = data.sort })
        data.items, data.hiddenGrey = ranked.items, ranked.hiddenGrey
    end
    return data
end

-- In one refresh pass (the one running, when Controller.refresh asks).
function Controller.levelData()
    return Controller.inPass(levelData)
end

function Controller.setLevelShowGrey(value)
    CraftProfitDB.settings.levelShowGrey = value and true or false
    if ns.LevelingUI then ns.LevelingUI.refresh() end
end

function Controller.toggleLevelSort()
    local settings = CraftProfitDB.settings
    settings.levelSort = settings.levelSort == "speed" and "cost" or "speed"
    if ns.LevelingUI then ns.LevelingUI.refresh() end
end

function Controller.nextLevelProfession()
    DB.nextKnown(CraftProfitCharDB)
    if ns.LevelingUI then ns.LevelingUI.refresh() end
end

-- A row of the leveling list was clicked: show that recipe in the main window.
function Controller.selectKnown(recipe)
    Controller.setRecipe(recipe, "pin")
end
