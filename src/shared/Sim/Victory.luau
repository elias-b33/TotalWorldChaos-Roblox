--!strict
-- Win conditions (docs/DESIGN.md "Win conditions"): domination (40% of provinces), alliance victory
-- (55% between up to 3 allies), or the best score at 25:00.

local Config = require("../Config")
local Events = require("./Events")
local Types = require("../Types")

type MatchState = Types.MatchState

local Victory = {}

function Victory.score(state: MatchState, nationId: number): number
	local provinces, development = 0, 0
	for _, p in state.provinces do
		if p.owner == nationId then
			provinces += 1
			development += p.development
		end
	end
	local nation = state.nations[nationId]
	local battles = if nation then nation.battlesWon else 0
	return provinces * Config.Win.ScorePerProvince
		+ development * Config.Win.ScorePerDevelopment
		+ battles * Config.Win.ScorePerBattleWon
end

-- Every nation's score, best first (ties: lower nation id first).
function Victory.scores(state: MatchState): { { nation: number, score: number } }
	local out = {}
	for id in state.nations do
		table.insert(out, { nation = id, score = Victory.score(state, id) })
	end
	table.sort(out, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.nation < b.nation
	end)
	return out
end

local function provinceCounts(state: MatchState): ({ [number]: number }, number)
	local counts: { [number]: number } = {}
	local total = 0
	for _, p in state.provinces do
		total += 1
		if p.owner then
			counts[p.owner] = (counts[p.owner] or 0) + 1
		end
	end
	return counts, total
end

-- Domination or alliance victory, if anyone has reached it.
function Victory.check(state: MatchState): Types.MatchResult?
	local counts, total = provinceCounts(state)
	local ids = {}
	for id in counts do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		if counts[id] >= Config.Win.DominationShare * total then
			return { kind = "Domination", winners = { id }, scores = Victory.scores(state), endedAt = state.tick }
		end
	end
	local allianceIds = {}
	for id in state.alliances do
		table.insert(allianceIds, id)
	end
	table.sort(allianceIds)
	for _, id in allianceIds do
		local alliance = state.alliances[id]
		local held = 0
		for _, m in alliance.members do
			held += counts[m] or 0
		end
		if #alliance.members >= 2 and held >= Config.Win.AllianceShare * total then
			local winners = table.clone(alliance.members)
			table.sort(winners)
			return { kind = "Alliance", winners = winners, scores = Victory.scores(state), endedAt = state.tick }
		end
	end
	return nil
end

-- Time is up: the best score wins (everyone tied for first wins).
function Victory.byScore(state: MatchState): Types.MatchResult
	local scores = Victory.scores(state)
	local winners = {}
	for _, s in scores do
		if s.score == scores[1].score then
			table.insert(winners, s.nation)
		end
	end
	return { kind = "Score", winners = winners, scores = scores, endedAt = state.tick }
end

function Victory.finish(state: MatchState, result: Types.MatchResult)
	state.result = result
	state.phase = "Results"
	for _, w in result.winners do
		Events.push(state, "Victory", w, 0, 0)
	end
end

return Victory
