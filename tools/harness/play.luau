--!nocheck
-- Plays scripted scenarios against the real server and client scripts (built place), headlessly.
--
--   mkdir -p build && rojo build -o build/game.rbxlx
--   lune run tools/harness/play smoke          # one scenario
--   lune run tools/harness/play all            # every scenario
--   MAP=earth lune run tools/harness/play smoke  # on another map (default: Config.DefaultMap)
--
-- Screenshots go to tools/harness/out/<scenario>/NN_name.png (rendered by render_scene.py).
-- A scenario fails on any script error, any warn(), any table Roblox would mangle over the network,
-- or a failed expectation.

local fs = require("@lune/fs")
local process = require("@lune/process")

local Config = require("../../src/shared/Config")
local Emulator = require("./Emulator")
local MapGrid = require("../../src/shared/MapGrid")
local Scene = require("./Scene")

local OUT = "tools/harness/out"
local LOBBY_SCENARIOS = { lobby = true, shop = true, quests = true, analytics = true, private = true, themes = true } -- these run the Lobby; the rest boot with SkipLobby
local PRIVATE_OWNER = 5001 -- the private scenario's server owner (Workspace "PrivateServerOwner")
local TUTORIAL_SCENARIOS = { tutorial = true } -- these boot a tutorial server (Workspace "Tutorial")
local scenarioName = process.args[1] or "smoke"
local shotCount = 0
local shotDir = OUT .. "/" .. scenarioName

local H = {}

function H.shot(client, name: string)
	shotCount += 1
	local base = string.format("%s/%02d_%s", shotDir, shotCount, name)
	Scene.save(client, base .. ".json")
	local r = process.exec("python3", { "tools/harness/render_scene.py", base .. ".json", base .. ".png" })
	if not r.ok then
		error("render failed: " .. r.stderr)
	end
	if process.env.KEEP_SCENE == nil then
		fs.removeFile(base .. ".json")
		for _, entry in fs.readDir(shotDir) do
			if string.find(entry, "%.rgba$") then
				fs.removeFile(shotDir .. "/" .. entry)
			end
		end
	end
	print("  📸 " .. base .. ".png")
end

function H.expect(cond, message: string)
	if not cond then
		error("EXPECTATION FAILED: " .. message, 2)
	end
	print("  ✓ " .. message)
end

-- A server-side module's table, e.g. H.server("Services.MatchService").
function H.server(path: string)
	local node = Emulator.server.dm:GetService("ServerScriptService").Server
	for _, name in string.split(path, ".") do
		node = node:FindFirstChild(name)
	end
	return Emulator.server.modules[node]
end

-- The client's copy of a client module, e.g. H.client(c, "ClientState").
function H.client(client, path: string)
	local node = client.localPlayer.PlayerScripts.Client
	for _, name in string.split(path, ".") do
		node = node:FindFirstChild(name)
	end
	return client.modules[node]
end

function H.state()
	return H.server("Services.MatchService").state()
end

function H.myNation(client)
	return H.client(client, "ClientState").myNation()
end

-- A province's centre in map pixels (the 2D map's coordinates).
function H.provinceMap(client, provinceId: number)
	return H.client(client, "MapRenderer").centerOf(provinceId)
end

-- Centre the view on a province, wait for the camera to settle, and tap a pixel of it on screen, away from the
-- tokens standing at its centre.
function H.tapProvince(client, provinceId: number, closeUp: boolean?)
	local MapView = H.client(client, "MapView")
	MapView.centreOn(H.provinceMap(client, provinceId), closeUp ~= false)
	Emulator.run(1.5)
	local map = H.client(client, "ClientState").map()
	local grid = MapGrid.decode(map)
	local c = H.provinceMap(client, provinceId)
	local spot = c
	for r = 12, 3, -1 do
		local p = c + Emulator.roblox.Vector2.new(0, r)
		if MapGrid.at(grid, p.X, p.Y) == provinceId then
			spot = p
			break
		end
	end
	local screen = MapView.toScreen(spot)
	Emulator.tapScreen(client, screen.X, screen.Y)
	Emulator.run(0.3)
end

local scenarios = {}

-- Phase 1: join, look around, develop, build, recruit, earn income.
function scenarios.smoke()
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	Emulator.run(2)
	H.shot(alice, "joined")
	local me = H.myNation(alice)
	H.expect(me == 1, "Alice is seated as nation 1")
	local state = H.state()
	local nation = state.nations[me]
	nation.gold = 500 -- enough to try everything

	Emulator.press(alice, "⭐")
	Emulator.run(1)
	H.shot(alice, "capital")
	local capital = state.provinces[nation.capital]
	local dev0 = capital.development
	Emulator.press(alice, "Develop")
	Emulator.run(1.5)
	H.expect(capital.development == dev0 + 1, "Develop raised the capital's development")
	Emulator.press(alice, "Farm")
	Emulator.run(1.5)
	H.expect(capital.building == "Farm", "Farm was built")
	Emulator.press(alice, "Regiment")
	Emulator.run(1.5)
	local armies = 0
	for _, a in state.armies do
		if a.owner == me then
			armies += 1
		end
	end
	H.expect(armies == 1, "Recruit created an army")
	H.shot(alice, "built")

	-- tap a foreign province on the 2D map
	local foreign
	for id, p in state.provinces do
		if p.owner ~= nil and p.owner ~= me then
			foreign = id
			break
		end
	end
	Emulator.press(alice, "✕")
	Emulator.run(0.5)
	local ClientState = H.client(alice, "ClientState")
	H.tapProvince(alice, foreign)
	local owner = ClientState.nation(state.provinces[foreign].owner)
	H.expect(Emulator.findText(alice, owner.name) ~= nil, "Tapping a foreign province shows its owner")
	H.shot(alice, "foreign")

	local gold0 = nation.gold
	Emulator.run(30)
	H.expect(nation.gold > gold0, "Income arrives every month")
	H.expect(ClientState.nation(me).gold == nation.gold, "The client's gold matches the server")

	-- Studio test switches (docs/STUDIO.md): set on Workspace, applied once on the next tick, then removed
	local workspace = Emulator.server.dm:GetService("Workspace")
	workspace:SetAttribute("DevTick", 179)
	workspace:SetAttribute("DevCharges", 3)
	workspace:SetAttribute("DevGold", 500)
	Emulator.run(2.5)
	H.expect(state.phase == "War", "DevTick 179 jumps to War")
	H.expect(nation.charges == 3 and nation.gold >= 500, "DevCharges and DevGold apply")
	H.expect(workspace:GetAttribute("DevTick") == nil, "the switches clear themselves")
end

-- The map's look at three zooms: whole map, region around the capital, the capital close up.
function scenarios.look()
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	Emulator.run(2)
	H.shot(alice, "whole_map")
	local state = H.state()
	local capital = state.nations[H.myNation(alice)].capital
	local MapView = H.client(alice, "MapView")
	MapView.centreOn(H.provinceMap(alice, capital), false)
	Emulator.pinch(alice, 3.5)
	Emulator.run(2)
	H.shot(alice, "region")
	-- the region zoom shows the whole-map painting; zoomed in, the close-up detail is laid over it
	local function closeUp()
		local canvas = MapView.canvas()
		local layer = canvas and canvas:FindFirstChild("Image")
		return layer and layer:FindFirstChild("Detail")
	end
	H.expect(closeUp() == nil, "no close-up detail at the region zoom")
	Emulator.pinch(alice, 3)
	Emulator.run(2)
	H.expect(closeUp() ~= nil and closeUp().Visible, "the close-up detail shows at close zoom")
	H.shot(alice, "close_up")

	-- the nearest mountain, the nearest coast and the nearest forest, close up
	local map = H.client(alice, "ClientState").map()
	local here = H.provinceMap(alice, capital)
	local function nearest(test)
		local best, bestD = nil, math.huge
		for _, def in map.provinces do
			local d = (H.provinceMap(alice, def.id) - here).Magnitude
			if test(def) and d < bestD then
				best, bestD = def.id, d
			end
		end
		return best
	end
	local mountain = nearest(function(def)
		return def.terrain == "Mountain"
	end)
	if mountain then
		-- (centre first and let the camera arrive: a pinch holds the point under the fingers where it is)
		MapView.centreOn(H.provinceMap(alice, mountain), false)
		Emulator.run(1.5)
		Emulator.pinch(alice, 2)
		Emulator.run(2)
		H.shot(alice, "mountain")
	end
	local grid = MapGrid.decode(map)
	local coast, coastD = nil, math.huge
	for y = 1, grid.height - 2, 2 do
		for x = 1, grid.width - 2, 2 do
			if MapGrid.at(grid, x, y) ~= 0 and MapGrid.at(grid, x, y + 1) == 0 then
				local p = Emulator.roblox.Vector2.new(x, y)
				if (p - here).Magnitude < coastD then
					coast, coastD = p, (p - here).Magnitude
				end
			end
		end
	end
	if coast then
		MapView.centreOn(coast, false)
		Emulator.run(2)
		H.expect(closeUp() ~= nil and closeUp().Visible, "the close-up follows the camera")
		H.shot(alice, "coast")
	end
	local woods = { forest = true, jungle = true, taiga = true, wildwood = true, crystalgrove = true }
	local forest = nearest(function(def)
		return woods[def.biome] == true
	end)
	if forest then
		MapView.centreOn(H.provinceMap(alice, forest), false)
		Emulator.run(2)
		H.shot(alice, "forest")
	end

	-- zoomed out again, the close-up's image is freed
	MapView.showWholeMap()
	Emulator.run(0.5)
	H.expect(closeUp() == nil, "the close-up is freed when zoomed out")
end

local function provinceByName(name: string): number
	local state = H.state()
	for id, p in state.provinces do
		if p.name == name then
			return id
		end
	end
	error("no province " .. name)
end

local tapProvince = H.tapProvince

-- Phase 2: march on a garrison, win the battle, siege and take the province; war, peace and results.
function scenarios.war()
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	local bob = Emulator.addClient("Bob")
	Emulator.run(2)
	local state = H.state()
	local A, B = H.myNation(alice), H.myNation(bob)
	H.expect(A == 1 and B == 2, "Alice is Aurora, Bob is Zephyr")
	state.nations[A].gold, state.nations[A].manpower = 400, 20000

	-- recruit 3 regiments at the capital
	Emulator.press(alice, "⭐")
	Emulator.run(1)
	for _ = 1, 3 do
		Emulator.press(alice, "Regiment")
		Emulator.run(1.2)
	end
	local army
	for _, a in state.armies do
		if a.owner == A then
			army = a
		end
	end
	H.expect(army ~= nil and army.men == 3000, "a 3k army stands at the capital")

	-- pick it up from the sheet, tap the neutral drift isle, Go
	Emulator.press(alice, "Move")
	Emulator.run(0.3)
	H.expect(Emulator.findText(alice, "Tap where to go") ~= nil, "the army sheet asks for a destination")
	local rock = provinceByName("Cinder Rock")
	tapProvince(alice, rock)
	H.expect(Emulator.findText(alice, "Cinder Rock") ~= nil, "route preview names the destination")
	H.shot(alice, "route_preview")
	Emulator.press(alice, "Go")
	Emulator.run(1)
	H.expect(#army.path > 0, "the army is marching")
	Emulator.run(6)
	H.shot(alice, "marching")

	-- arrive, fight the garrison, besiege, take it
	local deadline = Emulator.now() + 60
	while army.location ~= rock and Emulator.now() < deadline do
		Emulator.run(1)
	end
	H.expect(army.location == rock, "the army reached Cinder Rock")
	Emulator.run(1.5)
	H.shot(alice, "battle")
	Emulator.run(4)
	local garrisonLeft = false
	for _, a in state.armies do
		garrisonLeft = garrisonLeft or (a.owner == 0 and a.location == rock)
	end
	H.expect(not garrisonLeft, "the garrison was beaten")
	Emulator.run(8)
	H.shot(alice, "siege")
	deadline = Emulator.now() + 120
	while state.provinces[rock].owner ~= A and Emulator.now() < deadline do
		Emulator.run(1)
	end
	H.expect(state.provinces[rock].owner == A, "Cinder Rock was captured")
	Emulator.run(0.5)
	H.shot(alice, "captured")

	-- jump to the war phase, take the other drift province so Aurora borders Zephyr, declare war
	state.tick = 179
	state.provinces[provinceByName("Cinder Reach")].owner = A
	Emulator.run(2)
	local zephyrLeeward = provinceByName("Zephyr Leeward")
	tapProvince(alice, zephyrLeeward)
	H.shot(alice, "foreign_sheet")
	Emulator.press(alice, "Declare")
	Emulator.run(1.5)
	local Diplomacy = require("../../src/shared/Sim/Diplomacy")
	H.expect(Diplomacy.atWar(state, A, B), "Aurora and Zephyr are at war")
	H.shot(bob, "war_declared_on_bob")

	-- Bob offers peace with 50 gold; Alice accepts from the offer card
	state.nations[B].gold = 300
	Emulator.run(1)
	tapProvince(bob, provinceByName("Cinder Reach"))
	Emulator.press(bob, "+💰50")
	Emulator.run(2)
	H.expect(Emulator.findText(alice, "offers peace") ~= nil, "Alice sees Bob's peace offer")
	H.shot(alice, "peace_offer")
	local aliceGold = state.nations[A].gold
	Emulator.press(alice, "Accept")
	Emulator.run(1.5)
	H.expect(not Diplomacy.atWar(state, A, B), "peace was made")
	H.expect(state.nations[A].gold >= aliceGold + 50, "Alice got the tribute")

	-- the nations drawer
	Emulator.press(alice, "🌍")
	Emulator.run(0.5)
	H.expect(Emulator.findText(alice, "Zephyr") ~= nil, "the drawer lists the nations")
	H.shot(alice, "nations")
	Emulator.press(alice, "🌍")

	-- give Aurora 30% of the world: the coalition crown, then the domination share and the results screen
	local given = 0
	for _, p in state.provinces do
		if p.owner == A then
			given += 1
		end
	end
	local need = math.ceil(0.3 * 131)
	for _, p in state.provinces do
		if given < need and p.owner ~= A and p.terrain ~= "Mountain" then
			p.owner = A
			given += 1
		end
	end
	Emulator.run(1.5)
	H.expect(Emulator.findText(alice, "👑") ~= nil, "the coalition leader wears a crown")
	H.shot(alice, "crown")
	need = math.ceil(Config.Win.DominationShare * 131)
	for _, p in state.provinces do
		if given < need and p.owner ~= A and p.terrain ~= "Mountain" then
			p.owner = A
			given += 1
		end
	end
	Emulator.run(2)
	H.expect(state.result ~= nil and state.result.kind == "Domination", "Aurora won by domination")
	H.expect(Emulator.findText(alice, "You win") ~= nil, "Alice sees the victory screen")
	H.shot(alice, "results")
	Emulator.run(32)
	H.expect(state ~= H.state(), "a new match started after Results")
	H.expect(H.state().phase == "Peace", "the new match is in Peace")
end

-- Phase 3: Bob is eliminated, rises as a Primordial and drops a Meteor on Alice's army through the power UI.
function scenarios.primordial()
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	local bob = Emulator.addClient("Bob")
	Emulator.run(2)
	local state = H.state()
	local A, B = H.myNation(alice), H.myNation(bob)
	H.expect(A == 1 and B == 2, "Alice is Aurora, Bob is Zephyr")
	H.expect(Emulator.findText(alice, "⚡0") ~= nil, "a living nation sees the power button with its charges")

	-- open war; Aurora takes Zephyr's capital and all but two provinces: Zephyr is eliminated next tick
	state.tick = 10 * 60
	local kept = 0
	for _, p in state.provinces do
		if p.owner == B then
			if p.isCapital or kept >= 2 then
				p.owner = A
			else
				kept += 1
			end
		end
	end
	Emulator.run(2)
	local bobId = bob.serverPlayer.UserId
	H.expect(state.nations[B].eliminated, "Zephyr was eliminated")
	H.expect(state.primordials[bobId] ~= nil, "Bob rose as a Primordial")
	H.expect(Emulator.findText(bob, "You rose as a Primordial") ~= nil, "Bob sees the Primordial banner")
	H.expect(Emulator.findText(bob, "✨ Primordial") ~= nil, "Bob's top bar says Primordial")
	H.shot(bob, "primordial")
	Emulator.run(2.5) -- after the War toast
	H.expect(Emulator.findText(alice, "Zephyr was eliminated") ~= nil, "Alice hears about it")

	-- Bob has no orders to give, only powers
	tapProvince(bob, state.nations[A].capital)
	H.expect(Emulator.findText(bob, "Declare") == nil and Emulator.findText(bob, "Develop") == nil, "no orders")
	Emulator.press(bob, "✕")

	-- charges and a target: a 4k Aurora army at its capital
	state.primordials[bobId].charges = 3
	local Army = require("../../src/shared/Sim/Army")
	local capital = state.nations[A].capital
	local army = Army.spawn(state, A, capital, 4000)
	local dev = state.provinces[capital].development
	Emulator.run(1.5)
	H.expect(Emulator.findText(bob, "⚡3") ~= nil, "the power button shows Bob's 3 charges")

	-- button -> pick Meteor -> tap the army -> Confirm
	Emulator.press(bob, "⚡3")
	Emulator.run(0.3)
	H.expect(Emulator.findText(bob, "Meteor") ~= nil and Emulator.findText(bob, "Shield") ~= nil, "the picker lists powers")
	H.shot(bob, "picker")
	Emulator.press(bob, "Meteor")
	Emulator.run(0.3)
	H.expect(Emulator.findText(bob, "Tap an army") ~= nil, "Meteor asks for an army")
	local MapView = H.client(bob, "MapView")
	local spot = H.provinceMap(bob, capital) + Emulator.roblox.Vector2.new(0, -4)
	MapView.centreOn(spot, true)
	Emulator.run(1.5)
	local screen = MapView.toScreen(spot)
	Emulator.tapScreen(bob, screen.X, screen.Y)
	Emulator.run(0.3)
	H.expect(Emulator.findText(bob, "Aurora's army (4k)") ~= nil, "the target is Aurora's 4k army")
	H.shot(bob, "target")
	Emulator.press(bob, "Confirm")
	Emulator.run(1.5)
	H.expect(army.men == 2000, "the Meteor killed half the army")
	H.expect(state.provinces[capital].development == math.max(1, dev - 1), "and cost the capital a development level")
	H.expect(state.primordials[bobId].charges == 1, "Bob paid 2 charges")
	H.expect(Emulator.findText(alice, "Meteor struck your army") ~= nil, "Alice gets the toast")
	H.expect(Emulator.findText(bob, "⚡1") ~= nil, "Bob's button shows 1 charge left")
	H.shot(alice, "meteor_alice")
	H.shot(bob, "meteor_bob")

	-- the 30 s immunity: the picker shows Aurora as unavailable instead of sending a power the server refuses
	state.primordials[bobId].charges = 3
	Emulator.run(1.5)
	Emulator.press(bob, "⚡3")
	Emulator.press(bob, "Plague")
	tapProvince(bob, capital)
	H.expect(Emulator.findText(bob, "Aurora is immune for") ~= nil, "the target step says Aurora is immune")
	H.expect(Emulator.findText(bob, "Confirm") == nil, "and offers no Confirm")
	H.shot(bob, "immune_target")
	Emulator.press(bob, "Cancel")
	H.expect(state.nations[A].plagueUntil == nil, "Aurora is not plagued")

	-- Rebels: a black 🏴 token that shows even zoomed out, unlike the neutral garrisons
	local rebelTarget
	for id, p in state.provinces do
		if p.owner == 4 and not p.isCapital and p.terrain ~= "Mountain" and (rebelTarget == nil or id < rebelTarget) then
			rebelTarget = id
		end
	end
	Emulator.press(bob, "⚡3")
	Emulator.press(bob, "Rebels")
	tapProvince(bob, rebelTarget)
	Emulator.press(bob, "Confirm")
	Emulator.run(1.5)
	local rebels
	for _, a in state.armies do
		if a.rebel then
			rebels = a
		end
	end
	H.expect(rebels ~= nil and rebels.location == rebelTarget, "Rebels rose in " .. state.provinces[rebelTarget].name)
	H.client(alice, "MapView").showWholeMap()
	Emulator.run(1.5)
	local token = Emulator.findText(alice, "🏴 3k")
	H.expect(token ~= nil, "Alice sees the 🏴 Rebels token zoomed out")
	H.expect(Emulator.findText(alice, "🛡 ") == nil, "while garrisons stay hidden at that zoom")
	H.shot(alice, "rebels")
	H.client(alice, "MapView").centreOn(H.provinceMap(alice, rebelTarget), true)
	Emulator.run(1.5)
	H.shot(alice, "rebels_close")

	-- rejoining: Bob leaves and comes back as himself, still the Primordial of Zephyr
	Emulator.removeClient(bob)
	Emulator.run(2)
	bob = Emulator.addClient("Bob", nil, bobId)
	Emulator.run(2)
	H.expect(H.myNation(bob) == B, "Bob rejoins on Zephyr")
	H.expect(Emulator.findText(bob, "✨ Primordial") ~= nil, "still a Primordial")

	-- Carol takes a nation, leaves, and it is eliminated while a bot runs it: she rejoins as its Primordial
	local carol = Emulator.addClient("Carol")
	Emulator.run(2)
	local carolId = carol.serverPlayer.UserId
	local C = H.myNation(carol)
	H.expect(C == 3, "Carol takes the lowest free nation, " .. state.nations[3].name)
	Emulator.removeClient(carol)
	Emulator.run(2)
	H.expect(state.nations[C].controller == "Bot", "a bot runs it after she leaves")
	local dave = Emulator.addClient("Dave")
	Emulator.run(2)
	H.expect(H.myNation(dave) ~= C, "a newcomer doesn't take the nation Carol held")
	for _, p in state.provinces do
		if p.owner == C then
			p.owner = A
		end
	end
	Emulator.run(2)
	H.expect(state.nations[C].eliminated, state.nations[C].name .. " was eliminated under the bot")
	carol = Emulator.addClient("Carol", nil, carolId)
	Emulator.run(2)
	H.expect(H.myNation(carol) == C, "Carol rejoins on her eliminated nation, not a healthy one")
	H.expect(state.primordials[carolId] ~= nil, "and is its Primordial")
	H.expect(Emulator.findText(carol, "✨ Primordial") ~= nil, "her top bar says Primordial")
	H.shot(carol, "rejoined_primordial")
end

-- Phase 3: Alice and nine bots for six game minutes on Skyshards. The bots expand in Peace and go to war after
-- it, every command goes through the real CommandRouter, and a nation whose player leaves plays on as a bot.
function scenarios.bots()
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	Emulator.run(2)
	local state = H.state()
	local me = H.myNation(alice)
	H.expect(me == 1, "Alice is seated as nation 1")
	local Match = require("../../src/shared/Sim/Match")
	local start = {}
	for id, nation in state.nations do
		if id ~= me then
			H.expect(nation.controller == "Bot", nation.name .. " is a bot")
			start[id] = Match.provinceCount(state, id)
		end
	end

	-- count what bots submit and what the server refuses (dry runs inside the planner use copies of the state)
	local CommandRouter = H.server("CommandRouter")
	local submitted, rejected = {}, {}
	local submit = CommandRouter.submitForBot
	CommandRouter.submitForBot = function(nationId, command)
		submitted[nationId] = (submitted[nationId] or 0) + 1
		submit(nationId, command)
	end
	local sharedNode = Emulator.server.dm:GetService("ReplicatedStorage").Shared
	local Commands = Emulator.server.modules[sharedNode.Sim.Commands]
	local apply = Commands.apply
	Commands.apply = function(s, nationId, command)
		local ok, reason = apply(s, nationId, command)
		if not ok and s == H.state() and s.nations[nationId] and s.nations[nationId].controller == "Bot" then
			table.insert(rejected, string.format("%s %s: %s", s.nations[nationId].name, command.kind, tostring(reason)))
		end
		return ok, reason
	end

	H.shot(alice, "start")
	Emulator.run(60)
	local moving = 0
	for _, a in state.armies do
		if a.owner ~= me and a.owner ~= 0 and #a.path > 0 then
			moving += 1
		end
	end
	H.expect(moving > 0, "bot armies are marching after a minute")
	Emulator.run(115) -- just before the war phase
	H.shot(alice, "peace_expansion")
	local grown = 0
	for id, n in start do
		if Match.provinceCount(state, id) > n then
			grown += 1
		end
	end
	H.expect(grown >= 8, string.format("%d of 9 bots expanded in Peace", grown))

	-- Bob joins, takes a bot's nation, and leaves: it plays on as a bot straight away
	local bob = Emulator.addClient("Bob")
	Emulator.run(2)
	local B = H.myNation(bob)
	H.expect(B == 2 and state.nations[B].controller == "Player", "Bob takes over Zephyr")
	local before = submitted[B] or 0
	Emulator.run(10)
	H.expect((submitted[B] or 0) == before, "no bot plans for Bob's nation while he plays")
	Emulator.removeClient(bob)
	Emulator.run(10)
	H.expect(state.nations[B].controller == "Bot", "Zephyr is a bot again after Bob left")
	H.expect((submitted[B] or 0) > before, "the bot carries on for Zephyr")

	Emulator.run(360 - Emulator.now())
	H.shot(alice, "six_minutes")
	local total0, total = 0, 0
	for id, n in start do
		total0 += n
		total += Match.provinceCount(state, id)
		print(
			string.format("    %-10s %2d -> %2d provinces", state.nations[id].name, n, Match.provinceCount(state, id))
		)
	end
	H.expect(total > total0, string.format("bots own more provinces than they started with (%d -> %d)", total0, total))
	H.expect(next(state.wars) ~= nil, "bots went to war after Peace")
	local sent = 0
	for _, n in submitted do
		sent += n
	end
	for _, line in rejected do
		print("    rejected: " .. line)
	end
	H.expect(sent > 100 and #rejected <= 2, string.format("%d bot commands, %d refused by the server", sent, #rejected))
	Commands.apply = apply
	CommandRouter.submitForBot = submit
end

-- Phase 4: Alice wins a battle, takes a province and the match, sees her XP and Glory on the Results screen, and
-- the profile is saved; she leaves (releasing the session lock) and rejoins, and her XP and Glory are still there.
function scenarios.progression()
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	Emulator.run(2)
	local userId = alice.serverPlayer.UserId
	local Data = H.server("Services.PlayerDataService")
	local summary = H.client(alice, "ProfileState").summary()
	H.expect(Data.data(alice.serverPlayer) ~= nil, "Alice's profile loaded with a session lock")
	H.expect(summary and summary.level == 1 and summary.xp == 0 and summary.glory == 0, "a new player: level 1, no XP")
	H.expect(Emulator.findText(alice, "🎖 1") ~= nil, "the HUD shows level 1")

	-- recruit 3 regiments, march on the neutral Cinder Rock, beat its garrison and take it
	local state = H.state()
	local A = H.myNation(alice)
	state.nations[A].gold, state.nations[A].manpower = 400, 20000
	Emulator.press(alice, "⭐")
	Emulator.run(1)
	for _ = 1, 3 do
		Emulator.press(alice, "Regiment")
		Emulator.run(1.2)
	end
	Emulator.press(alice, "Move")
	Emulator.run(0.3)
	local rock = provinceByName("Cinder Rock")
	tapProvince(alice, rock)
	Emulator.press(alice, "Go")
	local deadline = Emulator.now() + 180
	while state.provinces[rock].owner ~= A and Emulator.now() < deadline do
		Emulator.run(1)
	end
	H.expect(state.provinces[rock].owner == A, "Alice won the battle and captured Cinder Rock")

	-- the domination share of the world for Aurora: domination and Results
	local total, given = 0, 0
	for _, p in state.provinces do
		total += 1
		given += if p.owner == A then 1 else 0
	end
	for _, p in state.provinces do
		if given < math.ceil(Config.Win.DominationShare * total) and p.owner ~= A and p.terrain ~= "Mountain" then
			p.owner = A
			given += 1
		end
	end
	Emulator.run(2)
	H.expect(state.result ~= nil and state.result.kind == "Domination", "Aurora won by domination")
	local report = H.client(alice, "ProfileState").reward()
	-- finish 100 + 1st place 150 + 1 province 5 + 1 battle 5 + first match today 200 = 460 XP (level 2);
	-- Glory 20 + 40 + 1 + 1 + 50, and 50 for the level-up, 25 for the first step of the play calendar = 187
	H.expect(report ~= nil and report.reward.xp == 460 and report.reward.glory == 187, "the reward: 460 XP, 187 Glory")
	H.expect(report.reward.placement == 1 and report.after.level == 2, "1st place, and Alice reached level 2")
	H.expect(Emulator.findText(alice, "+460 XP") ~= nil, "the Results screen shows the XP and Glory")
	H.expect(Emulator.findText(alice, "First match today") ~= nil, "with the breakdown")
	H.expect(Emulator.findText(alice, "Level 2!") ~= nil, "and the level-up")
	H.expect(Emulator.findText(alice, "160 / 360 XP") ~= nil, "and the level bar")
	H.expect(Emulator.findText(alice, "🎖 2") ~= nil, "the HUD shows level 2")
	H.shot(alice, "results_reward")

	Emulator.run(1)
	local saved = Emulator.dataStores.PlayerData["Player_" .. userId].value
	H.expect(saved.Data.xp == 460 and saved.Data.glory == 187, "the reward was saved to the DataStore")
	H.expect(saved.MetaData.ActiveSession ~= nil, "Alice's server holds the session lock")

	-- leave, rejoin
	Emulator.removeClient(alice)
	Emulator.run(3)
	saved = Emulator.dataStores.PlayerData["Player_" .. userId].value
	H.expect(saved.MetaData.ActiveSession == nil, "leaving saved the profile and released the session lock")
	H.expect(saved.Data.xp == 460 and saved.Data.stats.wins == 1, "the save has the XP and the win")
	local again = Emulator.addClient("Alice", nil, userId)
	Emulator.run(3)
	local data = Data.data(again.serverPlayer)
	H.expect(data and data.xp == 460 and data.glory == 187 and data.level == 2, "after rejoining: 460 XP, 187 Glory, level 2")
	H.expect(H.client(again, "ProfileState").summary().level == 2, "and Alice's client knows it")
	Emulator.run(30) -- the next match
	H.expect(H.state().result == nil, "a new match started")
	H.expect(Emulator.findText(again, "🎖 2") ~= nil, "the HUD shows level 2 after rejoining")
	H.shot(again, "rejoined")

	-- the server shuts down a minute into the match, before Alice leaves: she gets what leaving pays (4 XP of
	-- the finish reward), and no wrong kick message (a kick counts as a warning and fails the scenario)
	Emulator.run(60)
	Emulator.shutdown()
	saved = Emulator.dataStores.PlayerData["Player_" .. userId].value
	H.expect(saved.Data.xp > 460, string.format("the shutdown paid the match so far (%d XP)", saved.Data.xp))
	H.expect(saved.MetaData.ActiveSession == nil, "and released the session lock")
end

-- Phase 4: the Lobby. Three players vote (majority wins), the draft gives everyone the nation they tapped, a
-- player joining mid-draft gets one when his turn runs out, bots keep the rest, and the match starts in Peace.
-- After Results everyone stays and the next-map vote opens again.
function scenarios.lobby()
	local Lobby = require("../../src/shared/Sim/Lobby")
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	local bob = Emulator.addClient("Bob")
	local carol = Emulator.addClient("Carol")
	Emulator.run(2)
	local LobbyService = H.server("Services.LobbyService")
	H.expect(LobbyService.phase() == "Lobby", "the server opens the Lobby")
	H.expect(Emulator.findText(alice, "Vote for the map") ~= nil, "Alice sees the map vote")
	Emulator.run(2) -- the thumbnails are painted
	H.shot(alice, "vote")

	-- two taps per vote: the first chooses a card, the second votes
	Emulator.press(alice, "Card_eldmoor")
	Emulator.run(0.2)
	H.expect(Emulator.findText(alice, "Tap again") ~= nil, "the first tap only chooses the card")
	Emulator.press(alice, "Card_eldmoor")
	Emulator.press(bob, "Card_eldmoor")
	Emulator.press(bob, "Card_eldmoor")
	Emulator.press(carol, "Card_earth")
	Emulator.press(carol, "Card_earth")
	Emulator.run(1.5)
	local tally = Lobby.tally(LobbyService.state())
	H.expect(tally.eldmoor == 2 and tally.earth == 1, "the server counted Eldmoor 2, Earth 1")
	H.expect(Emulator.findText(alice, "Your vote") ~= nil, "Alice sees her vote")
	H.expect(Emulator.findText(carol, "🗳 2") ~= nil, "everyone sees the tally")
	H.shot(carol, "voted")

	-- the vote ends: the draft runs on Eldmoor
	local deadline = Emulator.now() + 70
	while LobbyService.phase() == "Lobby" and Emulator.now() < deadline do
		Emulator.run(1)
	end
	local state = H.state()
	H.expect(LobbyService.phase() == "Pick" and state.mapId == "eldmoor", "Eldmoor won and the draft starts on it")
	H.expect(state.phase == "Pick" and state.tick == 0, "the match waits in Pick at tick 0")
	Emulator.run(1.5)
	H.expect(Emulator.findText(alice, "Vote for the map") == nil, "the vote screen closed")

	local byUser = {
		[alice.serverPlayer.UserId] = alice,
		[bob.serverPlayer.UserId] = bob,
		[carol.serverPlayer.UserId] = carol,
	}
	local want = { [alice] = 4, [bob] = 6, [carol] = 9 }
	local dave
	for turn = 1, 3 do
		local client = byUser[Lobby.current(LobbyService.state())]
		H.expect(client ~= nil, "turn " .. turn .. " belongs to one of the voters")
		H.expect(Emulator.findText(client, "Your turn") ~= nil, client.name .. " is told it's their turn")
		local nation = state.nations[want[client]]
		if client == bob then
			Emulator.press(client, nation.name) -- straight from the list
		else
			H.tapProvince(client, nation.capital, false) -- on the map, then confirm
			H.expect(Emulator.findText(client, "Pick " .. nation.name) ~= nil, "tapping its land offers " .. nation.name)
			if turn == 1 then
				H.shot(client, "draft")
			end
			Emulator.press(client, "Pick " .. nation.name)
		end
		Emulator.run(1.5)
		H.expect(state.nations[want[client]].userId == client.serverPlayer.UserId, client.name .. " took " .. nation.name)
		if turn == 2 then
			dave = Emulator.addClient("Dave") -- joins mid-draft: last in the order
			Emulator.run(1)
			H.expect(#LobbyService.state().order == 4, "Dave joined the end of the draft order")
		end
	end
	H.shot(dave, "draft_dave")

	-- Dave lets his turn run out: he gets a random free nation, bots keep the rest, the match starts
	deadline = Emulator.now() + 20
	while state.phase == "Pick" and Emulator.now() < deadline do
		Emulator.run(1)
	end
	Emulator.run(1)
	H.expect(state.phase == "Peace" and state.tick <= 2, "the match started in Peace at tick 0")
	for client, id in want do
		H.expect(H.myNation(client) == id, client.name .. " plays the nation they tapped")
	end
	local daveNation = H.myNation(dave)
	H.expect(daveNation ~= 0 and state.nations[daveNation].userId == dave.serverPlayer.UserId, "Dave got a nation")
	local bots = 0
	for _, n in state.nations do
		if n.controller == "Bot" then
			bots += 1
		end
	end
	H.expect(bots == 6, "bots took the other 6 nations")
	H.expect(Emulator.findText(alice, "Your turn") == nil and Emulator.findText(alice, "is picking") == nil, "draft UI gone")
	H.shot(alice, "match_start")

	-- Results, then the next-map vote with everyone still here
	local total, given = 0, 0
	for _, p in state.provinces do
		total += 1
		if p.owner == 4 then
			given += 1
		end
	end
	for _, p in state.provinces do
		if given < math.ceil(Config.Win.DominationShare * total) and p.owner ~= 4 and p.terrain ~= "Mountain" then
			p.owner = 4
			given += 1
		end
	end
	Emulator.run(2)
	H.expect(state.result ~= nil, "Alice won by domination")
	Emulator.run(31)
	H.expect(LobbyService.phase() == "Lobby", "after Results the next-map vote opens")
	H.expect(#Emulator.server.dm:GetService("Players"):GetPlayers() == 4, "everyone stayed in the server")
	for _, client in { alice, bob, carol, dave } do
		H.expect(Emulator.findText(client, "Vote for the map") ~= nil, client.name .. " sees the next-map vote")
	end
	H.shot(bob, "next_vote")
	for _, client in { alice, bob, carol } do
		Emulator.press(client, "Card_skyshards")
		Emulator.press(client, "Card_skyshards")
	end
	deadline = Emulator.now() + 70
	while LobbyService.phase() == "Lobby" and Emulator.now() < deadline do
		Emulator.run(1)
	end
	H.expect(H.state() ~= state and H.state().mapId == "skyshards", "Skyshards won the next vote")
	-- nobody picks this time: every turn runs out and the server picks for them
	deadline = Emulator.now() + 40
	while H.state().phase == "Pick" and Emulator.now() < deadline do
		Emulator.run(1)
	end
	Emulator.run(1)
	H.expect(H.state().phase == "Peace", "the second match started")
	for _, client in { alice, bob, carol, dave } do
		H.expect(H.myNation(client) ~= 0, client.name .. " was given a nation")
	end
end

-- Phase 4: sound and effects. Every effect fires through the real flow (server state -> events in the delta ->
-- the client's Effects) and is photographed mid-animation; sounds are checked in the emulator's log.
function scenarios.effects()
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	Emulator.run(2)
	local state = H.state()
	local A = H.myNation(alice)
	local Effects = H.client(alice, "Effects")
	local MapView = H.client(alice, "MapView")
	local Army = require("../../src/shared/Sim/Army")
	local Primordial = require("../../src/shared/Sim/Primordial")
	local function soundsNamed(name: string): number
		local n = 0
		for _, s in Emulator.sounds do
			if s.name == name then
				n += 1
			end
		end
		return n
	end
	-- run in small steps until Effects shows `kind` (over `province`, if given); the bots fight battles of their own
	local function waitFor(kind: string, seconds: number?, province: number?)
		local start = Emulator.now()
		local function seen()
			for _, h in Effects.history() do
				if h.at >= start and h.kind == kind and (province == nil or h.province == province) then
					return true
				end
			end
			return false
		end
		local deadline = Emulator.now() + (seconds or 10)
		while not seen() and Emulator.now() < deadline do
			Emulator.run(0.1)
		end
		H.expect(seen(), "the " .. kind .. " effect plays")
	end

	H.expect(Emulator.findText(alice, "🔊") ~= nil, "the mute button sits in the top bar")
	local taps = soundsNamed("Tap")
	Emulator.press(alice, "⭐")
	Emulator.run(0.5)
	H.expect(soundsNamed("Tap") == taps + 1, "a button tap plays the tap sound")
	Emulator.press(alice, "✕")

	-- the War banner
	state.tick = 178
	waitFor("War", 5)
	Emulator.run(0.3)
	H.expect(Emulator.findText(alice, "WAR!") ~= nil, "the War banner shows")
	H.expect(soundsNamed("War") == 1, "the War sound plays")
	H.shot(alice, "phase_war")
	Emulator.run(3)

	-- a battle against the garrison of the nearest neutral province
	local capital = state.nations[A].capital
	local here = H.provinceMap(alice, capital)
	local target, best = nil, math.huge
	for id, p in state.provinces do
		local garrisoned = false
		for _, a in state.armies do
			garrisoned = garrisoned or (a.owner == 0 and a.location == id)
		end
		local d = (H.provinceMap(alice, id) - here).Magnitude
		if p.owner == nil and p.terrain ~= "Mountain" and garrisoned and d < best then
			target, best = id, d
		end
	end
	H.expect(target ~= nil, "found a garrisoned neutral province")
	MapView.centreOn(H.provinceMap(alice, target), true)
	Emulator.run(1.5)
	Army.spawn(state, A, target, 3000) -- big enough to win, small enough for a three-round fight
	waitFor("BattleStart", 5, target)
	Emulator.run(0.3)
	H.expect(Effects.stats().particles > 10, "dust and crossed swords are on the map")
	H.shot(alice, "battle_start")
	waitFor("ArmyDestroyed", 40, target)
	Emulator.run(0.25)
	H.expect(soundsNamed("ArmyDestroyed") >= 1, "a destroyed army plays its sound")
	H.shot(alice, "army_destroyed")

	-- the siege, sped up, and the capture ring in Alice's colour
	local deadline = Emulator.now() + 20
	while state.provinces[target].siege == nil and Emulator.now() < deadline do
		Emulator.run(0.5)
	end
	local siege = state.provinces[target].siege
	H.expect(siege ~= nil, "the siege began")
	siege.progress = math.max(siege.progress, siege.required - 2)
	waitFor("Capture", 10, target)
	Emulator.run(0.25)
	H.expect(state.provinces[target].owner == A, "Alice took the province")
	H.expect(soundsNamed("Capture") >= 1, "the capture sound plays")
	H.shot(alice, "capture")
	Emulator.run(2)

	-- Primordial powers, cast by Zephyr's nation through Sim.Primordial (immunity cleared between harmful ones)
	local caster = { nation = 2 }
	local function cast(power: string, targetId: number)
		state.nations[2].charges = 5
		state.nations[A].powerImmuneUntil = 0
		local ok, why = Primordial.use(state, caster, power, targetId)
		H.expect(ok, power .. " was cast (" .. tostring(why) .. ")")
	end
	MapView.centreOn(here, true)
	Emulator.run(1.5)
	local army = Army.spawn(state, A, capital, 6000)
	Emulator.run(1.5)
	cast("Meteor", army.id)
	waitFor("Meteor", 3, capital)
	Emulator.run(0.4)
	H.shot(alice, "meteor_falling")
	Emulator.run(0.5)
	H.expect(soundsNamed("MeteorImpact") == 1, "the meteor lands with a bang")
	H.shot(alice, "meteor_impact")
	Emulator.run(3)

	cast("Plague", A)
	waitFor("Plague", 3, capital)
	Emulator.run(0.5)
	H.shot(alice, "plague")
	Emulator.run(3)

	cast("Rebels", capital)
	waitFor("Rebels", 3, capital)
	Emulator.run(0.8)
	H.shot(alice, "rebels")
	Emulator.run(3)

	state.provinces[capital].building = "Farm"
	cast("Earthquake", capital)
	waitFor("Earthquake", 3, capital)
	Emulator.run(0.6)
	H.shot(alice, "earthquake")
	Emulator.run(3)

	cast("Blessing", capital)
	waitFor("Blessing", 3, capital)
	Emulator.run(0.7)
	H.shot(alice, "blessing")
	Emulator.run(2.5)

	cast("Shield", capital)
	waitFor("Shield", 3, capital)
	Emulator.run(1.5)
	H.expect(Effects.stats().domes == 1, "a shield dome stands over the province")
	H.shot(alice, "shield")
	H.expect(Effects.stats().particles <= 240, "particles stay inside the pool")

	-- mute: nothing plays until unmuted, and it is remembered
	Emulator.press(alice, "🔊")
	Emulator.run(0.2)
	H.expect(Emulator.findText(alice, "🔇") ~= nil, "the button shows muted")
	local before = #Emulator.sounds
	cast("Blessing", capital)
	waitFor("Blessing", 3, capital)
	Emulator.run(1)
	H.expect(#Emulator.sounds == before, "muted: no sounds")
	Emulator.press(alice, "🔇")
	Emulator.run(0.2)
	H.expect(Emulator.findText(alice, "🔊") ~= nil, "unmuted again")

	-- the Cataclysm banner, then the shield runs out and its dome goes
	state.tick = 20 * 60 - 2
	waitFor("Cataclysm", 5)
	Emulator.run(0.3)
	H.expect(Emulator.findText(alice, "CATACLYSM") ~= nil, "the Cataclysm banner shows")
	H.shot(alice, "phase_cataclysm")
	Emulator.run(3)
	H.expect(Effects.stats().domes == 0, "the dome is gone once the shield ends")
	H.expect(Effects.stats().active <= 14, "only a few effects run at once")

	-- Results: Aurora takes 40% of the world; the banner shows over the results screen
	local total, given = 0, 0
	for _, p in state.provinces do
		total += 1
		given += if p.owner == A then 1 else 0
	end
	for _, p in state.provinces do
		if given < math.ceil(Config.Win.DominationShare * total) and p.owner ~= A and p.terrain ~= "Mountain" then
			p.owner = A
			given += 1
		end
	end
	waitFor("Results", 5)
	Emulator.run(0.4)
	H.expect(Emulator.findText(alice, "MATCH OVER") ~= nil, "the Results banner shows")
	H.expect(soundsNamed("Results") == 1, "the Results sound plays")
	H.shot(alice, "phase_results")
end

-- Phase 4: the tutorial match. A new player on a tutorial server (Workspace "Tutorial") meets 5 Easy bots on an
-- otherwise neutral map and follows the six prompts with the normal UI: take a neutral province, recruit, siege,
-- make an ally, declare war, use a Primordial power. The profile remembers it; the next match's prompts can be
-- skipped with two taps.
function scenarios.tutorial()
	local Config = require("../../src/shared/Config")
	local Diplomacy = require("../../src/shared/Sim/Diplomacy")
	local Tutorial = require("../../src/shared/Sim/Tutorial")
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	Emulator.run(2)
	local state = H.state()
	local A = H.myNation(alice)
	local TutorialService = H.server("Services.TutorialService")
	local tut = TutorialService.current()
	H.expect(state.mapId == Config.Tutorial.Map and A == Config.Tutorial.PlayerSlot, "Alice plays the tutorial nation")
	local nations = 0
	for _, n in state.nations do
		nations += 1
	end
	H.expect(nations == 6, "Alice and 5 bots; the other nations are gone")
	H.expect(state.phase == "Peace" and state.tick <= 3, "the Lobby was skipped")
	H.expect(Emulator.findText(alice, "1/6") ~= nil, "the first prompt shows")
	local capital = state.nations[A].capital

	-- 1. take a neutral province: the arrow is on the army; tap it, Move, the grey province, Go
	H.expect(Emulator.findText(alice, "Tap your army") ~= nil, "it asks for the army")
	H.shot(alice, "prompt1_army")
	tapProvince(alice, capital)
	H.expect(Emulator.findText(alice, "Tap ➜ Move") ~= nil, "then for Move")
	H.shot(alice, "prompt1_move")
	Emulator.press(alice, "Move")
	Emulator.run(0.5)
	H.expect(Emulator.findText(alice, "Tap grey land") ~= nil, "then for the grey province")
	local target = Tutorial.neutralTarget(state, A)
	H.shot(alice, "prompt1_target")
	tapProvince(alice, target)
	H.expect(Emulator.findText(alice, "Tap ✅ Go") ~= nil, "then for Go")
	H.shot(alice, "prompt1_go")
	Emulator.press(alice, "Go")
	Emulator.run(8)
	H.expect(Emulator.findText(alice, "⏳") ~= nil, "then it says to wait")
	H.shot(alice, "prompt1_wait")
	local deadline = Emulator.now() + 120
	while tut.step == 1 and Emulator.now() < deadline do
		Emulator.run(1)
	end
	H.expect(state.provinces[target].owner == A and tut.step == 2, "taking the province finished prompt 1")
	Emulator.run(1)

	-- 2. recruit
	H.expect(Emulator.findText(alice, "2/6") ~= nil and Emulator.findText(alice, "Tap your land") ~= nil, "prompt 2")
	H.shot(alice, "prompt2_recruit")
	tapProvince(alice, capital)
	H.expect(Emulator.findText(alice, "Tap +1 Regiment") ~= nil, "it points at the Recruit button")
	H.shot(alice, "prompt2_button")
	Emulator.press(alice, "Regiment")
	Emulator.run(2)
	H.expect(tut.step == 3, "recruiting finished prompt 2")
	Emulator.press(alice, "✕")
	Emulator.run(0.5)

	-- 3. siege: the army again, the next grey province, Go, and the siege starts
	H.expect(Emulator.findText(alice, "3/6") ~= nil, "prompt 3")
	H.shot(alice, "prompt3_siege")
	local second = Tutorial.neutralTarget(state, A)
	tapProvince(alice, target)
	Emulator.press(alice, "Move")
	Emulator.run(0.5)
	tapProvince(alice, second)
	Emulator.press(alice, "Go")
	deadline = Emulator.now() + 120
	while tut.step == 3 and Emulator.now() < deadline do
		Emulator.run(1)
	end
	H.expect(tut.step == 4 and state.provinces[second].siege ~= nil, "the siege finished prompt 3")
	Emulator.run(1)

	-- 4. make an ally: tap the friend's land, Ally; the bot accepts
	local friend = tut.friend
	H.expect(Emulator.findText(alice, "Ally with " .. state.nations[friend].name) ~= nil, "prompt 4 names the friend")
	H.shot(alice, "prompt4_ally")
	tapProvince(alice, Tutorial.view(state, tut).province)
	H.expect(Emulator.findText(alice, "Tap 🤝 Ally") ~= nil, "it points at the Ally button")
	H.shot(alice, "prompt4_button")
	Emulator.press(alice, "🤝 Ally")
	Emulator.run(3)
	H.expect(Diplomacy.allied(state, A, friend), "the friend accepted")
	H.expect(tut.step == 5, "the alliance finished prompt 4")
	Emulator.press(alice, "✕")
	Emulator.run(2)

	-- 5. declare war: Peace ended early
	local rival = tut.rival
	H.expect(state.phase == "War", "War came early for the tutorial")
	H.expect(Emulator.findText(alice, "War on " .. state.nations[rival].name) ~= nil, "prompt 5 names the rival")
	H.shot(alice, "prompt5_war")
	tapProvince(alice, Tutorial.view(state, tut).province)
	H.expect(Emulator.findText(alice, "Tap ⚔ Declare war") ~= nil, "it points at Declare war")
	H.shot(alice, "prompt5_button")
	Emulator.press(alice, "Declare")
	Emulator.run(2)
	H.expect(Diplomacy.atWar(state, A, rival), "Alice is at war with the rival")
	H.expect(tut.step == 6, "the war finished prompt 5")
	Emulator.press(alice, "✕")
	Emulator.run(1)

	-- 6. a power: the button, Blessing, her own land, Confirm
	H.expect(state.nations[A].charges >= 1, "Alice has a charge")
	H.expect(Emulator.findText(alice, "Tap the ✨ button") ~= nil, "prompt 6 points at the power button")
	H.shot(alice, "prompt6_power")
	Emulator.press(alice, "✨")
	Emulator.run(0.5)
	H.expect(Emulator.findText(alice, "Pick 🌟 Blessing") ~= nil, "then at Blessing")
	H.shot(alice, "prompt6_blessing")
	Emulator.press(alice, "Blessing")
	Emulator.run(0.5)
	H.expect(Emulator.findText(alice, "Tap your land") ~= nil, "then at her land")
	tapProvince(alice, capital)
	H.expect(Emulator.findText(alice, "Tap ✅ Confirm") ~= nil, "then at Confirm")
	H.shot(alice, "prompt6_confirm")
	Emulator.press(alice, "Confirm")
	Emulator.run(2)
	H.expect(Tutorial.finished(tut), "the power finished the tutorial")
	H.expect(Emulator.findText(alice, "Tutorial done!") ~= nil, "Alice sees the end card")
	H.expect(Emulator.findText(alice, "1/6") == nil and Emulator.findText(alice, "6/6") == nil, "the prompt card is gone")
	local data = H.server("Services.PlayerDataService").data(alice.serverPlayer)
	H.expect(data and data.tutorialDone == true, "the profile remembers the tutorial is done")
	H.shot(alice, "done")
	Emulator.press(alice, "Keep playing")
	Emulator.run(0.5)
	H.expect(Emulator.findText(alice, "Tutorial done!") == nil, "the end card closes")

	-- the match ends; in Studio the next tutorial match starts here, and its prompts can be skipped (two taps)
	local total, given = 0, 0
	for _, p in state.provinces do
		total += 1
		given += if p.owner == A then 1 else 0
	end
	for _, p in state.provinces do
		if given < math.ceil(Config.Win.DominationShare * total) and p.owner ~= A and p.terrain ~= "Mountain" then
			p.owner = A
			given += 1
		end
	end
	Emulator.run(34)
	H.expect(H.state() ~= state and TutorialService.current() ~= tut, "a new tutorial match started")
	Emulator.run(1)
	H.expect(Emulator.findText(alice, "1/6") ~= nil, "its first prompt shows")
	Emulator.press(alice, "Skip")
	Emulator.run(0.3)
	H.expect(Emulator.findText(alice, "Sure?") ~= nil, "the first tap asks to confirm")
	H.shot(alice, "skip_confirm")
	Emulator.press(alice, "Sure?")
	Emulator.run(1.5)
	H.expect(TutorialService.current().skipped, "the server skipped the tutorial")
	H.expect(Emulator.findText(alice, "1/6") == nil, "the prompts are gone")

	-- analytics: the six prompts were onboarding steps 5-10, and the skip was logged with its prompt
	local onboarded, skips = {}, {}
	for _, r in Emulator.analytics do
		if r.userId == alice.serverPlayer.UserId and r.method == "LogOnboardingFunnelStepEvent" then
			table.insert(onboarded, r.args[1] .. ":" .. r.args[2])
		elseif r.method == "LogCustomEvent" and r.args[1] == "tutorial_skipped" then
			table.insert(skips, r)
		end
	end
	local prompts = "5:first_neutral_captured,6:first_recruit,7:first_siege_done,8:first_ally,9:first_war,10:first_power_used"
	H.expect(string.find(table.concat(onboarded, ","), prompts, 1, true) ~= nil, "onboarding steps 5-10 follow the prompts")
	H.expect(#skips == 1 and skips[1].args[2] == 1, "tutorial_skipped at prompt 1")
end

-- Phase 4: the shop. In the Lobby Alice gets the starter-pack offer, opens the shop, buys a flag with Glory, fails
-- to buy one with too little Glory, buys an Epic flag, VIP, a token and an emote with Robux (Studio test mode:
-- product ids are 0), equips them, and checks the purchase history; a receipt processed twice grants once. In the
-- match everyone sees her flag on her capital and in the nations list, her token skin and her emote, and Robux
-- purchases are closed.
function scenarios.shop()
	local ROBUX = utf8.char(0xE002)
	-- press a button on one shop card (several cards show the same price)
	local function pressIn(client, container: string, needle: string)
		local root = client.localPlayer.PlayerGui:FindFirstChild(container, true)
		assert(root, container .. " is not on screen")
		for _, d in root:GetDescendants() do
			if d:IsA("TextButton") and string.find(d.Text, needle, 1, true) then
				Emulator.eventOf(d, "Activated"):Fire(nil, 1)
				return
			end
		end
		error(container .. " has no button " .. needle)
	end
	-- call a server function that may yield (saves) on the emulator's scheduler and wait for its answer
	local function await(fn, ...)
		local args = table.pack(...)
		local result
		Emulator.task.spawn(function()
			result = table.pack(fn(table.unpack(args, 1, args.n)))
		end)
		local deadline = Emulator.now() + 10
		while result == nil and Emulator.now() < deadline do
			Emulator.run(0.1)
		end
		assert(result, "timed out")
		return table.unpack(result, 1, result.n)
	end
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	local bob = Emulator.addClient("Bob")
	Emulator.run(2)
	local Data = H.server("Services.PlayerDataService")
	local ShopService = H.server("Services.ShopService")
	local ShopState = H.client(alice, "ShopState")
	local player = alice.serverPlayer
	H.expect(ShopState.view() ~= nil and ShopState.view().robuxOpen, "Alice's shop state arrived: Robux open in the Lobby")
	H.expect(ShopState.view().testMode, "product ids are 0: Studio test mode")
	Emulator.press(alice, "Card_skyshards")
	Emulator.press(alice, "Card_skyshards")

	-- a returning player with 3,000 Glory and two finished matches: the starter pack is offered once
	Data.update(player, function(data)
		data.glory = 3000
		data.stats.matches = 2
	end)
	ShopService.onPhase("Lobby")
	Emulator.run(1)
	H.expect(Emulator.findText(alice, "Starter Pack") ~= nil, "the starter-pack offer pops up after the 2nd match")
	H.expect(Emulator.findText(alice, "Bought separately: " .. ROBUX .. " 297") ~= nil, "with the real sum of its pieces")
	H.shot(alice, "starter_offer")
	Emulator.press(alice, "Not now")
	ShopService.onPhase("Lobby")
	Emulator.run(1)
	H.expect(Emulator.findText(alice, "Not now") == nil, "at most once per session")

	-- the shop: offers first
	Emulator.press(alice, "🛒")
	Emulator.run(0.5)
	H.expect(Emulator.findText(alice, "🏅 3,000") ~= nil, "the shop shows Alice's Glory")
	H.expect(Emulator.findText(alice, ROBUX .. " 249") ~= nil, "VIP shows its Robux price")
	H.shot(alice, "shop_offers")

	-- a flag for Glory
	Emulator.press(alice, "Flags")
	Emulator.run(0.5)
	H.shot(alice, "shop_flags")
	pressIn(alice, "Card_flag_sun", "🏅 1,200")
	Emulator.run(1)
	local data = Data.data(player)
	H.expect(data.owned.flag_sun == true and data.glory == 1800, "Rising Sun bought for 1,200 Glory")
	H.expect(Emulator.findText(alice, "🏅 1,800") ~= nil, "the shop shows the new balance")

	-- too little Glory for the Epic Comet: refused, nothing taken
	Emulator.press(alice, "▶")
	Emulator.run(0.3)
	pressIn(alice, "Card_flag_comet", "🏅 2,500")
	Emulator.run(1)
	H.expect(data.glory == 1800 and data.owned.flag_comet == nil, "a Glory purchase with too little Glory fails cleanly")
	H.expect(Emulator.findText(alice, "Not enough Glory") ~= nil, "and says why")

	-- the Comet with Robux (test mode): granted through the receipt path, once
	pressIn(alice, "Card_flag_comet", ROBUX .. " 149")
	Emulator.run(1.5)
	H.expect(data.owned.flag_comet == true, "the Comet was granted (test-mode Robux purchase)")
	H.expect(#data.purchaseHistory == 1 and data.purchaseHistory[1].item == "flag_comet", "and recorded in the history")
	local receipts = 0
	for _ in data.receipts do
		receipts += 1
	end
	H.expect(receipts == 1, "with one receipt in the ledger")
	pressIn(alice, "Card_flag_comet", "Equip")
	Emulator.run(1)
	H.expect(data.equipped.Flag == "flag_comet", "Alice equipped the Comet")
	H.expect(Emulator.findText(alice, "✅ Equipped") ~= nil, "the card says Equipped")
	H.shot(alice, "shop_flag_equipped")

	-- ProcessReceipt firing twice for one purchase grants once
	local receipt = { PurchaseId = "twice-1", PlayerId = player.UserId, ProductId = 0, CurrencySpent = 49 }
	local first = await(ShopService.receipt, receipt, "flag_cross")
	local second = await(ShopService.receipt, receipt, "flag_cross")
	local granted = Emulator.roblox.Enum.ProductPurchaseDecision.PurchaseGranted
	H.expect(first == granted and second == granted, "both calls answer PurchaseGranted")
	H.expect(#data.purchaseHistory == 2, "but the purchase was granted and recorded once")
	local saved = Emulator.dataStores.PlayerData["Player_" .. player.UserId].value.Data
	H.expect(saved.receipts["twice-1"] ~= nil and saved.owned.flag_cross, "and saved before PurchaseGranted")
	local unknown = await(Emulator.processReceipt, { PurchaseId = "x", PlayerId = player.UserId, ProductId = 123, CurrencySpent = 1 })
	H.expect(unknown == Emulator.roblox.Enum.ProductPurchaseDecision.NotProcessedYet, "an unknown product is not granted")

	-- VIP (game pass, test mode): the VIP set and the gold frame
	Emulator.press(alice, "Offers")
	Emulator.run(0.3)
	pressIn(alice, "Card_vip", ROBUX .. " 249")
	Emulator.run(1.5)
	H.expect(ShopService.isVip(player), "Alice has VIP")
	H.expect(player:GetAttribute("Vip") == true, "her player carries the VIP attribute (chat tag)")
	H.expect(Emulator.findText(alice, "👑 VIP") ~= nil, "the shop shows her VIP")

	-- a border for Glory, a token and an emote for Robux, all equipped
	Emulator.press(alice, "Borders")
	Emulator.run(0.3)
	pressIn(alice, "Card_border_dashes", "🏅 1,200")
	Emulator.run(1)
	H.expect(data.owned.border_dashes and data.glory == 600, "Dashes border bought for Glory")
	pressIn(alice, "Card_border_dashes", "Equip")
	Emulator.run(1)
	Emulator.press(alice, "Tokens")
	Emulator.run(0.3)
	pressIn(alice, "Card_token_shield", ROBUX .. " 99")
	Emulator.run(1.5)
	pressIn(alice, "Card_token_shield", "Equip")
	Emulator.run(1)
	H.expect(data.equipped.Border == "border_dashes" and data.equipped.Token == "token_shield", "border and token equipped")
	Emulator.press(alice, "Emotes")
	Emulator.run(0.3)
	pressIn(alice, "Card_emote_charge", ROBUX .. " 25")
	Emulator.run(1.5)
	H.expect(data.owned.emote_charge == true, "an emote bought")
	H.shot(alice, "shop_emotes")
	Emulator.press(alice, "History")
	Emulator.run(0.5)
	H.expect(Emulator.findText(alice, "Comet Flag") ~= nil, "Purchase History lists the Comet")
	H.expect(Emulator.findText(alice, "VIP") ~= nil, "and VIP")
	H.shot(alice, "shop_history")
	Emulator.press(alice, "✕")
	Emulator.run(0.3)

	-- the match: the vote and the draft run out, everyone gets a nation
	local LobbyService = H.server("Services.LobbyService")
	local deadline = Emulator.now() + 120
	while LobbyService.active() and Emulator.now() < deadline do
		Emulator.run(1)
	end
	Emulator.run(2)
	local state = H.state()
	local A = H.myNation(alice)
	H.expect(state.phase == "Peace" and A ~= 0, "the match started and Alice has a nation")
	local mine
	for _, c in H.client(bob, "ClientState").snapshot().cosmetics do
		if c.nation == A then
			mine = c
		end
	end
	H.expect(mine and mine.flag == "flag_comet" and mine.border == "border_dashes", "Bob's client knows Alice's flag and border")
	H.expect(mine.token == "token_shield" and mine.vip and mine.frame == "frame_gold", "and her token skin and VIP frame")
	H.expect(ShopState.view().robuxOpen == false, "Robux purchases closed for the match")
	local ok, reason = await(ShopService.apply, player, { kind = "Buy", item = "flag_vanguard", currency = "Robux" })
	H.expect(ok == false and reason == "InMatch", "the server refuses a Robux purchase during a match")

	-- Alice's flag on her capital (on Bob's screen too) and an army with her token skin
	local nation = state.nations[A]
	nation.gold, nation.manpower = 200, 10000
	Emulator.press(alice, "⭐")
	Emulator.run(1)
	Emulator.press(alice, "Regiment")
	Emulator.run(2)
	local flagOnMap = alice.localPlayer.PlayerGui:FindFirstChild("Flag" .. A, true)
	H.expect(flagOnMap ~= nil and flagOnMap:FindFirstChild("Flag") ~= nil, "Alice's flag stands by her capital")
	H.expect(bob.localPlayer.PlayerGui:FindFirstChild("Flag" .. A, true) ~= nil, "Bob sees it too")
	local skinned = false
	for _, d in bob.localPlayer.PlayerGui:GetDescendants() do
		if d.Name == "TokenSkin" then
			skinned = true
		end
	end
	H.expect(skinned, "Bob sees Alice's army with her token skin")

	-- her emote over the capital, seen by Bob
	Emulator.press(alice, "😀")
	Emulator.run(0.3)
	Emulator.press(alice, "📯")
	Emulator.run(1.2)
	H.expect(bob.localPlayer.PlayerGui:FindFirstChild("Emote" .. A, true) ~= nil, "Bob sees Alice's emote")
	Emulator.press(alice, "✕") -- close the province sheet for a clear view
	Emulator.run(0.3)
	H.shot(alice, "map_flag_emote")
	Emulator.run(3)
	H.expect(bob.localPlayer.PlayerGui:FindFirstChild("Emote" .. A, true) == nil, "the emote disappears after 3 s")
	Emulator.press(alice, "😀")
	Emulator.run(0.3)
	Emulator.press(alice, "📯")
	Emulator.run(1.2)
	H.expect(bob.localPlayer.PlayerGui:FindFirstChild("Emote" .. A, true) == nil, "one emote per 10 seconds")

	-- the nations list shows flags, the VIP tag and the frame
	Emulator.press(bob, "🌍")
	Emulator.run(0.5)
	H.expect(Emulator.findText(bob, "Alice") ~= nil or Emulator.findText(bob, nation.name .. " [VIP]") ~= nil, "Bob's nations list")
	H.expect(Emulator.findText(bob, "[VIP]") ~= nil, "shows Alice's VIP tag")
	H.shot(bob, "nations_list")
	Emulator.press(bob, "🌍")

	-- Alice wins: her victory animation plays over her capital on Results; Robux purchases open again
	Data.update(player, function(d)
		d.owned.victory_fireworks = true
		d.equipped.Victory = "victory_fireworks"
	end)
	local total, given = 0, 0
	for _, p in state.provinces do
		total += 1
		given += if p.owner == A then 1 else 0
	end
	for _, p in state.provinces do
		if given < math.ceil(Config.Win.DominationShare * total) and p.owner ~= A and p.terrain ~= "Mountain" and not p.isCapital then
			p.owner = A
			given += 1
		end
	end
	Emulator.run(2.5)
	H.expect(state.result ~= nil, "Alice won")
	local report = H.client(alice, "ProfileState").reward()
	local vipLine
	for _, line in report.reward.lines do
		if line.kind == "Vip" then
			vipLine = line
		end
	end
	H.expect(vipLine ~= nil and vipLine.xp > 0 and vipLine.glory > 0, "VIP adds 25% match XP and Glory to her reward")
	local victory = bob.localPlayer.PlayerGui:FindFirstChild("Victory" .. A, true)
	H.expect(victory ~= nil and string.find("🎆 ✨ 🎇", victory.Text, 1, true) ~= nil, "Bob sees her fireworks")
	H.expect(ShopState.view().robuxOpen, "Robux purchases are open on the Results screen")
	H.expect(Emulator.findText(alice, "Starter Pack") == nil, "the starter pack isn't offered twice in a session")
	H.shot(bob, "results")
	bob.localPlayer.PlayerGui.Results.Enabled = false -- hide the Results panel to see the map under it
	H.client(bob, "MapView").centreOn(H.provinceMap(bob, state.nations[A].capital), true)
	Emulator.run(1.5)
	H.shot(bob, "victory")
end

-- Balance pass: a beaten army walks home (no teleport) under a 🏳 flag and takes no orders on the way.
function scenarios.retreat()
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	local bob = Emulator.addClient("Bob")
	Emulator.run(2)
	local state = H.state()
	local A, B = H.myNation(alice), H.myNation(bob)
	local Army = require("../../src/shared/Sim/Army")
	local Diplomacy = require("../../src/shared/Sim/Diplomacy")
	local rock, reach = provinceByName("Cinder Rock"), provinceByName("Cinder Reach")
	state.tick = 179
	state.provinces[rock].owner = A
	state.provinces[reach].owner = B
	for id, a in state.armies do
		if a.location == rock or a.location == reach then
			state.armies[id] = nil
		end
	end
	Emulator.run(2)
	H.expect((Diplomacy.declareWar(state, A, B)), "Aurora and Zephyr are at war")
	local beaten = Army.spawn(state, A, reach, 3000)
	Army.spawn(state, B, reach, 5000)
	H.client(alice, "MapView").centreOn(H.provinceMap(alice, reach), true)
	Emulator.run(1.5)
	H.shot(alice, "battle")
	local deadline = Emulator.now() + 10
	while not beaten.retreating and Emulator.now() < deadline do
		Emulator.run(0.5)
	end
	H.expect(beaten.retreating == true and beaten.location == reach, "the beaten army is still on the field, retreating")
	Emulator.run(2)
	H.expect(Emulator.findText(alice, "🏳") ~= nil, "its token flies the retreat flag")
	H.client(alice, "UI.ArmySheet").show(beaten.id)
	Emulator.run(0.5)
	H.expect(Emulator.findText(alice, "Retreating to Cinder Rock") ~= nil, "the army sheet says where it is going")
	H.shot(alice, "retreating")
	H.client(alice, "UI.ArmySheet").show(nil)
	deadline = Emulator.now() + 20
	while beaten.location ~= rock and Emulator.now() < deadline do
		Emulator.run(0.5)
	end
	Emulator.run(1)
	H.expect(beaten.location == rock and beaten.retreating == nil, "it walked home and is a normal army again")
	H.expect(state.armies[beaten.id] ~= nil and Emulator.findText(alice, "🏳") == nil, "no flag once home")
	H.shot(alice, "home")
end

-- Phase 4: daily and weekly quests, the login calendar and the play streak. The 📜 button in the Lobby, a quest
-- finished in a match (recruit 5 regiments) and shown on Results, claimed, a daily quest rerolled; then DevDay moves
-- the server's day on: new quests, and the calendar and streak move on the next finished match (a missed day is
-- covered), up to the streak flame in the nations list.
function scenarios.quests()
	-- press a button inside one quest row (several rows show "Claim" or "🔄")
	local function pressIn(client, container: string, needle: string)
		local root = client.localPlayer.PlayerGui:FindFirstChild(container, true)
		assert(root, container .. " is not on screen")
		for _, d in root:GetDescendants() do
			if d:IsA("TextButton") and string.find(d.Text, needle, 1, true) then
				Emulator.eventOf(d, "Activated"):Fire(nil, 1)
				return
			end
		end
		error(container .. " has no button " .. needle)
	end
	local LobbyService = H.server("Services.LobbyService")
	local Data = H.server("Services.PlayerDataService")
	local workspace = Emulator.server.dm:GetService("Workspace")
	-- wait out the vote and the draft: the match starts in Peace with Alice seated
	local function waitForMatch(client)
		local deadline = Emulator.now() + 200
		while (LobbyService.active() or H.state().phase ~= "Peace" or H.myNation(client) == 0) and Emulator.now() < deadline do
			Emulator.run(1)
		end
		Emulator.run(1)
		H.expect(H.state().phase == "Peace" and H.myNation(client) ~= 0, "a match started with Alice in it")
	end
	-- hand Alice's nation half the land: domination, Results, the reward
	local function win(client)
		local state = H.state()
		local A = H.myNation(client)
		local total, given = 0, 0
		for _, p in state.provinces do
			total += 1
			given += if p.owner == A then 1 else 0
		end
		for _, p in state.provinces do
			if given < math.ceil(Config.Win.DominationShare * total) and p.owner ~= A and p.terrain ~= "Mountain" and not p.isCapital then
				p.owner = A
				given += 1
			end
		end
		Emulator.run(2.5)
		H.expect(state.result ~= nil and H.client(client, "ProfileState").reward() ~= nil, "Alice won and got her reward")
	end
	local function calendarLine(report)
		for _, line in report.reward.lines do
			if line.kind == "Calendar" then
				return line
			end
		end
		return nil
	end

	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	Emulator.run(2)
	local player = alice.serverPlayer
	local QuestState = H.client(alice, "QuestState")
	local view = QuestState.view()
	H.expect(view ~= nil and #view.daily == 3 and #view.weekly == 3, "Alice has 3 daily and 3 weekly quests")
	H.expect(view.daily[1].tier == "Easy" and view.daily[2].tier == "Medium" and view.daily[3].tier == "Hard", "one easy, one medium, one hard")
	local data = Data.data(player)
	local firstIds = {}
	for _, q in data.quests.daily do
		table.insert(firstIds, q.id)
	end

	-- the Lobby's 📜 button opens the Quests screen
	Emulator.run(2)
	H.shot(alice, "lobby_button")
	Emulator.press(alice, "📜")
	Emulator.run(0.5)
	H.expect(Emulator.findText(alice, "Daily quests") ~= nil, "the Quests screen opens from the Lobby")
	H.expect(Emulator.findText(alice, "1 free reroll today") ~= nil, "with today's free reroll")
	H.shot(alice, "lobby_quests")
	Emulator.press(alice, "✕")
	Emulator.run(0.3)

	-- the easy quest is "Recruit 5 regiments" for this test
	local recruitKey
	Data.update(player, function(d)
		local q = d.quests.daily[1]
		q.id = "recruit5"
		q.key = "d" .. q.day .. "-recruit5"
		recruitKey = q.key
	end)
	H.server("Services.QuestService").sendView(player)
	waitForMatch(alice)

	-- in the match, the quests open from the 🌍 nations drawer (the top bar has no room for another button)
	Emulator.press(alice, "🌍")
	Emulator.run(0.3)
	Emulator.press(alice, "📜 Quests")
	Emulator.run(0.5)
	H.expect(Emulator.findText(alice, "Recruit 5 regiments") ~= nil, "the Quests screen opens from the nations drawer")
	H.shot(alice, "match_quests")
	Emulator.press(alice, "✕")
	Emulator.press(alice, "🌍")
	Emulator.run(0.3)

	-- recruit 5 regiments at the capital, then win
	local state = H.state()
	local nation = state.nations[H.myNation(alice)]
	nation.gold, nation.manpower = 400, 20000
	Emulator.press(alice, "⭐")
	Emulator.run(1)
	for _ = 1, 5 do
		Emulator.press(alice, "Regiment")
		Emulator.run(1.2)
	end
	win(alice)
	Emulator.run(1)
	local report = H.client(alice, "ProfileState").reward()
	local cal = calendarLine(report)
	H.expect(cal ~= nil and cal.glory == 25, "the day's first finished match pays the calendar's first step (25 Glory)")
	H.expect(Emulator.findText(alice, "Play calendar 1/7") ~= nil, "on the Results breakdown")
	H.expect(Emulator.findText(alice, "Recruit 5 regiments: done!") ~= nil, "the Results screen shows the quest finished")
	H.expect(Emulator.findText(alice, "to claim") ~= nil, "and a Quests button with quests to claim")
	H.shot(alice, "results_quests")

	-- claim it from the Results screen's Quests button
	local xp0, glory0 = data.xp, data.glory
	Emulator.press(alice, "to claim")
	Emulator.run(0.5)
	H.shot(alice, "quest_done")
	pressIn(alice, "Quest_recruit5", "Claim")
	Emulator.run(1)
	local claimed
	for _, q in data.quests.daily do
		if q.key == recruitKey then
			claimed = q.claimed
		end
	end
	H.expect(claimed == true, "the quest is claimed")
	H.expect(data.xp == xp0 + 100 and data.glory >= glory0 + 30, "it paid 100 XP and 30 Glory")
	H.expect(Emulator.findText(alice, "✅ Recruit 5 regiments") ~= nil, "the row shows it claimed")
	pressIn(alice, "Quest_recruit5", "✅")
	Emulator.run(0.5)
	H.expect(data.xp == xp0 + 100, "a second claim pays nothing")

	-- reroll the hard quest (the free one)
	local hard = data.quests.daily[3]
	local hardId = hard.id
	pressIn(alice, "Quest_" .. hardId, "🔄 Free")
	Emulator.run(1)
	H.expect(data.quests.daily[3].id ~= hardId and data.quests.rerollsUsed == 1, "the hard quest was rerolled for another")
	H.expect((Emulator.findText(alice, "Rerolls: 100") ~= nil), "the next reroll costs 100 Glory")
	H.shot(alice, "rerolled")
	Emulator.press(alice, "✕")

	-- the next day (DevDay): new daily quests next to yesterday's unfinished ones; the calendar waits for a match
	workspace:SetAttribute("DevDay", 1)
	Emulator.run(7)
	view = QuestState.view()
	H.expect(#view.daily == 5, "yesterday's 2 unfinished quests stay next to today's 3 (the claimed one went)")
	H.expect(view.calendar.step == 1 and not view.calendar.playedToday, "the calendar waits on step 1 until Alice plays")
	H.expect(view.freeRerolls == 1, "a new free reroll")
	waitForMatch(alice)
	win(alice)
	report = H.client(alice, "ProfileState").reward()
	cal = calendarLine(report)
	H.expect(cal ~= nil and cal.glory == 25 and data.login.step == 2, "day 2: the calendar's second step (25 Glory)")
	H.expect(data.login.streak == 2, "a 2-day play streak")

	-- a day off, then a third play day: the missed day is covered, the streak reaches 3 (a flame)
	workspace:SetAttribute("DevDay", 2)
	Emulator.run(7)
	H.expect(QuestState.view().streak == 2, "after one missed day the streak still stands")
	waitForMatch(alice)
	win(alice)
	report = H.client(alice, "ProfileState").reward()
	cal = calendarLine(report)
	H.expect(cal ~= nil and cal.glory == 50 and data.login.step == 3, "the calendar paused over the missed day: step 3 (50 Glory)")
	H.expect(data.login.streak == 3 and data.login.best == 3, "the streak is 3 days")
	Emulator.run(1)
	Emulator.press(alice, "Quests")
	Emulator.run(0.5)
	H.expect(Emulator.findText(alice, "3-day play streak") ~= nil, "the Quests screen shows the streak")
	H.expect(Emulator.findText(alice, "Flame") ~= nil, "and the flame it earned")
	H.shot(alice, "calendar_streak")
	Emulator.press(alice, "✕")
	alice.localPlayer.PlayerGui.Results.Enabled = false -- the nations list under the Results panel
	if Emulator.findText(alice, "Not now") then
		Emulator.press(alice, "Not now") -- the starter-pack offer (after the 2nd match) is the shop's
	end
	Emulator.press(alice, "🌍")
	Emulator.run(0.5)
	H.expect(Emulator.findText(alice, "🔥") ~= nil, "Alice's nation shows the streak flame in the nations list")
	H.shot(alice, "nations_flame")
	local saved = Emulator.dataStores.PlayerData["Player_" .. player.UserId].value.Data
	H.expect(saved.login.step == 3 and saved.login.streak == 3, "the calendar and streak are saved")
	H.expect(#firstIds == 3, "the first day's quests: " .. table.concat(firstIds, ", "))
end

-- Phase 5: analytics. A new player (Alice) and a returning one (Bob) go through the Lobby, the shop, the starter
-- pack, a whole match and the start of the next one, where Carol joins, Bob is eliminated, rises as a Primordial
-- and leaves, and Carol leaves. The emulator records every AnalyticsService call (Emulator.analytics); each funnel,
-- economy, progression and custom event from docs/LAUNCH.md "Analytics events" is checked against them.
function scenarios.analytics()
	local Telemetry = require("../../src/shared/Sim/Telemetry")
	local ROBUX = utf8.char(0xE002)
	local log = Emulator.analytics
	-- recorded calls: { method, userId, args }; args follow the player (enums as names)
	local function calls(method: string, userId: number?, first: any?)
		local out = {}
		for _, r in log do
			if r.method == method and (userId == nil or r.userId == userId) and (first == nil or r.args[1] == first) then
				table.insert(out, r)
			end
		end
		return out
	end
	local function customs(name: string, userId: number?)
		return calls("LogCustomEvent", userId, name)
	end
	local function fields(r)
		local f = r.args[#r.args] or {}
		local keys = Emulator.roblox.Enum.AnalyticsCustomFieldKeys
		return table.concat({
			f[keys.CustomField01.Name] or "",
			f[keys.CustomField02.Name] or "",
			f[keys.CustomField03.Name] or "",
		}, ",")
	end
	-- the step names of one funnel for one player, in order (and their sessions)
	local function steps(funnel: string, userId: number)
		local names, sessions = {}, {}
		for _, r in calls("LogFunnelStepEvent", userId, funnel) do
			table.insert(names, r.args[4])
			table.insert(sessions, r.args[2])
		end
		return table.concat(names, ","), sessions
	end
	local function onboarding(userId: number)
		local names = {}
		for _, r in calls("LogOnboardingFunnelStepEvent", userId) do
			table.insert(names, r.args[2])
		end
		return table.concat(names, ",")
	end
	local function has(list: string, item: string): boolean
		return table.find(string.split(list, ","), item) ~= nil
	end
	local function economy(userId: number, sku: string)
		for _, r in calls("LogEconomyEvent", userId) do
			if r.args[6] == sku then
				return r
			end
		end
		return nil
	end
	local function pressIn(client, container: string, needle: string)
		local root = client.localPlayer.PlayerGui:FindFirstChild(container, true)
		assert(root, container .. " is not on screen")
		for _, d in root:GetDescendants() do
			if d:IsA("TextButton") and string.find(d.Text, needle, 1, true) then
				Emulator.eventOf(d, "Activated"):Fire(nil, 1)
				return
			end
		end
		error(container .. " has no button " .. needle)
	end
	local function await(fn, ...)
		local args = table.pack(...)
		local result
		Emulator.task.spawn(function()
			result = table.pack(fn(table.unpack(args, 1, args.n)))
		end)
		local deadline = Emulator.now() + 10
		while result == nil and Emulator.now() < deadline do
			Emulator.run(0.1)
		end
		assert(result, "timed out")
		return table.unpack(result, 1, result.n)
	end
	local function runUntil(cond, seconds: number)
		local deadline = Emulator.now() + seconds
		while not cond() and Emulator.now() < deadline do
			Emulator.run(1)
		end
	end
	local function dominate(state, nation)
		local total, given = 0, 0
		for _, p in state.provinces do
			total += 1
			given += if p.owner == nation then 1 else 0
		end
		for _, p in state.provinces do
			if given < math.ceil(Config.Win.DominationShare * total) and p.owner ~= nation and p.terrain ~= "Mountain" then
				p.owner = nation
				given += 1
			end
		end
	end

	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	local bob = Emulator.addClient("Bob")
	Emulator.run(3)
	local a, b = alice.serverPlayer.UserId, bob.serverPlayer.UserId
	local Data = H.server("Services.PlayerDataService")
	local ShopService = H.server("Services.ShopService")
	local LobbyService = H.server("Services.LobbyService")

	-- joining: onboarding, MatchFlow's first step, the first account level
	H.expect(onboarding(a) == "joined,lobby_loaded", "Alice's onboarding: joined, lobby_loaded")
	H.expect(steps("MatchFlow", a) == "lobby", "MatchFlow step 1 (lobby) for Alice")
	local start = calls("LogProgressionStartEvent", a, "AccountLevel")
	H.expect(#start == 1 and start[1].args[2] == 1 and start[1].args[3] == "Settler", "AccountLevel 1 (Settler) started")
	-- Bob has played before (two matches): no more onboarding for him from here on
	Data.update(bob.serverPlayer, function(data)
		data.stats.matches = 2
	end)

	-- the shop: opened, a tab, a Glory purchase, a Robux purchase (Studio test mode), a refused one
	Data.update(alice.serverPlayer, function(data)
		data.glory = 3000
	end)
	Emulator.press(alice, "🛒")
	Emulator.run(0.5)
	Emulator.press(alice, "Flags")
	Emulator.run(0.5)
	pressIn(alice, "Card_flag_sun", "🏅 1,200")
	Emulator.run(1)
	local sun = economy(a, "flag_sun")
	H.expect(sun and sun.args[1] == "Sink" and sun.args[2] == "Glory" and sun.args[5] == "Shop", "a Glory Shop sink: flag_sun")
	H.expect(sun.args[3] == 1200 and sun.args[4] == 1800, "1,200 Glory, ending balance 1,800")
	H.expect(fields(sun) == "1-9,false,false", "with level_bucket, is_vip, is_payer")
	Emulator.press(alice, "▶")
	Emulator.run(0.3)
	pressIn(alice, "Card_flag_comet", ROBUX .. " 149")
	Emulator.run(1.5)
	local comet = economy(a, "flag_comet")
	H.expect(comet and comet.args[2] == "Robux" and comet.args[5] == "IAP" and comet.args[3] == 149, "a Robux IAP sink: flag_comet, 149")
	local shopSteps, shopSessions = steps("Shop", a)
	H.expect(
		shopSteps == "shop_opened,item_viewed,purchase_prompted,purchase_completed,purchase_completed,purchase_prompted",
		"the Shop funnel: opened, viewed (once), Glory buy prompted + completed, Robux buy completed + prompted"
	)
	H.expect(shopSessions[1] == shopSessions[#shopSessions], "all in one shop session")
	local ok, reason = await(ShopService.apply, alice.serverPlayer, { kind = "Buy", item = "flag_comet", currency = "Robux" })
	H.expect(ok == false and reason == "Owned", "buying the Comet twice is refused")
	local failed = customs("purchase_failed", a)
	H.expect(#failed == 1 and fields(failed[1]) == "flag_comet,Owned,", "purchase_failed: product and reason")
	Emulator.press(alice, "✕")
	Emulator.run(0.3)
	Emulator.press(alice, "🛒")
	Emulator.run(0.3)
	local _, sessions = steps("Shop", a)
	H.expect(sessions[#sessions] ~= shopSessions[1], "opening the shop again starts a new Shop session")
	Emulator.press(alice, "✕")
	Emulator.run(0.3)

	-- the starter pack for Bob: shown, opened (the pop-up), prompted, completed
	ShopService.onPhase("Lobby")
	Emulator.run(1)
	H.expect(Emulator.findText(bob, "Starter Pack") ~= nil, "Bob sees the starter-pack offer")
	Emulator.press(bob, "Buy")
	Emulator.run(1.5)
	local starterSteps, starterSessions = steps("StarterPack", b)
	H.expect(
		starterSteps == "offer_shown,offer_opened,purchase_completed,purchase_prompted",
		"the StarterPack funnel: shown, opened, then the purchase (test mode grants before the prompt step)"
	)
	H.expect(starterSessions[1] == tostring(b), "its session is Bob's userId")
	H.expect(economy(b, "starter") ~= nil, "and a Robux IAP sink for the starter pack")
	H.expect(steps("StarterPack", a) == "", "Alice (no finished match) isn't offered it")

	-- the map vote: Alice votes, Bob doesn't
	Emulator.press(alice, "Card_eldmoor")
	Emulator.press(alice, "Card_eldmoor")
	runUntil(function()
		return LobbyService.phase() ~= "Lobby"
	end, 70)
	local votes = customs("map_vote")
	H.expect(#votes == 1 and votes[1].userId == a and fields(votes[1]) == "eldmoor,lobby,fantasy", "map_vote: eldmoor, lobby, fantasy")
	H.expect(has(onboarding(a), "map_voted"), "Alice's onboarding: map_voted")

	-- the draft runs out: the match starts in Peace
	runUntil(function()
		return H.state().phase == "Peace" and not LobbyService.active()
	end, 40)
	Emulator.run(2)
	local state = H.state()
	local A, B = H.myNation(alice), H.myNation(bob)
	H.expect(A ~= 0 and B ~= 0, "both have a nation")
	H.expect(steps("MatchFlow", a) == "lobby,pick,peace", "MatchFlow for Alice: lobby, pick, peace")
	H.expect(steps("MatchFlow", b) == "lobby,pick,peace", "and for Bob")
	H.expect(has(onboarding(a), "nation_picked") and not has(onboarding(b), "nation_picked"), "onboarding: Alice picked a nation; Bob is past onboarding")

	-- War: nation_start for all ten nations after the first minute
	local Intents = H.client(alice, "Intents")
	Intents.develop(state.nations[A].capital) -- a command, so the jump to War isn't idle time
	Emulator.run(1.5)
	state.tick = Config.Phases.PeaceEndTick - 1
	Emulator.run(2)
	H.expect(state.phase == "War", "War")
	H.expect(has(steps("MatchFlow", a), "war"), "MatchFlow: war")
	local starts = customs("nation_start")
	H.expect(#starts == Config.NationsPerMatch, "nation_start for every nation")
	local humans = 0
	for _, r in starts do
		humans += if string.find(fields(r), "human", 1, true) then 1 else 0
	end
	H.expect(humans == 2 and fields(starts[A]) == "eldmoor," .. A .. ",human", "two of them human, with map and start nation")
	H.expect(starts[1].userId == a, "match-wide events go out for the lowest userId in the server")

	-- Bob uses a power on his own land
	state.nations[B].charges = 2
	H.client(bob, "Intents").power("Blessing", state.nations[B].capital)
	Emulator.run(1.5)
	local powers = customs("primordial_power_used", b)
	H.expect(#powers == 1 and fields(powers[1]) == "Blessing,eldmoor,living", "primordial_power_used: Blessing, eldmoor, living")

	-- Alice wins: match_end, match_win, player_result, Results, the reward's economy and progression events
	Intents.develop(state.nations[A].capital)
	Emulator.run(1.5)
	dominate(state, A)
	Emulator.run(2)
	H.expect(state.result ~= nil and state.result.kind == "Domination", "Alice won by domination")
	local ended = customs("match_end")
	H.expect(#ended == 1 and fields(ended[1]) == "eldmoor,domination,1-3", "match_end: eldmoor, domination, 1-3 humans")
	H.expect(ended[1].args[2] == Telemetry.minutes(state.result.endedAt), string.format("its value is the match length (%.1f min)", ended[1].args[2]))
	local wins = customs("match_win")
	H.expect(#wins == 1 and fields(wins[1]) == "eldmoor," .. A .. ",domination", "match_win: Alice's start nation")
	local results = customs("player_result")
	H.expect(#results == Config.NationsPerMatch, "player_result for every nation")
	local mine = results[A]
	H.expect(mine.userId == a and mine.args[2] == 1 and fields(mine) == "eldmoor," .. A .. ",human", "Alice placed 1st")
	H.expect(has(steps("MatchFlow", a), "results") and has(steps("MatchFlow", b), "results"), "MatchFlow: results")
	H.expect(has(onboarding(a), "first_match_finished"), "Alice's onboarding: first_match_finished")
	local data = Data.data(alice.serverPlayer)
	local matchReward, levelUp = economy(a, "match_reward"), economy(a, "level_up")
	H.expect(matchReward and matchReward.args[1] == "Source" and matchReward.args[5] == "Gameplay", "a Glory Gameplay source: match_reward")
	H.expect(levelUp and levelUp.args[3] == Config.Progression.LevelUpGlory, "and level_up (50 Glory)")
	H.expect(levelUp.args[4] == data.glory and matchReward.args[4] == data.glory - levelUp.args[3], "with the ending balances")
	H.expect(fields(matchReward) == "1-9,false,true", "Alice is a payer now")
	local done = calls("LogProgressionCompleteEvent", a, "AccountLevel")
	H.expect(#done == 1 and done[1].args[2] == 1, "AccountLevel 1 completed")
	H.expect(#calls("LogProgressionStartEvent", a, "AccountLevel") == 2, "and level 2 started")
	local firstSession = select(2, steps("MatchFlow", a))[1]

	-- the next-map vote: a new MatchFlow session, round "next"
	runUntil(function()
		return LobbyService.phase() == "Lobby"
	end, 40)
	Emulator.run(1)
	local _, flowSessions = steps("MatchFlow", a)
	H.expect(flowSessions[#flowSessions] ~= firstSession, "the next Lobby starts a new MatchFlow session")
	for _, client in { alice, bob } do
		Emulator.press(client, "Card_skyshards")
		Emulator.press(client, "Card_skyshards")
	end
	runUntil(function()
		return LobbyService.phase() ~= "Lobby"
	end, 70)
	votes = customs("map_vote")
	H.expect(#votes == 3 and fields(votes[3]) == "skyshards,next,sky", "map_vote round next")
	runUntil(function()
		return H.state().phase == "Peace" and not LobbyService.active()
	end, 40)
	Emulator.run(2)
	state = H.state()
	local nextStarted = 0
	for _, r in calls("LogFunnelStepEvent", nil, "MatchFlow") do
		if r.args[4] == "next_match_started" and r.args[2] == firstSession then
			nextStarted += 1
		end
	end
	H.expect(nextStarted == 1, "MatchFlow next_match_started on Alice's first-match session")
	local bobNext = 0
	for _, r in calls("LogFunnelStepEvent", b, "MatchFlow") do
		bobNext += if r.args[4] == "next_match_started" then 1 else 0
	end
	H.expect(bobNext == 1, "and on Bob's")
	H.expect(has(onboarding(a), "second_match_started"), "Alice's onboarding: second_match_started")

	-- Carol joins mid-match; Cataclysm; everyone has been idle for 17 minutes
	local carol = Emulator.addClient("Carol")
	Emulator.run(3)
	local c = carol.serverPlayer.UserId
	B = H.myNation(bob)
	state.tick = Config.Phases.WarEndTick - 1
	Emulator.run(2)
	H.expect(state.phase == "Cataclysm", "Cataclysm")
	H.expect(has(steps("MatchFlow", c), "cataclysm"), "MatchFlow: cataclysm (for Carol too, who joined late)")
	local afk = customs("afk_flagged", b)
	H.expect(#afk == 1 and fields(afk[1]) == "skyshards,Cataclysm,", "afk_flagged for Bob, once")

	-- Bob loses everything: player_eliminated, then he rises as a Primordial and uses a power
	for _, p in state.provinces do
		if p.owner == B then
			p.owner = H.myNation(alice)
		end
	end
	Emulator.run(2)
	H.expect(state.nations[B].eliminated and state.primordials[b] ~= nil, "Bob was eliminated and rose as a Primordial")
	local out = customs("player_eliminated", b)
	H.expect(#out == 1 and fields(out[1]) == "skyshards," .. B .. ",Cataclysm", "player_eliminated: map, start nation, phase")
	state.primordials[b].charges = 2
	H.client(bob, "Intents").power("Blessing", state.nations[H.myNation(alice)].capital)
	Emulator.run(1.5)
	powers = customs("primordial_power_used", b)
	H.expect(#powers == 2 and fields(powers[2]) == "Blessing,skyshards,primordial", "primordial_power_used by a Primordial")

	-- Bob and Carol leave
	Emulator.removeClient(bob)
	Emulator.run(1)
	local quits = customs("player_quit", b)
	H.expect(#quits == 1 and fields(quits[1]) == "skyshards,Cataclysm,true", "player_quit: Cataclysm, was a Primordial")
	H.expect(#customs("bot_replaced_leaver", b) == 0, "no bot takes over an eliminated nation")
	Emulator.removeClient(carol)
	Emulator.run(1)
	quits = customs("player_quit", c)
	H.expect(#quits == 1 and fields(quits[1]) == "skyshards,Cataclysm,false", "Carol's player_quit")
	local replaced = customs("bot_replaced_leaver", c)
	H.expect(#replaced == 1 and fields(replaced[1]) == "skyshards,Cataclysm,", "bot_replaced_leaver for Carol's nation")
	H.expect(replaced[1].args[2] == quits[1].args[2] and quits[1].args[2] >= 20, "both at the minute she left")

	-- the limits: known names only, at most 3 fields, no player names anywhere, nothing dropped
	local known = {}
	for _, name in Telemetry.CUSTOM_EVENTS do
		known[name] = true
	end
	local clean = true
	for _, r in log do
		if r.method == "LogCustomEvent" and not known[r.args[1]] then
			clean = false
		end
		for _, arg in r.args do
			local values = if type(arg) == "table" then arg else { arg }
			local count = 0
			for _, v in values do
				count += 1
				if type(v) == "string" and (string.find(v, "Alice") or string.find(v, "Bob") or string.find(v, "Carol")) then
					clean = false
				end
			end
			if type(arg) == "table" and count > 3 then
				clean = false
			end
		end
	end
	H.expect(clean, string.format("all %d events use known names, at most 3 fields and no player names", #log))
	local dropped = false
	for _, line in Emulator.log() do
		dropped = dropped or string.find(line, "over budget", 1, true) ~= nil
	end
	H.expect(not dropped, "nothing was dropped by the per-minute budget")
end

-- Phase 4: cosmetics in the match, part 2. In the Lobby Alice buys and equips the Night theme (Carol has it too,
-- Bob brings Winter) and they all vote Earth: Night wins the theme vote, the draft credits Alice and Carol, and
-- everyone's map is painted in Night. Bob opts out and sees the classic map. Then each power-effect variant plays
-- through the real flow (cast -> event with the caster -> Effects in the caster's look), photographed mid-animation.
function scenarios.themes()
	local Primordial = require("../../src/shared/Sim/Primordial")
	local Army = require("../../src/shared/Sim/Army")
	-- press a button on one shop card (several cards show the same price)
	local function pressIn(client, container: string, needle: string)
		local root = client.localPlayer.PlayerGui:FindFirstChild(container, true)
		assert(root, container .. " is not on screen")
		for _, d in root:GetDescendants() do
			if d:IsA("TextButton") and string.find(d.Text, needle, 1, true) then
				Emulator.eventOf(d, "Activated"):Fire(nil, 1)
				return
			end
		end
		error(container .. " has no button " .. needle)
	end
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	local bob = Emulator.addClient("Bob")
	local carol = Emulator.addClient("Carol")
	Emulator.run(2)
	local Data = H.server("Services.PlayerDataService")
	local LobbyService = H.server("Services.LobbyService")
	H.expect(LobbyService.phase() == "Lobby", "the server opens the Lobby")

	-- Alice buys the Night theme for Glory and equips it; her power effects are all variants
	Data.update(alice.serverPlayer, function(d)
		d.glory = 3000
		d.owned.fx_meteor_comet, d.owned.fx_plague_violet, d.owned.fx_blessing_rays = true, true, true
		d.equipped.PowerFxMeteor = "fx_meteor_comet"
		d.equipped.PowerFxPlague = "fx_plague_violet"
		d.equipped.PowerFxBlessing = "fx_blessing_rays"
	end)
	Data.update(carol.serverPlayer, function(d)
		d.owned.theme_night = true
		d.equipped.Theme = "theme_night"
	end)
	Data.update(bob.serverPlayer, function(d)
		d.owned.theme_winter, d.owned.fx_meteor_ice = true, true
		d.equipped.Theme = "theme_winter"
		d.equipped.PowerFxMeteor = "fx_meteor_ice"
	end)
	H.server("Services.ShopService").onPhase("Lobby")
	Emulator.run(1)
	Emulator.press(alice, "🛒")
	Emulator.run(0.5)
	Emulator.press(alice, "Themes")
	Emulator.run(1)
	H.expect(alice.localPlayer.PlayerGui:FindFirstChild("ThemePreview", true) ~= nil, "theme cards show a painted map")
	pressIn(alice, "Card_theme_night", "🏅 1,200")
	Emulator.run(1)
	local data = Data.data(alice.serverPlayer)
	H.expect(data.owned.theme_night == true and data.glory == 1800, "Night bought for 1,200 Glory")
	pressIn(alice, "Card_theme_night", "Equip")
	Emulator.run(1)
	H.expect(data.equipped.Theme == "theme_night", "Alice equipped Night")
	H.expect(Emulator.findText(alice, "What you see") ~= nil, "the Themes tab has the opt-out card")
	H.shot(alice, "shop_themes")
	Emulator.press(alice, "Powers")
	Emulator.run(1)
	H.expect(alice.localPlayer.PlayerGui:FindFirstChild("EffectPreview", true) ~= nil, "power effects show a preview")
	H.shot(alice, "shop_powers")
	Emulator.press(alice, "✕")
	Emulator.run(0.5)

	-- the vote: Alice's cards are painted in Night; everyone votes Earth (Night 2, Winter 1)
	Emulator.run(2)
	H.expect(Emulator.findText(alice, "You bring the Night theme") ~= nil, "the vote says Alice brings Night")
	H.expect(H.client(alice, "Cosmetics").myTheme() == "night", "her thumbnails are painted in Night")
	H.shot(alice, "vote_night_cards")
	for _, client in { alice, bob, carol } do
		Emulator.press(client, "Card_earth")
		Emulator.press(client, "Card_earth")
	end
	local deadline = Emulator.now() + 70
	while LobbyService.phase() == "Lobby" and Emulator.now() < deadline do
		Emulator.run(1)
	end
	local state = H.state()
	H.expect(state.mapId == "earth" and state.theme == "theme_night", "Earth won, painted in Night (2 votes to 1)")
	Emulator.run(1.5)
	H.expect(Emulator.findText(alice, "Night Earth, brought by Alice, Carol") ~= nil, "the draft credits its owners")
	H.shot(bob, "draft_night_earth")

	-- the match: every client paints Night
	deadline = Emulator.now() + 60
	while state.phase == "Pick" and Emulator.now() < deadline do
		Emulator.run(1)
	end
	Emulator.run(2)
	H.expect(state.phase == "Peace", "the match started")
	for _, client in { alice, bob, carol } do
		H.expect(H.client(client, "ClientState").snapshot().theme == "theme_night", client.name .. " got the theme")
		H.expect(H.client(client, "Cosmetics").matchTheme() == "night", client.name .. " paints the map in Night")
	end
	Emulator.run(3) -- the painting is spread over frames
	H.shot(alice, "night_earth")
	local A, B = H.myNation(alice), H.myNation(bob)
	local MapView = H.client(alice, "MapView")
	local capital = state.nations[A].capital
	MapView.centreOn(H.provinceMap(alice, capital), true)
	Emulator.run(2)
	H.shot(alice, "night_close_up")

	-- Bob opts out: "always classic", saved in his profile; his map repaints in the classic look
	Emulator.press(bob, "🛒")
	Emulator.run(0.5)
	Emulator.press(bob, "Themes")
	Emulator.run(0.5)
	pressIn(bob, "Card_ThemeSetting", "Always classic")
	Emulator.run(1)
	H.expect(Data.data(bob.serverPlayer).settings.defaultTheme == true, "the opt-out is saved")
	H.expect(H.client(bob, "Cosmetics").matchTheme() == "", "Bob's map goes back to classic")
	Emulator.press(bob, "✕")
	Emulator.run(3)
	H.shot(bob, "bob_opted_out")
	H.expect(H.client(alice, "Cosmetics").matchTheme() == "night", "Alice still sees Night")

	-- War: each power-effect variant, cast through Sim.Primordial (the event carries the caster)
	state.tick = 179
	Emulator.run(2)
	local Effects = H.client(alice, "Effects")
	local function cast(by: number, power: string, target: number)
		state.nations[by].charges = 5
		for _, n in state.nations do
			n.powerImmuneUntil = 0
		end
		local ok, why = Primordial.use(state, { nation = by }, power, target)
		H.expect(ok, power .. " was cast (" .. tostring(why) .. ")")
	end
	local function waitFor(kind: string, look: string)
		local start = Emulator.now()
		local function seen()
			for _, h in Effects.history() do
				if h.at >= start and h.kind == kind and h.look == look then
					return true
				end
			end
			return false
		end
		local until_ = Emulator.now() + 5
		while not seen() and Emulator.now() < until_ do
			Emulator.run(0.1)
		end
		H.expect(seen(), kind .. " plays in the " .. (if look == "" then "default" else look) .. " look")
	end
	local bobCapital = state.nations[B].capital
	MapView.centreOn(H.provinceMap(alice, bobCapital), true)
	Emulator.run(1.5)
	local target = Army.spawn(state, B, bobCapital, 6000)
	Emulator.run(1.2)
	cast(A, "Meteor", target.id)
	waitFor("Meteor", "comet")
	Emulator.run(0.45)
	H.shot(alice, "fx_comet_falling")
	Emulator.run(0.45)
	H.shot(alice, "fx_comet_impact")
	Emulator.run(3)

	cast(A, "Plague", B)
	waitFor("Plague", "violet")
	Emulator.run(0.5)
	H.shot(alice, "fx_violet_plague")
	Emulator.run(3)

	MapView.centreOn(H.provinceMap(alice, capital), true)
	Emulator.run(1.5)
	cast(A, "Blessing", capital)
	waitFor("Blessing", "rays")
	Emulator.run(0.6)
	H.shot(alice, "fx_sun_rays")
	Emulator.run(3)

	local mine = Army.spawn(state, A, capital, 6000)
	Emulator.run(1.2)
	cast(B, "Meteor", mine.id)
	waitFor("Meteor", "ice")
	Emulator.run(0.45)
	H.shot(alice, "fx_ice_falling")
	Emulator.run(0.45)
	H.shot(alice, "fx_ice_impact")
	Emulator.run(3)

	-- Carol has no variants: her Meteor keeps the default look; sounds are the same cue for every look
	local C = H.myNation(carol)
	Army.spawn(state, A, capital, 6000) -- joins the army already standing there (stacks merge)
	Emulator.run(1.2)
	local other
	for _, army in state.armies do
		if army.owner == A and army.location == capital then
			other = army
		end
	end
	cast(C, "Meteor", other.id)
	waitFor("Meteor", "")
	Emulator.run(2)
	local impacts = 0
	for _, s in Emulator.sounds do
		if s.name == "MeteorImpact" then
			impacts += 1
		end
	end
	H.expect(impacts >= 3, "every Meteor look lands with the same impact sound")
end

---------------------------------------------------------------------------------------------- main

-- Phase 4: private server settings. Olivia owns the server (Workspace "PrivateServerOwner"): in the Lobby she sets
-- a 15-minute match with 5 Hard bots, powers off, Eldmoor, and puts herself and Pete in one team. Pete can't change
-- anything. The match plays those settings and ends at 15:00, paying half (custom rules, 2 players).
function scenarios.private()
	Emulator.run(1)
	local olivia = Emulator.addClient("Olivia", nil, PRIVATE_OWNER)
	local pete = Emulator.addClient("Pete")
	Emulator.run(2)
	local LobbyService = H.server("Services.LobbyService")
	H.expect(LobbyService.phase() == "Lobby", "the private server opens the Lobby")
	H.expect(LobbyService.state().owner == PRIVATE_OWNER, "the server knows its owner")
	H.expect(Emulator.findText(olivia, "⚙ Settings") ~= nil, "Olivia, the owner, sees ⚙ Settings")
	H.expect(Emulator.findText(pete, "⚙ Settings") == nil, "Pete doesn't")
	H.expect(Emulator.findText(pete, "🔒 Private server") ~= nil, "everyone sees the settings summary")
	Emulator.run(2)
	H.shot(pete, "vote_summary")

	-- Pete tries anyway: the server refuses
	H.client(pete, "Intents").setting("minutes", 15)
	Emulator.run(1.5)
	H.expect(LobbyService.state().settings.minutes == 25, "Pete can't change the match length")
	H.expect(Emulator.findText(pete, "Only the server's owner") ~= nil, "Pete is told why")

	Emulator.press(olivia, "⚙ Settings")
	Emulator.run(0.5)
	H.expect(Emulator.findText(olivia, "Private server settings") ~= nil, "the settings sheet opens")
	H.expect(Emulator.findText(olivia, "full XP and Glory") == nil, "two players: the sheet says the rewards are half")
	H.shot(olivia, "settings_default")
	for _, name in { "Setting_minutes_15", "Setting_difficulty_Hard", "Setting_powers_false", "Setting_map_eldmoor" } do
		Emulator.press(olivia, name)
	end
	for _ = 1, 4 do
		Emulator.press(olivia, "BotsLess")
		Emulator.run(1.1) -- each step counts down from the last view
	end
	Emulator.press(olivia, "Team_" .. PRIVATE_OWNER)
	Emulator.press(olivia, "Team_" .. pete.serverPlayer.UserId)
	Emulator.run(1.5)
	local s = LobbyService.state().settings
	H.expect(s.minutes == 15 and s.difficulty == "Hard" and s.powers == false, "15 minutes, Hard bots, powers off")
	H.expect(s.bots == 5 and s.map == "eldmoor", "5 bots, on Eldmoor")
	H.expect(#s.teams == 2 and s.teams[1].team == 1 and s.teams[2].team == 1, "Olivia and Pete are team 1")
	H.expect(LobbyService.state().locked == "eldmoor", "the map setting locks the vote to Eldmoor")
	H.expect(Emulator.findText(olivia, "custom rules") ~= nil, "the sheet says custom rules pay half")
	H.shot(olivia, "settings_custom")
	Emulator.press(olivia, "SettingsDone")
	Emulator.run(0.5)
	H.expect(Emulator.findText(pete, "15 min") ~= nil and Emulator.findText(pete, "5 Hard bots") ~= nil, "Pete sees them")
	H.expect(Emulator.findText(pete, "powers off") ~= nil, "including powers off")
	H.shot(pete, "vote_locked")

	-- the vote runs out, nobody picks: the draft gives everyone a nation, then the match plays the settings
	local deadline = Emulator.now() + 120
	while (LobbyService.active() or H.state().phase == "Pick") and Emulator.now() < deadline do
		Emulator.run(1)
	end
	Emulator.run(1)
	local state = H.state()
	H.expect(state.mapId == "eldmoor" and state.phase == "Peace", "the match started on Eldmoor in Peace")
	H.expect(state.setup.private and state.setup.settings.minutes == 15, "the match setup carries the settings")
	local nations, bots = 0, 0
	for _, n in state.nations do
		nations += 1
		bots += if n.controller == "Bot" then 1 else 0
	end
	H.expect(nations == 7 and bots == 5, "2 players + 5 bots: the other 3 nations left the map")
	H.expect(H.server("Services.AIService").difficulty() == "Hard", "the bots play Hard")
	local O, P = H.myNation(olivia), H.myNation(pete)
	H.expect(O ~= 0 and P ~= 0 and state.nations[O].allianceId ~= nil, "both players have a nation")
	H.expect(state.nations[O].allianceId == state.nations[P].allianceId, "Olivia and Pete start allied (team 1)")
	H.expect(Emulator.findText(olivia, "🕊 14:5") ~= nil, "the clock counts down from 15:00")
	H.expect(Emulator.findText(olivia, "✨\n⚡") == nil, "no power button with powers off")
	H.shot(olivia, "match_start")

	-- powers are refused, and so is a new alliance (teams are locked)
	local workspace = Emulator.server.dm:GetService("Workspace")
	workspace:SetAttribute("DevTick", 179)
	Emulator.run(1.5)
	-- toasts queue up one after another: wait until this one shows
	local function toastShows(text: string): boolean
		local until_ = Emulator.now() + 12
		while Emulator.findText(olivia, text) == nil and Emulator.now() < until_ do
			Emulator.run(0.5)
		end
		return Emulator.findText(olivia, text) ~= nil
	end
	H.client(olivia, "Intents").power("Blessing", state.nations[O].capital)
	H.expect(toastShows("Powers are off"), "a power is refused: powers are off")
	local other = nil
	for id, n in state.nations do
		if id ~= O and id ~= P and n.controller == "Bot" then
			other = id
		end
	end
	H.client(olivia, "Intents").diplomacy("Ally", other)
	H.expect(toastShows("Teams are set"), "no new alliances: teams are locked")

	-- the Cataclysm at 10:00, the end at 15:00. The clock jumps less than the AFK time (5 min) at a time, and
	-- Olivia gives an order after each jump, so the match still pays her.
	local function jump(tick: number)
		workspace:SetAttribute("DevTick", tick)
		Emulator.run(1.5)
		H.client(olivia, "Intents").develop(state.nations[O].capital)
		Emulator.run(1)
	end
	jump(400)
	jump(599)
	H.expect(state.phase == "Cataclysm", "the Cataclysm starts at 10:00 (the last 5 minutes)")
	jump(850)
	workspace:SetAttribute("DevTick", 897)
	Emulator.run(4)
	H.expect(state.result ~= nil and state.result.endedAt == 15 * 60, "the match ended at 15:00")
	Emulator.run(1)
	local report = H.client(olivia, "ProfileState").reward()
	local half = false
	for _, line in report.reward.lines do
		half = half or line.kind == "CustomRules"
	end
	H.expect(half, "custom rules pay half")
	H.expect(Emulator.findText(olivia, "Private server: half") ~= nil, "the Results screen says so")
	H.shot(olivia, "results")
	Emulator.run(31)
	H.expect(LobbyService.phase() == "Lobby", "the next Lobby opens")
	H.expect(LobbyService.state().settings.minutes == 15, "and keeps the settings")
	H.expect(LobbyService.state().locked == "eldmoor", "including the map")
end

local function runScenario(name: string)
	print(string.format("\n== scenario: %s ==", name))
	shotCount = 0
	shotDir = OUT .. "/" .. name
	if fs.isDir(shotDir) then
		fs.removeDir(shotDir)
	end
	fs.writeDir(shotDir)
	-- scenarios start straight in Peace (Workspace "SkipLobby") unless they test the Lobby itself
	local withLobby = LOBBY_SCENARIOS[name] == true
	local attributes = { SkipLobby = not withLobby }
	if TUTORIAL_SCENARIOS[name] then
		attributes.Tutorial = true
	end
	if name == "private" then
		attributes.PrivateServerOwner = PRIVATE_OWNER
	end
	Emulator.boot(fs.readFile("build/game.rbxlx"), if withLobby then nil else process.env.MAP, attributes)
	scenarios[name]()
	Emulator.assertClean(name)
	print(string.format("== %s passed (%.0f s of game time) ==", name, Emulator.now()))
end

if scenarioName == "all" then
	local names = {}
	for name in scenarios do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local r = process.exec("lune", { "run", "tools/harness/play", name }, { stdio = "inherit" })
		if not r.ok then
			process.exit(1)
		end
	end
else
	assert(scenarios[scenarioName], "unknown scenario " .. scenarioName)
	runScenario(scenarioName)
end
