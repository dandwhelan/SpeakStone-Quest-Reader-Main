# Addon tests

```
lua5.1 tools/tests/run_tests.lua
```

Exits non-zero if anything failed. Lua 5.1 to match the client; the addon
uses nothing newer, so a later interpreter runs these too.

## Why these exist

The addon cannot be run outside the game, and the faults most worth catching
are the ones that live in time rather than in a line of code: a clip queued
behind the autoplay delay, a timer that outlives the clip it was scheduled
for, a channel muted by one path and released by another. Reading cannot
settle any of those. Given a clock the test holds rather than one it waits
for, all of them are a few lines.

So `wow_stub.lua` is a stand-in for the client, not an emulator. Frames
remember their scripts and nothing else, sound files are recorded rather than
played, `C_Timer` hands out timers that only fire when a test moves the clock,
and anything the addon calls that no test cares about resolves to a no-op --
so adding a widget to a window does not break the suite.

## Layout

| File | |
| --- | --- |
| `wow_stub.lua` | The client stand-in. `install()` returns the clock, the frames, and what was played. |
| `harness.lua` | Loads addon files into a fresh stub, and records checks. |
| `playback_spec.lua` | What gets spoken, and what gets put back afterwards. |
| `library_spec.lua` | What the audio library lists, listens for, and interrupts. |
| `run_tests.lua` | Runs every spec. |

A spec is a function that takes the harness. A failed check records itself and
lets the rest of the spec run -- stopping at the first failure hides the other
three.

## Adding one

```lua
local FILES = { "QuestReaderAddon.lua" }
local CLIPS = { ["100_description.ogg"] = 5 }

return function(t)
    t.spec("What this covers")

    local addon, env = t.load(FILES, CLIPS)
    env.questID = 100
    PlayQuestAudio("description", true)

    t.check("it says something", #env.played == 1, #env.played)
end
```

`t.load` returns a fresh addon table and a fresh client for every call, so
several situations can sit in one spec without leaking into each other. Add
the file to `SPECS` in `run_tests.lua`.

`env` carries `advance(seconds)`, `liveTimers()`, `fire(frame, event, ...)`,
`frames`, `isListening(event)`, `played`, `stopped`, `resetSound()`, `cvars`
and `questID`. `t` carries `check`, `spec`, `frameFor(env, event)` and
`playedAny(env, fragment)`.

The suite is build-side only -- `pkgmeta.yaml` keeps `tools` out of the zip a
player downloads.
