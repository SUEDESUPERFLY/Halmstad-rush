--!strict
-- Rekvisita som ger staden liv: palmer, tallar, gatlyktor, trafikljus, flaggor, skyltar,
-- parasoller, badvakttorn, surfbrädor, vindkraftverk, pariserhjul, fyr och båt.
-- Snurrande saker (vindkraftverk, pariserhjul) får taggen "Spinner" och roteras av klienten.

local CollectionService = game:GetService("CollectionService")

local Geometry = require(script.Parent.Geometry)

local Props = {}

local function yawCFrame(position: Vector3, yawDeg: number): CFrame
	return CFrame.new(position) * CFrame.Angles(0, math.rad(yawDeg), 0)
end

local function model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

function Props.Palm(parent: Instance, base: Vector3, rng: Random)
	local m = model(parent, "Palm")
	local height = rng:NextNumber(22, 30)
	local leanAngle = rng:NextNumber(0, math.pi * 2)
	local lean = Vector3.new(math.cos(leanAngle), 0, math.sin(leanAngle)) * rng:NextNumber(0.8, 1.6)
	local trunkColor = Color3.fromRGB(150, 115, 80)
	local points = {
		base - Vector3.new(0, 1, 0),
		base + lean * 0.6 + Vector3.new(0, height / 3, 0),
		base + lean * 2 + Vector3.new(0, height * 2 / 3, 0),
		base + lean * 4 + Vector3.new(0, height, 0),
	}
	local radii = { 1.1, 0.95, 0.8 }
	for i = 1, 3 do
		local segment = Geometry.Between(m, "Trunk", points[i], points[i + 1], radii[i] * 2, trunkColor, Enum.Material.Wood, true)
		if i == 1 then
			Geometry.Obstacle(segment)
		end
	end
	local top = points[4]
	local frondColor = Color3.fromRGB(60, 150, 70)
	local count = 7
	for i = 1, count do
		local yaw = (i / count) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local droop = math.rad(rng:NextNumber(20, 35))
		local frond = Geometry.Part(
			m,
			"Frond",
			Vector3.new(3, 0.3, 12),
			CFrame.new(top) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(-droop, 0, 0) * CFrame.new(0, 0, -6),
			frondColor,
			Enum.Material.Grass
		)
		frond.CanCollide = false
	end
	Geometry.Ball(m, "Coconuts", top - Vector3.new(0, 1.2, 0), 1.3, Color3.fromRGB(110, 80, 40)).CanCollide = false
end

function Props.Tree(parent: Instance, base: Vector3, rng: Random)
	local trunk = Geometry.Cylinder(parent, "TreeTrunk", base - Vector3.new(0, 1, 0), 1.2, 11, Color3.fromRGB(110, 80, 55), Enum.Material.Wood)
	Geometry.Obstacle(trunk)
	Geometry.Ball(parent, "TreeCrown", base + Vector3.new(0, 13, 0), rng:NextNumber(5, 7), Color3.fromRGB(70, 140, 70))
end

function Props.Pine(parent: Instance, base: Vector3, rng: Random)
	local height = rng:NextNumber(14, 20)
	local trunk = Geometry.Cylinder(parent, "PineTrunk", base - Vector3.new(0, 2, 0), 1, height * 0.5 + 2, Color3.fromRGB(100, 70, 50), Enum.Material.Wood)
	Geometry.Obstacle(trunk)
	local green = Color3.fromRGB(40, 100, 60)
	Geometry.Ball(parent, "PineLow", base + Vector3.new(0, height * 0.5, 0), height * 0.32, green)
	Geometry.Ball(parent, "PineHigh", base + Vector3.new(0, height * 0.85, 0), height * 0.22, green)
end

-- Gatlykta. `towardRoad` är riktningen från stolpen ut över gatan.
function Props.StreetLamp(parent: Instance, base: Vector3, towardRoad: Vector3)
	local m = model(parent, "StreetLamp")
	local grey = Color3.fromRGB(60, 62, 70)
	Geometry.Obstacle(Geometry.Cylinder(m, "Pole", base, 0.35, 16, grey, Enum.Material.Metal))
	local top = base + Vector3.new(0, 16, 0)
	local tip = top + towardRoad * 5
	Geometry.Between(m, "Arm", top, tip, 0.4, grey, Enum.Material.Metal)
	Geometry.Decor(Geometry.Part(m, "Light", Vector3.new(1.6, 0.5, 2.6), CFrame.lookAt(tip - Vector3.new(0, 0.4, 0), tip + towardRoad - Vector3.new(0, 0.4, 0)), Color3.fromRGB(255, 225, 170), Enum.Material.Neon))
end

-- Trafikljus på stolpe med arm ut över vägen. Lampan vänds mot `facing`.
function Props.TrafficLight(parent: Instance, base: Vector3, overRoad: Vector3, facing: Vector3)
	local m = model(parent, "TrafficLight")
	local dark = Color3.fromRGB(40, 40, 45)
	Geometry.Obstacle(Geometry.Cylinder(m, "Pole", base, 0.45, 15, dark, Enum.Material.Metal))
	local top = base + Vector3.new(0, 14.5, 0)
	local tip = top + overRoad * 9
	Geometry.Between(m, "Arm", top, tip, 0.5, dark, Enum.Material.Metal)
	local box = CFrame.lookAt(tip - Vector3.new(0, 2.6, 0), tip - Vector3.new(0, 2.6, 0) + facing)
	Geometry.Part(m, "Box", Vector3.new(1.8, 5, 1.2), box, dark)
	local colors = {
		{ Color3.fromRGB(90, 20, 20), 1.6 },
		{ Color3.fromRGB(90, 70, 20), 0 },
		{ Color3.fromRGB(60, 255, 120), -1.6 },
	}
	for _, info in colors do
		Geometry.Decor(Geometry.Part(m, "Lamp", Vector3.new(1.1, 1.1, 0.3), box * CFrame.new(0, info[2], -0.65), info[1], Enum.Material.Neon))
	end
end

-- Gatuskylt med två blad, ett per gata. Varje blad är parallellt med sin gata.
function Props.StreetNameSign(parent: Instance, base: Vector3, roads: { { Name: string, Direction: Vector3 } })
	local m = model(parent, "StreetSign")
	local green = Color3.fromRGB(20, 110, 60)
	Geometry.Obstacle(Geometry.Cylinder(m, "Pole", base, 0.25, 11, Color3.fromRGB(150, 150, 155), Enum.Material.Metal))
	for i, road in roads do
		if i > 2 then
			break
		end
		local position = base + Vector3.new(0, 11 - i * 1.8, 0)
		local blade = Geometry.Part(m, "Blade", Vector3.new(10, 1.5, 0.25), CFrame.fromMatrix(position, road.Direction, Vector3.yAxis), green)
		Geometry.Label(blade, Enum.NormalId.Front, road.Name, nil, green)
		Geometry.Label(blade, Enum.NormalId.Back, road.Name, nil, green)
	end
end

function Props.SwedishFlag(parent: Instance, base: Vector3, height: number)
	local m = model(parent, "Flag")
	Geometry.Obstacle(Geometry.Cylinder(m, "Pole", base, 0.3, height, Color3.new(1, 1, 1), Enum.Material.Metal))
	local width, flagHeight = 8, 5
	local center = base + Vector3.new(width / 2 + 0.3, height - flagHeight / 2 - 0.5, 0)
	local blue = Color3.fromRGB(0, 90, 170)
	local yellow = Color3.fromRGB(255, 205, 0)
	Geometry.Part(m, "Field", Vector3.new(width, flagHeight, 0.2), CFrame.new(center), blue)
	-- Korset: proportioner 5:2:9 på bredden, 4:2:4 på höjden
	local unitX = width / 16
	local crossX = center.X - width / 2 + unitX * 6
	Geometry.Part(m, "CrossV", Vector3.new(unitX * 2, flagHeight, 0.25), CFrame.new(crossX, center.Y, center.Z), yellow)
	Geometry.Part(m, "CrossH", Vector3.new(width, flagHeight / 5, 0.25), CFrame.new(center), yellow)
	for _, part in m:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "Pole" then
			Geometry.Decor(part)
		end
	end
end

-- Skyltar. Framsidan vänds åt `yaw` (0 = norr).
function Props.Sign(parent: Instance, kind: string, text: string, subText: string?, position: Vector3, yaw: number, width: number, color: Color3, textColor: Color3?)
	local m = model(parent, "Sign_" .. text)
	local frame = yawCFrame(position, yaw)
	local metal = Color3.fromRGB(170, 170, 175)
	if kind == "Arch" then
		local height = 22
		for _, side in { -1, 1 } do
			Geometry.Obstacle(Geometry.Part(m, "Post", Vector3.new(2, height, 2), frame * CFrame.new(side * width / 2, height / 2, 0), metal, Enum.Material.Metal))
		end
		local board = Geometry.Part(m, "Board", Vector3.new(width + 2, 7, 1), frame * CFrame.new(0, height + 2.5, 0), color)
		Geometry.Label(board, Enum.NormalId.Front, text, subText, color, textColor)
		Geometry.Label(board, Enum.NormalId.Back, text, subText, color, textColor)
		return
	end

	local boardHeight, bottom = 4, 1
	if kind == "Billboard" then
		boardHeight, bottom = width * 0.4, 10
	elseif kind == "Highway" then
		boardHeight, bottom = width * 0.4, 8
	elseif kind == "Plaque" then
		boardHeight, bottom = 4, 1.5
	end
	for _, side in { -1, 1 } do
		Geometry.Obstacle(Geometry.Part(m, "Post", Vector3.new(1, bottom + boardHeight / 2, 1), frame * CFrame.new(side * width * 0.3, (bottom + boardHeight / 2) / 2, 0.8), metal, Enum.Material.Metal))
	end
	local board = Geometry.Part(m, "Board", Vector3.new(width, boardHeight, 1), frame * CFrame.new(0, bottom + boardHeight / 2, 0), color)
	Geometry.Label(board, Enum.NormalId.Front, text, subText, color, textColor)
end

function Props.Umbrella(parent: Instance, base: Vector3, color: Color3)
	local m = model(parent, "Umbrella")
	Geometry.Cylinder(m, "Pole", base, 0.2, 7, Color3.new(1, 1, 1))
	Geometry.Cylinder(m, "Canopy", base + Vector3.new(0, 7, 0), 4.5, 0.5, color, Enum.Material.Fabric)
	Geometry.Part(m, "Towel", Vector3.new(3, 0.1, 6), CFrame.new(base + Vector3.new(3, 0.1, 1)), color, Enum.Material.Fabric).CanCollide = false
end

function Props.LifeguardTower(parent: Instance, base: Vector3, yaw: number)
	local m = model(parent, "LifeguardTower")
	local frame = yawCFrame(base, yaw)
	local wood = Color3.fromRGB(230, 225, 210)
	for _, dx in { -2.5, 2.5 } do
		for _, dz in { -2.5, 2.5 } do
			Geometry.Obstacle(Geometry.Part(m, "Leg", Vector3.new(0.6, 8, 0.6), frame * CFrame.new(dx, 4, dz), wood, Enum.Material.Wood))
		end
	end
	local cabin = Geometry.Part(m, "Cabin", Vector3.new(7, 4.5, 7), frame * CFrame.new(0, 10.25, 0), Color3.fromRGB(240, 70, 60), Enum.Material.WoodPlanks)
	Geometry.Label(cabin, Enum.NormalId.Front, "LIVRÄDDNING", nil, Color3.fromRGB(240, 70, 60))
	Geometry.Part(m, "Roof", Vector3.new(8.5, 0.6, 8.5), frame * CFrame.new(0, 12.8, 0), Color3.new(1, 1, 1))
	Geometry.Between(m, "Ramp", (frame * CFrame.new(0, 8, 3.5)).Position, (frame * CFrame.new(0, 0, 11)).Position, 2.4, wood, Enum.Material.WoodPlanks)
end

function Props.Surfboard(parent: Instance, base: Vector3, yaw: number, color: Color3)
	local board = Geometry.Part(parent, "Surfboard", Vector3.new(2.2, 7, 0.4), yawCFrame(base + Vector3.new(0, 2.8, 0), yaw) * CFrame.Angles(math.rad(-8), 0, 0), color)
	Geometry.Obstacle(board)
end

function Props.VolleyballNet(parent: Instance, center: Vector3)
	local m = model(parent, "Volleyball")
	for _, dx in { -9, 9 } do
		Geometry.Obstacle(Geometry.Cylinder(m, "Pole", center + Vector3.new(dx, 0, 0), 0.3, 8, Color3.new(1, 1, 1)))
	end
	local net = Geometry.Part(m, "Net", Vector3.new(18, 3, 0.1), CFrame.new(center + Vector3.new(0, 6.5, 0)), Color3.new(1, 1, 1))
	net.Transparency = 0.5
	Geometry.Decor(net)
end

function Props.WindTurbine(parent: Instance, base: Vector3, yaw: number)
	local m = model(parent, "WindTurbine")
	local white = Color3.fromRGB(240, 240, 245)
	local height = 90
	Geometry.Obstacle(Geometry.Cylinder(m, "Tower", base - Vector3.new(0, 1, 0), 2.5, height + 1, white, Enum.Material.Concrete))
	local hubFrame = yawCFrame(base + Vector3.new(0, height + 2, 0), yaw)
	Geometry.Part(m, "Nacelle", Vector3.new(4, 4, 11), hubFrame * CFrame.new(0, 0, 3), white)

	local rotor = model(m, "Rotor")
	local rotorFrame = hubFrame * CFrame.new(0, 0, -3)
	Geometry.Part(rotor, "Hub", Vector3.new(3, 3, 3), rotorFrame, white)
	for i = 0, 2 do
		Geometry.Part(rotor, "Blade", Vector3.new(2, 34, 0.5), rotorFrame * CFrame.Angles(0, 0, i * math.pi * 2 / 3) * CFrame.new(0, 18, 0), white)
	end
	rotor.WorldPivot = rotorFrame
	rotor:SetAttribute("SpinSpeed", 0.8)
	CollectionService:AddTag(rotor, "Spinner")
end

-- Pariserhjul i XY-planet (axeln längs Z). Hjulet snurrar på klienten.
function Props.FerrisWheel(parent: Instance, center: Vector3, radius: number)
	local m = model(parent, "FerrisWheel")
	local steel = Color3.fromRGB(230, 230, 235)
	for _, dz in { -5, 5 } do
		for _, dx in { -1, 1 } do
			local foot = center + Vector3.new(dx * radius * 0.55, -center.Y + 0.5, dz)
			Geometry.Obstacle(Geometry.Between(m, "Leg", foot, center + Vector3.new(0, 0, dz), 1.6, steel, Enum.Material.Metal))
		end
	end

	local wheel = model(m, "Wheel")
	local frame = CFrame.new(center)
	local segments = 20
	local neon = { Color3.fromRGB(255, 80, 170), Color3.fromRGB(60, 220, 230) }
	for i = 0, segments - 1 do
		local a0 = i / segments * math.pi * 2
		local a1 = (i + 1) / segments * math.pi * 2
		local p0 = (frame * CFrame.new(math.cos(a0) * radius, math.sin(a0) * radius, 0)).Position
		local p1 = (frame * CFrame.new(math.cos(a1) * radius, math.sin(a1) * radius, 0)).Position
		local rim = Geometry.Between(wheel, "Rim", p0, p1, 1, neon[i % 2 + 1], Enum.Material.Neon)
		Geometry.Decor(rim)
	end
	for i = 0, 3 do
		local a = i / 4 * math.pi
		local offset = Vector3.new(math.cos(a), math.sin(a), 0) * radius
		Geometry.Decor(Geometry.Between(wheel, "Spoke", center - offset, center + offset, 0.6, steel, Enum.Material.Metal))
	end
	local gondolaColors = { Color3.fromRGB(255, 200, 40), Color3.fromRGB(240, 70, 70), Color3.fromRGB(70, 160, 240) }
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local p = center + Vector3.new(math.cos(a), math.sin(a), 0) * radius
		Geometry.Decor(Geometry.Part(wheel, "Gondola", Vector3.new(4, 4, 4), CFrame.new(p), gondolaColors[i % 3 + 1]))
	end
	Geometry.Decor(Geometry.Part(wheel, "Hub", Vector3.new(3, 3, 12), frame, steel, Enum.Material.Metal))
	wheel.WorldPivot = frame
	wheel:SetAttribute("SpinSpeed", 0.15)
	CollectionService:AddTag(wheel, "Spinner")
end

function Props.Lighthouse(parent: Instance, base: Vector3)
	local m = model(parent, "Fyren")
	local colors = { Color3.fromRGB(220, 40, 40), Color3.new(1, 1, 1) }
	for i = 0, 5 do
		local radius = 5 - i * 0.3
		Geometry.Obstacle(Geometry.Cylinder(m, "Section", base + Vector3.new(0, i * 6, 0), radius, 6, colors[i % 2 + 1], Enum.Material.Concrete))
	end
	Geometry.Cylinder(m, "Gallery", base + Vector3.new(0, 36, 0), 4.5, 1, Color3.fromRGB(40, 40, 45), Enum.Material.Metal)
	Geometry.Ball(m, "Lantern", base + Vector3.new(0, 39, 0), 2.8, Color3.fromRGB(255, 230, 120)).Material = Enum.Material.Neon
	Geometry.Cylinder(m, "Cap", base + Vector3.new(0, 41.5, 0), 3, 1.5, Color3.fromRGB(220, 40, 40))
end

function Props.Ship(parent: Instance, center: Vector3, length: number, width: number, name: string)
	local m = model(parent, "Ship")
	local hull = Geometry.Part(m, "Hull", Vector3.new(length, 14, width), CFrame.new(center + Vector3.new(0, 1, 0)), Color3.fromRGB(30, 60, 120), Enum.Material.Metal)
	Geometry.Label(hull, Enum.NormalId.Front, name, nil, Color3.fromRGB(30, 60, 120))
	Geometry.Part(m, "Stripe", Vector3.new(length + 0.2, 1.5, width + 0.2), CFrame.new(center + Vector3.new(0, 6, 0)), Color3.new(1, 1, 1))
	Geometry.Part(m, "Deck", Vector3.new(length - 4, 0.5, width - 2), CFrame.new(center + Vector3.new(0, 8.2, 0)), Color3.fromRGB(150, 110, 70), Enum.Material.WoodPlanks)
	local bridge = center + Vector3.new(length * 0.28, 8, 0)
	Geometry.Part(m, "Superstructure", Vector3.new(40, 14, width - 6), CFrame.new(bridge + Vector3.new(0, 7, 0)), Color3.new(1, 1, 1))
	Geometry.Part(m, "Windows", Vector3.new(40.4, 2.5, width - 5.6), CFrame.new(bridge + Vector3.new(0, 11, 0)), Color3.fromRGB(40, 60, 80), Enum.Material.Glass)
	Geometry.Cylinder(m, "Funnel", bridge + Vector3.new(6, 14, 0), 3.5, 10, Color3.fromRGB(250, 200, 40))
	Geometry.Cylinder(m, "FunnelTop", bridge + Vector3.new(6, 24, 0), 3.6, 2, Color3.fromRGB(30, 30, 30))
end

function Props.Bench(parent: Instance, base: Vector3, yaw: number)
	local bench = Geometry.Part(parent, "Bench", Vector3.new(6, 1.6, 2), yawCFrame(base + Vector3.new(0, 0.8, 0), yaw), Color3.fromRGB(140, 100, 60), Enum.Material.WoodPlanks)
	Geometry.Obstacle(bench)
end

return Props
