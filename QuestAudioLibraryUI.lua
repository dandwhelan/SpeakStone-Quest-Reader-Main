local addonName, addon = ...

local NUM_VISIBLE_ROWS = 14
local ROW_HEIGHT = 26
-- Typing in the search box used to re-filter on every keystroke, and filtering
-- by name means resolving a title for every quest in the library. Held back by
-- this much, a burst of typing costs one pass instead of one per character.
local SEARCH_DEBOUNCE = 0.2
local FALLBACK_EXTS = { ".ogg", ".wav" }

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

local function SoundExtensions()
    return addon.soundExtensions or FALLBACK_EXTS
end

-- --------------------------------------------------------------------------
-- Building the window
-- --------------------------------------------------------------------------
local function BuildUI()
    local frame = CreateFrame("Frame", "QuestReaderAudioLibraryUI", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(400, 500)
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

        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", row, "LEFT", 4, 0)
        text:SetPoint("RIGHT", row, "RIGHT", -144, 0)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false)
        row.text = text

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

    -- Duration lookup helper
    function frame:GetAudioDuration(questID, audioType)
        for _, ext in ipairs(SoundExtensions()) do
            local filename = questID .. "_" .. audioType .. ext
            for _, soundLengths in pairs(addon.soundSources or {}) do
                if type(soundLengths) == "table" and soundLengths[filename] then
                    return soundLengths[filename]
                end
            end
        end
        return nil
    end

    -- Index builder: scans addon.soundSources fast and caches results
    function frame:BuildIndex(force)
        if self.isIndexed and not force then
            return
        end

        local questMap = {}
        for packName, soundLengths in pairs(addon.soundSources or {}) do
            if type(soundLengths) == "table" then
                for soundFile in pairs(soundLengths) do
                    local questID, audioType = soundFile:match("^(%d+)_(%a+)%.")
                    if questID and audioType then
                        local idNum = tonumber(questID)
                        if idNum then
                            local entry = questMap[idNum]
                            if not entry then
                                entry = { id = idNum, types = {} }
                                questMap[idNum] = entry
                            end
                            entry.types[audioType] = true
                        end
                    end
                end
            end
        end

        local list = {}
        for _, entry in pairs(questMap) do
            table.insert(list, entry)
        end
        table.sort(list, function(a, b) return a.id < b.id end)

        self.allQuests = list
        self.questMap = questMap
        self.isIndexed = true
        self.filteredList = nil
    end

    -- Real-time filter
    function frame:FilterList(query)
        if not self.allQuests then
            self:BuildIndex()
        end

        if not query or query:match("^%s*$") then
            self.filteredList = self.allQuests
        else
            local cleanQuery = query:lower():match("^%s*(.-)%s*$")
            local filtered = {}
            for _, entry in ipairs(self.allQuests) do
                local idStr = tostring(entry.id)
                if idStr:find(cleanQuery, 1, true) then
                    table.insert(filtered, entry)
                else
                    local title = GetQuestTitle(entry.id)
                    if title and title:lower():find(cleanQuery, 1, true) then
                        table.insert(filtered, entry)
                    end
                end
            end
            self.filteredList = filtered
        end

        local scrollBar = _G["QuestReaderAudioLibraryScrollFrameScrollBar"]
        if scrollBar then
            scrollBar:SetValue(0)
        end
        self:UpdateList()
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
                if title and title ~= "" then
                    row.text:SetText("|cffffd100[" .. data.id .. "]|r " .. title)
                else
                    row.text:SetText("Quest ID: |cffffffff" .. data.id .. "|r")
                end

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

        if numItems == 0 then
            self.countText:SetText("No matching quests found.")
        elseif self.filteredList and #self.filteredList ~= #(self.allQuests or {}) then
            self.countText:SetText(string.format("Showing %d / %d quests", numItems, #(self.allQuests or {})))
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

        for _, extension in ipairs(SoundExtensions()) do
            local soundFile = questID .. "_" .. audioType .. extension
            for packName, soundLengths in pairs(addon.soundSources or {}) do
                if type(soundLengths) == "table" and soundLengths[soundFile] then
                    local soundPath = "Interface\\AddOns\\" .. packName .. "\\Sounds\\" .. soundFile
                    local willPlay, handle = PlaySoundFile(soundPath, "Dialog")
                    if willPlay and handle then
                        activeDebugSound = handle
                        activePlayingQuestID = questID
                        activePlayingType = audioType
                        self:UpdateList()
                    end
                    return
                end
            end
        end

        print("SpeakStone Audio Library: clip not found for Quest ID " .. tostring(questID) .. " (" .. tostring(audioType) .. ")")
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
        -- A title the client did not know last time it may know now.
        wipe(titleMisses)
        self:PopulateList()
    end)

    frame:SetScript("OnHide", function(self)
        if searchTimer then
            searchTimer:Cancel()
            searchTimer = nil
        end
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
