--!strict
-- Stora blockbokstäver av Parts (5x7-pixelfont). Används för HALMSTAD-skylten på Galgberget.

local Geometry = require(script.Parent.Geometry)

local Letters = {}

local FONT: { [string]: { string } } = {
	A = { "01110", "10001", "10001", "11111", "10001", "10001", "10001" },
	D = { "11110", "10001", "10001", "10001", "10001", "10001", "11110" },
	H = { "10001", "10001", "10001", "11111", "10001", "10001", "10001" },
	L = { "10000", "10000", "10000", "10000", "10000", "10000", "11111" },
	M = { "10001", "11011", "10101", "10001", "10001", "10001", "10001" },
	S = { "01111", "10000", "10000", "01110", "00001", "00001", "11110" },
	T = { "11111", "00100", "00100", "00100", "00100", "00100", "00100" },
}

local COLUMNS, ROWS = 5, 7
local LETTER_GAP = 1.5 -- i pixlar

type Rect = { C0: number, C1: number, R0: number, R1: number }

-- Slår ihop pixlar till rektanglar: vågräta körningar i varje rad, sedan lodräta
-- sammanslagningar av identiska körningar i följande rader.
local function rectangles(glyph: { string }): { Rect }
	local open: { [string]: Rect } = {}
	local done: { Rect } = {}
	for row = 1, ROWS do
		local line = glyph[row]
		local runs: { [string]: boolean } = {}
		local col = 1
		while col <= COLUMNS do
			if line:sub(col, col) == "1" then
				local start = col
				while col + 1 <= COLUMNS and line:sub(col + 1, col + 1) == "1" do
					col += 1
				end
				local key = start .. ":" .. col
				runs[key] = true
				local existing = open[key]
				if existing then
					existing.R1 = row
				else
					open[key] = { C0 = start, C1 = col, R0 = row, R1 = row }
				end
			end
			col += 1
		end
		for key, rect in open do
			if not runs[key] then
				table.insert(done, rect)
				open[key] = nil
			end
		end
	end
	for _, rect in open do
		table.insert(done, rect)
	end
	return done
end

-- Bygger texten centrerad kring `center` (marknivå). `right` är läsriktningen,
-- `groundAt(x, z)` ger markhöjden så att varje bokstav står på backen.
function Letters.Build(
	parent: Instance,
	text: string,
	center: Vector3,
	right: Vector3,
	pixel: number,
	color: Color3,
	groundAt: (number, number) -> number
)
	local folder = Instance.new("Folder")
	folder.Name = "Sign_" .. text
	folder.Parent = parent

	local letterWidth = COLUMNS * pixel
	local step = letterWidth + LETTER_GAP * pixel
	local totalWidth = #text * step - LETTER_GAP * pixel
	local facing = right:Cross(Vector3.yAxis) -- framsidan, bort från läsaren räknat som -Z
	local thickness = pixel * 0.6

	for index = 1, #text do
		local char = text:sub(index, index)
		local glyph = FONT[char]
		if glyph then
			local letterLeft = -totalWidth / 2 + (index - 1) * step
			local letterCenter = center + right * (letterLeft + letterWidth / 2)
			local ground = groundAt(letterCenter.X, letterCenter.Z)
			local bottom = ground + 3
			local frame = CFrame.fromMatrix(Vector3.new(letterCenter.X, bottom, letterCenter.Z), right, Vector3.yAxis)

			for _, rect in rectangles(glyph) do
				local width = (rect.C1 - rect.C0 + 1) * pixel
				local height = (rect.R1 - rect.R0 + 1) * pixel
				local x = (rect.C0 - 1) * pixel + width / 2 - letterWidth / 2
				local y = (ROWS - rect.R1) * pixel + height / 2
				local part = Geometry.Part(folder, char, Vector3.new(width, height, thickness), frame * CFrame.new(x, y, 0), color, Enum.Material.SmoothPlastic)
				Geometry.Obstacle(part)
			end

			-- Stöttor bakom bokstaven ner i backen
			for _, offset in { -letterWidth * 0.3, letterWidth * 0.3 } do
				local top = (frame * CFrame.new(offset, pixel, thickness)).Position
				local foot = Vector3.new(top.X, groundAt(top.X, top.Z) - 2, top.Z)
				Geometry.Between(folder, "Support", foot, top, 0.8, Color3.fromRGB(120, 120, 125), Enum.Material.Metal)
			end
		end
	end
	local _ = facing
end

return Letters
