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
