local H = ...

-- The game raises "Division by zero" (found by /cp selftest in the beta) where
-- plain Lua returns inf or NaN, so a literal zero divisor must never appear.
H.test("no addon file divides by a literal zero", function()
    local p = io.popen("cd CraftProfit && find . -name '*.lua' | sort")
    local bad = {}
    for name in p:lines() do
        local f = assert(io.open("CraftProfit/" .. name))
        local n = 0
        for line in f:lines() do
            n = n + 1
            local code = line:gsub("%-%-.*$", "")
            if code:match("/%s*0%f[%D]") and not code:match("/%s*0%.%d") then bad[#bad + 1] = name .. ":" .. n end
        end
        f:close()
    end
    p:close()
    if #bad > 0 then error("literal division by zero at " .. table.concat(bad, ", ")) end
end)
