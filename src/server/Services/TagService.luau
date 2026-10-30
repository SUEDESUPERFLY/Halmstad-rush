--!strict
-- Kull med bilar (jaktläget). Lekfullt, inget polistema: den som är "den" jagar de andra
-- och tar över rollen genom att komma nära. Den som varit "den" kortast tid vinner.
-- Servern avgör allt (avstånd, roller, tid). Deltagarna krockar med varandra (TagCars)
-- men är spöken för andra spelare. Är man för få fylls det på med NPC-bilar.

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ActivityConfig = require(ReplicatedStorage.Shared.Config.ActivityConfig)
local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local VehicleConfig = require(ReplicatedStorage.Shared.Config.VehicleConfig)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Geometry = require(script.Parent.Parent.Map.Geometry)
local PlayerMode = require(script.Parent.Parent.Util.PlayerMode)
local EconomyService = require(script.Parent.EconomyService)
local NpcService = require(script.Parent.NpcService)
local RespawnService = require(script.Parent.RespawnService)
local VehicleService = require(script.Parent.VehicleService)

local Tag = ActivityConfig.Tag
local GROUP = ActivityConfig.CollisionGroupTag
local MODE = "Tag"

type Participant = {
	Name: string,
	Player: Player?,
	Npc: NpcService.Npc?,
	ItTime: number,
	CannotTag: Participant?, -- den som just tog dig kan du inte ta tillbaka direkt
	CannotTagUntil: number,
}

local TagService = {}

local state = "Idle" -- "Idle" | "Lobby" | "Running" | "Cooldown"
local participants: { Participant } = {}
local it: Participant? = nil
local lobbyEndsAt = 0
local endsAt = 0 -- servertid
local cooldownUntil = 0
local lastBroadcast = 0
local marker = Tag.Marker
local lastInvite: { [Player]: number } = {}
local remotes: { [string]: RemoteEvent } = {}

local NPC_COLORS = { Color3.fromRGB(255, 120, 200), Color3.fromRGB(120, 255, 160), Color3.fromRGB(255, 230, 90) }

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function positionOf(participant: Participant): Vector3?
	if participant.Npc then
		return participant.Npc.Chassis.Position
	end
	local car = participant.Player and VehicleService.GetCar(participant.Player)
	return car and car.PrimaryPart and car.PrimaryPart.Position
end

local function findParticipant(player: Player): Participant?
	for _, participant in participants do
		if participant.Player == player then
			return participant
		end
	end
	return nil
end

local function notifyAll(text: Locale.Message, kind: string)
	for _, participant in participants do
		if participant.Player then
			remotes.Notify:FireClient(participant.Player, text, kind)
		end
	end
end

local function nearestRunner(from: Participant): Participant?
	local origin = positionOf(from)
	if not origin then
		return nil
	end
	local best: Participant? = nil
	local bestDistance = math.huge
	for _, other in participants do
		if other ~= from then
			local position = positionOf(other)
			if position and (position - origin).Magnitude < bestDistance then
				best, bestDistance = other, (position - origin).Magnitude
			end
		end
	end
	return best
end

local function randomSpawn(): CFrame
	local point = RespawnService.RandomPointNear(marker, 40, Tag.SpawnRadius)
	if point then
		return RespawnService.PointCFrame(point)
	end
	return CFrame.new(marker + Vector3.new(0, 4, 0))
end

local function setIt(participant: Participant, tagger: Participant?)
	it = participant
	participant.CannotTag = tagger
	participant.CannotTagUntil = serverNow() + Tag.TagImmunity
	if participant.Player then
		remotes.Notify:FireClient(participant.Player, "YOU'RE IT!", "takedown")
	end
	notifyAll(Locale.Msg("%s is it!", participant.Name), "info")
end

local function sendState()
	for _, participant in participants do
		local player = participant.Player
		if player then
			local isIt = it == participant
			local target: Vector3? = nil
			if isIt then
				local runner = nearestRunner(participant)
				target = runner and positionOf(runner)
			elseif it then
				target = positionOf(it)
			end
			remotes.ActivityState:FireClient(player, {
				ActivityId = Tag.Id,
				Title = "TAG",
				Role = if isIt then "YOU'RE IT!" else Locale.Msg("Run! %s is it", if it then it.Name else "?"),
				Objective = if isIt then "Get close to someone to tag them" else "Stay away",
				EndsAt = endsAt,
				Score = Locale.Msg("Your time as it: %d s", math.floor(participant.ItTime)),
				Target = target,
				TargetLabel = if isIt then "CHASE" else "IT",
			})
		end
	end
end

local function cleanup()
	for _, participant in participants do
		if participant.Player then
			VehicleService.SetCollisionGroup(participant.Player, nil)
			PlayerMode.Clear(participant.Player, MODE)
		end
		if participant.Npc then
			NpcService.Remove(participant.Npc)
		end
	end
	participants = {}
	it = nil
	state = "Cooldown"
	cooldownUntil = os.clock() + 5
end

local function finishRound()
	local order = table.clone(participants)
	table.sort(order, function(a, b)
		return a.ItTime < b.ItTime
	end)
	local lines = {}
	for position, participant in order do
		table.insert(lines, Locale.Msg("%d. %s – %d s as it", position, participant.Name, math.floor(participant.ItTime)))
	end
	for position, participant in order do
		local player = participant.Player
		if player and player.Parent == Players then
			local reward = Tag.Rewards[math.min(position, #Tag.Rewards)]
			EconomyService.AddMoney(player, reward, Tag.Name)
			remotes.ActivityResult:FireClient(player, {
				Title = if position == 1 then "YOU WON TAG!" else Locale.Msg("TAG – place %d", position),
				Lines = lines,
				Reward = reward,
				Activity = Tag.Name,
			})
		end
	end
	cleanup()
end

local function spawnNpcs()
	local route = NpcService.GetRoute("StoraRingen")
	if not route then
		return
	end
	-- Närmaste ruttpunkt till markören
	local startIndex, bestDistance = 1, math.huge
	for i, point in route do
		local distance = (point - Vector2.new(marker.X, marker.Z)).Magnitude
		if distance < bestDistance then
			startIndex, bestDistance = i, distance
		end
	end
	local count = 0
	while #participants < Tag.MinParticipants do
		count += 1
		local index = (startIndex + count * 8 - 1) % #route + 1
		local npc = NpcService.SpawnOnRoute(route, index, NPC_COLORS[(count - 1) % #NPC_COLORS + 1], Tag.NpcSpeed, "Chaser", 2)
		local participant: Participant = {
			Name = ("Bot %d"):format(count),
			Npc = npc,
			ItTime = 0,
			CannotTag = nil,
			CannotTagUntil = 0,
		}
		-- Som "den" jagar boten närmaste deltagare, annars kör den runt på ringen
		npc.Target = function(): Vector3?
			if it ~= participant then
				return nil
			end
			local runner = nearestRunner(participant)
			return runner and positionOf(runner)
		end
		npc.RespawnAt = function(): CFrame?
			return randomSpawn()
		end
		table.insert(participants, participant)
	end
end

local function startRound()
	state = "Running"
	for _, participant in participants do
		local player = participant.Player
		if player then
			VehicleService.SetCollisionGroup(player, GROUP)
			VehicleService.MoveCar(player, randomSpawn())
		end
	end
	spawnNpcs()
	endsAt = serverNow() + Tag.RoundTime
	setIt(participants[math.random(1, #participants)], nil)
	sendState()
end

local function removeParticipant(player: Player)
	local participant = findParticipant(player)
	if not participant then
		return
	end
	table.remove(participants, table.find(participants, participant) :: number)
	if player.Parent == Players then
		VehicleService.SetCollisionGroup(player, nil)
		remotes.ActivityResult:FireClient(player, { Left = true })
	end
	PlayerMode.Clear(player, MODE)
	local playersLeft = 0
	for _, other in participants do
		if other.Player then
			playersLeft += 1
		end
	end
	if playersLeft == 0 then
		cleanup()
	elseif it == participant and state == "Running" then
		setIt(participants[math.random(1, #participants)], nil)
	end
end

local function updateRunning(dt: number)
	local current = it
	if not current then
		return
	end
	current.ItTime += dt
	local itPosition = positionOf(current)
	if itPosition then
		for _, other in participants do
			local position = other ~= current and positionOf(other)
			local blocked = current.CannotTag == other and serverNow() < current.CannotTagUntil
			if position and not blocked and (position - itPosition).Magnitude < Tag.TagDistance then
				notifyAll(Locale.Msg("%s tagged %s!", current.Name, other.Name), "nearmiss")
				setIt(other, current)
				break
			end
		end
	end
	if serverNow() >= endsAt then
		finishRound()
	elseif os.clock() - lastBroadcast > 0.5 then
		lastBroadcast = os.clock()
		sendState()
	end
end

local function onRequest(player: Player, id: unknown)
	if id ~= Tag.Id or (state ~= "Idle" and state ~= "Lobby") or findParticipant(player) then
		return
	end
	local car = VehicleService.GetCar(player)
	local root = car and car.PrimaryPart
	if not root or (root.Position - marker).Magnitude > ActivityConfig.MarkerRadius * 1.5 then
		return
	end
	if not PlayerMode.Set(player, MODE) then
		return
	end
	if state == "Idle" then
		state = "Lobby"
		lobbyEndsAt = os.clock() + Tag.LobbyTime
		participants = {}
	end
	table.insert(participants, {
		Name = player.DisplayName,
		Player = player,
		ItTime = 0,
		CannotTag = nil,
		CannotTagUntil = 0,
	})
	remotes.Notify:FireClient(player, Locale.Msg("Tag starts in %d s", math.ceil(lobbyEndsAt - os.clock())), "info")
end

function TagService.Init()
	for _, group in { GROUP, VehicleConfig.CollisionGroup, "Debris" } do
		if not PhysicsService:IsCollisionGroupRegistered(group) then
			PhysicsService:RegisterCollisionGroup(group)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(GROUP, VehicleConfig.CollisionGroup, false)
	PhysicsService:CollisionGroupSetCollidable(GROUP, "Debris", false)

	for _, name in { "ActivityInvite", "ActivityState", "ActivityResult", "Notify" } do
		remotes[name] = Remotes.Get(name)
	end
	Remotes.Get("RequestActivity").OnServerEvent:Connect(onRequest)
	Remotes.Get("LeaveActivity").OnServerEvent:Connect(removeParticipant)
	RespawnService.AddTeleportBlocker(function(player: Player): string?
		return if findParticipant(player) then "Not during tag" else nil
	end)
end

function TagService.Start()
	local point = RespawnService.FindNearest(Tag.Marker)
	if point then
		marker = point.Position
	end
	marker = Vector3.new(marker.X, MapData.GroundHeightAt(marker.X, marker.Z), marker.Z)
	local folder = Instance.new("Folder")
	folder.Name = "Activity_Kull"
	folder.Parent = workspace
	local ring = Geometry.Cylinder(folder, "Ring", marker + Vector3.new(0, 0.1, 0), ActivityConfig.MarkerRadius - 6, 0.3, Color3.fromRGB(255, 120, 200), Enum.Material.Neon)
	ring.Transparency = 0.6
	Geometry.Decor(ring)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(220, 60)
	billboard.StudsOffset = Vector3.new(0, 14, 0)
	billboard.MaxDistance = 500
	billboard.Parent = ring
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 120, 200)
	label.TextStrokeTransparency = 0.2
	label.Text = Tag.Name
	label.Parent = billboard
	Geometry.Localize(label)

	Players.PlayerRemoving:Connect(function(player)
		lastInvite[player] = nil
		removeParticipant(player)
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.1 then
			return
		end
		local step = accumulator
		accumulator = 0
		if state == "Lobby" and os.clock() >= lobbyEndsAt then
			startRound()
		elseif state == "Running" then
			updateRunning(step)
		elseif state == "Cooldown" and os.clock() >= cooldownUntil then
			state = "Idle"
		end

		if state == "Idle" or state == "Lobby" then
			for player, car in VehicleService.GetCars() do
				local root = car.PrimaryPart
				if
					root
					and PlayerMode.IsFree(player)
					and (root.Position - marker).Magnitude < ActivityConfig.MarkerRadius
					and os.clock() - (lastInvite[player] or 0) > 1
				then
					lastInvite[player] = os.clock()
					local description = if state == "Lobby" then "Tag starts soon – jump in!" else Tag.Description
					remotes.ActivityInvite:FireClient(player, Tag.Id, Tag.Name, description)
				end
			end
		end
	end)
end

return TagService
