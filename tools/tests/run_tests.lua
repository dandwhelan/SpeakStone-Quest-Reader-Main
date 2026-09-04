-- Run every spec. Exits non-zero if anything failed, so it is usable as a
-- gate as well as a thing to read.
--
--   lua5.1 tools/tests/run_tests.lua
--
-- Lua 5.1 to match the client. The addon uses nothing newer, so a later
-- interpreter will also run this, but 5.1 is what it has to work under.

local t = dofile((debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") or ".") .. "/harness.lua")

local SPECS = {
    "playback_spec.lua",
    "library_spec.lua",
}

for _, name in ipairs(SPECS) do
    local spec = assert(loadfile(t.root .. "/tools/tests/" .. name))()
    spec(t)
    print("")
end

print(string.format("%d passed, %d failed", t.passed, t.failed))
os.exit(t.failed == 0 and 0 or 1)
