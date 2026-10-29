--!strict
-- Which music plays (src/client/MusicMood.luau, docs/NEXT_FEATURES.md 6): every screen and phase's track, the hold
-- that keeps Peace and War from flipping, the moments that cut through it, and what counts as a battle of yours.
local Config = require("../src/shared/Config")
local MusicMood = require("../src/client/MusicMood")
local T = require("./TestKit")

local RULES = Config.Music
local HOLD = RULES.MinMoodSeconds
local WINDOW = RULES.BattleWindowSeconds

local function input(phase: string, extra: { [string]: any }?): MusicMood.Input
	local i: MusicMood.Input = { screen = "Match", phase = phase, atWar = false }
	for k, v in extra or {} do
		(i :: any)[k] = v
	end
	return i
end

local function wanted(i: MusicMood.Input, now: number?): MusicMood.Track
	return MusicMood.wanted(i, now or 1000, RULES)
end

T.test("every screen and phase has its track", function()
	T.equal(wanted({ screen = "Menu", phase = "War", atWar = true }), "Lobby", "the start menu")
	T.equal(wanted({ screen = "Lobby", phase = "Results", atWar = false }), "Lobby", "the map vote and the draft")
	T.equal(wanted(input("Pick")), "Lobby", "a match still drafting")
	T.equal(wanted(input("Peace")), "Peace")
	T.equal(wanted(input("War")), "Peace", "the War phase without a war of yours")
	T.equal(wanted(input("War", { atWar = true })), "War", "at war")
	T.equal(wanted(input("Cataclysm")), "Cataclysm")
	T.equal(wanted(input("Cataclysm", { atWar = true })), "Cataclysm", "the Cataclysm wins over a war")
	T.equal(wanted(input("Results", { won = true })), "Victory", "you won")
	T.equal(wanted(input("Results", { won = false })), "Results", "you didn't")
	T.equal(wanted(input("Results", { won = true, stingOver = true })), "Lobby", "after the sting, the Lobby theme")
end)

T.test("War plays for BattleWindowSeconds after a battle of yours", function()
	T.equal(wanted(input("War", { battleAt = 1000 }), 1000), "War")
	T.equal(wanted(input("War", { battleAt = 1000 }), 1000 + WINDOW - 1), "War")
	T.equal(wanted(input("War", { battleAt = 1000 }), 1000 + WINDOW), "Peace")
	T.equal(wanted(input("Peace", { battleAt = 1000 }), 1000), "Peace", "no War in the Peace phase")
end)

T.test("an eliminated player in War hears War", function()
	T.equal(wanted(input("War", { eliminated = true })), "War")
	T.equal(wanted(input("Cataclysm", { eliminated = true })), "Cataclysm")
end)

T.test("the sandbox plays Peace", function()
	T.equal(wanted(input("War", { sandbox = true, atWar = true })), "Peace")
	T.equal(wanted(input("Peace", { sandbox = true })), "Peace")
end)

T.test("Peace and War hold each other off for MinMoodSeconds", function()
	local war = input("War", { atWar = true })
	local peace = input("War")
	T.equal(MusicMood.pick(war, { track = "Peace", since = 0 }, 10, RULES), "Peace", "a war declared 10 s in waits")
	T.equal(MusicMood.pick(war, { track = "Peace", since = 0 }, HOLD, RULES), "War", "then plays")
	T.equal(MusicMood.pick(peace, { track = "War", since = 100 }, 100 + HOLD - 1, RULES), "War", "a quick peace")
	T.equal(MusicMood.pick(peace, { track = "War", since = 100 }, 100 + HOLD, RULES), "Peace", "back to Peace")
	T.equal(MusicMood.pick(war, { track = "War", since = 100 }, 101, RULES), "War", "no change, nothing to hold")
	T.equal(MusicMood.pick(war, { track = nil, since = 0 }, 1, RULES), "War", "the first track plays at once")
end)

T.test("Results, the Cataclysm and a new screen cut through the hold", function()
	T.equal(MusicMood.pick(input("Cataclysm"), { track = "War", since = 100 }, 101, RULES), "Cataclysm")
	T.equal(
		MusicMood.pick(input("Results", { won = true }), { track = "Cataclysm", since = 100 }, 101, RULES),
		"Victory"
	)
	T.equal(MusicMood.pick(input("Results"), { track = "War", since = 100 }, 101, RULES), "Results")
	local sting = input("Results", { stingOver = true })
	T.equal(MusicMood.pick(sting, { track = "Victory", since = 100 }, 104, RULES), "Lobby", "the sting ends")
	local menu: MusicMood.Input = { screen = "Menu", phase = "War", atWar = false }
	T.equal(MusicMood.pick(menu, { track = "War", since = 100 }, 101, RULES), "Lobby", "the menu opens")
	T.equal(
		MusicMood.pick(input("War", { atWar = true }), { track = "Lobby", since = 100 }, 101, RULES),
		"War",
		"joined mid-war"
	)
	T.equal(MusicMood.pick(input("Peace"), { track = "Lobby", since = 100 }, 101, RULES), "Peace", "the match starts")
end)

local function view(): MusicMood.View
	return {
		armies = { { owner = 2, inBattle = true }, { owner = 1, inBattle = false } },
		fleets = { { owner = 3, inBattle = true } },
		provinces = { { owner = 1, battle = false }, { owner = 2, battle = true } },
		diplomacy = { wars = { { attackers = { 2 }, defenders = { 3, 4 } } } },
		result = nil,
	}
end

T.test("a war of yours: as attacker or defender", function()
	local v = view()
	T.expect(MusicMood.atWar(v, 2), "the attacker")
	T.expect(MusicMood.atWar(v, 4), "a defender")
	T.expect(not MusicMood.atWar(v, 1), "a nation outside it")
	T.expect(not MusicMood.atWar(v, 0), "no nation")
end)

T.test("a battle of yours: your army, your fleet (a sea battle counts) or your province", function()
	local v = view()
	T.expect(MusicMood.fighting(v, 2), "an army of yours fights")
	T.expect(MusicMood.fighting(v, 3), "a fleet of yours fights")
	T.expect(not MusicMood.fighting(v, 1), "your army stands still, your province is quiet")
	v.provinces[1].battle = true
	T.expect(MusicMood.fighting(v, 1), "a battle in your province")
	T.expect(not MusicMood.fighting(v, 0), "no nation")
end)

T.test("a battle that ended in one delta, on land or at sea", function()
	local events: { MusicMood.Event } = {
		{ kind = "BattleEnded", a = 5, b = 6 },
		{ kind = "SeaBattle", a = 7, b = 8 },
		{ kind = "ProvinceTaken", a = 9, b = 10 },
	}
	T.expect(MusicMood.fought(events, 5) and MusicMood.fought(events, 6), "the winner and the loser on land")
	T.expect(MusicMood.fought(events, 8), "a sea battle")
	T.expect(not MusicMood.fought(events, 9), "a capture alone is not a battle")
	T.expect(not MusicMood.fought(events, 0), "no nation")
end)

T.test("you won: alone or with your alliance", function()
	local v = view()
	T.expect(not MusicMood.won(v, 1), "no result yet")
	v.result = { winners = { 1, 4 } }
	T.expect(MusicMood.won(v, 1) and MusicMood.won(v, 4), "both allies won")
	T.expect(not MusicMood.won(v, 2), "the others lost")
	T.expect(not MusicMood.won(v, 0), "a spectator didn't")
end)

T.test("six tracks, two of them stings", function()
	T.equal(#MusicMood.TRACKS, 6)
	T.expect(MusicMood.STINGS.Victory and MusicMood.STINGS.Results, "Victory and Results play once")
	T.expect(not MusicMood.STINGS.Peace, "the rest loop")
end)

T.finish()
