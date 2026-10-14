-- Controller, the first of its files in TOC order: creates ns.Controller. Chat output,
-- money format, the market, the refresh pass and what is read once per pass (item facts,
-- names, whether Enchanting is known, evaluations).
local _, ns = ...
local Util, Format, Prices, DB = ns.Util, ns.Format, ns.Prices, ns.DB
local Evaluate, Recipes = ns.Evaluate, ns.Recipes
local Disenchant = ns.Data.Disenchant

ns.Controller = ns.Controller or {}
local Controller = ns.Controller

local requestedItems = {}

-- The refresh pass in progress (Controller.inPass), or nil. One refresh evaluates the
-- recipe shown and every pin of each shown list (the leveling list: up to 400 recipes);
-- what does not change during it is looked up once: the market, the price lookup, whether
-- Enchanting is known, the item facts, and each evaluation. Filled on first use (nothing
-- opens the market before something needs it), dropped at the end: nothing outlives a pass.
local pass

function Controller.say(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffCraftProfit|r " .. tostring(text))
end

-- Forever has no GetCoinTextureString: GetMoneyString draws the gold, silver and copper
-- icons (measured with /cppn money). Anything else it answers falls back to plain text.
local function coinString(copper)
    if type(GetMoneyString) ~= "function" then return nil end
    local ok, text = pcall(GetMoneyString, copper)
    return ok and text or nil
end

function Controller.fmt(copper)
    return Format.money(copper, coinString)
end

-- Prices differ between markets, so each one has its own price table and history.
-- Forever has rulesets (Normal, PvP, RP, Hardcore) instead of realms; in the beta the
-- ruleset is the "realm" the character is on (for example "Classic Beta PvP 2", realm
-- id 4613). The realm id follows the real economy best, the faction picks the faction
-- auction house. The realm name is the fallback when no id is given. The neutral
-- auction house is not told apart from the faction one yet.
function Controller.marketKey()
    local id = type(GetRealmID) == "function" and GetRealmID() or nil
    local realm = Util.id(id) and tostring(id) or nil
    if not realm then
        local name = type(GetNormalizedRealmName) == "function" and GetNormalizedRealmName() or nil
        if type(name) ~= "string" or name == "" then
            name = type(GetRealmName) == "function" and GetRealmName() or nil
        end
        realm = type(name) == "string" and name ~= "" and name or "unknown"
    end
    local faction = type(UnitFactionGroup) == "function" and UnitFactionGroup("player") or nil
    local key = realm .. "-" .. (type(faction) == "string" and faction ~= "" and faction or "Neutral")
    -- A hardcore character never shares a market with a normal one, whatever its realm.
    local rules = C_GameRules
    if type(rules) == "table" and type(rules.IsHardcoreActive) == "function" then
        local ok, hardcore = pcall(rules.IsHardcoreActive)
        if ok and hardcore == true then key = key .. "-HC" end
    end
    return key
end

function Controller.market()
    if pass then
        pass.market = pass.market or DB.market(CraftProfitDB, Controller.marketKey())
        return pass.market
    end
    return DB.market(CraftProfitDB, Controller.marketKey())
end

-- Runs fn(...) inside a refresh pass, or inside the one already running (a list refreshed
-- by Controller.refresh shares its pass). Returns fn's first result.
function Controller.inPass(fn, ...)
    if pass then return fn(...) end
    pass = { info = {}, results = {} }
    local ok, value = pcall(fn, ...)
    pass = nil
    if not ok then error(value, 0) end
    return value
end

local isSecret = Util.isSecret

-- A game value, or nil when it is secret.
local function plain(v)
    if isSecret(v) then return nil end
    return v
end

-- Item facts, or nil while the game has not loaded the item yet. The request is
-- made once per item; ITEM_DATA_LOAD_RESULT triggers the refresh.
local function readItemInfo(itemID)
    local ok, _, _, quality, ilvl, _, _, _, _, _, _, sellPrice, classID, _, bindType = pcall(C_Item.GetItemInfo, itemID)
    if not ok then return nil end
    -- A secret field is dropped (nil): each one is compared or multiplied later. A secret
    -- quality reads as "not loaded".
    quality, ilvl, sellPrice = plain(quality), plain(ilvl), plain(sellPrice)
    classID, bindType = plain(classID), plain(bindType)
    if quality == nil then
        if not requestedItems[itemID] then
            requestedItems[itemID] = true
            C_Item.RequestLoadItemDataByID(itemID)
        end
        return nil
    end
    return { quality = quality, ilvl = ilvl, sellPrice = sellPrice, classID = classID, bindType = bindType }
end

-- readItemInfo, read once per refresh pass (callers must not modify the table).
function Controller.itemInfo(itemID)
    if not pass or not Util.id(itemID) then return readItemInfo(itemID) end
    local known = pass.info[itemID]
    if known == nil then
        known = readItemInfo(itemID) or false
        pass.info[itemID] = known
    end
    return known or nil
end

-- Item icon (file id or path) read secret-safely, or nil while the game has not loaded it.
function Controller.itemIcon(itemID)
    local api = C_Item
    local ok, icon
    if type(api.GetItemIconByID) == "function" then ok, icon = pcall(api.GetItemIconByID, itemID) end
    if not ok or isSecret(icon) or (type(icon) ~= "number" and type(icon) ~= "string") or icon == "" then
        local found, _, _, _, _, _, _, _, _, _, texture = pcall(api.GetItemInfo, itemID)
        icon = found and not isSecret(texture) and texture or nil
    end
    if (type(icon) ~= "number" and type(icon) ~= "string") or icon == "" then return nil end
    return icon
end

-- Item name read secret-safely (Util.text: a secret value raises when concatenated), or
-- nil while the game has not loaded the item.
function Controller.itemName(itemID)
    local ok, name = pcall(C_Item.GetItemInfo, itemID)
    local text = ok and Util.text(name, isSecret) or nil
    if text then return text end
    Controller.itemInfo(itemID) -- not loaded yet: ask the game, the refresh follows
    return nil
end

-- The name shown for a stored recipe (pin, known recipe, tracked recipe), in the game's
-- current language: names are stored when pinned or read and would stay in the old
-- language after a language switch. Recipes.liveName picks the client's recipe name, else
-- the crafted item's (loaded on demand: ITEM_DATA_LOAD_RESULT refreshes), else the stored
-- one, and writes a newer name back into the stored recipe. Identity stays the recipe id.
function Controller.recipeName(recipe)
    if type(recipe) ~= "table" then return "" end
    return Recipes.liveName(recipe, {
        locale = ns.Trade.locale(),
        recipeName = ns.Trade.recipeName,
        itemName = Controller.itemName,
    })
end

-- The name shown for a stored profession (a CraftProfitCharDB.known entry) in the game's
-- current language, else the stored one; a newer name is written back.
function Controller.professionName(prof)
    if type(prof) ~= "table" then return "-" end
    local live = ns.Trade.professionName(prof.key)
    if live and #live <= DB.MAX_PROFESSION_NAME then
        if live ~= prof.name then prof.name = live end
        return live
    end
    if type(prof.name) == "string" and prof.name ~= "" then return prof.name end
    return tostring(prof.key or "-")
end

-- Looked up once per refresh pass.
function Controller.knowsEnchanting()
    if pass and pass.knowsEnchanting ~= nil then return pass.knowsEnchanting end
    local known = ns.Trade.hasProfession(ns.Trade.ENCHANTING_SKILL_LINE)
    if pass then pass.knowsEnchanting = known end
    return known
end

-- crafts is only given for the recipe shown in the window; the pinned list is always
-- one craft. Within a refresh pass a recipe (the same table: a pin is evaluated for the list
-- under the main window and for the pinned window) is evaluated once per crafts and per-point
-- choice; callers must not modify the result.
function Controller.evaluate(recipe, crafts, forcePerPoint)
    local settings = CraftProfitDB.settings
    local showPerPoint = settings.showPerPoint or forcePerPoint == true
    local key, memo
    if pass then
        key = Evaluate.craftCount(crafts) .. (showPerPoint and ":point" or "")
        memo = pass.results[recipe]
        if memo and memo[key] then return memo[key] end
        pass.priceOf = pass.priceOf or Prices.priceOf(Controller.market(), time())
    end
    local result = Evaluate.run({
        recipe = recipe,
        crafts = crafts,
        priceOf = pass and pass.priceOf or Prices.priceOf(Controller.market(), time()),
        itemInfo = Controller.itemInfo,
        cut = settings.cut,
        showPerPoint = showPerPoint,
        lookupDisenchant = Disenchant.lookup,
        knowsEnchanting = Controller.knowsEnchanting(),
    })
    if pass then
        if not memo then
            memo = {}
            pass.results[recipe] = memo
        end
        memo[key] = result
    end
    return result
end

-- Shared with the other controller files (Boot.lua takes them into locals).
Controller._coinString = coinString
Controller._requestedItems = requestedItems
