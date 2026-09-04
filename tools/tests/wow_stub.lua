-- A stand-in for the parts of the WoW client the addon touches.
--
-- The addon cannot be run outside the game, and the faults worth testing are
-- the ones that live in time: a clip queued behind the autoplay delay, a
-- timer that outlives the clip it was scheduled for, a channel muted by one
-- code path and released by another. None of those can be reasoned about
-- reliably by reading, and all of them are cheap to drive if the clock is
-- something the test holds rather than something it waits for.
--
-- So this is deliberately thin. It is not an emulator and does not try to be
-- faithful: frames do nothing but remember their scripts, sound files are
-- recorded rather than played, and time only moves when a test says so.
-- Anything the addon calls that a test does not care about resolves to a
-- no-op, so adding a widget to the UI does not break the suite.

local M = {}

-- Every global this installs, so a second install for the next spec starts
-- from the same place rather than inheriting the last one's state.
local OWNED = {
    "C_Timer", "C_AddOns", "C_QuestLog", "C_GossipInfo", "CreateFrame", "LibStub",
    "PlaySoundFile", "StopSound", "GetCVar", "SetCVar", "UISpecialFrames",
    "SlashCmdList", "Minimap", "QuestFrame", "QuestFrameDetailPanel",
    "QuestFrameProgressPanel", "QuestFrameRewardPanel", "QuestMapFrame",
    "GetQuestID", "GetQuestText", "GetProgressText", "GetRewardText",
    "GetTitleText", "UnitGUID", "UnitName", "UnitExists", "UnitIsUnit",
    "UnitSex", "UnitRace", "UnitClass", "UnitCreatureType", "UnitFactionGroup",
    "ItemTextGetItem", "ItemTextGetPage", "ItemTextGetText", "GetLocale",
    "GetBuildInfo", "hooksecurefunc", "strsplit", "tinsert", "wipe", "time",
    "issecretvalue", "SecretUtil", "GameTooltip", "Settings", "EventUtil",
    "FauxScrollFrame_Update", "FauxScrollFrame_GetOffset",
    "FauxScrollFrame_OnVerticalScroll", "debugprofilestop", "StaticPopupDialogs",
    "StaticPopup_Show", "HideUIPanel", "SettingsPanel", "UIParent",
    "QuestReaderAddonDB", "QuestReaderSoundLengths", "QuestReaderHarvesterDB",
    "PlayQuestAudio", "QuestReaderAddon_RegisterSoundPack",
    "QuestReaderPendingSoundPacks", "YES", "NO",
}

--- Install the stub into the globals and hand back the controls a test needs.
---
--- @param soundLengths table  the clip index the addon should see, as a voice
---                            pack would supply it ("<file>" -> seconds)
--- @return table  { advance, fire, frames, played, stopped, cvars, timers }
function M.install(soundLengths)
    for _, name in ipairs(OWNED) do _G[name] = nil end

    local env = {}

    -- ----------------------------------------------------------------------
    -- Time. Nothing here waits; the test moves the clock and the timers due
    -- by then run in the order they were scheduled.
    -- ----------------------------------------------------------------------
    local clock, seq = 0, 0
    local timers = {}
    env.timers = timers

    local function NewTimer(delay, fn)
        seq = seq + 1
        local timer = { at = clock + delay, fn = fn, seq = seq }
        timers[timer] = true
        function timer:Cancel()
            self.cancelled = true
            timers[self] = nil
        end
        return timer
    end

    --- Move the clock forward, running whatever falls due.
    function env.advance(seconds)
        clock = clock + seconds
        local due = {}
        for timer in pairs(timers) do
            if timer.at <= clock then due[#due + 1] = timer end
        end
        table.sort(due, function(a, b) return a.seq < b.seq end)
        for _, timer in ipairs(due) do
            -- A timer cancelled by an earlier one in this same batch must not
            -- still fire: this is exactly the case the addon relies on.
            if timers[timer] then
                timers[timer] = nil
                timer.fn()
            end
        end
    end

    --- How many timers are still waiting. A test that ends with any left has
    --- found something the addon meant to cancel and did not.
    function env.liveTimers()
        local n = 0
        for _ in pairs(timers) do n = n + 1 end
        return n
    end

    _G.C_Timer = {
        After = function(delay, fn) NewTimer(delay, fn) end,
        NewTimer = NewTimer,
    }

    -- ----------------------------------------------------------------------
    -- Frames. A frame remembers its scripts and its registered events and
    -- does nothing else. Show and Hide fire OnShow/OnHide, because several of
    -- the addon's decisions -- what to index, what to listen for -- hang off
    -- those rather than off the call that opened the window.
    -- ----------------------------------------------------------------------
    local frames = {}
    env.frames = frames

    local frameMT = {}
    frameMT.__index = function(_, key)
        local method = rawget(frameMT, key)
        if method then return method end
        -- Frame methods are PascalCase and the addon's own fields are not, so
        -- an unknown capitalised name is a widget call worth swallowing and
        -- anything else is a field that is genuinely absent. Returning a
        -- no-op for both would make every "is this set?" test true.
        if type(key) == "string" and key:match("^%u") then
            return function() return nil end
        end
        return nil
    end

    function frameMT:RegisterEvent(event) self.events[event] = true end
    function frameMT:UnregisterEvent(event) self.events[event] = nil end
    function frameMT:UnregisterAllEvents() self.events = {} end
    function frameMT:IsEventRegistered(event) return self.events[event] or false end
    function frameMT:SetScript(name, fn) self.scripts[name] = fn end
    function frameMT:GetScript(name) return self.scripts[name] end
    function frameMT:HookScript(name, fn) self.hooks[#self.hooks + 1] = { name, fn } end
    function frameMT:IsVisible() return self.visible end
    function frameMT:IsShown() return self.visible end
    function frameMT:GetSize() return 100, 100 end
    function frameMT:GetWidth() return 100 end
    function frameMT:GetHeight() return 100 end
    function frameMT:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
    function frameMT:GetText() return self.text or "" end
    function frameMT:SetText(value) self.text = value end
    function frameMT:CreateFontString() return M.newFrame() end
    function frameMT:CreateTexture() return M.newFrame() end

    function frameMT:Show()
        local was = self.visible
        self.visible = true
        if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
    end

    function frameMT:Hide()
        local was = self.visible
        self.visible = false
        if was and self.scripts.OnHide then self.scripts.OnHide(self) end
    end

    function M.newFrame()
        return setmetatable({ events = {}, scripts = {}, hooks = {}, visible = false }, frameMT)
    end

    _G.CreateFrame = function(_, name, _, template)
        local frame = M.newFrame()
        if template then
            -- The pieces the Blizzard templates bring with them, for the
            -- windows built on top of them.
            frame.TitleText = M.newFrame()
            frame.InsetBg = M.newFrame()
            frame.Instructions = M.newFrame()
        end
        frames[#frames + 1] = frame
        if name then _G[name] = frame end
        return frame
    end

    --- Deliver an event to a frame, as the client would -- only if it asked.
    function env.fire(frame, event, ...)
        if frame.events[event] and frame.scripts.OnEvent then
            frame.scripts.OnEvent(frame, event, ...)
        end
    end

    --- Whether anything at all is listening for an event.
    function env.isListening(event)
        for _, frame in ipairs(frames) do
            if frame.events[event] then return true end
        end
        return false
    end

    -- ----------------------------------------------------------------------
    -- Sound. Recorded, not played: what matters is which file went to which
    -- channel, how many times, and what was stopped.
    -- ----------------------------------------------------------------------
    env.played, env.stopped = {}, {}
    local handle = 0

    _G.PlaySoundFile = function(path, channel)
        handle = handle + 1
        env.played[#env.played + 1] = { path = path, channel = channel, handle = handle }
        return true, handle
    end
    _G.StopSound = function(h) env.stopped[#env.stopped + 1] = h end

    --- Forget what has been played so far, so a test can speak about one
    --- interaction rather than the whole session.
    function env.resetSound()
        env.played, env.stopped = {}, {}
    end

    env.cvars = { Sound_DialogVolume = "1" }
    _G.GetCVar = function(key) return env.cvars[key] end
    _G.SetCVar = function(key, value) env.cvars[key] = value end

    -- ----------------------------------------------------------------------
    -- Libraries the addon pulls in at file scope.
    -- ----------------------------------------------------------------------
    local libs = {
        ["LibDataBroker-1.1"] = {
            NewDataObject = function(_, _, dataObject) return dataObject end,
        },
        ["LibDBIcon-1.0"] = {
            Register = function() end,
            Show = function() end,
            Hide = function() end,
            GetMinimapButton = function() return nil end,
        },
    }
    _G.LibStub = function(name) return libs[name] end

    -- ----------------------------------------------------------------------
    -- The rest of the client surface. Tests override what they care about.
    -- ----------------------------------------------------------------------
    _G.QuestReaderSoundLengths = soundLengths or {}

    _G.C_AddOns = {
        GetAddOnInfo = function() return nil end,
        IsAddOnLoaded = function() return false end,
        LoadAddOn = function() return false end,
        GetAddOnMetadata = function() return "test" end,
    }
    _G.C_QuestLog = {
        GetSelectedQuest = function() return nil end,
        GetTitleForQuestID = function(questID) return "Quest " .. tostring(questID) end,
        RequestLoadQuestByID = function() end,
    }
    _G.C_GossipInfo = { GetText = function() return "" end }

    _G.UIParent = M.newFrame()
    _G.Minimap = M.newFrame()
    _G.GameTooltip = M.newFrame()
    _G.SettingsPanel = M.newFrame()
    _G.QuestFrame = M.newFrame()
    _G.QuestFrameDetailPanel = M.newFrame()
    _G.QuestFrameProgressPanel = M.newFrame()
    _G.QuestFrameRewardPanel = M.newFrame()
    _G.QuestMapFrame = M.newFrame()
    _G.UISpecialFrames = {}
    _G.SlashCmdList = {}
    _G.StaticPopupDialogs = {}
    _G.StaticPopup_Show = function() end
    _G.HideUIPanel = function() end
    _G.YES, _G.NO = "Yes", "No"

    -- Which quest the client believes is on screen. Set by the test.
    env.questID = 0
    _G.GetQuestID = function() return env.questID end
    _G.GetQuestText = function() return "description text" end
    _G.GetProgressText = function() return "progress text" end
    _G.GetRewardText = function() return "reward text" end
    _G.GetTitleText = function() return "A Quest" end

    _G.UnitGUID = function() return nil end
    _G.UnitName = function(unit) return unit == "player" and "Tester" or nil end
    _G.UnitExists = function() return false end
    _G.UnitIsUnit = function() return false end
    _G.UnitSex = function() return 1 end
    _G.UnitRace = function() return nil end
    _G.UnitClass = function() return nil end
    _G.UnitCreatureType = function() return nil end
    _G.UnitFactionGroup = function() return "Alliance" end

    _G.ItemTextGetItem = function() return nil end
    _G.ItemTextGetPage = function() return 1 end
    _G.ItemTextGetText = function() return "" end

    _G.GetLocale = function() return "enUS" end
    _G.GetBuildInfo = function() return "12.0.0", "60000" end
    _G.hooksecurefunc = function() end
    _G.strsplit = function(_, str) return str end
    _G.tinsert = table.insert
    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    _G.time = os.time
    _G.debugprofilestop = function() return os.clock() * 1000 end

    _G.FauxScrollFrame_Update = function() end
    _G.FauxScrollFrame_GetOffset = function() return 0 end
    _G.FauxScrollFrame_OnVerticalScroll = function() end

    -- The addon's settings file registers through these; nothing in the
    -- suite drives the options panel, so they only have to exist.
    _G.EventUtil = { ContinueOnAddOnLoaded = function() end }
    _G.Settings = {
        RegisterCanvasLayoutCategory = function() return { ID = "test" } end,
        RegisterAddOnCategory = function() end,
    }

    return env
end

return M
