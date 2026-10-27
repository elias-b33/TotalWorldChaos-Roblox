--!strict
-- Left drawer (docs/DESIGN.md "UI and controls"): every nation with its colour, province count and your relation.

local Players = game:GetService("Players")

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Palette = require(Client.Palette)
local Relations = require(Client.Relations)
local Widgets = require(script.Parent.Widgets)

local Nations = {}

local drawer: Frame
local rows: Frame

local function render()
	if not drawer.Visible then
		return
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
		local dot = Instance.new("Frame")
		dot.Size = UDim2.fromOffset(12, 12)
		dot.BackgroundColor3 = Palette.nation(n.colorIndex)
		dot.BorderSizePixel = 0
		dot.LayoutOrder = 1
		dot.Parent = row
		Widgets.corner(dot, 6)
		local who = if n.id == me then "⭐ " elseif n.controller == "Player" then "👤 " else ""
		local status = if n.eliminated then "☠ " else Relations.icon(me, n.id)
		local label = Widgets.label(
			row,
			string.format("%s%s  🏴%d %s", who, n.name, Relations.provinceCount(n.id), status),
			14,
			24
		)
		label.Size = UDim2.new(1, -18, 1, 0)
		label.LayoutOrder = 2
	end
end

function Nations.toggle()
	drawer.Visible = not drawer.Visible
	render()
end

function Nations.init()
	local gui = Widgets.screen("Nations", 4)
	drawer = Widgets.panel(gui, 230)
	drawer.Name = "Drawer"
	drawer.Position = UDim2.fromOffset(8, 52)
	drawer.Visible = false
	Widgets.list(drawer, false, 4)
	Widgets.label(drawer, "🌍 Nations", 16, 24).LayoutOrder = 0
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
end

return Nations
