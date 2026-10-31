-- TmogCompetition: theme carousel window (a vertical slot-machine reel).
--
-- The reel loops through the theme pool. Three rows are visible: the selected
-- theme in the highlighted middle row, plus one above and one below. With a
-- single theme left, all three rows show it.
--
-- The module keeps the name "Wheel" because the spin flow (Themes.lua) drives
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
local ROW_H = 56            -- height of one reel row
local VISIBLE = 3           -- rows shown: above, selected, below
local DRAWN = VISIBLE + 2   -- extra rows so items slide in and out smoothly
local SPEED = 16            -- free spin speed (items per second)
local RAMP = 0.5            -- seconds to reach full speed
local MIN_LAND = 18         -- at least this many items scroll by while slowing down
local HOLD = 4              -- seconds the result stays before the reel shows the new pool
local TIMEOUT = 15          -- stop a free spin if the leader's result never arrives
local ROW_HEIGHT = 22       -- theme list rows

local PALETTE = {
    { 0.62, 0.36, 0.95 }, { 0.20, 0.70, 0.75 }, { 0.93, 0.38, 0.62 }, { 0.98, 0.68, 0.25 },
    { 0.33, 0.55, 0.95 }, { 0.35, 0.80, 0.50 }, { 0.95, 0.45, 0.35 }, { 0.55, 0.45, 0.85 },
}

local function Sound(kit)
    if SOUNDKIT and SOUNDKIT[kit] then PlaySound(SOUNDKIT[kit]) end
end

local function Copy(list)
    local out = {}
    for i, v in ipairs(list) do out[i] = v end
    return out
end

------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------
function Wheel:BuildReel(f)
    self.resultLabel = S:Text(f, 10, C.muted, "CENTER")
    self.resultLabel:SetPoint("TOP", 0, -48)

    local reel = S:Panel(f, C.bg, C.border)
    reel:SetPoint("TOP", 0, -64)
    reel:SetSize(INNER, ROW_H * VISIBLE + 8)
    self.reelFrame = reel

    -- Clipping viewport the rows slide through.
    local view = CreateFrame("Frame", nil, reel)
    view:SetPoint("TOPLEFT", 4, -4)
    view:SetPoint("BOTTOMRIGHT", -4, 4)
    view:SetClipsChildren(true)
    self.view = view

    self.reelRows = {}
    for i = 1, DRAWN do
        local row = S:Panel(view, C.panel, C.border)
        row:SetSize(INNER - 8, ROW_H - 6)
        row.swatch = row:CreateTexture(nil, "ARTWORK")
        row.swatch:SetPoint("TOPLEFT", 1, -1)
        row.swatch:SetPoint("BOTTOMLEFT", 1, 1)
        row.swatch:SetWidth(5)
        row.text = S:Text(row, 16, C.text, "CENTER")
        row.text:SetPoint("LEFT", 14, 0)
        row.text:SetPoint("RIGHT", -14, 0)
        self.reelRows[i] = row
    end

    -- Overlay: fades at the top/bottom and the highlight frame on the middle row.
    local overlay = CreateFrame("Frame", nil, view)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(view:GetFrameLevel() + 10)
    local bg = C.bg
    local top = overlay:CreateTexture(nil, "OVERLAY")
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    top:SetHeight(ROW_H)
    top:SetColorTexture(1, 1, 1, 1)
    top:SetGradient("VERTICAL", CreateColor(bg[1], bg[2], bg[3], 0), CreateColor(bg[1], bg[2], bg[3], 0.85))
    local bottom = overlay:CreateTexture(nil, "OVERLAY")
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT")
    bottom:SetHeight(ROW_H)
    bottom:SetColorTexture(1, 1, 1, 1)
    bottom:SetGradient("VERTICAL", CreateColor(bg[1], bg[2], bg[3], 0.85), CreateColor(bg[1], bg[2], bg[3], 0))

    local highlight = S:Panel(overlay, { 0, 0, 0, 0 }, C.accent)
    highlight:SetPoint("LEFT", -2, 0)
    highlight:SetPoint("RIGHT", 2, 0)
    highlight:SetHeight(ROW_H - 2)
    self.highlight = highlight

    -- Pointer arrows on both sides of the middle row.
    for _, side in ipairs({ { "LEFT", -7 }, { "RIGHT", 7 } }) do
        local arrow = reel:CreateTexture(nil, "OVERLAY")
        arrow:SetSize(10, 10)
        arrow:SetPoint("CENTER", reel, side[1], side[2], 0)
        arrow:SetColorTexture(unpack(C.accent))
        arrow:SetRotation(math.pi / 4)
    end

    self.empty = S:Text(overlay, 13, C.muted, "CENTER")
    self.empty:SetPoint("CENTER")
    S:Static(self.empty, "No themes yet")

    self.result = S:Text(f, 18, C.gold, "CENTER")
    self.result:SetPoint("TOP", reel, "BOTTOM", 0, -12)
    self.result:SetWidth(INNER)

    self.segments = {}
    self.pos = 0
end

function Wheel:BuildControls(f)
    self.spinBtn = S:Button(f, "Spin", 180, 32, "primary", function() ns.Themes:CmdSpin() end,
        "Spin for everyone. The theme it stops on is removed from the pool.")
    self.spinBtn.label:SetFontObject(S:Font(13))
    self.spinBtn:SetPoint("TOP", 0, -276)

    self.notLeader = S:Text(f, 11, C.muted, "CENTER")
    self.notLeader:SetPoint("TOP", 0, -286)
    S:Static(self.notLeader, "Only the raid leader can add themes and spin.")

    self.listLabel = S:Label(f, "Themes")
    self.listLabel:SetPoint("TOPLEFT", PAD, -330)
    self.resetBtn = S:Button(f, "Reset used", 90, 20, "ghost", function() ns.Themes:CmdReset() end,
        "Put every theme that was already picked back in the draw.")
    self.resetBtn:SetPoint("TOPRIGHT", -PAD, -324)

    local function add(edit)
        if ns.Themes:CmdAdd(edit:GetText()) then edit:SetText("") end
    end
    self.input = S:Input(f, INNER - 78, 26, "New theme, e.g. Pirates", 40, add)
    self.input:SetPoint("TOPLEFT", PAD, -352)
    self.addBtn = S:Button(f, "Add", 70, 26, "primary", function() add(self.input) end)
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
    local f = S:Window("TmogCompetitionWheel", WIDTH, HEIGHT, "Theme Draw")
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

-- Reel position p: item j (any integer) sits at (j - p) rows above the middle,
-- so the reel scrolls downward as p grows. Item j shows segment (j mod n) + 1.
local function SegmentAt(j, n)
    return j % n + 1
end

function Wheel:SetSegments(list)
    self.segments = list
    self.segKey = table.concat(list, "\n")
    self.centerItem = nil
    self.empty:SetShown(#list == 0)
    self.highlight:SetShown(#list > 0)
end

function Wheel:Draw(pos)
    self.pos = pos
    local n = #self.segments
    if n == 0 then
        for _, row in ipairs(self.reelRows) do row:Hide() end
        return
    end

    local base = math.floor(pos)
    local half = math.floor(DRAWN / 2)
    local holding = self.state == "holding"
    for i, row in ipairs(self.reelRows) do
        local j = base - half + i
        local offset = (j - pos) * ROW_H -- rows above the middle are positive
        local seg = SegmentAt(j, n)
        local distance = math.abs(j - pos)
        row:ClearAllPoints()
        row:SetPoint("CENTER", self.view, "CENTER", 0, offset)
        row.text:SetText(self.segments[seg])
        local c = self:SegmentColor(seg, n)
        row.swatch:SetColorTexture(c[1], c[2], c[3], 1)
        if distance < 0.5 then
            row.text:SetTextColor(unpack(holding and C.gold or C.text))
            row:SetBackdropColor(unpack(C.panelHi))
        else
            row.text:SetTextColor(unpack(C.muted))
            row:SetBackdropColor(unpack(C.panel))
        end
        row:Show()
    end

    -- Tick when a new item reaches the middle.
    local center = math.floor(pos + 0.5)
    if center ~= self.centerItem then
        self.centerItem = center
        if self:IsSpinning() then
            self.result:SetText(S:Color(C.text, self.segments[SegmentAt(center, n)]))
            local now = GetTime()
            if now - (self.lastTick or 0) > 0.06 then
                self.lastTick = now
                Sound("U_CHAT_SCROLL_BUTTON")
            end
        end
    end
end

------------------------------------------------------------------------
-- Spinning
------------------------------------------------------------------------
function Wheel:IsSpinning()
    return self.state == "spinning" or self.state == "landing"
end

-- Phase 1: spin freely until the leader's result arrives.
function Wheel:StartSpin(pool)
    self:Build()
    self.frame:Show()
    self:SetSegments(pool)
    self.state = "spinning"
    self.elapsed = 0
    self.speed = 0
    self.resultLabel:SetText(L["SPINNING..."])
    self.reelFrame:SetScript("OnUpdate", function(_, elapsed) self:OnUpdate(elapsed) end)
    self:Refresh()
end

-- Phase 2: slow down and stop with `pick` in the middle row.
-- (jitter is part of the message format from the old wheel and is not needed here.)
function Wheel:Land(pick, jitter, onDone)
    if not self:IsSpinning() then return end
    local idx
    for i, name in ipairs(self.segments) do
        if name:lower() == pick:lower() then idx = i break end
    end
    if not idx then
        -- Our pool was out of date: add the pick so the reel can still stop on it.
        local list = Copy(self.segments)
        list[#list + 1] = pick
        self:SetSegments(list)
        idx = #list
    end

    -- Find the first integer position >= pos + MIN_LAND whose item is the pick.
    local n = #self.segments
    local target = math.ceil(self.pos + MIN_LAND)
    target = target + ((idx - 1) - target % n) % n
    local distance = target - self.pos
    local speed = math.max(self.speed, SPEED * 0.5)
    -- Ease-out cubic starting at the current speed: duration = 3 * distance / speed.
    self.landing = { start = self.pos, distance = distance, duration = 3 * distance / speed, t = 0 }
    self.pick = pick
    self.onDone = onDone
    self.state = "landing"
end

function Wheel:OnUpdate(elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.state == "spinning" then
        self.speed = SPEED * math.min(1, self.elapsed / RAMP)
        self:Draw(self.pos + self.speed * elapsed)
        if self.elapsed > TIMEOUT then self:Abort() end
    elseif self.state == "landing" then
        local l = self.landing
        l.t = l.t + elapsed
        local p = math.min(1, l.t / l.duration)
        self:Draw(l.start + l.distance * (1 - (1 - p) ^ 3))
        if p >= 1 then self:Finish() end
    end
end

function Wheel:Finish()
    self.reelFrame:SetScript("OnUpdate", nil)
    self.state = "holding"
    self.pos = math.floor(self.pos + 0.5)
    self:Draw(self.pos)
    self.resultLabel:SetText(L["THE NEXT THEME IS"])
    self.result:SetText(S:Color(C.gold, self.pick))
    Sound("UI_EPICLOOT_TOAST")
    local done = self.onDone
    self.onDone = nil
    if done then done() end
    C_Timer.After(HOLD, function()
        if self.state == "holding" then
            self.state = nil
            self:Refresh()
        end
    end)
    self:Refresh()
end

function Wheel:Abort()
    if self.reelFrame then self.reelFrame:SetScript("OnUpdate", nil) end
    self.state = nil
    self.pos = math.floor((self.pos or 0) + 0.5)
    self:Refresh()
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
            "Remove this theme")
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
            row.status:SetText(current and S:Color(C.gold, L["CURRENT"]) or L["USED"])
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
    if not self.state then
        if table.concat(db.themes, "\n") ~= self.segKey then self:SetSegments(Copy(db.themes)) end
        self:Draw(self.pos)
        self.resultLabel:SetText(L["CURRENT THEME"])
        if db.currentTheme then
            self.result:SetText(S:Color(C.gold, db.currentTheme))
        else
            self.result:SetText(S:Color(C.muted, isLeader and L["Add themes, then spin"]
                or L["Waiting for the leader to spin"]))
        end
    end

    self.spinBtn:SetShown(isLeader)
    self.spinBtn:SetEnabled(not self:IsSpinning() and not ns.Themes.pickPending and #db.themes > 0)
    self.notLeader:SetShown(not isLeader)
    self.input:SetShown(isLeader)
    self.addBtn:SetShown(isLeader)
    self.resetBtn:SetShown(isLeader)
    self.resetBtn:SetEnabled(#db.usedThemes > 0)

    self.listLabel:SetText(S:Upper((L["Themes  -  %d left, %d used"]):format(#db.themes, #db.usedThemes)))
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
