--!strict
-- Results screen (docs/DESIGN.md "Match structure"): who won, how, and the scores, and beside them your XP and
-- Glory for the match with the breakdown and your level bar. The next match starts by itself.
-- Built from the UI kit: a panel with two columns (the match, your reward) and a footer row of buttons (Quests,
-- the season pass, achievements) beside the "next match" note; pixel icons instead of emoji, Fredoka One numbers.
-- Short enough for a phone in landscape (844×390, and 667×375).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Cosmetics = require(Client.Cosmetics)
local Palette = require(Client.Palette)
local ProfileState = require(Client.ProfileState)
local QuestState = require(Client.QuestState)
local Icons = require(script.Parent.Icons)
local Quests = require(script.Parent.Quests)
local Season = require(script.Parent.Season)
local SeasonState = require(Client.SeasonState)
local Trophies = require(script.Parent.Trophies)
local TrophyState = require(Client.TrophyState)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme

-- How the match was won: an icon and a line.
local HOW: { [string]: { icon: string, text: string } } = {
	Domination = {
		icon = "crown",
		text = string.format("Domination: %d%% of the world", math.floor(Config.Win.DominationShare * 100 + 0.5)),
	},
	Alliance = {
		icon = "handshake",
		text = string.format("Alliance victory: %d%% together", math.floor(Config.Win.AllianceShare * 100 + 0.5)),
	},
	Score = { icon = "trophy", text = "Best score when time ran out" },
}

-- The reward breakdown's rows (Types.RewardLine.kind): a pixel icon and a few words.
local LINES: { [string]: { icon: string, text: string } } = {
	Finish = { icon = "flag", text = "Finished" },
	Placement = { icon = "trophy", text = "Place" },
	Provinces = { icon = "castle", text = "Provinces taken" },
	Battles = { icon = "war", text = "Battles won" },
	Primordial = { icon = "sparkles", text = "Primordial" },
	Powers = { icon = "charge", text = "Powers used" },
	FirstMatch = { icon = "blessing", text = "First match today" },
	Vip = { icon = "crown", text = "VIP" },
	CustomRules = { icon = "lock", text = "Private server: half" },
	PaidEarlier = { icon = "clock", text = "Paid when you left" },
	LevelUp = { icon = "up", text = "Level up" },
	RankUp = { icon = "crown", text = "Rank up" },
	Calendar = { icon = "check", text = "Play calendar" },
	Achievement = { icon = "trophy", text = "Achievements" },
}
local XP_ICON, GLORY_ICON = "star", "medal" -- Glory is the 🏅 of the shop and the Lobby

local MAX_SCORES = 5 -- nations listed
local MAX_QUEST_LINES = 3 -- quests the match moved, shown under the scores
local MATCH_WIDTH = 316
local REWARD_WIDTH = 280
local COLUMN_GAP = Theme.space.xl
local PANEL_WIDTH = MATCH_WIDTH + COLUMN_GAP + REWARD_WIDTH + 2 * Widgets.PANEL_PAD -- inside the frame
local ROW_HEIGHT = 26 -- a nation's row in the standings
local LINE_HEIGHT = 18 -- a breakdown or quest line
local LEVEL_HEIGHT = 24 -- the level line over the level bar
local PROGRESS_WIDTH = 100 -- "1234 / 5678 XP" beside the level bar
local RANK_WIDTH = 22
local FLAG_SIZE = Vector2.new(20, 15)
local SCORE_WIDTH = 56
local NUMBER_WIDTH = 56 -- the XP and Glory columns of the breakdown
local SMALL_ICON = 16 -- icons beside small text (whole pixels: the 16×16 sprites at 1×)
local QUESTS_WIDTH, QUESTS_SHORT_WIDTH, SEASON_WIDTH = 210, 132, 172

local Results = {}

local dim: Frame
local panel: Frame
local panelScale: UIScale
local body: Frame
local rewardBody: Frame
local footer: Frame
local onShow: (() -> ())? = nil

local function signed(n: number): string
	return (if n >= 0 then "+" else "−") .. tostring(math.abs(n))
end

-- A line of small text with a 16 px pixel icon in front, LINE_HEIGHT tall, cut short with "…" if too long.
local function iconLine(parent: Instance, icon: string, text: string, order: number, color: Color3?): TextLabel
	local l = Widgets.label(parent, text, Theme.text.small, LINE_HEIGHT)
	l.TextWrapped = false
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.TextColor3 = color or Theme.color.text
	l.LayoutOrder = order
	Widgets.leadIcon(l, icon, SMALL_ICON)
	return l
end

-- A caption from another screen ("📜 Quests · 1 to claim", "🎟 Season · tier 3") on a kit button: its leading emoji
-- becomes the button's pixel icon, or `fallback` where there is no pixel icon for it (the emoji is dropped either way).
local function caption(button: TextButton, text: string, fallback: string)
	local icon, rest = Icons.split(text)
	if icon == nil then
		rest = (string.gsub(text, "^[^%w%p%s]+%s*", ""))
	end
	local mark = button:FindFirstChild("Icon")
	if mark and mark:IsA("GuiObject") then
		Icons.set(mark, icon or fallback)
	end
	button.Text = rest
end

-- One breakdown row: an icon and what, then the XP and the Glory it paid (under the column icons).
local function rewardRow(kind: string, label: string, xp: string, glory: string, order: number, color: Color3?)
	local row = Instance.new("Frame")
	row.Name = "Line_" .. kind
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, LINE_HEIGHT)
	row.LayoutOrder = order
	row.Parent = rewardBody
	local what = iconLine(row, (LINES[kind] or { icon = "star" }).icon, label, 0, color)
	what.Size = UDim2.new(1, -2 * NUMBER_WIDTH, 1, 0)
	for i, value in { xp, glory } do
		local n = Widgets.label(row, value, Theme.text.small, LINE_HEIGHT)
		n.FontFace = Theme.font.display
		n.TextXAlignment = Enum.TextXAlignment.Right
		n.TextColor3 = color or Theme.color.text
		n.AnchorPoint = Vector2.new(1, 0)
		n.Position = UDim2.new(1, -(2 - i) * NUMBER_WIDTH, 0, 0)
		n.Size = UDim2.fromOffset(NUMBER_WIDTH, LINE_HEIGHT)
	end
end

-- The icons over the breakdown's XP and Glory columns.
local function columnHeads(order: number)
	local row = Instance.new("Frame")
	row.Name = "Heads"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, SMALL_ICON)
	row.LayoutOrder = order
	row.Parent = rewardBody
	for i, icon in { XP_ICON, GLORY_ICON } do
		local mark = Widgets.icon(row, icon, SMALL_ICON)
		mark.AnchorPoint = Vector2.new(1, 0)
		mark.Position = UDim2.new(1, -(2 - i) * NUMBER_WIDTH, 0, 0)
	end
end

-- Your reward column. Returns false until the server has sent the reward.
local function renderReward(): boolean
	Widgets.clear(rewardBody)
	local report = ProfileState.reward()
	if report == nil then
		return false
	end
	local reward, before, after = report.reward, report.before, report.after
	-- the match's XP and Glory, each a chip
	local totals = Instance.new("Frame")
	totals.Name = "Totals"
	totals.BackgroundTransparency = 1
	totals.Size = UDim2.new(1, 0, 0, Theme.size.chip)
	totals.LayoutOrder = 1
	totals.Parent = rewardBody
	Widgets.list(totals, true, Theme.space.s)
	local xpChip = Widgets.chip(totals, XP_ICON, signed(reward.xp) .. " XP")
	xpChip.Name = "XP"
	xpChip.TextColor3 = Theme.color.gold
	local gloryChip = Widgets.chip(totals, GLORY_ICON, signed(reward.glory) .. " Glory")
	gloryChip.Name = "Glory"
	gloryChip.TextColor3 = Theme.color.gold
	gloryChip.LayoutOrder = 1
	if reward.afk then
		local idle = string.format("No reward: no orders for %d min", Config.Progression.AfkTicks // 60)
		iconLine(rewardBody, "clock", idle, 2, Theme.color.warn).Name = "Afk"
	end
	if #reward.lines > 0 then
		columnHeads(3)
	end
	local quests = QuestState.view()
	for i, l in reward.lines do
		local text = (LINES[l.kind] or { text = l.kind }).text
		if l.kind == "Placement" and reward.placement then
			text ..= " #" .. reward.placement
		end
		if l.kind == "Calendar" and quests then
			text ..= " " .. quests.calendar.step .. "/" .. #quests.calendar.glory
		end
		local bonus = l.kind == "LevelUp" or l.kind == "RankUp"
		rewardRow(
			l.kind,
			text,
			if l.xp ~= 0 then signed(l.xp) else "",
			if l.glory ~= 0 then signed(l.glory) else "",
			3 + i,
			if bonus then Theme.color.gold else nil
		)
	end
	local order = 4 + #reward.lines
	-- your level ("Lv 2 · Settler"; in gold "Level 2! · Settler" after a level-up, "New rank: Baron!" after a
	-- rank-up), then the level bar with the XP into the level beside it
	local rankUp, levelUp = after.rank > before.rank, after.level > before.level
	local headline = if rankUp
		then string.format("New rank: %s!", after.rankName)
		elseif levelUp then string.format("Level %d! · %s", after.level, after.rankName)
		else string.format("Lv %d · %s", after.level, after.rankName)
	local level = Widgets.label(rewardBody, headline, Theme.text.body, LEVEL_HEIGHT)
	level.Name = "Level"
	level.FontFace = Theme.font.display
	level.TextWrapped = false
	level.TextTruncate = Enum.TextTruncate.AtEnd
	level.TextColor3 = if rankUp or levelUp then Theme.color.gold else Theme.color.text
	level.LayoutOrder = order
	Widgets.leadIcon(level, if rankUp then "crown" else "up", Theme.size.icon)
	local barRow = Instance.new("Frame")
	barRow.Name = "LevelBar"
	barRow.BackgroundTransparency = 1
	barRow.Size = UDim2.new(1, 0, 0, LINE_HEIGHT)
	barRow.LayoutOrder = order + 1
	barRow.Parent = rewardBody
	local bar = Widgets.progress(barRow, nil, 12, Theme.color.gold)
	bar.AnchorPoint = Vector2.new(0, 0.5)
	bar.Position = UDim2.fromScale(0, 0.5)
	bar.Size = UDim2.new(1, -(PROGRESS_WIDTH + Theme.space.m), 0, 12)
	Widgets.setProgress(bar, if after.xpForLevel > 0 then math.clamp(after.xpIntoLevel / after.xpForLevel, 0, 1) else 1)
	local progress = Widgets.label(
		barRow,
		if after.xpForLevel > 0 then string.format("%d / %d XP", after.xpIntoLevel, after.xpForLevel) else "MAX",
		Theme.text.small,
		LINE_HEIGHT
	)
	progress.Name = "Progress"
	progress.TextXAlignment = Enum.TextXAlignment.Right
	progress.TextWrapped = false
	progress.AnchorPoint = Vector2.new(1, 0)
	progress.Position = UDim2.fromScale(1, 0)
	progress.Size = UDim2.fromOffset(PROGRESS_WIDTH, LINE_HEIGHT)
	local total =
		iconLine(rewardBody, GLORY_ICON, string.format("%d Glory", after.glory), order + 2, Theme.color.textDim)
	total.Name = "GloryTotal"
	return true
end

-- Under the scores: the quests this match moved (finished ones first) and the achievements it unlocked. Returns
-- false before the server has sent the quests.
local function renderQuests(hasReward: boolean): boolean
	local view = QuestState.view()
	if view == nil then
		return false
	end
	if hasReward then
		local moved: { Types.QuestEntry } = {}
		for _, list in { view.daily, view.weekly } do
			for _, q in list do
				if view.gains[q.key] then
					table.insert(moved, q)
				end
			end
		end
		table.sort(moved, function(a, b)
			return (a.progress >= a.target) and not (b.progress >= b.target)
		end)
		-- achievements this match unlocked: one line, in place of the last quest line
		local unlocked = {}
		local trophies = TrophyState.achievements()
		for _, a in if trophies then trophies.list else {} do
			if table.find(trophies and trophies.recent or {}, a.id) then
				table.insert(unlocked, a.name)
			end
		end
		if #unlocked > 0 then
			local l = iconLine(body, "trophy", "Unlocked: " .. table.concat(unlocked, ", "), 29, Theme.color.gold)
			l.Name = "Unlocked"
		end
		for i = 1, math.min(#moved, MAX_QUEST_LINES - (if #unlocked > 0 then 1 else 0)) do
			local q = moved[i]
			local done = q.progress >= q.target
			local text = if done
				then Quests.text(q) .. ": done!"
				else string.format("%s  %d/%d", Quests.text(q), q.progress, q.target)
			iconLine(
				body,
				if done then "check" else "scroll",
				text,
				20 + i,
				if done then Theme.color.gold else Theme.color.textDim
			)
		end
	end
	return true
end

-- The footer: Quests (with what there is to claim), the season pass while a season runs, the achievements, and the
-- note that the next match starts by itself.
local function renderFooter(hasQuests: boolean)
	Widgets.clear(footer)
	local used = 0
	if hasQuests then
		local seasonOn = SeasonState.active()
		-- beside the season pass, the short caption ("Quests (1)") keeps the row on a small phone
		local width = if seasonOn then QUESTS_SHORT_WIDTH else QUESTS_WIDTH
		local quests = Widgets.iconTextButton(footer, "scroll", "", width, Widgets.GOLD, Quests.open, "QuestsButton")
		quests.TextSize = Theme.text.small
		caption(quests, if seasonOn then Quests.shortButtonText() else Quests.buttonText(), "scroll")
		used += width + Theme.space.m
		if seasonOn then
			local season = Widgets.iconTextButton(footer, "star", "", SEASON_WIDTH, Widgets.SPECIAL, Season.open)
			season.Name = "SeasonButton"
			season.TextSize = Theme.text.small
			season.LayoutOrder = 1
			caption(season, Season.buttonText(), "star")
			used += SEASON_WIDTH + Theme.space.m
		end
		local trophies = Widgets.iconButton(footer, "trophy", "TrophiesButton", nil, Widgets.BUTTON, function()
			Trophies.open("Achievements")
		end)
		trophies.LayoutOrder = 2
		used += Widgets.BUTTON_HEIGHT + Theme.space.m
	end
	local note = Widgets.hint(footer, "Next match starts soon", Theme.text.small, Widgets.BUTTON_HEIGHT)
	note.Name = "NextMatch"
	note.Size = UDim2.new(1, -used, 1, 0)
	note.LayoutOrder = 3
	Widgets.leadIcon(note, "hourglass", SMALL_ICON)
end

-- One nation's row in the standings: rank, flag, name (in its colour), a crown for the winners, and the score. Your
-- own row sits on a raised card.
local function scoreRow(i: number, nationId: number, score: number, winner: boolean, mine: boolean)
	local n = ClientState.nation(nationId)
	local row = Instance.new("Frame")
	row.Name = "Score" .. i
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundColor3 = Theme.color.navyRaised
	row.BackgroundTransparency = if mine then 0 else 1
	row.BorderSizePixel = 0
	row.LayoutOrder = 2 + i
	row.Parent = body
	if mine then
		Widgets.corner(row, Theme.radius.s)
	end
	local rank = Widgets.label(row, tostring(i), Theme.text.body, ROW_HEIGHT)
	rank.FontFace = Theme.font.display
	rank.TextXAlignment = Enum.TextXAlignment.Center
	rank.TextColor3 = if i == 1 then Theme.color.gold else Theme.color.textDim
	rank.Size = UDim2.fromOffset(RANK_WIDTH, ROW_HEIGHT)
	local x = RANK_WIDTH + Theme.space.xs
	if n then -- the nation's flag (cosmetic)
		local flag =
			Cosmetics.flagLabel(row, Cosmetics.of(n.id).flag, n.colorIndex, UDim2.fromOffset(FLAG_SIZE.X, FLAG_SIZE.Y))
		flag.AnchorPoint = Vector2.new(0, 0.5)
		flag.Position = UDim2.new(0, x, 0.5, 0)
	end
	x += FLAG_SIZE.X + Theme.space.s
	local name = Widgets.label(row, if n then n.name else "?", Theme.text.body, ROW_HEIGHT)
	name.Name = "Name"
	name.TextWrapped = false
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.TextColor3 = if n then Palette.nation(n.colorIndex):Lerp(Theme.color.text, 0.35) else Theme.color.text
	name.Position = UDim2.fromOffset(x, 0)
	name.Size = UDim2.new(1, -(x + SCORE_WIDTH + SMALL_ICON + Theme.space.xs), 1, 0)
	if winner then
		local crown = Widgets.icon(row, "crown", SMALL_ICON)
		crown.AnchorPoint = Vector2.new(1, 0.5)
		crown.Position = UDim2.new(1, -(SCORE_WIDTH + 2), 0.5, 0)
	end
	local points = Widgets.label(row, tostring(score), Theme.text.body, ROW_HEIGHT)
	points.FontFace = Theme.font.display
	points.TextXAlignment = Enum.TextXAlignment.Right
	points.AnchorPoint = Vector2.new(1, 0)
	points.Position = UDim2.new(1, -Theme.space.s, 0, 0)
	points.Size = UDim2.fromOffset(SCORE_WIDTH - Theme.space.s, ROW_HEIGHT)
end

local function clearAll()
	Widgets.clear(body)
	Widgets.clear(rewardBody)
	Widgets.clear(footer)
end

-- An unusually long breakdown on a short screen: shrink the panel until it fits (the usual rewards fit 667×375 at
-- full size).
local function fitPanel()
	local available = dim.AbsoluteSize.Y - 2 * Theme.space.m
	local height = panel.AbsoluteSize.Y / panelScale.Scale
	local scale = if available > 0 and height > available then available / height else 1
	if math.abs(panelScale.Scale - scale) > 0.001 then
		panelScale.Scale = scale
	end
end

local function render()
	local snap = ClientState.snapshot()
	local result = if snap then snap.result else nil
	if result == nil then
		dim.Visible = false
		clearAll() -- a hidden screen keeps nothing (rebuilt when the next match ends): fewer GUI objects
		return
	end
	if not dim.Visible and onShow then
		onShow() -- close sheets and selections so the results stand alone
	end
	clearAll()
	local names = {}
	for _, w in result.winners do
		local n = ClientState.nation(w)
		table.insert(names, if n then n.name else "?")
	end
	local me = ClientState.myNation()
	local iWon = table.find(result.winners, me) ~= nil
	local heading = Widgets.title(
		body,
		if iWon then "You win!" else table.concat(names, " & ") .. " won",
		if iWon then Theme.text.hero else Theme.text.title,
		34
	)
	heading.Name = "Winner"
	heading.LayoutOrder = 1
	Widgets.leadIcon(heading, if iWon then "trophy" else "flag", Theme.icon.small)
	local how = HOW[result.kind] or { icon = "flag", text = result.kind }
	local howLine = Widgets.label(body, how.text, Theme.text.body, 22)
	howLine.Name = "How"
	howLine.LayoutOrder = 2
	Widgets.leadIcon(howLine, how.icon, Theme.size.icon)
	for i, s in result.scores do
		if i > MAX_SCORES then
			break
		end
		scoreRow(i, s.nation, s.score, table.find(result.winners, s.nation) ~= nil, s.nation == me)
	end
	local hasReward = renderReward()
	local hasQuests = renderQuests(hasReward)
	renderFooter(hasQuests)
	rewardBody.Visible = hasReward
	local width = PANEL_WIDTH - (if hasReward then 0 else COLUMN_GAP + REWARD_WIDTH)
	panel.Size = UDim2.fromOffset(width, 0)
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
	dim.BackgroundColor3 = Theme.color.navyDeep
	dim.BackgroundTransparency = 0.35
	dim.BorderSizePixel = 0
	dim.Visible = false
	dim.Parent = gui
	panel = Widgets.panel(dim, PANEL_WIDTH, "brass")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	Widgets.list(panel, false, Theme.space.m)
	panelScale = Instance.new("UIScale")
	panelScale.Parent = panel
	panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitPanel)
	dim:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitPanel)
	-- two columns side by side, short enough for a phone in landscape: the match, then your reward
	local columns = Instance.new("Frame")
	columns.Name = "Columns"
	columns.BackgroundTransparency = 1
	columns.Size = UDim2.fromScale(1, 0)
	columns.AutomaticSize = Enum.AutomaticSize.Y
	columns.Parent = panel
	Widgets.list(columns, true, COLUMN_GAP).VerticalAlignment = Enum.VerticalAlignment.Top
	body = Instance.new("Frame")
	body.Name = "Match"
	body.BackgroundTransparency = 1
	body.Size = UDim2.fromOffset(MATCH_WIDTH, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.LayoutOrder = 1
	body.Parent = columns
	Widgets.list(body, false, 2)
	rewardBody = Instance.new("Frame")
	rewardBody.Name = "Reward"
	rewardBody.BackgroundTransparency = 1
	rewardBody.Size = UDim2.fromOffset(REWARD_WIDTH, 0)
	rewardBody.AutomaticSize = Enum.AutomaticSize.Y
	rewardBody.LayoutOrder = 2
	rewardBody.Visible = false
	rewardBody.Parent = columns
	Widgets.list(rewardBody, false, 2)
	-- the buttons and the "next match" note, across the whole panel
	footer = Instance.new("Frame")
	footer.Name = "Footer"
	footer.BackgroundTransparency = 1
	footer.Size = UDim2.new(1, 0, 0, Widgets.BUTTON_HEIGHT)
	footer.LayoutOrder = 1
	footer.Parent = panel
	Widgets.list(footer, true, Theme.space.m)
	Widgets.fitScreen(gui) -- tablets: the screen's roots grow with the UI's scale
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
	QuestState.onChange(function()
		if dim.Visible then
			render() -- quest progress arrives with the reward
		end
	end)
	SeasonState.onChange(function()
		if dim.Visible then
			render() -- season XP arrives with the reward
		end
	end)
	TrophyState.onChange(function()
		if dim.Visible then
			render() -- achievements unlocked by the match arrive with the reward
		end
	end)
end

return Results
