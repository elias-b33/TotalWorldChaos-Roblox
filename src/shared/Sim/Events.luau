--!strict
-- Records things players should hear about. The server sends them with the tick's delta, then clears them.

local Types = require("../Types")

local Events = {}

-- by (optional): the nation that caused it, where clients need to know (a Power's caster).
function Events.push(state: Types.MatchState, kind: string, a: number?, b: number?, province: number?, by: number?)
	table.insert(state.events, { kind = kind, a = a or 0, b = b or 0, province = province or 0, by = by })
end

return Events
