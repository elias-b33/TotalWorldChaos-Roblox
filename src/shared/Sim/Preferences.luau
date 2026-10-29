--!strict
-- A player's saved preferences (docs/NEXT_FEATURES.md 3.3): the keys that exist, what each may hold and its value
-- when never set. They live in profile.settings and reach the client in its ProfileSummary. RequestPreference(key,
-- value) goes through CommandRouter (shape and rate limit), then PlayerDataService calls Preferences.set.
--
--   music   the speaker's Music toggle (docs/DESIGN.md "Sound and effects"): true = music plays
--   sounds  the speaker's Sounds toggle: true = sound effects play
--
-- A value equal to the key's default is stored as nil, so a profile only carries what its player changed.

local Types = require("../Types")

type Profile = Types.PlayerProfile
type Value = boolean | number | string

export type Key = { kind: string, default: Value } -- kind: the Luau type of its values

local Preferences = {}

Preferences.KEYS = {
	music = { kind = "boolean", default = true },
	sounds = { kind = "boolean", default = true },
} :: { [string]: Key }

-- May `key` hold `value`?
function Preferences.valid(key: string, value: unknown): boolean
	local def = Preferences.KEYS[key]
	return def ~= nil and type(value) == def.kind
end

-- A preference's value in a profile (its default when never set). Errors on an unknown key.
function Preferences.get(profile: Profile, key: string): Value
	local def = assert(Preferences.KEYS[key], "unknown preference " .. key)
	local value = profile.settings[key]
	return if type(value) == def.kind then value else def.default
end

-- Change a preference. Refused (nothing changes) for a key that doesn't exist or a value it may not hold.
function Preferences.set(profile: Profile, key: string, value: unknown): (boolean, string?)
	if not Preferences.valid(key, value) then
		return false, "BadSetting"
	end
	local def = Preferences.KEYS[key]
	profile.settings[key] = if value == def.default then nil else value
	return true, nil
end

return Preferences
