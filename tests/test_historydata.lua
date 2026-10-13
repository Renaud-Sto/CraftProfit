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
    if C.historyChanged then C.historyChanged() end
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
    -- The Profit view's typical week is in money.
    H.truthy(data.weekday[6].gap > 0 and data.weekday[7].gap > 0)
    H.truthy(data.weekday[1].gap <= 0)
    H.eq(data.measures, data.summary.measures)
    H.eq(data.days, 28)
    -- The icon row: each item with its group (the recipe views are the window's tabs).
    H.eq(data.items[1].key, "item:1")
    H.eq(data.items[1].itemID, 1)
    H.eq(data.items[1].group, "materials")
    H.eq(data.items[2].group, "materials")
    H.eq(data.items[3].key, "item:100")
    H.eq(data.items[3].name, "Item100")
    H.eq(data.items[3].group, "crafted")
    H.eq(#data.items, 3)
    -- The commission as a percentage, for the caption.
    H.eq(data.commission, 5)
    H.eq(data.goal, "craft")
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

H.test("historyData names the items with fewer than 3 days of data, in icon order", function()
    local T, C = boot()
    track(T, raw(5))
    -- Item 1: 2 days, item 2: 10 days, the crafted item 100: never measured.
    fill(C, 10, function(id, age)
        if id == 1 and age >= 2 then return nil end
        if id == 100 then return nil end
        return flat(id)
    end)
    local data = C.historyData(5, "net", 30)
    H.eq(data.status, "nodata")
    H.eq(data.thin, {
        { itemID = 1, name = "Item1", measures = 2, days = 2 },
        { itemID = 100, name = "Item100", measures = 0, days = 0 },
    })
    -- An item view reads the same list.
    H.eq(C.historyData(5, "item:1", 30).thin, data.thin)
    -- Enough data everywhere: nothing is thin.
    fill(C, 5, flat)
    H.eq(C.historyData(5, "net", 30).thin, {})
end)

H.test("historyData's thin list keeps 3 items, skips an unsold crafted item, falls back to #id", function()
    local T, C = boot()
    local recipe = raw(7, 200)                         -- 200 is bound: not sold
    recipe.reagents = { { itemID = 1, qty = 1 }, { itemID = 2, qty = 1 }, { itemID = 3, qty = 1 },
        { itemID = 4, qty = 1 } }
    track(T, recipe)
    local data = C.historyData(7, "net", 30)
    H.eq(#data.thin, 3)
    H.eq(data.thin[1].itemID, 1)
    H.eq(data.thin[2].itemID, 2)
    H.eq(data.thin[3], { itemID = 3, name = "#3", measures = 0, days = 0 })
    for _, item in ipairs(data.thin) do H.truthy(item.itemID ~= 200) end
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
    H.eq(#data.items, 2)                                -- items 1 and 2: no crafted group
    for _, item in ipairs(data.items) do H.eq(item.group, "materials") end
    H.eq(data.compare, nil)
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
    H.truthy(there.series[555])                        -- never in the deleted recipe: kept
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

-- Weapons that disenchant into 10938 / 10940 (quality 2, item level 15), bound on pickup:
-- a character without Enchanting cannot disenchant them, so the recording list leaves the
-- disenchant materials out. Deleting another recipe must still keep their series.
local DUST = { 10938, 10940 }

local function weaponRecipe(id, output, reagent)
    return { recipeID = id, name = "W" .. id, locale = "enUS", difficulty = 1, outputItemID = output,
        qtyMin = 1, qtyMax = 1, reagents = { { itemID = reagent, qty = 1 } } }
end

H.test("deleting a history keeps the disenchant materials another recipe may need (non-enchanter)", function()
    local T, C = boot()
    ITEMS[301] = { quality = 2, ilvl = 15, sellPrice = 1, classID = 2, bindType = 1 }
    ITEMS[302] = { quality = 2, ilvl = 15, sellPrice = 1, classID = 2, bindType = 1 }
    C.knowsEnchanting = function() return false end
    track(T, weaponRecipe(11, 301, 1))
    track(T, weaponRecipe(12, 302, 2), false)          -- paused: still protects its items
    local here = C.market()
    local there = T.ns.DB.market(T.env.CraftProfitDB, "9999-Alliance")
    for _, m in ipairs({ here, there }) do seed(m, { 1, 2, 301, 302, DUST[1], DUST[2] }) end
    H.eq(C.deleteHistory(11), true)
    for _, m in ipairs({ here, there }) do
        H.eq(m.series[1], nil)                         -- recipe 11's own reagent
        H.eq(m.series[301], nil)                       -- and its crafted item
        H.truthy(m.series[DUST[1]])                    -- shared with recipe 12's weapon
        H.truthy(m.series[DUST[2]])
        H.truthy(m.series[2])
        H.truthy(m.series[302])
    end
    ITEMS[301], ITEMS[302] = nil, nil
end)

H.test("deleting a history before an item is cached never deletes what that recipe could need", function()
    local T, C = boot()
    ITEMS[301] = { quality = 2, ilvl = 15, sellPrice = 1, classID = 2, bindType = 2 }
    track(T, weaponRecipe(11, 301, 1))
    track(T, weaponRecipe(12, 399, 2))                 -- 399: not loaded by the client yet
    local here = C.market()
    seed(here, { 1, 2, 301, 399, DUST[1], DUST[2] })
    H.eq(C.deleteHistory(11), true)
    H.eq(here.series[1], nil)
    H.eq(here.series[301], nil)
    -- 399 may disenchant into the same materials: they stay until its info is known.
    H.truthy(here.series[DUST[1]])
    H.truthy(here.series[DUST[2]])
    H.truthy(here.series[399])
    ITEMS[301] = nil
end)

H.test("deleting a history before an item is cached keeps an own reagent that is a disenchant material", function()
    local T, C = boot()
    -- An enchanting recipe using Lesser Magic Essence (10938), and a weapon not loaded yet
    -- that may disenchant into it.
    local enchant = weaponRecipe(11, 100, DUST[1])
    track(T, enchant)
    track(T, weaponRecipe(12, 399, 2))
    local here = C.market()
    local there = T.ns.DB.market(T.env.CraftProfitDB, "9999-Alliance")
    for _, m in ipairs({ here, there }) do seed(m, { DUST[1], 100, 2, 399 }) end
    H.eq(C.deleteHistory(11), true)
    for _, m in ipairs({ here, there }) do
        H.truthy(m.series[DUST[1]])                    -- 399 may still need it
        H.eq(m.series[100], nil)                       -- never a disenchant material: deleted
        H.truthy(m.series[399])
    end
end)

H.test("deleting a history once every item is cached removes an own disenchant material nobody needs", function()
    local T, C = boot()
    track(T, weaponRecipe(11, 100, DUST[1]))
    track(T, raw(6))
    local here = C.market()
    seed(here, { DUST[1], 100, 1, 2 })
    H.eq(C.deleteHistory(11), true)
    H.eq(here.series[DUST[1]], nil)
    H.truthy(here.series[100])                         -- recipe 6's crafted item
end)

H.test("the conservative item list ignores Enchanting and reports an unknown item", function()
    local _, C = boot()
    ITEMS[301] = { quality = 2, ilvl = 15, sellPrice = 1, classID = 2, bindType = 1 }
    C.knowsEnchanting = function() return false end
    local ids, complete = C.historyItemsAll(weaponRecipe(11, 301, 1))
    H.eq(ids, { 1, 301, DUST[2], DUST[1] })            -- the disenchant table's order
    H.eq(complete, true)
    local _, unknown = C.historyItemsAll(weaponRecipe(12, 399, 2))
    H.eq(unknown, false)
    ITEMS[301] = nil
end)

H.test("historyData sorts the items into materials, crafted item and disenchant groups", function()
    local T, C = boot()
    -- A weapon (quality 2, item level 15) that sells, and disenchants into DUST.
    ITEMS[301] = { quality = 2, ilvl = 15, sellPrice = 1, classID = 2, bindType = 2 }
    ITEMS[302] = { quality = 2, ilvl = 15, sellPrice = 1, classID = 2, bindType = 1 }
    track(T, weaponRecipe(11, 301, 1))
    track(T, weaponRecipe(12, 302, 2))
    local groups = {}
    for _, item in ipairs(C.historyData(11, "net", 30).items) do groups[item.itemID] = item.group end
    H.eq(groups, { [1] = "materials", [301] = "crafted", [10938] = "disenchant", [10940] = "disenchant" })
    -- Bound on pickup: never sold, so no crafted group; its disenchant materials stay.
    groups = {}
    for _, item in ipairs(C.historyData(12, "net", 30).items) do groups[item.itemID] = item.group end
    H.eq(groups[302], nil)
    H.eq(groups[2], "materials")
    for id, group in pairs(groups) do
        if id ~= 2 then H.eq(group, "disenchant") end
    end
    ITEMS[301], ITEMS[302] = nil, nil
end)

H.test("historyData compares today with the usual price, good or bad by view", function()
    local T, C = boot()
    track(T, raw(5))
    -- Ten days at the same prices, then item 1 at 80 today: materials 250 -> 210 (-16 %),
    -- profit 700 -> 740 (+6 %), sale unchanged.
    fill(C, 10, function(id, age)
        if age == 0 and id == 1 then return 80 end
        return flat(id)
    end)
    local m = C.historyData(5, "materials", 30)
    H.eq(m.compare, { pct = -16, tone = "down", good = true })
    H.eq(m.goal, "buy")
    local n = C.historyData(5, "net", 30)
    H.eq(n.compare, { gap = 40, tone = "up", good = true })
    H.eq(n.goal, "craft")
    local s = C.historyData(5, "sale", 30)
    H.eq(s.compare, { pct = 0, tone = "flat" })
    H.eq(s.goal, "sell")
    -- One reagent: cheaper is good news (bought); the crafted item: higher is good (sold).
    local item = C.historyData(5, "item:1", 30)
    H.eq(item.compare, { pct = -20, tone = "down", good = true })
    H.eq(item.goal, "buy")
    H.eq(C.historyData(5, "item:100", 30).goal, "sell")
    -- The low, high and newest days of the period come with the summary.
    H.eq(m.summary.todayDay, T.ns.History.dayOf(NOW))
    H.eq(m.summary.lowDay, T.ns.History.dayOf(NOW))
    H.truthy(m.summary.highDay < m.summary.todayDay)
end)

H.test("historyData has no comparison under 3 days of data", function()
    local T, C = boot()
    track(T, raw(5))
    fill(C, 2, flat)
    for _, view in ipairs({ "net", "materials", "sale", "item:1" }) do
        H.eq(C.historyData(5, view, 30).compare, nil)
    end
    fill(C, 3, flat)
    H.eq(C.historyData(5, "net", 30).compare, { gap = 0, tone = "flat" })
end)

H.test("historyData reads the commission from the settings", function()
    local T, C = boot()
    track(T, raw(5))
    T.env.CraftProfitDB.settings.cut = 0.075
    H.eq(C.historyData(5, "net", 30).commission, 7.5)
end)

H.test("historyData gives the auction house profit whatever the view, and whether it is a loss", function()
    local T, C = boot()
    track(T, raw(5))
    -- Materials 250 every day; the crafted item sells for 100 (95 after the cut): a 155
    -- loss, but today at 240 (228): a 22 loss, 133 better than usual.
    fill(C, 10, function(id, age)
        if id == 100 then return age == 0 and 240 or 100 end
        return flat(id)
    end)
    local expected = { today = -22, todayDay = T.ns.History.dayOf(NOW), usual = -155, enough = true,
        compare = { gap = 133, tone = "up", good = true }, atLoss = true }
    for _, view in ipairs({ "net", "materials", "sale", "item:1", "item:100" }) do
        for _, period in ipairs({ 7, 30, 60 }) do
            H.eq(C.historyData(5, view, period).profit, expected)
        end
    end
    -- The Profit view compares in money, for a usual loss too (History.compare cannot).
    H.eq(C.historyData(5, "net", 30).compare, expected.compare)
    -- A profit is not a loss; exactly 0 is (nothing is earned).
    fill(C, 10, flat)
    local profit = C.historyData(5, "materials", 30).profit
    H.eq(profit.today, 700)
    H.eq(profit.atLoss, false)
    T.env.CraftProfitDB.settings.cut = 0
    fill(C, 10, function(id) return id == 100 and 250 or flat(id) end)
    H.eq(C.historyData(5, "sale", 30).profit.today, 0)
    H.eq(C.historyData(5, "sale", 30).profit.atLoss, true)
end)

H.test("historyData: no sale, no profit, and no loss claimed", function()
    local T, C = boot()
    track(T, raw(7, 200))
    fill(C, 10, flat, { 1, 2, 200 })
    local profit = C.historyData(7, "materials", 30).profit
    H.eq(profit.today, nil)
    H.eq(profit.compare, nil)
    H.eq(profit.atLoss, false)
end)

H.test("historyList says which recipes are crafted at a loss today", function()
    local T, C = boot()
    track(T, raw(5))
    track(T, raw(7, 200))
    fill(C, 10, function(id) return id == 100 and 100 or flat(id) end, { 1, 2, 100, 200 })
    local list = C.historyList()
    H.eq(list[1].atLoss, true)
    -- Unknown (no sale): nil.
    H.eq(list[2].atLoss, nil)
    fill(C, 10, flat)
    H.eq(C.historyList()[1].atLoss, false)
    -- Data older than 24 hours: no arrows, nothing said.
    fill(C, 10, function(id, age) if age < 2 then return nil end return flat(id) end)
    H.eq(C.historyList()[1].atLoss, nil)
end)

H.test("historyList claims no loss when the sale price is not fresh", function()
    local T, C = boot()
    track(T, raw(5))
    -- Reagents measured today; the crafted item last sold three days ago (at a loss then).
    fill(C, 10, function(id, age)
        if id == 100 then return age >= 3 and 100 or nil end
        return flat(id)
    end)
    local entry = C.historyList()[1]
    H.eq(entry.fresh, true)
    H.eq(entry.atLoss, nil)
    H.eq(entry.indicator.sale, nil)                    -- no sale arrow from an old sale
    H.eq(entry.indicator.materials.tone, "flat")
end)

H.test("historyList freshness reads the reagents and the crafted item, never a disenchant material", function()
    local T, C = boot()
    ITEMS[301] = { quality = 2, ilvl = 15, sellPrice = 1, classID = 2, bindType = 2 }
    track(T, weaponRecipe(11, 301, 1))
    fill(C, 10, function(_, age) return age >= 3 and 100 or nil end, { 1, 301 })
    fill(C, 10, function() return 5 end, DUST)            -- disenchant materials: today
    H.eq(C.historyList()[1].fresh, false)
    H.eq(C.historyData(11, "net", 30).fresh, false)
    fill(C, 10, function() return 100 end, { 1, 301 })
    H.eq(C.historyList()[1].fresh, true)
    ITEMS[301] = nil
end)

H.test("the typical week reads 30 days whatever the period", function()
    local T, C = boot()
    track(T, raw(5))
    fill(C, 28, function(id, age)
        local wd = T.ns.History.weekday(NOW - age * DAY)
        if id == 100 then return (wd == 6 or wd == 7) and 1200 or 1000 end
        return flat(id)
    end)
    for _, view in ipairs({ "sale", "item:100" }) do
        local week = C.historyData(5, view, 7).weekday
        H.eq(week, C.historyData(5, view, 30).weekday)
        H.truthy(week[6].pct > 0 and week[7].pct > 0)
        H.eq(week[1].n, 4)
    end
end)

H.test("the Profit view's typical week is in money, even when the usual result is a loss", function()
    local T, C = boot()
    track(T, raw(5))
    -- Materials 250; the crafted item sells for 100 (95): a 155 loss, 200 (190) at the weekend.
    fill(C, 28, function(id, age)
        local wd = T.ns.History.weekday(NOW - age * DAY)
        if id == 100 then return (wd == 6 or wd == 7) and 200 or 100 end
        return flat(id)
    end)
    local data = C.historyData(5, "net", 30)
    H.eq(data.summary.usual, -155)
    H.eq(data.weekday[6], { gap = 95, n = 4 })
    H.eq(data.weekday[1], { gap = 0, n = 4 })
    H.eq(data.weekdayEmpty, nil)
    -- Other views stay in percent.
    H.eq(C.historyData(5, "sale", 30).weekday[1].gap, nil)
    -- Too few days: the reason is the number of days.
    fill(C, 5, flat)
    H.eq(C.historyData(5, "net", 30).weekdayEmpty, "days")
end)

-- Counts the recipe day computations (the costly part of historyList and historyData).
local function countDays(T)
    local V = T.ns.HistoryView
    local original, counter = V.recipeDays, { n = 0 }
    V.recipeDays = function(...)
        counter.n = counter.n + 1
        return original(...)
    end
    return counter
end

H.test("historyList and historyData are cached while nothing changes", function()
    local T, C = boot()
    track(T, raw(5))
    track(T, raw(6))
    fill(C, 10, flat)
    local calls = countDays(T)
    local list = C.historyList()
    local after = calls.n
    H.truthy(after > 0)
    H.truthy(C.historyList() == list)
    H.eq(calls.n, after)
    local data = C.historyData(5, "net", 30)
    after = calls.n
    H.truthy(C.historyData(5, "net", 30) == data)
    H.eq(calls.n, after)
    -- Another view, period or recipe is its own entry.
    H.truthy(C.historyData(5, "net", 7) ~= data)
    H.truthy(calls.n > after)
    after = calls.n
    H.truthy(C.historyData(5, "net", 30) == data)
    H.eq(calls.n, after)
end)

H.test("a record, a pause, a delete, the commission, the day and freshness invalidate the cache", function()
    local T, C = boot()
    track(T, raw(5))
    track(T, raw(6))
    fill(C, 10, flat)
    -- A recomputed list is a new table.
    local function recomputes(fn)
        local before = C.historyList()
        fn()
        return C.historyList() ~= before
    end
    H.eq(recomputes(function() end), false)
    -- A new price recorded: the newest point is in the next list.
    H.truthy(recomputes(function()
        C.market().prices[1] = { 60, 1, NOW }
        C.recordHistory({ [1] = true })
    end))
    H.truthy(recomputes(function() C.setHistoryActive(6, false) end))
    H.truthy(recomputes(function() T.env.CraftProfitDB.settings.cut = 0.1 end))
    H.truthy(recomputes(function() C.deleteHistory(6) end))
    H.eq(#C.historyList(), 1)
    -- An hour later nothing changed; past midnight, or once the newest point is a day old,
    -- the list is computed again.
    local clock = T.env.time
    H.eq(recomputes(function() T.env.time = function() return NOW + 60 end end), false)
    H.truthy(recomputes(function() T.env.time = function() return NOW + DAY + 60 end end))
    H.eq(C.historyList()[1].fresh, false)
    T.env.time = clock
end)
