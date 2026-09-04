-- Loading the addon under the stub, and saying whether a check held.
--
-- Deliberately small: there is no assertion library to learn, a spec is a
-- function that takes this table, and a failed check records itself and lets
-- the rest of the spec run. A check that stops the file at the first failure
-- hides the other three.

local M = {}

--- The repository root, worked out from where this file sits, so the suite
--- runs the same from the root or from tools/tests.
M.root = (debug.getinfo(1, "S").source:match("^@(.*)[/\\]tools[/\\]tests[/\\]")) or "."

local stub = dofile(M.root .. "/tools/tests/wow_stub.lua")
M.stub = stub

--- Install a fresh client and load the addon files into it.
---
--- Each spec gets its own `addon` table -- the one the game passes as the
--- second vararg to every file in a TOC -- so nothing carries between specs
--- but the globals the stub reinstalls.
---
--- @param files table         addon files to load, in TOC order
--- @param soundLengths table  the clip index the addon should see
--- @return table addon, table env
function M.load(files, soundLengths)
    local env = stub.install(soundLengths)
    local addon = {}
    for _, file in ipairs(files) do
        local chunk = assert(loadfile(M.root .. "/" .. file))
        chunk("QuestReaderAddon", addon)
    end
    -- ADDON_LOADED is what applies the defaults in the running game.
    if addon.EnsureDB then addon.EnsureDB() end
    return addon, env
end

-- ---------------------------------------------------------------------------
-- Results
-- ---------------------------------------------------------------------------
M.passed, M.failed = 0, 0

--- Name the group of checks that follows.
function M.spec(name)
    print(name)
end

--- Record one check. `detail` is printed only on failure, and should say what
--- was actually found -- "expected true" is not worth the line.
function M.check(label, condition, detail)
    if condition then
        M.passed = M.passed + 1
        print("  pass  " .. label)
    else
        M.failed = M.failed + 1
        print("  FAIL  " .. label .. (detail and ("  -- got " .. tostring(detail)) or ""))
    end
end

--- The first frame listening for an event, so a spec can deliver one the way
--- the client would rather than calling the handler directly.
function M.frameFor(env, event)
    for _, frame in ipairs(env.frames) do
        if frame.events[event] then return frame end
    end
end

--- Whether any clip whose file name contains `fragment` was played.
function M.playedAny(env, fragment)
    for _, sound in ipairs(env.played) do
        if sound.path:find(fragment, 1, true) then return true end
    end
    return false
end

return M
