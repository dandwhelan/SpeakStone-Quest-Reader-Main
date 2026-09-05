local addonName, addon = ...
local LDB = LibStub("LibDataBroker-1.1")
local icon = LibStub("LibDBIcon-1.0")

-- Ogg first: new content is generated as Ogg Vorbis, and where both exist the
-- smaller file is preferred.
-- Local, not a global: "SOUND_EXTENSIONS" is a name any other addon could
-- plausibly claim, and whichever loaded second would win. The audio library
-- used to be handed this list to walk itself; it shares FindSound now, which
-- is the only thing that ever needed to know the order.
local SOUND_EXTENSIONS = { ".ogg", ".wav" }

-- Sound packs (per-expansion audio, shipped as separate addons) merge their
-- duration index in here, keyed by the pack's addon name. Every lookup below
-- searches this whole table, so it does not matter how many packs are
-- installed, or whether a given one is: an absent pack just never adds an
-- entry, and the "no audio for this quest" path already used for gaps in the
-- base library covers it too. No error, no crash, just silence.
addon.soundSources = {}
addon.soundSources["QuestReaderAddon"] = QuestReaderSoundLengths

-- Anything derived from soundSources is cached, because deriving it means
-- walking every clip in every installed pack -- tens of thousands of table
-- entries with a string match each. A pack arriving later is the only thing
-- that can change the answer, so this is called from the two places that
-- register one.
local function InvalidateAudioCaches()
    addon.audioIndex = nil
    if addon.AudioLibraryInvalidate then
        addon.AudioLibraryInvalidate()
    end
end
addon.InvalidateAudioCaches = InvalidateAudioCaches

-- Expansion packs are independent addons, and WoW gives no guarantee about
-- which of two independent addons finishes loading first. A pack that loads
-- *before* this one has nowhere to register yet, so it drops itself into a
-- plain global that exists regardless of load order; a pack that loads
-- *after* calls this function directly. Either way the pack's audio becomes
-- visible as soon as both sides have run, whichever order that happens in.
--
-- Packs call this as:
--   QuestReaderAddon_RegisterSoundPack(addonName, ThisPackSoundLengths)
-- falling back to the pending-queue global if it is not yet defined. See
-- the example pack under packs/ for the exact two-line pattern.
function QuestReaderAddon_RegisterSoundPack(packName, soundLengths)
    if type(packName) ~= "string" or type(soundLengths) ~= "table" then
        return
    end
    -- Merge rather than replace: overwriting dropped the sounds bundled
    -- with the base addon in an earlier version of this mechanism, and
    -- breaking here meant only one pack could ever be registered.
    addon.soundSources[packName] = soundLengths
    -- The audio library caches its index on first open, and the settings
    -- dashboard caches its clip counts. A pack arriving after either would
    -- otherwise stay invisible until reload.
    InvalidateAudioCaches()
end

-- Drain anything a pack queued before this file ran (see above).
if type(_G.QuestReaderPendingSoundPacks) == "table" then
    for _, entry in ipairs(_G.QuestReaderPendingSoundPacks) do
        QuestReaderAddon_RegisterSoundPack(entry.name, entry.index)
    end
    _G.QuestReaderPendingSoundPacks = nil
end

-- Legacy mechanism, kept for the existing TWW language packs: explicitly
-- named OptionalDeps that this addon loads and merges itself, rather than
-- the pack registering on its own. New expansion packs should prefer
-- self-registration above; it does not require this addon to know their
-- names in advance.
local optionalSoundPacks = {
    "QuestReaderAddon_TWW_EN",
    "QuestReaderAddon_TWW_FR"
}

-- Default values for saved settings. SavedVariables are not populated until
-- ADDON_LOADED fires, so defaults are applied in InitializeAddonDB rather than
-- at file scope, where they would be overwritten by the saved variables file.
local defaultSettings = {
    showMinimapButton = true,
    -- The master switch. The three below are what it covers, so a player who
    -- wants narration for books but not for every passing greeting does not
    -- have to give up autoplay entirely.
    autoPlayEnabled = true,
    autoPlayQuests = true,
    autoPlayGossip = true,
    autoPlayItemText = true,
    autoPlayInQuestMap = false,
    -- Off: Blizzard's own voice acting plays, and narration waits its turn
    -- (see autoPlayDelay). The game's voiced dialogue is the thing the player
    -- came for where it exists; SpeakStone fills the silence where it does
    -- not. Turning this on silences the game's Dialog channel instead and
    -- narrates immediately.
    muteGossip = false,
    stopDialogueOnClose = true,
    showDebugMessages = false,
    -- Capture quest/gossip/book text as it is encountered, so gaps in the
    -- voiced library can be filled. On by default: this is the one thing the
    -- project needs from players that nothing else can supply, it costs
    -- nothing to run, and the player's own character name is scrubbed before
    -- anything is stored. Switched off in the settings panel.
    harvestEnabled = true,
    -- Shown at the bottom of the quest window / quest log. Some players use a
    -- replacement quest UI and never want ours drawn over it.
    showQuestButton = true,
    -- Seconds to hold narration back so Blizzard's own voice line can finish
    -- first. Was hardcoded to 2; a slider is better because the right value
    -- depends on how fast the player clicks through dialogue. Only applies
    -- while those lines are audible -- see muteGossip.
    autoPlayDelay = 2,
}

-- Autoplay for one kind of text. The master switch gates all three, so
-- turning autoplay off still means off; each kind then has its own say.
-- Nil-safe on the sub-keys so a saved-variables file written before they
-- existed reads as "on" rather than silently disabling narration.
local function AutoPlayAllowed(kind)
    if not QuestReaderAddonDB or not QuestReaderAddonDB.autoPlayEnabled then
        return false
    end
    return QuestReaderAddonDB[kind] ~= false
end
addon.AutoPlayAllowed = AutoPlayAllowed

-- Defined at the bottom of the file, alongside the rest of the CVar
-- handling. Declared here so everything in between can reach them, and so
-- they stop being globals -- "MuteDialogChannel" is not a name this addon
-- has any claim to.
local MuteDialogChannel, UnmuteDialogChannel

local function DebugPrint(...)
    if QuestReaderAddonDB and QuestReaderAddonDB.showDebugMessages then
        print(...)
    end
end
addon.DebugPrint = DebugPrint

-- Applying defaults is idempotent, and both this file and the settings panel
-- want it done before they read anything. Their ADDON_LOADED handlers run in
-- no guaranteed order -- EventUtil's frame registered for the event long
-- before ours did -- so the settings panel calls this itself rather than
-- assuming it has already run. Whichever gets there first does the work; the
-- second call finds every key present and changes nothing.
local dbInitialized = false

local function InitializeAddonDB()
    if dbInitialized then return end
    dbInitialized = true
    QuestReaderAddonDB = QuestReaderAddonDB or {}
    QuestReaderAddonDB.minimapButton = QuestReaderAddonDB.minimapButton or { hide = false }
    QuestReaderAddonDB.minimapIconPosition = QuestReaderAddonDB.minimapIconPosition or {}

    for option, default in pairs(defaultSettings) do
        if QuestReaderAddonDB[option] == nil then
            QuestReaderAddonDB[option] = default
        end
    end

    QuestReaderAddonDB.IsPaused = false
    QuestReaderAddonDB.IsSoundPaused = false

    -- Fold in anything from the older stores (the standalone Harvester addon,
    -- and the missingCaptures table this addon used before capture was built
    -- in). Runs after the defaults above so the store it writes into exists.
    if addon.HarvestMigrate then
        addon.HarvestMigrate()
    end
end

-- SetCVar writes through to the client's config file, so a session that ended
-- while narration had the Dialog channel muted -- a crash, or a disconnect
-- between the mute and the unmute -- comes back with the player's dialogue
-- still silent and nothing on screen to explain it. The volume that was
-- muted over is saved to disk at the same time, so this can put it back.
-- Never restores a zero: that is the state being rescued from.
local function RestoreStrandedDialogVolume()
    -- Called straight after InitializeAddonDB, so the store is there -- but
    -- the read below used to be guarded and the write beside it was not,
    -- which is the wrong way round for a function whose whole job is to run
    -- before anything else has touched the volume.
    if not QuestReaderAddonDB then return end
    local saved = QuestReaderAddonDB.savedDialogVolume
    QuestReaderAddonDB.savedDialogVolume = nil
    local level = tonumber(saved)
    if level and level > 0 then
        -- The number that was validated, not the raw saved value: a store
        -- written by an older build holds a string, and "0.5abc" reaching the
        -- CVar is not something to find out about at the client's discretion.
        SetCVar("Sound_DialogVolume", level)
        DebugPrint("SpeakStone: restored the dialogue volume left muted by the last session.")
    end
end
addon.EnsureDB = InitializeAddonDB

-- Create the LDB launcher
local questReaderLauncher = LDB:NewDataObject("QuestReaderAddon", {
    type = "launcher",
    -- Named with the extension on purpose. An extensionless texture path
    -- resolves to .blp first, and the old cs_icon.blp has been removed in
    -- favour of a TGA, which is the other format WoW loads and the only one
    -- of the two this project can author.
    icon = "Interface\\AddOns\\" .. addonName .. "\\cs_icon.tga",
    OnClick = function(_, button)
        if button == "LeftButton" then
            addon:OpenSettings()
        elseif button == "RightButton" then
            -- Capture is built in now, so this always has somewhere to go.
            -- The standalone Harvester addon still wins if it is installed,
            -- since in that case it, not this addon, holds the recordings.
            if SlashCmdList["QUESTREADERHARVEST"] then
                SlashCmdList["QUESTREADERHARVEST"]("export")
            else
                addon.ShowHarvestExport()
            end
        elseif button == "MiddleButton" then
            QuestReaderAddonDB.showDebugMessages = not QuestReaderAddonDB.showDebugMessages
            print("SpeakStone Debug Messages: " .. (QuestReaderAddonDB.showDebugMessages and "Enabled" or "Disabled"))
        end
    end,
    OnTooltipShow = function(tooltip)
        tooltip:AddLine("SpeakStone")
        tooltip:AddLine("|cffffffffLeft-Click:|r Open Settings", 1, 1, 1)
        tooltip:AddLine("|cffffffffMiddle-Click:|r Toggle Debug Messages (" .. ((QuestReaderAddonDB and QuestReaderAddonDB.showDebugMessages) and "|cff00ff00On|r" or "|cffff0000Off|r") .. ")", 1, 1, 1)
        tooltip:AddLine("|cff00ff00Right-Click:|r Export Captured Text", 0.2, 1, 0.2)
    end,
})

local function UpdateMinimapButtonVisibility()
    -- LibDBIcon reads its own hide flag out of this table on register and on
    -- profile refresh. Setting only showMinimapButton left the two disagreeing,
    -- so the button came back on the next login after being hidden.
    QuestReaderAddonDB.minimapButton = QuestReaderAddonDB.minimapButton or {}
    QuestReaderAddonDB.minimapButton.hide = not QuestReaderAddonDB.showMinimapButton
    if QuestReaderAddonDB.showMinimapButton then
        icon:Show("QuestReaderAddon")
        C_Timer.After(0.1, function()
            local minimapButton = icon:GetMinimapButton("QuestReaderAddon")
            if minimapButton and QuestReaderAddonDB.minimapIconPosition.point then
                minimapButton:ClearAllPoints()
                minimapButton:SetPoint(
                    QuestReaderAddonDB.minimapIconPosition.point,
                    Minimap,
                    QuestReaderAddonDB.minimapIconPosition.relPoint,
                    QuestReaderAddonDB.minimapIconPosition.x,
                    QuestReaderAddonDB.minimapIconPosition.y
                )
            end
        end)
    else
        icon:Hide("QuestReaderAddon")
    end
end
addon.UpdateMinimapButtonVisibility = UpdateMinimapButtonVisibility

-- Defined further down, next to the pack-loading it does; declared here so
-- the PLAYER_LOGIN handler below closes over the local rather than looking
-- for a global that no longer exists.
local DetectSoundPacks

-- Create a frame to listen for the ADDON_LOADED event
local loadingFrame = CreateFrame("Frame")
loadingFrame:RegisterEvent("ADDON_LOADED")
loadingFrame:RegisterEvent("PLAYER_LOGIN")
loadingFrame:SetScript("OnEvent", function(self, event, loadedAddonName)
    if event == "ADDON_LOADED" and loadedAddonName == addonName then
        InitializeAddonDB()
        RestoreStrandedDialogVolume()
        if questReaderLauncher then
            icon:Register("QuestReaderAddon", questReaderLauncher, {
                hide = not QuestReaderAddonDB.showMinimapButton,
                position = QuestReaderAddonDB.minimapIconPosition
            })
            C_Timer.After(0.5, function()
                UpdateMinimapButtonVisibility()
                local minimapButton = icon:GetMinimapButton("QuestReaderAddon")
                if minimapButton then
                    minimapButton:HookScript("OnDragStop", function()
                        local point, _, relPoint, x, y = minimapButton:GetPoint()
                        QuestReaderAddonDB.minimapIconPosition = {
                            point = point,
                            relPoint = relPoint,
                            x = x,
                            y = y
                        }
                    end)
                end
            end)
        else
            print("Error: questReaderLauncher is nil")
        end
        loadingFrame:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        -- All addons should now be loaded, call DetectSoundPacks safely here
        DetectSoundPacks()
        -- Held back so it is not lost in the wall of text every other addon
        -- prints at login.
        if addon.HarvestRemindIfLarge then
            C_Timer.After(10, addon.HarvestRemindIfLarge)
        end
        -- Both events this frame exists for have now fired once, and neither
        -- fires again in a way this addon cares about.
        loadingFrame:UnregisterEvent("PLAYER_LOGIN")
    end
end)
-- Quest frame buttons are created from InitializeQuestFrameButtons on
-- ADDON_LOADED. Creating them at file scope as well produced a second,
-- identical button stacked on the first under the same global name.
local questButtonFrame = CreateFrame("Frame")
questButtonFrame:RegisterEvent("ADDON_LOADED")

-- Kept so the settings toggle can show and hide them after creation.
addon.questButtons = {}

local function UpdateQuestButtonVisibility()
    local show = QuestReaderAddonDB.showQuestButton
    for _, button in ipairs(addon.questButtons) do
        if show then button:Show() else button:Hide() end
    end
end
addon.UpdateQuestButtonVisibility = UpdateQuestButtonVisibility

local function InitializeQuestFrameButtons()
    -- Create the button for the QuestFrame
    local questFrameButton = CreateFrame("Button", "QuestReaderButtonFrame", QuestFrame, "UIPanelButtonTemplate")
    questFrameButton:SetSize(90, 21)
    questFrameButton:SetText("Read Quest")
    questFrameButton:SetPoint("BOTTOMRIGHT", QuestFrame, "BOTTOMRIGHT", -120, 4)

    questFrameButton:SetScript("OnClick", function()
        PlayQuestAudio(nil, true)
    end)
    table.insert(addon.questButtons, questFrameButton)

    -- Create the button for the Quest Log (QuestMapFrame)
    if QuestMapFrame and QuestMapFrame.DetailsFrame then
        local questLogButton = CreateFrame("Button", "QuestLogReaderButtonFrame", QuestMapFrame.DetailsFrame, "UIPanelButtonTemplate")
        questLogButton:SetSize(90, 21)
        questLogButton:SetText("Read Quest")
        -- Position it at the top left of the details frame, offset to the right to be next to Back button
        questLogButton:SetPoint("TOPLEFT", QuestMapFrame.DetailsFrame, "TOPLEFT", 105, -10)

        questLogButton:SetScript("OnClick", function()
            PlayQuestAudio("description", true)
        end)
        table.insert(addon.questButtons, questLogButton)
    end

    UpdateQuestButtonVisibility()
end

questButtonFrame:SetScript("OnEvent", function(self, event, loadedAddonName)
    if loadedAddonName == addonName then
        InitializeQuestFrameButtons()
        questButtonFrame:UnregisterEvent("ADDON_LOADED")
    end
end)

-- Slash command to toggle minimap button
SLASH_QRTOGGLE1, SLASH_QRTOGGLE2 = '/qrtoggle', '/sstoggle'
SlashCmdList["QRTOGGLE"] = function()
    QuestReaderAddonDB.showMinimapButton = not QuestReaderAddonDB.showMinimapButton
    UpdateMinimapButtonVisibility()
    print("SpeakStone minimap button: " .. (QuestReaderAddonDB.showMinimapButton and "|cff00ff00shown|r" or "|cffff0000hidden|r"))
end

-- Load one of the legacy named packs and hand back its duration table, along
-- with the folder name the client knows it by -- which is what the sound
-- paths are built from, so it is taken from the client rather than assumed to
-- match the name we asked for.
local function LoadSoundPackIfAvailable(packName)
    local name, _, _, loadable = C_AddOns.GetAddOnInfo(packName)
    if not name or not loadable then
        return nil
    end
    if not C_AddOns.IsAddOnLoaded(packName) and not C_AddOns.LoadAddOn(packName) then
        return nil
    end
    return _G[packName], name
end

-- addon.soundSources is initialised at file scope, above, so it exists
-- before ADDON_LOADED fires and a pack that self-registers early has
-- somewhere to land.
addon.activeSound = nil
-- Quest audio the player has encountered that no installed pack provides.
addon.reportedMissing = {}
-- The passage type of the last quest panel seen. Declared here, empty, so the
-- "Read Quest" button has something valid to fall back on before any quest
-- panel has been shown. It used to be assigned from an out-of-scope variable
-- at the bottom of the file, which made it nil and turned a click with no
-- panel open into a "concatenate a nil value" error.
local lastTextType = ""

-- Everything derived from the installed packs, from one walk over them.
--
-- Walking every clip in every pack is the single most expensive thing this
-- addon does -- around 34,000 clips with today's packs and growing with every
-- expansion -- and it was being done twice over: once here for the settings
-- dashboard's counts, and again in QuestAudioLibraryUI's own index for the
-- library list, each with its own string match per clip. Both answers come
-- out of the same pass now, and both are dropped together when a pack
-- registers. The two used to derive the quest count with slightly different
-- patterns, so the dashboard and the library could disagree about how many
-- quests were voiced; sharing the pass makes that impossible.
local function BuildAudioIndex()
    local index = addon.audioIndex
    if index then return index end

    local packs, clips = {}, 0
    local quests, questCount = {}, 0
    for packName, soundLengths in pairs(addon.soundSources or {}) do
        if type(soundLengths) == "table" then
            local packClips = 0
            for soundFile in pairs(soundLengths) do
                packClips = packClips + 1
                -- "<questID>_<passage>.<ext>". Gossip and book clips are named
                -- "npc<id>_..." and "item<id>_...", so they do not match here
                -- and stay out of the quest library, which is what we want.
                local questID, passage = soundFile:match("^(%d+)_(%a+)%.")
                if questID then
                    local id = tonumber(questID)
                    if id then
                        local entry = quests[id]
                        if not entry then
                            -- idStr is kept rather than rebuilt with tostring
                            -- in the library's search filter, which compared
                            -- against it once per quest on every pass.
                            entry = { id = id, idStr = questID, types = {} }
                            quests[id] = entry
                            questCount = questCount + 1
                        end
                        entry.types[passage] = true
                    end
                end
            end
            if packClips > 0 then
                table.insert(packs, { name = packName, clips = packClips })
                clips = clips + packClips
            end
        end
    end
    table.sort(packs, function(a, b) return a.name < b.name end)

    index = { packs = packs, clips = clips, quests = quests, questCount = questCount }
    addon.audioIndex = index
    return index
end
addon.GetAudioIndex = BuildAudioIndex

-- How much audio is actually installed, and where it came from. The settings
-- panel shows this: "no audio for this quest" and "no packs installed at all"
-- look identical from the player's side otherwise.
function addon.GetInstalledAudioSummary()
    local index = BuildAudioIndex()
    return index.packs, index.clips, index.questCount
end

-- Function to detect available sound packs
function DetectSoundPacks()
    local registered = false

    for _, depName in ipairs(optionalSoundPacks) do
        -- LoadSoundPackIfAvailable asks the client whether the pack is
        -- loadable itself; asking here as well meant two GetAddOnInfo calls
        -- per pack for one answer.
        local pack, name = LoadSoundPackIfAvailable(depName)
        if pack then
            -- Merge rather than replace: overwriting dropped the sounds
            -- bundled with the base addon, and breaking here meant only
            -- one language pack could ever be active at a time.
            addon.soundSources[name or depName] = pack
            registered = true
        end
    end

    -- Once, after the loop. Invalidating per pack threw away an index that
    -- the next pack in the same loop would only have had to rebuild.
    if registered then
        InvalidateAudioCaches()
    end
end

local function GetCurrentSound()
    return addon.activeSound
end

-- The one place a clip is looked up, for all three playback paths. Returns
-- the file name, its full path, and the clip's length -- which is the value
-- SoundLengths stores against each file, and the only thing that can tell
-- this addon when playback has finished.
--
-- Callers pass their candidate base names in preference order; books have
-- several (item ID, then two name-derived shapes), quests and gossip one.
local function FindSound(baseNames)
    for _, baseName in ipairs(baseNames) do
        for _, extension in ipairs(SOUND_EXTENSIONS) do
            local candidate = baseName .. extension
            for packName, soundLengths in pairs(addon.soundSources) do
                if type(soundLengths) == "table" and soundLengths[candidate] then
                    return candidate,
                        "Interface\\AddOns\\" .. packName .. "\\Sounds\\" .. candidate,
                        tonumber(soundLengths[candidate])
                end
            end
        end
    end
end
-- The audio library looks clips up too, and had its own copy of this walk in
-- two places. One lookup means one set of rules about extension order and
-- pack precedence.
addon.FindSound = FindSound

-- The clip has run its course, or never started. Distinct from
-- StopCurrentSound, which interrupts one: there is no handle left to stop
-- here. The identity check keeps a late timer from tearing down whatever
-- clip has since replaced the one it was scheduled for.
local function FinishPlayback(soundData)
    if addon.activeSound ~= soundData then
        return
    end
    soundData.isPlaying = false
    soundData.endTimer = nil
    addon.activeSound = nil
    UnmuteDialogChannel()
end

-- Longest a clip is assumed to run when its pack does not record a length.
-- Only ever used to release the Dialog channel, so it is not a cutoff:
-- nothing here can stop a clip early, and one that is still going at two
-- minutes has outlasted anything the packs contain.
local MAX_CLIP_SECONDS = 120

local function DoPlaySound(soundData)
    soundData = soundData or GetCurrentSound()
    -- Identity-checked, not just non-nil. A delayed clip whose timer outlived
    -- it -- the player clicked on to the next panel while it was still
    -- waiting -- used to reach here and play whatever had replaced it, which
    -- then played again on its own timer: the same line twice over, with the
    -- first handle overwritten so nothing could stop it.
    if not soundData or addon.activeSound ~= soundData then
        return
    end

    local audioChannel = "Dialog"
    if QuestReaderAddonDB.muteGossip then
        MuteDialogChannel()
        audioChannel = "Master"
    end

    soundData.isPlaying, soundData.soundHandle = PlaySoundFile(soundData.soundPath, audioChannel)

    if not soundData.soundHandle then
        DebugPrint("Failed to play audio: " .. tostring(soundData.soundFile))
        -- Nothing is playing, so nothing will ever finish. Release the
        -- channel now rather than leaving Dialog muted under silence.
        FinishPlayback(soundData)
        return
    end

    -- Nothing tells an addon when a PlaySoundFile clip ends. Without this the
    -- sound stayed "playing" for the rest of the session: every later play
    -- called StopSound on a dead handle, and with "silence Blizzard's voice
    -- lines" on, the Dialog channel stayed at zero until the next narration
    -- or logout -- which, with "stop narration when the window closes" off,
    -- meant the player's dialogue simply never came back. The duration is
    -- already in SoundLengths; a small margin covers rounding in it.
    --
    -- Scheduled even when the length is missing or unreadable. Skipping it
    -- there reached that same dead end by another route: nothing ever
    -- finished the clip, so activeSound stayed set for the session and the
    -- Dialog channel stayed muted under it.
    local duration = soundData.duration
    if not duration or duration <= 0 then
        duration = MAX_CLIP_SECONDS
    end
    soundData.endTimer = C_Timer.NewTimer(duration + 0.25, function()
        FinishPlayback(soundData)
    end)
end

local function IsPlaying()
    local currentSound = GetCurrentSound()
    return currentSound and currentSound.isPlaying
end
addon.IsPlaying = IsPlaying

local function StopCurrentSound()
    local currentSound = GetCurrentSound()

    if not currentSound then
        return
    end

    if currentSound.nextSoundTimer then
        currentSound.nextSoundTimer:Cancel()
    end
    if currentSound.endTimer then
        currentSound.endTimer:Cancel()
    end

    if currentSound.soundHandle then
        StopSound(currentSound.soundHandle)
    end

    -- Unconditionally: the setting can be turned off while a clip is
    -- playing, and gating on it left the Dialog channel muted for the rest
    -- of the session.
    UnmuteDialogChannel()

    addon.activeSound = nil
end
addon.StopCurrentSound = StopCurrentSound

-- Capture for a passage that had no audio. The recording itself lives in
-- Harvester.lua, which captures every quest encountered; this only marks
-- the ones that were gaps, so /qrmissing can export just those without
-- keeping a second copy of the same text.
local MISSING_QUEST_TEXT_GETTERS = {
    description = GetQuestText,
    progress = GetProgressText,
    completion = GetRewardText,
}

local function CaptureMissingQuestAudio(questID, textType)
    local getter = MISSING_QUEST_TEXT_GETTERS[textType]
    if not getter or not addon.HarvestRecordPassage then
        return
    end
    -- Respects the capture toggle: a player who turned harvesting off
    -- should not have text quietly recorded by this path either.
    if not (addon.HarvestEnabled and addon.HarvestEnabled()) then
        return
    end
    local ok, text = pcall(getter)
    if ok and text and text ~= "" then
        addon.HarvestRecordPassage(questID, textType, text, true)
    end
end

-- Global on purpose: Bindings.xml calls this by name. Everything else that
-- used to sit in the global namespace alongside it now lives on addon.
function PlayQuestAudio(textType, skipDelay)
    -- Get quest ID from Quest Log if it's open, otherwise from quest giver
    local questID
    if QuestFrame and QuestFrame:IsVisible() then
        questID = GetQuestID()
    elseif QuestMapFrame and QuestMapFrame:IsVisible() then
        questID = C_QuestLog.GetSelectedQuest()
    else
        questID = GetQuestID()
    end

    if not textType then
        -- Initialize textType based on visible panels
        if QuestFrameDetailPanel and QuestFrameDetailPanel:IsVisible() then
            textType = "description"
        elseif QuestFrameProgressPanel and QuestFrameProgressPanel:IsVisible() then
            textType = "progress"
        elseif QuestFrameRewardPanel and QuestFrameRewardPanel:IsVisible() then
            textType = "completion"
        -- Gossip has its own playback path, PlayGossipAudio: it has no
        -- questID to key on, so it cannot share this function's lookup.
        else
            textType = lastTextType
            if not textType or textType == "" then
                return
            end
        end
    end

    if not textType or textType == "" then
        return
    end

    -- Debug: Ensure questID and textType are valid
    if questID and textType ~= "" then
        -- Unconditionally, not only when something is audible. A clip still
        -- waiting out the autoplay delay is not "playing", so gating on that
        -- left its timer running to fire over whatever came next.
        StopCurrentSound()

        -- Newly generated audio ships as Ogg Vorbis, which is a fraction of the
        -- size of the original PCM library and is what the game itself uses.
        -- Both are accepted so a pack can mix them while it is converted over.
        local baseName = questID .. "_" .. textType
        local soundFile, soundPath, duration = FindSound({ baseName })

        if not soundPath then
            -- Report the gap so players can tell "not recorded yet" apart from
            -- a broken addon, and can report the ID. Deduplicated per session so
            -- autoplay does not repeat the same line on every quest interaction.
            if not addon.reportedMissing[baseName] then
                addon.reportedMissing[baseName] = true
                DebugPrint("SpeakStone: no audio for quest " .. questID .. " (" .. textType .. ")")
            end
            -- Capture the text itself, not just the fact that it is missing,
            -- so it is ready to submit whether or not this player ever runs
            -- the separate Harvester addon.
            CaptureMissingQuestAudio(questID, textType)
            addon.activeSound = nil
            return
        end

        local soundData = {
            questID = questID,
            textType = textType,
            soundFile = soundFile,
            soundPath = soundPath,
            duration = duration,
        }
        addon.activeSound = soundData

        -- Delay shortly to account for greeting audio when using autoplay
        if QuestReaderAddonDB.autoPlayEnabled and not skipDelay and not QuestReaderAddonDB.muteGossip then
            local delay = tonumber(QuestReaderAddonDB.autoPlayDelay) or 2
            -- NewTimer, not After: After returns nothing, so the handle
            -- stored here was always nil and StopCurrentSound's Cancel never
            -- ran. A queued clip then fired after the player had walked away.
            -- The clip is passed in rather than read back out of activeSound,
            -- so a timer that survives its own cancellation plays nothing
            -- instead of playing its successor.
            soundData.nextSoundTimer = C_Timer.NewTimer(delay, function()
                DoPlaySound(soundData)
            end)
        else
            DoPlaySound(soundData)
        end
    end
end

local function IsSecret(val)
    if val == nil then return false end
    if issecretvalue and issecretvalue(val) then return true end
    if SecretUtil and SecretUtil.IsSecretValue and SecretUtil.IsSecretValue(val) then return true end
    return false
end

-- "Creature-0-<server>-<instance>-<zone>-<creatureID>-<spawn>"
-- Mirrors the harvester's own copy: the two never load together, so sharing
-- code between them is not an option without a third file just for this.
local function CreatureIDFromGUID(guid)
    if not guid or IsSecret(guid) or type(guid) ~= "string" then
        return nil
    end
    local ok, unitType, _, _, _, _, creatureID = pcall(strsplit, "-", guid)
    if ok and (unitType == "Creature" or unitType == "Vehicle") then
        return tonumber(creatureID)
    end
    return nil
end

local function PlayGossipAudio()
    local guid = UnitGUID("npc")
    if not guid or IsSecret(guid) then
        return
    end

    local npcID = CreatureIDFromGUID(guid)
    if not npcID or IsSecret(npcID) then
        return
    end

    -- Also clears a clip still waiting out the autoplay delay; see the quest
    -- path above.
    StopCurrentSound()

    -- An NPC can have several greeting variants, captured as gossip1,
    -- gossip2, and so on, but nothing here can tell which one the server
    -- just chose to show -- SoundLengths carries only a duration per file,
    -- not the text it was generated from. The first captured variant plays
    -- regardless. NPCs with a single greeting, the common case, are
    -- unaffected; NPCs with several will sometimes say the wrong line until
    -- variant matching is built.
    local baseName = "npc" .. npcID .. "_gossip1"
    local soundFile, soundPath, duration = FindSound({ baseName })

    if not soundPath then
        -- Same dedup as the quest path: report once per session, not once
        -- per NPC interaction.
        if not addon.reportedMissing[baseName] then
            addon.reportedMissing[baseName] = true
            DebugPrint("SpeakStone: no gossip audio for NPC " .. npcID)
        end
        addon.activeSound = nil
        return
    end

    local soundData = {
        questID = "npc" .. npcID,
        textType = "gossip",
        soundFile = soundFile,
        soundPath = soundPath,
        duration = duration,
    }
    addon.activeSound = soundData
    DoPlaySound(soundData)
end

local currentItemName = nil
local currentItemPage = 1
local itemAudioTimer = nil

local function PlayItemAudioDirect(itemLink, page)
    -- Also clears a clip still waiting out the autoplay delay; see the quest
    -- path above.
    StopCurrentSound()

    page = page or 1
    local itemID
    if itemLink then
        pcall(function()
            itemID = tonumber(itemLink:match("item:(%d+)"))
        end)
    end
    local baseNames = {}

    if itemID then
        table.insert(baseNames, "item" .. itemID .. "_page" .. page)
    elseif itemLink then
        local clean
        local ok = pcall(function()
            clean = itemLink:lower():gsub("[^%w%s]", ""):gsub("%s+", "_")
        end)
        if ok and clean and clean ~= "" then
            table.insert(baseNames, "item_" .. clean .. "_page" .. page)
            table.insert(baseNames, clean .. "_page" .. page)
        end
    end

    if #baseNames == 0 then
        return
    end

    local soundFile, soundPath, duration = FindSound(baseNames)

    if not soundPath then
        local displayName = itemID and ("item " .. itemID) or ("'" .. itemLink .. "'")
        local reportKey = baseNames[1]
        if not addon.reportedMissing[reportKey] then
            addon.reportedMissing[reportKey] = true
            DebugPrint("SpeakStone: no audio for " .. displayName .. " (page " .. page .. ")")
        end
        addon.activeSound = nil
        return
    end

    local soundData = {
        questID = baseNames[1],
        textType = "item",
        soundFile = soundFile,
        soundPath = soundPath,
        duration = duration,
    }
    addon.activeSound = soundData
    DebugPrint("SpeakStone: playing " .. (itemID and ("item " .. itemID) or ("'" .. itemLink .. "'")) .. " (page " .. page .. ")")
    DoPlaySound(soundData)
end

-- Defined below, but hooked from here. A forward declaration rather than a
-- global, which is what let the hook reach it before.
local PlayItemAudio

local function HookDialogueUI()
    if DUIBookFrame and not addon.duiHooked then
        if type(DUIBookFrame.ScrollToPage) == "function" and type(DUIBookFrame.ScrollTo) == "function" then
            addon.duiHooked = true
            hooksecurefunc(DUIBookFrame, "ScrollToPage", function(self, page)
                if self:IsShown() and page and page > 0 and page ~= currentItemPage and currentItemName then
                    PlayItemAudio(page)
                end
            end)
            hooksecurefunc(DUIBookFrame, "ScrollTo", function(self, offset)
                if self:IsShown() and offset == 0 and currentItemPage ~= 1 and currentItemName then
                    PlayItemAudio(1)
                end
            end)
        end
    end
end

function PlayItemAudio(page)
    local itemLink = ItemTextGetItem()
    if not itemLink or itemLink == "" then
        if DUIBookFrame and DUIBookFrame.Header and DUIBookFrame.Header.Title then
            pcall(function()
                itemLink = DUIBookFrame.Header.Title:GetText()
            end)
        end
    end
    if not itemLink or itemLink == "" then
        return
    end

    HookDialogueUI()

    -- Explicit page requested (e.g. user clicked page 1, 2, 3, 4 tab or scrolled)
    if page then
        currentItemPage = page
        currentItemName = itemLink
        if itemAudioTimer then
            itemAudioTimer:Cancel()
            itemAudioTimer = nil
        end
        PlayItemAudioDirect(itemLink, page)
        return
    end

    -- Initial opening event from game: always start on Page 1
    if itemLink ~= currentItemName then
        currentItemName = itemLink
        currentItemPage = 1

        if itemAudioTimer then
            itemAudioTimer:Cancel()
            itemAudioTimer = nil
        end

        -- Cancellable, for the same reason as the quest delay above.
        itemAudioTimer = C_Timer.NewTimer(0.1, function()
            itemAudioTimer = nil
            if currentItemName == itemLink then
                PlayItemAudioDirect(itemLink, 1)
            end
        end)
    else
        -- Standard Blizzard UI (without DialogueUI)
        if not DUIBookFrame or not DUIBookFrame:IsShown() then
            local p = ItemTextGetPage() or 1
            if p ~= currentItemPage then
                currentItemPage = p
                PlayItemAudioDirect(itemLink, p)
            end
        end
    end
end

-- The saved Dialog volume, held while narration is muting the channel.
-- A global here meant any other addon writing the same name could strand the
-- player's dialogue at zero.
local originalDialogVolume = nil

addon.PlayQuestAudio = PlayQuestAudio
addon.PlayGossipAudio = PlayGossipAudio
addon.PlayItemAudio = PlayItemAudio

local function OnPlayerLogout()
    local currentSound = GetCurrentSound()
    if currentSound then
        if currentSound.nextSoundTimer then
            currentSound.nextSoundTimer:Cancel()
        end
        if currentSound.endTimer then
            currentSound.endTimer:Cancel()
        end
    end
    UnmuteDialogChannel()
end

-- Keybindings
BINDING_HEADER_QUESTREADERADDON = "SpeakStone"
BINDING_NAME_PLAYACTIVEQUEST = "Play active quest voiceover"

-- Event Handling for Quest Dialog Events
local questEventFrame = CreateFrame("Frame")
questEventFrame:RegisterEvent("ADDON_LOADED")
questEventFrame:RegisterEvent("QUEST_DETAIL")
questEventFrame:RegisterEvent("QUEST_PROGRESS")
questEventFrame:RegisterEvent("QUEST_COMPLETE")
questEventFrame:RegisterEvent("QUEST_FINISHED")
questEventFrame:RegisterEvent("GOSSIP_SHOW")
questEventFrame:RegisterEvent("GOSSIP_CLOSED")
questEventFrame:RegisterEvent("ITEM_TEXT_READY")
questEventFrame:RegisterEvent("ITEM_TEXT_CLOSED")

questEventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        HookDialogueUI()
        -- ADDON_LOADED keeps firing for every on-demand addon the client
        -- loads all session. The hook is the only reason to listen, so once
        -- it is installed there is nothing left to wait for.
        if addon.duiHooked then
            self:UnregisterEvent("ADDON_LOADED")
        end
        return
    end
    -- Gossip and Items have no questID and their own lookup, so they are handled before
    -- anything below assumes one exists.
    if event == "GOSSIP_SHOW" then
        if AutoPlayAllowed("autoPlayGossip") then
            PlayGossipAudio()
        end
        return
    elseif event == "GOSSIP_CLOSED" then
        if QuestReaderAddonDB.stopDialogueOnClose then
            StopCurrentSound()
        end
        return
    elseif event == "ITEM_TEXT_READY" then
        if AutoPlayAllowed("autoPlayItemText") then
            PlayItemAudio()
        end
        return
    elseif event == "ITEM_TEXT_CLOSED" then
        currentItemName = nil
        currentItemPage = 1
        if itemAudioTimer then
            itemAudioTimer:Cancel()
            itemAudioTimer = nil
        end
        if QuestReaderAddonDB.stopDialogueOnClose then
            StopCurrentSound()
        end
        return
    end

    -- Map event to appropriate textType
    local textType = ""
    if event == "QUEST_DETAIL" then
        textType = "description"
    elseif event == "QUEST_PROGRESS" then
        textType = "progress"
    elseif event == "QUEST_COMPLETE" then
        textType = "completion"
    end

    if textType ~= "" and AutoPlayAllowed("autoPlayQuests") then
        if QuestMapFrame and QuestMapFrame:IsVisible() and not (QuestFrame and QuestFrame:IsVisible()) then
            if not QuestReaderAddonDB.autoPlayInQuestMap then
                lastTextType = textType
                return
            end
        end
        PlayQuestAudio(textType)  -- Call PlayQuestAudio with textType from event
    elseif event == "QUEST_FINISHED" and QuestReaderAddonDB.stopDialogueOnClose then
        StopCurrentSound() -- Stop sound when the quest dialog finishes
    end

    lastTextType = textType
end)

local logoutFrame = CreateFrame("Frame")
logoutFrame:RegisterEvent("PLAYER_LOGOUT")
logoutFrame:SetScript("OnEvent", OnPlayerLogout)

-- Slash command to toggle auto-play
SLASH_QUESTREADERAUTO1, SLASH_QUESTREADERAUTO2, SLASH_QUESTREADERAUTO3 = '/qrauto', '/ssauto', '/speakstoneauto'
SlashCmdList["QUESTREADERAUTO"] = function(msg)
    if msg == "on" then
        QuestReaderAddonDB.autoPlayEnabled = true
    elseif msg == "off" then
        QuestReaderAddonDB.autoPlayEnabled = false
    else
        QuestReaderAddonDB.autoPlayEnabled = not QuestReaderAddonDB.autoPlayEnabled
    end
    print("SpeakStone Auto-Play: " .. (QuestReaderAddonDB.autoPlayEnabled and "Enabled" or "Disabled"))
end

-- Slash command to toggle debug messages
SLASH_QUESTREADERDEBUG1, SLASH_QUESTREADERDEBUG2, SLASH_QUESTREADERDEBUG3 = '/qrdebug', '/ssdebug', '/speakstonedebug'
SlashCmdList["QUESTREADERDEBUG"] = function(msg)
    if msg == "on" then
        QuestReaderAddonDB.showDebugMessages = true
    elseif msg == "off" then
        QuestReaderAddonDB.showDebugMessages = false
    else
        QuestReaderAddonDB.showDebugMessages = not QuestReaderAddonDB.showDebugMessages
    end
    print("SpeakStone Debug Messages: " .. (QuestReaderAddonDB.showDebugMessages and "Enabled" or "Disabled"))
end

-- The export window, built the first time it is asked for. It used to be
-- created at file scope: a frame, a scroll frame, an edit box, a button and
-- two font strings put together on every login for a window most players
-- open rarely and many never do.
local exportFrame, exportEditBox

local function EnsureExportFrame()
    if exportFrame then
        return exportFrame, exportEditBox
    end

    local frame = CreateFrame("Frame", "QuestReaderMissingCopyFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(560, 440)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:Hide()
    -- Escape closes it like every other addon window. Previously only the edit
    -- box handled Escape, so clicking anywhere else in the frame first left the
    -- player with no way out but the X.
    tinsert(UISpecialFrames, "QuestReaderMissingCopyFrame")

    frame.TitleText:SetText("Captured Text -- Export to Submit")

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame.InsetBg, "TOPLEFT", 5, -5)
    -- The scroll area has to end above the button row, or the two overlap.
    scrollFrame:SetPoint("BOTTOMRIGHT", frame.InsetBg, "BOTTOMRIGHT", -27, 34)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetSize(scrollFrame:GetSize())
    editBox:SetMultiLine(true)
    -- Focus is not taken: the frame opens with everything already selected, and
    -- grabbing focus meant a stray keypress replaced the export the player was
    -- about to copy.
    editBox:SetAutoFocus(false)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    scrollFrame:SetScrollChild(editBox)

    -- One-click re-select, for when the highlight has been lost to a click in
    -- the box. Ctrl+A still works; this is just discoverable.
    local selectAllButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    selectAllButton:SetSize(110, 22)
    selectAllButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 8)
    selectAllButton:SetText("Select All")
    selectAllButton:SetScript("OnClick", function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)

    -- A long-running capture serialises to more than one edit box should be
    -- asked to hold, so the payload arrives in pieces and these step between
    -- them. Each piece is a complete export on its own -- see
    -- HarvestExportBatches -- so a player who pastes only the first has still
    -- sent something whole.
    local nextButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    nextButton:SetSize(58, 22)
    nextButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 8)
    nextButton:SetText("Next >")

    local partText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    partText:SetWidth(96)
    partText:SetJustifyH("CENTER")
    partText:SetPoint("RIGHT", nextButton, "LEFT", -4, 0)

    local prevButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    prevButton:SetSize(58, 22)
    prevButton:SetPoint("RIGHT", partText, "LEFT", -4, 0)
    prevButton:SetText("< Prev")

    local copyHintText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    copyHintText:SetPoint("LEFT", selectAllButton, "RIGHT", 10, 0)
    copyHintText:SetPoint("RIGHT", prevButton, "LEFT", -8, 0)
    copyHintText:SetJustifyH("LEFT")

    -- Put one piece in the box, ready to copy.
    function frame:ShowBatch(index)
        local batches = self.batches or {}
        local total = #batches
        if total == 0 then return end
        index = math.max(1, math.min(index or 1, total))
        self.batchIndex = index

        editBox:SetText(batches[index])
        editBox:SetCursorPosition(0)
        editBox:HighlightText()

        if total > 1 then
            partText:SetText(string.format("Part %d of %d", index, total))
            partText:Show()
            prevButton:Show()
            nextButton:Show()
            if index > 1 then prevButton:Enable() else prevButton:Disable() end
            if index < total then nextButton:Enable() else nextButton:Disable() end
            copyHintText:SetText("Ctrl+C, paste at |cff00ccffspeakstone.beanw.co.uk|r, then Next")
        else
            partText:Hide()
            prevButton:Hide()
            nextButton:Hide()
            copyHintText:SetText("Ctrl+C, then paste at |cff00ccffspeakstone.beanw.co.uk|r")
        end
    end

    prevButton:SetScript("OnClick", function() frame:ShowBatch((frame.batchIndex or 1) - 1) end)
    nextButton:SetScript("OnClick", function() frame:ShowBatch((frame.batchIndex or 1) + 1) end)

    exportFrame, exportEditBox = frame, editBox
    return frame, editBox
end

-- Slash command to export the text captured for quests the installed sound
-- packs have no audio for, ready to paste into the website's submit form --
-- see the missing-quest capture block above PlayQuestAudio.
-- Shared window for both export commands. addon.ShowHarvestExport is what
-- the launcher's right-click and the settings panel call, so all three routes
-- put up the same frame rather than each building their own.
function addon.ShowHarvestExport()
    if not addon.HarvestExportBatches then
        print("SpeakStone: capture module not loaded.")
        return
    end
    local batches, count = addon.HarvestExportBatches()
    if count == 0 then
        if not (addon.HarvestEnabled and addon.HarvestEnabled()) then
            -- Only say this when it is actually true. Blaming the setting
            -- while capture was running sent people to toggle a switch that
            -- was already on.
            print("SpeakStone: text capture is switched off -- turn it back on in settings, or with '/ssharvest on'.")
        else
            print("SpeakStone: nothing captured yet. Talk to an NPC or pick up a quest and it records automatically.")
        end
        return
    end

    -- The player has the payload in front of them now, so the reminder clock
    -- starts again regardless of what they do with it.
    if addon.HarvestMarkOffered then
        addon.HarvestMarkOffered()
    end

    local frame = EnsureExportFrame()
    frame.batches = batches
    frame:Show()
    frame:Raise()
    frame:ShowBatch(1)

    if #batches > 1 then
        -- Said plainly, because a player who copies the first box and stops
        -- would otherwise never know the rest existed. Each piece stands on
        -- its own, so stopping early costs only what is left, not the lot.
        print("SpeakStone: " .. count .. " entry(s) ready -- quests, greetings and books."
            .. " Too much for one paste, so it is in " .. #batches .. " parts:"
            .. " copy this one to speakstone.beanw.co.uk, then click Next and repeat.")
    else
        print("SpeakStone: " .. count .. " entry(s) ready -- quests, greetings and books. Ctrl+A, Ctrl+C, then paste at speakstone.beanw.co.uk to submit.")
    end
end

-- There is one export now, and this is an alias for it. The command used to
-- produce a quests-only subset; keeping the name working matters more than
-- retiring it, since it is the one printed in the README and in chat.
SLASH_QUESTREADERMISSING1, SLASH_QUESTREADERMISSING2, SLASH_QUESTREADERMISSING3 = '/qrmissing', '/ssmissing', '/speakstonemissing'
SlashCmdList["QUESTREADERMISSING"] = function()
    addon.ShowHarvestExport()
end

-- Everything captured: quests, gossip and book text, voiced or not. Not
-- registered if the standalone Harvester addon is loaded -- it claims these
-- same command names, and whichever loaded second would silently win.
if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("QuestReaderHarvester")) then
    SLASH_QUESTREADERHARVEST1, SLASH_QUESTREADERHARVEST2, SLASH_QUESTREADERHARVEST3 = '/qrharvest', '/ssharvest', '/speakstoneharvest'
    SlashCmdList["QUESTREADERHARVEST"] = function(msg)
        if msg == "export" or msg == "copy" then
            addon.ShowHarvestExport()
            return
        elseif msg == "wipe" or msg == "clear" then
            addon.HarvestWipe()
            print("SpeakStone: captured text cleared.")
            return
        elseif msg == "on" or msg == "off" then
            QuestReaderAddonDB.harvestEnabled = (msg == "on")
            print("SpeakStone: text capture " .. (msg == "on" and "enabled" or "disabled") .. ".")
            return
        end

        local quests, passages, unvoiced, npcs, lines, items, pages = addon.HarvestCounts()
        print("SpeakStone capture: " .. (QuestReaderAddonDB.harvestEnabled and "|cff00ff00on|r" or "|cffff0000off|r"))
        -- Greetings and book text first: neither exists in the client's own
        -- files nor anywhere scrapeable, so capture is the only way they can
        -- ever be obtained. Quest text can at least be sourced elsewhere.
        print("  " .. npcs .. " NPC(s), " .. lines .. " greeting line(s).")
        print("  " .. items .. " book(s)/plaque(s), " .. pages .. " page(s).")
        print("  " .. quests .. " quest(s), " .. passages .. " passage(s).")
        if unvoiced > 0 then
            -- A passage with no creature ID cannot be matched to a voice later.
            print("  " .. unvoiced .. " passage(s) have no NPC recorded (offered by an object or auto-accepted).")
        end
        print("  '/ssharvest export' to copy it all out, then paste at speakstone.beanw.co.uk.")
    end
end

-- The minimap button's position is saved by the OnDragStop hook installed
-- after icon:Register, up in the ADDON_LOADED handler. A second copy used to
-- sit here at file scope, where the button does not exist yet, so it never
-- hooked anything -- and it captured only GetPoint's first return into one
-- local before unpacking it into four fields, which would have stored a point
-- and three nils had it ever run.

-- Function to mute the dialog channel
function MuteDialogChannel()
    -- Check if the original volume has already been saved
    if not originalDialogVolume then
        -- Get the current dialog volume and store it
        originalDialogVolume = GetCVar("Sound_DialogVolume")
        -- And store it to disk as well. SetCVar writes through to the
        -- client's config, so the in-memory copy alone was lost to a crash
        -- or a disconnect, stranding the player's dialogue at zero with
        -- nothing to explain it. See RestoreStrandedDialogVolume.
        if QuestReaderAddonDB then
            QuestReaderAddonDB.savedDialogVolume = originalDialogVolume
        end
    end

    -- Set the dialog volume to 0 (mute)
    SetCVar("Sound_DialogVolume", 0)
end

-- Function to unmute the dialog channel
function UnmuteDialogChannel()
    if originalDialogVolume then
        -- Restore the original volume
        SetCVar("Sound_DialogVolume", originalDialogVolume)

        -- Clear the original volume to avoid accidental overwriting in future
        originalDialogVolume = nil
    end
    -- Cleared even when nothing was held in memory: the saved copy is only
    -- ever a rescue for a session that did not get here.
    if QuestReaderAddonDB then
        QuestReaderAddonDB.savedDialogVolume = nil
    end
end
