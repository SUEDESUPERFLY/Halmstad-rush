--!strict
-- Bygger Halmstad när servern startar: terräng och hus från stadskartan (CityBuilder),
-- landmärken, skyltar, stränder och områdena utanför kartan.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local CityBuilder = require(script.Parent.Parent.Map.CityBuilder)
local Geometry = require(script.Parent.Parent.Map.Geometry)
local Landmarks = require(script.Parent.Parent.Map.Landmarks)
local Props = require(script.Parent.Parent.Map.Props)
local RespawnService = require(script.Parent.RespawnService)
local VehicleService = require(script.Parent.VehicleService)

local MapService = {}

local MAP_SEED = 1307

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- Svensk sommareftermiddag: hög sol, klar luft, lite dis mot havet.
local function setupLighting()
	Lighting.ClockTime = 15.5
	Lighting.GeographicLatitude = 56.7 -- Halmstad
	Lighting.Brightness = 2.6
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.OutdoorAmbient = Color3.fromRGB(130, 135, 145)
	Lighting.Ambient = Color3.fromRGB(60, 62, 70)

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(200, 215, 230)
	atmosphere.Decay = Color3.fromRGB(110, 130, 160)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 1.2
	atmosphere.Parent = Lighting

	local correction = Instance.new("ColorCorrectionEffect")
	correction.Saturation = 0.08
	correction.Contrast = 0.05
	correction.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.3
	bloom.Size = 20
	bloom.Threshold = 1.8
	bloom.Parent = Lighting

	local clouds = Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.6
	clouds.Parent = workspace.Terrain
end

local function buildLandmarks(map: Folder, rng: Random)
	local landmarks = folder(map, "Landmarks")
	local data = MapData.Landmarks
	Landmarks.Fountain(landmarks, Vector2.new(0, 0))
	Landmarks.Church(landmarks, data.Church.Center, data.Church.Length, data.Church.Width)
	Landmarks.Castle(landmarks, data.Castle.Center, data.Castle.Size)
	Landmarks.NorrePort(landmarks, data.NorrePort.Position, data.NorrePort.Yaw)
	Landmarks.LookoutTower(landmarks, data.LookoutTower)
	Landmarks.Hallandsgarden(landmarks, data.Hallandsgarden, rng)
	Landmarks.Library(landmarks, data.Library.Center, data.Library.Yaw)
	Landmarks.Hotel(landmarks, data.Hotel)
	Landmarks.Pier(landmarks, data.Pier.Start, data.Pier.Length, data.Pier.Width, "Badbryggan")

	-- Piren vid Nissans mynning med fyr, och en båt ute på redden
	local breakwater = data.Breakwater
	Geometry.Box(
		landmarks,
		"Pir",
		Vector3.new(breakwater.Start.X - breakwater.Width / 2, -16, breakwater.Start.Y),
		Vector3.new(breakwater.Start.X + breakwater.Width / 2, 1, breakwater.Start.Y + breakwater.Length),
		Color3.fromRGB(140, 140, 140),
		Enum.Material.Concrete
	)
	Props.Lighthouse(landmarks, Vector3.new(breakwater.Start.X, 1, breakwater.Start.Y + breakwater.Length - 8))
	local ship = data.Ship
	Props.Ship(landmarks, Vector3.new(ship.Center.X, -4, ship.Center.Y), ship.Length, ship.Width, ship.Name)

	for _, position in data.WindTurbines do
		Props.WindTurbine(landmarks, Vector3.new(position.X, 0, position.Y), 0)
	end

	for _, beach in MapData.Beaches do
		Landmarks.Beach(landmarks, beach :: any, rng)
	end
end

local function buildSigns(map: Folder)
	local signs = folder(map, "Signs")
	for _, sign in MapData.Signs do
		local p = sign.Position
		local position = Vector3.new(p.X, MapData.GroundHeightAt(p.X, p.Z), p.Z)
		Props.Sign(signs, sign.Kind, sign.Text, sign.SubText, position, sign.Yaw, sign.Width, sign.Color, sign.TextColor)
	end
end

-- Lövträd längs landsvägen mot Tylösand
local function buildRoadsideTrees(map: Folder, rng: Random)
	local trees = folder(map, "Trees")
	for _, road in MapData.ExtraRoads do
		for i = 1, #road.Points - 1 do
			local a, b = road.Points[i], road.Points[i + 1]
			local direction = (b - a).Unit
			local side = Vector2.new(-direction.Y, direction.X)
			for distance = 30, (b - a).Magnitude - 30, 50 do
				for _, sign in { -1, 1 } do
					if rng:NextNumber() < 0.7 then
						local p = a + direction * distance + side * sign * (road.Width / 2 + rng:NextNumber(8, 18))
						Props.Tree(trees, Vector3.new(p.X, 0, p.Y), rng)
					end
				end
			end
		end
	end
	-- Tallskog på Galgberget
	local hill = MapData.Hills[1]
	for _ = 1, 70 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(hill.FlatRadius + 20, hill.Radius * 0.8)
		local x = hill.Center.X + math.cos(angle) * r
		local z = hill.Center.Y + math.sin(angle) * r
		if CityBuilder.CodeAt(x, z) == "P" or CityBuilder.CodeAt(x, z) == nil then
			Props.Pine(trees, Vector3.new(x, MapData.GroundHeightAt(x, z), z), rng)
		end
	end
end

local function buildSpawn(map: Folder)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlayerSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(40, 0.5, 0)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.Parent = map
end

local function registerRespawnPoints()
	RespawnService.AddPoints(CityBuilder.RoadPoints())
	-- Punkter längs vägarna utanför stadskartan
	local points = {}
	for _, road in MapData.ExtraRoads do
		for i = 1, #road.Points - 1 do
			local a, b = road.Points[i], road.Points[i + 1]
			local direction = (b - a).Unit
			local yaw = math.deg(math.atan2(-direction.X, -direction.Y))
			for distance = 0, (b - a).Magnitude, 50 do
				local p = a + direction * distance
				table.insert(points, { Position = Vector3.new(p.X, 0, p.Y), Yaw = yaw })
			end
		end
	end
	RespawnService.AddPoints(points)
end

function MapService.Init()
	local started = os.clock()
	setupLighting()

	local rng = Random.new(MAP_SEED)
	local map = folder(workspace, "Halmstad")
	CityBuilder.BuildTerrain()
	local terrainTime = os.clock() - started
	local buildingCount = CityBuilder.BuildBuildings(map)
	buildLandmarks(map, rng)
	buildSigns(map)
	buildRoadsideTrees(map, rng)
	buildSpawn(map)
	registerRespawnPoints()

	VehicleService.SetSpawnProvider(MapData.PlayerSpawn)
	print(
		("[MapService] Halmstad byggt på %.1f s (terräng %.1f s, %d hus)"):format(os.clock() - started, terrainTime, buildingCount)
	)
end

function MapService.Start() end

return MapService
