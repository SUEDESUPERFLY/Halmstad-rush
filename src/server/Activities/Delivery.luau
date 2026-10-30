--!strict
-- Budjobb: Pizzabud (3 leveranser från pizzerian) och Taxi (hämta, sedan lämna, 3 gånger).
-- Servern väljer mål på riktiga gator, mäter tid och avstånd och betalar ut.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActivityConfig = require(ReplicatedStorage.Shared.Config.ActivityConfig)

local D = ActivityConfig.Delivery

local Delivery = {}

local function newTarget(ctx: any, api: any, origin: Vector3, minDistance: number, maxDistance: number): boolean
	local point = api.RandomRoadPoint(origin, minDistance, maxDistance)
	if not point then
		return false
	end
	local distance = (point.Position - origin).Magnitude
	ctx.Data.Target = point.Position
	ctx.Data.Deadline = api.ServerNow() + D.BaseSeconds + distance * D.SecondsPerStud
	return true
end

local function pushState(ctx: any, api: any)
	local data = ctx.Data
	local isTaxi = ctx.Def.Variant == "Taxi"
	local objective
	if isTaxi then
		objective = if data.Stage == "Pickup" then "Hämta passageraren" else "Kör passageraren till målet"
	else
		objective = "Leverera pizzan"
	end
	api.SetState(ctx, {
		Title = ("%s %d/%d"):format(ctx.Def.Name, data.Done + 1, D.Count),
		Objective = objective,
		EndsAt = data.Deadline,
		Score = ("Intjänat: %d kr"):format(data.Earned),
		Target = data.Target,
		TargetLabel = if isTaxi and data.Stage == "Pickup" then "PASSAGERARE" else "MÅL",
	})
end

function Delivery.Start(ctx: any, api: any): boolean
	local root = api.GetCarRoot(ctx.Player)
	if not root then
		return false
	end
	ctx.Data.Done = 0
	ctx.Data.Earned = 0
	ctx.Data.Wrecks = 0
	local ok
	if ctx.Def.Variant == "Taxi" then
		ctx.Data.Stage = "Pickup"
		ok = newTarget(ctx, api, root.Position, D.PickupMinDistance, D.PickupMaxDistance)
	else
		ctx.Data.Stage = "Drop"
		ok = newTarget(ctx, api, root.Position, D.MinDistance, D.MaxDistance)
	end
	if ok then
		pushState(ctx, api)
	end
	return ok
end

function Delivery.Update(ctx: any, api: any, _dt: number)
	local data = ctx.Data
	local root = api.GetCarRoot(ctx.Player)
	if not root then
		return
	end
	if api.ServerNow() > data.Deadline then
		api.Finish(ctx, "Tiden är ute!", {
			("Klara: %d/%d"):format(data.Done, D.Count),
		}, data.Earned)
		return
	end
	local offset = (root.Position - data.Target) * Vector3.new(1, 0, 1)
	local speed = root.AssemblyLinearVelocity.Magnitude
	if offset.Magnitude > D.ArriveRadius or speed > D.ArriveMaxSpeed then
		return
	end

	if ctx.Def.Variant == "Taxi" and data.Stage == "Pickup" then
		data.Stage = "Drop"
		newTarget(ctx, api, root.Position, D.MinDistance, D.MaxDistance)
		api.Notify(ctx, "Passageraren klev in!", "info")
		pushState(ctx, api)
		return
	end

	local timeLeft = math.max(0, data.Deadline - api.ServerNow())
	local pay = math.max(10, math.floor(D.BasePay + timeLeft * D.TimeBonusPerSecond - data.Wrecks * D.WreckPenalty))
	data.Earned += pay
	data.Done += 1
	data.Wrecks = 0
	api.Notify(ctx, ("Levererat! +%d kr"):format(pay), "money")

	if data.Done >= D.Count then
		api.Finish(ctx, ctx.Def.Name .. " klart!", {
			("Klara: %d/%d"):format(data.Done, D.Count),
		}, data.Earned)
		return
	end
	if ctx.Def.Variant == "Taxi" then
		data.Stage = "Pickup"
		newTarget(ctx, api, root.Position, D.PickupMinDistance, D.PickupMaxDistance)
	else
		newTarget(ctx, api, root.Position, D.MinDistance, D.MaxDistance)
	end
	pushState(ctx, api)
end

function Delivery.OnWreck(ctx: any, api: any)
	ctx.Data.Wrecks += 1
	local message = if ctx.Def.Variant == "Taxi" then "Passageraren blev rädd! −%d kr dricks" else "Pizzan blev mosad! −%d kr"
	api.Notify(ctx, message:format(D.WreckPenalty), "wreck")
end

return Delivery
