--!strict
-- Spelarnas pengar (kronor), lagrade i den sparade profilen (DataService).
-- All ändring av saldot går genom den här modulen och sker bara på servern.
-- Leaderstats (Kronor, Takedowns) speglar profilen så att de syns i spelarlistan.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Leaderstats = require(script.Parent.Parent.Util.Leaderstats)
local DataService = require(script.Parent.DataService)

local EconomyService = {}

local notifyRemote: RemoteEvent

local function validAmount(amount: number): boolean
	return typeof(amount) == "number" and amount == amount and amount > 0 and amount <= EconomyConfig.MaxSingleReward
end

function EconomyService.GetMoney(player: Player): number
	local data = DataService.Get(player)
	return if data then data.Money else 0
end

-- Betalar ut ett belopp. `reason` visas för spelaren.
function EconomyService.AddMoney(player: Player, amount: number, reason: string?): boolean
	if player.Parent ~= Players or not validAmount(amount) then
		warn(("[EconomyService] Ogiltig utbetalning %s till %s"):format(tostring(amount), player.Name))
		return false
	end
	local rounded = math.floor(amount)
	local ok = DataService.Update(player, function(data)
		data.Money += rounded
	end)
	if ok then
		notifyRemote:FireClient(player, ("+%d kr%s"):format(rounded, if reason then "  " .. reason else ""), "money")
	end
	return ok
end

-- Drar ett belopp om spelaren har råd. Returnerar true om köpet gick igenom.
function EconomyService.Spend(player: Player, amount: number): boolean
	if typeof(amount) ~= "number" or amount ~= amount or amount < 0 then
		return false
	end
	local data = DataService.Get(player)
	if not data or data.Money < amount then
		return false
	end
	return DataService.Update(player, function(profile)
		profile.Money -= math.floor(amount)
	end)
end

function EconomyService.Init()
	notifyRemote = Remotes.Get("Notify")
end

function EconomyService.Start()
	DataService.Changed:Connect(function(player: Player, data)
		if player.Parent == Players then
			Leaderstats.Get(player, EconomyConfig.Currency).Value = data.Money
			Leaderstats.Get(player, "Takedowns").Value = data.Takedowns
		end
	end)
	local function onPlayer(player: Player)
		-- Ordning i spelarlistan: Kronor först
		Leaderstats.Get(player, EconomyConfig.Currency)
		Leaderstats.Get(player, "Takedowns")
		task.spawn(function()
			local data = DataService.WaitForData(player)
			if data and player.Parent == Players then
				Leaderstats.Get(player, EconomyConfig.Currency).Value = data.Money
				Leaderstats.Get(player, "Takedowns").Value = data.Takedowns
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return EconomyService
