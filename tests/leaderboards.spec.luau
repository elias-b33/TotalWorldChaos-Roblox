--!strict
-- Leaderboards (docs/MONETIZATION.md 7.3): weekly conquest points, the friends view, the level board, Warlord frame.
local Config = require("../src/shared/Config")
local Leaderboards = require("../src/shared/Sim/Leaderboards")
local Maps = require("../src/shared/Maps")
local Match = require("../src/shared/Sim/Match")
local Progression = require("../src/shared/Sim/Progression")
local Settings = require("../src/shared/Sim/Settings")
local Shop = require("../src/shared/Sim/Shop")
local T = require("./TestKit")
local Types = require("../src/shared/Types")

local L = Config.Leaderboards

local function reward(placement: number?, afk: boolean?, stayed: boolean?): Types.MatchReward
	return { xp = 0, glory = 0, lines = {}, placement = placement, stayed = stayed ~= false, afk = afk == true }
end

local function matchWith(humans: number, private: boolean?): Types.MatchState
	local setup = if private then { private = true, settings = Settings.defaults() } else nil
	local state = Match.new(Maps.get("skyshards"), setup)
	for i = 1, humans do
		Match.seatPlayer(state, 1000 + i)
	end
	return state
end

local function entries(list: { { number } }): { Leaderboards.Entry }
	local out = {}
	for _, pair in list do
		table.insert(out, { userId = pair[1], value = pair[2] })
	end
	return out
end

T.test("points by placement: 10, 7, 5, 3, 3, then 1; nothing for AFK, leaving or no nation", function()
	local expected = { 10, 7, 5, 3, 3, 1, 1, 1, 1, 1 }
	for place, points in expected do
		T.equal(Leaderboards.points(reward(place)), points, "place " .. place)
	end
	T.equal(Leaderboards.points(reward(1, true)), 0, "AFK")
	T.equal(Leaderboards.points(reward(nil, false, false)), 0, "left early")
	T.equal(Leaderboards.points(reward(nil)), 0, "a Primordial or spectator at Results")
end)

T.test("only public matches with 4+ real players count; private servers never", function()
	T.expect(Leaderboards.counts(matchWith(4)), "public, 4 players")
	T.expect(not Leaderboards.counts(matchWith(3)), "public, 3 players")
	T.expect(not Leaderboards.counts(matchWith(6, true)), "private, even with default rules and 6 players")
	T.equal(L.MinHumans, 4)
end)

T.test("a board per week; entries sort best first and equal points share a rank", function()
	T.equal(Leaderboards.weekKey(2857), "W2857")
	local sorted = Leaderboards.sorted(entries({ { 3, 5 }, { 1, 10 }, { 2, 5 }, { 4, 1 } }))
	T.equal(sorted[1].userId, 1)
	T.equal(sorted[2].userId, 2, "ties: lower id first, the same order on every server")
	T.equal(Leaderboards.rank(sorted, 3), 2, "5 points share 2nd")
	T.equal(Leaderboards.rank(sorted, 4), 4)
	T.equal(Leaderboards.rank(sorted, 99), 0, "not on the board")
end)

T.test("what this server knows (players here) goes over what was read", function()
	local read = entries({ { 1, 10 }, { 2, 3 } })
	local merged = Leaderboards.merge(read, { [2] = 13, [5] = 4, [6] = 0 })
	T.equal(merged[1].userId, 2)
	T.equal(merged[1].value, 13)
	T.equal(#merged, 3, "a new player with points joins; 0 points stay off")
	T.equal(Leaderboards.merge(read, { [1] = 2 })[1].value, 10, "never lower than the board")
end)

T.test("the friends view: you and your friends from the weekly board", function()
	local weekly = Leaderboards.sorted(entries({ { 1, 10 }, { 2, 7 }, { 3, 5 }, { 4, 1 } }))
	local view = Leaderboards.friends(weekly, { 3, 9 }, 4)
	T.equal(#view, 2)
	T.equal(view[1].userId, 3)
	T.equal(view[2].userId, 4)
	local alone = Leaderboards.friends(weekly, {}, 8)
	T.equal(#alone, 1)
	T.equal(alone[1].value, 0, "you are always on it")
end)

T.test("rows carry rank, display name and value only; the level board adds the level", function()
	local list = {}
	for i = 1, L.ShownRows + 5 do
		table.insert(list, { userId = i, value = 1000 - i })
	end
	local rows = Leaderboards.rows(list, 2, function(id)
		return "Name" .. id
	end)
	T.equal(#rows, L.ShownRows)
	T.equal(rows[2].name, "Name2")
	T.equal(rows[2].me, true)
	T.equal(rows[1].me, false)
	for key in rows[1] :: any do
		T.expect(key == "rank" or key == "name" or key == "value" or key == "me", "no user ids: " .. key)
	end
	local level = Leaderboards.rows(entries({ { 1, Progression.totalXpFor(12) } }), 1, tostring, true)
	T.equal(level[1].level, 12)
end)

T.test("the Warlord frame: last week's top 100 wear it this week, then it goes", function()
	local top = {}
	for i = 1, L.WarlordTop + 20 do
		table.insert(top, { userId = i, value = 500 - i })
	end
	local ids = Leaderboards.top(top)
	T.equal(#ids, L.WarlordTop)
	T.equal(#Leaderboards.top(entries({ { 1, 5 }, { 2, 0 } })), 1, "no points, no frame")

	local p = Progression.newProfile()
	T.expect(not Leaderboards.warlordDue(p, 7, 2000, { 8 }), "not in the top: nothing to do")
	T.expect(Leaderboards.warlordDue(p, 7, 2000, { 7 }))
	T.expect(Leaderboards.refreshWarlord(p, 7, 2000, { 7 }), "given")
	T.expect(Shop.owns(p, "frame_warlord", false) and Shop.equip(p, "frame_warlord", false), "worn like any frame")
	T.expect(not Leaderboards.warlordDue(p, 7, 2000, { 7 }), "nothing more to save")
	T.expect(not Leaderboards.refreshWarlord(p, 7, 2000, {}), "kept for the rest of its week")
	T.expect(not Leaderboards.refreshWarlord(p, 7, 2001, nil), "unread: nothing changes")
	T.expect(Leaderboards.refreshWarlord(p, 7, 2001, { 8 }), "a new week without making the top: it goes")
	T.expect(not Shop.owns(p, "frame_warlord", false))
	T.equal(Shop.equippedIn(p, "Frame", false), "frame_none", "back to the default frame")
	T.expect(Leaderboards.refreshWarlord(p, 7, 2002, { 7 }), "back in the top: back again")
end)

T.finish()
