--!strict
-- Map pings (Sim.Pings, docs/NEXT_FEATURES.md 4) on Skyshards: only allies may ping and only allies see them, the
-- cooldown and the per-minute cap, a third ping replacing the oldest, expiry, a fallen sender's pings, mountains,
-- the Ping command, and pings never reaching the snapshot or the delta.
local Commands = require("../src/shared/Sim/Commands")
local Config = require("../src/shared/Config")
local Diplomacy = require("../src/shared/Sim/Diplomacy")
local Maps = require("../src/shared/Maps")
local Match = require("../src/shared/Sim/Match")
local Pings = require("../src/shared/Sim/Pings")
local Rng = require("../src/shared/Sim/Rng")
local Snapshot = require("../src/shared/Snapshot")
local T = require("./TestKit")
local Telemetry = require("../src/shared/Sim/Telemetry")
local Tick = require("../src/shared/Sim/Tick")
local Types = require("../src/shared/Types")

local map = Maps.get("skyshards")
local AURORA, ZEPHYR, NIMBUS, TEMPEST = 1, 2, 3, 4

local function provinceOf(state: Types.MatchState, nationId: number): number
	for id, p in state.provinces do
		if p.owner == nationId then
			return id
		end
	end
	error("no province of " .. nationId)
end

local function mountain(state: Types.MatchState): number
	for id, p in state.provinces do
		if p.terrain == "Mountain" then
			return id
		end
	end
	error("no mountain")
end

-- Aurora and Zephyr allied, Nimbus at war with them, in Peace at tick 30.
local function fresh(): Types.MatchState
	local state = Match.new(map)
	state.tick = 30
	T.expect((Diplomacy.ally(state, AURORA, ZEPHYR)), "ally")
	return state
end

local function ping(state: Types.MatchState, nationId: number, kind: string, province: number): (boolean, string?)
	return Commands.apply(state, nationId, { kind = "Ping", ping = kind :: Types.PingKind, province = province })
end

T.test("the four kinds, and nothing else", function()
	for _, kind in Config.Pings.Kinds do
		T.expect(Pings.isKind(kind), kind)
	end
	T.equal(#Config.Pings.Kinds, 4)
	T.expect(not Pings.isKind("Hello"), "a made-up kind")
	T.expect(not Pings.isKind(1), "a number")
	T.expect(not Pings.isKind(nil), "nothing")
end)

T.test("a nation with no allies can't ping", function()
	local state = Match.new(map)
	local ok, reason = Pings.canPing(state, NIMBUS, "Attack", provinceOf(state, AURORA), 0)
	T.expect(not ok)
	T.equal(reason, "NoAllies")
	T.equal(#Pings.team(state, NIMBUS), 1, "its team is itself")
end)

T.test("an ally pings: it lands in state.pings with its lifetime", function()
	local state = fresh()
	local target = provinceOf(state, NIMBUS)
	local ok, reason = ping(state, AURORA, "Attack", target)
	T.expect(ok, tostring(reason))
	T.equal(#state.pings, 1)
	local p = state.pings[1]
	T.equal(p.id, 1)
	T.equal(p.by, AURORA)
	T.equal(p.kind, "Attack")
	T.equal(p.province, target)
	T.equal(p.untilTick, 30 + Config.Pings.LifeTicks)
end)

T.test("only the sender's alliance sees a ping: never an enemy, never a neutral", function()
	local state = fresh()
	state.tick = Config.Phases.PeaceEndTick
	state.phase = "War"
	state.wars[1] = { id = 1, attackers = { NIMBUS }, defenders = { AURORA, ZEPHYR }, startedAt = state.tick }
	T.expect(Diplomacy.atWar(state, NIMBUS, ZEPHYR), "Nimbus is at war with both")
	T.expect((ping(state, AURORA, "Defend", provinceOf(state, AURORA))), "ping")
	local seen: { [number]: boolean } = {}
	for _, n in Pings.recipients(state, state.pings[1]) do
		seen[n] = true
	end
	T.expect(seen[AURORA], "the sender sees its own ping")
	T.expect(seen[ZEPHYR], "the ally sees it")
	T.expect(not seen[NIMBUS], "the enemy never does")
	T.expect(not seen[TEMPEST], "a neutral never does")
	T.expect(not seen[0], "nor the neutral land")
	-- a third member joins: it sees the next ping too
	T.expect((Diplomacy.ally(state, ZEPHYR, TEMPEST)), "Tempest joins")
	T.equal(#Pings.recipients(state, state.pings[1]), 3)
end)

T.test("an eliminated ally sees nothing and doesn't count as an ally", function()
	local state = fresh()
	state.nations[ZEPHYR].eliminated = true
	local ok, reason = Pings.canPing(state, AURORA, "Look", provinceOf(state, AURORA), state.tick)
	T.expect(not ok)
	T.equal(reason, "NoAllies")
end)

T.test("the cooldown: one ping every CooldownTicks", function()
	local state = fresh()
	local target = provinceOf(state, NIMBUS)
	T.expect((ping(state, AURORA, "Attack", target)), "first")
	local ok, reason = ping(state, AURORA, "Help", target)
	T.expect(not ok)
	T.equal(reason, "TooSoon")
	state.tick += Config.Pings.CooldownTicks - 1
	T.equal(select(2, ping(state, AURORA, "Help", target)), "TooSoon", "one tick early")
	state.tick += 1
	T.expect((ping(state, AURORA, "Help", target)), "after the cooldown")
	-- the ally's cooldown is its own
	T.expect((ping(state, ZEPHYR, "Look", target)), "Zephyr pings at once")
end)

T.test("the per-minute cap: MaxPerMinute pings in any MinuteTicks", function()
	local state = fresh()
	local target = provinceOf(state, NIMBUS)
	local start = state.tick
	for i = 1, Config.Pings.MaxPerMinute do
		T.expect((ping(state, AURORA, "Look", target)), "ping " .. i)
		state.tick += Config.Pings.CooldownTicks
	end
	T.expect(state.tick - start < Config.Pings.MinuteTicks, "all inside one minute")
	local ok, reason = ping(state, AURORA, "Look", target)
	T.expect(not ok)
	T.equal(reason, "TooMany")
	state.tick = start + Config.Pings.MinuteTicks -- the first one leaves the window
	T.expect((ping(state, AURORA, "Look", target)), "a minute after the first")
end)

T.test("a third live ping replaces the sender's oldest", function()
	local state = fresh()
	local target = provinceOf(state, NIMBUS)
	for _ = 1, Config.Pings.MaxActive do
		T.expect((ping(state, AURORA, "Attack", target)), "ping")
		state.tick += Config.Pings.CooldownTicks
	end
	T.expect((ping(state, ZEPHYR, "Defend", target)), "the ally's ping")
	T.equal(#state.pings, Config.Pings.MaxActive + 1)
	T.expect((ping(state, AURORA, "Help", target)), "the third")
	T.equal(#state.pings, Config.Pings.MaxActive + 1, "Aurora still has MaxActive, Zephyr keeps its own")
	local ids = {}
	for _, p in state.pings do
		table.insert(ids, p.id)
	end
	T.equal(table.concat(ids, ","), "2,3,4", "the oldest (1) went")
end)

T.test("pings expire after untilTick, through the real tick", function()
	local state = fresh()
	local rng = Rng.new(1)
	T.expect((ping(state, AURORA, "Attack", provinceOf(state, NIMBUS))), "ping")
	local untilTick = state.pings[1].untilTick
	while state.tick < untilTick do
		Tick.advance(state, rng)
	end
	T.equal(#state.pings, 1, "still there at untilTick")
	Tick.advance(state, rng)
	T.equal(#state.pings, 0, "gone the tick after")
	T.equal(state.tick - 30, Config.Pings.LifeTicks + 1)
end)

T.test("a fallen sender's pings go at once; its history is forgotten after a minute", function()
	local state = fresh()
	T.expect((ping(state, AURORA, "Attack", provinceOf(state, NIMBUS))), "ping")
	T.expect(state.pingSent[AURORA] ~= nil, "history kept")
	state.nations[AURORA].eliminated = true
	Pings.expire(state)
	T.equal(#state.pings, 0)
	T.equal(#Pings.recipients(state, { id = 9, by = AURORA, kind = "Look", province = 1, untilTick = 99 }), 0)
	state.tick += Config.Pings.MinuteTicks
	Pings.expire(state)
	T.equal(state.pingSent[AURORA], nil, "history forgotten")
end)

T.test("mountains and unknown provinces are refused", function()
	local state = fresh()
	T.equal(select(2, ping(state, AURORA, "Look", mountain(state))), "BadTarget")
	T.equal(select(2, ping(state, AURORA, "Look", 9999)), "BadTarget")
	T.equal(#state.pings, 0)
	T.equal(state.pingSent[AURORA], nil, "a refused ping doesn't count against the cooldown")
end)

T.test(
	"pings only in Peace, War and Cataclysm; never for a spectator or a bot running someone else's nation",
	function()
		local state = fresh()
		state.phase = "Results"
		T.equal(select(2, Pings.canPing(state, AURORA, "Look", provinceOf(state, AURORA), state.tick)), "Phase")
		T.equal(select(2, ping(state, AURORA, "Look", provinceOf(state, AURORA))), "MatchOver")
		state.phase = "Peace"
		T.equal(select(2, ping(state, AURORA, "Fireworks", provinceOf(state, AURORA))), "BadRequest")
		-- a player acts only for the nation they hold
		Match.seatPlayer(state, 101)
		local command: Types.Command = { kind = "Ping", ping = "Look", province = provinceOf(state, AURORA) }
		T.equal(select(2, Commands.applyFor(state, 999, nil, command)), "NoNation", "a spectator")
		T.expect((Commands.applyFor(state, 101, AURORA, command)), "the player holding Aurora")
	end
)

T.test("pings never reach the snapshot or the delta", function()
	local state = fresh()
	table.clear(state.events)
	local before = Snapshot.full(state)
	T.expect((ping(state, AURORA, "Attack", provinceOf(state, NIMBUS))), "ping")
	local after = Snapshot.full(state)
	for key in after :: any do
		T.expect(not string.find(string.lower(key), "ping"), "snapshot field " .. key)
	end
	local delta = Snapshot.diff(before, after, state.events)
	T.equal(delta, nil, "a ping changes nothing anyone else is sent")
end)

T.test("ping_sent says the kind, the map and whose province it is", function()
	local state = fresh()
	state.nations[AURORA].userId = 101
	state.tick = Config.Phases.PeaceEndTick
	state.phase = "War"
	state.wars[1] = { id = 1, attackers = { AURORA, ZEPHYR }, defenders = { NIMBUS }, startedAt = state.tick }
	local function target(province: number): string
		local e = Telemetry.pingSent(state, 101, "Attack", province)
		T.equal(e.name, "ping_sent")
		T.equal(e.fields[1], "attack")
		T.equal(e.fields[2], "skyshards")
		return e.fields[3]
	end
	T.equal(target(provinceOf(state, AURORA)), "own")
	T.equal(target(provinceOf(state, ZEPHYR)), "ally")
	T.equal(target(provinceOf(state, NIMBUS)), "enemy")
	T.equal(target(provinceOf(state, TEMPEST)), "neutral", "a nation at peace with the sender")
	local unowned = 0
	for id, p in state.provinces do
		if p.owner == nil and p.terrain ~= "Mountain" then
			unowned = id
		end
	end
	T.equal(target(unowned), "neutral", "unowned land")
end)

T.finish()
