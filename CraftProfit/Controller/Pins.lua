-- Controller: the pinned recipes (difficulties, unpin, the pinned window's data) and the prices
-- that auction house searches and scans store.
local _, ns = ...
local Util, Prices, DB, Present = ns.Util, ns.Prices, ns.DB, ns.Present
local History = ns.History
local L = ns.L

local Controller = ns.Controller

-- Pinned recipes keep the difficulty they had when pinned; the open profession
-- window knows the current one, which changes as the skill rises. Runs when the window
-- opens, switches profession and updates its list.
function Controller.refreshPinDifficulties()
    if not ns.Trade.isShown() or ns.Trade.isDataSourceChanging() then return false end
    local changed = false
    for _, pin in ipairs(CraftProfitCharDB.pins) do
        local current = ns.Trade.difficultyOf(pin.recipeID)
        if current and current ~= pin.difficulty then
            pin.difficulty = current
            changed = true
        end
    end
    if changed then Controller.requestRefresh() end
    return changed
end

-- The "x" of a row in the pinned window: removes that pin and refreshes every view; the
-- selection stays as it was.
function Controller.unpin(recipeID)
    DB.pinRemove(CraftProfitCharDB, recipeID)
    Controller.refresh()
end

-- What the pinned window shows: the pins in the pinned list's order with their
-- evaluation, the sort, and how old their prices are (it never searches). The age is the
-- main window's: the oldest price the evaluations used (result.oldestAge, whether it came
-- from a full scan or a "Refresh pinned" or "Refresh recipe"), here over every pin; none -> never priced, stale.
local function pinsData()
    local settings = CraftProfitDB.settings
    local sortMode = CraftProfitCharDB.sortMode
    local items = ns.PinsUI.orderedPins(CraftProfitCharDB.pins, sortMode, Controller.evaluate)
    local age
    for _, item in ipairs(items) do
        local itemAge = item.result.oldestAge
        if Util.isFinite(itemAge) and (age == nil or itemAge > age) then age = itemAge end
    end
    return {
        items = items,
        byPoint = sortMode == DB.SORT_POINT,
        ageText = Present.ageText(L, age),
        stale = age == nil or age > settings.staleAfter,
    }
end

function Controller.pinsData()
    return Controller.inPass(pinsData)
end

local searched = {}

-- Writes one history point per tracked recipe the update touched.
function Controller.recordHistory(updated)
    Controller.historyChanged()
    History.record(CraftProfitDB, Controller.market(), time(), updated, Controller.historyItems)
end

-- A price search is over (finished or cancelled): its results make one batch.
function Controller.commitSearch()
    local updated = searched
    searched = {}
    Controller.recordHistory(updated)
end

-- Stores the median price of an AH search result. False when nothing was listed.
function Controller.recordListings(itemID, listings)
    local unit, volume = Prices.summarize(listings, CraftProfitDB.settings.medianN)
    -- `full` (set by the AH adapter) says the listings hold every unit on offer.
    local full = type(listings) == "table" and listings.full == true
    if unit and Prices.store(Controller.market(), itemID, unit, volume, time(), full) then searched[itemID] = true end
    return unit ~= nil
end

function Controller.onSnapshot(agg)
    local prices = agg.result(CraftProfitDB.settings.medianN)
    local count = Prices.merge(Controller.market(), prices, time())
    Controller.recordHistory(prices)
    if ns.PinsUI then ns.PinsUI.setStatus(string.format(L.SCAN_DONE, count)) end
    Controller.requestRefresh()
end
