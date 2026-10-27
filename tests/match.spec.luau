--!strict
local Config = require("../src/shared/Config")
local Maps = require("../src/shared/Maps")
local Match = require("../src/shared/Sim/Match")
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
	T.expect(not Match.isOver(p.MatchEndTick))
	T.expect(Match.isOver(p.MatchEndTick + p.ResultsTicks))
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
	T.equal(Match.seatPlayer(state, 333), 1, "the freed seat is reused")
end)

T.test("seats run out after ten players", function()
	local state = Match.new(Maps.get("skyshards"))
	for i = 1, 10 do
		T.equal(Match.seatPlayer(state, i), i)
	end
	T.equal(Match.seatPlayer(state, 11), nil)
end)

T.test("each nation starts with eight provinces", function()
	local state = Match.new(Maps.get("earth"))
	for id in state.nations do
		T.equal(Match.provinceCount(state, id), 8)
	end
end)

T.finish()
