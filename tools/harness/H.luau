--!nocheck
-- Shared helpers for the harness scenarios (tools/harness/scenarios/*.luau): screenshots, expectations,
-- finding and pressing GUI objects, the match state. play.luau runs the scenarios.

local fs = require("@lune/fs")
local process = require("@lune/process")

local Config = require("../../src/shared/Config")
local Emulator = require("./Emulator")
local MapGrid = require("../../src/shared/MapGrid")
local Scene = require("./Scene")

local OUT = "tools/harness/out"
local PRIVATE_OWNER = 5001 -- the private scenario's server owner (Workspace "PrivateServerOwner")
local shotCount = 0
local shotDir = OUT

local H = {}

-- Start a scenario: its screenshots go to tools/harness/out/<name>/, numbered from 01.
function H.begin(name: string)
	shotCount = 0
	shotDir = OUT .. "/" .. name
	if fs.isDir(shotDir) then
		fs.removeDir(shotDir)
	end
	fs.writeDir(shotDir)
end

function H.shot(client, name: string)
	shotCount += 1
	local base = string.format("%s/%02d_%s", shotDir, shotCount, name)
	Scene.save(client, base .. ".json")
	local r = process.exec("python3", { "tools/harness/render_scene.py", base .. ".json", base .. ".png" })
	if not r.ok then
		error("render failed: " .. r.stderr)
	end
	if process.env.KEEP_SCENE == nil then
		fs.removeFile(base .. ".json")
		for _, entry in fs.readDir(shotDir) do
			if string.find(entry, "%.rgba$") then
				fs.removeFile(shotDir .. "/" .. entry)
			end
		end
	end
	print("  📸 " .. base .. ".png")
end

function H.expect(cond, message: string)
	if not cond then
		error("EXPECTATION FAILED: " .. message, 2)
	end
	print("  ✓ " .. message)
end

-- Whether a GUI object is on screen: it and every ancestor visible, its ScreenGui enabled.
local function shown(inst): boolean
	local node = inst
	while node and not node:IsA("PlayerGui") do
		if (node:IsA("GuiObject") and not node.Visible) or (node:IsA("ScreenGui") and not node.Enabled) then
			return false
		end
		node = node.Parent
	end
	return true
end

-- The text of the first visible text object named `name` (chips and labels whose emoji is now a pixel icon, e.g.
-- the top bar's "Level", "Clock", or the power button's "Charges"), or nil.
function H.textOf(client, name: string): string?
	for _, d in client.localPlayer.PlayerGui:GetDescendants() do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Name == name and shown(d) then
			return d.Text
		end
	end
	return nil
end

-- True when a visible text object named `name` shows exactly `text` (one of several cards' chips, say).
function H.hasText(client, name: string, text: string): boolean
	for _, d in client.localPlayer.PlayerGui:GetDescendants() do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Name == name and d.Text == text and shown(d) then
			return true
		end
	end
	return false
end

-- True when the UI shows the pixel icon `icon` (src/client/IconArt.luau) somewhere.
function H.iconShown(client, icon: string): boolean
	for _, d in client.localPlayer.PlayerGui:GetDescendants() do
		if d:IsA("GuiObject") and d:GetAttribute("Icon") == icon and shown(d) then
			return true
		end
	end
	return false
end

-- The GUI object named `container` (a shop card, a quest row, a season cell) and everything in it, or nil.
local function within(client, container: string)
	local root = client.localPlayer.PlayerGui:FindFirstChild(container, true)
	if root == nil then
		return nil
	end
	local all = root:GetDescendants()
	table.insert(all, 1, root)
	return all
end

-- True when `obj` (or a visible object in it) shows the pixel icon `icon`.
local function hasIcon(obj, icon: string): boolean
	for _, d in { obj, table.unpack(obj:GetDescendants()) } do
		if d:IsA("GuiObject") and d:GetAttribute("Icon") == icon and shown(d) then
			return true
		end
	end
	return false
end

-- Press a visible button inside the object named `container` (the container itself counts) whose text contains
-- `needle` or whose Name is `needle`; with `icon`, the button must also show that pixel icon (a Glory price shows
-- the medal, a reroll the reroll arrows). Errors if there is none.
function H.pressIn(client, container: string, needle: string, icon: string?)
	local all = within(client, container)
	assert(all, container .. " is not on screen")
	for _, d in all do
		local text = d:IsA("TextButton") and string.find(d.Text, needle, 1, true) ~= nil
		if d:IsA("GuiButton") and shown(d) and (text or d.Name == needle) and (icon == nil or hasIcon(d, icon)) then
			Emulator.eventOf(d, "Activated"):Fire(nil, 1)
			return d
		end
	end
	error(container .. " has no button " .. needle .. (if icon then " with the " .. icon .. " icon" else ""))
end

-- True when a visible text object inside the object named `container` shows a text containing `needle`.
function H.within(client, container: string, needle: string): boolean
	for _, d in within(client, container) or {} do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and shown(d) and string.find(d.Text, needle, 1, true) then
			return true
		end
	end
	return false
end

-- True when the pixel icon `icon` shows inside the object named `container`.
function H.iconIn(client, container: string, icon: string): boolean
	local all = within(client, container)
	return all ~= nil and hasIcon(all[1], icon)
end

-- The pixel icon a label or button made by the UI kit shows (its child "Icon"), or nil.
function H.iconOf(obj): string?
	local icon = obj and obj:FindFirstChild("Icon")
	return if icon then icon:GetAttribute("Icon") else nil
end

-- The visible text objects (in the ScreenGui named `screen`, or anywhere) whose text contains `text` and whose own
-- pixel icon is `icon`: where an emoji used to lead the text ("🏴 3k" is now a Rebels flag icon and "3k").
function H.iconTexts(client, icon: string, text: string, screen: string?)
	local root = if screen then client.localPlayer.PlayerGui:FindFirstChild(screen) else client.localPlayer.PlayerGui
	local out = {}
	for _, d in if root then root:GetDescendants() else {} do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and string.find(d.Text, text, 1, true) and shown(d) then
			local mark = d:FindFirstChild("Icon")
			if mark and mark:GetAttribute("Icon") == icon and shown(mark) then
				table.insert(out, d)
			end
		end
	end
	return out
end

function H.iconText(client, icon: string, text: string, screen: string?): boolean
	return #H.iconTexts(client, icon, text, screen) > 0
end

-- The map's overlay named `name` (e.g. "Crown1", "Status12") when it is on screen, or nil.
function H.mapObject(client, name: string)
	local map = client.localPlayer.PlayerGui:FindFirstChild("Map")
	local obj = map and map:FindFirstChild(name, true)
	return if obj and shown(obj) then obj else nil
end

-- An army's strength badge on the map, when it shows: its text and its pixel icon (nil, nil when hidden).
function H.badge(client, armyId: number): (string?, string?)
	local token = H.mapObject(client, "Army" .. armyId)
	local badge = token and token:FindFirstChild("Strength")
	local icon = badge and badge:FindFirstChild("Icon")
	if badge == nil or icon == nil or not shown(badge) then
		return nil, nil
	end
	return badge.Text, icon:GetAttribute("Icon")
end

-- A server-side module's table, e.g. H.server("Services.MatchService").
function H.server(path: string)
	local node = Emulator.server.dm:GetService("ServerScriptService").Server
	for _, name in string.split(path, ".") do
		node = node:FindFirstChild(name)
	end
	return Emulator.server.modules[node]
end

-- The client's copy of a client module, e.g. H.client(c, "ClientState").
function H.client(client, path: string)
	local node = client.localPlayer.PlayerScripts.Client
	for _, name in string.split(path, ".") do
		node = node:FindFirstChild(name)
	end
	return client.modules[node]
end

-- A player's save as the DataStore holds it ({ Data, MetaData, ... }): Studio saves go to their own store.
function H.saved(userId: number)
	local Data = H.server("Services.PlayerDataService")
	local entry = Emulator.dataStores[Data.STORE_NAME][Data.KEY_PREFIX .. userId]
	return entry and entry.value
end

-- How many times a player's save has been written.
function H.writes(userId: number): number
	local Data = H.server("Services.PlayerDataService")
	local entry = Emulator.dataStores[Data.STORE_NAME][Data.KEY_PREFIX .. userId]
	return if entry then entry.version else 0
end

-- Did the server print a line containing `needle`?
function H.logged(needle: string): boolean
	for _, line in Emulator.log() do
		if string.find(line, needle, 1, true) then
			return true
		end
	end
	return false
end

function H.state()
	return H.server("Services.MatchService").state()
end

-- The server's copy of a shared module (ReplicatedStorage.Shared), e.g. H.shared("Config") to change a number for a
-- test on the running server.
function H.shared(path: string)
	local node = Emulator.server.dm:GetService("ReplicatedStorage").Shared
	for _, name in string.split(path, ".") do
		node = node:FindFirstChild(name)
	end
	return Emulator.server.modules[node]
end

-- Wait (game time) until a client shows a text containing `text` (toasts queue up one after another).
function H.waitText(client, text: string, seconds: number?): boolean
	local deadline = Emulator.now() + (seconds or 12)
	while Emulator.findText(client, text) == nil and Emulator.now() < deadline do
		Emulator.run(0.25)
	end
	return Emulator.findText(client, text) ~= nil
end

-- The GUI object named `name` anywhere on the client's screen, when it is shown (nil otherwise).
function H.find(client, name: string)
	local obj = client.localPlayer.PlayerGui:FindFirstChild(name, true)
	return if obj and shown(obj) then obj else nil
end

-- A visible button whose Name is `name` or whose text contains it.
function H.hasButton(client, name: string): boolean
	for _, b in Emulator.buttons(client) do
		if b.button.Name == name or string.find(b.text, name, 1, true) then
			return true
		end
	end
	return false
end

function H.myNation(client)
	return H.client(client, "ClientState").myNation()
end

-- A province's centre in map pixels (the 2D map's coordinates).
function H.provinceMap(client, provinceId: number)
	return H.client(client, "MapRenderer").centerOf(provinceId)
end

-- Centre the view on a province, wait for the camera to settle, and tap a pixel of it on screen, away from the
-- tokens standing at its centre.
function H.tapProvince(client, provinceId: number, closeUp: boolean?)
	local MapView = H.client(client, "MapView")
	MapView.centreOn(H.provinceMap(client, provinceId), closeUp ~= false)
	Emulator.run(1.5)
	local map = H.client(client, "ClientState").map()
	local grid = MapGrid.decode(map)
	local c = H.provinceMap(client, provinceId)
	local spot = c
	for r = 12, 3, -1 do
		local p = c + Emulator.roblox.Vector2.new(0, r)
		if MapGrid.at(grid, p.X, p.Y) == provinceId then
			spot = p
			break
		end
	end
	local screen = MapView.toScreen(spot)
	Emulator.tapScreen(client, screen.X, screen.Y)
	Emulator.run(0.3)
end

function H.provinceByName(name: string): number
	local state = H.state()
	for id, p in state.provinces do
		if p.name == name then
			return id
		end
	end
	error("no province " .. name)
end

H.OUT = OUT
H.PRIVATE_OWNER = PRIVATE_OWNER
H.shown = shown
H.hasIcon = hasIcon

return H
