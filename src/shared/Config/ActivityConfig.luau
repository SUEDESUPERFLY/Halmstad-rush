--!strict
-- Aktiviteter i fri körning (fas 6): budjobb, stunts, drift, krockläget och kull.
-- Markörernas lägen snäpps till närmaste gata när servern startar.
-- Alla poäng mäts och alla belöningar betalas av servern.

export type Ramp = { Start: Vector3, Yaw: number, Length: number, Angle: number, Width: number }

export type Activity = {
	Id: string,
	Name: string,
	Kind: string, -- "Delivery" | "StuntJump" | "Drift" | "CrashMode"
	Description: string,
	Marker: Vector3,
	SnapMarker: boolean?, -- false = markören ligger exakt där (t.ex. på stranden)
	-- Delivery
	Variant: string?, -- "Pizza" | "Taxi"
	-- StuntJump
	Ramp: Ramp?,
	RunUp: number?, -- studs före rampen där bilen ställs inför varje försök
	-- StuntJump / Drift: brons, silver, guld (poänggräns och belöning i kr)
	Medals: { number }?,
	Rewards: { number }?,
}

local ActivityConfig = {}

ActivityConfig.MarkerRadius = 25
ActivityConfig.CollisionGroupTag = "TagCars"

ActivityConfig.Activities = {
	{
		Id = "Pizza",
		Name = "Pizza Delivery",
		Kind = "Delivery",
		Variant = "Pizza",
		Description = "Deliver 3 pizzas before they go cold. Don't crash!",
		Marker = Vector3.new(-60, 0, -150),
	},
	{
		Id = "Taxi",
		Name = "Taxi",
		Kind = "Delivery",
		Variant = "Taxi",
		Description = "Pick up and drop off 3 passengers around town.",
		Marker = Vector3.new(362, 0, 654),
	},
	{
		Id = "StrandHoppet",
		Name = "Beach Jump",
		Kind = "StuntJump",
		Description = "Three tries: jump as far as you can from the ramp at Östra stranden.",
		Marker = Vector3.new(760, 0, 1818),
		SnapMarker = false,
		Ramp = { Start = Vector3.new(900, 0, 1818), Yaw = -90, Length = 36, Angle = 22, Width = 18 },
		RunUp = 160,
		Medals = { 50, 75, 95 },
		Rewards = { 100, 200, 350 },
	},
	{
		Id = "TylosandsHoppet",
		Name = "Tylösand Jump",
		Kind = "StuntJump",
		Description = "Three tries: longest jump along the beach at Tylösand.",
		Marker = Vector3.new(-4420, 0, 1105),
		SnapMarker = false,
		Ramp = { Start = Vector3.new(-4260, 0, 1105), Yaw = -90, Length = 36, Angle = 22, Width = 18 },
		RunUp = 160,
		Medals = { 50, 75, 95 },
		Rewards = { 100, 200, 350 },
	},
	{
		Id = "Driftkungen",
		Name = "Drift King",
		Kind = "Drift",
		Description = "45 seconds: drift as much as you can. Anywhere!",
		Marker = Vector3.new(200, 0, 1450),
		Medals = { 1500, 3000, 5000 },
		Rewards = { 100, 200, 350 },
	},
	{
		Id = "Krocklaget",
		Name = "Crash Mode",
		Kind = "CrashMode",
		Description = "Drive into the junction in the industrial area and cause as much damage as you can.",
		Marker = Vector3.new(420, 0, 1550),
	},
} :: { Activity }

-- Budjobb
ActivityConfig.Delivery = {
	Count = 3,
	ArriveRadius = 24,
	ArriveMaxSpeed = 35,
	MinDistance = 450,
	MaxDistance = 1300,
	PickupMinDistance = 150,
	PickupMaxDistance = 500,
	SecondsPerStud = 1 / 55,
	BaseSeconds = 12,
	BasePay = 60,
	TimeBonusPerSecond = 3,
	WreckPenalty = 15,
}

-- Stunthopp
ActivityConfig.StuntJump = {
	Attempts = 3,
	TimeLimit = 75,
	AirborneHeight = 5.5, -- chassit så här högt över marken = i luften
	TakeoffRadius = 30, -- hoppet måste börja nära rampens topp
	ResetDelay = 1.5,
	StudsToMeters = 0.28,
}

-- Drift
ActivityConfig.Drift = {
	Duration = 45,
	MinSpeed = 35,
	MinLateral = 12,
	PointsPerLateral = 10,
}

-- Krockläget: avskild korsning (utanför stadskartan, som testbanan)
ActivityConfig.CrashMode = {
	Origin = Vector3.new(6000, 0, -2200),
	RunUp = 420, -- startpunkt söder om korsningen
	Countdown = 3,
	TimeLimit = 25,
	AfterFirstImpact = 8,
	TrafficPerLane = 3,
	TrafficSpeed = 55,
	ImpactScore = 300,
	WreckScore = 2500,
	ChainBonus = 0.25, -- varje ytterligare kvaddning ökar multiplikatorn
	ScorePerKrona = 40,
	MaxReward = 600,
}

-- Kull med bilar
ActivityConfig.Tag = {
	Id = "Kull",
	Name = "Car Tag",
	Description = "Whoever is \"it\" chases the others. Shortest time as \"it\" wins.",
	Marker = Vector3.new(1768, 0, 376), -- vid Wrangelsgatan
	LobbyTime = 12,
	RoundTime = 120,
	TagDistance = 14,
	TagImmunity = 3,
	MinParticipants = 3, -- fylls ut med NPC-bilar
	SpawnRadius = 220,
	NpcSpeed = 70,
	Rewards = { 300, 150, 100 },
}

function ActivityConfig.Find(id: string): Activity?
	for _, activity in ActivityConfig.Activities do
		if activity.Id == id then
			return activity
		end
	end
	return nil
end

return ActivityConfig
