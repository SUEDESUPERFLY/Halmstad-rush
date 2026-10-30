--!strict
-- Hastighetsmätare, boost-mätare och popup-texter (DRIFT!, NEAR MISS!, AIR, TAKEDOWN!, WRECKED!).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Remotes = require(game:GetService("ReplicatedStorage").Shared.Remotes)
local VehicleController = require(script.Parent.Parent.Controllers.VehicleController)

local HUD = {}

local POPUP_COLORS: { [string]: Color3 } = {
	drift = Color3.fromRGB(255, 170, 40),
	nearmiss = Color3.fromRGB(80, 220, 255),
	air = Color3.fromRGB(150, 255, 120),
	respawn = Color3.fromRGB(120, 190, 255),
	location = Color3.fromRGB(255, 255, 255),
	info = Color3.fromRGB(220, 220, 220),
	takedown = Color3.fromRGB(255, 70, 60),
	wreck = Color3.fromRGB(255, 150, 40),
	money = Color3.fromRGB(255, 215, 80),
}

local BIG_POPUPS: { [string]: boolean } = { takedown = true, wreck = true }

local gui: ScreenGui
local speedLabel: TextLabel
local boostFill: Frame
local boostFrame: Frame
local popupHolder: Frame
local moneyLabel: TextLabel

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "HUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 12)
	panel.Size = UDim2.fromOffset(260, 74)
	panel.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
	panel.BackgroundTransparency = 0.35
	panel.Parent = gui
	corner(panel, 12)

	speedLabel = Instance.new("TextLabel")
	speedLabel.Name = "Speed"
	speedLabel.BackgroundTransparency = 1
	speedLabel.Position = UDim2.fromOffset(0, 4)
	speedLabel.Size = UDim2.new(1, 0, 0, 40)
	speedLabel.Font = Enum.Font.GothamBlack
	speedLabel.TextSize = 34
	speedLabel.TextColor3 = Color3.new(1, 1, 1)
	speedLabel.Text = "0 km/h"
	speedLabel.Parent = panel

	boostFrame = Instance.new("Frame")
	boostFrame.Name = "Boost"
	boostFrame.Position = UDim2.new(0, 14, 0, 50)
	boostFrame.Size = UDim2.new(1, -28, 0, 14)
	boostFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
	boostFrame.Parent = panel
	corner(boostFrame, 7)

	boostFill = Instance.new("Frame")
	boostFill.Name = "Fill"
	boostFill.Size = UDim2.fromScale(0.5, 1)
	boostFill.BackgroundColor3 = Color3.fromRGB(255, 120, 30)
	boostFill.Parent = boostFrame
	corner(boostFill, 7)

	popupHolder = Instance.new("Frame")
	popupHolder.Name = "Popups"
	popupHolder.BackgroundTransparency = 1
	popupHolder.AnchorPoint = Vector2.new(0.5, 0)
	popupHolder.Position = UDim2.new(0.5, 0, 0, 100)
	popupHolder.Size = UDim2.fromOffset(400, 200)
	popupHolder.Parent = gui

	moneyLabel = Instance.new("TextLabel")
	moneyLabel.Name = "Money"
	moneyLabel.AnchorPoint = Vector2.new(1, 0)
	moneyLabel.Position = UDim2.new(1, -16, 0, 70)
	moneyLabel.Size = UDim2.fromOffset(200, 40)
	moneyLabel.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
	moneyLabel.BackgroundTransparency = 0.35
	moneyLabel.Font = Enum.Font.GothamBlack
	moneyLabel.TextSize = 24
	moneyLabel.TextColor3 = Color3.fromRGB(255, 215, 80)
	moneyLabel.Text = "0 kr"
	moneyLabel.Parent = gui
	corner(moneyLabel, 10)

	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 4)
	layout.Parent = popupHolder
end

local function showPopup(text: string, kind: string)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	local big = BIG_POPUPS[kind] == true
	label.Size = UDim2.fromOffset(400, if big then 56 else 36)
	label.Font = Enum.Font.GothamBlack
	label.TextSize = if big then 48 else 30
	label.Text = text
	label.TextColor3 = POPUP_COLORS[kind] or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Parent = popupHolder

	local fade = TweenService:Create(
		label,
		TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.6),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	)
	fade:Play()
	fade.Completed:Once(function()
		label:Destroy()
	end)
end

-- Pengarna läses från leaderstats (servern äger värdet).
local function watchMoney()
	local player = Players.LocalPlayer
	local leaderstats = player:WaitForChild("leaderstats")
	local kronor = leaderstats:WaitForChild("Kronor") :: IntValue
	local function refresh()
		moneyLabel.Text = ("%d kr"):format(kronor.Value)
	end
	kronor.Changed:Connect(refresh)
	refresh()
end

function HUD.Start()
	build()
	task.spawn(watchMoney)

	VehicleController.Entered:Connect(function()
		gui.Enabled = true
	end)
	VehicleController.Exited:Connect(function()
		gui.Enabled = false
	end)
	VehicleController.Popup:Connect(showPopup)
	Remotes.Get("Notify").OnClientEvent:Connect(function(text: unknown, kind: unknown)
		if typeof(text) == "string" then
			showPopup(text, if typeof(kind) == "string" then kind else "info")
		end
	end)

	RunService.RenderStepped:Connect(function()
		if not gui.Enabled then
			return
		end
		local state = VehicleController.GetState()
		speedLabel.Text = ("%d km/h"):format(math.floor(math.abs(state.Speed) + 0.5))
		boostFill.Size = UDim2.fromScale(math.clamp(state.Boost, 0, 1), 1)
		boostFill.BackgroundColor3 = if state.Boosting
			then Color3.fromRGB(80, 220, 255)
			else Color3.fromRGB(255, 120, 30)
	end)
end

return HUD
