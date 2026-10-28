--!strict
-- Results screen (docs/DESIGN.md "Match structure"): who won, how, and the scores, and beside them your XP and
-- Glory for the match with the breakdown and your level bar. The next match starts by itself.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Types = require(ReplicatedStorage.Shared.Types)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Cosmetics = require(Client.Cosmetics)
local Palette = require(Client.Palette)
local ProfileState = require(Client.ProfileState)
local Widgets = require(script.Parent.Widgets)

local HOW = {
	Domination = "👑 Domination: 40% of the world",
	Alliance = "🤝 Alliance victory: 55% together",
	Score = "🏆 Best score when time ran out",
}

-- The reward breakdown's rows (Types.RewardLine.kind).
local LINE_LABELS: { [string]: string } = {
	Finish = "🏁 Finished",
	Placement = "🏆 Place",
	Provinces = "🏴 Provinces taken",
	Battles = "⚔ Battles won",
	Primordial = "✨ Primordial",
	Powers = "⚡ Powers used",
	FirstMatch = "☀ First match today",
	Vip = "💎 VIP",
	CustomRules = "⚙ Custom rules",
	LevelUp = "⬆ Level up",
	RankUp = "👑 Rank up",
}
local GOLD = Color3.fromRGB(255, 210, 90)
local DIM_TEXT = Color3.fromRGB(190, 195, 210)
local RESULTS_WIDTH = 330
local REWARD_WIDTH = 270
local COLUMN_GAP = 12
local PANEL_PADDING = 10 -- Widgets.panel's padding on each side

local Results = {}

local dim: Frame
local panel: Frame
local body: Frame
local rewardBody: Frame
local onShow: (() -> ())? = nil

local function signed(n: number): string
	return (if n >= 0 then "+" else "−") .. tostring(math.abs(n))
end

-- One breakdown row: what, XP, Glory.
local function rewardRow(label: string, xp: string, glory: string, order: number, color: Color3?)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 20)
	row.LayoutOrder = order
	row.Parent = rewardBody
	local cells: { { text: string, x: number, w: number } } = {
		{ text = label, x = 0, w = 0.56 },
		{ text = xp, x = 0.56, w = 0.2 },
		{ text = glory, x = 0.76, w = 0.24 },
	}
	for i, cell in cells do
		local l = Widgets.label(row, cell.text, 14, 20)
		l.Position = UDim2.fromScale(cell.x, 0)
		l.Size = UDim2.fromScale(cell.w, 1)
		l.TextXAlignment = if i == 1 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right
		l.TextColor3 = color or l.TextColor3
	end
end

-- Your level bar: "Lv 2 · Settler", the XP into the level, and a gold fill.
local function levelBar(after: Types.ProfileSummary, order: number)
	local progress = if after.xpForLevel > 0
		then string.format("%d / %d XP", after.xpIntoLevel, after.xpForLevel)
		else "MAX"
	Widgets.label(rewardBody, string.format("Lv %d · %s   %s", after.level, after.rankName, progress), 14, 20).LayoutOrder =
		order
	local bar = Instance.new("Frame")
	bar.Name = "LevelBar"
	bar.Size = UDim2.new(1, 0, 0, 12)
	bar.BackgroundColor3 = Color3.fromRGB(50, 54, 70)
	bar.BorderSizePixel = 0
	bar.LayoutOrder = order + 1
	bar.Parent = rewardBody
	Widgets.corner(bar, 6)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	local share = if after.xpForLevel > 0 then math.clamp(after.xpIntoLevel / after.xpForLevel, 0, 1) else 1
	fill.Size = UDim2.fromScale(share, 1)
	fill.BackgroundColor3 = GOLD
	fill.BorderSizePixel = 0
	fill.Parent = bar
	Widgets.corner(fill, 6)
end

-- Your reward column. Returns false until the server has sent the reward.
local function renderReward(): boolean
	Widgets.clear(rewardBody)
	local report = ProfileState.reward()
	if report == nil then
		return false
	end
	local reward, before, after = report.reward, report.before, report.after
	local header =
		Widgets.label(rewardBody, string.format("%s XP   %s 🏅", signed(reward.xp), signed(reward.glory)), 20, 30)
	header.TextColor3 = GOLD
	header.LayoutOrder = 1
	if reward.afk then
		Widgets.label(rewardBody, "💤 No reward: 5 minutes without an order", 14, 40).LayoutOrder = 2
	end
	for i, l in reward.lines do
		local label = LINE_LABELS[l.kind] or l.kind
		if l.kind == "Placement" and reward.placement then
			label ..= " #" .. reward.placement
		end
		local bonus = l.kind == "LevelUp" or l.kind == "RankUp"
		rewardRow(
			label,
			if l.xp ~= 0 then signed(l.xp) else "",
			if l.glory ~= 0 then signed(l.glory) .. " 🏅" else "",
			2 + i,
			if bonus then GOLD else nil
		)
	end
	local order = 3 + #reward.lines
	local banner = if after.rank > before.rank
		then "👑 New rank: " .. after.rankName .. "!"
		elseif after.level > before.level then "⬆ Level " .. after.level .. "!"
		else nil
	if banner then
		local l = Widgets.label(rewardBody, banner, 16, 26)
		l.TextColor3 = GOLD
		l.LayoutOrder = order
	end
	levelBar(after, order + 1)
	local total = Widgets.label(rewardBody, string.format("🏅 %d Glory", after.glory), 14, 20)
	total.TextColor3 = DIM_TEXT
	total.LayoutOrder = order + 3
	return true
end

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
		if n then -- the nation's flag (cosmetic) at the end of its row
			local flag = Cosmetics.flagLabel(l, Cosmetics.of(n.id).flag, n.colorIndex, UDim2.fromOffset(20, 15))
			flag.AnchorPoint = Vector2.new(1, 0.5)
			flag.Position = UDim2.new(1, -4, 0.5, 0)
		end
	end
	Widgets.label(body, "⏳ Next match starts soon", 14, 22).LayoutOrder = 20
	local hasReward = renderReward()
	rewardBody.Visible = hasReward
	local width = RESULTS_WIDTH + (if hasReward then COLUMN_GAP + REWARD_WIDTH else 0)
	panel.Size = UDim2.fromOffset(width + 2 * PANEL_PADDING, 0)
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
	panel = Widgets.panel(dim, RESULTS_WIDTH + 2 * PANEL_PADDING)
	panel.Name = "Panel"
	panel.BackgroundTransparency = 0
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	-- two columns side by side, short enough for a phone in landscape: the match, then your reward
	local columns = Instance.new("Frame")
	columns.BackgroundTransparency = 1
	columns.Size = UDim2.fromScale(1, 0)
	columns.AutomaticSize = Enum.AutomaticSize.Y
	columns.Parent = panel
	Widgets.list(columns, true, COLUMN_GAP).VerticalAlignment = Enum.VerticalAlignment.Top
	body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Size = UDim2.fromOffset(RESULTS_WIDTH, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.LayoutOrder = 1
	body.Parent = columns
	Widgets.list(body, false, 4)
	rewardBody = Instance.new("Frame")
	rewardBody.Name = "Reward"
	rewardBody.BackgroundTransparency = 1
	rewardBody.Size = UDim2.fromOffset(REWARD_WIDTH, 0)
	rewardBody.AutomaticSize = Enum.AutomaticSize.Y
	rewardBody.LayoutOrder = 2
	rewardBody.Visible = false
	rewardBody.Parent = columns
	Widgets.list(rewardBody, false, 2)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	ClientState.onReset(render)
	ClientState.onDelta(function(delta)
		if delta.result then
			render()
		end
	end)
	ProfileState.onChange(function()
		if dim.Visible then
			render() -- the reward can land just after the result
		end
	end)
end

return Results
