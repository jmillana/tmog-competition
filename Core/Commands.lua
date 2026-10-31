-- TmogCompetition: player and leader actions (voting, rounds, winners, resets).
local ADDON, ns = ...
local TC, L = ns.TC, ns.L
local Print, Round2 = TC.Print, ns.Util.Round2

StaticPopupDialogs["TMOGCOMPETITION_CONFIRM"] = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data) if data then data() end end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function TC:Confirm(text, fn)
    local popup = StaticPopupDialogs["TMOGCOMPETITION_CONFIRM"]
    popup.button1, popup.button2 = L.POPUP_YES, L.POPUP_NO
    StaticPopup_Show("TMOGCOMPETITION_CONFIRM", text, nil, fn)
end

function TC:Announce(msg, warning)
    if not self.db.announce or not IsInGroup() then
        Print(msg)
        return
    end
    local channel
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        channel = "INSTANCE_CHAT"
    elseif warning and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        channel = "RAID_WARNING"
    elseif IsInRaid() then
        channel = "RAID"
    else
        channel = "PARTY"
    end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not pcall(send, msg, channel) then Print(msg) end
end

function TC:Vote(score)
    local db = self.db
    local me = self:Me()
    if db.phase ~= "VOTING" then return end
    if me == db.contestant then
        Print(L.CORE_NO_SELF_VOTE)
        return
    end
    if not db.voters[me] then
        Print(L.CORE_JOINED_MID_ROUND)
        return
    end
    db.votes[me] = score
    db.myVote = score
    self:Send("VOTE", db.round, score)
    self:Refresh()
end

-- Leader pressed Start: begins the competition (a new one after a finish). The theme draw
-- is optional before shuffling the first contestant.
function TC:CmdStart()
    if not self:RequireLeader() then return end
    local db = self.db
    if db.phase == "VOTING" then
        Print(L.CORE_CLOSE_VOTING_FIRST)
        return
    end
    if db.started and not db.finished then return end
    self:EnsureNewCompetition()
    db.started = true
    self:Send("STARTED")
    self:Announce(L.CORE_ANNOUNCE_STARTED, true)
    self:Refresh()
end

function TC:CmdNextRound()
    if not self:RequireLeader() then return end
    local db = self.db
    if db.phase == "VOTING" then
        Print(L.CORE_CLOSE_BEFORE_NEXT)
        return
    end
    self:EnsureNewCompetition()
    if not db.started then -- e.g. /tmogc next without pressing Start
        db.started = true
        self:Send("STARTED")
    end
    local pool = self:GetPool()
    if #pool == 0 then
        Print(L.CORE_POOL_EMPTY)
        return
    end
    local pick = pool[math.random(#pool)]
    local voters = {}
    for name in pairs(self.participants) do
        if name ~= pick then voters[#voters + 1] = name end
    end
    table.sort(voters)

    local id = db.round + 1
    self:StartRoundLocal(id, pick, voters)
    self:Send("ROUND", id, pick)
    self:SendList("VOTERS", id, voters)
    self:Announce(L:Format("CORE_ANNOUNCE_ROUND", { round = id, player = self:Short(pick), min = self.MIN_SCORE, max = self.MAX_SCORE }), true)
    self:Refresh()
end

function TC:CmdCloseVoting()
    if not self:RequireLeader() then return end
    local db = self.db
    if db.phase ~= "VOTING" then
        Print(L.CORE_NO_VOTING)
        return
    end
    local function close()
        if db.phase ~= "VOTING" then return end
        local count, total = 0, 0
        for name in pairs(db.voters) do
            local score = db.votes[name]
            if type(score) == "number" then
                count = count + 1
                total = total + score
            end
        end
        local avg = count > 0 and Round2(total / count) or 0
        self:CloseLocal(db.round, db.contestant, avg, count, total)
        self:Send("CLOSE", db.round, db.contestant, ("%.2f"):format(avg), count, total)
        self:Announce(L:Format("CORE_ANNOUNCE_SCORE", { player = self:Short(db.contestant), score = avg, count = count }))
        self:Refresh()
    end
    local pending = self:GetPending()
    if #pending > 0 then
        self:Confirm(L:Format("CORE_CONFIRM_CLOSE_PENDING", { count = #pending }), close)
    else
        close()
    end
end

function TC:CmdAnnounceWinner()
    if not self:RequireLeader() then return end
    local db = self.db
    if db.phase == "VOTING" then
        Print(L.CORE_CLOSE_VOTING_FIRST)
        return
    end
    local ranking = self:GetRanking()
    if #ranking == 0 then
        Print(L.CORE_NO_RESULTS)
        return
    end
    local function announce()
        local best = ranking[1].avg
        local winners, shortNames = {}, {}
        for _, r in ipairs(ranking) do
            if r.avg ~= best then break end
            winners[#winners + 1] = r.name
            shortNames[#shortNames + 1] = self:Short(r.name)
        end
        local theme = db.currentTheme
        db.winner = { names = winners, avg = best, theme = theme }
        self:Send("WINNER", table.concat(winners, ","), ("%.2f"):format(best), theme or "")
        local who = table.concat(shortNames, ", ")
        if theme and #winners == 1 then
            self:Announce(L:Format("CORE_ANNOUNCE_THEME_WINNER", { theme = theme, player = who, score = best }), true)
        elseif theme then
            self:Announce(L:Format("CORE_ANNOUNCE_THEME_TIE", { theme = theme, players = who, score = best }), true)
        elseif #winners == 1 then
            self:Announce(L:Format("CORE_ANNOUNCE_WINNER", { player = who, score = best }), true)
        else
            self:Announce(L:Format("CORE_ANNOUNCE_TIE", { players = who, score = best }), true)
        end
        for i = 1, math.min(3, #ranking) do
            local r = ranking[i]
            self:Announce(L:Format("CORE_ANNOUNCE_RANK_LINE", { rank = r.rank, player = self:Short(r.name), score = r.avg, count = r.count }))
        end
        self:Refresh()
    end
    local remaining = #self:GetPool()
    if remaining > 0 then
        self:Confirm(L:Format("CORE_CONFIRM_WINNER_EARLY", { count = remaining }), announce)
    else
        announce()
    end
end

function TC:CmdResetPool()
    if not self:RequireLeader() then return end
    self:Confirm(L.CORE_CONFIRM_RESET_POOL, function()
        wipe(self.db.shown)
        self:Send("RESETPOOL")
        self:Refresh()
    end)
end

function TC:CmdResetAll()
    if not self:RequireLeader() then return end
    self:Confirm(L.CORE_CONFIRM_RESET_ALL, function()
        self:ResetAllLocal()
        self:Send("RESETALL")
        self:Refresh()
    end)
end

function TC:CmdFinishCompetition()
    if not self:RequireLeader() then return end
    local db = self.db
    if db.phase == "VOTING" then
        Print(L.CORE_CLOSE_VOTING_FIRST)
        return
    end
    if db.finished then
        Print(L.CORE_ALREADY_FINISHED)
        return
    end
    local ranking = self:GetOverallRanking()
    if #ranking == 0 then
        Print(L.CORE_NO_RESULTS)
        return
    end
    self:Confirm(L.CORE_CONFIRM_FINISH, function()
        local best = ranking[1].score
        local winners, shortNames = {}, {}
        for _, r in ipairs(ranking) do
            if r.score ~= best then break end
            winners[#winners + 1] = r.name
            shortNames[#shortNames + 1] = self:Short(r.name)
        end
        self:FinishLocal(winners, best)
        self:Send("FINISH", table.concat(winners, ","), ("%.2f"):format(best))
        local who = table.concat(shortNames, ", ")
        if #winners == 1 then
            self:Announce(L:Format("CORE_ANNOUNCE_OVERALL_WINNER", { player = who, score = best }), true)
        else
            self:Announce(L:Format("CORE_ANNOUNCE_OVERALL_TIE", { players = who, score = best }), true)
        end
        for i = 1, math.min(3, #ranking) do
            local r = ranking[i]
            self:Announce(L:Format("CORE_ANNOUNCE_OVERALL_LINE", { rank = r.rank, player = self:Short(r.name), score = r.score, themes = r.themes }))
        end
        if ns.UI then ns.UI:ShowOverall() end
        self:Refresh()
    end)
end

function TC:CmdRefresh()
    self:ScanGroup()
    if self:IsLeader() then
        self:Send("PING")
        self:SendSync()
    else
        self:ScheduleHello(true)
    end
    self:Refresh()
end
