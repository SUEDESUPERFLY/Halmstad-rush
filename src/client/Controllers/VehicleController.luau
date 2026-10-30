--!strict
-- Arkadfysik för bilen spelaren kör. Körs på klienten eftersom föraren äger
-- bilens fysik (nätverksägare). Servern vaktar hastighet och position.
--
-- Modell: chassit "svävar" på fyra raycast-fjädrar (VectorForce per hjul).
-- På marken styr vi farten direkt: framåtfart (gas/broms), sidledsfart (grepp/drift)
-- och girhastighet (styrning). I luften: lite luftkontroll och självrätning.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local VehicleConfig = require(ReplicatedStorage.Shared.Config.VehicleConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Suspension = require(ReplicatedStorage.Shared.Vehicle.Suspension)
local InputController = require(script.Parent.InputController)

local T = VehicleConfig.Tuning
local C = VehicleConfig.Crash
local player = Players.LocalPlayer

type Wheel = {
	Mount: Attachment,
	Force: VectorForce,
	Motor: Motor6D?,
	Front: boolean,
	SpringLength: number,
	Spin: number,
}

export type DriveState = {
	Speed: number, -- framåtfart i studs/s (negativ = backar)
	Boost: number, -- 0..1
	Boosting: boolean,
	Drifting: boolean,
	Airborne: boolean,
	Wrecked: boolean,
}

local VehicleController = {}

VehicleController.Entered = Signal.new() -- (car: Model)
VehicleController.Exited = Signal.new()
VehicleController.Popup = Signal.new() -- (text: string, kind: string)
VehicleController.Crashed = Signal.new() -- (strength: number, point: Vector3) lätt eller hård smäll
VehicleController.Wrecked = Signal.new() -- (car: Model, point: Vector3) bilen är kvaddad

local car: Model? = nil
local chassis: BasePart? = nil
local wheels: { Wheel } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true
-- Andra bilar är spöken: fjädringen ska inte kunna "stå" på dem.
rayParams.CollisionGroup = VehicleConfig.CollisionGroup

local state: DriveState = {
	Speed = 0,
	Boost = T.BoostStart,
	Boosting = false,
	Drifting = false,
	Airborne = false,
	Wrecked = false,
}

local steerSmoothed = 0
local currentGrip = T.Grip
local airTime = 0
local flippedTime = 0
local nearMissCooldown: { [Instance]: number } = {}
local lastResetRequest = 0
local resetRemote: RemoteEvent
local wreckRemote: RemoteEvent

-- Krockdetektering: hastigheten vi själva satte förra bildrutan jämförs med vad fysiken
-- gjort av den. En plötslig förändring i sidled/framåt = vi har kört in i något.
local lastSetVelocity: Vector3? = nil
local lastPosition: Vector3? = nil
local ignoreCrashUntil = 0
local inputLockUntil = 0

-- Bilens egenskaper (multiplikatorer) som servern satt som attribut på bilen.
local carStats = { Top = 1, Accel = 1, Handling = 1, Boost = 1, Charge = 1, Hill = 1 }
local attributeConnection: RBXScriptConnection? = nil

local function readCarStats(model: Model)
	local function get(name: string): number
		local value = model:GetAttribute(name)
		return if typeof(value) == "number" then value else 1
	end
	carStats.Top = get("TopSpeedMul")
	carStats.Accel = get("AccelerationMul")
	carStats.Handling = get("HandlingMul")
	carStats.Boost = get("BoostMul")
	carStats.Charge = get("ChargeMul")
	carStats.Hill = get("HillAssistMul")
end
local lockedThrottle = 0
local lockHold = false

local function moveToward(value: number, target: number, maxDelta: number): number
	if value < target then
		return math.min(value + maxDelta, target)
	end
	return math.max(value - maxDelta, target)
end

local function blend(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

function VehicleController.GetState(): DriveState
	return state
end

function VehicleController.GetCar(): Model?
	return car
end

-- Krockar räknas inte en stund (efter teleport, respawn eller återställning).
function VehicleController.IgnoreCrashes(seconds: number)
	ignoreCrashUntil = math.max(ignoreCrashUntil, os.clock() + seconds)
	lastSetVelocity = nil
end

-- Låser styrningen en stund. Rakt fram med samma gas (takedown-kameran), eller
-- `hold` = stå still med bromsen i (nedräkning före race).
function VehicleController.LockInput(seconds: number, hold: boolean?)
	inputLockUntil = os.clock() + seconds
	lockHold = hold == true
	lockedThrottle = if lockHold then 0 else InputController.GetDriveInput().Throttle
end

function VehicleController.AddBoost(amount: number)
	state.Boost = math.clamp(state.Boost + amount, 0, 1)
end

-- Avslutar kvaddat läge (anropas när servern har flyttat tillbaka bilen till gatan).
function VehicleController.EndWreck()
	state.Wrecked = false
	VehicleController.IgnoreCrashes(C.IgnoreAfterTeleport)
end

function VehicleController.RequestReset()
	local now = os.clock()
	if not car or now - lastResetRequest < VehicleConfig.Server.ResetCooldown then
		return
	end
	lastResetRequest = now
	VehicleController.IgnoreCrashes(C.IgnoreAfterTeleport)
	resetRemote:FireServer()
end

local function setPlayerControlsEnabled(enabled: boolean)
	local ok, playerModule = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: ModuleScript) :: any
	end)
	if ok and playerModule then
		local controls = playerModule:GetControls()
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end
end

local function exitCar()
	if not car then
		return
	end
	for _, wheel in wheels do
		wheel.Force.Force = Vector3.zero
	end
	car = nil
	chassis = nil
	wheels = {}
	if attributeConnection then
		attributeConnection:Disconnect()
		attributeConnection = nil
	end
	setPlayerControlsEnabled(true)
	VehicleController.Exited:Fire()
end

local function enterCar(model: Model)
	if car == model then
		return
	end
	exitCar()
	local root = model:WaitForChild("Chassis", 5) :: BasePart?
	if not root or not model.Parent then
		return
	end
	car = model
	chassis = root
	wheels = {}
	readCarStats(model)
	attributeConnection = model.AttributeChanged:Connect(function()
		readCarStats(model)
	end)
	for _, child in root:GetChildren() do
		if child:IsA("Attachment") and child.Name:sub(1, 6) == "Mount_" then
			local force = child:FindFirstChild("Spring") :: VectorForce
			table.insert(wheels, {
				Mount = child,
				Force = force,
				Motor = child:FindFirstChild("WheelMotor") :: Motor6D?,
				Front = child:GetAttribute("Front") == true,
				SpringLength = T.VisualSpringLength,
				Spin = 0,
			})
		end
	end
	local filter: { Instance } = { model }
	if player.Character then
		table.insert(filter, player.Character)
	end
	rayParams.FilterDescendantsInstances = filter

	state.Speed = 0
	state.Drifting = false
	state.Boosting = false
	steerSmoothed = 0
	currentGrip = T.Grip
	airTime = 0
	flippedTime = 0
	state.Wrecked = false
	VehicleController.IgnoreCrashes(C.IgnoreAfterTeleport)

	setPlayerControlsEnabled(false)
	VehicleController.Entered:Fire(model)
end

local function onSeatChanged(seatPart: BasePart?)
	if seatPart and seatPart.Parent and seatPart.Parent:GetAttribute("IsHalmstadCar") then
		local model = seatPart.Parent :: Model
		if model:GetAttribute("OwnerUserId") == player.UserId then
			enterCar(model)
			return
		end
	end
	exitCar()
end

local function checkNearMiss(cf: CFrame, speed: number)
	if speed < T.NearMissMinSpeed then
		return
	end
	local origin = cf.Position
	local halfWidth = VehicleConfig.Geometry.ChassisSize.X / 2
	local reach = halfWidth + T.NearMissDistance
	local now = os.clock()
	local directions = {
		cf.RightVector,
		-cf.RightVector,
		(cf.RightVector - cf.LookVector * 0.6).Unit,
		(-cf.RightVector - cf.LookVector * 0.6).Unit,
	}
	for _, direction in directions do
		local result = workspace:Raycast(origin, direction * reach, rayParams)
		if result and result.Instance:GetAttribute("Obstacle") then
			local hit = result.Instance
			if (nearMissCooldown[hit] or 0) < now then
				nearMissCooldown[hit] = now + T.NearMissCooldown
				state.Boost = math.min(1, state.Boost + T.ChargeNearMiss * carStats.Charge)
				VehicleController.Popup:Fire("NEAR MISS!", "nearmiss")
			end
		end
	end
end

local function wreck(point: Vector3)
	if state.Wrecked or not car then
		return
	end
	state.Wrecked = true
	state.Boosting = false
	state.Drifting = false
	VehicleController.Wrecked:Fire(car, point)
	task.delay(C.WreckDuration, function()
		if state.Wrecked then
			wreckRemote:FireServer()
			-- Om servern av någon anledning inte flyttar oss: släpp läget ändå.
			task.delay(1.5, function()
				if state.Wrecked then
					VehicleController.EndWreck()
				end
			end)
		end
	end)
end

local function detectCrash(position: Vector3, velocity: Vector3, now: number)
	local previous = lastSetVelocity
	local previousPosition = lastPosition
	lastPosition = position
	if not previous or not previousPosition or now < ignoreCrashUntil or state.Wrecked then
		return
	end
	if (position - previousPosition).Magnitude > C.TeleportDistance then
		VehicleController.IgnoreCrashes(C.IgnoreAfterTeleport)
		return
	end
	local before = previous * Vector3.new(1, 0, 1)
	local after = velocity * Vector3.new(1, 0, 1)
	local change = (after - before).Magnitude
	if change < C.LightImpact then
		return
	end
	local point = position + (if before.Magnitude > 1 then before.Unit else Vector3.zero) * 5
	VehicleController.Crashed:Fire(change, point)
	local slowedDown = before.Magnitude - after.Magnitude > change * 0.5
	if change >= C.WreckImpact and before.Magnitude >= C.WreckMinSpeed and slowedDown then
		wreck(point)
	end
end

local function updateWheelVisuals(dt: number, forwardSpeed: number)
	for _, wheel in wheels do
		local motor = wheel.Motor
		if motor then
			wheel.Spin = (wheel.Spin - forwardSpeed / T.WheelRadius * dt) % (math.pi * 2)
			local steerAngle = if wheel.Front then -steerSmoothed * T.MaxSteerAngle else 0
			motor.Transform = CFrame.new(0, T.VisualSpringLength - wheel.SpringLength, 0)
				* CFrame.Angles(0, steerAngle, 0)
				* CFrame.Angles(wheel.Spin, 0, 0)
		end
	end
end

local function step(dt: number)
	local root = chassis
	if not root or not car or not car.Parent then
		return
	end
	dt = math.min(dt, 1 / 30)

	local now = os.clock()
	local input = InputController.GetDriveInput()
	if now < inputLockUntil then
		-- (Broms vid stillastående = back, så "håll" är bara ingen gas.)
		input = { Throttle = lockedThrottle, Brake = 0, Steer = 0, Handbrake = false, Boost = false }
	end
	local cf = root.CFrame
	local velocity = root.AssemblyLinearVelocity
	local angular = root.AssemblyAngularVelocity

	detectCrash(cf.Position, velocity, now)
	if state.Wrecked then
		-- Kvaddad: ingen styrning eller fjädring, bilen får tumla fritt tills respawn.
		Suspension.Release(wheels)
		lastSetVelocity = nil
		state.Speed = velocity:Dot(cf.LookVector)
		return
	end

	-- Under race byter servern kollisionsgrupp (RaceCars); strålarna ska följa med.
	rayParams.CollisionGroup = root.CollisionGroup
	local grounded, normalSum = Suspension.Update(root, wheels, rayParams)
	steerSmoothed = moveToward(steerSmoothed, input.Steer, T.SteerSpeed * dt)

	local wantsBoost = input.Boost and state.Boost > 0
	state.Boosting = wantsBoost
	if wantsBoost then
		state.Boost = math.max(0, state.Boost - T.BoostDrainPerSecond * dt)
	end

	if grounded >= 2 then
		if state.Airborne and airTime >= T.MinAirTimeForPopup then
			VehicleController.Popup:Fire(("AIR %.1fs"):format(airTime), "air")
		end
		state.Airborne = false
		airTime = 0

		local normal = (normalSum / grounded).Unit
		local forward = cf.LookVector - normal * cf.LookVector:Dot(normal)
		forward = if forward.Magnitude > 1e-3 then forward.Unit else cf.LookVector
		local right = forward:Cross(normal)

		local vF = velocity:Dot(forward)
		local vR = velocity:Dot(right)
		local vN = velocity:Dot(normal)

		-- Gas, broms, back
		local maxSpeed = (if wantsBoost then T.BoostMaxSpeed * carStats.Boost else T.MaxSpeed) * carStats.Top
		local acceleration = (if wantsBoost then T.BoostAcceleration else T.Acceleration) * carStats.Accel
		local throttle = if wantsBoost then 1 else input.Throttle
		if throttle > 0 and vF < maxSpeed then
			vF = math.min(vF + acceleration * throttle * dt, maxSpeed)
		end
		-- Backhjälp: i uppförsbacke tar vi bort en del av tyngdkraften när man gasar.
		if throttle > 0 and forward.Y > 0 then
			vF += workspace.Gravity * forward.Y * math.min(T.HillAssist * carStats.Hill, 0.95) * throttle * dt
		end
		if input.Brake > 0 then
			if vF > 2 then
				vF = math.max(vF - T.BrakeDeceleration * input.Brake * dt, 0)
			else
				vF = math.max(vF - T.ReverseAcceleration * input.Brake * dt, -T.ReverseMaxSpeed)
			end
		end
		if throttle == 0 and input.Brake == 0 then
			vF *= math.exp(-T.Drag * dt)
			vF = moveToward(vF, 0, T.RollingResistance * dt)
		end
		if vF > maxSpeed then
			vF = math.max(maxSpeed, vF - T.OverspeedDecel * dt)
		end

		-- Drift
		local speedAbs = math.abs(vF)
		if input.Handbrake and speedAbs > T.DriftMinSpeed then
			if not state.Drifting then
				VehicleController.Popup:Fire("DRIFT!", "drift")
			end
			state.Drifting = true
		elseif state.Drifting then
			local stillSliding = math.abs(vR) > T.DriftExitLateral and speedAbs > T.DriftMinSpeed * 0.6
			if not stillSliding or input.Steer == 0 then
				state.Drifting = false
			end
		end
		if input.Handbrake then
			vF = moveToward(vF, 0, T.HandbrakeDecel * dt)
		end

		local targetGrip = if state.Drifting then T.DriftGrip else T.Grip * carStats.Handling
		currentGrip += (targetGrip - currentGrip) * blend(T.GripRecovery, dt)
		vR *= math.exp(-currentGrip * dt)

		if state.Drifting and speedAbs > 30 then
			state.Boost = math.min(1, state.Boost + T.ChargeDriftPerSecond * carStats.Charge * dt)
		end

		-- Styrning: sätt girhastigheten runt markens normal
		local speedRatio = math.clamp(speedAbs / T.MaxSpeed, 0, 1)
		local lowSpeedFactor = math.clamp(speedAbs / T.TurnSpeedFull, 0, 1)
		local turn = T.TurnRate * carStats.Handling * lowSpeedFactor * (1 - (1 - T.HighSpeedTurnFactor) * speedRatio)
		if state.Drifting then
			turn *= 1 + T.DriftTurnBonus
		end
		local direction = if vF >= 0 then 1 else -1
		local targetYaw = -steerSmoothed * turn * direction
		local currentYaw = angular:Dot(normal)
		local newYaw = currentYaw + (targetYaw - currentYaw) * blend(T.YawResponse, dt)
		angular += normal * (newYaw - currentYaw)

		velocity = forward * vF + right * vR + normal * vN
		state.Speed = vF
	else
		state.Airborne = grounded == 0
		state.Drifting = false
		if grounded == 0 then
			airTime += dt
			state.Boost = math.min(1, state.Boost + T.ChargeAirPerSecond * carStats.Charge * dt)
		end

		-- Luftkontroll (gir) och självrätning
		local up = cf.UpVector
		local currentYaw = angular:Dot(up)
		local targetYaw = -input.Steer * T.AirYawControl
		angular += up * ((targetYaw - currentYaw) * blend(2, dt))

		local tiltAxis = up:Cross(Vector3.yAxis)
		angular += tiltAxis * T.AirUprightStrength * dt
		local yawPart = Vector3.yAxis * angular:Dot(Vector3.yAxis)
		angular = yawPart + (angular - yawPart) * math.exp(-T.AirTiltDamping * dt)

		velocity -= Vector3.yAxis * T.ExtraGravity * dt
		state.Speed = velocity:Dot(cf.LookVector)
	end

	root.AssemblyLinearVelocity = velocity
	root.AssemblyAngularVelocity = angular
	lastSetVelocity = velocity

	checkNearMiss(cf, math.abs(state.Speed))
	updateWheelVisuals(dt, state.Speed)

	-- Ligger bilen på sidan/taket och står still? Återställ automatiskt.
	if cf.UpVector.Y < 0.3 and velocity.Magnitude < 8 then
		flippedTime += dt
		if flippedTime > T.FlippedResetDelay then
			flippedTime = 0
			VehicleController.RequestReset()
		end
	else
		flippedTime = 0
	end

	for instance, untilTime in nearMissCooldown do
		if untilTime < os.clock() then
			nearMissCooldown[instance] = nil
		end
	end
end

function VehicleController.Start()
	resetRemote = Remotes.Get("ResetVehicle")
	wreckRemote = Remotes.Get("ReportWreck")
	InputController.ResetPressed:Connect(VehicleController.RequestReset)
	RunService.PreSimulation:Connect(step)
end

-- Anropas sist av init.client, när kamera och UI redan lyssnar på Entered/Exited.
function VehicleController.Begin()
	local function onCharacter(character: Model)
		exitCar()
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
			onSeatChanged(humanoid.SeatPart)
		end)
		onSeatChanged(humanoid.SeatPart)
	end

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

return VehicleController
