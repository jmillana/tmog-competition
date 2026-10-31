-- TmogCompetition: shared flat/dark widget style used by every window.
local ADDON, ns = ...

local S = {}
ns.Style = S

local WHITE = "Interface\\Buttons\\WHITE8X8"
local FONT = STANDARD_TEXT_FONT
S.WHITE = WHITE

local C = {
    bg       = { 0.055, 0.055, 0.075, 0.97 },
    header   = { 0.085, 0.085, 0.115, 1 },
    panel    = { 0.115, 0.115, 0.150, 1 },
    panelHi  = { 0.165, 0.160, 0.210, 1 },
    border   = { 1, 1, 1, 0.07 },
    shadow   = { 0, 0, 0, 0.9 },
    accent   = { 0.76, 0.44, 1.00, 1 },
    accentHi = { 0.85, 0.58, 1.00, 1 },
    text     = { 0.94, 0.94, 0.96, 1 },
    muted    = { 0.56, 0.56, 0.64, 1 },
    success  = { 0.36, 0.84, 0.52, 1 },
    warning  = { 1.00, 0.74, 0.30, 1 },
    danger   = { 0.95, 0.38, 0.42, 1 },
    gold     = { 1.00, 0.82, 0.25, 1 },
    silver   = { 0.78, 0.80, 0.86, 1 },
    bronze   = { 0.82, 0.54, 0.32, 1 },
}
S.C = C

------------------------------------------------------------------------
-- Localization helpers
------------------------------------------------------------------------
local function T(key)
    return (ns.L and key and key ~= "") and ns.L[key] or key
end
S.T = T

-- string.upper only handles ASCII; also uppercase the Spanish accented letters.
local ACCENTS = { ["á"] = "Á", ["é"] = "É", ["í"] = "Í", ["ó"] = "Ó", ["ú"] = "Ú", ["ñ"] = "Ñ", ["ü"] = "Ü" }
function S:Upper(text)
    text = text:upper()
    for lower, upper in pairs(ACCENTS) do text = text:gsub(lower, upper) end
    return text
end

-- Text set once at build time. It is registered so a language change can re-translate it.
local statics = {}
function S:Static(widget, key, upper)
    statics[#statics + 1] = { widget = widget, key = key, upper = upper }
    local text = T(key)
    widget:SetText(upper and self:Upper(text) or text)
end

function S:Relocalize()
    for _, s in ipairs(statics) do
        local text = T(s.key)
        s.widget:SetText(s.upper and self:Upper(text) or text)
    end
end

local function Alpha(c, a) return { c[1], c[2], c[3], a } end
S.Alpha = Alpha

function S:Hex(c)
    return ("%02x%02x%02x"):format(math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

function S:Color(c, text)
    return "|cff" .. self:Hex(c) .. text .. "|r"
end

function S:RankColor(rank)
    return rank == 1 and C.gold or rank == 2 and C.silver or rank == 3 and C.bronze or C.muted
end

------------------------------------------------------------------------
-- Text
------------------------------------------------------------------------
local fonts = {}
function S:Font(size, flags)
    local key = size .. (flags or "")
    if not fonts[key] then
        local font = CreateFont("TmogCompetitionFont" .. key)
        font:SetFont(FONT, size, flags or "")
        font:SetShadowOffset(1, -1)
        font:SetShadowColor(0, 0, 0, 0.6)
        fonts[key] = font
    end
    return fonts[key]
end

function S:Text(parent, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(self:Font(size))
    fs:SetTextColor(unpack(color or C.text))
    fs:SetJustifyH(justify or "LEFT")
    fs:SetJustifyV("MIDDLE")
    fs:SetWordWrap(false)
    return fs
end

------------------------------------------------------------------------
-- Panels
------------------------------------------------------------------------
local BACKDROP = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }

function S:ApplyBackdrop(frame, bg, border)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(unpack(bg or C.panel))
    frame:SetBackdropBorderColor(unpack(border or C.border))
end

function S:Panel(parent, bg, border)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    self:ApplyBackdrop(f, bg, border)
    return f
end

-- Dark backdrop with a faint violet glow at the top, used behind character models.
function S:ModelBackground(parent)
    local tex = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
    tex:SetColorTexture(1, 1, 1, 1)
    tex:SetGradient("VERTICAL", CreateColor(0.04, 0.04, 0.06, 1), CreateColor(0.17, 0.12, 0.24, 1))
    return tex
end

function S:Divider(parent)
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetColorTexture(unpack(C.border))
    return tex
end

-- Small uppercase section label.
function S:Label(parent, text, color)
    local fs = self:Text(parent, 10, color or C.muted)
    self:Static(fs, text, true)
    return fs
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local function CloseButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(24, 24)
    b.lines = {}
    for i, pts in ipairs({ { "TOPLEFT", 7, -7, "BOTTOMRIGHT", -7, 7 }, { "TOPRIGHT", -7, -7, "BOTTOMLEFT", 7, 7 } }) do
        local line = b:CreateLine(nil, "OVERLAY")
        line:SetThickness(1.5)
        line:SetColorTexture(unpack(C.muted))
        line:SetStartPoint(pts[1], b, pts[2], pts[3])
        line:SetEndPoint(pts[4], b, pts[5], pts[6])
        b.lines[i] = line
    end
    local function color(c) for _, l in ipairs(b.lines) do l:SetColorTexture(unpack(c)) end end
    b:SetScript("OnEnter", function() color(C.danger) end)
    b:SetScript("OnLeave", function() color(C.muted) end)
    b:SetScript("OnClick", onClick)
    return b
end

-- Movable window with a header bar, accent underline and close button.
function S:Window(name, width, height, title, onMoved)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    self:ApplyBackdrop(f, C.bg, C.shadow)
    f:SetSize(width, height)
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:Hide()
    tinsert(UISpecialFrames, name)

    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(34)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        if onMoved then onMoved(f) end
    end)
    local hbg = header:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints()
    hbg:SetColorTexture(unpack(C.header))

    local underline = header:CreateTexture(nil, "ARTWORK")
    underline:SetPoint("BOTTOMLEFT")
    underline:SetPoint("BOTTOMRIGHT")
    underline:SetHeight(2)
    underline:SetColorTexture(1, 1, 1, 1)
    underline:SetGradient("HORIZONTAL", CreateColor(C.accent[1], C.accent[2], C.accent[3], 0.9),
        CreateColor(C.accent[1], C.accent[2], C.accent[3], 0))

    local diamond = header:CreateTexture(nil, "ARTWORK")
    diamond:SetSize(8, 8)
    diamond:SetPoint("LEFT", 14, 0)
    diamond:SetColorTexture(unpack(C.accent))
    diamond:SetRotation(math.pi / 4)

    local titleText = self:Text(header, 14, C.text)
    titleText:SetPoint("LEFT", diamond, "RIGHT", 10, 0)
    self:Static(titleText, title)
    f.TitleText = titleText

    local close = CloseButton(header, function() f:Hide() end)
    close:SetPoint("RIGHT", -6, 0)

    f.header = header
    f.closeButton = close
    return f
end

-- Gear icon button for a window header (sits left of the close button).
local GEAR_ATLASES = { "questlog-icon-setting", "GM-icon-settings" }
function S:GearButton(window, onClick, tooltip)
    local b = CreateFrame("Button", nil, window.header)
    b:SetSize(24, 24)
    b:SetPoint("RIGHT", window.closeButton, "LEFT", -2, 0)
    local icon = b:CreateTexture(nil, "OVERLAY")
    icon:SetSize(16, 16)
    icon:SetPoint("CENTER")
    local atlasSet = false
    for _, atlas in ipairs(GEAR_ATLASES) do
        if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
            icon:SetAtlas(atlas)
            atlasSet = true
            break
        end
    end
    if not atlasSet then icon:SetTexture("Interface\\Buttons\\UI-OptionsButton") end
    icon:SetDesaturated(true)
    icon:SetVertexColor(unpack(C.muted))
    b:SetScript("OnEnter", function(self)
        icon:SetVertexColor(unpack(C.accentHi))
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(T(tooltip), 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function()
        icon:SetVertexColor(unpack(C.muted))
        GameTooltip_Hide()
    end)
    b:SetScript("OnMouseDown", function() icon:SetPoint("CENTER", 0, -1) end)
    b:SetScript("OnMouseUp", function() icon:SetPoint("CENTER", 0, 0) end)
    b:SetScript("OnClick", onClick)
    return b
end

-- Checkbox with a label. getter() returns the state, setter(value) stores it.
function S:Checkbox(parent, label, tooltip, getter, setter)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(22)
    local box = self:Panel(b, C.bg, C.border)
    box:SetSize(16, 16)
    box:SetPoint("LEFT")
    box:EnableMouse(false)
    local fill = box:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 3, -3)
    fill:SetPoint("BOTTOMRIGHT", -3, 3)
    fill:SetColorTexture(unpack(C.accent))
    b.label = self:Text(b, 12, C.text)
    b.label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    self:Static(b.label, label)

    function b:Update()
        local on = getter()
        fill:SetShown(on)
        box:SetBackdropBorderColor(unpack(on and C.accent or C.border))
    end
    b:SetScript("OnClick", function(self)
        setter(not getter())
        self:Update()
    end)
    b:SetScript("OnEnter", function(self)
        self.label:SetTextColor(unpack(C.accentHi))
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
            GameTooltip:SetText(T(tooltip), 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self.label:SetTextColor(unpack(C.text))
        GameTooltip_Hide()
    end)
    b:Update()
    return b
end

------------------------------------------------------------------------
-- Buttons
------------------------------------------------------------------------
local VARIANTS = {
    primary   = { bg = C.accent, hover = C.accentHi, text = { 1, 1, 1, 1 }, border = Alpha(C.accentHi, 0.6) },
    secondary = { bg = C.panel, hover = C.panelHi, text = C.text, border = C.border },
    danger    = { bg = Alpha(C.danger, 0.10), hover = Alpha(C.danger, 0.24), text = C.danger, border = Alpha(C.danger, 0.45) },
    ghost     = { bg = { 0, 0, 0, 0 }, hover = C.panel, text = C.muted, border = C.border },
}

local function UpdateButton(b)
    local v = b.variant
    if b.selected then
        b:SetBackdropColor(unpack(C.accent))
        b:SetBackdropBorderColor(unpack(C.accentHi))
        b.label:SetTextColor(1, 1, 1, 1)
    else
        b:SetBackdropColor(unpack((b.hover and b:IsEnabled()) and v.hover or v.bg))
        b:SetBackdropBorderColor(unpack(v.border))
        b.label:SetTextColor(unpack(v.text))
    end
    b:SetAlpha(b:IsEnabled() and 1 or 0.35)
end

function S:Button(parent, text, width, height, variant, onClick, tooltip)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, height or 24)
    b.variant = VARIANTS[variant or "secondary"]
    b:SetBackdrop(BACKDROP)
    b.label = self:Text(b, 12, b.variant.text, "CENTER")
    b.label:SetPoint("CENTER")
    S:Static(b.label, text)

    function b:SetText(t) self.label:SetText(t) end
    function b:SetSelected(selected)
        self.selected = selected and true or false
        UpdateButton(self)
    end

    b:SetMotionScriptsWhileDisabled(true)
    b:SetScript("OnEnter", function(self)
        self.hover = true
        UpdateButton(self)
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(T(tooltip), 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self.hover = false
        UpdateButton(self)
        GameTooltip_Hide()
    end)
    b:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self.label:SetPoint("CENTER", 0, -1) end end)
    b:SetScript("OnMouseUp", function(self) self.label:SetPoint("CENTER", 0, 0) end)
    b:SetScript("OnEnable", UpdateButton)
    b:SetScript("OnDisable", UpdateButton)
    b:SetScript("OnClick", onClick)
    UpdateButton(b)
    return b
end

------------------------------------------------------------------------
-- Misc widgets
------------------------------------------------------------------------
function S:ProgressBar(parent, height)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(height or 6)
    bar:SetStatusBarTexture(WHITE)
    bar:SetStatusBarColor(unpack(C.accent))
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.07)
    return bar
end

-- Pill-shaped status label: badge:Set("VOTING", S.C.success)
function S:Badge(parent)
    local f = self:Panel(parent)
    f:SetHeight(18)
    f.text = self:Text(f, 10, C.text, "CENTER")
    f.text:SetPoint("CENTER")
    function f:Set(text, color)
        self.text:SetText(text)
        self.text:SetTextColor(unpack(color))
        self:SetBackdropColor(color[1], color[2], color[3], 0.14)
        self:SetBackdropBorderColor(color[1], color[2], color[3], 0.5)
        self:SetWidth(math.ceil(self.text:GetStringWidth()) + 16)
    end
    return f
end

-- Row of tabs with an accent underline on the selected one, and < > arrows when they overflow.
-- strip:SetItems({ { key = k, text = "Label" }, ... }, selectedKey)
-- onSelect(key) on left click, onRightClick(key, tabButton) on right click.
function S:TabStrip(parent, width, height, size, onSelect, onRightClick)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetSize(width, height)
    strip.tabs = {}
    strip.items = {}
    strip.offset = 1

    local base = self:Divider(strip)
    base:SetPoint("BOTTOMLEFT")
    base:SetPoint("BOTTOMRIGHT")
    base:SetHeight(1)

    strip.next = self:Button(strip, ">", 22, height - 6, "ghost", function()
        strip.offset = strip.offset + 1
        strip:Layout()
    end)
    strip.next:SetPoint("RIGHT", 0, 2)
    strip.prev = self:Button(strip, "<", 22, height - 6, "ghost", function()
        strip.offset = math.max(1, strip.offset - 1)
        strip:Layout()
    end)
    strip.prev:SetPoint("RIGHT", strip.next, "LEFT", -2, 0)

    local function GetTab(i)
        local tab = strip.tabs[i]
        if not tab then
            tab = CreateFrame("Button", nil, strip)
            tab:SetHeight(height)
            tab:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            tab.label = S:Text(tab, size, C.muted, "CENTER")
            tab.label:SetPoint("CENTER", 0, 1)
            tab.line = tab:CreateTexture(nil, "ARTWORK")
            tab.line:SetPoint("BOTTOMLEFT", 4, 0)
            tab.line:SetPoint("BOTTOMRIGHT", -4, 0)
            tab.line:SetHeight(2)
            tab.line:SetColorTexture(unpack(C.accent))
            local hl = tab:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.04)
            tab:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    if onRightClick then onRightClick(self.key, self) end
                elseif onSelect then
                    onSelect(self.key)
                end
            end)
            strip.tabs[i] = tab
        end
        return tab
    end

    local function Measure(i)
        local tab = GetTab(i)
        tab.label:SetText(strip.items[i].text)
        return math.ceil(tab.label:GetStringWidth()) + 24
    end

    function strip:Layout(ensureSelected)
        local items = self.items
        local widths, total = {}, 0
        for i = 1, #items do
            widths[i] = Measure(i)
            total = total + widths[i]
        end
        local overflow = total > width
        local avail = overflow and (width - 52) or width

        local function lastFitting(from)
            local x, last = 0, from - 1
            for i = from, #items do
                if x + widths[i] > avail and i > from then break end
                x = x + widths[i]
                last = i
            end
            return last
        end

        self.offset = math.max(1, math.min(self.offset, math.max(1, #items)))
        if ensureSelected and self.selectedIndex then
            if self.selectedIndex < self.offset then self.offset = self.selectedIndex end
            while lastFitting(self.offset) < self.selectedIndex and self.offset < self.selectedIndex do
                self.offset = self.offset + 1
            end
        end

        local last = lastFitting(self.offset)
        local x = 0
        for i = 1, math.max(#items, #self.tabs) do
            local tab = GetTab(i)
            if i >= self.offset and i <= last then
                tab.key = items[i].key
                tab:SetWidth(widths[i])
                tab:ClearAllPoints()
                tab:SetPoint("BOTTOMLEFT", x, 0)
                local selected = items[i].key == self.selected
                tab.line:SetShown(selected)
                tab.label:SetTextColor(unpack(selected and C.text or C.muted))
                tab:Show()
                x = x + widths[i]
            else
                tab:Hide()
            end
        end
        self.prev:SetShown(overflow)
        self.next:SetShown(overflow)
        self.prev:SetEnabled(self.offset > 1)
        self.next:SetEnabled(last < #items)
    end

    function strip:SetItems(items, selected)
        self.items = items
        self.selected = selected
        self.selectedIndex = nil
        for i, item in ipairs(items) do
            if item.key == selected then self.selectedIndex = i end
        end
        self:Layout(true)
    end

    return strip
end

-- Right-click menu using the modern Menu API. build(rootDescription) adds the entries.
-- Returns false when the API is missing so callers can fall back.
function S:ContextMenu(owner, build)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return false end
    MenuUtil.CreateContextMenu(owner, function(_, root) build(root) end)
    return true
end

-- Single-line text input with a placeholder. onEnter(editBox) runs when Enter is pressed.
function S:Input(parent, width, height, placeholder, maxLetters, onEnter)
    local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    self:ApplyBackdrop(e, C.bg, C.border)
    e:SetSize(width, height or 26)
    e:SetFontObject(self:Font(12))
    e:SetTextColor(unpack(C.text))
    e:SetTextInsets(8, 8, 0, 0)
    e:SetAutoFocus(false)
    e:SetMaxLetters(maxLetters or 0)

    e.placeholder = self:Text(e, 12, C.muted)
    e.placeholder:SetPoint("LEFT", 8, 0)
    self:Static(e.placeholder, placeholder or "")

    local function update()
        e.placeholder:SetShown(e:GetText() == "" and not e:HasFocus())
    end
    e:SetScript("OnTextChanged", update)
    e:SetScript("OnEditFocusGained", function()
        e:SetBackdropBorderColor(unpack(C.accent))
        update()
    end)
    e:SetScript("OnEditFocusLost", function()
        e:SetBackdropBorderColor(unpack(C.border))
        update()
    end)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnEnterPressed", function() if onEnter then onEnter(e) end end)
    return e
end

-- Mouse-wheel scroll area with a slim accent thumb. Put content in scroll.child.
function S:ScrollArea(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    scroll.child = child

    local thumb = scroll:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(3)
    thumb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)

    local function update()
        local range = scroll:GetVerticalScrollRange()
        if range <= 0 then thumb:Hide() return end
        local h = scroll:GetHeight()
        local th = math.max(16, h * h / (h + range))
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, -(h - th) * (scroll:GetVerticalScroll() / range))
        thumb:Show()
    end
    scroll.UpdateThumb = update

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local value = self:GetVerticalScroll() - delta * 40
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), value)))
        update()
    end)
    scroll:SetScript("OnScrollRangeChanged", function(self)
        local range = self:GetVerticalScrollRange()
        if self:GetVerticalScroll() > range then self:SetVerticalScroll(range) end
        update()
    end)
    scroll:SetScript("OnSizeChanged", function(self, width)
        child:SetWidth(width)
        update()
    end)
    return scroll
end
