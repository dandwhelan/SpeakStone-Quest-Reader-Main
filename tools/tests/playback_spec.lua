-- Narration: what gets spoken, and what gets put back afterwards.
--
-- Every check here is about the gap between choosing a clip and hearing it.
-- The addon holds narration back so Blizzard's own voice line can finish, it
-- silences the Dialog channel for the length of a clip when asked to, and it
-- has no notification of a clip ending -- so a queued clip, a cancelled
-- timer and a released channel are the three things most worth pinning down,
-- and all three are invisible to anything but a clock a test controls.

local FILES = { "QuestReaderAddon.lua" }

local CLIPS = {
    ["100_description.ogg"] = 5,
    ["100_progress.wav"] = 3,
    ["200_description.ogg"] = 7,
    -- Both formats for one passage: .ogg is meant to win.
    ["300_description.ogg"] = 4,
    ["300_description.wav"] = 4,
    -- A pack that recorded no usable length for its clip.
    ["400_description.ogg"] = 0,
}

return function(t)
    t.spec("Playback")

    -- A clip queued behind the delay, replaced before it ever spoke.
    do
        local addon, env = t.load(FILES, CLIPS)
        QuestReaderAddonDB.muteGossip = false
        QuestReaderAddonDB.autoPlayDelay = 2

        env.questID = 100
        PlayQuestAudio("description")      -- queued behind the delay
        env.questID = 200
        PlayQuestAudio("description")      -- the player clicked on before it spoke
        env.advance(2.1)

        t.check("a clip replaced during the delay is spoken once", #env.played == 1, #env.played)
        t.check("and the clip spoken is the current quest's",
            t.playedAny(env, "200_description"),
            env.played[1] and env.played[1].path or "nothing played")

        env.advance(8)
        t.check("nothing is left playing afterwards", addon.IsPlaying() ~= true)
        t.check("and no timer is left waiting", env.liveTimers() == 0, env.liveTimers())
    end

    -- Walking away closes the quest window, which stops narration --
    -- including narration that has not started yet.
    do
        local _, env = t.load(FILES, CLIPS)
        QuestReaderAddonDB.muteGossip = false
        QuestReaderAddonDB.autoPlayDelay = 2

        env.questID = 100
        PlayQuestAudio("description")
        env.fire(t.frameFor(env, "QUEST_FINISHED"), "QUEST_FINISHED")
        env.advance(3)
        t.check("walking away during the delay speaks nothing at all",
            #env.played == 0, #env.played)
    end

    -- Blizzard's own lines silenced: the addon takes the Dialog channel for
    -- the length of a clip and has to give it back.
    do
        local _, env = t.load(FILES, CLIPS)
        QuestReaderAddonDB.muteGossip = true

        env.questID = 100
        PlayQuestAudio("description", true)
        t.check("silencing Blizzard's lines mutes the Dialog channel",
            env.cvars.Sound_DialogVolume == 0, env.cvars.Sound_DialogVolume)
        t.check("and narration moves to the Master channel",
            env.played[1] and env.played[1].channel == "Master",
            env.played[1] and env.played[1].channel)

        env.advance(5.5)
        t.check("the channel is audible again once the clip has run",
            env.cvars.Sound_DialogVolume == "1", env.cvars.Sound_DialogVolume)
    end

    -- The same, for a clip whose pack recorded no length to work from.
    do
        local _, env = t.load(FILES, CLIPS)
        QuestReaderAddonDB.muteGossip = true

        env.questID = 400
        PlayQuestAudio("description", true)
        t.check("a clip with no recorded length still plays", #env.played == 1, #env.played)
        env.advance(121)
        t.check("and still releases the Dialog channel",
            env.cvars.Sound_DialogVolume == "1", env.cvars.Sound_DialogVolume)
        t.check("leaving no timer behind", env.liveTimers() == 0, env.liveTimers())
    end

    -- A quest no installed pack has audio for.
    do
        local _, env = t.load(FILES, CLIPS)
        QuestReaderAddonDB.muteGossip = false

        env.questID = 999
        PlayQuestAudio("description", true)
        t.check("a quest with no audio speaks nothing", #env.played == 0, #env.played)
        t.check("and does not touch the player's dialogue volume",
            env.cvars.Sound_DialogVolume == "1", env.cvars.Sound_DialogVolume)
    end

    -- The lookup every playback path and the audio library share.
    do
        local addon = t.load(FILES, CLIPS)

        local file, path, duration = addon.FindSound({ "100_description" })
        t.check("a clip resolves to its file and length",
            file == "100_description.ogg" and duration == 5,
            tostring(file) .. ", " .. tostring(duration))
        t.check("and to a path inside the pack that holds it",
            path == "Interface\\AddOns\\QuestReaderAddon\\Sounds\\100_description.ogg", path)
        t.check("where both formats exist, the smaller one wins",
            addon.FindSound({ "300_description" }) == "300_description.ogg",
            addon.FindSound({ "300_description" }))
        t.check("and a clip nobody has installed resolves to nothing",
            addon.FindSound({ "999_description" }) == nil)
    end
end
