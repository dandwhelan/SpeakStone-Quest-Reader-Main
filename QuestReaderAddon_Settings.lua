local addonName, addon = ...
local QuestReader = {}

EventUtil.ContinueOnAddOnLoaded(addonName, function()
    QuestReaderAddonDB = QuestReaderAddonDB or {}
    QuestReader:CreateSettings()
end)

local WEBSITE = "speakstone.beanw.co.uk"

local function OpenAudioLibraryUI()
    if QuestReaderAudioLibraryUI then
        QuestReaderAudioLibraryUI:Show()
        QuestReaderAudioLibraryUI:PopulateList()
    else
        print("SpeakStone Narration: the audio library window is not available.")
    end
end

-- The standalone companion addon, where someone still has it, owns capture and
-- the export commands. Every route into export has to ask, not assume.
local function StandaloneHarvesterActive()
    return C_AddOns and C_AddOns.IsAddOnLoaded
        and C_AddOns.IsAddOnLoaded("QuestReaderHarvester")
end

local function ExportHarvest()
    if StandaloneHarvesterActive() and SlashCmdList["QUESTREADERHARVEST"] then
        SlashCmdList["QUESTREADERHARVEST"]("export")
    else
        addon.ShowHarvestExport()
    end
end

StaticPopupDialogs["QUESTREADER_CONFIRM_CLEAR_HARVEST"] = {
    text = "Clear everything SpeakStone has captured -- quest text, greetings and books?\n\nThis cannot be undone, and anything not yet submitted is lost.",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        -- Only when the *standalone* addon owns that command. This addon now
        -- registers /qrharvest itself, so an unqualified check ran the
        -- built-in wipe here and again below, printing "cleared" twice.
        if StandaloneHarvesterActive() and SlashCmdList["QUESTREADERHARVEST"] then
            SlashCmdList["QUESTREADERHARVEST"]("wipe")
        elseif QuestReaderHarvesterDB then
            QuestReaderHarvesterDB.quests = {}
            QuestReaderHarvesterDB.gossip = {}
            QuestReaderHarvesterDB.itemText = {}
            print("SpeakStone Harvester: cleared.")
        end
        -- Clear this addon's own store too. It is separate from the
        -- standalone Harvester's, so wiping only one would leave the player
        -- looking at data they thought they had just cleared.
        if addon.HarvestWipe then
            addon.HarvestWipe()
            print("SpeakStone Narration: captured text cleared.")
        end
        if addon.RefreshSettingsStatus then addon.RefreshSettingsStatus() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Every option, with the one-line explanation that used to live only in the
-- README. Grouped, because a flat list of seven checkboxes gave no clue which
-- of them mattered when quest audio was not playing.
local SETTINGS_SECTIONS = {
    {
        title = "Playback",
        options = {
            {
                option = "autoPlayEnabled",
                label = "Read quests automatically",
                tooltip = "Start narrating as soon as a quest, greeting or book appears. Turn this on if you use Immersion or DialogueUI -- their windows bypass the Read Quest button.",
            },
            {
                option = "autoPlayInQuestMap",
                label = "Also read from the quest log map",
                tooltip = "Narrate when a quest is selected in the world map's quest list, not just at the quest giver.",
            },
            {
                option = "muteGossip",
                label = "Mute Blizzard's own voice lines",
                tooltip = "Silences the game's Dialog channel while SpeakStone speaks, so the two do not overlap. Narration also starts instantly instead of waiting for the greeting to finish.",
            },
            {
                option = "stopDialogueOnClose",
                label = "Stop narration when the window closes",
                tooltip = "Walking away mid-sentence stops the audio instead of leaving a disembodied voice following you.",
            },
        },
    },
    {
        title = "Interface",
        options = {
            {
                option = "showMinimapButton",
                label = "Show the minimap button",
                tooltip = "Left-click opens these settings, right-click exports captured text, middle-click toggles debug messages.",
                onChange = function() if addon.UpdateMinimapButtonVisibility then addon.UpdateMinimapButtonVisibility() end end,
            },
            {
                option = "showQuestButton",
                label = "Show the Read Quest button",
                tooltip = "The button at the bottom of the quest window and in the quest log. Hide it if your quest UI already covers that spot -- narration still works.",
                onChange = function() if addon.UpdateQuestButtonVisibility then addon.UpdateQuestButtonVisibility() end end,
            },
            {
                option = "showDebugMessages",
                label = "Show debug messages in chat",
                tooltip = "Prints which clip was chosen, and says so when a quest has no audio installed. Useful when reporting a problem.",
            },
        },
    },
    {
        title = "Contribute",
        options = {
            {
                option = "harvestEnabled",
                label = "Capture quest text to help voice missing quests",
                tooltip = "Records the text of quests, greetings and books you encounter, so unvoiced ones can be queued up. Your character's name is replaced with $n before anything is stored.",
                onChange = function() if addon.RefreshSettingsStatus then addon.RefreshSettingsStatus() end end,
            },
        },
    },
}

function QuestReader:CreateSettings()
    local optionsFrame
    optionsFrame = CreateFrame("Frame", nil, nil, "VerticalLayoutFrame")
    optionsFrame.spacing = 4
    local category, layout = Settings.RegisterCanvasLayoutCategory(optionsFrame, "SpeakStone Narration |T" .. addonName .. "\\cs_icon.tga:18:18:0:0|t")
    addon.settingsCategoryID = category.ID
    Settings.RegisterAddOnCategory(category)

    local layoutIndex = 0
    local function GetLayoutIndex()
        layoutIndex = layoutIndex + 1
        return layoutIndex
    end

    -- Header
    local Header = CreateFrame("Frame", nil, optionsFrame)
    Header:SetSize(150, 50)
    local headerText = Header:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    headerText:SetPoint("TOPLEFT", 7, -22)
    headerText:SetText("SpeakStone Narration")
    local divider = Header:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas("Options_HorizontalDivider", true)
    divider:SetPoint("BOTTOMLEFT", -50)
    Header.layoutIndex = GetLayoutIndex()
    Header.bottomPadding = 10

    local function makeSectionHeader(title)
        local section = CreateFrame("Frame", nil, optionsFrame)
        section:SetSize(400, 22)
        local text = section:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        text:SetPoint("BOTTOMLEFT", section, "BOTTOMLEFT", 7, 2)
        text:SetText(title)
        section.layoutIndex = GetLayoutIndex()
        section.topPadding = 10
        section.bottomPadding = 2
        return section
    end

    local function makeCheckButton(info)
        local checkButton = CreateFrame("CheckButton", addonName .. "CheckBox_" .. info.option, optionsFrame, "SettingsCheckBoxTemplate")
        checkButton.text = checkButton:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        checkButton.text:SetText(info.label)
        checkButton.text:SetPoint("LEFT", checkButton, "RIGHT", 4, 0)
        checkButton:SetSize(21, 20)
        checkButton.layoutIndex = GetLayoutIndex()
        -- The label is part of the click target, not just decoration next to it.
        checkButton:SetHitRectInsets(0, -checkButton.text:GetWidth(), 0, 0)
        checkButton.HoverBackground = nil
        checkButton:SetChecked(QuestReaderAddonDB[info.option])

        checkButton:SetScript("OnClick", function(self)
            QuestReaderAddonDB[info.option] = self:GetChecked()
            if info.onChange then info.onChange(self:GetChecked()) end
        end)
        checkButton:SetScript("OnShow", function(self)
            self:SetChecked(QuestReaderAddonDB[info.option])
        end)

        if info.tooltip then
            checkButton:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(info.label, 1, 0.82, 0)
                GameTooltip:AddLine(info.tooltip, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            checkButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        return checkButton
    end

    for _, section in ipairs(SETTINGS_SECTIONS) do
        makeSectionHeader(section.title)
        for _, info in ipairs(section.options) do
            makeCheckButton(info)
        end

        -- The delay only means anything while Blizzard's own greeting is
        -- audible, so it sits with the option that controls that.
        if section.title == "Playback" then
            local sliderFrame = CreateFrame("Frame", nil, optionsFrame)
            sliderFrame:SetSize(400, 46)
            sliderFrame.layoutIndex = GetLayoutIndex()
            sliderFrame.topPadding = 6

            local slider = CreateFrame("Slider", addonName .. "AutoPlayDelaySlider", sliderFrame, "OptionsSliderTemplate")
            slider:SetPoint("TOPLEFT", sliderFrame, "TOPLEFT", 10, -16)
            slider:SetWidth(200)
            slider:SetMinMaxValues(0, 6)
            slider:SetValueStep(0.5)
            slider:SetObeyStepOnDrag(true)
            _G[slider:GetName() .. "Low"]:SetText("0s")
            _G[slider:GetName() .. "High"]:SetText("6s")

            local function Describe(value)
                _G[slider:GetName() .. "Text"]:SetText(string.format("Wait before speaking: %.1fs", value))
            end

            slider:SetScript("OnValueChanged", function(self, value)
                value = math.floor(value * 2 + 0.5) / 2
                QuestReaderAddonDB.autoPlayDelay = value
                Describe(value)
            end)
            slider:SetScript("OnShow", function(self)
                local value = tonumber(QuestReaderAddonDB.autoPlayDelay) or 2
                self:SetValue(value)
                Describe(value)
            end)
            slider:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("Wait before speaking", 1, 0.82, 0)
                GameTooltip:AddLine("How long to hold back so the NPC's own greeting can finish. Ignored when Blizzard's voice lines are muted, because then there is nothing to wait for.", 1, 1, 1, true)
                GameTooltip:Show()
            end)
            slider:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
    end

    -- ----------------------------------------------------------------------
    -- Status. Without it, "no audio for this quest" and "no voice pack
    -- installed at all" look identical from the player's side, and there was
    -- no way to see whether capture had actually recorded anything.
    -- ----------------------------------------------------------------------
    local statusFrame = CreateFrame("Frame", nil, optionsFrame)
    statusFrame:SetSize(500, 60)
    statusFrame.layoutIndex = GetLayoutIndex()
    statusFrame.topPadding = 12

    local statusText = statusFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    statusText:SetPoint("TOPLEFT", statusFrame, "TOPLEFT", 7, 0)
    statusText:SetWidth(490)
    statusText:SetJustifyH("LEFT")
    statusText:SetSpacing(3)

    local function RefreshStatus()
        local lines = {}

        if addon.GetInstalledAudioSummary then
            local packs, clips, quests = addon.GetInstalledAudioSummary()
            if clips == 0 then
                table.insert(lines, "|cffff6060No voice packs installed.|r Download one from |cff00ccff" .. WEBSITE .. "|r -- the addon on its own has nothing to play.")
            else
                local names = {}
                for _, pack in ipairs(packs) do table.insert(names, pack.name) end
                table.insert(lines, string.format("|cff00ff00%d clip(s)|r across %d quest(s), from: %s",
                    clips, quests, table.concat(names, ", ")))
            end
        end

        if addon.HarvestCounts then
            local capturedQuests, passages, _, npcs, glines, items, pages = addon.HarvestCounts()
            if StandaloneHarvesterActive() then
                table.insert(lines, "The standalone Harvester addon is installed and is doing the capturing; SpeakStone's own capture is standing down.")
            elseif not QuestReaderAddonDB.harvestEnabled then
                table.insert(lines, "|cffff6060Capture is off.|r Nothing new is being recorded.")
            end
            -- Greetings and books lead. Neither has a table in the client or a
            -- scrapeable equivalent, so capture is the only way they can ever
            -- be obtained; quest text can be sourced other ways, and a quest
            -- with no audio is as often one removed from the game as one
            -- waiting for a voice.
            table.insert(lines, string.format("Captured |cffffd100%d greeting(s)|r from %d NPC(s) and |cffffd100%d page(s)|r across %d book(s) -- neither exists anywhere but a live client, so this is the part worth sending.",
                glines, npcs, pages, items))
            table.insert(lines, string.format("Also %d quest(s) over %d passage(s).", capturedQuests, passages))
        end

        statusText:SetText(table.concat(lines, "\n"))
        statusFrame:SetHeight(math.max(40, statusText:GetStringHeight() + 8))
    end
    addon.RefreshSettingsStatus = RefreshStatus
    statusFrame:SetScript("OnShow", RefreshStatus)
    RefreshStatus()

    -- ----------------------------------------------------------------------
    -- Actions
    -- ----------------------------------------------------------------------
    local function makeButtonRow(buttons)
        local row = CreateFrame("Frame", nil, optionsFrame)
        row:SetSize(520, 26)
        row.layoutIndex = GetLayoutIndex()
        row.topPadding = 6

        local previous
        for _, spec in ipairs(buttons) do
            local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            button:SetSize(spec.width or 170, 24)
            button:SetText(spec.text)
            if previous then
                button:SetPoint("LEFT", previous, "RIGHT", 8, 0)
            else
                button:SetPoint("LEFT", row, "LEFT", 7, 0)
            end
            button:SetScript("OnClick", spec.onClick)
            if spec.tooltip then
                button:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(spec.text, 1, 0.82, 0)
                    GameTooltip:AddLine(spec.tooltip, 1, 1, 1, true)
                    GameTooltip:Show()
                end)
                button:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
            previous = button
        end
        return row
    end

    makeButtonRow({
        {
            text = "Open Audio Library",
            onClick = OpenAudioLibraryUI,
            tooltip = "Browse and replay every voiced quest your installed packs provide. Also /qrlibrary.",
        },
        {
            text = "Export Captured Text",
            onClick = ExportHarvest,
            tooltip = "Everything recorded: NPC greetings, books and quest text, in one payload to paste at the site. Also /ssharvest export.",
        },
        {
            text = "Clear Captured Data",
            width = 150,
            onClick = function() StaticPopup_Show("QUESTREADER_CONFIRM_CLEAR_HARVEST") end,
            tooltip = "Throw away everything captured so far. Submit it first if you have not.",
        },
    })

    -- A clickable link is not something an addon can offer, so the next best
    -- thing is a box the player can select and copy without leaving the panel.
    local linkFrame = CreateFrame("Frame", nil, optionsFrame)
    linkFrame:SetSize(520, 40)
    linkFrame.layoutIndex = GetLayoutIndex()
    linkFrame.topPadding = 12

    local linkLabel = linkFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    linkLabel:SetPoint("TOPLEFT", linkFrame, "TOPLEFT", 7, 0)
    linkLabel:SetText("Submit captured text, and get voice packs, at:")

    local linkBox = CreateFrame("EditBox", nil, linkFrame, "InputBoxTemplate")
    linkBox:SetSize(240, 20)
    linkBox:SetPoint("TOPLEFT", linkLabel, "BOTTOMLEFT", 6, -4)
    linkBox:SetAutoFocus(false)
    linkBox:SetText("https://" .. WEBSITE)
    linkBox:SetCursorPosition(0)
    -- Read-only in effect: typing into it would only mislead.
    linkBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText("https://" .. WEBSITE)
            self:HighlightText()
        end
    end)
    linkBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    linkBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    optionsFrame:Layout()
end

-- Function to open settings
function addon:OpenSettings()
    if addon.settingsCategoryID then
        Settings.OpenToCategory(addon.settingsCategoryID)
    end
end

SLASH_QUESTREADER1, SLASH_QUESTREADER2, SLASH_QUESTREADER3, SLASH_QUESTREADER4 = '/qr', '/questreader', '/ss', '/speakstone'
SlashCmdList.QUESTREADER = function(msg)
    addon:OpenSettings()
end
