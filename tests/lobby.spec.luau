--!strict
local Config = require("../src/shared/Config")
local Lobby = require("../src/shared/Sim/Lobby")
local Maps = require("../src/shared/Maps")
local Match = require("../src/shared/Sim/Match")
local Rng = require("../src/shared/Sim/Rng")
local T = require("./TestKit")

local function newLobby()
	return Lobby.new(Maps.ids, nil)
end

T.test("a new lobby votes on all three maps for LobbyTicks", function()
	local lobby = newLobby()
	T.equal(lobby.phase, "Lobby")
	T.equal(lobby.ticksLeft, Config.Phases.LobbyTicks)
	T.equal(#lobby.maps, 3)
end)

T.test("the map with the most votes wins", function()
	local lobby = newLobby()
	T.expect(Lobby.vote(lobby, 1, "eldmoor"))
	T.expect(Lobby.vote(lobby, 2, "eldmoor"))
	T.expect(Lobby.vote(lobby, 3, "earth"))
	T.equal(Lobby.tally(lobby).eldmoor, 2)
	for seed = 1, 20 do
		T.equal(Lobby.winner(lobby, Rng.new(seed * 104729)), "eldmoor")
	end
end)

T.test("changing your vote replaces it, and leaving takes it back", function()
	local lobby = newLobby()
	Lobby.vote(lobby, 1, "earth")
	Lobby.vote(lobby, 1, "skyshards")
	T.equal(Lobby.tally(lobby).earth, 0)
	T.equal(Lobby.tally(lobby).skyshards, 1)
	Lobby.leave(lobby, nil, 1)
	T.equal(Lobby.tally(lobby).skyshards, 0)
end)

-- (small consecutive seeds start the Park-Miller generator near 0, so the seeds are spread out)
T.test("a tie is settled by the seeded Rng, the same way every time", function()
	local lobby = newLobby()
	Lobby.vote(lobby, 1, "earth")
	Lobby.vote(lobby, 2, "skyshards")
	local seen: { [string]: boolean } = {}
	for seed = 1, 40 do
		local a = Lobby.winner(lobby, Rng.new(seed * 104729))
		T.equal(Lobby.winner(lobby, Rng.new(seed * 104729)), a, "same seed, same map")
		T.expect(a == "earth" or a == "skyshards", "only tied maps can win, got " .. a)
		seen[a] = true
	end
	T.expect(seen.earth and seen.skyshards, "both tied maps win for some seed")
end)

T.test("nobody voting picks any map at random", function()
	local seen: { [string]: boolean } = {}
	for seed = 1, 60 do
		seen[Lobby.winner(newLobby(), Rng.new(seed * 104729))] = true
	end
	T.expect(seen.earth and seen.eldmoor and seen.skyshards)
end)

T.test("bad votes are refused", function()
	local lobby = newLobby()
	local ok, reason = Lobby.vote(lobby, 1, "atlantis")
	T.equal(ok, false)
	T.equal(reason, "UnknownMap")
	local locked = Lobby.new(Maps.ids, "earth")
	ok, reason = Lobby.vote(locked, 1, "earth")
	T.equal(reason, "Locked")
	T.equal(Lobby.winner(locked, Rng.new(5)), "earth")
	T.equal(#locked.maps, 1)
end)

T.test("the vote ends after LobbyTicks", function()
	local lobby = newLobby()
	local rng = Rng.new(1)
	for _ = 1, Config.Phases.LobbyTicks - 1 do
		T.equal(Lobby.step(lobby, nil, rng), false)
	end
	T.equal(Lobby.step(lobby, nil, rng), true)
end)

local function draft(players: { number }, seed: number)
	local lobby = newLobby()
	local match = Match.new(Maps.get("eldmoor"))
	Lobby.startPick(lobby, match, players, Rng.new(seed))
	return lobby, match
end

T.test("the draft order is a seeded shuffle of the players", function()
	local lobby = draft({ 11, 22, 33, 44 }, 7)
	local again = draft({ 11, 22, 33, 44 }, 7)
	T.equal(#lobby.order, 4)
	for i, id in lobby.order do
		T.equal(again.order[i], id)
	end
	local differs = false
	for seed = 1, 20 do
		local other = draft({ 11, 22, 33, 44 }, seed)
		for i, id in other.order do
			differs = differs or id ~= lobby.order[i]
		end
	end
	T.expect(differs, "different seeds give different orders")
end)

T.test("the draft puts the match in Pick and turns fit in PickTicks", function()
	local lobby, match = draft({ 1, 2, 3 }, 1)
	T.equal(match.phase, "Pick")
	T.equal(lobby.phase, "Pick")
	T.equal(lobby.mapId, "eldmoor")
	T.equal(Lobby.turnTicks(1), Config.Phases.PickTurnMaxTicks)
	T.equal(Lobby.turnTicks(10), Config.Phases.PickTurnMinTicks)
	for n = 1, 10 do
		T.expect(Lobby.turnTicks(n) * n <= Config.Phases.PickTicks, "10 players fit in the draft")
	end
end)

T.test("players pick in turn; out-of-turn and taken nations are refused", function()
	local lobby, match = draft({ 1, 2, 3 }, 3)
	local first, second = lobby.order[1], lobby.order[2]
	local ok, reason = Lobby.pick(lobby, match, second, 4)
	T.equal(ok, false)
	T.equal(reason, "NotYourTurn")
	T.expect(Lobby.pick(lobby, match, first, 4))
	T.equal(match.nations[4].userId, first)
	T.equal(match.nations[4].controller, "Player")
	T.equal(Lobby.current(lobby), second)
	ok, reason = Lobby.pick(lobby, match, second, 4)
	T.equal(reason, "Taken")
	ok, reason = Lobby.pick(lobby, match, second, 99)
	T.equal(reason, "BadTarget")
	T.expect(Lobby.apply(lobby, match, second, { kind = "Pick", nation = 9 }))
	T.equal(Match.nationOf(match, second), 9)
end)

T.test("a turn that runs out picks a random free nation; the draft then ends", function()
	local lobby, match = draft({ 1, 2 }, 5)
	local rng = Rng.new(9)
	local first = lobby.order[1]
	Lobby.pick(lobby, match, first, 1)
	for _ = 1, lobby.turnTicks - 1 do
		T.equal(Lobby.step(lobby, match, rng), false)
	end
	T.equal(Lobby.step(lobby, match, rng), true, "the last turn ran out")
	local auto = Match.nationOf(match, lobby.order[2])
	T.expect(auto ~= nil and auto ~= 1, "the second player got a free nation")
	local bots = 0
	for _, n in match.nations do
		if n.controller == "Bot" then
			bots += 1
		end
	end
	T.equal(bots, 8, "bots take the rest")
	Lobby.finish(match)
	T.equal(match.phase, "Peace")
	T.equal(match.tick, 0)
end)

T.test("when the draft time runs out everyone waiting is auto-picked", function()
	local lobby, match = draft({ 1, 2, 3 }, 2)
	local late = { 4, 5, 6, 7, 8, 9, 10, 11, 12 }
	for _, id in late do
		Lobby.join(lobby, match, id)
	end
	T.equal(#lobby.order, 10, "one place per nation")
	local rng = Rng.new(4)
	local done = false
	for _ = 1, Config.Phases.PickTicks do
		done = Lobby.step(lobby, match, rng)
	end
	T.expect(done, "the draft is over after PickTicks")
	for _, id in lobby.order do
		T.expect(Match.nationOf(match, id) ~= nil, "everyone in the order has a nation")
	end
	T.equal(Match.nationOf(match, 12), nil, "the 12th player watches")
end)

T.test("joining during the vote does nothing; during the draft adds you to the end", function()
	local lobby = newLobby()
	Lobby.join(lobby, nil, 5)
	T.equal(#lobby.order, 0)
	local pickLobby, match = draft({ 1, 2 }, 1)
	Lobby.join(pickLobby, match, 3)
	Lobby.join(pickLobby, match, 3)
	T.equal(#pickLobby.order, 3)
	T.equal(pickLobby.order[3], 3)
end)

T.test("leaving during the draft frees your nation and keeps the turn on the right player", function()
	local lobby, match = draft({ 1, 2, 3 }, 6)
	local a, b, c = lobby.order[1], lobby.order[2], lobby.order[3]
	Lobby.pick(lobby, match, a, 2)
	Lobby.leave(lobby, match, a)
	T.equal(match.nations[2].controller, "Bot", "a's nation goes back to a bot")
	T.equal(Lobby.current(lobby), b)
	Lobby.leave(lobby, match, b) -- it was b's turn: c is next, with a full turn
	T.equal(Lobby.current(lobby), c)
	T.equal(lobby.turnTicksLeft, lobby.turnTicks)
end)

T.test("an empty server ends the draft at once, with bots everywhere", function()
	local lobby, match = draft({}, 1)
	T.equal(Lobby.step(lobby, match, Rng.new(1)), true)
end)

T.test("the view is flat and names who picked what", function()
	local lobby, match = draft({ 7, 8 }, 1)
	Lobby.pick(lobby, match, lobby.order[1], 3)
	local view = Lobby.view(lobby, { [7] = "Alice", [8] = "Bob" })
	T.equal(view.phase, "Pick")
	T.equal(view.mapId, "eldmoor")
	T.equal(#view.order, 2)
	T.equal(view.order[1].nation, 3)
	T.equal(view.order[2].nation, 0)
	T.equal(view.turn, 2)
	local voting = newLobby()
	Lobby.vote(voting, 7, "earth")
	local v = Lobby.view(voting, {})
	T.equal(v.counts[table.find(v.maps, "earth") :: number], 1)
	T.equal(v.votes[1].map, "earth")
	T.equal(Lobby.view(nil, {}).phase, "None")
end)

T.finish()
