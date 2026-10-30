--!strict
-- Respawn-systemet:
--  * R / ↻: ställ bilen på hjulen där den står. Två tryck inom några sekunder = till närmaste väg.
--  * Automatiskt till närmaste väg om bilen hamnar i vattnet eller utanför kartan.
--  * Snabbresa till namngivna platser (MapData.Locations), med cooldown.
-- Respawnpunkterna läggs till av MapService (gatorna) och TestTrackService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local VehicleConfig = require(ReplicatedStorage.Shared.Config.VehicleConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local VehicleService = require(script.Parent.VehicleService)

local Settings = VehicleConfig.Respawn

export type RespawnPoint = {
	Position: Vector3,
	Yaw: number, -- grader, 0 = norr
}

local RespawnService = {}

local points: { RespawnPoint } = {}
-- Under ett race bestämmer RaceService var bilen ska respawna och spärrar snabbresa.
local respawnOverride: ((player: Player) -> CFrame?)? = nil
local teleportBlocker: ((player: Player) -> string?)? = nil
local lastReset: { [Player]: number } = {}
local lastTeleport: { [Player]: number } = {}
local notifyRemote: RemoteEvent

local function pointCFrame(point: RespawnPoint): CFrame
	return CFrame.new(point.Position + Vector3.new(0, 4, 0)) * CFrame.Angles(0, math.rad(point.Yaw), 0)
end

function RespawnService.AddPoints(newPoints: { RespawnPoint })
	for _, point in newPoints do
		table.insert(points, point)
	end
end

function RespawnService.FindNearest(position: Vector3): RespawnPoint?
	local best: RespawnPoint? = nil
	local bestDistance = math.huge
	for _, point in points do
		local distance = (point.Position - position).Magnitude
		if distance < bestDistance then
			best = point
			bestDistance = distance
		end
	end
	return best
end

function RespawnService.SetRespawnOverride(override: (player: Player) -> CFrame?)
	respawnOverride = override
end

-- Blockeraren returnerar ett meddelande om snabbresa inte är tillåten just nu.
function RespawnService.SetTeleportBlocker(blocker: (player: Player) -> string?)
	teleportBlocker = blocker
end

function RespawnService.RespawnOnRoad(player: Player, message: string?)
	local car = VehicleService.GetCar(player)
	if not car or not car.PrimaryPart then
		return
	end
	local target = respawnOverride and respawnOverride(player)
	if not target then
		local point = RespawnService.FindNearest(car.PrimaryPart.Position)
		target = if point then pointCFrame(point) else MapData.PlayerSpawn(1)
	end
	VehicleService.MoveCar(player, target)
	if message then
		notifyRemote:FireClient(player, message, "respawn")
	end
end

local function onResetRequested(player: Player)
	local now = os.clock()
	local previous = lastReset[player] or -math.huge
	if now - previous < VehicleConfig.Server.ResetCooldown then
		return
	end
	lastReset[player] = now
	if now - previous < Settings.DoubleResetWindow then
		RespawnService.RespawnOnRoad(player, "Back on the road")
	else
		VehicleService.UprightCar(player)
	end
end

local function onTeleportRequested(player: Player, locationId: unknown)
	if typeof(locationId) ~= "string" or #locationId > 40 then
		return
	end
	local location = MapData.FindLocation(locationId)
	if not location then
		return
	end
	local blocked = teleportBlocker and teleportBlocker(player)
	if blocked then
		notifyRemote:FireClient(player, blocked, "info")
		return
	end
	local now = os.clock()
	if now - (lastTeleport[player] or -math.huge) < Settings.TeleportCooldown then
		notifyRemote:FireClient(player, "Wait a moment…", "info")
		return
	end
	lastTeleport[player] = now
	local target = MapData.LocationCFrame(location)
	if location.SnapToRoad then
		local point = RespawnService.FindNearest(location.Position)
		if point then
			target = pointCFrame(point)
		end
	end
	if VehicleService.MoveCar(player, target) then
		notifyRemote:FireClient(player, location.Name, "location")
	end
end

function RespawnService.Init()
	notifyRemote = Remotes.Get("Notify")
	Remotes.Get("ResetVehicle").OnServerEvent:Connect(onResetRequested)
	Remotes.Get("TeleportToLocation").OnServerEvent:Connect(onTeleportRequested)
end

function RespawnService.Start()
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastReset[player] = nil
		lastTeleport[player] = nil
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < Settings.CheckInterval then
			return
		end
		accumulator = 0
		for player, car in VehicleService.GetCars() do
			local chassis = car.PrimaryPart
			if chassis then
				local position = chassis.Position
				if position.Y < MapData.WaterLevel + Settings.WaterMargin then
					RespawnService.RespawnOnRoad(player, "SPLASH!")
				elseif not MapData.IsInBounds(position) then
					RespawnService.RespawnOnRoad(player, "Out of bounds")
				end
			end
		end
	end)
end

return RespawnService
