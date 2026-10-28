--!nocheck
-- Music (docs/NEXT_FEATURES.md 6, docs/DESIGN.md "Sound and effects"): the moods follow the match and crossfade,
-- Peace and War hold each other off, the Cataclysm and Results cut through, the War and Cataclysm banners duck the
-- music, the speaker's popover turns Music and Sounds off one at a time, and both stay off after a rejoin.

local Config = require("../../../src/shared/Config")
local Diplomacy = require("../../../src/shared/Sim/Diplomacy")
local Emulator = require("../Emulator")
local H = require("../H")

local M = Config.Music
-- stand-ins, so the two players really play (Music.TRACKS stays empty until the owner picks the tracks)
local STAND_INS = {
	Lobby = "rbxassetid://9001",
	Peace = "rbxassetid://9002",
	War = "rbxassetid://9003",
	Cataclysm = "rbxassetid://9004",
	Victory = "rbxassetid://9005",
	Results = "rbxassetid://9006",
}

local function run()
	H.server("Services.AIService").step = function() end -- the bots sit still: the only war is Alice's
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	local userId = alice.localPlayer.UserId
	local Music = H.client(alice, "Music")
	for track, id in STAND_INS do
		Music.TRACKS[track] = id
	end
	local state = H.state()
	local workspace = Emulator.server.dm:GetService("Workspace")

	local function playing(): string
		return table.concat(Emulator.musicPlaying(alice), ",")
	end
	-- run in small steps until the mood is `track`; the seconds it took
	local function waitFor(track: string, seconds: number): number
		local start = Emulator.now()
		while Music.state().track ~= track and Emulator.now() - start < seconds do
			Emulator.run(0.1)
		end
		H.expect(Music.state().track == track, string.format("%s plays (not %s)", track, tostring(Music.state().track)))
		return Emulator.now() - start
	end
	local function volumeNear(v: number): boolean
		return math.abs(Music.state().volume - v) < 0.01
	end

	-- the chain: two AudioPlayers into one AudioFader named Music, into an AudioDeviceOutput
	Emulator.run(2)
	local fader = alice.dm:GetService("SoundService"):FindFirstChild("Music")
	H.expect(fader ~= nil and fader.ClassName == "AudioFader" and volumeNear(M.Volume), "an AudioFader named Music")
	local wired = 0
	for _, w in fader:GetDescendants() do
		if w.ClassName == "Wire" and w.TargetInstance == fader and w.SourceInstance.ClassName == "AudioPlayer" then
			wired += 1
		end
	end
	local out = fader:FindFirstChildOfClass("AudioDeviceOutput")
	local toOutput = fader:FindFirstChildOfClass("Wire")
	H.expect(wired == 2 and out and toOutput and toOutput.TargetInstance == out, "players A and B wired in, out to the device")

	-- Peace on joining
	H.expect(Music.state().track == "Peace", "Peace plays in the Peace phase")
	H.expect(playing() == "Peace", "one track plays: Peace")
	local peaceSince = Music.state().since

	-- War: the banner ducks the music; not at war yet, so Peace plays on
	workspace:SetAttribute("DevTick", 179)
	local deadline = Emulator.now() + 3
	while not volumeNear(M.DuckVolume) and Emulator.now() < deadline do
		Emulator.run(0.1)
	end
	H.expect(state.phase == "War" and volumeNear(M.DuckVolume), "the War banner ducks the music")
	H.expect(Music.state().track == "Peace", "the War phase without a war of yours plays Peace")
	Emulator.run(M.DuckSeconds + M.DuckFadeSeconds + 0.2)
	H.expect(volumeNear(M.Volume), "and lets it back up")

	-- Alice declares war a few seconds after Peace started: War waits out the hold, then crossfades in
	local A = H.myNation(alice)
	local B
	for _, p in state.provinces do -- give Alice a neutral province next to another nation, so they border
		for _, q in p.neighbors do
			local next = state.provinces[q]
			if B == nil and p.owner and p.owner ~= A and next.owner == nil and next.terrain ~= "Mountain" then
				next.owner = A
				B = p.owner
			end
		end
	end
	Emulator.run(1)
	H.client(alice, "Intents").diplomacy("War", B)
	Emulator.run(1.5)
	H.expect(Diplomacy.atWar(state, A, B), "Alice is at war with nation " .. tostring(B))
	H.expect(Music.state().track == "Peace", "Peace holds for MinMoodSeconds")
	waitFor("War", M.MinMoodSeconds)
	H.expect(Music.state().since - peaceSince >= M.MinMoodSeconds - 0.01, "War came once the hold was over")
	H.expect(playing() == "Peace,War", "a crossfade: both, for FadeSeconds")
	Emulator.run(M.FadeSeconds + 0.2)
	H.expect(playing() == "War", "then War alone: Peace stopped")
	local warSince = Music.state().since

	-- a quick peace: War holds, then Peace comes back
	Diplomacy.propose(state, "Peace", B, A, 0)
	H.expect(Diplomacy.accept(state, "Peace", A, B), "peace is made")
	Emulator.run(2)
	H.expect(Music.state().track == "War", "War holds after a quick peace")
	waitFor("Peace", M.MinMoodSeconds)
	H.expect(Music.state().since - warSince >= M.MinMoodSeconds - 0.01, "Peace came back once the hold was over")
	Emulator.run(M.FadeSeconds + 0.2)
	H.expect(playing() == "Peace", "Peace alone")

	-- the Cataclysm cuts through the hold at once, and its banner ducks the music
	workspace:SetAttribute("DevTick", 1199)
	local took = waitFor("Cataclysm", 3)
	H.expect(took < 3, "the Cataclysm at once")
	Emulator.run(0.5)
	H.expect(volumeNear(M.DuckVolume), "the Cataclysm banner ducks the music")
	Emulator.run(M.FadeSeconds)
	H.expect(playing() == "Cataclysm", "Cataclysm alone")

	-- the speaker: a popover with two toggles; Music off silences the music only
	Emulator.press(alice, "Mute")
	Emulator.run(0.3)
	H.expect(H.within(alice, "SpeakerMenu", "Music on") and H.within(alice, "SpeakerMenu", "Sounds on"), "two toggles")
	H.shot(alice, "speaker")
	local Sounds = H.client(alice, "Sounds")
	local speaker = alice.localPlayer.PlayerGui:FindFirstChild("Mute", true)
	Emulator.press(alice, "MusicToggle")
	Emulator.run(0.5)
	H.expect(playing() == "" and not Music.state().on, "Music off: no music player is playing")
	H.expect(Sounds.enabled("sounds") and speaker:GetAttribute("Muted") == false, "the sounds stay on")
	H.expect(H.within(alice, "SpeakerMenu", "Music off"), "the toggle says so")
	Emulator.press(alice, "MusicToggle")
	Emulator.run(0.2)
	H.expect(Music.state().on and playing() == "Cataclysm", "on again: the track starts over")
	Emulator.press(alice, "MusicToggle")
	Emulator.press(alice, "SoundsToggle")
	Emulator.run(0.5)
	H.expect(not Music.state().on and not Sounds.enabled("sounds"), "both off")
	H.expect(speaker:GetAttribute("Muted") == true, "both off: the speaker shows muted (Muted)")
	H.shot(alice, "speaker_off")
	Emulator.run(6)
	H.expect(not H.client(alice, "UI.Speaker").isOpen(), "the popover closes by itself")

	-- saved in the profile, with music_setting for each flip
	local Data = H.server("Services.PlayerDataService")
	local saved = Data.data(alice.serverPlayer).settings
	H.expect(saved.music == false and saved.sounds == false, "both saved in profile.settings")
	local logged = {}
	for _, r in Emulator.analytics do
		if r.method == "LogCustomEvent" and r.args[1] == "music_setting" and r.userId == userId then
			local f = r.args[#r.args]
			table.insert(logged, f.CustomField01 .. "," .. f.CustomField02 .. "," .. f.CustomField03)
		end
	end
	H.expect(#logged == 4, "music_setting for each of the four flips (" .. #logged .. ")")
	H.expect(logged[#logged] == "off,off,match", "the last one: both off, during the match")

	-- the server checks every preference: an unknown key, a value of the wrong kind, a bad shape, too many at once
	local answers = {}
	local remotes = alice.dm:GetService("ReplicatedStorage").Remotes
	remotes.CommandResult.OnClientEvent:Connect(function(_id, _ok, reason)
		table.insert(answers, reason or "ok")
	end)
	Emulator.run(1.1) -- a fresh second for the rate limit
	remotes.RequestPreference:FireServer(9001, "volume", true)
	remotes.RequestPreference:FireServer(9002, "music", "loud")
	remotes.RequestPreference:FireServer(9003, 5, true)
	Emulator.run(0.5)
	H.expect(table.concat(answers, ",") == "BadSetting,BadSetting,BadRequest", "refused: " .. table.concat(answers, ","))
	Emulator.run(1.1)
	answers = {}
	for i = 1, Config.Net.MaxIntentsPerSecond + 2 do
		remotes.RequestPreference:FireServer(9100 + i, "sounds", false)
	end
	Emulator.run(0.5)
	local tooFast = 0
	for _, reason in answers do
		tooFast += if reason == "TooFast" then 1 else 0
	end
	H.expect(tooFast == 2, "the rate limit answers the rest (" .. tooFast .. ")")
	saved = Data.data(alice.serverPlayer).settings
	H.expect(saved.music == false and saved.sounds == false and saved.volume == nil, "nothing else changed")
	local after = 0
	for _, r in Emulator.analytics do
		after += if r.method == "LogCustomEvent" and r.args[1] == "music_setting" then 1 else 0
	end
	H.expect(after == #logged, "a request that changes nothing logs nothing")

	-- a rejoin: still off
	Emulator.removeClient(alice)
	Emulator.run(3)
	local rejoined = #Emulator.sounds
	alice = Emulator.addClient("Alice", nil, userId)
	Music = H.client(alice, "Music")
	for track, id in STAND_INS do
		Music.TRACKS[track] = id
	end
	Emulator.run(3)
	Sounds = H.client(alice, "Sounds")
	H.expect(Music.state().track == "Cataclysm", "back in the Cataclysm")
	H.expect(not Music.state().on and playing() == "", "rejoined: the music is still off")
	local blip = false
	for i = rejoined + 1, #Emulator.sounds do
		blip = blip or Emulator.sounds[i].music == true
	end
	H.expect(not blip, "not even for a moment: the first track waits for the saved setting")
	H.expect(not Sounds.enabled("sounds"), "and the sounds")
	speaker = alice.localPlayer.PlayerGui:FindFirstChild("Mute", true)
	H.expect(speaker:GetAttribute("Muted") == true, "the speaker shows muted")
	Emulator.press(alice, "Mute")
	Emulator.press(alice, "MusicToggle")
	Emulator.run(M.FadeSeconds + 0.2)
	H.expect(playing() == "Cataclysm", "Music on: the mood's track fades in")
	H.expect(speaker:GetAttribute("Muted") == false, "not muted")

	-- Results: Alice wins, the Victory sting plays once, then the Lobby theme
	A = H.myNation(alice)
	local total, given = 0, 0
	for _, p in state.provinces do
		total += 1
		given += if p.owner == A then 1 else 0
	end
	for _, p in state.provinces do
		if given < math.ceil(Config.Win.DominationShare * total) and p.owner ~= A and p.terrain ~= "Mountain" then
			p.owner = A
			given += 1
		end
	end
	waitFor("Victory", 3)
	Emulator.run(M.FadeSeconds + 0.2)
	H.expect(playing() == "Victory", "you won: the Victory sting")
	local sting
	for _, p in alice.dm:GetService("SoundService").Music:GetChildren() do
		if p.ClassName == "AudioPlayer" and p:GetAttribute("Track") == "Victory" then
			sting = p
		end
	end
	H.expect(sting and sting.Looping == false, "a sting plays once")
	Emulator.endAudio(sting)
	waitFor("Lobby", 1)
	Emulator.run(M.FadeSeconds + 0.2)
	H.expect(playing() == "Lobby", "then the Lobby theme")
	waitFor("Peace", Config.Phases.ResultsTicks + 5)
	H.expect(H.state().phase == "Peace", "the next match: Peace")
end

return { run = run }
