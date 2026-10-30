--!strict
-- Block-out av Halmstad. Stiliserat och komprimerat, inte en exakt karta.
-- Koordinater i studs. X = öster, Z = söder (norr är -Z). Marken ligger på Y = 0.
-- Delas av server (bygger kartan, respawn) och klient (platsnamn, snabbresemeny).
--
--   Galgberget (NV)          Norra vägen / Nissansbron
--        \                     |
--   Västra ringen -- Centrum (Stora torg) | Nissan | Östra Förstaden -- Kustvägen
--        |                Slottet         |        Hamnen / industri
--   Tylösandsvägen (landsväg väster ut)   |        Östra stranden (SO)
--   Tylösand (långt i väster)           Havet (Laholmsbukten) i söder

export type Road = {
	Name: string,
	Width: number,
	Points: { Vector2 }, -- (X, Z)
	Trees: boolean?,
	LaneLines: boolean?,
}

export type Zone = {
	Name: string,
	Min: Vector2,
	Max: Vector2,
	Color: Color3,
	Material: Enum.Material,
	Layer: number, -- högre lager ritas ovanpå (undviker flimmer)
}

export type Block = {
	Min: Vector2,
	Max: Vector2,
	Style: string,
}

export type BuildingStyle = {
	CellMin: number,
	CellMax: number,
	MinHeight: number,
	MaxHeight: number,
	Gap: number, -- chans att en tomt lämnas tom (gränder och genvägar)
	Colors: { Color3 },
	RoofColor: Color3,
}

export type Hill = {
	Name: string,
	Center: Vector2,
	FlatRadius: number,
	Radius: number,
	Height: number,
	Material: Enum.Material,
}

export type Ramp = {
	Name: string,
	Start: Vector3, -- rampens nedre kant (mitt)
	Yaw: number, -- grader, 0 = stiger mot norr (-Z), 90 = mot väster, -90 = mot öster, 180 = mot söder
	Length: number,
	Angle: number,
	Width: number,
}

export type Location = {
	Id: string,
	Name: string,
	Position: Vector3,
	Yaw: number,
}

export type Area = {
	Name: string,
	Min: Vector2,
	Max: Vector2,
}

local function v(x: number, z: number): Vector2
	return Vector2.new(x, z)
end

local MapData = {}

MapData.WaterLevel = -3
MapData.SeaStartZ = 900
MapData.River = { MinX = 150, MaxX = 230 } -- Nissan rinner från norr till havet

-- Spelbara områden. Utanför dessa (eller i vattnet) respawnar bilen.
MapData.Bounds = {
	{ Min = v(-3000, -1400), Max = v(2000, 1400) }, -- Halmstad
	{ Min = v(5200, -800), Max = v(6800, 800) }, -- testbanan från fas 1
}

MapData.TestTrackOrigin = Vector3.new(6000, 0, 0)

MapData.Roads = {
	{ Name = "Storgatan", Width = 28, Points = { v(-150, 100), v(-150, -300) } },
	{ Name = "Brogatan", Width = 30, Points = { v(-500, 100), v(1000, 100) } },
	{ Name = "Norra vägen", Width = 30, Points = { v(-500, -300), v(1000, -300) } },
	{ Name = "Västra ringen", Width = 28, Points = { v(-500, -300), v(-500, 650) } },
	{ Name = "Strandgatan", Width = 28, Points = { v(110, -300), v(110, 650) } },
	{ Name = "Slottsgatan", Width = 26, Points = { v(-500, 350), v(110, 350) } },
	{ Name = "Hamngatan", Width = 30, Points = { v(-500, 650), v(1000, 650) } },
	{ Name = "Östra vägen", Width = 28, Points = { v(600, -300), v(600, 650) } },
	{ Name = "Hamnvägen", Width = 28, Points = { v(600, 500), v(1000, 500) } },
	{ Name = "Industrigatan", Width = 28, Points = { v(800, 100), v(800, 650) } },
	{ Name = "Kustvägen", Width = 28, Points = { v(1000, -300), v(1000, 760), v(1950, 760) } },
	{ Name = "Galgbergsvägen", Width = 24, Points = { v(-500, -300), v(-660, -470) } },
	{
		Name = "Tylösandsvägen",
		Width = 32,
		Points = { v(-500, 650), v(-900, 660), v(-1400, 560), v(-1900, 640), v(-2300, 720), v(-2400, 780) },
		Trees = true,
		LaneLines = true,
	},
	{ Name = "Tylösand strandväg", Width = 28, Points = { v(-2950, 780), v(-2100, 780) } },
} :: { Road }

-- Broar över Nissan: vägarna ovan går rakt över ån, här läggs räcken och pelare till.
MapData.Bridges = {
	{ Name = "Nissansbron", Z = -300, Width = 30 },
	{ Name = "Österbro", Z = 100, Width = 30 },
	{ Name = "Hamnbron", Z = 650, Width = 30 },
}

local PAVEMENT = Color3.fromRGB(150, 150, 145)
local SAND = Color3.fromRGB(235, 215, 160)
local QUAY = Color3.fromRGB(125, 125, 130)
local FIELD = Color3.fromRGB(205, 190, 95)

MapData.Zones = {
	{ Name = "Centrum", Min = v(-520, -320), Max = v(150, 640), Color = PAVEMENT, Material = Enum.Material.Concrete, Layer = 1 },
	{ Name = "Östra Förstaden", Min = v(230, -320), Max = v(1020, 640), Color = PAVEMENT, Material = Enum.Material.Concrete, Layer = 1 },
	{ Name = "Hamnkajen", Min = v(230, 640), Max = v(1000, 900), Color = QUAY, Material = Enum.Material.Concrete, Layer = 1 },
	{ Name = "Västra kajen", Min = v(-120, 640), Max = v(150, 900), Color = QUAY, Material = Enum.Material.Concrete, Layer = 1 },
	{ Name = "Stora torg", Min = v(-240, 120), Max = v(-60, 240), Color = Color3.fromRGB(185, 170, 150), Material = Enum.Material.Cobblestone, Layer = 2 },
	{ Name = "Tylösand strand", Min = v(-2950, 800), Max = v(-2100, 900), Color = SAND, Material = Enum.Material.Sand, Layer = 1 },
	{ Name = "Östra stranden", Min = v(1040, 790), Max = v(1950, 900), Color = SAND, Material = Enum.Material.Sand, Layer = 1 },
	{ Name = "Åker norr", Min = v(-2000, 420), Max = v(-700, 560), Color = FIELD, Material = Enum.Material.Grass, Layer = 1 },
	{ Name = "Åker söder", Min = v(-2000, 720), Max = v(-700, 880), Color = FIELD, Material = Enum.Material.Grass, Layer = 1 },
} :: { Zone }

MapData.BuildingStyles = {
	Town = {
		CellMin = 36,
		CellMax = 60,
		MinHeight = 22,
		MaxHeight = 48,
		Gap = 0.08,
		Colors = {
			Color3.fromRGB(230, 200, 160),
			Color3.fromRGB(210, 140, 110),
			Color3.fromRGB(240, 225, 190),
			Color3.fromRGB(190, 120, 100),
			Color3.fromRGB(225, 210, 150),
		},
		RoofColor = Color3.fromRGB(120, 70, 60),
	},
	Residential = {
		CellMin = 40,
		CellMax = 60,
		MinHeight = 14,
		MaxHeight = 30,
		Gap = 0.15,
		Colors = {
			Color3.fromRGB(245, 240, 230),
			Color3.fromRGB(200, 215, 230),
			Color3.fromRGB(235, 200, 170),
			Color3.fromRGB(190, 210, 180),
		},
		RoofColor = Color3.fromRGB(80, 80, 90),
	},
	Warehouse = {
		CellMin = 60,
		CellMax = 100,
		MinHeight = 16,
		MaxHeight = 26,
		Gap = 0.12,
		Colors = {
			Color3.fromRGB(150, 160, 170),
			Color3.fromRGB(90, 120, 160),
			Color3.fromRGB(170, 110, 80),
			Color3.fromRGB(120, 130, 120),
		},
		RoofColor = Color3.fromRGB(70, 70, 75),
	},
} :: { [string]: BuildingStyle }

-- Kvarter mellan vägarna (22 studs marginal från vägens mittlinje).
MapData.Blocks = {
	{ Min = v(-478, -278), Max = v(-172, 78), Style = "Town" },
	{ Min = v(-128, -278), Max = v(88, 78), Style = "Town" },
	{ Min = v(-478, 122), Max = v(-262, 328), Style = "Town" },
	{ Min = v(-38, 122), Max = v(88, 328), Style = "Town" },
	{ Min = v(-240, 262), Max = v(-60, 328), Style = "Town" },
	{ Min = v(-478, 372), Max = v(-90, 628), Style = "Town" },
	{ Min = v(-478, 672), Max = v(-142, 880), Style = "Warehouse" },
	{ Min = v(252, -278), Max = v(578, 78), Style = "Residential" },
	{ Min = v(622, -278), Max = v(978, 78), Style = "Residential" },
	{ Min = v(252, 122), Max = v(578, 628), Style = "Warehouse" },
	{ Min = v(622, 122), Max = v(778, 478), Style = "Residential" },
	{ Min = v(822, 122), Max = v(978, 478), Style = "Residential" },
	{ Min = v(622, 522), Max = v(778, 628), Style = "Warehouse" },
	{ Min = v(822, 522), Max = v(978, 628), Style = "Warehouse" },
} :: { Block }

-- Kullar byggs med Terrain (mjuka backar). Regionerna får inte överlappa varandra.
MapData.Hills = {
	{ Name = "Galgberget", Center = v(-1000, -750), FlatRadius = 110, Radius = 420, Height = 55, Material = Enum.Material.Grass },
	{ Name = "Puckel 1", Center = v(-1900, -450), FlatRadius = 0, Radius = 45, Height = 9, Material = Enum.Material.Ground },
	{ Name = "Puckel 2", Center = v(-1800, -450), FlatRadius = 0, Radius = 45, Height = 9, Material = Enum.Material.Ground },
	{ Name = "Puckel 3", Center = v(-1700, -450), FlatRadius = 0, Radius = 45, Height = 9, Material = Enum.Material.Ground },
	{ Name = "Puckel 4", Center = v(-1600, -450), FlatRadius = 0, Radius = 45, Height = 9, Material = Enum.Material.Ground },
	{ Name = "Puckel 5", Center = v(-1500, -450), FlatRadius = 0, Radius = 45, Height = 9, Material = Enum.Material.Ground },
	{ Name = "Dyn T1", Center = v(-2850, 715), FlatRadius = 0, Radius = 40, Height = 7, Material = Enum.Material.Sand },
	{ Name = "Dyn T2", Center = v(-2750, 715), FlatRadius = 0, Radius = 40, Height = 7, Material = Enum.Material.Sand },
	{ Name = "Dyn T3", Center = v(-2650, 715), FlatRadius = 0, Radius = 40, Height = 7, Material = Enum.Material.Sand },
	{ Name = "Dyn Ö1", Center = v(1300, 700), FlatRadius = 0, Radius = 45, Height = 7, Material = Enum.Material.Sand },
	{ Name = "Dyn Ö2", Center = v(1500, 700), FlatRadius = 0, Radius = 45, Height = 7, Material = Enum.Material.Sand },
	{ Name = "Dyn Ö3", Center = v(1700, 700), FlatRadius = 0, Radius = 45, Height = 7, Material = Enum.Material.Sand },
} :: { Hill }

MapData.Ramps = {
	-- Hoppa över Nissans mynning från östra kajen. Kräver boost!
	{ Name = "Hamnhoppet", Start = Vector3.new(290, 0, 830), Yaw = 90, Length = 44, Angle = 22, Width = 24 },
	-- Kickers på Galgbergets topp, ut över backarna
	{ Name = "Galgberget Syd", Start = Vector3.new(-1000, 55, -680), Yaw = 180, Length = 20, Angle = 16, Width = 20 },
	{ Name = "Galgberget Öst", Start = Vector3.new(-930, 55, -750), Yaw = -90, Length = 20, Angle = 16, Width = 20 },
	{ Name = "Galgberget Väst", Start = Vector3.new(-1070, 55, -750), Yaw = 90, Length = 20, Angle = 16, Width = 20 },
	-- Ut i havet vid Östra stranden (plask = respawn)
	{ Name = "Plaskrampen", Start = Vector3.new(1600, 0, 815), Yaw = 180, Length = 24, Angle = 18, Width = 20 },
	-- Fältramp vid landsvägen
	{ Name = "Åkerhoppet", Start = Vector3.new(-1150, 0, 520), Yaw = 90, Length = 30, Angle = 18, Width = 22 },
} :: { Ramp }

MapData.Landmarks = {
	Fountain = v(-150, 180),
	NorrePort = v(-150, -250),
	Castle = v(0, 490),
	LookoutTower = Vector3.new(-1000, 55, -810),
	Hotel = v(-2480, 650),
	Pier = { Start = v(-2500, 880), Length = 200, Width = 16 },
	BeachHuts = { FromX = 1100, ToX = 1900, Z = 812, SkipNearX = 1600 },
	Harbor = { Min = v(360, 690), Max = v(960, 775), CraneZ = 885, CraneXs = { 420, 620, 820 } },
}

-- Reserverad korsning för krockläget (fas 6)
MapData.CrashJunction = v(800, 500)

-- Snabbresa och respawn. Yaw i grader (0 = norr).
MapData.Locations = {
	{ Id = "StoraTorg", Name = "Stora torg", Position = Vector3.new(-150, 0, 215), Yaw = 0 },
	{ Id = "NorrePort", Name = "Norre port", Position = Vector3.new(-150, 0, -180), Yaw = 0 },
	{ Id = "Slottet", Name = "Halmstads slott", Position = Vector3.new(110, 0, 400), Yaw = 180 },
	{ Id = "Hamnen", Name = "Hamnen", Position = Vector3.new(900, 0, 830), Yaw = 90 },
	{ Id = "Galgberget", Name = "Galgberget", Position = Vector3.new(-560, 0, -360), Yaw = 43 },
	{ Id = "Landsvagen", Name = "Tylösandsvägen", Position = Vector3.new(-700, 0, 655), Yaw = 90 },
	{ Id = "Tylosand", Name = "Tylösand", Position = Vector3.new(-2300, 0, 780), Yaw = 90 },
	{ Id = "OstraStranden", Name = "Östra stranden", Position = Vector3.new(1100, 0, 760), Yaw = -90 },
	{ Id = "Testbanan", Name = "Testbanan", Position = Vector3.new(6000, 0, 300), Yaw = 0 },
} :: { Location }

-- Stadsdelar för namnskylten när man kör in i ett område. Första träffen gäller.
MapData.Districts = {
	{ Name = "Stora torg", Min = v(-240, 120), Max = v(-60, 240) },
	{ Name = "Halmstads slott", Min = v(-100, 400), Max = v(140, 600) },
	{ Name = "Nissan", Min = v(150, -1400), Max = v(230, 900) },
	{ Name = "Centrum", Min = v(-520, -320), Max = v(150, 640) },
	{ Name = "Västra kajen", Min = v(-520, 640), Max = v(150, 900) },
	{ Name = "Hamnen", Min = v(230, 480), Max = v(1020, 900) },
	{ Name = "Östra Förstaden", Min = v(230, -320), Max = v(1020, 480) },
	{ Name = "Östra stranden", Min = v(1020, 560), Max = v(2000, 900) },
	{ Name = "Galgberget", Min = v(-1450, -1200), Max = v(-560, -340) },
	{ Name = "Puckelbanan", Min = v(-1960, -510), Max = v(-1450, -390) },
	{ Name = "Tylösand", Min = v(-3000, 300), Max = v(-2100, 1400) },
	{ Name = "Tylösandsvägen", Min = v(-2100, 300), Max = v(-520, 900) },
	{ Name = "Testbanan", Min = v(5200, -800), Max = v(6800, 800) },
} :: { Area }

-- Spelarnas startplats: två rader om fem bilar på Stora torg, vända mot norr.
function MapData.PlayerSpawn(slot: number): CFrame
	local column = (slot - 1) % 5
	local row = math.floor((slot - 1) / 5) % 2
	return CFrame.new(-150 + (column - 2) * 14, 4, 215 + row * 16)
end

function MapData.LocationCFrame(location: Location): CFrame
	return CFrame.new(location.Position + Vector3.new(0, 4, 0)) * CFrame.Angles(0, math.rad(location.Yaw), 0)
end

function MapData.FindLocation(id: string): Location?
	for _, location in MapData.Locations do
		if location.Id == id then
			return location
		end
	end
	return nil
end

function MapData.IsInBounds(position: Vector3): boolean
	for _, area in MapData.Bounds do
		if position.X >= area.Min.X and position.X <= area.Max.X and position.Z >= area.Min.Y and position.Z <= area.Max.Y then
			return true
		end
	end
	return false
end

function MapData.DistrictAt(position: Vector3): string?
	for _, district in MapData.Districts do
		if
			position.X >= district.Min.X
			and position.X <= district.Max.X
			and position.Z >= district.Min.Y
			and position.Z <= district.Max.Y
		then
			return district.Name
		end
	end
	return nil
end

return MapData
