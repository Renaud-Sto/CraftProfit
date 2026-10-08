-- Sequential price search over a list of items. Pure Lua, no WoW API: the game
-- adapter supplies `send` and feeds `results` and `tick`.
local _, ns = ...
local Util = ns.Util

local PriceQueue = {}
PriceQueue.__index = PriceQueue
ns.PriceQueue = PriceQueue

local DEFAULT_TIMEOUT = 6
-- An item the AH refuses to take for this many timeouts is abandoned.
local THROTTLE_FACTOR = 3

-- Time must be finite: NaN would silently disable every timeout. Level 3 blames
-- the caller of the public method, not this helper.
local function checkTime(now)
    if not Util.isFinite(now) then
        error("PriceQueue: invalid time " .. tostring(now), 3)
    end
end

function PriceQueue.new(opts)
    local ids, seen = {}, {}
    for _, raw in ipairs(opts.itemIDs or {}) do
        local id = Util.id(raw)
        if id and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    return setmetatable({
        opts = opts,
        ids = ids,
        total = #ids,
        index = 0,
        done = 0,
        okCount = 0,
        failed = {},
        state = "idle",
        timeout = opts.timeout or DEFAULT_TIMEOUT,
    }, PriceQueue)
end

function PriceQueue:finish(cancelled)
    self.state = cancelled and "cancelled" or "done"
    self.current = nil
    if self.opts.onDone then
        self.opts.onDone({
            ok = self.okCount, failed = self.failed, total = self.total, cancelled = cancelled,
        })
    end
end

-- Tries to send the current item. The answer may arrive before send returns
-- (tests do this); then current has already moved on and we must not touch it.
function PriceQueue:attempt(now)
    local id = self.current
    local ok = self.opts.send(id)
    if self.current ~= id or self.state ~= "running" then return end
    if ok then
        self.sent = true
        self.sentAt = now
        self.waitingSince = nil
    else
        self.sent = false
        self.waitingSince = self.waitingSince or now
    end
end

function PriceQueue:advance(now)
    self.index = self.index + 1
    local id = self.ids[self.index]
    if not id then
        self:finish(false)
        return
    end
    self.current = id
    self.sent = false
    self.waitingSince = nil
    self:attempt(now)
end

function PriceQueue:complete(listings, err, now)
    local id = self.current
    self.done = self.done + 1
    if err then
        self.failed[#self.failed + 1] = { itemID = id, err = err }
    else
        self.okCount = self.okCount + 1
    end
    if self.opts.onItem then self.opts.onItem(id, listings, err) end
    if self.opts.onProgress then self.opts.onProgress(self.done, self.total) end
    -- A callback may have cancelled the queue.
    if self.state == "running" then self:advance(now) end
end

function PriceQueue:start(now)
    checkTime(now)
    if self.state ~= "idle" then return end
    self.state = "running"
    self:advance(now)
end

-- Call regularly (about every 0.2 s) with a monotonic clock.
function PriceQueue:tick(now)
    checkTime(now)
    if self.state ~= "running" then return end
    if self.sent then
        if now - self.sentAt >= self.timeout then self:complete(nil, "timeout", now) end
        return
    end
    self:attempt(now)
    if self.state == "running" and not self.sent and self.waitingSince
        and now - self.waitingSince > self.timeout * THROTTLE_FACTOR then
        self:complete(nil, "throttled", now)
    end
end

-- Feed the listings the AH returned for itemID. Anything but the current item
-- is ignored (stale events, other addons' searches).
function PriceQueue:results(itemID, listings, now)
    checkTime(now)
    if self.state ~= "running" or itemID ~= self.current then return end
    self:complete(listings or {}, nil, now)
end

function PriceQueue:cancel()
    if self.state == "running" then self:finish(true) end
end
