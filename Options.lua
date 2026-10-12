-- Settings panel built with AceConfig.
local ADDON_NAME, ns = ...
local L = ns.L

local function getter(key)
	return function()
		return ns.db.profile[key]
	end
end

local function setter(key)
	return function(_, value)
		ns.db.profile[key] = value
	end
end

function ns.BuildOptions()
	return {
		type = "group",
		name = L["TITLE"],
		args = {
			share = {
				order = 1,
				type = "toggle",
				name = L["OPT_SHARE"],
				desc = L["OPT_SHARE_DESC"],
				get = getter("share"),
				set = setter("share"),
				width = "full",
			},
			mapPins = {
				order = 2,
				type = "toggle",
				name = L["OPT_PINS"],
				get = getter("mapPins"),
				set = function(_, value)
					ns.SetMapPins(value)
				end,
				width = "full",
			},
			minimap = {
				order = 3,
				type = "toggle",
				name = L["OPT_MINIMAP"],
				get = function()
					return not ns.db.profile.minimap.hide
				end,
				set = function(_, value)
					ns.db.profile.minimap.hide = not value
					local icon = LibStub("LibDBIcon-1.0")
					if value then
						icon:Show(ADDON_NAME)
					else
						icon:Hide(ADDON_NAME)
					end
				end,
				width = "full",
			},
			debug = {
				order = 4,
				type = "toggle",
				name = L["OPT_DEBUG"],
				get = getter("debug"),
				set = setter("debug"),
				width = "full",
			},
		},
	}
end
