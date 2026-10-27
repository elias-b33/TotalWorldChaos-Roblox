--!strict
-- Small helpers so every panel looks the same: dark rounded panels, bold labels, 44 px+ buttons.

local Widgets = {}

Widgets.PANEL = Color3.fromRGB(18, 20, 30)
Widgets.BUTTON = Color3.fromRGB(60, 120, 220)
Widgets.BUTTON_OFF = Color3.fromRGB(70, 72, 84)
Widgets.DANGER = Color3.fromRGB(200, 60, 70)
Widgets.GOOD = Color3.fromRGB(46, 160, 90)
Widgets.BUTTON_HEIGHT = 44

function Widgets.corner(parent: GuiObject, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
	c.Parent = parent
end

function Widgets.padding(parent: GuiObject, px: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.Parent = parent
end

function Widgets.list(parent: GuiObject, horizontal: boolean?, gap: number?): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	l.Padding = UDim.new(0, gap or 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.VerticalAlignment = if horizontal then Enum.VerticalAlignment.Center else Enum.VerticalAlignment.Top
	l.Parent = parent
	return l
end

function Widgets.screen(name: string, order: number?): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.DisplayOrder = order or 0
	return gui
end

-- A dark rounded panel that grows to fit its content vertically. Active, so taps and drags on it never reach
-- the map underneath.
function Widgets.panel(parent: Instance, width: number): Frame
	local f = Instance.new("Frame")
	f.Active = true
	f.Size = UDim2.fromOffset(width, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.BackgroundColor3 = Widgets.PANEL
	f.BackgroundTransparency = 0.1
	f.BorderSizePixel = 0
	f.Parent = parent
	Widgets.corner(f, 12)
	Widgets.padding(f, 10)
	return f
end

function Widgets.label(parent: Instance, text: string, size: number?, height: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, height or 22)
	l.Font = Enum.Font.GothamBold
	l.TextSize = size or 15
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.Text = text
	l.Parent = parent
	return l
end

function Widgets.button(parent: Instance, text: string, width: number, color: Color3?, onPress: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(width, Widgets.BUTTON_HEIGHT)
	b.BackgroundColor3 = color or Widgets.BUTTON
	b.Font = Enum.Font.GothamBold
	b.TextSize = 15
	b.TextWrapped = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	b.Parent = parent
	Widgets.corner(b, 10)
	b.Activated:Connect(onPress)
	return b
end

function Widgets.clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

return Widgets
