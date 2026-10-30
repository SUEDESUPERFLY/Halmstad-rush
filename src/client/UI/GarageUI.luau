--!strict
-- Garagemenyn: köp bilar, byt bil, uppgradera och lackera.
-- Visar bara det servern skickat (ProfileUpdated). Varje knapp skickar en avsikt
-- (GarageAction) och servern avgör om den går igenom.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local CarCatalog = require(ReplicatedStorage.Shared.Config.CarCatalog)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ActivityController = require(script.Parent.Parent.Controllers.ActivityController)
local RaceController = require(script.Parent.Parent.Controllers.RaceController)
local VehicleController = require(script.Parent.Parent.Controllers.VehicleController)

local GarageUI = {}

local STAT_ROWS = {
	{ Key = "TopSpeed", Label = "Fart", Min = 0.85, Max = 1.35 },
	{ Key = "Acceleration", Label = "Acceleration", Min = 0.85, Max = 1.45 },
	{ Key = "Handling", Label = "Grepp", Min = 0.85, Max = 1.4 },
	{ Key = "Boost", Label = "Boost", Min = 0.95, Max = 1.3 },
}

local ACCENT = Color3.fromRGB(255, 190, 40)
local PANEL = Color3.fromRGB(18, 20, 30)
local CARD = Color3.fromRGB(35, 40, 58)

local gui: ScreenGui
local toggleButton: TextButton
local window: Frame
local carList: ScrollingFrame
local details: ScrollingFrame
local footer: TextLabel
local actionRemote: RemoteEvent

local profile: any = nil
local viewedCar = CarCatalog.StarterCar

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function text(parent: Instance, value: string, size: number, height: number, color: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = size
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Text = value
	label.Size = UDim2.new(1, 0, 0, height)
	label.Parent = parent
	return label
end

local function button(parent: Instance, value: string, color: Color3, height: number, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Text = value
	b.Font = Enum.Font.GothamBlack
	b.TextSize = 16
	b.TextColor3 = Color3.fromRGB(20, 20, 25)
	b.BackgroundColor3 = color
	b.Size = UDim2.new(1, 0, 0, height)
	b.AutoButtonColor = true
	b.Parent = parent
	corner(b, 8)
	b.Activated:Connect(onClick)
	return b
end

local function list(parent: Instance, padding: number)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, padding)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent
end

local function send(action: string, carId: string, arg: string?)
	actionRemote:FireServer(action, carId, arg)
end

local function clear(frame: Instance)
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local refresh: () -> ()

local function statBar(parent: Instance, labelText: string, ratio: number, order: number)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 22)
	row.LayoutOrder = order
	row.Parent = parent
	local label = text(row, labelText, 14, 22)
	label.Size = UDim2.new(0.38, 0, 1, 0)
	local track = Instance.new("Frame")
	track.BackgroundColor3 = CARD
	track.Position = UDim2.new(0.4, 0, 0.25, 0)
	track.Size = UDim2.new(0.6, 0, 0.5, 0)
	track.Parent = row
	corner(track, 6)
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = ACCENT
	fill.Size = UDim2.fromScale(math.clamp(ratio, 0.05, 1), 1)
	fill.Parent = track
	corner(fill, 6)
end

local function renderList()
	clear(carList)
	list(carList, 6)
	for index, car in CarCatalog.Cars do
		local owned = profile and profile.OwnedCars[car.Id] ~= nil
		local selected = profile and profile.SelectedCar == car.Id
		local status = if selected then "  ✓ I bruk" elseif owned then "  Ägd" else ("  %d kr"):format(car.Price)
		local b = button(carList, car.Name .. status, if car.Id == viewedCar then ACCENT else CARD, 40, function()
			viewedCar = car.Id
			refresh()
		end)
		b.TextColor3 = if car.Id == viewedCar then Color3.fromRGB(20, 20, 25) else Color3.new(1, 1, 1)
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.LayoutOrder = index
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 10)
		pad.Parent = b
	end
end

local function renderDetails()
	clear(details)
	list(details, 8)
	local car = CarCatalog.FindCar(viewedCar)
	if not car or not profile then
		return
	end
	local owned = profile.OwnedCars[car.Id]
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	text(details, car.Name, 26, 32, ACCENT).LayoutOrder = nextOrder()
	text(details, car.Description, 14, 36, Color3.fromRGB(200, 200, 210)).LayoutOrder = nextOrder()

	local stats = CarCatalog.ComputeStats(car.Id, owned and owned.Upgrades)
	for _, row in STAT_ROWS do
		local value = (stats :: any)[row.Key]
		statBar(details, row.Label, (value - row.Min) / (row.Max - row.Min), nextOrder())
	end

	if not owned then
		local canAfford = profile.Money >= car.Price
		button(details, ("KÖP · %d kr"):format(car.Price), if canAfford then ACCENT else Color3.fromRGB(110, 110, 120), 44, function()
			send("Buy", car.Id)
		end).LayoutOrder = nextOrder()
		return
	end

	if profile.SelectedCar ~= car.Id then
		button(details, "KÖR DENNA BIL", Color3.fromRGB(90, 210, 120), 44, function()
			send("Select", car.Id)
		end).LayoutOrder = nextOrder()
	end

	text(details, "UPPGRADERINGAR", 16, 22, ACCENT).LayoutOrder = nextOrder()
	for _, upgrade in CarCatalog.Upgrades do
		local level = owned.Upgrades[upgrade.Id] or 0
		local cost = upgrade.Costs[level + 1]
		local pips = string.rep("■", level) .. string.rep("□", #upgrade.Costs - level)
		local label = if cost then ("%s  %s  · %d kr"):format(upgrade.Name, pips, cost) else ("%s  %s  · MAX"):format(upgrade.Name, pips)
		local b = button(details, label, if cost then Color3.fromRGB(120, 180, 255) else CARD, 36, function()
			if cost then
				send("Upgrade", car.Id, upgrade.Id)
			end
		end)
		b.LayoutOrder = nextOrder()
		if not cost then
			b.TextColor3 = Color3.new(1, 1, 1)
		end
	end

	text(details, ("LACK · %d kr"):format(CarCatalog.PaintCost), 16, 22, ACCENT).LayoutOrder = nextOrder()
	local swatches = Instance.new("Frame")
	swatches.BackgroundTransparency = 1
	swatches.Size = UDim2.new(1, 0, 0, 84)
	swatches.LayoutOrder = nextOrder()
	swatches.Parent = details
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(36, 36)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.Parent = swatches
	for _, color in CarCatalog.Colors do
		local swatch = Instance.new("TextButton")
		swatch.Text = ""
		swatch.BackgroundColor3 = color.Color
		swatch.Parent = swatches
		corner(swatch, 18)
		if owned.Color == color.Id then
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.new(1, 1, 1)
			stroke.Thickness = 3
			stroke.Parent = swatch
		end
		swatch.Activated:Connect(function()
			send("Paint", car.Id, color.Id)
		end)
	end
end

refresh = function()
	if not window.Visible then
		return
	end
	renderList()
	renderDetails()
	if profile then
		footer.Text = ("Saldo: %d kr%s"):format(profile.Money, if profile.Persistent then "" else "   ·   Sparas inte i det här testet")
	end
end

local function setOpen(open: boolean)
	if open and (RaceController.IsRacing() or ActivityController.IsActive()) then
		return
	end
	window.Visible = open
	if open and profile then
		viewedCar = profile.SelectedCar
	end
	refresh()
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "GarageUI"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	toggleButton = Instance.new("TextButton")
	toggleButton.Text = "GARAGE (G)"
	toggleButton.Font = Enum.Font.GothamBold
	toggleButton.TextSize = 18
	toggleButton.TextColor3 = Color3.new(1, 1, 1)
	toggleButton.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
	toggleButton.BackgroundTransparency = 0.3
	toggleButton.Position = UDim2.fromOffset(134, 70)
	toggleButton.Size = UDim2.fromOffset(130, 40)
	toggleButton.Parent = gui
	corner(toggleButton, 10)
	toggleButton.Activated:Connect(function()
		setOpen(not window.Visible)
	end)

	window = Instance.new("Frame")
	window.Name = "Window"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromScale(0.9, 0.82)
	window.BackgroundColor3 = PANEL
	window.BackgroundTransparency = 0.05
	window.Visible = false
	window.Parent = gui
	corner(window, 16)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(720, 460)
	constraint.Parent = window

	local title = text(window, "GARAGE", 24, 36, ACCENT)
	title.Position = UDim2.fromOffset(18, 10)
	title.Size = UDim2.new(1, -80, 0, 36)
	title.Font = Enum.Font.GothamBlack

	local close = Instance.new("TextButton")
	close.Text = "✕"
	close.Font = Enum.Font.GothamBlack
	close.TextSize = 20
	close.TextColor3 = Color3.new(1, 1, 1)
	close.BackgroundColor3 = Color3.fromRGB(170, 50, 50)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 12)
	close.Size = UDim2.fromOffset(36, 36)
	close.Parent = window
	corner(close, 18)
	close.Activated:Connect(function()
		setOpen(false)
	end)

	carList = Instance.new("ScrollingFrame")
	carList.BackgroundTransparency = 1
	carList.BorderSizePixel = 0
	carList.Position = UDim2.fromOffset(16, 56)
	carList.Size = UDim2.new(0.38, -16, 1, -96)
	carList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	carList.CanvasSize = UDim2.new()
	carList.ScrollBarThickness = 4
	carList.Parent = window

	details = Instance.new("ScrollingFrame")
	details.BackgroundTransparency = 1
	details.BorderSizePixel = 0
	details.Position = UDim2.new(0.38, 12, 0, 56)
	details.Size = UDim2.new(0.62, -28, 1, -96)
	details.AutomaticCanvasSize = Enum.AutomaticSize.Y
	details.CanvasSize = UDim2.new()
	details.ScrollBarThickness = 4
	details.Parent = window

	footer = text(window, "", 14, 24, Color3.fromRGB(255, 215, 80))
	footer.Position = UDim2.new(0, 18, 1, -34)
	footer.Size = UDim2.new(1, -36, 0, 24)
end

function GarageUI.Start()
	actionRemote = Remotes.Get("GarageAction")
	build()

	Remotes.Get("ProfileUpdated").OnClientEvent:Connect(function(data: any)
		if typeof(data) == "table" and typeof(data.OwnedCars) == "table" then
			profile = data
			refresh()
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and gui.Enabled and input.KeyCode == Enum.KeyCode.G then
			setOpen(not window.Visible)
		end
	end)

	VehicleController.Entered:Connect(function()
		gui.Enabled = true
	end)
	VehicleController.Exited:Connect(function()
		gui.Enabled = false
	end)
	RaceController.SetupReceived:Connect(function()
		setOpen(false)
		toggleButton.Visible = false
	end)
	RaceController.Finished:Connect(function()
		toggleButton.Visible = true
	end)
end

return GarageUI
