--!strict
-- Sliding one-second window per key (one key per player): at most `perSecond` intents.
-- Time is passed in, so this is pure and testable.

export type RateLimit = {
	perSecond: number,
	recent: { [number]: { number } }, -- key -> timestamps inside the window
}

local RateLimit = {}

function RateLimit.new(perSecond: number): RateLimit
	return { perSecond = perSecond, recent = {} }
end

function RateLimit.allow(limit: RateLimit, key: number, now: number): boolean
	local list = limit.recent[key]
	if list == nil then
		list = {}
		limit.recent[key] = list
	end
	local kept = {}
	for _, t in list do
		if now - t < 1 then
			table.insert(kept, t)
		end
	end
	if #kept >= limit.perSecond then
		limit.recent[key] = kept
		return false
	end
	table.insert(kept, now)
	limit.recent[key] = kept
	return true
end

function RateLimit.forget(limit: RateLimit, key: number)
	limit.recent[key] = nil
end

return RateLimit
