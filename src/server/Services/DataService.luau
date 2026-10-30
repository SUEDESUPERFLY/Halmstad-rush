--!strict
-- Sparad spelardata med DataStore.
--
--  * Retry med exponentiell backoff på varje anrop.
--  * Sessionslås: posten innehåller `_lock = { JobId, Time }`. En server laddar bara om ingen annan
--    server har ett färskt lås (äldre än LockTimeout räknas som övergivet efter en krasch).
--    Annars väntar vi och försöker igen, och kickar till sist med en vänlig förklaring.
--  * Versionerat schema: `sanitize` migrerar och validerar allt som läses in.
--  * Autosparning, sparning när spelaren går och vid serveravstängning (BindToClose).
--  * Misslyckas laddningen sparas profilen ALDRIG (så att riktig data inte skrivs över med tom).
--  * Opublicerat place eller Studio utan API-åtkomst: data hålls bara i minnet, och spelaren får veta det.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarCatalog = require(ReplicatedStorage.Shared.Config.CarCatalog)
local DataConfig = require(ReplicatedStorage.Shared.Config.DataConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

export type CarData = {
	Upgrades: { [string]: number },
	Color: string,
}

export type PlayerData = {
	Version: number,
	Money: number,
	Takedowns: number,
	OwnedCars: { [string]: CarData },
	SelectedCar: string,
	Stats: { RacesFinished: number, RacesWon: number },
}

type Profile = {
	Data: PlayerData,
	Persistent: boolean,
	Dirty: boolean,
}

local DataService = {}

DataService.Loaded = Signal.new() -- (player, data)
DataService.Changed = Signal.new() -- (player, data)

local profiles: { [Player]: Profile } = {}
local store: DataStore? = nil
local persistent = false
local notifyRemote: RemoteEvent

local function defaultData(): PlayerData
	return {
		Version = DataConfig.SchemaVersion,
		Money = 0,
		Takedowns = 0,
		OwnedCars = {
			[CarCatalog.StarterCar] = { Upgrades = {}, Color = CarCatalog.DefaultColor },
		},
		SelectedCar = CarCatalog.StarterCar,
		Stats = { RacesFinished = 0, RacesWon = 0 },
	}
end

local function wholeNumber(value: any, max: number?): number
	local n = tonumber(value)
	if not n or n ~= n then
		return 0
	end
	return math.clamp(math.floor(n), 0, max or 1e12)
end

-- Migrerar äldre versioner och validerar allt. Okända bilar och färger kastas, nivåer kläms.
local function sanitize(raw: any): PlayerData
	local source = if type(raw) == "table" then raw else {}
	-- Migreringar läggs här när schemat ändras, t.ex.:
	-- if (source.Version or 0) < 2 then source.NyttFält = ... end
	local data = defaultData()
	data.Money = wholeNumber(source.Money)
	data.Takedowns = wholeNumber(source.Takedowns)

	if type(source.OwnedCars) == "table" then
		for carId, carData in source.OwnedCars do
			if type(carId) == "string" and CarCatalog.FindCar(carId) and type(carData) == "table" then
				local upgrades = {}
				for _, upgrade in CarCatalog.Upgrades do
					local level = if type(carData.Upgrades) == "table" then carData.Upgrades[upgrade.Id] else 0
					upgrades[upgrade.Id] = wholeNumber(level, #upgrade.Costs)
				end
				local color = if type(carData.Color) == "string" and CarCatalog.FindColor(carData.Color)
					then carData.Color
					else CarCatalog.DefaultColor
				data.OwnedCars[carId] = { Upgrades = upgrades, Color = color }
			end
		end
	end
	if type(source.SelectedCar) == "string" and data.OwnedCars[source.SelectedCar] then
		data.SelectedCar = source.SelectedCar
	end
	if type(source.Stats) == "table" then
		data.Stats.RacesFinished = wholeNumber(source.Stats.RacesFinished)
		data.Stats.RacesWon = wholeNumber(source.Stats.RacesWon)
	end
	data.Version = DataConfig.SchemaVersion
	return data
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

local function withRetries(label: string, callback: () -> any): (boolean, any)
	for attempt = 1, DataConfig.Retries do
		local ok, result = pcall(callback)
		if ok then
			return true, result
		end
		warn(("[DataService] %s misslyckades (försök %d/%d): %s"):format(label, attempt, DataConfig.Retries, tostring(result)))
		if attempt < DataConfig.Retries then
			task.wait(DataConfig.RetryBaseDelay * 2 ^ (attempt - 1))
		end
	end
	return false, nil
end

local function keyFor(player: Player): string
	return DataConfig.KeyPrefix .. player.UserId
end

local function save(player: Player, release: boolean): boolean
	local profile = profiles[player]
	local dataStore = store
	if not profile or not profile.Persistent or not dataStore then
		return false
	end
	local snapshot = deepCopy(profile.Data)
	local stolen = false
	local ok = withRetries("Spara " .. player.Name, function()
		return dataStore:UpdateAsync(keyFor(player), function(old: any)
			stolen = false
			local lock = if type(old) == "table" then old._lock else nil
			if type(lock) == "table" and lock.JobId ~= game.JobId then
				stolen = true -- en annan server har tagit över; skriv inte över deras data
				return nil
			end
			local out = deepCopy(snapshot)
			out._lock = if release then nil else { JobId = game.JobId, Time = os.time() }
			return out
		end)
	end)
	if ok and not stolen then
		profile.Dirty = false
	end
	return ok and not stolen
end

local function finishLoading(player: Player, profile: Profile)
	profiles[player] = profile
	DataService.Loaded:Fire(player, profile.Data)
	DataService.Changed:Fire(player, profile.Data)
end

local function load(player: Player)
	local dataStore = store
	if not persistent or not dataStore then
		finishLoading(player, { Data = defaultData(), Persistent = false, Dirty = false })
		task.delay(3, function()
			notifyRemote:FireClient(player, "Progress is not saved in this test (DataStore off)", "info")
		end)
		return
	end

	for _ = 1, DataConfig.LockWaitAttempts do
		local lockedElsewhere = false
		local ok, result = withRetries("Ladda " .. player.Name, function()
			return dataStore:UpdateAsync(keyFor(player), function(old: any)
				lockedElsewhere = false
				local lock = if type(old) == "table" then old._lock else nil
				if type(lock) == "table" and lock.JobId ~= game.JobId and os.time() - (tonumber(lock.Time) or 0) < DataConfig.LockTimeout then
					lockedElsewhere = true
					return nil
				end
				local data: any = sanitize(old)
				data._lock = { JobId = game.JobId, Time = os.time() }
				return data
			end)
		end)

		if player.Parent ~= Players then
			-- Spelaren hann gå. Släpp låset om vi tog det.
			if ok and not lockedElsewhere then
				profiles[player] = { Data = sanitize(result), Persistent = true, Dirty = false }
				save(player, true)
				profiles[player] = nil
			end
			return
		end

		if not ok then
			-- DataStore svarar inte: spela vidare utan sparning, men skriv aldrig över riktig data.
			finishLoading(player, { Data = defaultData(), Persistent = false, Dirty = false })
			notifyRemote:FireClient(player, "Could not load your progress – it won't be saved this time. Please rejoin later.", "info")
			return
		end
		if not lockedElsewhere then
			finishLoading(player, { Data = sanitize(result), Persistent = true, Dirty = false })
			return
		end
		task.wait(DataConfig.LockWaitDelay)
	end

	player:Kick("Your progress is still being saved on another server. Please rejoin in a minute.")
end

-- Väntar tills spelarens data är laddad. Returnerar nil om spelaren lämnade eller vid timeout.
function DataService.WaitForData(player: Player, timeout: number?): PlayerData?
	local deadline = os.clock() + (timeout or DataConfig.LoadTimeout)
	while not profiles[player] and player.Parent == Players and os.clock() < deadline do
		task.wait(0.1)
	end
	local profile = profiles[player]
	return profile and profile.Data
end

function DataService.Get(player: Player): PlayerData?
	local profile = profiles[player]
	return profile and profile.Data
end

-- All ändring av sparad data går genom Update, som markerar profilen för sparning
-- och meddelar lyssnare (leaderstats, garage-UI).
function DataService.Update(player: Player, mutate: (data: PlayerData) -> ()): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	mutate(profile.Data)
	profile.Dirty = true
	DataService.Changed:Fire(player, profile.Data)
	return true
end

function DataService.IsPersistent(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and profile.Persistent
end

function DataService.Init()
	notifyRemote = Remotes.Get("Notify")
	if game.PlaceId == 0 then
		warn("[DataService] Placet är inte publicerat: data sparas bara i minnet.")
		return
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(DataConfig.StoreName)
	end)
	if not ok then
		warn("[DataService] DataStore otillgänglig: " .. tostring(result))
		return
	end
	store = result
	local probeOk, probeError = pcall(function()
		return (result :: DataStore):GetAsync("__probe")
	end)
	persistent = probeOk
	if not probeOk then
		warn("[DataService] DataStore svarar inte (aktivera 'Enable Studio Access to API Services'): " .. tostring(probeError))
	end
end

function DataService.Start()
	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		if profiles[player] then
			save(player, true)
			profiles[player] = nil
		end
	end)

	task.spawn(function()
		while true do
			task.wait(DataConfig.AutosaveInterval)
			for player, profile in profiles do
				if profile.Persistent and profile.Dirty then
					task.spawn(save, player, false)
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				save(player, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
