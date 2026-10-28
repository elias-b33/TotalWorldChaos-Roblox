--!nocheck
-- Plays scripted scenarios against the real server and client scripts (built place), headlessly.
--
--   mkdir -p build && rojo build -o build/game.rbxlx
--   lune run tools/harness/play smoke          # one scenario
--   lune run tools/harness/play all            # every scenario
--   MAP=earth lune run tools/harness/play smoke  # on another map (default: Config.DefaultMap)
--
-- Every scenario is its own file, tools/harness/scenarios/<name>.luau, returning { run = function } plus its boot
-- options: lobby = true (it runs the Lobby; the rest boot with SkipLobby), tutorial = true (a tutorial server),
-- map = "earth" (the map it needs; MAP still overrides it) and attributes (extra Workspace attributes). Shared helpers
-- live in tools/harness/H.luau. Adding a scenario is adding a file: nothing else lists them.
-- Screenshots go to tools/harness/out/<scenario>/NN_name.png (rendered by render_scene.py). NO_SHOTS=1 skips the
-- PNG renders (every check still runs): much faster for verification runs that nobody looks at.
-- A scenario fails on any script error, any warn(), any table Roblox would mangle over the network,
-- or a failed expectation.

local fs = require("@lune/fs")
local process = require("@lune/process")

local Emulator = require("./Emulator")
local H = require("./H")

local DIR = "tools/harness/scenarios"
local scenarioName = process.args[1] or "smoke"

local function names(): { string }
	local list = {}
	for _, entry in fs.readDir(DIR) do
		local name = string.match(entry, "^(%w+)%.luau$")
		if name then
			table.insert(list, name)
		end
	end
	table.sort(list)
	return list
end

local function runScenario(name: string)
	print(string.format("\n== scenario: %s ==", name))
	local scenario = require("./scenarios/" .. name)
	H.begin(name)
	-- scenarios start straight in Peace (Workspace "SkipLobby") unless they test the Lobby itself
	local attributes = { SkipLobby = not scenario.lobby }
	if scenario.tutorial then
		attributes.Tutorial = true
	end
	for key, value in scenario.attributes or {} do
		attributes[key] = value
	end
	local map = if scenario.lobby then nil else process.env.MAP or scenario.map
	Emulator.boot(fs.readFile("build/game.rbxlx"), map, attributes)
	scenario.run()
	Emulator.assertClean(name)
	print(string.format("== %s passed (%.0f s of game time) ==", name, Emulator.now()))
end

if scenarioName == "all" then
	for _, name in names() do
		local r = process.exec("lune", { "run", "tools/harness/play", name }, { stdio = "inherit" })
		if not r.ok then
			process.exit(1)
		end
	end
else
	assert(fs.isFile(DIR .. "/" .. scenarioName .. ".luau"), "unknown scenario " .. scenarioName)
	runScenario(scenarioName)
end
