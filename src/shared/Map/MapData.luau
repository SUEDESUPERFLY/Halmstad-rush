--!strict
-- Halmstad, byggt från stadskartan (Destination Halmstad, City 2023).
-- Själva stadens markmaterial, hus och respawnpunkter genereras av tools/map/build_city.py
-- till src/server/Map/Generated/. Den här modulen innehåller allt som sätts för hand:
-- landmärken, platser, stadsdelar, kullar och områdena utanför kartan (Tylösand, kusten).
--
-- Skala: 1 kartpixel = 2 studs (≈ 1:3,6 mot verkligheten). Origo (0, 0) = Stora torg.
-- X = öster, Z = söder (norr är -Z). Marken ligger på Y = 0.

export type Hill = {
	Name: string,
	Center: Vector2,
	FlatRadius: number,
	Radius: number,
	Height: number,
	Material: Enum.Material,
}

export type Location = {
	Id: string,
	Name: string,
	Position: Vector3,
	Yaw: number, -- grader, 0 = norr
	SnapToRoad: boolean?, -- flytta till närmaste gatupunkt (stadens gator är genererade)
}

export type Sign = {
	Kind: string, -- "Billboard" | "Highway" | "Plaque" | "Arch"
	Text: string,
	SubText: string?,
	Position: Vector3,
	Yaw: number, -- hållet framsidan vänds mot (0 = norr, 90 = väster, -90 = öster, 180 = söder)
	Width: number,
	Color: Color3,
	TextColor: Color3?,
}

export type Road = {
	Name: string,
	Width: number,
	Points: { Vector2 },
}

export type District = {
	Name: string,
	Position: Vector2,
}

local function v(x: number, z: number): Vector2
	return Vector2.new(x, z)
end

local MapData = {}

MapData.WaterLevel = -4 -- Terrain-vatten fylls från -12 upp till hit

-- Stadskartans rutnät (se Generated/CityGrid). Havet tar vid söder om kusten.
MapData.City = { MinX = -2272, MaxX = 2264, MinZ = -1304, MaxZ = 1844 }
MapData.CoastZ = 1844
MapData.TylosandCoastZ = 1150 -- kusten väster om stadskartan

MapData.Bounds = {
	{ Min = v(-4800, -1700), Max = v(2800, 2700) }, -- Halmstad med omnejd
	{ Min = v(5200, -800), Max = v(6800, 800) }, -- testbanan
}

MapData.TestTrackOrigin = Vector3.new(6000, 0, 0)

MapData.Hills = {
	-- Galgberget med utsiktstornet. Gator och hus i backen följer terrängen.
	{ Name = "Galgberget", Center = v(-394, -1158), FlatRadius = 50, Radius = 430, Height = 36, Material = Enum.Material.Grass },
	{ Name = "Dyn 1", Center = v(-4300, 1112), FlatRadius = 0, Radius = 26, Height = 5, Material = Enum.Material.Sand },
	{ Name = "Dyn 2", Center = v(-3500, 1115), FlatRadius = 0, Radius = 26, Height = 5, Material = Enum.Material.Sand },
} :: { Hill }

-- Landmärken (lägen uppmätta på kartan)
MapData.Landmarks = {
	Church = { Center = v(-109, 78), Length = 70, Width = 32 }, -- S:t Nikolai kyrka, torn i väster
	Castle = { Center = v(-10, 335), Size = v(100, 70) }, -- Halmstads slott vid Nissan
	Library = { Center = v(310, -210), Yaw = 15 }, -- Stadsbiblioteket, delvis över ån
	NorrePort = { Position = v(86, -408), Yaw = 12 },
	LookoutTower = v(-394, -1158), -- Galgbergets utsiktstorn
	Hallandsgarden = v(-212, -1086), -- friluftsmuseet
	Hotel = v(-4150, 960), -- strandhotellet i Tylösand (generiskt namn)
	Pier = { Start = v(-4000, 1150), Length = 200, Width = 14 }, -- badbryggan i Tylösand
	Breakwater = { Start = v(-100, 1844), Length = 220, Width = 14 }, -- pir vid Nissans mynning
	Ship = { Center = v(80, 2010), Length = 150, Width = 30, Name = "M/S LAXEN" },
	WindTurbines = { v(-3000, 620), v(-3300, 560), v(-3600, 640) },
}

-- Vägar utanför stadskartan (Terrain-asfalt). Tylösandsvägen fortsätter där
-- Slottsjordsvägen lämnar kartan i väster.
MapData.ExtraRoads = {
	{
		Name = "Tylösandsvägen",
		Width = 30,
		Points = { v(-2272, 786), v(-2700, 790), v(-3150, 860), v(-3550, 960), v(-3800, 1030) },
	},
	{ Name = "Tylösand strandväg", Width = 26, Points = { v(-4550, 1050), v(-3300, 1050) } },
} :: { Road }

MapData.Beaches = {
	{
		Name = "Tylösand",
		Min = v(-4560, 1085),
		Max = v(-3300, 1145),
		Lifeguards = { -4350, -3700 },
		Volleyball = v(-3600, 1100),
		Surfboards = v(-4200, 1090),
		Keep = { -4000 },
	},
	{
		Name = "Östra stranden",
		Min = v(-60, 1800),
		Max = v(2240, 1840),
		Lifeguards = { 400, 1300, 2000 },
		Volleyball = v(900, 1815),
		Surfboards = v(150, 1803),
		Keep = { -100 },
	},
}

local SIGN_BLUE = Color3.fromRGB(30, 80, 160)
local SIGN_BROWN = Color3.fromRGB(120, 70, 40) -- turistskyltar i Sverige är bruna

MapData.Signs = {
	{ Kind = "Billboard", Text = "VÄLKOMMEN TILL HALMSTAD", Position = Vector3.new(-2500, 0, 825), Yaw = 90, Width = 44, Color = SIGN_BLUE },
	{ Kind = "Highway", Text = "Tylösand  ↑", SubText = "Halmstad C  ↓", Position = Vector3.new(-2400, 0, 755), Yaw = -90, Width = 26, Color = SIGN_BLUE },
	{ Kind = "Highway", Text = "Halmstad C  ↑", SubText = "Tylösand  ↓", Position = Vector3.new(-3300, 0, 935), Yaw = 75, Width = 26, Color = SIGN_BLUE },
	{ Kind = "Arch", Text = "TYLÖSAND", Position = Vector3.new(-3400, 0, 1050), Yaw = -90, Width = 40, Color = SIGN_BROWN },
	{ Kind = "Arch", Text = "ÖSTRA STRANDEN", Position = Vector3.new(120, 0, 1776), Yaw = 90, Width = 40, Color = SIGN_BROWN },
	{ Kind = "Plaque", Text = "HALMSTADS SLOTT", Position = Vector3.new(-62, 0, 292), Yaw = 0, Width = 18, Color = SIGN_BROWN },
	{ Kind = "Plaque", Text = "S:T NIKOLAI KYRKA", Position = Vector3.new(-109, 0, 100), Yaw = 180, Width = 18, Color = SIGN_BROWN },
	{ Kind = "Plaque", Text = "UTSIKTSTORNET", Position = Vector3.new(-394, 0, -1128), Yaw = 180, Width = 16, Color = SIGN_BROWN },
	{ Kind = "Plaque", Text = "HALLANDSGÅRDEN", Position = Vector3.new(-212, 0, -1052), Yaw = 180, Width = 18, Color = SIGN_BROWN },
	{ Kind = "Plaque", Text = "STADSBIBLIOTEKET", Position = Vector3.new(266, 0, -176), Yaw = 90, Width = 18, Color = SIGN_BROWN },
} :: { Sign }

-- Stadsdelsnamn (lägen från kartans lila etiketter). Närmaste namn visas.
MapData.Districts = {
	{ Name = "Galgberget", Position = v(-500, -1180) },
	{ Name = "Nickedala", Position = v(-2100, -800) },
	{ Name = "Karlsro", Position = v(-2118, -110) },
	{ Name = "Rotorp", Position = v(-1538, 188) },
	{ Name = "Alet", Position = v(-1596, 992) },
	{ Name = "Söder", Position = v(-684, 1128) },
	{ Name = "Gamletull", Position = v(402, -510) },
	{ Name = "Furet", Position = v(1042, -994) },
	{ Name = "Nyatorp", Position = v(1100, -160) },
	{ Name = "Nyhem", Position = v(1430, 906) },
	{ Name = "Östergård", Position = v(2108, 402) },
	{ Name = "Sannarp", Position = v(2186, -606) },
	{ Name = "Linehed", Position = v(2166, 1042) },
	{ Name = "Centrum", Position = v(0, 150) },
} :: { District }

-- Områden som vinner över närmaste stadsdel (första träffen gäller)
MapData.SpecialAreas = {
	{ Name = "Stora torg", Min = v(-90, -50), Max = v(85, 50) },
	{ Name = "Testbanan", Min = v(5200, -800), Max = v(6800, 800) },
	{ Name = "Tylösand", Min = v(-4800, 900), Max = v(-3300, 2700) },
	{ Name = "Tylösandsvägen", Min = v(-4800, -1700), Max = v(-2272, 2700) },
	{ Name = "Östra stranden", Min = v(-60, 1780), Max = v(2800, 2700) },
}

MapData.Locations = {
	{ Id = "StoraTorg", Name = "Stora torg", Position = Vector3.new(0, 0, 24), Yaw = 0 },
	{ Id = "Slottet", Name = "Halmstads slott", Position = Vector3.new(-40, 0, 270), Yaw = 0, SnapToRoad = true },
	{ Id = "NorreKatt", Name = "Norre Katts park", Position = Vector3.new(120, 0, -470), Yaw = 0, SnapToRoad = true },
	{ Id = "Biblioteket", Name = "Stadsbiblioteket", Position = Vector3.new(380, 0, -200), Yaw = 0, SnapToRoad = true },
	{ Id = "Galgberget", Name = "Galgberget", Position = Vector3.new(-360, 0, -1100), Yaw = 0, SnapToRoad = true },
	{ Id = "Centralen", Name = "Halmstad C", Position = Vector3.new(362, 0, 654), Yaw = 0, SnapToRoad = true },
	{ Id = "Arena", Name = "Halmstad Arena", Position = Vector3.new(2000, 0, -24), Yaw = 0, SnapToRoad = true },
	{ Id = "Hogskolan", Name = "Högskolan", Position = Vector3.new(1546, 0, 1276), Yaw = 0, SnapToRoad = true },
	{ Id = "RaceStoraRingen", Name = "Race: Stora ringen", Position = Vector3.new(-250, 0, 230), Yaw = -90 },
	{ Id = "OstraStranden", Name = "Östra stranden", Position = Vector3.new(600, 0, 1776), Yaw = -90 },
	{ Id = "Tylosand", Name = "Tylösand", Position = Vector3.new(-3500, 0, 1050), Yaw = 90 },
	{ Id = "Testbanan", Name = "Testbanan", Position = Vector3.new(6000, 0, 300), Yaw = 0 },
} :: { Location }

-- Höjden på en kulle i punkten (x, z). Samma formel används när terrängen byggs.
function MapData.HillHeight(hill: Hill, x: number, z: number): number
	local r = math.sqrt((x - hill.Center.X) ^ 2 + (z - hill.Center.Y) ^ 2)
	if r <= hill.FlatRadius then
		return hill.Height
	elseif r >= hill.Radius then
		return 0
	end
	local t = (r - hill.FlatRadius) / (hill.Radius - hill.FlatRadius)
	return hill.Height * (0.5 + 0.5 * math.cos(math.pi * t))
end

function MapData.GroundHeightAt(x: number, z: number): number
	local best = 0
	for _, hill in MapData.Hills do
		best = math.max(best, MapData.HillHeight(hill, x, z))
	end
	return best
end

-- Spelarnas startplats: två rader om fem bilar på Stora torg (fontänen i mitten), vända mot norr.
function MapData.PlayerSpawn(slot: number): CFrame
	local column = (slot - 1) % 5
	local row = math.floor((slot - 1) / 5) % 2
	return CFrame.new((column - 2) * 14, 4, if row == 0 then 24 else -24)
end

function MapData.LocationCFrame(location: Location): CFrame
	local p = location.Position
	local y = MapData.GroundHeightAt(p.X, p.Z)
	return CFrame.new(p.X, y + 4, p.Z) * CFrame.Angles(0, math.rad(location.Yaw), 0)
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
	for _, area in MapData.SpecialAreas do
		if position.X >= area.Min.X and position.X <= area.Max.X and position.Z >= area.Min.Y and position.Z <= area.Max.Y then
			return area.Name
		end
	end
	local best: string? = nil
	local bestDistance = math.huge
	for _, district in MapData.Districts do
		local d = (Vector2.new(position.X, position.Z) - district.Position).Magnitude
		if d < bestDistance then
			best, bestDistance = district.Name, d
		end
	end
	return best
end

return MapData
