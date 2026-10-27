--!strict
-- Phase 3: elimination, Primordials, charges, the six powers, immunity and the Cataclysm's disasters.
local Army = require("../src/shared/Sim/Army")
local Commands = require("../src/shared/Sim/Commands")
local Config = require("../src/shared/Config")
local Diplomacy = require("../src/shared/Sim/Diplomacy")
local Economy = require("../src/shared/Sim/Economy")
local Maps = require("../src/shared/Maps")
local Match = require("../src/shared/Sim/Match")
local Primordial = require("../src/shared/Sim/Primordial")
local Rng = require("../src/shared/Sim/Rng")
local Siege = require("../src/shared/Sim/Siege")
local Snapshot = require("../src/shared/Snapshot")
local T = require("./TestKit")
local Tick = require("../src/shared/Sim/Tick")
local Victory = require("../src/shared/Sim/Victory")
local Types = require("../src/shared/Types")

local A, B, C = 1, 2, 3
local BOB = 2002 -- Bob's userId

local function fresh(): Types.MatchState
	local state = Match.new(Maps.get("skyshards"))
	state.tick = Config.Phases.PeaceEndTick + 10
	state.phase = "War"
	return state
end

local function owned(state: Types.MatchState, nationId: number): { number }
	local out = {}
	for id, p in state.provinces do
		if p.owner == nationId then
			table.insert(out, id)
		end
	end
	table.sort(out)
	return out
end

-- a province of the nation that isn't its capital
local function plainProvince(state: Types.MatchState, nationId: number): number
	for _, id in owned(state, nationId) do
		if id ~= state.nations[nationId].capital then
			return id
		end
	end
	error("no province")
end

local function neutralProvince(state: Types.MatchState): number
	for id, p in state.provinces do
		if p.owner == nil and p.terrain ~= "Mountain" then
			return id
		end
	end
	error("no neutral province")
end

local function mountain(state: Types.MatchState): number?
	for id, p in state.provinces do
		if p.terrain == "Mountain" then
			return id
		end
	end
	return nil
end

-- Take everything from `victim` except `keep` non-capital provinces, giving it to `winner`.
local function strip(state: Types.MatchState, victim: number, winner: number, keep: number)
	local kept = 0
	for _, id in owned(state, victim) do
		if id ~= state.nations[victim].capital and kept < keep then
			kept += 1
		else
			state.provinces[id].owner = winner
		end
	end
end

local function cast(state, nation: number, power: Types.PrimordialPower, target: number)
	return Commands.apply(state, nation, { kind = "Power", power = power, target = target })
end

-- Costs, targets and effects ------------------------------------------------------------------------

T.test("costs come from Config", function()
	T.equal(Primordial.cost("Meteor"), 2)
	T.equal(Primordial.cost("Plague"), 2)
	T.equal(Primordial.cost("Rebels"), 2)
	T.equal(Primordial.cost("Earthquake"), 1)
	T.equal(Primordial.cost("Blessing"), 1)
	T.equal(Primordial.cost("Shield"), 1)
	for _, power in Primordial.POWERS do
		T.expect(Primordial.TARGETS[power] ~= nil, power .. " has a target type")
	end
end)

T.test("Meteor kills half an army and costs a development level in its province", function()
	local state = fresh()
	state.nations[A].charges = 3
	local where = plainProvince(state, B)
	local dev = state.provinces[where].development
	local army = Army.spawn(state, B, where, 4000)
	local ok, err = cast(state, A, "Meteor", army.id)
	T.expect(ok, err)
	T.equal(army.men, 2000)
	T.equal(state.provinces[where].development, math.max(1, dev - 1))
	T.equal(state.nations[A].charges, 1)
	local e = state.events[#state.events]
	T.equal(e.kind, "Power")
	T.equal(Primordial.POWERS[e.a], "Meteor")
	T.equal(e.b, B)
	T.equal(e.province, where)
end)

T.test("Meteor destroys an army left under the minimum, and never takes development below 1", function()
	local state = fresh()
	state.nations[A].charges = 2
	local where = plainProvince(state, B)
	state.provinces[where].development = 1
	local army = Army.spawn(state, B, where, 900)
	T.expect((cast(state, A, "Meteor", army.id)))
	T.equal(state.armies[army.id], nil)
	T.equal(state.provinces[where].development, 1)
end)

T.test("Plague halves a nation's manpower income for 60 s", function()
	local state = fresh()
	state.nations[A].charges = 2
	local before = Economy.monthlyIncome(state, B).manpower
	T.expect((cast(state, A, "Plague", B)))
	T.equal(state.nations[B].plagueUntil, state.tick + Config.Primordial.Powers.Plague.ticks)
	T.equal(Economy.monthlyIncome(state, B).manpower, before * 0.5)
	T.equal(Economy.monthlyIncome(state, B).gold, Economy.monthlyIncome(state, C).gold, "gold untouched")
	state.tick += Config.Primordial.Powers.Plague.ticks
	Primordial.expire(state)
	T.equal(state.nations[B].plagueUntil, nil)
	T.equal(Economy.monthlyIncome(state, B).manpower, before)
end)

T.test("Rebels spawn a 3,000-man neutral army that besieges the province and turns it neutral", function()
	local state = fresh()
	state.nations[A].charges = 2
	local where = plainProvince(state, B)
	T.expect((cast(state, A, "Rebels", where)))
	local rebels = Army.idleAt(state, 0, where)
	T.expect(rebels ~= nil, "a neutral army stands there")
	T.equal((rebels :: Types.Army).men, Config.Primordial.Powers.Rebels.men)
	local need = Siege.required(state.provinces[where])
	for _ = 1, need do
		Siege.step(state)
	end
	T.equal(state.provinces[where].owner, nil, "the rebels took it")
end)

T.test("Rebels fight the owner's army in the province", function()
	local state = fresh()
	state.nations[A].charges = 2
	local where = plainProvince(state, B)
	Army.spawn(state, B, where, 5000)
	T.expect((cast(state, A, "Rebels", where)))
	Tick.advance(state, Rng.new(3))
	T.expect(state.battles[where] ~= nil, "a battle started")
	T.expect(state.provinces[where].siege == nil, "no siege while fighting")
end)

T.test("Earthquake destroys a building, and needs one", function()
	local state = fresh()
	state.nations[A].charges = 2
	local where = plainProvince(state, B)
	local ok, err = cast(state, A, "Earthquake", where)
	T.expect(not ok)
	T.equal(err, "NoBuilding")
	state.provinces[where].building = "Fort"
	T.expect((cast(state, A, "Earthquake", where)))
	T.equal(state.provinces[where].building, "None")
	T.equal(state.nations[A].charges, 1)
end)

T.test("Blessing doubles one province's gold for 60 s", function()
	local state = fresh()
	state.nations[A].charges = 1
	local where = plainProvince(state, A)
	local before = Economy.monthlyIncome(state, A).gold
	local yield = Economy.provinceYield(state.provinces[where])
	T.expect((cast(state, A, "Blessing", where)))
	T.equal(Economy.monthlyIncome(state, A).gold, before + yield * Config.Primordial.Powers.Blessing.goldBonus)
	state.tick += Config.Primordial.Powers.Blessing.ticks
	T.equal(Economy.monthlyIncome(state, A).gold, before, "it wore off")
	Primordial.expire(state)
	T.equal(state.provinces[where].buffs.Blessing, nil)
end)

T.test("Divine shield stops a siege for 30 s", function()
	local state = fresh()
	state.nations[A].charges = 1
	local target = plainProvince(state, A)
	state.wars[1] = { id = 1, attackers = { B }, defenders = { A }, startedAt = state.tick }
	T.expect((cast(state, A, "Shield", target)))
	Army.spawn(state, B, target, 3000)
	for _ = 1, 5 do
		Siege.step(state)
	end
	T.equal(state.provinces[target].siege, nil, "no progress while shielded")
	state.tick += Config.Primordial.Powers.Shield.ticks
	Siege.step(state)
	T.expect(state.provinces[target].siege ~= nil, "the siege starts once the shield is gone")
end)

T.test("invalid targets are refused and cost nothing", function()
	local state = fresh()
	state.nations[A].charges = 5
	local function refused(power: Types.PrimordialPower, target: number, reason: string)
		local ok, err = cast(state, A, power, target)
		T.expect(not ok, power .. " should be refused")
		T.equal(err, reason, power)
	end
	refused("Meteor", 9999, "UnknownArmy")
	refused("Plague", 99, "BadTarget")
	refused("Rebels", 9999, "UnknownProvince")
	refused("Rebels", neutralProvince(state), "BadTarget")
	refused("Blessing", neutralProvince(state), "BadTarget")
	refused("Shield", neutralProvince(state), "BadTarget")
	local m = mountain(state)
	if m then
		refused("Earthquake", m, "BadTarget")
	end
	-- harmful powers on yourself
	refused("Plague", A, "OwnTarget")
	local mine = Army.spawn(state, A, state.nations[A].capital, 2000)
	refused("Meteor", mine.id, "OwnTarget")
	-- an eliminated nation is no target
	state.nations[C].eliminated = true
	refused("Plague", C, "BadTarget")
	T.equal(state.nations[A].charges, 5)
	-- not enough charges
	state.nations[A].charges = 1
	refused("Plague", B, "NotEnoughCharges")
	-- unknown power names never reach Sim through the router, but Sim refuses them too
	local ok = Primordial.use(state, { nation = A }, "Nuke" :: any, B)
	T.expect(not ok)
end)

T.test("no powers in Peace", function()
	local state = Match.new(Maps.get("skyshards"))
	state.nations[A].charges = 5
	local ok, err = cast(state, A, "Plague", B)
	T.expect(not ok)
	T.equal(err, "NoPowersYet")
end)

-- Immunity -------------------------------------------------------------------------------------------

T.test("a nation is hit by a harmful power at most once per 30 s; gifts ignore it", function()
	local state = fresh()
	state.nations[A].charges = 5
	state.nations[C].charges = 5
	T.expect((cast(state, A, "Plague", B)))
	T.equal(state.nations[B].powerImmuneUntil, state.tick + Config.Primordial.ImmunityTicks)
	local where = plainProvince(state, B)
	local ok, err = cast(state, C, "Rebels", where)
	T.expect(not ok)
	T.equal(err, "Immune")
	T.equal(state.nations[C].charges, 5, "a refused power costs nothing")
	-- B can still be shielded or blessed
	T.expect((cast(state, C, "Shield", where)))
	state.tick += Config.Primordial.ImmunityTicks - 1
	T.expect(not cast(state, C, "Rebels", where), "still immune one tick before the end")
	state.tick += 1
	T.expect((cast(state, C, "Rebels", where)))
end)

-- Charges --------------------------------------------------------------------------------------------

T.test("nations earn a charge every 4 minutes, Primordials every minute", function()
	local state = fresh()
	state.primordials[BOB] = { userId = BOB, charges = 0 }
	state.tick = 0
	for _ = 1, Config.Primordial.NationChargeTicks do
		state.tick += 1
		state.phase = Match.phaseAt(state.tick)
		Primordial.charge(state)
	end
	T.equal(state.nations[A].charges, 1)
	T.equal(
		state.primordials[BOB].charges,
		Config.Primordial.NationChargeTicks / Config.Primordial.PrimordialChargeTicks
	)
end)

T.test("charges come twice as fast in the Cataclysm", function()
	local state = fresh()
	state.primordials[BOB] = { userId = BOB, charges = 0 }
	state.tick = Config.Phases.WarEndTick
	state.phase = "Cataclysm"
	for _ = 1, Config.Primordial.NationChargeTicks do
		state.tick += 1
		Primordial.charge(state)
	end
	T.equal(state.nations[A].charges, 2)
	T.equal(state.primordials[BOB].charges, Config.Primordial.MaxCharges, "8 earned, capped")
end)

T.test("charges stop at the cap; eliminated nations earn none", function()
	local state = fresh()
	state.nations[A].charges = Config.Primordial.MaxCharges
	state.nations[B].eliminated = true
	state.tick = Config.Primordial.NationChargeTicks * 2
	Primordial.charge(state)
	T.equal(state.nations[A].charges, Config.Primordial.MaxCharges)
	T.equal(state.nations[B].charges, 0)
	T.equal(state.nations[C].charges, 1)
end)

-- Elimination ----------------------------------------------------------------------------------------

T.test("eliminated: capital lost and fewer than 3 provinces", function()
	local state = fresh()
	T.expect(not Primordial.shouldEliminate(state, B), "a full nation")
	strip(state, B, A, 3)
	T.expect(not Primordial.shouldEliminate(state, B), "no capital but 3 provinces")
	strip(state, B, A, 2)
	T.expect(Primordial.shouldEliminate(state, B), "no capital and 2 provinces")
	-- holding the capital alone keeps a nation alive
	for _, id in owned(state, C) do
		if id ~= state.nations[C].capital then
			state.provinces[id].owner = A
		end
	end
	T.expect(not Primordial.shouldEliminate(state, C), "capital only")
end)

T.test("an eliminated player rises as a Primordial; its land turns neutral with garrisons", function()
	local state = fresh()
	local bob = state.nations[B]
	bob.controller = "Player"
	bob.userId = BOB
	bob.charges = 1
	strip(state, B, A, 2)
	local left = owned(state, B)
	T.equal(#left, 2)
	local army = Army.spawn(state, B, left[1], 3000)
	-- an alliance of two and a war with A
	state.alliances[1] = { id = 1, members = { B, C } }
	bob.allianceId = 1
	state.nations[C].allianceId = 1
	state.wars[1] = { id = 1, attackers = { A }, defenders = { B, C }, startedAt = state.tick }
	Tick.advance(state, Rng.new(1))
	T.expect(bob.eliminated, "eliminated")
	T.equal(state.armies[army.id], nil, "its army disbanded")
	for _, id in left do
		T.equal(state.provinces[id].owner, nil, "neutral")
		local g = Army.idleAt(state, 0, id)
		T.expect(g ~= nil and g.men == Config.NeutralGarrison, "fresh garrison")
	end
	local p = state.primordials[BOB]
	T.expect(p ~= nil, "Bob is a Primordial")
	T.equal(p.charges, 1, "kept his unspent charges")
	T.equal(bob.charges, 0)
	T.equal(bob.allianceId, nil)
	T.equal(state.nations[C].allianceId, nil, "a one-nation alliance dissolves")
	T.equal(state.alliances[1], nil)
	T.expect(Diplomacy.atWar(state, A, C), "the war goes on without Bob")
	T.expect(not Diplomacy.atWar(state, A, B))
	local sawEvent = false
	for _, e in state.events do
		sawEvent = sawEvent or (e.kind == "Eliminated" and e.a == B)
	end
	T.expect(sawEvent, "an Eliminated event")
	-- Bob can't give orders any more, and leaving doesn't hand his dead nation to a bot seat
	local ok, err = Commands.apply(state, B, { kind = "Develop", province = left[1] })
	T.expect(not ok)
	T.equal(err, "NoNation")
	Match.unseatPlayer(state, BOB)
	T.equal(Match.seatPlayer(state, BOB), B, "rejoining keeps him the Primordial")
end)

T.test("an eliminated bot simply ends", function()
	local state = fresh()
	strip(state, C, A, 0)
	Tick.advance(state, Rng.new(1))
	T.expect(state.nations[C].eliminated)
	T.equal(next(state.primordials), nil)
end)

T.test("scores and win checks still work with an eliminated nation", function()
	local state = fresh()
	strip(state, B, A, 0)
	Tick.advance(state, Rng.new(1))
	T.expect(state.nations[B].eliminated)
	local scores = Victory.scores(state)
	T.equal(#scores, 10)
	T.equal(scores[1].nation, A, "Aurora leads with Zephyr's land")
	T.equal(Victory.score(state, B), 0)
	T.equal(state.result, nil, "16 of 131 is no domination")
	local result = Victory.byScore(state)
	T.equal(result.winners[1], A)
end)

-- Primordials ----------------------------------------------------------------------------------------

T.test("a Primordial earns charges and casts powers, and can do nothing else", function()
	local state = fresh()
	state.nations[B].eliminated = true
	state.primordials[BOB] = { userId = BOB, charges = 0 }
	state.tick = 10 * Config.Primordial.PrimordialChargeTicks -- War, on a charge boundary
	for _ = 1, 2 * Config.Primordial.PrimordialChargeTicks do
		state.tick += 1
		Primordial.charge(state)
	end
	T.equal(state.primordials[BOB].charges, 2)
	local where = plainProvince(state, A)
	local army = Army.spawn(state, A, where, 4000)
	local ok, err = Commands.applyPrimordial(state, BOB, { kind = "Power", power = "Meteor", target = army.id })
	T.expect(ok, err)
	T.equal(army.men, 2000)
	T.equal(state.primordials[BOB].charges, 0)
	ok, err = Commands.applyPrimordial(state, BOB, { kind = "Develop", province = where })
	T.expect(not ok)
	T.equal(err, "Primordial")
	ok, err = Commands.applyPrimordial(state, 777, { kind = "Power", power = "Plague", target = A })
	T.expect(not ok)
	T.equal(err, "NoNation")
	-- the nation that eliminated him is a fair target
	state.primordials[BOB].charges = 2
	state.nations[A].powerImmuneUntil = 0
	T.expect((Commands.applyPrimordial(state, BOB, { kind = "Power", power = "Plague", target = A })))
end)

-- Cataclysm ------------------------------------------------------------------------------------------

local function disasterTicks(seed: number): ({ number }, { string })
	local state = Match.new(Maps.get("skyshards"))
	state.tick = Config.Phases.WarEndTick - 1
	local rng = Rng.new(seed)
	local ticks, kinds = {}, {}
	while state.result == nil do
		Tick.advance(state, rng)
		for _, e in state.events do
			if e.kind == "Disaster" then
				table.insert(ticks, state.tick)
				table.insert(kinds, Primordial.POWERS[e.a] .. "@" .. e.province)
			end
		end
		table.clear(state.events)
	end
	return ticks, kinds
end

T.test("a disaster strikes every 60 s in the Cataclysm, from the seeded Rng", function()
	local ticks, kinds = disasterTicks(7)
	local expected = {}
	local t = Config.Phases.WarEndTick + Config.Primordial.CataclysmDisasterTicks
	while t < Config.Phases.MatchEndTick do
		table.insert(expected, t)
		t += Config.Primordial.CataclysmDisasterTicks
	end
	T.equal(#ticks, #expected)
	for i, tick in ticks do
		T.equal(tick, expected[i])
	end
	local again = select(2, disasterTicks(7))
	T.equal(table.concat(kinds, ","), table.concat(again, ","), "same seed, same disasters")
	for _, k in kinds do
		T.expect(not string.find(k, "Blessing") and not string.find(k, "Shield"), "only harmful powers")
	end
end)

T.test("no disasters before the Cataclysm", function()
	local state = fresh()
	state.tick = Config.Phases.PeaceEndTick
	state.phase = "War"
	T.expect(not Primordial.disasterDue(state))
	state.tick = Config.Phases.WarEndTick
	state.phase = "Cataclysm"
	T.expect(not Primordial.disasterDue(state), "not on the first Cataclysm tick")
	state.tick += Config.Primordial.CataclysmDisasterTicks
	T.expect(Primordial.disasterDue(state))
end)

T.test("a disaster respects immunity and hits only nations", function()
	local state = fresh()
	for _, n in state.nations do
		n.powerImmuneUntil = state.tick + 100
	end
	T.equal(Primordial.disaster(state, Rng.new(1)), nil, "everyone is immune: nothing happens")
	state.nations[B].powerImmuneUntil = 0
	local power = Primordial.disaster(state, Rng.new(1))
	T.expect(power ~= nil)
	local e = state.events[#state.events]
	T.equal(e.kind, "Disaster")
	T.equal(e.b, B)
	T.expect(state.nations[B].powerImmuneUntil > state.tick)
end)

-- Replication ----------------------------------------------------------------------------------------

T.test("snapshots carry charges, Primordials and effect timers; deltas only when they change", function()
	local state = fresh()
	state.nations[A].charges = 2
	local before = Snapshot.full(state)
	T.expect((cast(state, A, "Plague", B)))
	state.primordials[BOB] = { userId = BOB, charges = 3 }
	state.provinces[5].buffs.Blessing = state.tick + 60
	state.provinces[6].shieldUntil = state.tick + 30
	local after = Snapshot.full(state)
	local delta = Snapshot.diff(before, after, state.events)
	T.expect(delta ~= nil)
	local d = delta :: Snapshot.DeltaData
	T.expect(d.primordials ~= nil and #(d.primordials :: any) == 1)
	T.equal((d.primordials :: any)[1].charges, 3)
	local client = Snapshot.apply(before, d)
	T.equal(client.nations[A].charges, 0)
	T.equal(client.nations[B].plagueUntil, state.tick + 60)
	T.equal(client.provinces[5].blessedUntil, state.tick + 60)
	T.equal(client.provinces[6].shieldUntil, state.tick + 30)
	T.equal(client.primordials[1].userId, BOB)
	local again = Snapshot.diff(after, Snapshot.full(state), nil)
	T.equal(again, nil, "nothing changed, nothing sent")
end)

T.finish()
