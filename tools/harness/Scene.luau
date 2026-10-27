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
		node.radius = { inst.CornerRadius.Scale, inst.CornerRadius.Offset }
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
	fs.writeFile(path, serde.encode("json", Scene.capture(client)))
end

return Scene
