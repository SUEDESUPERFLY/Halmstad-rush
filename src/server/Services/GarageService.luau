--!strict
-- Garaget: köpa bilar, byta bil, uppgradera och lackera. Allt valideras här:
-- klienten skickar bara vad den vill göra (handling + bil-id + ev. uppgradering/färg),
-- servern kontrollerar ägande, nivåer, pris och saldo innan något ändras.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarCatalog = require(ReplicatedStorage.Shared.Config.CarCatalog)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PlayerMode = require(script.Parent.Parent.Util.PlayerMode)
local VehicleService = require(script.Parent.VehicleService)

local GarageService = {}

local ACTION_COOLDOWN = 0.3
local ACTIONS = { Buy = true, Select = true, Upgrade = true, Paint = true }

local lastAction: { [Player]: number } = {}
local notifyRemote: RemoteEvent
local profileRemote: RemoteEvent

local function notify(player: Player, message: Locale.Message, kind: string?)
	notifyRemote:FireClient(player, message, kind or "info")
end

-- Det klienten behöver för garagemenyn (bara en kopia, inget som klienten kan ändra).
local function sendProfile(player: Player, data: DataService.PlayerData)
	profileRemote:FireClient(player, {
		Money = data.Money,
		SelectedCar = data.SelectedCar,
		OwnedCars = data.OwnedCars,
		Persistent = DataService.IsPersistent(player),
	})
end

local function buy(player: Player, data: DataService.PlayerData, car: CarCatalog.Car)
	if data.OwnedCars[car.Id] then
		notify(player, Locale.Msg("You already own %s", car.Name))
		return
	end
	if not EconomyService.Spend(player, car.Price) then
		notify(player, Locale.Msg("Not enough money (%d kr)", car.Price))
		return
	end
	DataService.Update(player, function(profile)
		profile.OwnedCars[car.Id] = { Upgrades = {}, Color = CarCatalog.DefaultColor }
		profile.SelectedCar = car.Id
	end)
	notify(player, Locale.Msg("Bought %s!", car.Name), "money")
	VehicleService.RebuildCar(player)
end

local function selectCar(player: Player, data: DataService.PlayerData, car: CarCatalog.Car)
	if not data.OwnedCars[car.Id] or data.SelectedCar == car.Id then
		return
	end
	DataService.Update(player, function(profile)
		profile.SelectedCar = car.Id
	end)
	VehicleService.RebuildCar(player)
end

local function upgrade(player: Player, data: DataService.PlayerData, car: CarCatalog.Car, upgradeId: string)
	local owned = data.OwnedCars[car.Id]
	local definition = CarCatalog.FindUpgrade(upgradeId)
	if not owned or not definition then
		return
	end
	local level = owned.Upgrades[definition.Id] or 0
	local cost = definition.Costs[level + 1]
	if not cost then
		notify(player, Locale.Msg("%s is already maxed", Locale.Msg(definition.Name)))
		return
	end
	if not EconomyService.Spend(player, cost) then
		notify(player, Locale.Msg("Not enough money (%d kr)", cost))
		return
	end
	DataService.Update(player, function(profile)
		local carData = profile.OwnedCars[car.Id]
		carData.Upgrades[definition.Id] = level + 1
	end)
	notify(player, Locale.Msg("%s level %d!", Locale.Msg(definition.Name), level + 1), "money")
	if data.SelectedCar == car.Id then
		VehicleService.RefreshCar(player)
	end
end

local function paint(player: Player, data: DataService.PlayerData, car: CarCatalog.Car, colorId: string)
	local owned = data.OwnedCars[car.Id]
	local color = CarCatalog.FindColor(colorId)
	if not owned or not color or owned.Color == color.Id then
		return
	end
	if color.Pass and player:GetAttribute("Pass_" .. color.Pass) ~= true then
		notify(player, Locale.Msg("%s needs VIP Paint (in the SHOP)", Locale.Msg(color.Name)))
		return
	end
	if color.Unlock and player:GetAttribute("Unlock_" .. color.Unlock) ~= true then
		local how = if color.Unlock == "AllSalmon" then "Find all hidden salmon" else "Join the game's Roblox group"
		notify(player, Locale.Msg("%s is locked: %s", Locale.Msg(color.Name), Locale.Msg(how)))
		return
	end
	if not EconomyService.Spend(player, CarCatalog.PaintCost) then
		notify(player, Locale.Msg("Not enough money (%d kr)", CarCatalog.PaintCost))
		return
	end
	DataService.Update(player, function(profile)
		profile.OwnedCars[car.Id].Color = color.Id
	end)
	notify(player, Locale.Msg("Painted %s", Locale.Msg(color.Name)), "money")
	if data.SelectedCar == car.Id then
		VehicleService.RefreshCar(player)
	end
end

local function onGarageAction(player: Player, action: unknown, carId: unknown, arg: unknown)
	-- Validering av indata
	if typeof(action) ~= "string" or not ACTIONS[action] then
		return
	end
	if typeof(carId) ~= "string" or #carId > 40 then
		return
	end
	if arg ~= nil and (typeof(arg) ~= "string" or #(arg :: string) > 40) then
		return
	end
	local now = os.clock()
	if now - (lastAction[player] or 0) < ACTION_COOLDOWN then
		return
	end
	lastAction[player] = now

	local car = CarCatalog.FindCar(carId :: string)
	local data = DataService.Get(player)
	if not car or not data then
		return
	end
	if not PlayerMode.IsFree(player) then
		notify(player, "The garage is closed right now – finish what you're doing first")
		return
	end

	if action == "Buy" then
		buy(player, data, car)
	elseif action == "Select" then
		selectCar(player, data, car)
	elseif action == "Upgrade" then
		upgrade(player, data, car, (arg :: string?) or "")
	elseif action == "Paint" then
		paint(player, data, car, (arg :: string?) or "")
	end
end

function GarageService.Init()
	notifyRemote = Remotes.Get("Notify")
	profileRemote = Remotes.Get("ProfileUpdated")
	Remotes.Get("GarageAction").OnServerEvent:Connect(onGarageAction)
end

function GarageService.Start()
	DataService.Changed:Connect(function(player: Player, data)
		if player.Parent == Players then
			sendProfile(player, data)
		end
	end)
	local function onPlayer(player: Player)
		task.spawn(function()
			local data = DataService.WaitForData(player)
			if data then
				sendProfile(player, data)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
	end)
end

return GarageService
