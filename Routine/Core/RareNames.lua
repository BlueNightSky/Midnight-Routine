local _, ns = ...
if ns.Inactive then return end
local MR = ns.MR
local queue, pending, attempts = {}, {}, {}
local running = false
local locale = GetLocale()
local cacheKey = MR.isForever and "forever" or "retail"

local function ValidName(name)
    if issecretvalue and issecretvalue(name) then return false end
    return type(name) == "string" and name ~= "" and name ~= UNKNOWNOBJECT and name ~= UNKNOWN
end

local function GetCache()
    if not MR.db then return nil end
    local global = MR.db.global
    global.rareNames = global.rareNames or {}
    global.rareNames[cacheKey] = global.rareNames[cacheKey] or {}
    local names = global.rareNames[cacheKey]
    names[locale] = names[locale] or {}
    return names[locale]
end

local function ScanName(npcID)
    local info = C_TooltipInfo.GetHyperlink("unit:Creature-0-0-0-0-" .. npcID .. "-0")
    local line = info and info.lines and info.lines[1]
    if line and Enum and Enum.TooltipDataLineType and line.type == Enum.TooltipDataLineType.UnitName and ValidName(line.leftText) then
        return line.leftText
    end
end

local function ProcessQueue()
    local cache = GetCache()
    local changed = false
    for _ = 1, math.min(10, #queue) do
        local npcID = table.remove(queue, 1)
        if not npcID then break end
        attempts[npcID] = (attempts[npcID] or 0) + 1
        local ok, name = pcall(ScanName, npcID)
        if ok and name and cache then
            changed = cache[npcID] ~= name or changed
            cache[npcID] = name
            pending[npcID] = nil
        elseif attempts[npcID] < 3 then
            queue[#queue + 1] = npcID
        else
            pending[npcID] = nil
        end
    end
    if changed then
        if ns.Forever and ns.Forever.InvalidateRareNames then ns.Forever.InvalidateRareNames() end
        if MR.RebuildRaresFrame then MR:RebuildRaresFrame() end
    end
    running = #queue > 0
    if running then C_Timer.After(0.5, ProcessQueue) end
end

function MR:GetLocalizedRareName(npcID, fallback)
    if not npcID then return fallback end
    local cache = GetCache()
    local name = cache and cache[npcID]
    if ValidName(name) then return name end
    if cache and C_TooltipInfo and C_TooltipInfo.GetHyperlink and C_Timer and C_Timer.After
        and not pending[npcID] and (attempts[npcID] or 0) < 3 then
        pending[npcID] = true
        queue[#queue + 1] = npcID
        if not running then
            running = true
            C_Timer.After(0.5, ProcessQueue)
        end
    end
    return fallback
end
