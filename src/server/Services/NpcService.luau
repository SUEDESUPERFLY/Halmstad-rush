--!strict
-- NPC-bilar som kör runt på Halmstads huvudgator (rutter från tools/map/build_city.py).
-- Servern äger deras fysik. De använder samma raycast-fjädring som spelarbilarna.
--
-- Takedowns avgörs här: när en NPC-bil får en hård smäll och en spelarbil var nära,
-- eller välter/kvaddas inom några sekunder efter en knuff, räknas det som en takedown.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local VehicleConfig = require(ReplicatedStorage.Shared.Config.VehicleConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Suspension = require(ReplicatedStorage.Shared.Vehicle.Suspension)
local CarBuilder = require(script.Parent.Parent.Vehicle.CarBuilder)
local CityRoutes = require(script.Parent.Parent.Map.Generated.CityRoutes)
local CrashService = require(script.Parent.CrashService)
local VehicleService = require(script.Parent.VehicleService)

local N = VehicleConfig.Npc

export type Npc = {
	Kind: string, -- "Traffic" | "Racer" | "Arena" | "Chaser"
	Target: (() -> Vector3?)?, -- om satt: kör mot den här punkten i stället för att följa rutten
	RespawnAt: (() -> CFrame?)?, -- om satt: var bilen ska dyka upp igen
	Speed: number, -- marschfart
	SpeedScale: number, -- justeras av RaceService (rubber band)
	Passed: number, -- antal passerade ruttpunkter (racets framsteg)
	WreckDuration: number,
	Model: Model,
	Chassis: BasePart,
	Wheels: { Suspension.Wheel },
	RayParams: RaycastParams,
	Route: { Vector2 },
	Index: number,
	Mode: string, -- "Drive" | "Wrecked"
	WreckedAt: number,
	StuckTime: number,
	LastSetVelocity: Vector3?,
	LastHitter: Player?,
	LastHitTime: number,
}

local NpcService = {}

local npcs: { Npc } = {}
local eventListeners: { (npc: Npc, event: string, strength: number) -> () } = {}
local routes: { [string]: { Vector2 } } = {}
local crashEffectRemote: RemoteEvent
local folder: Folder

local function decodeRoute(encoded: string): { Vector2 }
	local points = {}
	for x, z in encoded:gmatch("(%-?%d+),(%-?%d+)") do
		table.insert(points, Vector2.new(tonumber(x) :: number, tonumber(z) :: number))
	end
	return points
end

local function moveToward(value: number, target: number, maxDelta: number): number
	if value < target then
		return math.min(value + maxDelta, target)
	end
	return math.max(value - maxDelta, target)
end

local function setGroup(root: Instance)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = N.CollisionGroup
		end
	end
end

-- Enkel förare (två block) så att NPC-bilarna inte ser förarlösa ut.
local function addDriver(model: Model, chassis: BasePart, rng: Random)
	local seat = model:FindFirstChild("DriverSeat") :: BasePart?
	if not seat then
		return
	end
	local shirt = Color3.fromHSV(rng:NextNumber(), 0.5, 0.8)
	local parts = {
		{ Vector3.new(2, 2.2, 1.2), CFrame.new(0, 1.4, 0), shirt },
		{ Vector3.new(1.3, 1.3, 1.3), CFrame.new(0, 3.2, 0), Color3.fromRGB(240, 200, 160) },
	}
	for _, info in parts do
		local part = Instance.new("Part")
		part.Name = "Driver"
		part.Size = info[1]
		part.CFrame = seat.CFrame * info[2]
		part.Color = info[3]
		part.CanCollide = false
		part.CanQuery = false
		part.Massless = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = chassis
		weld.Part1 = part
		weld.Parent = part
		part.Parent = model
	end
end

local function cframeAt(route: { Vector2 }, index: number): CFrame
	local point = route[index]
	local nextPoint = route[index % #route + 1]
	local y = MapData.GroundHeightAt(point.X, point.Y) + 4
	local position = Vector3.new(point.X, y, point.Y)
	local ahead = Vector3.new(nextPoint.X, y, nextPoint.Y)
	return CFrame.lookAt(position, ahead)
end

local function playerCarPositions(): { Vector3 }
	local positions = {}
	for _, car in VehicleService.GetCars() do
		if car.PrimaryPart then
			table.insert(positions, car.PrimaryPart.Position)
		end
	end
	return positions
end

-- Väljer en ruttpunkt långt från spelare (så att ingen ser bilen dyka upp) och inte
-- ovanpå en annan NPC-bil.
local function chooseSpawnIndex(route: { Vector2 }, preferred: number): number
	local carPositions = playerCarPositions()
	local npcPositions = {}
	for _, other in npcs do
		table.insert(npcPositions, other.Chassis.Position)
	end
	for offset = 0, #route - 1 do
		local index = (preferred + offset - 1) % #route + 1
		local point = route[index]
		local clear = true
		for _, position in carPositions do
			if (Vector2.new(position.X, position.Z) - point).Magnitude < N.MinSpawnDistance then
				clear = false
				break
			end
		end
		for _, position in npcPositions do
			if clear and (Vector2.new(position.X, position.Z) - point).Magnitude < N.SpawnSpacing then
				clear = false
				break
			end
		end
		if clear then
			return index
		end
	end
	return preferred
end

local function placeNpc(npc: Npc, index: number)
	npc.Index = index % #npc.Route + 1
	npc.Model:PivotTo(cframeAt(npc.Route, index))
	npc.Chassis.AssemblyLinearVelocity = Vector3.zero
	npc.Chassis.AssemblyAngularVelocity = Vector3.zero
	npc.Mode = "Drive"
	npc.StuckTime = 0
	npc.LastSetVelocity = nil
	npc.LastHitter = nil
end

local function fireEvent(npc: Npc, event: string, strength: number)
	for _, listener in eventListeners do
		task.spawn(listener, npc, event, strength)
	end
end

local function respawnNpc(npc: Npc)
	local custom = npc.RespawnAt and npc.RespawnAt()
	if custom then
		npc.Model:PivotTo(custom)
		npc.Chassis.AssemblyLinearVelocity = Vector3.zero
		npc.Chassis.AssemblyAngularVelocity = Vector3.zero
		npc.Mode = "Drive"
		npc.StuckTime = 0
		npc.LastSetVelocity = nil
		npc.LastHitter = nil
		return
	end
	if npc.Kind == "Racer" then
		-- Tävlingsbilar kommer tillbaka strax bakom där de kvaddades
		local back = 3
		npc.Passed -= back
		placeNpc(npc, (npc.Index - 1 - back - 1) % #npc.Route + 1)
		return
	end
	placeNpc(npc, chooseSpawnIndex(npc.Route, npc.Index + math.floor(#npc.Route / 3)))
end

local function spawnNpc(route: { Vector2 }, index: number, color: Color3, rng: Random): Npc
	local model = CarBuilder.Build(color, 0)
	model.Name = "NpcCar"
	model:SetAttribute("IsNpc", true)
	local chassis = model.PrimaryPart :: BasePart
	chassis:SetAttribute("Obstacle", true) -- nära-ögat-boost när man susar förbi trafiken
	addDriver(model, chassis, rng)
	setGroup(model)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { model }
	rayParams.RespectCanCollide = true
	rayParams.CollisionGroup = N.CollisionGroup

	local npc: Npc = {
		Kind = "Traffic",
		Speed = N.CruiseSpeed,
		SpeedScale = 1,
		Passed = 0,
		WreckDuration = N.WreckDuration,
		Model = model,
		Chassis = chassis,
		Wheels = Suspension.FindWheels(chassis),
		RayParams = rayParams,
		Route = route,
		Index = index,
		Mode = "Drive",
		WreckedAt = 0,
		StuckTime = 0,
		LastSetVelocity = nil,
		LastHitter = nil,
		LastHitTime = 0,
	}
	model:PivotTo(cframeAt(route, index))
	model.Parent = folder
	chassis:SetNetworkOwner(nil)
	placeNpc(npc, index)
	table.insert(npcs, npc)
	return npc
end

local function nearestPlayerCar(position: Vector3): Player?
	local best: Player? = nil
	local bestDistance = N.HitRadius
	for player, car in VehicleService.GetCars() do
		local root = car.PrimaryPart
		if root then
			local distance = (root.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = player, distance
			end
		end
	end
	return best
end

local function wreckNpc(npc: Npc, strength: number, now: number)
	npc.Mode = "Wrecked"
	npc.WreckedAt = now
	Suspension.Release(npc.Wheels)
	local root = npc.Chassis
	-- Tecknad krock: bilen studsar upp och snurrar
	local mass = root.AssemblyMass
	root:ApplyImpulse(Vector3.new(0, mass * 45, 0))
	root:ApplyAngularImpulse(Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * mass * 60)
	crashEffectRemote:FireAllClients(root.Position, strength)
	fireEvent(npc, "Wrecked", strength)

	local hitter = npc.LastHitter
	if hitter and now - npc.LastHitTime <= N.TakedownWindow then
		CrashService.AwardTakedown(hitter, root)
	end
end

local function updateNpc(npc: Npc, dt: number, now: number)
	local root = npc.Chassis
	local cf = root.CFrame
	local position = cf.Position
	local velocity = root.AssemblyLinearVelocity
	local angular = root.AssemblyAngularVelocity

	if npc.Mode == "Wrecked" then
		if now - npc.WreckedAt > npc.WreckDuration then
			respawnNpc(npc)
		end
		return
	end

	if position.Y < MapData.WaterLevel + 1 or not MapData.IsInBounds(position) then
		respawnNpc(npc)
		return
	end

	-- Smällar: jämför med hastigheten vi själva satte förra rutan
	local previous = npc.LastSetVelocity
	if previous then
		local change = ((velocity - previous) * Vector3.new(1, 0, 1)).Magnitude
		if change > N.ImpactThreshold then
			local hitter = nearestPlayerCar(position)
			if hitter then
				npc.LastHitter = hitter
				npc.LastHitTime = now
			end
			fireEvent(npc, "Impact", change)
			if change > N.WreckImpact then
				wreckNpc(npc, change, now)
				return
			end
		end
	end
	if cf.UpVector.Y < 0.3 then
		wreckNpc(npc, 40, now)
		return
	end

	local grounded, normalSum = Suspension.Update(root, npc.Wheels, npc.RayParams)
	if grounded < 2 then
		npc.LastSetVelocity = nil
		return
	end

	local flat = Vector2.new(position.X, position.Z)
	local toTarget3: Vector3
	local targetSpeed: number
	local chasePoint = npc.Target and npc.Target()
	if chasePoint then
		-- Kör mot en punkt (kull). Enkel hinderundvikning med tre strålar framåt.
		local direction = (chasePoint - position) * Vector3.new(1, 0, 1)
		toTarget3 = if direction.Magnitude > 1 then direction.Unit else cf.LookVector * Vector3.new(1, 0, 1)
		local look = (cf.LookVector * Vector3.new(1, 0, 1)).Unit
		local origin = position + Vector3.new(0, 1, 0)
		local reach = N.AvoidDistance
		if workspace:Raycast(origin, look * reach, npc.RayParams) then
			local left = CFrame.Angles(0, math.rad(40), 0):VectorToWorldSpace(look)
			local rightDir = CFrame.Angles(0, math.rad(-40), 0):VectorToWorldSpace(look)
			local leftHit = workspace:Raycast(origin, left * reach, npc.RayParams)
			local rightHit = workspace:Raycast(origin, rightDir * reach, npc.RayParams)
			local leftFree = if leftHit then leftHit.Distance else reach
			local rightFree = if rightHit then rightHit.Distance else reach
			local turnDeg = if leftFree >= rightFree then 70 else -70
			toTarget3 = CFrame.Angles(0, math.rad(turnDeg), 0):VectorToWorldSpace(look)
		end
		targetSpeed = npc.Speed * npc.SpeedScale
	else
		-- Följ rutten
		local route = npc.Route
		local target = route[npc.Index]
		local guard = 0
		while (target - flat).Magnitude < N.WaypointRadius and guard < 5 do
			npc.Index = npc.Index % #route + 1
			npc.Passed += 1
			target = route[npc.Index]
			guard += 1
		end
		local after = route[npc.Index % #route + 1]
		local toTarget = target - flat
		toTarget3 = Vector3.new(toTarget.X, 0, toTarget.Y).Unit
		local segment = (after - target)
		local segment3 = Vector3.new(segment.X, 0, segment.Y).Unit
		local turn = math.acos(math.clamp(toTarget3:Dot(segment3), -1, 1))
		targetSpeed = npc.Speed * npc.SpeedScale * (1 - math.min(turn / (math.pi / 2), 0.6))
	end

	local normal = (normalSum / grounded).Unit
	local forward = cf.LookVector - normal * cf.LookVector:Dot(normal)
	forward = if forward.Magnitude > 1e-3 then forward.Unit else cf.LookVector
	local right = forward:Cross(normal)
	local vF = velocity:Dot(forward)
	local vR = velocity:Dot(right)
	local vN = velocity:Dot(normal)

	vF = moveToward(vF, targetSpeed, N.Acceleration * dt)
	vR *= math.exp(-N.Grip * dt)

	local flatLook = (forward * Vector3.new(1, 0, 1)).Unit
	local yawError = math.atan2(flatLook:Cross(toTarget3).Y, flatLook:Dot(toTarget3))
	local targetYaw = math.clamp(yawError * N.TurnGain, -N.MaxYawRate, N.MaxYawRate)
	local currentYaw = angular:Dot(normal)
	angular += normal * ((targetYaw - currentYaw) * (1 - math.exp(-N.YawResponse * dt)))

	velocity = forward * vF + right * vR + normal * vN
	root.AssemblyLinearVelocity = velocity
	root.AssemblyAngularVelocity = angular
	npc.LastSetVelocity = velocity

	if velocity.Magnitude < 4 then
		npc.StuckTime += dt
		if npc.StuckTime > N.StuckTime then
			respawnNpc(npc)
		end
	else
		npc.StuckTime = 0
	end
end

function NpcService.GetRoute(name: string): { Vector2 }?
	return routes[name]
end

-- NPC-motståndare i ett race. Startar vid ruttpunkt `index` och kör med farten `speed`.
function NpcService.SpawnRacer(routeName: string, index: number, color: Color3, speed: number, wreckDuration: number): Npc?
	local route = routes[routeName]
	if not route then
		return nil
	end
	return NpcService.SpawnOnRoute(route, index, color, speed, "Racer", wreckDuration)
end

-- NPC-bil på en valfri rutt (t.ex. korsningstrafiken i krockläget).
function NpcService.SpawnOnRoute(route: { Vector2 }, index: number, color: Color3, speed: number, kind: string, wreckDuration: number): Npc
	local npc = spawnNpc(route, index, color, Random.new())
	npc.Kind = kind
	npc.Speed = speed
	npc.WreckDuration = wreckDuration
	npc.Model.Name = kind .. "Car"
	return npc
end

-- Lyssnar på smällar ("Impact") och kvaddningar ("Wrecked") för alla NPC-bilar.
-- Antal trafikbilar som ska finnas: en färre per riktig spelare.
local function trafficTarget(): number
	local target = N.TrafficMax - #Players:GetPlayers() * N.TrafficPerPlayer
	return math.max(N.TrafficMin, target)
end

local function trafficCars(): { Npc }
	local list = {}
	for _, npc in npcs do
		if npc.Kind == "Traffic" then
			table.insert(list, npc)
		end
	end
	return list
end

-- Flyttar trafiken ett steg mot målet. Bilar tas bara bort långt från spelare
-- (och aldrig mitt i en knuff som kan bli en takedown), nya dyker upp utom synhåll.
local function adjustTraffic(rng: Random)
	local traffic = trafficCars()
	local target = trafficTarget()
	if #traffic > target then
		local players = playerCarPositions()
		local now = os.clock()
		for _, npc in traffic do
			local hitRecently = npc.LastHitter ~= nil and now - npc.LastHitTime < N.TakedownWindow + 1
			local far = true
			for _, position in players do
				if (position - npc.Chassis.Position).Magnitude < N.DespawnDistance then
					far = false
					break
				end
			end
			if far and not hitRecently and npc.Mode == "Drive" then
				NpcService.Remove(npc)
				return
			end
		end
	elseif #traffic < target then
		-- Lägg bilen på den rutt som har minst trafik i förhållande till sin andel
		local counts: { [string]: number } = {}
		for _, npc in traffic do
			for name, route in routes do
				if npc.Route == route then
					counts[name] = (counts[name] or 0) + 1
				end
			end
		end
		local bestName, bestRatio = nil, math.huge
		for name, share in N.RouteShare :: { [string]: number } do
			local ratio = (counts[name] or 0) / share
			if routes[name] and #routes[name] > 0 and ratio < bestRatio then
				bestName, bestRatio = name, ratio
			end
		end
		if bestName then
			local route = routes[bestName]
			local index = chooseSpawnIndex(route, rng:NextInteger(1, #route))
			spawnNpc(route, index, N.Colors[rng:NextInteger(1, #N.Colors)], rng)
		end
	end
end

function NpcService.OnEvent(listener: (npc: Npc, event: string, strength: number) -> ())
	table.insert(eventListeners, listener)
end

function NpcService.Remove(npc: Npc)
	local index = table.find(npcs, npc)
	if index then
		table.remove(npcs, index)
	end
	npc.Model:Destroy()
end

function NpcService.Init()
	if not PhysicsService:IsCollisionGroupRegistered(N.CollisionGroup) then
		PhysicsService:RegisterCollisionGroup(N.CollisionGroup)
	end
	crashEffectRemote = Remotes.Get("CrashEffect")
	for name, encoded in CityRoutes :: { [string]: string } do
		routes[name] = decodeRoute(encoded)
	end
end

function NpcService.Start()
	folder = Instance.new("Folder")
	folder.Name = "NpcCars"
	folder.Parent = workspace

	local rng = Random.new(2024)
	-- Första trafiken sprids jämnt längs rutterna
	local target = trafficTarget()
	for name, share in N.RouteShare :: { [string]: number } do
		local route = routes[name]
		local count = math.round(target * share)
		if route and #route > 0 then
			for i = 0, count - 1 do
				spawnNpc(route, math.floor(i * #route / count) + 1, N.Colors[rng:NextInteger(1, #N.Colors)], rng)
			end
		end
	end
	task.spawn(function()
		while true do
			task.wait(N.TrafficAdjustInterval)
			adjustTraffic(rng)
		end
	end)

	RunService.PreSimulation:Connect(function(dt)
		dt = math.min(dt, 1 / 30)
		local now = os.clock()
		for _, npc in npcs do
			if npc.Chassis.Parent then
				updateNpc(npc, dt, now)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		for _, npc in npcs do
			if npc.LastHitter == player then
				npc.LastHitter = nil
			end
		end
	end)
	print(("[NpcService] %d NPC-bilar ute på gatorna"):format(#npcs))
end

return NpcService
