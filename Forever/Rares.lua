local _, ns = ...
local L = LibStub("AceLocale-3.0"):GetLocale("MidnightRoutine", true)
if not ns.MR.isForever then return end
ns.Forever = ns.Forever or {}
local F = ns.Forever
function F.GetRareZones()
    local zones, byKey = {}, {}
    local char = ns.MR.db and ns.MR.db.char
    for id, saved in pairs(char and char.foreverRares or {}) do
        local data = type(saved) == "table" and saved or { name = saved }
        local key = data.mapID and tostring(data.mapID) or "discovered"
        local zone = byKey[key]
        if not zone then
            local info = data.mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(data.mapID)
            zone = { key = key, label = info and info.name or L["Forever_DiscoveredRares"], color = { 0.84, 0.66, 1 }, rares = {} }
            zones[#zones + 1], byKey[key] = zone, zone
        end
        zone.rares[#zone.rares + 1] = { data.name, nil, data.mapID, data.x, data.y, tonumber(id) }
    end
    table.sort(zones, function(a, b) return a.label < b.label end)
    for _, zone in ipairs(zones) do
        table.sort(zone.rares, function(a, b) return a[1] < b[1] end)
    end
    return zones
end
function F.DiscoverRare()
    local char = ns.MR.db and ns.MR.db.char
    if not (char and UnitClassification and UnitGUID and UnitName) then return false end
    local classification = UnitClassification("target")
    if classification ~= "rare" and classification ~= "rareelite" then return false end
    local guid, name = UnitGUID("target"), UnitName("target")
    local id = guid and guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if not (id and name) then return false end
    char.foreverRares = char.foreverRares or {}
    local old = char.foreverRares[id]
    if type(old) == "table" and old.mapID then return false end
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local position = mapID and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
    local x, y
    if position then x, y = position:GetXY() end
    char.foreverRares[id] = { name = name, mapID = mapID, x = x and x * 100, y = y and y * 100 }
    return true
end
