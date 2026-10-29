--!nocheck
-- A whole match, headlessly: one idle player and nine bots for the full 25 minutes, then Results and the start
-- of the next match. Fails on any script error or warn(), or if the player's screen ever holds more GUI objects
-- than the budget (docs/DESIGN.md "Performance budget"; counted every 5 s). Prints one line per game minute: the
-- minute's most GUI objects, the fleets on the map (sailing ones in brackets) and the bytes the server sends every client per tick: the delta (average and the
-- minute's biggest) plus the moving armies' positions, estimated as Roblox packs them (about 9 bytes a number, a
-- string's length plus 2). Fails if a minute averages over the network budget (10 KB a second, one tick a second).
--
--   mkdir -p build && rojo build -o build/game.rbxlx
--   lune run tools/harness/soak                 # Config.DefaultMap; MAP=earth for another map
--   SHOTS=1 lune run tools/harness/soak         # plus a screenshot every 5 minutes in tools/harness/out/soak/
--   FLEETS=4 lune run tools/harness/soak        # at 12:00 every living nation also gets 4 one-ship fleets, each
--                                               # sailing across the map: the GUI and network budgets with ~40 fleets
local fs = require("@lune/fs")
local process = require("@lune/process")

local Emulator = require("./Emulator")
local Scene = require("./Scene")

local OUT = "tools/harness/out/soak"
local GUI_BUDGET = 2000
local NET_BUDGET = 10 * 1024 -- bytes per client per second (docs/DESIGN.md "Performance budget")
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

-- what every client is sent per tick: the delta and the positions of moving armies (wrapped where Replicator calls)
local function bytes(v: any): number
	local t = type(v)
	if t == "number" then
		return 9
	elseif t == "string" then
		return 2 + #v
	elseif t == "table" then
		local n = 2
		for k, x in v do
			n += bytes(k) + bytes(x)
		end
		return n
	end
	return 1
end
local Snapshot = Emulator.server.modules[Emulator.server.dm:GetService("ReplicatedStorage").Shared.Snapshot]
local tickBytes, minuteBytes, minuteTicks, minuteMax = 0, 0, 0, 0
local diff, positions = Snapshot.diff, Snapshot.positions
Snapshot.diff = function(...)
	local delta = diff(...)
	-- one delta per tick: close the last tick's count here
	minuteBytes += tickBytes
	minuteTicks += 1
	minuteMax = math.max(minuteMax, tickBytes)
	tickBytes = if delta then bytes(delta) else 0
	return delta
end
Snapshot.positions = function(...)
	local list = positions(...)
	tickBytes += 2 + #list * 4 * 9 -- id, from, to, progress
	return list
end
local first = MatchService.state()
local me = alice.modules[alice.localPlayer.PlayerScripts.Client.ClientState].myNation()
print(string.format("soak on %s: Alice is nation %d, nine bots", first.mapId, me))
print(" clock   phase       gui  armies  fleets  Alice  wars  bytes/tick (max)  Lua MB  wall s")

-- FLEETS: extra one-ship fleets per living nation at 12:00, each sent sailing to the zone farthest from where it
-- starts (the bots take them over when they arrive)
local function addFleets(state, perNation: number)
	local Navy = Emulator.server.modules[Emulator.server.dm:GetService("ReplicatedStorage").Shared.Sim.Navy]
	local zones = #state.zones
	local function farthest(from: number): number
		local dist, queue, last = { [from] = 0 }, { from }, from
		local head = 1
		while head <= #queue do
			last = queue[head]
			head += 1
			for _, n in state.zones[last].neighbors do
				if dist[n] == nil then
					dist[n] = dist[last] + 1
					table.insert(queue, n)
				end
			end
		end
		return last
	end
	local n = 0
	for id, nation in state.nations do
		if not nation.eliminated then
			for k = 1, perNation do
				local from = (id * perNation + k) % zones + 1
				local fleet = Navy.spawn(state, id, from, 1)
				Navy.sail(state, id, fleet.id, farthest(from))
				n += 1
			end
		end
	end
	print(string.format("  + %d fleets sailing", n))
end
local extraFleets = tonumber(process.env.FLEETS)

local function countFleets(state): (number, number)
	local fleets, sailing = 0, 0
	for _, f in state.fleets do
		fleets += 1
		if #f.path > 0 then
			sailing += 1
		end
	end
	return fleets, sailing
end

local peak, peakAt = 0, ""
local netPeak, netPeakAt, fleetPeak = 0, "", 0
local wall0 = os.clock()
for minute = 1, math.ceil(MINUTES) do
	local t0 = os.clock()
	local stress = extraFleets and minute == 13
	if stress then
		addFleets(MatchService.state(), extraFleets)
	end
	-- the GUI is counted every 5 s (fleets come and go within a minute); the line shows the minute's most
	local gui = 0
	for step = 1, 12 do
		local bytes0, ticks0 = minuteBytes, minuteTicks
		Emulator.run(5)
		gui = math.max(gui, guiObjects(alice))
		local f, s = countFleets(MatchService.state())
		fleetPeak = math.max(fleetPeak, f)
		if stress and step <= 8 then
			print(
				string.format(
					"   +%2d s: %d fleets (%d sailing), %d GUI objects, %d bytes a tick",
					step * 5,
					f,
					s,
					guiObjects(alice),
					(minuteBytes - bytes0) // math.max(minuteTicks - ticks0, 1)
				)
			)
		end
	end
	local state = MatchService.state()
	local armies, wars, mine = 0, 0, 0
	for _ in state.armies do
		armies += 1
	end
	local fleets, sailing = countFleets(state)
	local perTick = minuteBytes / math.max(minuteTicks, 1)
	if perTick > netPeak then
		netPeak, netPeakAt = perTick, string.format("%d:%02d", state.tick // 60, state.tick % 60)
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
			"%6s  %-10s %4d  %6d  %3d (%d)  %5d  %4d  %6d (%6d)  %6.1f  %6.1f",
			clock,
			state.phase,
			gui,
			armies,
			fleets,
			sailing,
			mine,
			wars,
			math.floor(perTick),
			minuteMax,
			collectgarbage("count") / 1024,
			os.clock() - t0
		)
	)
	minuteBytes, minuteTicks, minuteMax = 0, 0, 0
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
print(
	string.format(
		"most fleets at once: %d; busiest minute on the network: %d bytes a tick at %s (budget %d)",
		fleetPeak,
		math.floor(netPeak),
		netPeakAt,
		NET_BUDGET
	)
)
print(string.format("wall time: %.0f s", os.clock() - wall0))
assert(result ~= nil, "the match never ended")
assert(MatchService.state() ~= first, "the next match never started")
assert(peak <= GUI_BUDGET, "over the GUI budget")
assert(netPeak <= NET_BUDGET, "over the network budget")
Emulator.assertClean("soak")
print("== soak passed ==")
