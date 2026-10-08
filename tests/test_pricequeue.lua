local H = ...

local function load() return H.newNS("Util", "PriceQueue").PriceQueue end

-- Builds a queue wired to recording callbacks. `sendResult` decides what send returns.
local function build(ids, sendResult)
    local PQ = load()
    local log = { sent = {}, items = {}, progress = {}, done = nil }
    local q
    q = PQ.new({
        itemIDs = ids,
        timeout = 6,
        send = function(id)
            log.sent[#log.sent + 1] = id
            if type(sendResult) == "function" then return sendResult(id, q) end
            return sendResult ~= false
        end,
        onItem = function(id, listings, err) log.items[#log.items + 1] = { id, listings, err } end,
        onProgress = function(done, total) log.progress[#log.progress + 1] = { done, total } end,
        onDone = function(summary) log.done = summary end,
    })
    return q, log
end

H.test("items are searched one at a time, in order", function()
    local q, log = build({ 1, 2, 3 })
    q:start(0)
    H.eq(log.sent, { 1 })
    q:results(1, { { unit = 5, qty = 1 } }, 1)
    H.eq(log.sent, { 1, 2 })
    q:results(2, {}, 2)
    q:results(3, {}, 3)
    H.eq(log.sent, { 1, 2, 3 })
    H.eq(q.state, "done")
    H.eq(log.done, { ok = 3, failed = {}, total = 3, cancelled = false })
    H.eq(log.items[1], { 1, { { unit = 5, qty = 1 } }, nil })
    H.eq(log.progress, { { 1, 3 }, { 2, 3 }, { 3, 3 } })
end)

H.test("an item that never answers times out and the queue moves on", function()
    local q, log = build({ 1, 2 })
    q:start(0)
    q:tick(5.9)
    H.eq(log.sent, { 1 })
    q:tick(6)
    H.eq(log.items[1], { 1, nil, "timeout" })
    H.eq(log.sent, { 1, 2 })
    q:results(2, {}, 7)
    H.eq(log.done, { ok = 1, failed = { { itemID = 1, err = "timeout" } }, total = 2, cancelled = false })
end)

H.test("results for an item that is not current are ignored", function()
    local q, log = build({ 1, 2 })
    q:start(0)
    q:results(2, {}, 1)
    q:results(99, {}, 1)
    H.eq(#log.items, 0)
    q:results(1, {}, 2)
    q:results(1, {}, 3)
    H.eq(#log.items, 1)
end)

H.test("a throttled AH is retried on every tick, then the item fails", function()
    local allow = false
    local q, log = build({ 1, 2 }, function() return allow end)
    q:start(0)
    q:tick(1)
    q:tick(2)
    H.eq(log.sent, { 1, 1, 1 })
    allow = true
    q:tick(3)
    H.eq(log.sent, { 1, 1, 1, 1 })
    q:tick(3.1)
    H.eq(#log.items, 0)
    q:results(1, {}, 4)
    H.eq(log.sent[#log.sent], 2)
end)

H.test("an item that is never accepted fails as throttled after three timeouts", function()
    local q, log = build({ 1, 2 }, function(id) return id == 2 end)
    q:start(0)
    q:tick(18)
    H.eq(#log.items, 0)
    q:tick(18.1)
    H.eq(log.items[1], { 1, nil, "throttled" })
    H.eq(log.sent[#log.sent], 2)
end)

H.test("cancel stops the queue and ignores late results", function()
    local q, log = build({ 1, 2, 3 })
    q:start(0)
    q:cancel()
    H.eq(q.state, "cancelled")
    H.eq(log.done, { ok = 0, failed = {}, total = 3, cancelled = true })
    q:results(1, {}, 1)
    q:tick(100)
    H.eq(#log.items, 0)
    H.eq(log.sent, { 1 })
end)

H.test("duplicate and invalid item ids are dropped", function()
    local q, log = build({ 1, 1, "x", 0, 2, 0 / 0 })
    q:start(0)
    q:results(1, {}, 1)
    q:results(2, {}, 2)
    H.eq(log.sent, { 1, 2 })
    H.eq(log.done.total, 2)
end)

H.test("an empty queue finishes immediately", function()
    local q, log = build({})
    q:start(0)
    H.eq(q.state, "done")
    H.eq(log.done, { ok = 0, failed = {}, total = 0, cancelled = false })
end)

H.test("an answer that arrives while send is still running does not double-advance", function()
    local q, log = build({ 1, 2, 3 }, function(id, queue)
        queue:results(id, {}, 0)
        return true
    end)
    q:start(0)
    H.eq(log.sent, { 1, 2, 3 })
    H.eq(q.state, "done")
    H.eq(log.done.ok, 3)
end)

H.test("an invalid clock value raises and leaves the state untouched", function()
    local q = build({ 1 })
    H.raises(function() q:start(0 / 0) end)
    H.eq(q.state, "idle")
    q:start(0)
    H.raises(function() q:tick(nil) end)
    H.raises(function() q:results(1, {}, 1 / 0) end)
    H.eq(q.state, "running")
end)

H.test("start twice, tick before start and tick after done are harmless", function()
    local q, log = build({ 1 })
    q:tick(1)
    q:start(0)
    q:start(1)
    H.eq(log.sent, { 1 })
    q:results(1, {}, 2)
    q:tick(50)
    H.eq(#log.items, 1)
end)

H.test("a callback that cancels the queue stops it cleanly", function()
    local PQ = load()
    local sent = {}
    local q
    q = PQ.new({
        itemIDs = { 1, 2 },
        send = function(id) sent[#sent + 1] = id; return true end,
        onItem = function() q:cancel() end,
    })
    q:start(0)
    q:results(1, {}, 1)
    H.eq(sent, { 1 })
    H.eq(q.state, "cancelled")
end)
