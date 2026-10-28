--!nocheck
-- A small Roblox emulator for Lune, so the real server and client scripts can run headlessly.
--
-- What it gives the scripts: real Roblox instances (from @lune/roblox, so property names are checked against the
-- Roblox API), plus the parts Lune lacks: events, remotes between a server and several clients, Players,
-- a task scheduler on virtual time (a 25-minute match runs in seconds), RunService frames, touch input,
-- a camera with real projection maths and raycasts against parts.
--
-- It is a test tool, not a perfect Roblox: physics, rendering and replication of workspace are not emulated.

local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local stdio = require("@lune/stdio")

local Instance = roblox.Instance

local Emulator = {}

---------------------------------------------------------------------------------------------- logging

local errors: { string } = {}
local warnings: { string } = {}
local logLines: { string } = {}
local quiet = false

function Emulator.setQuiet(q: boolean)
	quiet = q
end

local function log(line: string)
	table.insert(logLines, line)
	if not quiet then
		print(line)
	end
end

function Emulator.errors()
	return errors
end

function Emulator.warnings()
	return warnings
end

function Emulator.log()
	return logLines
end

---------------------------------------------------------------------------------------------- scheduler

local now = 0
local seq = 0
local queue = {} -- { at, seq, co, args }
local cancelled: { [thread]: boolean } = {}
local threadMachine: { [thread]: any } = {}

local function resume(co: thread, ...)
	if cancelled[co] or coroutine.status(co) == "dead" then
		return
	end
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		local who = threadMachine[co] and threadMachine[co].name or "?"
		local msg = string.format("[%s] ERROR %s\n%s", who, tostring(err), debug.traceback(co))
		table.insert(errors, msg)
		log(msg)
	end
end

local function schedule(co: thread, at: number, ...)
	seq += 1
	table.insert(queue, { at = at, seq = seq, co = co, args = table.pack(...) })
end

local function newThread(fn: any, owner: any): thread
	if type(fn) == "thread" then
		return fn
	end
	local co = coroutine.create(fn)
	threadMachine[co] = owner or threadMachine[coroutine.running()]
	return co
end

local task = {}

function task.spawn(fn, ...)
	local co = newThread(fn)
	resume(co, ...)
	return co
end

function task.defer(fn, ...)
	local co = newThread(fn)
	schedule(co, now, ...)
	return co
end

function task.delay(t, fn, ...)
	local co = newThread(fn)
	schedule(co, now + (t or 0), ...)
	return co
end

function task.wait(t)
	local co = coroutine.running()
	local start = now
	schedule(co, now + math.max(t or 0, 1 / 60))
	coroutine.yield()
	return now - start
end

function task.cancel(co)
	cancelled[co] = true
end

function Emulator.now(): number
	return now
end

-- Run every thread due up to `untilTime`, in time order.
local function runDue(untilTime: number)
	while true do
		local bestIndex, best = nil, nil
		for i, item in queue do
			if item.at <= untilTime and (best == nil or item.at < best.at or (item.at == best.at and item.seq < best.seq)) then
				bestIndex, best = i, item
			end
		end
		if best == nil then
			break
		end
		table.remove(queue, bestIndex)
		now = math.max(now, best.at)
		resume(best.co, table.unpack(best.args, 1, best.args.n))
	end
end

---------------------------------------------------------------------------------------------- signals

local Signal = {}
Signal.__index = Signal

function Signal.new(queueWhenUnconnected: boolean?)
	return setmetatable({ conns = {}, queued = if queueWhenUnconnected then {} else nil, waiting = {} }, Signal)
end

function Signal:Connect(fn)
	local conn = { Connected = true }
	function conn.Disconnect()
		conn.Connected = false
	end
	conn.fn = fn
	table.insert(self.conns, conn)
	if self.queued and #self.queued > 0 then
		local pending = self.queued
		self.queued = {}
		for _, args in pending do
			task.spawn(fn, table.unpack(args, 1, args.n))
		end
	end
	return setmetatable(conn, {
		__index = function(_, k)
			if k == "Disconnect" then
				return function()
					conn.Connected = false
				end
			end
			return nil
		end,
	})
end

function Signal:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn.Connected = false
		fn(...)
	end)
	return conn
end

function Signal:Wait()
	local co = coroutine.running()
	table.insert(self.waiting, co)
	return coroutine.yield()
end

function Signal:Fire(...)
	local live = {}
	for _, c in self.conns do
		if c.Connected then
			table.insert(live, c)
		end
	end
	self.conns = live
	if #live == 0 and #self.waiting == 0 and self.queued then
		table.insert(self.queued, table.pack(...))
		return
	end
	for _, c in live do
		task.spawn(c.fn, ...)
	end
	local waiting = self.waiting
	self.waiting = {}
	for _, co in waiting do
		resume(co, ...)
	end
end

local events: { [any]: { [string]: any } } = {} -- strong keys: Lune hands out the same wrapper only while it is alive

local function eventOf(inst, name: string, queueWhenUnconnected: boolean?)
	local byName = events[inst]
	if byName == nil then
		byName = {}
		events[inst] = byName
	end
	local sig = byName[name]
	if sig == nil then
		sig = Signal.new(queueWhenUnconnected)
		byName[name] = sig
	end
	return sig
end

Emulator.eventOf = eventOf

local EVENT_PROPS = {
	{ "RemoteEvent", { "OnServerEvent", "OnClientEvent" }, true },
	{ "UnreliableRemoteEvent", { "OnServerEvent", "OnClientEvent" }, false },
	{ "Players", { "PlayerAdded", "PlayerRemoving" }, false },
	{
		"UserInputService",
		{ "InputBegan", "InputChanged", "InputEnded", "TouchTap", "TouchPan", "TouchPinch", "TouchStarted", "TouchEnded" },
		false,
	},
	{ "RunService", { "Heartbeat", "RenderStepped", "Stepped" }, false },
	{ "GuiButton", { "Activated", "MouseButton1Click" }, false },
	{ "Instance", { "ChildAdded", "ChildRemoved", "Destroying", "AncestryChanged", "DescendantAdded" }, false },
	{ "MarketplaceService", { "PromptGamePassPurchaseFinished", "PromptProductPurchaseFinished" }, false },
	{ "TeleportService", { "TeleportInitFailed" }, false },
}
for _, spec in EVENT_PROPS do
	local class, names, queued = spec[1], spec[2], spec[3]
	for _, name in names do
		roblox.implementProperty(class, name, function(inst)
			return eventOf(inst, name, queued)
		end)
	end
end

---------------------------------------------------------------------------------------------- machines

export type Machine = {
	name: string,
	dm: any,
	isServer: boolean,
	modules: { [any]: any },
	loading: { [any]: boolean },
	renderSteps: { [string]: { priority: number, fn: any } },
	viewport: any,
	camera: any,
	localPlayer: any,
	serverPlayer: any,
}

local machineOfDm: { [any]: Machine } = {}
local machineOfInst: { [any]: Machine } = {}
local clientOfServerPlayer: { [any]: Machine } = {}
local machines: { Machine } = {}

local function machineOf(inst): Machine?
	local m = machineOfInst[inst]
	if m then
		return m
	end
	local node = inst
	while node do
		if machineOfDm[node] then
			return machineOfDm[node]
		end
		node = node.Parent
	end
	return nil
end

-- Roblox copies remote arguments; it also turns sparse arrays and non-string dictionary keys into surprises.
-- Copy the same way and record a warning for anything that would arrive changed.
local function netCopy(v, path: string, problems: { string })
	if type(v) ~= "table" then
		return v
	end
	local n = #v
	local count = 0
	local hasStringKey, hasOtherKey = false, false
	for k in v do
		count += 1
		if type(k) == "string" then
			hasStringKey = true
		elseif not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then
			hasOtherKey = true
		end
	end
	if hasOtherKey or (hasStringKey and n > 0) then
		table.insert(problems, path .. " is a sparse or mixed table; Roblox would mangle it over the network")
	end
	local out = {}
	for k, val in v do
		out[k] = netCopy(val, path .. "." .. tostring(k), problems)
	end
	return out
end

local function sendArgs(label: string, ...)
	local problems = {}
	local args = table.pack(...)
	local copied = { n = args.n }
	for i = 1, args.n do
		copied[i] = netCopy(args[i], label .. "#" .. i, problems)
	end
	for _, p in problems do
		local msg = "NETWORK " .. p
		table.insert(warnings, msg)
		log(msg)
	end
	return copied
end

-- remote instance -> its peers on the other side, keyed by remote name
local function serverRemoteFor(clientRemote)
	return Emulator.server.dm:GetService("ReplicatedStorage").Remotes:FindFirstChild(clientRemote.Name)
end

local function clientRemoteFor(serverRemote, client: Machine)
	local folder = client.dm:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
	return folder and folder:FindFirstChild(serverRemote.Name)
end

for _, class in { "RemoteEvent", "UnreliableRemoteEvent" } do
	roblox.implementMethod(class, "FireServer", function(remote, ...)
		local client = machineOf(remote)
		local target = serverRemoteFor(remote)
		local args = sendArgs(client.name .. "->" .. remote.Name, ...)
		task.defer(function()
			eventOf(target, "OnServerEvent", class == "RemoteEvent")
				:Fire(client.serverPlayer, table.unpack(args, 1, args.n))
		end)
	end)
	roblox.implementMethod(class, "FireClient", function(remote, player, ...)
		local client = clientOfServerPlayer[player]
		if client == nil then
			return
		end
		local target = clientRemoteFor(remote, client)
		local args = sendArgs("server->" .. client.name .. ":" .. remote.Name, ...)
		task.defer(function()
			eventOf(target, "OnClientEvent", class == "RemoteEvent"):Fire(table.unpack(args, 1, args.n))
		end)
	end)
	roblox.implementMethod(class, "FireAllClients", function(remote, ...)
		for _, m in machines do
			if not m.isServer and m.serverPlayer and m.serverPlayer.Parent then
				remote:FireClient(m.serverPlayer, ...)
			end
		end
	end)
end

roblox.implementMethod("Instance", "WaitForChild", function(inst, name, timeout)
	local found = inst:FindFirstChild(name)
	local waited = 0
	while found == nil do
		if coroutine.isyieldable() then
			waited += task.wait(0.05)
		else
			error("WaitForChild(" .. name .. ") on " .. inst:GetFullName() .. " outside a thread", 2)
		end
		found = inst:FindFirstChild(name)
		if found == nil and waited > (timeout or 10) then
			error(string.format("WaitForChild timed out: %s.%s", inst:GetFullName(), name), 2)
		end
	end
	return found
end)

roblox.implementMethod("Players", "GetPlayers", function(players)
	local out = {}
	for _, child in players:GetChildren() do
		if child.ClassName == "Player" then
			table.insert(out, child)
		end
	end
	return out
end)

roblox.implementMethod("RunService", "BindToRenderStep", function(rs, name, priority, fn)
	machineOf(rs).renderSteps[name] = { priority = priority, fn = fn }
end)
roblox.implementMethod("RunService", "UnbindFromRenderStep", function(rs, name)
	machineOf(rs).renderSteps[name] = nil
end)
roblox.implementMethod("RunService", "IsServer", function(rs)
	return machineOf(rs).isServer
end)
roblox.implementMethod("RunService", "IsClient", function(rs)
	return not machineOf(rs).isServer
end)
-- The emulator runs as Studio. A scenario may set Emulator.studio = false for a moment to see what a live server
-- would answer (set it back before the game runs on: services read IsStudio all the time).
Emulator.studio = true
roblox.implementMethod("RunService", "IsStudio", function()
	return Emulator.studio ~= false
end)

-- Players.LocalPlayer, Workspace.CurrentCamera and Camera.ViewportSize already exist in the API, and Lune can't
-- override existing properties, so addClient sets them directly instead.

-- Terrain: remember water fills so screenshots can draw the sea.
local terrainBlocks: { [any]: { { cf: any, size: any, material: any } } } = {}

roblox.implementMethod("Terrain", "FillBlock", function(terrain, cf, size, material)
	terrainBlocks[terrain] = terrainBlocks[terrain] or {}
	table.insert(terrainBlocks[terrain], { cf = cf, size = size, material = material })
end)
roblox.implementMethod("Terrain", "Clear", function(terrain)
	terrainBlocks[terrain] = {}
end)

-- EditableImage: a plain table with the methods the client uses; Content.fromObject turns it into an
-- "rbxtemp://editable/<n>" content so an ImageLabel can hold it (see makeEnv), and screenshots can find it.
local editables: { [number]: any } = {}

roblox.implementMethod("AssetService", "CreateEditableImage", function(_service, options)
	local size = (options and options.Size) or roblox.Vector2.new(512, 512)
	local image = {
		id = #editables + 1,
		Size = size,
		pixels = buffer.create(size.X * size.Y * 4),
	}
	function image.WritePixelsBuffer(self, position, rectSize, data)
		local w = self.Size.X
		for row = 0, rectSize.Y - 1 do
			buffer.copy(
				self.pixels,
				((position.Y + row) * w + position.X) * 4,
				data,
				row * rectSize.X * 4,
				rectSize.X * 4
			)
		end
	end
	function image.Destroy(_self) end
	editables[image.id] = image
	return image
end)

function Emulator.editableImage(uri: string)
	local id = tonumber(string.match(uri, "^rbxtemp://editable/(%d+)$"))
	return if id then editables[id] else nil
end

roblox.implementMethod("GuiService", "GetGuiInset", function()
	return roblox.Vector2.zero, roblox.Vector2.zero
end)

function Emulator.terrainBlocks(client: Machine)
	return terrainBlocks[client.dm:GetService("Workspace"):FindFirstChildOfClass("Terrain")] or {}
end

---------------------------------------------------------------------------------------------- tweens and sounds

-- TweenService: tweens step once a frame in Emulator.run (numbers, and anything with :Lerp: UDim2, Color3,
-- Vector2...), with the common easing styles, delays, repeats and reverses, so screenshots catch effects
-- mid-animation. Sounds don't play; every Play is logged in Emulator.sounds instead.
local TweenInfo = {}
function TweenInfo.new(time, style, direction, repeatCount, reverses, delayTime)
	return {
		Time = time or 1,
		EasingStyle = style or roblox.Enum.EasingStyle.Quad,
		EasingDirection = direction or roblox.Enum.EasingDirection.Out,
		RepeatCount = repeatCount or 0,
		Reverses = reverses or false,
		DelayTime = delayTime or 0,
	}
end

local activeTweens = {}

local function easeIn(style: string, t: number): number
	if style == "Linear" then
		return t
	elseif style == "Sine" then
		return 1 - math.cos(t * math.pi / 2)
	elseif style == "Cubic" then
		return t * t * t
	elseif style == "Back" then
		return t * t * (2.70158 * t - 1.70158)
	end
	return t * t -- Quad and anything else
end

local function ease(info, t: number): number
	local style = info.EasingStyle.Name
	local dir = info.EasingDirection.Name
	if dir == "In" then
		return easeIn(style, t)
	elseif dir == "Out" then
		return 1 - easeIn(style, 1 - t)
	end
	return if t < 0.5 then easeIn(style, t * 2) / 2 else 1 - easeIn(style, (1 - t) * 2) / 2
end

local function lerp(a, b, t: number)
	if type(a) == "number" then
		return a + (b - a) * t
	end
	local ok, v = pcall(function()
		return a:Lerp(b, t)
	end)
	if ok then
		return v
	end
	return if t >= 1 then b else a
end

roblox.implementMethod("TweenService", "Create", function(_service, inst, info, goals)
	local tween = { Instance = inst, Completed = Signal.new() }
	function tween.Play(self)
		self.from = {}
		for prop in goals do
			self.from[prop] = inst[prop]
		end
		self.started = now
		activeTweens[self] = true
	end
	function tween.Cancel(self)
		activeTweens[self] = nil
	end
	tween.Pause = tween.Cancel
	tween.Destroy = tween.Cancel
	function tween.step(self)
		local elapsed = now - self.started - info.DelayTime
		if elapsed < 0 then
			return
		end
		local cycle = info.Time * (if info.Reverses then 2 else 1)
		local loops = if cycle > 0 then math.floor(elapsed / cycle) else math.huge
		local done = info.RepeatCount >= 0 and loops > info.RepeatCount
		local alpha
		if done then
			alpha = if info.Reverses then 0 else 1
		else
			local within = (elapsed - loops * cycle) / math.max(info.Time, 1e-6)
			alpha = if within > 1 then 2 - within else within
		end
		local k = ease(info, math.clamp(alpha, 0, 1))
		for prop, goal in goals do
			inst[prop] = lerp(self.from[prop], goal, k)
		end
		if done then
			activeTweens[self] = nil
			self.Completed:Fire(roblox.Enum.PlaybackState.Completed)
		end
	end
	return tween
end)

local function stepTweens()
	local list = {}
	for t in activeTweens do
		table.insert(list, t)
	end
	for _, t in list do
		if activeTweens[t] then
			local ok, err = pcall(t.step, t)
			if not ok then
				activeTweens[t] = nil
				table.insert(errors, "[tween] ERROR " .. tostring(err))
				log("[tween] ERROR " .. tostring(err))
			end
		end
	end
end

Emulator.sounds = {} -- { name, id, time } for every Sound:Play()

roblox.implementMethod("Sound", "Play", function(sound)
	table.insert(Emulator.sounds, { name = sound.Name, id = sound.SoundId, time = now })
end)
roblox.implementMethod("Sound", "Stop", function() end)
roblox.implementMethod("Sound", "Pause", function() end)
roblox.implementMethod("Sound", "Resume", function() end)

---------------------------------------------------------------------------------------------- data stores

-- In-memory DataStoreService and MessagingService with the calls ProfileStore makes, so player saves run
-- ProfileStore's live path (session locks, UpdateAsync transforms, release on leave) instead of its mock.
-- Data lives as long as the boot, so a player can leave and rejoin; scenarios read it from Emulator.dataStores.

local function deepCopy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, val in v do
		out[k] = deepCopy(val)
	end
	return out
end

Emulator.dataStores = {} -- store name -> key -> { value, version, userIds, metadata }

local function keyInfo(entry)
	return {
		Version = tostring(entry.version),
		CreatedTime = 0,
		UpdatedTime = 0,
		GetMetadata = function()
			return deepCopy(entry.metadata)
		end,
		GetUserIds = function()
			return deepCopy(entry.userIds)
		end,
	}
end

local function newDataStore(name: string)
	local entries = Emulator.dataStores[name] or {}
	Emulator.dataStores[name] = entries
	local store = {}
	local function write(key, value, userIds, metadata)
		local old = entries[key]
		local entry = {
			value = deepCopy(value),
			version = (if old then old.version else 0) + 1,
			userIds = deepCopy(userIds or {}),
			metadata = deepCopy(metadata or {}),
		}
		entries[key] = entry
		return entry
	end
	function store.GetAsync(_self, key)
		task.wait() -- a DataStore call yields
		local entry = entries[key]
		if entry == nil then
			return nil
		end
		return deepCopy(entry.value), keyInfo(entry)
	end
	function store.SetAsync(_self, key, value, userIds)
		task.wait()
		return keyInfo(write(key, value, userIds, nil)).Version
	end
	function store.UpdateAsync(_self, key, transform)
		task.wait()
		local entry = entries[key]
		local value, userIds, metadata = transform(deepCopy(entry and entry.value), entry and keyInfo(entry))
		if value == nil then
			return nil -- the transform cancelled the update
		end
		local written = write(key, value, userIds, metadata)
		return deepCopy(written.value), keyInfo(written)
	end
	function store.RemoveAsync(_self, key)
		task.wait()
		local entry = entries[key]
		entries[key] = nil
		if entry == nil then
			return nil
		end
		return deepCopy(entry.value), keyInfo(entry)
	end
	return store
end

roblox.implementMethod("DataStoreService", "GetDataStore", function(_service, name)
	return newDataStore(name)
end)
roblox.implementMethod("DataStoreOptions", "SetExperimentalFeatures", function() end)

-- OrderedDataStores (leaderboards): number values, sorted pages. Kept in Emulator.orderedStores[name/scope][key].
-- Emulator.orderedCalls counts the calls by method, so a scenario can check the DataStore budget.
Emulator.orderedStores = {} :: { [string]: { [string]: number } }
Emulator.orderedCalls = {} :: { [string]: number }

local function sortedPages(entries: { [string]: number }, ascending: boolean, pageSize: number)
	local list = {}
	for key, value in entries do
		table.insert(list, { key = key, value = value })
	end
	table.sort(list, function(a, b)
		if a.value ~= b.value then
			return if ascending then a.value < b.value else a.value > b.value
		end
		return a.key < b.key
	end)
	local pages = { IsFinished = false }
	local first = 1
	local function update()
		pages.IsFinished = first + pageSize > #list
	end
	function pages.GetCurrentPage(_self)
		local out = {}
		for i = first, math.min(first + pageSize - 1, #list) do
			table.insert(out, { key = list[i].key, value = list[i].value })
		end
		return out
	end
	function pages.AdvanceToNextPageAsync(_self)
		task.wait()
		first += pageSize
		update()
	end
	update()
	return pages
end

local function newOrderedStore(name: string, scope: string?)
	local id = name .. "/" .. (scope or "global")
	local entries = Emulator.orderedStores[id] or {}
	Emulator.orderedStores[id] = entries
	local function count(method: string)
		Emulator.orderedCalls[method] = (Emulator.orderedCalls[method] or 0) + 1
		task.wait() -- a DataStore call yields
	end
	local store = {}
	function store.GetAsync(_self, key)
		count("GetAsync")
		return entries[key]
	end
	function store.SetAsync(_self, key, value)
		count("SetAsync")
		assert(type(value) == "number" and value == math.floor(value), "OrderedDataStore values are integers")
		entries[key] = value
	end
	function store.IncrementAsync(_self, key, delta)
		count("IncrementAsync")
		entries[key] = (entries[key] or 0) + (delta or 1)
		return entries[key]
	end
	function store.RemoveAsync(_self, key)
		count("RemoveAsync")
		local old = entries[key]
		entries[key] = nil
		return old
	end
	function store.GetSortedAsync(_self, ascending, pageSize)
		count("GetSortedAsync")
		assert(pageSize >= 1 and pageSize <= 100, "GetSortedAsync pages hold 1 to 100 entries")
		return sortedPages(entries, ascending, pageSize)
	end
	return store
end

roblox.implementMethod("DataStoreService", "GetOrderedDataStore", function(_service, name, scope)
	return newOrderedStore(name, scope)
end)

-- Friends (Players:GetFriendsAsync) from Emulator.friends[userId] = { userIds }, and display names
-- (UserService:GetUserInfosByUserIdsAsync) from Emulator.displayNames[userId] (addClient fills it in).
Emulator.friends = {} :: { [number]: { number } }
Emulator.displayNames = {} :: { [number]: string }
Emulator.friendCalls = {} :: { number } -- the userId of every GetFriendsAsync call

local function displayName(userId: number): string
	return Emulator.displayNames[userId] or ("Player" .. tostring(userId))
end

roblox.implementMethod("Players", "GetFriendsAsync", function(_players, userId)
	task.wait()
	table.insert(Emulator.friendCalls, userId)
	local list = {}
	for _, id in Emulator.friends[userId] or {} do
		table.insert(list, { Id = id, Username = displayName(id), DisplayName = displayName(id), IsOnline = false })
	end
	local pages = { IsFinished = true }
	function pages.GetCurrentPage(_self)
		return list
	end
	function pages.AdvanceToNextPageAsync(_self) end
	return pages
end)

roblox.implementMethod("UserService", "GetUserInfosByUserIdsAsync", function(_service, ids)
	task.wait()
	local out = {}
	for _, id in ids do
		table.insert(out, { Id = id, Username = displayName(id), DisplayName = displayName(id), HasVerifiedBadge = false })
	end
	return out
end)

local subscriptions: { [string]: { any } } = {}

roblox.implementMethod("MessagingService", "SubscribeAsync", function(_service, topic, callback)
	local list = subscriptions[topic] or {}
	subscriptions[topic] = list
	local entry = { fn = callback }
	table.insert(list, entry)
	return {
		Disconnect = function()
			local i = table.find(list, entry)
			if i then
				table.remove(list, i)
			end
		end,
	}
end)
roblox.implementMethod("MessagingService", "PublishAsync", function(_service, topic, data)
	for _, entry in subscriptions[topic] or {} do
		task.spawn(entry.fn, { Data = deepCopy(data), Sent = os.time() })
	end
end)

local guids = 0
roblox.implementMethod("HttpService", "GenerateGUID", function(_service, wrap)
	guids += 1
	local guid = string.format("%08X-0000-4000-8000-%012X", guids, guids)
	return if wrap == false then guid else "{" .. guid .. "}"
end)

-- Property-changed signals exist but never fire headless (sizes and positions don't change here).
roblox.implementMethod("Instance", "GetPropertyChangedSignal", function(inst, property)
	return eventOf(inst, "PropertyChanged_" .. tostring(property), false)
end)

local closeCallbacks = {}
roblox.implementMethod("DataModel", "BindToClose", function(_dm, fn)
	table.insert(closeCallbacks, fn)
end)

roblox.implementMethod("Players", "GetPlayerByUserId", function(players, userId)
	for _, child in players:GetChildren() do
		if child.ClassName == "Player" and child.UserId == userId then
			return child
		end
	end
	return nil
end)

---------------------------------------------------------------------------------------------- marketplace

-- MarketplaceService with what ShopService uses. The server's ProcessReceipt callback is kept so a scenario can
-- call it (Emulator.processReceipt); prompts are recorded in Emulator.prompts instead of opening a dialog; game
-- pass ownership comes from Emulator.gamePasses[userId][passId] and live prices from Emulator.productPrices.
Emulator.prompts = {} -- { { kind = "Product" | "GamePass", userId, id } }
Emulator.gamePasses = {} :: { [number]: { [number]: boolean } }
Emulator.productPrices = {} :: { [number]: number }
local marketplaceCallbacks: { [any]: any } = {}

roblox.implementProperty("MarketplaceService", "ProcessReceipt", function(service)
	return marketplaceCallbacks[service]
end, function(service, fn)
	marketplaceCallbacks[service] = fn
end)
roblox.implementMethod("MarketplaceService", "PromptProductPurchase", function(_service, player, id)
	table.insert(Emulator.prompts, { kind = "Product", userId = player.UserId, id = id })
end)
roblox.implementMethod("MarketplaceService", "PromptGamePassPurchase", function(_service, player, id)
	table.insert(Emulator.prompts, { kind = "GamePass", userId = player.UserId, id = id })
end)
roblox.implementMethod("MarketplaceService", "UserOwnsGamePassAsync", function(_service, userId, passId)
	task.wait()
	local owned = Emulator.gamePasses[userId]
	return owned ~= nil and owned[passId] == true
end)
roblox.implementMethod("MarketplaceService", "GetProductInfoAsync", function(_service, id)
	task.wait()
	return { PriceInRobux = Emulator.productPrices[id] or 0 }
end)

-- Call the server's MarketplaceService.ProcessReceipt with a receipt, as Roblox would. Yields; returns the decision.
function Emulator.processReceipt(receipt)
	local service = Emulator.server.dm:GetService("MarketplaceService")
	local fn = marketplaceCallbacks[service]
	assert(fn, "the server never set MarketplaceService.ProcessReceipt")
	return fn(receipt)
end

---------------------------------------------------------------------------------------------- ads and notifications

-- AdService (rewarded video) and ExperienceNotificationService (the opt-in prompt). A scenario sets what they answer:
--   Emulator.adAvailability  the Enum.AdAvailabilityResult name GetAdAvailabilityNowAsync answers ("NoFill")
--   Emulator.adResult        the Enum.ShowAdResult name ShowRewardedVideoAdAsync answers ("ShowCompleted"); on
--                            ShowCompleted the reward's receipt (channel AdReward) goes to ProcessReceipt, as Roblox
--   Emulator.canPromptOptIn  what CanPromptOptInAsync answers (false)
-- Every call is recorded in Emulator.adCalls: { method, userId, arg }.
Emulator.adAvailability = "NoFill"
Emulator.adResult = "ShowCompleted"
Emulator.canPromptOptIn = false
Emulator.adCalls = {}
local adReceipts = 0

local function recordAd(method: string, inst, arg)
	local m = machineOf(inst)
	local userId = if m and m.localPlayer then m.localPlayer.UserId else nil
	table.insert(Emulator.adCalls, { method = method, userId = userId, arg = arg })
end

roblox.implementMethod("AdService", "GetAdAvailabilityNowAsync", function(service, format)
	task.wait()
	recordAd("GetAdAvailabilityNowAsync", service, format and format.Name)
	return { AdAvailabilityResult = roblox.Enum.AdAvailabilityResult[Emulator.adAvailability] }
end)
roblox.implementMethod("AdService", "RegisterAdOpportunityAsync", function(service, button)
	recordAd("RegisterAdOpportunityAsync", service, button and button.Name)
end)
roblox.implementMethod("AdService", "CreateAdRewardFromDevProductId", function(service, productId)
	recordAd("CreateAdRewardFromDevProductId", service, productId)
	return { productId = productId }
end)
roblox.implementMethod("AdService", "ShowRewardedVideoAdAsync", function(service, player, reward)
	recordAd("ShowRewardedVideoAdAsync", service, player and player.UserId)
	task.wait(1) -- the video
	local result = Emulator.adResult
	if result == "ShowCompleted" then
		adReceipts += 1
		task.spawn(Emulator.processReceipt, {
			PurchaseId = "ad-" .. adReceipts,
			PlayerId = player.UserId,
			ProductId = reward.productId,
			CurrencySpent = 0,
			ProductPurchaseChannel = roblox.Enum.ProductPurchaseChannel.AdReward,
		})
	end
	return roblox.Enum.ShowAdResult[result]
end)
roblox.implementMethod("ExperienceNotificationService", "CanPromptOptInAsync", function(service)
	task.wait()
	recordAd("CanPromptOptInAsync", service, nil)
	return Emulator.canPromptOptIn
end)
roblox.implementMethod("ExperienceNotificationService", "PromptOptIn", function(service)
	recordAd("PromptOptIn", service, nil)
end)

-- How many times `method` was called (by the client with this user id, if given).
function Emulator.adCallCount(method: string, userId: number?): number
	local n = 0
	for _, c in Emulator.adCalls do
		if c.method == method and (userId == nil or c.userId == userId) then
			n += 1
		end
	end
	return n
end

---------------------------------------------------------------------------------------------- analytics

-- AnalyticsService: every call is recorded in Emulator.analytics instead of going to Roblox, so a scenario can
-- assert the events. Each record: { method, userId, args } (args = what came after the player; enums as names).
Emulator.analytics = {}
for _, method in {
	"LogCustomEvent",
	"LogFunnelStepEvent",
	"LogOnboardingFunnelStepEvent",
	"LogEconomyEvent",
	"LogProgressionEvent",
	"LogProgressionStartEvent",
	"LogProgressionCompleteEvent",
	"LogProgressionFailEvent",
} do
	roblox.implementMethod("AnalyticsService", method, function(_service, player, ...)
		local args = table.pack(...)
		for i = 1, args.n do
			if typeof(args[i]) == "EnumItem" then
				args[i] = args[i].Name
			end
		end
		table.insert(Emulator.analytics, { method = method, userId = player and player.UserId, args = args })
	end)
end

-- TextChatService.OnIncomingMessage is a client callback; keep it so the client can set it.
local chatCallbacks: { [any]: any } = {}
roblox.implementProperty("TextChatService", "OnIncomingMessage", function(service)
	return chatCallbacks[service]
end, function(service, fn)
	chatCallbacks[service] = fn
end)

-- A kick is never expected in a scenario: record it as a warning so the scenario fails.
roblox.implementMethod("Player", "Kick", function(player, message)
	local msg = string.format("KICK %s: %s", player.Name, tostring(message))
	table.insert(warnings, msg)
	log(msg)
end)

---------------------------------------------------------------------------------------------- camera maths

local function cameraRay(cam, x: number, y: number)
	local m = machineOf(cam)
	local vp = m.viewport
	local cf = cam.CFrame
	local tanV = math.tan(math.rad(cam.FieldOfView) / 2)
	local aspect = vp.X / vp.Y
	local nx = (2 * x / vp.X - 1) * tanV * aspect
	local ny = (1 - 2 * y / vp.Y) * tanV
	local dir = (cf.RightVector * nx + cf.UpVector * ny + cf.LookVector).Unit
	return { Origin = cf.Position, Direction = dir }
end

roblox.implementMethod("Camera", "ScreenPointToRay", function(cam, x, y, depth)
	local r = cameraRay(cam, x, y)
	return { Origin = r.Origin, Direction = r.Direction * (depth or 1), Unit = r }
end)
roblox.implementMethod("Camera", "ViewportPointToRay", function(cam, x, y, depth)
	local r = cameraRay(cam, x, y)
	return { Origin = r.Origin, Direction = r.Direction * (depth or 1) }
end)

-- World point -> (screen x, screen y, in front of camera)
function Emulator.worldToScreen(m: Machine, p)
	local cam = m.camera
	local cf = cam.CFrame
	local rel = p - cf.Position
	local z = rel:Dot(cf.LookVector)
	local tanV = math.tan(math.rad(cam.FieldOfView) / 2)
	local aspect = m.viewport.X / m.viewport.Y
	local nx = rel:Dot(cf.RightVector) / (z * tanV * aspect)
	local ny = rel:Dot(cf.UpVector) / (z * tanV)
	return (nx + 1) / 2 * m.viewport.X, (1 - ny) / 2 * m.viewport.Y, z > 0
end

-- Raycast against parts: cylinders as discs/columns (axis along their local X), wedges as boxes cut by their slope
-- (cross-section in local Y/Z keeps the bottom and back faces), everything else as boxes.
local function intersectPart(part, origin, dir)
	local cf = part.CFrame
	local size = part.Size
	local lo = cf:PointToObjectSpace(origin)
	local ld = cf:VectorToObjectSpace(dir)
	local half = size / 2
	local tmin, tmax = -math.huge, math.huge
	for _, axis in { "X", "Y", "Z" } do
		local o, d, h = lo[axis], ld[axis], half[axis]
		if math.abs(d) < 1e-9 then
			if o < -h or o > h then
				return nil
			end
		else
			local t1, t2 = (-h - o) / d, (h - o) / d
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			tmin, tmax = math.max(tmin, t1), math.min(tmax, t2)
			if tmin > tmax then
				return nil
			end
		end
	end
	if part:IsA("WedgePart") then
		-- inside when y * hz - z * hy <= 0 (below the slope from front-bottom to back-top)
		local ny, nz = half.Z, -half.Y
		local o = lo.Y * ny + lo.Z * nz
		local d = ld.Y * ny + ld.Z * nz
		if math.abs(d) < 1e-9 then
			if o > 0 then
				return nil
			end
		else
			local t = -o / d
			if d < 0 then
				tmin = math.max(tmin, t)
			else
				tmax = math.min(tmax, t)
			end
			if tmin > tmax then
				return nil
			end
		end
	end
	if tmax < 0 then
		return nil
	end
	local t = math.max(tmin, 0)
	if part:IsA("Part") and part.Shape == roblox.Enum.PartType.Cylinder then
		-- inside the box; also require the hit to be within the circular cross-section (Y/Z plane)
		local p = lo + ld * t
		local r = math.min(half.Y, half.Z)
		if p.Y * p.Y + p.Z * p.Z > r * r + 1e-6 then
			return nil
		end
	end
	return t
end

roblox.implementMethod("Workspace", "Raycast", function(ws, origin, direction, params)
	local candidates = {}
	if params and params.FilterType == roblox.Enum.RaycastFilterType.Include then
		for _, root in params.FilterDescendantsInstances do
			if root:IsA("BasePart") then
				table.insert(candidates, root)
			end
			for _, d in root:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(candidates, d)
				end
			end
		end
	else
		for _, d in ws:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(candidates, d)
			end
		end
	end
	local best, bestT = nil, math.huge
	local len = direction.Magnitude
	local unit = direction.Unit
	for _, part in candidates do
		if part.CanQuery then
			local t = intersectPart(part, origin, unit)
			if t and t <= len and t < bestT then
				best, bestT = part, t
			end
		end
	end
	if best == nil then
		return nil
	end
	return { Instance = best, Position = origin + unit * bestT, Distance = bestT }
end)

---------------------------------------------------------------------------------------------- scripts

local RaycastParams = {}
function RaycastParams.new()
	return { FilterType = roblox.Enum.RaycastFilterType.Exclude, FilterDescendantsInstances = {}, IgnoreWater = false }
end

local function resolveStringRequire(from, path: string)
	local node
	local parts = string.split(path, "/")
	local i = 1
	if parts[1] == "." then
		node = from.Parent
		i = 2
	elseif parts[1] == ".." then
		node = from.Parent.Parent
		i = 2
	else
		error("unsupported require path " .. path)
	end
	while parts[i] == ".." do
		node = node.Parent
		i += 1
	end
	for j = i, #parts do
		local child = node:FindFirstChild(parts[j])
		if child == nil then
			error(string.format("require(%q) from %s: %s has no child %s", path, from:GetFullName(), node:GetFullName(), parts[j]))
		end
		node = child
	end
	return node
end

local makeEnv

local function requireModule(m: Machine, target, from)
	if type(target) == "string" then
		target = resolveStringRequire(from, target)
	end
	if m.modules[target] ~= nil then
		return m.modules[target]
	end
	if target.ClassName ~= "ModuleScript" then
		error("require expects a ModuleScript, got " .. target:GetFullName())
	end
	if m.loading[target] then
		error("cyclic require of " .. target:GetFullName())
	end
	m.loading[target] = true
	local chunk = luau.load(target.Source, { debugName = target:GetFullName(), environment = makeEnv(m, target) })
	local result = chunk()
	m.loading[target] = nil
	m.modules[target] = result
	return result
end

makeEnv = function(m: Machine, scriptInst)
	local env = {
		game = m.dm,
		workspace = m.dm:GetService("Workspace"),
		script = scriptInst,
		require = function(target)
			return requireModule(m, target, scriptInst)
		end,
		task = task,
		wait = task.wait,
		spawn = task.spawn,
		delay = task.delay,
		Instance = {
			new = function(className, parent)
				local inst = Instance.new(className)
				machineOfInst[inst] = m
				if inst:IsA("GuiObject") then
					-- no layout engine here: GUI sits at the screen origin (Lune has no default for these)
					inst.AbsolutePosition = roblox.Vector2.zero
					inst.AbsoluteSize = roblox.Vector2.zero
				end
				if parent then
					inst.Parent = parent
				end
				return inst
			end,
		},
		Enum = roblox.Enum,
		Vector2 = roblox.Vector2,
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		BrickColor = roblox.BrickColor,
		Rect = roblox.Rect,
		NumberRange = roblox.NumberRange,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		Font = roblox.Font,
		Content = {
			fromObject = function(object)
				if type(object) == "table" and object.id then
					return roblox.Content.fromUri("rbxtemp://editable/" .. object.id)
				end
				return roblox.Content.fromObject(object)
			end,
			fromUri = roblox.Content.fromUri,
			fromAssetId = roblox.Content.fromAssetId,
			none = roblox.Content.none,
		},
		RaycastParams = RaycastParams,
		TweenInfo = TweenInfo,
		os = {
			clock = function()
				return now
			end,
			time = function()
				return 1700000000 + math.floor(now)
			end,
			date = os.date,
		},
		tick = function()
			return now
		end,
		time = function()
			return now
		end,
		print = function(...)
			local parts = table.pack(...)
			for i = 1, parts.n do
				parts[i] = tostring(parts[i])
			end
			log(string.format("[%s %6.1fs] %s", m.name, now, table.concat(parts, " ")))
		end,
		warn = function(...)
			local parts = table.pack(...)
			for i = 1, parts.n do
				parts[i] = tostring(parts[i])
			end
			local msg = string.format("[%s %6.1fs] WARN %s", m.name, now, table.concat(parts, " "))
			table.insert(warnings, msg)
			log(msg)
		end,
	}
	return env
end

local function runScript(m: Machine, scriptInst)
	local chunk = luau.load(scriptInst.Source, { debugName = scriptInst:GetFullName(), environment = makeEnv(m, scriptInst) })
	local co = coroutine.create(chunk)
	threadMachine[co] = m
	resume(co)
end

local function newMachine(name: string, dm, isServer: boolean): Machine
	local m: Machine = {
		name = name,
		dm = dm,
		isServer = isServer,
		modules = {},
		loading = {},
		renderSteps = {},
		viewport = roblox.Vector2.new(844, 390), -- a phone in landscape
		camera = nil,
		localPlayer = nil,
		serverPlayer = nil,
	}
	machineOfDm[dm] = m
	table.insert(machines, m)
	return m
end

---------------------------------------------------------------------------------------------- public API

-- mapId (optional) picks the map the way the Workspace "MapId" attribute does in Studio. attributes (optional)
-- are more Workspace attributes, e.g. { SkipLobby = true }.
function Emulator.boot(placeBytes: string, mapId: string?, attributes: { [string]: any }?)
	Emulator.placeBytes = placeBytes
	local dm = roblox.deserializePlace(placeBytes)
	dm.PlaceId = 0 -- an unpublished place in Studio (ProfileStore tags its session locks with these)
	dm.JobId = ""
	if mapId then
		dm:GetService("Workspace"):SetAttribute("MapId", mapId)
	end
	for name, value in attributes or {} do
		dm:GetService("Workspace"):SetAttribute(name, value)
	end
	local server = newMachine("server", dm, true)
	Emulator.server = server
	for _, s in dm:GetService("ServerScriptService"):GetDescendants() do
		if s.ClassName == "Script" then
			runScript(server, s)
		end
	end
	return server
end

local nextUserId = 1000


-- userId (optional) lets a player rejoin as themselves; otherwise every client gets a new one.
function Emulator.addClient(name: string, viewport: any?, userId: number?): Machine
	local dm = roblox.deserializePlace(Emulator.placeBytes)
	-- clients never see server scripts
	for _, child in dm:GetService("ServerScriptService"):GetChildren() do
		child:Destroy()
	end
	local client = newMachine(name, dm, false)
	if viewport then
		client.viewport = viewport
	end
	-- replicate what the server created in ReplicatedStorage (the Remotes folder)
	local serverRs = Emulator.server.dm:GetService("ReplicatedStorage")
	local clientRs = dm:GetService("ReplicatedStorage")
	for _, child in serverRs:GetChildren() do
		if clientRs:FindFirstChild(child.Name) == nil then
			child:Clone().Parent = clientRs
		end
	end
	local terrain = Instance.new("Terrain")
	terrain.Parent = dm:GetService("Workspace")
	pcall(function()
		dm:GetService("Workspace").Terrain = terrain
	end)
	local cam = Instance.new("Camera")
	cam.FieldOfView = 70
	cam.ViewportSize = client.viewport
	cam.Parent = dm:GetService("Workspace")
	dm:GetService("Workspace").CurrentCamera = cam
	client.camera = cam

	if userId == nil then
		nextUserId += 1
		userId = nextUserId
	end
	local serverPlayer = Instance.new("Player")
	serverPlayer.Name = name
	serverPlayer.DisplayName = name -- Lune has no default for it
	serverPlayer.UserId = userId
	Emulator.displayNames[userId] = Emulator.displayNames[userId] or name
	local localPlayer = Instance.new("Player")
	localPlayer.Name = name
	localPlayer.UserId = userId
	Instance.new("PlayerGui").Parent = localPlayer
	local playerScripts = Instance.new("PlayerScripts")
	playerScripts.Parent = localPlayer
	localPlayer.Parent = dm:GetService("Players")
	dm:GetService("Players").LocalPlayer = localPlayer
	client.localPlayer = localPlayer
	client.serverPlayer = serverPlayer
	clientOfServerPlayer[serverPlayer] = client

	serverPlayer.Parent = Emulator.server.dm:GetService("Players")
	eventOf(Emulator.server.dm:GetService("Players"), "PlayerAdded"):Fire(serverPlayer)

	-- StarterPlayerScripts are copied into PlayerScripts and run there
	for _, child in dm:GetService("StarterPlayer"):FindFirstChildOfClass("StarterPlayerScripts"):GetChildren() do
		child:Clone().Parent = playerScripts
	end
	for _, s in playerScripts:GetDescendants() do
		if s.ClassName == "LocalScript" then
			runScript(client, s)
		end
	end
	return client
end

function Emulator.removeClient(client: Machine)
	local players = Emulator.server.dm:GetService("Players")
	eventOf(players, "PlayerRemoving"):Fire(client.serverPlayer)
	task.defer(function()
		client.serverPlayer.Parent = nil
	end)
end

local FRAME = 0.1

-- Advance virtual time, running scripts, frames and render steps.
function Emulator.run(seconds: number)
	local target = now + seconds
	while now < target - 1e-9 do
		local frameEnd = math.min(now + FRAME, target)
		runDue(frameEnd)
		now = frameEnd
		for _, m in machines do
			local rs = m.dm:GetService("RunService")
			local steps = {}
			for _, s in m.renderSteps do
				table.insert(steps, s)
			end
			table.sort(steps, function(a, b)
				return a.priority < b.priority
			end)
			for _, s in steps do
				local co = newThread(s.fn, m)
				resume(co, FRAME)
			end
			eventOf(rs, "RenderStepped"):Fire(FRAME)
			eventOf(rs, "Heartbeat"):Fire(FRAME)
		end
		stepTweens()
	end
end

---------------------------------------------------------------------------------------------- input helpers

function Emulator.tapScreen(client: Machine, x: number, y: number)
	local uis = client.dm:GetService("UserInputService")
	eventOf(uis, "TouchTap"):Fire({ roblox.Vector2.new(x, y) }, false)
end

function Emulator.tapWorld(client: Machine, worldPos)
	local x, y, visible = Emulator.worldToScreen(client, worldPos)
	assert(visible, "point is behind the camera")
	Emulator.tapScreen(client, x, y)
	return x, y
end

function Emulator.pan(client: Machine, dx: number, dy: number)
	local uis = client.dm:GetService("UserInputService")
	local sig = eventOf(uis, "TouchPan")
	sig:Fire({}, roblox.Vector2.new(0, 0), roblox.Vector2.zero, roblox.Enum.UserInputState.Begin, false)
	sig:Fire({}, roblox.Vector2.new(dx, dy), roblox.Vector2.zero, roblox.Enum.UserInputState.Change, false)
	sig:Fire({}, roblox.Vector2.new(dx, dy), roblox.Vector2.zero, roblox.Enum.UserInputState.End, false)
end

function Emulator.pinch(client: Machine, scale: number)
	local uis = client.dm:GetService("UserInputService")
	local sig = eventOf(uis, "TouchPinch")
	sig:Fire({}, 1, 0, roblox.Enum.UserInputState.Begin, false)
	sig:Fire({}, scale, 0, roblox.Enum.UserInputState.Change, false)
	sig:Fire({}, scale, 0, roblox.Enum.UserInputState.End, false)
end

local function visibleInTree(inst): boolean
	local node = inst
	while node do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		if node:IsA("ScreenGui") and not node.Enabled then
			return false
		end
		node = node.Parent
	end
	return true
end

-- Every visible button in the client's PlayerGui, as { button, text }.
function Emulator.buttons(client: Machine)
	local out = {}
	for _, d in client.localPlayer.PlayerGui:GetDescendants() do
		if d:IsA("GuiButton") and visibleInTree(d) then
			table.insert(out, { button = d, text = if d:IsA("TextButton") then d.Text else d.Name })
		end
	end
	return out
end

-- Press the first visible button whose text contains `needle` (plain match), or whose name is `needle`. Errors if
-- there is none.
function Emulator.press(client: Machine, needle: string)
	for _, b in Emulator.buttons(client) do
		if string.find(b.text, needle, 1, true) or b.button.Name == needle then
			eventOf(b.button, "Activated"):Fire(nil, 1)
			return b.button
		end
	end
	local names = {}
	for _, b in Emulator.buttons(client) do
		table.insert(names, (string.gsub(b.text, "\n", " ")))
	end
	error(string.format("%s: no visible button with %q (have: %s)", client.name, needle, table.concat(names, " | ")), 2)
end

function Emulator.findText(client: Machine, needle: string): string?
	for _, d in client.localPlayer.PlayerGui:GetDescendants() do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and visibleInTree(d) and string.find(d.Text, needle, 1, true) then
			return d.Text
		end
	end
	return nil
end

-- Fail loudly with everything that went wrong so far.
-- Shut the server down the way Roblox may: every BindToClose callback first (each in its own thread), then the
-- players still here leave.
function Emulator.shutdown(seconds: number?)
	for _, fn in closeCallbacks do
		resume(newThread(fn, Emulator.server))
	end
	Emulator.run(seconds or 3)
	for _, m in machines do
		if m.serverPlayer and m.serverPlayer.Parent then
			Emulator.removeClient(m)
		end
	end
	Emulator.run(1)
end

function Emulator.assertClean(label: string)
	if #errors > 0 or #warnings > 0 then
		stdio.ewrite(string.format("\n%s: %d errors, %d warnings\n", label, #errors, #warnings))
		for _, e in errors do
			stdio.ewrite(e .. "\n")
		end
		for _, w in warnings do
			stdio.ewrite(w .. "\n")
		end
		error(label .. " failed")
	end
end

Emulator.machines = machines
Emulator.task = task
Emulator.roblox = roblox

return Emulator
