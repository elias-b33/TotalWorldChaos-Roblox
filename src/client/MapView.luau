--!strict
-- The 2D map on screen (docs/DESIGN.md "UI and controls"): a full-screen GUI with the pixel-art map on a canvas
-- that pans and zooms. One finger or mouse drag pans, pinch zooms around the fingers, the wheel zooms around the
-- pointer, a tap (or click) is handed to the tap handler. Map positions are in map-art pixels (1 pixel = 1 stud);
-- things drawn on the map are children of the canvas, placed by scale so they follow every pan and zoom.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local TAP_SLOP = 8 -- pixels a press may move and still count as a tap
local MAX_ZOOM = 10 -- screen pixels per map pixel at the closest zoom
local ZOOM_LEVELS = 3 -- whole map, region, close-up (mouse wheel steps between them)
local SMOOTHING = 12 -- higher = snappier
local TOP_BAR = 44 -- the HUD's top bar (UI/Hud BAR_HEIGHT): the map is framed below it

local MapView = {}

export type TapHandler = (screenPos: Vector2) -> ()

type Anchor = { screen: Vector2, map: Vector2 } -- keep this map point under this screen point while zooming

local gui: ScreenGui? = nil
local root: Frame? = nil -- full-screen background; its corner is the origin of map-screen coordinates
local canvas: Frame? = nil
local mapSize = Vector2.new(1024, 512)
local zoom = 1
local targetZoom = 1
local focus = Vector2.zero -- map pixel at the centre of the screen
local targetFocus = Vector2.zero
local anchor: Anchor? = nil
local applied = { x = math.huge, y = math.huge, w = -1, h = -1 }
local lastZoom = -1
local zoomListeners: { (number) -> () } = {}

local function viewport(): Vector2
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(800, 600)
end

-- The part of the screen the map is framed in (below the top bar), and its centre.
local function viewArea(): Vector2
	local vp = viewport()
	return Vector2.new(vp.X, math.max(vp.Y - TOP_BAR, 1))
end

local function viewCentre(): Vector2
	local vp = viewport()
	return Vector2.new(vp.X / 2, TOP_BAR + (vp.Y - TOP_BAR) / 2)
end

local function fitZoom(): number
	local area = viewArea()
	return math.min(area.X / mapSize.X, area.Y / mapSize.Y)
end

local function clampZoom(z: number): number
	return math.clamp(z, fitZoom(), MAX_ZOOM)
end

-- Keep the map's edges on screen: centred on an axis where the map is smaller than the screen.
local function clampFocus(p: Vector2, z: number): Vector2
	local half = viewArea() / 2 / z
	local x = if mapSize.X <= half.X * 2 then mapSize.X / 2 else math.clamp(p.X, half.X, mapSize.X - half.X)
	local y = if mapSize.Y <= half.Y * 2 then mapSize.Y / 2 else math.clamp(p.Y, half.Y, mapSize.Y - half.Y)
	return Vector2.new(x, y)
end

-- Zoom of each wheel step: whole map, region, close-up (evenly spaced on a log scale).
local function levelZoom(level: number): number
	local t = (level - 1) / (ZOOM_LEVELS - 1)
	return fitZoom() * (MAX_ZOOM / fitZoom()) ^ t
end

local function nearestLevel(): number
	local best, bestDiff = 1, math.huge
	for level = 1, ZOOM_LEVELS do
		local diff = math.abs(math.log(levelZoom(level)) - math.log(targetZoom))
		if diff < bestDiff then
			best, bestDiff = level, diff
		end
	end
	return best
end

-- Input positions -> map-screen coordinates (relative to the full-screen map GUI). Both input positions and
-- AbsolutePosition leave out the same top-bar and notch insets, so the difference is exact on every device.
local function fromInput(p: Vector2): Vector2
	local frame = root
	return if frame then p - frame.AbsolutePosition else p
end

local function pan(deltaPixels: Vector2)
	anchor = nil
	targetFocus = clampFocus(targetFocus - deltaPixels / zoom, targetZoom)
	focus = clampFocus(focus - deltaPixels / zoom, zoom)
end

-- Build the map GUI for a new map (replacing any old one). Returns the canvas to draw on.
function MapView.create(size: Vector2, background: Color3): Frame
	if gui then
		gui:Destroy()
	end
	mapSize = size
	local screen = Instance.new("ScreenGui")
	screen.Name = "Map"
	screen.ScreenInsets = Enum.ScreenInsets.None -- the whole screen, under the HUD
	screen.DisplayOrder = -10
	screen.ResetOnSpawn = false
	local back = Instance.new("Frame")
	back.Name = "Background"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = background
	back.BorderSizePixel = 0
	back.Parent = screen
	local frame = Instance.new("Frame")
	frame.Name = "Canvas"
	frame.BackgroundTransparency = 1
	frame.Parent = back
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
	root = back
	canvas = frame
	applied = { x = math.huge, y = math.huge, w = -1, h = -1 }
	MapView.showWholeMap()
	return frame
end

function MapView.canvas(): Frame?
	return canvas
end

-- Screen pixels per map pixel right now.
function MapView.zoom(): number
	return zoom
end

-- Called with the new zoom whenever it changes (labels show or hide by zoom).
function MapView.onZoom(fn: (number) -> ())
	table.insert(zoomListeners, fn)
end

function MapView.toScreen(p: Vector2): Vector2
	return viewCentre() + (p - focus) * zoom
end

function MapView.toMap(screenPos: Vector2): Vector2
	return focus + (screenPos - viewCentre()) / zoom
end

-- The region zoom (the middle wheel step), for things that should show from there on.
function MapView.regionZoom(): number
	return levelZoom(2)
end

function MapView.centreOn(p: Vector2, closeUp: boolean?)
	anchor = nil
	if closeUp then
		targetZoom = levelZoom(2)
	end
	targetFocus = clampFocus(p, targetZoom)
end

function MapView.showWholeMap()
	anchor = nil
	targetZoom = fitZoom()
	zoom = targetZoom
	targetFocus = clampFocus(mapSize / 2, zoom)
	focus = targetFocus
end

local function apply()
	local frame = canvas
	if frame == nil then
		return
	end
	local centre = viewCentre()
	-- whole pixels, so the pixel art doesn't shimmer while panning
	local x = math.floor(centre.X - focus.X * zoom + 0.5)
	local y = math.floor(centre.Y - focus.Y * zoom + 0.5)
	local w = math.floor(mapSize.X * zoom + 0.5)
	local h = math.floor(mapSize.Y * zoom + 0.5)
	if x ~= applied.x or y ~= applied.y then
		frame.Position = UDim2.fromOffset(x, y)
		applied.x, applied.y = x, y
	end
	if w ~= applied.w or h ~= applied.h then
		frame.Size = UDim2.fromOffset(w, h)
		applied.w, applied.h = w, h
	end
	if math.abs(zoom - lastZoom) > 1e-3 then
		lastZoom = zoom
		for _, fn in zoomListeners do
			fn(zoom)
		end
	end
end

-- Zoom to z keeping the map point under screenPos where it is (pinch midpoint, mouse pointer).
local function zoomAround(screenPos: Vector2, z: number, immediate: boolean)
	anchor = { screen = screenPos, map = MapView.toMap(screenPos) }
	targetZoom = clampZoom(z)
	if immediate then
		zoom = targetZoom
	end
end

function MapView.init(onTap: TapHandler)
	local function tap(inputPos: Vector2)
		onTap(fromInput(inputPos))
	end

	-- Mouse: drag to pan, click to select, wheel to step zoom levels around the pointer.
	local mouseDown: Vector2? = nil
	local mouseLast = Vector2.zero
	local mouseMoved = false
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		mouseDown = Vector2.new(input.Position.X, input.Position.Y)
		mouseLast = mouseDown :: Vector2
		mouseMoved = false
	end)
	UserInputService.InputChanged:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseMovement and mouseDown then
			local pos = Vector2.new(input.Position.X, input.Position.Y)
			if (pos - (mouseDown :: Vector2)).Magnitude > TAP_SLOP then
				mouseMoved = true
			end
			if mouseMoved then
				pan(pos - mouseLast)
			end
			mouseLast = pos
		elseif input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
			-- wheel forward (+Z) zooms in, towards the close-up
			local level = math.clamp(nearestLevel() + math.sign(input.Position.Z), 1, ZOOM_LEVELS)
			zoomAround(fromInput(Vector2.new(input.Position.X, input.Position.Y)), levelZoom(level), false)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and mouseDown then
			if not mouseMoved then
				tap(Vector2.new(input.Position.X, input.Position.Y))
			end
			mouseDown = nil
		end
	end)

	-- Touch: tap to select, one-finger pan, pinch to zoom around the fingers.
	UserInputService.TouchTap:Connect(function(positions, processed)
		if not processed and positions[1] then
			tap(positions[1])
		end
	end)
	local lastTranslation = Vector2.zero
	UserInputService.TouchPan:Connect(function(_positions, totalTranslation, _velocity, state, processed)
		if processed then
			return
		end
		if state == Enum.UserInputState.Begin then
			lastTranslation = Vector2.zero
		end
		pan(totalTranslation - lastTranslation)
		lastTranslation = totalTranslation
	end)
	local pinchStartZoom = zoom
	local pinchCentre = Vector2.zero
	UserInputService.TouchPinch:Connect(function(positions, scale, _velocity, state, processed)
		if processed then
			return
		end
		if state == Enum.UserInputState.Begin then
			pinchStartZoom = targetZoom
			local sum = Vector2.zero
			for _, p in positions do
				sum += p
			end
			pinchCentre = if #positions > 0 then fromInput(sum / #positions) else viewCentre()
		end
		zoomAround(pinchCentre, pinchStartZoom * scale, true)
	end)

	RunService.RenderStepped:Connect(function(dt: number)
		local a = 1 - math.exp(-SMOOTHING * dt)
		targetZoom = clampZoom(targetZoom)
		zoom += (targetZoom - zoom) * a
		if math.abs(targetZoom - zoom) < 1e-3 then
			zoom = targetZoom
		end
		local hold = anchor
		if hold then
			-- the anchored map point stays under its screen point while the zoom changes
			focus = clampFocus(hold.map - (hold.screen - viewCentre()) / zoom, zoom)
			targetFocus = focus
			if zoom == targetZoom then
				anchor = nil
			end
		else
			targetFocus = clampFocus(targetFocus, targetZoom)
			focus = clampFocus(focus:Lerp(targetFocus, a), zoom)
			if (targetFocus - focus).Magnitude < 0.01 then
				focus = targetFocus
			end
		end
		apply()
	end)
end

return MapView
