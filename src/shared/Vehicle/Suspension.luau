--!strict
-- Raycast-fjädring som delas av spelarbilar (klienten) och NPC-bilar (servern).
-- Varje hjul har en monteringspunkt (Attachment) och en VectorForce som trycker upp chassit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VehicleConfig = require(ReplicatedStorage.Shared.Config.VehicleConfig)

local T = VehicleConfig.Tuning

export type Wheel = {
	Mount: Attachment,
	Force: VectorForce,
	SpringLength: number,
}

local Suspension = {}

-- Hittar hjulen ("Mount_*" på chassit) i en bil byggd av CarBuilder.
function Suspension.FindWheels(chassis: BasePart): { Wheel }
	local wheels: { Wheel } = {}
	for _, child in chassis:GetChildren() do
		if child:IsA("Attachment") and child.Name:sub(1, 6) == "Mount_" then
			table.insert(wheels, {
				Mount = child,
				Force = child:FindFirstChild("Spring") :: VectorForce,
				SpringLength = T.VisualSpringLength,
			})
		end
	end
	return wheels
end

-- Uppdaterar fjäderkrafterna. Returnerar antal hjul i marken och summan av markens normaler.
function Suspension.Update(root: BasePart, wheels: { any }, rayParams: RaycastParams): (number, Vector3)
	local cf = root.CFrame
	local up = cf.UpVector
	local mass = root.AssemblyMass
	local rayLength = T.SuspensionRestLength + T.WheelRadius
	local maxForce = mass * workspace.Gravity * 4
	local grounded = 0
	local normalSum = Vector3.zero

	for _, wheel in wheels do
		local mountPos = wheel.Mount.WorldPosition
		local result = workspace:Raycast(mountPos, -up * rayLength, rayParams)
		if result then
			grounded += 1
			normalSum += result.Normal
			local springLength = math.max(result.Distance - T.WheelRadius, 0)
			local compression = T.SuspensionRestLength - springLength
			local pointVelocity = root:GetVelocityAtPosition(mountPos):Dot(up)
			local force = (mass / 4) * (T.SpringStrength * compression - T.SpringDamping * pointVelocity)
			wheel.Force.Force = up * math.clamp(force, 0, maxForce)
			wheel.SpringLength = springLength
		else
			wheel.Force.Force = Vector3.zero
			wheel.SpringLength = T.SuspensionRestLength
		end
	end

	return grounded, normalSum
end

-- Nollställer krafterna (t.ex. när en bil är kraschad och ska tumla fritt).
function Suspension.Release(wheels: { any })
	for _, wheel in wheels do
		wheel.Force.Force = Vector3.zero
	end
end

return Suspension
