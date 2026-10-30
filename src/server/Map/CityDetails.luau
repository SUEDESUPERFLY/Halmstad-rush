--!strict
-- Detaljer som gör staden snyggare (fas 9), byggda på servern från samma kartdata:
--  * Sadeltak av tegel/plåt och fönsterband på husen
--  * Mittlinjer och gatlyktor längs huvudgatorna (rutterna i CityRoutes)
--  * Lövträd i parkerna och tallar på Galgberget
-- Allt är förankrat. Fönster och vägmarkeringar är dekor (ingen kollision eller raycast).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local Geometry = require(script.Parent.Geometry)
local Props = require(script.Parent.Props)
local CityRoutes = require(script.Parent.Generated.CityRoutes)

local CityDetails = {}

-- Material som kom med Robloxs nya material 2023. Faller tillbaka om de saknas.
function CityDetails.Material(name: string, fallback: Enum.Material): Enum.Material
	local ok, material = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok and material then material else fallback
end

local CLAY_TILES = CityDetails.Material("ClayRoofTiles", Enum.Material.Slate)
local SHINGLES = CityDetails.Material("RoofShingles", Enum.Material.Slate)

local ROAD_CODES = { A = true, Y = true, D = true }

-- Tak per husstil (se CityBuilder.STYLES): lutning (höjd / kortsida), maxhöjd och färger.
local ROOFS = {
	[0] = { -- stenstaden: plåt och tegel
		Pitch = 0.32,
		MaxHeight = 7,
		Options = {
			{ Color = Color3.fromRGB(70, 74, 80), Material = Enum.Material.Metal },
			{ Color = Color3.fromRGB(150, 68, 52), Material = CLAY_TILES },
			{ Color = Color3.fromRGB(165, 78, 58), Material = CLAY_TILES },
		},
	},
	[1] = { -- flerfamiljshus: tegeltak
		Pitch = 0.28,
		MaxHeight = 6,
		Options = {
			{ Color = Color3.fromRGB(150, 68, 52), Material = CLAY_TILES },
			{ Color = Color3.fromRGB(120, 60, 48), Material = CLAY_TILES },
			{ Color = Color3.fromRGB(75, 76, 82), Material = SHINGLES },
		},
	},
	[2] = { -- villor: tegel eller svart takpapp
		Pitch = 0.42,
		MaxHeight = 7,
		Options = {
			{ Color = Color3.fromRGB(160, 72, 54), Material = CLAY_TILES },
			{ Color = Color3.fromRGB(45, 46, 52), Material = SHINGLES },
			{ Color = Color3.fromRGB(90, 92, 98), Material = SHINGLES },
		},
	},
}

local OVERHANG = 0.8
local WINDOW_COLOR = Color3.fromRGB(52, 66, 84)
local CORNICE_COLOR = Color3.fromRGB(225, 215, 195)

local function wedge(parent: Instance, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): WedgePart
	local part = Instance.new("WedgePart")
	part.Name = "Roof"
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Parent = parent
	return part
end

-- Sadeltak med nocken längs husets långsida. Kilarnas låga kant pekar utåt.
local function pitchedRoof(parent: Instance, center: Vector3, width: number, depth: number, style: number, rng: Random)
	local roof = ROOFS[style]
	local option = roof.Options[rng:NextInteger(1, #roof.Options)]
	local alongX = width >= depth
	local long = (if alongX then width else depth) + OVERHANG * 2
	local short = (if alongX then depth else width) + OVERHANG * 2
	local height = math.clamp(short * roof.Pitch, 2, roof.MaxHeight)
	local outward = if alongX then Vector3.zAxis else Vector3.xAxis
	for _, side in { -1, 1 } do
		local direction = outward * side
		local position = center + direction * (short / 4) + Vector3.new(0, height / 2, 0)
		wedge(parent, Vector3.new(long, height, short / 2), CFrame.lookAt(position, position + direction), option.Color, option.Material)
	end
end

-- Ett fönsterband per våning. Bandet sticker ut på långsidorna men inte på gavlarna,
-- så hörnen syns som murade pelare.
local function windowBands(parent: Instance, ground: number, px: number, pz: number, width: number, depth: number, height: number)
	local alongX = width >= depth
	local size = if alongX
		then Vector3.new(math.max(width - 2.4, 1), 2.6, depth + 0.3)
		else Vector3.new(width + 0.3, 2.6, math.max(depth - 2.4, 1))
	local y = 3.5
	while y + size.Y < height - 1.5 do
		local band = Geometry.Part(parent, "Windows", size, CFrame.new(px, ground + y + size.Y / 2, pz), WINDOW_COLOR, Enum.Material.Glass)
		band.Reflectance = 0.15
		Geometry.Decor(band)
		y += 7
	end
end

-- Tak, fönster och takfot för ett hus. `ground` är markhöjden, `height` husets höjd över marken.
function CityDetails.DecorateBuilding(
	parent: Instance,
	px: number,
	pz: number,
	width: number,
	depth: number,
	ground: number,
	height: number,
	style: number,
	rng: Random
)
	local top = ground + height
	windowBands(parent, ground, px, pz, width, depth, height)
	if ROOFS[style] then
		pitchedRoof(parent, Vector3.new(px, top, pz), width, depth, style, rng)
	else
		-- Platt tak med ljus takfot (offentliga tegelbyggnader)
		local cornice = Geometry.Part(parent, "Cornice", Vector3.new(width + 1, 0.8, depth + 1), CFrame.new(px, top + 0.4, pz), CORNICE_COLOR, Enum.Material.Concrete)
		Geometry.Decor(cornice)
	end
end

local function decodeRoute(encoded: string): { Vector2 }
	local points = {}
	for x, z in encoded:gmatch("(%-?%d+),(%-?%d+)") do
		table.insert(points, Vector2.new(tonumber(x) :: number, tonumber(z) :: number))
	end
	return points
end

local function groundPoint(p: Vector2): Vector3
	return Vector3.new(p.X, MapData.GroundHeightAt(p.X, p.Y), p.Y)
end

-- Streckad mittlinje och gatlyktor längs huvudgatorna.
-- `codeAt` ger kartkoden för en punkt (CityBuilder.CodeAt).
function CityDetails.BuildStreets(parent: Instance, codeAt: (number, number) -> string?)
	local markings = Instance.new("Folder")
	markings.Name = "RoadMarkings"
	local lamps = Instance.new("Folder")
	lamps.Name = "StreetLamps"
	local white = Color3.fromRGB(235, 235, 230)
	local placedLamps: { Vector3 } = {}

	local function lampNear(position: Vector3): boolean
		for _, other in placedLamps do
			if (other - position).Magnitude < 40 then
				return true
			end
		end
		return false
	end

	for _, encoded in CityRoutes do
		local route = decodeRoute(encoded)
		local carry = 0 -- sträcka sedan förra strecket, så att mönstret fortsätter över ruttpunkterna
		local sinceLamp = 0
		local lampSide = 1
		for i = 1, #route - 1 do
			local a, b = route[i], route[i + 1]
			local length = (b - a).Magnitude
			if length > 0.1 then
				local direction = (b - a) / length
				local normal = Vector2.new(-direction.Y, direction.X)
				local onBridge = codeAt(a.X, a.Y) == "D"

				-- Mittlinje: 6 studs streck, 8 studs mellanrum
				local distance = (14 - carry) % 14
				while distance + 6 <= length do
					local from = groundPoint(a + direction * distance)
					local to = groundPoint(a + direction * (distance + 6))
					local lift = Vector3.new(0, if onBridge then 0.06 else 0.08, 0)
					local dash = Geometry.Part(markings, "CenterLine", Vector3.new(0.6, 0.1, 6), CFrame.lookAt((from + to) / 2 + lift, to + lift), white, Enum.Material.SmoothPlastic)
					Geometry.Decor(dash)
					distance += 14
				end
				carry = (carry + length) % 14

				-- Gatlyktor ungefär var 60:e stud, varannan sida, vid gatukanten
				sinceLamp += length
				if sinceLamp >= 60 then
					sinceLamp = 0
					lampSide = -lampSide
					local center = (a + b) / 2
					for offset = 4, 40, 2 do
						local p = center + normal * lampSide * offset
						local code = codeAt(p.X, p.Y)
						if code == nil or code == "W" then
							break
						end
						if not ROAD_CODES[code] then
							local base = groundPoint(center + normal * lampSide * (offset + 1))
							if not lampNear(base) then
								table.insert(placedLamps, base)
								local towardRoad = Vector3.new(-normal.X * lampSide, 0, -normal.Y * lampSide)
								Props.StreetLamp(lamps, base, towardRoad)
							end
							break
						end
					end
				end
			end
		end
	end
	markings.Parent = parent
	lamps.Parent = parent
	return #placedLamps
end

export type KeepOut = { Center: Vector2, Radius: number }

-- Lövträd i parkerna (kod P), tallar på Galgberget. Inga träd nära gator eller landmärken.
function CityDetails.BuildParkTrees(
	parent: Instance,
	rng: Random,
	codeAt: (number, number) -> string?,
	area: { MinX: number, MinZ: number, MaxX: number, MaxZ: number },
	keepOut: { KeepOut }
)
	local folder = Instance.new("Folder")
	folder.Name = "ParkTrees"
	local hill = MapData.Hills[1]
	local spacing = 26
	local count = 0
	for z = area.MinZ, area.MaxZ, spacing do
		for x = area.MinX, area.MaxX, spacing do
			local px = x + rng:NextNumber(-8, 8)
			local pz = z + rng:NextNumber(-8, 8)
			if rng:NextNumber() < 0.45 and codeAt(px, pz) == "P" then
				local clear = true
				for _, zone in keepOut do
					if (Vector2.new(px, pz) - zone.Center).Magnitude < zone.Radius then
						clear = false
						break
					end
				end
				for _, offset in { Vector2.new(8, 0), Vector2.new(-8, 0), Vector2.new(0, 8), Vector2.new(0, -8) } do
					local code = codeAt(px + offset.X, pz + offset.Y)
					if code == nil or ROAD_CODES[code] or code == "W" or code == "R" then
						clear = false
						break
					end
				end
				if clear then
					local base = Vector3.new(px, MapData.GroundHeightAt(px, pz), pz)
					local onHill = (Vector2.new(px, pz) - hill.Center).Magnitude < hill.Radius
					if onHill and rng:NextNumber() < 0.7 then
						Props.Pine(folder, base, rng)
					else
						Props.Tree(folder, base, rng)
					end
					count += 1
					if count % 300 == 0 then
						task.wait()
					end
				end
			end
		end
	end
	folder.Parent = parent
	return count
end

return CityDetails
