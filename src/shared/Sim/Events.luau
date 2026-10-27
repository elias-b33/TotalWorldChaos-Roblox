--!strict
-- Records things players should hear about. The server sends them with the tick's delta, then clears them.

local Types = require("../Types")

local Events = {}

function Events.push(state: Types.MatchState, kind: string, a: number?, b: number?, province: number?)
	table.insert(state.events, { kind = kind, a = a or 0, b = b or 0, province = province or 0 })
end

return Events
