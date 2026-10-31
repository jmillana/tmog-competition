-- TmogCompetition: local state changes (shared by the leader and by message handlers).
local ADDON, ns = ...
local TC = ns.TC

function TC:ClearRoundVotes()
    local db = self.db
    wipe(db.voters)
    wipe(db.votes)
    db.myVote = nil
end

function TC:StartRoundLocal(id, contestant, voterList)
    local db = self.db
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
    local db = self.db
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
    local db = self.db
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
    local db = self.db
    self:ArchiveCurrent()
    wipe(db.shown)
    self:ClearRoundVotes()
    db.phase = "IDLE"
    db.contestant = nil
    db.winner = nil
end

-- Clears the competition state. resetRound restarts the round counter.
local function ClearCompetition(resetRound)
    local db = TC.db
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
    wipe(self.db.outfits)
    if ns.History then ns.History:EndCompetition() end
end

-- Leader finished the competition: every theme is archived and the overall winner kept.
function TC:FinishLocal(names, score)
    local db = self.db
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
    self.db.currentTheme = nil
end

-- Leader side: if the last competition was finished, start a new one for everyone.
function TC:EnsureNewCompetition()
    local db = self.db
    if not db.finished then return end
    local reset = db.restartRounds and true or false
    self:NewCompetitionLocal(reset)
    self:Send("NEWCOMP", reset and 1 or 0)
end

function TC:CanVote(name)
    local db = self.db
    return db.phase == "VOTING" and name ~= db.contestant and db.voters[name] == true
end
