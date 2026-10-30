--!strict
-- Krockar och takedowns på servern:
--  * Kvaddade spelarbilar flyttas tillbaka till gatan (ReportWreck, med cooldown).
--    Under ett race tar RespawnService:s override hand om var bilen hamnar.
--  * Takedowns räknas här, syns i leaderstats och ger pengar. Klienten kan aldrig själv
--    rapportera en takedown: NpcService och RaceService avgör utifrån vad servern ser.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local VehicleConfig = require(ReplicatedStorage.Shared.Config.VehicleConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Leaderstats = require(script.Parent.Parent.Util.Leaderstats)
local EconomyService = require(script.Parent.EconomyService)
local RespawnService = require(script.Parent.RespawnService)

local CrashService = {}

type WreckListener = (player: Player) -> ()
type TakedownListener = (player: Player, victim: BasePart) -> ()

local lastWreck: { [Player]: number } = {}
local wreckListeners: { WreckListener } = {}
local takedownListeners: { TakedownListener } = {}
local takedownRemote: RemoteEvent

-- Lyssnare som vill veta när en spelare kvaddats (t.ex. RaceService för takedowns mellan spelare).
function CrashService.OnWrecked(listener: WreckListener)
	table.insert(wreckListeners, listener)
end

function CrashService.OnTakedown(listener: TakedownListener)
	table.insert(takedownListeners, listener)
end

local function onReportWreck(player: Player)
	local now = os.clock()
	if now - (lastWreck[player] or -math.huge) < VehicleConfig.Crash.ReportWreckCooldown then
		return
	end
	lastWreck[player] = now
	for _, listener in wreckListeners do
		task.spawn(listener, player)
	end
	RespawnService.RespawnOnRoad(player, "Back in action!")
end

-- `victim` är chassit på bilen som togs ut (NPC eller annan racedeltagare).
function CrashService.AwardTakedown(player: Player, victim: BasePart)
	if player.Parent ~= Players then
		return
	end
	Leaderstats.Get(player, "Takedowns").Value += 1
	EconomyService.AddMoney(player, EconomyConfig.TakedownReward, "Takedown")
	takedownRemote:FireClient(player, victim)
	for _, listener in takedownListeners do
		task.spawn(listener, player, victim)
	end
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
	local function onPlayer(player: Player)
		Leaderstats.Get(player, "Takedowns")
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastWreck[player] = nil
	end)
end

return CrashService
