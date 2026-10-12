-- Addon object, saved settings and small helpers shared by all modules.
local ADDON_NAME, ns = ...

local addon = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceEvent-3.0", "AceConsole-3.0")
ns.addon = addon
ns.L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)

ns.DEFAULTS = {
	profile = {
		share = true,
		mapPins = true,
		debug = false,
		firstRunShown = false,
		minimap = { hide = false },
	},
}

-- Secret values arrive from restricted APIs; treat them as missing data.
local issecretvalue = issecretvalue or function()
	return false
end

function ns.Usable(value)
	return value ~= nil and not issecretvalue(value)
end

-- Registers an event that may be missing on other clients without breaking the load.
function ns.SafeRegister(module, event, handler)
	local ok = pcall(module.RegisterEvent, module, event, handler)
	return ok
end

function ns.Debug(...)
	if ns.db and ns.db.profile.debug then
		print("|cff8fd14fSpawnscout|r", ...)
	end
end

function ns.Print(...)
	print("|cff8fd14fSpawnscout|r", ...)
end

-- "A" or "H": reports from the other faction are dropped, so neither side sees the other's spots.
function ns.Faction()
	return UnitFactionGroup("player") == "Horde" and "H" or "A"
end

function ns.InInstance()
	local inInstance = IsInInstance()
	return inInstance and true or false
end

function ns.OnTaxi()
	return UnitOnTaxi and UnitOnTaxi("player") and true or false
end

-- Zone-level map for the player: caves and sub-maps roll up to their zone,
-- so a cave and the forest around it share one set of coordinates.
function ns.ZoneMapID()
	local mapID = C_Map.GetBestMapForUnit("player")
	local guard = 0
	while mapID and guard < 8 do
		local info = C_Map.GetMapInfo(mapID)
		if not info or info.mapType <= Enum.UIMapType.Zone or not info.parentMapID or info.parentMapID == 0 then
			break
		end
		mapID = info.parentMapID
		guard = guard + 1
	end
	return mapID
end

function ns.EnemyPlatesShown()
	local value = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("nameplateShowEnemies")
	return value == "1"
end

-- Turns enemy nameplates on at the player's click; nameplate settings cannot change in combat.
function ns.ShowEnemyPlates()
	if InCombatLockdown() then
		ns.Print(ns.L["PLATES_COMBAT"])
		return false
	end
	C_CVar.SetCVar("nameplateShowEnemies", "1")
	return true
end

function ns.MapName(mapID)
	local info = mapID and C_Map.GetMapInfo(mapID)
	return info and info.name or ("#" .. tostring(mapID))
end

-- Forever names are "Given Family" and unique per region; other clients use "Name-Realm".
function ns.QualifiedUnitName(unit)
	local getName = UnitNameUnmodified or UnitName
	local name, qualifier = getName(unit)
	if not ns.Usable(name) or name == "" then
		return nil
	end
	if ns.Usable(qualifier) and qualifier ~= "" and not name:find(" ", 1, true) then
		local regional = RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled()
		return name .. (regional and " " or "-") .. qualifier
	end
	return name
end

-- Letters only, lower case: "Ana Forever", "Ana-Forever" and "anaforever" compare equal.
function ns.NameKey(name)
	if not ns.Usable(name) then
		return nil
	end
	return (tostring(name):gsub("[%s%-]", ""):lower())
end

function ns.FormatNumber(value)
	value = math.floor(value + 0.5)
	if value >= 10000 then
		return string.format("%.1fk", value / 1000)
	end
	return tostring(value)
end

-- Dot colour by tagged share: green free, yellow busy, red crowded, grey unknown.
function ns.CrowdColor(tapped)
	if not tapped then
		return 0.6, 0.6, 0.6
	elseif tapped < 25 then
		return 0.25, 0.85, 0.3
	elseif tapped < 50 then
		return 0.95, 0.8, 0.2
	end
	return 0.9, 0.25, 0.2
end

-- Built-in map waypoint, tracked on screen like a quest objective.
function ns.SetWaypoint(mapID, x, y)
	if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint) then
		ns.Print(ns.L["NO_WAYPOINT"])
		return false
	end
	if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(mapID) then
		ns.Print(ns.L["NO_WAYPOINT"])
		return false
	end
	C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
		C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	end
	ns.Print(ns.L["WAYPOINT_SET"]:format(ns.MapName(mapID), x * 100, y * 100))
	return true
end
