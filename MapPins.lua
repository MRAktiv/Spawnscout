-- World map overlay: one dot per reported spot on the zone map being viewed.
local _, ns = ...
local addon = ns.addon

local MapPins = addon:NewModule("MapPins", "AceEvent-3.0")
ns.MapPins = MapPins

local TEMPLATE = "SpawnscoutPinTemplate"

MapPins.shown = 0

-- The map canvas mixins come with Blizzard_MapCanvas; without them the overlay stays off.
if MapCanvasDataProviderMixin and MapCanvasPinMixin then
	SpawnscoutDataProviderMixin = CreateFromMixins(MapCanvasDataProviderMixin)

	function SpawnscoutDataProviderMixin:RemoveAllData()
		self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
	end

	function SpawnscoutDataProviderMixin:RefreshAllData()
		self:RemoveAllData()
		local map = self:GetMap()
		local count = 0
		if ns.db.profile.mapPins then
			for _, spot in ipairs(ns.Net:Spots(map:GetMapID())) do
				map:AcquirePin(TEMPLATE, spot)
				count = count + 1
			end
		end
		MapPins.shown = count
	end

	SpawnscoutPinMixin = CreateFromMixins(MapCanvasPinMixin)

	-- Acquiring a pin calls the protected SetPassThroughButtons; from an addon in combat it is blocked
	-- and breaks the map (HereBeDragons stubs it the same way). Right click on a dot no longer zooms out.
	SpawnscoutPinMixin.SetPassThroughButtons = function() end

	function SpawnscoutPinMixin:OnLoad()
		self:UseFrameLevelType("PIN_FRAME_LEVEL_DIG_SITE")
		self:SetScalingLimits(1, 0.8, 1.4)
	end

	-- Spots in another layer are dimmed: the player cannot reach that world without regrouping.
	function SpawnscoutPinMixin:OnAcquired(spot)
		self.spot = spot
		self:SetPosition(spot.x, spot.y)
		local r, g, b = ns.CrowdColor(spot.tapped)
		self.Dot:SetColorTexture(r, g, b, spot.layerState == "other" and 0.45 or 1)
	end

	function SpawnscoutPinMixin:OnMouseEnter()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		for index, line in ipairs(ns.UI:SpotTooltip(self.spot)) do
			if index == 1 then
				GameTooltip:SetText(line)
			else
				GameTooltip:AddLine(line, 1, 1, 1)
			end
		end
		GameTooltip:Show()
	end

	function SpawnscoutPinMixin:OnMouseLeave()
		GameTooltip:Hide()
	end

	function SpawnscoutPinMixin:OnClick(button)
		if button == "LeftButton" and self.spot then
			ns.SetWaypoint(self.spot.mapID, self.spot.x, self.spot.y)
		end
	end
end

function MapPins:OnEnable()
	self:RegisterMessage("SPAWNSCOUT_SPOTS_CHANGED", "Refresh")
	self:Attach()
end

function MapPins:Attach()
	if self.provider or not SpawnscoutDataProviderMixin or not WorldMapFrame or not WorldMapFrame.AddDataProvider then
		return
	end
	self.provider = CreateFromMixins(SpawnscoutDataProviderMixin)
	WorldMapFrame:AddDataProvider(self.provider)
end

function MapPins:Refresh()
	if self.provider and WorldMapFrame:IsShown() then
		self.provider:RefreshAllData()
	end
end
