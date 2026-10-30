--!strict
-- Topplistor med OrderedDataStore: veckans race, veckans takedowns och rekordet genom tiderna.
--  * Värden lämnas in av ChallengeService (Submit) och skrivs högst var LeaderboardWriteInterval:e
--    sekund per spelare och lista. Tider sparas i millisekunder (heltal).
--  * Listorna hämtas var LeaderboardRefresh:e sekund och skickas till alla (LeaderboardState).
--  * Tavlan på Stora torg byggs här (stolpar och skylt med taggen "LeaderboardBoard");
--    texten ritas av klienten, så att den hamnar på spelarens språk.
-- Utan DataStore (opublicerat place i Studio) blir listorna tomma.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local ChallengeConfig = require(ReplicatedStorage.Shared.Config.ChallengeConfig)
local CommunityConfig = require(ReplicatedStorage.Shared.Config.CommunityConfig)
local RaceConfig = require(ReplicatedStorage.Shared.Config.RaceConfig)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Geometry = require(script.Parent.Parent.Map.Geometry)

local LeaderboardService = {}

type Board = {
	Id: string,
	Title: Locale.Message,
	StoreName: () -> string,
	Ascending: boolean,
	Format: string, -- "time" | "count"
}

local stateRemote: RemoteEvent
local pending: { [string]: { [number]: number } } = {} -- board-id -> userId -> värde
local lastWrite: { [string]: number } = {} -- "board:userId" -> os.clock()
local names: { [number]: string } = {}
local lastState: { [string]: any }? = nil

local function weekly(): number
	return ChallengeConfig.Week(os.time())
end

local function raceName(id: string): string
	local race = RaceConfig.Find(id)
	return if race then race.Name else id
end

local function boards(): { Board }
	local weeklyRace = ChallengeConfig.Weekly.RaceId
	local list: { Board } = {
		{
			Id = "WeeklyTime",
			Title = Locale.Msg("Race of the week: %s", raceName(weeklyRace)),
			StoreName = function()
				return ("LB_WeeklyTime_%s_%d"):format(weeklyRace, weekly())
			end,
			Ascending = true,
			Format = "time",
		},
		{
			Id = "WeeklyTakedowns",
			Title = "Takedowns this week",
			StoreName = function()
				return ("LB_WeeklyTakedowns_%d"):format(weekly())
			end,
			Ascending = false,
			Format = "count",
		},
	}
	for _, race in RaceConfig.Races do
		table.insert(list, {
			Id = "BestTime_" .. race.Id,
			Title = Locale.Msg("All-time record: %s", race.Name),
			StoreName = function()
				return "LB_BestTime_" .. race.Id
			end,
			Ascending = true,
			Format = "time",
		})
	end
	return list
end

local function findBoard(id: string): Board?
	for _, board in boards() do
		if board.Id == id then
			return board
		end
	end
	return nil
end

local function storeValue(board: Board, value: number): number
	return if board.Format == "time" then math.floor(value * 1000 + 0.5) else math.floor(value)
end

-- Lämnar in ett nytt värde för spelaren. Skrivs vid nästa skrivrunda.
function LeaderboardService.Submit(player: Player, boardId: string, value: number)
	if typeof(value) ~= "number" or value ~= value or value <= 0 or not findBoard(boardId) then
		return
	end
	pending[boardId] = pending[boardId] or {}
	pending[boardId][player.UserId] = value
end

local function writePending(force: boolean)
	local now = os.clock()
	for boardId, values in pending do
		local board = findBoard(boardId)
		if board then
			for userId, value in values do
				local key = boardId .. ":" .. userId
				if force or now - (lastWrite[key] or -math.huge) >= CommunityConfig.LeaderboardWriteInterval then
					lastWrite[key] = now
					values[userId] = nil
					local ok, err = pcall(function()
						DataStoreService:GetOrderedDataStore(board.StoreName()):SetAsync(tostring(userId), storeValue(board, value))
					end)
					if not ok then
						warn("[LeaderboardService] Kunde inte spara topplistan: " .. tostring(err))
					end
				end
			end
		end
	end
end

local function nameOf(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	local name = if player then player.Name else nil
	if not name then
		local ok, result = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		name = if ok and typeof(result) == "string" then result else "?"
	end
	names[userId] = name :: string
	return name :: string
end

local function refresh()
	local result = {}
	for _, board in boards() do
		local entries = {}
		local ok, page = pcall(function()
			local pages = DataStoreService:GetOrderedDataStore(board.StoreName()):GetSortedAsync(board.Ascending, CommunityConfig.LeaderboardSize)
			return pages:GetCurrentPage()
		end)
		if ok and typeof(page) == "table" then
			for rank, entry in page do
				local userId = tonumber(entry.key)
				local value = tonumber(entry.value)
				if userId and value then
					table.insert(entries, {
						Rank = rank,
						UserId = userId,
						Name = nameOf(userId),
						Value = if board.Format == "time" then value / 1000 else value,
					})
				end
			end
		end
		table.insert(result, { Id = board.Id, Title = board.Title, Format = board.Format, Entries = entries })
	end
	local state = {
		Boards = result,
		Weekly = {
			RaceName = raceName(ChallengeConfig.Weekly.RaceId),
			Target = ChallengeConfig.Weekly.TargetTime,
			Reward = ChallengeConfig.Weekly.Reward,
			EndsAt = (weekly() + 1) * 7 * 86400 - 3 * 86400,
		},
	}
	lastState = state
	stateRemote:FireAllClients(state)
end

-- Tavlan på Stora torg: en skylt på två stolpar som man kan köra under.
local function buildBoard()
	local folder = Instance.new("Model")
	folder.Name = "LeaderboardBoard"
	local base = CommunityConfig.BoardPosition
	local dark = Color3.fromRGB(30, 32, 40)
	for _, side in { -1, 1 } do
		Geometry.Obstacle(Geometry.Cylinder(folder, "Pole", base + Vector3.new(side * 21, 0, 0), 0.6, 28, dark, Enum.Material.Metal))
	end
	local center = base + Vector3.new(0, 19, 0)
	local panel = Geometry.Part(folder, "Panel", Vector3.new(44, 18, 1), CFrame.lookAt(center, center + Vector3.zAxis), Color3.fromRGB(18, 20, 30))
	CollectionService:AddTag(panel, "LeaderboardBoard")
	folder.Parent = workspace
end

function LeaderboardService.Init()
	stateRemote = Remotes.Get("LeaderboardState")
end

function LeaderboardService.Start()
	buildBoard()
	Players.PlayerAdded:Connect(function(player)
		local state = lastState
		if state then
			stateRemote:FireClient(player, state)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		names[player.UserId] = player.Name
	end)
	game:BindToClose(function()
		writePending(true)
	end)
	task.spawn(function()
		while true do
			writePending(false)
			refresh()
			task.wait(CommunityConfig.LeaderboardRefresh)
		end
	end)
end

return LeaderboardService
