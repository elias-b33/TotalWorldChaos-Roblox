--!strict
-- Catch-up rules (docs/DESIGN.md "Catch-up"): they slow the biggest nation down and help the smallest.
--
-- Overextension: above Config.CatchUp.OverextensionStart provinces, every full OverextensionStep extra provinces
--   cut gold income (provinces + capital, before upkeep) by OverextensionPenalty. 21-24 provinces: -0%,
--   25-29: -5%, 30-34: -10%, ... never below zero income.
-- Underdog: the UnderdogCount living nations with the fewest provinces defend at +Config.Battle.UnderdogBonus
--   combat strength (the defending side of a battle only, not sieges). A tie at the cut-off leaves everyone in it
--   out, so there are never more than UnderdogCount underdogs, and nobody is one while everyone is level.
-- Coalition: a living nation holding Config.Diplomacy.CoalitionThreshold of the ownable provinces (mountains don't
--   count) wears the crown, and any
--   nation's side fighting against a crowned nation gets +Config.Battle.CoalitionBonus combat strength (neutral
--   garrisons and Rebels don't). Two crowned nations fighting each other both get it.
-- Eliminated nations hold no provinces that count, are never underdogs and never wear the crown.

local Config = require("../Config")
local Types = require("../Types")

type MatchState = Types.MatchState

local CatchUp = {}

-- Mountains can never be owned, so shares (the crown, domination, alliance victory) count only the other provinces.
function CatchUp.ownable(terrain: Types.Terrain): boolean
	return terrain ~= "Mountain"
end

-- How many provinces of this map can be owned.
function CatchUp.ownableCount(provinces: { [number]: { terrain: Types.Terrain } }): number
	local n = 0
	for _, p in provinces do
		if CatchUp.ownable(p.terrain) then
			n += 1
		end
	end
	return n
end

-- Province counts of living nations (nations with no provinces count as 0), and the number of ownable provinces.
function CatchUp.counts(state: MatchState): ({ [number]: number }, number)
	local counts: { [number]: number } = {}
	for id, nation in state.nations do
		if not nation.eliminated then
			counts[id] = 0
		end
	end
	local total = 0
	for _, p in state.provinces do
		if CatchUp.ownable(p.terrain) then
			total += 1
		end
		local owner = p.owner
		if owner ~= nil and counts[owner] ~= nil then
			counts[owner] += 1
		end
	end
	return counts, total
end

-- Gold income multiplier for a nation holding this many provinces.
function CatchUp.overextension(provinces: number): number
	local c = Config.CatchUp
	local extra = provinces - c.OverextensionStart
	if extra < c.OverextensionStep then
		return 1
	end
	return math.max(0, 1 - math.floor(extra / c.OverextensionStep) * c.OverextensionPenalty)
end

function CatchUp.goldMultiplier(state: MatchState, nationId: number): number
	local n = 0
	for _, p in state.provinces do
		if p.owner == nationId then
			n += 1
		end
	end
	return CatchUp.overextension(n)
end

-- Underdogs from living nations' province counts: at most UnderdogCount of them, and only nations someone
-- out-sizes. A nation qualifies when it plus every nation at or below its count make UnderdogCount or fewer.
function CatchUp.underdogsFrom(counts: { [number]: number }): { [number]: boolean }
	local out: { [number]: boolean } = {}
	local largest = -math.huge
	for _, n in counts do
		largest = math.max(largest, n)
	end
	for id, mine in counts do
		if mine < largest then
			local atOrBelow = 0
			for _, other in counts do
				if other <= mine then
					atOrBelow += 1
				end
			end
			if atOrBelow <= Config.CatchUp.UnderdogCount then
				out[id] = true
			end
		end
	end
	return out
end

-- Crowned nations from living nations' province counts and the map's ownable provinces (normally none or one).
function CatchUp.leadersFrom(counts: { [number]: number }, total: number): { [number]: boolean }
	local out: { [number]: boolean } = {}
	if total <= 0 then
		return out
	end
	for id, n in counts do
		if n >= Config.Diplomacy.CoalitionThreshold * total then
			out[id] = true
		end
	end
	return out
end

function CatchUp.underdogs(state: MatchState): { [number]: boolean }
	return CatchUp.underdogsFrom((CatchUp.counts(state)))
end

function CatchUp.leaders(state: MatchState): { [number]: boolean }
	return CatchUp.leadersFrom(CatchUp.counts(state))
end

-- Battle.bonus: extra combat strength for one side. Owners are the nations on that side (0 = neutral).
function CatchUp.battleBonus(state: MatchState, owners: { number }, enemies: { number }, defending: boolean): number
	local counts, total = CatchUp.counts(state)
	local underdogs = if defending then CatchUp.underdogsFrom(counts) else {}
	local leaders = CatchUp.leadersFrom(counts, total)
	local underdog, nationSide, facingLeader = false, false, false
	for _, id in owners do
		underdog = underdog or underdogs[id] == true
		nationSide = nationSide or id ~= 0
	end
	for _, id in enemies do
		facingLeader = facingLeader or leaders[id] == true
	end
	local bonus = 0
	if underdog then
		bonus += Config.Battle.UnderdogBonus
	end
	if nationSide and facingLeader then
		bonus += Config.Battle.CoalitionBonus
	end
	return bonus
end

return CatchUp
