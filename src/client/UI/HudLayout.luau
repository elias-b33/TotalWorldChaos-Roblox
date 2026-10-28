--!strict
-- Where the top bar goes (docs/UI_DIRECTION.md 7.9), and so where everything under it starts. The bar's plates
-- float in Roblox's own top-bar row, right of Roblox's buttons (GuiService.TopbarInset is the free part of that
-- row, and it changes at runtime); when the row is too narrow or too short, they go in a row just under it. One
-- runtime value, contentTop, places the nations drawer, the offers, the tutorial card and the toasts; the map frames
-- itself under barBottom.

local GuiService = game:GetService("GuiService")

local Theme = require(script.Parent.Theme)

local HudLayout = {}

HudLayout.ITEM = Theme.size.bar -- the tallest plate (a gem button), phone px
HudLayout.EDGE = Theme.space.m -- kept clear at each end of the row
HudLayout.MIN_WIDTH = 420 -- a free row narrower than this: the fallback row under it
HudLayout.GAP = Theme.space.m -- under the bar

export type Row = {
	x0: number, -- the row's left and right ends, screen px
	x1: number,
	top: number, -- the plates' top, screen px
	scale: number, -- the bar's scale: the UI's, but never taller than Roblox's row
	inRow: boolean, -- in Roblox's row (false: the fallback row under it)
}

-- The bar's row for a top-bar inset (screen px), a screen size and the UI's scale.
function HudLayout.compute(inset: Rect, screen: Vector2, uiScale: number): Row
	local item = HudLayout.ITEM
	if inset.Width >= HudLayout.MIN_WIDTH and inset.Height >= item then
		local k = math.max(1, math.min(uiScale, inset.Height / (item + 2)))
		return {
			x0 = inset.Min.X + HudLayout.EDGE,
			x1 = inset.Max.X - HudLayout.EDGE,
			top = inset.Min.Y + math.floor((inset.Height - item * k) / 2),
			scale = k,
			inRow = true,
		}
	end
	return {
		x0 = HudLayout.EDGE,
		x1 = screen.X - HudLayout.EDGE,
		top = inset.Max.Y + 4,
		scale = uiScale,
		inRow = false,
	}
end

local listeners: { () -> () } = {}

local function screenSize(): Vector2
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(844, 390)
end

-- The row now.
function HudLayout.row(): Row
	local ok, inset = pcall(function()
		return GuiService.TopbarInset
	end)
	local rect = if ok and typeof(inset) == "Rect" then inset else Rect.new(0, 0, 0, 0)
	local screen = screenSize()
	return HudLayout.compute(rect, screen, Theme.uiScale(screen))
end

-- The bar's bottom edge, screen px: the map's free area starts here.
function HudLayout.barBottom(): number
	local row = HudLayout.row()
	return row.top + HudLayout.ITEM * row.scale
end

-- Where content under the bar may start, in the phone px of a screen that keeps Roblox's top-bar inset (its
-- root objects are fitted with Widgets.fit, which scales their offsets by the UI's scale).
function HudLayout.contentTop(): number
	local ok, inset = pcall(function()
		return GuiService:GetGuiInset()
	end)
	local insetY = if ok and typeof(inset) == "Vector2" then inset.Y else 0
	local screen = screenSize()
	local k = Theme.uiScale(screen)
	return math.max(0, HudLayout.barBottom() + HudLayout.GAP * k - insetY) / k
end

-- Call `fn` when the row moves (Roblox's row changed, or the screen did).
function HudLayout.onChange(fn: () -> ())
	table.insert(listeners, fn)
end

local function changed()
	for _, fn in listeners do
		task.spawn(fn)
	end
end

GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(changed)
local camera = workspace.CurrentCamera
if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(changed)
end

return HudLayout
