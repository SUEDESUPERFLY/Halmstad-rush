--!strict
-- Visar stadsdelens namn stort när man kör in i ett nytt område (GTA-känsla).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local VehicleController = require(script.Parent.Parent.Controllers.VehicleController)

local DistrictBanner = {}

local CHECK_INTERVAL = 0.5
local SHOW_TIME = 2.5

local label: TextLabel
local currentDistrict: string? = nil
local showToken = 0

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DistrictBanner"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.3)
	label.Size = UDim2.fromOffset(700, 70)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 54
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.TextTransparency = 1
	label.TextStrokeColor3 = Color3.fromRGB(20, 30, 60)
	label.Parent = gui
end

local function show(name: string)
	showToken += 1
	local token = showToken
	label.Text = string.upper(name)
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0.2
	task.delay(SHOW_TIME, function()
		if token ~= showToken then
			return
		end
		TweenService:Create(label, TweenInfo.new(0.8), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
end

function DistrictBanner.Start()
	build()
	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)
			local car = VehicleController.GetCar()
			local chassis = car and car.PrimaryPart
			if chassis then
				local district = MapData.DistrictAt(chassis.Position)
				if district and district ~= currentDistrict then
					show(district)
				end
				currentDistrict = district
			end
		end
	end)
end

return DistrictBanner
