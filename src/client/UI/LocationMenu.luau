--!strict
-- Snabbresemeny: M-tangenten (eller MAP-knappen) öppnar en lista med platser.
-- Klienten skickar bara platsens id. Servern validerar id och cooldown.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local VehicleController = require(script.Parent.Parent.Controllers.VehicleController)

local LocationMenu = {}

local gui: ScreenGui
local panel: ScrollingFrame
local teleportRemote: RemoteEvent

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function setOpen(open: boolean)
	panel.Visible = open
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "LocationMenu"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local toggle = Instance.new("TextButton")
	toggle.Name = "MapButton"
	toggle.Text = "MAP (M)"
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 18
	toggle.TextColor3 = Color3.new(1, 1, 1)
	toggle.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
	toggle.BackgroundTransparency = 0.3
	toggle.Position = UDim2.fromOffset(16, 70)
	toggle.Size = UDim2.fromOffset(110, 40)
	toggle.Parent = gui
	corner(toggle, 10)
	toggle.Activated:Connect(function()
		setOpen(not panel.Visible)
	end)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Panel"
	scroll.Visible = false
	scroll.Position = UDim2.fromOffset(16, 118)
	scroll.Size = UDim2.new(0, 240, 1, -140)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 6
	scroll.BorderSizePixel = 0
	panel = scroll
	panel.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
	panel.BackgroundTransparency = 0.2
	panel.Parent = gui
	corner(panel, 12)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel

	local title = Instance.new("TextLabel")
	title.Text = "TRAVEL TO"
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 18
	title.TextColor3 = Color3.fromRGB(255, 190, 60)
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 24)
	title.LayoutOrder = 0
	title.Parent = panel

	for index, location in MapData.Locations do
		local button = Instance.new("TextButton")
		button.Name = location.Id
		button.Text = location.Name
		button.Font = Enum.Font.GothamBold
		button.TextSize = 18
		button.TextColor3 = Color3.new(1, 1, 1)
		button.BackgroundColor3 = Color3.fromRGB(45, 55, 80)
		button.Size = UDim2.new(1, 0, 0, 36)
		button.LayoutOrder = index
		button.Parent = panel
		corner(button, 8)
		button.Activated:Connect(function()
			teleportRemote:FireServer(location.Id)
			setOpen(false)
		end)
	end
end

function LocationMenu.Start()
	teleportRemote = Remotes.Get("TeleportToLocation")
	build()

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not gui.Enabled then
			return
		end
		if input.KeyCode == Enum.KeyCode.M or input.KeyCode == Enum.KeyCode.ButtonSelect then
			setOpen(not panel.Visible)
		end
	end)

	VehicleController.Entered:Connect(function()
		gui.Enabled = true
	end)
	VehicleController.Exited:Connect(function()
		gui.Enabled = false
		setOpen(false)
	end)
end

return LocationMenu
