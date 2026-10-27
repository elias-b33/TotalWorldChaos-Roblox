--!nocheck
-- Plays scripted scenarios against the real server and client scripts (built place), headlessly.
--
--   mkdir -p build && rojo build -o build/game.rbxlx
--   lune run tools/harness/play smoke          # one scenario
--   lune run tools/harness/play all            # every scenario
--
-- Screenshots go to tools/harness/out/<scenario>/NN_name.png (rendered by render_scene.py).
-- A scenario fails on any script error, any warn(), any table Roblox would mangle over the network,
-- or a failed expectation.

local fs = require("@lune/fs")
local process = require("@lune/process")

local Emulator = require("./Emulator")
local Scene = require("./Scene")

local OUT = "tools/harness/out"
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
	fs.removeFile(base .. ".json")
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

function H.provinceWorld(client, provinceId: number)
	local MapRenderer = H.client(client, "MapRenderer")
	local map = H.client(client, "ClientState").map()
	return MapRenderer.toWorld(map.provinces[provinceId].center)
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

	-- tap a foreign province through the camera and raycast
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
	local CameraController = H.client(alice, "CameraController")
	CameraController.centreOn(H.provinceWorld(alice, foreign), true)
	Emulator.run(2)
	Emulator.tapWorld(alice, H.provinceWorld(alice, foreign) + Emulator.roblox.Vector3.new(0, 1, 0))
	Emulator.run(0.5)
	local owner = ClientState.nation(state.provinces[foreign].owner)
	H.expect(Emulator.findText(alice, owner.name) ~= nil, "Tapping a foreign province shows its owner")
	H.shot(alice, "foreign")

	local gold0 = nation.gold
	Emulator.run(30)
	H.expect(nation.gold > gold0, "Income arrives every month")
	H.expect(ClientState.nation(me).gold == nation.gold, "The client's gold matches the server")
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

local function tapProvince(client, provinceId: number)
	local CameraController = H.client(client, "CameraController")
	CameraController.centreOn(H.provinceWorld(client, provinceId), true)
	Emulator.run(1.5)
	-- aim a little off-centre so army tokens standing at the centre don't catch the tap
	Emulator.tapWorld(client, H.provinceWorld(client, provinceId) + Emulator.roblox.Vector3.new(0, 1, 4))
	Emulator.run(0.3)
end

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

	-- give Aurora 40% of the world: domination and the results screen
	local need = math.ceil(0.4 * 131)
	local given = 0
	for _, p in state.provinces do
		if p.owner == A then
			given += 1
		end
	end
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

---------------------------------------------------------------------------------------------- main

local function runScenario(name: string)
	print(string.format("\n== scenario: %s ==", name))
	shotCount = 0
	shotDir = OUT .. "/" .. name
	if fs.isDir(shotDir) then
		fs.removeDir(shotDir)
	end
	fs.writeDir(shotDir)
	Emulator.boot(fs.readFile("build/game.rbxlx"))
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
