--!strict
-- Client bootstrap: map, camera, HUD and province sheet, all fed by ClientState. The client only sends intents.

local Client = script.Parent
local CameraController = require(Client.CameraController)
local ClientState = require(Client.ClientState)
local Hud = require(Client.UI.Hud)
local Intents = require(Client.Intents)
local MapRenderer = require(Client.MapRenderer)
local ProvinceSheet = require(Client.UI.ProvinceSheet)

local function selectProvince(id: number?)
	MapRenderer.select(id)
	ProvinceSheet.show(id)
end

local function centreOnCapital()
	local map = ClientState.map()
	local me = ClientState.nation(ClientState.myNation())
	if map and me then
		CameraController.centreOn(MapRenderer.toWorld(map.provinces[me.capital].center), true)
		selectProvince(me.capital)
	end
end

-- Listeners first (in draw order), then start listening to the server.
MapRenderer.init()
Hud.init(centreOnCapital)
ProvinceSheet.init(function()
	MapRenderer.select(nil)
end)
Intents.init(Hud.toast)
CameraController.init(selectProvince)
ClientState.onReset(function()
	CameraController.showWholeMap()
end)
ClientState.init()
