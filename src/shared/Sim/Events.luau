--!strict
-- Records things players should hear about. The server sends them with the tick's delta, then clears them.

local Types = require("../Types")

local Events = {}

-- by (optional): the nation that caused it, where clients need to know (a Power's caster). men (optional): the men a
-- Meteor killed (achievements). line (optional): an insult's or comeback's line (Shared.Flavour.Insults).
function Events.push(
	state: Types.MatchState,
	kind: string,
	a: number?,
	b: number?,
	province: number?,
	by: number?,
	men: number?,
	line: number?
)
	table.insert(
		state.events,
		{ kind = kind, a = a or 0, b = b or 0, province = province or 0, by = by, men = men, line = line }
	)
end

return Events
