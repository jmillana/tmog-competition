-- TmogCompetition: capture, share and render each contestant's outfit.
--
-- When a player goes on stage their client reads its own transmog from a hidden
-- DressUpModel and broadcasts the appearance IDs. Every client stores them so the
-- gallery can redraw the outfit later, even when the player is far away or has
-- changed clothes.
local ADDON, ns = ...
local TC = ns.TC
local L = ns.L

local Outfit = {}
ns.Outfit = Outfit

Outfit.version = 0 -- bumped whenever any stored outfit changes, so models know to redraw

local CHUNK = 200
local CAPTURE_INTERVAL, CAPTURE_TRIES = 0.25, 20

local function NativeForm()
    return PlayerUtil and PlayerUtil.ShouldUseNativeFormInModelScene
        and PlayerUtil.ShouldUseNativeFormInModelScene() or false
end

------------------------------------------------------------------------
-- Capture
------------------------------------------------------------------------
local captureModel
local function GetCaptureModel()
    if not captureModel then
        captureModel = CreateFrame("DressUpModel", nil, UIParent)
        captureModel:SetSize(64, 64)
        captureModel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
        captureModel:SetAlpha(0)
        captureModel:EnableMouse(false)
    end
    return captureModel
end

-- ItemTransmogInfo list (indexed by inventory slot) -> compact slots table.
local function ReadList(list)
    local slots, any = {}, false
    for slot, info in pairs(list) do
        local app = info.appearanceID or 0
        local sec = info.secondaryAppearanceID or 0
        local ill = info.illusionID or 0
        if app ~= 0 or sec ~= 0 or ill ~= 0 then
            slots[slot] = { app, sec, ill }
            any = true
        end
    end
    return slots, any
end

function Outfit:CaptureAndSend()
    if self.ticker then self.ticker:Cancel() end
    local model = GetCaptureModel()
    model:Show()
    model:SetUnit("player", false, NativeForm())

    local tries = 0
    self.ticker = C_Timer.NewTicker(CAPTURE_INTERVAL, function(ticker)
        tries = tries + 1
        local list = model.GetItemTransmogInfoList and model:GetItemTransmogInfoList()
        local slots, any = {}, false
        if list then slots, any = ReadList(list) end
        if not any and tries < CAPTURE_TRIES then return end

        ticker:Cancel()
        self.ticker = nil
        model:Hide()
        if not any then
            TC.Print(L.OUTFIT_CAPTURE_FAILED)
            return
        end
        local _, _, raceID = UnitRace("player")
        local outfit = { race = raceID, sex = UnitSex("player"), slots = slots }
        self:Store(TC:Me(), outfit)
        self:Send(outfit)
    end)
end

------------------------------------------------------------------------
-- Sharing
------------------------------------------------------------------------
function Outfit:Store(name, outfit)
    if not name then return end
    TC.db.outfits[name] = outfit
    self.version = self.version + 1
    if ns.History then ns.History:OnOutfit(name, outfit) end
    TC:Refresh()
    if ns.Gallery then ns.Gallery:Refresh() end
end

-- OUTFIT, raceID, sex, more(1/0), "slot:appearance:secondary:illusion,..."
function Outfit:Send(outfit)
    local items = {}
    for slot, s in pairs(outfit.slots) do
        items[#items + 1] = ("%d:%d:%d:%d"):format(slot, s[1], s[2], s[3])
    end
    local chunk, len = {}, 0
    local function flush(more)
        TC:Send("OUTFIT", outfit.race or 0, outfit.sex or 0, more and 1 or 0, table.concat(chunk, ","))
        wipe(chunk)
        len = 0
    end
    for _, item in ipairs(items) do
        if #chunk > 0 and len + #item + 1 > CHUNK then flush(true) end
        chunk[#chunk + 1] = item
        len = len + #item + 1
    end
    flush(false)
end

function Outfit:ScheduleResend()
    if self.resendPending then return end
    self.resendPending = true
    C_Timer.After(1 + math.random() * 3, function()
        self.resendPending = false
        local outfit = TC.db.outfits[TC:Me()]
        if outfit then self:Send(outfit) end
    end)
end

local buffers = {}
TC.Handlers.OUTFIT = function(self, sender, race, sex, more, data)
    local buf = buffers[sender]
    if not buf or GetTime() - buf.time > 10 then
        buf = { slots = {} }
        buffers[sender] = buf
    end
    buf.time = GetTime()
    if data and data ~= "" then
        for item in data:gmatch("[^,]+") do
            local slot, app, sec, ill = strsplit(":", item)
            slot = tonumber(slot)
            if slot then buf.slots[slot] = { tonumber(app) or 0, tonumber(sec) or 0, tonumber(ill) or 0 } end
        end
    end
    if more == "0" then
        buffers[sender] = nil
        Outfit:Store(sender, { race = tonumber(race), sex = tonumber(sex), slots = buf.slots })
    end
end

-- While on stage, re-capture when the contestant changes gear or transmog.
local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "TRANSMOGRIFY_SUCCESS" }) do
    if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid(event) then
        pcall(events.RegisterEvent, events, event)
    end
end
events:SetScript("OnEvent", function()
    local db = TC.db
    if not db or db.phase ~= "VOTING" or db.contestant ~= TC:Me() or Outfit.recapturePending then return end
    Outfit.recapturePending = true
    C_Timer.After(1, function()
        Outfit.recapturePending = false
        Outfit:CaptureAndSend()
    end)
end)

------------------------------------------------------------------------
-- Rendering
------------------------------------------------------------------------
local function ApplySlots(model, outfit)
    model:Undress()
    local canSetInfo = model.SetItemTransmogInfo and ItemUtil and ItemUtil.CreateItemTransmogInfo
    for slot, s in pairs(outfit.slots) do
        local ok = false
        if canSetInfo then
            local info = ItemUtil.CreateItemTransmogInfo(s[1], s[2], s[3])
            ok = pcall(model.SetItemTransmogInfo, model, info, slot, slot ~= INVSLOT_MAINHAND)
        end
        if not ok and s[1] ~= 0 then pcall(model.TryOn, model, s[1]) end
    end
end

-- Prepares a DressUpModel for Render: re-applies the outfit once the body has loaded,
-- and lets the user drag to rotate it.
function Outfit:SetupModel(model)
    model:SetScript("OnModelLoaded", function(m)
        local apply = m.applyOnLoad
        m.applyOnLoad = nil
        if apply then apply() end
    end)
    model:EnableMouse(true)
    model:SetScript("OnMouseDown", function(m, button)
        if button == "LeftButton" then m.dragX = GetCursorPosition() end
    end)
    model:SetScript("OnMouseUp", function(m, button)
        m.dragX = nil
        if button == "RightButton" and m.onRightClick then m.onRightClick(m) end
    end)
    model:SetScript("OnUpdate", function(m)
        if not m.dragX then return end
        local x = GetCursorPosition()
        m.facing = (m.facing or 0) + (x - m.dragX) * 0.02
        m.dragX = x
        m:SetFacing(m.facing)
    end)
end

-- Draws `name` on a DressUpModel. With useStored, the saved outfit is put on the body,
-- otherwise the live unit is shown as it looks right now.
-- Returns an optional note to show under the model.
function Outfit:Render(model, name, useStored)
    local outfit = useStored and name and TC.db.outfits[name] or nil
    if outfit then return self:RenderOutfit(model, name, outfit) end

    model.applyOnLoad = nil
    if not name then
        model:ClearModel()
        return nil
    end
    local unit = TC.group[name]
    if unit and UnitIsVisible(unit) then
        model:SetUnit(unit, false, UnitIsUnit(unit, "player") and NativeForm() or false)
        return nil
    end
    model:ClearModel()
    return L:Format("OUTFIT_MOVE_CLOSER", { player = TC:Short(name) })
end

-- Draws a specific saved outfit for `name` (used by the gallery history).
function Outfit:RenderOutfit(model, name, outfit)
    model.applyOnLoad = nil
    if not outfit then
        model:ClearModel()
        return L.OUTFIT_NOT_CAPTURED
    end

    local unit = name and TC.group[name]
    local note
    if unit and UnitIsVisible(unit) then
        model:SetUnit(unit, false, UnitIsUnit(unit, "player") and NativeForm() or false)
    else
        model:SetUnit("player", false, NativeForm())
        if name ~= TC:Me() then
            local ok = false
            if model.SetCustomRace and outfit.race and outfit.sex then
                ok = pcall(model.SetCustomRace, model, outfit.race, outfit.sex - 2)
            end
            if not ok then note = L.OUTFIT_ON_YOUR_CHARACTER end
        end
    end

    ApplySlots(model, outfit)
    model.applyOnLoad = function() ApplySlots(model, outfit) end
    return note
end

-- Cache key so callers only redraw when something relevant changed.
function Outfit:RenderKey(name, useStored)
    local unit = name and TC.group[name]
    local visible = unit and UnitIsVisible(unit) and 1 or 0
    return ("%s|%d|%d|%s"):format(name or "", visible, self.version, tostring(useStored))
end
