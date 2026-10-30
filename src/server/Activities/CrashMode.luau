--!strict
-- Krockläget (Burnout Crash Mode): en avskild korsning i ett industriområde som bokas av en
-- spelare åt gången. Korsande trafik kör fram och tillbaka; spelaren kör in i korsningen.
-- Skadevärdet räknas av servern: smällar och kvaddningar på trafikbilarna (NpcService-händelser),
-- med kedjebonus för varje ytterligare kvaddning.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ActivityConfig = require(ReplicatedStorage.Shared.Config.ActivityConfig)
local Geometry = require(ServerScriptService.Server.Map.Geometry)

local C = ActivityConfig.CrashMode

local CrashMode = {}

local busyBy: Player? = nil
local NpcService: any = nil -- sätts av ActivityService (undviker cirkulär require)

local ROAD_LENGTH = 1200
local ROAD_WIDTH = 40
local ASPHALT = Color3.fromRGB(62, 64, 70)
local LANE_OFFSET = 7

function CrashMode.SetNpcService(service: any)
	NpcService = service
end

-- Bygger korsningen (en gång när servern startar).
function CrashMode.BuildArena()
	local origin = C.Origin
	local arena = Instance.new("Folder")
	arena.Name = "Krocklaget"
	arena.Parent = workspace

	Geometry.Part(arena, "Ground", Vector3.new(1400, 4, 1400), CFrame.new(origin + Vector3.new(0, -2, 0)), Color3.fromRGB(140, 140, 135), Enum.Material.Concrete)
	Geometry.Part(arena, "RoadNS", Vector3.new(ROAD_WIDTH, 0.2, ROAD_LENGTH), CFrame.new(origin + Vector3.new(0, 0.1, 0)), ASPHALT, Enum.Material.Asphalt)
	Geometry.Part(arena, "RoadEW", Vector3.new(ROAD_LENGTH, 0.2, ROAD_WIDTH), CFrame.new(origin + Vector3.new(0, 0.11, 0)), ASPHALT, Enum.Material.Asphalt)
	-- Vägmarkeringar och övergångsställen
	for offset = -ROAD_LENGTH / 2 + 30, ROAD_LENGTH / 2 - 30, 30 do
		if math.abs(offset) > ROAD_WIDTH then
			Geometry.Decor(Geometry.Part(arena, "Line", Vector3.new(1, 0.05, 12), CFrame.new(origin + Vector3.new(0, 0.25, offset)), Color3.new(1, 1, 1)))
			Geometry.Decor(Geometry.Part(arena, "Line", Vector3.new(12, 0.05, 1), CFrame.new(origin + Vector3.new(offset, 0.25, 0)), Color3.new(1, 1, 1)))
		end
	end
	-- Industribyggnader och containrar runt korsningen
	local rng = Random.new(77)
	local colors = { Color3.fromRGB(150, 160, 170), Color3.fromRGB(90, 120, 160), Color3.fromRGB(170, 110, 80), Color3.fromRGB(200, 190, 160) }
	for _, quadrant in { Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, -1) } do
		for i = 0, 3 do
			local distance = 70 + i * 120
			local size = Vector3.new(rng:NextNumber(60, 90), rng:NextNumber(18, 34), rng:NextNumber(50, 80))
			local center = origin + Vector3.new(quadrant.X * (distance + size.X / 2), size.Y / 2, quadrant.Z * (60 + size.Z / 2 + rng:NextNumber(0, 40)))
			Geometry.Obstacle(Geometry.Part(arena, "Warehouse", size, CFrame.new(center), colors[rng:NextInteger(1, #colors)], Enum.Material.Concrete))
		end
	end
	local sign = Geometry.Part(arena, "Sign", Vector3.new(40, 10, 1), CFrame.new(origin + Vector3.new(0, 16, 80)) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(200, 40, 40))
	Geometry.Label(sign, Enum.NormalId.Front, "KROCKLÄGET", "Industrikorsningen", Color3.fromRGB(200, 40, 40))
	Geometry.Label(sign, Enum.NormalId.Back, "KROCKLÄGET", "Industrikorsningen", Color3.fromRGB(200, 40, 40))
end

local function startCFrame(): CFrame
	local at = C.Origin + Vector3.new(LANE_OFFSET, 4, C.RunUp)
	return CFrame.lookAt(at, at - Vector3.zAxis)
end

-- Fram-och-tillbaka-rutt längs en väg, i ett körfält
local function laneRoute(direction: Vector3, side: number): { Vector2 }
	local origin = C.Origin
	local right = Vector3.new(-direction.Z, 0, direction.X)
	local half = ROAD_LENGTH / 2 - 40
	local points = {}
	for step = -half, half, 40 do
		local p = origin + direction * step + right * LANE_OFFSET * side
		table.insert(points, Vector2.new(p.X, p.Z))
	end
	return points
end

local function pushState(ctx: any, api: any)
	local data = ctx.Data
	api.SetState(ctx, {
		Title = "KROCKLÄGET",
		Objective = if data.FirstImpact then "Orsaka mer skada!" else "Kör in i korsningen – full fart!",
		EndsAt = data.EndsAt,
		CountdownTo = data.StartAt,
		Score = ("Skadevärde: %d kr"):format(data.Score),
		Target = C.Origin,
		TargetLabel = "KORSNINGEN",
	})
end

function CrashMode.Start(ctx: any, api: any): boolean
	if busyBy and busyBy.Parent then
		api.Notify(ctx, "Korsningen är upptagen – försök igen snart", "info")
		return false
	end
	busyBy = ctx.Player
	local data = ctx.Data
	data.Score = 0
	data.Wrecks = 0
	data.Npcs = {}
	data.ImpactsByNpc = {}
	data.StartAt = api.ServerNow() + C.Countdown
	data.EndsAt = data.StartAt + C.TimeLimit
	data.FirstImpact = nil

	-- Korsande trafik i båda riktningarna på tvärvägen, och mötande trafik rakt fram
	local colors = { Color3.fromRGB(235, 235, 235), Color3.fromRGB(70, 70, 75), Color3.fromRGB(30, 60, 110), Color3.fromRGB(200, 190, 160) }
	local lanes = {
		{ Vector3.xAxis, 1 },
		{ -Vector3.xAxis, 1 },
		{ Vector3.zAxis, 1 },
	}
	for laneIndex, lane in lanes do
		local route = laneRoute(lane[1], lane[2])
		for i = 1, C.TrafficPerLane do
			local index = math.floor((i - 1) * #route / C.TrafficPerLane) + 1 + laneIndex
			local npc = NpcService.SpawnOnRoute(route, (index - 1) % #route + 1, colors[(i + laneIndex) % #colors + 1], C.TrafficSpeed, "Arena", 999)
			table.insert(data.Npcs, npc)
		end
	end

	api.MoveCar(ctx.Player, startCFrame()) -- klienten håller bilen still till CountdownTo
	pushState(ctx, api)
	return true
end

-- Anropas av ActivityService för varje NPC-händelse.
function CrashMode.OnNpcEvent(ctx: any, api: any, npc: any, event: string, _strength: number)
	local data = ctx.Data
	if not table.find(data.Npcs, npc) or api.ServerNow() < data.StartAt then
		return
	end
	data.FirstImpact = data.FirstImpact or api.ServerNow()
	if event == "Wrecked" then
		data.Wrecks += 1
		local multiplier = 1 + (data.Wrecks - 1) * C.ChainBonus
		data.Score += math.floor(C.WreckScore * multiplier)
		api.Notify(ctx, ("KVADDAD! x%.2f"):format(multiplier), "takedown")
	elseif event == "Impact" then
		local count = data.ImpactsByNpc[npc] or 0
		if count < 3 then
			data.ImpactsByNpc[npc] = count + 1
			data.Score += C.ImpactScore
		end
	end
	pushState(ctx, api)
end

function CrashMode.Update(ctx: any, api: any, _dt: number)
	local data = ctx.Data
	local now = api.ServerNow()
	local afterImpact = data.FirstImpact and now - data.FirstImpact > C.AfterFirstImpact
	if now > data.EndsAt or afterImpact then
		local reward = math.min(C.MaxReward, math.floor(data.Score / C.ScorePerKrona))
		api.Finish(ctx, "KROCKLÄGET", {
			("Skadevärde: %d kr"):format(data.Score),
			("Kvaddade bilar: %d"):format(data.Wrecks),
		}, reward)
	end
end

function CrashMode.RespawnCFrame(_ctx: any, _api: any): CFrame?
	return startCFrame()
end

function CrashMode.Stop(ctx: any, api: any)
	for _, npc in ctx.Data.Npcs or {} do
		NpcService.Remove(npc)
	end
	ctx.Data.Npcs = {}
	if busyBy == ctx.Player then
		busyBy = nil
	end
	-- Tillbaka till markören i stan
	local marker = api.MarkerCFrame(ctx.Def.Id)
	if marker and ctx.Player.Parent then
		api.MoveCar(ctx.Player, marker)
	end
end

return CrashMode
