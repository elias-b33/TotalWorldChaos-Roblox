--!strict
-- Top-down map camera (docs/DESIGN.md "UI and controls"): one finger or mouse drag pans, pinch or wheel zooms
-- between the whole map and a single province, a tap (or click) selects a province.

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local MapRenderer = require(script.Parent.MapRenderer)

local TAP_SLOP = 8 -- pixels a press may move and still count as a tap
local ZOOM_LEVELS = 3 -- whole map, region, province (mouse wheel steps between them)
local CLOSEST_SHARE = 0.08 -- the province zoom shows this share of the whole-map view
local SMOOTHING = 12 -- higher = snappier
local TILT = 0.3 -- the eye sits this far south of the focus per stud of height: a slight tilt shows the relief

local CameraController = {}

local camera = workspace.CurrentCamera
local focus = Vector3.zero -- point on the ground under the screen centre
local height = 400 -- camera height above the ground (studs)
local targetFocus = focus
local targetHeight = height
export type TapHandler = (kind: "Army" | "Province" | nil, id: number?) -> ()

local onTap: TapHandler? = nil

local function maxHeight(): number
	-- high enough that the whole map fits the screen, with a small margin
	local size = MapRenderer.mapSize()
	local viewport = camera.ViewportSize
	local tanHalf = math.tan(math.rad(camera.FieldOfView) / 2)
	local aspect = viewport.X / math.max(viewport.Y, 1)
	local fitHeight = (size.Y / 2) / tanHalf
	local fitWidth = (size.X / 2) / (tanHalf * aspect)
	return math.max(fitHeight, fitWidth) * 1.08
end

local function minHeight(): number
	return maxHeight() * CLOSEST_SHARE
end

local function clampFocus(p: Vector3): Vector3
	local half = MapRenderer.mapSize() / 2
	return Vector3.new(math.clamp(p.X, -half.X, half.X), 0, math.clamp(p.Z, -half.Y, half.Y))
end

-- Studs on the ground per screen pixel at the current height.
local function studsPerPixel(): number
	return 2 * height * math.tan(math.rad(camera.FieldOfView) / 2) / math.max(camera.ViewportSize.Y, 1)
end

local function pan(deltaPixels: Vector2)
	local k = studsPerPixel()
	targetFocus = clampFocus(targetFocus - Vector3.new(deltaPixels.X * k, 0, deltaPixels.Y * k))
	focus = clampFocus(focus - Vector3.new(deltaPixels.X * k, 0, deltaPixels.Y * k))
end

local function zoomTo(h: number)
	targetHeight = math.clamp(h, minHeight(), maxHeight())
end

-- Height of each wheel step: whole map, region, province (evenly spaced on a log scale).
local function levelHeight(level: number): number
	local t = (level - 1) / (ZOOM_LEVELS - 1)
	return maxHeight() * CLOSEST_SHARE ^ t
end

local function nearestLevel(): number
	local best, bestDiff = 1, math.huge
	for level = 1, ZOOM_LEVELS do
		local diff = math.abs(math.log(levelHeight(level)) - math.log(targetHeight))
		if diff < bestDiff then
			best, bestDiff = level, diff
		end
	end
	return best
end

-- What is under a screen point: an army token (they sit on top) or a province.
local function pick(screenPos: Vector2): ("Army" | "Province" | nil, number?)
	local ray = camera:ScreenPointToRay(screenPos.X, screenPos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = MapRenderer.pickables()
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 5000, params)
	if hit then
		local armyId = hit.Instance:GetAttribute("ArmyId")
		if type(armyId) == "number" then
			return "Army", armyId
		end
		local provinceId = hit.Instance:GetAttribute("ProvinceId")
		if type(provinceId) == "number" then
			return "Province", provinceId
		end
	end
	return nil, nil
end

local function tap(screenPos: Vector2)
	if onTap then
		onTap(pick(screenPos))
	end
end

function CameraController.centreOn(worldPos: Vector3, closeUp: boolean?)
	targetFocus = clampFocus(worldPos)
	if closeUp then
		targetHeight = levelHeight(2)
	end
end

function CameraController.showWholeMap()
	targetFocus = Vector3.zero
	focus = Vector3.zero
	height = maxHeight()
	targetHeight = height
end

function CameraController.init(tapHandler: TapHandler)
	onTap = tapHandler
	camera.CameraType = Enum.CameraType.Scriptable

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
			-- wheel forward (+Z) zooms in, towards the province level
			local level = math.clamp(nearestLevel() + math.sign(input.Position.Z), 1, ZOOM_LEVELS)
			zoomTo(levelHeight(level))
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
	local pinchStartHeight = height
	UserInputService.TouchPinch:Connect(function(_positions, scale, _velocity, state, processed)
		if processed then
			return
		end
		if state == Enum.UserInputState.Begin then
			pinchStartHeight = targetHeight
		end
		zoomTo(pinchStartHeight / math.max(scale, 0.01))
	end)

	RunService:BindToRenderStep("MapCamera", Enum.RenderPriority.Camera.Value, function(dt)
		local a = 1 - math.exp(-SMOOTHING * dt)
		targetHeight = math.clamp(targetHeight, minHeight(), maxHeight())
		height += (targetHeight - height) * a
		focus = focus:Lerp(targetFocus, a)
		-- looking down at the map with a slight tilt, north (-Z) at the top of the screen
		camera.CFrame = CFrame.lookAt(focus + Vector3.new(0, height, height * TILT), focus, Vector3.yAxis)
	end)
end

return CameraController
