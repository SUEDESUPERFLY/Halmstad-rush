--!strict
-- Aktiviteter för en spelare åt gången: budjobb, stunthopp, drift och krockläget.
-- Varje aktivitet är en modul i src/server/Activities/ med Start/Update (och ev. OnWreck,
-- RespawnCFrame, Stop). Den här servicen sköter allt gemensamt: markörer i världen,
-- inbjudan, start, avbrott, respawn under aktiviteten, spärr för snabbresa och belöning.
-- Klienten får bara visningsdata (ActivityState/ActivityResult) och kan aldrig rapportera poäng.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ActivityConfig = require(ReplicatedStorage.Shared.Config.ActivityConfig)
local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Geometry = require(script.Parent.Parent.Map.Geometry)
local PlayerMode = require(script.Parent.Parent.Util.PlayerMode)
local CrashService = require(script.Parent.CrashService)
local EconomyService = require(script.Parent.EconomyService)
local NpcService = require(script.Parent.NpcService)
local RespawnService = require(script.Parent.RespawnService)
local VehicleService = require(script.Parent.VehicleService)

local Activities = script.Parent.Parent.Activities
local MODULES: { [string]: any } = {
	Delivery = require(Activities.Delivery),
	StuntJump = require(Activities.StuntJump),
	Drift = require(Activities.Drift),
	CrashMode = require(Activities.CrashMode),
}

local MODE = "Activity"

type Context = {
	Player: Player,
	Def: ActivityConfig.Activity,
	Module: any,
	Data: { [string]: any },
	State: { [string]: any },
	Ended: boolean,
}

local ActivityService = {}

local contexts: { [Player]: Context } = {}
local markers: { [string]: Vector3 } = {}
local lastInvite: { [Player]: number } = {}
local remotes: { [string]: RemoteEvent } = {}

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local endActivity: (ctx: Context, result: { [string]: any }?) -> ()

-- Funktioner som aktivitetsmodulerna får använda
local api = {}

function api.ServerNow(): number
	return serverNow()
end

function api.GetCarRoot(player: Player): BasePart?
	local car = VehicleService.GetCar(player)
	return car and car.PrimaryPart
end

function api.MoveCar(player: Player, target: CFrame)
	VehicleService.MoveCar(player, target)
end

function api.RandomRoadPoint(origin: Vector3, minDistance: number, maxDistance: number)
	return RespawnService.RandomPointNear(origin, minDistance, maxDistance)
end

function api.MarkerCFrame(id: string): CFrame?
	local position = markers[id]
	if not position then
		return nil
	end
	local point = RespawnService.FindNearest(position)
	return if point then RespawnService.PointCFrame(point) else CFrame.new(position + Vector3.new(0, 4, 0))
end

function api.Notify(ctx: Context, text: string, kind: string?)
	remotes.Notify:FireClient(ctx.Player, text, kind or "info")
end

function api.SetState(ctx: Context, fields: { [string]: any })
	if ctx.Ended then
		return
	end
	for key, value in fields do
		ctx.State[key] = value
	end
	remotes.ActivityState:FireClient(ctx.Player, ctx.State)
end

function api.Finish(ctx: Context, title: string, lines: { string }, reward: number)
	if ctx.Ended then
		return
	end
	endActivity(ctx, { Title = title, Lines = lines, Reward = math.max(0, math.floor(reward)), Activity = ctx.Def.Name })
end

endActivity = function(ctx: Context, result: { [string]: any }?)
	if ctx.Ended then
		return
	end
	ctx.Ended = true
	contexts[ctx.Player] = nil
	if ctx.Module.Stop then
		local ok, err = pcall(ctx.Module.Stop, ctx, api)
		if not ok then
			warn("[ActivityService] Stop misslyckades: " .. tostring(err))
		end
	end
	PlayerMode.Clear(ctx.Player, MODE)
	if ctx.Player.Parent ~= Players then
		return
	end
	local payload = result or { Title = "Avbrutet", Lines = {}, Reward = 0, Activity = ctx.Def.Name }
	if payload.Reward > 0 then
		EconomyService.AddMoney(ctx.Player, payload.Reward, ctx.Def.Name)
	end
	remotes.ActivityResult:FireClient(ctx.Player, payload)
end

local function startActivity(player: Player, def: ActivityConfig.Activity)
	local module = MODULES[def.Kind]
	if not module or not PlayerMode.Set(player, MODE) then
		return
	end
	local ctx: Context = {
		Player = player,
		Def = def,
		Module = module,
		Data = {},
		State = { ActivityId = def.Id },
		Ended = false,
	}
	contexts[player] = ctx
	local ok, started = pcall(module.Start, ctx, api)
	if not ok or not started then
		if not ok then
			warn(("[ActivityService] %s kunde inte starta: %s"):format(def.Id, tostring(started)))
		end
		contexts[player] = nil
		ctx.Ended = true
		PlayerMode.Clear(player, MODE)
		remotes.ActivityResult:FireClient(player, { Left = true })
	end
end

local function onRequest(player: Player, id: unknown)
	if typeof(id) ~= "string" or #id > 40 then
		return
	end
	local def = ActivityConfig.Find(id :: string)
	local marker = markers[id :: string]
	if not def or not marker or not PlayerMode.IsFree(player) then
		return
	end
	local root = api.GetCarRoot(player)
	if not root or (root.Position - marker).Magnitude > ActivityConfig.MarkerRadius * 1.5 then
		return
	end
	startActivity(player, def)
end

local function onLeave(player: Player)
	local ctx = contexts[player]
	if ctx then
		endActivity(ctx, nil)
	end
end

local function buildMarker(def: ActivityConfig.Activity, position: Vector3)
	local folder = Instance.new("Folder")
	folder.Name = "Activity_" .. def.Id
	folder.Parent = workspace
	local color = if def.Kind == "Delivery"
		then Color3.fromRGB(80, 200, 120)
		elseif def.Kind == "CrashMode" then Color3.fromRGB(230, 70, 60)
		else Color3.fromRGB(80, 170, 255)
	local ring = Geometry.Cylinder(folder, "Ring", position + Vector3.new(0, 0.1, 0), ActivityConfig.MarkerRadius - 6, 0.3, color, Enum.Material.Neon)
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
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Text = def.Name
	label.Parent = billboard

	if def.Ramp then
		local ramp = def.Ramp
		Geometry.Ramp(folder, "Ramp", ramp.Start, ramp.Yaw, ramp.Length, ramp.Angle, ramp.Width)
	end
end

function ActivityService.IsBusy(player: Player): boolean
	return contexts[player] ~= nil
end

function ActivityService.Init()
	for _, name in { "ActivityInvite", "ActivityState", "ActivityResult", "Notify" } do
		remotes[name] = Remotes.Get(name)
	end
	Remotes.Get("RequestActivity").OnServerEvent:Connect(onRequest)
	Remotes.Get("LeaveActivity").OnServerEvent:Connect(onLeave)

	CrashService.OnWrecked(function(player: Player)
		local ctx = contexts[player]
		if ctx and ctx.Module.OnWreck then
			ctx.Module.OnWreck(ctx, api)
		end
	end)
	RespawnService.AddRespawnOverride(function(player: Player): CFrame?
		local ctx = contexts[player]
		if ctx and ctx.Module.RespawnCFrame then
			return ctx.Module.RespawnCFrame(ctx, api)
		end
		return nil
	end)
	RespawnService.AddTeleportBlocker(function(player: Player): string?
		if contexts[player] then
			return "Finish or leave your activity first"
		end
		return nil
	end)

	MODULES.CrashMode.SetNpcService(NpcService)
	NpcService.OnEvent(function(npc, event: string, strength: number)
		for _, ctx in contexts do
			if ctx.Module.OnNpcEvent then
				ctx.Module.OnNpcEvent(ctx, api, npc, event, strength)
			end
		end
	end)
end

function ActivityService.Start()
	MODULES.CrashMode.BuildArena()
	for _, def in ActivityConfig.Activities do
		local position = def.Marker
		if def.SnapMarker ~= false then
			local point = RespawnService.FindNearest(def.Marker)
			if point then
				position = point.Position
			end
		end
		position = Vector3.new(position.X, MapData.GroundHeightAt(position.X, position.Z), position.Z)
		markers[def.Id] = position
		buildMarker(def, position)
	end

	Players.PlayerRemoving:Connect(function(player)
		lastInvite[player] = nil
		local ctx = contexts[player]
		if ctx then
			endActivity(ctx, nil)
		end
	end)

	local inviteClock = 0
	RunService.Heartbeat:Connect(function(dt)
		for _, ctx in contexts do
			if not ctx.Ended then
				local ok, err = pcall(ctx.Module.Update, ctx, api, dt)
				if not ok then
					warn(("[ActivityService] %s: %s"):format(ctx.Def.Id, tostring(err)))
					endActivity(ctx, nil)
				end
			end
		end

		inviteClock += dt
		if inviteClock < 0.25 then
			return
		end
		inviteClock = 0
		for player, car in VehicleService.GetCars() do
			local root = car.PrimaryPart
			if root and PlayerMode.IsFree(player) and os.clock() - (lastInvite[player] or 0) > 1 then
				for _, def in ActivityConfig.Activities do
					local marker = markers[def.Id]
					if marker and (root.Position - marker).Magnitude < ActivityConfig.MarkerRadius then
						lastInvite[player] = os.clock()
						remotes.ActivityInvite:FireClient(player, def.Id, def.Name, def.Description)
						break
					end
				end
			end
		end
	end)
end

return ActivityService
