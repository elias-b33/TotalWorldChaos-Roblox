--!strict
-- Which music plays (docs/DESIGN.md "Sound and effects", docs/NEXT_FEATURES.md 6): pure rules with no Roblox APIs,
-- so tests/music.spec.luau runs them under Lune (like PixelArt). src/client/Music feeds them what the client sees and
-- plays the track they pick.
--
--   Lobby      the start menu, the map vote and the draft
--   Peace      building and expanding; the War phase while you are not fighting; the whole sandbox
--   War        the War phase while your nation is at war or fought a battle (on land or at sea) in the last
--              BattleWindowSeconds; a Primordial (your nation fell) hears it for the rest of the War phase
--   Cataclysm  from 20:00
--   Victory    at Results if you won, else Results: a sting played once, then the Lobby theme
--
-- Peace and War never switch back to each other within MinMoodSeconds, so a quick peace doesn't flip the music
-- twice; every other change (a new screen, the Cataclysm, Results) is at once. The numbers are Config.Music's: the
-- caller passes them in as `rules` (a client module can't reach Shared through a string require).

local MusicMood = {}

export type Track = "Lobby" | "Peace" | "War" | "Cataclysm" | "Victory" | "Results"
export type Screen = "Menu" | "Lobby" | "Match"

export type Input = {
	screen: Screen, -- the start menu, the Lobby (vote or draft) or a match
	phase: string, -- the match's phase (Types.Phase) on the Match screen
	atWar: boolean, -- your nation is in a war
	battleAt: number?, -- when a battle of yours was last seen, on the same clock as `now` (nil = never)
	won: boolean?, -- at Results: your nation (or its alliance) won
	eliminated: boolean?, -- your nation fell: you are a Primordial
	sandbox: boolean?, -- a sandbox world (docs/DESIGN.md "Sandbox")
	stingOver: boolean?, -- at Results: the Victory or Results sting has played to its end
}

export type Current = { track: Track?, since: number } -- what plays and since when (nil = nothing yet)
export type Rules = { MinMoodSeconds: number, BattleWindowSeconds: number } -- Config.Music

-- The parts of the client's copy of the match (Snapshot.SnapshotData) the mood reads.
export type View = {
	armies: { { owner: number, inBattle: boolean } },
	fleets: { { owner: number, inBattle: boolean } },
	provinces: { { owner: number, battle: boolean } },
	diplomacy: { wars: { { attackers: { number }, defenders: { number } } } },
	result: { winners: { number } }?,
}
export type Event = { kind: string, a: number, b: number }

MusicMood.TRACKS = { "Lobby", "Peace", "War", "Cataclysm", "Victory", "Results" } :: { Track }
-- Played once instead of looped.
MusicMood.STINGS = { Victory = true, Results = true } :: { [string]: boolean }

-- Moods that hold each other off for MinMoodSeconds.
local HELD: { [string]: boolean } = { Peace = true, War = true }

-- The track the moment asks for, before the hold.
function MusicMood.wanted(input: Input, now: number, rules: Rules): Track
	if input.screen ~= "Match" then
		return "Lobby"
	elseif input.sandbox then
		return "Peace"
	end
	local phase = input.phase
	if phase == "Results" then
		if input.stingOver then
			return "Lobby"
		end
		return if input.won then "Victory" else "Results"
	elseif phase == "Cataclysm" then
		return "Cataclysm"
	elseif phase == "War" then
		local battleAt = input.battleAt
		local fought = battleAt ~= nil and now - battleAt < rules.BattleWindowSeconds
		return if input.atWar or input.eliminated or fought then "War" else "Peace"
	elseif phase == "Lobby" or phase == "Pick" then
		return "Lobby"
	end
	return "Peace"
end

-- The track to play now: the wanted one, unless Peace and War would swap before MinMoodSeconds have passed.
function MusicMood.pick(input: Input, current: Current, now: number, rules: Rules): Track
	local want = MusicMood.wanted(input, now, rules)
	local playing = current.track
	if playing == nil or playing == want then
		return want
	end
	if HELD[want] and HELD[playing] and now - current.since < rules.MinMoodSeconds then
		return playing
	end
	return want
end

local function has(list: { number }, id: number): boolean
	return table.find(list, id) ~= nil
end

-- Is nation `me` (0 = none) in a war?
function MusicMood.atWar(view: View, me: number): boolean
	if me == 0 then
		return false
	end
	for _, war in view.diplomacy.wars do
		if has(war.attackers, me) or has(war.defenders, me) then
			return true
		end
	end
	return false
end

-- Is a battle of yours on: one of your armies or fleets fighting (a sea battle counts), or a battle in one of your
-- provinces?
function MusicMood.fighting(view: View, me: number): boolean
	if me == 0 then
		return false
	end
	for _, army in view.armies do
		if army.owner == me and army.inBattle then
			return true
		end
	end
	for _, fleet in view.fleets do
		if fleet.owner == me and fleet.inBattle then
			return true
		end
	end
	for _, province in view.provinces do
		if province.owner == me and province.battle then
			return true
		end
	end
	return false
end

-- Did one of a delta's events end a battle of yours, on land (BattleEnded) or at sea (SeaBattle)? A battle won in a
-- single round starts and ends inside one delta, so only its event shows it.
function MusicMood.fought(events: { Event }, me: number): boolean
	if me == 0 then
		return false
	end
	for _, e in events do
		if (e.kind == "BattleEnded" or e.kind == "SeaBattle") and (e.a == me or e.b == me) then
			return true
		end
	end
	return false
end

-- Did nation `me` win the match (alone or with its alliance)?
function MusicMood.won(view: View, me: number): boolean
	local result = view.result
	return me ~= 0 and result ~= nil and has(result.winners, me)
end

return MusicMood
