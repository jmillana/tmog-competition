-- TmogCompetition: settings window (opened from the gear icon on the main window).
local ADDON, ns = ...
local TC, S = ns.TC, ns.Style
local C = S.C

local Settings = {}
ns.Settings = Settings

local WIDTH, HEIGHT = 330, 350
local PAD = 16
local INNER = WIDTH - 2 * PAD

-- Re-translates every open window after the language changes.
function ns.ApplyLanguage(lang)
    TC.db.language = lang
    ns.SetLanguage(lang)
    S:Relocalize()
    TC:Refresh()
    if ns.Gallery then ns.Gallery:Refresh() end
    if ns.Explore then ns.Explore:Refresh() end
    Settings:Refresh()
end

function Settings:Build()
    if self.frame then return end
    local f = S:Window("TmogCompetitionSettings", WIDTH, HEIGHT, "SETTINGS_TITLE")
    self.frame = f
    f:SetFrameStrata("DIALOG")

    local langLabel = S:Label(f, "SETTINGS_LANGUAGE")
    langLabel:SetPoint("TOPLEFT", PAD, -50)

    self.langButtons = {}
    for i, lang in ipairs(ns.LANGUAGES) do
        local b = S:Button(f, lang.label, INNER, 26, "secondary", function() ns.ApplyLanguage(lang.key) end)
        b:SetPoint("TOPLEFT", PAD, -66 - (i - 1) * 30)
        b.key = lang.key
        self.langButtons[i] = b
    end

    local generalLabel = S:Label(f, "SETTINGS_GENERAL")
    generalLabel:SetPoint("TOPLEFT", PAD, -172)

    self.announce = S:Checkbox(f, "SETTINGS_ANNOUNCE",
        "SETTINGS_ANNOUNCE_TIP",
        function() return TC.db.announce end,
        function(value) TC.db.announce = value end)
    self.announce:SetPoint("TOPLEFT", PAD, -188)
    self.announce:SetWidth(INNER)

    self.autoShow = S:Checkbox(f, "SETTINGS_AUTO_SHOW",
        "SETTINGS_AUTO_SHOW_TIP",
        function() return TC.db.autoShow end,
        function(value) TC.db.autoShow = value end)
    self.autoShow:SetPoint("TOPLEFT", PAD, -214)
    self.autoShow:SetWidth(INNER)

    self.restartRounds = S:Checkbox(f, "SETTINGS_RESTART_ROUNDS",
        "SETTINGS_RESTART_ROUNDS_TIP",
        function() return TC.db.restartRounds end,
        function(value) TC.db.restartRounds = value end)
    self.restartRounds:SetPoint("TOPLEFT", PAD, -240)
    self.restartRounds:SetWidth(INNER)

    local note = S:Text(f, 10, C.muted, "CENTER")
    note:SetPoint("BOTTOM", 0, 16)
    note:SetWidth(INNER)
    S:Static(note, "SETTINGS_SAVED_NOTE")

    f:SetScript("OnShow", function() self:Refresh() end)
end

function Settings:Refresh()
    if not self.frame or not self.frame:IsShown() or not TC.db then return end
    local current = TC.db.language or "auto"
    for _, b in ipairs(self.langButtons) do
        b:SetSelected(b.key == current)
    end
    self.announce:Update()
    self.autoShow:Update()
    self.restartRounds:Update()
end

function Settings:Toggle()
    self:Build()
    if self.frame:IsShown() then
        self.frame:Hide()
        return
    end
    self.frame:ClearAllPoints()
    local main = ns.UI.frame
    if main and main:IsShown() then
        self.frame:SetPoint("TOPLEFT", main, "TOPRIGHT", 8, 0)
    else
        self.frame:SetPoint("CENTER")
    end
    self.frame:Show()
end
