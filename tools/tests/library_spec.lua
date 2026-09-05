-- The audio library window: what it lists, what it listens for, and what it
-- does to narration already in progress.
--
-- The index it lists from is the one expensive walk the addon makes -- every
-- clip in every installed pack -- so what belongs in it, and what does not,
-- is worth stating. The rest is about the window's edges: an event it should
-- only care about while it is open, and a preview that has to get out of the
-- way of the quest being read aloud.

local FILES = { "QuestReaderAddon.lua", "QuestAudioLibraryUI.lua" }

local CLIPS = {
    ["100_description.ogg"] = 5,
    ["100_progress.wav"] = 3,
    ["200_description.ogg"] = 7,
    -- Neither of these is a quest, and neither belongs in the quest list.
    ["npc55_gossip1.ogg"] = 4,
    ["item777_page1.ogg"] = 9,
}

return function(t)
    t.spec("Audio library")

    -- ----------------------------------------------------------------------
    local addon, env = t.load(FILES, CLIPS)
    local index = addon.GetAudioIndex()

    t.check("only quests are counted as quests", index.questCount == 2, index.questCount)
    t.check("a quest records every passage it has audio for",
        index.quests[100].types.description and index.quests[100].types.progress)
    t.check("greetings stay out of the quest list", index.quests[55] == nil)
    t.check("as does book text", index.quests[777] == nil)

    local packs, clips = addon.GetInstalledAudioSummary()
    t.check("every installed clip is counted", clips == 5, clips)
    t.check("and attributed to the pack that holds it",
        #packs == 1 and packs[1].name == "QuestReaderAddon" and packs[1].clips == 5)

    -- ----------------------------------------------------------------------
    local ui = addon.OpenAudioLibrary()
    t.check("the window opens", ui:IsShown() == true)
    t.check("and listens for quest names while it is open",
        env.isListening("QUEST_DATA_LOAD_RESULT"))

    ui:FilterList("100")
    t.check("a search narrows the list", #ui.filteredList == 1, #ui.filteredList)
    t.check("to the quest that was searched for",
        ui.filteredList[1] and ui.filteredList[1].id == 100,
        ui.filteredList[1] and ui.filteredList[1].id)

    ui:FilterList("")
    t.check("and clearing it restores the whole library", #ui.filteredList == 2, #ui.filteredList)

    -- ----------------------------------------------------------------------
    t.check("durations come back for a clip that exists",
        ui:GetAudioDuration(100, "description") == 5,
        ui:GetAudioDuration(100, "description"))
    t.check("and not for one that does not",
        ui:GetAudioDuration(999, "description") == nil)

    -- ----------------------------------------------------------------------
    -- A preview clicked while a quest is being read aloud.
    QuestReaderAddonDB.muteGossip = true
    env.questID = 200
    PlayQuestAudio("description", true)
    t.check("narration has the Dialog channel muted",
        env.cvars.Sound_DialogVolume == 0, env.cvars.Sound_DialogVolume)

    env.resetSound()
    ui:PlaySpecificAudio(100, "progress")

    t.check("previewing stops the narration underneath it", #env.stopped == 1, #env.stopped)
    t.check("so the channel the preview plays on is audible",
        env.cvars.Sound_DialogVolume == "1", env.cvars.Sound_DialogVolume)
    t.check("and the preview plays the file that exists",
        t.playedAny(env, "100_progress.wav"),
        env.played[1] and env.played[1].path or "nothing played")

    -- ----------------------------------------------------------------------
    ui:Hide()
    t.check("a closed window stops listening for quest names",
        env.isListening("QUEST_DATA_LOAD_RESULT") == false)
    t.check("and leaves nothing ticking behind it", env.liveTimers() == 0, env.liveTimers())
end
