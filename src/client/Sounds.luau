--!strict
-- Every sound the game plays, in one place, plus the mute toggle (the 🔊 button Hud puts at the right end of the
-- top bar, remembered for the session) and a tap sound for every button.
--
-- Only sounds that ship inside every Roblox client (rbxasset://sounds/...) are used, so nothing has to be uploaded.
-- They can't be checked outside Studio: play each one once in Studio (see docs/DESIGN.md "Sound and effects") and
-- swap any id that is missing or sounds wrong. A missing file is harmless: Roblox logs "Failed to load sound" and
-- the game carries on silently. To use an uploaded sound later, put its "rbxassetid://<id>" here.

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

-- id: the file; volume 0..1; gap: seconds before the same sound may start again (a burst of battles plays once).
local SOUNDS: { [string]: { id: string, volume: number, gap: number } } = {
	Tap = { id = "rbxasset://sounds/clickfast.wav", volume = 0.35, gap = 0.05 },
	BattleStart = { id = "rbxasset://sounds/swordlunge.wav", volume = 0.45, gap = 0.4 },
	BattleEnd = { id = "rbxasset://sounds/swordslash.wav", volume = 0.45, gap = 0.4 },
	ArmyDestroyed = { id = "rbxasset://sounds/collide.wav", volume = 0.5, gap = 0.4 },
	Capture = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.45, gap = 0.3 },
	Lost = { id = "rbxasset://sounds/uuhhh.mp3", volume = 0.4, gap = 1 },
	MeteorFall = { id = "rbxasset://sounds/Rocket whoosh 01.wav", volume = 0.6, gap = 0.2 },
	MeteorImpact = { id = "rbxasset://sounds/Rocket shot.wav", volume = 0.7, gap = 0.2 },
	Plague = { id = "rbxasset://sounds/splat.wav", volume = 0.5, gap = 0.5 },
	Rebels = { id = "rbxasset://sounds/unsheath.wav", volume = 0.55, gap = 0.5 },
	Earthquake = { id = "rbxasset://sounds/HalloweenThunder.wav", volume = 0.6, gap = 0.5 },
	Blessing = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.5, gap = 0.5 },
	Shield = { id = "rbxasset://sounds/swoosh.wav", volume = 0.5, gap = 0.5 },
	War = { id = "rbxasset://sounds/unsheath.wav", volume = 0.6, gap = 1 },
	Cataclysm = { id = "rbxasset://sounds/HalloweenThunder.wav", volume = 0.7, gap = 1 },
	Results = { id = "rbxasset://sounds/victory.wav", volume = 0.6, gap = 1 },
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
