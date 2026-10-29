--!strict
-- Client bootstrap: the 2D map, HUD, sheets and panels, all fed by ClientState. The client only sends intents.
--
-- Taps: your army -> pick it up; then a province -> route preview + Go, or one of your fleets -> walk to its coast and
-- Board. Your fleet -> pick it up; then a sea zone -> route preview + Sail, or a coastal province -> Land there.
-- Any other province -> its sheet. Someone else's army -> the sheet of the province it stands in; someone else's
-- fleet -> its sheet (no orders). Empty space or the water -> close everything.
-- While a Primordial power waits for a target, every tap goes to the power instead.
-- A long press (or right-click) on a province opens the ping wheel for your allies (UI/Pings).

-- Roblox's own player list would open over the HUD's right end on PC; the game has its own (🌍).
pcall(function()
	game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

local Client = script.Parent
local ArmySheet = require(Client.UI.ArmySheet)
local ClientState = require(Client.ClientState)
local Draft = require(Client.UI.Draft)
local Effects = require(Client.Effects)
local EventCard = require(Client.UI.EventCard)
local FleetSheet = require(Client.UI.FleetSheet)
local Hud = require(Client.UI.Hud)
local Insults = require(Client.UI.Insults)
local Intents = require(Client.Intents)
local LobbyState = require(Client.LobbyState)
local MapRenderer = require(Client.MapRenderer)
local MapView = require(Client.MapView)
local MapVote = require(Client.UI.MapVote)
local Menu = require(Client.UI.Menu)
local Music = require(Client.Music)
local Nations = require(Client.UI.Nations)
local Offers = require(Client.UI.Offers)
local Pings = require(Client.UI.Pings)
local Powers = require(Client.UI.Powers)
local PrivateSettings = require(Client.UI.PrivateSettings)
local ProfileState = require(Client.ProfileState)
local ProvinceSheet = require(Client.UI.ProvinceSheet)
local Relations = require(Client.Relations)
local Results = require(Client.UI.Results)
local Sandbox = require(Client.UI.Sandbox)
local Sounds = require(Client.Sounds)
local Tutorial = require(Client.UI.Tutorial)
local Cosmetics = require(Client.Cosmetics)
local Emotes = require(Client.UI.Emotes)
local Shop = require(Client.UI.Shop)
local ShopState = require(Client.ShopState)
local Quests = require(Client.UI.Quests)
local QuestState = require(Client.QuestState)
local Ads = require(Client.Ads)
local Season = require(Client.UI.Season)
local SeasonState = require(Client.SeasonState)
local Trophies = require(Client.UI.Trophies)
local TrophyState = require(Client.TrophyState)

local selectedArmy: number? = nil
local selectedFleet: number? = nil

local function clearArmy()
	selectedArmy = nil
	MapRenderer.selectArmy(nil)
	MapRenderer.showRoute(nil, nil)
	ArmySheet.show(nil)
end

local function clearFleet()
	selectedFleet = nil
	MapRenderer.selectFleet(nil)
	MapRenderer.showSeaRoute(nil, nil)
	FleetSheet.show(nil)
end

local function selectProvince(id: number?)
	clearArmy()
	clearFleet()
	MapRenderer.select(id)
	ProvinceSheet.show(id)
end

local function selectArmy(id: number)
	ProvinceSheet.show(nil)
	MapRenderer.select(nil)
	clearFleet()
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

-- Your fleet, or someone else's to look at (no orders): its route if it is sailing, and its sheet.
local function selectFleet(id: number)
	ProvinceSheet.show(nil)
	MapRenderer.select(nil)
	clearArmy()
	selectedFleet = id
	MapRenderer.selectFleet(id)
	local fleet = ClientState.fleet(id)
	if fleet and fleet.next ~= 0 then
		local landAt = if fleet.landAt ~= 0 then fleet.landAt else nil
		MapRenderer.showSeaRoute(fleet.zone, Relations.sailPath(fleet.zone, fleet.dest), false, landAt)
	else
		MapRenderer.showSeaRoute(nil, nil)
	end
	FleetSheet.show(id)
end

-- The selected fleet, if it is yours to order.
local function myFleet()
	local fleet = if selectedFleet then ClientState.fleet(selectedFleet) else nil
	local me = ClientState.myNation()
	return if fleet and me ~= 0 and fleet.owner == me then fleet else nil
end

-- A sea zone for the selected fleet: preview the route; the player confirms with Sail.
local function chooseSail(zoneId: number)
	local fleet = myFleet()
	if fleet == nil then
		clearFleet()
		return
	end
	local path = Relations.sailPath(fleet.zone, zoneId)
	if path == nil then
		Hud.toast(Intents.text("NoPath"))
		return
	end
	MapRenderer.showSeaRoute(fleet.zone, path, true)
	FleetSheet.show(fleet.id, { kind = "Sail", zone = zoneId, path = path })
end

-- A coast for the selected fleet to land its men on: preview the route; the player confirms with Land. What the
-- server would refuse is said at once (no coast, nobody aboard, land the army may not enter).
local function chooseLanding(provinceId: number)
	local fleet = myFleet()
	if fleet == nil then
		clearFleet()
		return
	end
	local reason = if #Relations.shores(provinceId) == 0
		then "NoCoast"
		elseif fleet.men <= 0 then "NoTroops"
		elseif not Relations.canEnter(fleet.owner, provinceId) then "NoPath"
		else nil
	local path = if reason then nil else Relations.landingPath(fleet.zone, provinceId)
	if path == nil then
		Hud.toast(Intents.text(reason or "NoPath"))
		return
	end
	MapRenderer.showSeaRoute(fleet.zone, path, true, provinceId)
	FleetSheet.show(fleet.id, { kind = "Land", province = provinceId, path = path })
end

-- One of your fleets for the selected army: preview its march to the fleet's coast; the player confirms with Board.
local function chooseBoarding(fleetId: number)
	local armyId = selectedArmy
	local army = if armyId then ClientState.army(armyId) else nil
	local fleet = ClientState.fleet(fleetId)
	if armyId == nil or army == nil or fleet == nil then
		clearArmy()
		return
	end
	if Relations.room(fleet) <= 0 then
		Hud.toast(Intents.text("FleetFull"))
		return
	end
	local path = Relations.boardingPath(army, fleet)
	if path == nil then
		Hud.toast(Intents.text("NoPath"))
		return
	end
	MapRenderer.showRoute(army.location, path, true)
	ArmySheet.show(armyId, nil, nil, { fleet = fleetId, path = path })
end

-- Powers and the draft only target armies and provinces.
local function landKind(kind: MapRenderer.Pick?): ("Army" | "Province")?
	if kind == "Army" then
		return "Army"
	elseif kind == "Province" then
		return "Province"
	end
	return nil
end

local function onTap(kind: MapRenderer.Pick?, id: number?)
	if Draft.active() then -- the nation draft: a tap chooses a nation
		Draft.tap(landKind(kind), id)
		return
	end
	if Powers.targeting() then
		Powers.tap(landKind(kind), id)
		return
	end
	local me = ClientState.myNation()
	if kind == "Fleet" and id then
		local fleet = ClientState.fleet(id)
		if fleet and me ~= 0 and fleet.owner == me then
			if selectedArmy then
				chooseBoarding(id)
			elseif selectedFleet == id then
				clearFleet()
			else
				selectFleet(id)
			end
		elseif fleet and myFleet() then
			chooseSail(fleet.zone) -- someone else's fleet: sail to it
		elseif fleet then
			selectFleet(id)
		else
			selectProvince(nil)
		end
		return
	end
	if kind == "Zone" and id then
		if myFleet() then
			chooseSail(id)
		else
			selectProvince(nil) -- the water closes everything, as it always did
		end
		return
	end
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
		elseif myFleet() then
			chooseLanding(id)
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

-- A nation's row in the drawer: close the drawer and show that nation's capital (or, once it lost it, one of its
-- provinces) with its province sheet, whose diplomacy buttons are the nation's.
local function showNation(nationId: number)
	local snap = ClientState.snapshot()
	local nation = ClientState.nation(nationId)
	if snap == nil or nation == nil then
		return
	end
	local where: number? = nil
	for _, record in snap.provinces do
		if record.owner == nationId and (where == nil or record.id == nation.capital) then
			where = record.id
		end
	end
	if where then
		Nations.toggle()
		MapView.centreOn(MapRenderer.centerOf(where), true)
		selectProvince(where)
	end
end

-- Listeners first (in draw order), then start listening to the server.
MapRenderer.init()
Hud.init(centreOnCapital, Nations.toggle, function()
	Shop.toggle()
end)
ProvinceSheet.init(function()
	MapRenderer.select(nil)
end, selectArmy)
ArmySheet.init(
	function(armyId: number, dest: number)
		Intents.move(armyId, dest)
		Hud.toast("➜ On the march")
		clearArmy()
	end,
	clearArmy,
	function(armyId: number, fleetId: number)
		Intents.embark(armyId, fleetId)
		Hud.toast("⛵ Off to board")
		clearArmy()
	end
)
FleetSheet.init(
	function(fleetId: number, order: FleetSheet.Order)
		if order.kind == "Sail" then
			Intents.sail(fleetId, order.zone)
			Hud.toast("⛵ Setting sail")
		else
			Intents.land(fleetId, order.province)
			Hud.toast("⛵ Sailing to land")
		end
		clearFleet()
	end,
	clearFleet,
	function(keeper: number?)
		if keeper then
			selectFleet(keeper) -- it merged into another fleet of yours: follow it
		else
			clearFleet()
		end
	end
)
Offers.init()
Insults.init()
EventCard.init(Hud.toast)
Powers.init(Hud.toast, function()
	selectProvince(nil) -- the power picker replaces any open sheet
end)
Sandbox.init(Hud.toast, function()
	selectProvince(nil) -- a new nation (or none): the open sheets were for the old one
end)
Nations.init(Quests.open, Quests.shortButtonText, showNation)
Tutorial.init(function()
	return selectedArmy
end)
Results.init(function()
	selectProvince(nil)
end)
Intents.init(Hud.toast)
MapView.init(function(screenPos: Vector2)
	onTap(MapRenderer.pick(screenPos))
end)
-- A long press (or right-click) on a province, or an army standing in one, opens the ping wheel there. While the
-- draft or a power waits for a target, it is a tap like any other.
Pings.init(Hud.toast)
MapView.onLongPress(function(screenPos: Vector2)
	local kind, id = MapRenderer.pick(screenPos)
	if Draft.active() or Powers.targeting() then
		onTap(kind, id)
		return
	end
	if kind == "Army" and id then
		local army = ClientState.army(id)
		kind, id = "Province", if army then army.location else nil
	end
	if kind == "Province" and id then
		Pings.open(id, screenPos)
	end
end)
MapVote.init()
PrivateSettings.init()
Draft.init()
Menu.init() -- the start menu: above every other screen while the server shows it
ClientState.onReset(function()
	selectedArmy = nil
	selectedFleet = nil
end)
Cosmetics.init()
Shop.init(Hud.toast)
Quests.init()
Season.init(Hud.toast)
Trophies.init()
Emotes.init()
Effects.init() -- after MapRenderer: draws on the canvas it builds
Sounds.init() -- after every other UI: hooks a tap sound onto their buttons
Music.init() -- follows the menu, the Lobby and the match from here on
Ads.init() -- the notification opt-in prompt after the first finished match
ProfileState.init()
ShopState.init()
QuestState.init()
SeasonState.init()
TrophyState.init()
LobbyState.init()
ClientState.init()
Intents.signal("Loaded") -- analytics: the screens are built (onboarding "lobby_loaded")
