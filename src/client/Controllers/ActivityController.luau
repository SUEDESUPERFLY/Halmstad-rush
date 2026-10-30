--!strict
-- Klientens del av aktiviteterna (budjobb, stunts, drift, krockläget, kull):
-- tar emot inbjudan, status och resultat från servern, visar ett ljus vid målet och
-- håller bilen still under nedräkningar. Servern mäter och avgör allt.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local VehicleController = require(script.Parent.VehicleController)

local ActivityController = {}

ActivityController.Invited = Signal.new() -- (id, name, description)
ActivityController.StateChanged = Signal.new() -- (state)
ActivityController.Finished = Signal.new() -- (result)

local requestRemote: RemoteEvent
local leaveRemote: RemoteEvent
local state: { [string]: any }? = nil
local beacon: Model? = nil
local beaconLabel: TextLabel? = nil
local lastCountdown = 0

local BEACON_COLOR = Color3.fromRGB(90, 230, 140)

local function clearBeacon()
	if beacon then
		beacon:Destroy()
		beacon = nil
		beaconLabel = nil
	end
end

local function placeBeacon(position: Vector3, label: string)
	if not beacon then
		local model = Instance.new("Model")
		model.Name = "ActivityBeacon"
		local pillar = Instance.new("Part")
		pillar.Name = "Pillar"
		pillar.Anchored = true
		pillar.CanCollide = false
		pillar.CanQuery = false
		pillar.CanTouch = false
		pillar.Material = Enum.Material.Neon
		pillar.Color = BEACON_COLOR
		pillar.Transparency = 0.45
		pillar.Shape = Enum.PartType.Cylinder
		pillar.Size = Vector3.new(120, 10, 10)
		pillar.Parent = model
		model.PrimaryPart = pillar

		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(160, 50)
		billboard.StudsOffset = Vector3.new(0, 66, 0)
		billboard.AlwaysOnTop = true
		billboard.Parent = pillar
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamBlack
		text.TextScaled = true
		text.TextColor3 = BEACON_COLOR
		text.TextStrokeTransparency = 0.2
		text.Parent = billboard
		beaconLabel = text
		model.Parent = workspace
		beacon = model
	end
	local current = beacon :: Model
	local pillar = current.PrimaryPart :: BasePart
	pillar.CFrame = CFrame.new(position + Vector3.new(0, 60, 0)) * CFrame.Angles(0, 0, math.rad(90))
	current:SetAttribute("Label", label)
end

function ActivityController.Request(id: string)
	requestRemote:FireServer(id)
end

function ActivityController.Leave()
	leaveRemote:FireServer()
end

function ActivityController.IsActive(): boolean
	return state ~= nil
end

function ActivityController.Start()
	requestRemote = Remotes.Get("RequestActivity")
	leaveRemote = Remotes.Get("LeaveActivity")

	Remotes.Get("ActivityInvite").OnClientEvent:Connect(function(id: unknown, name: unknown, description: unknown)
		if state == nil and typeof(id) == "string" then
			ActivityController.Invited:Fire(id, Locale.Resolve(name), Locale.Resolve(description))
		end
	end)

	Remotes.Get("ActivityState").OnClientEvent:Connect(function(data: any)
		if typeof(data) ~= "table" then
			return
		end
		state = data
		if typeof(data.Target) == "Vector3" then
			placeBeacon(data.Target, Locale.Resolve(if data.TargetLabel ~= nil then data.TargetLabel else "GOAL"))
		else
			clearBeacon()
		end
		-- Nedräkning: håll bilen still tills servern säger kör
		if typeof(data.CountdownTo) == "number" and data.CountdownTo ~= lastCountdown then
			lastCountdown = data.CountdownTo
			local left = data.CountdownTo - workspace:GetServerTimeNow()
			if left > 0 then
				VehicleController.LockInput(left, true)
				VehicleController.IgnoreCrashes(1.5)
			end
		end
		ActivityController.StateChanged:Fire(data)
	end)

	Remotes.Get("ActivityResult").OnClientEvent:Connect(function(result: any)
		state = nil
		clearBeacon()
		if typeof(result) == "table" then
			ActivityController.Finished:Fire(result)
		end
	end)

	-- Avståndet till målet på ljusets etikett
	RunService.RenderStepped:Connect(function()
		local current = beacon
		local label = beaconLabel
		local car = VehicleController.GetCar()
		if not current or not label or not car or not car.PrimaryPart then
			return
		end
		local pillar = current.PrimaryPart :: BasePart
		local distance = ((pillar.Position - car.PrimaryPart.Position) * Vector3.new(1, 0, 1)).Magnitude
		label.Text = ("▼ %s · %d m"):format(tostring(current:GetAttribute("Label")), math.floor(distance * 0.28))
	end)
end

return ActivityController
