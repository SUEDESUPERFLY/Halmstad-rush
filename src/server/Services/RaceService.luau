--!strict
-- Race i Halmstads gator. Servern avgör allt: vem som är med, kontrollpunkter (i ordning),
-- placering, måltid och belöning. Klienten visar bara portar, nedräkning och resultat.
--
-- Flöde: Idle -> Lobby (andra kan gå med) -> Countdown (alla på startgriden) -> Running -> Cooldown.
-- Under racet ligger deltagarna i kollisionsgruppen RaceCars: de krockar med varandra och trafiken
-- men är fortfarande spöken för spelare som inte kör racet.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local RaceConfig = require(ReplicatedStorage.Shared.Config.RaceConfig)
local VehicleConfig = require(ReplicatedStorage.Shared.Config.VehicleConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Geometry = require(script.Parent.Parent.Map.Geometry)
local CrashService = require(script.Parent.CrashService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local NpcService = require(script.Parent.NpcService)
local RespawnService = require(script.Parent.RespawnService)
local VehicleService = require(script.Parent.VehicleService)
local PlayerMode = require(script.Parent.Parent.Util.PlayerMode)

type Checkpoint = {
	Position: Vector3,
	Direction: Vector3,
	Progress: number, -- ruttpunkter från start till den här kontrollpunkten
}

type Participant = {
	Name: string,
	Player: Player?,
	Npc: NpcService.Npc?,
	NextCheckpoint: number,
	FinishTime: number?,
	Grid: CFrame,
	Takedowns: number,
}

type Session = {
	Race: RaceConfig.RaceDefinition,
	Route: { Vector2 },
	StartPosition: Vector3,
	Checkpoints: { Checkpoint },
	LapLength: number,
	State: string, -- "Idle" | "Lobby" | "Countdown" | "Running" | "Cooldown"
	Participants: { Participant },
	LobbyEndsAt: number,
	StartAt: number, -- servertid (workspace:GetServerTimeNow())
	FirstFinishAt: number?,
	CooldownUntil: number,
	LastBroadcast: number,
}

local RaceService = {}

local sessions: { [string]: Session } = {}
local lastInvite: { [Player]: number } = {}
local remotes: { [string]: RemoteEvent } = {}

local RIVAL_COLORS = {
	Color3.fromRGB(250, 120, 20),
	Color3.fromRGB(20, 180, 170),
	Color3.fromRGB(200, 40, 140),
	Color3.fromRGB(240, 220, 40),
}

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function wrap(index: number, count: number): number
	return (index - 1) % count + 1
end

local function routePosition(route: { Vector2 }, index: number): (Vector3, Vector3)
	local i = wrap(index, #route)
	local p = route[i]
	local before = route[wrap(i - 1, #route)]
	local after = route[wrap(i + 1, #route)]
	local direction = Vector3.new(after.X - before.X, 0, after.Y - before.Y).Unit
	return Vector3.new(p.X, MapData.GroundHeightAt(p.X, p.Y), p.Y), direction
end

local function buildCheckpoints(race: RaceConfig.RaceDefinition, route: { Vector2 }): { Checkpoint }
	local spacing = race.CheckpointSpacing
	local count = math.floor(#route / spacing)
	if #route - (count - 1) * spacing < spacing / 2 then
		count -= 1
	end
	local checkpoints = {}
	for lap = 0, race.Laps - 1 do
		for k = 1, count do
			local offset = if k == count then #route else k * spacing
			local position, direction = routePosition(route, race.StartIndex + offset)
			table.insert(checkpoints, {
				Position = position,
				Direction = direction,
				Progress = lap * #route + offset,
			})
		end
	end
	return checkpoints
end

local function gridCFrame(session: Session, slot: number): CFrame
	local row = math.floor((slot - 1) / 2)
	local side = if slot % 2 == 1 then -5 else 5
	local position, direction = routePosition(session.Route, session.Race.StartIndex - 1 - row * 2)
	local right = Vector3.new(-direction.Z, 0, direction.X)
	local at = position + right * side + Vector3.new(0, 4, 0)
	return CFrame.lookAt(at, at + direction)
end

local function findParticipant(player: Player): (Session?, Participant?)
	for _, session in sessions do
		for _, participant in session.Participants do
			if participant.Player == player then
				return session, participant
			end
		end
	end
	return nil, nil
end

local function playerCount(session: Session): number
	local count = 0
	for _, participant in session.Participants do
		if participant.Player then
			count += 1
		end
	end
	return count
end

local function progressOf(session: Session, participant: Participant): number
	if participant.Npc then
		return participant.Npc.Passed
	end
	local reached = participant.NextCheckpoint - 1
	local base = if reached > 0 then session.Checkpoints[reached].Progress else 0
	local nextCheckpoint = session.Checkpoints[participant.NextCheckpoint]
	local car = participant.Player and VehicleService.GetCar(participant.Player)
	if not nextCheckpoint or not car or not car.PrimaryPart then
		return base
	end
	local gap = nextCheckpoint.Progress - base
	local distance = (car.PrimaryPart.Position - nextCheckpoint.Position).Magnitude / 20
	return base + math.max(0, gap - distance)
end

-- Ordning: i mål (snabbast först), sedan längst kommen.
local function standings(session: Session): { Participant }
	local order = table.clone(session.Participants)
	local progress = {}
	for _, participant in order do
		progress[participant] = progressOf(session, participant)
	end
	table.sort(order, function(a, b)
		if a.FinishTime and b.FinishTime then
			return a.FinishTime < b.FinishTime
		elseif a.FinishTime or b.FinishTime then
			return a.FinishTime ~= nil
		end
		return progress[a] > progress[b]
	end)
	return order
end

local function restorePlayer(player: Player)
	VehicleService.SetCollisionGroup(player, nil)
	PlayerMode.Clear(player, "Race")
end

local function cleanup(session: Session)
	for _, participant in session.Participants do
		if participant.Player then
			restorePlayer(participant.Player)
		end
		if participant.Npc then
			NpcService.Remove(participant.Npc)
		end
	end
	session.Participants = {}
	session.FirstFinishAt = nil
	session.State = "Cooldown"
	session.CooldownUntil = os.clock() + RaceConfig.CooldownAfterRace
end

local function finishRace(session: Session)
	local order = standings(session)
	local results = {}
	for position, participant in order do
		local reward = 0
		if participant.Player and participant.FinishTime then
			local rewards = session.Race.Rewards
			reward = rewards[math.min(position, #rewards)]
		end
		if participant.Player then
			reward += participant.Takedowns * RaceConfig.TakedownBonus
		end
		table.insert(results, {
			Position = position,
			Name = participant.Name,
			Time = participant.FinishTime,
			UserId = if participant.Player then participant.Player.UserId else 0,
			Reward = reward,
			Takedowns = participant.Takedowns,
		})
	end
	for position, participant in order do
		local player = participant.Player
		if player then
			if participant.FinishTime then
				DataService.Update(player, function(data)
					data.Stats.RacesFinished += 1
					if position == 1 then
						data.Stats.RacesWon += 1
					end
				end)
			end
			for _, result in results do
				if result.UserId == player.UserId and result.Reward > 0 then
					EconomyService.AddMoney(player, result.Reward, session.Race.Name)
				end
			end
			remotes.RaceFinished:FireClient(player, { RaceName = session.Race.Name, Results = results })
		end
	end
	cleanup(session)
end

local function removePlayer(session: Session, player: Player)
	for i, participant in session.Participants do
		if participant.Player == player then
			table.remove(session.Participants, i)
			break
		end
	end
	if player.Parent == Players then
		restorePlayer(player)
		remotes.RaceFinished:FireClient(player, { Left = true })
	end
	if session.State ~= "Idle" and session.State ~= "Cooldown" and playerCount(session) == 0 then
		cleanup(session)
	end
end

local function startCountdown(session: Session)
	session.State = "Countdown"
	local slot = 0
	for _, participant in session.Participants do
		slot += 1
		participant.Grid = gridCFrame(session, slot)
		local player = participant.Player
		if player then
			VehicleService.SetCollisionGroup(player, RaceConfig.CollisionGroup)
			VehicleService.MoveCar(player, participant.Grid)
		end
	end
	local race = session.Race
	for r = 1, math.min(race.Rivals, RaceConfig.MaxParticipants - slot) do
		slot += 1
		local grid = gridCFrame(session, slot)
		local row = math.floor((slot - 1) / 2)
		local npc = NpcService.SpawnRacer(
			race.Route,
			wrap(race.StartIndex - 1 - row * 2, #session.Route),
			RIVAL_COLORS[(r - 1) % #RIVAL_COLORS + 1],
			race.RivalSpeeds[math.min(r, #race.RivalSpeeds)],
			RaceConfig.RivalWreckDuration
		)
		if npc then
			npc.Model:PivotTo(grid)
			npc.Passed = -(1 + row * 2)
			npc.SpeedScale = 0 -- står still tills GO
			table.insert(session.Participants, {
				Name = ("Rival %d"):format(r),
				Npc = npc,
				NextCheckpoint = 1,
				Grid = grid,
				Takedowns = 0,
			})
		end
	end

	session.StartAt = serverNow() + RaceConfig.Countdown
	local checkpoints = {}
	for _, checkpoint in session.Checkpoints do
		table.insert(checkpoints, { Position = checkpoint.Position, Direction = checkpoint.Direction })
	end
	for _, participant in session.Participants do
		if participant.Player then
			remotes.RaceSetup:FireClient(participant.Player, {
				RaceId = race.Id,
				Name = race.Name,
				StartAt = session.StartAt,
				Checkpoints = checkpoints,
				Participants = #session.Participants,
			})
		end
	end
end

local function updateRunning(session: Session)
	local now = serverNow()
	local elapsed = now - session.StartAt
	local total = #session.Checkpoints

	-- Spelare: kontrollpunkter i ordning
	for _, participant in session.Participants do
		local player = participant.Player
		if player and not participant.FinishTime then
			local car = VehicleService.GetCar(player)
			local checkpoint = session.Checkpoints[participant.NextCheckpoint]
			if car and car.PrimaryPart and checkpoint then
				local offset = (car.PrimaryPart.Position - checkpoint.Position) * Vector3.new(1, 0.3, 1)
				if offset.Magnitude < RaceConfig.CheckpointRadius then
					participant.NextCheckpoint += 1
					remotes.RaceCheckpoint:FireClient(player, participant.NextCheckpoint - 1)
					if participant.NextCheckpoint > total then
						participant.FinishTime = elapsed
						session.FirstFinishAt = session.FirstFinishAt or os.clock()
					end
				end
			end
		end
	end

	-- NPC-motståndare: mål när de kört hela banan. Rubber band mot ledande spelare.
	local leader = 0
	for _, participant in session.Participants do
		if participant.Player then
			leader = math.max(leader, progressOf(session, participant))
		end
	end
	for _, participant in session.Participants do
		local npc = participant.Npc
		if npc and not participant.FinishTime then
			if npc.Passed >= session.LapLength * session.Race.Laps then
				participant.FinishTime = elapsed
				session.FirstFinishAt = session.FirstFinishAt or os.clock()
				npc.SpeedScale = 0.4
			else
				local gap = (leader - npc.Passed) * RaceConfig.RubberBand
				npc.SpeedScale = 1 + math.clamp(gap, -RaceConfig.RubberBandMax, RaceConfig.RubberBandMax)
			end
		end
	end

	if os.clock() - session.LastBroadcast > 0.5 then
		session.LastBroadcast = os.clock()
		local order = standings(session)
		for position, participant in order do
			if participant.Player then
				remotes.RaceUpdate:FireClient(participant.Player, position, #order, elapsed)
			end
		end
	end

	local allPlayersDone = true
	for _, participant in session.Participants do
		if participant.Player and not participant.FinishTime then
			allPlayersDone = false
		end
	end
	local timedOut = session.FirstFinishAt ~= nil and os.clock() - session.FirstFinishAt > RaceConfig.FinishTimeout
	if allPlayersDone or timedOut or elapsed > RaceConfig.MaxRaceTime then
		finishRace(session)
	end
end

local function updateSession(session: Session)
	local state = session.State
	if state == "Lobby" then
		if os.clock() >= session.LobbyEndsAt then
			startCountdown(session)
		end
	elseif state == "Countdown" then
		-- Ingen tjuvstart: den som rullar iväg ställs tillbaka på sin ruta
		for _, participant in session.Participants do
			local player = participant.Player
			local car = player and VehicleService.GetCar(player)
			if player and car and car.PrimaryPart then
				if (car.PrimaryPart.Position - participant.Grid.Position).Magnitude > RaceConfig.GridMoveTolerance then
					VehicleService.MoveCar(player, participant.Grid)
				end
			end
		end
		if serverNow() >= session.StartAt then
			session.State = "Running"
			for _, participant in session.Participants do
				if participant.Npc then
					participant.Npc.SpeedScale = 1
				end
			end
		end
	elseif state == "Running" then
		updateRunning(session)
	elseif state == "Cooldown" then
		if os.clock() >= session.CooldownUntil then
			session.State = "Idle"
		end
	end

	-- Inbjudan till spelare vid startlinjen
	if state == "Idle" or state == "Lobby" then
		for player, car in VehicleService.GetCars() do
			local root = car.PrimaryPart
			if root and (root.Position - session.StartPosition).Magnitude < RaceConfig.StartRadius then
				local inSession = findParticipant(player)
				if not inSession and PlayerMode.IsFree(player) and os.clock() - (lastInvite[player] or 0) > 1 then
					lastInvite[player] = os.clock()
					remotes.RaceInvite:FireClient(player, session.Race.Id, session.Race.Name, state == "Lobby")
				end
			end
		end
	end
end

local function onJoinRequested(player: Player, raceId: unknown)
	if typeof(raceId) ~= "string" or #raceId > 40 then
		return
	end
	local session = sessions[raceId]
	if not session or (session.State ~= "Idle" and session.State ~= "Lobby") then
		return
	end
	if findParticipant(player) then
		return
	end
	local car = VehicleService.GetCar(player)
	if not car or not car.PrimaryPart then
		return
	end
	if (car.PrimaryPart.Position - session.StartPosition).Magnitude > RaceConfig.StartRadius * 1.5 then
		return
	end
	if playerCount(session) >= RaceConfig.MaxParticipants then
		return
	end
	if not PlayerMode.Set(player, "Race") then
		return
	end
	if session.State == "Idle" then
		session.State = "Lobby"
		session.LobbyEndsAt = os.clock() + RaceConfig.LobbyTime
		session.Participants = {}
	end
	table.insert(session.Participants, {
		Name = player.DisplayName,
		Player = player,
		NextCheckpoint = 1,
		Grid = CFrame.new(),
		Takedowns = 0,
	})
	local left = math.max(0, math.ceil(session.LobbyEndsAt - os.clock()))
	remotes.Notify:FireClient(player, ("%s – start in %d s"):format(session.Race.Name, left), "info")
end

local function onLeaveRequested(player: Player)
	local session = findParticipant(player)
	if session then
		removePlayer(session, player)
	end
end

-- Kvaddad racedeltagare: närmaste andra deltagare får en takedown.
local function onPlayerWrecked(player: Player)
	local session = findParticipant(player)
	if not session or session.State ~= "Running" then
		return
	end
	local victim = VehicleService.GetCar(player)
	local victimRoot = victim and victim.PrimaryPart
	if not victimRoot then
		return
	end
	local best: Participant? = nil
	local bestDistance = RaceConfig.PlayerTakedownRadius
	for _, participant in session.Participants do
		local other = participant.Player
		local car = other and other ~= player and VehicleService.GetCar(other)
		if car and car.PrimaryPart then
			local distance = (car.PrimaryPart.Position - victimRoot.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = participant, distance
			end
		end
	end
	if best and best.Player then
		CrashService.AwardTakedown(best.Player, victimRoot)
	end
end

-- Takedowns under racet (på motståndare eller andra deltagare) ger bonus vid målgång.
local function onTakedown(player: Player, victim: BasePart)
	local session, participant = findParticipant(player)
	if not session or not participant or session.State ~= "Running" then
		return
	end
	for _, other in session.Participants do
		local model = if other.Npc then other.Npc.Model elseif other.Player then VehicleService.GetCar(other.Player) else nil
		if model and victim:IsDescendantOf(model) then
			participant.Takedowns += 1
			return
		end
	end
end

local function buildStartMarker(session: Session)
	local marker = Instance.new("Folder")
	marker.Name = "RaceStart_" .. session.Race.Id
	marker.Parent = workspace
	local base = session.StartPosition
	local ring = Geometry.Cylinder(marker, "Ring", base + Vector3.new(0, 0.1, 0), RaceConfig.StartRadius - 6, 0.3, Color3.fromRGB(255, 200, 40), Enum.Material.Neon)
	ring.Transparency = 0.6
	Geometry.Decor(ring)
	local _, direction = routePosition(session.Route, session.Race.StartIndex)
	local right = Vector3.new(-direction.Z, 0, direction.X)
	for _, side in { -1, 1 } do
		local post = Geometry.Part(
			marker,
			"Post",
			Vector3.new(1.5, 18, 1.5),
			CFrame.new(base + right * side * 20 + Vector3.new(0, 9, 0)),
			Color3.new(1, 1, 1),
			Enum.Material.Metal
		)
		Geometry.Obstacle(post)
	end
	local banner = Geometry.Part(marker, "Banner", Vector3.new(40, 4, 0.5), CFrame.lookAt(base + Vector3.new(0, 19, 0), base + Vector3.new(0, 19, 0) - direction) * CFrame.Angles(0, 0, 0), Color3.fromRGB(20, 20, 25))
	Geometry.Label(banner, Enum.NormalId.Front, "START / MÅL", session.Race.Name, Color3.fromRGB(20, 20, 25))
	Geometry.Label(banner, Enum.NormalId.Back, "START / MÅL", session.Race.Name, Color3.fromRGB(20, 20, 25))

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(220, 60)
	billboard.StudsOffset = Vector3.new(0, 26, 0)
	billboard.MaxDistance = 600
	billboard.Parent = ring
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 210, 60)
	label.TextStrokeTransparency = 0.2
	label.Text = "RACE: " .. session.Race.Name
	label.Parent = billboard
end

function RaceService.IsRacing(player: Player): boolean
	return findParticipant(player) ~= nil
end

function RaceService.Init()
	for _, group in { RaceConfig.CollisionGroup, VehicleConfig.CollisionGroup, "Debris" } do
		if not PhysicsService:IsCollisionGroupRegistered(group) then
			PhysicsService:RegisterCollisionGroup(group)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(RaceConfig.CollisionGroup, VehicleConfig.CollisionGroup, false)
	PhysicsService:CollisionGroupSetCollidable(RaceConfig.CollisionGroup, "Debris", false)

	for _, name in { "RaceInvite", "RaceSetup", "RaceCheckpoint", "RaceUpdate", "RaceFinished", "Notify" } do
		remotes[name] = Remotes.Get(name)
	end
	Remotes.Get("RequestJoinRace").OnServerEvent:Connect(onJoinRequested)
	Remotes.Get("LeaveRace").OnServerEvent:Connect(onLeaveRequested)

	CrashService.OnWrecked(onPlayerWrecked)
	CrashService.OnTakedown(onTakedown)

	-- Kvaddad eller i vattnet under racet: tillbaka till senaste kontrollpunkten
	RespawnService.AddRespawnOverride(function(player: Player): CFrame?
		local session, participant = findParticipant(player)
		if not session or not participant or (session.State ~= "Running" and session.State ~= "Countdown") then
			return nil
		end
		local reached = participant.NextCheckpoint - 1
		if reached < 1 or session.State == "Countdown" then
			return participant.Grid
		end
		local checkpoint = session.Checkpoints[reached]
		local at = checkpoint.Position + Vector3.new(0, 4, 0)
		return CFrame.lookAt(at, at + checkpoint.Direction)
	end)
	RespawnService.AddTeleportBlocker(function(player: Player): string?
		if findParticipant(player) then
			return "Not during a race"
		end
		return nil
	end)
end

function RaceService.Start()
	for _, race in RaceConfig.Races do
		local route = NpcService.GetRoute(race.Route)
		if route then
			local startPosition = routePosition(route, race.StartIndex)
			local session: Session = {
				Race = race,
				Route = route,
				StartPosition = startPosition,
				Checkpoints = buildCheckpoints(race, route),
				LapLength = #route,
				State = "Idle",
				Participants = {},
				LobbyEndsAt = 0,
				StartAt = 0,
				FirstFinishAt = nil,
				CooldownUntil = 0,
				LastBroadcast = 0,
			}
			sessions[race.Id] = session
			buildStartMarker(session)
			print(("[RaceService] %s: %d kontrollpunkter"):format(race.Name, #session.Checkpoints))
		else
			warn("[RaceService] Rutten saknas: " .. race.Route)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		lastInvite[player] = nil
		local session = findParticipant(player)
		if session then
			removePlayer(session, player)
		end
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.1 then
			return
		end
		accumulator = 0
		for _, session in sessions do
			updateSession(session)
		end
	end)
end

return RaceService
