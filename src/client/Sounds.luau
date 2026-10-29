--!strict
-- Every sound the game plays, in one place, plus the mute toggle (the 🔊 button Hud puts at the right end of the
-- top bar, remembered for the session) and a tap sound for every button.
--
-- Stand-ins until the owner picks real sounds: every id is one of the few files every Roblox client ships in
-- content/sounds (the default character sounds: footsteps, jumps, landings, falling, swimming, an explosion, a
-- splash, "oof", "ouch", the volume-slider tick), played at different speeds so each moment sounds different.
-- To use a Creator Store or uploaded sound, put its "rbxassetid://<id>" here (docs/STUDIO.md "Sounds"). A missing
-- file is harmless: Roblox logs it and the game carries on silently.

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local Sounds = {}

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
	| "Ping"

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
	Ping = { id = "rbxasset://sounds/volume_slider.ogg", volume = 0.7, speed = 1.9, gap = 0.5 }, -- an ally's map ping
}

local muted = false -- module state lives as long as the client session, across matches
local instances: { [string]: Sound } = {}
local lastPlayed: { [string]: number } = {}
local muteButton: TextButton? = nil
local showMuted: ((boolean) -> ())? = nil -- draws the mute button's icon (the top bar's pixel icons)
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

-- Play a sound (unless muted, or the same one just started). Never errors.
function Sounds.play(name: SoundName)
	if muted then
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

function Sounds.muted(): boolean
	return muted
end

function Sounds.setMuted(value: boolean)
	muted = value
	if value then
		for _, sound in instances do
			pcall(function()
				sound:Stop()
			end)
		end
	end
	local button = muteButton
	if showMuted then
		showMuted(muted)
	elseif button then
		button.Text = if muted then "🔇" else "🔊"
	end
end

-- The mute toggle: Hud builds the button in the top bar, Sounds keeps its icon in step (through `show` when given,
-- else as the button's text).
function Sounds.attachMuteButton(button: TextButton, show: ((boolean) -> ())?)
	muteButton = button
	showMuted = show
	if show then
		show(muted)
	else
		button.Text = if muted then "🔇" else "🔊"
	end
	button.Activated:Connect(function()
		Sounds.setMuted(not muted)
	end)
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

-- Call last, after the other UI is built: every button there and every button made later taps.
function Sounds.init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	for _, d in playerGui:GetDescendants() do
		hookButton(d)
	end
	playerGui.DescendantAdded:Connect(hookButton)
end

return Sounds
