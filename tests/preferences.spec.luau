--!strict
-- Saved preferences (src/shared/Sim/Preferences.luau, docs/NEXT_FEATURES.md 3.3): the speaker's Music and Sounds
-- toggles, kept in profile.settings and sent back in the profile summary.
local Preferences = require("../src/shared/Sim/Preferences")
local Progression = require("../src/shared/Sim/Progression")
local T = require("./TestKit")

T.test("music and sounds are on until a player turns them off", function()
	local profile = Progression.newProfile()
	T.equal(Preferences.get(profile, "music"), true)
	T.equal(Preferences.get(profile, "sounds"), true)
	local summary = Progression.summary(profile)
	T.expect(summary.music and summary.sounds, "the summary says both are on")
end)

T.test("a toggle is saved in profile.settings and reaches the summary", function()
	local profile = Progression.newProfile()
	T.equal(Preferences.set(profile, "music", false), true)
	T.equal(profile.settings.music, false, "saved")
	T.equal(Preferences.get(profile, "music"), false)
	T.equal(Preferences.get(profile, "sounds"), true, "the other toggle is untouched")
	local summary = Progression.summary(profile)
	T.expect(not summary.music and summary.sounds, "the summary carries it")
	T.equal(Preferences.set(profile, "music", true), true)
	T.equal(profile.settings.music, nil, "back on: the default is stored as nothing")
	T.equal(Preferences.get(profile, "music"), true)
end)

T.test("unknown keys and values of the wrong kind change nothing", function()
	local profile = Progression.newProfile()
	local ok, reason = Preferences.set(profile, "volume", 3)
	T.equal(ok, false)
	T.equal(reason, "BadSetting")
	ok, reason = Preferences.set(profile, "music", "off")
	T.equal(ok, false, "a string for a toggle")
	T.equal(reason, "BadSetting")
	T.equal(Preferences.set(profile, "sounds", 0), false, "a number for a toggle")
	T.equal(
		Preferences.set(profile, "warlordWeek", 5),
		false,
		"another setting in profile.settings is not a preference"
	)
	T.equal(next(profile.settings), nil, "nothing was written")
end)

T.test("a stored value of the wrong kind reads as the default", function()
	local profile = Progression.newProfile()
	profile.settings.sounds = "garbled"
	T.equal(Preferences.get(profile, "sounds"), true)
end)

T.test("every key has a kind and a default of that kind", function()
	for key, def in Preferences.KEYS do
		T.equal(type(def.default), def.kind, key)
		T.expect(Preferences.valid(key, def.default), key .. " accepts its default")
	end
	T.expect(not Preferences.valid("nope", true), "an unknown key")
end)

T.finish()
