-- TmogCompetition: main window.
local ADDON, ns = ...
local TC, S = ns.TC, ns.Style
local L = ns.L
local C = S.C

local UI = {}
ns.UI = UI

local WIDTH, HEIGHT = 400, 750
local PAD = 14
local INNER = WIDTH - 2 * PAD
local ROW_HEIGHT = 22
local MODEL_W, CARD_H = 140, 190

local PHASES = {
    IDLE = { "WAITING", C.muted },
    VOTING = { "VOTING OPEN", C.success },
    CLOSED = { "VOTING CLOSED", C.warning },
}

------------------------------------------------------------------------
-- Name helpers (also used by the gallery)
------------------------------------------------------------------------
function UI:ColoredName(name)
    local short = TC:Short(name)
    local unit = TC.group[name]
    if unit then
        local _, class = UnitClass(unit)
        local color = class and RAID_CLASS_COLORS[class]
        if color then return color:WrapTextInColorCode(short) end
    end
    return short
end

function UI:NameList(names)
    local list = {}
    for i, name in ipairs(names) do list[i] = self:ColoredName(name) end
    return table.concat(list, ", ")
end

------------------------------------------------------------------------
-- Build
------------------------------------------------------------------------
function UI:BuildStatus(f)
    self.phase = S:Badge(f)
    self.phase:SetPoint("TOPLEFT", PAD, -48)
    self.roundText = S:Text(f, 12, C.text)
    self.roundText:SetPoint("LEFT", self.phase, "RIGHT", 8, 0)
    self.leaderText = S:Text(f, 11, C.muted, "RIGHT")
    self.leaderText:SetPoint("RIGHT", f, "TOPRIGHT", -PAD, -57)
end

function UI:BuildContestantCard(f)
    local card = S:Panel(f)
    card:SetPoint("TOPLEFT", PAD, -76)
    card:SetSize(INNER, CARD_H)

    local modelBg = S:ModelBackground(card)
    modelBg:SetPoint("TOPLEFT", 1, -1)
    modelBg:SetSize(MODEL_W, CARD_H - 2)

    local m = CreateFrame("DressUpModel", nil, card)
    m:SetPoint("TOPLEFT", 1, -1)
    m:SetSize(MODEL_W, CARD_H - 2)
    ns.Outfit:SetupModel(m)
    m.msg = S:Text(m, 11, C.muted, "CENTER")
    m.msg:SetPoint("LEFT", 8, 0)
    m.msg:SetPoint("RIGHT", -8, 0)
    m.msg:SetWordWrap(true)
    self.model = m

    local divider = S:Divider(card)
    divider:SetPoint("TOPLEFT", MODEL_W + 1, -1)
    divider:SetSize(1, CARD_H - 2)

    local x = MODEL_W + 16
    local w = INNER - x - 12
    local label = S:Label(card, "Now showcasing", C.accent)
    label:SetPoint("TOPLEFT", x, -16)

    self.contestant = S:Text(card, 18, C.text)
    self.contestant:SetPoint("TOPLEFT", x, -32)
    self.contestant:SetWidth(w)

    self.progress = S:ProgressBar(card, 6)
    self.progress:SetPoint("TOPLEFT", x, -66)
    self.progress:SetWidth(w)

    self.votesText = S:Text(card, 12, C.text)
    self.votesText:SetPoint("TOPLEFT", x, -82)
    self.votesText:SetWidth(w)

    self.pendingText = S:Text(card, 11, C.muted)
    self.pendingText:SetPoint("TOPLEFT", x, -102)
    self.pendingText:SetSize(w, CARD_H - 112)
    self.pendingText:SetJustifyV("TOP")
    self.pendingText:SetWordWrap(true)
end

function UI:BuildVoting(f)
    local label = S:Label(f, "Your vote")
    label:SetPoint("TOPLEFT", PAD, -282)
    self.myVoteText = S:Text(f, 11, C.muted, "RIGHT")
    self.myVoteText:SetPoint("TOPRIGHT", -PAD, -280)

    local count = TC.MAX_SCORE - TC.MIN_SCORE + 1
    local gap = 4
    local bw = math.floor((INNER - (count - 1) * gap) / count)
    self.voteButtons = {}
    for score = TC.MIN_SCORE, TC.MAX_SCORE do
        local b = S:Button(f, tostring(score), bw, 32, "secondary", function() TC:Vote(score) end)
        b.label:SetFontObject(S:Font(14))
        b:SetPoint("TOPLEFT", PAD + (score - TC.MIN_SCORE) * (bw + gap), -298)
        self.voteButtons[score] = b
    end
end

function UI:BuildLeaderControls(f)
    self.leaderLabel = S:Label(f, "Leader controls")
    self.leaderLabel:SetPoint("TOPLEFT", PAD, -346)

    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", PAD, -362)
    bar:SetSize(INNER, 82)
    self.leaderBar = bar

    local w = math.floor((INNER - 8) / 3)
    local function place(button, col, row)
        button:SetPoint("TOPLEFT", col * (w + 4), -row * 30)
    end
    self.nextBtn = S:Button(bar, "Shuffle & Start", w, 26, "primary", function() TC:CmdNextRound() end,
        "Pick a random player who hasn't showcased yet and open voting.")
    place(self.nextBtn, 0, 0)
    self.closeBtn = S:Button(bar, "Close Voting", w, 26, "secondary", function() TC:CmdCloseVoting() end,
        "End the current round and reveal the score.")
    place(self.closeBtn, 1, 0)
    self.winnerBtn = S:Button(bar, "Announce Winner", w, 26, "secondary", function() TC:CmdAnnounceWinner() end,
        "Announce the highest average score to the group.")
    place(self.winnerBtn, 2, 0)
    self.poolBtn = S:Button(bar, "Reset Pool", w, 22, "ghost", function() TC:CmdResetPool() end,
        "Make everyone eligible for the shuffle again. Scores are kept.")
    place(self.poolBtn, 0, 1)
    self.resetBtn = S:Button(bar, "Reset All", w, 22, "danger", function() TC:CmdResetAll() end,
        "Clear all scores, outfits and the shuffle pool.")
    place(self.resetBtn, 1, 1)
    self.refreshBtn = S:Button(bar, "Refresh", w, 22, "ghost", function() TC:CmdRefresh() end,
        "Ask everyone in the group to report that they have the addon, and resend the competition state.")
    place(self.refreshBtn, 2, 1)
    self.finishBtn = S:Button(bar, "Finish Competition", INNER, 26, "secondary",
        function() TC:CmdFinishCompetition() end,
        "End the competition and announce the overall ranking (sum of each player's theme scores).")
    self.finishBtn:SetPoint("TOPLEFT", 0, -56)

    self.notLeader = S:Panel(f, S.Alpha(C.panel, 0.5))
    self.notLeader:SetPoint("TOPLEFT", PAD, -350)
    self.notLeader:SetSize(INNER, 40)
    local text = S:Text(self.notLeader, 11, C.muted, "CENTER")
    text:SetPoint("CENTER")
    S:Static(text, "Only the group leader can run the competition.")
end

function UI:BuildWinnerBanner(f)
    local banner = S:Panel(f, S.Alpha(C.gold, 0.10), S.Alpha(C.gold, 0.45))
    banner:SetPoint("TOPLEFT", PAD, -428)
    banner:SetSize(INNER, 30)
    banner.text = S:Text(banner, 13, C.gold, "CENTER")
    banner.text:SetPoint("LEFT", 10, 0)
    banner.text:SetPoint("RIGHT", -10, 0)
    self.winnerBanner = banner
end

function UI:LayoutRow(row, size, color)
    row.rank = S:Text(row, size, color, "CENTER")
    row.rank:SetPoint("LEFT", 2, 0)
    row.rank:SetWidth(24)
    row.name = S:Text(row, size, color)
    row.name:SetPoint("LEFT", 32, 0)
    row.name:SetWidth(180)
    row.votes = S:Text(row, size - 1, C.muted, "RIGHT")
    row.votes:SetPoint("RIGHT", -10, 0)
    row.votes:SetWidth(70)
    row.score = S:Text(row, size, color, "RIGHT")
    row.score:SetPoint("RIGHT", row.votes, "LEFT", -6, 0)
    row.score:SetWidth(50)
end

function UI:BuildRanking(f)
    local card = S:Panel(f)
    card:SetPoint("BOTTOMRIGHT", -PAD, 50)
    self.rankingCard = card

    -- One tab per category (theme) plus Overall.
    self.rankTabs = S:TabStrip(card, INNER - 12, 26, 11, function(key)
        self.rankTab = key
        self:Refresh()
    end)
    self.rankTabs:SetPoint("TOPLEFT", 6, -4)

    local header = CreateFrame("Frame", nil, card)
    header:SetPoint("TOPLEFT", 6, -34)
    header:SetPoint("TOPRIGHT", -6, -34)
    header:SetHeight(20)
    self:LayoutRow(header, 10, C.muted)
    header.rank:SetText("#")
    self.rankHeader = header -- column titles depend on the tab, set in RefreshRanking

    local divider = S:Divider(card)
    divider:SetPoint("TOPLEFT", 6, -56)
    divider:SetPoint("TOPRIGHT", -6, -56)
    divider:SetHeight(1)

    local scroll = S:ScrollArea(card)
    scroll:SetPoint("TOPLEFT", 6, -60)
    scroll:SetPoint("BOTTOMRIGHT", -6, 6)
    self.scroll = scroll
    self.rows = {}
end

function UI:BuildFooter(f)
    local galleryBtn = S:Button(f, "Gallery", 80, 26, "primary", function() ns.Gallery:Toggle() end,
        "Show every contestant's outfit with the current ranking.")
    galleryBtn:SetPoint("BOTTOMRIGHT", -PAD, 14)
    local themesBtn = S:Button(f, "Themes", 80, 26, "secondary", function() ns.Wheel:Toggle() end,
        "Open the theme draw.")
    themesBtn:SetPoint("RIGHT", galleryBtn, "LEFT", -6, 0)

    self.footer = S:Text(f, 11, C.muted)
    self.footer:SetPoint("BOTTOMLEFT", PAD, 12)
    self.footer:SetSize(INNER - 176, 30)

    self.themeText = S:Text(f.header, 12, C.muted, "RIGHT")
    self.themeText:SetPoint("RIGHT", f.header, "RIGHT", -62, 0)
    self.themeText:SetWidth(170)
    self.footer:SetJustifyV("BOTTOM")
    self.footer:SetWordWrap(true)
end

function UI:Build()
    if self.frame then return end
    local f = S:Window("TmogCompetitionFrame", WIDTH, HEIGHT, "Transmog Competition", function(frame)
        local point, _, relPoint, x, y = frame:GetPoint()
        TC.db.frame = { point, relPoint, x, y }
    end)
    self.frame = f
    local pos = TC.db.frame
    if pos then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        f:SetPoint("CENTER")
    end
    S:GearButton(f, function() ns.Settings:Toggle() end, "Settings")

    self:BuildStatus(f)
    self:BuildContestantCard(f)
    self:BuildVoting(f)
    self:BuildLeaderControls(f)
    self:BuildWinnerBanner(f)
    self:BuildRanking(f)
    self:BuildFooter(f)

    f:SetScript("OnShow", function()
        self.modelKey = nil
        self:Refresh()
        self.ticker = C_Timer.NewTicker(1.5, function() self:UpdateModel() end)
    end)
    f:SetScript("OnHide", function()
        if self.ticker then self.ticker:Cancel() end
        self.ticker = nil
    end)
end

function UI:GetRow(i)
    local row = self.rows[i]
    if not row then
        local child = self.scroll.child
        row = CreateFrame("Frame", nil, child)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_HEIGHT)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.hl = row:CreateTexture(nil, "HIGHLIGHT")
        row.hl:SetAllPoints()
        row.hl:SetColorTexture(1, 1, 1, 0.04)
        row:EnableMouse(true)
        self:LayoutRow(row, 12, C.text)
        self.rows[i] = row
    end
    return row
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
function UI:UpdateModel()
    local m = self.model
    if not m then return end
    local db = TC.db
    local name = db.phase ~= "IDLE" and db.contestant or nil
    -- During voting show the contestant live when possible; otherwise use their shared outfit.
    local unit = name and TC.group[name]
    local useStored = db.phase ~= "VOTING" or not (unit and UnitIsVisible(unit))
    local key = ns.Outfit:RenderKey(name, useStored)
    if key == self.modelKey then return end
    self.modelKey = key

    m.facing = 0
    local note = ns.Outfit:Render(m, name, useStored)
    m:SetFacing(0)
    m.msg:SetText(name and (note or "") or L["Waiting for the next round."])
end

function UI:RefreshContestant(db)
    local onStage = db.phase ~= "IDLE" and db.contestant
    self.contestant:SetText(onStage and self:ColoredName(db.contestant) or S:Color(C.muted, L["No one yet"]))

    if db.phase == "VOTING" then
        local pending, total = TC:GetPending()
        local voted = total - #pending
        self.progress:Show()
        self.progress:SetStatusBarColor(unpack(#pending == 0 and C.success or C.accent))
        self.progress:SetValue(total > 0 and voted / total or 0)
        self.votesText:SetText((L["%d of %d voted"]):format(voted, total))
        if #pending > 0 then
            self.pendingText:SetText(S:Color(C.muted, L["Waiting on "]) .. self:NameList(pending))
        else
            self.pendingText:SetText(S:Color(C.success, L["All votes are in!"]))
        end
    elseif db.phase == "CLOSED" and db.results[db.contestant] then
        local r = db.results[db.contestant]
        self.progress:Show()
        self.progress:SetStatusBarColor(unpack(C.gold))
        self.progress:SetValue(r.avg / TC.MAX_SCORE)
        self.votesText:SetText(S:Color(C.gold, (L["%.2f"]):format(r.avg)) .. S:Color(C.muted, (L[" / %d"]):format(TC.MAX_SCORE)))
        self.pendingText:SetText((L["from %d vote(s)"]):format(r.count))
    else
        self.progress:Hide()
        self.votesText:SetText("")
        self.pendingText:SetText(TC:IsLeader() and L["Press Shuffle & Start to pick the first contestant."]
            or L["The leader will pick the next contestant."])
    end
    self:UpdateModel()
end

function UI:RefreshVoting(db, me)
    local canVote = TC:CanVote(me)
    for score, b in pairs(self.voteButtons) do
        b:SetEnabled(canVote)
        b:SetSelected(db.phase == "VOTING" and db.myVote == score)
    end
    if db.phase ~= "VOTING" then
        self.myVoteText:SetText(L["Voting is closed"])
    elseif me == db.contestant then
        self.myVoteText:SetText(S:Color(C.accent, L["You're on stage! Strike a pose."]))
    elseif not db.voters[me] then
        self.myVoteText:SetText(L["You joined mid-round. Vote next round."])
    elseif db.myVote then
        self.myVoteText:SetText((L["Voted %s, click to change"]):format(S:Color(C.accent, db.myVote)))
    else
        self.myVoteText:SetText((L["Pick a score from %d to %d"]):format(TC.MIN_SCORE, TC.MAX_SCORE))
    end
end

local function CategoryName(theme)
    return theme or L["No theme"]
end

-- Builds the tab list and returns the selected category (nil for Overall).
function UI:RefreshRankTabs(db)
    local categories = TC:GetCategories()
    local items, byKey = {}, {}
    local hasResults = false
    for _, cat in ipairs(categories) do
        if next(cat.results) then hasResults = true end
    end
    if hasResults or db.finished then items[#items + 1] = { key = "overall", text = L["Overall"] } end
    for _, cat in ipairs(categories) do
        local text = CategoryName(cat.theme)
        items[#items + 1] = { key = cat.key, text = cat.current and S:Color(C.success, text) or text }
        byKey[cat.key] = cat
    end

    -- Jump back to the default tab when the competition moves on (new theme, finish).
    local context = ("%s|%s|%d"):format(tostring(db.finished), tostring(db.currentTheme), #db.themeResults)
    if context ~= self.rankContext then
        self.rankContext = context
        self.rankTab = nil
    end
    local valid = self.rankTab == "overall" and items[1] and items[1].key == "overall" or byKey[self.rankTab]
    if not valid then self.rankTab = db.finished and "overall" or "current" end
    if self.rankTab == "current" and not byKey.current then self.rankTab = "overall" end

    self.rankTabs:SetItems(items, self.rankTab)
    return byKey[self.rankTab]
end

function UI:RefreshRanking(db)
    local category = self:RefreshRankTabs(db)
    local header = self.rankHeader
    local overall = self.rankTab == "overall"
    header.name:SetText(L["PLAYER"])
    header.score:SetText(overall and L["POINTS"] or L["SCORE"])
    header.votes:SetText(overall and L["THEMES"] or L["VOTES"])

    local entries
    if overall then
        entries = TC:GetOverallRanking()
    elseif category and category.current then
        entries = TC:GetScoreboard() -- includes players still waiting to showcase
    else
        entries = TC:RankResults(category and category.results or {})
    end

    for i, e in ipairs(entries) do
        local row = self:GetRow(i)
        row:Show()
        row.name:SetText(self:ColoredName(e.name))
        local onStage = not overall and category and category.current
            and db.phase == "VOTING" and e.name == db.contestant
        if overall then
            row.rank:SetText(e.rank)
            row.rank:SetTextColor(unpack(S:RankColor(e.rank)))
            row.score:SetText(("%.2f"):format(e.score))
            row.score:SetTextColor(unpack(e.rank == 1 and C.gold or C.text))
            row.votes:SetText(e.themes)
        elseif e.avg then
            row.rank:SetText(e.rank)
            row.rank:SetTextColor(unpack(S:RankColor(e.rank)))
            row.score:SetText((L["%.2f"]):format(e.avg))
            row.score:SetTextColor(unpack(e.rank == 1 and C.gold or C.text))
            row.votes:SetText(e.count)
        else
            row.rank:SetText("-")
            row.rank:SetTextColor(unpack(C.muted))
            row.score:SetText("")
            row.votes:SetText(onStage and S:Color(C.success, L["on stage"]) or L[e.status])
        end
        if onStage then
            row.bg:SetColorTexture(C.success[1], C.success[2], C.success[3], 0.10)
        elseif e.rank == 1 then
            row.bg:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.08)
        elseif i % 2 == 0 then
            row.bg:SetColorTexture(1, 1, 1, 0.025)
        else
            row.bg:SetColorTexture(0, 0, 0, 0)
        end
    end
    for i = #entries + 1, #self.rows do self.rows[i]:Hide() end
    self.scroll.child:SetHeight(math.max(1, #entries * ROW_HEIGHT))
    self.scroll:UpdateThumb()
end

function UI:Refresh()
    if not self.frame or not self.frame:IsShown() or not TC.db then return end
    local db = TC.db
    local me = TC:Me()
    local isLeader = TC:IsLeader()
    local pool = TC:GetPool()

    -- Status
    local phase = PHASES[db.phase] or PHASES.IDLE
    self.phase:Set(L[phase[1]], phase[2])
    if db.finished then
        self.roundText:SetText(L["Competition finished"])
    else
        self.roundText:SetText(db.round > 0 and (L["Round %d"]):format(db.round) or L["Not started"])
    end
    self.leaderText:SetText(TC.leader and (S:Color(C.muted, L["Leader "]) .. self:ColoredName(TC.leader)) or "")
    self.themeText:SetText(db.currentTheme and (L["Theme "] .. S:Color(C.gold, db.currentTheme)) or "")

    self:RefreshContestant(db)
    self:RefreshVoting(db, me)

    -- Leader controls
    self.leaderLabel:SetShown(isLeader)
    self.leaderBar:SetShown(isLeader)
    self.notLeader:SetShown(not isLeader)
    -- After a finish, Shuffle & Start begins the next competition.
    self.nextBtn:SetEnabled(db.phase ~= "VOTING" and (#pool > 0 or db.finished))
    self.closeBtn:SetEnabled(db.phase == "VOTING")
    self.winnerBtn:SetEnabled(db.phase ~= "VOTING" and not db.finished and next(db.results) ~= nil)
    self.finishBtn:SetEnabled(db.phase ~= "VOTING" and not db.finished and #TC:GetOverallRanking() > 0)
    self.finishBtn:SetText(db.finished and L["Competition finished"] or L["Finish Competition"])

    -- Winner banner: overall winner once finished, otherwise the current theme's winner.
    local ov = db.finished and db.overallWinner
    local w = db.winner
    local hasWinner = (ov and #ov.names > 0) or (w and #w.names > 0)
    self.winnerBanner:SetShown(hasWinner and true or false)
    if ov and #ov.names > 0 then
        local label = #ov.names > 1 and L["OVERALL WINNERS"] or L["OVERALL WINNER"]
        self.winnerBanner.text:SetText(("%s  %s  %s"):format(label, self:NameList(ov.names),
            S:Color(C.gold, ("%.2f"):format(ov.score))))
    elseif hasWinner then
        local label = #w.names > 1 and L["WINNERS"] or L["WINNER"]
        if w.theme then label = label .. " - " .. S:Upper(w.theme) end
        self.winnerBanner.text:SetText(("%s  %s  %s"):format(label, self:NameList(w.names),
            S:Color(C.gold, ("%.2f"):format(w.avg))))
    end

    -- Leader controls take more room than the "only the leader" note.
    local top = isLeader and -454 or -400
    self.winnerBanner:SetPoint("TOPLEFT", PAD, top)
    self.rankingCard:SetPoint("TOPLEFT", PAD, hasWinner and (top - 38) or top)

    self:RefreshRanking(db)

    -- Footer
    local inGroup = 0
    for name in pairs(TC.participants) do
        if TC.group[name] then inGroup = inGroup + 1 end
    end
    local footer = (L["%s of %d still to showcase"]):format(S:Color(C.text, #pool), inGroup)
    local missing = TC:GetMissingAddon()
    if #missing > 0 then
        footer = footer .. "\n" .. S:Color(C.danger, L["Missing addon: "]) .. self:NameList(missing)
    end
    self.footer:SetText(footer)
end

------------------------------------------------------------------------
-- Visibility
------------------------------------------------------------------------
function UI:Show()
    self:Build()
    self.frame:Show()
end

-- Opens the window on the Overall tab (used when the competition finishes).
function UI:ShowOverall()
    self:Build()
    self.frame:Show()
    self.rankContext = nil
    self:Refresh()
    self.rankTab = "overall"
    self:Refresh()
end

function UI:Toggle()
    self:Build()
    self.frame:SetShown(not self.frame:IsShown())
end
