local _, ns = ...
local MR = ns.MR

local L = LibStub("AceLocale-3.0"):GetLocale("MidnightRoutine")

local CURSE_SURGE_START_GRACE = 900
local CURSE_SURGE_SITES = {
    { name = L["CurseSurgeSite_MalformedLeviathan"],       zone = 2512, x = 46.7, y = 62.8 },
    { name = L["CurseSurgeSite_BroodmothersNest"],         zone = 2512, x = 45.7, y = 29.6 },
    { name = L["CurseSurgeSite_LoomingMutagenior"],        zone = 2512, x = 26.4, y = 64.9 },
    { name = L["CurseSurgeSite_MlurkkrMassacre"],          zone = 2512, x = 70.5, y = 32.7 },
    { name = L["CurseSurgeSite_SiegeWhisperingMarsch"],    zone = 2512, x = 67.1, y = 77.5 },
}

local CURSE_SURGE_POI_TO_SITE = {
    [8940] = 1, 
    [8938] = 2, 
    [8936] = 3, 
    [8939] = 4, 
    [8937] = 5, 
}

local scheduledCurseSurges = {}
local activeCurseSurgeSite
local endedCurseSurgeSite
local endedCurseSurgeAt
local curseSurgeDataReadAt

local function ReadCurseSurgeFromMap()
    if not (C_AreaPoiInfo and C_AreaPoiInfo.GetEventsForMap) then
        return nil, false
    end

    local ok, list = pcall(C_AreaPoiInfo.GetEventsForMap, 2512)
    if not ok or type(list) ~= "table" then
        return nil, false
    end

    for _, areaPoiID in ipairs(list) do
        local siteIndex = CURSE_SURGE_POI_TO_SITE[areaPoiID]
        if siteIndex then
            return CURSE_SURGE_SITES[siteIndex], true
        end
    end

    return nil, true
end

local function ReadCurseSurgeFromScenario()
    if not (C_ScenarioInfo and C_ScenarioInfo.GetScenarioInfo) then
        return nil
    end

    local ok, info = pcall(C_ScenarioInfo.GetScenarioInfo)
    if not ok or type(info) ~= "table" or info.isComplete or type(info.name) ~= "string" then
        return nil
    end

    for _, site in ipairs(CURSE_SURGE_SITES) do
        if info.name:find(site.name, 1, true) then
            return site
        end
    end
end

local function RefreshCurseSurgeData(force)
    if not C_EventScheduler then
        return
    end
    if not force and curseSurgeDataReadAt and GetTime() - curseSurgeDataReadAt < 5 then
        return
    end
    curseSurgeDataReadAt = GetTime()

    if C_EventScheduler.GetScheduledEvents then
        local ok, list = pcall(C_EventScheduler.GetScheduledEvents)
        if ok and type(list) == "table" then
            local events = {}
            for _, ev in ipairs(list) do
                if type(ev) == "table" then
                    local siteIndex = CURSE_SURGE_POI_TO_SITE[ev.areaPoiID]
                    local startTime = tonumber(ev.startTime)
                    if siteIndex and startTime then
                        events[#events + 1] = {
                            site = CURSE_SURGE_SITES[siteIndex],
                            startTime = startTime,
                            endTime = tonumber(ev.endTime),
                        }
                    end
                end
            end
            table.sort(events, function(a, b)
                return a.startTime < b.startTime
            end)
            scheduledCurseSurges = events
        end
    end

    local detectedSite, mapStateRead = ReadCurseSurgeFromMap()
    if not mapStateRead and C_EventScheduler.GetOngoingEvents then
        local ok, list = pcall(C_EventScheduler.GetOngoingEvents)
        if ok and type(list) == "table" then
            for _, ev in ipairs(list) do
                if type(ev) == "table" then
                    local siteIndex = CURSE_SURGE_POI_TO_SITE[ev.areaPoiID]
                    if siteIndex then
                        detectedSite = CURSE_SURGE_SITES[siteIndex]
                        break
                    end
                end
            end
        end
    end

    detectedSite = ReadCurseSurgeFromScenario() or detectedSite
    if activeCurseSurgeSite and not detectedSite then
        endedCurseSurgeSite = activeCurseSurgeSite
        endedCurseSurgeAt = GetServerTime()
    elseif detectedSite then
        endedCurseSurgeSite = nil
        endedCurseSurgeAt = nil
    end
    activeCurseSurgeSite = detectedSite
end

local function GetCurseSurgeState()
    if activeCurseSurgeSite then
        return "live", nil, activeCurseSurgeSite
    end

    local now = GetServerTime()
    local startingEvent
    local nextEvent
    for _, ev in ipairs(scheduledCurseSurges) do
        if ev.startTime > now and not nextEvent then
            nextEvent = ev
        elseif ev.startTime <= now
            and now - ev.startTime <= CURSE_SURGE_START_GRACE
            and (not ev.endTime or ev.endTime > now) then
            startingEvent = ev
        end
    end

    local recentlyEnded = endedCurseSurgeSite == (startingEvent and startingEvent.site)
        and endedCurseSurgeAt
        and now - endedCurseSurgeAt < CURSE_SURGE_START_GRACE
    if startingEvent and not recentlyEnded then
        return "starting", 0, startingEvent.site
    end
    if nextEvent then
        return "next", nextEvent.startTime - now, nextEvent.site
    end

    return "unavailable"
end

local function FormatCurseSurgeCountdown(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function GetCurseSurgeZoneChannelIndex()
    local list = { GetChannelList() }
    local generalLabel = GENERAL or "General"
    for i = 1, #list, 3 do
        local id, name = list[i], list[i + 1]
        if id and type(name) == "string" and name:find(generalLabel, 1, true) then
            return id
        end
    end
end

-- Same clickable pin the game inserts when you shift-click a map pin into chat --
-- readers can click straight to the spot. CURSE_SURGE_SITES coords are already
-- 0-100 percent, so *100 lands on the hyperlink's 0-10000 scale.
local function CurseSurgePinLink(mapID, x, y)
    return string.format("|cffffff00|Hworldmap:%d:%d:%d|h[%s]|h|r",
        mapID, math.floor(x * 100 + 0.5), math.floor(y * 100 + 0.5),
        MAP_PIN_HYPERLINK or "Map Pin Location")
end

local function GetCurseSurgeGroupChatType()
    local instanceCategory = Enum and Enum.PartyCategory and Enum.PartyCategory.Instance or LE_PARTY_CATEGORY_INSTANCE
    if IsInGroup and instanceCategory and IsInGroup(instanceCategory) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid and IsInRaid() then
        return "RAID"
    end
    if IsInGroup and IsInGroup() then
        return "PARTY"
    end
end

local function AnnounceCurseSurge(toGroup)
    local phase, seconds, site = GetCurseSurgeState()
    if not site then
        print(L["Chat_CurseSurgeNoSite"] or "|cff2ae7c6MidnightRoutine:|r Nothing to announce right now.")
        return
    end

    local msg
    if phase == "live" then
        msg = string.format(L["Chat_CurseSurgeAnnounceLive"] or "Routine: %s is LIVE on the Coiled Isle! (%.1f, %.1f)",
            site.name, site.x, site.y)
    else
        msg = string.format(L["Chat_CurseSurgeAnnounceNext"] or "Routine: %s next in %s on the Coiled Isle (%.1f, %.1f)",
            site.name, FormatCurseSurgeCountdown(seconds), site.x, site.y)
    end
    msg = msg .. " " .. CurseSurgePinLink(site.zone, site.x, site.y)

    if toGroup then
        local chatType = GetCurseSurgeGroupChatType()
        if chatType then
            SendChatMessage(msg, chatType)
        else
            print(L["Chat_CurseSurgeNoGroup"] or "|cff2ae7c6MidnightRoutine:|r You are not in a party, raid, or instance group.")
        end
        return
    end

    local idx = GetCurseSurgeZoneChannelIndex()
    if idx then
        SendChatMessage(msg, "CHANNEL", nil, idx)
    else
        SendChatMessage(msg, "SAY")
    end
end

local curseSurgeBoundaryTimer

local function ScheduleCurseSurgeBoundaryRefresh()
    if curseSurgeBoundaryTimer then
        curseSurgeBoundaryTimer:Cancel()
        curseSurgeBoundaryTimer = nil
    end

    local phase, seconds = GetCurseSurgeState()
    local wait = 30
    if phase == "live" then
        wait = 10
    elseif phase == "starting" then
        wait = 5
    elseif phase == "next" and seconds and seconds > 0 then
        wait = math.min(seconds + 1, 60)
    elseif phase == "next" then
        wait = 5
    end

    curseSurgeBoundaryTimer = C_Timer.NewTimer(wait, function()
        curseSurgeBoundaryTimer = nil
        if C_EventScheduler and C_EventScheduler.RequestEvents then
            pcall(C_EventScheduler.RequestEvents)
        end
        RefreshCurseSurgeData(true)
        if MR.RequestScan then MR:RequestScan() end
        ScheduleCurseSurgeBoundaryRefresh()
    end)
end

if MR.IsPatchAvailable and MR:IsPatchAvailable("12.1.0") then
    ScheduleCurseSurgeBoundaryRefresh()

    local curseSurgeSchedulerWatcher = CreateFrame("Frame")
    curseSurgeSchedulerWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    curseSurgeSchedulerWatcher:RegisterEvent("EVENT_SCHEDULER_UPDATE")
    curseSurgeSchedulerWatcher:RegisterEvent("AREA_POIS_UPDATED")
    curseSurgeSchedulerWatcher:RegisterEvent("SCENARIO_UPDATE")
    curseSurgeSchedulerWatcher:RegisterEvent("SCENARIO_COMPLETED")
    curseSurgeSchedulerWatcher:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            if C_EventScheduler and C_EventScheduler.RequestEvents then
                pcall(C_EventScheduler.RequestEvents)
            end
            RefreshCurseSurgeData(true)
            if MR.RequestScan then MR:RequestScan() end
            ScheduleCurseSurgeBoundaryRefresh()
            return
        end

        RefreshCurseSurgeData(true)
        if MR.RequestScan then MR:RequestScan() end
        ScheduleCurseSurgeBoundaryRefresh()
    end)
end

MR:RegisterModule({
    key         = "midnight_activities",
    label       = L["Activities_Title"],
    labelColor  = "#ff9040",
    resetType   = "weekly",
    defaultOpen = true,
    scanReturnsChanged = true,

    onScan = function(mod)
        RefreshCurseSurgeData()
        local _, _, site = GetCurseSurgeState()
        local changed = false
        for _, row in ipairs(mod.rows) do
            if row.key == "curse_surge" then
                local note = site
                    and string.format(L["Act_CurseSurge_NoteSite"] or "%s\nSite: %s (%.1f, %.1f)", L["Act_CurseSurge_Note"], site.name, site.x, site.y)
                    or L["Act_CurseSurge_Note"]
                if row.note ~= note or row.zone ~= (site and site.zone) then
                    changed = true
                end
                row.note = note
                if site then
                    row.zone, row.x, row.y = site.zone, site.x, site.y
                    row.waypointTitle = site.name
                else
                    row.zone, row.x, row.y, row.waypointTitle = nil, nil, nil, nil
                end
            end
        end
        return changed
    end,

    rows = {
        {
            key           = "stormarion_assault",
            label         = L["Act_Stormarion_Label"],
            max           = 1,
            note          = L["Act_Stormarion_Note"],
            patchKey      = "12.0.0",
            questIds      = { 90962 },
            timerEpoch    = 1772370083,
            timerInterval = 1800,
            timerDuration = 900,
        },
        {
            key           = "curse_surge",
            label         = L["Act_CurseSurge_Label"],
            max           = 1,
            note          = L["Act_CurseSurge_Note"],
            patchKey      = "12.1.0",
            timerStateFunc = GetCurseSurgeState,
            autoTracked   = true,
            noDefaultTooltipHint = true,
            tooltipFunc = function(tip)
                tip:AddLine(" ")
                tip:AddLine(L["Act_CurseSurge_AnnounceHint"] or "Shift-right-click: announce to zone chat.\nCtrl-right-click: announce to your group.", 0.55, 0.55, 0.60, true)
            end,
            onRightClick = function()
                if IsControlKeyDown and IsControlKeyDown() then
                    AnnounceCurseSurge(true)
                    return true
                end
                if IsShiftKeyDown() then
                    AnnounceCurseSurge(false)
                    return true
                end
                return false
            end,
        },
    },
})
