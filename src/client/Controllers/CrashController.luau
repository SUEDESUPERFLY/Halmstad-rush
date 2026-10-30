--!strict
-- Kopplar ihop krockar med effekter, kamera och meddelanden:
--  * Lätt smäll: gnistor och kameraskak.
--  * Kvaddad bil (WRECKED!): krockkamera med slow motion-känsla, plåtdelar, rök, sedan respawn.
--  * Takedown (servern avgör): popup, boost och en kort krockkamera på NPC-bilen.
--  * NPC-krockar (alla spelare ser): gnistor och plåtdelar där krocken skedde.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VehicleConfig = require(ReplicatedStorage.Shared.Config.VehicleConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CameraController = require(script.Parent.CameraController)
local EffectsController = require(script.Parent.EffectsController)
local VehicleController = require(script.Parent.VehicleController)

local C = VehicleConfig.Crash

local CrashController = {}

local EFFECT_RADIUS = 600 -- visa NPC-krockar bara i närheten

local function carColor(model: Model?): Color3
	local chassis = model and model.PrimaryPart
	return if chassis then chassis.Color else Color3.fromRGB(200, 60, 60)
end

local function onCrashed(strength: number, point: Vector3)
	EffectsController.Sparks(point, strength)
	CameraController.Shake(math.clamp(strength / 60, 0.2, 1.2), 0.35)
end

local function onWrecked(car: Model, point: Vector3)
	local chassis = car.PrimaryPart
	if not chassis then
		return
	end
	VehicleController.Popup:Fire("WRECKED!", "wreck")
	local velocity = chassis.AssemblyLinearVelocity
	local direction = if velocity.Magnitude > 1 then velocity.Unit else Vector3.yAxis
	EffectsController.Debris(point, direction, carColor(car), 10, C.WreckDuration * 0.7)
	EffectsController.Smoke(chassis.Position, 12)
	EffectsController.SlowMotionLook(C.WreckDuration)
	CameraController.CrashCam(chassis, C.WreckDuration)
	CameraController.Shake(1.2, 0.5)
end

local function onTakedown(npcChassis: unknown)
	if typeof(npcChassis) ~= "Instance" or not (npcChassis :: Instance):IsA("BasePart") then
		return
	end
	local chassis = npcChassis :: BasePart
	VehicleController.Popup:Fire("TAKEDOWN!", "takedown")
	VehicleController.AddBoost(C.ChargeTakedown)
	VehicleController.LockInput(C.TakedownCamDuration)
	EffectsController.SlowMotionLook(C.TakedownCamDuration)
	CameraController.CrashCam(chassis, C.TakedownCamDuration)
end

local function onCrashEffect(position: unknown, strength: unknown)
	if typeof(position) ~= "Vector3" or typeof(strength) ~= "number" then
		return
	end
	local car = VehicleController.GetCar()
	local chassis = car and car.PrimaryPart
	if chassis and (chassis.Position - (position :: Vector3)).Magnitude > EFFECT_RADIUS then
		return
	end
	EffectsController.Sparks(position :: Vector3, strength :: number)
	EffectsController.Smoke(position :: Vector3, 6)
	EffectsController.Debris(position :: Vector3, Vector3.yAxis, Color3.fromRGB(170, 170, 175), 6, 1)
end

function CrashController.Start()
	VehicleController.Crashed:Connect(onCrashed)
	VehicleController.Wrecked:Connect(onWrecked)
	Remotes.Get("Takedown").OnClientEvent:Connect(onTakedown)
	Remotes.Get("CrashEffect").OnClientEvent:Connect(onCrashEffect)
	-- När servern flyttar bilen (respawn, snabbresa) är kvaddningen över och
	-- den stora hastighetsändringen ska inte räknas som en krock.
	Remotes.Get("Notify").OnClientEvent:Connect(function(_text: unknown, kind: unknown)
		if kind == "respawn" or kind == "location" then
			VehicleController.EndWreck()
		end
	end)
end

return CrashController
