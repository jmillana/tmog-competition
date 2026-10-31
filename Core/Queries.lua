-- TmogCompetition: read-only queries used by the UI and by leader actions.
local ADDON, ns = ...
local TC = ns.TC
local Round2 = ns.Util.Round2

-- Participants in the group who have not showcased yet.
function TC:GetPool()
    local db = self.db
    local pool = {}
    for name in pairs(self.participants) do
        if self.group[name] and not db.shown[name] then pool[#pool + 1] = name end
    end
    table.sort(pool)
    return pool
end

-- Eligible voters still in the group who have not voted. Returns pendingList, eligibleCount.
function TC:GetPending()
    local db = self.db
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
    return self:RankResults(self.db.results)
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
    local db = self.db
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
    local db = self.db
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
