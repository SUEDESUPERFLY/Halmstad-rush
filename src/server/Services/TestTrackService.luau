--!strict
-- Fas 1: en testplatta med ramper, slalom och pelare för nära-ögat-boost.
-- Ersätts av Halmstad-kartan i fas 2 (men behålls som "TestTrack" för felsökning).

local Lighting = game:GetService("Lighting")
local ServerScriptService = game:GetService("ServerScriptService")

local VehicleService = require(ServerScriptService.Server.Services.VehicleService)

local TestTrackService = {}

local SPAWN_Z = 300
local track: Folder

local function block(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = track
	return part
end

-- Platta markeringar som inte påverkar körning.
local function decal(name: string, size: Vector3, position: Vector3, color: Color3)
	local part = block(name, size, CFrame.new(position), color)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
end

-- Ramp som börjar i marknivå vid `start` och stiger i riktningen `yawDeg`
-- (0 = mot -Z, samma håll som bilarna startar åt).
local function ramp(name: string, start: Vector3, yawDeg: number, length: number, angleDeg: number, width: number): Part
	local thickness = 2
	local yaw = CFrame.Angles(0, math.rad(yawDeg), 0)
	local flatForward = yaw.LookVector
	local angle = math.rad(angleDeg)
	local slope = flatForward * math.cos(angle) + Vector3.yAxis * math.sin(angle)
	local right = yaw.RightVector
	local normal = right:Cross(slope).Unit
	local surfaceMid = start + slope * (length / 2)
	local center = surfaceMid - normal * (thickness / 2)
	local cframe = CFrame.fromMatrix(center, slope:Cross(normal), normal)
	local part = block(name, Vector3.new(width, thickness, length), cframe, Color3.fromRGB(240, 170, 40), Enum.Material.DiamondPlate)
	return part
end

local function rampTop(start: Vector3, yawDeg: number, length: number, angleDeg: number): Vector3
	local flatForward = CFrame.Angles(0, math.rad(yawDeg), 0).LookVector
	local angle = math.rad(angleDeg)
	return start + flatForward * length * math.cos(angle) + Vector3.yAxis * length * math.sin(angle)
end

local function obstacle(part: BasePart)
	part:SetAttribute("Obstacle", true)
end

local function build()
	track = Instance.new("Folder")
	track.Name = "TestTrack"
	track.Parent = workspace

	local asphalt = Color3.fromRGB(70, 72, 78)
	block("Ground", Vector3.new(1600, 4, 1600), CFrame.new(0, -2, 0), asphalt, Enum.Material.Asphalt)

	-- Raksträcka med mittlinje från start mot norr (-Z)
	for z = SPAWN_Z - 40, -700, -30 do
		decal("LaneLine", Vector3.new(1, 0.05, 14), Vector3.new(0, 0.03, z), Color3.new(1, 1, 1))
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, 0.5, SPAWN_Z + 60)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(60, 160, 255)
	spawn.Parent = track

	-- 1) Liten kicker rakt fram
	ramp("Kicker", Vector3.new(0, 0, 150), 0, 18, 15, 20)

	-- 2) Table-top: upp, platå, ner
	local upStart = Vector3.new(0, 0, -50)
	ramp("TableUp", upStart, 0, 40, 14, 26)
	local top = rampTop(upStart, 0, 40, 14)
	local plateauLength = 40
	block(
		"TablePlateau",
		Vector3.new(26, top.Y, plateauLength),
		CFrame.new(top.X, top.Y / 2, top.Z - plateauLength / 2),
		Color3.fromRGB(240, 170, 40),
		Enum.Material.DiamondPlate
	)
	ramp("TableDown", Vector3.new(0, 0, top.Z - plateauLength - 40 * math.cos(math.rad(14))), 180, 40, 14, 26)

	-- 3) Stor hoppramp ut i luften
	ramp("BigJump", Vector3.new(0, 0, -300), 0, 50, 22, 24)

	-- 4) Slalom med pelare (nära-ögat-boost)
	for i = 0, 9 do
		local x = 150 + (i % 2) * 14 - 7
		local pillar = block(
			"Pillar",
			Vector3.new(4, 16, 4),
			CFrame.new(x, 8, 200 - i * 45),
			Color3.fromRGB(230, 230, 235),
			Enum.Material.Concrete
		)
		obstacle(pillar)
	end

	-- 5) Smal "tunnel" av väggar: kör genom för nära-ögat på båda sidor
	for _, x in { -150 - 9, -150 + 9 } do
		local wall = block("TunnelWall", Vector3.new(2, 8, 160), CFrame.new(x, 4, 100), Color3.fromRGB(200, 60, 60), Enum.Material.Brick)
		obstacle(wall)
	end

	-- 6) Driftcirkel
	local radius = 90
	for i = 0, 23 do
		local a = i / 24 * math.pi * 2
		local cone = block(
			"Cone",
			Vector3.new(2, 3, 2),
			CFrame.new(-350 + math.cos(a) * radius, 1.5, -200 + math.sin(a) * radius),
			Color3.fromRGB(255, 120, 20)
		)
		obstacle(cone)
	end

	-- 7) Sidoramper åt öster och väster
	ramp("SideRampEast", Vector3.new(300, 0, -100), -90, 30, 18, 20)
	ramp("SideRampWest", Vector3.new(-300, 0, 100), 90, 30, 18, 20)

	-- Kanter så man ser var plattan slutar
	for _, data in
		{
			{ Vector3.new(1600, 3, 3), Vector3.new(0, 1.5, -800) },
			{ Vector3.new(1600, 3, 3), Vector3.new(0, 1.5, 800) },
			{ Vector3.new(3, 3, 1600), Vector3.new(-800, 1.5, 0) },
			{ Vector3.new(3, 3, 1600), Vector3.new(800, 1.5, 0) },
		}
	do
		block("Edge", data[1], CFrame.new(data[2]), Color3.fromRGB(255, 220, 0))
	end
end

function TestTrackService.Init()
	Lighting.ClockTime = 14
	Lighting.Brightness = 2
	build()

	VehicleService.SetSpawnProvider(function(slot: number): CFrame
		-- Två rader om fem, alla vända mot -Z
		local column = (slot - 1) % 5
		local row = math.floor((slot - 1) / 5)
		return CFrame.new((column - 2) * 14, 4, SPAWN_Z + row * 20)
	end)
end

function TestTrackService.Start() end

return TestTrackService
