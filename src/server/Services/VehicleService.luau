--!strict
-- Ger varje spelare en bil, sätter föraren i den och vaktar fysiken.
--
-- Nätverksmodell: föraren äger bilens fysik (SetNetworkOwner) så att styrningen
-- känns direkt. Servern litar inte blint på det: den kontrollerar hastighet och
-- förflyttning och rättar till bilen om något ser fel ut.
--
-- Spökläge: alla bilar (och förare) ligger i kollisionsgruppen "Cars", som inte
-- krockar med sig själv. Krockar mellan spelare slås på per läge i senare faser.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CarCatalog = require(ReplicatedStorage.Shared.Config.CarCatalog)
local VehicleConfig = require(ReplicatedStorage.Shared.Config.VehicleConfig)
local CarBuilder = require(script.Parent.Parent.Vehicle.CarBuilder)
local DataService = require(script.Parent.DataService)

local ServerLimits = VehicleConfig.Server
local CAR_GROUP = VehicleConfig.CollisionGroup

type CarRecord = {
	Player: Player,
	Model: Model,
	Chassis: BasePart,
	Seat: Seat,
	Slot: number,
	LastPosition: Vector3,
	LastCheck: number,
	SpeedStrikes: number,
	IgnoreChecksUntil: number,
	CollisionGroup: string,
	SpeedCap: number, -- bilens högsta tillåtna fart (med uppgraderingar)
}

local VehicleService = {}

local cars: { [Player]: CarRecord } = {}
local usedSlots: { [number]: boolean } = {}
local spawnProvider: ((slot: number) -> CFrame)? = nil

-- Bilens egenskaper som attribut (klienten läser dem för sin fysik).
local STAT_ATTRIBUTES = {
	TopSpeed = "TopSpeedMul",
	Acceleration = "AccelerationMul",
	Handling = "HandlingMul",
	Boost = "BoostMul",
	Charge = "ChargeMul",
	HillAssist = "HillAssistMul",
}

-- Vald bil, färg och uppgraderingar från profilen (standardbilen om profilen saknas).
local function carSettings(player: Player): (string, Color3, CarCatalog.Stats)
	local data = DataService.WaitForData(player)
	local carId = if data then data.SelectedCar else CarCatalog.StarterCar
	local carData = data and data.OwnedCars[carId]
	local color = CarCatalog.FindColor(if carData then carData.Color else CarCatalog.DefaultColor)
	local stats = CarCatalog.ComputeStats(carId, carData and carData.Upgrades)
	return carId, (color or CarCatalog.Colors[1]).Color, stats
end

local function applyStats(model: Model, carId: string, stats: CarCatalog.Stats): number
	model:SetAttribute("CarId", carId)
	for stat, attribute in STAT_ATTRIBUTES do
		model:SetAttribute(attribute, (stats :: any)[stat])
	end
	return ServerLimits.HorizontalSpeedCap * CarCatalog.MaxBoostMultiplier(stats)
end

-- Kartan (eller testbanan) talar om var nya bilar ska starta.
function VehicleService.SetSpawnProvider(provider: (slot: number) -> CFrame)
	spawnProvider = provider
end

local function getSpawnCFrame(slot: number): CFrame
	if spawnProvider then
		return spawnProvider(slot)
	end
	return CFrame.new(slot * 12, 5, 0)
end

local function claimSlot(): number
	local slot = 1
	while usedSlots[slot] do
		slot += 1
	end
	usedSlots[slot] = true
	return slot
end

local function setCollisionGroup(root: Instance, group: string)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = group
		end
	end
end

-- Flyttar en bil som klienten äger. Servern tar tillfälligt över ägarskapet
-- så att flytten inte skrivs över av klientens simulering.
local function forceMove(record: CarRecord, target: CFrame, velocity: Vector3?)
	local chassis = record.Chassis
	chassis:SetNetworkOwner(nil)
	record.Model:PivotTo(target)
	chassis.AssemblyLinearVelocity = velocity or Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero
	record.LastPosition = target.Position
	record.IgnoreChecksUntil = os.clock() + 1
	task.delay(0.15, function()
		if cars[record.Player] == record and chassis.Parent then
			chassis:SetNetworkOwner(record.Player)
		end
	end)
end

local function flatYaw(cf: CFrame): CFrame
	local look = cf.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(Vector3.zero, look.Unit)
end

local function destroyCar(player: Player)
	local record = cars[player]
	if not record then
		return
	end
	cars[player] = nil
	usedSlots[record.Slot] = nil
	record.Model:Destroy()
end

local function seatDriver(record: CarRecord, humanoid: Humanoid)
	if record.Seat.Occupant == humanoid then
		return
	end
	local character = humanoid.Parent :: Model
	-- Föraren ska inte påverka bilens tyngdpunkt och ska vara spöke precis som bilen.
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Massless = true
			descendant.CollisionGroup = record.CollisionGroup
		end
	end
	character:PivotTo(record.Seat.CFrame + Vector3.new(0, 3, 0))
	record.Seat:Sit(humanoid)
	task.defer(function()
		if record.Chassis.Parent then
			record.Chassis:SetNetworkOwner(record.Player)
		end
	end)
end

local function createCar(player: Player, character: Model, at: CFrame?, group: string?)
	destroyCar(player)

	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root or character.Parent == nil then
		return
	end

	local carId, color, stats = carSettings(player)
	if player.Character ~= character or character.Parent == nil then
		return
	end
	local car = CarCatalog.FindCar(carId) or CarCatalog.Cars[1]
	local slot = claimSlot()
	local model = CarBuilder.Build(color, player.UserId, car.Style)
	local speedCap = applyStats(model, carId, stats)
	if player:GetAttribute("Pass_Underglow") == true then
		CarBuilder.AddUnderglow(model, Color3.fromRGB(80, 220, 255))
	end
	local collisionGroup = group or CAR_GROUP
	setCollisionGroup(model, collisionGroup)
	local spawnCFrame = at or getSpawnCFrame(slot)
	model:PivotTo(spawnCFrame)
	model.Parent = workspace

	local record: CarRecord = {
		Player = player,
		Model = model,
		Chassis = model.PrimaryPart :: BasePart,
		Seat = model:FindFirstChild("DriverSeat") :: Seat,
		Slot = slot,
		LastPosition = spawnCFrame.Position,
		LastCheck = os.clock(),
		SpeedStrikes = 0,
		IgnoreChecksUntil = os.clock() + 2,
		CollisionGroup = collisionGroup,
		SpeedCap = speedCap,
	}
	cars[player] = record
	record.Chassis:SetNetworkOwner(player)

	seatDriver(record, humanoid)

	-- Om föraren av någon anledning åker ur sätet sätter vi tillbaka hen.
	humanoid.Seated:Connect(function(isSeated: boolean)
		if isSeated or cars[player] ~= record or humanoid.Health <= 0 then
			return
		end
		task.delay(0.5, function()
			if cars[player] == record and humanoid.Parent and humanoid.Health > 0 then
				seatDriver(record, humanoid)
			end
		end)
	end)

	humanoid.Died:Connect(function()
		if cars[player] == record then
			destroyCar(player)
		end
	end)
end

local function spawnCarFor(player: Player, character: Model)
	createCar(player, character, nil, nil)
end

local function validateCar(record: CarRecord, now: number)
	local chassis = record.Chassis
	local position = chassis.Position
	local elapsed = now - record.LastCheck
	record.LastCheck = now

	if now < record.IgnoreChecksUntil then
		record.LastPosition = position
		return
	end

	-- Bara horisontellt: fritt fall får gå fort.
	local velocity = chassis.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local moved = (position - record.LastPosition) * Vector3.new(1, 0, 1)
	local maxMove = record.SpeedCap * elapsed * 1.5 + ServerLimits.TeleportSlack

	if moved.Magnitude > maxMove then
		warn(("[VehicleService] %s flyttade %.0f studs på %.2f s, återställer"):format(
			record.Player.Name,
			moved.Magnitude,
			elapsed
		))
		forceMove(record, CFrame.new(record.LastPosition + Vector3.new(0, 3, 0)) * flatYaw(chassis.CFrame))
		return
	end

	if horizontalSpeed > record.SpeedCap then
		record.SpeedStrikes += 1
		if record.SpeedStrikes >= ServerLimits.SpeedStrikesBeforeCorrection then
			warn(("[VehicleService] %s körde %.0f studs/s, bromsar"):format(record.Player.Name, horizontalSpeed))
			record.SpeedStrikes = 0
			forceMove(record, chassis.CFrame, velocity.Unit * record.SpeedCap * 0.8)
			return
		end
	else
		record.SpeedStrikes = 0
	end

	record.LastPosition = position
end

function VehicleService.GetCar(player: Player): Model?
	local record = cars[player]
	return record and record.Model
end

-- Alla aktiva bilar, för t.ex. RespawnService. Ändra inte i tabellen.
function VehicleService.GetCars(): { [Player]: Model }
	local result = {}
	for player, record in cars do
		if record.Chassis.Parent then
			result[player] = record.Model
		end
	end
	return result
end

-- Flyttar spelarens bil på ett sätt som servervalideringen godkänner.
function VehicleService.MoveCar(player: Player, target: CFrame): boolean
	local record = cars[player]
	if not record then
		return false
	end
	forceMove(record, target)
	return true
end

-- Byter kollisionsgrupp för spelarens bil och förare (t.ex. "RaceCars" under ett race).
-- Utan grupp återgår bilen till spökläget för fri körning.
function VehicleService.SetCollisionGroup(player: Player, group: string?)
	local record = cars[player]
	if not record then
		return
	end
	record.CollisionGroup = group or CAR_GROUP
	setCollisionGroup(record.Model, record.CollisionGroup)
	if player.Character then
		setCollisionGroup(player.Character, record.CollisionGroup)
	end
end

-- Byter till spelarens valda bil (efter köp eller byte i garaget) där den gamla stod.
function VehicleService.RebuildCar(player: Player)
	local record = cars[player]
	local character = player.Character
	if not record or not character then
		return
	end
	local at = CFrame.new(record.Chassis.Position + Vector3.new(0, 4, 0)) * flatYaw(record.Chassis.CFrame)
	task.spawn(createCar, player, character, at, record.CollisionGroup)
end

-- Uppdaterar egenskaper och lack på bilen som redan finns (efter uppgradering eller lackering).
function VehicleService.RefreshCar(player: Player)
	local record = cars[player]
	if not record then
		return
	end
	local carId, color, stats = carSettings(player)
	if record.Model:GetAttribute("CarId") ~= carId then
		VehicleService.RebuildCar(player)
		return
	end
	record.SpeedCap = applyStats(record.Model, carId, stats)
	CarBuilder.Paint(record.Model, color)
end

-- Ställer bilen på hjulen där den står, vänd åt samma håll.
function VehicleService.UprightCar(player: Player): boolean
	local record = cars[player]
	if not record then
		return false
	end
	local current = record.Chassis.CFrame
	forceMove(record, CFrame.new(current.Position + Vector3.new(0, 5, 0)) * flatYaw(current))
	return true
end

function VehicleService.Init()
	if not PhysicsService:IsCollisionGroupRegistered(CAR_GROUP) then
		PhysicsService:RegisterCollisionGroup(CAR_GROUP)
	end
	PhysicsService:CollisionGroupSetCollidable(CAR_GROUP, CAR_GROUP, false)
end

function VehicleService.Start()
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			spawnCarFor(player, character)
		end)
		if player.Character then
			task.spawn(spawnCarFor, player, player.Character)
		end
	end

	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(destroyCar)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < ServerLimits.CheckInterval then
			return
		end
		accumulator = 0
		local now = os.clock()
		for _, record in cars do
			if record.Chassis.Parent then
				validateCar(record, now)
			end
		end
	end)
end

return VehicleService
