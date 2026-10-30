--!strict
-- Krockar och takedowns på servern:
--  * Kvaddade spelarbilar flyttas tillbaka till gatan (ReportWreck, med cooldown).
--  * Takedowns räknas här och syns i leaderstats. Klienten kan aldrig rapportera en takedown,
--    den avgörs av NpcService utifrån vad servern själv ser.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VehicleConfig = require(ReplicatedStorage.Shared.Config.VehicleConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RespawnService = require(script.Parent.RespawnService)

local CrashService = {}

local lastWreck: { [Player]: number } = {}
local takedownRemote: RemoteEvent

local function getStat(player: Player, name: string): IntValue?
	local leaderstats = player:FindFirstChild("leaderstats")
	return leaderstats and leaderstats:FindFirstChild(name) :: IntValue?
end

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local takedowns = Instance.new("IntValue")
	takedowns.Name = "Takedowns"
	takedowns.Parent = leaderstats
	leaderstats.Parent = player
end

local function onReportWreck(player: Player)
	local now = os.clock()
	if now - (lastWreck[player] or -math.huge) < VehicleConfig.Crash.ReportWreckCooldown then
		return
	end
	lastWreck[player] = now
	RespawnService.RespawnOnRoad(player, "Back in action!")
end

-- Anropas av NpcService när en spelare har knuffat ut en NPC-bil.
function CrashService.AwardTakedown(player: Player, npcChassis: BasePart)
	if player.Parent ~= Players then
		return
	end
	local stat = getStat(player, "Takedowns")
	if stat then
		stat.Value += 1
	end
	takedownRemote:FireClient(player, npcChassis)
end

function CrashService.Init()
	-- Klientens lokala plåtdelar ska inte påverka bilarna
	for _, group in { "Debris", VehicleConfig.CollisionGroup } do
		if not PhysicsService:IsCollisionGroupRegistered(group) then
			PhysicsService:RegisterCollisionGroup(group)
		end
	end
	PhysicsService:CollisionGroupSetCollidable("Debris", VehicleConfig.CollisionGroup, false)
	PhysicsService:CollisionGroupSetCollidable("Debris", "Debris", false)
	takedownRemote = Remotes.Get("Takedown")
	Remotes.Get("CrashEffect")
	Remotes.Get("ReportWreck").OnServerEvent:Connect(onReportWreck)
end

function CrashService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		if not player:FindFirstChild("leaderstats") then
			onPlayerAdded(player)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		lastWreck[player] = nil
	end)
end

return CrashService
