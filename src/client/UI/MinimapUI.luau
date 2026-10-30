--!strict
-- Minikarta med norr uppåt: gator, huvudgator och vatten (genererat från stadskartan),
-- havet och vägen till Tylösand, aktivitetsmarkörer, andra spelare, aktuellt mål och en pil
-- för den egna bilen. Kartan flyttas under en fast ram (ClipsDescendants), så bara positionen
-- uppdateras varje bildruta.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ActivityConfig = require(ReplicatedStorage.Shared.Config.ActivityConfig)
local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local MinimapData = require(ReplicatedStorage.Shared.Map.MinimapData)
local ActivityController = require(script.Parent.Parent.Controllers.ActivityController)
local RaceController = require(script.Parent.Parent.Controllers.RaceController)
local VehicleController = require(script.Parent.Parent.Controllers.VehicleController)

local MinimapUI = {}

local SCALE = 0.11 -- pixlar per stud
local SIZE = 190
local WORLD_MIN = Vector2.new(-4800, -1700)
local WORLD_MAX = Vector2.new(2800, 2700)

local COLORS = {
	Land = Color3.fromRGB(96, 128, 82),
	Road = Color3.fromRGB(205, 205, 210),
	Main = Color3.fromRGB(250, 210, 70),
	Water = Color3.fromRGB(60, 120, 180),
	Activity = Color3.fromRGB(90, 230, 140),
	Race = Color3.fromRGB(255, 190, 40),
	Tag = Color3.fromRGB(255, 120, 200),
	Player = Color3.new(1, 1, 1),
	Target = Color3.fromRGB(90, 230, 140),
}

local gui: ScreenGui
local frame: Frame
local canvas: Frame
local arrow: TextLabel
local targetDot: Frame
local playerDots: { [Player]: Frame } = {}
local expanded = true

local function toCanvas(x: number, z: number): UDim2
	return UDim2.fromOffset((x - WORLD_MIN.X) * SCALE, (z - WORLD_MIN.Y) * SCALE)
end

local function rect(parent: Instance, x: number, z: number, width: number, depth: number, color: Color3)
	local r = Instance.new("Frame")
	r.BorderSizePixel = 0
	r.BackgroundColor3 = color
	r.Position = toCanvas(x, z)
	r.Size = UDim2.fromOffset(math.max(1, width * SCALE), math.max(1, depth * SCALE))
	r.Parent = parent
end

local function line(parent: Instance, a: Vector2, b: Vector2, width: number, color: Color3)
	local r = Instance.new("Frame")
	r.BorderSizePixel = 0
	r.BackgroundColor3 = color
	r.AnchorPoint = Vector2.new(0.5, 0.5)
	local mid = (a + b) / 2
	r.Position = toCanvas(mid.X, mid.Y)
	r.Size = UDim2.fromOffset((b - a).Magnitude * SCALE, math.max(2, width * SCALE))
	r.Rotation = math.deg(math.atan2(b.Y - a.Y, b.X - a.X))
	r.Parent = parent
end

local function dot(parent: Instance, position: Vector3, color: Color3, size: number): Frame
	local d = Instance.new("Frame")
	d.AnchorPoint = Vector2.new(0.5, 0.5)
	d.BackgroundColor3 = color
	d.BorderSizePixel = 0
	d.Size = UDim2.fromOffset(size, size)
	d.Position = toCanvas(position.X, position.Z)
	d.ZIndex = 3
	d.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = d
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(20, 20, 25)
	stroke.Thickness = 1
	stroke.Parent = d
	return d
end

local function buildCanvas()
	canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.BackgroundColor3 = COLORS.Land
	canvas.BorderSizePixel = 0
	canvas.Size = UDim2.fromOffset((WORLD_MAX.X - WORLD_MIN.X) * SCALE, (WORLD_MAX.Y - WORLD_MIN.Y) * SCALE)
	canvas.Parent = frame

	-- Havet söder om kusten och väster om stadskartan
	rect(canvas, WORLD_MIN.X, MapData.CoastZ, WORLD_MAX.X - WORLD_MIN.X, WORLD_MAX.Y - MapData.CoastZ, COLORS.Water)
	rect(canvas, WORLD_MIN.X, MapData.TylosandCoastZ, MapData.City.MinX - WORLD_MIN.X, MapData.CoastZ - MapData.TylosandCoastZ, COLORS.Water)

	-- Stadens gator och vatten (genererat)
	local colorFor = { [0] = COLORS.Road, [1] = COLORS.Main, [2] = COLORS.Water }
	for x, z, w, d, kind in (MinimapData :: string):gmatch("(%-?%d+),(%-?%d+),(%d+),(%d+),(%d)") do
		rect(canvas, tonumber(x) :: number, tonumber(z) :: number, tonumber(w) :: number, tonumber(d) :: number, colorFor[tonumber(kind) :: number])
	end
	-- Vägar utanför stadskartan
	for _, road in MapData.ExtraRoads do
		for i = 1, #road.Points - 1 do
			line(canvas, road.Points[i], road.Points[i + 1], road.Width, COLORS.Main)
		end
	end
	-- Aktiviteter, kull och race
	for _, activity in ActivityConfig.Activities do
		dot(canvas, activity.Marker, COLORS.Activity, 8)
	end
	dot(canvas, ActivityConfig.Tag.Marker, COLORS.Tag, 8)
	local raceStart = MapData.FindLocation("RaceStoraRingen")
	if raceStart then
		dot(canvas, raceStart.Position, COLORS.Race, 9)
	end

	targetDot = dot(canvas, Vector3.zero, COLORS.Target, 12)
	targetDot.Visible = false
	targetDot.ZIndex = 4
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "MinimapUI"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	frame = Instance.new("Frame")
	frame.Name = "Minimap"
	frame.Position = UDim2.fromOffset(16, 120)
	frame.Size = UDim2.fromOffset(SIZE, SIZE)
	frame.BackgroundColor3 = COLORS.Land
	frame.ClipsDescendants = true
	frame.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(20, 20, 25)
	stroke.Thickness = 3
	stroke.Parent = frame

	buildCanvas()

	arrow = Instance.new("TextLabel")
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Position = UDim2.fromScale(0.5, 0.5)
	arrow.Size = UDim2.fromOffset(22, 22)
	arrow.BackgroundTransparency = 1
	arrow.Font = Enum.Font.GothamBlack
	arrow.TextScaled = true
	arrow.Text = "▲"
	arrow.TextColor3 = Color3.fromRGB(255, 80, 60)
	arrow.TextStrokeTransparency = 0
	arrow.ZIndex = 5
	arrow.Parent = frame

	local north = Instance.new("TextLabel")
	north.Position = UDim2.fromOffset(4, 2)
	north.Size = UDim2.fromOffset(16, 16)
	north.BackgroundTransparency = 1
	north.Font = Enum.Font.GothamBlack
	north.TextSize = 14
	north.Text = "N"
	north.TextColor3 = Color3.new(1, 1, 1)
	north.TextStrokeTransparency = 0.3
	north.ZIndex = 5
	north.Parent = frame
end

local function update()
	local car = VehicleController.GetCar()
	local chassis = car and car.PrimaryPart
	if not chassis then
		return
	end
	local position = chassis.Position
	local offset = toCanvas(position.X, position.Z)
	canvas.Position = UDim2.fromOffset(SIZE / 2 - offset.X.Offset, SIZE / 2 - offset.Y.Offset)
	local look = chassis.CFrame.LookVector
	arrow.Rotation = math.deg(math.atan2(look.X, -look.Z))

	-- Andra spelare
	for _, other in Players:GetPlayers() do
		if other ~= Players.LocalPlayer then
			local character = other.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local marker = playerDots[other]
			if root then
				if not marker then
					marker = dot(canvas, root.Position, COLORS.Player, 7)
					playerDots[other] = marker
				end
				local current = marker :: Frame
				current.Position = toCanvas(root.Position.X, root.Position.Z)
			elseif marker then
				marker:Destroy()
				playerDots[other] = nil
			end
		end
	end
end

function MinimapUI.SetTarget(position: Vector3?)
	if position then
		targetDot.Position = toCanvas(position.X, position.Z)
		targetDot.Visible = true
	else
		targetDot.Visible = false
	end
end

function MinimapUI.Start()
	build()
	VehicleController.Entered:Connect(function()
		gui.Enabled = true
	end)
	VehicleController.Exited:Connect(function()
		gui.Enabled = false
	end)
	ActivityController.StateChanged:Connect(function(state: any)
		MinimapUI.SetTarget(if typeof(state.Target) == "Vector3" then state.Target else nil)
	end)
	ActivityController.Finished:Connect(function()
		MinimapUI.SetTarget(nil)
	end)
	local function showNextCheckpoint()
		MinimapUI.SetTarget(RaceController.NextCheckpoint())
	end
	RaceController.SetupReceived:Connect(showNextCheckpoint)
	RaceController.CheckpointPassed:Connect(showNextCheckpoint)
	RaceController.Finished:Connect(function()
		MinimapUI.SetTarget(nil)
	end)
	Players.PlayerRemoving:Connect(function(other)
		local marker = playerDots[other]
		if marker then
			marker:Destroy()
			playerDots[other] = nil
		end
	end)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.N then
			expanded = not expanded
			frame.Visible = expanded
		end
	end)
	RunService.RenderStepped:Connect(function()
		if gui.Enabled and expanded then
			update()
		end
	end)
end

return MinimapUI
