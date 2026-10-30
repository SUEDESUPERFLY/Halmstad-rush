--!strict
-- Butiken: game passes, developer products (Robux) och daglig belöning (kronor).
--
--  * Game passes kontrolleras med UserOwnsGamePassAsync när spelaren kommer in och när ett
--    köp går igenom. Ägandet läggs som attribut på spelaren ("Pass_<Key>") så att andra
--    services kan läsa det utan att anropa MarketplaceService.
--  * ProcessReceipt är idempotent: köp-ID:t sparas i profilen (och sparas direkt) innan köpet
--    bekräftas, så att samma köp aldrig delas ut två gånger.
--  * Daglig belöning räknas med serverns klocka (UTC-dag) och sparas i profilen.
--  * I Studio kan pass och produkter provas utan riktiga köp (ShopConfig.StudioTestPurchases).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local VehicleService = require(script.Parent.VehicleService)

local ShopService = {}

local ACTION_COOLDOWN = 0.5
local lastAction: { [Player]: number } = {}
local remotes: { [string]: RemoteEvent } = {}

local function today(): number
	return math.floor(os.time() / 86400)
end

local function dailyStatus(player: Player)
	local data = DataService.Get(player)
	if not data then
		return { Available = false, Streak = 0, Reward = 0 }
	end
	local day = today()
	local available = data.Daily.LastDay ~= day
	local streak = if data.Daily.LastDay == day - 1 or data.Daily.LastDay == day then data.Daily.Streak else 0
	local nextStreak = if available then streak + 1 else streak
	return { Available = available, Streak = streak, Reward = ShopConfig.DailyReward(math.max(nextStreak, 1)) }
end

local function sendState(player: Player)
	local passes = {}
	for _, pass in ShopConfig.Passes do
		passes[pass.Key] = player:GetAttribute(ShopConfig.PassAttribute(pass.Key)) == true
	end
	remotes.ShopState:FireClient(player, {
		Passes = passes,
		Daily = dailyStatus(player),
		Studio = RunService:IsStudio() and ShopConfig.StudioTestPurchases,
	})
end

local function setPass(player: Player, key: string, owned: boolean)
	local attribute = ShopConfig.PassAttribute(key)
	if player:GetAttribute(attribute) == owned then
		return
	end
	player:SetAttribute(attribute, owned)
	if key == "Underglow" then
		VehicleService.RebuildCar(player)
	end
	sendState(player)
end

local function checkPasses(player: Player)
	for _, pass in ShopConfig.Passes do
		if pass.Id ~= 0 then
			for _ = 1, 3 do
				local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.Id)
				if ok then
					if owns then
						setPass(player, pass.Key, true)
					end
					break
				end
				task.wait(2)
			end
		end
	end
end

-- Effekten av en developer product
local function grantProduct(player: Player, key: string)
	if key == "Confetti" then
		local car = VehicleService.GetCar(player)
		if car and car.PrimaryPart then
			remotes.Celebrate:FireAllClients(car.PrimaryPart.Position)
		end
		remotes.Notify:FireClient(player, "Confetti! 🎉", "money")
	elseif key == "Support" then
		remotes.Notify:FireClient(player, "Thanks for the support! ❤", "money")
	end
end

local function processReceipt(info: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = DataService.WaitForData(player, 10)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(info.PurchaseId)
	if table.find(data.Receipts, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- redan utdelat
	end
	local product = nil
	for _, candidate in ShopConfig.Products do
		if candidate.Id == info.ProductId then
			product = candidate
		end
	end
	if not product then
		warn("[ShopService] Okänd produkt: " .. tostring(info.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Dela ut, kom ihåg köpet och spara. Misslyckas sparningen försöker Roblox igen senare,
	-- men då finns köp-ID:t redan i profilen och köpet delas inte ut en gång till.
	grantProduct(player, product.Key)
	DataService.AddReceipt(player, purchaseId)
	if DataService.IsPersistent(player) and not DataService.SaveNow(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function claimDaily(player: Player)
	local status = dailyStatus(player)
	if not status.Available then
		remotes.Notify:FireClient(player, "You have already collected today's reward", "info")
		return
	end
	local streak = status.Streak + 1
	local reward = ShopConfig.DailyReward(streak)
	local ok = DataService.Update(player, function(data)
		data.Daily.LastDay = today()
		data.Daily.Streak = streak
	end)
	if ok then
		EconomyService.AddMoney(player, reward, Locale.Msg("Daily reward (day %d in a row)", streak))
		sendState(player)
	end
end

local function onShopAction(player: Player, action: unknown, key: unknown)
	local now = os.clock()
	if now - (lastAction[player] or 0) < ACTION_COOLDOWN then
		return
	end
	lastAction[player] = now
	if action == "ClaimDaily" then
		claimDaily(player)
	elseif action == "StudioTest" then
		-- Bara i Studio: prova pass och produkter utan riktiga köp
		if not (RunService:IsStudio() and ShopConfig.StudioTestPurchases) or typeof(key) ~= "string" then
			return
		end
		local pass = ShopConfig.FindPass(key :: string)
		if pass then
			setPass(player, pass.Key, player:GetAttribute(ShopConfig.PassAttribute(pass.Key)) ~= true)
		elseif ShopConfig.FindProduct(key :: string) then
			grantProduct(player, key :: string)
		end
	end
end

function ShopService.HasPass(player: Player, key: string): boolean
	return player:GetAttribute(ShopConfig.PassAttribute(key)) == true
end

function ShopService.Init()
	for _, name in { "ShopState", "Celebrate", "Notify" } do
		remotes[name] = Remotes.Get(name)
	end
	Remotes.Get("ShopAction").OnServerEvent:Connect(onShopAction)
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		if not purchased then
			return
		end
		for _, pass in ShopConfig.Passes do
			if pass.Id == passId and pass.Id ~= 0 then
				setPass(player, pass.Key, true)
				remotes.Notify:FireClient(player, Locale.Msg("Thanks! %s is yours.", Locale.Msg(pass.Name)), "money")
			end
		end
	end)
end

function ShopService.Start()
	local function onPlayer(player: Player)
		task.spawn(function()
			checkPasses(player)
			if DataService.WaitForData(player) then
				sendState(player)
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

return ShopService
