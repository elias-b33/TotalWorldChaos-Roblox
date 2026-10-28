--!nocheck
-- Dumps what one client would see (camera, parts, billboards, selection, GUI tree) to JSON for render_scene.py.

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Emulator = require("./Emulator")

local Scene = {}

local function c3(c)
	return { c.R, c.G, c.B }
end

local function udim2(u)
	return { u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset }
end

local function enumName(e)
	return tostring(e):match("%.([%w_]+)$") or tostring(e)
end

local function textOf(inst)
	local label = if inst:IsA("TextLabel") or inst:IsA("TextButton") then inst else inst:FindFirstChildOfClass("TextLabel")
	return label
end

-- EditableImages shown by ImageLabels, written next to the scene as raw RGBA when it is saved.
local images = {}

local function dumpGui(inst)
	local node = {
		class = inst.ClassName,
		name = inst.Name,
		children = {},
	}
	if inst:IsA("GuiObject") then
		node.visible = inst.Visible
		node.size = udim2(inst.Size)
		node.position = udim2(inst.Position)
		node.anchor = { inst.AnchorPoint.X, inst.AnchorPoint.Y }
		node.bg = c3(inst.BackgroundColor3)
		node.bgT = inst.BackgroundTransparency
		node.autoSize = enumName(inst.AutomaticSize)
		node.layoutOrder = inst.LayoutOrder
		node.zIndex = inst.ZIndex
		if inst:IsA("TextLabel") or inst:IsA("TextButton") then
			node.text = inst.Text
			node.textSize = inst.TextSize
			node.textColor = c3(inst.TextColor3)
			node.textXAlign = enumName(inst.TextXAlignment)
			node.textWrapped = inst.TextWrapped
			node.stroke = inst.TextStrokeTransparency < 0.9
			node.strokeColor = c3(inst.TextStrokeColor3)
			node.strokeT = inst.TextStrokeTransparency
			node.textT = inst.TextTransparency
			node.textYAlign = enumName(inst.TextYAlignment)
			node.truncate = enumName(inst.TextTruncate) ~= "None"
			node.font = { family = inst.FontFace.Family, weight = enumName(inst.FontFace.Weight) }
		end
		if inst.Rotation ~= 0 then
			node.rotation = inst.Rotation
		end
		if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
			local image = Emulator.editableImage(inst.ImageContent.Uri or "")
			if image then
				table.insert(images, image)
				node.image = {
					index = #images,
					width = image.Size.X,
					height = image.Size.Y,
					pixelated = enumName(inst.ResampleMode) == "Pixelated",
					fit = enumName(inst.ScaleType) == "Fit", -- the whole image inside the box, keeping its shape
					color = c3(inst.ImageColor3),
					transparency = inst.ImageTransparency,
				}
				if enumName(inst.ScaleType) == "Slice" then -- a 9-slice frame (FrameArt)
					local r = inst.SliceCenter
					node.image.slice = { r.Min.X, r.Min.Y, r.Max.X, r.Max.Y }
					node.image.sliceScale = inst.SliceScale
				end
			end
		end
		-- every enabled stroke (an object may have several: an ink outline and a glow), and its drop shadows
		local strokes, shadows = {}, {}
		for _, child in inst:GetChildren() do
			if child:IsA("UIStroke") and child.Enabled then
				table.insert(strokes, {
					color = c3(child.Color),
					thickness = child.Thickness,
					transparency = child.Transparency,
					-- Contextual on a text object outlines the text, not the box
					text = enumName(child.ApplyStrokeMode) == "Contextual"
						and (inst:IsA("TextLabel") or inst:IsA("TextButton")),
					position = enumName(child.BorderStrokePosition), -- Outer, Center or Inner
					zIndex = child.ZIndex,
				})
			elseif child:IsA("UIShadow") and child.Enabled then
				table.insert(shadows, {
					color = c3(child.Color),
					transparency = child.Transparency,
					offset = { child.Offset.X.Offset, child.Offset.Y.Offset },
					blur = child.BlurRadius.Offset,
					spread = { child.Spread.X.Offset, child.Spread.Y.Offset },
				})
			end
		end
		if #strokes > 0 then
			node.uiStrokes = strokes
			node.uiStroke = strokes[#strokes]
		end
		if #shadows > 0 then
			node.shadows = shadows
		end
		local gradient = inst:FindFirstChildOfClass("UIGradient")
		if gradient and gradient.Enabled then
			local colors, alphas = {}, {}
			for _, k in gradient.Color.Keypoints do
				table.insert(colors, { k.Time, k.Value.R, k.Value.G, k.Value.B })
			end
			for _, k in gradient.Transparency.Keypoints do
				table.insert(alphas, { k.Time, k.Value })
			end
			node.gradient = {
				colors = colors,
				transparency = alphas,
				rotation = gradient.Rotation,
				offset = { gradient.Offset.X, gradient.Offset.Y },
			}
		end
		local scale = inst:FindFirstChildOfClass("UIScale")
		if scale and scale.Scale ~= 1 then
			node.scale = scale.Scale
		end
	elseif inst:IsA("UIListLayout") then
		node.fill = enumName(inst.FillDirection)
		node.padding = { inst.Padding.Scale, inst.Padding.Offset }
		node.valign = enumName(inst.VerticalAlignment)
		node.halign = enumName(inst.HorizontalAlignment)
	elseif inst:IsA("UIGridLayout") then
		node.cell = udim2(inst.CellSize)
		node.cellPadding = udim2(inst.CellPadding)
	elseif inst:IsA("UIPadding") then
		node.pad = {
			inst.PaddingTop.Offset,
			inst.PaddingBottom.Offset,
			inst.PaddingLeft.Offset,
			inst.PaddingRight.Offset,
		}
	elseif inst:IsA("UICorner") then
		-- CornerRadius sets all four corners; an object that sets corners one by one never touches it (Lune then
		-- has no value for it), so read the four instead
		local ok, radius = pcall(function()
			return inst.CornerRadius
		end)
		if ok then
			node.radius = { radius.Scale, radius.Offset }
		else
			node.radius = { 0, 0 }
			node.corners = {}
			for i, c in { inst.TopLeftRadius, inst.TopRightRadius, inst.BottomRightRadius, inst.BottomLeftRadius } do
				node.corners[i] = { c.Scale, c.Offset }
			end
		end
	elseif inst:IsA("UISizeConstraint") then
		node.maxSize = { inst.MaxSize.X, inst.MaxSize.Y }
	elseif inst:IsA("ScreenGui") then
		node.enabled = inst.Enabled
		node.displayOrder = inst.DisplayOrder
	end
	for _, child in inst:GetChildren() do
		table.insert(node.children, dumpGui(child))
	end
	return node
end

function Scene.capture(client)
	local ws = client.dm:GetService("Workspace")
	local cam = client.camera
	local parts = {}
	local billboards = {}
	local selections = {}
	local highlights = {}
	for _, d in ws:GetDescendants() do
		if d:IsA("BasePart") and not d:IsA("Terrain") then
			table.insert(parts, {
				name = d.Name,
				shape = if d:IsA("WedgePart") then "Wedge" elseif d:IsA("Part") then enumName(d.Shape) else "Block",
				cf = { d.CFrame:GetComponents() },
				size = { d.Size.X, d.Size.Y, d.Size.Z },
				color = c3(d.Color),
				transparency = d.Transparency,
				material = enumName(d.Material),
				variant = d.MaterialVariant,
			})
		elseif d:IsA("BillboardGui") and d.Enabled then
			local adornee = d.Adornee or d.Parent
			if adornee and adornee:IsA("BasePart") then
				local offset = d.StudsOffsetWorldSpace
				local p = adornee.CFrame.Position + offset
				table.insert(billboards, {
					pos = { p.X, p.Y, p.Z },
					maxDistance = d.MaxDistance,
					size = udim2(d.Size),
					gui = dumpGui(d),
				})
			end
		elseif d:IsA("Highlight") and d.Enabled and d.Adornee then
			for _, p in d.Adornee:GetDescendants() do
				if p:IsA("BasePart") then
					table.insert(highlights, {
						shape = if p:IsA("WedgePart") then "Wedge" else "Block",
						cf = { p.CFrame:GetComponents() },
						size = { p.Size.X, p.Size.Y, p.Size.Z },
						color = c3(d.FillColor),
						alpha = 1 - d.FillTransparency,
					})
				end
			end
		elseif d:IsA("SelectionBox") and d.Visible and d.Adornee then
			local a = d.Adornee
			table.insert(selections, {
				cf = { a.CFrame:GetComponents() },
				size = { a.Size.X, a.Size.Y, a.Size.Z },
				shape = if a:IsA("Part") then enumName(a.Shape) else "Block",
				color = c3(d.Color3),
			})
		end
	end
	local gui = {}
	for _, sg in client.localPlayer.PlayerGui:GetChildren() do
		table.insert(gui, dumpGui(sg))
	end
	return {
		viewport = { client.viewport.X, client.viewport.Y },
		camera = { cf = { cam.CFrame:GetComponents() }, fov = cam.FieldOfView },
		parts = parts,
		billboards = billboards,
		selections = selections,
		highlights = highlights,
		water = (function()
			local out = {}
			for _, b in Emulator.terrainBlocks(client) do
				local t = ws:FindFirstChildOfClass("Terrain")
				table.insert(out, {
					cf = { b.cf:GetComponents() },
					size = { b.size.X, b.size.Y, b.size.Z },
					color = c3(t.WaterColor),
				})
			end
			return out
		end)(),
		gui = gui,
		time = Emulator.now(),
	}
end

function Scene.save(client, path: string)
	Emulator.flushProperties() -- captions catch up with their roots' text (see Emulator.flushProperties)
	images = {}
	local scene = Scene.capture(client)
	for i, image in images do
		local file = string.format("%s.img%d.rgba", path, i)
		fs.writeFile(file, buffer.tostring(image.pixels))
		scene.images = scene.images or {}
		scene.images[i] = file
	end
	fs.writeFile(path, serde.encode("json", scene))
end

return Scene
