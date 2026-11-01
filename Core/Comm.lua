-- TmogCompetition: addon communication (send queue, lists, hello/sync and message dispatch).
-- Message handlers live in Core/Handlers.lua; modules register their own types too.
local ADDON, ns = ...
local TC, L = ns.TC, ns.L
local Print, SortedKeys = TC.Print, ns.Util.SortedKeys

local SEP = "\t"
local LIST_CHUNK = 200     -- max bytes of list data per message (hard limit is 255 per message)
local SEND_INTERVAL = 0.1  -- seconds between queued sends
local MAX_TRIES = 150      -- give up on a throttled message after ~15s

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
    local db = self.db
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
    if ns.Timer then ns.Timer:SendSync() end
end

------------------------------------------------------------------------
-- Dispatch
------------------------------------------------------------------------
local Handlers, ListHandlers = {}, {}
local LEADER_ONLY = {
    PING = true, ROUND = true, CLOSE = true, WINNER = true,
    RESETPOOL = true, RESETALL = true, STATE = true, L = true,
    FINISH = true, NEWCOMP = true, TRCOUNT = true, STARTED = true,
    PLAYERSPIN = true, PLAYERRESULT = true,
}
-- Core/Handlers.lua and modules (Outfit, Themes) register their message types here.
TC.Handlers, TC.ListHandlers, TC.LEADER_ONLY = Handlers, ListHandlers, LEADER_ONLY

function TC:OnAddonMessage(prefix, text, channel, sender)
    if prefix ~= self.PREFIX or not self.db then return end
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
