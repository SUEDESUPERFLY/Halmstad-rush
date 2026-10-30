--!strict
-- Spelarnas pengar (kronor). Fas 4: bara i minnet. Fas 5 sparar med DataStore.
-- All ändring av saldot går genom den här modulen och sker bara på servern.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Leaderstats = require(script.Parent.Parent.Util.Leaderstats)

local EconomyService = {}

local notifyRemote: RemoteEvent

function EconomyService.GetMoney(player: Player): number
	return Leaderstats.Get(player, EconomyConfig.Currency).Value
end

-- Betalar ut ett belopp. `reason` visas för spelaren.
function EconomyService.AddMoney(player: Player, amount: number, reason: string?): boolean
	if player.Parent ~= Players then
		return false
	end
	if typeof(amount) ~= "number" or amount ~= amount or amount <= 0 or amount > EconomyConfig.MaxSingleReward then
		warn(("[EconomyService] Ogiltigt belopp %s till %s"):format(tostring(amount), player.Name))
		return false
	end
	local rounded = math.floor(amount)
	local stat = Leaderstats.Get(player, EconomyConfig.Currency)
	stat.Value += rounded
	notifyRemote:FireClient(player, ("+%d kr%s"):format(rounded, if reason then "  " .. reason else ""), "money")
	return true
end

function EconomyService.Init()
	notifyRemote = Remotes.Get("Notify")
end

function EconomyService.Start()
	local function onPlayer(player: Player)
		Leaderstats.Get(player, EconomyConfig.Currency).Value = EconomyConfig.StartMoney
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return EconomyService
