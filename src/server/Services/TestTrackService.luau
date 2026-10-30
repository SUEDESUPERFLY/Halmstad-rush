--!strict
-- Testplattan från fas 1, flyttad till MapData.TestTrackOrigin (öster om Halmstad).
-- Nås via snabbresemenyn ("Testbanan"). Bra för att finjustera bilens känsla.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local Geometry = require(script.Parent.Parent.Map.Geometry)
local RespawnService = require(script.Parent.RespawnService)

local TestTrackService = {}

local SPAWN_Z = 300

local function build(): Model
	local track = Instance.new("Model")
	track.Name = "TestTrack"

	local asphalt = Color3.fromRGB(70, 72, 78)
	Geometry.Part(track, "Ground", Vector3.new(1600, 4, 1600), CFrame.new(0, -2, 0), asphalt, Enum.Material.Asphalt)

	for z = SPAWN_Z - 40, -700, -30 do
		Geometry.Decor(Geometry.Part(track, "LaneLine", Vector3.new(1, 0.05, 14), CFrame.new(0, 0.03, z), Color3.new(1, 1, 1)))
	end

	-- 1) Liten kicker
	Geometry.Ramp(track, "Kicker", Vector3.new(0, 0, 150), 0, 18, 15, 20)

	-- 2) Table-top: upp, platå, ner
	local upStart = Vector3.new(0, 0, -50)
	Geometry.Ramp(track, "TableUp", upStart, 0, 40, 14, 26)
	local top = Geometry.RampTop(upStart, 0, 40, 14)
	local plateauLength = 40
	Geometry.Part(
		track,
		"TablePlateau",
		Vector3.new(26, top.Y, plateauLength),
		CFrame.new(top.X, top.Y / 2, top.Z - plateauLength / 2),
		Color3.fromRGB(240, 170, 40),
		Enum.Material.DiamondPlate
	)
	Geometry.Ramp(track, "TableDown", Vector3.new(0, 0, top.Z - plateauLength - 40 * math.cos(math.rad(14))), 180, 40, 14, 26)

	-- 3) Stort hopp
	Geometry.Ramp(track, "BigJump", Vector3.new(0, 0, -300), 0, 50, 22, 24)

	-- 4) Slalom med pelare
	for i = 0, 9 do
		local x = 150 + (i % 2) * 14 - 7
		Geometry.Obstacle(
			Geometry.Part(track, "Pillar", Vector3.new(4, 16, 4), CFrame.new(x, 8, 200 - i * 45), Color3.fromRGB(230, 230, 235), Enum.Material.Concrete)
		)
	end

	-- 5) Smal tunnel
	for _, x in { -159, -141 } do
		Geometry.Obstacle(
			Geometry.Part(track, "TunnelWall", Vector3.new(2, 8, 160), CFrame.new(x, 4, 100), Color3.fromRGB(200, 60, 60), Enum.Material.Brick)
		)
	end

	-- 6) Driftcirkel
	for i = 0, 23 do
		local a = i / 24 * math.pi * 2
		Geometry.Obstacle(
			Geometry.Part(track, "Cone", Vector3.new(2, 3, 2), CFrame.new(-350 + math.cos(a) * 90, 1.5, -200 + math.sin(a) * 90), Color3.fromRGB(255, 120, 20))
		)
	end

	-- 7) Sidoramper
	Geometry.Ramp(track, "SideRampEast", Vector3.new(300, 0, -100), -90, 30, 18, 20)
	Geometry.Ramp(track, "SideRampWest", Vector3.new(-300, 0, 100), 90, 30, 18, 20)

	for _, data in
		{
			{ Vector3.new(1600, 3, 3), Vector3.new(0, 1.5, -800) },
			{ Vector3.new(1600, 3, 3), Vector3.new(0, 1.5, 800) },
			{ Vector3.new(3, 3, 1600), Vector3.new(-800, 1.5, 0) },
			{ Vector3.new(3, 3, 1600), Vector3.new(800, 1.5, 0) },
		}
	do
		Geometry.Part(track, "Edge", data[1], CFrame.new(data[2]), Color3.fromRGB(255, 220, 0))
	end

	track.WorldPivot = CFrame.new()
	track:PivotTo(CFrame.new(MapData.TestTrackOrigin))
	track.Parent = workspace
	return track
end

function TestTrackService.Init()
	build()

	-- Respawnpunkter längs mittlinjen
	local points = {}
	for z = SPAWN_Z, -700, -100 do
		table.insert(points, { Position = MapData.TestTrackOrigin + Vector3.new(0, 0, z), Yaw = 0 })
	end
	RespawnService.AddPoints(points)
end

function TestTrackService.Start() end

return TestTrackService
