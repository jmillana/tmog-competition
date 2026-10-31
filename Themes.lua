-- TmogCompetition: theme pool and the leader-driven theme carousel.
--
-- Spin flow:
--   1. Leader sends THEMESPIN: every client opens the carousel and starts spinning.
--   2. ~2s later the leader's client picks a theme, removes it from the pool and
--      sends THEMERESULT: every carousel slows down and stops on it.
--   3. When the leader's carousel stops, it announces the theme in group chat.
local ADDON, ns = ...
local TC = ns.TC
local L = ns.L

local Themes = {}
ns.Themes = Themes

local MAX_LEN = 40
local PICK_DELAY = 2 -- seconds the carousel spins freely before the leader picks

for _, cmd in ipairs({ "THEMEADD", "THEMEDEL", "THEMESPIN", "THEMERESULT", "THEMERESET", "THEMECUR" }) do
    TC.LEADER_ONLY[cmd] = true
end

local function Copy(list)
    local out = {}
    for i, v in ipairs(list) do out[i] = v end
    return out
end

local function IndexOf(list, name)
    local lower = name:lower()
    for i, v in ipairs(list) do
        if v:lower() == lower then return i end
    end
end

-- Theme names travel inside comma/colon/tab separated messages, so those are stripped.
function Themes:Clean(name)
    name = (name or ""):gsub("[,:\t|]", " ")
    name = strtrim((name:gsub("%s+", " ")))
    if name == "" then return nil, L["Type a theme name first."] end
    if #name > MAX_LEN then return nil, ("Theme names can be up to %d characters."):format(MAX_LEN) end
    return name
end

function Themes:Exists(name)
    local db = TC.db
    return IndexOf(db.themes, name) or IndexOf(db.usedThemes, name)
end

------------------------------------------------------------------------
-- Local state changes (leader applies them directly, others via messages)
------------------------------------------------------------------------
function Themes:AddLocal(name)
    if not self:Exists(name) then table.insert(TC.db.themes, name) end
end

function Themes:RemoveLocal(name)
    local db = TC.db
    local i = IndexOf(db.themes, name)
    if i then table.remove(db.themes, i) end
    i = IndexOf(db.usedThemes, name)
    if i then table.remove(db.usedThemes, i) end
    if db.currentTheme and db.currentTheme:lower() == name:lower() then db.currentTheme = nil end
end

function Themes:PickLocal(name)
    local db = TC.db
    local i = IndexOf(db.themes, name)
    if i then table.remove(db.themes, i) end
    if not IndexOf(db.usedThemes, name) then table.insert(db.usedThemes, name) end
    db.currentTheme = name
    TC:StartThemeLocal() -- fresh ranking, winner and shuffle pool for the new theme
    if ns.History then ns.History:OnThemePicked() end
end

function Themes:ResetLocal()
    local db = TC.db
    for _, name in ipairs(db.usedThemes) do
        if not IndexOf(db.themes, name) then table.insert(db.themes, name) end
    end
    wipe(db.usedThemes)
    db.currentTheme = nil
end

------------------------------------------------------------------------
-- Leader commands
------------------------------------------------------------------------
function Themes:CmdAdd(text)
    if not TC:RequireLeader() then return false end
    local name, err = self:Clean(text)
    if not name then
        TC.Print(err)
        return false
    end
    if self:Exists(name) then
        TC.Print((L["\"%s\" is already on the list."]):format(name))
        return false
    end
    self:AddLocal(name)
    TC:Send("THEMEADD", name)
    TC:Refresh()
    return true
end

function Themes:CmdRemove(name)
    if not TC:RequireLeader() then return end
    self:RemoveLocal(name)
    TC:Send("THEMEDEL", name)
    TC:Refresh()
end

function Themes:CmdReset()
    if not TC:RequireLeader() then return end
    TC:Confirm(L["Put every used theme back in the carousel?"], function()
        self:ResetLocal()
        TC:Send("THEMERESET")
        TC:Refresh()
    end)
end

function Themes:CmdSpin()
    if not TC:RequireLeader() then return end
    if ns.Wheel:IsSpinning() or self.pickPending then
        TC.Print(L["The carousel is already spinning."])
        return
    end
    if #TC.db.themes == 0 then
        TC.Print(L["The theme pool is empty. Add themes or reset the used ones."])
        return
    end
    if TC.db.phase == "VOTING" then
        TC.Print(L["Close the current voting first."])
        return
    end
    -- Picking a theme starts a fresh ranking; warn if this one was never announced.
    if next(TC.db.results) and not TC.db.winner then
        TC:Confirm(L["This theme has results but no winner was announced. Spin anyway?\nIts ranking stays in the gallery."],
            function() self:Spin() end)
        return
    end
    self:Spin()
end

function Themes:Spin()
    if ns.Wheel:IsSpinning() or self.pickPending then return end
    TC:Send("THEMESPIN")
    ns.Wheel:StartSpin(Copy(TC.db.themes))
    self.pickPending = true

    C_Timer.After(PICK_DELAY, function()
        self.pickPending = false
        local pool = TC.db.themes
        if #pool == 0 then
            ns.Wheel:Abort()
            return
        end
        local pick = pool[math.random(#pool)]
        local jitter = 0.2 + math.random() * 0.6 -- where inside the segment the pointer stops
        self:PickLocal(pick)
        TC:Send("THEMERESULT", pick, ("%.3f"):format(jitter))
        ns.Wheel:Land(pick, jitter, function()
            TC:Announce((L["The next transmog theme is: %s!"]):format(pick), true)
        end)
        TC:Refresh()
    end)
end

------------------------------------------------------------------------
-- Messages
------------------------------------------------------------------------
local H = TC.Handlers

H.THEMEADD = function(self, sender, name)
    if name and name ~= "" then Themes:AddLocal(name) end
end

H.THEMEDEL = function(self, sender, name)
    if name and name ~= "" then Themes:RemoveLocal(name) end
end

H.THEMESPIN = function(self)
    ns.Wheel:StartSpin(Copy(TC.db.themes))
end

H.THEMERESULT = function(self, sender, name, jitter)
    if not name or name == "" then return end
    -- Late or missed THEMESPIN: start from the current pool so the carousel still stops on it.
    if not ns.Wheel:IsSpinning() then ns.Wheel:StartSpin(Copy(TC.db.themes)) end
    Themes:PickLocal(name)
    ns.Wheel:Land(name, tonumber(jitter) or 0.5)
end

H.THEMERESET = function(self)
    Themes:ResetLocal()
end

H.THEMECUR = function(self, sender, name)
    TC.db.currentTheme = (name and name ~= "") and name or nil
end

TC.ListHandlers.TPOOL = function(self, id, items)
    TC.db.themes = items
end

TC.ListHandlers.TUSED = function(self, id, items)
    TC.db.usedThemes = items
end

-- Part of the leader's full sync for late joiners and reloads.
function Themes:SendSync()
    local db = TC.db
    TC:Send("THEMECUR", db.currentTheme)
    TC:SendList("TPOOL", 0, db.themes)
    TC:SendList("TUSED", 0, db.usedThemes)
end
