local ADDON_NAME, Addon = ...

local panel = CreateFrame("Frame")
panel.name = "CPU Load Manager"
Addon.optionsPanel = panel

local headerIcon = panel:CreateTexture(nil, "ARTWORK")
headerIcon:SetSize(32, 32)
headerIcon:SetPoint("TOPLEFT", 16, -10)
headerIcon:SetTexture("Interface\\AddOns\\CPULoadManager\\Assets\\CPULoadManagerIcon")

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("LEFT", headerIcon, "RIGHT", 10, 0)
title:SetText("CPU Load Manager")

local version = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
version:SetPoint("TOPRIGHT", -18, -16)
version:SetText("v" .. (C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "1.2.3") .. "  •  Retail 12.1")

local creator = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
creator:SetPoint("TOPRIGHT", version, "BOTTOMRIGHT", 0, -4)
creator:SetText("by Mimezu")

local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", 16, -50)
subtitle:SetWidth(620)
subtitle:SetJustifyH("LEFT")
subtitle:SetText("Automatically caps CPU-heavy settings for crowded or group content and restores your exact normal values afterward. GPU-only quality settings are not changed.")

local enabled = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
enabled:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -18)
enabled.Text:SetText("Enable automatic CPU profiles")
enabled:SetScript("OnClick", function(self)
    Addon:SetEnabled(self:GetChecked())
end)

local announce = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
announce:SetPoint("TOPLEFT", enabled, "BOTTOMLEFT", 0, -8)
announce.Text:SetText("Print profile changes in chat")
announce:SetScript("OnClick", function(self)
    Addon.db.announce = not not self:GetChecked()
end)

local statusLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
statusLabel:SetPoint("TOPLEFT", announce, "BOTTOMLEFT", 4, -20)
statusLabel:SetText("Current status")

local status = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
status:SetPoint("TOPLEFT", statusLabel, "BOTTOMLEFT", 0, -6)
status:SetWidth(620)
status:SetJustifyH("LEFT")

local debugLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
debugLabel:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -22)
debugLabel:SetText("Debug / manual profile override")

local debugHelp = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
debugHelp:SetPoint("TOPLEFT", debugLabel, "BOTTOMLEFT", 0, -5)
debugHelp:SetWidth(620)
debugHelp:SetJustifyH("LEFT")
debugHelp:SetText("Force any profile for live testing. Choose Automatic detection when finished. Changes wait until combat ends if necessary.")

local manualDropdown = CreateFrame("Frame", "CPULoadManagerManualDropdown", panel, "UIDropDownMenuTemplate")
manualDropdown:SetPoint("TOPLEFT", debugHelp, "BOTTOMLEFT", -16, -5)
UIDropDownMenu_SetWidth(manualDropdown, 240)
UIDropDownMenu_JustifyText(manualDropdown, "LEFT")
UIDropDownMenu_Initialize(manualDropdown, function(self)
    for _, choice in ipairs(Addon.manualChoices) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = choice.label
        info.value = choice.value
        info.checked = Addon.db and Addon.db.manualProfile == choice.value
        info.func = function(button)
            Addon:SetManualProfile(button.value)
            UIDropDownMenu_SetSelectedValue(manualDropdown, button.value)
            UIDropDownMenu_SetText(manualDropdown, Addon:GetManualChoiceLabel(button.value))
        end
        UIDropDownMenu_AddButton(info)
    end
end)

local details = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
details:SetPoint("TOPLEFT", manualDropdown, "BOTTOMLEFT", 16, -18)
details:SetWidth(620)
details:SetJustifyH("LEFT")
details:SetSpacing(5)
details:SetText(
    "Automatic levels:\n" ..
    "• Major city: crowded-player labels, particles, clutter, detail, and view distance\n" ..
    "• 5-player dungeon: minor spell, particle, and world-detail caps\n" ..
    "• Raid group ≤10: moderate caps, inside or outside an instance\n" ..
    "• Raid group 11–24: stronger caps\n" ..
    "• Raid group 25+ or PvP instance: most aggressive CPU caps\n\n" ..
    "Important: projected textures are never disabled. Your normal setting wins whenever it is already lower than a profile cap. Physics is restart-required in Retail, so lower Physics Interactions once manually if wanted. Use /cpuload addcity while standing in an unrecognized hub; /cpuload delcity removes it."
)

local refresh = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
refresh:SetSize(130, 24)
refresh:SetPoint("TOPLEFT", details, "BOTTOMLEFT", 0, -20)
refresh:SetText("Recheck now")
refresh:SetScript("OnClick", function()
    Addon:Evaluate(true)
end)

local benchmark = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
benchmark:SetSize(155, 24)
benchmark:SetPoint("LEFT", refresh, "RIGHT", 10, 0)
benchmark:SetText("Run 15s benchmark")
benchmark:SetScript("OnClick", function()
    Addon:StartBenchmark(15)
end)

local clearBenchmark = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
clearBenchmark:SetSize(140, 24)
clearBenchmark:SetPoint("LEFT", benchmark, "RIGHT", 10, 0)
clearBenchmark:SetText("Clear comparison")
clearBenchmark:SetScript("OnClick", function()
    Addon:ClearBenchmarkComparison()
end)

local benchmarkStatus = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
benchmarkStatus:SetPoint("TOPLEFT", refresh, "BOTTOMLEFT", 0, -9)
benchmarkStatus:SetWidth(620)
benchmarkStatus:SetJustifyH("LEFT")

function Addon:RefreshOptions()
    if not self.db then return end
    enabled:SetChecked(self.db.enabled)
    announce:SetChecked(self.db.announce)
    status:SetText(self:GetStatusText())
    local manual = self.db.manualProfile or "auto"
    UIDropDownMenu_SetSelectedValue(manualDropdown, manual)
    UIDropDownMenu_SetText(manualDropdown, self:GetManualChoiceLabel(manual))
    if self.GetBenchmarkStatus then
        benchmarkStatus:SetText(self:GetBenchmarkStatus())
        benchmark:SetEnabled(not self:IsBenchmarkRunning())
    end
end

panel:SetScript("OnShow", function()
    Addon:RefreshOptions()
end)

if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name, panel.name)
    Settings.RegisterAddOnCategory(category)
    Addon.settingsCategory = category
end

function Addon:OpenOptions()
    if Settings and Settings.OpenToCategory and self.settingsCategory then
        Settings.OpenToCategory(self.settingsCategory:GetID())
    else
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end
