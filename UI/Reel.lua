-- TmogCompetition: vertical slot-machine reel shared by the theme draw and the player draw.
--
-- The reel loops through a list of items. Three rows are visible: the selected item in
-- the highlighted middle row, plus one above and one below. With a single item left,
-- all three rows show it.
--
-- Spin flow: StartSpin(items) spins freely, Land(pick, onDone) slows down and stops on
-- `pick`, then the result is held for a few seconds before the reel goes idle again.
local ADDON, ns = ...
local TC, S = ns.TC, ns.Style
local C = S.C

local Reel = {}
Reel.__index = Reel
ns.Reel = Reel

Reel.ROW_H = 56          -- height of one reel row
Reel.VISIBLE = 3         -- rows shown: above, selected, below
local ROW_H, VISIBLE = Reel.ROW_H, Reel.VISIBLE
local DRAWN = VISIBLE + 2 -- extra rows so items slide in and out smoothly
local SPEED = 16          -- free spin speed (items per second)
local RAMP = 0.5          -- seconds to reach full speed
local MIN_LAND = 18       -- at least this many items scroll by while slowing down
local HOLD = 4            -- seconds the result stays before the reel goes idle
local TIMEOUT = 15        -- stop a free spin if the leader's result never arrives

local function Sound(kit)
    if SOUNDKIT and SOUNDKIT[kit] then PlaySound(SOUNDKIT[kit]) end
end

local function Copy(list)
    local out = {}
    for i, v in ipairs(list) do out[i] = v end
    return out
end
Reel.Copy = Copy

-- Creates a reel anchored at the top of `parent`, `y` pixels down.
-- opts:
--   label(item)        text shown for an item (default: the item itself)
--   color(seg, n, item) swatch color { r, g, b }
--   emptyKey           locale key shown when there are no items
--   onTick(item)       a new item reached the middle while spinning
--   onFinish(pick)     the reel stopped on `pick`
--   onIdle()           the hold time after a result is over
function Reel:Create(parent, width, y, opts)
    local r = setmetatable({ opts = opts, items = {}, pos = 0 }, Reel)

    local frame = S:Panel(parent, C.bg, C.border)
    frame:SetPoint("TOP", 0, y)
    frame:SetSize(width, ROW_H * VISIBLE + 8)
    r.frame = frame

    -- Clipping viewport the rows slide through.
    local view = CreateFrame("Frame", nil, frame)
    view:SetPoint("TOPLEFT", 4, -4)
    view:SetPoint("BOTTOMRIGHT", -4, 4)
    view:SetClipsChildren(true)
    r.view = view

    r.rows = {}
    for i = 1, DRAWN do
        local row = S:Panel(view, C.panel, C.border)
        row:SetSize(width - 8, ROW_H - 6)
        row.swatch = row:CreateTexture(nil, "ARTWORK")
        row.swatch:SetPoint("TOPLEFT", 1, -1)
        row.swatch:SetPoint("BOTTOMLEFT", 1, 1)
        row.swatch:SetWidth(5)
        row.text = S:Text(row, 16, C.text, "CENTER")
        row.text:SetPoint("LEFT", 14, 0)
        row.text:SetPoint("RIGHT", -14, 0)
        r.rows[i] = row
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
    r.highlight = highlight

    -- Pointer arrows on both sides of the middle row.
    for _, side in ipairs({ { "LEFT", -7 }, { "RIGHT", 7 } }) do
        local arrow = frame:CreateTexture(nil, "OVERLAY")
        arrow:SetSize(10, 10)
        arrow:SetPoint("CENTER", frame, side[1], side[2], 0)
        arrow:SetColorTexture(unpack(C.accent))
        arrow:SetRotation(math.pi / 4)
    end

    r.empty = S:Text(overlay, 13, C.muted, "CENTER")
    r.empty:SetPoint("CENTER")
    if opts.emptyKey then S:Static(r.empty, opts.emptyKey) end

    -- The window can be closed mid-spin, which stops OnUpdate: settle right away so
    -- the result (and the leader's follow-up action) still happens.
    frame:SetScript("OnHide", function()
        if r.state == "landing" then
            r:Draw(r.landing.start + r.landing.distance)
            r:Finish()
        elseif r.state == "spinning" then
            r:Abort()
        end
    end)
    return r
end

------------------------------------------------------------------------
-- Drawing
------------------------------------------------------------------------
-- Reel position p: item j (any integer) sits at (j - p) rows above the middle,
-- so the reel scrolls downward as p grows. Item j shows segment (j mod n) + 1.
local function SegmentAt(j, n)
    return j % n + 1
end

function Reel:Label(item)
    return self.opts.label and self.opts.label(item) or item
end

function Reel:SetItems(list)
    self.items = list
    self.key = table.concat(list, "\n")
    self.centerItem = nil
    self.empty:SetShown(#list == 0)
    self.highlight:SetShown(#list > 0)
end

-- Replaces the items when idle and the list changed, then redraws.
function Reel:SyncIdle(list)
    if self.state then return end
    if table.concat(list, "\n") ~= self.key then self:SetItems(Copy(list)) end
    self:Draw(self.pos)
end

function Reel:Draw(pos)
    self.pos = pos
    local n = #self.items
    if n == 0 then
        for _, row in ipairs(self.rows) do row:Hide() end
        return
    end

    local base = math.floor(pos)
    local half = math.floor(DRAWN / 2)
    local holding = self.state == "holding"
    for i, row in ipairs(self.rows) do
        local j = base - half + i
        local seg = SegmentAt(j, n)
        local item = self.items[seg]
        row:ClearAllPoints()
        row:SetPoint("CENTER", self.view, "CENTER", 0, (j - pos) * ROW_H) -- rows above the middle are positive
        row.text:SetText(self:Label(item))
        local c = self.opts.color(seg, n, item)
        row.swatch:SetColorTexture(c[1], c[2], c[3], 1)
        if math.abs(j - pos) < 0.5 then
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
            if self.opts.onTick then self.opts.onTick(self.items[SegmentAt(center, n)]) end
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
function Reel:IsSpinning()
    return self.state == "spinning" or self.state == "landing"
end

-- Phase 1: spin freely until the leader's result arrives.
function Reel:StartSpin(items)
    self:SetItems(items)
    self.state = "spinning"
    self.elapsed = 0
    self.speed = 0
    self.frame:SetScript("OnUpdate", function(_, elapsed) self:OnUpdate(elapsed) end)
end

-- Phase 2: slow down and stop with `pick` in the middle row. Returns false when the
-- reel is not spinning (onDone is then not called).
function Reel:Land(pick, onDone)
    if not self:IsSpinning() then return false end
    local idx
    for i, item in ipairs(self.items) do
        if item:lower() == pick:lower() then idx = i break end
    end
    if not idx then
        -- Our list was out of date: add the pick so the reel can still stop on it.
        local list = Copy(self.items)
        list[#list + 1] = pick
        self:SetItems(list)
        idx = #list
    end

    -- Find the first integer position >= pos + MIN_LAND whose item is the pick.
    local n = #self.items
    local target = math.ceil(self.pos + MIN_LAND)
    target = target + ((idx - 1) - target % n) % n
    local distance = target - self.pos
    local speed = math.max(self.speed, SPEED * 0.5)
    -- Ease-out cubic starting at the current speed: duration = 3 * distance / speed.
    self.landing = { start = self.pos, distance = distance, duration = 3 * distance / speed, t = 0 }
    self.pick = pick
    self.onDone = onDone
    self.state = "landing"
    return true
end

function Reel:OnUpdate(elapsed)
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

function Reel:Finish()
    self.frame:SetScript("OnUpdate", nil)
    self.state = "holding"
    self.pos = math.floor(self.pos + 0.5)
    if self.frame:IsVisible() then self:Draw(self.pos) end
    if self.opts.onFinish then self.opts.onFinish(self.pick) end
    Sound("UI_EPICLOOT_TOAST")
    local done = self.onDone
    self.onDone = nil
    if done then done() end
    local token = {}
    self.holdToken = token
    C_Timer.After(HOLD, function()
        if self.state == "holding" and self.holdToken == token then
            self.state = nil
            if self.opts.onIdle then self.opts.onIdle() end
            TC:Refresh()
        end
    end)
    TC:Refresh()
end

function Reel:Abort()
    self.frame:SetScript("OnUpdate", nil)
    self.state = nil
    self.pos = math.floor((self.pos or 0) + 0.5)
    TC:Refresh()
end
