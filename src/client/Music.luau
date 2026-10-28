--!strict
-- The music (docs/DESIGN.md "Sound and effects", docs/NEXT_FEATURES.md 6): a track for each mood of the match,
-- picked by MusicMood from what this client sees, crossfaded over Config.Music.FadeSeconds.
--
-- Two AudioPlayers, A and B, are wired into one AudioFader named Music (the music's volume, and the duck under the
-- phase banners), wired into an AudioDeviceOutput, all in SoundService. A mood change loads the new track on the idle
-- player, plays it at volume 0 and fades it in while the other fades out and stops: one track plays once a fade is
-- over, never more than the two of a crossfade. Victory and Results are stings, played once (then the Lobby theme);
-- the rest loop. The speaker's Music toggle (Sounds) stops both players; turned on again, the mood's track fades in.
--
-- TRACKS are empty until the owner picks them (docs/STUDIO.md "Music"): an empty track is silence, never an error.
-- Sounds.luau keeps its Sound objects for the effects.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

ReplicatedStorage:WaitForChild("Shared")
local Config = require(ReplicatedStorage.Shared.Config)

local ClientState = require(script.Parent.ClientState)
local LobbyState = require(script.Parent.LobbyState)
local MusicMood = require(script.Parent.MusicMood)
local Sounds = require(script.Parent.Sounds)
local Menu = require(script.Parent.UI.Menu)

local M = Config.Music
local CHECK_SECONDS = 0.25 -- how often the mood is checked
local SETTINGS_WAIT = 10 -- the first track waits this long at most for the saved Music toggle (the profile)

local Music = {}

-- One "rbxassetid://<id>" per mood, from the Creator Store (docs/STUDIO.md "Music"). Empty = silent.
Music.TRACKS = {
	Lobby = "",
	Peace = "",
	War = "",
	Cataclysm = "",
	Victory = "",
	Results = "",
} :: { [string]: string }

local fader: AudioFader? = nil
local players: { AudioPlayer } = {} -- A and B
local active = 0 -- the player holding the current track (0 = none yet)
local current: MusicMood.Current = { track = nil, since = 0 }
local playing: { [AudioPlayer]: string } = {} -- the track each player is playing
local fades: { [Instance]: Tween } = {}
local on = true -- the Music toggle, as last applied
local battleAt: number? = nil -- when a battle of yours was last seen
local stingOver = false -- this Results phase's sting has played to its end
local duckSerial = 0
local lastCheck = -math.huge
local startedAt = 0

local function wire(source: Instance, target: Instance)
	local w = Instance.new("Wire")
	w.Name = "Wire"
	w.SourceInstance = source
	w.TargetInstance = target
	w.Parent = source
end

-- Tween one property, replacing the tween already running on that object; `done` runs if it finishes.
local function tween(inst: Instance, seconds: number, goal: { [string]: any }, done: (() -> ())?)
	local running = fades[inst]
	fades[inst] = nil -- first: a cancelled tween's Completed must not run its `done`
	if running then
		running:Cancel()
	end
	local t = TweenService:Create(inst, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), goal)
	fades[inst] = t
	t.Completed:Connect(function()
		if fades[inst] == t then
			fades[inst] = nil
			if done then
				done()
			end
		end
	end)
	t:Play()
end

local function stop(p: AudioPlayer)
	playing[p] = nil
	pcall(function()
		p:Stop()
	end)
end

-- Stop a player at once (its fade too).
local function silence(p: AudioPlayer)
	local running = fades[p]
	fades[p] = nil
	if running then
		running:Cancel()
	end
	p.Volume = 0
	stop(p)
end

-- Load a track on a player and fade it in (nothing to play: an empty track, or music off).
local function start(p: AudioPlayer, track: string)
	p:SetAttribute("Track", track)
	p.Looping = not MusicMood.STINGS[track]
	local id = Music.TRACKS[track] or ""
	if id == "" or not on then
		return
	end
	p.Asset = id
	p.Volume = 0
	local ok = pcall(function()
		p:Play()
	end)
	if ok then
		playing[p] = track
		tween(p, M.FadeSeconds, { Volume = 1 })
	end
end

local function switchTo(track: MusicMood.Track)
	current = { track = track, since = os.clock() }
	if #players == 0 then
		return
	end
	local old = players[active]
	active = if active == 1 then 2 else 1
	local new = players[active]
	silence(new) -- still fading out from the change before: it stops now
	start(new, track)
	if old then
		tween(old, M.FadeSeconds, { Volume = 0 }, function()
			stop(old)
		end)
	end
end

local function screen(): MusicMood.Screen?
	if Menu.isOpen() then
		return "Menu"
	elseif LobbyState.phase() ~= "None" then
		return "Lobby"
	elseif ClientState.snapshot() then
		return "Match"
	end
	return nil -- nothing from the server yet
end

local function check()
	local s = screen()
	if s == nil or (not Sounds.loaded() and os.clock() - startedAt < SETTINGS_WAIT) then
		return -- nothing from the server yet, or a player who turned music off would hear it start
	end
	local snapshot = ClientState.snapshot()
	local me = ClientState.myNation()
	local phase = if snapshot then snapshot.phase else "Lobby"
	if phase ~= "Results" then
		stingOver = false
	end
	local view: MusicMood.View? = snapshot :: any -- SnapshotData has every field the mood reads
	local input: MusicMood.Input = {
		screen = s,
		phase = phase,
		atWar = view ~= nil and MusicMood.atWar(view, me),
		battleAt = battleAt,
		won = view ~= nil and MusicMood.won(view, me),
		eliminated = ClientState.myPrimordial() ~= nil,
		sandbox = snapshot ~= nil and snapshot.setup.sandbox == true,
		stingOver = stingOver,
	}
	local track = MusicMood.pick(input, current, os.clock(), M)
	if track ~= current.track then
		switchTo(track)
	end
end

local function build()
	local f = Instance.new("AudioFader")
	f.Name = "Music"
	f.Volume = M.Volume
	local output = Instance.new("AudioDeviceOutput")
	output.Name = "Output"
	output.Parent = f
	wire(f, output)
	for _, name in { "A", "B" } do
		local p = Instance.new("AudioPlayer")
		p.Name = name
		p.Looping = true
		p.Volume = 0
		p.Parent = f
		wire(p, f)
		p.Ended:Connect(function()
			local track = playing[p] -- nil when we stopped it ourselves
			playing[p] = nil
			if track and players[active] == p and MusicMood.STINGS[track] then
				stingOver = true -- the sting played to its end: the Lobby theme
			end
		end)
		table.insert(players, p)
	end
	f.Parent = SoundService
	fader = f
end

local function onSettings()
	local wanted = Sounds.enabled("music")
	if wanted == on then
		return
	end
	on = wanted
	if not on then
		for _, p in players do
			silence(p)
		end
	elseif current.track and players[active] then
		start(players[active], current.track)
	end
end

-- Dip the music under a banner (the War and Cataclysm banners; later ones too) so its sound lands: down to
-- DuckVolume, back after DuckSeconds. Another duck meanwhile keeps it down longer.
function Music.duck()
	local f = fader
	if f == nil then
		return
	end
	duckSerial += 1
	local serial = duckSerial
	tween(f, M.DuckFadeSeconds, { Volume = M.DuckVolume })
	task.delay(M.DuckSeconds, function()
		if duckSerial == serial then
			tween(f, M.DuckFadeSeconds, { Volume = M.Volume })
		end
	end)
end

-- What plays, for the harness and for checks in Studio: the mood's track (kept while the music is off or the track
-- is empty), since when (os.clock), the Music toggle, the fader's volume and the tracks actually playing.
function Music.state(): { track: string?, since: number, on: boolean, volume: number, playing: { string } }
	local list = {}
	for _, p in players do
		local track = playing[p]
		if track then
			table.insert(list, track)
		end
	end
	local f = fader
	return {
		track = current.track,
		since = current.since,
		on = on,
		volume = if f then f.Volume else 0,
		playing = list,
	}
end

function Music.init()
	startedAt = os.clock()
	local ok = pcall(build)
	if not ok then
		players = {} -- no audio API on this device: the game plays without music
		fader = nil
	end
	on = Sounds.enabled("music")
	Sounds.onSettings(onSettings)
	ClientState.onReset(function()
		battleAt = nil -- a new match
	end)
	ClientState.onDelta(function(delta)
		local me = ClientState.myNation()
		local snapshot = ClientState.snapshot()
		local fought = MusicMood.fought(delta.events :: any, me) -- MatchEvents: kind, a, b and more
		if fought or (snapshot ~= nil and MusicMood.fighting(snapshot :: any, me)) then
			battleAt = os.clock()
		end
	end)
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - lastCheck >= CHECK_SECONDS then
			lastCheck = now
			check()
		end
	end)
end

return Music
