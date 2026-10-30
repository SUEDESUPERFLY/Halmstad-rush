--!strict
-- Bygger fantasibilarna av enkla Parts. Alla bilar har samma chassi och hjulupphängning
-- (samma fysik); karossen skiljer sig per stil. Bilens egenskaper (fart, grepp, boost)
-- sätts som attribut av VehicleService, inte här.
--
-- Chassit är den enda kroppen med massa; allt annat är Massless och svetsat.
-- Delar med attributet Paint = true lackeras med bilens färg (CarBuilder.Paint).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VehicleConfig = require(ReplicatedStorage.Shared.Config.VehicleConfig)

local Tuning = VehicleConfig.Tuning
local Geometry = VehicleConfig.Geometry

local CarBuilder = {}

local DARK = Color3.fromRGB(35, 35, 40)
local GLASS = Color3.fromRGB(150, 200, 230)
local CHROME = Color3.fromRGB(200, 200, 210)

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

-- Hjälpare för karossdelar: färg = bilens lack om `paint` är sant.
local function body(chassis: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3?, extra: { [string]: any }?)
	local props: { [string]: any } = { Name = name, Size = size, Color = color or chassis.Color }
	if extra then
		for key, value in extra do
			props[key] = value
		end
	end
	local part = makePart(props)
	if color == nil then
		part:SetAttribute("Paint", true)
	end
	weldTo(part, chassis, offset)
	return part
end

local function glass(chassis: BasePart, name: string, size: Vector3, offset: CFrame)
	return body(chassis, name, size, offset, GLASS, { Transparency = 0.45, Material = Enum.Material.Glass })
end

local function lights(chassis: BasePart, width: number)
	local size = Geometry.ChassisSize
	for _, x in { -width, width } do
		body(chassis, "Headlight", Vector3.new(1.2, 0.5, 0.2), CFrame.new(x, 0.2, -size.Z / 2 - 0.05), Color3.fromRGB(255, 250, 220), { Material = Enum.Material.Neon })
		body(chassis, "Taillight", Vector3.new(1.2, 0.4, 0.2), CFrame.new(x, 0.3, size.Z / 2 + 0.05), Color3.fromRGB(255, 40, 40), { Material = Enum.Material.Neon })
	end
end

local STYLES: { [string]: (chassis: BasePart, top: number) -> () } = {}

-- Kustpilen: öppen cabriolet med störtbåge
STYLES.Cabriolet = function(chassis, top)
	body(chassis, "Hood", Vector3.new(5.6, 0.6, 3.4), CFrame.new(0, top + 0.3, -3.6))
	body(chassis, "Trunk", Vector3.new(5.6, 0.7, 2.6), CFrame.new(0, top + 0.35, 4.1))
	glass(chassis, "Windshield", Vector3.new(5.4, 1.6, 0.2), CFrame.new(0, top + 1.0, -1.7) * CFrame.Angles(math.rad(-25), 0, 0))
	body(chassis, "RollBar", Vector3.new(5.4, 0.4, 0.4), CFrame.new(0, top + 2.0, 2.4), DARK)
	for _, x in { -2.6, 2.6 } do
		body(chassis, "RollBarPost", Vector3.new(0.4, 2.0, 0.4), CFrame.new(x, top + 1.0, 2.4), DARK)
	end
	body(chassis, "Spoiler", Vector3.new(5.8, 0.25, 1.2), CFrame.new(0, top + 1.3, 5.0), DARK)
	body(chassis, "Stripe", Vector3.new(1.2, 0.05, 11.05), CFrame.new(0, top + 0.01, 0), Color3.new(1, 1, 1))
	lights(chassis, 2.1)
end

-- Laxen: liten kvick halvkombi med högt tak
STYLES.Hatch = function(chassis, top)
	body(chassis, "Hood", Vector3.new(5.6, 0.8, 2.6), CFrame.new(0, top + 0.4, -4.0))
	glass(chassis, "Cabin", Vector3.new(5.4, 3.4, 6.2), CFrame.new(0, top + 1.7, 0.6))
	body(chassis, "Roof", Vector3.new(5.6, 0.4, 6.4), CFrame.new(0, top + 3.6, 0.6))
	body(chassis, "Tail", Vector3.new(5.6, 2.2, 1.2), CFrame.new(0, top + 1.1, 4.6))
	body(chassis, "Bumper", Vector3.new(6.2, 0.6, 0.6), CFrame.new(0, -0.3, -5.6), DARK)
	lights(chassis, 2.0)
end

-- Tylösand GT: låg coupé med stor vinge
STYLES.Coupe = function(chassis, top)
	body(chassis, "Hood", Vector3.new(5.6, 0.5, 4.2), CFrame.new(0, top + 0.25, -3.3))
	glass(chassis, "Canopy", Vector3.new(5.0, 2.0, 4.2), CFrame.new(0, top + 1.0, 0.6))
	body(chassis, "Roof", Vector3.new(5.0, 0.3, 2.6), CFrame.new(0, top + 2.15, 0.8))
	body(chassis, "Deck", Vector3.new(5.6, 0.7, 2.8), CFrame.new(0, top + 0.35, 4.0))
	body(chassis, "Wing", Vector3.new(6.2, 0.3, 1.4), CFrame.new(0, top + 1.8, 5.0), DARK)
	for _, x in { -2.4, 2.4 } do
		body(chassis, "WingPost", Vector3.new(0.3, 1.4, 0.3), CFrame.new(x, top + 1.0, 5.0), DARK)
		body(chassis, "SideStripe", Vector3.new(0.05, 0.5, 10), CFrame.new(x * 1.26, 0.1, 0), Color3.new(1, 1, 1))
	end
	lights(chassis, 2.2)
end

-- Galgbergaren: hög terrängbil med takräcke och bågskydd
STYLES.Jeep = function(chassis, top)
	body(chassis, "Hood", Vector3.new(5.8, 1.2, 3.4), CFrame.new(0, top + 0.6, -3.6))
	glass(chassis, "Cabin", Vector3.new(5.6, 3.2, 5.0), CFrame.new(0, top + 1.6, 0.6))
	body(chassis, "Roof", Vector3.new(5.8, 0.4, 5.2), CFrame.new(0, top + 3.4, 0.6))
	body(chassis, "Rack", Vector3.new(5.0, 0.3, 4.0), CFrame.new(0, top + 4.0, 0.6), DARK)
	body(chassis, "Bed", Vector3.new(5.8, 1.4, 2.6), CFrame.new(0, top + 0.7, 4.2))
	body(chassis, "BullBar", Vector3.new(6.0, 1.2, 0.4), CFrame.new(0, 0.4, -5.8), CHROME, { Material = Enum.Material.Metal })
	body(chassis, "SpareWheel", Vector3.new(0.8, 2.4, 2.4), CFrame.new(0, top + 1.2, 5.7) * CFrame.Angles(0, math.rad(90), 0), DARK, { Shape = Enum.PartType.Cylinder })
	lights(chassis, 2.2)
end

-- Stormvind: kilformad superbil med neon under
STYLES.Hyper = function(chassis, top)
	body(chassis, "Nose", Vector3.new(5.8, 0.4, 4.6), CFrame.new(0, top + 0.1, -3.2) * CFrame.Angles(math.rad(6), 0, 0))
	glass(chassis, "Canopy", Vector3.new(4.4, 1.6, 4.0), CFrame.new(0, top + 0.8, 0.4))
	body(chassis, "Engine", Vector3.new(5.8, 1.0, 3.6), CFrame.new(0, top + 0.5, 3.6))
	body(chassis, "Wing", Vector3.new(6.6, 0.3, 1.6), CFrame.new(0, top + 2.0, 5.1), DARK)
	for _, x in { -2.6, 2.6 } do
		body(chassis, "Fin", Vector3.new(0.3, 1.8, 1.6), CFrame.new(x, top + 1.1, 5.1), DARK)
		body(chassis, "Intake", Vector3.new(0.4, 0.8, 2.0), CFrame.new(x * 1.12, top + 0.2, 1.8), DARK)
	end
	body(chassis, "Underglow", Vector3.new(5.0, 0.1, 9.0), CFrame.new(0, -0.85, 0), Color3.fromRGB(80, 200, 255), { Material = Enum.Material.Neon })
	lights(chassis, 2.3)
end

function CarBuilder.Build(bodyColor: Color3, ownerUserId: number, style: string?): Model
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
	chassis:SetAttribute("Paint", true)
	chassis.Parent = model
	model.PrimaryPart = chassis

	local builder = STYLES[style or "Cabriolet"] or STYLES.Cabriolet
	builder(chassis, size.Y / 2)

	-- Säte. CanTouch = false så att ingen kan kliva in av misstag; servern sätter föraren med Seat:Sit.
	local seat = Instance.new("Seat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 0.4, 2)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanTouch = false
	seat.CanQuery = false
	seat.Massless = true
	weldTo(seat, chassis, CFrame.new(0, size.Y / 2 + 0.2, 0.6))

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
			Color = CHROME,
			Material = Enum.Material.Metal,
		})
		weldTo(hub, wheel, CFrame.new())
		hub.Parent = model
	end

	return model
end

-- Lackerar om en färdig bil (alla delar med attributet Paint).
function CarBuilder.Paint(model: Model, color: Color3)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("Paint") then
			descendant.Color = color
		end
	end
end

return CarBuilder
