local addonName, addon = ...
local SpeakStone = {}

EventUtil.ContinueOnAddOnLoaded(addonName, function()
    QuestReaderAddonDB = QuestReaderAddonDB or {}
    SpeakStone:CreateSettings()
end)

local WEBSITE = "speakstone.beanw.co.uk"

local function OpenAudioLibraryUI()
    if QuestReaderAudioLibraryUI then
        QuestReaderAudioLibraryUI:Show()
        QuestReaderAudioLibraryUI:PopulateList()
    else
        print("SpeakStone: the audio library window is not available.")
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
            -- Left over from the standalone addon, cleared silently: the one
            -- line printed below covers both stores, and two "cleared"
            -- messages for one click read as if something went twice.
            QuestReaderHarvesterDB.quests = {}
            QuestReaderHarvesterDB.gossip = {}
            QuestReaderHarvesterDB.itemText = {}
        end
        -- Clear this addon's own store too. It is separate from the
        -- standalone Harvester's, so wiping only one would leave the player
        -- looking at data they thought they had just cleared.
        if addon.HarvestWipe then
            addon.HarvestWipe()
            print("SpeakStone: captured text cleared.")
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
                label = "Silence Blizzard's own voice lines",
                tooltip = "Off by default: where Blizzard has voiced a line, that recording plays and SpeakStone waits its turn. Turn this on to mute the game's Dialog channel instead, so narration starts immediately and nothing plays over it.",
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

-- --------------------------------------------------------------------------
-- Small shared helpers
-- --------------------------------------------------------------------------

local GOLD = { 1, 0.82, 0 }

local function AttachTooltip(frame, title, body)
    if not body then return end
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title, GOLD[1], GOLD[2], GOLD[3])
        GameTooltip:AddLine(body, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- --------------------------------------------------------------------------
-- The window
-- --------------------------------------------------------------------------

local FRAME_WIDTH = 700
local FRAME_HEIGHT = 540
local CARD_WIDTH = 226
local CARD_HEIGHT = 92
local CARD_GAP = 8
local LEFT_X = 16
local RIGHT_X = LEFT_X + CARD_WIDTH + 20
local TOP_Y = -34

-- A dashboard tile: a small label, a headline value, a wrapped caption and an
-- optional action line. The state a player needs first -- whether any voice
-- pack is installed at all -- used to be one red sentence inside a paragraph
-- below the options, which is to say invisible.
local function CreateCard(parent, spec)
    local card = CreateFrame("Button", nil, parent)
    card:SetSize(CARD_WIDTH, CARD_HEIGHT)

    local bg = card:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.09, 0.08, 0.07, 0.85)

    -- The one piece of colour on the tile. It carries the state, so a glance
    -- at the left column says which tile wants attention.
    local accent = card:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT")
    accent:SetPoint("TOPRIGHT")
    accent:SetHeight(2)
    accent:SetColorTexture(0.72, 0.57, 0.19, 1)
    card.accent = accent

    local label = card:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    label:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -9)
    label:SetText(spec.label)
    card.label = label

    local value = card:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    value:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
    value:SetWidth(CARD_WIDTH - 20)
    value:SetJustifyH("LEFT")
    card.value = value

    local caption = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    caption:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 8)
    caption:SetWidth(CARD_WIDTH - 20)
    caption:SetJustifyH("LEFT")
    caption:SetSpacing(2)
    card.caption = caption

    if spec.onClick then
        card:SetScript("OnClick", spec.onClick)
        local highlight = card:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.06)
    end

    return card
end

-- Colour and text for one card, given the current state. Kept apart from the
-- frame building so a refresh is a data update, not a rebuild.
local function SetCardState(card, accent, value, caption)
    card.accent:SetColorTexture(accent[1], accent[2], accent[3], 1)
    card.value:SetText(value or "")
    card.value:SetTextColor(accent[1], accent[2], accent[3])
    card.caption:SetText(caption or "")
end

local ACCENT_GOOD = { 0.25, 0.82, 0.48 }
local ACCENT_BAD = { 1, 0.42, 0.37 }
local ACCENT_NEUTRAL = { 0.85, 0.75, 0.45 }

function SpeakStone:CreateWindow()
    if addon.settingsWindow then return addon.settingsWindow end

    local frame = CreateFrame("Frame", "SpeakStoneSettingsFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    tinsert(UISpecialFrames, "SpeakStoneSettingsFrame")

    if frame.TitleText then
        frame.TitleText:SetText("SpeakStone")
    end

    local version = C_AddOns and C_AddOns.GetAddOnMetadata
        and C_AddOns.GetAddOnMetadata(addonName, "Version")
    if version then
        local versionText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        versionText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -8)
        versionText:SetText("v" .. version)
    end

    -- ----------------------------------------------------------------------
    -- Left column: status cards
    -- ----------------------------------------------------------------------
    local cards = {}

    local function PlaceCard(spec, index)
        local card = CreateCard(frame, spec)
        card:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_X, TOP_Y - (index - 1) * (CARD_HEIGHT + CARD_GAP))
        return card
    end

    cards.packs = PlaceCard({ label = "VOICE PACKS", onClick = OpenAudioLibraryUI }, 1)
    AttachTooltip(cards.packs, "Voice packs", "How much audio is installed and where it came from. Click to browse and replay every voiced quest your packs provide.")

    cards.captured = PlaceCard({ label = "CAPTURED", onClick = ExportHarvest }, 2)
    AttachTooltip(cards.captured, "Captured text", "Greetings and book pages exist nowhere but a live client, so they are the part worth sending. Click to export everything recorded so far.")

    cards.capture = PlaceCard({ label = "CAPTURE" }, 3)
    AttachTooltip(cards.capture, "Capture", "Whether SpeakStone is recording the text it encounters. Your character's name is replaced with $n before anything is stored.")

    -- A clickable link is not something an addon can offer, so the next best
    -- thing is a box the player can select and copy without leaving the panel.
    local linkCard = PlaceCard({ label = "CONTRIBUTE" }, 4)
    linkCard.value:Hide()
    linkCard.caption:ClearAllPoints()
    linkCard.caption:SetPoint("TOPLEFT", linkCard.label, "BOTTOMLEFT", 0, -4)
    linkCard.caption:SetText("Submit captured text, and get voice packs, at:")
    linkCard.accent:SetColorTexture(ACCENT_NEUTRAL[1], ACCENT_NEUTRAL[2], ACCENT_NEUTRAL[3], 1)

    local linkBox = CreateFrame("EditBox", nil, linkCard, "InputBoxTemplate")
    linkBox:SetSize(CARD_WIDTH - 30, 20)
    linkBox:SetPoint("BOTTOMLEFT", linkCard, "BOTTOMLEFT", 16, 8)
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

    -- ----------------------------------------------------------------------
    -- Right column: the options themselves, unchanged in content
    -- ----------------------------------------------------------------------
    local optionsWidth = FRAME_WIDTH - RIGHT_X - 22
    local cursorY = TOP_Y

    local function Advance(height)
        cursorY = cursorY - height
    end

    local function makeSectionHeader(title)
        local text = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        text:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_X, cursorY)
        text:SetText(title)
        Advance(20)

        local divider = frame:CreateTexture(nil, "ARTWORK")
        divider:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_X, cursorY)
        divider:SetSize(optionsWidth, 1)
        divider:SetColorTexture(0.35, 0.31, 0.24, 0.9)
        Advance(8)
    end

    local function makeCheckButton(info)
        local checkButton = CreateFrame("CheckButton", addonName .. "CheckBox_" .. info.option, frame, "SettingsCheckBoxTemplate")
        checkButton:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_X + 2, cursorY)
        checkButton.text = checkButton:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        checkButton.text:SetText(info.label)
        checkButton.text:SetPoint("LEFT", checkButton, "RIGHT", 4, 0)
        checkButton:SetSize(21, 20)
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

        AttachTooltip(checkButton, info.label, info.tooltip)
        Advance(24)
        return checkButton
    end

    for index, section in ipairs(SETTINGS_SECTIONS) do
        if index > 1 then Advance(12) end
        makeSectionHeader(section.title)
        for _, info in ipairs(section.options) do
            makeCheckButton(info)
        end

        -- The delay only means anything while Blizzard's own greeting is
        -- audible, so it sits with the option that controls that.
        if section.title == "Playback" then
            Advance(14)
            local slider = CreateFrame("Slider", addonName .. "AutoPlayDelaySlider", frame, "OptionsSliderTemplate")
            slider:SetPoint("TOPLEFT", frame, "TOPLEFT", RIGHT_X + 8, cursorY)
            slider:SetWidth(220)
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
            AttachTooltip(slider, "Wait before speaking", "How long to hold back so Blizzard's own voice line can finish before SpeakStone speaks. Ignored when those lines are silenced above, because then there is nothing to wait for.")
            Advance(34)
        end
    end

    -- ----------------------------------------------------------------------
    -- Actions. The cards are shortcuts to two of these, not replacements.
    -- ----------------------------------------------------------------------
    local buttons = {
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
    }

    local previous
    for _, spec in ipairs(buttons) do
        local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        button:SetSize(spec.width or 170, 24)
        button:SetText(spec.text)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 8, 0)
        else
            button:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", LEFT_X, 14)
        end
        button:SetScript("OnClick", spec.onClick)
        AttachTooltip(button, spec.text, spec.tooltip)
        previous = button
    end

    -- ----------------------------------------------------------------------
    -- Keeping the cards true
    -- ----------------------------------------------------------------------
    local function RefreshDashboard()
        if addon.GetInstalledAudioSummary then
            local packs, clips, quests = addon.GetInstalledAudioSummary()
            if clips == 0 then
                SetCardState(cards.packs, ACCENT_BAD, "None installed",
                    "The addon has nothing to play until you add one. Get a pack at " .. WEBSITE .. ".")
            else
                local names = {}
                for _, pack in ipairs(packs) do table.insert(names, pack.name) end
                SetCardState(cards.packs, ACCENT_GOOD, clips,
                    string.format("clip(s) across %d quest(s)\n%s", quests, table.concat(names, ", ")))
            end
        end

        -- Whether capture is running is not a fact about the counts, so it is
        -- set outside the block below: with the capture module absent, the
        -- card used to be left blank rather than saying anything.
        if StandaloneHarvesterActive() then
            SetCardState(cards.capture, ACCENT_NEUTRAL, "Harvester",
                "The standalone Harvester addon is installed and is doing the capturing; SpeakStone's own capture is standing down.")
        elseif QuestReaderAddonDB.harvestEnabled then
            SetCardState(cards.capture, ACCENT_GOOD, "Recording",
                "Quest text, greetings and books are being recorded as you meet them.")
        else
            SetCardState(cards.capture, ACCENT_BAD, "Off",
                "Nothing new is being recorded. Turn on capture under Contribute.")
        end

        if addon.HarvestCounts then
            local capturedQuests, passages, _, npcs, glines, items, pages = addon.HarvestCounts()
            -- Greetings and books lead. Neither has a table in the client nor
            -- a scrapeable equivalent, so capture is the only way they can
            -- ever be obtained; quest text can be sourced other ways.
            SetCardState(cards.captured, ACCENT_NEUTRAL, glines,
                string.format("greeting(s) from %d NPC(s)\n%d page(s) in %d book(s) - %d quest(s), %d passage(s)",
                    npcs, pages, items, capturedQuests, passages))
        end
    end

    addon.RefreshSettingsStatus = RefreshDashboard
    frame:SetScript("OnShow", RefreshDashboard)
    RefreshDashboard()

    addon.settingsWindow = frame
    return frame
end

-- The game's own AddOns list still needs an entry, or the addon looks absent
-- from Options entirely. It is a doorway now, not the settings themselves.
function SpeakStone:CreateSettings()
    self:CreateWindow()

    local optionsFrame = CreateFrame("Frame", nil, nil, "VerticalLayoutFrame")
    optionsFrame.spacing = 8
    -- Textures resolve from the game root, not the addon folder, so the
    -- path needs the Interface\\AddOns prefix -- without it the escape drew
    -- nothing at all.
    local category = Settings.RegisterCanvasLayoutCategory(optionsFrame, "SpeakStone |TInterface\\AddOns\\" .. addonName .. "\\cs_icon.tga:18:18:0:0|t")
    addon.settingsCategoryID = category.ID
    Settings.RegisterAddOnCategory(category)

    local header = CreateFrame("Frame", nil, optionsFrame)
    header:SetSize(400, 50)
    local headerText = header:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    headerText:SetPoint("TOPLEFT", 7, -22)
    headerText:SetText("SpeakStone")
    local divider = header:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas("Options_HorizontalDivider", true)
    divider:SetPoint("BOTTOMLEFT", -50)
    header.layoutIndex = 1
    header.bottomPadding = 10

    local blurbFrame = CreateFrame("Frame", nil, optionsFrame)
    blurbFrame:SetSize(500, 40)
    blurbFrame.layoutIndex = 2
    blurbFrame.bottomPadding = 8
    local blurb = blurbFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    blurb:SetPoint("TOPLEFT", blurbFrame, "TOPLEFT", 7, 0)
    blurb:SetWidth(490)
    blurb:SetJustifyH("LEFT")
    blurb:SetSpacing(3)
    blurb:SetText("SpeakStone's settings, voice pack status and captured text all live in its own window.\nOpen it here, with the minimap button, or by typing |cffffd100/ss|r.")

    local openFrame = CreateFrame("Frame", nil, optionsFrame)
    openFrame:SetSize(500, 30)
    openFrame.layoutIndex = 3
    local openButton = CreateFrame("Button", nil, openFrame, "UIPanelButtonTemplate")
    openButton:SetSize(200, 24)
    openButton:SetPoint("TOPLEFT", openFrame, "TOPLEFT", 7, 0)
    openButton:SetText("Open SpeakStone settings")
    openButton:SetScript("OnClick", function()
        HideUIPanel(SettingsPanel)
        addon:OpenSettings()
    end)

    optionsFrame:Layout()
end

-- Function to open settings
function addon:OpenSettings()
    local frame = addon.settingsWindow or SpeakStone:CreateWindow()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

SLASH_QUESTREADER1, SLASH_QUESTREADER2, SLASH_QUESTREADER3, SLASH_QUESTREADER4 = '/qr', '/questreader', '/ss', '/speakstone'
SlashCmdList.QUESTREADER = function(msg)
    addon:OpenSettings()
end
