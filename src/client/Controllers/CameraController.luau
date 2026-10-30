--!strict
-- Jaktkamera bakom bilen. Följer färdriktningen (så drifter syns), vidgar FOV
-- med farten och skakar lätt vid boost.

local RunService = game:GetService("RunService")

local VehicleController = require(script.Parent.VehicleController)
local VehicleConfig = require(game:GetService("ReplicatedStorage").Shared.Config.VehicleConfig)

local T = VehicleConfig.Tuning

local CameraController = {}

local BIND_NAME = "HalmstadRushCamera"
local DISTANCE = 18
local HEIGHT = 6.5
local LOOK_AHEAD = 8
local BASE_FOV = 70
local SPEED_FOV = 22
local BOOST_FOV = 8

local camera = workspace.CurrentCamera
local smoothedDirection = Vector3.new(0, 0, -1)
local smoothedPosition: Vector3? = nil
local fov = BASE_FOV

local function blend(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

local function update(dt: number)
	local car = VehicleController.GetCar()
	local chassis = car and car.PrimaryPart
	if not chassis then
		return
	end
	camera = workspace.CurrentCamera
	local state = VehicleController.GetState()
	local cf = chassis.CFrame
	local velocity = chassis.AssemblyLinearVelocity
	local flatVelocity = velocity * Vector3.new(1, 0, 1)
	local flatLook = cf.LookVector * Vector3.new(1, 0, 1)
	if flatLook.Magnitude < 0.01 then
		flatLook = smoothedDirection
	end

	-- Riktning: blanda bilens nos och färdriktningen. Vid back: titta som bilen pekar.
	local desired = flatLook.Unit
	if flatVelocity.Magnitude > 20 and state.Speed > 0 then
		desired = (flatLook.Unit * 0.5 + flatVelocity.Unit * 0.5).Unit
	end
	smoothedDirection = (smoothedDirection:Lerp(desired, blend(5, dt)))
	if smoothedDirection.Magnitude < 0.01 then
		smoothedDirection = desired
	end
	smoothedDirection = smoothedDirection.Unit

	local carPos = cf.Position
	local targetPos = carPos - smoothedDirection * DISTANCE + Vector3.yAxis * HEIGHT
	if smoothedPosition == nil then
		smoothedPosition = targetPos
	end
	-- Följ snabbt i sidled men låt höjden släpa lite (mjukare vid hopp).
	local current = smoothedPosition :: Vector3
	local horizontal = current:Lerp(targetPos, blend(12, dt))
	local vertical = current.Y + (targetPos.Y - current.Y) * blend(6, dt)
	local position = Vector3.new(horizontal.X, vertical, horizontal.Z)
	smoothedPosition = position

	local lookAt = carPos + smoothedDirection * LOOK_AHEAD + Vector3.yAxis * 2
	local result = CFrame.lookAt(position, lookAt)

	if state.Boosting then
		local t = os.clock() * 40
		result *= CFrame.new(math.noise(t, 0) * 0.15, math.noise(0, t) * 0.15, 0)
	end
	camera.CFrame = result

	local speedRatio = math.clamp(math.abs(state.Speed) / T.BoostMaxSpeed, 0, 1)
	local targetFov = BASE_FOV + SPEED_FOV * speedRatio + (if state.Boosting then BOOST_FOV else 0)
	fov += (targetFov - fov) * blend(4, dt)
	camera.FieldOfView = fov
end

function CameraController.Start()
	VehicleController.Entered:Connect(function()
		smoothedPosition = nil
		camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		RunService:UnbindFromRenderStep(BIND_NAME)
		RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, update)
	end)

	VehicleController.Exited:Connect(function()
		RunService:UnbindFromRenderStep(BIND_NAME)
		camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = BASE_FOV
	end)
end

return CameraController
