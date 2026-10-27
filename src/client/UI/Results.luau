--!strict
-- Results screen (docs/DESIGN.md "Match structure"): who won, how, and the scores. The next match starts by itself.

local Players = game:GetService("Players")

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Palette = require(Client.Palette)
local Widgets = require(script.Parent.Widgets)

local HOW = {
	Domination = "👑 Domination: 40% of the world",
	Alliance = "🤝 Alliance victory: 55% together",
	Score = "🏆 Best score when time ran out",
}

local Results = {}

local dim: Frame
local panel: Frame
local body: Frame
local onShow: (() -> ())? = nil

local function render()
	local snap = ClientState.snapshot()
	local result = if snap then snap.result else nil
	if result == nil then
		dim.Visible = false
		return
	end
	if not dim.Visible and onShow then
		onShow() -- close sheets and selections so the results stand alone
	end
	Widgets.clear(body)
	local names = {}
	for _, w in result.winners do
		local n = ClientState.nation(w)
		table.insert(names, if n then n.name else "?")
	end
	local me = ClientState.myNation()
	local iWon = table.find(result.winners, me) ~= nil
	Widgets.label(body, (if iWon then "🎉 You win! " else "🏁 ") .. table.concat(names, " & ") .. " won", 22, 32).LayoutOrder =
		1
	Widgets.label(body, HOW[result.kind] or result.kind, 15, 22).LayoutOrder = 2
	for i, s in result.scores do
		if i > 5 then
			break
		end
		local n = ClientState.nation(s.nation)
		local l = Widgets.label(
			body,
			string.format(
				"%d.  %s%s   %d",
				i,
				if s.nation == me then "⭐ " else "",
				if n then n.name else "?",
				s.score
			),
			16,
			24
		)
		l.TextColor3 = if n then Palette.nation(n.colorIndex):Lerp(Color3.new(1, 1, 1), 0.4) else l.TextColor3
		l.LayoutOrder = 2 + i
	end
	Widgets.label(body, "⏳ Next match starts soon", 14, 22).LayoutOrder = 20
	dim.Visible = true
end

function Results.init(showHandler: () -> ())
	onShow = showHandler
	local gui = Widgets.screen("Results", 10)
	-- dim the whole screen behind the results
	dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Active = true -- the map can't be tapped behind the results
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel = 0
	dim.Visible = false
	dim.Parent = gui
	panel = Widgets.panel(dim, 360)
	panel.Name = "Panel"
	panel.BackgroundTransparency = 0
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Size = UDim2.fromScale(1, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Parent = panel
	Widgets.list(body, false, 4)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	ClientState.onReset(render)
	ClientState.onDelta(function(delta)
		if delta.result then
			render()
		end
	end)
end

return Results
