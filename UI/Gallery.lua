-- TmogCompetition: gallery of saved transmogs.
-- Top tabs: Bookmarks + one per competition. Sub-tabs: one per theme picked in that competition.
-- Everything here is local to this client (see Modules/History.lua).
local ADDON, ns = ...
local TC, S, Outfit = ns.TC, ns.Style, ns.Outfit
local L = ns.L
local C = S.C

local Gallery = {}
ns.Gallery = Gallery

local COLS, ROWS = 4, 2
local PER_PAGE = COLS * ROWS
local CELL_W, CELL_H = 170, 250
local MODEL_H = 192
local GAP = 10
local PAD = 16
local TOP = 150
local WIDTH = PAD * 2 + COLS * CELL_W + (COLS - 1) * GAP
local HEIGHT = TOP + ROWS * CELL_H + (ROWS - 1) * GAP + 52
local BOOKMARKS = "bookmarks"
local CLEAR_W = 116 -- clear buttons right of the top tabs; the tab strip leaves room for them
local STAR = "Interface\\Common\\FavoritesIcon"

-- Gold star for a favourite; the same star greyed out when it is not one.
local function SetStar(tex, on)
    tex:SetTexture(STAR)
    tex:SetDesaturated(not on)
    tex:SetVertexColor(1, 1, 1)
end

-- "No theme" is stored as an internal key; show it translated.
local function ThemeName(name)
    return name == "No theme" and L.THEME_NONE or name
end

local function EntryName(entry)
    local color = entry.class and RAID_CLASS_COLORS[entry.class]
    if color then return color:WrapTextInColorCode(TC:Short(entry.name)) end
    return ns.UI:ColoredName(entry.name)
end

------------------------------------------------------------------------
-- Rename popup
------------------------------------------------------------------------
local function PopupEditBox(dialog)
    return (dialog.GetEditBox and dialog:GetEditBox()) or dialog.editBox or dialog.EditBox
end

StaticPopupDialogs["TMOGCOMPETITION_RENAME"] = {
    text = "GALLERY_RENAME_TITLE",
    button1 = ACCEPT or "POPUP_ACCEPT",
    button2 = CANCEL or "POPUP_CANCEL",
    hasEditBox = 1,
    maxLetters = 40,
    OnShow = function(dialog, comp)
        local edit = PopupEditBox(dialog)
        if edit and comp then
            edit:SetText(comp.title or "")
            edit:HighlightText()
            edit:SetFocus()
        end
    end,
    OnAccept = function(dialog, comp)
        local edit = PopupEditBox(dialog)
        if edit and comp then ns.History:Rename(comp, edit:GetText()) end
    end,
    EditBoxOnEnterPressed = function(edit, comp)
        if comp then ns.History:Rename(comp, edit:GetText()) end
        StaticPopup_Hide("TMOGCOMPETITION_RENAME")
    end,
    EditBoxOnEscapePressed = function() StaticPopup_Hide("TMOGCOMPETITION_RENAME") end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------
function Gallery:CreateCell(i)
    local col = (i - 1) % COLS
    local row = math.floor((i - 1) / COLS)
    local cell = S:Panel(self.frame)
    cell:SetSize(CELL_W, CELL_H)
    cell:SetPoint("TOPLEFT", PAD + col * (CELL_W + GAP), -TOP - row * (CELL_H + GAP))
    cell:EnableMouse(true)
    cell:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then self:OpenCellMenu(cell) end
    end)

    local modelBg = S:ModelBackground(cell)
    modelBg:SetPoint("TOPLEFT", 1, -1)
    modelBg:SetSize(CELL_W - 2, MODEL_H)

    local m = CreateFrame("DressUpModel", nil, cell)
    m:SetPoint("TOPLEFT", 1, -1)
    m:SetSize(CELL_W - 2, MODEL_H)
    Outfit:SetupModel(m)
    m.onRightClick = function() self:OpenCellMenu(cell) end
    cell.model = m

    -- Everything drawn on top of the model lives on this overlay frame.
    local overlay = CreateFrame("Frame", nil, cell)
    overlay:SetAllPoints(m)
    overlay:SetFrameLevel(m:GetFrameLevel() + 2)

    cell.msg = S:Text(overlay, 11, C.muted, "CENTER")
    cell.msg:SetPoint("LEFT", 8, 0)
    cell.msg:SetPoint("RIGHT", -8, 0)
    cell.msg:SetWordWrap(true)

    cell.badge = S:Badge(overlay)
    cell.badge:SetPoint("TOPLEFT", 8, -8)

    -- Favourite toggle: empty star, filled once the look is in Bookmarks.
    local star = CreateFrame("Button", nil, overlay)
    star:SetSize(24, 24)
    star:SetPoint("TOPRIGHT", -6, -6)
    star:SetHitRectInsets(-4, -4, -4, -4) -- easier to click than the small icon
    star.icon = star:CreateTexture(nil, "OVERLAY")
    star.icon:SetAllPoints()
    star:SetScript("OnClick", function() self:ToggleBookmark(cell.item) end)
    star:SetScript("OnEnter", function()
        star:SetAlpha(1)
        GameTooltip:SetOwner(star, "ANCHOR_TOP")
        GameTooltip:SetText(star.on and L.GALLERY_REMOVE_BOOKMARK or L.GALLERY_BOOKMARK, 1, 1, 1)
        GameTooltip:Show()
    end)
    star:SetScript("OnLeave", function()
        star:SetAlpha(star.on and 1 or 0.45)
        GameTooltip_Hide()
    end)
    function star:Set(on)
        self.on = on and true or false
        SetStar(self.icon, self.on)
        self:SetAlpha((self.on or self:IsMouseOver()) and 1 or 0.45)
    end
    cell.star = star

    cell.note = S:Text(overlay, 10, C.muted)
    cell.note:SetPoint("BOTTOMLEFT", 8, 10)
    cell.note:SetWidth(CELL_W - 84)

    cell.explore = S:Button(overlay, "GALLERY_EXPLORE", 64, 20, "secondary", function() self:ExploreCell(cell) end,
        "GALLERY_EXPLORE_TIP")
    cell.explore:SetPoint("BOTTOMRIGHT", -6, 6)

    local divider = S:Divider(cell)
    divider:SetPoint("TOPLEFT", 1, -MODEL_H - 1)
    divider:SetSize(CELL_W - 2, 1)

    cell.name = S:Text(cell, 13, C.text, "CENTER")
    cell.name:SetPoint("TOP", m, "BOTTOM", 0, -9)
    cell.name:SetWidth(CELL_W - 12)
    cell.score = S:Text(cell, 12, C.text, "CENTER")
    cell.score:SetPoint("TOP", cell.name, "BOTTOM", 0, -5)
    cell.score:SetWidth(CELL_W - 12)
    cell.sub = S:Text(cell, 10, C.muted, "CENTER")
    cell.sub:SetPoint("TOP", cell.score, "BOTTOM", 0, -4)
    cell.sub:SetWidth(CELL_W - 12)
    return cell
end

function Gallery:Build()
    if self.frame then return end
    local f = S:Window("TmogCompetitionGallery", WIDTH, HEIGHT, "GALLERY_TITLE")
    self.frame = f
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")

    self.topTabs = S:TabStrip(f, WIDTH - 2 * PAD - CLEAR_W - 10, 30, 13, function(key)
        self.sel, self.themeIdx, self.page = key, nil, 1
        self:Refresh()
    end, function(key, tab)
        self:OpenCompetitionMenu(key, tab)
    end)
    self.topTabs:SetPoint("TOPLEFT", PAD, -40)
    -- Trash icon on every competition tab (not on Bookmarks, which has its own clear button).
    self.topTabs:SetDeleteHandler(function(key) return key ~= BOOKMARKS end, function(key)
        local comp = ns.History:Find(key)
        if comp then self:ConfirmRemoveCompetition(comp) end
    end, "GALLERY_DELETE_COMPETITION_TIP")

    -- Competition tabs: clear every competition (bookmarks are kept).
    self.clearAll = S:Button(f, "GALLERY_CLEAR_ALL", CLEAR_W, 24, "danger", function()
        TC:Confirm(L.GALLERY_CONFIRM_CLEAR_ALL,
            function()
                ns.History:Clear()
                self.sel, self.themeIdx = nil, nil
                self:Refresh()
            end)
    end, "GALLERY_CLEAR_ALL_TIP")
    self.clearAll:SetPoint("TOPRIGHT", -PAD, -44)

    -- Bookmarks tab: its own button that only clears bookmarks.
    self.clearBookmarks = S:Button(f, "GALLERY_CLEAR_BOOKMARKS", CLEAR_W, 24, "danger", function()
        TC:Confirm(L.GALLERY_CONFIRM_CLEAR_BOOKMARKS, function()
            ns.History:ClearBookmarks()
            self:Refresh()
        end)
    end, "GALLERY_CLEAR_BOOKMARKS_TIP")
    self.clearBookmarks:SetPoint("TOPRIGHT", -PAD, -44)
    self.clearBookmarks:Hide()

    self.subTabs = S:TabStrip(f, WIDTH - 2 * PAD, 26, 11, function(key)
        self.themeIdx, self.page = key, 1
        self:Refresh()
    end)
    self.subTabs:SetPoint("TOPLEFT", PAD, -74)
    -- Trash icon on every theme tab.
    self.subTabs:SetDeleteHandler(function() return true end, function(index)
        local comp = ns.History:Find(self.sel)
        local theme = comp and comp.themes[index]
        if theme then self:ConfirmRemoveTheme(comp, theme) end
    end, "GALLERY_DELETE_THEME_TIP")

    self.heading = S:Text(f, 16, C.text, "CENTER")
    self.heading:SetPoint("TOP", 0, -110)
    self.heading:SetWidth(WIDTH - 2 * PAD)
    self.subtitle = S:Text(f, 11, C.muted, "CENTER")
    self.subtitle:SetPoint("TOP", 0, -130)
    self.subtitle:SetWidth(WIDTH - 2 * PAD)

    self.cells = {}
    for i = 1, PER_PAGE do self.cells[i] = self:CreateCell(i) end

    self.page = 1
    self.prev = S:Button(f, "GALLERY_PREV", 90, 26, "secondary", function()
        self.page = self.page - 1
        self:Refresh()
    end)
    self.prev:SetPoint("BOTTOMLEFT", PAD, 14)
    self.next = S:Button(f, "GALLERY_NEXT", 90, 26, "secondary", function()
        self.page = self.page + 1
        self:Refresh()
    end)
    self.next:SetPoint("BOTTOMRIGHT", -PAD, 14)
    self.pageText = S:Text(f, 11, C.muted, "CENTER")
    self.pageText:SetPoint("BOTTOM", 0, 21)

    f:SetScript("OnShow", function()
        for _, cell in ipairs(self.cells) do cell.key = nil end
        self:Refresh()
        self.ticker = C_Timer.NewTicker(2, function() self:Refresh() end)
    end)
    f:SetScript("OnHide", function()
        if self.ticker then self.ticker:Cancel() end
        self.ticker = nil
    end)
end

------------------------------------------------------------------------
-- Menus and actions
------------------------------------------------------------------------
function Gallery:ConfirmRemoveCompetition(comp)
    TC:Confirm(L:Format("GALLERY_CONFIRM_REMOVE_COMPETITION", { competition = comp.title }),
        function()
            ns.History:RemoveCompetition(comp.id)
            self.sel, self.themeIdx = nil, nil
            self:Refresh()
        end)
end

function Gallery:ConfirmRemoveTheme(comp, theme)
    TC:Confirm(L:Format("GALLERY_CONFIRM_REMOVE_THEME", { theme = ThemeName(theme.name), competition = comp.title }),
        function()
            ns.History:RemoveTheme(comp, theme)
            self.themeIdx = nil
            self:Refresh()
        end)
end

function Gallery:OpenCompetitionMenu(key, tab)
    local comp = key ~= BOOKMARKS and ns.History:Find(key)
    if not comp then return end
    local function rename()
        local popup = StaticPopupDialogs.TMOGCOMPETITION_RENAME
        popup.text, popup.button1, popup.button2 = L.GALLERY_RENAME_TITLE, L.POPUP_ACCEPT, L.POPUP_CANCEL
        StaticPopup_Show("TMOGCOMPETITION_RENAME", nil, nil, comp) end
    local function remove() self:ConfirmRemoveCompetition(comp) end
    if not S:ContextMenu(tab, function(root)
        root:CreateTitle(comp.title)
        root:CreateButton(L.GALLERY_RENAME, rename)
        root:CreateButton(L.GALLERY_REMOVE_COMPETITION, remove)
    end) then
        rename()
    end
end

-- Adds the look to Bookmarks, or removes it if it is already there.
function Gallery:ToggleBookmark(item)
    if not item then return end
    local History, entry = ns.History, item.entry
    if item.bookmark then
        -- On the Bookmarks tab the look disappears for good, so ask first.
        TC:Confirm(L:Format("GALLERY_CONFIRM_REMOVE_BOOKMARK", {
            player = TC:Short(entry.name),
            theme = ThemeName(entry.theme or ""),
            competition = entry.competition or "",
        }), function()
            History:RemoveBookmark(entry.key)
        end)
        return
    end
    local key = History:Key(item.comp, item.theme, entry)
    if History:IsBookmarked(key) then
        History:RemoveBookmark(key)
    else
        History:AddBookmark(item.comp, item.theme, entry)
    end
end

function Gallery:OpenCellMenu(cell)
    local item = cell.item
    if not item then return end
    local History = ns.History
    local entry = item.entry
    local function toggleBookmark() self:ToggleBookmark(item) end

    local bookmarked = item.bookmark or History:IsBookmarked(History:Key(item.comp, item.theme, entry))
    if not S:ContextMenu(cell, function(root)
        root:CreateTitle(TC:Short(entry.name))
        root:CreateButton(bookmarked and L.GALLERY_REMOVE_BOOKMARK or L.GALLERY_BOOKMARK, toggleBookmark)
        if entry.outfit then root:CreateButton(L.GALLERY_EXPLORE, function() self:ExploreCell(cell) end) end
        if not item.bookmark then
            root:CreateButton(L.GALLERY_REMOVE_LOOK, function() History:RemoveEntry(item.theme, entry.name) end)
        end
    end) then
        toggleBookmark() -- no menu API: right-click just toggles the bookmark
    end
end

function Gallery:ExploreCell(cell)
    local item = cell.item
    if not item then return end
    local context = item.bookmark and (ThemeName(item.entry.theme) .. " - " .. item.entry.competition)
        or (ThemeName(item.theme.name) .. " - " .. item.comp.title)
    ns.Explore:Open(EntryName(item.entry), item.entry.outfit, context, self.frame)
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
function Gallery:DefaultSelection()
    local History = ns.History
    if History:ActiveId() and History:Find(History:ActiveId()) then return History:ActiveId() end
    local comps = History:Competitions()
    if #comps > 0 then return comps[#comps].id end
    return BOOKMARKS
end

function Gallery:DefaultTheme(comp)
    if comp.id == ns.History:ActiveId() and TC.db.currentTheme then
        for i, theme in ipairs(comp.themes) do
            if theme.name == TC.db.currentTheme then return i end
        end
    end
    return #comp.themes > 0 and #comp.themes or nil
end

function Gallery:RefreshTabs()
    local History = ns.History
    if self.sel ~= BOOKMARKS and not History:Find(self.sel) then self.sel = self:DefaultSelection() end

    local items = { { key = BOOKMARKS, text = L.GALLERY_BOOKMARKS .. " " .. S:Color(C.muted, #History:Bookmarks()) } }
    local comps = History:Competitions()
    for i = #comps, 1, -1 do
        local comp = comps[i]
        local live = comp.id == History:ActiveId() and S:Color(C.success, L.GALLERY_LIVE .. "  ") or ""
        items[#items + 1] = { key = comp.id, text = live .. comp.title }
    end
    self.topTabs:SetItems(items, self.sel)

    if self.sel == BOOKMARKS then
        self.subTabs:Hide()
        return nil
    end
    local comp = History:Find(self.sel)
    if not self.themeIdx or not comp.themes[self.themeIdx] then self.themeIdx = self:DefaultTheme(comp) end
    local subItems = {}
    for i, theme in ipairs(comp.themes) do
        local count = 0
        for _ in pairs(theme.entries) do count = count + 1 end
        subItems[i] = { key = i, text = ThemeName(theme.name) .. "  " .. S:Color(C.muted, count) }
    end
    self.subTabs:SetItems(subItems, self.themeIdx)
    self.subTabs:Show()
    return comp, self.themeIdx and comp.themes[self.themeIdx]
end

-- Builds the list of cells to show plus heading texts.
function Gallery:CollectItems()
    local History = ns.History
    local comp, theme = self:RefreshTabs()
    local items = {}

    if self.sel == BOOKMARKS then
        for _, bookmark in ipairs(History:Bookmarks()) do
            items[#items + 1] = { entry = bookmark, bookmark = true }
        end
        self.heading:SetText(S:Color(C.text, L.GALLERY_BOOKMARKS))
        self.subtitle:SetText(#items > 0 and L.GALLERY_BOOKMARKS_HINT
            or L.GALLERY_BOOKMARKS_EMPTY)
        return items
    end

    if not theme then
        self.heading:SetText(S:Color(C.text, comp.title))
        self.subtitle:SetText(L.GALLERY_NO_ROUNDS)
        return items
    end

    for _, entry in ipairs(History:Ranked(theme)) do
        items[#items + 1] = { entry = entry, comp = comp, theme = theme }
    end
    local winners = {}
    for _, item in ipairs(items) do
        if item.entry.rank == 1 then winners[#winners + 1] = EntryName(item.entry) end
    end
    if #winners > 0 then
        self.heading:SetText(("%s  %s  %s"):format(S:Color(C.gold, #winners > 1 and L.GALLERY_WINNERS or L.GALLERY_WINNER),
            table.concat(winners, ", "), S:Color(C.gold, ("%.2f"):format(items[1].entry.avg))))
    else
        self.heading:SetText(S:Color(C.text, ThemeName(theme.name)))
    end
    self.subtitle:SetText(L:Format("GALLERY_SUBTITLE", { competition = comp.title, theme = ThemeName(theme.name) }))
    return items
end

function Gallery:RefreshCell(cell, item)
    local entry = item.entry
    cell.item = item
    local unit = TC.group[entry.name]
    local visible = unit and UnitIsVisible(unit) and 1 or 0
    local key = ("%s|%d|%d"):format(tostring(entry), Outfit.version, visible)
    if cell.key ~= key then
        cell.key = key
        cell.model.facing = 0
        local note = Outfit:RenderOutfit(cell.model, entry.name, entry.outfit)
        cell.model:SetFacing(0)
        cell.msg:SetText(entry.outfit and "" or (note or ""))
        cell.note:SetText(entry.outfit and (note or "") or "")
    end

    cell.name:SetText(EntryName(entry))
    cell.explore:SetShown(entry.outfit ~= nil)

    if entry.avg then
        cell.score:SetText(S:Color(entry.rank == 1 and C.gold or C.text, ("%.2f"):format(entry.avg))
            .. S:Color(C.muted, "  " .. L:Format("GALLERY_VOTES", { count = entry.count or 0 })))
    else
        cell.score:SetText(S:Color(C.muted, L.GALLERY_NOT_SCORED))
    end

    local bookmarked
    if item.bookmark then
        bookmarked = true
        cell.sub:SetText(("%s - %s"):format(ThemeName(entry.theme or ""), entry.competition or ""))
    else
        bookmarked = ns.History:IsBookmarked(ns.History:Key(item.comp, item.theme, entry))
        cell.sub:SetText("")
    end
    cell.star:Set(bookmarked)

    if entry.rank then
        cell.badge:Show()
        cell.badge:Set("#" .. entry.rank, entry.rank <= 3 and S:RankColor(entry.rank) or C.text)
    else
        cell.badge:Hide()
    end
    if entry.rank == 1 and not item.bookmark then
        cell:SetBackdropBorderColor(C.gold[1], C.gold[2], C.gold[3], 0.7)
    else
        cell:SetBackdropBorderColor(unpack(C.border))
    end
end

function Gallery:Refresh()
    if not self.frame or not self.frame:IsShown() or not TC.db then return end
    local items = self:CollectItems()
    local pages = math.max(1, math.ceil(#items / PER_PAGE))
    self.page = math.max(1, math.min(self.page or 1, pages))

    for i, cell in ipairs(self.cells) do
        local item = items[(self.page - 1) * PER_PAGE + i]
        if item then
            cell:Show()
            self:RefreshCell(cell, item)
        else
            cell:Hide()
            cell.item, cell.key = nil, nil
        end
    end

    self.prev:SetEnabled(self.page > 1)
    self.next:SetEnabled(self.page < pages)
    self.pageText:SetText(L:Format("GALLERY_PAGE", { page = self.page, pages = pages }))

    -- Each page has its own clear button: competitions vs bookmarks.
    local onBookmarks = self.sel == BOOKMARKS
    self.clearAll:SetShown(not onBookmarks)
    self.clearAll:SetEnabled(#ns.History:Competitions() > 0)
    self.clearBookmarks:SetShown(onBookmarks)
    S:FitLabel(self.clearAll) -- shrink the text if a translation is too long
    S:FitLabel(self.clearBookmarks)
    self.clearBookmarks:SetEnabled(#ns.History:Bookmarks() > 0)
end

------------------------------------------------------------------------
-- Visibility
------------------------------------------------------------------------
-- Opens on the live competition and the current theme.
function Gallery:Show()
    self:Build()
    self.sel, self.themeIdx, self.page = nil, nil, 1
    self.frame:Show()
    self:Refresh()
end

function Gallery:Toggle()
    self:Build()
    if self.frame:IsShown() then self.frame:Hide() else self:Show() end
end
