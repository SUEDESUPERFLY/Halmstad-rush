--!strict
-- Bygger Halmstad från de genererade kartdatafilerna:
--  * Terrain: ett material per 4x4-studs-ruta (asfalt, trottoar, gräs, vatten, broar, sand)
--  * Hus: ett block per fotavtryck, med färg och material efter stadsdelens stil
--  * Respawnpunkter mitt på gatorna
-- Allt utanför stadskartan (havet, Tylösand, Galgbergets norra sida) byggs också här.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local CityDetails = require(script.Parent.CityDetails)
local Geometry = require(script.Parent.Geometry)
local CityGrid = require(script.Parent.Generated.CityGrid)
local CityBuildings = require(script.Parent.Generated.CityBuildings)
local CityRoadPoints = require(script.Parent.Generated.CityRoadPoints)

local CityBuilder = {}

local CELL = CityGrid.CellSize
local BOTTOM = -16 -- terrängens undersida
local CHUNK = 64 -- celler per WriteVoxels-anrop i varje led

local Material = Enum.Material

-- Kod -> markmaterial (W = vatten, D = brodäck över vatten)
local SURFACE: { [string]: Enum.Material } = {
	A = Material.Asphalt,
	Y = Material.Asphalt,
	B = Material.Pavement,
	K = Material.Pavement, -- trottoar: kvarterskant mot gata
	C = Material.Cobblestone, -- gårdar i stenstaden
	L = Material.Grass, -- gräsmattor och trädgårdar utanför centrum
	P = Material.Grass,
	G = Material.Concrete,
	F = Material.LeafyGrass,
	S = Material.Grass,
	R = Material.Pavement,
	N = Material.Sand,
}

local codeBytes: buffer
local codeOf: { [number]: string } = {}

local function decodeGrid()
	local width, height = CityGrid.Width, CityGrid.Height
	codeBytes = buffer.create(width * height)
	local codes = CityGrid.Codes
	local indexOf: { [string]: number } = {}
	for i = 1, #codes do
		local ch = codes:sub(i, i)
		indexOf[ch] = i
		codeOf[i] = ch
	end
	for row, line in CityGrid.Rows do
		local offset = (row - 1) * width
		for ch, count in line:gmatch("(%a)(%d+)") do
			local n = tonumber(count) :: number
			buffer.fill(codeBytes, offset, indexOf[ch], n)
			offset += n
		end
	end
end

-- Koden för rutan som innehåller världspunkten (x, z), eller nil utanför stadskartan.
function CityBuilder.CodeAt(x: number, z: number): string?
	local cx = math.floor((x - CityGrid.OriginX) / CELL)
	local cz = math.floor((z - CityGrid.OriginZ) / CELL)
	if cx < 0 or cz < 0 or cx >= CityGrid.Width or cz >= CityGrid.Height then
		return nil
	end
	return codeOf[buffer.readu8(codeBytes, cz * CityGrid.Width + cx)]
end

local function isRoad(code: string?): boolean
	return code == "A" or code == "Y" or code == "D"
end

-- Som CodeAt, men kvarteren delas upp: trottoar (K) närmast gatan, gårdar (C) i
-- stenstaden och gräs (L) längre ut. Zonerna följer husgeneratorn (750 / 1500 studs).
function CityBuilder.SurfaceCodeAt(x: number, z: number): string?
	local code = CityBuilder.CodeAt(x, z)
	if code ~= "B" then
		return code
	end
	if
		isRoad(CityBuilder.CodeAt(x + CELL, z))
		or isRoad(CityBuilder.CodeAt(x - CELL, z))
		or isRoad(CityBuilder.CodeAt(x, z + CELL))
		or isRoad(CityBuilder.CodeAt(x, z - CELL))
	then
		return "K"
	end
	return if math.sqrt(x * x + z * z) < 750 then "C" else "L"
end

-- Skriver terräng för ett rektangulärt område (i hela celler) med en materialfunktion.
local function writeArea(minX: number, minZ: number, countX: number, countZ: number, codeAt: (number, number) -> string)
	for chunkX = 0, countX - 1, CHUNK do
		for chunkZ = 0, countZ - 1, CHUNK do
			local nx = math.min(CHUNK, countX - chunkX)
			local nz = math.min(CHUNK, countZ - chunkZ)
			local x0 = minX + chunkX * CELL
			local z0 = minZ + chunkZ * CELL

			local codes = table.create(nx * nz)
			local heights = table.create(nx * nz)
			local maxHeight = 0
			for ix = 1, nx do
				local x = x0 + (ix - 0.5) * CELL
				for iz = 1, nz do
					local z = z0 + (iz - 0.5) * CELL
					local index = (ix - 1) * nz + iz
					codes[index] = codeAt(x, z)
					local h = MapData.GroundHeightAt(x, z)
					heights[index] = h
					if h > maxHeight then
						maxHeight = h
					end
				end
			end

			local top = math.max(0, math.ceil(maxHeight / CELL) * CELL)
			local layers = (top - BOTTOM) / CELL
			local materials = table.create(nx)
			local occupancies = table.create(nx)
			for ix = 1, nx do
				local matX = table.create(layers)
				local occX = table.create(layers)
				for iy = 1, layers do
					matX[iy] = table.create(nz)
					occX[iy] = table.create(nz)
				end
				for iz = 1, nz do
					local index = (ix - 1) * nz + iz
					local code = codes[index]
					local h = heights[index]
					local surface = SURFACE[code] or Material.Grass
					for iy = 1, layers do
						local y0 = BOTTOM + (iy - 1) * CELL
						local material, occupancy = Material.Air, 0
						if code == "W" or code == "D" then
							if y0 < -12 then
								material, occupancy = Material.Sand, 1
							elseif y0 < -4 then
								material, occupancy = Material.Water, 1
							elseif code == "D" and y0 < 0 then
								material, occupancy = Material.Asphalt, 1
							end
						else
							occupancy = math.clamp((h - y0) / CELL, 0, 1)
							if occupancy > 0 then
								material = surface
							end
						end
						matX[iy][iz] = material
						occX[iy][iz] = occupancy
					end
				end
				materials[ix] = matX
				occupancies[ix] = occX
			end

			local region = Region3.new(Vector3.new(x0, BOTTOM, z0), Vector3.new(x0 + nx * CELL, top, z0 + nz * CELL))
			workspace.Terrain:WriteVoxels(region, CELL, materials, occupancies)
		end
		task.wait() -- låt servern andas mellan kolumnerna
	end
end

local function terrainBox(min: Vector3, max: Vector3, material: Enum.Material)
	local size = max - min
	local maxChunk = 1024
	local nx = math.max(1, math.ceil(size.X / maxChunk))
	local nz = math.max(1, math.ceil(size.Z / maxChunk))
	local chunkSize = Vector3.new(size.X / nx, size.Y, size.Z / nz)
	for ix = 0, nx - 1 do
		for iz = 0, nz - 1 do
			local chunkMin = min + Vector3.new(ix * chunkSize.X, 0, iz * chunkSize.Z)
			workspace.Terrain:FillBlock(CFrame.new(chunkMin + chunkSize / 2), chunkSize, material)
		end
	end
end

local function terrainRoad(a: Vector2, b: Vector2, width: number)
	local from = Vector3.new(a.X, -2, a.Y)
	local to = Vector3.new(b.X, -2, b.Y)
	local length = (to - from).Magnitude + width
	workspace.Terrain:FillBlock(CFrame.lookAt((from + to) / 2, to), Vector3.new(width, 4, length), Material.Asphalt)
end

local function setTerrainLook()
	local terrain = workspace.Terrain
	terrain:SetMaterialColor(Material.Asphalt, Color3.fromRGB(62, 64, 70))
	terrain:SetMaterialColor(Material.Pavement, Color3.fromRGB(176, 170, 160))
	terrain:SetMaterialColor(Material.Cobblestone, Color3.fromRGB(140, 132, 122))
	terrain:SetMaterialColor(Material.Concrete, Color3.fromRGB(150, 150, 152))
	terrain:SetMaterialColor(Material.Grass, Color3.fromRGB(96, 140, 70))
	terrain:SetMaterialColor(Material.LeafyGrass, Color3.fromRGB(128, 150, 80))
	terrain:SetMaterialColor(Material.Sand, Color3.fromRGB(226, 208, 160))
	terrain.WaterColor = Color3.fromRGB(40, 95, 115)
	terrain.WaterTransparency = 0.5
	terrain.WaterReflectance = 0.6
	terrain.WaterWaveSize = 0.12
	terrain.WaterWaveSpeed = 8
end

function CityBuilder.BuildTerrain()
	decodeGrid()
	setTerrainLook()
	local city = MapData.City
	local landTop = 0

	-- 1) Gräsmark under hela världen norr om kusten
	terrainBox(Vector3.new(-4800, BOTTOM, -1700), Vector3.new(2800, landTop, MapData.CoastZ), Material.Grass)
	-- 2) Havet söder om kusten och väster om stadskartan (sandbotten + vatten)
	for _, area in
		{
			{ Vector2.new(-4800, MapData.CoastZ), Vector2.new(2800, 2700) },
			{ Vector2.new(-4800, MapData.TylosandCoastZ), Vector2.new(city.MinX, MapData.CoastZ) },
		}
	do
		local min, max = area[1], area[2]
		terrainBox(Vector3.new(min.X, BOTTOM, min.Y), Vector3.new(max.X, -12, max.Y), Material.Sand)
		terrainBox(Vector3.new(min.X, -12, min.Y), Vector3.new(max.X, -4, max.Y), Material.Water)
		terrainBox(Vector3.new(min.X, -4, min.Y), Vector3.new(max.X, landTop, max.Y), Material.Air)
	end
	-- 3) Tylösands strand
	terrainBox(Vector3.new(-4600, BOTTOM, 1072), Vector3.new(city.MinX, landTop, MapData.TylosandCoastZ), Material.Sand)

	-- 4) Själva stadskartan
	local countX = CityGrid.Width
	local countZ = CityGrid.Height
	writeArea(CityGrid.OriginX, CityGrid.OriginZ, countX, countZ, function(x, z)
		return CityBuilder.SurfaceCodeAt(x, z) or "P"
	end)

	-- 5) Galgbergets norra del utanför kartan, och sanddyner
	for _, hill in MapData.Hills do
		local minX = math.floor((hill.Center.X - hill.Radius) / CELL) * CELL
		local minZ = math.floor((hill.Center.Y - hill.Radius) / CELL) * CELL
		local maxZ = hill.Center.Y + hill.Radius
		if hill.Name == "Galgberget" then
			maxZ = math.min(maxZ, CityGrid.OriginZ) -- resten är redan skriven
		end
		local count = math.ceil(hill.Radius * 2 / CELL)
		local countRows = math.ceil((maxZ - minZ) / CELL)
		if countRows > 0 then
			local fallback = if hill.Material == Material.Sand then "N" else "P"
			writeArea(minX, minZ, count, countRows, function(x, z)
				return CityBuilder.CodeAt(x, z) or fallback
			end)
		end
	end

	-- 6) Vägar utanför stadskartan
	for _, road in MapData.ExtraRoads do
		for i = 1, #road.Points - 1 do
			terrainRoad(road.Points[i], road.Points[i + 1], road.Width)
		end
	end
end

local STYLES = {
	-- 0: stenstaden i centrum (puts i varma toner)
	[0] = {
		Material = CityDetails.Material("Plaster", Material.SmoothPlastic),
		Colors = {
			Color3.fromRGB(226, 196, 150),
			Color3.fromRGB(236, 226, 204),
			Color3.fromRGB(196, 120, 92),
			Color3.fromRGB(238, 216, 160),
			Color3.fromRGB(210, 172, 140),
			Color3.fromRGB(190, 192, 188),
		},
	},
	-- 1: flerfamiljshus (tegel och ljus puts)
	[1] = {
		Material = Material.Brick,
		Colors = {
			Color3.fromRGB(176, 104, 78),
			Color3.fromRGB(214, 190, 150),
			Color3.fromRGB(200, 198, 192),
			Color3.fromRGB(160, 90, 70),
		},
	},
	-- 2: villor (falurött, vitt, gult, ljusgrått)
	[2] = {
		Material = Material.WoodPlanks,
		Colors = {
			Color3.fromRGB(150, 45, 35),
			Color3.fromRGB(150, 45, 35),
			Color3.fromRGB(240, 238, 230),
			Color3.fromRGB(232, 204, 120),
			Color3.fromRGB(200, 205, 210),
		},
	},
	-- 3: större offentliga byggnader (tegel)
	[3] = {
		Material = Material.Brick,
		Colors = { Color3.fromRGB(165, 85, 65), Color3.fromRGB(150, 78, 60) },
	},
}

-- Flyttar in husväggar som står mot en gata, så att trottoaren syns.
local SIDEWALK = 3
local function pullBackFromRoads(px: number, pz: number, width: number, depth: number): (number, number, number, number)
	local minX, maxX = px - width / 2, px + width / 2
	local minZ, maxZ = pz - depth / 2, pz + depth / 2
	if isRoad(CityBuilder.CodeAt(minX - 2, pz)) and maxX - minX > SIDEWALK + 6 then
		minX += SIDEWALK
	end
	if isRoad(CityBuilder.CodeAt(maxX + 2, pz)) and maxX - minX > SIDEWALK + 6 then
		maxX -= SIDEWALK
	end
	if isRoad(CityBuilder.CodeAt(px, minZ - 2)) and maxZ - minZ > SIDEWALK + 6 then
		minZ += SIDEWALK
	end
	if isRoad(CityBuilder.CodeAt(px, maxZ + 2)) and maxZ - minZ > SIDEWALK + 6 then
		maxZ -= SIDEWALK
	end
	return (minX + maxX) / 2, (minZ + maxZ) / 2, maxX - minX, maxZ - minZ
end

function CityBuilder.BuildBuildings(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Buildings"
	local rng = Random.new(1307)
	local count = 0
	for x, z, w, d, h, s in (CityBuildings :: string):gmatch("(%-?%d+),(%-?%d+),(%d+),(%d+),(%d+),(%d)") do
		local px, pz = tonumber(x) :: number, tonumber(z) :: number
		local width, depth, height = tonumber(w) :: number, tonumber(d) :: number, tonumber(h) :: number
		local styleIndex = tonumber(s) :: number
		local style = STYLES[styleIndex] or STYLES[0]
		px, pz, width, depth = pullBackFromRoads(px, pz, width, depth)
		local ground = MapData.GroundHeightAt(px, pz)
		local base = ground - 1
		local part = Geometry.Part(
			folder,
			"Building",
			Vector3.new(width, height + 1, depth),
			CFrame.new(px, base + (height + 1) / 2, pz),
			style.Colors[rng:NextInteger(1, #style.Colors)],
			style.Material
		)
		Geometry.Obstacle(part)
		CityDetails.DecorateBuilding(folder, px, pz, width, depth, ground, height, styleIndex, rng)
		count += 1
		if count % 300 == 0 then
			task.wait()
		end
	end
	folder.Parent = parent
	return count
end

export type RoadPoint = { Position: Vector3, Yaw: number }

function CityBuilder.RoadPoints(): { RoadPoint }
	local points: { RoadPoint } = {}
	for x, z, yaw in (CityRoadPoints :: string):gmatch("(%-?%d+),(%-?%d+),(%-?%d+)") do
		local px, pz = tonumber(x) :: number, tonumber(z) :: number
		table.insert(points, {
			Position = Vector3.new(px, MapData.GroundHeightAt(px, pz), pz),
			Yaw = tonumber(yaw) :: number,
		})
	end
	return points
end

return CityBuilder
