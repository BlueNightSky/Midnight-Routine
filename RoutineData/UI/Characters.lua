local _, ns = ...
local RoutineData = ns.RoutineData
local API = RoutineData.API
local L = LibStub("AceLocale-3.0"):GetLocale("RoutineData")
local category, panel, search, summary, scroll, content, empty
local rows, buttons, filters = {}, {}, {}
local sortMode, hiddenOnly = "name", false
local Refresh
local function Text(parent, font, x, y, width, value)
    local text = parent:CreateFontString(nil, "OVERLAY", font)
    text:SetPoint("TOPLEFT", x, y)
    text:SetWidth(width)
    text:SetJustifyH("LEFT")
    text:SetText(value or "")
    return text
end
local function Button(parent, label, width, x, y, handler)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 24)
    button:SetPoint("TOPLEFT", x, y)
    button:SetText(label)
    button:SetScript("OnClick", handler)
    return button
end
local function HiddenCharacters()
    local settings = RoutineData.db.settings
    if type(settings.hiddenCharacters) ~= "table" then settings.hiddenCharacters = {} end
    return settings.hiddenCharacters
end
function RoutineData:IsCharacterHidden(key)
    return HiddenCharacters()[key] == true
end
function RoutineData:SetCharacterHidden(key, hidden)
    HiddenCharacters()[key] = hidden and true or nil
    self:Fire("CharacterVisibilityChanged", key)
end
local function Money(value)
    return GetMoneyString and GetMoneyString(value, true) or tostring(value)
end
local function Updated(timestamp)
    if timestamp <= 0 then return L["Roster_Unknown"] end
    local age = math.max(0, GetServerTime() - timestamp)
    if age < 60 then return L["Roster_Now"] end
    if age < 3600 then return string.format(L["Roster_Minutes"], math.floor(age / 60)) end
    if age < 86400 then return string.format(L["Roster_Hours"], math.floor(age / 3600)) end
    return string.format(L["Roster_Days"], math.floor(age / 86400))
end
local function CreateRow(index)
    local row = CreateFrame("Button", nil, content)
    row:SetHeight(54)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * 54)
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * 54)
    local background = row:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.12, 0.16, 0.18, index % 2 == 0 and 0.94 or 0.72)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.visibility = Button(row, "", 64, 528, -15, function()
        RoutineData:SetCharacterHidden(row.key, not RoutineData:IsCharacterHidden(row.key))
        Refresh()
    end)
    row.name = Text(row, "GameFontNormal", 12, -10, 230)
    row.realm = Text(row, "GameFontHighlightSmall", 12, -30, 230)
    row.gold = Text(row, "GameFontHighlight", 248, -12, 154)
    row.updated = Text(row, "GameFontHighlightSmall", 408, -12, 112)
    row.current = Text(row, "GameFontNormalSmall", 408, -31, 112)
    row:SetScript("OnEnter", function(self)
        local info = self.info
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(RoutineData.CharacterLabel(info.key, info.classFile))
        if info.realm ~= "" then GameTooltip:AddLine(info.realm, 0.7, 0.7, 0.7) end
        GameTooltip:AddDoubleLine(L["Roster_Gold"], Money(info.gold))
        if info.lastSyncAt > 0 then GameTooltip:AddDoubleLine(L["Roster_Updated"], date("%Y-%m-%d %H:%M", info.lastSyncAt)) end
        if info.mythicPlusScore and info.mythicPlusScore > 0 then GameTooltip:AddDoubleLine(L["Roster_Score"], tostring(info.mythicPlusScore)) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[index] = row
    return row
end
Refresh = function(resetScroll)
    if not panel or not RoutineData.db then return end
    local hidden = HiddenCharacters()
    local query = string.lower(search:GetText() or "")
    local totalGold, total, entries = 0, 0, {}
    local visibleCount, hiddenCount = 0, 0
    for _, key in ipairs(API.GetCharacters()) do
        local info = API.GetCharacterInfo(key)
        if info then
            if hidden[key] then hiddenCount = hiddenCount + 1 else visibleCount = visibleCount + 1 end
            if (hidden[key] == true) == hiddenOnly then
                total = total + 1
                totalGold = totalGold + info.gold
            end
            local matches = query == "" or string.find(string.lower(key .. " " .. (info.classFile or "")), query, 1, true)
            if matches and ((hidden[key] == true) == hiddenOnly) then entries[#entries + 1] = info end
        end
    end
    table.sort(entries, function(a, b)
        if sortMode == "gold" and a.gold ~= b.gold then return a.gold > b.gold end
        if sortMode == "recent" and a.lastSyncAt ~= b.lastSyncAt then return a.lastSyncAt > b.lastSyncAt end
        return string.lower(a.key) < string.lower(b.key)
    end)
    summary:SetText(string.format(L["Roster_Summary"], #entries, total, Money(totalGold)))
    filters.visible:SetText(L["Roster_Visible"] .. " (" .. visibleCount .. ")")
    filters.hidden:SetText(L["Roster_Hidden"] .. " (" .. hiddenCount .. ")")
    filters.visible:SetEnabled(hiddenOnly)
    filters.hidden:SetEnabled(not hiddenOnly)
    local current = RoutineData:GetCurrentCharacterKey()
    for index, info in ipairs(entries) do
        local row = rows[index] or CreateRow(index)
        row.key, row.info = info.key, info
        row.visibility:SetText(hidden[info.key] and L["Roster_Show"] or L["Roster_Hide"])
        local color = info.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[info.classFile]
        row.name:SetText(color and color:WrapTextInColorCode(info.name) or info.name)
        row.realm:SetText(info.realm ~= "" and info.realm or L["Roster_Regional"])
        row.gold:SetText(Money(info.gold))
        row.updated:SetText(Updated(info.lastSyncAt))
        row.current:SetText(hidden[info.key] and "|cffff5555" .. L["Roster_Hidden"] .. "|r" or (info.key == current and L["Roster_Current"] or ""))
        row:Show()
    end
    for index = #entries + 1, #rows do rows[index]:Hide() end
    content:SetHeight(math.max(1, #entries * 54))
    empty:SetText(total == 0 and L["Roster_Empty"] or L["Roster_NoMatches"])
    empty:SetShown(#entries == 0)
    local maximum = math.max(0, content:GetHeight() - scroll:GetHeight())
    scroll:SetVerticalScroll(resetScroll and 0 or math.min(scroll:GetVerticalScroll(), maximum))
    for mode, button in pairs(buttons) do button:SetEnabled(mode ~= sortMode) end
end
function RoutineData:OpenRoster()
    if category and Settings and Settings.OpenToCategory then Settings.OpenToCategory(category:GetID()) end
end
function RoutineData:RegisterRosterOptions(parentCategory)
    if not Settings.RegisterCanvasLayoutSubcategory then return end
    panel = CreateFrame("Frame", "RoutineDataCharacterRoster", UIParent)
    panel:Hide()
    Text(panel, "GameFontNormalLarge", 16, -16, 600, L["Roster_Title"])
    Text(panel, "GameFontHighlightSmall", 16, -45, 600, L["Roster_Description"])
    local surface = panel:CreateTexture(nil, "BACKGROUND")
    surface:SetPoint("TOPLEFT", 8, -62)
    surface:SetPoint("BOTTOMLEFT", 8, 12)
    surface:SetWidth(632)
    surface:SetColorTexture(0.025, 0.035, 0.045, 0.96)
    summary = Text(panel, "GameFontHighlight", 28, -78, 580)
    Text(panel, "GameFontNormalSmall", 28, -112, 400, L["Roster_Search"])
    search = CreateFrame("EditBox", "RoutineDataRosterSearch", panel, "InputBoxTemplate")
    search:SetSize(440, 26)
    search:SetPoint("TOPLEFT", 34, -130)
    search:SetAutoFocus(false)
    search:SetMaxLetters(100)
    search:SetScript("OnTextChanged", function() Refresh(true) end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    Button(panel, L["Roster_Clear"], 100, 500, -131, function() search:SetText(""); search:ClearFocus() end)
    filters.visible = Button(panel, L["Roster_Visible"], 126, 24, -170, function() hiddenOnly = false; Refresh(true) end)
    filters.hidden = Button(panel, L["Roster_Hidden"], 126, 154, -170, function() hiddenOnly = true; Refresh(true) end)
    buttons.name = Button(panel, L["Roster_Name"], 80, 340, -170, function() sortMode = "name"; Refresh(true) end)
    buttons.gold = Button(panel, L["Roster_Gold"], 80, 425, -170, function() sortMode = "gold"; Refresh(true) end)
    buttons.recent = Button(panel, L["Roster_Recent"], 90, 510, -170, function() sortMode = "recent"; Refresh(true) end)
    Text(panel, "GameFontNormalSmall", 28, -214, 230, L["Roster_Character"])
    Text(panel, "GameFontNormalSmall", 264, -214, 154, L["Roster_Gold"])
    Text(panel, "GameFontNormalSmall", 424, -214, 112, L["Roster_Updated"])
    scroll = CreateFrame("ScrollFrame", "RoutineDataRosterScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -236)
    scroll:SetPoint("BOTTOMLEFT", 16, 48)
    scroll:SetWidth(600)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(600, 1)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maximum = math.max(0, content:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maximum, self:GetVerticalScroll() - delta * 54)))
    end)
    empty = Text(panel, "GameFontHighlight", 28, -266, 560)
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", 16, 20)
    hint:SetText(L["Roster_HideHint"])
    panel:SetScript("OnShow", function() Refresh(true) end)
    panel:SetScript("OnHide", function() search:ClearFocus(); GameTooltip:Hide() end)
    category = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, L["Roster_Title"])
    local listener = {}
    for _, event in ipairs({ "DataChanged", "GoldUpdated", "CharacterRemoved", "DataReady", "CharacterVisibilityChanged" }) do
        RoutineData.RegisterCallback(listener, event, function() if panel:IsShown() then Refresh() end end)
    end
end
