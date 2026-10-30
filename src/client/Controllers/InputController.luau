--!strict
-- Samlar körinput från tangentbord, handkontroll och pekskärm till ett gemensamt format.
--
-- Tangentbord: W/S eller pilar = gas/broms (back), A/D = styr, Space = handbroms/drift,
--              Shift = boost, R = återställ bilen.
-- Handkontroll: RT = gas, LT = broms, vänster spak = styr, X = drift, A = boost, Y = återställ.
-- Pekskärm: knappar på skärmen (skapas av TouchControls).

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)

export type DriveInput = {
	Throttle: number, -- 0..1
	Brake: number, -- 0..1
	Steer: number, -- -1 (vänster) .. 1 (höger)
	Handbrake: boolean,
	Boost: boolean,
}

local InputController = {}

InputController.ResetPressed = Signal.new()

-- Pekskärmsknapparna skriver hit
local touchState = {
	Throttle = false,
	Brake = false,
	Left = false,
	Right = false,
	Handbrake = false,
	Boost = false,
}

local gamepad = {
	Throttle = 0,
	Brake = 0,
	Steer = 0,
	Handbrake = false,
	Boost = false,
}

local STICK_DEADZONE = 0.15

function InputController.SetTouch(name: string, pressed: boolean)
	(touchState :: any)[name] = pressed
end

local function key(...: Enum.KeyCode): boolean
	for _, code in { ... } do
		if UserInputService:IsKeyDown(code) then
			return true
		end
	end
	return false
end

local function focused(): boolean
	return UserInputService:GetFocusedTextBox() ~= nil
end

function InputController.GetDriveInput(): DriveInput
	local typing = focused()
	local kThrottle = not typing and key(Enum.KeyCode.W, Enum.KeyCode.Up)
	local kBrake = not typing and key(Enum.KeyCode.S, Enum.KeyCode.Down)
	local kLeft = not typing and key(Enum.KeyCode.A, Enum.KeyCode.Left)
	local kRight = not typing and key(Enum.KeyCode.D, Enum.KeyCode.Right)
	local kHandbrake = not typing and key(Enum.KeyCode.Space)
	local kBoost = not typing and key(Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift)

	local throttle = math.max(if kThrottle or touchState.Throttle then 1 else 0, gamepad.Throttle)
	local brake = math.max(if kBrake or touchState.Brake then 1 else 0, gamepad.Brake)

	local steer = gamepad.Steer
	local digitalSteer = (if kRight or touchState.Right then 1 else 0) - (if kLeft or touchState.Left then 1 else 0)
	if digitalSteer ~= 0 then
		steer = digitalSteer
	end

	return {
		Throttle = throttle,
		Brake = brake,
		Steer = math.clamp(steer, -1, 1),
		Handbrake = kHandbrake or touchState.Handbrake or gamepad.Handbrake,
		Boost = kBoost or touchState.Boost or gamepad.Boost,
	}
end

function InputController.Start()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.ButtonY then
			InputController.ResetPressed:Fire()
		elseif input.KeyCode == Enum.KeyCode.ButtonX then
			gamepad.Handbrake = true
		elseif input.KeyCode == Enum.KeyCode.ButtonA then
			gamepad.Boost = true
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.ButtonX then
			gamepad.Handbrake = false
		elseif input.KeyCode == Enum.KeyCode.ButtonA then
			gamepad.Boost = false
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Gamepad1 then
			return
		end
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			local x = input.Position.X
			gamepad.Steer = if math.abs(x) > STICK_DEADZONE then x else 0
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			gamepad.Throttle = input.Position.Z
		elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
			gamepad.Brake = input.Position.Z
		end
	end)
end

return InputController
