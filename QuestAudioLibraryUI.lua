local _, addon = ...

local NUM_VISIBLE_ROWS = 14
local ROW_HEIGHT = 34
-- Typing in the search box used to re-filter on every keystroke, and filtering
-- by name means resolving a title for every quest in the library. Held back by
-- this much, a burst of typing costs one pass instead of one per character.
local SEARCH_DEBOUNCE = 0.2
-- How long one pass of the filter may hold the client's frame before handing
-- it back. Resolving a quest title is two protected API calls, and a name
-- search asks for one per quest that does not match on ID -- tens of
-- thousands of them with a full pack set, which is seconds of frozen client
-- if it is done in a single pass. The search runs across frames instead, so
-- the window stays responsive and results fill in as they are found.
local FILTER_BUDGET_MS = 8
-- Consulted only every so many quests: reading the clock costs more than the
-- comparison it guards, and a hundred quests is far below one frame's worth.
local FILTER_CHECK_EVERY = 100
-- Used where debugprofilestop is unavailable, since there is then no way to
-- ask how long the pass has been running.
local FILTER_CHUNK = 400

-- The window, built the first time it is opened. It used to be assembled at
-- file scope: fourteen rows of a button and three sub-buttons apiece, around
-- eighty frames, put together on every login whether or not anyone ever looked
-- at the library.
local UI
local searchTimer

-- --------------------------------------------------------------------------
-- Quest titles
--
-- Resolving one is two pcall'd API calls, and the search filter asks for every
-- quest in the library -- tens of thousands of them with a full pack set. Once
-- known, a title never changes, so it is kept.
--
-- A miss is a different matter: the client may simply not know the quest yet
-- and may learn it later, so misses are remembered only for as long as the
-- window stays open, and are dropped each time it is reopened.
-- --------------------------------------------------------------------------
local titleCache = {}
local titleMisses = {}

local function GetQuestTitle(questID)
    if not questID then return nil end

    local cached = titleCache[questID]
    if cached then return cached end
    if titleMisses[questID] then return nil end

    local resolved
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local ok, title = pcall(C_QuestLog.GetTitleForQuestID, questID)
        if ok and title and title ~= "" and not (issecretvalue and issecretvalue(title)) then
            resolved = title
        end
    end
    if not resolved and QuestUtils_GetQuestName then
        local ok, title = pcall(QuestUtils_GetQuestName, questID)
        if ok and title and title ~= "" and not (issecretvalue and issecretvalue(title)) then
            resolved = title
        end
    end

    if resolved then
        titleCache[questID] = resolved
    else
        titleMisses[questID] = true
    end
    return resolved
end

-- The client only knows a quest's title once it has the quest's data, which
-- for most of a pack's tens of thousands of quests it does not. Asking the
-- server closes that gap, but it is a per-quest round trip, so it is asked
-- only for the handful of rows actually on screen -- never for the filter
-- pass, which walks the whole library.
--
-- Requests are remembered for the session: a quest the server declined to
-- send is not going to answer differently a scroll later.
local titleRequests = {}
local pendingRefresh = false

local function RequestQuestTitle(questID)
    if not questID or titleCache[questID] or titleRequests[questID] then return end
    if not (C_QuestLog and C_QuestLog.RequestLoadQuestByID) then return end
    titleRequests[questID] = true
    pcall(C_QuestLog.RequestLoadQuestByID, questID)
end

-- Registered only while the window is open, from its OnShow. QUEST_DATA_LOAD_RESULT
-- fires for every quest anything in the UI asks the server about, all
-- session, and the only reason to hear it is to redraw a list that is on
-- screen -- so a player who never opens the library was paying for an event
-- handler that could not have anything to do.
local titleLoader = CreateFrame("Frame")
titleLoader:SetScript("OnEvent", function(_, _, questID, success)
    if not success or not questID or not titleRequests[questID] then return end
    -- The title is known now, so the miss recorded for it is stale.
    titleMisses[questID] = nil
    if pendingRefresh then return end
    pendingRefresh = true
    -- Answers arrive in bursts, one per row; redrawing once covers them all.
    C_Timer.After(0.1, function()
        pendingRefresh = false
        if UI and UI:IsShown() then
            UI:UpdateList()
        end
    end)
end)

-- --------------------------------------------------------------------------
-- Building the window
-- --------------------------------------------------------------------------
local function BuildUI()
    local frame = CreateFrame("Frame", "QuestReaderAudioLibraryUI", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(400, 612)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()

    -- Allow closing with Escape key
    tinsert(UISpecialFrames, "QuestReaderAudioLibraryUI")

    -- Title
    if frame.TitleText then
        frame.TitleText:SetText("SpeakStone Audio Library")
    else
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", frame, "TOP", 0, -5)
        title:SetText("SpeakStone Audio Library")
        frame.title = title
    end

    -- Search Box
    local searchBox = CreateFrame("EditBox", "QuestReaderAudioLibrarySearchBox", frame, "SearchBoxTemplate")
    searchBox:SetSize(360, 22)
    searchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -32)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(60)
    if searchBox.Instructions then
        searchBox.Instructions:SetText("Search quest ID or name...")
    end
    frame.searchBox = searchBox

    -- ScrollFrame (FauxScrollFrame for high performance virtualized rows)
    local scrollFrame = CreateFrame("ScrollFrame", "QuestReaderAudioLibraryScrollFrame", frame, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -62)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -36, 44)
    frame.scrollFrame = scrollFrame

    -- Bottom status and stop preview button
    local countText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 16)
    countText:SetJustifyH("LEFT")
    frame.countText = countText

    local stopButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    stopButton:SetSize(90, 22)
    stopButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 12)
    stopButton:SetText("Stop Audio")
    stopButton:SetScript("OnClick", function()
        frame:StopAudio()
    end)
    frame.stopButton = stopButton

    -- Mouse wheel scrolling handler
    local function OnListMouseWheel(delta)
        local scrollBar = _G["QuestReaderAudioLibraryScrollFrameScrollBar"]
        if scrollBar and scrollBar:IsShown() then
            local current = scrollBar:GetValue()
            local minVal, maxVal = scrollBar:GetMinMaxValues()
            local step = ROW_HEIGHT * 3
            if delta > 0 then
                scrollBar:SetValue(math.max(minVal, current - step))
            else
                scrollBar:SetValue(math.min(maxVal, current + step))
            end
        end
    end

    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(self, delta)
        OnListMouseWheel(delta)
    end)

    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function()
            frame:UpdateList()
        end)
    end)

    -- Create pooled row frames (14 rows created once and reused)
    frame.rows = {}
    for i = 1, NUM_VISIBLE_ROWS do
        local row = CreateFrame("Button", nil, frame)
        row:SetSize(342, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -62 - (i - 1) * ROW_HEIGHT)

        -- Highlight texture
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.08)

        -- Alternate row background
        if i % 2 == 0 then
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(1, 1, 1, 0.025)
        end

        -- Two lines: the quest's name on top, its ID beneath, so a row reads
        -- as the quest it is and still carries the number the files are
        -- named after.
        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -3)
        text:SetPoint("RIGHT", row, "RIGHT", -144, 0)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false)
        row.text = text

        local idText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        idText:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -1)
        idText:SetPoint("RIGHT", row, "RIGHT", -144, 0)
        idText:SetJustifyH("LEFT")
        idText:SetWordWrap(false)
        row.idText = idText

        -- Completion button
        local compBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        compBtn:SetSize(44, 20)
        compBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        compBtn:SetText("Comp")
        row.compBtn = compBtn

        -- Progress button
        local progBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        progBtn:SetSize(44, 20)
        progBtn:SetPoint("RIGHT", compBtn, "LEFT", -3, 0)
        progBtn:SetText("Prog")
        row.progBtn = progBtn

        -- Description button
        local descBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        descBtn:SetSize(44, 20)
        descBtn:SetPoint("RIGHT", progBtn, "LEFT", -3, 0)
        descBtn:SetText("Desc")
        row.descBtn = descBtn

        -- Click handlers
        descBtn:SetScript("OnClick", function()
            if row.questData then
                frame:PlaySpecificAudio(row.questData.id, "description")
            end
        end)
        progBtn:SetScript("OnClick", function()
            if row.questData then
                frame:PlaySpecificAudio(row.questData.id, "progress")
            end
        end)
        compBtn:SetScript("OnClick", function()
            if row.questData then
                frame:PlaySpecificAudio(row.questData.id, "completion")
            end
        end)

        -- Tooltips
        local function ShowRowTooltip(owner)
            if not row.questData then return end
            GameTooltip:SetOwner(owner or row, "ANCHOR_RIGHT")
            local title = GetQuestTitle(row.questData.id)
            if title then
                GameTooltip:AddLine(title, 1, 0.82, 0)
                GameTooltip:AddLine("Quest ID: " .. row.questData.id, 0.7, 0.7, 0.7)
            else
                GameTooltip:AddLine("Quest ID: " .. row.questData.id, 1, 0.82, 0)
            end

            local dLen = frame:GetAudioDuration(row.questData.id, "description")
            local pLen = frame:GetAudioDuration(row.questData.id, "progress")
            local cLen = frame:GetAudioDuration(row.questData.id, "completion")

            if dLen then GameTooltip:AddLine("Description: " .. string.format("%.1fs", dLen), 0.3, 1, 0.3) end
            if pLen then GameTooltip:AddLine("Progress: " .. string.format("%.1fs", pLen), 0.3, 1, 0.3) end
            if cLen then GameTooltip:AddLine("Completion: " .. string.format("%.1fs", cLen), 0.3, 1, 0.3) end

            GameTooltip:Show()
        end

        row:SetScript("OnEnter", function(self) ShowRowTooltip(self) end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        descBtn:SetScript("OnEnter", function(self) ShowRowTooltip(self) end)
        descBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        progBtn:SetScript("OnEnter", function(self) ShowRowTooltip(self) end)
        progBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        compBtn:SetScript("OnEnter", function(self) ShowRowTooltip(self) end)
        compBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Mouse wheel forwarding
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(self, delta) OnListMouseWheel(delta) end)
        descBtn:EnableMouseWheel(true)
        descBtn:SetScript("OnMouseWheel", function(self, delta) OnListMouseWheel(delta) end)
        progBtn:EnableMouseWheel(true)
        progBtn:SetScript("OnMouseWheel", function(self, delta) OnListMouseWheel(delta) end)
        compBtn:EnableMouseWheel(true)
        compBtn:SetScript("OnMouseWheel", function(self, delta) OnListMouseWheel(delta) end)

        frame.rows[i] = row
    end

    -- ----------------------------------------------------------------------
    -- Methods
    -- ----------------------------------------------------------------------
    local activeDebugSound = nil
    local activePlayingQuestID = nil
    local activePlayingType = nil

    -- Duration lookup helper. The walk over every installed pack, in
    -- extension order, is the addon's own FindSound -- this file used to
    -- carry its own copy of it here and again in PlaySpecificAudio, which is
    -- three places to keep agreeing about which extension wins.
    function frame:GetAudioDuration(questID, audioType)
        if not addon.FindSound then return nil end
        local _, _, duration = addon.FindSound({ questID .. "_" .. audioType })
        return duration
    end

    -- The filter pass currently running, if it has not finished yet. Declared
    -- ahead of BuildIndex so that rebuilding the index can retire one.
    local activeFilter
    local function CancelFilter()
        if activeFilter then
            if activeFilter.timer then activeFilter.timer:Cancel() end
            activeFilter = nil
        end
        frame.filtering = false
    end

    -- The per-quest index is built once for the whole addon, in
    -- QuestReaderAddon.lua, because the settings dashboard needs a walk over
    -- the same packs to count clips. This used to repeat that walk with its
    -- own string match per clip -- tens of thousands of them -- for an answer
    -- the other pass had already worked out.
    function frame:BuildIndex(force)
        if self.isIndexed and not force then
            return
        end

        CancelFilter()

        local list = {}
        if addon.GetAudioIndex then
            for _, entry in pairs(addon.GetAudioIndex().quests) do
                table.insert(list, entry)
            end
        end
        table.sort(list, function(a, b) return a.id < b.id end)

        self.allQuests = list
        self.isIndexed = true
        self.filteredList = nil
        -- A rebuilt index invalidates the narrowing below, which assumes the
        -- previous result was drawn from the same library.
        self.lastQuery = nil
        self.lastResult = nil
    end

    -- Real-time filter, run across frames.
    --
    -- Matching on ID is a substring test; matching on name is not, because a
    -- title has to be resolved first and that is two protected API calls per
    -- quest. Done in one pass over a full pack set that is tens of thousands
    -- of them and a client frozen for seconds, so the pass takes a slice of
    -- each frame and yields, filling the list in as it goes.
    function frame:FilterList(query)
        if not self.allQuests then
            self:BuildIndex()
        end
        CancelFilter()

        local scrollBar = _G["QuestReaderAudioLibraryScrollFrameScrollBar"]
        if scrollBar then
            scrollBar:SetValue(0)
        end

        local cleanQuery = query and query:lower():match("^%s*(.-)%s*$") or ""
        if cleanQuery == "" then
            self.filteredList = self.allQuests
            self.lastQuery = ""
            self.lastResult = self.allQuests
            self:UpdateList()
            return
        end

        -- Extending a query can only ever narrow the result: a quest that
        -- matches "westf" matched "west" too, whether it matched on ID or on
        -- title. So the longer query is filtered over what the shorter one
        -- produced rather than over the whole library.
        --
        -- Only over a *finished* result, though. A pass that was cancelled
        -- part-way through -- which is what happens when someone keeps typing
        -- -- has found only some of its matches, and narrowing from that would
        -- drop the rest for good rather than merely deferring them. That is
        -- why the completed result is kept apart from the one on screen.
        local startingList = self.allQuests
        if self.lastQuery and self.lastQuery ~= "" and self.lastResult
            and cleanQuery:sub(1, #self.lastQuery) == self.lastQuery then
            startingList = self.lastResult
        end

        local state = { query = cleanQuery, source = startingList, index = 1, results = {} }
        activeFilter = state
        self.filteredList = state.results
        self.filtering = true

        local function Step()
            -- A newer query, a rebuilt index or a closed window retires this
            -- pass; the timer that woke it may already be obsolete.
            if activeFilter ~= state then return end

            local source, results, needle = state.source, state.results, state.query
            local total = #source
            local i = state.index
            local startedAt = debugprofilestop and debugprofilestop() or nil
            local processed = 0

            while i <= total do
                local entry = source[i]
                local idStr = entry.idStr or tostring(entry.id)
                if idStr:find(needle, 1, true) then
                    results[#results + 1] = entry
                else
                    local title = GetQuestTitle(entry.id)
                    if title and title:lower():find(needle, 1, true) then
                        results[#results + 1] = entry
                    end
                end
                i = i + 1
                processed = processed + 1
                if processed % FILTER_CHECK_EVERY == 0 then
                    if startedAt then
                        if debugprofilestop() - startedAt >= FILTER_BUDGET_MS then break end
                    elseif processed >= FILTER_CHUNK then
                        break
                    end
                end
            end

            state.index = i
            if i > total then
                activeFilter = nil
                frame.filtering = false
                -- Complete, so the next query may narrow over it.
                frame.lastQuery = needle
                frame.lastResult = results
                frame:UpdateList()
            else
                frame:UpdateList()
                -- Next frame, not next second: this is a yield, not a delay.
                state.timer = C_Timer.NewTimer(0, Step)
            end
        end

        Step()
    end

    -- Filtering by name touches the whole library, so a burst of typing is
    -- collapsed into one pass rather than one per character.
    function frame:QueueFilter(query)
        if searchTimer then
            searchTimer:Cancel()
        end
        searchTimer = C_Timer.NewTimer(SEARCH_DEBOUNCE, function()
            searchTimer = nil
            if frame:IsShown() then
                frame:FilterList(query)
            end
        end)
    end

    -- Update visible rows
    function frame:UpdateList()
        local list = self.filteredList or self.allQuests or {}
        local numItems = #list
        -- Taken once. UpdateList runs on every frame of a search pass, and
        -- each of the branches below used to build a throwaway table to take
        -- a length from.
        local totalItems = self.allQuests and #self.allQuests or 0
        FauxScrollFrame_Update(self.scrollFrame, numItems, NUM_VISIBLE_ROWS, ROW_HEIGHT)
        local offset = FauxScrollFrame_GetOffset(self.scrollFrame)

        for i = 1, NUM_VISIBLE_ROWS do
            local index = offset + i
            local row = self.rows[i]
            if index <= numItems then
                local data = list[index]
                row.questData = data
                row:Show()

                local title = GetQuestTitle(data.id)
                if not title then
                    RequestQuestTitle(data.id)
                end
                if title and title ~= "" then
                    row.text:SetText("|cffffd100" .. title .. "|r")
                else
                    row.text:SetText("|cff9d9d9dUnknown quest|r")
                end
                row.idText:SetText("Quest " .. data.id)

                -- Description
                if data.types["description"] then
                    row.descBtn:Show()
                    if activePlayingQuestID == data.id and activePlayingType == "description" then
                        row.descBtn:SetText("|cff00ff00Desc|r")
                    else
                        row.descBtn:SetText("Desc")
                    end
                else
                    row.descBtn:Hide()
                end

                -- Progress
                if data.types["progress"] then
                    row.progBtn:Show()
                    if activePlayingQuestID == data.id and activePlayingType == "progress" then
                        row.progBtn:SetText("|cff00ff00Prog|r")
                    else
                        row.progBtn:SetText("Prog")
                    end
                else
                    row.progBtn:Hide()
                end

                -- Completion
                if data.types["completion"] then
                    row.compBtn:Show()
                    if activePlayingQuestID == data.id and activePlayingType == "completion" then
                        row.compBtn:SetText("|cff00ff00Comp|r")
                    else
                        row.compBtn:SetText("Comp")
                    end
                else
                    row.compBtn:Hide()
                end
            else
                row.questData = nil
                row:Hide()
            end
        end

        if self.filtering then
            -- A pass still running has not found everything yet, and "no
            -- matching quests" while it is still looking is simply wrong --
            -- which is what the empty result reads as for the first frame of
            -- every name search.
            self.countText:SetText(string.format("Searching... %d so far", numItems))
        elseif numItems == 0 then
            self.countText:SetText("No matching quests found.")
        elseif self.filteredList and numItems ~= totalItems then
            self.countText:SetText(string.format("Showing %d / %d quests", numItems, totalItems))
        else
            self.countText:SetText(string.format("Total: %d voiced quests", numItems))
        end
    end

    -- Audio playback
    function frame:StopAudio()
        if activeDebugSound then
            StopSound(activeDebugSound)
            activeDebugSound = nil
        end
        activePlayingQuestID = nil
        activePlayingType = nil
        self:UpdateList()
    end

    function frame:PlaySpecificAudio(questID, audioType)
        self:StopAudio()
        -- Narration running behind the window would otherwise play over the
        -- preview -- and with "silence Blizzard's own voice lines" on it is
        -- holding Sound_DialogVolume at zero, which is the channel the
        -- preview plays on, so the preview was silent for as long as the
        -- narration lasted.
        if addon.StopCurrentSound then
            addon.StopCurrentSound()
        end

        local soundPath
        if addon.FindSound then
            local _, path = addon.FindSound({ questID .. "_" .. audioType })
            soundPath = path
        end

        if not soundPath then
            print("SpeakStone Audio Library: clip not found for Quest ID " .. tostring(questID) .. " (" .. tostring(audioType) .. ")")
            return
        end

        local willPlay, handle = PlaySoundFile(soundPath, "Dialog")
        if willPlay and handle then
            activeDebugSound = handle
            activePlayingQuestID = questID
            activePlayingType = audioType
            self:UpdateList()
        end
    end

    -- Main populate / toggle
    function frame:PopulateList()
        self:BuildIndex()
        self:FilterList(self.searchBox:GetText())
    end

    function frame:ToggleVisibility()
        if self:IsVisible() then
            self:Hide()
        else
            self:Show()
        end
    end

    -- SearchBox script
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if SearchBoxTemplate_OnTextChanged then
            SearchBoxTemplate_OnTextChanged(self)
        end
        frame:QueueFilter(self:GetText())
    end)

    searchBox:SetScript("OnEscapePressed", function(self)
        if self:GetText() ~= "" then
            self:SetText("")
        else
            frame:Hide()
        end
    end)

    frame:SetScript("OnShow", function(self)
        self:Raise()
        titleLoader:RegisterEvent("QUEST_DATA_LOAD_RESULT")
        -- A title the client did not know last time it may know now -- so the
        -- narrowed result from the previous open, computed while those were
        -- still misses, cannot be reused either.
        wipe(titleMisses)
        self.lastQuery = nil
        self.lastResult = nil
        self:PopulateList()
    end)

    frame:SetScript("OnHide", function(self)
        -- Titles still in flight are of no use to a list nobody is looking
        -- at, and the client caches what it has already sent -- so a quest
        -- whose answer lands after this is resolved from the cache on the
        -- next open rather than lost.
        titleLoader:UnregisterEvent("QUEST_DATA_LOAD_RESULT")
        if searchTimer then
            searchTimer:Cancel()
            searchTimer = nil
        end
        -- A pass left running against a closed window is work nobody is
        -- waiting for, and it would keep waking every frame until it finished.
        CancelFilter()
        self:StopAudio()
    end)

    return frame
end

local function EnsureUI()
    if not UI then
        UI = BuildUI()
    end
    return UI
end

-- Called when a sound pack registers after the index was built. Nothing to do
-- if the window has never been opened -- it will index on first show.
function addon.AudioLibraryInvalidate()
    if UI then
        UI.isIndexed = false
        if UI:IsShown() then
            UI:PopulateList()
        end
    end
end

function addon.OpenAudioLibrary()
    local frame = EnsureUI()
    frame:Show()
    return frame
end

function addon.ToggleAudioLibrary()
    EnsureUI():ToggleVisibility()
end

-- Slash command
SLASH_QRLIBRARY1, SLASH_QRLIBRARY2 = '/qrlibrary', '/sslibrary'
SlashCmdList["QRLIBRARY"] = function()
    addon.ToggleAudioLibrary()
end
