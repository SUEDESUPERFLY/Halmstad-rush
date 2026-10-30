--!strict
-- Byggstenar för block-out: lådor, plattor, vägsegment, ramper, cylindrar och terrängkullar.

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

-- Mjuk kulle i Terrain: platt topp inom flatRadius, cosinus-sluttning ut till radius.
function Geometry.TerrainHill(center: Vector2, flatRadius: number, radius: number, height: number, material: Enum.Material)
	local terrain = workspace.Terrain
	local resolution = 4
	local region = Region3.new(
		Vector3.new(center.X - radius, 0, center.Y - radius),
		Vector3.new(center.X + radius, height + resolution, center.Y + radius)
	):ExpandToGrid(resolution)
	local regionMin = region.CFrame.Position - region.Size / 2
	local countX = math.floor(region.Size.X / resolution + 0.5)
	local countY = math.floor(region.Size.Y / resolution + 0.5)
	local countZ = math.floor(region.Size.Z / resolution + 0.5)

	local function heightAt(x: number, z: number): number
		local r = math.sqrt((x - center.X) ^ 2 + (z - center.Y) ^ 2)
		if r <= flatRadius then
			return height
		elseif r >= radius then
			return 0
		end
		local t = (r - flatRadius) / (radius - flatRadius)
		return height * (0.5 + 0.5 * math.cos(math.pi * t))
	end

	local materials = table.create(countX)
	local occupancies = table.create(countX)
	for ix = 1, countX do
		local x = regionMin.X + (ix - 0.5) * resolution
		local matX = table.create(countY)
		local occX = table.create(countY)
		for iy = 1, countY do
			matX[iy] = table.create(countZ)
			occX[iy] = table.create(countZ)
		end
		for iz = 1, countZ do
			local z = regionMin.Z + (iz - 0.5) * resolution
			local surface = heightAt(x, z)
			for iy = 1, countY do
				local y0 = regionMin.Y + (iy - 1) * resolution
				local occupancy = math.clamp((surface - y0) / resolution, 0, 1)
				matX[iy][iz] = if occupancy > 0 then material else Enum.Material.Air
				occX[iy][iz] = occupancy
			end
		end
		materials[ix] = matX
		occupancies[ix] = occX
	end

	terrain:WriteVoxels(region, resolution, materials, occupancies)
end

return Geometry
