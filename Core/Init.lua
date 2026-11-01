-- TmogCompetition: core object, constants, saved-variable defaults and shared helpers.
local ADDON, ns = ...

local TC = CreateFrame("Frame")
ns.TC = TC
_G.TmogCompetition = TC

TC.PREFIX = "TMOGC"
TC.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"
TC.MIN_SCORE, TC.MAX_SCORE = 1, 10

TC.group = {}        -- fullName -> unit token (current group members)
TC.participants = {} -- fullName -> { version = "x.y.z" } (group members running the addon)
TC.leader = nil      -- fullName of the group leader

TC.DEFAULTS = {
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
    themeHint = false,     -- leader just pressed Start: highlight Shuffle Themes until a theme or player is drawn
    announce = true,
    autoShow = true,
    frame = nil,
}

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local Util = {}
ns.Util = Util

function TC.Print(msg)
    print("|cffff80ffTmogCompetition|r: " .. msg)
end

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

function Util.SortedKeys(t)
    local list = {}
    for k in pairs(t) do list[#list + 1] = k end
    table.sort(list)
    return list
end

function Util.Split(data, sep)
    local list = {}
    if data and data ~= "" then
        for item in data:gmatch("[^" .. sep .. "]+") do list[#list + 1] = item end
    end
    return list
end

function Util.Round2(n)
    return tonumber(("%.2f"):format(n))
end

function TC:Refresh()
    if ns.UI then ns.UI:Refresh() end
    if ns.Wheel then ns.Wheel:Refresh() end
end
