--!strict
-- Which province names fit on screen without overlapping (docs/DESIGN.md "Map rendering"). Pure: boxes in, the
-- ids to show out, so it runs under Lune. Bigger provinces claim their space first; a name that would overlap one
-- already placed stays hidden until the player zooms in far enough for both to fit.

local LabelLayout = {}

export type Box = {
	id: number,
	x: number, -- left edge, screen pixels
	y: number, -- top edge
	w: number,
	h: number,
	priority: number, -- higher claims space first (province size)
}

local GAP = 2 -- screen pixels kept clear between two names

local function overlaps(a: Box, b: Box): boolean
	return a.x < b.x + b.w + GAP and b.x < a.x + a.w + GAP and a.y < b.y + b.h + GAP and b.y < a.y + a.h + GAP
end

-- The ids of the boxes to show: greedily by priority (ties by id, so the result never flickers between frames).
function LabelLayout.place(boxes: { Box }): { [number]: boolean }
	local order = table.clone(boxes)
	table.sort(order, function(a, b)
		if a.priority ~= b.priority then
			return a.priority > b.priority
		end
		return a.id < b.id
	end)
	local placed: { Box } = {}
	local shown: { [number]: boolean } = {}
	for _, box in order do
		local free = true
		for _, other in placed do
			if overlaps(box, other) then
				free = false
				break
			end
		end
		if free then
			table.insert(placed, box)
			shown[box.id] = true
		end
	end
	return shown
end

-- A text's width in screen pixels, estimated for GothamBold at this size (TextService isn't available everywhere
-- this runs, and an estimate a few pixels off is fine for spacing).
function LabelLayout.textWidth(text: string, textSize: number): number
	return (utf8.len(text) or #text) * textSize * 0.6 + 4
end

return LabelLayout
