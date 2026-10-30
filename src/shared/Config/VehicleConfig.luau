--!strict
-- Alla siffror som styr bilens känsla. Justera här, inte i fysikkoden.
-- Enheter: studs, sekunder. 1 stud/s ≈ 1 km/h i HUD:en (1 stud ≈ 0,28 m).

local VehicleConfig = {}

VehicleConfig.Tuning = {
	-- Fjädring (raycast-hjul)
	SuspensionRestLength = 2.0, -- max avstånd montering -> hjulcentrum
	SpringStrength = 196, -- jämvikt: kompression = Gravity / SpringStrength ≈ 1 stud
	SpringDamping = 18, -- ~0,65 av kritisk dämpning: lite studsig arkadkänsla
	WheelRadius = 1.1,
	VisualSpringLength = 1.0, -- fjäderlängd i vila, används för hjulens grundposition
	MaxSteerAngle = math.rad(28), -- endast visuellt (framhjulen)

	-- Motor
	MaxSpeed = 110,
	Acceleration = 48,
	BrakeDeceleration = 110,
	ReverseAcceleration = 40,
	ReverseMaxSpeed = 35,
	Drag = 0.35, -- exponentiell fartförlust utan gas (per sekund)
	RollingResistance = 6,
	OverspeedDecel = 25, -- hur snabbt farten sjunker tillbaka efter boost

	-- Styrning
	TurnRate = 2.4, -- rad/s vid full styrning
	TurnSpeedFull = 25, -- under denna fart minskar svängförmågan (bilen svänger inte stillastående)
	HighSpeedTurnFactor = 0.55, -- andel svängförmåga kvar vid toppfart
	SteerSpeed = 5, -- hur snabbt rattutslaget når målet (per sekund)
	YawResponse = 10,

	-- Grepp och drift
	Grip = 10, -- hur snabbt sidledsfart dör ut (per sekund)
	DriftGrip = 1.3,
	GripRecovery = 4,
	DriftTurnBonus = 0.6,
	DriftMinSpeed = 35,
	DriftExitLateral = 8,
	HandbrakeDecel = 12,
	HillAssist = 0.6, -- andel av tyngdkraften i uppförsbacke som tas bort när man gasar (arkadkänsla)

	-- Luft
	AirYawControl = 2.0,
	AirUprightStrength = 7,
	AirTiltDamping = 1.5,
	ExtraGravity = 45, -- extra tyngd i luften för mer "punchiga" hopp

	-- Boost (Burnout-stil)
	BoostMaxSpeed = 165,
	BoostAcceleration = 85,
	BoostDrainPerSecond = 0.3,
	BoostStart = 0.5, -- startvärde i fas 1 så att det går att testa direkt
	ChargeDriftPerSecond = 0.18,
	ChargeAirPerSecond = 0.25,
	ChargeNearMiss = 0.12,
	NearMissDistance = 5,
	NearMissMinSpeed = 60,
	NearMissCooldown = 1.5,
	MinAirTimeForPopup = 0.6,

	-- Auto-återställning när bilen ligger på taket
	FlippedResetDelay = 2.5,
}

-- Gränser som servern kontrollerar. Klienten simulerar fysiken, servern håller koll.
VehicleConfig.Server = {
	HorizontalSpeedCap = 165 * 1.25,
	CheckInterval = 0.25,
	SpeedStrikesBeforeCorrection = 3,
	TeleportSlack = 12, -- extra studs som tolereras per kontroll
	ResetCooldown = 1.5,
}

-- Respawn och snabbresa (RespawnService)
VehicleConfig.Respawn = {
	DoubleResetWindow = 4, -- tryck R två gånger inom detta antal sekunder = till närmaste väg
	TeleportCooldown = 5,
	CheckInterval = 0.25,
	WaterMargin = 1, -- respawn när chassit är så här nära vattenytan
	RoadPointSpacing = 50,
}

-- Krockar och takedowns (fas 3)
VehicleConfig.Crash = {
	LightImpact = 30, -- studs/s fartändring på en bildruta: gnistor och skak
	WreckImpact = 70, -- hård smäll: bilen kvaddas
	WreckMinSpeed = 55, -- man måste ha kört minst så här fort för att kvaddas
	WreckDuration = 1.8, -- krockkamerans längd innan respawn
	TakedownCamDuration = 1.1,
	ChargeTakedown = 0.3, -- boost för en takedown
	TeleportDistance = 25, -- större hopp än så på en bildruta = teleport, inte krock
	IgnoreAfterTeleport = 1.5,
	ReportWreckCooldown = 2, -- servern: minsta tid mellan två respawn efter kvaddning
}

-- NPC-bilar som kör runt på huvudgatorna (fas 3)
VehicleConfig.Npc = {
	CollisionGroup = "NPCCars",
	PerRoute = { StoraRingen = 7, Vastra = 3 },
	CruiseSpeed = 62,
	Acceleration = 35,
	Grip = 8,
	TurnGain = 3,
	MaxYawRate = 1.8,
	YawResponse = 6,
	WaypointRadius = 16,
	ImpactThreshold = 22, -- fartändring som räknas som en smäll
	WreckImpact = 38, -- smäll som kvaddar NPC-bilen
	HitRadius = 22, -- spelarbil inom detta avstånd vid smällen = den som knuffade
	TakedownWindow = 3, -- sekunder efter knuffen som en kvaddning räknas som takedown
	WreckDuration = 4,
	StuckTime = 5,
	MinSpawnDistance = 120, -- respawna inte närmare spelare än så
	Colors = {
		Color3.fromRGB(235, 235, 235),
		Color3.fromRGB(70, 70, 75),
		Color3.fromRGB(150, 160, 170),
		Color3.fromRGB(30, 60, 110),
		Color3.fromRGB(120, 30, 30),
		Color3.fromRGB(200, 190, 160),
	},
}

-- Kollisionsgrupp för bilar och förare. Krockar inte med sig själv (spökläge i fri roam).
VehicleConfig.CollisionGroup = "Cars"

-- Bilens geometri (relativt chassits centrum). Framåt = -Z.
VehicleConfig.Geometry = {
	ChassisSize = Vector3.new(6, 1.6, 11),
	WheelMounts = {
		{ Name = "FL", Offset = Vector3.new(-3.3, -0.3, -3.8), Front = true },
		{ Name = "FR", Offset = Vector3.new(3.3, -0.3, -3.8), Front = true },
		{ Name = "RL", Offset = Vector3.new(-3.3, -0.3, 3.8), Front = false },
		{ Name = "RR", Offset = Vector3.new(3.3, -0.3, 3.8), Front = false },
	},
	WheelWidth = 1.2,
}

return VehicleConfig
