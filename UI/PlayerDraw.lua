-- TmogCompetition: player draw window. Same reel as the theme draw (UI/Reel.lua), spun
-- for everyone when the leader clicks Shuffle / Next participant. It closes by itself
-- a few seconds after the result.
local ADDON, ns = ...
local TC, S = ns.TC, ns.Style
local L = ns.L
local C = S.C

local PlayerDraw = {}
ns.PlayerDraw = PlayerDraw

local WIDTH, HEIGHT = 380, 318
local PAD = 16
local INNER = WIDTH - 2 * PAD
local FALLBACK = { 0.62, 0.36, 0.95 }

local function ClassColor(name)
    local unit = TC.group[name]
    local class = unit and select(2, UnitClass(unit))
    local c = class and RAID_CLASS_COLORS[class]
    if c then return { c.r, c.g, c.b } end
    return FALLBACK
end

function PlayerDraw:Build()
    if self.frame then return end
    local f = S:Window("TmogCompetitionPlayerDraw", WIDTH, HEIGHT, "PLAYERS_TITLE")
    self.frame = f
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")

    self.resultLabel = S:Text(f, 10, C.muted, "CENTER")
    self.resultLabel:SetPoint("TOP", 0, -48)

    self.reel = ns.Reel:Create(f, INNER, -64, {
        emptyKey = "PLAYERS_NONE",
        label = function(name) return TC:Short(name) end,
        color = function(_, _, name) return ClassColor(name) end,
        onTick = function(name) self.result:SetText(S:Color(C.text, TC:Short(name))) end,
        onFinish = function(name)
            self.resultLabel:SetText(L.PLAYERS_UP_NEXT)
            self.result:SetText(ns.UI and ns.UI:ColoredName(name) or TC:Short(name))
        end,
        onIdle = function() f:Hide() end,
    })

    self.result = S:Text(f, 18, C.gold, "CENTER")
    self.result:SetPoint("TOP", self.reel.frame, "BOTTOM", 0, -12)
    self.result:SetWidth(INNER)

    self.footer = S:Text(f, 11, C.muted, "CENTER")
    self.footer:SetPoint("BOTTOM", 0, 16)
end

function PlayerDraw:IsSpinning()
    return self.reel ~= nil and self.reel:IsSpinning()
end

-- Phase 1: spin freely through the players who have not showcased yet.
function PlayerDraw:StartSpin(pool)
    self:Build()
    self.frame:Show()
    self.reel:StartSpin(pool)
    self.resultLabel:SetText(L.DRAW_SPINNING)
    self.result:SetText("")
    self.footer:SetText(L:Format("PLAYERS_LEFT", { left = #pool }))
    TC:Refresh()
end

-- Phase 2: slow down and stop on `pick`. Returns false if the reel was not spinning.
function PlayerDraw:Land(pick, onDone)
    if self.reel then return self.reel:Land(pick, onDone) end
    return false
end

function PlayerDraw:Abort()
    if self.reel then self.reel:Abort() end
    if self.frame then self.frame:Hide() end
end
