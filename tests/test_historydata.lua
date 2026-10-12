local H = ...
local W = dofile("tests/fakewow.lua")
local stubClock = dofile("tests/stubclock.lua")

local DAY = 86400
local NOW = 1700000000 -- the fake game's time(): a Tuesday, 22:13 UTC

-- classID 0: never disenchanted. Item 200 is bound on pickup.
local ITEMS = {
    [1] = { quality = 1, ilvl = 10, sellPrice = 5, classID = 0, bindType = 0 },
    [2] = { quality = 1, ilvl = 10, sellPrice = 5, classID = 0, bindType = 0 },
    [100] = { quality = 2, ilvl = 15, sellPrice = 200, classID = 0, bindType = 2 },
    [200] = { quality = 2, ilvl = 15, sellPrice = 200, classID = 0, bindType = 1 },
}

local function raw(id, output)
    return { recipeID = id, name = "R" .. id, locale = "enUS", difficulty = 1, outputItemID = output or 100,
        qtyMin = 1, qtyMax = 1, reagents = { { itemID = 1, qty = 2 }, { itemID = 2, qty = 1 } } }
end

local function boot()
    local T = W.boot(H, { items = ITEMS })
    T.env.GetMoneyString = function(c) return "<" .. c .. ">" end
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    T.ns.History.setDateFn(stubClock(0))
    return T, T.ns.Controller
end

local function track(T, recipe, active)
    H.truthy(T.ns.History.track(T.env.CraftProfitDB, T.ns.Recipes.normalize(recipe)))
    if active == false then T.ns.History.pause(T.env.CraftProfitDB, recipe.recipeID) end
end

-- One complete point `age` days (and `extra` seconds) before NOW.
local function pt(age, unit, extra)
    return { NOW - age * DAY - (extra or 0), unit, 5, unit, unit, 1, true }
end

-- Prices of items 1, 2 and 100 over `days` days; `price(id, age)` gives each one.
local function fill(C, days, price, ids)
    local series = C.market().series
    for _, id in ipairs(ids or { 1, 2, 100 }) do
        series[id] = {}
        for age = days - 1, 0, -1 do
            local unit = price(id, age)
            if unit then series[id][#series[id] + 1] = pt(age, unit) end
        end
    end
end

local function flat(id) return ({ [1] = 100, [2] = 50, [100] = 1000, [200] = 1000 })[id] end

H.test("historyList: no tracked recipe gives an empty list", function()
    local _, C = boot()
    H.eq(C.historyList(), {})
end)

H.test("historyList keeps the saved order, the paused flag and the arrows of fresh data", function()
    local T, C = boot()
    track(T, raw(5))
    track(T, raw(6), false)
    fill(C, 10, function(id, age)
        if age == 0 and id == 1 then return 80 end       -- materials cheaper today
        return flat(id)
    end)
    local list = C.historyList()
    H.eq(#list, 2)
    H.eq(list[1].recipe.recipeID, 5)
    H.eq(list[1].active, true)
    H.eq(list[2].recipe.recipeID, 6)
    H.eq(list[2].active, false)
    H.eq(list[1].fresh, true)
    H.eq(list[1].indicator.materials.good, true)
    H.eq(list[1].indicator.materials.tone, "down")
    H.eq(list[1].indicator.sale.tone, "flat")
end)

H.test("historyList hides the arrows when the newest measurement is older than 24 hours", function()
    local T, C = boot()
    track(T, raw(5))
    fill(C, 10, function(id, age)
        if age < 2 then return nil end                  -- nothing in the last two days
        if age == 2 and id == 1 then return 80 end
        return flat(id)
    end)
    local entry = C.historyList()[1]
    H.eq(entry.fresh, false)
    H.eq(entry.indicator, nil)
    -- Not enough data: no arrows either, even when fresh.
    fill(C, 2, flat)
    entry = C.historyList()[1]
    H.eq(entry.fresh, true)
    H.eq(entry.indicator, nil)
end)

H.test("historyItemsOf lists the reagents, then the crafted item unless it is bound", function()
    local _, C = boot()
    H.eq(C.historyItemsOf(raw(5)), { 1, 2, 100 })
    H.eq(C.historyItemsOf(raw(7, 200)), { 1, 2 })
end)

H.test("historyData for the result: chart model, summary, weekday profile, items and market", function()
    local T, C = boot()
    track(T, raw(5))
    -- The crafted item sells higher at the weekend.
    fill(C, 28, function(id, age)
        if id ~= 100 then return flat(id) end
        local wd = T.ns.History.weekday(NOW - age * DAY)
        return (wd == 6 or wd == 7) and 1200 or 1000
    end)
    local data = C.historyData(5, "net", 30)
    H.eq(data.recipe.recipeID, 5)
    H.eq(data.view, "net")
    H.eq(data.period, 30)
    H.eq(data.status, "ok")
    H.eq(data.chart.field, "net")
    H.eq(data.chart.period, 30)
    H.eq(#data.chart.days, 28)
    H.eq(data.chart.usual, data.summary.usual)
    H.eq(data.chart.newest, T.ns.History.dayOf(NOW))
    H.truthy(data.summary.enough)
    H.eq(data.summary.daysCovered, 28)
    H.truthy(data.weekday[6].pct > 0 and data.weekday[7].pct > 0)
    H.truthy(data.weekday[1].pct <= 0)
    H.eq(data.measures, data.summary.measures)
    H.eq(data.days, 28)
    -- The icon row: the two recipe views, then each item.
    H.eq(data.items[1].key, "net")
    H.eq(data.items[2].key, "materials")
    H.eq(data.items[3].key, "item:1")
    H.eq(data.items[3].itemID, 1)
    H.eq(data.items[5].key, "item:100")
    H.eq(data.items[5].name, "Item100")
    H.eq(#data.items, 5)
    H.eq(type(data.market), "string")
    H.truthy(#data.market > 0)
end)

H.test("historyData for one item uses its daily series and its 30 day usual price", function()
    local T, C = boot()
    track(T, raw(5))
    fill(C, 20, function(id, age) return flat(id) + (age % 3) end)
    local data = C.historyData(5, "item:1", 7)
    local series = C.market().series[1]
    H.eq(data.view, "item:1")
    H.eq(data.chart.field, nil)
    H.eq(data.chart.days, T.ns.History.dailySeries(series, NOW, 7))
    H.eq(data.summary.usual, T.ns.History.usual(series, NOW).price)
    H.eq(data.chart.usual, data.summary.usual)
    H.eq(data.status, "ok")
end)

H.test("historyData defaults a bad view or period and refuses an unknown recipe", function()
    local T, C = boot()
    track(T, raw(5))
    fill(C, 5, flat)
    H.eq(C.historyData(99, "net", 30), nil)
    local data = C.historyData(5, "item:777", 45)
    H.eq(data.view, "net")
    H.eq(data.period, 30)
    H.eq(C.historyData(5, nil, nil).view, "net")
    H.eq(C.historyData(5, "sale", 60).view, "sale")
    H.eq(C.historyData(5, "sale", 60).period, 60)
end)

H.test("historyData says when there is not enough data, with the numbers", function()
    local T, C = boot()
    track(T, raw(5))
    local data = C.historyData(5, "net", 30)
    H.eq(data.status, "nodata")
    H.eq(data.measures, 0)
    H.eq(data.days, 0)
    for days, status in pairs({ [1] = "nodata", [2] = "nodata", [3] = "ok", [60] = "ok" }) do
        fill(C, days, flat)
        data = C.historyData(5, "net", 60)
        H.eq(data.status, status)
        H.eq(data.days, math.min(days, 30))
    end
    -- 60 days on the 60 day chart.
    H.eq(#data.chart.days, 60)
end)

H.test("a paused recipe says so, and a bound crafted item has no sale", function()
    local T, C = boot()
    track(T, raw(5), false)
    fill(C, 10, flat)
    H.eq(C.historyData(5, "net", 30).status, "paused")
    track(T, raw(7, 200))
    fill(C, 10, flat, { 1, 2, 200 })
    local data = C.historyData(7, "sale", 30)
    H.eq(data.status, "nodata")
    H.eq(#data.items, 4)                                -- net, materials, items 1 and 2
    H.eq(C.historyData(7, "materials", 30).status, "ok")
end)

H.test("openHistory shows the window and selects the recipe, and is safe without it", function()
    local T, C = boot()
    track(T, raw(5))
    local saved = T.ns.HistoryWindow
    T.ns.HistoryWindow = nil
    C.openHistory(5)
    local calls = {}
    T.ns.HistoryWindow = {
        show = function() calls[#calls + 1] = "show" end,
        select = function(id) calls[#calls + 1] = id end,
    }
    C.openHistory(5)
    H.eq(calls, { "show", 5 })
    T.ns.HistoryWindow = saved
end)

-- Series of `ids` in a market: one point each.
local function seed(market, ids)
    for _, id in ipairs(ids) do market.series[id] = { pt(1, 10) } end
end

H.test("pausing keeps the data, resuming records again, and both count as tracked", function()
    local T, C = boot()
    track(T, raw(5))
    fill(C, 5, flat)
    C.setHistoryActive(5, false)
    H.eq(T.ns.History.isActive(T.env.CraftProfitDB, 5), false)
    H.eq(#T.env.CraftProfitDB.tracked, 1)
    H.eq(#C.market().series[1], 5)
    C.setHistoryActive(5, true)
    H.eq(T.ns.History.isActive(T.env.CraftProfitDB, 5), true)
    C.setHistoryActive(99, false)                      -- not tracked: nothing happens
    H.eq(#T.env.CraftProfitDB.tracked, 1)
end)

H.test("deleting a history removes the recipe and its series in every market, sparing shared items", function()
    local T, C = boot()
    track(T, raw(5))                                   -- items 1, 2, 100
    local other = raw(6)
    other.reagents = { { itemID = 1, qty = 1 }, { itemID = 3, qty = 1 } }
    track(T, other)                                    -- items 1, 3, 100
    local here = C.market()
    local there = T.ns.DB.market(T.env.CraftProfitDB, "9999-Alliance")
    seed(here, { 1, 2, 3, 100 })
    seed(there, { 1, 2, 3, 100, 555 })
    here.prices[2] = { 50, 1, NOW }
    H.eq(C.deleteHistory(5), true)
    H.eq(#T.env.CraftProfitDB.tracked, 1)
    for _, market in ipairs({ here, there }) do
        H.eq(market.series[2], nil)                    -- only recipe 5 needed it
        H.truthy(market.series[1])                     -- shared with recipe 6
        H.truthy(market.series[3])
        H.truthy(market.series[100])
    end
    H.eq(there.series[555], nil)                       -- an orphan from before goes too
    H.eq(here.prices[2], { 50, 1, NOW })               -- current prices are never touched
    H.eq(T.chat[#T.chat], "|cff66ccffCraftProfit|r " .. string.format(T.ns.L.HISTORY_DELETED, "R5"))
    H.eq(C.deleteHistory(5), false)
end)

H.test("/cp history remove cleans every market too and keeps its message", function()
    local T, C = boot()
    track(T, raw(5))
    local there = T.ns.DB.market(T.env.CraftProfitDB, "9999-Alliance")
    seed(C.market(), { 1, 2, 100 })
    seed(there, { 1, 2, 100 })
    C.historyCommand("remove 1")
    H.eq(next(there.series), nil)
    H.eq(next(C.market().series), nil)
    H.eq(T.chat[#T.chat], "|cff66ccffCraftProfit|r " .. string.format(T.ns.L.HISTORY_REMOVED, "R5"))
end)
