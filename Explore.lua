-- TmogCompetition: "Explore" panel listing every piece of a saved outfit with item tooltips.
local ADDON, ns = ...
local TC, S = ns.TC, ns.Style
local L = ns.L
local C = S.C

local Explore = {}
ns.Explore = Explore

local WIDTH, HEIGHT = 330, 520
local PAD = 14
local ROW_HEIGHT = 34

-- Display order and names of transmog slots (inventory slot IDs).
local SLOTS = {
    { 1, "HEADSLOT", "Head" }, { 3, "SHOULDERSLOT", "Shoulder" }, { 15, "BACKSLOT", "Back" },
    { 5, "CHESTSLOT", "Chest" }, { 4, "SHIRTSLOT", "Shirt" }, { 19, "TABARDSLOT", "Tabard" },
    { 9, "WRISTSLOT", "Wrist" }, { 10, "HANDSSLOT", "Hands" }, { 6, "WAISTSLOT", "Waist" },
    { 7, "LEGSSLOT", "Legs" }, { 8, "FEETSLOT", "Feet" }, { 16, "MAINHANDSLOT", "Main Hand" },
    { 17, "SECONDARYHANDSLOT", "Off Hand" },
}

local function SlotName(def)
    return L[def[3]] -- follows the addon language, not the game client
end

local function InsertLink(link)
    if not link then return end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        ChatFrameUtil.InsertLink(link)
    elseif ChatEdit_InsertLink then
        ChatEdit_InsertLink(link)
    end
end

local function IsAppearanceCollected(info)
    if info.isCollected then return true end
    local sources = info.visualID and C_TransmogCollection.GetAllAppearanceSources
        and C_TransmogCollection.GetAllAppearanceSources(info.visualID)
    for _, sourceID in ipairs(sources or {}) do
        local other = C_TransmogCollection.GetSourceInfo(sourceID)
        if other and other.isCollected then return true end
    end
    return false
end

------------------------------------------------------------------------
-- Piece data
------------------------------------------------------------------------
-- Returns { slot, label, itemID, name, quality, icon, link, collected, illusionLink } per piece.
function Explore:GetPieces(outfit)
    local pieces = {}
    local function addSource(label, sourceID)
        if not sourceID or sourceID == 0 then return end
        local info = C_TransmogCollection.GetSourceInfo(sourceID)
        if not info or not info.itemID then return end
        local piece = {
            label = label,
            itemID = info.itemID,
            name = info.name,
            quality = info.quality,
            icon = C_Item.GetItemIconByID(info.itemID),
            collected = IsAppearanceCollected(info),
        }
        local itemName, link, quality = C_Item.GetItemInfo(info.itemID)
        piece.name = piece.name or itemName
        piece.link = link
        piece.quality = piece.quality or quality
        if not itemName then piece.pending = true end -- item data still loading
        pieces[#pieces + 1] = piece
        return piece
    end

    for _, def in ipairs(SLOTS) do
        local s = outfit.slots[def[1]]
        if s then
            local label = SlotName(def)
            local piece = addSource(label, s[1])
            if s[2] ~= 0 and s[2] ~= s[1] then addSource(label .. " (2)", s[2]) end
            if s[3] ~= 0 and piece and C_TransmogCollection.GetIllusionStrings then
                local ok, name, link = pcall(C_TransmogCollection.GetIllusionStrings, s[3])
                if ok and name then
                    piece.illusionName, piece.illusionLink = name, link
                end
            end
        end
    end
    return pieces
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
function Explore:Build()
    if self.frame then return end
    local f = S:Window("TmogCompetitionExplore", WIDTH, HEIGHT, "Explore Outfit")
    self.frame = f
    f:SetFrameStrata("DIALOG")

    self.who = S:Text(f, 15, C.text)
    self.who:SetPoint("TOPLEFT", PAD, -46)
    self.who:SetWidth(WIDTH - 2 * PAD)
    self.context = S:Text(f, 11, C.muted)
    self.context:SetPoint("TOPLEFT", PAD, -66)
    self.context:SetWidth(WIDTH - 2 * PAD)

    local card = S:Panel(f)
    card:SetPoint("TOPLEFT", PAD, -86)
    card:SetPoint("BOTTOMRIGHT", -PAD, 74)
    local scroll = S:ScrollArea(card)
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -4, 4)
    self.scroll = scroll
    self.rows = {}

    self.hint = S:Text(f, 10, C.muted, "CENTER")
    self.hint:SetPoint("BOTTOM", 0, 50)
    S:Static(self.hint, "Hover a piece for its tooltip. Shift-click to link it in chat.")

    self.tryOn = S:Button(f, "Try on", 120, 26, "primary", function() self:TryOn() end,
        "Open the whole outfit in the dressing room.")
    self.tryOn:SetPoint("BOTTOM", 0, 14)

    f:SetScript("OnHide", function() self.outfit = nil end)
end

function Explore:GetRow(i)
    local row = self.rows[i]
    if row then return row end

    row = CreateFrame("Button", nil, self.scroll.child)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_HEIGHT)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)

    row.iconBorder = row:CreateTexture(nil, "ARTWORK", nil, 0)
    row.iconBorder:SetSize(28, 28)
    row.iconBorder:SetPoint("LEFT", 6, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK", nil, 1)
    row.icon:SetSize(26, 26)
    row.icon:SetPoint("CENTER", row.iconBorder)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.slot = S:Text(row, 10, C.muted)
    row.slot:SetPoint("TOPLEFT", 42, -4)
    row.name = S:Text(row, 12, C.text)
    row.name:SetPoint("BOTTOMLEFT", 42, 5)
    row.name:SetWidth(WIDTH - 2 * PAD - 120)
    row.status = S:Text(row, 10, C.muted, "RIGHT")
    row.status:SetPoint("RIGHT", -10, 0)

    row:SetScript("OnEnter", function(self)
        local p = self.piece
        if not p then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if p.link then GameTooltip:SetHyperlink(p.link) else GameTooltip:SetItemByID(p.itemID) end
        if p.illusionName then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Illusion: "] .. p.illusionName, C.accent[1], C.accent[2], C.accent[3])
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnClick", function(self)
        if self.piece and IsModifiedClick("CHATLINK") then InsertLink(self.piece.link) end
    end)

    self.rows[i] = row
    return row
end

function Explore:Refresh()
    if not self.frame or not self.frame:IsShown() or not self.outfit then return end
    local pieces = self:GetPieces(self.outfit)
    local pending = false

    for i, p in ipairs(pieces) do
        local row = self:GetRow(i)
        row.piece = p
        row:Show()
        row.icon:SetTexture(p.icon or 134400) -- question mark icon
        local color = p.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[p.quality]
        local r, g, b = 1, 1, 1
        if color then r, g, b = color.r, color.g, color.b end
        row.iconBorder:SetColorTexture(r, g, b, 0.8)
        row.slot:SetText(p.label:upper() .. (p.illusionName and ("  +  " .. p.illusionName:upper()) or ""))
        row.name:SetText(p.name or L["Loading..."])
        row.name:SetTextColor(r, g, b)
        row.status:SetText(p.collected and S:Color(C.success, L["Collected"]) or L["Not collected"])
        if p.pending then
            pending = true
            if Item and Item.CreateFromItemID then
                Item:CreateFromItemID(p.itemID):ContinueOnItemLoad(function() self:QueueRefresh() end)
            end
        end
    end
    for i = #pieces + 1, #self.rows do self.rows[i]:Hide() end
    self.scroll.child:SetHeight(math.max(1, #pieces * ROW_HEIGHT))
    self.scroll:UpdateThumb()

    if #pieces == 0 then
        self.context:SetText(L["No pieces could be read for this outfit."])
    end
    self.tryOn:SetEnabled(DressUpItemTransmogInfoList ~= nil and #pieces > 0)
    return pending
end

-- Several items can finish loading at once; refresh once for all of them.
function Explore:QueueRefresh()
    if self.refreshQueued then return end
    self.refreshQueued = true
    C_Timer.After(0.1, function()
        self.refreshQueued = false
        self:Refresh()
    end)
end

function Explore:TryOn()
    if not self.outfit or not DressUpItemTransmogInfoList or not ItemUtil then return end
    local list = {}
    for slot = 1, 19 do
        local s = self.outfit.slots[slot]
        list[slot] = ItemUtil.CreateItemTransmogInfo(s and s[1] or 0, s and s[2] or 0, s and s[3] or 0)
    end
    pcall(DressUpItemTransmogInfoList, list)
end

-- Opens the panel for an outfit. title is the (coloured) player name,
-- anchor (optional) is the frame to sit next to.
function Explore:Open(title, outfit, context, anchor)
    if not outfit then
        TC.Print(L["This outfit wasn't captured, so there is nothing to explore."])
        return
    end
    self:Build()
    self.outfit = outfit
    self.who:SetText(title)
    self.context:SetText(context or "")
    self.frame:ClearAllPoints()
    if anchor then
        self.frame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
    else
        self.frame:SetPoint("CENTER")
    end
    self.frame:Show()
    self.scroll:SetVerticalScroll(0)
    self:Refresh()
end
