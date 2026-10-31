-- TmogCompetition: game events, saved-variable setup and slash commands.
local ADDON, ns = ...
local TC, L = ns.TC, ns.L
local Print = TC.Print

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
TC:SetScript("OnEvent", function(self, event, ...) self[event](self, ...) end)
TC:RegisterEvent("ADDON_LOADED")

function TC:ADDON_LOADED(name)
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")

    TmogCompetitionDB = TmogCompetitionDB or {}
    local db = TmogCompetitionDB
    for k, v in pairs(self.DEFAULTS) do
        if db[k] == nil and type(v) == "table" then
            db[k] = {}
        elseif db[k] == nil then
            db[k] = v
        end
    end
    self.db = db
    ns.SetLanguage(db.language)
    -- The restart option first shipped switched off; switch it on once (later choices are kept).
    if not db.restartRoundsDefaulted then
        db.restartRounds = true
        db.restartRoundsDefaulted = true
    end

    C_ChatInfo.RegisterAddonMessagePrefix(self.PREFIX)
    self:RegisterEvent("CHAT_MSG_ADDON")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    self:RegisterEvent("PARTY_LEADER_CHANGED")
end

function TC:CHAT_MSG_ADDON(...)
    self:OnAddonMessage(...)
end

function TC:PLAYER_ENTERING_WORLD(isLogin, isReload)
    self.me = nil
    self:ScanGroup()
    if isLogin or isReload then
        self.wasInGroup = IsInGroup()
        if IsInGroup() then self:ScheduleHello(true) end
    end
    self:Refresh()
end

function TC:GROUP_ROSTER_UPDATE()
    self:ScanGroup()
    local inGroup = IsInGroup()
    if inGroup and not self.wasInGroup then self:ScheduleHello(true) end
    self.wasInGroup = inGroup
    self:Refresh()
end

function TC:PARTY_LEADER_CHANGED()
    self:ScanGroup()
    self:Refresh()
end

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
local COMMANDS = {
    next = "CmdNextRound",
    close = "CmdCloseVoting",
    winner = "CmdAnnounceWinner",
    resetpool = "CmdResetPool",
    resetall = "CmdResetAll",
    sync = "CmdRefresh",
    finish = "CmdFinishCompetition",
    start = "CmdStart",
}

SLASH_TMOGCOMPETITION1 = "/tmogc"
SLASH_TMOGCOMPETITION2 = "/tmogcomp"
SlashCmdList.TMOGCOMPETITION = function(input)
    local db = TC.db
    local msg, rest = strtrim(input or ""):match("^(%S*)%s*(.-)$")
    msg = msg:lower()
    if msg == "" or msg == "show" then
        ns.UI:Toggle()
    elseif msg == "settings" or msg == "config" then
        ns.Settings:Toggle()
    elseif msg == "themes" or msg == "wheel" then
        ns.Wheel:Toggle()
    elseif msg == "spin" then
        ns.Themes:CmdSpin()
    elseif msg == "addtheme" then
        ns.Themes:CmdAdd(rest)
    elseif msg == "gallery" then
        ns.Gallery:Toggle()
    elseif msg == "outfit" then
        ns.Outfit:CaptureAndSend()
    elseif COMMANDS[msg] then
        TC[COMMANDS[msg]](TC)
    elseif msg == "announce" then
        db.announce = not db.announce
        Print(db.announce and L.CORE_ANNOUNCE_ON or L.CORE_ANNOUNCE_OFF)
    elseif msg == "autoshow" then
        db.autoShow = not db.autoShow
        Print(db.autoShow and L.CORE_AUTO_SHOW_ON or L.CORE_AUTO_SHOW_OFF)
    else
        Print(L.CORE_COMMANDS .. " /tmogc [show | settings | themes | spin | addtheme <name> | gallery | outfit | start | next | close | winner | finish | resetpool | resetall | sync | announce | autoshow]")
    end
end
