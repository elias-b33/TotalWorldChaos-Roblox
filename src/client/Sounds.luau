--!strict
-- Every sound the game plays, in one place, plus the speaker's two settings and a tap sound for every button.
--
-- The settings: Sounds (these effects) and Music (src/client/Music listens), flipped in the popover under the top
-- bar's speaker (UI/Speaker) and saved in the profile (Sim.Preferences); the saved ones arrive with the first
-- profile summary. The speaker button (Name Mute) shows muted, with its Muted attribute true, when both are off.
--
-- Stand-ins until the owner picks real sounds: every id is one of the few files every Roblox client ships in
-- content/sounds (the default character sounds: footsteps, jumps, landings, falling, swimming, an explosion, a
-- splash, "oof", "ouch", the volume-slider tick), played at different speeds so each moment sounds different.
-- To use a Creator Store or uploaded sound, put its "rbxassetid://<id>" here (docs/STUDIO.md "Sounds"). A missing
-- file is harmless: Roblox logs it and the game carries on silently.

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local ProfileState = require(script.Parent.ProfileState)

local Sounds = {}

export type Setting = "music" | "sounds"

export type SoundName =
	"Tap"
	| "BattleStart"
	| "BattleEnd"
	| "ArmyDestroyed"
	| "Capture"
	| "Lost"
	| "MeteorFall"
	| "MeteorImpact"
	| "Plague"
	| "Rebels"
	| "Earthquake"
	| "Blessing"
	| "Shield"
	| "War"
	| "Cataclysm"
	| "Results"

-- id: the file; volume 0..1; speed: playback speed (pitch); gap: seconds before the same sound may start again (a
-- burst of battles plays once).
local SOUNDS: { [string]: { id: string, volume: number, speed: number, gap: number } } = {
	Tap = { id = "rbxasset://sounds/volume_slider.ogg", volume = 0.5, speed = 1.2, gap = 0.05 },
	BattleStart = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.6, speed = 0.8, gap = 0.4 },
	BattleEnd = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.6, speed = 1.1, gap = 0.4 },
	ArmyDestroyed = { id = "rbxasset://sounds/impact_explosion_03.mp3", volume = 0.35, speed = 1.4, gap = 0.4 },
	Capture = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.5, speed = 1.3, gap = 0.3 },
	Lost = { id = "rbxasset://sounds/oof.ogg", volume = 0.45, speed = 1, gap = 1 },
	MeteorFall = { id = "rbxasset://sounds/action_falling.ogg", volume = 0.6, speed = 1.3, gap = 0.2 },
	MeteorImpact = { id = "rbxasset://sounds/impact_explosion_03.mp3", volume = 0.7, speed = 1, gap = 0.2 },
	Plague = { id = "rbxasset://sounds/impact_water.mp3", volume = 0.5, speed = 0.6, gap = 0.5 },
	Rebels = { id = "rbxasset://sounds/action_footsteps_plastic.mp3", volume = 0.6, speed = 0.9, gap = 0.5 },
	Earthquake = { id = "rbxasset://sounds/impact_explosion_03.mp3", volume = 0.6, speed = 0.45, gap = 0.5 },
	Blessing = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.5, speed = 1.8, gap = 0.5 },
	Shield = { id = "rbxasset://sounds/action_swim.mp3", volume = 0.5, speed = 1.5, gap = 0.5 },
	War = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.7, speed = 0.55, gap = 1 },
	Cataclysm = { id = "rbxasset://sounds/impact_explosion_03.mp3", volume = 0.7, speed = 0.6, gap = 1 },
	Results = { id = "rbxasset://sounds/action_get_up.mp3", volume = 0.6, speed = 1.2, gap = 1 },
}

-- module state lives as long as the client session, across matches
local settings: { [string]: boolean } = { music = true, sounds = true }
local loaded = false -- the saved settings arrived (the first profile summary)
local settingListeners: { () -> () } = {}
local instances: { [string]: Sound } = {}
local lastPlayed: { [string]: number } = {}
local muteButton: TextButton? = nil
local showMuted: ((boolean) -> ())? = nil -- draws the speaker button's icon (the top bar's pixel icons)
local hooked: { [Instance]: boolean } = {}

local function soundFor(name: string): Sound?
	local existing = instances[name]
	if existing then
		return existing
	end
	local def = SOUNDS[name]
	if def == nil then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = def.id
	sound.Volume = def.volume
	sound.PlaybackSpeed = def.speed
	sound.Parent = SoundService -- not in a part: plays everywhere at the same volume
	instances[name] = sound
	return sound
end

-- Play a sound (unless Sounds is off, or the same one just started). Never errors.
function Sounds.play(name: SoundName)
	if not settings.sounds then
		return
	end
	local def = SOUNDS[name]
	local now = os.clock()
	if def == nil or now - (lastPlayed[name] or -math.huge) < def.gap then
		return
	end
	lastPlayed[name] = now
	local sound = soundFor(name)
	if sound then
		pcall(function()
			sound:Play()
		end)
	end
end

-- Have the saved settings arrived (the first profile summary)?
function Sounds.loaded(): boolean
	return loaded
end

-- Is a speaker setting on?
function Sounds.enabled(setting: Setting): boolean
	return settings[setting] ~= false
end

-- Both settings off: the speaker shows muted.
function Sounds.muted(): boolean
	return not settings.music and not settings.sounds
end

local function showSpeaker()
	local muted = Sounds.muted()
	local button = muteButton
	if showMuted then
		showMuted(muted)
	elseif button then
		button.Text = if muted then "🔇" else "🔊"
	end
end

-- Turn a speaker setting on or off on this client (UI/Speaker also saves it, with RequestPreference). Sounds off
-- stops the sounds playing now; Music listens for its own (Sounds.onSettings).
function Sounds.set(setting: Setting, on: boolean)
	if settings[setting] == on then
		return
	end
	settings[setting] = on
	if setting == "sounds" and not on then
		for _, sound in instances do
			pcall(function()
				sound:Stop()
			end)
		end
	end
	showSpeaker()
	for _, fn in settingListeners do
		task.spawn(fn)
	end
end

-- Call `fn` whenever a speaker setting changes.
function Sounds.onSettings(fn: () -> ())
	table.insert(settingListeners, fn)
end

-- The speaker button: Hud builds it in the top bar and UI/Speaker opens its popover from it; Sounds keeps its icon
-- in step with the two settings (through `show` when given, else as the button's text).
function Sounds.attachMuteButton(button: TextButton, show: ((boolean) -> ())?)
	muteButton = button
	showMuted = show
	showSpeaker()
end

-- The id of a sound, for the harness and for anyone checking the list.
function Sounds.id(name: SoundName): string?
	local def = SOUNDS[name]
	return if def then def.id else nil
end

local function hookButton(inst: Instance)
	if inst:IsA("GuiButton") and not hooked[inst] then
		hooked[inst] = true
		inst.Activated:Connect(function()
			Sounds.play("Tap")
		end)
		inst.Destroying:Connect(function()
			hooked[inst] = nil
		end)
	end
end

-- Call last, after the other UI is built: every button there and every button made later taps. The saved settings
-- apply once, from the first profile summary (later summaries only echo what this client set).
function Sounds.init()
	ProfileState.onChange(function()
		local summary = ProfileState.summary()
		if summary and not loaded then
			loaded = true
			Sounds.set("music", summary.music ~= false)
			Sounds.set("sounds", summary.sounds ~= false)
		end
	end)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	for _, d in playerGui:GetDescendants() do
		hookButton(d)
	end
	playerGui.DescendantAdded:Connect(hookButton)
end

return Sounds
