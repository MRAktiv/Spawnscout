-- Own measurements while fighting: kill experience per hour and how crowded the mobs around are.
local _, ns = ...
local addon, Logic = ns.addon, ns.Logic

local Measure = addon:NewModule("Measure", "AceEvent-3.0", "AceTimer-3.0")
ns.Measure = Measure

local COMBAT_GRACE = 3
local CROWD_EVERY = 5
local RECENT_MAX = 6

Measure.meter = Logic.NewMeter()
Measure.crowd = Logic.NewCrowd()
Measure.lastCombat = -math.huge
Measure.recent = {}
-- Totals since login for the diagnostics: was anything tagged by others ever seen, did tagging come back secret.
Measure.stats = { samples = 0, withMobs = 0, mobs = 0, tagged = 0, secret = 0 }

function Measure:OnEnable()
	self:RegisterEvent("PLAYER_XP_UPDATE", "OnXP")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")
	self:RegisterEvent("UPDATE_EXHAUSTION", "OnExhaustion")
	self:ScheduleRepeatingTimer("SampleCrowd", CROWD_EVERY)
	self:OnXP(nil, "player")
end

-- Rested pool as it was before the next gain; a gain made while rested carries the bonus.
function Measure:OnExhaustion()
	self.lastRested = GetXPExhaustion and GetXPExhaustion() or nil
end

-- Kill experience arrives as the mob dies, sometimes in the same moment combat ends.
function Measure:Fighting()
	return UnitAffectingCombat("player") or GetTime() - self.lastCombat <= COMBAT_GRACE
end

function Measure:OnCombatEnd()
	self.lastCombat = GetTime()
end

-- A new zone starts a new measurement: the rate and crowding belong to one place.
function Measure:CheckZone()
	local mapID = ns.ZoneMapID()
	if mapID ~= self.mapID then
		self.mapID = mapID
		Logic.ResetMeter(self.meter)
		Logic.ResetCrowd(self.crowd)
	end
end

-- Player position on the zone map in thousandths, nil when it cannot be read.
function Measure:Position()
	local mapID = ns.ZoneMapID()
	local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if not position then
		return nil
	end
	local x, y = position:GetXY()
	if not (ns.Usable(x) and ns.Usable(y)) or x <= 0 or y <= 0 or x >= 1 or y >= 1 then
		return nil
	end
	return math.floor(x * 1000), math.floor(y * 1000)
end

function Measure:OnXP(_, unit)
	if unit and unit ~= "player" then
		return
	end
	local xp, maxXP, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
	if not (ns.Usable(xp) and ns.Usable(maxXP)) then
		return
	end
	local delta = Logic.XPDelta(self.meter, xp, maxXP, level)
	local rested = (self.lastRested or 0) > 0
	self.lastRested = GetXPExhaustion and GetXPExhaustion() or nil
	if delta <= 0 or ns.InInstance() then
		return
	end
	self:CheckZone()
	local fighting = self:Fighting() and true or false
	local x, y = self:Position()
	local counted = Logic.AddGain(self.meter, delta, GetTime(), fighting, rested, x, y)
	table.insert(self.recent, 1, { xp = delta, fighting = fighting, rested = rested, counted = counted })
	self.recent[RECENT_MAX + 1] = nil
end

-- Nameplate snapshot at the farming spot: attackable mobs worth experience and how many are tagged by others.
-- Taken in combat or near the spot between pulls, never on the way to a quest giver.
-- With enemy nameplates hidden no mob is visible, so crowding stays unknown instead of reading as empty.
function Measure:SampleCrowd()
	if ns.InInstance() or ns.OnTaxi() or not ns.EnemyPlatesShown() then
		return
	end
	self:CheckZone()
	if not UnitAffectingCombat("player") then
		local _, _, active = Logic.Rate(self.meter, GetTime())
		local spotX, spotY = Logic.SpotPosition(self.meter)
		local x, y = self:Position()
		if not (active and spotX and x and Logic.NearSpot(x, y, spotX, spotY)) then
			return
		end
	end
	local level = UnitLevel("player")
	local total, tapped, secret = 0, 0, 0
	for index = 1, 40 do
		local unit = "nameplate" .. index
		if UnitExists(unit) and not UnitIsPlayer(unit) and UnitCanAttack("player", unit) and not UnitIsDead(unit) then
			local mobLevel = UnitLevel(unit)
			if ns.Usable(mobLevel) and Logic.WorthLevel(level, mobLevel) then
				total = total + 1
				local denied = UnitIsTapDenied(unit)
				if not ns.Usable(denied) then
					secret = secret + 1
				elseif denied then
					tapped = tapped + 1
				end
			end
		end
	end
	local stats = self.stats
	stats.samples = stats.samples + 1
	stats.withMobs = stats.withMobs + (total > 0 and 1 or 0)
	stats.mobs = stats.mobs + total
	stats.tagged = stats.tagged + tapped
	stats.secret = stats.secret + secret
	self.lastSample = { total = total, tapped = tapped }
	Logic.AddCrowdSample(self.crowd, GetTime(), total, tapped)
end

function Measure:Snapshot()
	self:CheckZone()
	local now = GetTime()
	local rate, kills, active = Logic.Rate(self.meter, now)
	local tapped, free = Logic.Crowding(self.crowd, now)
	local x, y, spotKills = Logic.SpotPosition(self.meter)
	return { rate = rate, kills = kills, active = active, tapped = tapped, free = free, x = x, y = y, spotKills = spotKills }
end
