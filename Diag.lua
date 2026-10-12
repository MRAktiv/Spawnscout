-- /spawnscout diag: checks in the live client what the offline tests cannot cover.
local _, ns = ...
local addon, Logic, L = ns.addon, ns.Logic, ns.L

local Diag = addon:NewModule("Diag", "AceTimer-3.0")
ns.Diag = Diag

Diag.lines = {}

local function out(...)
	local parts = {}
	for index = 1, select("#", ...) do
		parts[#parts + 1] = tostring((select(index, ...)))
	end
	local line = table.concat(parts, " ")
	Diag.lines[#Diag.lines + 1] = line
	print("|cff8fd14fSS|r", line)
	Diag:UpdateCopy()
end

-- Nameplates on screen right now, split the way crowding counts them.
local function plateCounts()
	local level = UnitLevel("player")
	local plates, players, hostile, worth, tapped = 0, 0, 0, 0, 0
	for index = 1, 40 do
		local unit = "nameplate" .. index
		if UnitExists(unit) then
			plates = plates + 1
			if UnitIsPlayer(unit) then
				players = players + 1
			elseif UnitCanAttack("player", unit) and not UnitIsDead(unit) then
				hostile = hostile + 1
				local mobLevel = UnitLevel(unit)
				if ns.Usable(mobLevel) and Logic.WorthLevel(level, mobLevel) then
					worth = worth + 1
					local denied = UnitIsTapDenied(unit)
					if not ns.Usable(denied) then
						tapped = "secret"
					elseif denied and type(tapped) == "number" then
						tapped = tapped + 1
					end
				end
			end
		end
	end
	return plates, players, hostile, worth, tapped
end

function Diag:Run()
	self.lines = {}
	self:ShowCopy()
	self:Collect(out)
	self:Echo()
end

-- Every check except the echo, written through out.
function Diag:Collect(out)
	out(L["DIAG_HEADER"])
	local version, build, _, interface = GetBuildInfo()
	out("client", version, build, "interface", interface, "project", tostring(WOW_PROJECT_ID), "locale", GetLocale())

	local exhaustion = GetXPExhaustion and GetXPExhaustion()
	out("player level", UnitLevel("player"), "xp", tostring(UnitXP("player")), "/", tostring(UnitXPMax("player")), "rested", tostring(exhaustion), "combat", tostring(UnitAffectingCombat("player")))

	local gains = {}
	for _, gain in ipairs(ns.Measure.recent) do
		gains[#gains + 1] = string.format("%d%s%s%s", gain.xp, gain.fighting and "f" or "", gain.rested and "r" or "", gain.counted and "+" or "-")
	end
	out("recent gains (f fight, r rested, + counted)", #gains > 0 and table.concat(gains, " ") or "-")

	local snapshot = ns.Measure:Snapshot()
	out("rate", tostring(snapshot.rate), "kills", snapshot.kills, "active", tostring(snapshot.active), "tagged", tostring(snapshot.tapped), "free", snapshot.free and string.format("%.1f", snapshot.free) or "nil")
	out("spot", snapshot.x and (snapshot.x .. " " .. snapshot.y) or "-", "kills there", tostring(snapshot.spotKills))

	local cvar = C_CVar and C_CVar.GetCVar
	out("cvar nameplateShowEnemies", tostring(cvar and cvar("nameplateShowEnemies")), "nameplateShowAll", tostring(cvar and cvar("nameplateShowAll")))
	local plates, players, hostile, worth, tapped = plateCounts()
	out("plates", plates, "players", players, "hostile", hostile, "worth xp", worth, "tagged by others", tapped)
	local stats = ns.Measure.stats
	out("crowd since login: samples", stats.samples, "with mobs", stats.withMobs, "mobs", stats.mobs, "tagged", stats.tagged, "secret", stats.secret)

	local mapID = ns.ZoneMapID()
	local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if position then
		local x, y = position:GetXY()
		local cx, cy = Logic.Cell(math.floor(x * 1000), math.floor(y * 1000))
		out("position map", mapID, ns.MapName(mapID), string.format("%.3f %.3f", x, y), "cell", cx, cy)
	else
		out("position map", tostring(mapID), "no position")
	end

	local layer = ns.Layer
	out("layer", tostring(layer:Label()), tostring(layer:Current()), "keys", Logic.LayerSummary(layer.tracker))

	local net = ns.Net
	out("channel id", tostring(net:ChannelID()), "join", tostring(net.joinResult), "instance", tostring(ns.InInstance()), "share", tostring(ns.db.profile.share))
	local channels = {}
	for index = 1, 20 do
		local id, name = GetChannelName(index)
		if type(id) == "number" and id > 0 and name then
			channels[#channels + 1] = id .. " " .. tostring(name)
		end
	end
	out("channels", #channels > 0 and table.concat(channels, ", ") or "-")
	out("restored at login", tostring(net.restored or false), "temporary join", tostring(JoinTemporaryChannel ~= nil), "zone channels", tostring(ns.Net.ZoneChannelsJoined()))
	out("reports stored", net:ReportCount(), "received", net.received, "sent", net.sent, "spots for you", #net:Spots())

	out("world map", tostring(WorldMapFrame ~= nil), "provider", tostring(ns.MapPins.provider ~= nil), "pins shown", ns.MapPins.shown)
	local canSet = mapID and C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(mapID)
	out("waypoint api", tostring(C_Map.SetUserWaypoint ~= nil), "UiMapPoint", tostring(UiMapPoint ~= nil), "supertrack", tostring(C_SuperTrack ~= nil), "can set here", tostring(canSet))
end

function Diag:Echo()
	if not ns.Net:ChannelID() then
		out(L["DIAG_ECHO_FAIL"], "(no channel id)")
		return
	end
	self.nonce = tostring(math.random(100000, 999999))
	self.sentAt = GetTime()
	ns.Net:Send("T1;" .. self.nonce)
	self:ScheduleTimer(function()
		if self.nonce then
			out(L["DIAG_ECHO_FAIL"])
			self.nonce = nil
		end
	end, 5)
end

-- The sender name is printed so the format of names on the channel can be checked.
function Diag:OnEcho(text, sender)
	local nonce = text:match("^T1;(%d+)$")
	if nonce and nonce == self.nonce then
		self.nonce = nil
		out(L["DIAG_ECHO_OK"]:format(GetTime() - self.sentAt), "sender", tostring(sender))
	end
end

-- Chat text cannot be copied in WoW, so the report also sits in a selectable box.
function Diag:ShowCopy()
	local AceGUI = LibStub("AceGUI-3.0", true)
	if not AceGUI then
		return
	end
	if not self.window then
		local window = AceGUI:Create("Frame")
		window:SetTitle(L["TITLE"])
		window:SetStatusText(L["DIAG_COPY"])
		window:SetLayout("Fill")
		window:SetWidth(640)
		window:SetHeight(420)
		window:SetCallback("OnClose", function(widget)
			AceGUI:Release(widget)
			Diag.window, Diag.box = nil, nil
		end)
		local box = AceGUI:Create("MultiLineEditBox")
		box:SetLabel("")
		box:DisableButton(true)
		window:AddChild(box)
		self.window, self.box = window, box
	end
	self:UpdateCopy()
end

function Diag:UpdateCopy()
	if self.box then
		self.box:SetText(table.concat(self.lines, "\n"))
		self.box:HighlightText()
		self.box:SetFocus()
	end
end
