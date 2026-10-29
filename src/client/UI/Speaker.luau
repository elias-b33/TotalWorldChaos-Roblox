--!strict
-- The speaker's popover (docs/DESIGN.md "Sound and effects", docs/UI_DIRECTION.md 7.9): tapping the top bar's
-- speaker opens a slate plate under it with two 44 px toggles, Music (a note) and Sounds (the speaker), so either
-- takes two taps. A toggle changes at once on this client (Sounds) and is saved in the profile (RequestPreference,
-- Sim.Preferences); the saved settings come back with the Profile remote when the player joins. The popover closes
-- when the speaker is tapped again, or OPEN_SECONDS after the last tap.
-- The popover is a popover: it draws above the cards in the offers column (an event card can stand right under the
-- speaker), so it lives in its own screen over the bar's place rather than in the bar.

local Players = game:GetService("Players")

local Client = script.Parent.Parent
local Intents = require(Client.Intents)
local Sounds = require(Client.Sounds)
local HudLayout = require(script.Parent.HudLayout)
local Icons = require(script.Parent.Icons)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local TOGGLE_WIDTH = 148 -- "Sounds off" and its 16 px icon, centred together
local OPEN_SECONDS = 5 -- the popover closes this long after the last tap
local DISPLAY_ORDER = 6 -- over the offers column (3), the nations drawer and the power picker (4), the tutorial (5)

type Toggle = { setting: Sounds.Setting, name: string, label: string, on: string, off: string }
local TOGGLES: { Toggle } = {
	{ setting = "music", name = "MusicToggle", label = "Music", on = "music", off = "musicOff" },
	{ setting = "sounds", name = "SoundsToggle", label = "Sounds", on = "soundOn", off = "soundOff" },
}

local Speaker = {}

local speaker: TextButton? = nil
local holder: Frame? = nil -- where the bar is, at the bar's scale, in the popover's own screen
local holderScale: UIScale? = nil
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

-- Under the speaker, its right edge on the speaker's (in the bar's own coordinates and scale: the holder copies the
-- bar's place and scale).
local function place()
	local p, button, h, scale = panel, speaker, holder, holderScale
	if p and button and h and scale then
		local bar = button.Parent :: GuiObject
		h.Position = bar.Position
		h.Size = bar.Size
		local barScale = bar:FindFirstChildOfClass("UIScale")
		scale.Scale = if barScale then barScale.Scale else 1
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
	-- like the bar's screen: the screen's own coordinates, Roblox's top-bar row included
	local gui = Widgets.screen("Speaker", DISPLAY_ORDER)
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	local h = Instance.new("Frame")
	h.Name = "BarPlace"
	h.BackgroundTransparency = 1
	h.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = h
	holder, holderScale = h, scale
	local p = Widgets.panel(h, TOGGLE_WIDTH + 20, "plate")
	p.Name = "SpeakerMenu"
	p.AnchorPoint = Vector2.new(1, 0)
	p.Visible = false
	Widgets.list(p, false, Theme.space.s)
	panel = p
	for i, t in TOGGLES do
		-- the kit's icon-and-caption button: a 16 px icon centred with its caption
		local b = Widgets.iconTextButton(p, t.on, t.label .. " on", TOGGLE_WIDTH, Widgets.GOOD, function()
			flip(t)
		end, t.name)
		b.LayoutOrder = i
		icons[t.setting] = b:FindFirstChild("Icon") :: GuiObject
		buttons[t.setting] = b
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
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
