--!strict
-- Halmstads kända byggnader och platser, placerade efter stadskartan.
-- Förenklade former men rätt läge, storlek och karaktär.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local Geometry = require(script.Parent.Geometry)
local Props = require(script.Parent.Props)

local Landmarks = {}

local COPPER = Color3.fromRGB(95, 150, 125)
local DARK_ROOF = Color3.fromRGB(58, 58, 64)
local BRICK = Color3.fromRGB(150, 70, 52)
local FALU_RED = Color3.fromRGB(150, 45, 35)

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function ground(x: number, z: number): number
	return MapData.GroundHeightAt(x, z)
end

-- Sadeltak längs X-axeln i `frame` (lokalt), med given bredd (Z) och höjd.
local function gableRoof(parent: Instance, frame: CFrame, length: number, width: number, rise: number, color: Color3)
	local half = width / 2
	local slope = math.sqrt(half * half + rise * rise)
	local angle = math.atan2(rise, half)
	for _, side in { -1, 1 } do
		Geometry.Part(
			parent,
			"Roof",
			Vector3.new(length, 0.8, slope + 0.6),
			frame * CFrame.new(0, rise / 2, side * half / 2) * CFrame.Angles(side * angle, 0, 0),
			color
		)
	end
end

-- Fontänen "Europa och tjuren" mitt på Stora torg
function Landmarks.Fountain(parent: Instance, at: Vector2)
	local f = folder(parent, "EuropaOchTjuren")
	local base = Vector3.new(at.X, 0, at.Y)
	Geometry.Obstacle(Geometry.Cylinder(f, "Basin", base, 10, 2.2, Color3.fromRGB(170, 170, 172), Enum.Material.Granite))
	local water = Geometry.Cylinder(f, "Water", base + Vector3.new(0, 1.9, 0), 9, 0.3, Color3.fromRGB(70, 140, 180), Enum.Material.Glass)
	water.Transparency = 0.3
	Geometry.Decor(water)
	Geometry.Obstacle(Geometry.Cylinder(f, "Plinth", base, 3, 5, Color3.fromRGB(150, 150, 152), Enum.Material.Granite))
	-- Tjuren (stiliserad, i ärgad brons)
	Geometry.Part(f, "BullBody", Vector3.new(3, 2.6, 6), CFrame.new(base + Vector3.new(0, 6.5, 0)), COPPER, Enum.Material.Metal)
	Geometry.Part(f, "BullHead", Vector3.new(2, 2, 2.2), CFrame.new(base + Vector3.new(0, 7.6, -3.6)), COPPER, Enum.Material.Metal)
	Geometry.Part(f, "Europa", Vector3.new(1.2, 3, 1.2), CFrame.new(base + Vector3.new(0, 9.3, 0.6)), COPPER, Enum.Material.Metal)
	-- Svenska flaggor vid torget
	Props.SwedishFlag(parent, base + Vector3.new(-60, 0, -42), 22)
	Props.SwedishFlag(parent, base + Vector3.new(60, 0, -42), 22)
end

-- S:t Nikolai kyrka: tegelkyrka med västtorn och kopparspira
function Landmarks.Church(parent: Instance, center: Vector2, length: number, width: number)
	local f = folder(parent, "SanktNikolai")
	local wallHeight = 24
	local frame = CFrame.new(center.X, ground(center.X, center.Y), center.Y)
	Geometry.Obstacle(Geometry.Part(f, "Nave", Vector3.new(length, wallHeight, width), frame * CFrame.new(0, wallHeight / 2, 0), BRICK, Enum.Material.Brick))
	gableRoof(f, frame * CFrame.new(0, wallHeight, 0), length + 2, width + 2, 14, COPPER)
	-- Torn i väster
	local towerX = -length / 2 - 7
	local towerHeight = 58
	Geometry.Obstacle(Geometry.Part(f, "Tower", Vector3.new(16, towerHeight, 16), frame * CFrame.new(towerX, towerHeight / 2, 0), BRICK, Enum.Material.Brick))
	local y = towerHeight
	for i, size in { 15, 11, 7, 3.5 } do
		local h = if i == 4 then 10 else 7
		Geometry.Part(f, "Spire", Vector3.new(size, h, size), frame * CFrame.new(towerX, y + h / 2, 0), COPPER, Enum.Material.Metal)
		y += h
	end
	Geometry.Ball(f, "SpireTop", (frame * CFrame.new(towerX, y + 0.8, 0)).Position, 0.9, Color3.fromRGB(230, 190, 60))
	-- Klockfönster
	for _, side in { -1, 1 } do
		Geometry.Part(f, "Window", Vector3.new(4, 7, 0.4), frame * CFrame.new(towerX, towerHeight - 9, side * 8.1), Color3.fromRGB(40, 40, 45))
	end
end

-- Halmstads slott: ljus putsad borg vid Nissan, tre längor kring en gård öppen mot ån
function Landmarks.Castle(parent: Instance, center: Vector2, size: Vector2)
	local f = folder(parent, "HalmstadsSlott")
	local wall = Color3.fromRGB(232, 210, 160)
	local height = 26
	local frame = CFrame.new(center.X, ground(center.X, center.Y), center.Y)
	local wingDepth = 20
	-- Västra längan (huvudbyggnaden)
	local west = frame * CFrame.new(-size.X / 2 + wingDepth / 2, height / 2, 0)
	Geometry.Obstacle(Geometry.Part(f, "WestWing", Vector3.new(wingDepth, height, size.Y), west, wall, Enum.Material.Plaster))
	gableRoof(f, frame * CFrame.new(-size.X / 2 + wingDepth / 2, height, 0) * CFrame.Angles(0, math.rad(90), 0), size.Y + 2, wingDepth + 2, 10, DARK_ROOF)
	-- Norra och södra längorna
	for _, side in { -1, 1 } do
		local wingFrame = frame * CFrame.new(wingDepth / 2, 0, side * (size.Y / 2 - wingDepth / 2))
		Geometry.Obstacle(Geometry.Part(f, "Wing", Vector3.new(size.X - wingDepth, height - 4, wingDepth), wingFrame * CFrame.new(0, (height - 4) / 2, 0), wall, Enum.Material.Plaster))
		gableRoof(f, wingFrame * CFrame.new(0, height - 4, 0), size.X - wingDepth + 2, wingDepth + 2, 9, DARK_ROOF)
	end
	-- Trapptorn i hörnet
	local towerBase = (frame * CFrame.new(-size.X / 2 + 4, 0, -size.Y / 2 + 4)).Position
	Geometry.Obstacle(Geometry.Cylinder(f, "StairTower", towerBase, 6, height + 8, wall, Enum.Material.Plaster))
	Geometry.Cylinder(f, "TowerCap", towerBase + Vector3.new(0, height + 8, 0), 6.5, 2, DARK_ROOF)
	Geometry.Part(f, "TowerSpire", Vector3.new(4, 8, 4), CFrame.new(towerBase + Vector3.new(0, height + 14, 0)), COPPER, Enum.Material.Metal)
	Props.SwedishFlag(parent, (frame * CFrame.new(size.X / 2 - 6, 0, 0)).Position, 26)
end

-- Norre port: den gamla stadsporten i tegel, som Storgatan går igenom
function Landmarks.NorrePort(parent: Instance, position: Vector2, yaw: number)
	local f = folder(parent, "NorrePort")
	local frame = CFrame.new(position.X, ground(position.X, position.Y), position.Y) * CFrame.Angles(0, math.rad(yaw), 0)
	local gap = 22
	for _, side in { -1, 1 } do
		Geometry.Obstacle(Geometry.Part(f, "Pillar", Vector3.new(10, 26, 14), frame * CFrame.new(side * (gap / 2 + 5), 13, 0), BRICK, Enum.Material.Brick))
	end
	Geometry.Part(f, "Arch", Vector3.new(gap + 20, 9, 14), frame * CFrame.new(0, 26.5, 0), BRICK, Enum.Material.Brick)
	gableRoof(f, frame * CFrame.new(0, 31, 0), gap + 22, 16, 7, DARK_ROOF)
end

function Landmarks.LookoutTower(parent: Instance, at: Vector2)
	local f = folder(parent, "Utsiktstornet")
	local base = Vector3.new(at.X, ground(at.X, at.Y), at.Y)
	local stone = Color3.fromRGB(150, 140, 125)
	Geometry.Obstacle(Geometry.Part(f, "Tower", Vector3.new(12, 40, 12), CFrame.new(base + Vector3.new(0, 18, 0)), stone, Enum.Material.Cobblestone))
	Geometry.Part(f, "Battlements", Vector3.new(15, 3, 15), CFrame.new(base + Vector3.new(0, 39.5, 0)), stone, Enum.Material.Cobblestone)
	Props.SwedishFlag(f, base + Vector3.new(0, 41, 0), 10)
end

-- Hallandsgården: friluftsmuseum med faluröda stugor och gräsmark
function Landmarks.Hallandsgarden(parent: Instance, at: Vector2, rng: Random)
	local f = folder(parent, "Hallandsgarden")
	local offsets = { Vector2.new(-24, -14), Vector2.new(14, -18), Vector2.new(-10, 18), Vector2.new(24, 14) }
	for _, offset in offsets do
		local p = at + offset
		local frame = CFrame.new(p.X, ground(p.X, p.Y), p.Y) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0)
		Geometry.Obstacle(Geometry.Part(f, "Cottage", Vector3.new(16, 8, 10), frame * CFrame.new(0, 4, 0), FALU_RED, Enum.Material.WoodPlanks))
		gableRoof(f, frame * CFrame.new(0, 8, 0), 17, 11, 5, Color3.fromRGB(70, 60, 50))
		for _, side in { -1, 1 } do
			Geometry.Part(f, "Corner", Vector3.new(0.5, 8, 0.5), frame * CFrame.new(side * 8, 4, 5.1), Color3.new(1, 1, 1))
		end
	end
end

-- Stadsbiblioteket: långsmal glasbyggnad på pelare, delvis över Nissan
function Landmarks.Library(parent: Instance, center: Vector2, yaw: number)
	local f = folder(parent, "Stadsbiblioteket")
	local frame = CFrame.new(center.X, 0, center.Y) * CFrame.Angles(0, math.rad(yaw), 0)
	local length, width, lift, height = 26, 90, 6, 14
	Geometry.Obstacle(
		Geometry.Part(f, "Glass", Vector3.new(length, height, width), frame * CFrame.new(0, lift + height / 2, 0), Color3.fromRGB(120, 170, 170), Enum.Material.Glass)
	).Transparency = 0.15
	Geometry.Part(f, "RoofSlab", Vector3.new(length + 2, 1, width + 2), frame * CFrame.new(0, lift + height + 0.5, 0), Color3.new(1, 1, 1))
	Geometry.Part(f, "FloorSlab", Vector3.new(length + 1, 1, width + 1), frame * CFrame.new(0, lift - 0.5, 0), Color3.new(1, 1, 1))
	for i = -3, 3 do
		Geometry.Cylinder(f, "Pillar", (frame * CFrame.new(0, -12, i * 13)).Position, 1, lift + 12, Color3.new(1, 1, 1), Enum.Material.Concrete)
	end
end

function Landmarks.Hotel(parent: Instance, at: Vector2)
	local f = folder(parent, "Strandhotellet")
	local body = Geometry.Part(f, "Body", Vector3.new(160, 30, 50), CFrame.new(at.X, 15, at.Y), Color3.fromRGB(245, 245, 240), Enum.Material.Plaster)
	Geometry.Obstacle(body)
	Geometry.Part(f, "Roof", Vector3.new(162, 2, 52), CFrame.new(at.X, 31, at.Y), DARK_ROOF)
	for floor = 1, 3 do
		Geometry.Part(f, "WindowBand", Vector3.new(160.4, 2.5, 50.4), CFrame.new(at.X, floor * 8, at.Y), Color3.fromRGB(60, 80, 100), Enum.Material.Glass)
	end
end

function Landmarks.Pier(parent: Instance, start: Vector2, length: number, width: number, name: string)
	local f = folder(parent, name)
	local wood = Color3.fromRGB(150, 110, 70)
	Geometry.Box(f, "Deck", Vector3.new(start.X - width / 2, -0.5, start.Y), Vector3.new(start.X + width / 2, 0.5, start.Y + length), wood, Enum.Material.WoodPlanks)
	for z = start.Y + 25, start.Y + length, 25 do
		for _, side in { -1, 1 } do
			Geometry.Cylinder(f, "Post", Vector3.new(start.X + side * (width / 2 - 1), -16, z), 1, 16, wood, Enum.Material.Wood)
		end
	end
end

-- Stranddetaljer: parasoller, badvakttorn, surfbrädor och volleybollnät
function Landmarks.Beach(parent: Instance, beach: { [string]: any }, rng: Random)
	local f = folder(parent, "Strand_" .. beach.Name)
	local min: Vector2, max: Vector2 = beach.Min, beach.Max
	local colors = {
		Color3.fromRGB(230, 70, 60),
		Color3.fromRGB(60, 130, 220),
		Color3.fromRGB(250, 200, 50),
		Color3.fromRGB(240, 240, 240),
		Color3.fromRGB(80, 180, 120),
	}
	local function keepClear(x: number): boolean
		for _, keep in beach.Keep do
			if math.abs(x - keep) < 25 then
				return true
			end
		end
		return false
	end
	for x = min.X + 20, max.X - 20, 55 do
		if not keepClear(x) and rng:NextNumber() < 0.7 then
			local z = rng:NextNumber(min.Y + 8, max.Y - 8)
			Props.Umbrella(f, Vector3.new(x, ground(x, z), z), colors[rng:NextInteger(1, #colors)])
		end
	end
	for _, x in beach.Lifeguards do
		Props.LifeguardTower(f, Vector3.new(x, 0, (min.Y + max.Y) / 2), 180)
	end
	local volley: Vector2 = beach.Volleyball
	Props.VolleyballNet(f, Vector3.new(volley.X, 0, volley.Y))
	local boards: Vector2 = beach.Surfboards
	for i = 0, 4 do
		Props.Surfboard(f, Vector3.new(boards.X + i * 3, 0, boards.Y), rng:NextNumber(-10, 10), colors[i % #colors + 1])
	end
end

return Landmarks
