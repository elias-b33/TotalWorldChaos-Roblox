--!strict
local Army = require("../src/shared/Sim/Army")
local Config = require("../src/shared/Config")
local Maps = require("../src/shared/Maps")
local Match = require("../src/shared/Sim/Match")
local Primordial = require("../src/shared/Sim/Primordial")
local T = require("./TestKit")

T.test("a new match copies the map's start territories and capitals", function()
	local map = Maps.get("skyshards")
	local state = Match.new(map)
	T.equal(state.mapId, "skyshards")
	T.equal(state.tick, 0)
	T.equal(state.phase, "Peace")
	for _, def in map.provinces do
		T.equal(state.provinces[def.id].owner, def.startOwner, def.name)
		T.equal(state.provinces[def.id].building, "None")
	end
	for _, def in map.nations do
		local nation = state.nations[def.slot]
		T.equal(nation.capital, def.capital)
		T.equal(nation.gold, Config.StartGold)
		T.equal(nation.manpower, Config.StartManpower)
		T.equal(nation.controller, "Bot")
	end
end)

T.test("match state does not share neighbour lists with the map data", function()
	local map = Maps.get("earth")
	local state = Match.new(map)
	table.insert(state.provinces[1].neighbors, 999)
	T.expect(table.find(map.provinces[1].neighbors, 999) == nil)
end)

T.test("phases follow the match clock", function()
	local p = Config.Phases
	T.equal(Match.phaseAt(0), "Peace")
	T.equal(Match.phaseAt(p.PeaceEndTick - 1), "Peace")
	T.equal(Match.phaseAt(p.PeaceEndTick), "War")
	T.equal(Match.phaseAt(p.WarEndTick), "Cataclysm")
	T.equal(Match.phaseAt(p.MatchEndTick), "Results")
end)

T.test("players take the lowest free nation and bots take it back when they leave", function()
	local state = Match.new(Maps.get("eldmoor"))
	T.equal(Match.seatPlayer(state, 111), 1)
	T.equal(Match.seatPlayer(state, 222), 2)
	T.equal(Match.seatPlayer(state, 111), 1, "rejoining keeps the seat")
	T.equal(state.nations[2].controller, "Player")
	T.equal(Match.nationOf(state, 222), 2)
	Match.unseatPlayer(state, 111)
	T.equal(state.nations[1].controller, "Bot")
	T.equal(state.nations[1].userId, nil)
	T.equal(Match.seatPlayer(state, 333), 3, "a newcomer takes a nation no absent player held")
	T.equal(Match.seatPlayer(state, 111), 1, "the leaver gets their nation back")
end)

T.test("a rejoining player gets their own nation back, not a healthier one", function()
	local state = Match.new(Maps.get("eldmoor"))
	T.equal(Match.seatPlayer(state, 111), 1)
	T.equal(Match.seatPlayer(state, 222), 2)
	Match.unseatPlayer(state, 222)
	Match.unseatPlayer(state, 111)
	T.equal(Match.seatPlayer(state, 222), 2, "not the lower-numbered nation 1")
	T.equal(Match.seatPlayer(state, 111), 1)
	T.equal(state.seats[111], 1)
end)

T.test("a held nation goes to a newcomer only when nothing else is free", function()
	local state = Match.new(Maps.get("skyshards"))
	for i = 1, 10 do
		Match.seatPlayer(state, i)
	end
	Match.unseatPlayer(state, 4)
	T.equal(Match.seatPlayer(state, 99), 4, "the only seat left")
	T.equal(Match.seatPlayer(state, 4), nil, "taken meanwhile: the leaver watches")
end)

T.test("a player whose nation was eliminated while away rejoins as its Primordial", function()
	local state = Match.new(Maps.get("eldmoor"))
	T.equal(Match.seatPlayer(state, 111), 1)
	Match.unseatPlayer(state, 111)
	-- the bot that took over loses the nation: a bot simply ends, no Primordial yet
	Primordial.eliminate(state, 1)
	T.equal(state.primordials[111], nil)
	T.equal(Match.seatPlayer(state, 111), 1, "back on the eliminated nation, not a living one")
	T.equal(state.nations[1].userId, 111)
	local p = state.primordials[111]
	T.expect(p ~= nil and p.charges == 0, "a Primordial with no charges yet")
	T.equal(Match.nationOf(state, 111), 1)
end)

T.test("during Results a newcomer isn't seated, but a returning player gets their nation back", function()
	local state = Match.new(Maps.get("eldmoor"))
	T.equal(Match.seatPlayer(state, 111), 1)
	Match.unseatPlayer(state, 111)
	state.result = { kind = "Score", winners = { 2 }, scores = {}, endedAt = state.tick }
	state.phase = "Results"
	T.equal(Match.seatPlayer(state, 555), nil, "the newcomer watches the Results")
	T.equal(state.nations[3].controller, "Bot")
	T.equal(Match.seatPlayer(state, 111), 1, "the player who played it sees their own result")
end)

T.test("army ids are never reused, even after the newest army dies", function()
	local state = Match.new(Maps.get("eldmoor"))
	local first = Army.spawn(state, 1, state.nations[1].capital, 1000)
	state.armies[first.id] = nil
	local second = Army.spawn(state, 1, state.nations[1].capital, 1000)
	T.expect(second.id > first.id, "a new id")
	T.equal(state.nextArmyId, second.id + 1)
	for id in state.armies do
		T.expect(id < state.nextArmyId, "every id is below the counter")
	end
end)

T.test("seats run out after ten players", function()
	local state = Match.new(Maps.get("skyshards"))
	for i = 1, 10 do
		T.equal(Match.seatPlayer(state, i), i)
	end
	T.equal(Match.seatPlayer(state, 11), nil)
end)

T.test("neutral land starts garrisoned; owned land and mountains do not", function()
	local map = Maps.get("eldmoor")
	local state = Match.new(map)
	local garrisoned: { [number]: number } = {}
	for _, a in state.armies do
		T.equal(a.owner, 0)
		garrisoned[a.location] = a.men
	end
	for _, def in map.provinces do
		if def.startOwner == nil and def.terrain ~= "Mountain" then
			T.equal(garrisoned[def.id], def.garrison or Config.NeutralGarrison, def.name)
		else
			T.equal(garrisoned[def.id], nil, def.name)
		end
	end
end)

T.test("the match is over once Results has been shown", function()
	local state = Match.new(Maps.get("skyshards"))
	T.expect(not Match.isOver(state))
	state.result = { kind = "Score", winners = { 1 }, scores = {}, endedAt = 100 }
	state.tick = 100 + Config.Phases.ResultsTicks - 1
	T.expect(not Match.isOver(state))
	state.tick += 1
	T.expect(Match.isOver(state))
end)

T.test("each nation starts with eight provinces", function()
	local state = Match.new(Maps.get("earth"))
	for id in state.nations do
		T.equal(Match.provinceCount(state, id), 8)
	end
end)

T.finish()
