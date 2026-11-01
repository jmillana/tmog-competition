-- TmogCompetition: handlers for the core addon messages (dispatched by Core/Comm.lua).
local ADDON, ns = ...
local TC = ns.TC
local Split = ns.Util.Split
local Handlers, ListHandlers = TC.Handlers, TC.ListHandlers

function Handlers.HELLO(self, sender, version, wantReply)
    self.participants[sender] = { version = version }
    if wantReply == "1" then
        self:ScheduleHello(false)
        if self:IsLeader() then self:ScheduleSync() end
        -- Everyone who already showcased re-sends their own outfit to the newcomer.
        if ns.Outfit and self.db.shown[self:Me()] then ns.Outfit:ScheduleResend() end
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
    if self.db.autoShow and ns.UI then ns.UI:Show() end
end

-- Player draw: the leader's reel spins (PLAYERSPIN), then stops on the pick (PLAYERRESULT).
-- The round itself starts with the ROUND message once the leader's reel has stopped.
function Handlers.PLAYERSPIN(self)
    if ns.PlayerDraw then ns.PlayerDraw:StartSpin(self:GetPool()) end
end

function Handlers.PLAYERRESULT(self, sender, name)
    if not name or name == "" or not ns.PlayerDraw then return end
    -- Late or missed PLAYERSPIN: start from our own pool so the reel still stops on it.
    if not ns.PlayerDraw:IsSpinning() then ns.PlayerDraw:StartSpin(self:GetPool()) end
    ns.PlayerDraw:Land(name)
end

function Handlers.VOTE(self, sender, id, score)
    local db = self.db
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
    self.db.winner = { names = Split(names, ","), avg = tonumber(avg) or 0, theme = (theme ~= "" and theme) or nil }
    PlaySound(SOUNDKIT.UI_RAID_BOSS_WHISPER_WARNING or SOUNDKIT.RAID_WARNING)
    if ns.Gallery then ns.Gallery:Show() end
end

function Handlers.RESETPOOL(self)
    wipe(self.db.shown)
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
    self.db.started = true
end

-- Sync of archived themes: TRCOUNT n, then one "TR" list per theme ("@theme", "name:avg:count:total", ...).
function Handlers.TRCOUNT(self, sender, count)
    local db = self.db
    count = tonumber(count) or 0
    for i = #db.themeResults, count + 1, -1 do table.remove(db.themeResults, i) end
end

function Handlers.STATE(self, sender, round, phase, contestant, winners, winAvg, winTheme, finished, ovNames, ovScore, started)
    local db = self.db
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

------------------------------------------------------------------------
-- Lists (sent in chunks with TC:SendList)
------------------------------------------------------------------------
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
    local db = self.db
    if id ~= db.round then return end
    wipe(db.voters)
    for _, name in ipairs(items) do db.voters[name] = true end
end

function ListHandlers.VOTED(self, id, items)
    local db = self.db
    if id ~= db.round then return end
    for _, name in ipairs(items) do db.votes[name] = db.votes[name] or true end
end

function ListHandlers.SHOWN(self, id, items)
    local db = self.db
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
    self.db.themeResults[id] = { theme = (theme ~= "" and theme) or nil, results = results }
end

function ListHandlers.RES(self, id, items)
    local db = self.db
    wipe(db.results)
    for _, item in ipairs(items) do
        local name, avg, count, total = strsplit(":", item)
        if name and avg then
            db.results[name] = { avg = tonumber(avg) or 0, count = tonumber(count) or 0, total = tonumber(total) or 0 }
        end
    end
end
