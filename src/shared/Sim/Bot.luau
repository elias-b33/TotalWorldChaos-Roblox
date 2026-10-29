--!strict
-- Bot AI (docs/DESIGN.md "Bot AI"). Each plan walks the priority list and returns the first command that applies:
--   1. Defend  2. Recruit  3. Expand  4. Attack  5. Build  6. Diplomacy  (7. Primordial power: see below)
-- Troops, by role in the race's roster: the line troop is the base; a threatened province raises the ranged troop
-- (while it is under Config.Bots.RangedShare of my men); at war, a bot that can pay for them and keep its upkeep
-- reserve recruits its special, its elite and its fast troop, each up to its share of my men (see pickTroop).
-- Tactics (docs/DESIGN.md "Bot AI", Config.Bots): it raises the troop that beats the armies near its land
-- (counterRole), judges fights with the counters, flanks and both sides' morale (strengths, Battle.outcome), won't
-- attack into a counter without a bigger margin, rests armies with low morale, and strikes with two stacks from two
-- sides at once (strikeTogether, takePlaces).
-- The EU4 pack's diplomacy rides along with the plan like the power does (see social): a bot lets a nation it has
-- nothing against through its land, insults back now and then, and now and then insults a rival. An insulted
-- bot leans towards war with its insulter: that nation is its first war target, at Config.Bots.GrudgeAttackRatio of
-- its usual attack ratio.
-- Bots send the same commands players do, through CommandRouter, and every command is dry-run against
-- Sim/Commands first, so a bot almost never sends one the server refuses. No cheating: bots read the same state
-- any player could see and pay full price for everything.
--
-- Bot.plan is pure: state + nation + rng + difficulty (+ an optional memory the caller keeps) -> commands.
-- Bot.step does the scheduling for a whole match (who plans this tick), for AIService and headless runs.

local Battle = require("./Battle")
local Commands = require("./Commands")
local Config = require("../Config")
local Diplomacy = require("./Diplomacy")
local Economy = require("./Economy")
local EventCards = require("./EventCards")
local Pathing = require("./Pathing")
local Primordial = require("./Primordial")
local Races = require("./Races")
local Rng = require("./Rng")
local Troops = require("./Troops")
local Types = require("../Types")

type MatchState = Types.MatchState
type Army = Types.Army
type Command = Types.Command

export type Difficulty = Types.Difficulty

export type Settings = {
	planTicks: number,
	attackRatio: number,
	noPlayerWarTicks: number,
	targetsLeadingPlayer: boolean,
}

-- What a bot remembers between plans: its province count when each of its wars started, when it last made each
-- kind of offer to each nation (so it doesn't repeat itself every time an offer expires), and the insults and event
-- cards it has decided how to answer.
export type Memory = {
	warStart: { [number]: { startedAt: number, provinces: number } }, -- war id -> snapshot
	offeredAt: { [string]: number }, -- "Ally:3" -> tick
	answered: { [string]: boolean }, -- "insulter:window end" (an insult), "card:id" (an event card) -> decided
}

export type Schedule = {
	nextDue: { [number]: number }, -- nation id -> tick it plans next
	memory: { [number]: Memory },
}

export type Order = { nation: number, command: Command }

local ACTIVE_PHASES = { Peace = true, War = true, Cataclysm = true }

local Bot = {}

function Bot.settings(difficulty: Difficulty): Settings
	if difficulty == "Easy" then
		return Config.Bots.Easy
	elseif difficulty == "Hard" then
		return Config.Bots.Hard
	end
	return Config.Bots.Normal
end

function Bot.newMemory(): Memory
	return { warStart = {}, offeredAt = {}, answered = {} }
end

function Bot.newSchedule(): Schedule
	return { nextDue = {}, memory = {} }
end

-- Dry run --------------------------------------------------------------------------------------------

-- Neighbour lists and the sea's layout never change during a match, so the copy shares them.
local STATIC = { neighbors = true, zones = true, shores = true, straits = true }
local function copy(t: { [any]: any }): any
	local out = table.clone(t)
	for k, x in out do
		if type(x) == "table" and not STATIC[k] then
			out[k] = copy(x)
		end
	end
	return out
end

-- Would the server accept this command right now? Runs the real Sim/Commands on a copy of the state.
function Bot.check(state: MatchState, nationId: number, command: Command): (boolean, string?)
	return Commands.apply(copy(state) :: MatchState, nationId, command)
end

-- What one plan knows about the world ---------------------------------------------------------------

type Threat = {
	location: number, -- where the hostile armies stand
	target: number, -- my province they threaten (the same province if they are inside it)
	armies: { Army },
	inside: boolean,
}

type Ctx = {
	state: MatchState,
	me: number,
	nation: Types.Nation,
	settings: Settings,
	rng: Rng.Rng,
	mine: { number }, -- my provinces, sorted
	isMine: { [number]: boolean },
	counts: { [number]: number }, -- provinces per owner
	totalProvinces: number, -- ownable ones (not mountains)
	armiesAt: { [number]: { Army } },
	hostile: { [number]: { Army } }, -- armies that would fight mine, by province
	mayEnter: { [number]: boolean }, -- owners whose land my armies may enter (Diplomacy.canEnter)
	myArmies: { Army }, -- sorted by id
	men: number,
	troopMen: { [string]: number }, -- my men per troop type
	upkeep: number, -- what my armies cost a month
	isEnemy: { [number]: boolean }, -- nations at war with me
	enemies: { number },
	grudge: { [number]: boolean }, -- nations that insulted me (I hold a grudge against them)
	targeted: { [number]: boolean }, -- provinces my armies stand in (abroad) or are marching to
	reserved: { [number]: number }, -- army id -> where the threat it guards against stands
}

local function sortedKeys(t: { [number]: any }): { number }
	local ids = {}
	for id in t do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

local function context(state: MatchState, me: number, rng: Rng.Rng, settings: Settings): Ctx
	local mine, isMine, counts = {}, {}, {}
	local total = 0
	for _, id in sortedKeys(state.provinces) do
		if state.provinces[id].terrain ~= "Mountain" then
			total += 1 -- shares count ownable provinces only (CatchUp.counts)
		end
		local owner = state.provinces[id].owner
		if owner then
			counts[owner] = (counts[owner] or 0) + 1
		end
		if owner == me then
			table.insert(mine, id)
			isMine[id] = true
		end
	end
	local isEnemy, enemies, mayEnter, grudge = {}, {}, {}, {}
	for _, id in sortedKeys(state.nations) do
		if Diplomacy.atWar(state, me, id) then
			isEnemy[id] = true
			table.insert(enemies, id)
		end
		mayEnter[id] = isEnemy[id] == true or Diplomacy.friendly(state, me, id) or Diplomacy.hasAccess(state, me, id)
		grudge[id] = Diplomacy.grudge(state, me, id) or nil
	end
	local armiesAt: { [number]: { Army } } = {}
	local hostile: { [number]: { Army } } = {}
	local myArmies = {}
	local men = 0
	local troopMen: { [string]: number } = {}
	local targeted = {}
	for _, id in sortedKeys(state.armies) do
		local a = state.armies[id]
		if a.owner == me then
			for troop, n in a.troops do
				troopMen[troop] = (troopMen[troop] or 0) + n
			end
		end
		if a.retreating then
			-- walking home: it takes no orders and fights nobody, but it is still mine to count
			if a.owner == me then
				men += a.men
			end
			continue
		end
		armiesAt[a.location] = armiesAt[a.location] or {}
		table.insert(armiesAt[a.location], a)
		if a.owner ~= me and (a.owner == 0 or isEnemy[a.owner]) then
			hostile[a.location] = hostile[a.location] or {}
			table.insert(hostile[a.location], a)
		end
		if a.owner == me then
			table.insert(myArmies, a)
			men += a.men
			if #a.path > 0 then
				targeted[a.path[#a.path]] = true
			elseif not isMine[a.location] then
				targeted[a.location] = true
			end
		end
	end
	return {
		state = state,
		me = me,
		nation = state.nations[me],
		settings = settings,
		rng = rng,
		mine = mine,
		isMine = isMine,
		counts = counts,
		totalProvinces = total,
		armiesAt = armiesAt,
		hostile = hostile,
		mayEnter = mayEnter,
		myArmies = myArmies,
		men = men,
		troopMen = troopMen,
		upkeep = Economy.upkeep(state, me),
		isEnemy = isEnemy,
		enemies = enemies,
		grudge = grudge,
		targeted = targeted,
		reserved = {},
	}
end

local function hostileOwner(ctx: Ctx, owner: number): boolean
	return owner ~= ctx.me and (owner == 0 or ctx.isEnemy[owner] == true)
end

local NONE: { Army } = {}

-- Armies in a province that would fight mine (neutral garrisons and Rebels, and nations at war with me).
local function hostileAt(ctx: Ctx, provinceId: number): { Army }
	return ctx.hostile[provinceId] or NONE
end

-- Same rule as Diplomacy.canEnter, from the owners worked out once per plan.
local function canEnter(ctx: Ctx, provinceId: number): boolean
	local p = ctx.state.provinces[provinceId]
	if p == nil or p.terrain == "Mountain" then
		return false
	end
	return p.owner == nil or ctx.mayEnter[p.owner] == true
end

local function menOf(armies: { Army }): number
	local n = 0
	for _, a in armies do
		n += a.men
	end
	return n
end

-- Combat strength (men × each troop's attack or defence × its counter against the other side × the Battle
-- modifiers: terrain, fort, race, flank and catch-up bonuses) of my armies and theirs if they fight in this province.
-- `iDefend` says which side holds it. Rolls are the random ± per battle (0 = average). Also each side's kills per man
-- and round (losses split evenly over troop types, so it holds for the whole battle) and my bare modifier. My armies
-- count the provinces they stand in as their directions: stacks striking from two neighbours flank.
local function strengths(
	ctx: Ctx,
	provinceId: number,
	mine: { Army },
	theirs: { Army },
	iDefend: boolean,
	myRoll: number,
	theirRoll: number
): (number, number, number, number, number)
	local sides: Battle.Sides = if iDefend
		then { defenderOwner = ctx.me, defenders = mine, attackers = theirs }
		else {
			defenderOwner = if #theirs > 0 then theirs[1].owner else 0,
			defenders = theirs,
			attackers = mine,
		}
	local myMod = Battle.modifier(ctx.state, provinceId, sides, iDefend, myRoll)
	local theirMod = Battle.modifier(ctx.state, provinceId, sides, not iDefend, theirRoll)
	local terrain = ctx.state.provinces[provinceId].terrain
	local neutral = true -- garrisons and Rebels: my specials' anti-garrison trick counts
	for _, a in theirs do
		neutral = neutral and a.owner == 0
	end
	local my = Battle.strength(mine, iDefend, terrain, neutral and #theirs > 0, Battle.composition(theirs)) * myMod
	local their = Battle.strength(theirs, not iDefend, terrain, false, Battle.composition(mine)) * theirMod
	local myMen, theirMen = menOf(mine), menOf(theirs)
	local rate = Config.Battle.KillRatePerRound
	local myRate = rate * (if myMen > 0 then my / myMen else myMod)
	local theirRate = rate * (if theirMen > 0 then their / theirMen else theirMod)
	return my, their, myRate, theirRate, myMod
end

-- Plays out a battle's rounds with both sides' morale (Battle.outcome): do I win, with enough men to survive?
local function wouldWin(mine: Battle.Fighter, theirs: Battle.Fighter, iDefend: boolean): boolean
	local won, left = Battle.outcome(mine, theirs, iDefend)
	return won and left >= Config.Army.MinArmyMen
end

local function fighter(armies: { Army }, rate: number, scale: number?): Battle.Fighter
	return { men = menOf(armies) * (scale or 1), rate = rate, morale = Battle.morale(armies) }
end

-- Can these armies beat everything standing in a province they attack, even with unlucky rolls?
local function canBeat(ctx: Ctx, provinceId: number, armies: { Army }): boolean
	local theirs = hostileAt(ctx, provinceId)
	if #theirs == 0 then
		return menOf(armies) >= Config.Army.MinArmyMen
	end
	local spread = Config.Battle.RandomSpread
	local _, _, myRate, theirRate = strengths(ctx, provinceId, armies, theirs, false, -spread, spread)
	return wouldWin(fighter(armies, myRate), fighter(theirs, theirRate), false)
end

-- How much one side's men gain from the troop counters against the other's, on average per man (0 = nothing).
local function counterEdge(side: { Army }, enemy: { Army }): number
	local shares = Troops.roleShares(Battle.composition(enemy))
	local comp = Battle.composition(side)
	local total, sum = 0, 0
	for _, troop in Troops.LIST do
		local n = comp[troop]
		if n then
			total += n
			sum += n * Troops.counter(Troops.stats(troop).role, shares)
		end
	end
	return if total > 0 then sum / total - 1 else 0
end

-- Are these armies strong enough (by the difficulty's attack ratio, times `factor` if given) to attack `theirs` in
-- a province? Not with low morale; against troops that counter mine, only with Config.Bots.CounteredExtraRatio more.
-- Strong enough is either that much more strength, or a win even against that many times their men (a worn-out
-- enemy breaks early).
local function aboveRatio(ctx: Ctx, provinceId: number, armies: { Army }, theirs: { Army }, factor: number?): boolean
	if menOf(armies) < Config.Army.MinArmyMen or Battle.morale(armies) < Config.Bots.MinAttackMorale then
		return false
	elseif #theirs == 0 then
		return true
	end
	local my, their, myRate, theirRate = strengths(ctx, provinceId, armies, theirs, false, 0, 0)
	local ratio = ctx.settings.attackRatio * (factor or 1)
	if counterEdge(theirs, armies) - counterEdge(armies, theirs) > Config.Bots.CounterEdge then
		ratio += Config.Bots.CounteredExtraRatio
	end
	return my >= ratio * their or wouldWin(fighter(armies, myRate), fighter(theirs, theirRate, ratio), false)
end

-- The route an army would take (the same BFS as Movement.order), if it doesn't fight anyone before arriving.
local function clearRoute(ctx: Ctx, army: Army, to: number): { number }?
	local path = Pathing.find(ctx.state, ctx.me, army.location, to)
	if path == nil or #path == 0 then
		return nil
	end
	for i = 1, #path - 1 do
		if #hostileAt(ctx, path[i]) > 0 then
			return nil
		end
	end
	return path
end

-- Provinces reachable from `from`, nearest first, without walking through hostile armies (they can be the goal).
local function reachable(ctx: Ctx, from: number): ({ number }, { [number]: number })
	local state = ctx.state
	local dist: { [number]: number } = { [from] = 0 }
	local order = {}
	local queue = { from }
	local head = 1
	while head <= #queue do
		local cur = queue[head]
		head += 1
		if cur == from or #hostileAt(ctx, cur) == 0 then
			for _, n in state.provinces[cur].neighbors do
				if dist[n] == nil and canEnter(ctx, n) then
					dist[n] = dist[cur] + 1
					table.insert(order, n)
					table.insert(queue, n)
				end
			end
		end
	end
	return order, dist
end

-- The nearest province `want` accepts that this army can reach with a clear route; a random one among equally
-- near ones, so matches with different seeds play out differently.
local function pickTarget(ctx: Ctx, army: Army, want: (number) -> boolean): number?
	local order, dist = reachable(ctx, army.location)
	local checks = 0
	local i = 1
	while i <= #order and checks < Config.Bots.MaxRouteChecks do
		local d = dist[order[i]]
		local group = {}
		while i <= #order and dist[order[i]] == d do
			if want(order[i]) then
				table.insert(group, order[i])
			end
			i += 1
		end
		while #group > 0 and checks < Config.Bots.MaxRouteChecks do
			local p = table.remove(group, Rng.int(ctx.rng, 1, #group)) :: number
			checks += 1
			if clearRoute(ctx, army, p) then
				return p
			end
		end
	end
	return nil
end

-- My armies free for a new job, grouped by province (a stack marches and fights together): standing still at
-- home, rested (Config.Bots.MinAttackMorale), not besieging, not fighting, not guarding a border. Biggest stack first.
type Stack = { location: number, armies: { Army }, men: number }

-- Men of other nations' armies in a province that neither fight me nor help me besiege it, and the lowest of their
-- nation ids.
local function rivalsAt(ctx: Ctx, provinceId: number): (number, number)
	local men, lowest = 0, math.huge
	for _, a in ctx.armiesAt[provinceId] or {} do
		if a.owner ~= 0 and not hostileOwner(ctx, a.owner) and not Diplomacy.friendly(ctx.state, ctx.me, a.owner) then
			men += a.men
			lowest = math.min(lowest, a.owner)
		end
	end
	return men, lowest
end

-- Abroad (neutral or enemy land), my army is busy while it fights or besieges. Siege.step gives a province's siege
-- to whoever started it, so if a rival at peace with me holds the siege here, my army gives way.
local function holdsGround(ctx: Ctx, a: Army): boolean
	local province = ctx.state.provinces[a.location]
	local owner = province.owner
	if owner ~= nil and not ctx.isEnemy[owner] then
		return false -- at home (or stranded in a land at peace with me)
	end
	local siege = province.siege
	if #hostileAt(ctx, a.location) > 0 then
		return true
	elseif siege and Diplomacy.friendly(ctx.state, ctx.me, siege.by) then
		return true -- my siege (or an ally's)
	end
	-- no siege of mine: wait for one only if no rival stands here (it may hold the siege, or win the next one)
	return (rivalsAt(ctx, a.location)) == 0
end

local function freeStacks(ctx: Ctx): { Stack }
	local byLocation: { [number]: Stack } = {}
	local out: { Stack } = {}
	for _, a in ctx.myArmies do
		if
			not a.inBattle
			and #a.path == 0
			and a.morale >= Config.Bots.MinAttackMorale -- a tired or broken army rests
			and not holdsGround(ctx, a)
			and ctx.reserved[a.id] == nil
		then
			local stack = byLocation[a.location]
			if stack == nil then
				stack = { location = a.location, armies = {}, men = 0 }
				byLocation[a.location] = stack
				table.insert(out, stack)
			end
			table.insert(stack.armies, a)
			stack.men += a.men
		end
	end
	table.sort(out, function(x, y)
		if x.men ~= y.men then
			return x.men > y.men
		end
		return x.location < y.location
	end)
	return out
end

-- Every army of the stack marches to the same province, so they arrive and fight together.
local function moveStack(stack: Stack, to: number): { Command }
	local out: { Command } = {}
	for _, a in stack.armies do
		local move: Command = { kind = "Move", army = a.id, to = to }
		table.insert(out, move)
	end
	return out
end

-- Regiments of a troop I can pay for in one command.
local function affordable(ctx: Ctx, troop: Types.Troop): number
	local nation = ctx.nation
	local t = Troops.stats(troop)
	local n = math.min(
		Config.Army.MaxRecruitPerCommand,
		math.floor(nation.gold / t.gold),
		math.floor(nation.manpower / t.manpower)
	)
	return math.max(0, n)
end

-- How many of up to `regiments` regiments of a troop I can buy and still keep Config.Bots.UpkeepReserveMonths of
-- upkeep (theirs included) in the bank.
local function richEnough(ctx: Ctx, troop: Types.Troop, regiments: number): number
	local t = Troops.stats(troop)
	local n = math.min(regiments, affordable(ctx, troop))
	local each = t.upkeep * Races.upkeepMultiplier(ctx.nation.race) -- an Upkeep race pays less
	while n >= 1 and ctx.nation.gold - n * t.gold < Config.Bots.UpkeepReserveMonths * (ctx.upkeep + n * each) do
		n -= 1
	end
	return n
end

-- Are this troop type's men (`men`) still under `share` of my army? The line troop stays the base of the mix.
local function underShare(ctx: Ctx, men: number, share: number): boolean
	return men <= share * ctx.men
end

-- The role shares of my enemies' armies in and next to my land (Troops.roleShares).
local function frontMix(ctx: Ctx): { [string]: number }
	local near: { [number]: boolean } = {}
	for _, id in ctx.mine do
		near[id] = true
		for _, n in ctx.state.provinces[id].neighbors do
			near[n] = true
		end
	end
	local men: Types.Composition = {}
	for location in near do
		for _, a in ctx.armiesAt[location] or NONE do
			if a.owner ~= 0 and ctx.isEnemy[a.owner] then
				for _, troop in Troops.LIST do
					men[troop] = (men[troop] or 0) + (a.troops[troop] or 0)
				end
			end
		end
	end
	return Troops.roleShares(men)
end

-- What to recruit (up to `regiments` regiments) for the next fight, from my race's roster. At war: my special while
-- it is under Config.Bots.SpecialShare of my men, else my elite and my fast troop while each is under its share
-- (Config.Bots.EliteShare, FastShare), the one furthest below its share first (a tie: the elite), else the troop that
-- beats my enemies' armies near my land (frontMix, Troops.bestCounter) while it is under Config.Bots.CounterShare,
-- the first of those I am rich enough for, but never a troop those armies beat (Troops.counterScore at or under
-- -CounterMinScore). Else my line troop, the base.
local function pickTroop(ctx: Ctx, regiments: number): (Types.Troop, number)
	local race = ctx.nation.race
	local line = Troops.ofRole(race, "line") or Troops.BASE
	if #ctx.enemies > 0 then
		local options: { Types.Troop } = {}
		local special = Troops.ofRole(race, "special")
		if special and underShare(ctx, ctx.troopMen[special] or 0, Config.Bots.SpecialShare) then
			table.insert(options, special)
		end
		-- the elite and the fast troop: how full each one's share is (0 = none yet, 1 = at its share)
		local fill: { [Types.Troop]: number } = {}
		local pair: { Types.Troop } = {}
		for _, entry in { { "elite", Config.Bots.EliteShare }, { "fast", Config.Bots.FastShare } } do
			local troop = Troops.ofRole(race, entry[1] :: Types.TroopRole)
			local share = entry[2] :: number
			local men = if troop then ctx.troopMen[troop] or 0 else 0
			if troop and underShare(ctx, men, share) then
				fill[troop] = men / math.max(share * ctx.men, 1)
				table.insert(pair, troop)
			end
		end
		if #pair == 2 and fill[pair[2]] < fill[pair[1]] then
			pair[1], pair[2] = pair[2], pair[1]
		end
		for _, troop in pair do
			table.insert(options, troop)
		end
		local mix = frontMix(ctx)
		local role = Troops.bestCounter(mix, Config.Bots.CounterMinScore)
		local counter = if role and role ~= "line" then Troops.ofRole(race, role) else nil
		if counter and underShare(ctx, ctx.troopMen[counter] or 0, Config.Bots.CounterShare) then
			table.insert(options, counter)
		end
		for _, troop in options do
			local beaten = Troops.counterScore(Troops.stats(troop).role, mix) <= -Config.Bots.CounterMinScore
			local n = if beaten then 0 else richEnough(ctx, troop, regiments)
			if n >= 1 then
				return troop, n
			end
		end
	end
	return line, math.min(regiments, affordable(ctx, line))
end

-- The commands, if the server would accept all of them in this order (dry run on one copy of the state).
local function tryAll(ctx: Ctx, commands: { Command }): { Command }?
	if #commands == 0 then
		return nil
	end
	local scratch = copy(ctx.state) :: MatchState
	for _, command in commands do
		if not Commands.apply(scratch, ctx.me, command) then
			return nil
		end
	end
	return commands
end

local function try(ctx: Ctx, command: Command): { Command }?
	return tryAll(ctx, { command })
end

local function playerWarAllowed(ctx: Ctx, target: number): boolean
	local nation = ctx.state.nations[target]
	return nation == nil or nation.controller ~= "Player" or ctx.state.tick >= ctx.settings.noPlayerWarTicks
end

-- Easy leaves players alone early: until noPlayerWarTicks it doesn't march into a player's land (or Meteor them)
-- even in a war it was dragged into or the player started; it only defends its own.
local function mayInvade(ctx: Ctx, provinceId: number): boolean
	local owner = ctx.state.provinces[provinceId].owner
	return owner == nil or playerWarAllowed(ctx, owner)
end

-- The living player (not me) holding the most provinces.
local function leadingPlayer(ctx: Ctx): number?
	local best: number?, bestCount = nil, -1
	for _, id in sortedKeys(ctx.state.nations) do
		local n = ctx.state.nations[id]
		local count = ctx.counts[id] or 0
		if id ~= ctx.me and n.controller == "Player" and not n.eliminated and count > bestCount then
			best, bestCount = id, count
		end
	end
	return best
end

-- 1. Defend ----------------------------------------------------------------------------------------------

-- Hostile armies inside or next to my land. Neutral armies only count inside it (garrisons never move).
local function threats(ctx: Ctx): { Threat }
	local state = ctx.state
	local out: { Threat } = {}
	for _, location in sortedKeys(ctx.armiesAt) do
		local inside = ctx.isMine[location] == true
		local armies = {}
		for _, a in ctx.armiesAt[location] do
			if (a.owner ~= 0 and ctx.isEnemy[a.owner]) or (inside and a.owner == 0) then
				table.insert(armies, a)
			end
		end
		if #armies > 0 then
			local target: number? = if inside then location else nil
			if target == nil then
				-- which of my provinces they threaten: where they are heading, else my capital, else my richest
				local nextStep = armies[1].path[1]
				local best: number? = nil
				for _, n in state.provinces[location].neighbors do
					if ctx.isMine[n] then
						local p = state.provinces[n]
						if n == nextStep or p.isCapital then
							best = n
							break
						end
						if best == nil or p.development > state.provinces[best].development then
							best = n
						end
					end
				end
				target = best
			end
			if target then
				table.insert(out, { location = location, target = target, armies = armies, inside = inside })
			end
		end
	end
	table.sort(out, function(a, b)
		if a.inside ~= b.inside then
			return a.inside
		end
		local ma, mb = menOf(a.armies), menOf(b.armies)
		if ma ~= mb then
			return ma > mb
		end
		return a.location < b.location
	end)
	return out
end

-- My armies already holding a province or marching to it.
local function guardsOf(ctx: Ctx, provinceId: number): { Army }
	local out = {}
	for _, a in ctx.myArmies do
		local dest = if #a.path > 0 then a.path[#a.path] else a.location
		if dest == provinceId then
			table.insert(out, a)
		end
	end
	return out
end

-- My nearest rested army (by steps) that could come and help in a province, with a clear route there.
local function nearestHelper(ctx: Ctx, provinceId: number, skip: { [number]: boolean }): Army?
	local candidates = { provinceId }
	local order = reachable(ctx, provinceId)
	for _, p in order do
		table.insert(candidates, p)
	end
	local checks = 0
	for _, p in candidates do
		local best: Army? = nil
		for _, a in ctx.armiesAt[p] or {} do
			local rested = p == provinceId or a.morale >= Config.Bots.MinAttackMorale -- a tired army doesn't march to help
			if a.owner == ctx.me and not a.inBattle and not skip[a.id] and ctx.reserved[a.id] == nil and rested then
				if best == nil or a.men > best.men then
					best = a
				end
			end
		end
		if best then
			if p == provinceId then
				return best -- it stands there but is about to leave: stopping it is enough
			end
			checks += 1
			if clearRoute(ctx, best, provinceId) then
				return best
			end
			if checks >= Config.Bots.MaxRouteChecks then
				return nil
			end
		end
	end
	return nil
end

local function defend(ctx: Ctx): { Command }?
	local ratio = Config.Bots.DefendRatio
	local list = threats(ctx)
	-- armies holding (or marching to) any threatened province stay there: pulling them from one threatened
	-- province to another would leave them walking back and forth
	local skip = {}
	for _, t in list do
		for _, g in guardsOf(ctx, t.target) do
			skip[g.id] = true
		end
	end
	for _, t in list do
		local guards = guardsOf(ctx, t.target)
		-- by strength with the counters, not morale: a tired guard recruiting until it wouldn't break drained the gold
		-- bots keep for elites (docs/BALANCE.md section 22)
		local my, their, _, _, myMod = strengths(ctx, t.target, guards, t.armies, true, 0, 0)
		if my >= ratio * their then
			for _, g in guards do
				ctx.reserved[g.id] = t.location
			end
		else
			local helper = nearestHelper(ctx, t.target, skip)
			if helper then
				local all = table.clone(guards)
				table.insert(all, helper)
				local together = strengths(ctx, t.target, all, t.armies, true, 0, 0)
				if together >= ratio * their then
					local result = try(ctx, { kind = "Move", army = helper.id, to = t.target })
					if result then
						return result
					end
				end
			end
			-- not enough men nearby: raise them where the threat is: my ranged troop (the best defenders) if I can pay
			-- and it is still under Config.Bots.RangedShare of my men, and my line troop, the one that defends better
			-- against this enemy's mix first (its counters)
			local race = ctx.nation.race
			local line = Troops.ofRole(race, "line") or Troops.BASE
			local ranged = Troops.ofRole(race, "ranged")
			local options: { Types.Troop } = if ranged
					and underShare(ctx, ctx.troopMen[ranged] or 0, Config.Bots.RangedShare)
				then { ranged, line }
				else { line }
			local shares = Troops.roleShares(Battle.composition(t.armies))
			local function holding(troop: Types.Troop): number
				local stats = Troops.stats(troop)
				return stats.defence * Troops.counter(stats.role, shares)
			end
			if #options == 2 and holding(options[2]) > holding(options[1]) then
				options[1], options[2] = options[2], options[1]
			end
			local missing = ratio * their - my
			for _, troop in options do
				local perRegiment = Config.Army.MenPerRegiment * holding(troop) * myMod
				local regiments = math.min(math.ceil(missing / perRegiment), affordable(ctx, troop))
				if regiments >= 1 then
					local result =
						try(ctx, { kind = "Recruit", province = t.target, regiments = regiments, troop = troop })
					if result then
						return result
					end
				end
			end
		end
	end
	return nil
end

-- 2. Recruit ---------------------------------------------------------------------------------------------

-- Where new regiments are most useful: facing an enemy, then facing anyone (neutral land or a neighbour),
-- topping up a small army before starting a new one; else the capital.
local function recruitSite(ctx: Ctx): number?
	local state = ctx.state
	local batchMen = Config.Bots.RecruitBatch * Config.Army.MenPerRegiment
	local best: number?, bestRank, bestDev = nil, math.huge, -1
	for _, id in ctx.mine do
		local p = state.provinces[id]
		local front, enemyFront = false, false
		for _, n in p.neighbors do
			local q = state.provinces[n]
			if q.terrain ~= "Mountain" and q.owner ~= ctx.me then
				if q.owner == nil or not Diplomacy.allied(state, ctx.me, q.owner) then
					front = true
				end
				if q.owner and ctx.isEnemy[q.owner] then
					enemyFront = true
				end
			end
		end
		local idle: Army? = nil
		for _, a in ctx.armiesAt[id] or {} do
			if a.owner == ctx.me and #a.path == 0 and not a.inBattle then
				idle = a
				break
			end
		end
		local rank
		if front and (idle == nil or idle.men < batchMen) then
			rank = (if enemyFront then 0 else 2) + (if idle then 0 else 1)
		elseif p.isCapital then
			rank = 4
		else
			rank = 5
		end
		if rank < bestRank or (rank == bestRank and p.development > bestDev) then
			best, bestRank, bestDev = id, rank, p.development
		end
	end
	return best
end

local function recruit(ctx: Ctx): { Command }?
	local wanted = #ctx.mine * Config.Bots.MenPerProvince
	if ctx.men >= wanted then
		return nil
	end
	local troop, regiments =
		pickTroop(ctx, math.min(Config.Bots.RecruitBatch, math.ceil((wanted - ctx.men) / Config.Army.MenPerRegiment)))
	local site = recruitSite(ctx)
	if regiments < 1 or site == nil then
		return nil
	end
	return try(ctx, { kind = "Recruit", province = site, regiments = regiments, troop = troop })
end

-- 3. Expand ----------------------------------------------------------------------------------------------

local function expand(ctx: Ctx): { Command }?
	local state = ctx.state
	for _, stack in freeStacks(ctx) do
		local target = pickTarget(ctx, stack.armies[1], function(p)
			return state.provinces[p].owner == nil
				and not ctx.targeted[p]
				and p ~= stack.location
				and (rivalsAt(ctx, p)) == 0
				and canBeat(ctx, p, stack.armies)
		end)
		if target then
			local result = tryAll(ctx, moveStack(stack, target))
			if result then
				return result
			end
		end
	end
	return nil
end

-- 4. Attack ----------------------------------------------------------------------------------------------

-- The men of a nation and its allies.
local function sideMen(ctx: Ctx, nationId: number): number
	local members = Diplomacy.allianceMembers(ctx.state, nationId)
	local n = 0
	for _, a in ctx.state.armies do
		if table.find(members, a.owner) then
			n += a.men
		end
	end
	return n
end

-- Armies of these nations in a province or next to it: who would meet an attack there.
local function localDefence(ctx: Ctx, provinceId: number, members: { number }): { Army }
	local out = {}
	local function add(p: number)
		for _, a in ctx.armiesAt[p] or {} do
			if table.find(members, a.owner) then
				table.insert(out, a)
			end
		end
	end
	add(provinceId)
	for _, n in ctx.state.provinces[provinceId].neighbors do
		add(n)
	end
	return out
end

-- Against a nation that insulted me, my attack ratio is multiplied by this: Config.Bots.GrudgeAttackRatio, but never
-- so far that I'd attack with less than Config.Bots.GrudgeMinRatio of the defenders' strength (an even fight).
function Bot.grudgeFactor(attackRatio: number): number
	return math.max(Config.Bots.GrudgeAttackRatio, Config.Bots.GrudgeMinRatio / attackRatio)
end

-- At peace with everyone: declare war on my weakest neighbour (Hard: the leading player first) if I am not
-- weaker overall and one of my free stacks beats, by the attack ratio, everything guarding one of its border
-- provinces. A neighbour that insulted me comes first, and my stack needs only Config.Bots.GrudgeAttackRatio of the
-- usual attack ratio against it (never under Config.Bots.GrudgeMinRatio, an even fight).
local function declareWar(ctx: Ctx): { Command }?
	local state = ctx.state
	if state.phase == "Peace" then
		return nil
	end
	local stacks = freeStacks(ctx)
	if #stacks == 0 then
		return nil
	end
	type Candidate = { id: number, men: number, tiebreak: number, front: { number } }
	local byId: { [number]: Candidate } = {}
	local candidates: { Candidate } = {}
	for _, id in ctx.mine do
		for _, n in state.provinces[id].neighbors do
			local owner = state.provinces[n].owner
			if owner and owner ~= ctx.me then
				local c = byId[owner]
				if c == nil then
					local nation = state.nations[owner]
					if
						nation
						and not nation.eliminated
						and not Diplomacy.allied(state, ctx.me, owner)
						and not Diplomacy.hasTruce(state, ctx.me, owner)
						and playerWarAllowed(ctx, owner)
					then
						c = { id = owner, men = sideMen(ctx, owner), tiebreak = 0, front = {} }
						byId[owner] = c
						table.insert(candidates, c)
					end
				end
				if c and table.find(c.front, n) == nil then
					table.insert(c.front, n)
				end
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.id < b.id
	end)
	for _, c in candidates do
		c.tiebreak = Rng.next(ctx.rng)
	end
	local leader = if ctx.settings.targetsLeadingPlayer then leadingPlayer(ctx) else nil
	table.sort(candidates, function(a, b)
		local ga, gb = ctx.grudge[a.id] == true, ctx.grudge[b.id] == true
		if ga ~= gb then
			return ga -- an insult is remembered
		end
		if (a.id == leader) ~= (b.id == leader) then
			return a.id == leader
		end
		if a.men ~= b.men then
			return a.men < b.men
		end
		return a.tiebreak < b.tiebreak
	end)
	local mySide = sideMen(ctx, ctx.me)
	local distances: { { [number]: number } } = {}
	for i, stack in stacks do
		local _, dist = reachable(ctx, stack.location)
		distances[i] = dist
	end
	for _, c in candidates do
		local factor = if ctx.grudge[c.id] then Bot.grudgeFactor(ctx.settings.attackRatio) else 1
		if mySide >= c.men then
			local members = Diplomacy.allianceMembers(state, c.id)
			for i, stack in stacks do
				local dist = distances[i]
				for _, p in c.front do
					local near = false
					for _, n in state.provinces[p].neighbors do
						near = near or n == stack.location or (dist[n] ~= nil and ctx.isMine[n] == true)
					end
					if near and aboveRatio(ctx, p, stack.armies, localDefence(ctx, p, members), factor) then
						return try(ctx, { kind = "Diplomacy", action = "War", target = c.id, gold = 0 })
					end
				end
			end
		end
	end
	return nil
end

-- Two stacks that can take an enemy province together but not alone strike it from two sides (docs/DESIGN.md
-- "Bot AI"): they march in on the same tick from two neighbours of it, so they arrive together from two directions
-- and flank (strikeTogether); free stacks first take up places there (takePlaces).

-- Enemy land with enemy armies in it that my armies may march into now.
local function pincerTarget(ctx: Ctx, p: number): boolean
	local owner = ctx.state.provinces[p].owner
	return owner ~= nil
		and ctx.isEnemy[owner] == true
		and #hostileAt(ctx, p) > 0
		and mayInvade(ctx, p)
		and not ctx.targeted[p]
		and (rivalsAt(ctx, p)) == 0
end

-- Neither stack takes the province alone, both together do (standing in two places, they count as two directions).
local function together(ctx: Ctx, p: number, a: Stack, b: Stack): boolean
	local theirs = hostileAt(ctx, p)
	if aboveRatio(ctx, p, a.armies, theirs) or aboveRatio(ctx, p, b.armies, theirs) then
		return false
	end
	local both = table.clone(a.armies)
	for _, army in b.armies do
		table.insert(both, army)
	end
	return aboveRatio(ctx, p, both, theirs)
end

-- Two of these stacks standing next to the same province strike it together.
local function strikeTogether(ctx: Ctx, stacks: { Stack }): { Command }?
	local checks = 0
	for i, a in stacks do
		for _, p in ctx.state.provinces[a.location].neighbors do
			if pincerTarget(ctx, p) then
				for k = i + 1, #stacks do
					local b = stacks[k]
					if b.location ~= a.location and table.find(ctx.state.provinces[p].neighbors, b.location) then
						checks += 1
						if together(ctx, p, a, b) then
							local commands = moveStack(a, p)
							for _, command in moveStack(b, p) do
								table.insert(commands, command)
							end
							return tryAll(ctx, commands)
						elseif checks >= Config.Bots.MaxRouteChecks then
							return nil
						end
					end
				end
			end
		end
	end
	return nil
end

-- My two biggest free stacks walk to two different neighbours of the nearest province they can take together (clear
-- of enemies, the nearest such place for each); the next plans strike once both stand there.
local function takePlaces(ctx: Ctx): { Command }?
	local stacks = freeStacks(ctx)
	if #stacks < 2 then
		return nil
	end
	local a, b = stacks[1], stacks[2]
	local order, distA = reachable(ctx, a.location)
	local _, distB = reachable(ctx, b.location)
	-- the nearest neighbour of p a stack can reach and stand in, other than `taken`
	local function place(p: number, dist: { [number]: number }, taken: number?): number?
		local best: number?, bestD = nil, math.huge
		for _, n in ctx.state.provinces[p].neighbors do
			local d = dist[n]
			if d and d < bestD and n ~= taken and #hostileAt(ctx, n) == 0 then
				best, bestD = n, d
			end
		end
		return best
	end
	local checks = 0
	for _, p in order do
		if distB[p] and pincerTarget(ctx, p) then
			checks += 1
			local atA = place(p, distA, nil)
			local atB = place(p, distB, atA)
			if atA == nil or atB == nil then
				atB = place(p, distB, nil)
				atA = if atB then place(p, distA, atB) else nil
			end
			if atA and atB and together(ctx, p, a, b) then
				local commands: { Command } = {}
				for _, step in { { stack = a, to = atA }, { stack = b, to = atB } } do
					if step.stack.location ~= step.to then
						if clearRoute(ctx, step.stack.armies[1], step.to) == nil then
							return nil
						end
						for _, command in moveStack(step.stack, step.to) do
							table.insert(commands, command)
						end
					end
				end
				return tryAll(ctx, commands)
			elseif checks >= Config.Bots.MaxRouteChecks then
				return nil
			end
		end
	end
	return nil
end

local function attack(ctx: Ctx): { Command }?
	if #ctx.enemies == 0 then
		return declareWar(ctx)
	end
	local state = ctx.state
	-- guards strike the army they are watching when they are clearly stronger
	local guardStacks: { [string]: Stack } = {}
	local keys = {}
	for _, a in ctx.myArmies do
		local watching = ctx.reserved[a.id]
		if watching and watching ~= a.location and not a.inBattle and #a.path == 0 then
			local key = a.location .. ">" .. watching
			if guardStacks[key] == nil then
				guardStacks[key] = { location = a.location, armies = {}, men = 0 }
				table.insert(keys, key)
			end
			table.insert(guardStacks[key].armies, a)
			guardStacks[key].men += a.men
		end
	end
	for _, key in keys do
		local stack = guardStacks[key]
		local watching = ctx.reserved[stack.armies[1].id] :: number
		if
			mayInvade(ctx, watching)
			and aboveRatio(ctx, watching, stack.armies, hostileAt(ctx, watching))
			and clearRoute(ctx, stack.armies[1], watching)
		then
			local result = tryAll(ctx, moveStack(stack, watching))
			if result then
				return result
			end
		end
	end
	-- two stacks (guards or free) standing on two sides of a province they can take together strike it now
	local ready: { Stack } = {}
	for _, key in keys do
		local stack = guardStacks[key]
		if Battle.morale(stack.armies) >= Config.Bots.MinAttackMorale then
			table.insert(ready, stack)
		end
	end
	for _, stack in freeStacks(ctx) do
		table.insert(ready, stack)
	end
	local struck = strikeTogether(ctx, ready)
	if struck then
		return struck
	end
	-- free stacks march on the nearest enemy province they can take (Hard: the leading player's first)
	local focus = if ctx.settings.targetsLeadingPlayer then leadingPlayer(ctx) else nil
	if focus and not ctx.isEnemy[focus] then
		focus = nil
	end
	for _, stack in freeStacks(ctx) do
		local function enemyLand(p: number, onlyFocus: boolean): boolean
			local owner = state.provinces[p].owner
			return owner ~= nil
				and ctx.isEnemy[owner] == true
				and (not onlyFocus or owner == focus)
				and mayInvade(ctx, p)
				and not ctx.targeted[p]
				and (rivalsAt(ctx, p)) == 0
				and aboveRatio(ctx, p, stack.armies, hostileAt(ctx, p))
		end
		local target: number? = nil
		if focus then
			target = pickTarget(ctx, stack.armies[1], function(p)
				return enemyLand(p, true)
			end)
		end
		if target == nil then
			target = pickTarget(ctx, stack.armies[1], function(p)
				return enemyLand(p, false)
			end)
		end
		if target then
			local result = tryAll(ctx, moveStack(stack, target))
			if result then
				return result
			end
		end
	end
	-- no stack can take a province alone: two of them take up places on two sides of one they can take together
	local placed = takePlaces(ctx)
	if placed then
		return placed
	end
	-- my enemies are out of reach (far away, or left with no land): find a new war nearby
	for _, id in ctx.mine do
		for _, n in state.provinces[id].neighbors do
			local owner = state.provinces[n].owner
			if owner and ctx.isEnemy[owner] then
				return nil
			end
		end
	end
	return declareWar(ctx)
end

-- No stack can expand or attack alone: bring the smallest free stack to the biggest, so they strike together.
local function gather(ctx: Ctx): { Command }?
	local stacks = freeStacks(ctx)
	if #stacks < 2 then
		return nil
	end
	local big, small = stacks[1], stacks[#stacks]
	if clearRoute(ctx, small.armies[1], big.location) then
		return tryAll(ctx, moveStack(small, big.location))
	end
	return nil
end

-- 5. Build -----------------------------------------------------------------------------------------------

local function build(ctx: Ctx): { Command }?
	local state = ctx.state
	local spare = ctx.nation.gold - Config.Bots.UpkeepReserveMonths * ctx.upkeep
	if spare <= 0 then
		return nil
	end
	local hasBarracks = false
	local inland, border = {}, {}
	for _, id in ctx.mine do
		local p = state.provinces[id]
		if p.building == "Barracks" then
			hasBarracks = true
		end
		if p.building == "None" then
			local facesNation = false
			for _, n in p.neighbors do
				local owner = state.provinces[n].owner
				if owner and owner ~= ctx.me then
					facesNation = true
				end
			end
			table.insert(if facesNation then border else inland, id)
		end
	end
	-- the capital first, then the most developed (lowest id on ties)
	local function richest(list: { number }): number?
		local best: number? = nil
		for _, id in list do
			local p = state.provinces[id]
			if best == nil then
				best = id
			else
				local b = state.provinces[best]
				if
					(p.isCapital and not b.isCapital) or (p.isCapital == b.isCapital and p.development > b.development)
				then
					best = id
				end
			end
		end
		return best
	end
	-- barracks first (one), then farms inland, then forts on borders with other nations, then develop
	local command: Command? = nil
	local cost = 0
	local spot = richest(inland) or richest(border)
	if not hasBarracks and spot then
		command = { kind = "Build", province = spot, building = "Barracks" }
		cost = Config.Buildings.Barracks.cost
	elseif richest(inland) then
		command = { kind = "Build", province = richest(inland) :: number, building = "Farm" }
		cost = Config.Buildings.Farm.cost
	elseif richest(border) then
		command = { kind = "Build", province = richest(border) :: number, building = "Fort" }
		cost = Economy.buildingCost("Fort", ctx.nation.race) :: number
	else
		local poorest: number? = nil
		for _, id in ctx.mine do
			local p = state.provinces[id]
			if p.development < Config.Economy.MaxDevelopment then
				if poorest == nil or p.development < state.provinces[poorest].development then
					poorest = id
				end
			end
		end
		if poorest then
			command = { kind = "Develop", province = poorest }
			cost = Economy.developCost(state.provinces[poorest].development)
		end
	end
	if command == nil then
		-- everything is built and fully developed: turn the spare gold into regiments
		local troop, regiments = pickTroop(ctx, Config.Army.MaxRecruitPerCommand)
		regiments = math.min(regiments, math.floor(spare / Troops.stats(troop).gold))
		local site = recruitSite(ctx)
		if regiments >= 1 and site then
			return try(ctx, { kind = "Recruit", province = site, regiments = regiments, troop = troop })
		end
		return nil
	end
	if cost > spare then
		return nil -- save up for it
	end
	return try(ctx, command)
end

-- 6. Diplomacy -------------------------------------------------------------------------------------------

local function hasOffer(ctx: Ctx, kind: string, from: number, to: number): boolean
	for _, o in ctx.state.offers do
		if o.kind == kind and o.from == from and o.to == to and o.expiresAt > ctx.state.tick then
			return true
		end
	end
	return false
end

local function sharesEnemy(ctx: Ctx, other: number): boolean
	for _, e in ctx.enemies do
		if Diplomacy.atWar(ctx.state, other, e) then
			return true
		end
	end
	return false
end

-- Remember my province count when each war started; forget wars that ended.
local function rememberWars(ctx: Ctx, memory: Memory)
	local state = ctx.state
	for id, snap in memory.warStart do
		local war = state.wars[id]
		if war == nil or war.startedAt ~= snap.startedAt then
			memory.warStart[id] = nil
		end
	end
	for _, id in sortedKeys(state.wars) do
		local war = state.wars[id]
		local inIt = table.find(war.attackers, ctx.me) ~= nil or table.find(war.defenders, ctx.me) ~= nil
		if inIt and memory.warStart[id] == nil then
			memory.warStart[id] = { startedAt = war.startedAt, provinces = #ctx.mine }
		end
	end
end

-- Enemies in wars where I have lost at least PeaceLossShare of my provinces, biggest first.
local function losingTo(ctx: Ctx, memory: Memory): { number }
	local state = ctx.state
	local out = {}
	for _, id in sortedKeys(memory.warStart) do
		local snap = memory.warStart[id]
		local war = state.wars[id]
		if snap.provinces > 0 and 1 - #ctx.mine / snap.provinces >= Config.Bots.PeaceLossShare then
			local otherSide = if table.find(war.attackers, ctx.me) then war.defenders else war.attackers
			for _, n in otherSide do
				if Diplomacy.atWar(state, ctx.me, n) and table.find(out, n) == nil then
					table.insert(out, n)
				end
			end
		end
	end
	table.sort(out, function(a, b)
		local ca, cb = ctx.counts[a] or 0, ctx.counts[b] or 0
		if ca ~= cb then
			return ca > cb
		end
		return a < b
	end)
	return out
end

local function diplomacy(ctx: Ctx, memory: Memory): { Command }?
	local state = ctx.state
	local me = ctx.me
	-- may I make this offer? Not while one is open, and not again before the cooldown
	local function mayOffer(kind: string, to: number): boolean
		local last = memory.offeredAt[kind .. ":" .. to]
		return not hasOffer(ctx, kind, me, to) and (last == nil or state.tick - last >= Config.Bots.OfferCooldownTicks)
	end
	local function offer(kind: "Ally" | "Peace", to: number): { Command }?
		local result = try(ctx, { kind = "Diplomacy", action = kind, target = to, gold = 0 })
		if result then
			memory.offeredAt[kind .. ":" .. to] = state.tick
		end
		return result
	end
	-- peace once a war has cost me too much: take an offer, or make one
	local losing = losingTo(ctx, memory)
	for _, enemy in losing do
		if hasOffer(ctx, "Peace", enemy, me) then
			local result = try(ctx, { kind = "Diplomacy", action = "AcceptPeace", target = enemy, gold = 0 })
			if result then
				return result
			end
		end
	end
	if #losing > 0 and mayOffer("Peace", losing[1]) then
		local result = offer("Peace", losing[1])
		if result then
			return result
		end
	end
	-- allies against a shared enemy: accept an offer, or make one
	for _, o in state.offers do
		if o.kind == "Ally" and o.to == me and o.expiresAt > state.tick and sharesEnemy(ctx, o.from) then
			local result = try(ctx, { kind = "Diplomacy", action = "AcceptAlly", target = o.from, gold = 0 })
			if result then
				return result
			end
		end
	end
	local myAlliance = Diplomacy.allianceMembers(state, me)
	if #ctx.enemies > 0 and #myAlliance < Config.Diplomacy.MaxAllianceSize then
		local best: number?, bestCount = nil, -1
		for _, id in sortedKeys(state.nations) do
			local n = state.nations[id]
			local theirAlliance = Diplomacy.allianceMembers(state, id)
			-- an alliance can take in one more nation, two loners can form one; two alliances never merge
			local room = (#myAlliance == 1 or #theirAlliance == 1)
				and #myAlliance + #theirAlliance <= Config.Diplomacy.MaxAllianceSize
			if
				id ~= me
				and not n.eliminated
				and room
				and not Diplomacy.allied(state, me, id)
				and not ctx.isEnemy[id]
				and sharesEnemy(ctx, id)
				and mayOffer("Ally", id)
				and (ctx.counts[id] or 0) > bestCount
			then
				best, bestCount = id, ctx.counts[id] or 0
			end
		end
		if best then
			local result = offer("Ally", best)
			if result then
				return result
			end
		end
	end
	-- join the coalition: declare on a crowned leader that is already at war with someone
	if state.phase ~= "Peace" then
		local leader: number?, leaderCount = nil, -1
		for _, id in sortedKeys(ctx.counts) do
			if ctx.counts[id] > leaderCount then
				leader, leaderCount = id, ctx.counts[id]
			end
		end
		if
			leader
			and leader ~= me
			and state.nations[leader]
			and leaderCount >= Config.Diplomacy.CoalitionThreshold * ctx.totalProvinces
			and not ctx.isEnemy[leader]
			and not Diplomacy.allied(state, me, leader)
			and playerWarAllowed(ctx, leader)
		then
			local leaderAtWar = false
			for _, id in sortedKeys(state.nations) do
				leaderAtWar = leaderAtWar or Diplomacy.atWar(state, leader, id)
			end
			if leaderAtWar then
				local result = try(ctx, { kind = "Diplomacy", action = "War", target = leader, gold = 0 })
				if result then
					return result
				end
			end
		end
	end
	return nil
end

-- 7. Primordial power ------------------------------------------------------------------------------------
-- A Meteor on the biggest army of a nation I'm at war with that isn't immune to powers right now (the same
-- command a player sends). A charge never waits for a quiet moment: this step rides along with the plan's
-- other command.

local function primordial(ctx: Ctx): { Command }?
	local state = ctx.state
	if #ctx.enemies == 0 or ctx.nation.charges < Config.Primordial.Powers.Meteor.charges then
		return nil
	end
	local best: Army?, bestMen = nil, 0
	for _, id in sortedKeys(state.armies) do
		local a = state.armies[id]
		local owner = state.nations[a.owner]
		if
			ctx.isEnemy[a.owner]
			and owner
			and owner.powerImmuneUntil <= state.tick
			and Primordial.cooldownLeft(state, { nation = ctx.me }, a.owner) == 0
			and playerWarAllowed(ctx, a.owner)
			and a.men > bestMen
		then
			best, bestMen = a, a.men
		end
	end
	if best == nil then
		return nil
	end
	return try(ctx, { kind = "Power", power = "Meteor", target = best.id })
end

-- 8. Insults and military access (the EU4 pack) -----------------------------------------------------------------
-- They ride along with the plan's other commands too. A bot lets a nation through its land when it asks, unless they
-- are at war or the bot holds a grudge against it; insults back (Config.Bots.InsultBackChance, decided once per
-- insult; otherwise it keeps its grudge, and never laughs one off); and now and then (Config.Bots.InsultChance per
-- plan) insults a rival: a nation it is at war with, else a neighbour that isn't its ally.

local function social(ctx: Ctx, memory: Memory): { Command }
	local state = ctx.state
	local out: { Command } = {}
	if state.setup.settings.diplomacy ~= true then
		return out
	end
	local me = ctx.me
	for _, o in state.offers do
		if o.kind == "Access" and o.to == me and o.expiresAt > state.tick and not ctx.isEnemy[o.from] then
			if not ctx.grudge[o.from] then
				local accept = try(ctx, { kind = "Diplomacy", action = "AcceptAccess", target = o.from, gold = 0 })
				if accept then
					table.insert(out, accept[1])
					break
				end
			end
		end
	end
	for _, w in state.answers do
		local key = w.to .. ":" .. w.untilTick
		if w.from == me and w.untilTick > state.tick and not memory.answered[key] then
			memory.answered[key] = true
			if Rng.next(ctx.rng) < Config.Bots.InsultBackChance then
				local answer = try(ctx, { kind = "Diplomacy", action = "InsultBack", target = w.to, gold = 0 })
				if answer then
					table.insert(out, answer[1])
				end
			end
		end
	end
	if Rng.next(ctx.rng) < Config.Bots.InsultChance then
		local rivals: { number } = {}
		if #ctx.enemies > 0 then
			rivals = table.clone(ctx.enemies)
		else
			for _, id in ctx.mine do
				for _, n in state.provinces[id].neighbors do
					local owner = state.provinces[n].owner
					if owner and owner ~= me and table.find(rivals, owner) == nil then
						table.insert(rivals, owner)
					end
				end
			end
			table.sort(rivals)
		end
		local options: { number } = {}
		for _, id in rivals do
			if not Diplomacy.allied(state, me, id) and Diplomacy.cooldownLeft(state, "Insult", me, id) == 0 then
				table.insert(options, id)
			end
		end
		if #options > 0 then
			local target = options[Rng.int(ctx.rng, 1, #options)]
			local insult = try(ctx, { kind = "Diplomacy", action = "Insult", target = target, gold = 0 })
			if insult then
				table.insert(out, insult[1])
			end
		end
	end
	return out
end

-- 9. Event cards (the EU4 pack, stage 2): a bot answers its open card once, on its first plan after the card came,
-- with the affordable choice worth the most gold (Sim.EventCards.worth), through the same command players use. It
-- decides after the plan's other orders (on a copy of the world where they went through), so a choice that costs gold
-- never fails because a recruit in the same plan spent it.

local function eventChoice(ctx: Ctx, memory: Memory, planned: { Command }): Command?
	local card = EventCards.open(ctx.state, ctx.me)
	if card == nil then
		return nil
	end
	local key = "card:" .. card.id
	if memory.answered[key] then
		return nil
	end
	memory.answered[key] = true
	local scratch = copy(ctx.state) :: MatchState
	for _, command in planned do
		Commands.apply(scratch, ctx.me, command)
	end
	local cardId, choice = EventCards.botChoice(scratch, ctx.me)
	if cardId == nil or choice == nil then
		return nil
	end
	local answer: Command = { kind = "EventChoice", card = cardId, choice = choice }
	return if Commands.apply(scratch, ctx.me, answer) then answer else nil
end

-- Plan ---------------------------------------------------------------------------------------------------

-- The commands this bot wants this turn (usually one, sometimes none).
function Bot.plan(
	state: MatchState,
	nationId: number,
	rng: Rng.Rng,
	difficulty: Difficulty,
	memory: Memory?
): { Command }
	local nation = state.nations[nationId]
	if nation == nil or nation.eliminated or state.result ~= nil or not ACTIVE_PHASES[state.phase] then
		return {}
	end
	local ctx = context(state, nationId, rng, Bot.settings(difficulty))
	local mem = memory or Bot.newMemory()
	rememberWars(ctx, mem)
	local commands = defend(ctx)
		or recruit(ctx)
		or expand(ctx)
		or attack(ctx)
		or gather(ctx)
		or build(ctx)
		or diplomacy(ctx, mem)
		or {}
	local extra = social(ctx, mem)
	local power = primordial(ctx)
	if power then
		table.insert(extra, power[1])
	end
	local planned = table.clone(commands)
	for _, command in extra do
		table.insert(planned, command)
	end
	local event = eventChoice(ctx, mem, planned)
	if event then
		table.insert(extra, event)
	end
	if #extra > 0 then
		commands = table.clone(commands)
		for _, command in extra do
			table.insert(commands, command)
		end
	end
	return commands
end

-- Schedule -----------------------------------------------------------------------------------------------

-- Tick order step 7: the bots due this tick plan, at most Config.Bots.BotsPlanningPerTick of them, longest
-- waiting first; each then waits its difficulty's planTicks. A nation that just became a bot (a player left)
-- jumps the queue. Returns the orders to submit through CommandRouter, in order.
-- `levels` (optional) gives some nations another difficulty than `difficulty` (mixed bot tournaments).
function Bot.step(
	schedule: Schedule,
	state: MatchState,
	rng: Rng.Rng,
	difficulty: Difficulty,
	levels: { [number]: Difficulty }?
): { Order }
	local orders: { Order } = {}
	if state.result ~= nil or not ACTIVE_PHASES[state.phase] then
		return orders
	end
	local due = {}
	-- new to the schedule (match start, or a player just left): due at once, in a random order. The order sticks
	-- for the whole match (which bots plan right after each payday, who reaches contested land first), so a fixed
	-- order by nation id would favour the same start slots in every match.
	local fresh = {}
	for _, id in sortedKeys(state.nations) do
		local nation = state.nations[id]
		if nation.controller == "Bot" and not nation.eliminated and schedule.nextDue[id] == nil then
			table.insert(fresh, id)
		end
	end
	for i = #fresh, 2, -1 do
		local j = Rng.int(rng, 1, i)
		fresh[i], fresh[j] = fresh[j], fresh[i]
	end
	for i, id in fresh do
		schedule.nextDue[id] = -2 + i / (#fresh + 1) -- below every real tick, in shuffled order
	end
	for _, id in sortedKeys(state.nations) do
		local nation = state.nations[id]
		if nation.controller == "Bot" and not nation.eliminated then
			if schedule.nextDue[id] <= state.tick then
				table.insert(due, id)
			end
		else
			schedule.nextDue[id] = nil
		end
	end
	table.sort(due, function(a, b)
		local da, db = schedule.nextDue[a], schedule.nextDue[b]
		if da ~= db then
			return da < db
		end
		return a < b
	end)
	local meteored: { [number]: boolean } = {} -- nations a bot's power hits this tick
	for i = 1, math.min(#due, Config.Bots.BotsPlanningPerTick) do
		local id = due[i]
		local level = if levels and levels[id] then levels[id] else difficulty
		schedule.nextDue[id] = state.tick + Bot.settings(level).planTicks
		local memory = schedule.memory[id] or Bot.newMemory()
		schedule.memory[id] = memory
		for _, command in Bot.plan(state, id, rng, level, memory) do
			-- two bots planning on the same tick could Meteor the same nation; the second would hit its immunity
			local hit = if command.kind == "Power" and state.armies[command.target]
				then state.armies[command.target].owner
				else nil
			if hit == nil or not meteored[hit] then
				table.insert(orders, { nation = id, command = command })
				if hit then
					meteored[hit] = true
				end
			end
		end
	end
	return orders
end

return Bot
