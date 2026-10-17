local _, ns = ...
if ns.Inactive then return end
local MR = ns.MR
if not MR.isForever then return end

local L = LibStub("AceLocale-3.0"):GetLocale("MidnightRoutine")
local owner = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
local active, selected, highlight, elapsed
local hovered
local nodes = {}
local buttons = {}
local bindingsReady
local keys = {
    { "PADDDOWN", "down" }, { "PADDUP", "up" },
    { "PADDLEFT", "left" }, { "PADDRIGHT", "right" },
    { "PAD1", "confirm" }, { "PAD2", "back" },
    { "PAD3", "status" }, { "PAD4", "context" },
    { "PADLSHOULDER", "previous" }, { "PADRSHOULDER", "next" },
}

local function Available()
    return MR.db and C_GamePad and C_GamePad.IsEnabled() and not InCombatLockdown()
end

local function Surface()
    local config = MR:GetConfigFrame()
    if config and config:IsVisible() and config.scroll then
        return config, config.scroll, config.scroll:GetScrollChild(), true
    end
    local board = MR.altBoardFrame
    if board and board:IsVisible() then
        local scroll = board.detailScroll
        if board.bankPane and board.bankPane:IsVisible() then
            scroll = board.bankPane.scroll
            return board, scroll, scroll:GetScrollChild(), "alt"
        end
        for _, candidate in ipairs({ board.moduleScroll, board.overviewScroll, board.detailScroll, board.leftScroll }) do
            if candidate:IsVisible() then scroll = candidate break end
        end
        return board, scroll, scroll and scroll:GetScrollChild(), "alt"
    end
    return MR.frame, MR.scroll, MR.content, false
end

function MR:RefreshForeverControllerHints()
    local hint = self._foreverControllerHint
    if not hint then return end
    local surface = Surface()
    local visible = active and Available() and self.db.profile.showForeverControllerHints ~= false
        and surface and surface:IsVisible()
    if visible and hint._host ~= surface then
        hint._host = surface
        hint:SetParent(surface)
        hint:ClearAllPoints()
        hint:SetPoint("TOPLEFT", surface, "BOTTOMLEFT", 0, -2)
        hint:SetPoint("TOPRIGHT", surface, "BOTTOMRIGHT", 0, -2)
    end
    hint:SetShown(visible and true or false)
end

local function UpdateScroll(scroll)
    local frame, _, _, config = Surface()
    if config == "alt" then
        if frame.bankPane and frame.bankPane.scroll == scroll then
            if frame.bankPane.update then frame.bankPane.update() end
            return
        end
        for _, key in ipairs({ "left", "detail", "module", "overview" }) do
            if frame[key .. "Scroll"] == scroll and frame[key .. "ScrollUpdate"] then
                frame[key .. "ScrollUpdate"]()
                return
            end
        end
    elseif config then
        if frame.UpdateScrollBar then frame.UpdateScrollBar() end
    else
        if MR.UpdateScrollBar then MR.UpdateScrollBar() end
        MR:RefreshMainPanelViewport()
    end
end

local function Bindings()
    if InCombatLockdown() then return end
    if not bindingsReady then
        owner:SetAttribute("_onstate-combat", "if newstate == 'combat' then self:ClearBindings() end")
        RegisterStateDriver(owner, "combat", "[combat] combat; safe")
        bindingsReady = true
    end
    SecureHandlerExecute(owner, "self:ClearBindings()")
    if not Available() then return end
    if active then
        for _, entry in ipairs(keys) do
            SecureHandlerExecute(owner, string.format("self:SetBindingClick(true, %q, %q)", entry[1], buttons[entry[2]]:GetName()))
        end
    end
end

local function Stop()
    active, selected = nil, nil
    if hovered then
        local handler = hovered:GetScript("OnLeave")
        if handler then handler(hovered) end
        hovered = nil
    end
    if highlight then highlight:Hide() end
    MR:RefreshForeverControllerHints()
    Bindings()
end

local function Collect()
    wipe(nodes)
    local surface, scroll, content, config = Surface()
    if not content then return end
    local top = content:GetTop()
    if not top then return end
    local function Add(frame, key, kind, fixed)
        if not frame or not frame:IsVisible() then return end
        local nodeScroll, nodeContent = scroll, content
        if config == "alt" then
            nodeScroll = nil
            local parent = frame:GetParent()
            while parent and parent ~= surface do
                if parent:GetObjectType() == "ScrollFrame" then nodeScroll = parent break end
                parent = parent:GetParent()
            end
            nodeContent = nodeScroll and nodeScroll:GetScrollChild()
            fixed = not nodeScroll
        end
        local y, x = frame:GetTop(), frame:GetLeft()
        if y and x and frame:GetHeight() > 0 then
            local origin = nodeContent and nodeContent:GetTop() or top
            nodes[#nodes + 1] = { frame = frame, key = key, kind = kind, y = origin - y, x = x, screenY = y, fixed = fixed, scroll = nodeScroll, content = nodeContent }
        end
    end
    if config then
        local tabs = {}
        local entries = surface._foreverControllerTabs or {}
        if config == "alt" then
            entries = {}
            for _, key in ipairs({ "character", "modules", "concentration", "banks" }) do
                entries[#entries + 1] = { key = key, frame = surface.altTabs[key] }
            end
        end
        for _, tab in ipairs(entries) do
            tabs[tab.frame] = true
            Add(tab.frame, (config == "alt" and "alt:tab:" or "config:tab:") .. tab.key, "tab")
        end
        local function Walk(parent)
            for _, child in ipairs({ parent:GetChildren() }) do
                if child:IsVisible() and not tabs[child] then
                    local kind = child:GetObjectType()
                    if kind == "Slider" or ((kind == "Button" or kind == "CheckButton") and child:GetScript("OnClick")) then
                        if not child.IsEnabled or child:IsEnabled() then
                            Add(child, "config:" .. tostring(child), kind == "Slider" and "slider" or "control")
                        end
                    elseif config == "alt" and child._entry and child:GetScript("OnEnter") then
                        Add(child, "alt:display:" .. tostring(child), "display")
                    end
                    Walk(child)
                end
            end
        end
        Walk(config == "alt" and surface or (surface.body or content))
    else
        Add(MR.warbandBtn, "toolbar:warband", "toolbar", true)
        Add(MR.cfgBtn, "toolbar:config", "toolbar", true)
        Add(MR.minBtn, "toolbar:minimize", "toolbar", true)
        Add(MR.closeBtn, "toolbar:close", "toolbar", true)
        for key, frame in pairs(MR._mainExpansionHeaderFrames or {}) do
            Add(frame, key, "expansion")
        end
        for key, card in pairs(MR._mainSectionFrames or {}) do
            Add(card._hdrFrame, key .. ":header", "header")
            for rowKey, row in pairs(card._rows or {}) do
                Add(row, key .. ":" .. tostring(rowKey), "row")
            end
        end
    end
    table.sort(nodes, function(a, b)
        if a.fixed ~= b.fixed then return a.fixed == true end
        if math.abs(a.y - b.y) > 1 then return a.y < b.y end
        return a.x < b.x
    end)
end

local function FindSelected()
    if selected then
        for i, node in ipairs(nodes) do
            if node.key == selected.key then return node, i end
        end
    end
end

local function Select(node, reveal)
    selected = node
    if not node then highlight:Hide() return end
    local surface, scroll, content = Surface()
    scroll, content = node.scroll or scroll, node.content or content
    highlight:SetParent(node.fixed and surface or scroll)
    highlight:SetFrameLevel(node.frame:GetFrameLevel() + 10)
    if reveal and scroll and not node.fixed then
        local offset = scroll:GetVerticalScroll()
        local height = scroll:GetHeight()
        local bottom = node.y + node.frame:GetHeight()
        local target = offset
        if node.y < offset then target = node.y
        elseif bottom > offset + height then target = bottom - height end
        target = math.max(0, math.min(target, math.max(0, content:GetHeight() - height)))
        if math.abs(target - offset) > 0.5 then
            scroll:SetVerticalScroll(target)
            UpdateScroll(scroll)
            Collect()
            node = FindSelected()
            selected = node
            if not node then highlight:Hide() return end
        end
    end
    highlight:ClearAllPoints()
    highlight:SetAllPoints(node.frame)
    highlight:Show()
    if hovered ~= node.frame then
        if hovered then
            local handler = hovered:GetScript("OnLeave")
            if handler then handler(hovered) end
        end
        hovered = node.frame
        local handler = hovered:GetScript("OnEnter")
        if handler then handler(hovered) end
    end
end

local function Refresh()
    Collect()
    local node = FindSelected()
    local _, scroll = Surface()
    scroll = node and node.scroll or scroll
    local offset = scroll and scroll:GetVerticalScroll() or 0
    local height = scroll and scroll:GetHeight() or 0
    if node and not node.fixed and (node.y + node.frame:GetHeight() <= offset or node.y >= offset + height) then node = nil end
    if not node then
        for _, candidate in ipairs(nodes) do
            local candidateOffset = candidate.scroll and candidate.scroll:GetVerticalScroll() or offset
            if not candidate.fixed and candidate.kind ~= "tab" and candidate.y >= candidateOffset - 1 then node = candidate break end
        end
    end
    Select(node or nodes[1])
    MR:RefreshForeverControllerHints()
end

local function Move(direction)
    Collect()
    local node = FindSelected()
    if not node then Refresh() return end
    if node.kind == "slider" and (direction == "left" or direction == "right") then
        local minimum, maximum = node.frame:GetMinMaxValues()
        local step = node.frame:GetValueStep()
        if not step or step <= 0 then step = 1 end
        node.frame:SetValue(math.max(minimum, math.min(maximum, node.frame:GetValue() + (direction == "left" and -step or step))))
        Refresh()
        return
    end
    local nextNode
    if direction == "up" or direction == "down" then
        local score
        for _, candidate in ipairs(nodes) do
            local dy = node.screenY - candidate.screenY
            if direction == "up" then dy = -dy end
            if dy > 2 and candidate.kind ~= "tab" and candidate.kind ~= "toolbar"
                and (not node.scroll or node.fixed or candidate.scroll == node.scroll) then
                local distance = dy + math.abs(candidate.x - node.x) * 3
                if not score or distance < score then score, nextNode = distance, candidate end
            end
        end
    else
        local score
        for _, candidate in ipairs(nodes) do
            local dx = candidate.x - node.x
            if (direction == "left" and dx < -5) or (direction == "right" and dx > 5) then
                local distance = math.abs(candidate.screenY - node.screenY) * 4 + math.abs(dx)
                if not score or distance < score then
                    score, nextNode = distance, candidate
                end
            end
        end
    end
    if not nextNode and (direction == "up" or direction == "down") then
        local _, scroll, content = Surface()
        scroll, content = node.scroll or scroll, node.content or content
        local offset = scroll:GetVerticalScroll()
        local delta = math.max(30, scroll:GetHeight() * 0.5) * (direction == "up" and -1 or 1)
        scroll:SetVerticalScroll(math.max(0, math.min(offset + delta, math.max(0, content:GetHeight() - scroll:GetHeight()))))
        UpdateScroll(scroll)
        Collect()
        for i = 1, #nodes do
            local candidate = nodes[direction == "up" and (#nodes - i + 1) or i]
            if not candidate.fixed and candidate.kind ~= "tab" and candidate.scroll == scroll
                and ((direction == "down" and candidate.y > node.y + 1) or (direction == "up" and candidate.y < node.y - 1)) then
                nextNode = candidate
                break
            end
        end
    end
    Select(nextNode or FindSelected(), true)
end

local function Bumper(direction)
    local surface, scroll, _, config = Surface()
    if config then
        if config == "alt" then
            local tabs = { "character", "modules", "concentration", "banks" }
            local current = ns.WarbandBoardInternal.WBGetAltBoardView()
            local index = 1
            for i, key in ipairs(tabs) do if current == key then index = i break end end
            local key = tabs[((index - 1 + direction) % #tabs) + 1]
            ns.WarbandBoardInternal.WBSetAltBoardView(key)
            MR:RefreshWarbandBoardSelection()
            selected = { key = "alt:tab:" .. key }
            Refresh()
            return
        end
        local tabs = surface._foreverControllerTabs or {}
        if #tabs == 0 then return end
        local index = 1
        for i, tab in ipairs(tabs) do
            if tab.key == (MR._cfgPage or "windows") then index = i break end
        end
        local tab = tabs[((index - 1 + direction) % #tabs) + 1]
        MR._cfgPage = tab.key
        scroll:SetVerticalScroll(0)
        MR:PopulateConfigFrame(surface)
        MR:PositionConfigFrame(surface)
        selected = { key = "config:tab:" .. tab.key }
        Refresh()
        return
    end
    Collect()
    local toolbar, index = {}, nil
    for _, node in ipairs(nodes) do
        if node.kind == "toolbar" then
            toolbar[#toolbar + 1] = node
            if selected and node.key == selected.key then index = #toolbar end
        end
    end
    if #toolbar == 0 then return end
    index = index and (((index - 1 + direction) % #toolbar) + 1) or (direction > 0 and 1 or #toolbar)
    Select(toolbar[index])
end

local function Invoke(frame, script, button)
    local handler = frame and frame:GetScript(script)
    if handler then
        if script == "OnClick" and frame:GetObjectType() == "CheckButton" then
            frame:SetChecked(not frame:GetChecked())
        end
        handler(frame, button or "LeftButton")
    end
end

local function Activate()
    if not Available() or not highlight then return end
    active = true
    Refresh()
    Bindings()
end

local autoPending
local function AutoActivate()
    if autoPending then return end
    autoPending = true
    C_Timer.After(0, function()
        autoPending = nil
        if not MR.db or MR.db.profile.foreverControllerEnabled ~= true then return end
        local surface, scroll = Surface()
        if not Available() or not surface or not surface:IsVisible() or not scroll or not scroll:IsVisible() then
            Stop()
            return
        end
        Activate()
    end)
end

function MR:RefreshForeverControllerSupport()
    if self.db and self.db.profile.foreverControllerEnabled == true then
        AutoActivate()
    else
        Stop()
    end
    self:RefreshForeverControllerHints()
end

local function Handle(action)
    if not Available() then return end
    if not active then return end
    if action == "back" then
        local surface, _, _, config = Surface()
        if config then surface:Hide() selected = nil Refresh()
        else Stop() MR:HideMainPanel(true) end
        return
    end
    if action == "previous" or action == "next" then
        Bumper(action == "previous" and -1 or 1)
        return
    end
    if action == "up" or action == "down" or action == "left" or action == "right" then
        Move(action)
        return
    end
    Collect()
    local node = FindSelected()
    if not node then Refresh() return end
    local frame = node.frame
    if (node.kind == "toolbar" or node.kind == "tab" or node.kind == "control") and action == "confirm" then
        if node.key ~= "toolbar:config" and node.key ~= "toolbar:warband" and node.kind == "toolbar" then Stop() end
        Invoke(frame, "OnClick")
        if node.key == "toolbar:config" or node.key == "toolbar:warband" then selected = nil end
    elseif node.kind == "header" and action == "confirm" then
        Invoke(frame, "OnMouseDown")
        Invoke(frame, "OnMouseUp")
    elseif node.kind == "expansion" and action == "confirm" then
        Invoke(frame, "OnClick")
    elseif node.kind == "row" then
        if action == "status" then
            if frame._statusBtn and frame._statusBtn:IsShown() then Invoke(frame._statusBtn, "OnClick") end
        elseif action == "confirm" then
            if frame._headerActionButton and frame._headerActionButton:IsShown() then
                Stop()
                Invoke(frame._headerActionButton, "OnClick")
            else
                local data = frame._mrData
                if data and data.row and data.row.onLeftClick then Stop() end
                Invoke(frame, "OnMouseDown")
            end
        elseif action == "context" then
            local data = frame._mrData
            if data and data.row and data.row.onRightClick then Stop() end
            Invoke(frame, "OnMouseDown", "RightButton")
        end
    end
    if active then Refresh() end
end

for _, action in ipairs({ "up", "down", "left", "right", "previous", "next", "confirm", "back", "status", "context" }) do
    local button = CreateFrame("Button", "RoutineForeverController_" .. action, UIParent)
    button:Hide()
    button:RegisterForClicks("AnyUp")
    button:SetScript("OnClick", function() Handle(action) end)
    buttons[action] = button
end

local BuildUI = MR.BuildUI
function MR:BuildUI(...)
    BuildUI(self, ...)
    if not self.frame or self._foreverControllerInitialized then return end
    self._foreverControllerInitialized = true
    local hint = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
    self._foreverControllerHint = hint
    hint:SetHeight(44)
    hint:SetClampedToScreen(true)
    hint:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    hint:SetBackdropColor(0.03, 0.05, 0.07, 0.95)
    local text = hint:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOPLEFT", 6, -4)
    text:SetPoint("BOTTOMRIGHT", -6, 4)
    text:SetText(L["Controller_Hints"]:format(
        GetBindingText("PAD1", "KEY_") or "PAD1", GetBindingText("PAD3", "KEY_") or "PAD3",
        GetBindingText("PAD4", "KEY_") or "PAD4", GetBindingText("PAD2", "KEY_") or "PAD2"))
    hint:Hide()
    highlight = CreateFrame("Frame", nil, self.scroll, "BackdropTemplate")
    highlight:SetFrameLevel(self.scroll:GetFrameLevel() + 30)
    highlight:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    highlight:SetBackdropBorderColor(0.16, 0.91, 0.78, 1)
    highlight:EnableMouse(false)
    highlight:Hide()
    self.frame:HookScript("OnHide", Stop)
    self.frame:HookScript("OnShow", AutoActivate)
    self.frame:HookScript("OnHide", AutoActivate)
    AutoActivate()
    owner:SetScript("OnUpdate", function(_, delta)
        if not active then return end
        elapsed = (elapsed or 0) + delta
        if elapsed < 0.15 then return end
        elapsed = 0
        local surface, scroll = Surface()
        if not Available() or not surface or not surface:IsVisible() or not scroll or not scroll:IsVisible() then Stop() return end
        Refresh()
    end)
end

local BuildConfigFrame = MR.BuildConfigFrame
function MR:BuildConfigFrame(...)
    local frame = BuildConfigFrame(self, ...)
    frame:HookScript("OnShow", AutoActivate)
    frame:HookScript("OnHide", AutoActivate)
    return frame
end

local ToggleWarbandBoard = MR.ToggleWarbandBoard
function MR:ToggleWarbandBoard(...)
    ToggleWarbandBoard(self, ...)
    local frame = self.altBoardFrame
    if frame and not frame._foreverControllerAutoHooked then
        frame._foreverControllerAutoHooked = true
        frame:HookScript("OnShow", AutoActivate)
        frame:HookScript("OnHide", AutoActivate)
    end
    AutoActivate()
end

owner:RegisterEvent("PLAYER_ENTERING_WORLD")
owner:RegisterEvent("PLAYER_REGEN_DISABLED")
owner:RegisterEvent("PLAYER_REGEN_ENABLED")
owner:RegisterEvent("GAME_PAD_ACTIVE_CHANGED")
owner:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" or not Available() then Stop() end
    Bindings()
    if event ~= "PLAYER_REGEN_DISABLED" then AutoActivate() end
end)
