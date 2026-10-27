--!strict
-- A greedy expansion planner for balance measurements: NOT the bot AI. It sends ordinary commands through
-- Sim/Commands (the same rules players and bots obey) and is meant to be close to the best a nation can do
-- against opponents that stand still.
--
-- Each tick, for one nation:
--   1. Every idle army that is not besieging picks the target with the best development per tick of travel
--      and siege among provinces it can beat (neutral land, plus enemy land once war is allowed), skipping
--      targets another of its armies already has and provinces a rival at peace stands in or marches to (two
--      rival besiegers block each other for good). Too weak for any target: it recruits up to the size the
--      nearest target needs, where it stands.
--   2. Spare manpower raises a new army next to the best untaken target.
--   3. After Peace it declares war on every neighbour it may (only when `war` is on).
--   4. Gold above what the manpower can be turned into goes into the improvement with the best yield per gold
--      (develop, farm or barracks; 100 manpower is valued like 1 gold, the regiment price ratio).

local Battle = require("../../src/shared/Sim/Battle")
local Commands = require("../../src/shared/Sim/Commands")
local Config = require("../../src/shared/Config")
local Diplomacy = require("../../src/shared/Sim/Diplomacy")
local Economy = require("../../src/shared/Sim/Economy")
local Pathing = require("../../src/shared/Sim/Pathing")
local Siege = require("../../src/shared/Sim/Siege")
local Types = require("../../src/shared/Types")

type MatchState = Types.MatchState

local Planner = {}

local MARGIN = 1.2 -- attack with this much more than the break-even strength
local ROUNDS_FACTOR = Config.Battle.Rounds * Config.Battle.KillRatePerRound -- 0.45: first-order battle model

export type Options = { war: boolean }

-- Ticks from `from` to every province this nation can enter (Dijkstra over movement times).
local function travelTimes(state: MatchState, nationId: number, from: number): { [number]: number }
	local dist: { [number]: number } = { [from] = 0 }
	local open = { from }
	while #open > 0 do
		local bestI, best = 1, math.huge
		for i, id in open do
			if dist[id] < best then
				bestI, best = i, dist[id]
			end
		end
		local cur = table.remove(open, bestI) :: number
		for _, n in state.provinces[cur].neighbors do
			if Diplomacy.canEnter(state, nationId, n) then
				local d = dist[cur] + Pathing.moveTicks(state.provinces[n].terrain)
				if dist[n] == nil or d < dist[n] then
					if dist[n] == nil then
						table.insert(open, n)
					end
					dist[n] = d
				end
			end
		end
	end
	return dist
end

local function hostileMen(state: MatchState, nationId: number, provinceId: number): (number, number)
	local men, owner = 0, 0
	for _, a in state.armies do
		if a.location == provinceId and Diplomacy.hostile(state, nationId, a.owner) then
			men += a.men
			owner = a.owner
		end
	end
	return men, owner
end

-- Men this nation needs to take the province: enough to beat whoever stands there, and at least a regiment.
function Planner.need(state: MatchState, nationId: number, provinceId: number): number
	local men, owner = hostileMen(state, nationId, provinceId)
	if men == 0 then
		return Config.Army.MenPerRegiment
	end
	local p = state.provinces[provinceId]
	local md = 1
	if p.terrain == "Forest" or p.terrain == "Hills" then
		md += Config.Battle.TerrainDefenceBonus
	end
	if p.building == "Fort" and p.owner ~= nil then
		md += Config.Buildings.Fort.defenceBonus
	end
	md += Battle.bonus(state, { owner }, { nationId }, true)
	local ma = 1 + Battle.bonus(state, { nationId }, { owner }, false)
	local breakEven = (1 + ROUNDS_FACTOR * md) / (1 + ROUNDS_FACTOR * ma)
	return math.max(men * breakEven * MARGIN, men + 2 * Config.Army.MinArmyMen)
end

local function isTarget(state: MatchState, nationId: number, opts: Options, provinceId: number): boolean
	local p = state.provinces[provinceId]
	if p.terrain == "Mountain" then
		return false
	end
	if p.owner == nil then
		return true
	end
	return opts.war and Diplomacy.atWar(state, nationId, p.owner)
end

local function regimentsFor(men: number): number
	return math.ceil(men / Config.Army.MenPerRegiment)
end

local function recruit(state: MatchState, nationId: number, provinceId: number, regiments: number): boolean
	local nation = state.nations[nationId]
	local affordable = math.min(
		regiments,
		math.floor(nation.gold / Config.Army.RegimentGold),
		math.floor(nation.manpower / Config.Army.RegimentManpower),
		Config.Army.MaxRecruitPerCommand
	)
	if affordable < 1 then
		return false
	end
	return (Commands.apply(state, nationId, { kind = "Recruit", province = provinceId, regiments = affordable }))
end

local function bestImprovement(state: MatchState, nationId: number): (Types.Command?, number)
	local best: Types.Command? = nil
	local bestValue, bestCost = 0, 0
	for id, p in state.provinces do
		if p.owner == nationId then
			local g, m = Economy.provinceYield(p)
			if p.development < Config.Economy.MaxDevelopment then
				local cost = Economy.developCost(p.development)
				local gain = g / p.development + m / p.development / 100
				if gain / cost > bestValue then
					best, bestValue, bestCost = { kind = "Develop", province = id } :: Types.Command, gain / cost, cost
				end
			end
			if p.building == "None" then
				local farm = p.development * Config.Buildings.Farm.goldBonus / Config.Buildings.Farm.cost
				if farm > bestValue then
					best, bestValue, bestCost =
						{ kind = "Build", province = id, building = "Farm" } :: Types.Command,
						farm,
						Config.Buildings.Farm.cost
				end
				local barracks = p.development
					* Config.Buildings.Barracks.manpowerBonus
					/ Config.Buildings.Barracks.cost
				if barracks > bestValue then
					best, bestValue, bestCost =
						{ kind = "Build", province = id, building = "Barracks" } :: Types.Command,
						barracks,
						Config.Buildings.Barracks.cost
				end
			end
		end
	end
	return best, bestCost
end

function Planner.step(state: MatchState, nationId: number, opts: Options)
	local nation = state.nations[nationId]
	if nation == nil or nation.eliminated then
		return
	end
	if opts.war and state.phase ~= "Peace" then
		for other in state.nations do
			if other ~= nationId and not Diplomacy.atWar(state, nationId, other) then
				Diplomacy.declareWar(state, nationId, other)
			end
		end
	end

	-- targets already taken by one of our armies (on the way or besieging)
	local taken: { [number]: boolean } = {}
	local idle = {}
	local ids = {}
	for id in state.armies do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		local a = state.armies[id]
		if a.owner ~= nationId and a.owner ~= 0 and not Diplomacy.hostile(state, nationId, a.owner) then
			-- a rival at peace standing in (or marching to) a province would block our siege there
			taken[a.location] = true
			if #a.path > 0 then
				taken[a.path[#a.path]] = true
			end
		elseif a.owner == nationId then
			if #a.path > 0 then
				taken[a.path[#a.path]] = true
			elseif
				a.inBattle or (state.provinces[a.location].siege and state.provinces[a.location].siege.by == nationId)
			then
				taken[a.location] = true -- fighting or besieging here
			else
				table.insert(idle, a)
			end
		end
	end

	for _, a in idle do
		local dist = travelTimes(state, nationId, a.location)
		local best, bestScore, nearest, nearestD = nil, 0, nil, math.huge
		for pid, d in dist do
			if not taken[pid] and isTarget(state, nationId, opts, pid) then
				local p = state.provinces[pid]
				local need = Planner.need(state, nationId, pid)
				local score = p.development / (d + Config.Battle.Rounds + Siege.required(p))
				if a.men >= need and score > bestScore then
					best, bestScore = pid, score
				end
				if d < nearestD then
					nearest, nearestD = pid, d
				end
			end
		end
		if best then
			taken[best] = true
			Commands.apply(state, nationId, { kind = "Move", army = a.id, to = best })
		elseif nearest then
			local short = Planner.need(state, nationId, nearest) - a.men
			recruit(state, nationId, a.location, regimentsFor(short))
		end
	end

	-- spare manpower: a new army beside the best untaken target
	if nation.manpower >= 2 * Config.Army.RegimentManpower and nation.gold >= 2 * Config.Army.RegimentGold then
		local bestTarget, bestFrom, bestScore = nil, nil, 0
		for pid, p in state.provinces do
			if not taken[pid] and isTarget(state, nationId, opts, pid) then
				for _, n in p.neighbors do
					if state.provinces[n].owner == nationId then
						local score = p.development / (Pathing.moveTicks(p.terrain) + Siege.required(p))
						if score > bestScore then
							bestTarget, bestFrom, bestScore = pid, n, score
						end
					end
				end
			end
		end
		if bestTarget and bestFrom then
			recruit(state, nationId, bestFrom, regimentsFor(Planner.need(state, nationId, bestTarget)))
		end
	end

	-- improvements with the gold the manpower can't use
	local reserve = Config.Army.RegimentGold * math.floor(nation.manpower / Config.Army.RegimentManpower)
	local command, cost = bestImprovement(state, nationId)
	if command and nation.gold - cost >= reserve then
		Commands.apply(state, nationId, command)
	end
end

return Planner
