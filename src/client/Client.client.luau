--!strict
-- Client bootstrap: the 2D map, HUD, sheets and panels, all fed by ClientState. The client only sends intents.
--
-- Taps: your army -> pick it up; then a province -> route preview + Go. Any other province -> its sheet.
-- Someone else's army -> the sheet of the province it stands in. Empty space -> close everything.
-- While a Primordial power waits for a target, every tap goes to the power instead.

-- Roblox's own player list would open over the HUD's right end on PC; the game has its own (🌍).
pcall(function()
	game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

local Client = script.Parent
local ArmySheet = require(Client.UI.ArmySheet)
local ClientState = require(Client.ClientState)
local Draft = require(Client.UI.Draft)
local Effects = require(Client.Effects)
local Hud = require(Client.UI.Hud)
local Insults = require(Client.UI.Insults)
local Intents = require(Client.Intents)
local LobbyState = require(Client.LobbyState)
local MapRenderer = require(Client.MapRenderer)
local MapView = require(Client.MapView)
local MapVote = require(Client.UI.MapVote)
local Nations = require(Client.UI.Nations)
local Offers = require(Client.UI.Offers)
local Powers = require(Client.UI.Powers)
local PrivateSettings = require(Client.UI.PrivateSettings)
local ProfileState = require(Client.ProfileState)
local ProvinceSheet = require(Client.UI.ProvinceSheet)
local Relations = require(Client.Relations)
local Results = require(Client.UI.Results)
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

local function clearArmy()
	selectedArmy = nil
	MapRenderer.selectArmy(nil)
	MapRenderer.showRoute(nil, nil)
	ArmySheet.show(nil)
end

local function selectProvince(id: number?)
	clearArmy()
	if Insults.isOpen() then
		Insults.close()
	end
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
	if Draft.active() then -- the nation draft: a tap chooses a nation
		Draft.tap(kind, id)
		return
	end
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
ArmySheet.init(function(armyId: number, dest: number)
	Intents.move(armyId, dest)
	Hud.toast("➜ On the march")
	clearArmy()
end, clearArmy)
Offers.init()
Insults.init(function()
	selectProvince(nil) -- the insult picker replaces the province sheet it was opened from
end)
Powers.init(Hud.toast, function()
	selectProvince(nil) -- the power picker replaces any open sheet
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
MapVote.init()
PrivateSettings.init()
Draft.init()
ClientState.onReset(function()
	selectedArmy = nil
end)
Cosmetics.init()
Shop.init(Hud.toast)
Quests.init()
Season.init(Hud.toast)
Trophies.init()
Emotes.init()
Effects.init() -- after MapRenderer: draws on the canvas it builds
Sounds.init() -- after every other UI: hooks a tap sound onto their buttons
Ads.init() -- the notification opt-in prompt after the first finished match
ProfileState.init()
ShopState.init()
QuestState.init()
SeasonState.init()
TrophyState.init()
LobbyState.init()
ClientState.init()
Intents.signal("Loaded") -- analytics: the screens are built (onboarding "lobby_loaded")
