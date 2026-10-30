--!strict
-- Ger varje spelare en bil, sätter föraren i den och vaktar fysiken.
--
-- Nätverksmodell: föraren äger bilens fysik (SetNetworkOwner) så att styrningen
-- känns direkt. Servern litar inte blint på det: den kontrollerar hastighet och
-- förflyttning och rättar till bilen om något ser fel ut.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local VehicleConfig = require(ReplicatedStorage.Shared.Config.VehicleConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CarBuilder = require(script.Parent.Parent.Vehicle.CarBuilder)

local ServerLimits = VehicleConfig.Server

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
	LastReset: number,
}

local VehicleService = {}

local cars: { [Player]: CarRecord } = {}
local usedSlots: { [number]: boolean } = {}
local spawnProvider: ((slot: number) -> CFrame)? = nil

local CAR_COLORS = {
	Color3.fromRGB(230, 60, 60),
	Color3.fromRGB(40, 130, 230),
	Color3.fromRGB(250, 190, 30),
	Color3.fromRGB(60, 190, 90),
	Color3.fromRGB(160, 80, 220),
	Color3.fromRGB(250, 120, 30),
}

-- Andra services (t.ex. testbanan, senare kartan) talar om var bilar ska starta.
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

local function flatYaw(cf: CFrame): CFrame
	local look = cf.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(Vector3.zero, look.Unit)
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
	-- Föraren ska inte påverka bilens tyngdpunkt.
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Massless = true
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

local function spawnCarFor(player: Player, character: Model)
	destroyCar(player)

	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root or character.Parent == nil then
		return
	end

	local slot = claimSlot()
	local model = CarBuilder.Build(CAR_COLORS[(slot - 1) % #CAR_COLORS + 1], player.UserId)
	local spawnCFrame = getSpawnCFrame(slot)
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
		LastReset = 0,
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

local function resetCar(record: CarRecord, toSpawn: boolean)
	local target
	if toSpawn then
		target = getSpawnCFrame(record.Slot)
	else
		local current = record.Chassis.CFrame
		target = CFrame.new(current.Position + Vector3.new(0, 5, 0)) * flatYaw(current)
	end
	forceMove(record, target)
end

local function onResetRequested(player: Player)
	local record = cars[player]
	if not record then
		return
	end
	local now = os.clock()
	if now - record.LastReset < ServerLimits.ResetCooldown then
		return
	end
	record.LastReset = now
	resetCar(record, false)
end

local function validateCar(record: CarRecord, now: number)
	local chassis = record.Chassis
	local position = chassis.Position
	local elapsed = now - record.LastCheck
	record.LastCheck = now

	if position.Y < ServerLimits.FallResetY then
		resetCar(record, true)
		return
	end

	if now < record.IgnoreChecksUntil then
		record.LastPosition = position
		return
	end

	-- Bara horisontellt: fritt fall får gå fort.
	local velocity = chassis.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local moved = (position - record.LastPosition) * Vector3.new(1, 0, 1)
	local maxMove = ServerLimits.HorizontalSpeedCap * elapsed * 1.5 + ServerLimits.TeleportSlack

	if moved.Magnitude > maxMove then
		warn(("[VehicleService] %s flyttade %.0f studs på %.2f s, återställer"):format(
			record.Player.Name,
			moved.Magnitude,
			elapsed
		))
		forceMove(record, CFrame.new(record.LastPosition + Vector3.new(0, 3, 0)) * flatYaw(chassis.CFrame))
		return
	end

	if horizontalSpeed > ServerLimits.HorizontalSpeedCap then
		record.SpeedStrikes += 1
		if record.SpeedStrikes >= ServerLimits.SpeedStrikesBeforeCorrection then
			warn(("[VehicleService] %s körde %.0f studs/s, bromsar"):format(record.Player.Name, horizontalSpeed))
			record.SpeedStrikes = 0
			local capped = velocity.Unit * ServerLimits.HorizontalSpeedCap * 0.8
			forceMove(record, chassis.CFrame, capped)
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

function VehicleService.Init()
	Remotes.Get("ResetVehicle").OnServerEvent:Connect(onResetRequested)
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
