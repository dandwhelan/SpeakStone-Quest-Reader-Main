-- Quest/gossip/book text capture, built into the base addon.
--
-- This began life as a separate companion addon
-- (tools/QuestReaderHarvester/) and is now folded in here, because asking a
-- player to find and install a second addon to contribute the one thing the
-- project most needs was a poor trade. It is on by default and can be turned
-- off in the settings panel.
--
-- Why capture at all: quest description/progress/completion text is delivered
-- by the server at runtime and exists nowhere in the files Blizzard ships, so
-- the only ways to get it are to read it off a live client or scrape a site
-- that already did. Gossip text is worse -- there is no gossip-text table in
-- the client either, and no scrapeable equivalent, so it can *only* come from
-- capture like this.
--
-- The standalone addon still exists and still works. If someone has it
-- installed and enabled, this module stands down entirely rather than both
-- recording the same lines into two different stores.

local addonName, addon = ...

local QUEST_PASSAGES = { "description", "progress", "completion" }

local function DebugPrint(...)
    if addon.DebugPrint then addon.DebugPrint(...) end
end

-- The standalone companion addon, if the player still has it, owns capture.
local function StandaloneActive()
    return C_AddOns and C_AddOns.IsAddOnLoaded
        and C_AddOns.IsAddOnLoaded("QuestReaderHarvester")
end

local function Enabled()
    return QuestReaderAddonDB and QuestReaderAddonDB.harvestEnabled
        and not StandaloneActive()
end
addon.HarvestEnabled = Enabled

local function Store()
    QuestReaderAddonDB.harvest = QuestReaderAddonDB.harvest or {}
    local h = QuestReaderAddonDB.harvest
    h.quests = h.quests or {}
    h.gossip = h.gossip or {}
    h.itemText = h.itemText or {}
    -- Which captured quests had no audio installed at the time. Just a set of
    -- IDs pointing into h.quests, so /qrmissing can export the gaps alone
    -- without a second copy of the same text living in the saved variables.
    h.missingIDs = h.missingIDs or {}
    return h
end
addon.HarvestStore = Store

-- --------------------------------------------------------------------------
-- Secret-value guards. WoW 12.x returns tagged "secret" values where plain
-- strings used to be; touching one throws, so everything from a unit is
-- checked before use.
-- --------------------------------------------------------------------------
local function IsSecret(val)
    if val == nil then return false end
    if issecretvalue and issecretvalue(val) then return true end
    if SecretUtil and SecretUtil.IsSecretValue and SecretUtil.IsSecretValue(val) then return true end
    return false
end

-- "Creature-0-<server>-<instance>-<zone>-<creatureID>-<spawn>"
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

-- Resolve who is actually speaking, or admit that it cannot.
--
-- The "npc" unit token is only meaningful while an interaction is genuinely
-- open, and it is not safe to assume it is. Observed in the wild: with a
-- replacement dialogue addon (DialogueUI and similar) the event can arrive
-- when the unit has already gone, and UnitName("npc") then returned the
-- *player's own* name -- which got recorded as the quest giver. Worse, a
-- stale GUID persisted across several different NPCs, so every gossip line
-- captured in a session collapsed into one creature ID.
--
-- Attributing a line to the wrong NPC is worse than not attributing it: it
-- gets voiced in a stranger's voice and nothing downstream can tell. So each
-- of these checks fails closed, to "unknown speaker", rather than guessing.
local function CurrentSpeaker()
    if not UnitExists("npc") then
        return {}
    end
    -- The decisive one. If "npc" has fallen back to the player, everything
    -- read from it is the player, not the speaker.
    local okUnit, isPlayer = pcall(UnitIsUnit, "npc", "player")
    if not okUnit or isPlayer then
        return {}
    end

    local guid = UnitGUID("npc")
    local name = UnitName("npc")
    if IsSecret(guid) then guid = nil end
    if IsSecret(name) then name = nil end
    if name == UnitName("player") then
        return {}
    end

    return { id = CreatureIDFromGUID(guid), name = name }
end

-- --------------------------------------------------------------------------
-- Identity scrubbing.
--
-- Server text arrives with the player's own name already substituted in: "$n"
-- became the character's name before the addon ever saw the string. Left
-- alone that costs three things -- two players' captures of the same line are
-- different text and can never confirm each other, a stranger's character
-- name gets baked into generated audio, and that name travels to whoever the
-- capture is shared with for no purpose. So it is put back to "$n" at capture
-- time and never reaches SavedVariables at all.
--
-- Only the name is reverted. Class and race substitutions are just as real --
-- a Silvermoon Guard greets a priest as "priest", which is $c -- but words
-- like "priest" also occur naturally in quest text and a single capture
-- cannot tell the two apart. Guessing would corrupt genuine lines, so class
-- and race travel as metadata instead and get resolved where several players'
-- captures of one line can be compared.
-- --------------------------------------------------------------------------
local playerNamePattern = nil

local function Detokenize(text)
    if not text or text == "" then return text end
    if not playerNamePattern then
        local name = UnitName("player")
        if not name or name == "" then return text end
        local ok, escaped = pcall(function() return (name:gsub("(%W)", "%%%1")) end)
        if ok and escaped then
            playerNamePattern = escaped
        else
            return text
        end
    end
    local ok, res = pcall(function() return (text:gsub(playerNamePattern, "$n")) end)
    return (ok and res) or text
end

local function PlayerMetadata()
    local localizedClass, classToken = UnitClass("player")
    local localizedRace, raceToken = UnitRace("player")
    return {
        playerClass = classToken,
        playerClassName = localizedClass,
        playerRace = raceToken,
        playerRaceName = localizedRace,
        -- 1 unknown, 2 male, 3 female.
        playerSex = UnitSex("player"),
        faction = UnitFactionGroup("player"),
    }
end

-- --------------------------------------------------------------------------
-- Recording
-- --------------------------------------------------------------------------

-- The speaker is recorded per passage, not per quest: the NPC who offers a
-- quest is frequently not the one who takes it back, and voicing the turn-in
-- in the giver's voice is a mistake that can only be fixed by regenerating.
local function RecordPassage(questID, passage, text, wasMissing)
    if not questID or questID == 0 or not text or text == "" then return end

    local h = Store()
    local entry = h.quests[questID]
    if not entry then
        entry = {}
        h.quests[questID] = entry
    end
    entry.title = GetTitleText() or entry.title

    local speaker = CurrentSpeaker()
    entry[passage] = {
        text = Detokenize(text),
        npcID = speaker.id,
        npcName = speaker.name,
    }
    if wasMissing then
        h.missingIDs[questID] = true
    end
end
addon.HarvestRecordPassage = RecordPassage

-- Gossip is keyed on npcID directly: an NPC that gives no quest has no quest
-- ID to fold into. Some NPCs cycle through several greeting variants, so
-- distinct texts are kept as a list, deduplicated by exact match so revisiting
-- does not grow it without bound.
local function RecordGossip(npcID, npcName, text)
    if not text or text == "" then return end
    -- With no way to say who spoke, the line cannot be voiced by anyone in
    -- particular, so there is nothing worth storing.
    if not npcID and not npcName then return end

    -- Before the duplicate check, not after: two greetings differing only by
    -- the player's name are the same greeting, and comparing raw strings
    -- would store both.
    text = Detokenize(text)

    local gossip = Store().gossip
    local key = npcID

    -- A creature ID maps to exactly one name, so an existing bucket under
    -- this ID carrying a different name means the ID is stale -- the symptom
    -- that previously merged many NPCs into one entry. Fall back to keying by
    -- name so the two stay separate, and drop the untrustworthy ID rather
    -- than record it against the wrong speaker.
    if key and npcName then
        local existing = gossip[key]
        if existing and existing.npcName and existing.npcName ~= npcName then
            DebugPrint("SpeakStone Narration: creature " .. tostring(key)
                .. " already recorded as '" .. existing.npcName
                .. "', now reporting '" .. npcName .. "' -- keying by name.")
            key = nil
        end
    end
    if not key then
        key = "name:" .. (npcName or "unknown")
        npcID = nil
    end

    local entry = gossip[key]
    if not entry then
        entry = { npcName = npcName, npcID = npcID, texts = {} }
        gossip[key] = entry
    end
    entry.npcName = npcName or entry.npcName
    entry.npcID = npcID or entry.npcID
    for _, existing in ipairs(entry.texts) do
        if existing == text then return end
    end
    table.insert(entry.texts, text)
end

-- Books, letters, scrolls and dungeon plaques, read through ItemTextFrame.
local function RecordItemText(itemID, itemName, page, text)
    if not text or text == "" then return end
    local items = Store().itemText
    -- Plaques and world objects come through the same frame as books but
    -- carry no item link, so they can only be keyed by name. Both key shapes
    -- have to be accepted; the ID is recorded whenever known so the two can be
    -- reconciled later.
    local key = itemID or itemName or "unknown"
    local entry = items[key]
    if not entry then
        entry = { itemID = itemID, itemName = itemName, pages = {} }
        items[key] = entry
    end
    entry.itemName = itemName or entry.itemName
    entry.itemID = itemID or entry.itemID
    entry.pages[page or 1] = Detokenize(text)
end

-- --------------------------------------------------------------------------
-- Events
-- --------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("QUEST_DETAIL")
frame:RegisterEvent("QUEST_PROGRESS")
frame:RegisterEvent("QUEST_COMPLETE")
frame:RegisterEvent("GOSSIP_SHOW")
frame:RegisterEvent("ITEM_TEXT_READY")

frame:SetScript("OnEvent", function(_, event)
    if not Enabled() then return end

    if event == "GOSSIP_SHOW" then
        local speaker = CurrentSpeaker()
        local ok, text = pcall(C_GossipInfo.GetText)
        if ok then RecordGossip(speaker.id, speaker.name, text) end
        return
    end

    if event == "ITEM_TEXT_READY" then
        local itemLink = ItemTextGetItem()
        local itemID, itemName
        if itemLink then
            pcall(function()
                itemID = tonumber(itemLink:match("item:(%d+)"))
                itemName = itemLink:match("%[(.-)%]")
            end)
        end
        if not itemName then
            local ok, rawItem = pcall(ItemTextGetItem)
            if ok and type(rawItem) == "string" then itemName = rawItem end
        end
        RecordItemText(itemID, itemName, ItemTextGetPage() or 1, ItemTextGetText())
        return
    end

    local questID = GetQuestID()
    if event == "QUEST_DETAIL" then
        RecordPassage(questID, "description", GetQuestText())
    elseif event == "QUEST_PROGRESS" then
        RecordPassage(questID, "progress", GetProgressText())
    elseif event == "QUEST_COMPLETE" then
        RecordPassage(questID, "completion", GetRewardText())
    end
end)

-- --------------------------------------------------------------------------
-- Counting and export
-- --------------------------------------------------------------------------
function addon.HarvestCounts()
    local h = Store()
    local quests, passages, unvoiced = 0, 0, 0
    for _, entry in pairs(h.quests) do
        quests = quests + 1
        for _, passage in ipairs(QUEST_PASSAGES) do
            local captured = entry[passage]
            if captured then
                passages = passages + 1
                -- A passage with no creature ID cannot be matched to a voice.
                if not captured.npcID then unvoiced = unvoiced + 1 end
            end
        end
    end
    local npcs, lines = 0, 0
    for _, entry in pairs(h.gossip) do
        npcs = npcs + 1
        lines = lines + #entry.texts
    end
    local items, pages = 0, 0
    for _, entry in pairs(h.itemText) do
        items = items + 1
        for _ in pairs(entry.pages) do pages = pages + 1 end
    end
    local missing = 0
    for _ in pairs(h.missingIDs) do missing = missing + 1 end
    return quests, passages, unvoiced, npcs, lines, items, pages, missing
end

-- Minimal Lua-table serialiser. The website's parser only cares about the
-- shape (top-level .quests/.gossip/.itemText plus locale and player
-- metadata), not which addon wrote it, so this output is interchangeable with
-- the standalone Harvester's.
local function Serialize(tbl, indent)
    indent = indent or ""
    local lines = {}
    for k, v in pairs(tbl) do
        local keyOk, keyStr = pcall(function()
            return type(k) == "number" and ("[" .. k .. "]") or ('["' .. tostring(k) .. '"]')
        end)
        if keyOk then
            if type(v) == "table" then
                table.insert(lines, indent .. keyStr .. " = {\n" .. Serialize(v, indent .. "  ") .. indent .. "},")
            elseif type(v) == "string" then
                local ok, escaped = pcall(function()
                    return v:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\r", "\\r"):gsub("\n", "\\n")
                end)
                if ok then
                    table.insert(lines, indent .. keyStr .. ' = "' .. escaped .. '",')
                end
            elseif type(v) == "number" or type(v) == "boolean" then
                local ok, valStr = pcall(tostring, v)
                if ok then
                    table.insert(lines, indent .. keyStr .. " = " .. valStr .. ",")
                end
            end
        end
    end
    return table.concat(lines, "\n") .. "\n"
end

--- Build the export payload.
--- @param missingOnly boolean restrict to quests that had no audio installed
function addon.HarvestExportText(missingOnly)
    local h = Store()
    local quests = h.quests
    if missingOnly then
        quests = {}
        for questID in pairs(h.missingIDs) do
            if h.quests[questID] then quests[questID] = h.quests[questID] end
        end
    end

    local data = {
        locale = GetLocale(),
        build = select(2, GetBuildInfo()),
        addonVersion = (C_AddOns and C_AddOns.GetAddOnMetadata
                        and C_AddOns.GetAddOnMetadata(addonName, "Version")) or "unknown",
        quests = quests,
    }
    if not missingOnly then
        data.gossip = h.gossip
        data.itemText = h.itemText
    end
    for key, value in pairs(PlayerMetadata()) do
        data[key] = value
    end

    local count = 0
    for _ in pairs(quests) do count = count + 1 end
    return "QuestReaderAddonExport = {\n" .. Serialize(data, "  ") .. "}", count
end

function addon.HarvestWipe()
    local h = Store()
    h.quests, h.gossip, h.itemText, h.missingIDs = {}, {}, {}, {}
end

-- --------------------------------------------------------------------------
-- Migration
--
-- Two older stores fed into this one: the standalone addon's saved variables,
-- and the short-lived missingCaptures table this addon used before capture
-- was folded in. Both are drained on first load and then left alone, so
-- nothing a player already collected is stranded.
-- --------------------------------------------------------------------------
-- Bumped when captured data has to be repaired rather than just carried
-- forward. 2: speaker attribution was unreliable -- see CurrentSpeaker.
local HARVEST_SCHEMA = 2

-- Throw away what the speaker bug produced.
--
-- Gossip goes entirely: it is keyed on the speaker, and a stale creature ID
-- merged many different NPCs into one bucket, so there is no way after the
-- fact to tell which line belonged to whom. Keeping it would mean submitting
-- lines to be voiced by an NPC who never said them, which is worse than
-- having none.
--
-- Quest text is kept -- the text itself is correct and is keyed by quest ID,
-- not by speaker -- but any speaker field that is provably wrong is cleared,
-- so the passage is submitted as "speaker unknown" instead of confidently
-- wrong. Only the player's own name is detectable as wrong here.
local function RepairSpeakerData(h)
    local dropped = 0
    for _ in pairs(h.gossip) do dropped = dropped + 1 end
    h.gossip = {}

    local playerName = UnitName("player")
    local scrubbed = 0
    for _, entry in pairs(h.quests) do
        for _, passage in ipairs(QUEST_PASSAGES) do
            local captured = entry[passage]
            if captured and captured.npcName and captured.npcName == playerName then
                captured.npcName, captured.npcID = nil, nil
                scrubbed = scrubbed + 1
            end
        end
    end

    if dropped > 0 or scrubbed > 0 then
        print("SpeakStone Narration: cleared " .. dropped
            .. " gossip capture(s) recorded with unreliable speaker information"
            .. (scrubbed > 0 and (", and " .. scrubbed .. " quest passage(s) attributed to your own character") or "")
            .. ". Quest text itself was kept. This was a bug, now fixed -- re-capture gossip by talking to NPCs again.")
    end
end

function addon.HarvestMigrate()
    local h = Store()
    local moved = 0

    if (h.schema or 1) < HARVEST_SCHEMA then
        RepairSpeakerData(h)
        h.schema = HARVEST_SCHEMA
    end

    local old = QuestReaderAddonDB.missingCaptures
    if old and old.quests then
        for questID, entry in pairs(old.quests) do
            if not h.quests[questID] then
                h.quests[questID] = entry
                moved = moved + 1
            end
            h.missingIDs[questID] = true
        end
        QuestReaderAddonDB.missingCaptures = nil
    end

    if type(QuestReaderHarvesterDB) == "table" then
        for questID, entry in pairs(QuestReaderHarvesterDB.quests or {}) do
            if not h.quests[questID] then
                h.quests[questID] = entry
                moved = moved + 1
            end
        end
        for npcID, entry in pairs(QuestReaderHarvesterDB.gossip or {}) do
            if not h.gossip[npcID] then h.gossip[npcID] = entry end
        end
        for key, entry in pairs(QuestReaderHarvesterDB.itemText or {}) do
            if not h.itemText[key] then h.itemText[key] = entry end
        end
    end

    if moved > 0 then
        DebugPrint("SpeakStone Narration: imported " .. moved .. " previously captured quest(s).")
    end
end
