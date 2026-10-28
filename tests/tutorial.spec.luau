--!strict
-- The tutorial match (docs/DESIGN.md "Tutorial"): setup, seating, the six prompts in order, the bots' part, where
-- the arrow points, skipping, and the profile's tutorialDone flag.
local Commands = require("../src/shared/Sim/Commands")
local Config = require("../src/shared/Config")
local Diplomacy = require("../src/shared/Sim/Diplomacy")
local Maps = require("../src/shared/Maps")
local Match = require("../src/shared/Sim/Match")
local Progression = require("../src/shared/Sim/Progression")
local Rng = require("../src/shared/Sim/Rng")
local T = require("./TestKit")
local Tick = require("../src/shared/Sim/Tick")
local Tutorial = require("../src/shared/Sim/Tutorial")
local Types = require("../src/shared/Types")

type MatchState = Types.MatchState

local SLOT = Config.Tutorial.PlayerSlot
local USER = 77

local function fresh(): (MatchState, Types.TutorialState)
	local state = Match.new(Maps.get(Config.Tutorial.Map))
	local tut = Tutorial.setup(state, SLOT)
	return state, tut
end

local function count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

local function myArmy(state: MatchState): Types.Army?
	for _, a in state.armies do
		if a.owner == SLOT then
			return a
		end
	end
	return nil
end

-- The server's loop for the tutorial: queued commands (the player's and the bots' tutorial orders), a tick, then
-- the tutorial watches. Stops when the step changes or after `ticks`.
local function run(state: MatchState, tut: Types.TutorialState, ticks: number)
	local rng = Rng.new(5)
	local step = tut.step
	for _ = 1, ticks do
		for _, order in Tutorial.botOrders(state, tut) do
			Commands.apply(state, order.nation, order.command)
		end
		Tick.advance(state, rng)
		Tutorial.update(state, tut)
		table.clear(state.events)
		if tut.step ~= step then
			return
		end
	end
end

-- A player command, recorded the way TutorialService does.
local function player(state: MatchState, tut: Types.TutorialState, command: Types.Command): boolean
	local ok, reason = Commands.apply(state, SLOT, command)
	Tutorial.recordCommand(tut, command, ok)
	T.expect(ok, command.kind .. " refused: " .. tostring(reason))
	return ok
end

T.test("the tutorial map's player slot has a neutral neighbour and borders a nation", function()
	local state = Match.new(Maps.get(Config.Tutorial.Map))
	local neutral, borders = false, false
	for _, p in state.provinces do
		if p.owner == SLOT then
			for _, n in p.neighbors do
				local q = state.provinces[n]
				neutral = neutral or (q.owner == nil and q.terrain ~= "Mountain")
				borders = borders or (q.owner ~= nil and q.owner ~= SLOT)
			end
		end
	end
	T.expect(neutral, "a neutral province to take first")
	T.expect(borders, "a nation to declare war on")
end)

T.test("setup keeps the player and the nearest bots; the rest of the map turns neutral", function()
	local state, tut = fresh()
	T.equal(count(state.nations), Config.Tutorial.Bots + 1)
	T.expect(state.nations[SLOT] ~= nil)
	for _, p in state.provinces do
		if p.owner then
			T.expect(state.nations[p.owner] ~= nil, p.name .. " belongs to a nation still in the match")
		end
	end
	-- every neutral land province has a garrison
	local guarded: { [number]: boolean } = {}
	for _, a in state.armies do
		if a.owner == 0 then
			guarded[a.location] = true
		end
	end
	for id, p in state.provinces do
		if p.owner == nil and p.terrain ~= "Mountain" then
			T.expect(guarded[id], p.name .. " has a garrison")
			T.expect(not p.isCapital, p.name .. " is no longer a capital")
		end
	end
	-- the player's neighbours stay
	for _, p in state.provinces do
		if p.owner == SLOT then
			for _, n in p.neighbors do
				local owner = state.provinces[n].owner
				T.expect(owner == nil or state.nations[owner] ~= nil)
			end
		end
	end
	local army = myArmy(state)
	T.expect(army ~= nil and army.men == Config.Tutorial.StartRegiments * Config.Army.MenPerRegiment, "a ready army")
	T.equal(army and army.location, state.nations[SLOT].capital)
	T.equal(state.nations[SLOT].controller, "Player", "the slot is held for the player")
	T.equal(tut.step, 1)
	T.equal(count(tut.startProvinces), Match.provinceCount(state, SLOT))
end)

T.test("the player is seated in the tutorial nation; a second player gets a bot's nation", function()
	local state, tut = fresh()
	T.equal(Tutorial.seat(state, tut, USER), SLOT)
	T.equal(state.nations[SLOT].userId, USER)
	T.equal(Tutorial.seat(state, tut, USER), SLOT, "rejoining")
	local other = Tutorial.seat(state, tut, USER + 1)
	T.expect(other ~= nil and other ~= SLOT)
end)

T.test("no prompt moves on before the player is seated", function()
	local state, tut = fresh()
	state.provinces[assert(Tutorial.neutralTarget(state, SLOT))].owner = SLOT
	T.equal(Tutorial.update(state, tut), nil)
	Tutorial.seat(state, tut, USER)
	T.equal(Tutorial.update(state, tut), 2)
end)

T.test("prompts finish in order, never ahead of time", function()
	local state, tut = fresh()
	Tutorial.seat(state, tut, USER)
	-- an alliance during the first prompt doesn't finish it, and the prompt doesn't move
	local other = assert(Tutorial.pickFriend(state, tut))
	state.alliances[1] = { id = 1, members = { SLOT, other } }
	state.nations[SLOT].allianceId = 1
	state.nations[other].allianceId = 1
	T.equal(Tutorial.update(state, tut), nil)
	T.equal(tut.step, 1)
	-- a recruit made early counts once its prompt comes up
	Tutorial.recordCommand(
		tut,
		{ kind = "Recruit", province = state.nations[SLOT].capital, regiments = 1, troop = "Infantry" },
		true
	)
	Tutorial.recordCommand(tut, { kind = "Power", power = "Blessing", target = 1 }, false)
	T.equal(tut.actions.Power, nil, "a refused command doesn't count")
	state.provinces[assert(Tutorial.neutralTarget(state, SLOT))].owner = SLOT
	T.equal(Tutorial.update(state, tut), 2)
	T.equal(Tutorial.update(state, tut), 3, "one prompt per tick")
end)

T.test("all six prompts through the real rules, with the bots' help", function()
	local state, tut = fresh()
	Tutorial.seat(state, tut, USER)
	local view = Tutorial.view(state, tut)
	T.equal(view.step, 1)
	T.equal(view.total, 6)

	-- 1. Take: march the ready army on the neutral neighbour with the smallest garrison
	local target = assert(Tutorial.neutralTarget(state, SLOT))
	T.equal(view.province, target, "the arrow points at the province to take")
	T.equal(state.provinces[target].owner, nil)
	local army = assert(myArmy(state))
	player(state, tut, { kind = "Move", army = army.id, to = target })
	run(state, tut, 120)
	T.equal(tut.step, 2, "taking the province finished the first prompt")
	T.equal(state.provinces[target].owner, SLOT)

	-- 2. Recruit, at the capital the arrow points at
	view = Tutorial.view(state, tut)
	T.equal(view.province, state.nations[SLOT].capital)
	player(state, tut, { kind = "Recruit", province = view.province, regiments = 1, troop = "Infantry" })
	run(state, tut, 2)
	T.equal(tut.step, 3)

	-- 3. Siege: march on the next neutral province and stay
	local second = assert(Tutorial.neutralTarget(state, SLOT))
	T.expect(second ~= target)
	T.equal(Tutorial.view(state, tut).province, second)
	army = assert(myArmy(state))
	player(state, tut, { kind = "Move", army = army.id, to = second })
	T.equal(Tutorial.view(state, tut).province, second, "the arrow follows the army's destination")
	run(state, tut, 120)
	T.equal(tut.step, 4, "a siege finished the third prompt")
	T.expect(state.provinces[second].siege ~= nil)

	-- 4. Ally: the friend accepts the player's offer
	local friend = assert(tut.friend)
	view = Tutorial.view(state, tut)
	T.equal(view.nation, friend)
	T.equal(state.provinces[view.province].owner, friend, "the arrow points at the friend's land")
	T.equal(state.phase, "Peace")
	player(state, tut, { kind = "Diplomacy", action = "Ally", target = friend, gold = 0 })
	local orders = Tutorial.botOrders(state, tut)
	T.equal(#orders, 1)
	T.equal(orders[1].nation, friend)
	run(state, tut, 3)
	T.expect(Diplomacy.allied(state, SLOT, friend), "allied")
	T.equal(tut.step, 5)

	-- 5. War: Peace ends at once; the rival borders the player and is the weakest neighbour
	local rival = assert(tut.rival)
	T.expect(rival ~= friend)
	T.expect(Diplomacy.borders(state, SLOT, rival), "the rival borders the player")
	T.equal(state.tick, Config.Phases.PeaceEndTick - 1, "the clock jumped to the end of Peace")
	run(state, tut, 1)
	T.equal(state.phase, "War")
	view = Tutorial.view(state, tut)
	T.equal(view.nation, rival)
	T.equal(state.provinces[view.province].owner, rival)
	player(state, tut, { kind = "Diplomacy", action = "War", target = rival, gold = 0 })
	T.expect(Diplomacy.atWar(state, friend, rival), "the ally joined the war")
	run(state, tut, 2)
	T.equal(tut.step, 6)

	-- 6. Power: the player has a charge for a Blessing on their own land
	T.expect(state.nations[SLOT].charges >= Config.Tutorial.GiftCharges, "a charge to spend")
	view = Tutorial.view(state, tut)
	player(state, tut, { kind = "Power", power = "Blessing", target = view.province })
	run(state, tut, 2)
	T.expect(Tutorial.finished(tut), "the tutorial is done")
	T.equal(tut.finishedAt, state.tick)
	T.equal(Tutorial.view(state, tut).step, 7)
	T.equal(Tutorial.update(state, tut), nil, "nothing after the last prompt")
end)

T.test("bots don't accept alliances from anyone but the tutorial player", function()
	local state, tut = fresh()
	Tutorial.seat(state, tut, USER)
	local a = assert(Tutorial.pickFriend(state, tut))
	local b = assert(Tutorial.pickRival(state, tut))
	Commands.apply(state, a, { kind = "Diplomacy", action = "Ally", target = b, gold = 0 })
	T.equal(#Tutorial.botOrders(state, tut), 0)
end)

T.test("skipping hides the prompts for good", function()
	local state, tut = fresh()
	Tutorial.seat(state, tut, USER)
	Tutorial.skip(tut)
	T.equal(Tutorial.view(state, tut).step, 0)
	state.provinces[assert(Tutorial.neutralTarget(state, SLOT))].owner = SLOT
	T.equal(Tutorial.update(state, tut), nil)
end)

T.test("new profiles still need the tutorial; players with a match behind them don't", function()
	T.equal(Progression.newProfile().tutorialDone, false)
	local old: any = Progression.newProfile()
	old.version = 1
	old.tutorialDone = false -- what ProfileStore's Reconcile fills in for a v1 save
	old.stats.matches = 3
	Progression.migrate(old)
	T.equal(old.version, Progression.PROFILE_VERSION)
	T.equal(old.tutorialDone, true)
	local new: any = Progression.newProfile()
	new.version = 1
	Progression.migrate(new)
	T.equal(new.tutorialDone, false)
end)

T.test("a public server sends only players who haven't done the tutorial or played a match", function()
	local p = Progression.newProfile()
	T.expect(Tutorial.needed(p), "a new player")
	p.stats.matches = 1 -- played a public match (say the tutorial teleport failed)
	T.expect(not Tutorial.needed(p), "a player with a match behind them")
	p.stats.matches = 0
	p.tutorialDone = true -- finished, skipped, or played the tutorial match to its end
	T.expect(not Tutorial.needed(p), "a player who did the tutorial")
end)

T.finish()
