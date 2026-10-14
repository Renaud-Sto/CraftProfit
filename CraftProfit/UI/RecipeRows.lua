-- The profit tag at the right of each recipe row of the profession window's list: the net of
-- one craft ("+12s 23c" green, "-2s" red), for the learned recipes the addon has scanned.
--
-- Taint: the list is Blizzard's. Nothing of it is hooked or written to: the tags are our own
-- font strings, made on the recycled rows; a row initialised by the list (scroll, filter,
-- profession switch) reaches us through the ScrollBox's own callback registry
-- (OnInitializedFrame), and a refresh walks the rows on screen with ForEachFrame. Every piece
-- is looked up with type checks and every call is under pcall: a client where the list, its
-- ScrollBox, the event or the rows differ gets no tags, never an error or a chat line. The
-- Professions UI is created lazily: attach runs when the profession window is shown.
local _, ns = ...
local Util = ns.Util

local RecipeRows = {}
ns.RecipeRows = RecipeRows

-- Fixed width, right-justified: the tag never grows over the row (a long recipe name may
-- run under it; see docs/technical.md).
local TAG_W = 60
-- From the row's right edge, or from Blizzard's lock icon when it is shown there.
local EDGE_GAP = 4
local ICON_GAP = 2
RecipeRows.TAG_W = TAG_W

local ctl
-- The ScrollBox our callback is registered on: once per ScrollBox.
local registeredOn
-- Row -> its tag (weak keys: the rows are Blizzard's, nothing is stored on them). Exposed for
-- tests.
local tags = setmetatable({}, { __mode = "k" })
RecipeRows.tags = tags

local function field(t, key)
    if type(t) ~= "table" then return nil end
    return t[key]
end

-- The recipe list's ScrollBox, or nil while the Professions UI does not exist (or differs).
local function scrollBox()
    local box = field(field(field(ProfessionsFrame, "CraftingPage"), "RecipeList"), "ScrollBox")
    if type(box) ~= "table" then return nil end
    return box
end

local function professionShown()
    local f = ProfessionsFrame
    if type(f) ~= "table" or type(f.IsShown) ~= "function" then return false end
    local ok, shown = pcall(f.IsShown, f)
    return ok and shown == true
end

-- Tags are drawn: the option is on and the profession window is shown (no evaluation while
-- it is hidden).
local function active()
    return ctl ~= nil and ctl.showRowTags() and professionShown()
end

-- The recipe id of a row's element data (a tree node: its data holds recipeInfo; a category
-- holds none), or nil.
local function recipeIDOf(elementData)
    if type(elementData) ~= "table" then return nil end
    local data = elementData
    if type(elementData.GetData) == "function" then
        local ok, d = pcall(elementData.GetData, elementData)
        if not ok then return nil end
        data = d
    elseif type(elementData.data) == "table" then
        data = elementData.data
    end
    local info = field(data, "recipeInfo")
    if type(info) ~= "table" then return nil end
    local id = info.recipeID
    if Util.isSecret(id) then return nil end
    return Util.id(id)
end

-- The row's tag, made on first need: the game's small font, fixed width, one line.
local function tagOf(row)
    local tag = tags[row]
    if tag or type(row.CreateFontString) ~= "function" then return tag end
    local ok, fs = pcall(row.CreateFontString, row, nil, "OVERLAY", "GameFontHighlightSmall")
    if not ok or type(fs) ~= "table" then return nil end
    fs:SetWidth(TAG_W)
    fs:SetJustifyH("RIGHT")
    fs:SetWordWrap(false)
    tags[row] = fs
    return fs
end

-- At the row's right end, left of Blizzard's lock icon when it is shown there (its place is
-- read, never changed).
local function place(tag, row)
    tag:ClearAllPoints()
    local icon = row.LockedIcon
    if type(icon) == "table" and type(icon.IsShown) == "function" then
        local ok, shown = pcall(icon.IsShown, icon)
        if ok and shown == true then
            tag:SetPoint("RIGHT", icon, "LEFT", -ICON_GAP, 0)
            return
        end
    end
    tag:SetPoint("RIGHT", row, "RIGHT", -EDGE_GAP, 0)
end

-- Paints one row (inside a refresh pass); a row without a figure has no tag.
local function paint(row, elementData)
    if type(row) ~= "table" then return end
    if elementData == nil and type(row.GetElementData) == "function" then
        local ok, data = pcall(row.GetElementData, row)
        if ok then elementData = data end
    end
    local id = recipeIDOf(elementData)
    local text, color
    if id then text, color = ctl.rowTag(id) end
    local tag = text and tagOf(row) or tags[row]
    if not tag then return end
    if not text then
        tag:Hide()
        return
    end
    place(tag, row)
    tag:SetText(text)
    tag:SetTextColor(color[1], color[2], color[3], color[4])
    tag:Show()
end

local function safePaint(row, elementData)
    pcall(paint, row, elementData)
end

local function hideAll()
    for _, tag in pairs(tags) do tag:Hide() end
end

-- The list initialised a row: that row only is evaluated.
local function onInitialized(_, row, elementData)
    if not active() then
        local tag = type(row) == "table" and tags[row]
        if tag then tag:Hide() end
        return
    end
    pcall(ctl.inPass, safePaint, row, elementData)
end

-- Registers on the list's callback when it exists and was not yet. True on a new registration.
local function register()
    local box = scrollBox()
    if not box or box == registeredOn or type(box.RegisterCallback) ~= "function" then return false end
    local event = field(field(ScrollBoxListMixin, "Event"), "OnInitializedFrame")
    if event == nil then return false end
    if not pcall(box.RegisterCallback, box, event, onInitialized, RecipeRows) then return false end
    registeredOn = box
    return true
end

-- Repaints the rows on screen in one refresh pass (the one running, from Controller.refresh),
-- or hides every tag when the option is off. Nothing while the profession window is hidden.
function RecipeRows.refresh()
    if not ctl then return end
    if not ctl.showRowTags() then
        hideAll()
        return
    end
    if not professionShown() then return end
    register()
    local box = scrollBox()
    if not box or type(box.ForEachFrame) ~= "function" then return end
    pcall(ctl.inPass, function()
        box:ForEachFrame(function(row, elementData) safePaint(row, elementData) end)
    end)
end

-- The profession window was shown or switched profession: registers on its list (once) and
-- paints the rows already there.
function RecipeRows.attach()
    register()
    RecipeRows.refresh()
end

-- Builds nothing: the list belongs to the Professions UI, created lazily.
function RecipeRows.init(controller)
    ctl = controller
end
