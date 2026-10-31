-- TmogCompetition: group roster and leader tracking.
local ADDON, ns = ...
local TC, L = ns.TC, ns.L

function TC:ScanGroup()
    local group = wipe(self.group)
    self.leader = nil

    local function add(unit)
        local name = self:UnitFullName(unit)
        if name then
            group[name] = unit
            if UnitIsGroupLeader(unit) then self.leader = name end
        end
    end

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do add("raid" .. i) end
    else
        add("player")
        if IsInGroup() then
            for i = 1, GetNumSubgroupMembers() do add("party" .. i) end
        end
    end

    local me = self:Me()
    if not IsInGroup() then self.leader = me end

    for name in pairs(self.participants) do
        if not group[name] then self.participants[name] = nil end
    end
    if me then self.participants[me] = { version = self.VERSION } end
end

function TC:IsLeader()
    return not IsInGroup() or UnitIsGroupLeader("player")
end

function TC:RequireLeader()
    if self:IsLeader() then return true end
    TC.Print(L.CORE_LEADER_ONLY)
    return false
end
