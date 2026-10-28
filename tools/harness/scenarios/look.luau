--!nocheck
-- The map's look at three zooms: whole map, region around the capital, the capital close up.

local Emulator = require("../Emulator")
local MapGrid = require("../../../src/shared/MapGrid")
local H = require("../H")

local function run()
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	Emulator.run(2)
	H.shot(alice, "whole_map")
	local state = H.state()
	local capital = state.nations[H.myNation(alice)].capital
	local MapView = H.client(alice, "MapView")
	MapView.centreOn(H.provinceMap(alice, capital), false)
	Emulator.pinch(alice, 3.5)
	Emulator.run(2)
	H.shot(alice, "region")
	-- an idle neutral garrison's badge shows only where it covers no province name and no other garrison's badge;
	-- the others keep their grey token. Checked from the objects on the map, each badge as wide as its padding plus
	-- its text estimated the way the layout estimates it.
	local Renderer = H.client(alice, "MapRenderer")
	local LabelLayout = H.client(alice, "LabelLayout")
	local Vector2 = Emulator.roblox.Vector2
	local function canvasPoint(pos): any -- a position on the map's canvas, on screen
		local m = Renderer.mapSize()
		return MapView.toScreen(Vector2.new(pos.X.Scale * m.X, pos.Y.Scale * m.Y))
			+ Vector2.new(pos.X.Offset, pos.Y.Offset)
	end
	local function garrisonBadges(): (number, number, string?)
		local s = H.state()
		local names, badges, waiting = {}, {}, 0
		for id in s.provinces do
			local name = H.mapObject(alice, "P" .. id)
			if name then
				local c = canvasPoint(name.Position)
				local pips = name:FindFirstChild("Pips")
				local h = name.Size.Y.Offset
					+ (if pips and pips.Visible then pips.Position.Y.Offset + pips.Size.Y.Offset else 0)
				table.insert(names, { x = c.X - name.Size.X.Offset / 2, y = c.Y, w = name.Size.X.Offset, h = h, what = name.Text })
			end
		end
		local count = {}
		for _, a in s.armies do
			count[a.location] = (count[a.location] or 0) + 1
		end
		for id, a in s.armies do
			local idle = a.owner == 0 and not a.rebel and not a.inBattle and count[a.location] == 1
			local token = if idle then H.mapObject(alice, "Army" .. id) else nil
			local badge = token and token:FindFirstChild("Strength")
			if badge and badge.Visible then
				local pad = badge:FindFirstChildOfClass("UIPadding")
				local w = pad.PaddingLeft.Offset + pad.PaddingRight.Offset + LabelLayout.textWidth(badge.Text, badge.TextSize)
				local t = canvasPoint(token.Position)
				local bottom = t.Y - token.Size.Y.Offset / 2 + badge.Position.Y.Offset
				local h = badge.Size.Y.Offset
				table.insert(badges, { x = t.X + badge.Position.X.Offset - w / 2, y = bottom - h, w = w, h = h, what = "the garrison in " .. s.provinces[a.location].name })
			elseif token then
				waiting += 1
			end
		end
		local function overlap(a, b): boolean
			return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
		end
		for i, b in badges do
			for _, n in names do
				if overlap(b, n) then
					return #badges, waiting, b.what .. "'s badge covers the name " .. n.what
				end
			end
			for j = i + 1, #badges do
				if overlap(b, badges[j]) then
					return #badges, waiting, b.what .. "'s badge covers " .. badges[j].what .. "'s"
				end
			end
		end
		return #badges, waiting, nil
	end
	local shownBadges, waitingBadges, problem = garrisonBadges()
	H.expect(problem == nil, string.format("at the region zoom, %d garrison badges show where there's room and %d wait (%s)", shownBadges, waitingBadges, problem or "none covers a name or another"))
	-- the region zoom shows the whole-map painting; zoomed in, the close-up detail is laid over it
	local function closeUp()
		local canvas = MapView.canvas()
		local layer = canvas and canvas:FindFirstChild("Image")
		return layer and layer:FindFirstChild("Detail")
	end
	H.expect(closeUp() == nil, "no close-up detail at the region zoom")
	Emulator.pinch(alice, 3)
	Emulator.run(2)
	H.expect(closeUp() ~= nil and closeUp().Visible, "the close-up detail shows at close zoom")
	H.shot(alice, "close_up")
	shownBadges, waitingBadges, problem = garrisonBadges()
	H.expect(shownBadges > 0 and problem == nil, string.format("close up, %d garrison badges show and %d wait (%s)", shownBadges, waitingBadges, problem or "none covers a name or another"))

	-- the nearest mountain, the nearest coast and the nearest forest, close up
	local map = H.client(alice, "ClientState").map()
	local here = H.provinceMap(alice, capital)
	local function nearest(test)
		local best, bestD = nil, math.huge
		for _, def in map.provinces do
			local d = (H.provinceMap(alice, def.id) - here).Magnitude
			if test(def) and d < bestD then
				best, bestD = def.id, d
			end
		end
		return best
	end
	local mountain = nearest(function(def)
		return def.terrain == "Mountain"
	end)
	if mountain then
		-- (centre first and let the camera arrive: a pinch holds the point under the fingers where it is)
		MapView.centreOn(H.provinceMap(alice, mountain), false)
		Emulator.run(1.5)
		Emulator.pinch(alice, 2)
		Emulator.run(2)
		H.shot(alice, "mountain")
	end
	local grid = MapGrid.decode(map)
	local coast, coastD = nil, math.huge
	for y = 1, grid.height - 2, 2 do
		for x = 1, grid.width - 2, 2 do
			if MapGrid.at(grid, x, y) ~= 0 and MapGrid.at(grid, x, y + 1) == 0 then
				local p = Emulator.roblox.Vector2.new(x, y)
				if (p - here).Magnitude < coastD then
					coast, coastD = p, (p - here).Magnitude
				end
			end
		end
	end
	if coast then
		MapView.centreOn(coast, false)
		Emulator.run(2)
		H.expect(closeUp() ~= nil and closeUp().Visible, "the close-up follows the camera")
		H.shot(alice, "coast")
	end
	local woods = { forest = true, jungle = true, taiga = true, wildwood = true, crystalgrove = true }
	local forest = nearest(function(def)
		return woods[def.biome] == true
	end)
	if forest then
		MapView.centreOn(H.provinceMap(alice, forest), false)
		Emulator.run(2)
		H.shot(alice, "forest")
	end

	-- zoomed out again, the close-up's image is freed
	MapView.showWholeMap()
	Emulator.run(0.5)
	H.expect(closeUp() == nil, "the close-up is freed when zoomed out")

	-- the overlays at each zoom step: names with pip bars, army badges, a siege's pill and power badges, the
	-- selected army and province in gold
	local Army = require("../../../src/shared/Sim/Army")
	local Primordial = require("../../../src/shared/Sim/Primordial")
	local state = H.state()
	local A = H.myNation(alice)
	state.tick = 179 -- War (powers need it)
	Emulator.run(1.5)
	local siegeAt, siegeD = nil, math.huge
	for id, p in state.provinces do
		local d = (H.provinceMap(alice, id) - here).Magnitude
		if p.owner == nil and p.terrain ~= "Mountain" and d < siegeD then
			siegeAt, siegeD = id, d
		end
	end
	for id, a in state.armies do
		if a.location == siegeAt then
			state.armies[id] = nil -- no garrison: the army goes straight to the siege
		end
	end
	Army.spawn(state, A, siegeAt, 2000)
	local guard = Army.spawn(state, A, capital, 3000)
	state.nations[2].charges = 5
	H.expect(Primordial.use(state, { nation = 2 }, "Shield", capital), "a shield on the capital")
	H.expect(Primordial.use(state, { nation = 2 }, "Blessing", capital), "and a blessing")
	Emulator.run(6) -- their toasts come and go
	Renderer.select(capital)
	Renderer.selectArmy(guard.id)
	Emulator.run(0.5)
	H.shot(alice, "overlays_whole")
	MapView.centreOn(here, true)
	Emulator.run(1.5)
	H.shot(alice, "overlays_region")
	Emulator.pinch(alice, 3)
	MapView.centreOn(here, false) -- the pinch zooms round the middle of the screen: back to the capital
	Emulator.run(2)
	H.shot(alice, "overlays_close")
	local Theme = H.client(alice, "UI.Theme")
	local name = H.mapObject(alice, "P" .. capital)
	H.expect(name ~= nil and name.TextColor3 == Theme.color.gold, "the selected province's name is gold")
	local pips = name:FindFirstChild("Pips")
	H.expect(pips ~= nil and pips.Visible, "with its development pips under it")
	local text, icon = H.badge(alice, guard.id)
	local infantry = require("../../../src/shared/Sim/Troops").icon(state.mapId, "Infantry") -- the map's own name for it
	H.expect(text == "3k" and icon == infantry, "the army's badge: its main troop's icon (" .. infantry .. ") and 3k")
	local badge = H.mapObject(alice, "Army" .. guard.id):FindFirstChild("Strength")
	H.expect(badge:FindFirstChildOfClass("UIStroke").Color == Theme.color.gold, "the selected army's badge is outlined in gold")
	-- a province's status pills as "icon:text" words, sorted
	local function pills(provinceId: number): string
		local row = H.mapObject(alice, "Status" .. provinceId)
		local out = {}
		for _, pill in if row then row:GetChildren() else {} do
			local mark = pill:FindFirstChild("Icon")
			if pill:IsA("TextLabel") and pill.Visible and mark then
				table.insert(out, mark:GetAttribute("Icon") .. ":" .. pill.Text)
			end
		end
		table.sort(out)
		return table.concat(out, " ")
	end
	H.expect(string.match(pills(capital), "^blessing:%d+ powerShield:%d+$") ~= nil, "the capital's status row: blessing and shield with their seconds (" .. pills(capital) .. ")")
	H.expect(string.match(pills(siegeAt), "^hourglass:%d+%%$") ~= nil, "the siege shows its progress (" .. pills(siegeAt) .. ")")
end

return { run = run }
