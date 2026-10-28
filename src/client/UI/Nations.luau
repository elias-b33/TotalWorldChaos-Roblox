--!strict
-- Left drawer (docs/DESIGN.md "UI and controls"): every nation with its flag, province count and your relation,
-- and at the top the way to your quests during a match (the top bar has no room for another button).
-- One row per nation: flag, race, who plays it, name (in a nameplate frame if they own one), streak flame, VIP badge,
-- then provinces and your relation as pixel icons. Under the rows, your race and its one-line bonus.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Catalogue = require(ReplicatedStorage.Shared.Catalogue)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Cosmetics = require(Client.Cosmetics)
local RaceInfo = require(Client.RaceInfo)
local Relations = require(Client.Relations)
local HudLayout = require(script.Parent.HudLayout)
local Icons = require(script.Parent.Icons)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local WIDTH = 256 -- the longest name (Ashen Dominion) fits next to its flag and race icon
local ROW_HEIGHT = 22 -- ten rows, the header and the race line fit a 390 px tall phone
local RACE_LINE_HEIGHT = 34 -- two lines of small text
local COUNT_WIDTH = 54
local TITLE_MAX_WIDTH = 96 -- a worn title after the name, cut with … past this

local Nations = {}

-- The play-streak flames after a player's nation name, by tier (Sim.Login.flameTier): 3, 7, 14 and 30 days.
local FLAMES: { { string } } = { { "fire" }, { "fire", "fire" }, { "fireBlue" }, { "fireBlue", "crown" } }

local drawer: Frame
local rows: Frame
local raceLine: TextLabel
local questsButton: TextButton? = nil
local questsText: () -> string = function()
	return "📜 Quests"
end

local function renderQuestsButton()
	local b = questsButton
	if b then
		local text = questsText()
		Widgets.setIconText(b, text, "scroll")
		b.Name = text -- the full caption, emoji and all, is what the harness presses
	end
end

local function render()
	if not drawer.Visible then
		return
	end
	renderQuestsButton()
	local snap = ClientState.snapshot()
	Widgets.clear(rows)
	if snap == nil then
		raceLine.Visible = false
		return
	end
	local me = ClientState.myNation()
	local mine = ClientState.nation(me)
	raceLine.Visible = mine ~= nil
	if mine then
		raceLine.Text = string.format("%s: %s", RaceInfo.name(mine.race), RaceInfo.bonus(mine.race))
		Icons.set(raceLine:FindFirstChild("Icon") :: GuiObject, RaceInfo.icon(mine.race))
	end
	local list = table.clone(snap.nations)
	table.sort(list, function(a, b)
		return Relations.score(a.id) > Relations.score(b.id)
	end)
	for i, n in list do
		local row = Instance.new("Frame")
		row.Name = "Nation" .. n.id
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		row.LayoutOrder = i
		row.Parent = rows
		local left = Instance.new("Frame")
		left.BackgroundTransparency = 1
		left.Size = UDim2.new(1, -(COUNT_WIDTH + 22), 1, 0)
		left.Parent = row
		left.ClipsDescendants = true -- a very long name and title stop at the province count
		Widgets.list(left, true, Theme.space.xs)
		-- the nation's flag (cosmetic), in its colour
		local looks = Cosmetics.of(n.id)
		local flag = Cosmetics.flagLabel(left, looks.flag, n.colorIndex, UDim2.fromOffset(20, 15))
		flag.LayoutOrder = 0
		local race = Widgets.icon(left, RaceInfo.icon(n.race), 16) -- the nation's race
		race.Name = "Race"
		race.LayoutOrder = 1
		local who = if n.id == me then "star" elseif n.controller == "Player" then "manpower" else nil
		if who then
			Widgets.icon(left, who, 16).LayoutOrder = 2
		end
		local label = Widgets.label(left, n.name, Theme.text.small, ROW_HEIGHT - 4)
		label.Size = UDim2.fromOffset(0, ROW_HEIGHT - 4)
		label.AutomaticSize = Enum.AutomaticSize.X
		label.TextWrapped = false
		label.LayoutOrder = 3
		if n.eliminated then
			label.TextColor3 = Theme.color.textDim
		end
		-- nameplate frame (cosmetic): an outline around the name
		local frameColor = Cosmetics.frameColor(looks.frame)
		if frameColor then
			label.BackgroundTransparency = 0.8
			label.BackgroundColor3 = frameColor
			Widgets.corner(label, Theme.radius.s)
			Widgets.padding(label, Theme.space.xs, 0)
			Widgets.stroke(label, frameColor)
		end
		for k, flame in FLAMES[looks.flame or 0] or {} do -- play-streak reward (MONETIZATION 5.6)
			Widgets.icon(left, flame, 16).LayoutOrder = 3 + k
		end
		if looks.vip then
			local vip = Widgets.badge(left, "VIP", Theme.color.gold)
			vip.TextColor3 = Theme.color.textDark
			vip.Size = UDim2.fromOffset(0, 18)
			vip.LayoutOrder = 9
		end
		-- a title after the name (MONETIZATION 3.2: an achievement's or the season pass's): last and capped, so a long
		-- name and title cut the title, nothing else
		local title = if looks.title then Catalogue.item(looks.title) else nil
		if title then
			local t = Widgets.label(left, "· " .. title.art, Theme.text.small, ROW_HEIGHT - 4)
			t.Name = "Title"
			t.Size = UDim2.fromOffset(0, ROW_HEIGHT - 4)
			t.AutomaticSize = Enum.AutomaticSize.X
			t.TextWrapped = false
			t.TextTruncate = Enum.TextTruncate.AtEnd
			t.TextColor3 = Theme.color.goldPale
			t.LayoutOrder = 10
			local cap = Instance.new("UISizeConstraint")
			cap.MaxSize = Vector2.new(TITLE_MAX_WIDTH, math.huge)
			cap.Parent = t
		end
		-- provinces held, then your relation (at war, allied, truce) or a skull once eliminated
		local count = Widgets.chip(row, "flag", tostring(Relations.provinceCount(n.id)), COUNT_WIDTH, 22)
		count.Name = "Provinces"
		count.AnchorPoint = Vector2.new(1, 0.5)
		count.Position = UDim2.new(1, -22, 0.5, 0)
		local status = if n.eliminated then "skull" else Icons.fromEmoji(Relations.icon(me, n.id))
		if status then
			local mark = Widgets.icon(row, status, 18)
			mark.AnchorPoint = Vector2.new(1, 0.5)
			mark.Position = UDim2.fromScale(1, 0.5)
		end
	end
end

function Nations.toggle()
	drawer.Visible = not drawer.Visible
	if not drawer.Visible then
		Widgets.clear(rows) -- a closed drawer keeps no rows (rebuilt when it opens)
	end
	render()
end

-- onQuests: opens the Quests screen; buttonText: its button's text (with the number of quests to claim).
function Nations.init(onQuests: (() -> ())?, buttonText: (() -> string)?)
	local gui = Widgets.screen("Nations", 4)
	drawer = Widgets.panel(gui, WIDTH)
	drawer.Name = "Drawer"
	drawer.Visible = false
	Widgets.list(drawer, false, Theme.space.xs)
	-- the title on a plate on the drawer's top edge, and beside it, on the same edge, the way to the quests (a row
	-- under ten nations would run off a phone)
	local header = Widgets.header(drawer, "Nations", "globe")
	if onQuests then
		questsText = buttonText or questsText
		local b = Widgets.iconTextButton(header, "scroll", "", 112, Widgets.GOLD, onQuests)
		b.Name = "QuestsButton"
		b.TextSize = Theme.text.small
		b.ZIndex = 3
		b.AnchorPoint = Vector2.new(1, 0)
		local pad = drawer:FindFirstChildOfClass("UIPadding") :: UIPadding
		b.Position = UDim2.new(1, pad.PaddingRight.Offset - 6, 0, -pad.PaddingTop.Offset - 22)
		questsButton = b
		renderQuestsButton()
	end
	rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	rows.Size = UDim2.fromScale(1, 0)
	rows.AutomaticSize = Enum.AutomaticSize.Y
	rows.LayoutOrder = 1
	rows.Parent = drawer
	Widgets.list(rows, false, 1)
	raceLine = Widgets.label(drawer, "", Theme.text.small, RACE_LINE_HEIGHT)
	raceLine.Name = "RaceLine"
	raceLine.TextColor3 = Theme.color.goldPale
	raceLine.TextYAlignment = Enum.TextYAlignment.Top
	raceLine.TextTruncate = Enum.TextTruncate.AtEnd
	raceLine.LayoutOrder = 2
	raceLine.Visible = false
	Widgets.leadIcon(raceLine, "humans", 16, Theme.space.xs)
	-- under the top bar, with room for what stands on its top edge (the Quests button reaches 22 px above it)
	local function place()
		local above = if onQuests then Widgets.BUTTON_HEIGHT // 2 else Theme.size.titlePlate // 2
		Widgets.fit(drawer, nil, UDim2.fromOffset(Theme.space.m, HudLayout.contentTop() + above))
	end
	place()
	HudLayout.onChange(place)
	Widgets.fitScreen(gui) -- tablets: the screen's roots grow with the UI's scale
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
