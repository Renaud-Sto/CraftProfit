local H = ...
local W = dofile("tests/fakewow.lua")

-- classID 0: disenchanting never applies, so the figures do not depend on the disenchant table.
local ITEMS = {
    [100] = { quality = 2, ilvl = 15, sellPrice = 200, classID = 0, bindType = 2 },
    [101] = { quality = 2, ilvl = 15, sellPrice = 1, classID = 0, bindType = 2 },
}

-- A learned recipe as the profession scan stores it: two of item 1 and one of item 2 make
-- `output` (100 sells well, 101 badly).
local function raw(id, output)
    return {
        recipeID = id, name = "R" .. id, locale = "enUS", difficulty = 1, outputItemID = output or 100,
        qtyMin = 1, qtyMax = 1, reagents = { { itemID = 1, qty = 2 }, { itemID = 2, qty = 1 } },
    }
end

-- Boots with Blacksmithing (164) open; `known` recipes stored for it.
local function boot(known, settings)
    local T = W.boot(H, { items = ITEMS })
    T.env.CraftProfitDB = settings and { settings = settings } or nil
    T.env.ProfessionsFrame = { IsShown = function() return true end }
    T.env.C_TradeSkillUI = {
        GetBaseProfessionInfo = function() return { professionID = 164, professionName = "Forge" } end,
    }
    T.ns.Controller.onEvent("ADDON_LOADED", "CraftProfit")
    if known then T.ns.DB.setKnown(T.env.CraftProfitCharDB, "164", "Forge", known, 1700000000) end
    return T
end

local function stock(T)
    local P, db = T.ns.Prices, T.ns.Controller.market()
    P.store(db, 1, 100, 10, 1699999940)
    P.store(db, 2, 50, 10, 1699999880)
    P.store(db, 100, 1000, 10, 1699999970)
end

-- Controller ------------------------------------------------------------------------------

H.test("rowTag: the net of one craft of a known recipe, as the pinned list counts it, in its colour", function()
    local T = boot({ raw(5), raw(6, 101) })
    stock(T)
    local C, Colors, F = T.ns.Controller, T.ns.Colors, T.ns.Format
    local recipe = T.env.CraftProfitCharDB.known[1].recipes[1]
    local net = C.evaluate(recipe, 1).net
    H.truthy(net > 0)
    H.eq({ C.rowTag(5) }, { "+" .. F.short(net), Colors.FIXED.profit })
    -- Its output sells for 1 copper anywhere: a loss.
    T.ns.Prices.store(C.market(), 101, 1, 10, 1699999970)
    local text, color = C.rowTag(6)
    H.eq(text:sub(1, 1), "-")
    H.eq(color, Colors.FIXED.loss)
end)

H.test("rowTag: nothing for a recipe not stored, another profession's, or one without prices", function()
    local T = boot({ raw(5) })
    local C = T.ns.Controller
    -- No price at all.
    H.eq({ C.rowTag(5) }, {})
    stock(T)
    H.truthy(C.rowTag(5))
    H.eq({ C.rowTag(7) }, {})
    H.eq({ C.rowTag(nil) }, {})
    H.eq({ C.rowTag("5") }, {})
    -- Another profession open: its stored list (none here) is the one read.
    T.env.C_TradeSkillUI.GetBaseProfessionInfo = function() return { professionID = 197, professionName = "Couture" } end
    H.eq({ C.rowTag(5) }, {})
    -- The client cannot say which profession is open.
    T.env.C_TradeSkillUI.GetBaseProfessionInfo = function() error("boom") end
    H.eq({ C.rowTag(5) }, {})
end)

H.test("rowTag follows a new scan of the profession", function()
    local T = boot({ raw(5) })
    stock(T)
    local C = T.ns.Controller
    H.eq({ C.rowTag(6) }, {})
    T.ns.DB.setKnown(T.env.CraftProfitCharDB, "164", "Forge", { raw(6) }, 1700000000)
    H.truthy(C.rowTag(6))
    H.eq({ C.rowTag(5) }, {})
end)

H.test("rowTag: a missing resale price keeps the known figure in the incomplete colour", function()
    local T = boot({ raw(5) })
    local C, Colors = T.ns.Controller, T.ns.Colors
    -- Reagents priced, the output not: the vendor price is known, the AH one is missing.
    local P, db = T.ns.Prices, C.market()
    P.store(db, 1, 100, 10, 1699999940)
    P.store(db, 2, 50, 10, 1699999880)
    local result = C.evaluate(T.env.CraftProfitCharDB.known[1].recipes[1], 1)
    H.truthy(result.net ~= nil and result.incomplete)
    H.eq({ C.rowTag(5) }, { T.ns.Format.short(result.net), Colors.FIXED.incomplete })
    H.eq(T.ns.Format.short(result.net):sub(1, 1), "-")
end)

H.test("showRowTags defaults to on, setShowRowTags saves a boolean and repaints the rows", function()
    local T = boot()
    local C = T.ns.Controller
    H.eq(C.showRowTags(), true)
    local repaints = 0
    T.ns.RecipeRows = { refresh = function() repaints = repaints + 1 end }
    C.setShowRowTags(false)
    H.eq(T.env.CraftProfitDB.settings.showRowTags, false)
    H.eq(C.showRowTags(), false)
    H.eq(repaints, 1)
    C.setShowRowTags("yes")
    H.eq(T.env.CraftProfitDB.settings.showRowTags, true)
    H.eq(repaints, 2)
    -- A saved "off" survives the next login.
    local T2 = boot(nil, { showRowTags = false })
    H.eq(T2.ns.Controller.showRowTags(), false)
end)

-- The profession window's list -------------------------------------------------------------

-- A font string that records what the module sets on it.
local function fontString()
    local fs = W.frame()
    fs.SetTextColor = function(self, r, g, b, a) self.color = { r, g, b, a } end
    fs.SetPoint = function(self, ...) self.point = { ... } end
    fs.ClearAllPoints = function(self) self.point = nil end
    fs.SetWidth = function(self, w) self.width = w end
    fs.SetJustifyH = function(self, v) self.justify = v end
    fs.SetWordWrap = function(self, v) self.wrap = v end
    return fs
end

-- A recycled row of the list: counts the font strings made on it.
local function row()
    local r = W.frame()
    r.made = 0
    r.CreateFontString = function(self, _, layer, font)
        self.made = self.made + 1
        local fs = fontString()
        fs.layer, fs.font = layer, font
        return fs
    end
    return r
end

-- A tree node as the list hands it out: its data holds the recipe info (or a category).
local function node(recipeID)
    return { GetData = function() return { recipeInfo = { recipeID = recipeID } } end }
end

-- The profession window with a recipe list: `entries` = { { frame, elementData } } on screen.
local function list(T, entries)
    local box = { registered = {}, entries = entries }
    function box:RegisterCallback(event, fn, owner)
        self.registered[#self.registered + 1] = { event = event, fn = fn, owner = owner }
    end
    function box:ForEachFrame(fn)
        for _, e in ipairs(self.entries) do fn(e[1], e[2]) end
    end
    -- Blizzard's list initialising a row (scroll, filter, tab switch).
    function box:init(frame, elementData)
        for _, cb in ipairs(self.registered) do
            if cb.event == "OnInitializedFrame" then cb.fn(cb.owner, frame, elementData) end
        end
    end
    T.env.ScrollBoxListMixin = { Event = { OnInitializedFrame = "OnInitializedFrame" } }
    T.env.ProfessionsFrame = {
        shown = true,
        IsShown = function(self) return self.shown end,
        CraftingPage = { RecipeList = { ScrollBox = box } },
    }
    return box
end

local function tagOf(T, frame) return T.ns.RecipeRows.tags[frame] end

H.test("attach registers on the list's own callback once and tags the known rows with their net", function()
    local T = boot({ raw(5) })
    stock(T)
    local known, unknown, header = row(), row(), row()
    local box = list(T, {
        { known, node(5) }, { unknown, node(7) }, { header, { GetData = function() return { categoryInfo = {} } end } },
    })
    local R, C, Colors = T.ns.RecipeRows, T.ns.Controller, T.ns.Colors
    R.attach()
    R.attach()
    C.onEvent("TRADE_SKILL_SHOW")
    C.refresh()
    H.eq(#box.registered, 1)
    H.eq(box.registered[1].event, "OnInitializedFrame")
    local tag = tagOf(T, known)
    local text = C.inPass(C.rowTag, 5)
    H.eq(tag.text, text)
    H.eq(text:sub(1, 1), "+")
    H.eq(tag.color, Colors.FIXED.profit)
    H.truthy(tag.shown)
    -- The game's small font, right-justified in a fixed width, one line.
    H.eq(tag.font, "GameFontHighlightSmall")
    H.eq(tag.layer, "OVERLAY")
    H.eq(tag.width, R.TAG_W)
    H.eq(tag.justify, "RIGHT")
    H.eq(tag.wrap, false)
    H.eq(tag.point, { "RIGHT", known, "RIGHT", -4, 0 })
    -- One font string per row, whatever the repaints.
    H.eq(known.made, 1)
    -- Nothing drawn on an unknown recipe or a category.
    H.eq(unknown.made, 0)
    H.eq(header.made, 0)
    H.eq(T.chat, {})
end)

H.test("a row initialised by the list is tagged; a recycled row loses a tag it no longer has", function()
    local T = boot({ raw(5) })
    stock(T)
    local box = list(T, {})
    T.ns.RecipeRows.attach()
    local r = row()
    box:init(r, node(5))
    H.truthy(tagOf(T, r).shown)
    H.eq(tagOf(T, r).text:sub(1, 1), "+")
    box:init(r, node(7))
    H.falsy(tagOf(T, r).shown)
    box:init(r, { GetData = function() return { categoryInfo = {} } end })
    H.falsy(tagOf(T, r).shown)
    box:init(r, node(5))
    H.truthy(tagOf(T, r).shown)
    H.eq(r.made, 1)
end)

H.test("the tag sits left of Blizzard's lock icon when it is shown, never moving it", function()
    local T = boot({ raw(5) })
    stock(T)
    local r = row()
    local icon = W.frame()
    icon.shown = true
    icon.SetPoint = function() error("moved a Blizzard region") end
    r.LockedIcon = icon
    local box = list(T, { { r, node(5) } })
    T.ns.RecipeRows.attach()
    H.eq(tagOf(T, r).point, { "RIGHT", icon, "LEFT", -2, 0 })
    icon.shown = false
    box:init(r, node(5))
    H.eq(tagOf(T, r).point, { "RIGHT", r, "RIGHT", -4, 0 })
end)

H.test("prices changed: the refresh repaints the rows on screen in one pass", function()
    local T = boot({ raw(5) })
    local r = row()
    list(T, { { r, node(5) } })
    local C = T.ns.Controller
    T.ns.RecipeRows.attach()
    -- No price yet: no tag.
    H.eq(r.made, 0)
    stock(T)
    local passes = 0
    local inPass = C.inPass
    C.inPass = function(...) passes = passes + 1; return inPass(...) end
    C.refresh()
    H.truthy(tagOf(T, r).shown)
    H.eq(tagOf(T, r).text:sub(1, 1), "+")
    -- The refresh's own pass; the rows share it.
    local before = passes
    T.ns.RecipeRows.refresh()
    H.eq(passes, before + 1)
end)

H.test("a finished scan of the profession repaints the rows", function()
    local T = boot()
    stock(T)
    local r = row()
    list(T, { { r, node(5) } })
    T.ns.RecipeRows.attach()
    H.eq(r.made, 0)
    T.env.Enum = { CraftingReagentType = { Basic = 1 } }
    T.env.C_TradeSkillUI.GetAllRecipeIDs = function() return { 5 } end
    T.env.C_TradeSkillUI.GetRecipeInfo = function(id)
        return { recipeID = id, name = "R" .. id, learned = true, relativeDifficulty = 1 }
    end
    T.env.C_TradeSkillUI.GetRecipeSchematic = function()
        return { outputItemID = 100, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = {
            { reagentType = 1, quantityRequired = 2, reagents = { { itemID = 1 } } },
            { reagentType = 1, quantityRequired = 1, reagents = { { itemID = 2 } } },
        } }
    end
    T.ns.Controller.onEvent("TRADE_SKILL_LIST_UPDATE")
    T.run()
    H.truthy(tagOf(T, r) and tagOf(T, r).shown)
end)

H.test("the option off hides every tag at once and evaluates nothing; on paints them again", function()
    local T = boot({ raw(5) })
    stock(T)
    local r = row()
    local box = list(T, { { r, node(5) } })
    local C = T.ns.Controller
    T.ns.RecipeRows.attach()
    H.truthy(tagOf(T, r).shown)
    C.setShowRowTags(false)
    H.falsy(tagOf(T, r).shown)
    local asked = 0
    local rowTag = C.rowTag
    C.rowTag = function(...) asked = asked + 1; return rowTag(...) end
    box:init(r, node(5))
    C.refresh()
    H.falsy(tagOf(T, r).shown)
    H.eq(asked, 0)
    C.setShowRowTags(true)
    H.truthy(tagOf(T, r).shown)
    H.eq(asked, 1)
end)

H.test("nothing is evaluated while the profession window is hidden", function()
    local T = boot({ raw(5) })
    stock(T)
    local r = row()
    local box = list(T, { { r, node(5) } })
    local C = T.ns.Controller
    T.ns.RecipeRows.attach()
    T.env.ProfessionsFrame.shown = false
    local asked = 0
    local rowTag = C.rowTag
    C.rowTag = function(...) asked = asked + 1; return rowTag(...) end
    box:init(r, node(5))
    C.refresh()
    T.ns.RecipeRows.refresh()
    H.eq(asked, 0)
end)

H.test("a row without its data in the call reads the row's own element data", function()
    local T = boot({ raw(5) })
    stock(T)
    local r = row()
    r.GetElementData = function() return node(5) end
    list(T, { { r, nil } })
    T.ns.RecipeRows.attach()
    H.truthy(tagOf(T, r).shown)
    -- A node that is the data itself, or keeps it in .data.
    local box = T.env.ProfessionsFrame.CraftingPage.RecipeList.ScrollBox
    local r2, r3 = row(), row()
    box:init(r2, { recipeInfo = { recipeID = 5 } })
    box:init(r3, { data = { recipeInfo = { recipeID = 5 } } })
    H.truthy(tagOf(T, r2).shown)
    H.truthy(tagOf(T, r3).shown)
end)

H.test("every missing or different piece makes it do nothing, silently", function()
    local T = boot({ raw(5) })
    stock(T)
    local R, C = T.ns.RecipeRows, T.ns.Controller
    local function quiet(setup)
        setup()
        R.attach()
        R.refresh()
        C.refresh()
        C.onEvent("TRADE_SKILL_SHOW")
    end
    quiet(function() T.env.ProfessionsFrame = nil end)
    quiet(function() T.env.ProfessionsFrame = { IsShown = function() return true end } end)
    quiet(function() T.env.ProfessionsFrame = { IsShown = function() return true end, CraftingPage = {} } end)
    quiet(function()
        T.env.ProfessionsFrame = { IsShown = function() return true end, CraftingPage = { RecipeList = {} } }
    end)
    -- (Only this module's entry points: the profession adapter itself expects IsShown to answer.)
    T.env.ProfessionsFrame = { IsShown = function() error("boom") end, CraftingPage = { RecipeList = { ScrollBox = {} } } }
    R.attach()
    R.refresh()
    -- No event name: nothing registered, the rows on screen are still painted by a refresh.
    local box = list(T, { { row(), node(5) } })
    T.env.ScrollBoxListMixin = nil
    quiet(function() end)
    H.eq(#box.registered, 0)
    T.env.ScrollBoxListMixin = { Event = {} }
    quiet(function() end)
    H.eq(#box.registered, 0)
    -- The list raises: when registering, when walking its rows.
    T.env.ScrollBoxListMixin = { Event = { OnInitializedFrame = "OnInitializedFrame" } }
    box.RegisterCallback = function() error("boom") end
    box.ForEachFrame = function() error("boom") end
    quiet(function() end)
    -- Rows of another shape.
    box = list(T, {})
    R.attach()
    local bad = row()
    bad.CreateFontString = nil
    box:init(bad, node(5))
    box:init(row(), { GetData = function() error("boom") end })
    box:init(row(), { GetData = function() return "x" end })
    box:init(row(), { GetData = function() return { recipeInfo = "x" } end })
    box:init(row(), { GetData = function() return { recipeInfo = { recipeID = 0 / 0 } } end })
    box:init(row(), nil)
    box:init(nil, node(5))
    box:init("x", node(5))
    local throwing = row()
    throwing.CreateFontString = function() error("boom") end
    box:init(throwing, node(5))
    -- A secret recipe id is never indexed.
    T.env.issecretvalue = function(v) return v == "SECRET" end
    local secret = row()
    box:init(secret, node("SECRET"))
    H.eq(secret.made, 0)
    -- The controller failing on a row.
    C.rowTag = function() error("boom") end
    box:init(row(), node(5))
    R.refresh()
    H.eq(T.chat, {})
end)
