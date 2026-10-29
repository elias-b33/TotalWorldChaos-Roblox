--!strict
-- Results screen (docs/DESIGN.md "Match structure", docs/UI_DIRECTION.md 7.13): who won, how, and the scores, and
-- beside them your XP and Glory for the match with the breakdown and your level bar. The next match starts by
-- itself.
-- The moment of the match: a gold ribbon on the brass window's top edge ("YOU WIN!" with a trophy, or "<winners>
-- WON" with a flag) over a turning sunburst, the standings with your row raised, two reward cells that count up,
-- the breakdown in a recessed well, the level bar filling, and a footer of buttons (Quests, the season pass,
-- achievements) beside the "next match" note and your Glory.
-- Short enough for a phone in landscape (844×390, and 667×375): the window hangs from a fixed line near the top of
-- the screen (Theme.results.ribbonY, where Effects' MATCH OVER banner also pops) and shrinks to fit (fitPanel) when a
-- long breakdown would run off the bottom.
-- Room to grow (docs/NEXT_FEATURES.md section 5, the match replay and awards): the window's "Pages" holds one page,
-- "Rewards", today's two columns; a "Match" page goes beside it, and its tabs ride the window's top edge in the
-- "Header" row right of the ribbon. The footer is shared by both.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

ReplicatedStorage:WaitForChild("Shared")
local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Cosmetics = require(Client.Cosmetics)
local Palette = require(Client.Palette)
local ProfileState = require(Client.ProfileState)
local QuestState = require(Client.QuestState)
local Frames = require(script.Parent.Frames)
local Icons = require(script.Parent.Icons)
local Quests = require(script.Parent.Quests)
local Season = require(script.Parent.Season)
local SeasonState = require(Client.SeasonState)
local TextWidth = require(Client.TextWidth)
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
local WINDOW_WIDTH = 680 -- at most; a small phone gets its width less the margins (the left column gives way)
local REWARD_WIDTH = 306 -- the right column: two reward cells, the breakdown well
local COLUMN_GAP = Theme.space.xl
local CONTENT_TOP = 30 -- the columns start under the ribbon's tails
local SECTION_GAP = Theme.space.xs
local PANEL_GAP = Theme.space.s -- between the pages and the footer
local BOTTOM_PAD = 12 -- the brass frame's bottom border
local ROW_HEIGHT = 28 -- a nation's row in the standings
local HOW_HEIGHT = 22
local LINE_HEIGHT = 20 -- a quest line under the standings
local BREAKDOWN_ROW = 16 -- a breakdown line (its 16 px icon fills it: no half pixels)
local BREAKDOWN_PAD = Theme.space.xs -- inside its well, above and below
local LEVEL_HEIGHT = 20 -- the level line over the level bar
local BAR_HEIGHT = 14
local PROGRESS_WIDTH = 104 -- "1234 / 5678 XP" beside the level bar
local RANK_WIDTH = 22
local MARKER = 3 -- the gold marker on your row's left
local FLAG_SIZE = Vector2.new(20, 15)
local SCORE_WIDTH = 56
local NUMBER_WIDTH = 50 -- the XP and Glory columns of the breakdown
local CELL_GAP = Theme.space.s
local CELL_WIDTH = (REWARD_WIDTH - CELL_GAP) // 2
local SMALL_ICON = 16 -- icons beside small text (whole pixels: the 16×16 sprites at 1×)
local QUESTS_WIDTH, QUESTS_SHORT_WIDTH, SEASON_WIDTH = 214, 158, 176
local NAME_LIGHTEN = 0.18 -- nation names in their colour, lightened
local WHITE = Color3.new(1, 1, 1)

-- The moment (docs/UI_DIRECTION.md 6.8): the reward cells count up from 0 after a short wait, the level bar fills,
-- a level-up line stamps in, the sunburst turns, and the ribbon's shine sweeps once Effects' MATCH OVER banner over
-- it has gone.
local COUNT_DELAY = 0.3
local COUNT_SECONDS = 0.8
local FILL_SECONDS = 0.6
local STAMP_FROM = 1.4
local SHINE_DELAY = 2.1
local SUNBURST_SHOWN = 640 -- the 64 px rays at 10× (an integer scale): they fan out over the window's top edge
local SUNBURST_TRANSPARENCY = 0.6
local SUNBURST_TURN = 6 -- degrees a second

local Results = {}

local dim: Frame
local panel: Frame
local panelScale: UIScale
local ribbon: TextLabel
local sunburst: ImageLabel
local sunImage: EditableImage? = nil
local pages: Frame
local columns: Frame
local body: Frame
local rewardBody: Frame
local footer: Frame
local onShow: (() -> ())? = nil

-- The count-up runs once per reward (render() runs again whenever quests, the season or achievements arrive).
type Count = {
	report: Types.RewardReport?,
	started: number,
	xp: TextLabel?,
	glory: TextLabel?,
	bar: Frame?,
	level: TextLabel?,
	fillFrom: number,
	fillTo: number,
	stamp: boolean,
	stamped: boolean,
}
local count: Count = {
	report = nil,
	started = 0,
	xp = nil,
	glory = nil,
	bar = nil,
	level = nil,
	fillFrom = 0,
	fillTo = 0,
	stamp = false,
	stamped = false,
}

local function signed(n: number): string
	return (if n >= 0 then "+" else "−") .. tostring(math.abs(n))
end

local function quadOut(t: number): number
	return 1 - (1 - t) * (1 - t)
end

-- A line of small text with a 16 px pixel icon in front, `height` tall, cut short with "…" if too long.
local function iconLine(
	parent: Instance,
	icon: string,
	text: string,
	order: number,
	color: Color3?,
	height: number?
): TextLabel
	local l = Widgets.label(parent, text, Theme.text.small, height or LINE_HEIGHT)
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

-- The reward's numbers at this moment of the count-up (all of them at once under reduced motion).
local function stepCount(): boolean
	local report = count.report
	if report == nil then
		return true
	end
	local t = os.clock() - count.started
	local reduced = Widgets.reducedMotion()
	local k = if reduced then 1 else quadOut(math.clamp((t - COUNT_DELAY) / COUNT_SECONDS, 0, 1))
	if count.xp then
		count.xp.Text = signed(math.floor(report.reward.xp * k + 0.5))
	end
	if count.glory then
		count.glory.Text = signed(math.floor(report.reward.glory * k + 0.5))
	end
	if count.bar then
		local f = if reduced then 1 else quadOut(math.clamp((t - COUNT_DELAY) / FILL_SECONDS, 0, 1))
		Widgets.setProgress(count.bar, count.fillFrom + (count.fillTo - count.fillFrom) * f)
	end
	local done = reduced or t >= COUNT_DELAY + COUNT_SECONDS
	-- a level-up (or rank-up) line stamps in once the numbers have landed
	if done and count.stamp and not count.stamped then
		count.stamped = true
		local level = count.level
		if level and not reduced then
			local scale = Instance.new("UIScale")
			scale.Scale = STAMP_FROM
			scale.Parent = level
			TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = 1,
			}):Play()
		end
	end
	return done
end

-- One breakdown row: an icon and what, then the XP and the Glory it paid (under the column icons).
local function rewardRow(
	parent: Instance,
	kind: string,
	label: string,
	xp: string,
	glory: string,
	order: number,
	color: Color3?
)
	local row = Instance.new("Frame")
	row.Name = "Line_" .. kind
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, BREAKDOWN_ROW)
	row.LayoutOrder = order
	row.Parent = parent
	local what = iconLine(row, (LINES[kind] or { icon = "star" }).icon, label, 0, color, BREAKDOWN_ROW)
	what.Size = UDim2.new(1, -2 * NUMBER_WIDTH, 1, 0)
	for i, value in { xp, glory } do
		local n = Widgets.label(row, value, Theme.text.small, BREAKDOWN_ROW)
		n.FontFace = Theme.font.display
		n.TextXAlignment = Enum.TextXAlignment.Right
		n.TextWrapped = false
		n.TextColor3 = color or Theme.color.text
		n.AnchorPoint = Vector2.new(1, 0)
		n.Position = UDim2.new(1, -(2 - i) * NUMBER_WIDTH, 0, 0)
		n.Size = UDim2.fromOffset(NUMBER_WIDTH, BREAKDOWN_ROW)
		Widgets.textStroke(n)
	end
end

-- The icons over the breakdown's XP and Glory columns.
local function columnHeads(parent: Instance, order: number)
	local row = Instance.new("Frame")
	row.Name = "Heads"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, SMALL_ICON)
	row.LayoutOrder = order
	row.Parent = parent
	for i, icon in { XP_ICON, GLORY_ICON } do
		local mark = Widgets.icon(row, icon, SMALL_ICON)
		mark.AnchorPoint = Vector2.new(1, 0)
		mark.Position = UDim2.new(1, -(2 - i) * NUMBER_WIDTH, 0, 0)
	end
end

-- Your reward column. Returns false until the server has sent the reward.
local function renderReward(): boolean
	Widgets.clear(rewardBody)
	count.xp, count.glory, count.bar, count.level = nil, nil, nil, nil
	local report = ProfileState.reward()
	if report == nil then
		return false
	end
	local reward, before, after = report.reward, report.before, report.after
	local rankUp, levelUp = after.rank > before.rank, after.level > before.level
	if count.report ~= report then -- a new reward: count it up from 0
		count.report = report
		count.started = os.clock()
		count.stamp = rankUp or levelUp
		count.stamped = false
	end
	-- the match's XP and Glory, each a raised cell with a big icon
	local totals = Instance.new("Frame")
	totals.Name = "Totals"
	totals.BackgroundTransparency = 1
	totals.Size = UDim2.new(1, 0, 0, Widgets.REWARD_CELL_HEIGHT)
	totals.LayoutOrder = 1
	totals.Parent = rewardBody
	Widgets.list(totals, true, CELL_GAP)
	local xpCell = Widgets.rewardCell(totals, XP_ICON, signed(reward.xp), "XP", CELL_WIDTH)
	xpCell.Name = "XP"
	local gloryCell = Widgets.rewardCell(totals, GLORY_ICON, signed(reward.glory), "Glory", CELL_WIDTH)
	gloryCell.Name = "Glory"
	gloryCell.LayoutOrder = 1
	count.xp, count.glory = xpCell, gloryCell
	if reward.afk then
		local idle = string.format("No reward: no orders for %d min", Config.Progression.AfkTicks // 60)
		iconLine(rewardBody, "clock", idle, 2, Theme.color.negative).Name = "Afk"
	end
	-- the breakdown, in a recessed well: the column icons, then a row per line
	if #reward.lines > 0 then
		local well = Instance.new("ImageLabel")
		well.Name = "Breakdown"
		well.BorderSizePixel = 0
		well.Size = UDim2.fromScale(1, 0)
		well.AutomaticSize = Enum.AutomaticSize.Y
		well.LayoutOrder = 3
		well.Parent = rewardBody
		Widgets.material(well, "well")
		local pad = Widgets.padding(well, Theme.space.m, 0)
		pad.PaddingTop = UDim.new(0, BREAKDOWN_PAD)
		pad.PaddingBottom = UDim.new(0, BREAKDOWN_PAD)
		Widgets.list(well, false, 0)
		columnHeads(well, 0)
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
				well,
				l.kind,
				text,
				if l.xp ~= 0 then signed(l.xp) else "",
				if l.glory ~= 0 then signed(l.glory) else "",
				i,
				if bonus then Theme.color.gold else nil
			)
		end
	end
	-- your level ("Lv 2 · Settler"; in gold "Level 2! · Settler" after a level-up, "New rank: Baron!" after a
	-- rank-up), then the level bar with the XP into the level beside it
	local headline = if rankUp
		then string.format("New rank: %s!", after.rankName)
		elseif levelUp then string.format("Level %d! · %s", after.level, after.rankName)
		else string.format("Lv %d · %s", after.level, after.rankName)
	local line = Instance.new("Frame")
	line.Name = "LevelLine"
	line.BackgroundTransparency = 1
	line.Size = UDim2.new(1, 0, 0, LEVEL_HEIGHT)
	line.LayoutOrder = 4
	line.Parent = rewardBody
	local level = Widgets.label(line, headline, Theme.text.button, LEVEL_HEIGHT)
	level.Name = "Level"
	level.FontFace = Theme.font.display
	level.TextWrapped = false
	level.TextTruncate = Enum.TextTruncate.AtEnd
	level.TextColor3 = if rankUp or levelUp then Theme.color.gold else Theme.color.text
	level.Size = UDim2.new(1, -PROGRESS_WIDTH, 1, 0)
	Widgets.textStroke(level)
	Widgets.leadIcon(level, if rankUp then "crown" else "up", Theme.size.icon)
	count.level = level
	local progress = Widgets.label(
		line,
		if after.xpForLevel > 0 then string.format("%d / %d XP", after.xpIntoLevel, after.xpForLevel) else "MAX",
		Theme.text.small,
		LEVEL_HEIGHT
	)
	progress.Name = "Progress"
	progress.TextXAlignment = Enum.TextXAlignment.Right
	progress.TextWrapped = false
	progress.AnchorPoint = Vector2.new(1, 0)
	progress.Position = UDim2.fromScale(1, 0)
	progress.Size = UDim2.fromOffset(PROGRESS_WIDTH, LEVEL_HEIGHT)
	local barRow = Instance.new("Frame")
	barRow.Name = "LevelBar"
	barRow.BackgroundTransparency = 1
	barRow.Size = UDim2.new(1, 0, 0, BAR_HEIGHT)
	barRow.LayoutOrder = 5
	barRow.Parent = rewardBody
	local bar = Widgets.progress(barRow, nil, BAR_HEIGHT, Theme.color.gold)
	count.bar = bar
	count.fillTo = if after.xpForLevel > 0 then math.clamp(after.xpIntoLevel / after.xpForLevel, 0, 1) else 1
	count.fillFrom = if levelUp
			or rankUp
			or before.xpForLevel <= 0
		then 0
		else math.clamp(before.xpIntoLevel / before.xpForLevel, 0, count.fillTo)
	stepCount() -- the numbers as far as the count-up has got
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

-- The window's width on this screen (phone px): 680, or the screen less its margins on a small phone.
local function windowWidth(): number
	local screen = Widgets.screenSize(dim) / Widgets.uiScale()
	local w = math.min(WINDOW_WIDTH, screen.X - 2 * Theme.space.m)
	return w - w % 2
end

-- The footer: Quests (with what there is to claim), the season pass while a season runs, the achievements, the
-- note that the next match starts by itself, and your Glory.
local function renderFooter(hasQuests: boolean, gloryTotal: number?)
	Widgets.clear(footer)
	local used = 0
	if hasQuests then
		local seasonOn = SeasonState.active()
		-- beside the season pass, the short caption ("Quests (1)") keeps the row on a small phone
		local width = if seasonOn then QUESTS_SHORT_WIDTH else QUESTS_WIDTH
		local quests = Widgets.iconTextButton(
			footer,
			"scroll",
			"",
			width,
			Widgets.GOLD,
			Quests.open,
			"QuestsButton",
			Theme.size.iconButton
		)
		caption(quests, if seasonOn then Quests.shortButtonText() else Quests.buttonText(), "scroll")
		used += width + Theme.space.m
		if seasonOn then
			local season = Widgets.iconTextButton(
				footer,
				"ticket",
				"",
				SEASON_WIDTH,
				Widgets.SPECIAL,
				Season.open,
				"SeasonButton",
				Theme.size.iconButton
			)
			season.LayoutOrder = 1
			caption(season, Season.buttonText(), "ticket")
			used += SEASON_WIDTH + Theme.space.m
		end
		local trophies = Widgets.iconButton(footer, "trophy", "TrophiesButton", nil, Widgets.BUTTON, function()
			Trophies.open("Achievements")
		end)
		trophies.LayoutOrder = 2
		used += Widgets.BUTTON_HEIGHT + Theme.space.m
	end
	local totalText = if gloryTotal then string.format("%d Glory", gloryTotal) else ""
	local totalWidth = 0
	if gloryTotal then
		totalWidth = SMALL_ICON + Theme.space.s + math.ceil(TextWidth.measure(totalText, Theme.text.small, "body")) + 2
		used += totalWidth + Theme.space.m
	end
	-- the note says it in fewer words when the season's button leaves it little room
	local room = windowWidth() - 2 * Widgets.PANEL_PAD - used - SMALL_ICON - Theme.space.s
	local long = "Next match starts soon"
	local text = if TextWidth.measure(long, Theme.text.small, "body") <= room then long else "Next match soon"
	local note = Widgets.hint(footer, text, Theme.text.small, Widgets.BUTTON_HEIGHT)
	note.Name = "NextMatch"
	note.TextWrapped = false
	note.TextTruncate = Enum.TextTruncate.AtEnd
	note.Size = UDim2.new(1, -used, 1, 0)
	note.LayoutOrder = 3
	Widgets.leadIcon(note, "hourglass", SMALL_ICON)
	if gloryTotal then
		local total = Widgets.label(footer, totalText, Theme.text.small, Widgets.BUTTON_HEIGHT)
		total.Name = "GloryTotal"
		total.TextColor3 = Theme.color.textDim
		total.TextWrapped = false
		total.Size = UDim2.fromOffset(totalWidth, Widgets.BUTTON_HEIGHT)
		total.LayoutOrder = 4
		Widgets.leadIcon(total, GLORY_ICON, SMALL_ICON)
	end
end

-- One nation's row in the standings: rank, flag, name (in its colour), a crown for the winners, and the score. Your
-- own row sits on a raised plate with a gold marker at its left.
local function scoreRow(i: number, nationId: number, score: number, winner: boolean, mine: boolean)
	local n = ClientState.nation(nationId)
	local row = Instance.new("ImageLabel")
	row.Name = "Score" .. i
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.LayoutOrder = 2 + i
	row.Parent = body
	if mine then
		Widgets.material(row, "raised")
		local marker = Instance.new("Frame")
		marker.Name = "Marker"
		marker.BackgroundColor3 = Theme.color.gold
		marker.BorderSizePixel = 0
		marker.Position = UDim2.fromOffset(2, 4)
		marker.Size = UDim2.new(0, MARKER, 1, -8)
		marker.ZIndex = 2
		marker.Parent = row
	end
	local rank = Widgets.label(row, tostring(i), Theme.text.title - 4, ROW_HEIGHT)
	rank.FontFace = Theme.font.display
	rank.TextXAlignment = Enum.TextXAlignment.Center
	rank.TextColor3 = if i == 1 then Theme.color.gold else Theme.color.slate300
	rank.Position = UDim2.fromOffset(MARKER + 2, 0)
	rank.Size = UDim2.fromOffset(RANK_WIDTH, ROW_HEIGHT)
	rank.ZIndex = 2
	Widgets.textStroke(rank)
	local x = MARKER + 2 + RANK_WIDTH + Theme.space.xs
	if n then -- the nation's flag (cosmetic)
		local flag =
			Cosmetics.flagLabel(row, Cosmetics.of(n.id).flag, n.colorIndex, UDim2.fromOffset(FLAG_SIZE.X, FLAG_SIZE.Y))
		flag.Position = UDim2.fromOffset(x, (ROW_HEIGHT - FLAG_SIZE.Y) // 2)
		flag.ZIndex = 2
	end
	x += FLAG_SIZE.X + Theme.space.s
	local name = Widgets.label(row, if n then n.name else "?", Theme.text.body + 1, ROW_HEIGHT)
	name.Name = "Name"
	name.TextWrapped = false
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.TextColor3 = if n then Palette.nation(n.colorIndex):Lerp(WHITE, NAME_LIGHTEN) else Theme.color.text
	name.Position = UDim2.fromOffset(x, 0)
	name.Size = UDim2.new(1, -(x + SCORE_WIDTH + SMALL_ICON + Theme.space.s), 1, 0)
	name.ZIndex = 2
	if winner then
		local crown = Widgets.icon(row, "crown", SMALL_ICON)
		crown.Position = UDim2.new(1, -(SCORE_WIDTH + SMALL_ICON + 2), 0, (ROW_HEIGHT - SMALL_ICON) // 2)
		crown.ZIndex = 2
	end
	local points = Widgets.label(row, tostring(score), Theme.text.title - 4, ROW_HEIGHT)
	points.Name = "Points"
	points.FontFace = Theme.font.display
	points.TextXAlignment = Enum.TextXAlignment.Right
	points.TextWrapped = false
	points.AnchorPoint = Vector2.new(1, 0)
	points.Position = UDim2.new(1, -Theme.space.s, 0, 0)
	points.Size = UDim2.fromOffset(SCORE_WIDTH - Theme.space.s, ROW_HEIGHT)
	points.ZIndex = 2
	Widgets.textStroke(points)
end

local function clearAll()
	Widgets.clear(body)
	Widgets.clear(rewardBody)
	Widgets.clear(footer)
end

-- The height a list of fixed-height rows takes (the harness has no layout engine to ask, so the fit below is worked
-- out from the rows, the same on Roblox and in screenshots).
local function listHeight(frame: GuiObject): number
	local list = frame:FindFirstChildOfClass("UIListLayout")
	local gap = if list then list.Padding.Offset else 0
	local pad = frame:FindFirstChildOfClass("UIPadding")
	local total, rows = if pad then pad.PaddingTop.Offset + pad.PaddingBottom.Offset else 0, 0
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") and child.Visible then
			total += if child.AutomaticSize == Enum.AutomaticSize.Y then listHeight(child) else child.Size.Y.Offset
			rows += 1
		end
	end
	return total + math.max(rows - 1, 0) * gap
end

-- A long breakdown on a short screen: shrink the window round its top edge until it fits under the ribbon's line
-- (the usual rewards fit 844×390 at full size).
local function fitPanel()
	local screen = Widgets.screenSize(dim) / Widgets.uiScale()
	local tallest = math.max(listHeight(body), if rewardBody.Visible then listHeight(rewardBody) else 0)
	local height = CONTENT_TOP + tallest + PANEL_GAP + Widgets.BUTTON_HEIGHT + BOTTOM_PAD
	local available = screen.Y - Theme.results.ribbonY - Theme.space.m
	local scale = if available > 0 and height > available then available / height else 1
	if math.abs(panelScale.Scale - scale) > 0.001 then
		panelScale.Scale = scale
	end
end

-- The sunburst behind the ribbon: its own image while Results shows (destroyed when it closes), turning slowly.
local function showSunburst(show: boolean)
	if show and sunImage == nil then
		sunImage = Frames.sunburst()
		if sunImage then
			sunburst.ImageContent = Content.fromObject(sunImage)
		end
	elseif not show and sunImage then
		sunburst.ImageContent = Content.none
		sunImage:Destroy()
		sunImage = nil
	end
	sunburst.Visible = show and sunImage ~= nil
end

local function render()
	local snap = ClientState.snapshot()
	local result = if snap then snap.result else nil
	if result == nil then
		dim.Visible = false
		showSunburst(false)
		count.report = nil
		clearAll() -- a hidden screen keeps nothing (rebuilt when the next match ends): fewer GUI objects
		return
	end
	local opening = not dim.Visible
	if opening and onShow then
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
	ribbon.Text = if iWon then "YOU WIN!" else string.upper(table.concat(names, " & ")) .. " WON"
	local mark = ribbon:FindFirstChild("Icon")
	if mark and mark:IsA("GuiObject") then
		Icons.set(mark, if iWon then "trophy" else "flag")
	end
	local how = HOW[result.kind] or { icon = "flag", text = result.kind }
	local howLine = Widgets.label(body, how.text, Theme.text.body, HOW_HEIGHT)
	howLine.Name = "How"
	howLine.TextWrapped = false
	howLine.TextTruncate = Enum.TextTruncate.AtEnd
	howLine.TextColor3 = Theme.color.gold
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
	local report = ProfileState.reward()
	renderFooter(hasQuests, if hasReward and report then report.after.glory else nil)
	rewardBody.Visible = hasReward
	local width = windowWidth()
	local matchWidth = width - 2 * Widgets.PANEL_PAD - REWARD_WIDTH - COLUMN_GAP
	if not hasReward then -- just the match: the window keeps the column's width
		width = matchWidth + 2 * Widgets.PANEL_PAD
	end
	body.Size = UDim2.fromOffset(matchWidth, 0)
	panel.Size = UDim2.fromOffset(width, 0)
	dim.Visible = true
	fitPanel()
	if opening then
		showSunburst(true)
		Widgets.shine(ribbon, SHINE_DELAY)
	end
end

function Results.init(showHandler: () -> ())
	onShow = showHandler
	local gui = Widgets.screen("Results", 10)
	-- the whole screen, top-bar row included (the window hangs from near the top, its ribbon in that row), but
	-- clear of a notch
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	-- dim the whole screen behind the results
	dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Active = true -- the map can't be tapped behind the results
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Theme.color.slate950
	dim.BackgroundTransparency = 0.4
	dim.BorderSizePixel = 0
	dim.Visible = false
	dim.Parent = gui
	-- the sunburst: gold rays round the ribbon, behind the window
	sunburst = Instance.new("ImageLabel")
	sunburst.Name = "Sunburst"
	sunburst.AnchorPoint = Vector2.new(0.5, 0.5)
	sunburst.Position = UDim2.new(0.5, 0, 0, Theme.results.ribbonY)
	sunburst.Size = UDim2.fromOffset(SUNBURST_SHOWN, SUNBURST_SHOWN)
	sunburst.BackgroundTransparency = 1
	sunburst.ImageTransparency = SUNBURST_TRANSPARENCY
	sunburst.ResampleMode = Enum.ResamplerMode.Pixelated
	sunburst.ZIndex = 0
	sunburst.Visible = false
	sunburst.Parent = dim
	-- the brass window, hanging from its top edge
	panel = Widgets.panel(dim, WINDOW_WIDTH, "brass")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, Theme.results.ribbonY)
	panel.ZIndex = 1
	Widgets.list(panel, false, PANEL_GAP)
	local pad = panel:FindFirstChildOfClass("UIPadding") :: UIPadding
	pad.PaddingTop = UDim.new(0, CONTENT_TOP - PANEL_GAP) -- under the zero-height header row
	pad.PaddingBottom = UDim.new(0, BOTTOM_PAD)
	panelScale = Instance.new("UIScale")
	panelScale.Parent = panel
	dim:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if dim.Visible then
			fitPanel()
		end
	end)
	-- the header row (no height): the ribbon centred on the window's top edge
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.fromScale(1, 0)
	header.LayoutOrder = -1
	header.ZIndex = 3
	header.Parent = panel
	ribbon = Widgets.ribbon(header, "YOU WIN!", "trophy", Theme.color.gold, Theme.results.ribbonWidth)
	ribbon.Name = "Winner"
	ribbon.AnchorPoint = Vector2.new(0.5, 0)
	ribbon.Position = UDim2.new(0.5, 0, 0, -pad.PaddingTop.Offset - Widgets.RIBBON_HEIGHT // 2)
	ribbon.ZIndex = 3
	-- the pages: today the rewards page (two columns side by side, short enough for a phone in landscape: the match,
	-- then your reward); a match replay page joins it later
	pages = Instance.new("Frame")
	pages.Name = "Pages"
	pages.BackgroundTransparency = 1
	pages.Size = UDim2.fromScale(1, 0)
	pages.AutomaticSize = Enum.AutomaticSize.Y
	pages.Parent = panel
	columns = Instance.new("Frame")
	columns.Name = "Rewards"
	columns.BackgroundTransparency = 1
	columns.Size = UDim2.fromScale(1, 0)
	columns.AutomaticSize = Enum.AutomaticSize.Y
	columns.Parent = pages
	Widgets.list(columns, true, COLUMN_GAP).VerticalAlignment = Enum.VerticalAlignment.Top
	body = Instance.new("Frame")
	body.Name = "Match"
	body.BackgroundTransparency = 1
	body.Size = UDim2.fromOffset(WINDOW_WIDTH - 2 * Widgets.PANEL_PAD - REWARD_WIDTH - COLUMN_GAP, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.LayoutOrder = 1
	body.Parent = columns
	Widgets.list(body, false, 0)
	rewardBody = Instance.new("Frame")
	rewardBody.Name = "Reward"
	rewardBody.BackgroundTransparency = 1
	rewardBody.Size = UDim2.fromOffset(REWARD_WIDTH, 0)
	rewardBody.AutomaticSize = Enum.AutomaticSize.Y
	rewardBody.LayoutOrder = 2
	rewardBody.Visible = false
	rewardBody.Parent = columns
	Widgets.list(rewardBody, false, SECTION_GAP)
	-- the buttons, the "next match" note and your Glory, across the whole window
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
	-- the count-up and the sunburst's turn
	RunService.Heartbeat:Connect(function()
		if not dim.Visible then
			return
		end
		local running = os.clock() - count.started <= COUNT_DELAY + COUNT_SECONDS + 0.1
		if count.report and (running or (count.stamp and not count.stamped)) then
			stepCount()
		end
		if sunburst.Visible and not Widgets.reducedMotion() then
			sunburst.Rotation = (os.clock() * SUNBURST_TURN) % 360
		end
	end)
end

return Results
