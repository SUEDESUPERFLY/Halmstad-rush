--!strict
-- Klientens del av racen: tar emot inbjudan, uppställning, kontrollpunkter och resultat
-- från servern och visar portarna i världen. Servern avgör allt som räknas.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local VehicleController = require(script.Parent.VehicleController)

export type CheckpointInfo = { Position: Vector3, Direction: Vector3 }
export type RaceSetup = {
	RaceId: string,
	Name: string,
	StartAt: number,
	Checkpoints: { CheckpointInfo },
	Participants: number,
}

local RaceController = {}

RaceController.Invited = Signal.new() -- (raceId, raceName, lobbyOpen)
RaceController.SetupReceived = Signal.new() -- (setup)
RaceController.CheckpointPassed = Signal.new() -- (passed, total)
RaceController.Updated = Signal.new() -- (position, participants, elapsed)
RaceController.Finished = Signal.new() -- (data)

local GATE_WIDTH = 46
local GATE_HEIGHT = 16
local NEXT_COLOR = Color3.fromRGB(255, 200, 40)
local LATER_COLOR = Color3.fromRGB(120, 200, 255)
local FINISH_COLOR = Color3.fromRGB(255, 255, 255)

local setup: RaceSetup? = nil
local passed = 0
local gateFolder: Folder
local joinRemote: RemoteEvent
local leaveRemote: RemoteEvent

local function clearGates()
	gateFolder:ClearAllChildren()
end

local function gatePart(parent: Instance, size: Vector3, cframe: CFrame, color: Color3, transparency: number): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency
	part.Size = size
	part.CFrame = cframe
	part.Parent = parent
	return part
end

local function buildGate(index: number, isNext: boolean)
	local current = setup
	if not current then
		return
	end
	local checkpoint = current.Checkpoints[index]
	if not checkpoint then
		return
	end
	local isFinish = index == #current.Checkpoints
	local color = if isFinish then FINISH_COLOR elseif isNext then NEXT_COLOR else LATER_COLOR
	local transparency = if isNext then 0.1 else 0.6
	local model = Instance.new("Model")
	model.Name = "Gate" .. index
	local base = CFrame.lookAt(checkpoint.Position, checkpoint.Position + checkpoint.Direction)
	for _, side in { -1, 1 } do
		gatePart(model, Vector3.new(1.6, GATE_HEIGHT, 1.6), base * CFrame.new(side * GATE_WIDTH / 2, GATE_HEIGHT / 2, 0), color, transparency)
	end
	local beam = gatePart(model, Vector3.new(GATE_WIDTH, 1.6, 1.6), base * CFrame.new(0, GATE_HEIGHT, 0), color, transparency)

	if isNext then
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(120, 50)
		billboard.StudsOffset = Vector3.new(0, 6, 0)
		billboard.AlwaysOnTop = true
		billboard.Parent = beam
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = color
		label.TextStrokeTransparency = 0.2
		label.Text = if isFinish then "▼ " .. Locale.T("FINISH") else ("▼ %d/%d"):format(index, #current.Checkpoints)
		label.Parent = billboard
	end
	model.Parent = gateFolder
end

local function refreshGates()
	clearGates()
	local current = setup
	if not current then
		return
	end
	buildGate(passed + 1, true)
	buildGate(passed + 2, false)
end

function RaceController.Join(raceId: string)
	joinRemote:FireServer(raceId)
end

function RaceController.Leave()
	leaveRemote:FireServer()
end

-- Nästa kontrollpunkt (för minikartan), eller nil utanför race.
function RaceController.NextCheckpoint(): Vector3?
	local current = setup
	local checkpoint = current and current.Checkpoints[passed + 1]
	return checkpoint and checkpoint.Position
end

function RaceController.IsRacing(): boolean
	return setup ~= nil
end

function RaceController.Start()
	gateFolder = Instance.new("Folder")
	gateFolder.Name = "RaceGates"
	gateFolder.Parent = workspace

	joinRemote = Remotes.Get("RequestJoinRace")
	leaveRemote = Remotes.Get("LeaveRace")

	Remotes.Get("RaceInvite").OnClientEvent:Connect(function(raceId: unknown, raceName: unknown, lobbyOpen: unknown)
		if setup == nil and typeof(raceId) == "string" and typeof(raceName) == "string" then
			RaceController.Invited:Fire(raceId, raceName, lobbyOpen == true)
		end
	end)

	Remotes.Get("RaceSetup").OnClientEvent:Connect(function(data: any)
		if typeof(data) ~= "table" or typeof(data.Checkpoints) ~= "table" then
			return
		end
		setup = data :: RaceSetup
		passed = 0
		local untilStart = (data.StartAt :: number) - workspace:GetServerTimeNow()
		VehicleController.LockInput(math.max(untilStart, 0), true)
		VehicleController.IgnoreCrashes(1.5)
		refreshGates()
		RaceController.SetupReceived:Fire(data)
	end)

	Remotes.Get("RaceCheckpoint").OnClientEvent:Connect(function(index: unknown)
		local current = setup
		if not current or typeof(index) ~= "number" then
			return
		end
		passed = index :: number
		refreshGates()
		RaceController.CheckpointPassed:Fire(passed, #current.Checkpoints)
	end)

	Remotes.Get("RaceUpdate").OnClientEvent:Connect(function(position: unknown, total: unknown, elapsed: unknown)
		if setup and typeof(position) == "number" and typeof(total) == "number" and typeof(elapsed) == "number" then
			RaceController.Updated:Fire(position, total, elapsed)
		end
	end)

	Remotes.Get("RaceFinished").OnClientEvent:Connect(function(data: any)
		setup = nil
		passed = 0
		clearGates()
		if typeof(data) == "table" then
			RaceController.Finished:Fire(data)
		end
	end)
end

return RaceController
