--!strict
-- Byggstenar: lådor, plattor, remsor, ramper, cylindrar, klot och skylttext.

local Geometry = {}

local MAX_PART_SIZE = 2000

function Geometry.Part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Markerar en del som "hinder": ger nära-ögat-boost när man susar förbi.
function Geometry.Obstacle(part: BasePart): BasePart
	part:SetAttribute("Obstacle", true)
	return part
end

-- Visuell del som inte påverkar fysik eller raycasts.
function Geometry.Decor(part: BasePart): BasePart
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	return part
end

-- Låda från hörn till hörn. Delas upp i flera Parts om den är större än Robloxs maxstorlek.
function Geometry.Box(
	parent: Instance,
	name: string,
	min: Vector3,
	max: Vector3,
	color: Color3,
	material: Enum.Material?
): { Part }
	local parts = {}
	local size = max - min
	local nx = math.max(1, math.ceil(size.X / MAX_PART_SIZE))
	local nz = math.max(1, math.ceil(size.Z / MAX_PART_SIZE))
	local stepX = size.X / nx
	local stepZ = size.Z / nz
	for ix = 0, nx - 1 do
		for iz = 0, nz - 1 do
			local chunkMin = Vector3.new(min.X + ix * stepX, min.Y, min.Z + iz * stepZ)
			local chunkSize = Vector3.new(stepX, size.Y, stepZ)
			table.insert(
				parts,
				Geometry.Part(parent, name, chunkSize, CFrame.new(chunkMin + chunkSize / 2), color, material)
			)
		end
	end
	return parts
end

-- Horisontell platta (zon) med given översida.
function Geometry.Slab(
	parent: Instance,
	name: string,
	min: Vector2,
	max: Vector2,
	topY: number,
	color: Color3,
	material: Enum.Material?
): { Part }
	return Geometry.Box(parent, name, Vector3.new(min.X, topY - 1, min.Y), Vector3.new(max.X, topY, max.Y), color, material)
end

-- Rak remsa mellan två punkter (vägsegment, vägmarkering).
function Geometry.Strip(
	parent: Instance,
	name: string,
	a: Vector2,
	b: Vector2,
	width: number,
	topY: number,
	thickness: number,
	color: Color3,
	material: Enum.Material?
): Part
	local from = Vector3.new(a.X, topY - thickness / 2, a.Y)
	local to = Vector3.new(b.X, topY - thickness / 2, b.Y)
	local length = (to - from).Magnitude
	local cframe = CFrame.lookAt((from + to) / 2, to)
	return Geometry.Part(parent, name, Vector3.new(width, thickness, length), cframe, color, material)
end

-- Stående cylinder. `base` är mitten av undersidan.
function Geometry.Cylinder(
	parent: Instance,
	name: string,
	base: Vector3,
	radius: number,
	height: number,
	color: Color3,
	material: Enum.Material?
): Part
	local part = Geometry.Part(
		parent,
		name,
		Vector3.new(height, radius * 2, radius * 2),
		CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		material
	)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- Del mellan två godtyckliga punkter (t.ex. palmstam). Cylinder om `round` är sant.
function Geometry.Between(
	parent: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	thickness: number,
	color: Color3,
	material: Enum.Material?,
	round: boolean?
): Part
	local length = (b - a).Magnitude
	local cframe = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
	local part = Geometry.Part(parent, name, Vector3.new(length, thickness, thickness), cframe, color, material)
	if round then
		part.Shape = Enum.PartType.Cylinder
	end
	return part
end

-- Text på en parts yta (skyltar). Statisk text från oss, inte från spelare.
function Geometry.Label(
	part: BasePart,
	face: Enum.NormalId,
	text: string,
	subText: string?,
	background: Color3,
	textColor: Color3?
): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0.2
	gui.Parent = part

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = background
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 6
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame

	local main = Instance.new("TextLabel")
	main.BackgroundTransparency = 1
	main.Position = UDim2.fromScale(0.04, if subText then 0.08 else 0.1)
	main.Size = UDim2.fromScale(0.92, if subText then 0.55 else 0.8)
	main.Font = Enum.Font.GothamBlack
	main.TextScaled = true
	main.Text = text
	main.TextColor3 = textColor or Color3.new(1, 1, 1)
	main.Parent = frame

	if subText then
		local sub = Instance.new("TextLabel")
		sub.BackgroundTransparency = 1
		sub.Position = UDim2.fromScale(0.08, 0.64)
		sub.Size = UDim2.fromScale(0.84, 0.28)
		sub.Font = Enum.Font.GothamBold
		sub.TextScaled = true
		sub.Text = subText
		sub.TextColor3 = textColor or Color3.new(1, 1, 1)
		sub.Parent = frame
	end
	return gui
end

function Geometry.Ball(parent: Instance, name: string, center: Vector3, radius: number, color: Color3): Part
	local part = Geometry.Part(parent, name, Vector3.one * radius * 2, CFrame.new(center), color)
	part.Shape = Enum.PartType.Ball
	return part
end

-- Ramp som börjar vid `start` (nedre kanten) och stiger i riktningen `yawDeg`.
-- 0 = stiger mot -Z (norr), 90 = mot -X (väster), -90 = mot +X (öster), 180 = mot +Z (söder).
function Geometry.Ramp(
	parent: Instance,
	name: string,
	start: Vector3,
	yawDeg: number,
	length: number,
	angleDeg: number,
	width: number,
	color: Color3?,
	material: Enum.Material?
): Part
	local thickness = 2
	local yaw = CFrame.Angles(0, math.rad(yawDeg), 0)
	local angle = math.rad(angleDeg)
	local slope = yaw.LookVector * math.cos(angle) + Vector3.yAxis * math.sin(angle)
	local normal = yaw.RightVector:Cross(slope).Unit
	local center = start + slope * (length / 2) - normal * (thickness / 2)
	local cframe = CFrame.fromMatrix(center, slope:Cross(normal), normal)
	return Geometry.Part(
		parent,
		name,
		Vector3.new(width, thickness, length),
		cframe,
		color or Color3.fromRGB(240, 170, 40),
		material or Enum.Material.DiamondPlate
	)
end

function Geometry.RampTop(start: Vector3, yawDeg: number, length: number, angleDeg: number): Vector3
	local flatForward = CFrame.Angles(0, math.rad(yawDeg), 0).LookVector
	local angle = math.rad(angleDeg)
	return start + flatForward * length * math.cos(angle) + Vector3.yAxis * length * math.sin(angle)
end

return Geometry
