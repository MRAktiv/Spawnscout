-- "Where it is free" window: own measurement on top, then the best spots for the player's level.
local _, ns = ...
local addon, Logic, L = ns.addon, ns.Logic, ns.L

local UI = addon:NewModule("UI", "AceEvent-3.0")
ns.UI = UI

local WIDTH = 640
local ROWS = 10
local ROW_HEIGHT = 20
local GREY = "|cff9d9d9d"
-- "||" is how WoW text shows a single pipe.
local SEPARATOR = " || "

function UI:OnEnable()
	self:RegisterMessage("SPAWNSCOUT_SPOTS_CHANGED", "Refresh")
	self:RegisterMessage("SPAWNSCOUT_LAYER_CHANGED", "Refresh")
end

local function colorize(text, tapped)
	local r, g, b = ns.CrowdColor(tapped)
	return string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), text)
end

function UI:RateText(rate)
	local text = L["RATE"]:format(ns.FormatNumber(rate))
	local maxXP = UnitXPMax("player")
	if ns.Usable(maxXP) and maxXP and maxXP > 0 then
		text = text .. " " .. L["RATE_LEVEL"]:format(math.floor(rate * 100 / maxXP + 0.5))
	end
	return text
end

function UI:TaggedText(tapped)
	if tapped then
		return colorize(L["TAGGED"]:format(tapped), tapped)
	end
	return colorize(L["TAGGED_UNKNOWN"], nil)
end

-- One line per spot; kept apart from frames so the content can be tested.
function UI:SpotLine(spot)
	local parts = {
		string.format("%s %.0f, %.0f", ns.MapName(spot.mapID), spot.x * 100, spot.y * 100),
		self:RateText(spot.rate),
		self:TaggedText(spot.tapped),
		L["REPORTS"]:format(spot.count),
		L["LAYER_" .. spot.layerState],
		L["AGE"]:format(math.floor(spot.age / 60)),
	}
	if spot.mine then
		parts[#parts + 1] = L["YOU_HERE"]
	end
	return table.concat(parts, SEPARATOR)
end

function UI:SpotTooltip(spot)
	local lines = {
		string.format("%s %.0f, %.0f", ns.MapName(spot.mapID), spot.x * 100, spot.y * 100),
		self:RateText(spot.rate),
		self:TaggedText(spot.tapped),
	}
	if spot.free then
		lines[#lines + 1] = L["FREE"]:format(spot.free)
	end
	lines[#lines + 1] = L["REPORTS"]:format(spot.count)
	lines[#lines + 1] = L["LAYER_" .. spot.layerState]
	lines[#lines + 1] = L["AGE"]:format(math.floor(spot.age / 60))
	if spot.mine then
		lines[#lines + 1] = L["YOU_HERE"]
	end
	lines[#lines + 1] = GREY .. L["CLICK_WAYPOINT"] .. "|r"
	return lines
end

function UI:HeaderLine()
	local snapshot = ns.Measure:Snapshot()
	local parts = { L["ME"]:format(UnitLevel("player")), ns.Layer:StatusText() }
	if snapshot.rate then
		parts[#parts + 1] = self:RateText(snapshot.rate)
		parts[#parts + 1] = self:TaggedText(snapshot.tapped)
	end
	return table.concat(parts, SEPARATOR)
end

function UI:Create()
	local frame = CreateFrame("Frame", "SpawnscoutFrame", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(WIDTH, 120 + ROWS * 22)
	frame:SetPoint("CENTER", 0, 100)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	tinsert(UISpecialFrames, "SpawnscoutFrame")
	frame.TitleText:SetText(L["WINDOW_TITLE"])

	frame.header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.header:SetPoint("TOPLEFT", 16, -32)
	frame.header:SetWidth(WIDTH - 32)
	frame.header:SetJustifyH("LEFT")

	frame.rows = {}
	for index = 1, ROWS do
		local row = CreateFrame("Button", nil, frame)
		row:SetSize(WIDTH - 32, ROW_HEIGHT)
		row:SetPoint("TOPLEFT", 16, -56 - (index - 1) * 22)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.text:SetAllPoints()
		row.text:SetJustifyH("LEFT")
		row:SetScript("OnClick", function(button)
			if button.spot then
				ns.SetWaypoint(button.spot.mapID, button.spot.x, button.spot.y)
			end
		end)
		frame.rows[index] = row
	end

	frame.note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.note:SetPoint("BOTTOMLEFT", 16, 12)
	frame.note:SetWidth(WIDTH - 32)
	frame.note:SetJustifyH("LEFT")

	-- Crowding needs enemy nameplates; the hint and the button show only while they are off.
	frame.platesHint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.platesHint:SetPoint("BOTTOMLEFT", 16, 40)
	frame.platesHint:SetWidth(WIDTH - 150)
	frame.platesHint:SetJustifyH("LEFT")
	frame.platesHint:SetText(L["PLATES_OFF"])
	frame.platesButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.platesButton:SetSize(110, 22)
	frame.platesButton:SetPoint("BOTTOMRIGHT", -16, 34)
	frame.platesButton:SetText(L["PLATES_ON"])
	frame.platesButton:SetScript("OnClick", function()
		if ns.ShowEnemyPlates() then
			UI:Refresh()
		end
	end)
	self.frame = frame
end

function UI:Refresh()
	local frame = self.frame
	if not frame or not frame:IsShown() then
		return
	end
	frame.header:SetText(self:HeaderLine())
	local spots = ns.Net:Spots()
	for index, row in ipairs(frame.rows) do
		local spot = spots[index]
		row.spot = spot
		if spot then
			row.text:SetText(self:SpotLine(spot))
			row:SetHeight(ROW_HEIGHT)
			row:Show()
		elseif index == 1 then
			-- The no-data sentence needs two lines; the rows below it are hidden.
			row.text:SetText(GREY .. L["NO_SPOTS"] .. "|r")
			row:SetHeight(ROW_HEIGHT * 2)
			row:Show()
		else
			row:Hide()
		end
	end
	frame.note:SetText(L["NOTE"]:format(Logic.LEVEL_RANGE, Logic.REPORT_TTL / 60) .. " " .. (ns.db.profile.share and L["NOTE_SHARE"] or L["NOTE_SHARE_OFF"]))
	local platesOff = not ns.EnemyPlatesShown()
	frame.platesHint:SetShown(platesOff)
	frame.platesButton:SetShown(platesOff)
end

function UI:Toggle()
	if not self.frame then
		self:Create()
	end
	if self.frame:IsShown() then
		self.frame:Hide()
	else
		self.frame:Show()
		self:Refresh()
	end
end
