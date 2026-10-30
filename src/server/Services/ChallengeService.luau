--!strict
-- Dagliga utmaningar, kom igång-guiden och veckans race. Allt räknas här på servern:
--  * från GameEvents (takedowns, målgångar, aktiviteter, laxar), som servern själv avgjort
--  * från bilarnas replikerade rörelse: körd sträcka, sladd och boost. Farten är redan
--    begränsad av VehicleService, och teleporter räknas inte som körd sträcka.
-- Klienten får bara visningsdata (GoalsState).

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChallengeConfig = require(ReplicatedStorage.Shared.Config.ChallengeConfig)
local CommunityConfig = require(ReplicatedStorage.Shared.Config.CommunityConfig)
local RaceConfig = require(ReplicatedStorage.Shared.Config.RaceConfig)
local VehicleConfig = require(ReplicatedStorage.Shared.Config.VehicleConfig)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameEvents = require(script.Parent.Parent.Util.GameEvents)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local VehicleService = require(script.Parent.VehicleService)

local ChallengeService = {}

local C = ChallengeConfig
local goalsRemote: RemoteEvent

type Sample = { Position: Vector3, Meters: number, Drift: number, Boost: number }
local samples: { [Player]: Sample } = {}

local function today(): number
	return C.Day(os.time())
end

local function thisWeek(): number
	return C.Week(os.time())
end

-- Nollställer dagens och veckans siffror när en ny dag eller vecka börjat (anropas inuti Update).
local function rollOver(data: DataService.PlayerData)
	local day = today()
	if data.Challenges.Day ~= day then
		data.Challenges = { Day = day, Progress = {}, Claimed = {}, Bonus = false }
	end
	local week = thisWeek()
	if data.Weekly.Week ~= week then
		data.Weekly = { Week = week, Takedowns = 0, BestTime = 0, TargetClaimed = false }
	end
end

local function salmonFound(data: DataService.PlayerData): number
	local count = 0
	for _ in data.Salmon do
		count += 1
	end
	return count
end

local function tutorialActive(data: DataService.PlayerData): boolean
	return data.Tutorial.Step <= #C.Tutorial
end

-- Visningsdata till klientens utmaningspanel.
local function sendState(player: Player)
	local data = DataService.Get(player)
	if not data or player.Parent ~= Players then
		return
	end
	local items = {}
	local state: { [string]: any } = {}
	if tutorialActive(data) then
		state.Mode = "Tutorial"
		for index, step in C.Tutorial do
			local progress = if index < data.Tutorial.Step then step.Goal elseif index == data.Tutorial.Step then data.Tutorial.Progress else 0
			table.insert(items, {
				Text = Locale.Msg(step.Text, step.Goal),
				Progress = math.floor(progress),
				Goal = step.Goal,
				Reward = step.Reward,
				Done = index < data.Tutorial.Step,
			})
		end
	else
		state.Mode = "Daily"
		for _, goal in C.ForDay(today()) do
			local claimed = data.Challenges.Claimed[goal.Id] == true
			table.insert(items, {
				Text = Locale.Msg(goal.Text, goal.Goal),
				Progress = if claimed then goal.Goal else math.floor(data.Challenges.Progress[goal.Id] or 0),
				Goal = goal.Goal,
				Reward = goal.Reward,
				Done = claimed,
			})
		end
		state.Bonus = { Reward = C.AllDoneBonus, Done = data.Challenges.Bonus }
		state.ResetsAt = (today() + 1) * 86400 -- nästa dygn (UTC), klienten räknar ner
	end
	state.Items = items
	local race = RaceConfig.Find(C.Weekly.RaceId)
	state.Weekly = {
		RaceName = if race then race.Name else C.Weekly.RaceId,
		Target = C.Weekly.TargetTime,
		Best = data.Weekly.BestTime,
		Reward = C.Weekly.Reward,
		Done = data.Weekly.TargetClaimed,
	}
	state.Salmon = { Found = salmonFound(data), Total = #CommunityConfig.Salmon }
	goalsRemote:FireClient(player, state)
end

local function logFunnel(player: Player, step: number, name: string)
	pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name)
	end)
end

-- Räknar upp en händelse mot guiden, dagens utmaningar och veckans siffror.
local function apply(player: Player, kind: string, amount: number, info: { [string]: any })
	local data = DataService.Get(player)
	if not data then
		return
	end
	local payouts: { { Amount: number, Reason: Locale.Message } } = {}
	local events: { string } = {}
	local tutorialStepDone: number? = nil
	local tutorialFinished = false

	DataService.Update(player, function(d)
		rollOver(d)

		-- Kom igång-guiden: bara det aktuella steget räknas
		if tutorialActive(d) then
			local step = C.Tutorial[d.Tutorial.Step]
			if step.Kind == kind then
				d.Tutorial.Progress += amount
				if d.Tutorial.Progress >= step.Goal then
					table.insert(payouts, { Amount = step.Reward, Reason = Locale.Msg("Step done: %s", Locale.Msg(step.Text, step.Goal)) })
					tutorialStepDone = d.Tutorial.Step
					d.Tutorial.Step += 1
					d.Tutorial.Progress = 0
					tutorialFinished = not tutorialActive(d)
				end
			end
		end

		-- Dagens utmaningar
		local allDone = true
		for _, goal in C.ForDay(today()) do
			if not d.Challenges.Claimed[goal.Id] then
				if goal.Kind == kind then
					local progress = math.min(goal.Goal, (d.Challenges.Progress[goal.Id] or 0) + amount)
					d.Challenges.Progress[goal.Id] = progress
					if progress >= goal.Goal then
						d.Challenges.Claimed[goal.Id] = true
						table.insert(payouts, { Amount = goal.Reward, Reason = Locale.Msg("Challenge done: %s", Locale.Msg(goal.Text, goal.Goal)) })
					end
				end
			end
			if not d.Challenges.Claimed[goal.Id] then
				allDone = false
			end
		end
		if allDone and not d.Challenges.Bonus then
			d.Challenges.Bonus = true
			table.insert(payouts, { Amount = C.AllDoneBonus, Reason = "All daily challenges done!" })
			table.insert(events, "DailyAll")
		end

		-- Veckans siffror och bästa tider
		if kind == "Takedown" then
			d.Weekly.Takedowns += amount
			LeaderboardService.Submit(player, "WeeklyTakedowns", d.Weekly.Takedowns)
		elseif kind == "RaceFinished" and typeof(info.Time) == "number" and typeof(info.RaceId) == "string" then
			local time = info.Time :: number
			local raceId = info.RaceId :: string
			local best = d.Best[raceId]
			if not best or best == 0 or time < best then
				d.Best[raceId] = time
				LeaderboardService.Submit(player, "BestTime_" .. raceId, time)
			end
			if raceId == C.Weekly.RaceId then
				if d.Weekly.BestTime == 0 or time < d.Weekly.BestTime then
					d.Weekly.BestTime = time
					LeaderboardService.Submit(player, "WeeklyTime", time)
				end
				if time <= C.Weekly.TargetTime and not d.Weekly.TargetClaimed then
					d.Weekly.TargetClaimed = true
					table.insert(payouts, { Amount = C.Weekly.Reward, Reason = "Race of the week: target beaten!" })
				end
			end
		end
	end)

	for _, payout in payouts do
		EconomyService.AddMoney(player, payout.Amount, payout.Reason)
	end
	for _, event in events do
		GameEvents.Fire(player, event)
	end
	local stepDone = tutorialStepDone
	if stepDone then
		logFunnel(player, stepDone + 1, C.Tutorial[stepDone].Id)
	end
	if tutorialFinished then
		Remotes.Get("Notify"):FireClient(player, "Tutorial complete! Daily challenges unlocked.", "takedown")
	end
	sendState(player)
end

-- Körd sträcka, sladd och boost från bilarnas rörelse (servern ser den replikerade farten).
local function sampleCars()
	local T = VehicleConfig.Tuning
	local cars = VehicleService.GetCars()
	for player, car in cars do
		local root = car.PrimaryPart
		if root then
			local sample = samples[player]
			local position = root.Position
			if not sample then
				samples[player] = { Position = position, Meters = 0, Drift = 0, Boost = 0 }
			else
				local moved = ((position - sample.Position) * Vector3.new(1, 0, 1)).Magnitude
				if moved <= C.MaxStudsPerSample then
					sample.Meters += moved * C.MetersPerStud
				end
				sample.Position = position
				local velocity = root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
				local speed = velocity.Magnitude
				local lateral = math.abs(velocity:Dot(root.CFrame.RightVector))
				if speed > C.DriftMinSpeed and lateral > C.DriftMinLateral then
					sample.Drift += C.SampleInterval
				end
				local topSpeed = T.MaxSpeed * (tonumber(car:GetAttribute("TopSpeedMul")) or 1)
				if speed > topSpeed * C.BoostOverTopSpeed then
					sample.Boost += C.SampleInterval
				end
			end
		end
	end
	for player in samples do
		if not cars[player] then
			samples[player] = nil
		end
	end
end

-- Skickar ihopsamlad sträcka och sekunder som händelser (hela meter och sekunder).
local function flushSamples()
	for player, sample in samples do
		local meters = math.floor(sample.Meters)
		if meters >= 10 then
			sample.Meters -= meters
			GameEvents.Fire(player, "Distance", meters)
		end
		local drift = math.floor(sample.Drift)
		if drift >= 1 then
			sample.Drift -= drift
			GameEvents.Fire(player, "Drift", drift)
		end
		local boost = math.floor(sample.Boost)
		if boost >= 1 then
			sample.Boost -= boost
			GameEvents.Fire(player, "Boost", boost)
		end
	end
end

function ChallengeService.Init()
	goalsRemote = Remotes.Get("GoalsState")
end

function ChallengeService.Start()
	GameEvents.Fired:Connect(function(player: Player, kind: string, amount: number, info: { [string]: any })
		if player.Parent == Players then
			apply(player, kind, amount, info)
		end
	end)

	local function onPlayer(player: Player)
		task.spawn(function()
			local data = DataService.WaitForData(player)
			if not data then
				return
			end
			DataService.Update(player, rollOver)
			if salmonFound(data) >= #CommunityConfig.Salmon then
				apply(player, "SalmonFound", 99, {}) -- alla laxar redan hittade: laxutmaningen räknas som klar
			end
			if tutorialActive(data) and data.Tutorial.Step == 1 and data.Tutorial.Progress == 0 then
				logFunnel(player, 1, "Joined")
			end
			sendState(player)
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		samples[player] = nil
	end)

	-- Ny dag: skicka nya utmaningar till alla
	task.spawn(function()
		local lastDay = today()
		while true do
			task.wait(30)
			if today() ~= lastDay then
				lastDay = today()
				for _, player in Players:GetPlayers() do
					DataService.Update(player, rollOver)
					sendState(player)
				end
			end
		end
	end)

	task.spawn(function()
		local sinceFlush = 0
		while true do
			task.wait(C.SampleInterval)
			sampleCars()
			sinceFlush += C.SampleInterval
			if sinceFlush >= 2 then
				sinceFlush = 0
				flushSamples()
			end
		end
	end)
end

-- Skickar panelens innehåll igen (t.ex. när en lax hittats).
function ChallengeService.Refresh(player: Player)
	sendState(player)
end

return ChallengeService
