-- TmogCompetition: core state, group tracking, addon communication and leader actions.
local ADDON, ns = ...
local L = ns.L

local TC = CreateFrame("Frame")
ns.TC = TC
_G.TmogCompetition = TC

TC.PREFIX = "TMOGC"
TC.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"
TC.MIN_SCORE, TC.MAX_SCORE = 1, 10

local SEP = "\t"
local LIST_CHUNK = 200     -- max bytes of list data per message (hard limit is 255 per message)
local SEND_INTERVAL = 0.1  -- seconds between queued sends
local MAX_TRIES = 150      -- give up on a throttled message after ~15s

TC.group = {}        -- fullName -> unit token (current group members)
TC.participants = {} -- fullName -> { version = "x.y.z" } (group members running the addon)
TC.leader = nil      -- fullName of the group leader

local db

local DEFAULTS = {
    round = 0,
    phase = "IDLE", -- IDLE | VOTING | CLOSED
    contestant = nil,
    voters = {},    -- [name] = true: who may vote this round
    votes = {},     -- [name] = score (or true when only "has voted" is known from a sync)
    myVote = nil,
    results = {},   -- [name] = { avg, count, total }
    shown = {},     -- [name] = true: already showcased (shuffle pool)
    winner = nil,   -- { names = {...}, avg = n, theme = "Pirates" or nil }
    outfits = {},   -- [name] = { race, sex, slots = { [slotID] = { appearanceID, secondaryID, illusionID } } }
    themes = {},     -- theme pool still available for the draw (in order)
    usedThemes = {}, -- themes already picked
    currentTheme = nil,
    language = "auto", -- "auto" follows the game client, or "enUS" / "esES"
    themeResults = {},   -- finished themes of this competition: { { theme = name|nil, results = {...} }, ... }
    finished = false,    -- the leader finished the competition (overall ranking announced)
    overallWinner = nil, -- { names = {...}, score = n }
    restartRounds = true, -- leader option: a new competition after a finish restarts the round counter
    started = false,       -- the leader pressed Start for the running competition
    announce = true,
    autoShow = true,
    frame = nil,
}

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function Print(msg)
    print("|cffff80ffTmogCompetition|r: " .. msg)
end
TC.Print = Print

local function MyRealm()
    local realm = GetNormalizedRealmName()
    if realm and realm ~= "" then return realm end
    return ((GetRealmName() or ""):gsub("[%s%-]", ""))
end

function TC:Normalize(name)
    if not name or name == "" then return nil end
    if name:find("-", 1, true) then return name end
    return name .. "-" .. MyRealm()
end

function TC:UnitFullName(unit)
    local name, realm = UnitFullName(unit)
    if not name or name == "" or name == UNKNOWNOBJECT then return nil end
    if not realm or realm == "" then realm = MyRealm() end
    return name .. "-" .. realm
end

function TC:Me()
    if not self.me then self.me = self:UnitFullName("player") end
    return self.me
end

function TC:Short(name)
    return name and Ambiguate(name, "none") or "?"
end

local function SortedKeys(t)
    local list = {}
    for k in pairs(t) do list[#list + 1] = k end
    table.sort(list)
    return list
end

local function Split(data, sep)
    local list = {}
    if data and data ~= "" then
        for item in data:gmatch("[^" .. sep .. "]+") do list[#list + 1] = item end
    end
    return list
end

local function Round2(n)
    return tonumber(("%.2f"):format(n))
end

function TC:Refresh()
    if ns.UI then ns.UI:Refresh() end
    if ns.Wheel then ns.Wheel:Refresh() end
end

------------------------------------------------------------------------
-- Group tracking
------------------------------------------------------------------------
function TC:ScanGroup()
    local group = wipe(self.group)
    self.leader = nil

    local function add(unit)
        local name = self:UnitFullName(unit)
        if name then
            group[name] = unit
            if UnitIsGroupLeader(unit) then self.leader = name end
        end
    end

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do add("raid" .. i) end
    else
        add("player")
        if IsInGroup() then
            for i = 1, GetNumSubgroupMembers() do add("party" .. i) end
        end
    end

    local me = self:Me()
    if not IsInGroup() then self.leader = me end

    for name in pairs(self.participants) do
        if not group[name] then self.participants[name] = nil end
    end
    if me then self.participants[me] = { version = self.VERSION } end
end

function TC:IsLeader()
    return not IsInGroup() or UnitIsGroupLeader("player")
end

function TC:RequireLeader()
    if self:IsLeader() then return true end
    Print(L.CORE_LEADER_ONLY)
    return false
end

------------------------------------------------------------------------
-- Communication
------------------------------------------------------------------------
function TC:Channel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

local queue = {}
local sendFrame = CreateFrame("Frame")
sendFrame:Hide()
local sinceLast = 0

local function IsThrottled(result)
    local E = Enum and Enum.SendAddonMessageResult
    return E and (result == E.AddonMessageThrottle or result == E.ChannelThrottle)
end

sendFrame:SetScript("OnUpdate", function(frame, elapsed)
    sinceLast = sinceLast + elapsed
    if sinceLast < SEND_INTERVAL then return end
    sinceLast = 0
    local item = queue[1]
    if not item then frame:Hide() return end
    local result = C_ChatInfo.SendAddonMessage(TC.PREFIX, item.msg, item.channel)
    item.tries = item.tries + 1
    if IsThrottled(result) and item.tries < MAX_TRIES then return end
    table.remove(queue, 1)
end)

-- Sends a message to the group. Callers apply the change locally themselves,
-- so when solo nothing needs to be sent.
function TC:Send(...)
    local channel = self:Channel()
    if not channel then return end
    local parts = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        parts[i] = v == nil and "" or tostring(v)
    end
    local msg = table.concat(parts, SEP)
    if #msg > 255 then
        Print(L.CORE_MESSAGE_TOO_LONG .. " " .. parts[1])
        return
    end
    queue[#queue + 1] = { msg = msg, channel = channel, tries = 0 }
    sendFrame:Show()
end

-- Sends a list split across as many messages as needed: L, tag, id, more(1/0), "a,b,c".
function TC:SendList(tag, id, items)
    local chunk, len = {}, 0
    local function flush(more)
        self:Send("L", tag, id, more and 1 or 0, table.concat(chunk, ","))
        wipe(chunk)
        len = 0
    end
    for _, item in ipairs(items) do
        if #chunk > 0 and len + #item + 1 > LIST_CHUNK then flush(true) end
        chunk[#chunk + 1] = item
        len = len + #item + 1
    end
    flush(false)
end

function TC:ScheduleHello(wantReply)
    if wantReply then self.helloWantsReply = true end
    if self.helloPending then return end
    self.helloPending = true
    C_Timer.After(0.5 + math.random() * 2, function()
        self.helloPending = false
        local flag = self.helloWantsReply and 1 or 0
        self.helloWantsReply = false
        self:Send("HELLO", self.VERSION, flag)
    end)
end

function TC:ScheduleSync()
    if self.syncPending then return end
    self.syncPending = true
    C_Timer.After(1.5, function()
        self.syncPending = false
        self:SendSync()
    end)
end

function TC:SendSync()
    if not IsInGroup() or not self:IsLeader() then return end
    local w, ov = db.winner, db.overallWinner
    self:Send("STATE", db.round, db.phase, db.contestant,
        w and table.concat(w.names, ",") or "", w and ("%.2f"):format(w.avg) or "", w and w.theme or "",
        db.finished and 1 or 0, ov and table.concat(ov.names, ",") or "", ov and ("%.2f"):format(ov.score) or "",
        db.started and 1 or 0)
    self:Send("TRCOUNT", #db.themeResults)
    for i, entry in ipairs(db.themeResults) do
        local items = { "@" .. (entry.theme or "") }
        for name, r in pairs(entry.results) do
            items[#items + 1] = ("%s:%.2f:%d:%d"):format(name, r.avg, r.count, r.total)
        end
        self:SendList("TR", i, items)
    end
    self:SendList("SHOWN", db.round, SortedKeys(db.shown))
    local res = {}
    for name, r in pairs(db.results) do
        res[#res + 1] = ("%s:%.2f:%d:%d"):format(name, r.avg, r.count, r.total)
    end
    self:SendList("RES", db.round, res)
    if db.phase == "VOTING" then
        self:SendList("VOTERS", db.round, SortedKeys(db.voters))
        self:SendList("VOTED", db.round, SortedKeys(db.votes))
    end
    if ns.Themes then ns.Themes:SendSync() end
end

------------------------------------------------------------------------
-- Local state changes (shared by the leader and by message handlers)
------------------------------------------------------------------------
function TC:ClearRoundVotes()
    wipe(db.voters)
    wipe(db.votes)
    db.myVote = nil
end

function TC:StartRoundLocal(id, contestant, voterList)
    db.round = id
    db.phase = "VOTING"
    db.contestant = contestant
    db.shown[contestant] = true
    db.winner = nil
    self:ClearRoundVotes()
    for _, name in ipairs(voterList or {}) do db.voters[name] = true end
    if ns.History then ns.History:OnRoundStart(contestant) end
    if contestant == self:Me() and ns.Outfit then ns.Outfit:CaptureAndSend() end
end

function TC:CloseLocal(id, contestant, avg, count, total)
    db.round = id
    db.phase = "CLOSED"
    db.contestant = contestant
    db.shown[contestant] = true
    db.results[contestant] = { avg = avg, count = count, total = total }
    if ns.History then ns.History:OnRoundClosed(contestant, avg, count, total) end
end

-- Moves the current theme's results into db.themeResults (kept for the category tabs
-- and the overall ranking). Must run before db.currentTheme changes.
function TC:ArchiveCurrent()
    if next(db.results) then
        local copy = {}
        for name, r in pairs(db.results) do copy[name] = { avg = r.avg, count = r.count, total = r.total } end
        table.insert(db.themeResults, { theme = db.currentTheme, results = copy })
    end
    wipe(db.results)
end

-- A new theme starts a fresh ranking: everyone can showcase again. The previous
-- theme's results move to its own category tab.
function TC:StartThemeLocal()
    self:ArchiveCurrent()
    wipe(db.shown)
    self:ClearRoundVotes()
    db.phase = "IDLE"
    db.contestant = nil
    db.winner = nil
end

-- Clears the competition state. resetRound restarts the round counter.
local function ClearCompetition(resetRound)
    wipe(db.results)
    wipe(db.themeResults)
    wipe(db.shown)
    TC:ClearRoundVotes()
    db.phase = "IDLE"
    db.contestant = nil
    db.winner = nil
    db.finished = false
    db.overallWinner = nil
    db.started = false
    if resetRound then db.round = 0 end
end

-- Reset All always restarts the round counter: it is a full reset.
function TC:ResetAllLocal()
    ClearCompetition(true)
    wipe(db.outfits)
    if ns.History then ns.History:EndCompetition() end
end

-- Leader finished the competition: every theme is archived and the overall winner kept.
function TC:FinishLocal(names, score)
    self:ArchiveCurrent()
    self:ClearRoundVotes()
    db.phase = "IDLE"
    db.contestant = nil
    db.finished = true
    db.started = false -- the next Start begins a new competition
    db.overallWinner = { names = names, score = score }
    if ns.History then ns.History:EndCompetition() end
end

-- First action after a finished competition starts a new one.
function TC:NewCompetitionLocal(resetRound)
    ClearCompetition(resetRound)
    db.currentTheme = nil
end

-- Leader side: if the last competition was finished, start a new one for everyone.
function TC:EnsureNewCompetition()
    if not db.finished then return end
    local reset = db.restartRounds and true or false
    self:NewCompetitionLocal(reset)
    self:Send("NEWCOMP", reset and 1 or 0)
end

function TC:CanVote(name)
    return db.phase == "VOTING" and name ~= db.contestant and db.voters[name] == true
end

------------------------------------------------------------------------
-- Message handlers
------------------------------------------------------------------------
local Handlers, ListHandlers = {}, {}
local LEADER_ONLY = {
    PING = true, ROUND = true, CLOSE = true, WINNER = true,
    RESETPOOL = true, RESETALL = true, STATE = true, L = true,
    FINISH = true, NEWCOMP = true, TRCOUNT = true, STARTED = true,
}
-- Other files (Outfit.lua, Themes.lua) register their own message types here.
TC.Handlers, TC.ListHandlers, TC.LEADER_ONLY = Handlers, ListHandlers, LEADER_ONLY

function Handlers.HELLO(self, sender, version, wantReply)
    self.participants[sender] = { version = version }
    if wantReply == "1" then
        self:ScheduleHello(false)
        if self:IsLeader() then self:ScheduleSync() end
        -- Everyone who already showcased re-sends their own outfit to the newcomer.
        if ns.Outfit and db.shown[self:Me()] then ns.Outfit:ScheduleResend() end
    end
end

function Handlers.PING(self)
    self:ScheduleHello(false)
end

function Handlers.ROUND(self, sender, id, contestant)
    id = tonumber(id)
    if not id or not contestant or contestant == "" then return end
    self:StartRoundLocal(id, contestant, nil)
    PlaySound(SOUNDKIT.RAID_WARNING)
    if db.autoShow and ns.UI then ns.UI:Show() end
end

function Handlers.VOTE(self, sender, id, score)
    id, score = tonumber(id), tonumber(score)
    if id ~= db.round or not score or not self:CanVote(sender) then return end
    db.votes[sender] = math.max(self.MIN_SCORE, math.min(self.MAX_SCORE, math.floor(score)))
end

function Handlers.CLOSE(self, sender, id, contestant, avg, count, total)
    id = tonumber(id)
    if not id or not contestant or contestant == "" then return end
    self:CloseLocal(id, contestant, tonumber(avg) or 0, tonumber(count) or 0, tonumber(total) or 0)
end

function Handlers.WINNER(self, sender, names, avg, theme)
    db.winner = { names = Split(names, ","), avg = tonumber(avg) or 0, theme = (theme ~= "" and theme) or nil }
    PlaySound(SOUNDKIT.UI_RAID_BOSS_WHISPER_WARNING or SOUNDKIT.RAID_WARNING)
    if ns.Gallery then ns.Gallery:Show() end
end

function Handlers.RESETPOOL(self)
    wipe(db.shown)
end

function Handlers.RESETALL(self)
    self:ResetAllLocal()
end

function Handlers.FINISH(self, sender, names, score)
    self:FinishLocal(Split(names, ","), tonumber(score) or 0)
    PlaySound(SOUNDKIT.UI_RAID_BOSS_WHISPER_WARNING or SOUNDKIT.RAID_WARNING)
    if ns.UI then ns.UI:ShowOverall() end
end

function Handlers.NEWCOMP(self, sender, resetRound)
    self:NewCompetitionLocal(resetRound == "1")
end

function Handlers.STARTED(self)
    db.started = true
end

-- Sync of archived themes: TRCOUNT n, then one "TR" list per theme ("@theme", "name:avg:count:total", ...).
function Handlers.TRCOUNT(self, sender, count)
    count = tonumber(count) or 0
    for i = #db.themeResults, count + 1, -1 do table.remove(db.themeResults, i) end
end

function Handlers.STATE(self, sender, round, phase, contestant, winners, winAvg, winTheme, finished, ovNames, ovScore, started)
    db.finished = finished == "1"
    db.started = started == "1"
    if ovNames and ovNames ~= "" then
        db.overallWinner = { names = Split(ovNames, ","), score = tonumber(ovScore) or 0 }
    else
        db.overallWinner = nil
    end
    round = tonumber(round) or 0
    if round ~= db.round then self:ClearRoundVotes() end
    db.round = round
    db.phase = (phase == "VOTING" or phase == "CLOSED") and phase or "IDLE"
    db.contestant = contestant ~= "" and contestant or nil
    if winners and winners ~= "" then
        db.winner = { names = Split(winners, ","), avg = tonumber(winAvg) or 0,
            theme = (winTheme and winTheme ~= "") and winTheme or nil }
    else
        db.winner = nil
    end
end

local listBuffers = {}
function Handlers.L(self, sender, tag, id, more, data)
    id = tonumber(id)
    local buf = listBuffers[tag]
    if not buf or buf.id ~= id then
        buf = { id = id, items = {} }
        listBuffers[tag] = buf
    end
    for _, item in ipairs(Split(data, ",")) do buf.items[#buf.items + 1] = item end
    if more == "0" then
        listBuffers[tag] = nil
        local fn = ListHandlers[tag]
        if fn then fn(self, id, buf.items) end
    end
end

function ListHandlers.VOTERS(self, id, items)
    if id ~= db.round then return end
    wipe(db.voters)
    for _, name in ipairs(items) do db.voters[name] = true end
end

function ListHandlers.VOTED(self, id, items)
    if id ~= db.round then return end
    for _, name in ipairs(items) do db.votes[name] = db.votes[name] or true end
end

function ListHandlers.SHOWN(self, id, items)
    wipe(db.shown)
    for _, name in ipairs(items) do db.shown[name] = true end
end

function ListHandlers.TR(self, id, items)
    if not id or not items[1] then return end
    local theme = items[1]:match("^@(.*)$")
    local results = {}
    for i = 2, #items do
        local name, avg, count, total = strsplit(":", items[i])
        if name and avg then
            results[name] = { avg = tonumber(avg) or 0, count = tonumber(count) or 0, total = tonumber(total) or 0 }
        end
    end
    db.themeResults[id] = { theme = (theme ~= "" and theme) or nil, results = results }
end

function ListHandlers.RES(self, id, items)
    wipe(db.results)
    for _, item in ipairs(items) do
        local name, avg, count, total = strsplit(":", item)
        if name and avg then
            db.results[name] = { avg = tonumber(avg) or 0, count = tonumber(count) or 0, total = tonumber(total) or 0 }
        end
    end
end

function TC:OnAddonMessage(prefix, text, channel, sender)
    if prefix ~= self.PREFIX or not db then return end
    sender = self:Normalize(sender)
    if not sender or sender == self:Me() then return end
    local args = { strsplit(SEP, text) }
    local cmd = table.remove(args, 1)
    local handler = Handlers[cmd]
    if not handler then return end
    if LEADER_ONLY[cmd] and sender ~= self.leader then
        self:ScanGroup()
        if sender ~= self.leader then return end
    end
    handler(self, sender, unpack(args))
    self:Refresh()
end

------------------------------------------------------------------------
-- Queries used by the UI
------------------------------------------------------------------------
-- Participants in the group who have not showcased yet.
function TC:GetPool()
    local pool = {}
    for name in pairs(self.participants) do
        if self.group[name] and not db.shown[name] then pool[#pool + 1] = name end
    end
    table.sort(pool)
    return pool
end

-- Eligible voters still in the group who have not voted. Returns pendingList, eligibleCount.
function TC:GetPending()
    local pending, total = {}, 0
    for name in pairs(db.voters) do
        if self.group[name] then
            total = total + 1
            if db.votes[name] == nil then pending[#pending + 1] = name end
        end
    end
    table.sort(pending)
    return pending, total
end

-- Results sorted by average, then vote count, then name. Ties share a rank.
function TC:GetRanking()
    return self:RankResults(db.results)
end

-- Ranks a results table ({ [name] = { avg, count, total } }) by average.
function TC:RankResults(results)
    local list = {}
    for name, r in pairs(results) do
        list[#list + 1] = { name = name, avg = r.avg, count = r.count, total = r.total }
    end
    table.sort(list, function(a, b)
        if a.avg ~= b.avg then return a.avg > b.avg end
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    for i, r in ipairs(list) do
        local prev = list[i - 1]
        r.rank = (prev and prev.avg == r.avg) and prev.rank or i
    end
    return list
end

-- Categories for the ranking tabs: every finished theme, plus the running one.
-- Each is { key = index|"current", theme = name|nil, results = {...}, current = bool }.
function TC:GetCategories()
    local list = {}
    for i, entry in ipairs(db.themeResults) do
        list[#list + 1] = { key = i, theme = entry.theme, results = entry.results }
    end
    if not db.finished then
        list[#list + 1] = { key = "current", theme = db.currentTheme, results = db.results, current = true }
    end
    return list
end

-- Overall ranking: sum of each player's theme averages across the competition.
function TC:GetOverallRanking()
    local totals = {}
    for _, cat in ipairs(self:GetCategories()) do
        for name, r in pairs(cat.results) do
            local t = totals[name] or { name = name, score = 0, themes = 0 }
            t.score = t.score + r.avg
            t.themes = t.themes + 1
            totals[name] = t
        end
    end
    local list = {}
    for _, t in pairs(totals) do
        t.score = Round2(t.score)
        list[#list + 1] = t
    end
    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.themes ~= b.themes then return a.themes > b.themes end
        return a.name < b.name
    end)
    for i, t in ipairs(list) do
        local prev = list[i - 1]
        t.rank = (prev and prev.score == t.score) and prev.rank or i
    end
    return list
end

-- Ranking followed by participants without a result yet.
function TC:GetScoreboard()
    local rows, seen = {}, {}
    for _, r in ipairs(self:GetRanking()) do
        rows[#rows + 1] = r
        seen[r.name] = true
    end
    local others = {}
    for name in pairs(self.participants) do
        if not seen[name] then others[#others + 1] = name end
    end
    table.sort(others)
    for _, name in ipairs(others) do
        local status
        if db.phase == "VOTING" and name == db.contestant then
            status = "MAIN_STATUS_ON_STAGE"
        elseif db.shown[name] then
            status = "MAIN_STATUS_SHOWN"
        else
            status = "MAIN_STATUS_WAITING"
        end
        rows[#rows + 1] = { name = name, status = status }
    end
    return rows
end

-- Group members who are not running the addon.
function TC:GetMissingAddon()
    local missing = {}
    for name in pairs(self.group) do
        if not self.participants[name] then missing[#missing + 1] = name end
    end
    table.sort(missing)
    return missing
end

------------------------------------------------------------------------
-- Player and leader actions
------------------------------------------------------------------------
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
    if not db.announce or not IsInGroup() then
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
        wipe(db.shown)
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

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
TC:SetScript("OnEvent", function(self, event, ...) self[event](self, ...) end)
TC:RegisterEvent("ADDON_LOADED")

function TC:ADDON_LOADED(name)
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")

    TmogCompetitionDB = TmogCompetitionDB or {}
    db = TmogCompetitionDB
    for k, v in pairs(DEFAULTS) do
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
