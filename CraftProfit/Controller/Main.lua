-- Controller: the recipe shown in the main window (the selection state), the refresh of every
-- view, window placement, the main window's buttons and clicks, the auction house opening and
-- closing, and the profession window's selection.
local _, ns = ...
local Util, DB, Evaluate, Present = ns.Util, ns.DB, ns.Evaluate, ns.Present
local Recipes, History = ns.Recipes, ns.History
local L = ns.L

local Controller = ns.Controller
local say = Controller.say

local state = { recipe = nil, source = nil, crafts = 1 }

-- A reagent was clicked in the window: search it at the AH, quantity preset.
function Controller.onReagentClick(itemID, qty)
    if not ns.AH.isOpen then
        say(L.SEARCH_NEED_AH)
        return
    end
    local name = Controller.itemName(itemID)
    if not name then
        say(L.ITEM_NOT_LOADED)
        return
    end
    local ok = ns.AH.browse(name, itemID, qty)
    if not ok then say(L.BROWSE_UNAVAILABLE) end
end

-- The AH tile or the title of the window was clicked: search the crafted item at the AH
-- (no quantity preset), to see how many are for sale next to the price shown.
function Controller.onOutputClick()
    local recipe = state.recipe
    if not recipe or not recipe.outputItemID then return end
    if not ns.AH.isOpen then
        say(L.SEARCH_NEED_AH)
        return
    end
    local itemID = recipe.outputItemID
    -- Same rule as Evaluate: an item bound when picked up cannot be auctioned.
    if Evaluate.isBindOnPickup(Controller.itemInfo(itemID)) then
        say(L.SEARCH_UNSELLABLE)
        return
    end
    local name = Controller.itemName(itemID)
    if not name then
        say(L.ITEM_NOT_LOADED)
        return
    end
    if not ns.AH.browse(name, itemID, nil) then say(L.BROWSE_UNAVAILABLE) end
end

-- The multiplier belongs to one recipe: selecting another one starts again at 1.
local function choose(recipe, source)
    if not (state.recipe and recipe and state.recipe.recipeID == recipe.recipeID) then state.crafts = 1 end
    state.recipe, state.source = recipe, source
end

function Controller.setCrafts(value)
    state.crafts = Evaluate.craftCount(value)
    Controller.refresh()
end

function Controller.currentRecipeID()
    return state.recipe and state.recipe.recipeID or nil
end

local function refreshAll()
    local settings = CraftProfitDB.settings
    local recipe = state.recipe
    if recipe then
        local model = Present.build(Controller.evaluate(recipe, state.crafts), L, Controller.fmt,
            { staleAfter = settings.staleAfter, itemName = Controller.itemName })
        model.title = Controller.recipeName(recipe)
        for _, reagent in ipairs(recipe.reagents or {}) do Controller.itemInfo(reagent.itemID) end
        model.pinned = DB.pinIndex(CraftProfitCharDB, recipe.recipeID) ~= nil
        model.tracked = History.isActive(CraftProfitDB, recipe.recipeID)
        model.history = model.tracked and Controller.windowHistory(recipe.recipeID) or nil
        model.showPerPoint = settings.showPerPoint
        model.costExpanded = settings.costExpanded
        ns.Window.render(model)
    else
        ns.Window.showEmpty(L.NO_RECIPE)
    end
    if ns.PinsUI then ns.PinsUI.refresh() end
    if ns.LevelingUI then ns.LevelingUI.refresh() end
    if ns.PinnedWindow then ns.PinnedWindow.refresh() end
    if ns.HistoryWindow then ns.HistoryWindow.refresh() end
    if ns.OptionsUI then ns.OptionsUI.refresh() end
end

-- Every view, in one refresh pass.
function Controller.refresh()
    Controller.inPass(refreshAll)
end

-- Coalesces bursts (many ITEM_DATA_LOAD_RESULT events, one per search result). While a
-- price search runs, each answered item asks for a refresh: they are coalesced over about
-- a second instead (the values still move, less often). A request at the usual pace does
-- not wait for a slower one already queued (the search just ended): it replaces it.
local REFRESH_DELAY, SEARCH_REFRESH_DELAY = 0.1, 1
local refreshQueued, refreshToken = nil, 0

function Controller.requestRefresh()
    local searching = ns.PinsUI and ns.PinsUI.state == "running"
    local delay = searching and SEARCH_REFRESH_DELAY or REFRESH_DELAY
    if refreshQueued and refreshQueued <= delay then return end
    refreshToken = refreshToken + 1
    local token = refreshToken
    refreshQueued = delay
    C_Timer.After(delay, function()
        if token ~= refreshToken then return end
        refreshQueued = nil
        Controller.refresh()
    end)
end

-- Default placement: a window without a saved position opens with its top left corner
-- 6 px right of the shown CraftProfit window that reaches furthest right (itself excluded),
-- so the windows never open on top of each other. Returns x, y (TOPLEFT against UIParent's
-- BOTTOMLEFT: absolute, so no window is ever anchored to another that depends on it), or
-- nil when no such window is shown and measured: the caller keeps its own default.
local BESIDE_GAP = 6

-- A number the frame answers through `method`, or nil (missing method, no answer).
local function ask(f, method)
    local fn = f[method]
    if type(fn) ~= "function" then return nil end
    local v = fn(f)
    return Util.isFinite(v) and v or nil
end

-- The right edge and top of `f` on screen; from the left edge and width (bottom and height)
-- when the client does not answer them directly. nil when it cannot be measured.
local function edges(f)
    local right, top = ask(f, "GetRight"), ask(f, "GetTop")
    if not right then
        local left, width = ask(f, "GetLeft"), ask(f, "GetWidth")
        right = left and width and left + width or nil
    end
    if not top then
        local bottom, height = ask(f, "GetBottom"), ask(f, "GetHeight")
        top = bottom and height and bottom + height or nil
    end
    return right, top
end

function Controller.besidePosition(except)
    local tops, entries = {}, {}
    for _, mod in ipairs({ ns.Window, ns.LevelingUI, ns.PinnedWindow, ns.HistoryWindow, ns.OptionsUI }) do
        local f = type(mod) == "table" and type(mod.frame) == "function" and mod.frame() or nil
        if f and f ~= except then
            local right, top = edges(f)
            -- A window whose top cannot be measured cannot be sat beside.
            entries[#entries + 1] = { shown = f:IsShown() == true and top ~= nil, right = right }
            tops[#entries] = top
        end
    end
    local index = ns.Layout.rightmost(entries)
    if not index then return nil end
    return entries[index].right + BESIDE_GAP, tops[index]
end

-- The main window's position: the saved one, else beside a shown CraftProfit window, else
-- nil (Window.attach then places it beside `target`).
local function mainPosition()
    local saved = CraftProfitDB.settings.window
    if saved then return saved end
    local x, y = Controller.besidePosition(ns.Window.frame())
    if x then return { point = "TOPLEFT", x = x, y = y } end
    return nil
end

function Controller.setRecipe(recipe, source)
    choose(recipe, source)
    local window = ns.Window
    if not window.isShown() then
        local target = ns.Trade.frame()
        if source == "pin" and ns.AH.isOpen then target = AuctionHouseFrame or AuctionFrame end
        window.attach(target, mainPosition())
        window.show()
    end
    Controller.refresh()
end

function Controller.selectPin(recipeID)
    local index = DB.pinIndex(CraftProfitCharDB, recipeID)
    if not index then return end
    choose(CraftProfitCharDB.pins[index], "pin")
    Controller.refresh()
end

-- The main window, as /cp show and /cp hide drive it.
function Controller.showMainWindow()
    local window = ns.Window
    if not window.isShown() then
        window.attach(ns.Trade.frame() or AuctionHouseFrame or AuctionFrame, mainPosition())
        window.show()
    end
    Controller.refresh()
end

function Controller.hideMainWindow()
    ns.Window.hide()
end

function Controller.toggleMainWindow()
    if ns.Window.isShown() then Controller.hideMainWindow() else Controller.showMainWindow() end
end

-- The "Track history" box: starts recording this recipe (or pauses it, keeping
-- what was recorded).
function Controller.setTracking(checked)
    local recipe = state.recipe
    if not recipe then return end
    Controller.historyChanged()
    if checked then
        local ok, reason = History.track(CraftProfitDB, recipe)
        if not ok and reason == "full" then say(string.format(L.TRACK_FULL, History.MAX_TRACKED)) end
    else
        History.pause(CraftProfitDB, recipe.recipeID)
    end
    Controller.refresh()
end

function Controller.togglePin()
    local recipe = state.recipe
    if not recipe then return end
    if DB.pinIndex(CraftProfitCharDB, recipe.recipeID) then
        DB.pinRemove(CraftProfitCharDB, recipe.recipeID)
    else
        -- Read at each attempt: a limit changed in the options window applies at once.
        local limit = Controller.pinLimit()
        local ok, reason = DB.pinAdd(CraftProfitCharDB, recipe, limit)
        if not ok and reason == "full" then say(string.format(L.PINS_LIMIT_REACHED, limit)) end
    end
    Controller.refresh()
end

-- "Refresh recipe": searches the AH for the items of the recipe on screen only (reagents,
-- output, disenchant materials when relevant), through the pinned list's search. Ignored
-- while a search runs; with the AH closed it says so in chat.
function Controller.refreshRecipe()
    local recipe = state.recipe
    if not recipe then return end
    if not ns.AH.isOpen then
        say(L.SEARCH_NEED_AH)
        return
    end
    if ns.PinsUI then ns.PinsUI.startSearch({ recipe }) end
end

function Controller.onAHOpen(open)
    if ns.PinsUI then ns.PinsUI.onAHOpen(open) end
    local window = ns.Window
    if open then
        if not state.recipe then
            local first = CraftProfitCharDB.pins[1]
            if first then choose(first, "pin") end
        end
        if not window.isShown() then
            window.attach(AuctionHouseFrame or AuctionFrame, mainPosition())
            window.show()
        end
        Controller.refresh()
    elseif state.source == "profession" then
        Controller.refresh()
    else
        choose(nil, nil)
        window.hide()
        -- The profession window may still be open: let the watcher report it again.
        ns.Trade.invalidate()
    end
    -- The hidden window keeps its last recipe: its button must still follow the AH.
    if window.updateRefreshButton then window.updateRefreshButton() end
end

-- The recipe id the profession window reported last; nil while it is closed.
local lastProfessionID

-- The profession window selection changed (or the window closed), or the watcher reports
-- the same one again (Trade.invalidate: the list updated after a craft, a skill-up or a
-- filter change). Only a new selection replaces the recipe shown and opens the main window:
-- the same one again refreshes its data (difficulty, quantities) without reopening a window
-- the player closed, and leaves a recipe picked from a list (source "pin") in place.
local function onSelection(recipeID)
    local previous = lastProfessionID
    lastProfessionID = recipeID
    if recipeID then
        if state.source == "pin" and recipeID == previous then return end
        local recipe = Recipes.normalize(ns.Trade.readSelected())
        if recipe then
            if state.source == "profession" and recipeID == Controller.currentRecipeID() then
                choose(recipe, "profession")
                Controller.refresh()
            else
                Controller.setRecipe(recipe, "profession")
            end
            return
        end
    end
    if state.source == "profession" then
        -- A pinned recipe stays selected as a pin, so it is still there at the AH.
        local recipe = state.recipe
        local index = recipe and DB.pinIndex(CraftProfitCharDB, recipe.recipeID)
        if index then
            choose(CraftProfitCharDB.pins[index], "pin")
        else
            choose(nil, nil)
        end
        if ns.AH.isOpen then
            -- The window was anchored to the profession window that just closed.
            local ahFrame = AuctionHouseFrame or AuctionFrame
            if ahFrame then ns.Window.attach(ahFrame, CraftProfitDB.settings.window) end
            Controller.refresh()
        else
            ns.Window.hide()
        end
    end
end

-- Shared with the other controller files (Boot.lua takes them into locals).
Controller._onSelection = onSelection
