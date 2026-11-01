-- TmogCompetition: on-screen hh:mm:ss countdown shown to every player.
--
-- The leader's Countdown button sends TIMER <seconds> (0 cancels). Each client counts
-- down from the moment it receives it, so everyone sees the same time give or take latency.
-- Drag to move (the position is saved), right-click to hide it.
local ADDON, ns = ...
local TC, S = ns.TC, ns.Style
local L = ns.L
local C = S.C

local Timer = {}
ns.Timer = Timer

local WARN_AT = 10 -- last seconds shown in the warning color
local LINGER = 5   -- seconds "00:00:00" stays on screen after the end

TC.LEADER_ONLY.TIMER = true

function Timer:Format(seconds)
    seconds = math.max(0, seconds)
    return ("%02d:%02d:%02d"):format(math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
end

function Timer:Build()
    if self.frame then return end
    local f = S:Panel(UIParent, C.bg, S.Alpha(C.accent, 0.6))
    f:SetSize(190, 62)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local point, _, relPoint, x, y = f:GetPoint()
        TC.db.timerPos = { point, relPoint, x, y }
    end)
    f:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then f:Hide() end
    end)
    f:SetScript("OnEnter", function()
        GameTooltip:SetOwner(f, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L.TIMER_TIP, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", GameTooltip_Hide)
    f:Hide()

    local pos = TC.db.timerPos
    if pos then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        f:SetPoint("TOP", 0, -140)
    end

    local label = S:Text(f, 10, C.muted, "CENTER")
    label:SetPoint("TOP", 0, -8)
    S:Static(label, "TIMER_LABEL", true)

    self.time = S:Text(f, 26, C.gold, "CENTER")
    self.time:SetPoint("TOP", label, "BOTTOM", 0, -4)

    self.frame = f
end

-- Starts (or restarts) the countdown locally. 0 or less cancels it.
function Timer:Start(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    if seconds <= 0 then
        self:Stop()
        return
    end
    self:Build()
    self.endTime = GetTime() + seconds
    self.shown = nil
    self.frame:Show()
    self.frame:SetScript("OnUpdate", function() self:Update() end)
    self:Update()
    TC:Refresh() -- the leader's Cancel button
end

function Timer:Stop()
    self.endTime = nil
    self.token = nil
    if self.frame then
        self.frame:SetScript("OnUpdate", nil)
        self.frame:Hide()
    end
    TC:Refresh()
end

-- Seconds left, or nil when no countdown is running.
function Timer:Remaining()
    if not self.endTime then return nil end
    local left = math.ceil(self.endTime - GetTime())
    if left <= 0 then return nil end
    return left
end

function Timer:Update()
    local left = math.max(0, math.ceil(self.endTime - GetTime()))
    if left == self.shown then return end
    self.shown = left
    self.time:SetText(self:Format(left))
    self.time:SetTextColor(unpack(left == 0 and C.success or left <= WARN_AT and C.warning or C.gold))
    if left > 0 then return end

    -- Time's up: keep 00:00:00 visible for a moment, then hide.
    self.frame:SetScript("OnUpdate", nil)
    self.endTime = nil
    TC:Refresh()
    if SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
    local token = {}
    self.token = token
    C_Timer.After(LINGER, function()
        if self.token == token then self:Stop() end
    end)
end

-- Leader side: show it for everyone.
function Timer:Broadcast(seconds)
    self:Start(seconds)
    TC:Send("TIMER", math.max(0, math.floor(seconds)))
end

-- Part of the leader's full sync for late joiners and reloads.
function Timer:SendSync()
    local left = self:Remaining()
    if left then TC:Send("TIMER", left) end
end

TC.Handlers.TIMER = function(self, sender, seconds)
    Timer:Start(seconds)
end
