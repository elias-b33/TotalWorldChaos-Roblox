--!strict
-- Read-only questions about the client's copy of the match, for the UI: who is at war, who may go where,
-- scores and ranks. The server re-checks everything; this only decides which buttons to show.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Pathing = require(Shared.Sim.Pathing)
local Races = require(Shared.Sim.Races)
local Snapshot = require(Shared.Snapshot)
local Troops = require(Shared.Sim.Troops)
local Types = require(Shared.Types)

local ClientState = require(script.Parent.ClientState)

local Relations = {}

local function diplomacy()
	local snap = ClientState.snapshot()
	return if snap then snap.diplomacy else nil
end

function Relations.atWar(a: number, b: number): boolean
	local d = diplomacy()
	if d == nil or a == b or a == 0 or b == 0 then
		return false
	end
	for _, w in d.wars do
		local aAtt, aDef = table.find(w.attackers, a) ~= nil, table.find(w.defenders, a) ~= nil
		local bAtt, bDef = table.find(w.attackers, b) ~= nil, table.find(w.defenders, b) ~= nil
		if (aAtt and bDef) or (aDef and bAtt) then
			return true
		end
	end
	return false
end

function Relations.allied(a: number, b: number): boolean
	if a == b or a == 0 or b == 0 then
		return false
	end
	local na, nb = ClientState.nation(a), ClientState.nation(b)
	return na ~= nil and nb ~= nil and na.allianceId ~= 0 and na.allianceId == nb.allianceId
end

function Relations.truce(a: number, b: number): boolean
	local d = diplomacy()
	if d == nil then
		return false
	end
	local tick = ClientState.tick()
	for _, t in d.truces do
		if t.untilTick > tick and ((t.a == a and t.b == b) or (t.a == b and t.b == a)) then
			return true
		end
	end
	return false
end

-- Military access (the EU4 pack): may `guest`'s armies march through `owner`'s land right now?
function Relations.hasAccess(guest: number, owner: number): boolean
	local d = diplomacy()
	if d == nil then
		return false
	end
	local tick = ClientState.tick()
	for _, x in d.access or {} do
		if x.guest == guest and x.owner == owner and x.untilTick > tick then
			return true
		end
	end
	return false
end

-- Seconds until `a` may do `kind` ("Insult" | "Gift") to `b` again (0 = now).
function Relations.cooldown(kind: string, a: number, b: number): number
	local d = diplomacy()
	if d == nil then
		return 0
	end
	local tick = ClientState.tick()
	for _, c in d.cooldowns or {} do
		if c.kind == kind and c.a == a and c.b == b and c.untilTick > tick then
			return c.untilTick - tick
		end
	end
	return 0
end

-- Seconds left on `holder`'s grudge against `against` (an insult's combat bonus), 0 = none.
function Relations.grudge(holder: number, against: number): number
	local d = diplomacy()
	if d == nil then
		return 0
	end
	local tick = ClientState.tick()
	for _, g in d.grudges or {} do
		if g.holder == holder and g.against == against and g.untilTick > tick then
			return g.untilTick - tick
		end
	end
	return 0
end

-- The insult `nationId` may still answer with a comeback (the newest open window), or nil.
function Relations.comebackFor(nationId: number): Types.Comeback?
	local d = diplomacy()
	if d == nil or nationId == 0 then
		return nil
	end
	local tick = ClientState.tick()
	local best: Types.Comeback? = nil
	for _, w in d.comebacks or {} do
		if w.from == nationId and w.untilTick > tick and (best == nil or w.untilTick > best.untilTick) then
			best = w
		end
	end
	return best
end

-- "⚔" at war, "🤝" allied, "🕊" truce, "🚶" military access (either way), "" otherwise.
function Relations.icon(a: number, b: number): string
	if Relations.atWar(a, b) then
		return "⚔"
	elseif Relations.allied(a, b) then
		return "🤝"
	elseif Relations.truce(a, b) then
		return "🕊"
	elseif Relations.hasAccess(a, b) or Relations.hasAccess(b, a) then
		return "🚶"
	end
	return ""
end

function Relations.borders(a: number, b: number): boolean
	local snap, map = ClientState.snapshot(), ClientState.map()
	if snap == nil or map == nil then
		return false
	end
	for _, p in snap.provinces do
		if p.owner == a then
			for _, n in map.provinces[p.id].neighbors do
				if snap.provinces[n].owner == b then
					return true
				end
			end
		end
	end
	return false
end

function Relations.canEnter(nationId: number, provinceId: number): boolean
	local map = ClientState.map()
	local record = ClientState.province(provinceId)
	if map == nil or record == nil or map.provinces[provinceId].terrain == "Mountain" then
		return false
	end
	local owner = record.owner
	return owner == 0
		or owner == nationId
		or Relations.allied(nationId, owner)
		or Relations.atWar(nationId, owner)
		or Relations.hasAccess(nationId, owner)
end

-- The route an army of `nationId` would take, or nil if it can't get there.
function Relations.path(nationId: number, from: number, to: number): { number }?
	local map = ClientState.map()
	if map == nil then
		return nil
	end
	return Pathing.search(function(id)
		return map.provinces[id].neighbors
	end, function(id)
		return Relations.canEnter(nationId, id)
	end, from, to)
end

-- Seconds an army takes to walk a route (Sim.Movement.moveTicks): its slowest troop's speed, with Elves crossing
-- forest at plains speed. Without an army, normal infantry speed.
function Relations.travelTime(path: { number }, army: Snapshot.ArmyRecord?): number
	local map = ClientState.map()
	local t = 0
	if map then
		local troops: Types.Composition = if army then Troops.decode(army.troops) else { Infantry = 1 }
		local owner = if army then ClientState.nation(army.owner) else nil
		local race = if owner then owner.race :: Types.Race else nil
		for _, id in path do
			local terrain = Races.moveTerrain(race, map.provinces[id].terrain)
			t += Troops.moveTicks(troops, terrain) * Config.TickSeconds
		end
	end
	return t
end

function Relations.provinceCount(nationId: number): number
	local snap = ClientState.snapshot()
	local n = 0
	if snap then
		for _, p in snap.provinces do
			if p.owner == nationId then
				n += 1
			end
		end
	end
	return n
end

-- Same formula as Sim.Victory.score.
function Relations.score(nationId: number): number
	local snap = ClientState.snapshot()
	local nation = ClientState.nation(nationId)
	if snap == nil or nation == nil then
		return 0
	end
	local provinces, development = 0, 0
	for _, p in snap.provinces do
		if p.owner == nationId then
			provinces += 1
			development += p.development
		end
	end
	return provinces * Config.Win.ScorePerProvince
		+ development * Config.Win.ScorePerDevelopment
		+ nation.battlesWon * Config.Win.ScorePerBattleWon
end

-- 1 = best score.
function Relations.rank(nationId: number): number
	local snap = ClientState.snapshot()
	if snap == nil then
		return 0
	end
	local mine = Relations.score(nationId)
	local rank = 1
	for _, n in snap.nations do
		if n.id ~= nationId and Relations.score(n.id) > mine then
			rank += 1
		end
	end
	return rank
end

function Relations.offersTo(nationId: number)
	local d = diplomacy()
	local out = {}
	if d then
		local tick = ClientState.tick()
		for _, o in d.offers do
			if o.to == nationId and o.expiresAt > tick then
				table.insert(out, o)
			end
		end
	end
	return out
end

return Relations
