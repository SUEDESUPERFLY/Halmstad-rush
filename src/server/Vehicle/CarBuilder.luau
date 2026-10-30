--!strict
-- Bygger en fantasibil ("Kustpilen") av enkla Parts.
-- Chassit är den enda kroppen med massa; allt annat är Massless och svetsat.
-- Klienten hittar hjulen via attributen och styr fjädringen via VectorForces.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VehicleConfig = require(ReplicatedStorage.Shared.Config.VehicleConfig)

local Tuning = VehicleConfig.Tuning
local Geometry = VehicleConfig.Geometry

local CarBuilder = {}

local function makePart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(part :: any)[key] = value
	end
	return part
end

local function weldTo(part: BasePart, chassis: BasePart, offset: CFrame)
	part.CFrame = chassis.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = chassis
	weld.Part1 = part
	weld.Parent = part
	part.Parent = chassis.Parent
end

function CarBuilder.Build(bodyColor: Color3, ownerUserId: number): Model
	local model = Instance.new("Model")
	model.Name = "Car_" .. ownerUserId
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("IsHalmstadCar", true)
	model:SetAttribute("OwnerUserId", ownerUserId)

	local size = Geometry.ChassisSize
	local chassis = makePart({
		Name = "Chassis",
		Size = size,
		Color = bodyColor,
		CanCollide = true,
		CanQuery = true,
		CanTouch = true,
		Massless = false,
		RootPriority = 10,
		CustomPhysicalProperties = PhysicalProperties.new(1.5, 0.1, 0.2, 1, 1),
	})
	chassis.Parent = model
	model.PrimaryPart = chassis

	-- Kaross (visuell)
	local top = size.Y / 2
	weldTo(makePart({ Name = "Hood", Size = Vector3.new(5.6, 0.6, 3.4), Color = bodyColor }), chassis, CFrame.new(0, top + 0.3, -3.6))
	weldTo(makePart({ Name = "Trunk", Size = Vector3.new(5.6, 0.7, 2.6), Color = bodyColor }), chassis, CFrame.new(0, top + 0.35, 4.1))
	weldTo(
		makePart({
			Name = "Windshield",
			Size = Vector3.new(5.4, 1.6, 0.2),
			Color = Color3.fromRGB(150, 200, 230),
			Transparency = 0.4,
			Material = Enum.Material.Glass,
		}),
		chassis,
		CFrame.new(0, top + 1.0, -1.7) * CFrame.Angles(math.rad(-25), 0, 0)
	)
	weldTo(
		makePart({ Name = "RollBar", Size = Vector3.new(5.4, 0.4, 0.4), Color = Color3.fromRGB(40, 40, 45) }),
		chassis,
		CFrame.new(0, top + 2.0, 2.4)
	)
	for _, x in { -2.6, 2.6 } do
		weldTo(
			makePart({ Name = "RollBarPost", Size = Vector3.new(0.4, 2.0, 0.4), Color = Color3.fromRGB(40, 40, 45) }),
			chassis,
			CFrame.new(x, top + 1.0, 2.4)
		)
		weldTo(
			makePart({
				Name = "Headlight",
				Size = Vector3.new(1.2, 0.5, 0.2),
				Color = Color3.fromRGB(255, 250, 220),
				Material = Enum.Material.Neon,
			}),
			chassis,
			CFrame.new(x * 0.8, 0.2, -size.Z / 2 - 0.05)
		)
		weldTo(
			makePart({
				Name = "Taillight",
				Size = Vector3.new(1.2, 0.4, 0.2),
				Color = Color3.fromRGB(255, 40, 40),
				Material = Enum.Material.Neon,
			}),
			chassis,
			CFrame.new(x * 0.8, 0.3, size.Z / 2 + 0.05)
		)
	end
	weldTo(
		makePart({ Name = "Spoiler", Size = Vector3.new(5.8, 0.25, 1.2), Color = Color3.fromRGB(30, 30, 30) }),
		chassis,
		CFrame.new(0, top + 1.3, 5.0)
	)
	weldTo(
		makePart({ Name = "Stripe", Size = Vector3.new(1.2, 0.05, 11.05), Color = Color3.new(1, 1, 1) }),
		chassis,
		CFrame.new(0, top + 0.01, 0)
	)

	-- Säte. CanTouch = false så att ingen kan kliva in av misstag; servern sätter föraren med Seat:Sit.
	local seat = Instance.new("Seat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 0.4, 2)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanTouch = false
	seat.CanQuery = false
	seat.Massless = true
	weldTo(seat, chassis, CFrame.new(0, top + 0.2, 0.6))

	-- Hjul: monteringspunkt (Attachment + VectorForce) och visuellt hjul (Motor6D).
	for _, mount in Geometry.WheelMounts do
		local attachment = Instance.new("Attachment")
		attachment.Name = "Mount_" .. mount.Name
		attachment.Position = mount.Offset
		attachment:SetAttribute("Front", mount.Front)
		attachment.Parent = chassis

		local force = Instance.new("VectorForce")
		force.Name = "Spring"
		force.Attachment0 = attachment
		force.RelativeTo = Enum.ActuatorRelativeTo.World
		force.ApplyAtCenterOfMass = false
		force.Force = Vector3.zero
		force.Parent = attachment

		local wheel = makePart({
			Name = "Wheel_" .. mount.Name,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(Geometry.WheelWidth, Tuning.WheelRadius * 2, Tuning.WheelRadius * 2),
			Color = Color3.fromRGB(25, 25, 25),
		})
		wheel.Parent = model

		local motor = Instance.new("Motor6D")
		motor.Name = "WheelMotor"
		motor.Part0 = chassis
		motor.Part1 = wheel
		motor.C0 = CFrame.new(mount.Offset - Vector3.new(0, Tuning.VisualSpringLength, 0))
		motor.Parent = attachment

		local hub = makePart({
			Name = "Hub",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(Geometry.WheelWidth + 0.1, 1.0, 1.0),
			Color = Color3.fromRGB(200, 200, 210),
			Material = Enum.Material.Metal,
		})
		weldTo(hub, wheel, CFrame.new())
		hub.Parent = model
	end

	return model
end

return CarBuilder
