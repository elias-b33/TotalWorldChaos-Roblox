--!strict
-- Left drawer (docs/DESIGN.md "UI and controls"): every nation with its colour, province count and your relation,
-- and at the bottom the way to your quests during a match (the top bar has no room for another button).

local Players = game:GetService("Players")

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Cosmetics = require(Client.Cosmetics)
local Relations = require(Client.Relations)
local Widgets = require(script.Parent.Widgets)

local Nations = {}

-- The play-streak flame after a player's nation name, by tier (Sim.Login.flameTier): 3, 7, 14 and 30 days.
local FLAMES = { " 🔥", " 🔥🔥", " 💙", " 💙👑" }

local drawer: Frame
local rows: Frame
local questsButton: TextButton? = nil
local questsText: () -> string = function()
	return "📜 Quests"
end

local function render()
	if not drawer.Visible then
		return
	end
	if questsButton then
		questsButton.Text = questsText()
	end
	local snap = ClientState.snapshot()
	Widgets.clear(rows)
	if snap == nil then
		return
	end
	local me = ClientState.myNation()
	local list = table.clone(snap.nations)
	table.sort(list, function(a, b)
		return Relations.score(a.id) > Relations.score(b.id)
	end)
	for i, n in list do
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 24)
		row.LayoutOrder = i
		row.Parent = rows
		Widgets.list(row, true, 6)
		-- the nation's flag (cosmetic), in its colour
		local looks = Cosmetics.of(n.id)
		local flag = Cosmetics.flagLabel(row, looks.flag, n.colorIndex, UDim2.fromOffset(20, 15))
		flag.LayoutOrder = 1
		local who = if n.id == me then "⭐ " elseif n.controller == "Player" then "👤 " else ""
		local status = if n.eliminated then "☠ " else Relations.icon(me, n.id)
		local vip = if looks.vip then " [VIP]" else ""
		local flame = FLAMES[looks.flame or 0] or "" -- play-streak reward (MONETIZATION 5.6)
		local label = Widgets.label(
			row,
			string.format("%s%s%s%s  🏴%d %s", who, n.name, flame, vip, Relations.provinceCount(n.id), status),
			14,
			24
		)
		label.Size = UDim2.new(1, -26, 1, 0)
		label.LayoutOrder = 2
		-- nameplate frame (cosmetic): an outline around the name
		local frameColor = Cosmetics.frameColor(looks.frame)
		if frameColor then
			label.BackgroundTransparency = 0.85
			label.BackgroundColor3 = frameColor
			Widgets.corner(label, 6)
			local stroke = Instance.new("UIStroke")
			stroke.Color = frameColor
			stroke.Thickness = 2
			stroke.Parent = label
		end
	end
end

function Nations.toggle()
	drawer.Visible = not drawer.Visible
	render()
end

-- onQuests: opens the Quests screen; buttonText: its button's text (with the number of quests to claim).
function Nations.init(onQuests: (() -> ())?, buttonText: (() -> string)?)
	local gui = Widgets.screen("Nations", 4)
	drawer = Widgets.panel(gui, 230)
	drawer.Name = "Drawer"
	drawer.Position = UDim2.fromOffset(8, 52)
	drawer.Visible = false
	Widgets.list(drawer, false, 4)
	-- the title, and beside it the way to the quests (in the header: a row under ten nations runs off a phone)
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, if onQuests then Widgets.BUTTON_HEIGHT else 24)
	header.LayoutOrder = 0
	header.Parent = drawer
	Widgets.label(header, "🌍 Nations", 16, if onQuests then Widgets.BUTTON_HEIGHT else 24)
	if onQuests then
		questsText = buttonText or questsText
		local b = Widgets.button(header, questsText(), 116, Color3.fromRGB(120, 90, 40), onQuests)
		b.Name = "QuestsButton"
		b.TextSize = 14
		b.AnchorPoint = Vector2.new(1, 0)
		b.Position = UDim2.fromScale(1, 0)
		questsButton = b
	end
	rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	rows.Size = UDim2.fromScale(1, 0)
	rows.AutomaticSize = Enum.AutomaticSize.Y
	rows.LayoutOrder = 1
	rows.Parent = drawer
	Widgets.list(rows, false, 2)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	ClientState.onReset(render)
	ClientState.onDelta(function(delta)
		if #delta.provinces > 0 or #delta.nations > 0 or delta.diplomacy then
			render()
		end
	end)
	Cosmetics.onChange(render)
end

return Nations
