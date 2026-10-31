-- TmogCompetition: local gallery history (competitions > themes > transmogs) and bookmarks.
-- This is kept per client and never synced: each player curates their own gallery.
local ADDON, ns = ...
local TC = ns.TC

local History = {}
ns.History = History

local NO_THEME = "No theme"

local function Store()
    local db = TC.db
    db.history = db.history or { competitions = {} }
    db.bookmarks = db.bookmarks or {}
    return db.history, db.bookmarks
end

function History:Changed()
    if ns.Gallery then ns.Gallery:Refresh() end
end

------------------------------------------------------------------------
-- Competitions and themes
------------------------------------------------------------------------
function History:Competitions()
    return (Store()).competitions
end

function History:Find(id)
    for _, comp in ipairs(self:Competitions()) do
        if comp.id == id then return comp end
    end
end

function History:ActiveId()
    return (Store()).activeId
end

-- The competition rounds are currently filed under. A new one (titled with the date)
-- starts with the first round after a Reset All.
function History:Active(create)
    local history = Store()
    local comp = history.activeId and self:Find(history.activeId)
    if not comp and create then
        comp = {
            id = ("%d-%04d"):format(time(), math.random(0, 9999)),
            title = ns.FormatDate(time()),
            created = time(),
            themes = {},
        }
        table.insert(history.competitions, comp)
        history.activeId = comp.id
    end
    return comp
end

function History:Theme(comp, name, create)
    name = name or NO_THEME
    for _, theme in ipairs(comp.themes) do
        if theme.name == name then return theme end
    end
    if create then
        local theme = { name = name, entries = {}, created = time() }
        table.insert(comp.themes, theme)
        return theme
    end
end

function History:CurrentTheme(create)
    local comp = self:Active(create)
    if not comp then return end
    return self:Theme(comp, TC.db.currentTheme, create), comp
end

function History:Entry(player, create)
    local theme, comp = self:CurrentTheme(create)
    if not theme then return end
    local entry = theme.entries[player]
    if not entry and create then
        local unit = TC.group[player]
        entry = { name = player, class = unit and select(2, UnitClass(unit)) or nil, time = time() }
        theme.entries[player] = entry
    end
    return entry, theme, comp
end

-- Scored entries by average (ties share a rank), then unscored ones.
function History:Ranked(theme)
    local list = {}
    for _, entry in pairs(theme.entries) do list[#list + 1] = entry end
    table.sort(list, function(a, b)
        if (a.avg ~= nil) ~= (b.avg ~= nil) then return a.avg ~= nil end
        if a.avg and a.avg ~= b.avg then return a.avg > b.avg end
        if (a.count or 0) ~= (b.count or 0) then return (a.count or 0) > (b.count or 0) end
        return a.name < b.name
    end)
    for i, entry in ipairs(list) do
        local prev = list[i - 1]
        if entry.avg then
            entry.rank = (prev and prev.avg == entry.avg) and prev.rank or i
        else
            entry.rank = nil
        end
    end
    return list
end

------------------------------------------------------------------------
-- Hooks called by the competition code
------------------------------------------------------------------------
function History:OnThemePicked()
    self:CurrentTheme(true)
    self:Changed()
end

function History:OnRoundStart(player)
    local entry = self:Entry(player, true)
    -- Showcasing again under the same theme replaces the previous look.
    entry.outfit, entry.avg, entry.count, entry.total = nil, nil, nil, nil
    entry.time = time()
    self:Changed()
end

function History:OnOutfit(player, outfit)
    local entry, theme, comp = self:Entry(player, false)
    if not entry then return end
    entry.outfit = outfit
    self:SyncBookmark(comp, theme, entry)
    self:Changed()
end

function History:OnRoundClosed(player, avg, count, total)
    local entry, theme, comp = self:Entry(player, true)
    entry.avg, entry.count, entry.total = avg, count, total
    self:SyncBookmark(comp, theme, entry)
    self:Changed()
end

function History:EndCompetition()
    (Store()).activeId = nil
    self:Changed()
end

------------------------------------------------------------------------
-- Editing
------------------------------------------------------------------------
function History:Rename(comp, title)
    title = strtrim(title or "")
    if title ~= "" then comp.title = title end
    self:Changed()
end

function History:RemoveEntry(theme, player)
    theme.entries[player] = nil
    self:Changed()
end

-- Clears all history. Bookmarks are kept.
function History:Clear()
    local history = Store()
    wipe(history.competitions)
    history.activeId = nil
    self:Changed()
end

-- Removes one competition. Its bookmarks are kept. If it was the running one, the next
-- round simply starts a new dated competition.
function History:RemoveCompetition(id)
    local history = Store()
    for i, comp in ipairs(history.competitions) do
        if comp.id == id then
            table.remove(history.competitions, i)
            break
        end
    end
    if history.activeId == id then history.activeId = nil end
    self:Changed()
end

function History:ClearBookmarks()
    wipe(self:Bookmarks())
    self:Changed()
end

------------------------------------------------------------------------
-- Bookmarks (independent copies, so they survive Clear and removals)
------------------------------------------------------------------------
function History:Bookmarks()
    return select(2, Store())
end

function History:Key(comp, theme, entry)
    return comp.id .. "|" .. theme.name .. "|" .. entry.name
end

function History:FindBookmark(key)
    for i, bookmark in ipairs(self:Bookmarks()) do
        if bookmark.key == key then return i, bookmark end
    end
end

function History:IsBookmarked(key)
    return self:FindBookmark(key) ~= nil
end

local function Fill(bookmark, comp, theme, entry)
    bookmark.name, bookmark.class = entry.name, entry.class
    bookmark.avg, bookmark.count, bookmark.rank = entry.avg, entry.count, entry.rank
    bookmark.outfit = entry.outfit
    bookmark.competition, bookmark.theme = comp.title, theme.name
end

function History:AddBookmark(comp, theme, entry)
    local key = self:Key(comp, theme, entry)
    if self:FindBookmark(key) then return end
    local bookmark = { key = key, time = time() }
    Fill(bookmark, comp, theme, entry)
    table.insert(self:Bookmarks(), 1, bookmark)
    self:Changed()
end

function History:RemoveBookmark(key)
    local i = self:FindBookmark(key)
    if i then table.remove(self:Bookmarks(), i) end
    self:Changed()
end

-- Keeps a bookmark made mid-round up to date when the score or outfit arrives.
function History:SyncBookmark(comp, theme, entry)
    local _, bookmark = self:FindBookmark(self:Key(comp, theme, entry))
    if bookmark then Fill(bookmark, comp, theme, entry) end
end
