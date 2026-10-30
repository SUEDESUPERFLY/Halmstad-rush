--!strict
-- Igenkännbara platser i block-out-form: slottet, Norre port, fontänen på Stora torg,
-- utsiktstornet på Galgberget, strandhotellet, badbryggan, hamnen och strandbodar.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local Geometry = require(script.Parent.Geometry)

local Landmarks = {}

local STONE = Color3.fromRGB(205, 170, 140)
local COPPER = Color3.fromRGB(95, 150, 125)
local WATER = Color3.fromRGB(70, 140, 200)
local WOOD = Color3.fromRGB(150, 110, 70)

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

function Landmarks.Fountain(parent: Instance, at: Vector2)
	local f = folder(parent, "Fontanen")
	local base = Vector3.new(at.X, 0.08, at.Y)
	Geometry.Obstacle(Geometry.Cylinder(f, "Basin", base, 14, 2, Color3.fromRGB(170, 170, 175), Enum.Material.Concrete))
	Geometry.Decor(Geometry.Cylinder(f, "Water", base + Vector3.new(0, 2, 0), 12.5, 0.2, WATER, Enum.Material.Glass))
	Geometry.Obstacle(Geometry.Cylinder(f, "Column", base, 2.5, 12, Color3.fromRGB(190, 190, 195), Enum.Material.Marble))
	Geometry.Ball(f, "Statue", base + Vector3.new(0, 14, 0), 3, COPPER)
end

function Landmarks.NorrePort(parent: Instance, at: Vector2)
	local f = folder(parent, "NorrePort")
	local brick = Color3.fromRGB(170, 90, 70)
	for _, side in { -1, 1 } do
		local pillar = Geometry.Part(
			f,
			"Pillar",
			Vector3.new(8, 24, 12),
			CFrame.new(at.X + side * 19, 12, at.Y),
			brick,
			Enum.Material.Brick
		)
		Geometry.Obstacle(pillar)
	end
	Geometry.Part(f, "Arch", Vector3.new(46, 8, 12), CFrame.new(at.X, 28, at.Y), brick, Enum.Material.Brick)
	Geometry.Part(f, "Roof", Vector3.new(48, 3, 14), CFrame.new(at.X, 33.5, at.Y), Color3.fromRGB(60, 60, 65))
end

function Landmarks.Castle(parent: Instance, at: Vector2)
	local f = folder(parent, "Slottet")
	local width, depth, height = 120, 140, 30
	local body = Geometry.Part(
		f,
		"Body",
		Vector3.new(width - 20, height, depth - 20),
		CFrame.new(at.X, height / 2, at.Y),
		STONE,
		Enum.Material.Brick
	)
	Geometry.Obstacle(body)
	Geometry.Part(f, "Roof", Vector3.new(width - 16, 4, depth - 16), CFrame.new(at.X, height + 2, at.Y), COPPER)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local base = Vector3.new(at.X + sx * (width / 2 - 12), 0, at.Y + sz * (depth / 2 - 12))
			Geometry.Obstacle(Geometry.Cylinder(f, "Tower", base, 12, 44, STONE, Enum.Material.Brick))
			Geometry.Ball(f, "TowerRoof", base + Vector3.new(0, 46, 0), 11, COPPER)
		end
	end
end

function Landmarks.LookoutTower(parent: Instance, base: Vector3)
	local f = folder(parent, "Utsiktstornet")
	local tower = Geometry.Part(
		f,
		"Tower",
		Vector3.new(14, 44, 14),
		CFrame.new(base + Vector3.new(0, 19, 0)),
		Color3.fromRGB(200, 195, 185),
		Enum.Material.Concrete
	)
	Geometry.Obstacle(tower)
	Geometry.Part(f, "Deck", Vector3.new(22, 2, 22), CFrame.new(base + Vector3.new(0, 42, 0)), WOOD, Enum.Material.WoodPlanks)
	Geometry.Part(f, "Flag", Vector3.new(0.5, 10, 0.5), CFrame.new(base + Vector3.new(0, 48, 0)), Color3.new(1, 1, 1))
end

function Landmarks.Hotel(parent: Instance, at: Vector2)
	local f = folder(parent, "Strandhotellet")
	local body = Geometry.Part(
		f,
		"Body",
		Vector3.new(160, 36, 60),
		CFrame.new(at.X, 18, at.Y),
		Color3.fromRGB(245, 245, 240),
		Enum.Material.Concrete
	)
	Geometry.Obstacle(body)
	Geometry.Part(f, "Roof", Vector3.new(164, 2, 64), CFrame.new(at.X, 37, at.Y), Color3.fromRGB(60, 110, 160))
	Geometry.Part(f, "Sign", Vector3.new(60, 6, 1), CFrame.new(at.X, 30, at.Y + 30.6), Color3.fromRGB(60, 110, 160), Enum.Material.Neon)
end

function Landmarks.Pier(parent: Instance, start: Vector2, length: number, width: number)
	local f = folder(parent, "Badbryggan")
	Geometry.Box(
		f,
		"Deck",
		Vector3.new(start.X - width / 2, -0.5, start.Y),
		Vector3.new(start.X + width / 2, 0.5, start.Y + length),
		WOOD,
		Enum.Material.WoodPlanks
	)
	for z = start.Y + 30, start.Y + length, 30 do
		for _, side in { -1, 1 } do
			Geometry.Cylinder(f, "Post", Vector3.new(start.X + side * (width / 2 - 1), -15, z), 1, 15, WOOD, Enum.Material.Wood)
		end
	end
end

function Landmarks.BeachHuts(parent: Instance, fromX: number, toX: number, z: number, skipNearX: number, rng: Random)
	local f = folder(parent, "Strandbodar")
	local colors = {
		Color3.fromRGB(240, 90, 90),
		Color3.fromRGB(90, 170, 240),
		Color3.fromRGB(250, 210, 60),
		Color3.fromRGB(120, 210, 120),
		Color3.new(1, 1, 1),
	}
	for x = fromX, toX, 50 do
		if math.abs(x - skipNearX) > 30 then
			local hut = Geometry.Part(
				f,
				"Hut",
				Vector3.new(7, 7, 7),
				CFrame.new(x, 3.5, z),
				colors[rng:NextInteger(1, #colors)],
				Enum.Material.WoodPlanks
			)
			Geometry.Obstacle(hut)
		end
	end
end

function Landmarks.Harbor(parent: Instance, rng: Random)
	local data = MapData.Landmarks.Harbor
	local f = folder(parent, "Hamnen")
	local colors = {
		Color3.fromRGB(200, 60, 50),
		Color3.fromRGB(40, 100, 180),
		Color3.fromRGB(230, 160, 30),
		Color3.fromRGB(60, 150, 90),
		Color3.fromRGB(130, 130, 140),
	}

	-- Containerstaplar i rader med gränder emellan
	for x = data.Min.X, data.Max.X, 30 do
		for z = data.Min.Y, data.Max.Y, 28 do
			if rng:NextNumber() > 0.25 then
				local stack = rng:NextInteger(1, 3)
				for level = 0, stack - 1 do
					local container = Geometry.Part(
						f,
						"Container",
						Vector3.new(20, 8.5, 8),
						CFrame.new(x, 4.25 + level * 8.5, z),
						colors[rng:NextInteger(1, #colors)],
						Enum.Material.CorrodedMetal
					)
					Geometry.Obstacle(container)
				end
			end
		end
	end

	-- Kranar vid kajkanten
	local craneColor = Color3.fromRGB(240, 180, 30)
	for _, x in data.CraneXs do
		for _, dx in { -10, 10 } do
			for _, dz in { -7, 7 } do
				local leg = Geometry.Part(
					f,
					"CraneLeg",
					Vector3.new(2, 44, 2),
					CFrame.new(x + dx, 22, data.CraneZ + dz),
					craneColor,
					Enum.Material.Metal
				)
				Geometry.Obstacle(leg)
			end
		end
		Geometry.Part(f, "CraneTop", Vector3.new(24, 5, 70), CFrame.new(x, 46, data.CraneZ + 10), craneColor, Enum.Material.Metal)
	end
end

-- Fyller ett kvarter med hus i rutnät. Tomma tomter blir gränder att köra igenom.
function Landmarks.FillBlock(parent: Instance, block: MapData.Block, rng: Random)
	local style = MapData.BuildingStyles[block.Style]
	assert(style, "Okänd husstil: " .. block.Style)
	local minX, maxX = block.Min.X, block.Max.X
	local minZ, maxZ = block.Min.Y, block.Max.Y

	local function nextSize(position: number, limit: number): number
		local size = rng:NextNumber(style.CellMin, style.CellMax)
		if limit - (position + size) < style.CellMin * 0.6 then
			size = limit - position
		end
		return size
	end

	local x = minX
	while maxX - x > 8 do
		local w = nextSize(x, maxX)
		local z = minZ
		while maxZ - z > 8 do
			local d = nextSize(z, maxZ)
			if rng:NextNumber() > style.Gap then
				local height = rng:NextNumber(style.MinHeight, style.MaxHeight)
				local center = Vector3.new(x + w / 2, height / 2, z + d / 2)
				local building = Geometry.Part(
					parent,
					"Building",
					Vector3.new(w - 6, height, d - 6),
					CFrame.new(center),
					style.Colors[rng:NextInteger(1, #style.Colors)],
					Enum.Material.Concrete
				)
				Geometry.Obstacle(building)
				Geometry.Part(
					parent,
					"Roof",
					Vector3.new(w - 5, 1, d - 5),
					CFrame.new(center.X, height + 0.5, center.Z),
					style.RoofColor
				)
			end
			z += d
		end
		x += w
	end
end

return Landmarks
