local ADDON_NAME, Addon = ...

local frame = CreateFrame("Frame")
Addon.frame = frame

local DEFAULTS = {
    enabled = true,
    announce = false,
    manualProfile = "auto",
    customCityMaps = {},
    baseline = nil,
    applied = nil,
    released = nil,
}

-- Capital/hub uiMapIDs. Parent maps are followed so interiors inherit their
-- city's profile. Custom IDs cover future hubs without requiring an addon update.
local CITY_MAPS = {
    [84] = true,   -- Stormwind City
    [85] = true,   -- Orgrimmar
    [87] = true,   -- Ironforge
    [88] = true,   -- Thunder Bluff
    [89] = true,   -- Darnassus
    [90] = true,   -- Undercity
    [103] = true,  -- The Exodar
    [110] = true,  -- Silvermoon City
    [111] = true,  -- Shattrath City
    [125] = true,  -- Dalaran (Northrend)
    [627] = true,  -- Dalaran (Broken Isles)
    [1161] = true, -- Boralus
    [1163] = true, -- Dazar'alor interior
    [1164] = true, -- Dazar'alor interior
    [1165] = true, -- Dazar'alor
    [1670] = true, -- Oribos floors
    [1671] = true,
    [1672] = true,
    [1673] = true,
    [2112] = true, -- Valdrakken
    [2339] = true, -- Dornogal
    [2393] = true, -- Silvermoon (Midnight)
    [2443] = true, -- Silvermoon alternate phase (Midnight)
    [2472] = true, -- Tazavesh (K'aresh hub)
    [2576] = true, -- The Den (Harandar hub)
}

-- Every numeric setting below is a ceiling: the addon will never raise a
-- setting above the player's normal value. Projected textures are deliberately
-- untouched because they communicate important encounter mechanics.
local PROFILES = {
    city = {
        label = "Major city / populated hub",
        caps = {
            graphicsSpellDensity = 0,
            graphicsParticleDensity = 1,
            graphicsEnvironmentDetail = 3,
            graphicsGroundClutter = 1,
            graphicsViewDistance = 4,
            weatherDensity = 0,
            Sound_NumChannels = 64,
        },
        force = {
            nameplateShowFriends = "0",
            UnitNameFriendlyPlayerName = "0",
            Sound_EnableReverb = "0",
            Sound_EnablePositionalLowPassFilter = "0",
        },
    },
    party = {
        label = "5-player dungeon",
        caps = {
            graphicsSpellDensity = 2,
            graphicsParticleDensity = 4,
            graphicsEnvironmentDetail = 8,
            graphicsGroundClutter = 8,
            graphicsViewDistance = 8,
        },
    },
    raid10 = {
        label = "Raid group (10 or fewer)",
        caps = {
            graphicsSpellDensity = 1,
            graphicsParticleDensity = 3,
            graphicsEnvironmentDetail = 5,
            graphicsGroundClutter = 6,
            graphicsViewDistance = 7,
            Sound_NumChannels = 96,
        },
    },
    raid20 = {
        label = "Raid group (11-24)",
        caps = {
            graphicsSpellDensity = 1,
            graphicsParticleDensity = 2,
            graphicsEnvironmentDetail = 5,
            graphicsGroundClutter = 4,
            graphicsViewDistance = 5,
            Sound_NumChannels = 64,
        },
        force = {
            Sound_EnableReverb = "0",
            Sound_EnablePositionalLowPassFilter = "0",
        },
    },
    large = {
        label = "Raid group (25+) / PvP instance",
        caps = {
            graphicsSpellDensity = 0,
            graphicsParticleDensity = 1,
            graphicsEnvironmentDetail = 3,
            graphicsGroundClutter = 1,
            graphicsViewDistance = 3,
            weatherDensity = 0,
            -- Keep at least 64 so simultaneous boss-mod and encounter sounds
            -- are not starved, while still reducing unusually high baselines.
            Sound_NumChannels = 64,
        },
        force = {
            Sound_EnableReverb = "0",
            Sound_EnablePositionalLowPassFilter = "0",
        },
    },
}

Addon.manualChoices = {
    { value = "auto", label = "Automatic detection" },
    { value = "normal", label = "Normal settings (no profile)" },
    { value = "city", label = "Major city / populated hub" },
    { value = "party", label = "5-player dungeon" },
    { value = "raid10", label = "Raid group (10 or fewer)" },
    { value = "raid20", label = "Raid group (11-24)" },
    { value = "large", label = "Raid group (25+) / PvP instance" },
}

function Addon:GetManualChoiceLabel(value)
    for _, choice in ipairs(self.manualChoices) do
        if choice.value == value then return choice.label end
    end
    return self.manualChoices[1].label
end

-- Retail stores a separate set of graphics values when Raid Graphics is
-- enabled. Manage both copies independently without changing RAIDsettingsEnabled.
local RAID_EQUIVALENTS = {
    graphicsSpellDensity = "raidGraphicsSpellDensity",
    graphicsParticleDensity = "raidGraphicsParticleDensity",
    graphicsEnvironmentDetail = "raidGraphicsEnvironmentDetail",
    graphicsGroundClutter = "raidGraphicsGroundClutter",
    graphicsViewDistance = "raidGraphicsViewDistance",
}
local BASE_FOR_RAID = {}
for baseCVar, raidCVar in pairs(RAID_EQUIVALENTS) do
    BASE_FOR_RAID[raidCVar] = baseCVar
end

local MANAGED_CVARS = {}
for _, profile in pairs(PROFILES) do
    for cvar in pairs(profile.caps or {}) do
        MANAGED_CVARS[cvar] = true
        if RAID_EQUIVALENTS[cvar] then
            MANAGED_CVARS[RAID_EQUIVALENTS[cvar]] = true
        end
    end
    for cvar in pairs(profile.force or {}) do
        MANAGED_CVARS[cvar] = true
    end
end

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff55c7ffCPU Load Manager:|r " .. message)
end
Addon.Print = Print

local function GetCVarSafe(cvar)
    local ok, value = pcall(C_CVar.GetCVar, cvar)
    if ok and value ~= nil then
        return tostring(value)
    end
end

local function SetCVarSafe(cvar, value)
    value = tostring(value)
    local current = GetCVarSafe(cvar)
    if current == nil or current == value then
        return current ~= nil
    end
    local infoOK, info = pcall(C_CVar.GetCVarInfo, cvar)
    if infoOK and type(info) == "table" and
        (info.isReadOnly or info.isSecure or info.isLockedFromUser) then
        return false
    end
    local setOK, result = pcall(C_CVar.SetCVar, cvar, value)
    return setOK and result ~= false
end

local function CopyDefaults()
    CPULoadManagerDB = CPULoadManagerDB or {}
    for key, value in pairs(DEFAULTS) do
        if CPULoadManagerDB[key] == nil then
            CPULoadManagerDB[key] = value
        end
    end
    if type(CPULoadManagerDB.customCityMaps) ~= "table" then
        CPULoadManagerDB.customCityMaps = {}
    end
    Addon.db = CPULoadManagerDB
end

local function CaptureBaseline()
    if Addon.db.baseline then
        return
    end

    local baseline = {}
    for cvar in pairs(MANAGED_CVARS) do
        local value = GetCVarSafe(cvar)
        if value ~= nil then
            baseline[cvar] = value
        end
    end
    Addon.db.baseline = baseline
    Addon.db.applied = {}
    Addon.db.released = {}
end

local function RestoreBaseline()
    local baseline = Addon.db and Addon.db.baseline
    if not baseline then
        return
    end

    local applied = Addon.db.applied or {}
    for cvar, value in pairs(baseline) do
        local current = GetCVarSafe(cvar)
        -- Restore only values still owned by the addon. A manual edit made
        -- while a profile was active is preserved.
        if applied[cvar] ~= nil and current == tostring(applied[cvar]) then
            SetCVarSafe(cvar, value)
        end
    end
    Addon.db.baseline = nil
    Addon.db.applied = nil
    Addon.db.released = nil
end

local function IsCityOrHub()
    local inInstance = IsInInstance()
    if inInstance then return false end

    local mapID = C_Map.GetBestMapForUnit("player")
    local checked = 0
    while mapID and checked < 8 do
        if CITY_MAPS[mapID] or Addon.db.customCityMaps[mapID] then
            return true
        end
        local mapInfo = C_Map.GetMapInfo(mapID)
        mapID = mapInfo and mapInfo.parentMapID
        checked = checked + 1
    end
    return false
end

function Addon:GetCurrentMapID()
    return C_Map.GetBestMapForUnit("player")
end

function Addon:SetCurrentMapAsCity(enabled)
    local mapID = self:GetCurrentMapID()
    if not mapID then return false end
    self.db.customCityMaps[mapID] = enabled and true or nil
    self:Evaluate(true)
    return true, mapID
end

local function SelectProfile()
    local manual = Addon.db.manualProfile
    if manual == "normal" then
        return nil
    elseif PROFILES[manual] then
        return manual
    end

    local inInstance, instanceType = IsInInstance()
    local inRaid = IsInRaid()
    local groupSize = GetNumGroupMembers() or 0

    if inInstance and (instanceType == "pvp" or instanceType == "arena") then
        return "large"
    end

    -- A very large raid remains the strongest profile even while gathered in a city.
    if inRaid and groupSize >= 25 then
        return "large"
    end

    if IsCityOrHub() then
        return "city"
    end

    if inInstance and (instanceType == "party" or instanceType == "scenario") then
        return "party"
    end

    -- Raid-group profiles also apply outdoors, as requested.
    if inRaid then
        if groupSize <= 10 then
            return "raid10"
        end
        return "raid20"
    end

    return nil
end

local function ApplyProfile(profileKey)
    local profile = PROFILES[profileKey]
    if not profile then
        RestoreBaseline()
        Addon.activeProfile = nil
        return
    end

    CaptureBaseline()
    local baseline = Addon.db.baseline or {}
    local applied = Addon.db.applied or {}
    local released = Addon.db.released or {}

    for cvar in pairs(MANAGED_CVARS) do
        local normal = baseline[cvar]
        local current = GetCVarSafe(cvar)
        local previous = applied[cvar]

        -- If the current value no longer matches our last write, the player or
        -- another addon changed it. Relinquish this CVar until normal settings
        -- are restored so their choice wins.
        if previous ~= nil and current ~= tostring(previous) then
            released[cvar] = true
            applied[cvar] = nil
        end

        if normal ~= nil and not released[cvar] then
            local desired = normal
            local ceiling = profile.caps and profile.caps[cvar]
            if ceiling == nil and BASE_FOR_RAID[cvar] and profile.caps then
                ceiling = profile.caps[BASE_FOR_RAID[cvar]]
            end
            if ceiling ~= nil and tonumber(normal) then
                desired = tostring(math.min(tonumber(normal), ceiling))
            elseif profile.force and profile.force[cvar] ~= nil then
                desired = tostring(profile.force[cvar])
            end

            if desired ~= tostring(normal) then
                if SetCVarSafe(cvar, desired) then
                    applied[cvar] = desired
                else
                    applied[cvar] = nil
                end
            else
                if previous ~= nil and current == tostring(previous) then
                    SetCVarSafe(cvar, normal)
                end
                applied[cvar] = nil
            end
        end
    end

    Addon.db.applied = applied
    Addon.db.released = released
    Addon.activeProfile = profileKey
end

function Addon:GetStatusText()
    if not self.db or not self.db.enabled then
        if self.db and self.db.baseline and InCombatLockdown() then
            return "Disabled — restoration queued until combat ends"
        end
        return "Disabled — normal settings restored"
    end
    local manual = self.db.manualProfile
    if self.pendingAfterCombat and manual ~= "auto" then
        return "Queued until combat ends: " .. self:GetManualChoiceLabel(manual)
    end
    if manual == "normal" then
        return "Manual override: Normal settings"
    elseif PROFILES[manual] then
        return "Manual override: " .. PROFILES[manual].label
    end
    if self.activeProfile and PROFILES[self.activeProfile] then
        return "Active: " .. PROFILES[self.activeProfile].label
    end
    return "Enabled — using your normal settings"
end

function Addon:Evaluate(force)
    if not self.db then
        return
    end

    if InCombatLockdown() then
        self.pendingAfterCombat = true
        if self.RefreshOptions then self:RefreshOptions() end
        return
    end
    self.pendingAfterCombat = nil

    if not self.db.enabled then
        RestoreBaseline()
        self.activeProfile = nil
        if self.RefreshOptions then self:RefreshOptions() end
        return
    end

    local selected = SelectProfile()
    if force or selected ~= self.activeProfile then
        if selected ~= self.activeProfile and self.IsBenchmarkRunning and self:IsBenchmarkRunning() then
            self:CancelBenchmark("Context/profile changed; benchmark cancelled to keep the sample valid.")
        end
        local oldProfile = self.activeProfile
        ApplyProfile(selected)
        if self.db.announce and oldProfile ~= selected then
            Print(self:GetStatusText())
        end
        if self.RefreshOptions then self:RefreshOptions() end
    end
end

function Addon:SetEnabled(enabled)
    if self.IsBenchmarkRunning and self:IsBenchmarkRunning() then
        self:CancelBenchmark("Addon state changed; benchmark cancelled.")
    end
    self.db.enabled = not not enabled
    self:Evaluate(true)
end

function Addon:SetManualProfile(value)
    local valid = value == "auto" or value == "normal" or PROFILES[value] ~= nil
    if not valid then return false end
    if self.IsBenchmarkRunning and self:IsBenchmarkRunning() then
        self:CancelBenchmark("Manual profile changed; benchmark cancelled.")
    end
    self.db.manualProfile = value
    self:Evaluate(true)
    return true
end

local pendingEvaluation
function Addon:ScheduleEvaluation(delay)
    if pendingEvaluation then
        pendingEvaluation:Cancel()
    end
    pendingEvaluation = C_Timer.NewTimer(delay or 0.5, function()
        pendingEvaluation = nil
        Addon:Evaluate(false)
    end)
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("ZONE_CHANGED")
frame:RegisterEvent("ZONE_CHANGED_INDOORS")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("PLAYER_UPDATE_RESTING")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        CopyDefaults()
        Addon:ScheduleEvaluation(1)
    elseif event == "PLAYER_LOGOUT" then
        -- Never leave capped values behind if the addon is disabled before the
        -- next login. The active context will be evaluated again after login.
        RestoreBaseline()
        Addon.activeProfile = nil
    elseif event == "PLAYER_REGEN_ENABLED" then
        if Addon.pendingAfterCombat then
            Addon:Evaluate(true)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        Addon:ScheduleEvaluation(2)
    else
        Addon:ScheduleEvaluation(0.5)
    end
end)

SLASH_CPULOADMANAGER1 = "/cpuload"
SLASH_CPULOADMANAGER2 = "/clm"
SlashCmdList.CPULOADMANAGER = function(input)
    local raw = strtrim(input or ""):lower()
    local command, argument = raw:match("^(%S+)%s*(.-)$")
    command = command or ""
    if command == "on" then
        Addon:SetEnabled(true)
        Print(Addon:GetStatusText())
    elseif command == "off" then
        Addon:SetEnabled(false)
        Print(Addon:GetStatusText())
    elseif command == "status" then
        Print(Addon:GetStatusText())
    elseif command == "refresh" then
        Addon:Evaluate(true)
        Print(Addon:GetStatusText())
    elseif command == "force" then
        if Addon:SetManualProfile(argument) then
            Print(Addon:GetStatusText())
        else
            Print("Force values: auto, normal, city, party, raid10, raid20, large")
        end
    elseif command == "benchmark" or command == "bench" then
        local ok, message = Addon:StartBenchmark(argument)
        if not ok then Print(message) end
    elseif command == "benchclear" then
        Addon:ClearBenchmarkComparison()
    elseif command == "addcity" then
        local ok, mapID = Addon:SetCurrentMapAsCity(true)
        Print(ok and ("Added current map " .. mapID .. " as a city/hub.") or "No current map is available.")
    elseif command == "delcity" then
        local ok, mapID = Addon:SetCurrentMapAsCity(false)
        Print(ok and ("Removed current map " .. mapID .. " from custom cities/hubs.") or "No current map is available.")
    elseif Addon.OpenOptions then
        Addon:OpenOptions()
    else
        Print("Commands: /cpuload on, off, status, refresh, force, benchmark, benchclear, addcity, delcity")
    end
end
