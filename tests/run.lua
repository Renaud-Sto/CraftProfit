-- Runs every tests/test_*.lua. Run from the project root: luajit tests/run.lua
local H = dofile("tests/harness.lua")

local files = {}
local p = io.popen("ls tests/test_*.lua 2>/dev/null")
for line in p:lines() do files[#files + 1] = line end
p:close()
table.sort(files)

if #files == 0 then
    print("no test files found")
    os.exit(1)
end

for _, f in ipairs(files) do
    H.setFile(f)
    local chunk, err = loadfile(f)
    if not chunk then
        H.failed = H.failed + 1
        H.failures[#H.failures + 1] = f .. ": " .. tostring(err)
        print("FAIL " .. f .. ": " .. tostring(err))
    else
        local ok, e = pcall(chunk, H)
        if not ok then
            H.failed = H.failed + 1
            H.failures[#H.failures + 1] = f .. ": " .. tostring(e)
            print("FAIL " .. f .. ": " .. tostring(e))
        end
    end
end

print(string.format("%d passed, %d failed", H.passed, H.failed))
os.exit(H.failed == 0 and 0 or 1)
