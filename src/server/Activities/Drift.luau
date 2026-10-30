--!strict
-- Driftkungen: drifta så mycket som möjligt på tiden. Servern räknar poängen själv
-- från bilens hastighet i sidled (replikerad från förarens klient, och begränsad av fartkontrollen).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActivityConfig = require(ReplicatedStorage.Shared.Config.ActivityConfig)

local Settings = ActivityConfig.Drift

local Drift = {}

local function medal(def: any, score: number): (string, number)
	local medals, rewards = def.Medals, def.Rewards
	if score >= medals[3] then
		return "GULD", rewards[3]
	elseif score >= medals[2] then
		return "SILVER", rewards[2]
	elseif score >= medals[1] then
		return "BRONS", rewards[1]
	end
	return "Ingen medalj", 0
end

local function pushState(ctx: any, api: any)
	local medals = ctx.Def.Medals
	api.SetState(ctx, {
		Title = ctx.Def.Name,
		Objective = ("Brons %d · Silver %d · Guld %d"):format(medals[1], medals[2], medals[3]),
		EndsAt = ctx.Data.EndsAt,
		Score = ("Driftpoäng: %d"):format(math.floor(ctx.Data.Score)),
	})
end

function Drift.Start(ctx: any, api: any): boolean
	ctx.Data.Score = 0
	ctx.Data.EndsAt = api.ServerNow() + Settings.Duration
	ctx.Data.LastPush = 0
	pushState(ctx, api)
	return true
end

function Drift.Update(ctx: any, api: any, dt: number)
	local data = ctx.Data
	if api.ServerNow() > data.EndsAt then
		local name, reward = medal(ctx.Def, data.Score)
		api.Finish(ctx, name, { ("Driftpoäng: %d"):format(math.floor(data.Score)) }, reward)
		return
	end
	local root = api.GetCarRoot(ctx.Player)
	if not root then
		return
	end
	local velocity = root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
	local lateral = math.abs(velocity:Dot(root.CFrame.RightVector))
	if velocity.Magnitude > Settings.MinSpeed and lateral > Settings.MinLateral then
		data.Score += lateral * Settings.PointsPerLateral * dt
	end
	if os.clock() - data.LastPush > 0.25 then
		data.LastPush = os.clock()
		pushState(ctx, api)
	end
end

function Drift.OnWreck(ctx: any, api: any)
	-- En krock nollställer inte poängen men kostar en bit
	ctx.Data.Score = math.max(0, ctx.Data.Score - 300)
	api.Notify(ctx, "Krock! −300 driftpoäng", "wreck")
end

return Drift
