--!strict
-- The 2D map on screen (docs/DESIGN.md "UI and controls"): a full-screen GUI with the pixel-art map on a canvas
-- that pans and zooms. One finger or mouse drag pans, pinch or wheel zooms between the whole map and a close-up,
-- a tap (or click) is handed to the tap handler. Map positions are in map-art pixels (1 pixel = 1 stud);
-- things drawn on the map are children of the canvas, placed by scale so they follow every pan and zoom.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local TAP_SLOP = 8 -- pixels a press may move and still count as a tap
local MAX_ZOOM = 10 -- screen pixels per map pixel at the closest zoom
local ZOOM_LEVELS = 3 -- whole map, region, close-up (mouse wheel steps between them)
local SMOOTHING = 12 -- higher = snappier

local MapView = {}

export type TapHandler = (screenPos: Vector2) -> ()

local gui: ScreenGui? = nil
local canvas: Frame? = nil
local mapSize = Vector2.new(1024, 512)
local zoom = 1
local targetZoom = 1
local focus = Vector2.zero -- map pixel at the centre of the screen
local targetFocus = Vector2.zero
local lastZoom = -1
local zoomListeners: { (number) -> () } = {}

local function viewport(): Vector2
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(800, 600)
end

local function fitZoom(): number
	local vp = viewport()
	return math.min(vp.X / mapSize.X, vp.Y / mapSize.Y)
end

local function clampZoom(z: number): number
	return math.clamp(z, fitZoom(), MAX_ZOOM)
end

local function clampFocus(p: Vector2): Vector2
	return Vector2.new(math.clamp(p.X, 0, mapSize.X), math.clamp(p.Y, 0, mapSize.Y))
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

local function pan(deltaPixels: Vector2)
	targetFocus = clampFocus(targetFocus - deltaPixels / zoom)
	focus = clampFocus(focus - deltaPixels / zoom)
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
	canvas = frame
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
	return viewport() / 2 + (p - focus) * zoom
end

function MapView.toMap(screenPos: Vector2): Vector2
	return focus + (screenPos - viewport() / 2) / zoom
end

function MapView.centreOn(p: Vector2, closeUp: boolean?)
	targetFocus = clampFocus(p)
	if closeUp then
		targetZoom = levelZoom(2)
	end
end

function MapView.showWholeMap()
	targetZoom = fitZoom()
	zoom = targetZoom
	targetFocus = mapSize / 2
	focus = targetFocus
end

local function apply()
	local frame = canvas
	if frame == nil then
		return
	end
	local vp = viewport()
	local topLeft = vp / 2 - focus * zoom
	frame.Position = UDim2.fromOffset(topLeft.X, topLeft.Y)
	frame.Size = UDim2.fromOffset(mapSize.X * zoom, mapSize.Y * zoom)
	if math.abs(zoom - lastZoom) > 1e-3 then
		lastZoom = zoom
		for _, fn in zoomListeners do
			fn(zoom)
		end
	end
end

function MapView.init(onTap: TapHandler)
	local function tap(inputPos: Vector2)
		-- input positions leave out the top bar inset; the map GUI covers the whole screen
		local inset = GuiService:GetGuiInset()
		onTap(inputPos + inset)
	end

	-- Mouse: drag to pan, click to select, wheel to step zoom levels.
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
			targetZoom = levelZoom(level)
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

	-- Touch: tap to select, one-finger pan, pinch to zoom.
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
	UserInputService.TouchPinch:Connect(function(_positions, scale, _velocity, state, processed)
		if processed then
			return
		end
		if state == Enum.UserInputState.Begin then
			pinchStartZoom = targetZoom
		end
		targetZoom = clampZoom(pinchStartZoom * scale)
	end)

	RunService.RenderStepped:Connect(function(dt: number)
		local a = 1 - math.exp(-SMOOTHING * dt)
		targetZoom = clampZoom(targetZoom)
		zoom += (targetZoom - zoom) * a
		focus = focus:Lerp(targetFocus, a)
		apply()
	end)
end

return MapView
