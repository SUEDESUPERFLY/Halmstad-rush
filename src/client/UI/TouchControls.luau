--!strict
-- Körknappar för pekskärm. Visas bara på enheter med touch och bara när man kör.
-- Vänster: styr vänster/höger. Höger: gas, broms, drift, boost. Uppe till höger: återställ.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local InputController = require(script.Parent.Parent.Controllers.InputController)
local VehicleController = require(script.Parent.Parent.Controllers.VehicleController)

local TouchControls = {}

local gui: ScreenGui

local function makeButton(name: string, text: string, size: number, position: UDim2, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = text
	button.AutoButtonColor = false
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Size = UDim2.fromOffset(size, size)
	button.Position = position
	button.BackgroundColor3 = color
	button.BackgroundTransparency = 0.35
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamBlack
	button.TextScaled = true
	button.Parent = gui

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = button

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.18, 0)
	padding.PaddingRight = UDim.new(0.18, 0)
	padding.PaddingTop = UDim.new(0.3, 0)
	padding.PaddingBottom = UDim.new(0.3, 0)
	padding.Parent = button

	return button
end

-- Håll-knapp: aktiv så länge ett finger ligger på den (fungerar med flera fingrar samtidigt).
local function bindHold(button: TextButton, inputName: string)
	local activeTouches: { [InputObject]: boolean } = {}
	local function refresh()
		local pressed = next(activeTouches) ~= nil
		InputController.SetTouch(inputName, pressed)
		button.BackgroundTransparency = if pressed then 0.1 else 0.35
	end
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			activeTouches[input] = true
			refresh()
		end
	end)
	button.InputEnded:Connect(function(input)
		activeTouches[input] = nil
		refresh()
	end)
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "TouchControls"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local grey = Color3.fromRGB(40, 40, 50)
	bindHold(makeButton("Left", "◀", 110, UDim2.new(0, 90, 1, -100), grey), "Left")
	bindHold(makeButton("Right", "▶", 110, UDim2.new(0, 215, 1, -100), grey), "Right")

	bindHold(makeButton("Gas", "GAS", 120, UDim2.new(1, -90, 1, -110), Color3.fromRGB(40, 170, 70)), "Throttle")
	bindHold(makeButton("Brake", "BRAKE", 90, UDim2.new(1, -215, 1, -70), Color3.fromRGB(190, 50, 50)), "Brake")
	bindHold(makeButton("Drift", "DRIFT", 90, UDim2.new(1, -215, 1, -175), Color3.fromRGB(220, 140, 30)), "Handbrake")
	bindHold(makeButton("Boost", "BOOST", 100, UDim2.new(1, -90, 1, -240), Color3.fromRGB(40, 150, 230)), "Boost")

	local reset = makeButton("Reset", "↻", 60, UDim2.new(1, -50, 0, 120), grey)
	reset.Activated:Connect(VehicleController.RequestReset)
end

function TouchControls.Start()
	if not UserInputService.TouchEnabled then
		return
	end
	build()
	pcall(function()
		(Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui).ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
	end)
	VehicleController.Entered:Connect(function()
		gui.Enabled = true
	end)
	VehicleController.Exited:Connect(function()
		gui.Enabled = false
		for _, name in { "Throttle", "Brake", "Left", "Right", "Handbrake", "Boost" } do
			InputController.SetTouch(name, false)
		end
	end)
end

return TouchControls
