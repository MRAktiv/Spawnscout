-- Shares spot reports on one channel and keeps what other players report.
-- Addons cannot send from inside instances, so reports go out only in the open world.
local _, ns = ...
local addon, Logic = ns.addon, ns.Logic

local Net = addon:NewModule("Net", "AceEvent-3.0", "AceTimer-3.0", "AceComm-3.0")
ns.Net = Net

local PREFIX = "Spawnscout"
local CHANNEL = "Spawnscout"
local SEND_EVERY = 120
local SELF = "@self"
local JOIN_WAIT = 60
local MAX_CHANNELS = 20
local ZONE_CHANNEL = Enum.PermanentChatChannelType and Enum.PermanentChatChannelType.Zone or 1

Net.reports = {}
Net.lastSent = -math.huge
Net.received = 0
Net.sent = 0

-- True once a game zone channel (General, LocalDefense) holds a number. A channel joined
-- before them takes their number, and /1 stops being General.
function Net.ZoneChannelsJoined()
	if not (C_ChatInfo and C_ChatInfo.GetChannelInfoFromIdentifier) then
		return true
	end
	for index = 1, MAX_CHANNELS do
		local id = GetChannelName(index)
		if type(id) == "number" and id > 0 then
			local info = C_ChatInfo.GetChannelInfoFromIdentifier(tostring(id))
			if info and info.channelType == ZONE_CHANNEL then
				return true
			end
		end
	end
	return false
end

function Net:OnEnable()
	self.enabledAt = GetTime()
	-- A channel the server kept from the last session comes back before the zone channels; give its number up.
	if self:ChannelID() and not Net.ZoneChannelsJoined() then
		self.restored = true
		pcall(LeaveChannelByName, CHANNEL)
	end
	self:RegisterComm(PREFIX, "OnComm")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnWorld")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "OnWorld")
	local filter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
	if filter then
		for _, event in ipairs({ "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER", "CHAT_MSG_CHANNEL" }) do
			filter(event, Net.HideOwnChannel)
		end
	end
	self:ScheduleRepeatingTimer("Tick", 20)
	self:ScheduleTimer("OnWorld", 5)
end

-- Chat filter: hides notices and text of the Spawnscout channel. The first argument is the message.
function Net.HideOwnChannel(_, _, ...)
	for index = 2, select("#", ...) do
		local value = select(index, ...)
		if type(value) == "string" and ns.Usable(value) and (value == CHANNEL or value:match("^%d+%. " .. CHANNEL .. "$")) then
			return true
		end
	end
	return false
end

function Net:Active()
	return not ns.InInstance()
end

function Net:ChannelID()
	local id = GetChannelName(CHANNEL)
	if type(id) == "number" and id > 0 then
		return id
	end
	return nil
end

function Net:UpdateChannel()
	if self:ChannelID() then
		return
	end
	if not self:Active() then
		return
	end
	if not Net.ZoneChannelsJoined() and GetTime() - self.enabledAt < JOIN_WAIT then
		return
	end
	local join = JoinTemporaryChannel or JoinChannelByName
	local ok, err = pcall(join, CHANNEL)
	self.joinResult = ok and "ok" or tostring(err)
end

function Net:OnWorld()
	self:UpdateChannel()
end

function Net:Tick()
	self:UpdateChannel()
	local now = GetTime()
	Logic.ExpireReports(self.reports, now)
	if now - self.lastSent >= SEND_EVERY then
		self:SendReport()
	end
	self:SendMessage("SPAWNSCOUT_SPOTS_CHANGED")
end

-- Report of the farming spot, placed where the kills were rather than where the player stands now
-- (a quest giver after the pulls). Nil while there is nothing worth sharing.
function Net:BuildReport()
	if not self:Active() or ns.OnTaxi() then
		return nil
	end
	local snapshot = ns.Measure:Snapshot()
	if not snapshot.rate or not snapshot.active or not snapshot.x then
		return nil
	end
	return {
		mapID = ns.ZoneMapID(),
		x = snapshot.x,
		y = snapshot.y,
		layer = ns.Layer:Current(),
		level = UnitLevel("player"),
		rate = snapshot.rate,
		tapped = snapshot.tapped,
		free = snapshot.free and math.min(math.floor(snapshot.free * 10 + 0.5), 999) or nil,
		kills = snapshot.kills,
		faction = ns.Faction(),
	}
end

-- The own report is kept locally right away; sharing only decides whether it goes to the channel.
function Net:SendReport()
	local report = self:BuildReport()
	if not report then
		return
	end
	local now = GetTime()
	self.lastSent = now
	Logic.AddReport(self.reports, SELF, report, now)
	local text = Logic.EncodeReport(report)
	local sent = ns.db.profile.share and self:Send(text)
	if sent then
		self.sent = self.sent + 1
	end
	self:SendMessage("SPAWNSCOUT_SPOTS_CHANGED")
end

function Net:Send(text)
	local id = self:ChannelID()
	if not id or not self:Active() then
		return false
	end
	self:SendCommMessage(PREFIX, text, "CHANNEL", id, "BULK")
	return true
end

-- Own copy of a message is recognised by the sender name: the channel can return it minutes later.
function Net:OnComm(_, text, distribution, sender)
	if distribution ~= "CHANNEL" or type(text) ~= "string" or not ns.Usable(sender) then
		return
	end
	if ns.NameKey(sender) == ns.NameKey(ns.QualifiedUnitName("player")) then
		if text:sub(1, 1) == "T" and ns.Diag then
			ns.Diag:OnEcho(text, sender)
		end
		return
	end
	if text:sub(1, 1) == "S" then
		local report = Logic.DecodeReport(text)
		if report and report.faction == ns.Faction() then
			Logic.AddReport(self.reports, ns.NameKey(sender), report, GetTime())
			self.received = self.received + 1
		end
	end
end

function Net:Viewer()
	return { level = UnitLevel("player"), layer = ns.Layer:Current(), self = SELF }
end

function Net:Spots(mapFilter)
	return Logic.BuildSpots(self.reports, self:Viewer(), GetTime(), mapFilter)
end

function Net:ReportCount()
	local count = 0
	for _ in pairs(self.reports) do
		count = count + 1
	end
	return count
end
