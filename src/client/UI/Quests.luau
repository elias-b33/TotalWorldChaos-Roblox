--!strict
-- The Quests screen (docs/MONETIZATION.md 5.4–5.6), phone first: daily quests on the left, weekly quests, the
-- 7-step login calendar and the play streak on the right. Each quest shows its progress bar and reward, a Claim
-- button once finished and a reroll button on unfinished daily quests (free ones first, then Glory).
-- Opens from the scroll button in the Lobby, the Quests button in the nations drawer during a match, and the
-- Results screen. No pressure (section 10): no countdowns, no "you'll lose your streak" messages.
-- Rewarded video (the game's one ad placement): "Watch an ad · +1 free reroll" in the header, only during the
-- Lobby's map vote, only once the free rerolls are used, and only while Roblox says an ad is available for this
-- player (Client.Ads), so players it reports as ineligible (under 13) never see it.
-- Built from the UI kit (docs/DESIGN.md "UI style"); the panel's contents are built when it opens and dropped when
-- it closes.

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
local Icons = require(script.Parent.Icons)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local BAR = Widgets.BUTTON_HEIGHT
local ROW_HEIGHT = Widgets.BUTTON_HEIGHT -- a quest; its button is the row's full height
local ROW_GAP = 2 -- six daily quests (today's and yesterday's) fit a 375 px phone
local SECTION_HEIGHT = 18
local COLUMN_GAP = Theme.space.m
local LEFT_SHARE = 0.54 -- of the panel's width: the daily column
local TEXT_LEFT = 14 -- right of the tier stripe
local REWARD_WIDTH = 70
local COUNT_WIDTH = 44
local ACTION_WIDTH = 80
local REROLL_SHARE = 0.4 -- of the header left of the ad button: the reroll line (two lines on a small phone)
local AD_WIDTH = 224
local STEP_HEIGHT = 44
local STREAK_HEIGHT = 36

local TIER_COLORS: { [string]: Color3 } = {
	Easy = Theme.color.good,
	Medium = Theme.color.primary,
	Hard = Theme.color.danger,
	Weekly = Theme.color.special,
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

-- Streak reward tiers (Config.Progression.Login.StreakFlames): what each one is, and its icon.
local FLAMES = { "Flame", "Big flame", "Blue flame", "the Unyielding" }
local FLAME_ICONS = { "fire", "fire", "fireBlue", "crown" }

-- The open panel's pieces (nil while the screen is closed: its contents are dropped).
type Refs = {
	glory: TextLabel,
	rerolls: TextLabel,
	daily: Frame,
	weekly: Frame,
}

local QuestsUI = {}

local gui: ScreenGui
local openButton: TextButton
local badge: TextLabel
local panel: Frame
-- the ad button stays (hidden) while the screen is closed: Roblox registers each ad button once (Client.Ads)
local adButton: TextButton
local ui: Refs? = nil
local checkedView: Types.QuestView? = nil -- the quest view Roblox was last asked about an ad for

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

local function section(parent: Instance, icon: string, text: string, order: number)
	local l = Widgets.label(parent, text, Theme.text.small, SECTION_HEIGHT)
	l.FontFace = Theme.font.display
	l.TextColor3 = Theme.color.gold
	l.TextWrapped = false
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.LayoutOrder = order
	Widgets.leadIcon(l, icon, 16, Theme.space.xs)
	return l
end

-- A label sized to its text and anchored at its right edge (a reward line before the row's button).
local function rightLine(parent: Instance, text: string, right: number, y: number, color: Color3): TextLabel
	local l = Widgets.label(parent, text, Theme.text.small, 18)
	l.FontFace = Theme.font.display
	l.TextColor3 = color
	l.TextWrapped = false
	l.AnchorPoint = Vector2.new(1, 0)
	l.Position = UDim2.new(1, -right, 0, y)
	l.Size = UDim2.fromOffset(0, 18)
	l.AutomaticSize = Enum.AutomaticSize.X
	return l
end

-- The reroll button: free ones first, then Glory (the reroll icon, the price and the Glory medal).
local function rerollButton(row: Frame, q: Types.QuestEntry, view: Types.QuestView): TextButton
	local free = view.freeRerolls > 0
	local summary = ProfileState.summary()
	local afford = free or (summary ~= nil and summary.glory >= view.rerollGlory)
	local b = Widgets.button(
		row,
		if free then "Free" else tostring(view.rerollGlory),
		ACTION_WIDTH,
		Widgets.BUTTON,
		function()
			Intents.rerollQuest(q.key)
		end
	)
	b.TextSize = Theme.text.small
	b.TextXAlignment = Enum.TextXAlignment.Left
	b.TextWrapped = false
	Widgets.padding(b, Theme.space.s, 0)
	Widgets.leadIcon(b, "reroll", Theme.size.icon, Theme.space.xs)
	if not free then
		local medal = Icons.label(b, "medal", 16)
		medal.AnchorPoint = Vector2.new(1, 0.5)
		medal.Position = UDim2.fromScale(1, 0.5)
	end
	if not afford then
		Widgets.setEnabled(b, false) -- still sends: the server says why
	end
	return b
end

-- One quest: tier stripe, text, progress bar, reward, and Claim / reroll / claimed.
local function questRow(parent: Instance, q: Types.QuestEntry, daily: boolean, order: number)
	local view = QuestState.view()
	local done = q.progress >= q.target
	local row = Widgets.card(parent, nil, ROW_HEIGHT)
	row.Name = "Quest_" .. q.id
	row.LayoutOrder = order
	local pad = row:FindFirstChildOfClass("UIPadding")
	if pad then
		pad:Destroy() -- the row's button runs to its edge; the rest sits at fixed offsets
	end
	local stripe = Instance.new("Frame")
	stripe.Name = "Tier"
	stripe.Position = UDim2.fromOffset(Theme.space.s, Theme.space.s)
	stripe.Size = UDim2.new(0, 4, 1, -2 * Theme.space.s)
	stripe.BackgroundColor3 = TIER_COLORS[q.tier] or Theme.color.textDim
	stripe.BorderSizePixel = 0
	stripe.Parent = row
	Widgets.corner(stripe, 2)

	-- the action at the right edge decides how much room the text gets
	local action: GuiObject? = nil
	if q.claimed then
		local t = Widgets.tag(row, "check", nil, 36)
		t.AnchorPoint = Vector2.new(1, 0.5)
		t.Position = UDim2.new(1, -Theme.space.s, 0.5, 0)
		action = t
	elseif done then
		local b = Widgets.button(row, "Claim", ACTION_WIDTH, Widgets.GOOD, function()
			Intents.claimQuest(q.key)
		end)
		b.TextSize = Theme.text.body
		b.AnchorPoint = Vector2.new(1, 0)
		b.Position = UDim2.fromScale(1, 0)
		action = b
	elseif daily and view then
		local b = rerollButton(row, q, view)
		b.AnchorPoint = Vector2.new(1, 0)
		b.Position = UDim2.fromScale(1, 0)
		action = b
	end
	local actionWidth = if action == nil then 0 elseif q.claimed then 36 + Theme.space.s else ACTION_WIDTH
	if action then
		action.Name = "Action"
	end
	local right = actionWidth + Theme.space.s -- the reward lines end here

	local title = Widgets.label(row, QuestsUI.text(q), Theme.text.body, 20)
	title.Name = "Title"
	title.Position = UDim2.fromOffset(TEXT_LEFT, 2)
	title.Size = UDim2.new(1, -(TEXT_LEFT + REWARD_WIDTH + right), 0, 20)
	title.TextWrapped = false
	title.TextTruncate = Enum.TextTruncate.AtEnd
	if q.claimed then
		title.TextColor3 = Theme.color.textDim
		Widgets.leadIcon(title, "check", 16, Theme.space.xs)
	elseif daily and q.daysLeft == 0 then -- yesterday's: today is its last day
		Widgets.leadIcon(title, "hourglass", 16, Theme.space.xs)
	end
	local bar =
		Widgets.progress(row, nil, 10, if done then Theme.color.gold else TIER_COLORS[q.tier] or Theme.color.textDim)
	bar.Position = UDim2.fromOffset(TEXT_LEFT, 27)
	bar.Size = UDim2.new(1, -(TEXT_LEFT + REWARD_WIDTH + right + COUNT_WIDTH), 0, 10)
	Widgets.setProgress(bar, q.progress / q.target)
	local count = Widgets.label(row, string.format("%d/%d", math.min(q.progress, q.target), q.target), nil, 18)
	count.Name = "Count"
	count.TextSize = Theme.text.small
	count.TextColor3 = Theme.color.textDim
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.AnchorPoint = Vector2.new(1, 0)
	count.Position = UDim2.new(1, -(REWARD_WIDTH + right), 0, 23)
	count.Size = UDim2.fromOffset(COUNT_WIDTH - Theme.space.xs, 18)

	local color = if q.claimed then Theme.color.textDim else Theme.color.gold
	rightLine(row, string.format("+%s XP", formatNumber(q.xp)), right, 3, color)
	local glory = rightLine(row, "+" .. q.glory, right, 23, color)
	Widgets.leadIcon(glory, "medal", 16, 2)
end

-- The 7 calendar steps: done ones gold with a tick, the next one outlined. Each shows its day and its Glory.
local function calendar(parent: Instance, view: Types.QuestView, order: number)
	local row = Instance.new("Frame")
	row.Name = "Calendar"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, STEP_HEIGHT)
	row.LayoutOrder = order
	row.Parent = parent
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(1 / #view.calendar.glory, -Theme.space.xs, 1, 0)
	grid.CellPadding = UDim2.fromOffset(Theme.space.xs, 0)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = row
	local step = view.calendar.step
	-- after the 7th step the next play day starts a new cycle: show it fresh unless today finished it
	local shown = if step == #view.calendar.glory and not view.calendar.playedToday then 0 else step
	for i, glory in view.calendar.glory do
		local done = i <= shown
		local cell = Instance.new("TextLabel")
		cell.Name = "Step" .. i
		cell.LayoutOrder = i
		cell.BackgroundColor3 = if done then Theme.color.goldDeep else Theme.color.navyRaised
		cell.BorderSizePixel = 0
		cell.FontFace = Theme.font.display
		cell.TextSize = Theme.text.small
		cell.TextColor3 = if done then Theme.color.goldPale else Theme.color.text
		cell.Text = string.format("%s\n%d", if done then "" else tostring(i), glory)
		cell.Parent = row
		Widgets.corner(cell, Theme.radius.m)
		if done then
			local tick = Widgets.icon(cell, "check", 16)
			tick.AnchorPoint = Vector2.new(0.5, 0)
			tick.Position = UDim2.new(0.5, 0, 0, Theme.space.xs)
		end
		if i == shown + 1 and not view.calendar.playedToday then
			Widgets.stroke(cell, Theme.color.gold)
		end
	end
end

-- The ad button: in the map vote (Sim.Ads.timeOk), with a video to offer (Sim.Quests.videoRerollsLeft) and an ad Roblox says is
-- available. Asks Roblox once per quest view, when the button could show.
local function updateAd()
	local view = QuestState.view()
	local voteLeft = if LobbyState.phase() == "Lobby" then LobbyState.secondsLeft() else nil
	local wanted = ui ~= nil and panel.Visible and view ~= nil and view.videoRerolls > 0 and SimAds.timeOk(voteLeft)
	if wanted and checkedView ~= view then
		checkedView = view
		Ads.check()
	end
	local show = wanted and Ads.available()
	adButton.Visible = show
	if show and view then
		adButton.Text = string.format(
			"Watch an ad%s\n+1 free reroll · %d left today",
			if Ads.testMode() then " (test)" else "",
			view.videoRerolls
		)
		Ads.register(adButton)
	end
end

local function render()
	local r = ui
	if r == nil or not panel.Visible then
		return
	end
	local summary = ProfileState.summary()
	r.glory.Text = formatNumber(if summary then summary.glory else 0)
	local view = QuestState.view()
	Widgets.clear(r.daily)
	Widgets.clear(r.weekly)
	if view == nil then
		r.rerolls.Text = ""
		section(r.daily, "hourglass", "Loading your quests…", 0)
		return
	end
	r.rerolls.Text = if view.freeRerolls > 0
		then string.format("%d free reroll%s today", view.freeRerolls, if view.freeRerolls == 1 then "" else "s")
		else string.format("Rerolls: %d Glory", view.rerollGlory)

	section(r.daily, "clock", "Daily quests · new ones every day", 0)
	for i, q in view.daily do
		questRow(r.daily, q, true, i)
	end
	section(r.weekly, "calendar", "Weekly quests · new ones on Monday", 0)
	for i, q in view.weekly do
		questRow(r.weekly, q, false, i)
	end
	section(r.weekly, "calendar", "Play calendar · Glory a day you play", 10)
	calendar(r.weekly, view, 11)
	-- the play streak and the flame it earned (Sim.Login.flameTier), and the rule that keeps it kind
	local box = Instance.new("Frame")
	box.Name = "StreakBox"
	box.BackgroundTransparency = 1
	box.Size = UDim2.new(1, 0, 0, STREAK_HEIGHT)
	box.LayoutOrder = 12
	box.Parent = r.weekly
	local streak = if view.streak > 0
		then string.format("%d-day play streak", view.streak)
		else "Finish a match to start a play streak"
	local line = Widgets.label(
		box,
		string.format(
			"%s%s%s",
			streak,
			if view.best > 0 then " · best " .. view.best else "",
			if view.flame > 0 then " · " .. FLAMES[view.flame] else ""
		),
		Theme.text.small,
		18
	)
	line.Name = "Streak"
	line.TextWrapped = false
	line.TextTruncate = Enum.TextTruncate.AtEnd
	Widgets.leadIcon(line, FLAME_ICONS[view.flame] or "fire", 16, Theme.space.xs)
	local rule = Widgets.hint(box, "One missed day a week doesn't break it", Theme.text.small, 18)
	rule.Position = UDim2.fromOffset(0, 18)
	rule.TextWrapped = false
	rule.TextTruncate = Enum.TextTruncate.AtEnd
	updateAd()
end

local function refreshButton()
	local inLobby = LobbyState.phase() ~= "None" or ClientState.snapshot() == nil
	openButton.Visible = inLobby and not panel.Visible
	Widgets.setCount(badge, QuestState.readyCount())
end

local function column(parent: Instance, name: string, width: UDim, order: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.Size = UDim2.new(width.Scale, width.Offset, 1, 0)
	f.LayoutOrder = order
	f.Parent = parent
	Widgets.list(f, false, ROW_GAP)
	return f
end

local setOpen: (boolean) -> ()

-- The panel's contents, built when it opens: header (title, Glory, rerolls, the ad button, close), two columns.
local function build(): Refs
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, BAR)
	header.LayoutOrder = 1
	header.Parent = panel
	local close = Widgets.iconButton(header, "close", "✕", BAR, nil, function()
		setOpen(false)
	end)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(1, 0)
	local info = Instance.new("Frame")
	info.Name = "Info"
	info.BackgroundTransparency = 1
	info.Size = UDim2.new(1, -(BAR + AD_WIDTH + 2 * Theme.space.m), 1, 0)
	info.Parent = header
	Widgets.list(info, true, Theme.space.m)
	local title = Widgets.title(info, "Quests", Theme.text.title, BAR)
	title.Size = UDim2.fromOffset(0, BAR)
	title.AutomaticSize = Enum.AutomaticSize.X
	title.TextTruncate = Enum.TextTruncate.None
	title.LayoutOrder = 1
	Widgets.leadIcon(title, "scroll", Theme.size.iconButton)
	local glory = Widgets.chip(info, "medal", "", nil, Theme.size.chip)
	glory.Name = "Glory"
	glory.LayoutOrder = 2
	local rerolls = Widgets.label(info, "", Theme.text.small, BAR)
	rerolls.Name = "Rerolls"
	rerolls.Size = UDim2.fromScale(REROLL_SHARE, 1)
	rerolls.TextColor3 = Theme.color.textDim
	rerolls.LayoutOrder = 3
	Widgets.leadIcon(rerolls, "reroll", Theme.size.icon, Theme.space.xs)

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, 0, 1, -(BAR + Theme.space.xs))
	body.LayoutOrder = 2
	body.Parent = panel
	Widgets.list(body, true, COLUMN_GAP).VerticalAlignment = Enum.VerticalAlignment.Top
	local daily = column(body, "Daily", UDim.new(LEFT_SHARE, -COLUMN_GAP // 2), 1)
	local weekly = column(body, "Weekly", UDim.new(1 - LEFT_SHARE, -COLUMN_GAP // 2), 2)
	return { glory = glory, rerolls = rerolls, daily = daily, weekly = weekly }
end

setOpen = function(open: boolean)
	panel.Visible = open
	if open and ui == nil then
		ui = build()
	elseif not open and ui ~= nil then
		Widgets.clear(panel) -- a closed screen keeps no rows or buttons (rebuilt when it opens)
		ui = nil
	end
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

-- "📜 Quests", with the number of finished quests waiting to be claimed (for buttons in other panels; the emoji
-- becomes the scroll icon).
function QuestsUI.buttonText(): string
	local ready = QuestState.readyCount()
	return if ready > 0 then string.format("📜 Quests · %d to claim", ready) else "📜 Quests"
end

-- The same, short enough for a small button.
function QuestsUI.shortButtonText(): string
	local ready = QuestState.readyCount()
	return if ready > 0 then string.format("📜 Quests (%d)", ready) else "📜 Quests"
end

function QuestsUI.init()
	gui = Widgets.screen("Quests", 31) -- above the shop and the lobby screens
	-- the Lobby's scroll button, next to the cart (the lobby screens cover the top bar), in a screen of its own under
	-- the shop (30) and the private-server sheet (31), so a full-screen panel covers it instead of the other way round
	local buttonGui = Widgets.screen("QuestsButton", 29)

	openButton = Widgets.cornerButton(buttonGui, 1, "scroll", "QuestsButton", Theme.color.primary, function()
		setOpen(true)
	end)
	badge = Widgets.countBadge(openButton)

	panel = Widgets.window(gui, "QuestsPanel")
	Widgets.list(panel, false, Theme.space.xs)

	-- over the panel's header, left of its close cross (the panel is 8 px from the screen's edges, padded 12 / 8)
	adButton = Widgets.iconTextButton(gui, "video", "", AD_WIDTH, Widgets.BUTTON, function()
		Ads.watch()
		updateAd()
	end, "AdButton")
	adButton.TextSize = Theme.text.small
	adButton.TextWrapped = false
	adButton.ZIndex = 2
	adButton.AnchorPoint = Vector2.new(1, 0)
	adButton.Position = UDim2.new(1, -(Theme.space.m + Theme.space.l + BAR + Theme.space.m), 0, 2 * Theme.space.m)
	adButton.Visible = false

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
