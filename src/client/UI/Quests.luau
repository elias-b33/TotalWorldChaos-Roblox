--!strict
-- The Quests screen (docs/MONETIZATION.md 5.4–5.6), phone first: daily quests on the left, weekly quests, the
-- 7-step login calendar and the play streak on the right. Each quest shows its progress bar and reward, a Claim
-- button once finished and a 🔄 reroll on unfinished daily quests (free ones first, then Glory).
-- Opens from the 📜 button in the Lobby, the 📜 Quests button in the 🌍 Nations drawer during a match, and the
-- Results screen. No pressure (section 10): no countdowns, no "you'll lose your streak" messages.
-- Rewarded video (the game's one ad placement): "📺 Watch an ad · +1 free reroll" in the header, next to the reroll
-- count, only during the Lobby's map vote, only once the free rerolls are used, and only while Roblox says an ad is
-- available for this player (Client.Ads), so players it reports as ineligible (under 13) never see it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local SimAds = require(ReplicatedStorage.Shared.Sim.Ads)
local Types = require(ReplicatedStorage.Shared.Types)

local Client = script.Parent.Parent
local Ads = require(Client.Ads)
local ClientState = require(Client.ClientState)
local Intents = require(Client.Intents)
local LobbyState = require(Client.LobbyState)
local ProfileState = require(Client.ProfileState)
local QuestState = require(Client.QuestState)
local Widgets = require(script.Parent.Widgets)

local GLORY = "🏅"
local BUTTON_SIZE = 52
local HEADER_HEIGHT = 40
local ROW_HEIGHT = 44
local SECTION_HEIGHT = 20
local GAP = 4
local COLUMN_GAP = 10
local LEFT_SHARE = 0.54 -- of the panel's width: the daily column
local REWARD_WIDTH = 66
local ACTION_WIDTH = 64
local AD_WIDTH = 176
local AD_COLOR = Color3.fromRGB(60, 110, 200)
local STEP_HEIGHT = 46
local CARD = Color3.fromRGB(32, 35, 50)
local GOLD = Color3.fromRGB(242, 193, 78)
local OFF_TEXT = Color3.fromRGB(150, 152, 165)
local BAR_BACK = Color3.fromRGB(50, 54, 70)

local TIER_COLORS: { [string]: Color3 } = {
	Easy = Color3.fromRGB(90, 200, 120),
	Medium = Color3.fromRGB(90, 160, 255),
	Hard = Color3.fromRGB(255, 150, 60),
	Weekly = Color3.fromRGB(190, 110, 255),
}

-- Quest text by stat (Config.Progression.Quests.Pool). %d is the target.
local TEXT: { [string]: { one: string, many: string } } = {
	Matches = { one = "Play a match", many = "Play %d matches" },
	NeutralCaptures = { one = "Capture a neutral province", many = "Capture %d neutral provinces" },
	Captures = { one = "Capture a province", many = "Capture %d provinces" },
	Regiments = { one = "Recruit a regiment", many = "Recruit %d regiments" },
	Buildings = { one = "Build a building", many = "Build %d buildings" },
	Developments = { one = "Develop a province", many = "Develop provinces %d times" },
	DevLevel = { one = "Develop a province to level %d", many = "Develop a province to level %d" },
	Battles = { one = "Win a battle", many = "Win %d battles" },
	Alliances = { one = "Form an alliance", many = "Form %d alliances" },
	Top5 = { one = "Finish in the top 5", many = "Finish in the top 5, %d times" },
	Top3 = { one = "Finish in the top 3", many = "Finish in the top 3, %d times" },
	Wins = { one = "Win a match", many = "Win %d matches" },
	Capitals = { one = "Capture an enemy capital", many = "Capture %d enemy capitals" },
	Held = { one = "Hold %d provinces at once", many = "Hold %d provinces at once" },
	Powers = { one = "Use a Primordial power", many = "Use %d Primordial powers" },
}

-- Streak reward tiers (Config.Progression.Login.StreakFlames): what each one is.
local FLAMES = { "🔥 Flame", "🔥🔥 Big flame", "💙 Blue flame", "👑 the Unyielding" }

local QuestsUI = {}

local gui: ScreenGui
local openButton: TextButton
local badge: TextLabel
local panel: Frame
local gloryLabel: TextLabel
local rerollLabel: TextLabel
local adButton: TextButton
local checkedView: Types.QuestView? = nil -- the quest view Roblox was last asked about an ad for
local dailyColumn: Frame
local weeklyColumn: Frame

local function formatNumber(n: number): string
	local s = tostring(math.floor(n))
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	return (string.gsub(out, "^,", ""))
end

-- "Win 3 battles" (also used by the Results screen).
function QuestsUI.text(q: Types.QuestEntry): string
	local t = TEXT[q.stat]
	if t == nil then
		return q.id
	end
	local pattern = if q.target == 1 then t.one else t.many
	return if string.find(pattern, "%%d") then string.format(pattern, q.target) else pattern
end

local function section(parent: Instance, text: string, order: number)
	local l = Widgets.label(parent, text, 15, SECTION_HEIGHT)
	l.LayoutOrder = order
	return l
end

local function bar(parent: Instance, share: number, color: Color3): Frame
	local back = Instance.new("Frame")
	back.Name = "Bar"
	back.BackgroundColor3 = BAR_BACK
	back.BorderSizePixel = 0
	back.Parent = parent
	Widgets.corner(back, 4)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(math.clamp(share, 0, 1), 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = back
	Widgets.corner(fill, 4)
	return back
end

-- One quest: tier stripe, text, progress bar, reward, and Claim / reroll / done.
local function questRow(parent: Instance, q: Types.QuestEntry, daily: boolean, order: number)
	local view = QuestState.view()
	local done = q.progress >= q.target
	local row = Instance.new("Frame")
	row.Name = "Quest_" .. q.id
	row.BackgroundColor3 = CARD
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.LayoutOrder = order
	row.Parent = parent
	Widgets.corner(row, 8)
	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0, 5, 1, -12)
	stripe.Position = UDim2.fromOffset(4, 6)
	stripe.BackgroundColor3 = TIER_COLORS[q.tier] or OFF_TEXT
	stripe.BorderSizePixel = 0
	stripe.Parent = row
	Widgets.corner(stripe, 3)

	local textWidth = -(16 + REWARD_WIDTH + ACTION_WIDTH + 8)
	local prefix = if q.claimed then "✅ " elseif daily and q.daysLeft == 0 then "⌛ " else ""
	local title = Widgets.label(row, prefix .. QuestsUI.text(q), 14, 20)
	title.Position = UDim2.fromOffset(14, 3)
	title.Size = UDim2.new(1, textWidth, 0, 20)
	title.TextWrapped = false
	title.TextTruncate = Enum.TextTruncate.AtEnd
	if q.claimed then
		title.TextColor3 = OFF_TEXT
	end
	local progress = bar(row, q.progress / q.target, if done then GOLD else TIER_COLORS[q.tier] or OFF_TEXT)
	progress.Position = UDim2.fromOffset(14, 28)
	progress.Size = UDim2.new(1, textWidth - 46, 0, 8)
	local count = Widgets.label(row, string.format("%d/%d", math.min(q.progress, q.target), q.target), 12, 16)
	count.Position = UDim2.new(1, -(REWARD_WIDTH + ACTION_WIDTH + 8 + 44), 0, 24)
	count.Size = UDim2.fromOffset(42, 16)
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.TextColor3 = OFF_TEXT

	local reward = Widgets.label(row, string.format("+%s XP\n+%d %s", formatNumber(q.xp), q.glory, GLORY), 12, 34)
	reward.Position = UDim2.new(1, -(REWARD_WIDTH + ACTION_WIDTH + 6), 0, 5)
	reward.Size = UDim2.fromOffset(REWARD_WIDTH, 34)
	reward.TextXAlignment = Enum.TextXAlignment.Right
	reward.TextColor3 = if q.claimed then OFF_TEXT else GOLD

	local action: TextButton? = nil
	if q.claimed then
		local claimed = Widgets.button(row, "✅", ACTION_WIDTH, Widgets.BUTTON_OFF, function() end)
		claimed.AutoButtonColor = false
		action = claimed
	elseif done then
		action = Widgets.button(row, "Claim", ACTION_WIDTH, Widgets.GOOD, function()
			Intents.claimQuest(q.key)
		end)
	elseif daily and view then
		local free = view.freeRerolls > 0
		local summary = ProfileState.summary()
		local afford = free or (summary ~= nil and summary.glory >= view.rerollGlory)
		local text = if free then "🔄 Free" else string.format("🔄 %d%s", view.rerollGlory, GLORY)
		action = Widgets.button(
			row,
			text,
			ACTION_WIDTH,
			if afford then Widgets.BUTTON else Widgets.BUTTON_OFF,
			function()
				Intents.rerollQuest(q.key)
			end
		)
	end
	if action then
		action.Name = "Action"
		action.TextSize = 13
		action.AnchorPoint = Vector2.new(1, 0.5)
		action.Position = UDim2.new(1, -4, 0.5, 0)
		action.Size = UDim2.fromOffset(ACTION_WIDTH, ROW_HEIGHT - 8)
	end
end

-- The 7 calendar steps: done ones ticked, the next one outlined.
local function calendar(parent: Instance, view: Types.QuestView, order: number)
	local row = Instance.new("Frame")
	row.Name = "Calendar"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, STEP_HEIGHT)
	row.LayoutOrder = order
	row.Parent = parent
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(1 / #view.calendar.glory, -GAP, 1, 0)
	grid.CellPadding = UDim2.fromOffset(GAP, 0)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = row
	local step = view.calendar.step
	-- after the 7th step the next play day starts a new cycle: show it fresh unless today finished it
	local shown = if step == #view.calendar.glory and not view.calendar.playedToday then 0 else step
	for i, glory in view.calendar.glory do
		local cell = Instance.new("TextLabel")
		cell.Name = "Step" .. i
		cell.LayoutOrder = i
		cell.BackgroundColor3 = if i <= shown then Color3.fromRGB(60, 52, 24) else CARD
		cell.Font = Enum.Font.GothamBold
		cell.TextSize = 12
		cell.TextColor3 = if i <= shown then GOLD else Color3.new(1, 1, 1)
		cell.Text = string.format("%s %d\n%d%s", if i <= shown then "✅" else "Day", i, glory, GLORY)
		cell.Parent = row
		Widgets.corner(cell, 8)
		if i == shown + 1 and not view.calendar.playedToday then
			local stroke = Instance.new("UIStroke")
			stroke.Color = GOLD
			stroke.Thickness = 2
			stroke.Parent = cell
		end
	end
end

-- The ad button: in the map vote (Sim.Ads.timeOk), with a video to offer (Sim.Quests.videoRerollsLeft) and an ad Roblox says is
-- available. Asks Roblox once per quest view, when the button could show.
local function updateAd()
	if adButton == nil then
		return
	end
	local view = QuestState.view()
	local voteLeft = if LobbyState.phase() == "Lobby" then LobbyState.secondsLeft() else nil
	local wanted = panel.Visible and view ~= nil and view.videoRerolls > 0 and SimAds.timeOk(voteLeft)
	if wanted and checkedView ~= view then
		checkedView = view
		Ads.check()
	end
	local show = wanted and Ads.available()
	adButton.Visible = show
	if show and view then
		adButton.Text = string.format(
			"📺 Watch an ad%s\n+1 free reroll · %d left today",
			if Ads.testMode() then " (test)" else "",
			view.videoRerolls
		)
		Ads.register(adButton)
	end
	rerollLabel.Size = UDim2.new(1, if show then -(330 + AD_WIDTH) else -330, 0, HEADER_HEIGHT)
end

local function render()
	if panel == nil or not panel.Visible then
		return
	end
	local summary = ProfileState.summary()
	gloryLabel.Text = GLORY .. " " .. formatNumber(if summary then summary.glory else 0)
	local view = QuestState.view()
	Widgets.clear(dailyColumn)
	Widgets.clear(weeklyColumn)
	if view == nil then
		rerollLabel.Text = ""
		Widgets.label(dailyColumn, "⏳ Loading your quests…", 15, 24)
		return
	end
	rerollLabel.Text = if view.freeRerolls > 0
		then string.format("🔄 %d free reroll%s today", view.freeRerolls, if view.freeRerolls == 1 then "" else "s")
		else string.format("🔄 Rerolls: %d %s", view.rerollGlory, GLORY)

	section(dailyColumn, "☀ Daily quests · new ones every day", 0)
	for i, q in view.daily do
		questRow(dailyColumn, q, true, i)
	end
	section(weeklyColumn, "📅 Weekly quests · new ones on Monday", 0)
	for i, q in view.weekly do
		questRow(weeklyColumn, q, false, i)
	end
	section(weeklyColumn, "🗓 Play calendar · one step per day you play", 10)
	calendar(weeklyColumn, view, 11)
	local streak = if view.streak > 0
		then string.format("🔥 %d-day play streak", view.streak)
		else "🔥 Finish a match to start a play streak"
	local earned = if view.flame > 0 then " · " .. FLAMES[view.flame] else ""
	local line = Widgets.label(
		weeklyColumn,
		string.format(
			"%s%s%s\nOne missed day a week doesn't break it",
			streak,
			if view.best > 0 then " · best " .. view.best else "",
			earned
		),
		12,
		32
	)
	line.Name = "Streak"
	line.TextColor3 = OFF_TEXT
	line.LayoutOrder = 12
	updateAd()
end

local function refreshButton()
	local inLobby = LobbyState.phase() ~= "None" or ClientState.snapshot() == nil
	openButton.Visible = inLobby and not panel.Visible
	local ready = QuestState.readyCount()
	badge.Visible = ready > 0
	badge.Text = tostring(ready)
end

local function setOpen(open: boolean)
	panel.Visible = open
	refreshButton()
	if open then
		checkedView = nil -- ask Roblox again each time the screen opens
		render()
	else
		updateAd()
	end
end

function QuestsUI.open()
	setOpen(true)
end

function QuestsUI.close()
	setOpen(false)
end

function QuestsUI.isOpen(): boolean
	return panel.Visible
end

-- "📜 Quests", with the number of finished quests waiting to be claimed (for buttons in other panels).
function QuestsUI.buttonText(): string
	local ready = QuestState.readyCount()
	return if ready > 0 then string.format("📜 Quests · %d to claim", ready) else "📜 Quests"
end

-- The same, short enough for a small button.
function QuestsUI.shortButtonText(): string
	local ready = QuestState.readyCount()
	return if ready > 0 then string.format("📜 Quests (%d)", ready) else "📜 Quests"
end

local function column(parent: Instance, name: string, width: UDim, order: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.Size = UDim2.new(width.Scale, width.Offset, 1, 0)
	f.LayoutOrder = order
	f.Parent = parent
	Widgets.list(f, false, GAP)
	return f
end

function QuestsUI.init()
	gui = Widgets.screen("Quests", 31) -- above the shop and the lobby screens
	-- the Lobby's 📜 button, next to its 🛒 (the lobby screens cover the top bar), in a screen of its own under the
	-- shop (30) and the private-server sheet (31), so a full-screen panel covers it instead of the other way round
	local buttonGui = Widgets.screen("QuestsButton", 29)

	openButton = Instance.new("TextButton")
	openButton.Name = "QuestsButton"
	openButton.AnchorPoint = Vector2.new(0, 1)
	openButton.Position = UDim2.new(0, 12 + BUTTON_SIZE + 10, 1, -12)
	openButton.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE)
	openButton.BackgroundColor3 = Color3.fromRGB(120, 90, 40)
	openButton.Font = Enum.Font.GothamBold
	openButton.TextSize = 24
	openButton.TextColor3 = Color3.new(1, 1, 1)
	openButton.Text = "📜"
	openButton.Parent = buttonGui
	Widgets.corner(openButton, BUTTON_SIZE // 2)
	openButton.Activated:Connect(function()
		setOpen(true)
	end)
	badge = Instance.new("TextLabel")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(1, 4, 0, -4)
	badge.Size = UDim2.fromOffset(20, 20)
	badge.BackgroundColor3 = Widgets.DANGER
	badge.Font = Enum.Font.GothamBold
	badge.TextSize = 12
	badge.TextColor3 = Color3.new(1, 1, 1)
	badge.Visible = false
	badge.Parent = openButton
	Widgets.corner(badge, 10)

	panel = Instance.new("Frame")
	panel.Name = "QuestsPanel"
	panel.Active = true
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(1, -16, 1, -16)
	panel.BackgroundColor3 = Widgets.PANEL
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	Widgets.corner(panel, 12)
	Widgets.padding(panel, 10)
	Widgets.list(panel, false, 6)

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
	header.LayoutOrder = 1
	header.Parent = panel
	local title = Widgets.label(header, "📜 Quests", 20, HEADER_HEIGHT)
	title.Size = UDim2.fromOffset(130, HEADER_HEIGHT)
	gloryLabel = Widgets.label(header, "", 18, HEADER_HEIGHT)
	gloryLabel.Name = "Glory"
	gloryLabel.Position = UDim2.fromOffset(140, 0)
	gloryLabel.Size = UDim2.fromOffset(120, HEADER_HEIGHT)
	gloryLabel.TextColor3 = GOLD
	rerollLabel = Widgets.label(header, "", 14, HEADER_HEIGHT)
	rerollLabel.Name = "Rerolls"
	rerollLabel.Position = UDim2.fromOffset(270, 0)
	rerollLabel.Size = UDim2.new(1, -330, 0, HEADER_HEIGHT)
	rerollLabel.TextColor3 = OFF_TEXT
	adButton = Widgets.button(header, "", AD_WIDTH, AD_COLOR, function()
		Ads.watch()
		updateAd()
	end)
	adButton.Name = "AdButton"
	adButton.TextSize = 12
	adButton.AnchorPoint = Vector2.new(1, 0)
	adButton.Position = UDim2.new(1, -52, 0, 0)
	adButton.Size = UDim2.fromOffset(AD_WIDTH, HEADER_HEIGHT)
	adButton.Visible = false
	local close = Widgets.button(header, "✕", 44, Widgets.DANGER, function()
		setOpen(false)
	end)
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(1, 0)
	close.Size = UDim2.fromOffset(44, HEADER_HEIGHT)

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, 0, 1, -(HEADER_HEIGHT + 6))
	body.LayoutOrder = 2
	body.Parent = panel
	Widgets.list(body, true, COLUMN_GAP).VerticalAlignment = Enum.VerticalAlignment.Top
	dailyColumn = column(body, "Daily", UDim.new(LEFT_SHARE, -COLUMN_GAP // 2), 1)
	weeklyColumn = column(body, "Weekly", UDim.new(1 - LEFT_SHARE, -COLUMN_GAP // 2), 2)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	buttonGui.Parent = gui.Parent

	QuestState.onChange(function()
		refreshButton()
		render()
	end)
	ProfileState.onChange(render)
	ClientState.onReset(refreshButton)
	LobbyState.onChange(function()
		refreshButton()
		updateAd()
	end)
	Ads.onChange(updateAd)
end

return QuestsUI
