--!nocheck
-- A whole match, headlessly: one idle player and nine bots for the full 25 minutes, then Results and the start
-- of the next match. Fails on any script error or warn(), or if the player's screen ever holds more GUI objects
-- than the budget (docs/DESIGN.md "Performance budget"). Prints one line per game minute.
--
--   mkdir -p build && rojo build -o build/game.rbxlx
--   lune run tools/harness/soak                 # Config.DefaultMap; MAP=earth for another map
--   SHOTS=1 lune run tools/harness/soak         # plus a screenshot every 5 minutes in tools/harness/out/soak/
local fs = require("@lune/fs")
local process = require("@lune/process")

local Emulator = require("./Emulator")
local Scene = require("./Scene")

local OUT = "tools/harness/out/soak"
local GUI_BUDGET = 2000
local MINUTES = 26.5 -- the match, Results and the first seconds of the next match

local function server(path: string)
	local node = Emulator.server.dm:GetService("ServerScriptService").Server
	for _, name in string.split(path, ".") do
		node = node:FindFirstChild(name)
	end
	return Emulator.server.modules[node]
end

local function guiObjects(client): number
	local n = 0
	for _, d in client.localPlayer.PlayerGui:GetDescendants() do
		if d:IsA("GuiObject") then
			n += 1
		end
	end
	return n
end

local function shot(client, name: string)
	if fs.isDir(OUT) == false then
		fs.writeDir(OUT)
	end
	local base = OUT .. "/" .. name
	Scene.save(client, base .. ".json")
	local r = process.exec("python3", { "tools/harness/render_scene.py", base .. ".json", base .. ".png" })
	assert(r.ok, "render failed: " .. r.stderr)
	fs.removeFile(base .. ".json")
	for _, entry in fs.readDir(OUT) do
		if string.find(entry, "%.rgba$") then
			fs.removeFile(OUT .. "/" .. entry)
		end
	end
	print("  📸 " .. base .. ".png")
end

if fs.isDir(OUT) then
	fs.removeDir(OUT)
end
Emulator.setQuiet(true)
Emulator.boot(fs.readFile("build/game.rbxlx"), process.env.MAP, { SkipLobby = true })
Emulator.run(1)
local alice = Emulator.addClient("Alice")
Emulator.run(1)

local MatchService = server("Services.MatchService")
local first = MatchService.state()
local me = alice.modules[alice.localPlayer.PlayerScripts.Client.ClientState].myNation()
print(string.format("soak on %s: Alice is nation %d, nine bots", first.mapId, me))
print(" clock   phase       gui  armies  Alice  wars  Lua MB  wall s")

local peak, peakAt = 0, ""
local wall0 = os.clock()
for minute = 1, math.ceil(MINUTES) do
	local t0 = os.clock()
	Emulator.run(60)
	local state = MatchService.state()
	local gui = guiObjects(alice)
	local armies, wars, mine = 0, 0, 0
	for _ in state.armies do
		armies += 1
	end
	for _ in state.wars do
		wars += 1
	end
	for _, p in state.provinces do
		if p.owner == me then
			mine += 1
		end
	end
	local clock = string.format("%d:%02d", state.tick // 60, state.tick % 60)
	if state ~= first then
		clock = "next " .. clock
	end
	print(
		string.format(
			"%6s  %-10s %4d  %6d  %5d  %4d  %6.1f  %6.1f",
			clock,
			state.phase,
			gui,
			armies,
			mine,
			wars,
			collectgarbage("count") / 1024,
			os.clock() - t0
		)
	)
	if gui > peak then
		peak, peakAt = gui, clock
	end
	if process.env.SHOTS and minute % 5 == 0 then
		shot(alice, string.format("%02d_min", minute))
	end
end

-- who owns the armies at the end of the first match, and how big they are
local byOwner = {}
for _, army in first.armies do
	local entry = byOwner[army.owner] or { n = 0, men = 0, idle = 0 }
	entry.n += 1
	entry.men += army.men
	if #army.path == 0 and not army.inBattle then
		entry.idle += 1
	end
	byOwner[army.owner] = entry
end
print("\narmies at the end, by owner:")
for owner = 0, 10 do
	local entry = byOwner[owner]
	if entry then
		local name = if owner == 0 then "neutral" else first.nations[owner].name
		print(string.format("  %-10s %3d armies, %6d men, %3d standing", name, entry.n, entry.men, entry.idle))
	end
end
local stacked = 0
local seen = {}
for _, army in first.armies do
	local key = army.owner .. ":" .. army.location
	if #army.path == 0 and not army.inBattle then
		if seen[key] then
			stacked += 1
		end
		seen[key] = true
	end
end
print(string.format("standing armies sharing a province with another of the same owner: %d", stacked))

local result = first.result
print(string.format("\nresult: %s", if result then result.kind .. " at tick " .. result.endedAt else "none"))
print(string.format("peak GUI objects: %d at %s (budget %d)", peak, peakAt, GUI_BUDGET))
print(string.format("wall time: %.0f s", os.clock() - wall0))
assert(result ~= nil, "the match never ended")
assert(MatchService.state() ~= first, "the next match never started")
assert(peak <= GUI_BUDGET, "over the GUI budget")
Emulator.assertClean("soak")
print("== soak passed ==")
