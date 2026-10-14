-- Controller: saved settings (sort mode, appearance, pin limit, minimap button, recipe row
-- tags, window positions).
local _, ns = ...
local Util, DB = ns.Util, ns.DB
local L = ns.L

local Controller = ns.Controller
local say = Controller.say

-- Sorting by cost per point needs the cost per point: it switches the option on.
function Controller.setSortMode(mode)
    DB.setSortMode(CraftProfitCharDB, mode)
    if CraftProfitCharDB.sortMode == DB.SORT_POINT then
        CraftProfitDB.settings.showPerPoint = true
    end
    Controller.refresh()
end

function Controller.toggleSort()
    Controller.setSortMode(CraftProfitCharDB.sortMode == DB.SORT_POINT and DB.SORT_NET or DB.SORT_POINT)
end

-- Appearance ---------------------------------------------------------------------

-- Picks the header strip and the tile card (either nil = keep), repaints every window at
-- once (Native keeps its panels and tiles) and saves the choice. An unknown key refuses the
-- whole call: nothing changes. Returns true when the look changed.
function Controller.setAppearance(header, tile)
    if header ~= nil and not DB.HEADER_KEYS[header] then return false end
    if tile ~= nil and not DB.TILE_KEYS[tile] then return false end
    -- Merged into the SAVED choice, never read back from Native: what is on screen may
    -- differ (a developer preview), and must not leak into the save.
    local saved = CraftProfitDB.settings.appearance
    local newHeader, newTile = header or saved.header, tile or saved.tile
    local changed = newHeader ~= saved.header or newTile ~= saved.tile
    ns.Native.setHeaderVariant(newHeader)
    ns.Native.setTileVariant(newTile)
    CraftProfitDB.settings.appearance = { header = newHeader, tile = newTile }
    return changed
end

-- The saved look: header, tile keys.
function Controller.appearance()
    local appearance = CraftProfitDB.settings.appearance
    return appearance.header, appearance.tile
end

-- Pinned recipes limit -------------------------------------------------------------

-- How many recipes a character may pin (account wide setting, one of DB.PIN_LIMITS).
function Controller.pinLimit()
    return DB.pinLimit(CraftProfitDB.settings.maxPins)
end

-- The pinned panels' title with the pin count over the limit, e.g. "PINNED RECIPES (21/30)".
-- The count can exceed the limit after it was lowered (pins are never deleted for it).
function Controller.pinsTitle()
    return string.format(L.PANEL_PINS_COUNT, #CraftProfitCharDB.pins, Controller.pinLimit())
end

-- Saves a new limit and refreshes every view (the options window lights it). Anything but a
-- listed limit is refused and changes nothing. Pins over a lower limit are kept: it only
-- blocks new ones. Returns true when the limit was accepted.
function Controller.setPinLimit(n)
    if not DB.isPinLimit(n) then return false end
    CraftProfitDB.settings.maxPins = n
    Controller.refresh()
    return true
end

-- Options window and minimap button ---------------------------------------------------

function Controller.minimapHidden()
    return CraftProfitDB.settings.minimap.hide == true
end

-- Hides (true) or shows the minimap button, saves it, and applies it when the button
-- module is loaded.
function Controller.setMinimapHidden(hidden)
    CraftProfitDB.settings.minimap.hide = hidden and true or false
    local button = ns.MinimapButton
    if type(button) == "table" and type(button.apply) == "function" then button.apply() end
    -- The options window's check box follows a change made elsewhere (/cp minimap).
    if ns.OptionsUI then ns.OptionsUI.refresh() end
end

function Controller.minimapAngle()
    return CraftProfitDB.settings.minimap.angle
end

-- Saves where the minimap button was dragged; a bad angle is ignored.
function Controller.setMinimapAngle(angle)
    local clean = DB.angle(angle)
    if clean then CraftProfitDB.settings.minimap.angle = clean end
end

-- /cp minimap: hides the button, or shows it again, and says which in one line.
function Controller.minimapCommand()
    local hidden = not Controller.minimapHidden()
    Controller.setMinimapHidden(hidden)
    say(hidden and L.MINIMAP_HIDDEN or L.MINIMAP_SHOWN)
end

-- The profit tags on the profession window's recipe rows -------------------------------

function Controller.showRowTags()
    return CraftProfitDB.settings.showRowTags == true
end

-- Saves the choice and repaints the rows at once (or hides their tags), and the options
-- window's check box.
function Controller.setShowRowTags(value)
    CraftProfitDB.settings.showRowTags = value and true or false
    if ns.RecipeRows then ns.RecipeRows.refresh() end
    if ns.OptionsUI then ns.OptionsUI.refresh() end
end

function Controller.saveOptionsPosition(x, y)
    if Util.isFinite(x) and Util.isFinite(y) then
        CraftProfitDB.settings.optionsWindow = { x = x, y = y }
    end
end

function Controller.savePinsPosition(x, y)
    if Util.isFinite(x) and Util.isFinite(y) then
        CraftProfitDB.settings.pinsWindow = { x = x, y = y }
    end
end

function Controller.saveHistoryPosition(x, y)
    if Util.isFinite(x) and Util.isFinite(y) then
        CraftProfitDB.settings.historyWindow = { x = x, y = y }
    end
end

function Controller.saveLevelPosition(x, y)
    if Util.isFinite(x) and Util.isFinite(y) then
        CraftProfitDB.settings.levelWindow = { x = x, y = y }
    end
end
