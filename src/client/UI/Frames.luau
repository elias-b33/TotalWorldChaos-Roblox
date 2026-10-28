--!strict
-- Painted frames on screen (docs/UI_DIRECTION.md 7.0), modelled on Icons: FrameArt paints each (frame, style)
-- once, on first use, into a small EditableImage that every label showing it shares, drawn as a 9-slice at
-- SliceScale 2 with pixelated resampling (the map's 2 px grid). About fifty images, under 100 KB in all. Where
-- EditableImage isn't allowed (the game setting is off, or the phone is out of image memory) content returns nil
-- and widgets keep their flat look (7.16), as icons fall back to emoji.

local AssetService = game:GetService("AssetService")

local Client = script.Parent.Parent
local FrameArt = require(Client.FrameArt)

local Frames = {}

Frames.SCALE = 2 -- GUI px per art pixel

export type Style = string | Color3

local images: { [string]: EditableImage | false } = {}
local unavailable = false -- once one frame fails, every frame uses the flat look

-- A colour as FrameArt takes it: its name when it is one of the palette's, else 0xRRGGBB.
local function styleKey(style: Style): string | number
	if typeof(style) == "Color3" then
		local n = tonumber(style:ToHex(), 16) or 0
		for name, value in FrameArt.COLORS do
			if value == n then
				return name
			end
		end
		return n
	end
	return style :: string
end

-- Whether frames can be painted on this device (false after the first failure).
function Frames.available(): boolean
	return not unavailable
end

-- The shared image for a frame in a style, or nil when the device can't make one.
function Frames.image(frame: string, style: Style): EditableImage?
	local key = styleKey(style)
	local cacheKey = frame .. "|" .. tostring(key)
	local cached = images[cacheKey]
	if cached ~= nil then
		return if cached then cached else nil
	end
	if unavailable or FrameArt.FRAMES[frame] == nil then
		images[cacheKey] = false
		return nil
	end
	local pixels, w, h = FrameArt.paint(frame, FrameArt.palette(frame, key))
	local ok, result = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(w, h) })
	end)
	if not ok or result == nil then
		unavailable = true
		images[cacheKey] = false
		return nil
	end
	local editable = result :: EditableImage
	editable:WritePixelsBuffer(Vector2.zero, Vector2.new(w, h), pixels)
	images[cacheKey] = editable
	return editable
end

-- The Content for an ImageLabel showing a frame, or nil (flat look).
function Frames.content(frame: string, style: Style): Content?
	local image = Frames.image(frame, style)
	return if image then Content.fromObject(image) else nil
end

-- A frame's SliceCenter (nil for medallions, which are drawn unsliced at 2×).
function Frames.slice(frame: string): Rect?
	local def = FrameArt.FRAMES[frame]
	local s = def and def.slice
	if s == nil then
		return nil
	end
	return Rect.new(s[1], s[2], s[3], s[4])
end

-- Show a frame in an ImageLabel (or ImageButton): 9-slice at the pixel grid. Returns false (and changes nothing)
-- when frames are unavailable.
function Frames.apply(label: ImageLabel | ImageButton, frame: string, style: Style): boolean
	local content = Frames.content(frame, style)
	if content == nil then
		return false
	end
	label.ImageContent = content
	label.ResampleMode = Enum.ResamplerMode.Pixelated
	local slice = Frames.slice(frame)
	if slice then
		label.ScaleType = Enum.ScaleType.Slice
		label.SliceCenter = slice
		label.SliceScale = Frames.SCALE
	else
		label.ScaleType = Enum.ScaleType.Stretch
	end
	label:SetAttribute("Frame", frame)
	return true
end

-- The size of a frame's art on screen (art pixels × 2), e.g. a medallion's.
function Frames.size(frame: string): Vector2
	local w, h = FrameArt.size(frame)
	return Vector2.new(w * Frames.SCALE, h * Frames.SCALE)
end

return Frames
