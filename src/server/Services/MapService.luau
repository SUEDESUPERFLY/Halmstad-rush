--!strict
-- Bygger block-out-kartan över Halmstad från MapData när servern startar.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local Geometry = require(script.Parent.Parent.Map.Geometry)
local Landmarks = require(script.Parent.Parent.Map.Landmarks)
local VehicleService = require(script.Parent.VehicleService)

local MapService = {}

local MAP_SEED = 1307 -- samma frö = samma stad varje gång

local GRASS = Color3.fromRGB(106, 160, 80)
local ASPHALT = Color3.fromRGB(60, 62, 68)
local WATER = Color3.fromRGB(50, 120, 190)
local SEABED = Color3.fromRGB(190, 175, 130)

local ZONE_LAYER_HEIGHT = 0.04
local ROAD_TOP = 0.16
local MARKING_TOP = 0.2

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function buildGroundAndWater(map: Folder)
	local ground = folder(map, "Ground")
	local river = MapData.River
	local seaZ = MapData.SeaStartZ
	local bounds = MapData.Bounds[1]
	local minX, maxX = bounds.Min.X, bounds.Max.X
	local minZ, maxZ = bounds.Min.Y, bounds.Max.Y

	-- Land väster och öster om Nissan
	Geometry.Box(ground, "Land", Vector3.new(minX, -15, minZ), Vector3.new(river.MinX, 0, seaZ), GRASS, Enum.Material.Grass)
	Geometry.Box(ground, "Land", Vector3.new(river.MaxX, -15, minZ), Vector3.new(maxX, 0, seaZ), GRASS, Enum.Material.Grass)

	-- Botten under vattnet
	Geometry.Box(ground, "Seabed", Vector3.new(minX, -30, seaZ), Vector3.new(maxX, -15, maxZ), SEABED, Enum.Material.Sand)
	Geometry.Box(ground, "Riverbed", Vector3.new(river.MinX, -30, minZ), Vector3.new(river.MaxX, -15, seaZ), SEABED, Enum.Material.Sand)

	-- Vattenytor (går att köra igenom; respawn sker under vattenytan)
	local water = folder(map, "Water")
	local level = MapData.WaterLevel
	for _, part in Geometry.Box(water, "Sea", Vector3.new(minX, level - 1, seaZ), Vector3.new(maxX, level, maxZ), WATER, Enum.Material.Glass) do
		part.Transparency = 0.3
		Geometry.Decor(part)
	end
	for _, part in
		Geometry.Box(water, "Nissan", Vector3.new(river.MinX, level - 1, minZ), Vector3.new(river.MaxX, level, seaZ), WATER, Enum.Material.Glass)
	do
		part.Transparency = 0.3
		Geometry.Decor(part)
	end
end

local function buildZones(map: Folder)
	local zones = folder(map, "Zones")
	for _, zone in MapData.Zones do
		Geometry.Slab(zones, zone.Name, zone.Min, zone.Max, zone.Layer * ZONE_LAYER_HEIGHT, zone.Color, zone.Material)
	end
end

local function addTrees(parent: Instance, a: Vector2, b: Vector2, offset: number, rng: Random)
	local direction = (b - a).Unit
	local side = Vector2.new(-direction.Y, direction.X)
	local length = (b - a).Magnitude
	for distance = 40, length - 40, 45 do
		for _, sign in { -1, 1 } do
			if rng:NextNumber() > 0.2 then
				local p = a + direction * distance + side * sign * (offset + rng:NextNumber(0, 10))
				local trunk = Geometry.Cylinder(parent, "TreeTrunk", Vector3.new(p.X, 0, p.Y), 1.2, 10, Color3.fromRGB(110, 80, 55), Enum.Material.Wood)
				Geometry.Obstacle(trunk)
				Geometry.Ball(parent, "TreeCrown", Vector3.new(p.X, 13, p.Y), rng:NextNumber(5, 7), Color3.fromRGB(70, 140, 70))
			end
		end
	end
end

local function buildRoads(map: Folder, rng: Random)
	local roads = folder(map, "Roads")
	local trees = folder(map, "Trees")
	for _, road in MapData.Roads do
		local roadFolder = folder(roads, road.Name)
		for i, point in road.Points do
			-- Rund fog i varje knutpunkt så att kurvor och korsningar blir hela
			Geometry.Cylinder(roadFolder, "Joint", Vector3.new(point.X, ROAD_TOP - 1, point.Y), road.Width / 2, 1, ASPHALT, Enum.Material.Asphalt)
			local nextPoint = road.Points[i + 1]
			if nextPoint then
				Geometry.Strip(roadFolder, "Segment", point, nextPoint, road.Width, ROAD_TOP, 1, ASPHALT, Enum.Material.Asphalt)
				if road.LaneLines then
					local direction = (nextPoint - point).Unit
					local length = (nextPoint - point).Magnitude
					for distance = 20, length - 20, 30 do
						local a = point + direction * distance
						local line = Geometry.Strip(roadFolder, "LaneLine", a, a + direction * 12, 1, MARKING_TOP, 0.1, Color3.new(1, 1, 1))
						Geometry.Decor(line)
					end
				end
				if road.Trees then
					addTrees(trees, point, nextPoint, road.Width / 2 + 6, rng)
				end
			end
		end
	end
end

local function buildBridges(map: Folder)
	local bridges = folder(map, "Bridges")
	local river = MapData.River
	local railColor = Color3.fromRGB(220, 220, 225)
	for _, bridge in MapData.Bridges do
		local f = folder(bridges, bridge.Name)
		local length = river.MaxX - river.MinX + 20
		local centerX = (river.MinX + river.MaxX) / 2
		for _, side in { -1, 1 } do
			local rail = Geometry.Part(
				f,
				"Railing",
				Vector3.new(length, 3, 1),
				CFrame.new(centerX, ROAD_TOP + 1.5, bridge.Z + side * (bridge.Width / 2 + 0.5)),
				railColor,
				Enum.Material.Metal
			)
			Geometry.Obstacle(rail)
		end
		Geometry.Box(
			f,
			"Underside",
			Vector3.new(river.MinX, -2, bridge.Z - bridge.Width / 2),
			Vector3.new(river.MaxX, ROAD_TOP - 1, bridge.Z + bridge.Width / 2),
			Color3.fromRGB(120, 120, 125),
			Enum.Material.Concrete
		)
		Geometry.Cylinder(f, "Pier", Vector3.new(centerX, -15, bridge.Z), 5, 13, Color3.fromRGB(120, 120, 125), Enum.Material.Concrete)
	end
end

local function buildBlocks(map: Folder, rng: Random)
	local buildings = folder(map, "Buildings")
	for _, block in MapData.Blocks do
		Landmarks.FillBlock(buildings, block, rng)
	end
end

local function buildHillsAndRamps(map: Folder)
	for _, hill in MapData.Hills do
		Geometry.TerrainHill(hill.Center, hill.FlatRadius, hill.Radius, hill.Height, hill.Material)
	end
	local ramps = folder(map, "Ramps")
	for _, ramp in MapData.Ramps do
		Geometry.Ramp(ramps, ramp.Name, ramp.Start, ramp.Yaw, ramp.Length, ramp.Angle, ramp.Width)
	end
end

local function buildLandmarks(map: Folder, rng: Random)
	local landmarks = folder(map, "Landmarks")
	local data = MapData.Landmarks
	Landmarks.Fountain(landmarks, data.Fountain)
	Landmarks.NorrePort(landmarks, data.NorrePort)
	Landmarks.Castle(landmarks, data.Castle)
	Landmarks.LookoutTower(landmarks, data.LookoutTower)
	Landmarks.Hotel(landmarks, data.Hotel)
	Landmarks.Pier(landmarks, data.Pier.Start, data.Pier.Length, data.Pier.Width)
	Landmarks.BeachHuts(landmarks, data.BeachHuts.FromX, data.BeachHuts.ToX, data.BeachHuts.Z, data.BeachHuts.SkipNearX, rng)
	Landmarks.Harbor(landmarks, rng)
end

local function buildSpawn(map: Folder)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlayerSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(-200, 0.5, 225)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.Parent = map
end

function MapService.Init()
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 140, 150)

	local started = os.clock()
	local rng = Random.new(MAP_SEED)
	local map = folder(workspace, "Halmstad")
	buildGroundAndWater(map)
	buildZones(map)
	buildRoads(map, rng)
	buildBridges(map)
	buildBlocks(map, rng)
	buildLandmarks(map, rng)
	buildHillsAndRamps(map)
	buildSpawn(map)

	VehicleService.SetSpawnProvider(MapData.PlayerSpawn)
	print(("[MapService] Halmstad byggt på %.2f s"):format(os.clock() - started))
end

function MapService.Start() end

return MapService
