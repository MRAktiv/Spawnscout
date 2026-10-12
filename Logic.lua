-- Pure logic: layer from creature GUIDs, kill experience rate, crowding, wire protocol and spot ranking.
-- No WoW API calls here, so the whole file runs under the offline test harness.
local _, ns = ...

local Logic = {}
ns.Logic = Logic

local PROTOCOL = "1"
local GRID = 20
local RATE_WINDOW = 600
local MIN_KILLS = 3
local MIN_SPAN = 120
local IDLE_AFTER = 180
local CROWD_WINDOW = 300
local REPORT_TTL = 900
local LEVEL_RANGE = 2
local MAX_RATE = 500000
local SPOT_RADIUS = 75

Logic.PROTOCOL = PROTOCOL
Logic.GRID = GRID
Logic.REPORT_TTL = REPORT_TTL
Logic.LEVEL_RANGE = LEVEL_RANGE

-- Creature GUID: Creature-0-<server>-<instance>-<zoneUID>-<npcID>-<spawnUID>.
-- The server and zoneUID pair identifies the world copy (layer) the creature lives in.
function Logic.ParseCreatureGUID(guid)
	if type(guid) ~= "string" then
		return nil
	end
	local kind, server, zoneUID, npcID = guid:match("^(%a+)%-%d+%-(%d+)%-%d+%-(%d+)%-(%d+)%-%x+$")
	if kind ~= "Creature" and kind ~= "Vehicle" then
		return nil
	end
	if zoneUID == "0" or server == "0" then
		return nil
	end
	return server, zoneUID, tonumber(npcID)
end

function Logic.LayerKeyFromGUID(guid)
	local server, zoneUID = Logic.ParseCreatureGUID(guid)
	if server then
		return server .. "-" .. zoneUID
	end
	return nil
end

-- Layer tracker: switches the current layer only after two different creatures agree,
-- so a single odd NPC cannot flip the result.
function Logic.NewLayerTracker()
	return { current = nil, mapID = nil, pending = nil, seen = {} }
end

function Logic.ObserveLayer(tracker, mapID, key, guid, now)
	if not key then
		return false
	end
	if tracker.mapID ~= mapID then
		tracker.mapID = mapID
		tracker.current = nil
		tracker.pending = nil
		tracker.seen = {}
	end
	if not tracker.seen[key] then
		tracker.seen[key] = { first = now, order = 0 }
		local count = 0
		for _ in pairs(tracker.seen) do
			count = count + 1
		end
		tracker.seen[key].order = count
	end
	local entry = tracker.seen[key]
	entry.last = now
	entry.guids = entry.guids or {}
	if guid and not entry.guids[guid] then
		entry.guids[guid] = true
		entry.npcs = (entry.npcs or 0) + 1
	end
	if tracker.current == key then
		tracker.pending = nil
		return false
	end
	local pending = tracker.pending
	if pending and pending.key == key and pending.guid ~= guid then
		tracker.current = key
		tracker.pending = nil
		return true
	end
	if not pending or pending.key ~= key then
		tracker.pending = { key = key, guid = guid }
	end
	return false
end

function Logic.ResetLayer(tracker)
	tracker.current = nil
	tracker.pending = nil
end

-- Short local label for a layer key: A, B, C in the order this client met them on the map.
function Logic.LayerLabel(tracker, key)
	local entry = key and tracker.seen[key]
	if not entry then
		return "?"
	end
	return string.char(64 + math.min(entry.order, 26))
end

-- "4621-37 x3, 4621-41 x1": every layer key met on this map and how many different creatures showed it.
function Logic.LayerSummary(tracker)
	local keys = {}
	for key in pairs(tracker.seen) do
		keys[#keys + 1] = key
	end
	table.sort(keys, function(a, b)
		return tracker.seen[a].order < tracker.seen[b].order
	end)
	for index, key in ipairs(keys) do
		keys[index] = key .. " x" .. (tracker.seen[key].npcs or 0)
	end
	return table.concat(keys, ", ")
end

-- Highest mob level that gives no experience (Classic formula).
function Logic.GrayLevel(level)
	if level <= 5 then
		return 0
	elseif level < 40 then
		return level - math.floor(level / 10) - 5
	end
	return level - math.floor(level / 5) - 1
end

-- Mobs that count for crowding: worth experience and not far above the player.
function Logic.WorthLevel(level, mobLevel)
	return mobLevel > 0 and mobLevel > Logic.GrayLevel(level) and mobLevel <= level + 5
end

-- Kill experience meter. Gains count only while fighting or right after, so quest turn-ins
-- and exploration stay out; rested bonus doubles kill experience and is halved back.
function Logic.NewMeter()
	return { gains = {} }
end

-- Experience gained since the previous reading, including across a level-up.
function Logic.XPDelta(meter, xp, maxXP, level)
	local delta = 0
	if meter.lastXP then
		if level > meter.lastLevel then
			delta = (meter.lastMax - meter.lastXP) + xp
		else
			delta = xp - meter.lastXP
		end
	end
	meter.lastXP, meter.lastMax, meter.lastLevel = xp, maxXP, level
	return math.max(delta, 0)
end

-- x and y: where the kill happened, in thousandths of the zone map (nil when unknown).
function Logic.AddGain(meter, amount, now, fighting, rested, x, y)
	if amount <= 0 or not fighting then
		return false
	end
	if rested then
		amount = amount / 2
	end
	meter.gains[#meter.gains + 1] = { at = now, xp = amount, x = x, y = y }
	return true
end

function Logic.ResetMeter(meter)
	meter.gains = {}
end

-- Experience per hour over the last ten minutes. The first kill's experience is left out,
-- because the time spent before it is not in the span. Returns rate (nil while too little data),
-- kills in the window and whether the player is still killing.
function Logic.Rate(meter, now)
	local kept, total = {}, 0
	for _, gain in ipairs(meter.gains) do
		if now - gain.at <= RATE_WINDOW then
			kept[#kept + 1] = gain
			total = total + gain.xp
		end
	end
	meter.gains = kept
	local count = #kept
	if count == 0 then
		return nil, 0, false
	end
	local first, last = kept[1], kept[count]
	local active = now - last.at <= IDLE_AFTER
	local span = now - first.at
	if count < MIN_KILLS or span < MIN_SPAN then
		return nil, count, active
	end
	return math.floor((total - first.xp) * 3600 / span + 0.5), count, active
end

-- Crowding from nameplate snapshots: share of nearby mobs already tagged by someone else
-- and how many untagged ones are around on average.
function Logic.NewCrowd()
	return { samples = {} }
end

function Logic.AddCrowdSample(crowd, now, total, tapped)
	crowd.samples[#crowd.samples + 1] = { at = now, total = total, tapped = tapped }
end

function Logic.ResetCrowd(crowd)
	crowd.samples = {}
end

-- Returns tagged share in percent (nil when no mobs were seen) and free mobs per snapshot.
function Logic.Crowding(crowd, now)
	local kept, total, tapped = {}, 0, 0
	for _, sample in ipairs(crowd.samples) do
		if now - sample.at <= CROWD_WINDOW then
			kept[#kept + 1] = sample
			total = total + sample.total
			tapped = tapped + sample.tapped
		end
	end
	crowd.samples = kept
	if #kept == 0 then
		return nil, nil
	end
	local share = total > 0 and math.floor(tapped * 100 / total + 0.5) or nil
	return share, (total - tapped) / #kept
end

-- Grid cell of a position given in thousandths of the zone map.
function Logic.Cell(x, y)
	return math.min(math.floor(x * GRID / 1000), GRID - 1), math.min(math.floor(y * GRID / 1000), GRID - 1)
end

-- Report: S1;<map>;<x>;<y>;<layer>;<level>;<rate>;<tagged>;<free x10>;<kills>;<faction A|H>
-- x and y in thousandths of the zone map; layer, tagged and free are "-" when unknown.
function Logic.EncodeReport(report)
	local text = table.concat({
		"S" .. PROTOCOL,
		tostring(report.mapID),
		tostring(report.x),
		tostring(report.y),
		report.layer or "-",
		tostring(report.level),
		tostring(report.rate),
		report.tapped and tostring(report.tapped) or "-",
		report.free and tostring(report.free) or "-",
		tostring(report.kills),
	}, ";")
	if report.faction then
		text = text .. ";" .. report.faction
	end
	return text
end

function Logic.DecodeReport(text)
	if type(text) ~= "string" then
		return nil
	end
	local version, mapID, x, y, layer, level, rate, tapped, free, kills, rest =
		text:match("^S(%d+);(%d+);(%d+);(%d+);([%d%-]+);(%d+);(%d+);([%d%-]+);([%d%-]+);(%d+)(.*)$")
	if version ~= PROTOCOL then
		return nil
	end
	local faction = rest:match("^;([AH])$")
	if rest ~= "" and not faction then
		return nil
	end
	local report = {
		mapID = tonumber(mapID),
		x = tonumber(x),
		y = tonumber(y),
		layer = layer ~= "-" and layer or nil,
		level = tonumber(level),
		rate = tonumber(rate),
		tapped = tonumber(tapped),
		free = tonumber(free),
		kills = tonumber(kills),
		faction = faction,
	}
	if report.layer and not report.layer:match("^%d+%-%d+$") then
		return nil
	end
	if (tapped ~= "-" and not report.tapped) or (free ~= "-" and not report.free) then
		return nil
	end
	if report.x > 999 or report.y > 999 or report.level < 1 or report.level > 100 or report.rate < 1 or report.rate > MAX_RATE
		or (report.tapped and report.tapped > 100) or (report.free and report.free > 999) or report.kills < MIN_KILLS then
		return nil
	end
	return report
end

-- One report per sender: a newer one replaces the older.
function Logic.AddReport(store, sender, report, now)
	report.at = now
	store[sender] = report
end

function Logic.ExpireReports(store, now)
	for sender, report in pairs(store) do
		if now - report.at > REPORT_TTL then
			store[sender] = nil
		end
	end
end

local function median(list)
	if #list == 0 then
		return nil
	end
	table.sort(list)
	local middle = math.floor((#list + 1) / 2)
	if #list % 2 == 1 then
		return list[middle]
	end
	return math.floor((list[middle] + list[middle + 1]) / 2 + 0.5)
end

Logic.Median = median

-- The farming spot: kills of the window that lie near their median position, averaged.
-- A stray kill on the road is left out; kills scattered over the zone give no spot.
-- Returns x, y in thousandths of the zone map and the number of kills at the spot.
function Logic.SpotPosition(meter)
	local xs, ys, placed = {}, {}, {}
	for _, gain in ipairs(meter.gains) do
		if gain.x and gain.y then
			xs[#xs + 1], ys[#ys + 1] = gain.x, gain.y
			placed[#placed + 1] = gain
		end
	end
	if #placed < MIN_KILLS then
		return nil
	end
	local mx, my = median(xs), median(ys)
	local sx, sy, count = 0, 0, 0
	for _, gain in ipairs(placed) do
		local dx, dy = gain.x - mx, gain.y - my
		if dx * dx + dy * dy <= SPOT_RADIUS * SPOT_RADIUS then
			sx, sy, count = sx + gain.x, sy + gain.y, count + 1
		end
	end
	if count < MIN_KILLS then
		return nil
	end
	return math.floor(sx / count + 0.5), math.floor(sy / count + 0.5), count
end

function Logic.NearSpot(x, y, spotX, spotY)
	local dx, dy = x - spotX, y - spotY
	return dx * dx + dy * dy <= SPOT_RADIUS * SPOT_RADIUS
end

-- Spots for a viewer: reports near the viewer's level grouped by map, cell and layer,
-- best experience rate first. mapFilter limits the result to one zone map.
function Logic.BuildSpots(store, viewer, now, mapFilter)
	local groups, list = {}, {}
	for sender, report in pairs(store) do
		if now - report.at <= REPORT_TTL and math.abs(report.level - viewer.level) <= LEVEL_RANGE
			and (not mapFilter or report.mapID == mapFilter) then
			local cx, cy = Logic.Cell(report.x, report.y)
			local key = report.mapID .. ":" .. cx .. ":" .. cy .. ":" .. (report.layer or "-")
			local group = groups[key]
			if not group then
				group = { key = key, mapID = report.mapID, layer = report.layer, rates = {}, tagged = {}, free = 0, freeCount = 0, x = 0, y = 0, count = 0, newest = report.at }
				groups[key] = group
				list[#list + 1] = group
			end
			group.count = group.count + 1
			group.rates[#group.rates + 1] = report.rate
			if report.tapped then
				group.tagged[#group.tagged + 1] = report.tapped
			end
			if report.free then
				group.free = group.free + report.free
				group.freeCount = group.freeCount + 1
			end
			group.x = group.x + report.x
			group.y = group.y + report.y
			group.newest = math.max(group.newest, report.at)
			if sender == viewer.self then
				group.mine = true
			end
		end
	end
	local spots = {}
	for _, group in ipairs(list) do
		local layerState = "unknown"
		if viewer.layer and group.layer then
			layerState = viewer.layer == group.layer and "same" or "other"
		end
		spots[#spots + 1] = {
			key = group.key,
			mapID = group.mapID,
			x = group.x / group.count / 1000,
			y = group.y / group.count / 1000,
			rate = median(group.rates),
			tapped = median(group.tagged),
			free = group.freeCount > 0 and group.free / group.freeCount / 10 or nil,
			count = group.count,
			age = now - group.newest,
			layerState = layerState,
			mine = group.mine or false,
		}
	end
	table.sort(spots, function(a, b)
		if a.rate ~= b.rate then
			return a.rate > b.rate
		end
		local ta, tb = a.tapped or 101, b.tapped or 101
		if ta ~= tb then
			return ta < tb
		end
		return a.key < b.key
	end)
	return spots
end
