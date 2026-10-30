--!strict
-- Bilar, uppgraderingar och lackfärger. Allt köps med kronor som man kör ihop i spelet
-- (aldrig med Robux, se CLAUDE.md: inget pay-to-win). Servern räknar ut bilens egenskaper
-- med ComputeStats och sätter dem som attribut på bilen; klienten läser attributen.

export type Stats = {
	TopSpeed: number, -- multiplikator för maxfart och boostfart
	Acceleration: number,
	Handling: number, -- svängförmåga och grepp
	Boost: number, -- boostens maxfart
	Charge: number, -- hur snabbt boost laddas
	HillAssist: number,
}

export type Car = {
	Id: string,
	Name: string,
	Style: string, -- karosstil i CarBuilder
	Price: number,
	Description: string,
	Stats: Stats,
}

export type Upgrade = {
	Id: string,
	Name: string,
	Costs: { number }, -- pris för nivå 1, 2, 3 ...
	PerLevel: { [string]: number }, -- ökning av Stats per nivå
}

export type PaintColor = { Id: string, Name: string, Color: Color3 }

local CarCatalog = {}

CarCatalog.StarterCar = "Kustpilen"
CarCatalog.PaintCost = 150

local function stats(top: number, accel: number, handling: number, boost: number, hill: number?): Stats
	return { TopSpeed = top, Acceleration = accel, Handling = handling, Boost = boost, Charge = 1, HillAssist = hill or 1 }
end

CarCatalog.Cars = {
	{
		Id = "Kustpilen",
		Name = "Kustpilen",
		Style = "Cabriolet",
		Price = 0,
		Description = "Öppen cabriolet. Allround och lätt att köra.",
		Stats = stats(1.0, 1.0, 1.0, 1.0),
	},
	{
		Id = "Laxen",
		Name = "Laxen",
		Style = "Hatch",
		Price = 1500,
		Description = "Liten och kvick. Snabb i stan, svänger skarpt.",
		Stats = stats(0.96, 1.18, 1.18, 1.0),
	},
	{
		Id = "Galgbergaren",
		Name = "Galgbergaren",
		Style = "Jeep",
		Price = 3000,
		Description = "Terrängbil som klättrar uppför Galgberget som inget.",
		Stats = stats(0.97, 1.12, 0.95, 1.05, 1.5),
	},
	{
		Id = "TylosandGT",
		Name = "Tylösand GT",
		Style = "Coupe",
		Price = 5000,
		Description = "Låg coupé byggd för landsvägen ut till havet.",
		Stats = stats(1.1, 1.1, 1.08, 1.06),
	},
	{
		Id = "Stormvind",
		Name = "Stormvind",
		Style = "Hyper",
		Price = 12000,
		Description = "Halländsk superbil. Snabbast i stan, kräver en lugn hand.",
		Stats = stats(1.18, 1.2, 1.02, 1.12),
	},
} :: { Car }

CarCatalog.Upgrades = {
	{ Id = "Engine", Name = "Motor", Costs = { 400, 900, 1800 }, PerLevel = { TopSpeed = 0.035, Acceleration = 0.06 } },
	{ Id = "Grip", Name = "Grepp", Costs = { 300, 700, 1400 }, PerLevel = { Handling = 0.06 } },
	{ Id = "Turbo", Name = "Turbo", Costs = { 500, 1100, 2200 }, PerLevel = { Boost = 0.04, Charge = 0.12 } },
} :: { Upgrade }

CarCatalog.Colors = {
	{ Id = "Red", Name = "Röd", Color = Color3.fromRGB(220, 50, 50) },
	{ Id = "FaluRed", Name = "Falu rödfärg", Color = Color3.fromRGB(150, 45, 35) },
	{ Id = "Orange", Name = "Orange", Color = Color3.fromRGB(245, 130, 30) },
	{ Id = "Yellow", Name = "Gul", Color = Color3.fromRGB(245, 200, 40) },
	{ Id = "Green", Name = "Grön", Color = Color3.fromRGB(50, 170, 80) },
	{ Id = "Teal", Name = "Havsgrön", Color = Color3.fromRGB(30, 160, 160) },
	{ Id = "Blue", Name = "Blå", Color = Color3.fromRGB(40, 110, 220) },
	{ Id = "Navy", Name = "Marinblå", Color = Color3.fromRGB(25, 45, 100) },
	{ Id = "Purple", Name = "Lila", Color = Color3.fromRGB(140, 70, 200) },
	{ Id = "White", Name = "Vit", Color = Color3.fromRGB(240, 240, 240) },
	{ Id = "Silver", Name = "Silver", Color = Color3.fromRGB(170, 175, 185) },
	{ Id = "Black", Name = "Svart", Color = Color3.fromRGB(30, 30, 35) },
} :: { PaintColor }

CarCatalog.DefaultColor = "Red"

function CarCatalog.FindCar(id: string): Car?
	for _, car in CarCatalog.Cars do
		if car.Id == id then
			return car
		end
	end
	return nil
end

function CarCatalog.FindUpgrade(id: string): Upgrade?
	for _, upgrade in CarCatalog.Upgrades do
		if upgrade.Id == id then
			return upgrade
		end
	end
	return nil
end

function CarCatalog.FindColor(id: string): PaintColor?
	for _, color in CarCatalog.Colors do
		if color.Id == id then
			return color
		end
	end
	return nil
end

-- Bilens slutliga egenskaper med uppgraderingar.
function CarCatalog.ComputeStats(carId: string, upgrades: { [string]: number }?): Stats
	local car = CarCatalog.FindCar(carId) or CarCatalog.Cars[1]
	local result = table.clone(car.Stats)
	for _, upgrade in CarCatalog.Upgrades do
		local level = if upgrades then upgrades[upgrade.Id] or 0 else 0
		for stat, amount in upgrade.PerLevel do
			(result :: any)[stat] += amount * level
		end
	end
	return result
end

-- Högsta möjliga multiplikator för maxfart + boost (används av serverns fartkontroll).
function CarCatalog.MaxBoostMultiplier(stats: Stats): number
	return stats.TopSpeed * stats.Boost
end

return CarCatalog
