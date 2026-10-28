--!strict
-- Pixel icons on screen (docs/DESIGN.md "UI style"). Each icon is painted once by IconArt into a 16×16
-- EditableImage (1 KB), on first use, and shared by every label that shows it; ImageLabels draw it with
-- pixelated resampling so it stays crisp at 16, 20, 24 or 32 px. Where EditableImage isn't allowed (the game
-- setting is off, or the phone is out of image memory) icons fall back to a plain emoji in a TextLabel.

local AssetService = game:GetService("AssetService")

local Client = script.Parent.Parent
local IconArt = require(Client.IconArt)

local Icons = {}

local images: { [string]: EditableImage | false } = {} -- painted icons by name (false = EditableImage unavailable)
local unavailable = false -- once one icon fails, every icon uses its fallback

-- The shared EditableImage for an icon, or nil when the device can't make one.
function Icons.image(name: string): EditableImage?
	local cached = images[name]
	if cached ~= nil then
		return if cached then cached else nil
	end
	if unavailable or IconArt.rows(name) == nil then
		images[name] = false
		return nil
	end
	local pixels, w, h = IconArt.paint(name)
	local ok, result = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(w, h) })
	end)
	if not ok or result == nil then
		unavailable = true
		images[name] = false
		return nil
	end
	local editable = result :: EditableImage
	editable:WritePixelsBuffer(Vector2.zero, Vector2.new(w, h), pixels)
	images[name] = editable
	return editable
end

-- The emoji a device without EditableImage shows for an icon.
function Icons.fallback(name: string): string
	return IconArt.FALLBACK[name] or "•"
end

-- The icon for an emoji at the start of a text, and the rest of the text ("⚔ War!" -> "war", "War!").
function Icons.split(text: string): (string?, string)
	return IconArt.split(text)
end

-- The icon that stands for an emoji (relation marks, power icons...), or nil.
function Icons.fromEmoji(emoji: string): string?
	return IconArt.EMOJI[(string.gsub(emoji, "\u{FE0F}", ""))]
end

-- An icon `size` px square: an ImageLabel named "Icon", or a TextLabel with the emoji when there is no image.
function Icons.label(parent: Instance, name: string, size: number): GuiObject
	local image = Icons.image(name)
	local obj: GuiObject
	if image then
		local l = Instance.new("ImageLabel")
		l.BackgroundTransparency = 1
		l.ResampleMode = Enum.ResamplerMode.Pixelated
		l.ImageContent = Content.fromObject(image)
		obj = l
	else
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.FontFace = Font.fromEnum(Enum.Font.BuilderSansBold)
		l.TextSize = math.max(14, math.floor(size * 0.8))
		l.TextColor3 = Color3.new(1, 1, 1)
		l.Text = Icons.fallback(name)
		obj = l
	end
	obj.Name = "Icon"
	obj.Size = UDim2.fromOffset(size, size)
	obj:SetAttribute("Icon", name)
	obj.Parent = parent
	return obj
end

-- Show another icon in a label made by Icons.label (no-op when it already shows that one).
function Icons.set(obj: GuiObject, name: string?)
	if name == nil then
		obj.Visible = false
		return
	end
	obj.Visible = true
	if obj:GetAttribute("Icon") == name then
		return
	end
	obj:SetAttribute("Icon", name)
	local image = Icons.image(name)
	if obj:IsA("ImageLabel") then
		if image then
			obj.ImageContent = Content.fromObject(image)
		end
	elseif obj:IsA("TextLabel") then
		obj.Text = Icons.fallback(name)
	end
end

-- Grey an icon out (a disabled button) or bring its colours back.
function Icons.dim(obj: GuiObject, dimmed: boolean)
	if obj:IsA("ImageLabel") then
		obj.ImageTransparency = if dimmed then 0.55 else 0
	elseif obj:IsA("TextLabel") then
		obj.TextTransparency = if dimmed then 0.55 else 0
	end
end

return Icons
