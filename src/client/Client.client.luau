--!strict
-- Client bootstrap: the 2D map, HUD, sheets and panels, all fed by ClientState. The client only sends intents.
--
-- Taps: your army -> pick it up; then a province -> route preview + Go. Any other province -> its sheet.
-- Someone else's army -> the sheet of the province it stands in. Empty space -> close everything.
-- While a Primordial power waits for a target, every tap goes to the power instead.

local Client = script.Parent
local ArmySheet = require(Client.UI.ArmySheet)
local ClientState = require(Client.ClientState)
local Hud = require(Client.UI.Hud)
local Intents = require(Client.Intents)
local MapRenderer = require(Client.MapRenderer)
local MapView = require(Client.MapView)
local Nations = require(Client.UI.Nations)
local Offers = require(Client.UI.Offers)
local Powers = require(Client.UI.Powers)
local ProfileState = require(Client.ProfileState)
local ProvinceSheet = require(Client.UI.ProvinceSheet)
local Relations = require(Client.Relations)
local Results = require(Client.UI.Results)

local selectedArmy: number? = nil

local function clearArmy()
	selectedArmy = nil
	MapRenderer.selectArmy(nil)
	MapRenderer.showRoute(nil, nil)
	ArmySheet.show(nil)
end

local function selectProvince(id: number?)
	clearArmy()
	MapRenderer.select(id)
	ProvinceSheet.show(id)
end

local function selectArmy(id: number)
	ProvinceSheet.show(nil)
	MapRenderer.select(nil)
	selectedArmy = id
	MapRenderer.selectArmy(id)
	local army = ClientState.army(id)
	if army and army.dest ~= 0 then
		MapRenderer.showRoute(army.location, Relations.path(army.owner, army.location, army.dest))
	else
		MapRenderer.showRoute(nil, nil)
	end
	ArmySheet.show(id)
end

-- A destination for the selected army: preview the route; the player confirms with Go.
local function chooseDestination(provinceId: number)
	local armyId = selectedArmy
	local army = if armyId then ClientState.army(armyId) else nil
	if armyId == nil or army == nil then
		clearArmy()
		return
	end
	local path = Relations.path(army.owner, army.location, provinceId)
	if path == nil then
		Hud.toast("🚫 Can't get there")
		return
	end
	MapRenderer.showRoute(army.location, path, true)
	ArmySheet.show(armyId, provinceId, path)
end

local function onTap(kind: "Army" | "Province" | nil, id: number?)
	if Powers.targeting() then
		Powers.tap(kind, id)
		return
	end
	local me = ClientState.myNation()
	if kind == "Army" and id then
		local army = ClientState.army(id)
		if army and army.owner == me and me ~= 0 then
			if selectedArmy == id then
				clearArmy()
			else
				selectArmy(id)
			end
			return
		end
		kind, id = "Province", if army then army.location else nil
	end
	if kind == "Province" and id then
		if selectedArmy then
			chooseDestination(id)
		else
			selectProvince(id)
		end
		return
	end
	selectProvince(nil)
end

local function centreOnCapital()
	local map = ClientState.map()
	local me = ClientState.nation(ClientState.myNation())
	if map and me then
		MapView.centreOn(MapRenderer.centerOf(me.capital), true)
		selectProvince(me.capital)
	end
end

-- Listeners first (in draw order), then start listening to the server.
MapRenderer.init()
Hud.init(centreOnCapital, Nations.toggle)
ProvinceSheet.init(function()
	MapRenderer.select(nil)
end, selectArmy)
ArmySheet.init(function(armyId: number, dest: number)
	Intents.move(armyId, dest)
	Hud.toast("➜ On the march")
	clearArmy()
end, clearArmy)
Offers.init()
Powers.init(Hud.toast, function()
	selectProvince(nil) -- the power picker replaces any open sheet
end)
Nations.init()
Results.init(function()
	selectProvince(nil)
end)
Intents.init(Hud.toast)
MapView.init(function(screenPos: Vector2)
	onTap(MapRenderer.pick(screenPos))
end)
ClientState.onReset(function()
	selectedArmy = nil
end)
ProfileState.init()
ClientState.init()
