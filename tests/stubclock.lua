-- A fake local clock for the price history tests (not a test file: run.lua only runs
-- tests/test_*.lua). stubClock(base, dstFrom, dstTo) returns a date function like
-- date("*t", t) and a time function like time(fields) for a zone `base` seconds ahead of
-- UTC, one hour more from the UTC instant dstFrom (inclusive) to dstTo (exclusive), so
-- the tests never depend on the machine's time zone. Local day n since the epoch is
-- given as { year = 1970, month = 1, day = n + 1 }; the time function only reads those
-- fields back, it does not normalise them.
local DAY = 86400

return function(base, dstFrom, dstTo)
    local function offsetAt(t)
        if dstFrom and t >= dstFrom and t < dstTo then return base + 3600 end
        return base
    end
    local function dateFn(fmt, t)
        assert(fmt == "*t")
        local s = t + offsetAt(t)
        local n = math.floor(s / DAY)
        local secs = s - n * DAY
        return { year = 1970, month = 1, day = n + 1, hour = math.floor(secs / 3600),
            min = math.floor(secs % 3600 / 60), sec = secs % 60, wday = (n + 4) % 7 + 1 }
    end
    local function timeFn(f)
        local s = (f.day - 1) * DAY + f.hour * 3600 + f.min * 60 + f.sec
        for _, off in ipairs({ base, base + 3600 }) do
            if offsetAt(s - off) == off then return s - off end
        end
        return s - base
    end
    return dateFn, timeFn
end
