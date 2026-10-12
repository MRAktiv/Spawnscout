-- Startup: saved settings, options panel, minimap button and slash commands.
local ADDON_NAME, ns = ...
local addon, L = ns.addon, ns.L

local ICON = "Interface\\AddOns\\Spawnscout\\Media\\icon"

-- The settings panel opener is restricted in some states; the Ace dialog is the fallback.
function ns.OpenOptions()
	if Settings and Settings.OpenToCategory and ns.optionsCategoryID then
		if pcall(Settings.OpenToCategory, ns.optionsCategoryID) then
			return
		end
	end
	LibStub("AceConfigDialog-3.0"):Open(ADDON_NAME)
end

-- World map dots on or off; the options toggle and the minimap button share it.
function ns.SetMapPins(value)
	ns.db.profile.mapPins = value
	ns.MapPins:Refresh()
	LibStub("AceConfigRegistry-3.0"):NotifyChange(ADDON_NAME)
end

local function tooltip(tip)
	tip:AddLine(L["TITLE"])
	tip:AddLine(ns.UI:HeaderLine(), 1, 1, 1)
	tip:AddLine(L["SPOTS_COUNT"]:format(#ns.Net:Spots()), 1, 1, 1)
	tip:AddLine(" ")
	tip:AddLine(L["TOOLTIP_LEFT"], 0.6, 0.6, 0.6)
	tip:AddLine(ns.db.profile.mapPins and L["TOOLTIP_SHIFT_HIDE"] or L["TOOLTIP_SHIFT_SHOW"], 0.6, 0.6, 0.6)
	tip:AddLine(L["TOOLTIP_RIGHT"], 0.6, 0.6, 0.6)
end

function addon:OnInitialize()
	ns.db = LibStub("AceDB-3.0"):New("SpawnscoutDB", ns.DEFAULTS, true)

	LibStub("AceConfig-3.0"):RegisterOptionsTable(ADDON_NAME, ns.BuildOptions)
	local _, categoryID = LibStub("AceConfigDialog-3.0"):AddToBlizOptions(ADDON_NAME, L["TITLE"])
	ns.optionsCategoryID = categoryID

	local launcher = LibStub("LibDataBroker-1.1"):NewDataObject(ADDON_NAME, {
		type = "launcher",
		text = L["TITLE"],
		icon = ICON,
		OnClick = function(_, button)
			if button == "RightButton" then
				ns.OpenOptions()
			elseif IsShiftKeyDown() then
				ns.SetMapPins(not ns.db.profile.mapPins)
				ns.Print(ns.db.profile.mapPins and L["PINS_SHOWN"] or L["PINS_HIDDEN"])
			else
				ns.UI:Toggle()
			end
		end,
		OnTooltipShow = tooltip,
	})
	LibStub("LibDBIcon-1.0"):Register(ADDON_NAME, launcher, ns.db.profile.minimap)

	self:RegisterChatCommand("spawnscout", "OnSlash")
	self:RegisterChatCommand("sscout", "OnSlash")
end

function addon:OnEnable()
	if not ns.db.profile.firstRunShown then
		ns.db.profile.firstRunShown = true
		ns.Print(L["FIRST_RUN"])
	end
end

function addon:OnSlash(input)
	local command = (input or ""):lower():match("^%s*(%S*)")
	if command == "diag" then
		ns.Diag:Run()
	elseif command == "options" or command == "config" then
		ns.OpenOptions()
	elseif command == "debug" then
		ns.db.profile.debug = not ns.db.profile.debug
		ns.Print("debug", tostring(ns.db.profile.debug))
	else
		ns.UI:Toggle()
	end
end
