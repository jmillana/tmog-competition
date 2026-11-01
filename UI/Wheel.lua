-- TmogCompetition: theme draw window (the reel itself is UI/Reel.lua).
--
-- The module keeps the name "Wheel" because the spin flow (Modules/Themes.lua) drives
-- it through StartSpin / Land / Abort / IsSpinning.
local ADDON, ns = ...
local TC, S = ns.TC, ns.Style
local L = ns.L
local C = S.C

local Wheel = {}
ns.Wheel = Wheel

local WIDTH, HEIGHT = 380, 600
local PAD = 16
local INNER = WIDTH - 2 * PAD
local ROW_HEIGHT = 22       -- theme list rows

local PALETTE = {
    { 0.62, 0.36, 0.95 }, { 0.20, 0.70, 0.75 }, { 0.93, 0.38, 0.62 }, { 0.98, 0.68, 0.25 },
    { 0.33, 0.55, 0.95 }, { 0.35, 0.80, 0.50 }, { 0.95, 0.45, 0.35 }, { 0.55, 0.45, 0.85 },
}

------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------
function Wheel:BuildReel(f)
    self.resultLabel = S:Text(f, 10, C.muted, "CENTER")
    self.resultLabel:SetPoint("TOP", 0, -48)

    self.reel = ns.Reel:Create(f, INNER, -64, {
        emptyKey = "DRAW_NO_THEMES",
        color = function(seg, n) return self:SegmentColor(seg, n) end,
        onTick = function(theme) self.result:SetText(S:Color(C.text, theme)) end,
        onFinish = function(theme)
            self.resultLabel:SetText(L.DRAW_NEXT_THEME_IS)
            self.result:SetText(S:Color(C.gold, theme))
        end,
    })

    self.result = S:Text(f, 18, C.gold, "CENTER")
    self.result:SetPoint("TOP", self.reel.frame, "BOTTOM", 0, -12)
    self.result:SetWidth(INNER)
end

function Wheel:BuildControls(f)
    self.spinBtn = S:Button(f, "DRAW_SPIN", 180, 32, "primary", function() ns.Themes:CmdSpin() end,
        "DRAW_SPIN_TIP")
    self.spinBtn.label:SetFontObject(S:Font(13))
    self.spinBtn:SetPoint("TOP", 0, -276)

    self.notLeader = S:Text(f, 11, C.muted, "CENTER")
    self.notLeader:SetPoint("TOP", 0, -286)
    S:Static(self.notLeader, "DRAW_LEADER_ONLY")

    self.listLabel = S:Label(f, "DRAW_THEMES")
    self.listLabel:SetPoint("TOPLEFT", PAD, -330)
    self.resetBtn = S:Button(f, "DRAW_RESET_USED", 90, 20, "ghost", function() ns.Themes:CmdReset() end,
        "DRAW_RESET_USED_TIP")
    self.resetBtn:SetPoint("TOPRIGHT", -PAD, -324)

    local function add(edit)
        if ns.Themes:CmdAdd(edit:GetText()) then edit:SetText("") end
    end
    self.input = S:Input(f, INNER - 78, 26, "DRAW_NEW_THEME_PLACEHOLDER", 40, add)
    self.input:SetPoint("TOPLEFT", PAD, -352)
    self.addBtn = S:Button(f, "DRAW_ADD", 70, 26, "primary", function() add(self.input) end)
    self.addBtn:SetPoint("TOPRIGHT", -PAD, -352)

    local card = S:Panel(f)
    card:SetPoint("BOTTOMRIGHT", -PAD, 16)
    self.listCard = card
    local scroll = S:ScrollArea(card)
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -4, 4)
    self.scroll = scroll
    self.rows = {}
end

function Wheel:Build()
    if self.frame then return end
    local f = S:Window("TmogCompetitionWheel", WIDTH, HEIGHT, "DRAW_TITLE")
    self.frame = f
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    self:BuildReel(f)
    self:BuildControls(f)
    f:SetScript("OnShow", function() self:Refresh() end)
end

------------------------------------------------------------------------
-- Drawing
------------------------------------------------------------------------
function Wheel:SegmentColor(seg, n)
    local idx = (seg - 1) % #PALETTE + 1
    if seg == n and n > 1 and idx == 1 then idx = 2 end -- last never matches the first when looping
    return PALETTE[idx]
end

------------------------------------------------------------------------
-- Spinning (the reel lives in UI/Reel.lua)
------------------------------------------------------------------------
function Wheel:IsSpinning()
    return self.reel ~= nil and self.reel:IsSpinning()
end

-- Phase 1: spin freely until the leader's result arrives.
function Wheel:StartSpin(pool)
    self:Build()
    self.frame:Show()
    self.reel:StartSpin(pool)
    self.resultLabel:SetText(L.DRAW_SPINNING)
    TC:Refresh() -- also updates the main window's Shuffle Themes button
end

-- Phase 2: slow down and stop with `pick` in the middle row.
-- (jitter is part of the message format from the old wheel and is not needed here.)
function Wheel:Land(pick, jitter, onDone)
    if self.reel then return self.reel:Land(pick, onDone) end
    return false
end

function Wheel:Abort()
    if self.reel then self.reel:Abort() end
end

------------------------------------------------------------------------
-- Theme list
------------------------------------------------------------------------
function Wheel:GetRow(i)
    local row = self.rows[i]
    if not row then
        row = CreateFrame("Frame", nil, self.scroll.child)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_HEIGHT)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.swatch = row:CreateTexture(nil, "ARTWORK")
        row.swatch:SetSize(4, ROW_HEIGHT - 8)
        row.swatch:SetPoint("LEFT", 6, 0)
        row.name = S:Text(row, 12, C.text)
        row.name:SetPoint("LEFT", 18, 0)
        row.name:SetWidth(200)
        row.remove = S:Button(row, "x", 20, 18, "ghost", function() ns.Themes:CmdRemove(row.theme) end,
            "DRAW_REMOVE_THEME_TIP")
        row.remove:SetPoint("RIGHT", -8, 0)
        row.status = S:Text(row, 10, C.muted, "RIGHT")
        row.status:SetPoint("RIGHT", row.remove, "LEFT", -8, 0)
        self.rows[i] = row
    end
    return row
end

function Wheel:RefreshList(db, isLeader)
    local entries = {}
    for i, name in ipairs(db.themes) do entries[#entries + 1] = { name = name, seg = i } end
    for _, name in ipairs(db.usedThemes) do entries[#entries + 1] = { name = name, used = true } end

    for i, e in ipairs(entries) do
        local row = self:GetRow(i)
        row:Show()
        row.theme = e.name
        row.name:SetText(e.name)
        row.remove:SetShown(isLeader)
        if e.used then
            row.name:SetTextColor(unpack(C.muted))
            row.swatch:SetColorTexture(1, 1, 1, 0.1)
            local current = db.currentTheme and db.currentTheme:lower() == e.name:lower()
            row.status:SetText(current and S:Color(C.gold, L.DRAW_STATUS_CURRENT) or L.DRAW_STATUS_USED)
        else
            local c = self:SegmentColor(e.seg, #db.themes)
            row.name:SetTextColor(unpack(C.text))
            row.swatch:SetColorTexture(c[1], c[2], c[3], 1)
            row.status:SetText("")
        end
        row.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.025 or 0)
    end
    for i = #entries + 1, #self.rows do self.rows[i]:Hide() end
    self.scroll.child:SetHeight(math.max(1, #entries * ROW_HEIGHT))
    self.scroll:UpdateThumb()
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
function Wheel:Refresh()
    if not self.frame or not self.frame:IsShown() or not TC.db then return end
    local db = TC.db
    local isLeader = TC:IsLeader()

    -- While spinning or showing a result the reel keeps its own snapshot of the pool.
    if not self.reel.state then
        self.reel:SyncIdle(db.themes)
        self.resultLabel:SetText(L.DRAW_CURRENT_THEME)
        if db.currentTheme then
            self.result:SetText(S:Color(C.gold, db.currentTheme))
        else
            self.result:SetText(S:Color(C.muted, isLeader and L.DRAW_HINT_LEADER
                or L.DRAW_HINT_WAIT))
        end
    end

    self.spinBtn:SetShown(isLeader)
    self.spinBtn:SetEnabled(not TC:IsDrawRunning() and #db.themes > 0)
    self.notLeader:SetShown(not isLeader)
    self.input:SetShown(isLeader)
    self.addBtn:SetShown(isLeader)
    self.resetBtn:SetShown(isLeader)
    self.resetBtn:SetEnabled(#db.usedThemes > 0)

    self.listLabel:SetText(S:Upper(L:Format("DRAW_THEMES_COUNT", { left = #db.themes, used = #db.usedThemes })))
    self.listCard:SetPoint("TOPLEFT", PAD, isLeader and -386 or -352)
    self:RefreshList(db, isLeader)
end

------------------------------------------------------------------------
-- Visibility
------------------------------------------------------------------------
function Wheel:Show()
    self:Build()
    self.frame:Show()
end

function Wheel:Toggle()
    self:Build()
    self.frame:SetShown(not self.frame:IsShown())
end
