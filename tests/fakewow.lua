-- Fake WoW environment for smoke tests. Loads the real addon files, in the
-- order listed in CraftProfit.toc, into one namespace with stubbed game APIs.
-- Not a test file: tests/run.lua only runs tests/test_*.lua.
local W = {}

-- A permissive fake frame: known methods record state, every other method is a
-- no-op, so UI code can run without a game client.
function W.frame()
    local f = { scripts = {}, events = {}, shown = false }
    local methods = {
        SetText = function(self, t) self.text = t end,
        GetText = function(self) return self.text end,
        SetScript = function(self, name, fn) self.scripts[name] = fn end,
        HookScript = function(self, name, fn) self.scripts[name] = fn end,
        RegisterEvent = function(self, e) self.events[#self.events + 1] = e end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        SetShown = function(self, v) self.shown = v and true or false end,
        IsShown = function(self) return self.shown end,
        SetChecked = function(self, v) self.checked = v and true or false end,
        GetChecked = function(self) return self.checked end,
        GetLeft = function() return 100 end,
        GetTop = function() return 700 end,
        SetHeight = function(self, h) self.height = h end,
        GetHeight = function(self) return self.height or 0 end,
        CreateFontString = function() return W.frame() end,
        CreateTexture = function() return W.frame() end,
    }
    return setmetatable(f, { __index = function(_, k) return methods[k] or function() end end })
end

-- opts: locale, items = { [itemID] = {quality, ilvl, sellPrice, classID, bindType} }
function W.boot(H, opts)
    opts = opts or {}
    local ns = {}
    local env = setmetatable({}, { __index = _G })
    local T = { ns = ns, env = env, chat = {}, timers = {}, tickers = {}, clock = 1000, loadRequests = {} }

    env.GetTime = function() return T.clock end
    env.time = function() return 1700000000 end
    env.GetLocale = function() return opts.locale or "enUS" end
    env.UIParent = W.frame()
    env.CreateFrame = function() return W.frame() end
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) T.chat[#T.chat + 1] = m end }
    env.GetCoinTextureString = function(c) return "<" .. c .. ">" end
    env.SlashCmdList = {}
    env.Enum = {}
    env.C_Timer = {
        After = function(_, fn) T.timers[#T.timers + 1] = fn end,
        NewTicker = function(_, fn)
            local ticker = { fn = fn, cancelled = false }
            function ticker.Cancel() ticker.cancelled = true end
            T.tickers[#T.tickers + 1] = ticker
            return ticker
        end,
    }
    env.C_Item = {
        GetItemInfo = function(id)
            local i = opts.items and opts.items[id]
            if not i then return nil end
            return "Item" .. id, "link", i.quality, i.ilvl, 1, "type", "sub", 1, "", 0,
                i.sellPrice, i.classID, 0, i.bindType
        end,
        RequestLoadItemDataByID = function(id) T.loadRequests[#T.loadRequests + 1] = id end,
    }
    env.C_AuctionHouse = {}

    local toc = assert(io.open("CraftProfit/CraftProfit.toc")):read("*a")
    for line in toc:gmatch("[^\r\n]+") do
        if not line:match("^##") and line:match("%S") then
            local name = (line:gsub("%.lua%s*$", ""))
            H.loadModule(name, ns, env)
        end
    end

    -- Runs every callback scheduled with C_Timer.After.
    function T.run()
        while #T.timers > 0 do table.remove(T.timers, 1)() end
    end
    return T
end

return W
