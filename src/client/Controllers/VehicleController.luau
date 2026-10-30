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
local InputController = require(script.Parent.InputController)

local T = VehicleConfig.Tuning
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
}

local VehicleController = {}

VehicleController.Entered = Signal.new() -- (car: Model)
VehicleController.Exited = Signal.new()
VehicleController.Popup = Signal.new() -- (text: string, kind: string)

local car: Model? = nil
local chassis: BasePart? = nil
local wheels: { Wheel } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local state: DriveState = {
	Speed = 0,
	Boost = T.BoostStart,
	Boosting = false,
	Drifting = false,
	Airborne = false,
}

local steerSmoothed = 0
local currentGrip = T.Grip
local airTime = 0
local flippedTime = 0
local nearMissCooldown: { [Instance]: number } = {}
local lastResetRequest = 0
local resetRemote: RemoteEvent

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

function VehicleController.RequestReset()
	local now = os.clock()
	if not car or now - lastResetRequest < VehicleConfig.Server.ResetCooldown then
		return
	end
	lastResetRequest = now
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
				state.Boost = math.min(1, state.Boost + T.ChargeNearMiss)
				VehicleController.Popup:Fire("NEAR MISS!", "nearmiss")
			end
		end
	end
end

local function updateSuspension(cf: CFrame, mass: number): (number, Vector3)
	local root = chassis :: BasePart
	local up = cf.UpVector
	local rayLength = T.SuspensionRestLength + T.WheelRadius
	local maxForce = mass * workspace.Gravity * 4
	local grounded = 0
	local normalSum = Vector3.zero

	for _, wheel in wheels do
		local mountPos = wheel.Mount.WorldPosition
		local result = workspace:Raycast(mountPos, -up * rayLength, rayParams)
		if result then
			grounded += 1
			normalSum += result.Normal
			local springLength = math.max(result.Distance - T.WheelRadius, 0)
			local compression = T.SuspensionRestLength - springLength
			local pointVelocity = root:GetVelocityAtPosition(mountPos):Dot(up)
			local force = (mass / 4) * (T.SpringStrength * compression - T.SpringDamping * pointVelocity)
			wheel.Force.Force = up * math.clamp(force, 0, maxForce)
			wheel.SpringLength = springLength
		else
			wheel.Force.Force = Vector3.zero
			wheel.SpringLength = T.SuspensionRestLength
		end
	end

	return grounded, normalSum
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

	local input = InputController.GetDriveInput()
	local cf = root.CFrame
	local mass = root.AssemblyMass
	local velocity = root.AssemblyLinearVelocity
	local angular = root.AssemblyAngularVelocity

	local grounded, normalSum = updateSuspension(cf, mass)
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
		local maxSpeed = if wantsBoost then T.BoostMaxSpeed else T.MaxSpeed
		local acceleration = if wantsBoost then T.BoostAcceleration else T.Acceleration
		local throttle = if wantsBoost then 1 else input.Throttle
		if throttle > 0 and vF < maxSpeed then
			vF = math.min(vF + acceleration * throttle * dt, maxSpeed)
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

		local targetGrip = if state.Drifting then T.DriftGrip else T.Grip
		currentGrip += (targetGrip - currentGrip) * blend(T.GripRecovery, dt)
		vR *= math.exp(-currentGrip * dt)

		if state.Drifting and speedAbs > 30 then
			state.Boost = math.min(1, state.Boost + T.ChargeDriftPerSecond * dt)
		end

		-- Styrning: sätt girhastigheten runt markens normal
		local speedRatio = math.clamp(speedAbs / T.MaxSpeed, 0, 1)
		local lowSpeedFactor = math.clamp(speedAbs / T.TurnSpeedFull, 0, 1)
		local turn = T.TurnRate * lowSpeedFactor * (1 - (1 - T.HighSpeedTurnFactor) * speedRatio)
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
			state.Boost = math.min(1, state.Boost + T.ChargeAirPerSecond * dt)
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
