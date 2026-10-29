--!strict
-- The speaker's popover (docs/DESIGN.md "Sound and effects", docs/UI_DIRECTION.md 7.9): tapping the top bar's
-- speaker opens a slate plate under it with two 44 px toggles, Music (a note) and Sounds (the speaker), so either
-- takes two taps. A toggle changes at once on this client (Sounds) and is saved in the profile (RequestPreference,
-- Sim.Preferences); the saved settings come back with the Profile remote when the player joins. The popover closes
-- when the speaker is tapped again, or OPEN_SECONDS after the last tap.

local Client = script.Parent.Parent
local Intents = require(Client.Intents)
local Sounds = require(Client.Sounds)
local HudLayout = require(script.Parent.HudLayout)
local Icons = require(script.Parent.Icons)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local TOGGLE_WIDTH = 148 -- "Sounds off" beside a 32 px icon
local OPEN_SECONDS = 5 -- the popover closes this long after the last tap

type Toggle = { setting: Sounds.Setting, name: string, label: string, on: string, off: string }
local TOGGLES: { Toggle } = {
	{ setting = "music", name = "MusicToggle", label = "Music", on = "music", off = "musicOff" },
	{ setting = "sounds", name = "SoundsToggle", label = "Sounds", on = "soundOn", off = "soundOff" },
}

local Speaker = {}

local speaker: TextButton? = nil
local panel: Frame? = nil
local buttons: { [string]: TextButton } = {}
local icons: { [string]: GuiObject } = {}
local serial = 0

-- Green with its icon when on, slate with the crossed-out icon when off.
local function refresh()
	for _, t in TOGGLES do
		local b, icon = buttons[t.setting], icons[t.setting]
		if b and icon then
			local on = Sounds.enabled(t.setting)
			b.Text = t.label .. (if on then " on" else " off")
			b:SetAttribute("On", on)
			Widgets.setEnabled(b, true, if on then Widgets.GOOD else Widgets.BUTTON_OFF)
			Icons.set(icon, if on then t.on else t.off)
		end
	end
end

-- Under the speaker, its right edge on the speaker's (in the bar's own coordinates and scale).
local function place()
	local p, button = panel, speaker
	if p and button then
		local bar = button.Parent :: GuiObject
		local right = button.Position.X.Offset + button.Size.X.Offset - bar.Size.X.Offset
		p.Position = UDim2.new(1, right, 0, HudLayout.ITEM + Theme.space.s)
	end
end

local function setOpen(open: boolean)
	local p = panel
	if p == nil then
		return
	end
	serial += 1
	p.Visible = open
	if open then
		place()
		refresh()
		local mine = serial
		task.delay(OPEN_SECONDS, function()
			if serial == mine then
				p.Visible = false
			end
		end)
	end
end

local function flip(t: Toggle)
	local on = not Sounds.enabled(t.setting)
	Sounds.set(t.setting, on)
	Intents.preference(t.setting, on)
	refresh()
	setOpen(true) -- the clock starts again
end

-- Build the popover for the speaker button (Hud's, Name Mute) and open it from there.
function Speaker.attach(button: TextButton)
	speaker = button
	local p = Widgets.panel(button.Parent :: Instance, TOGGLE_WIDTH + 20, "plate")
	p.Name = "SpeakerMenu"
	p.AnchorPoint = Vector2.new(1, 0)
	p.Visible = false
	Widgets.list(p, false, Theme.space.s)
	panel = p
	for i, t in TOGGLES do
		local b = Widgets.button(p, "", TOGGLE_WIDTH, Widgets.GOOD, function()
			flip(t)
		end)
		b.Name = t.name
		b.LayoutOrder = i
		b.TextXAlignment = Enum.TextXAlignment.Left
		Widgets.padding(b, Theme.space.s, 0)
		icons[t.setting] = Widgets.leadIcon(b, t.on, Theme.size.iconButton, Theme.space.s)
		buttons[t.setting] = b
	end
	refresh()
	button.Activated:Connect(function()
		setOpen(not p.Visible)
	end)
	Sounds.onSettings(refresh) -- the saved settings arrived
	HudLayout.onChange(function()
		task.defer(place) -- after the bar has laid itself out again
	end)
end

-- Is the popover open?
function Speaker.isOpen(): boolean
	local p = panel
	return p ~= nil and p.Visible
end

return Speaker
