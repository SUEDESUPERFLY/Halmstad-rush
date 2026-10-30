--!strict
-- Stunthopp: tre försök från en ramp. Servern mäter själv avståndet från uppskjutet
-- (nära rampens topp) till landningen, utifrån bilens position. Medalj efter längsta hoppet.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActivityConfig = require(ReplicatedStorage.Shared.Config.ActivityConfig)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local MapData = require(ReplicatedStorage.Shared.Map.MapData)

local S = ActivityConfig.StuntJump

local StuntJump = {}

local function rampFrame(def: any): (Vector3, Vector3)
	local ramp = def.Ramp
	local forward = CFrame.Angles(0, math.rad(ramp.Yaw), 0).LookVector
	local top = ramp.Start + forward * ramp.Length * math.cos(math.rad(ramp.Angle))
	return top, forward
end

local function runUpCFrame(def: any): CFrame
	local ramp = def.Ramp
	local _, forward = rampFrame(def)
	local at = ramp.Start - forward * def.RunUp
	local y = MapData.GroundHeightAt(at.X, at.Z) + 4
	local position = Vector3.new(at.X, y, at.Z)
	return CFrame.lookAt(position, position + forward)
end

local function meters(studs: number): number
	return math.floor(studs * S.StudsToMeters + 0.5)
end

local function medal(def: any, best: number): (string, number)
	local medals, rewards = def.Medals, def.Rewards
	if best >= medals[3] then
		return "GOLD", rewards[3]
	elseif best >= medals[2] then
		return "SILVER", rewards[2]
	elseif best >= medals[1] then
		return "BRONZE", rewards[1]
	end
	return "No medal", 0
end

local function pushState(ctx: any, api: any)
	local data = ctx.Data
	local top = rampFrame(ctx.Def)
	local medals = ctx.Def.Medals
	api.SetState(ctx, {
		Title = Locale.Msg("%s · try %d/%d", Locale.Msg(ctx.Def.Name), math.min(data.Attempts + 1, S.Attempts), S.Attempts),
		Objective = Locale.Msg("Bronze %d m · Silver %d m · Gold %d m", meters(medals[1]), meters(medals[2]), meters(medals[3])),
		EndsAt = data.EndsAt,
		Score = Locale.Msg("Best: %d m", meters(data.Best)),
		Target = top,
		TargetLabel = "RAMP",
	})
end

local function finish(ctx: any, api: any)
	local name, reward = medal(ctx.Def, ctx.Data.Best)
	api.Finish(ctx, name, { Locale.Msg("Longest jump: %d m", meters(ctx.Data.Best)) }, reward)
end

function StuntJump.Start(ctx: any, api: any): boolean
	ctx.Data.Attempts = 0
	ctx.Data.Best = 0
	ctx.Data.Phase = "Approach"
	ctx.Data.EndsAt = api.ServerNow() + S.TimeLimit
	api.MoveCar(ctx.Player, runUpCFrame(ctx.Def))
	pushState(ctx, api)
	return true
end

function StuntJump.Update(ctx: any, api: any, _dt: number)
	local data = ctx.Data
	if api.ServerNow() > data.EndsAt then
		finish(ctx, api)
		return
	end
	if data.Phase == "Resetting" then
		return
	end
	local root = api.GetCarRoot(ctx.Player)
	if not root then
		return
	end
	local position = root.Position
	local ground = MapData.GroundHeightAt(position.X, position.Z)
	local airborne = position.Y - ground > S.AirborneHeight
	local flat = Vector3.new(position.X, 0, position.Z)

	if data.Phase == "Approach" then
		local top = rampFrame(ctx.Def)
		if airborne and (flat - Vector3.new(top.X, 0, top.Z)).Magnitude < S.TakeoffRadius then
			data.Phase = "Air"
			data.Takeoff = flat
			data.GroundedFrames = 0
		end
	elseif data.Phase == "Air" then
		if airborne then
			data.GroundedFrames = 0
			return
		end
		data.GroundedFrames += 1
		if data.GroundedFrames < 3 then
			return
		end
		local distance = (flat - data.Takeoff).Magnitude
		data.Attempts += 1
		data.Best = math.max(data.Best, distance)
		api.Notify(ctx, Locale.Msg("Jump: %d m", meters(distance)), "air")
		if data.Attempts >= S.Attempts then
			finish(ctx, api)
			return
		end
		-- Tillbaka till startsträckan inför nästa försök
		data.Phase = "Resetting"
		pushState(ctx, api)
		task.delay(S.ResetDelay, function()
			if not ctx.Ended then
				api.MoveCar(ctx.Player, runUpCFrame(ctx.Def))
				data.Phase = "Approach"
			end
		end)
	end
end

function StuntJump.RespawnCFrame(ctx: any, _api: any): CFrame?
	ctx.Data.Phase = "Approach"
	return runUpCFrame(ctx.Def)
end

return StuntJump
