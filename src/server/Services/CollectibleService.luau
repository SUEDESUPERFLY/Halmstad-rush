--!strict
-- Gömda laxar runt om i Halmstad (CommunityConfig.Salmon). Servern bygger dem, ser när en
-- spelares bil kör igenom en lax och sparar fyndet i profilen (Salmon). Klienten döljer laxar
-- som spelaren redan hittat (CollectibleState) och snurrar dem (taggen "Spinner").
-- Alla laxar ger en extra belöning, lacken "Salmon silver" (Unlock_AllSalmon) och en badge.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CommunityConfig = require(ReplicatedStorage.Shared.Config.CommunityConfig)
local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local Locale = require(ReplicatedStorage.Shared.Localization.Locale)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CityBuilder = require(script.Parent.Parent.Map.CityBuilder)
local GameEvents = require(script.Parent.Parent.Util.GameEvents)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local VehicleService = require(script.Parent.VehicleService)

local CollectibleService = {}

local stateRemote: RemoteEvent
local celebrateRemote: RemoteEvent
local placed: { { Id: string, Position: Vector3 } } = {}

-- Ytor där en lax får ligga: park, torg, sand, fält, idrottsplats. Gata eller bro i nödfall.
local OPEN = { P = true, G = true, N = true, F = true, S = true }
local ROAD = { A = true, Y = true, D = true }

local function findSpot(spot: CommunityConfig.SalmonSpot): Vector2
	if spot.Exact then
		return spot.Position
	end
	local minRadius = spot.MinRadius or 0
	local fallback: Vector2? = nil
	for radius = minRadius, minRadius + 160, 4 do
		local steps = math.max(1, math.floor(2 * math.pi * radius / 4))
		for i = 0, steps - 1 do
			local angle = i / steps * 2 * math.pi
			local p = spot.Position + Vector2.new(math.cos(angle), math.sin(angle)) * radius
			local code = CityBuilder.CodeAt(p.X, p.Y)
			if code and OPEN[code] then
				return p
			elseif code and ROAD[code] and not fallback then
				fallback = p
			end
		end
	end
	return fallback or spot.Position
end

-- En silverglänsande lax: kropp, stjärtfena, ryggfena och öga. Ingen kollision.
local function buildSalmon(parent: Instance, id: string, position: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Salmon_" .. id
	local silver = Color3.fromRGB(205, 212, 222)
	local function part(name: string, size: Vector3, cframe: CFrame, color: Color3): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Size = size
		p.CFrame = cframe
		p.Color = color
		p.Material = Enum.Material.Metal
		p.Reflectance = 0.25
		p.Parent = model
		return p
	end
	local center = CFrame.new(position)
	local body = part("Body", Vector3.new(7, 2.6, 1.6), center, silver)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = body
	local tail = Instance.new("WedgePart")
	tail.Name = "Tail"
	tail.Anchored = true
	tail.CanCollide = false
	tail.CanQuery = false
	tail.CanTouch = false
	tail.Size = Vector3.new(0.4, 3, 2)
	tail.CFrame = center * CFrame.new(4, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
	tail.Color = Color3.fromRGB(170, 180, 195)
	tail.Material = Enum.Material.Metal
	tail.Parent = model
	part("Fin", Vector3.new(1.6, 1, 0.3), center * CFrame.new(0.5, 1.5, 0), Color3.fromRGB(150, 160, 175))
	part("Eye", Vector3.new(0.5, 0.5, 1.7), center * CFrame.new(-2.6, 0.4, 0), Color3.fromRGB(20, 20, 25))
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(170, 220, 255)
	light.Range = 12
	light.Brightness = 1.5
	light.Parent = body
	-- Snurrar runt lodaxeln: SpinnerController roterar kring pivotens Z-axel
	model.WorldPivot = center * CFrame.Angles(math.rad(90), 0, 0)
	model:SetAttribute("SpinSpeed", 1.2)
	model:SetAttribute("SalmonId", id)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- alla delar strömmas in samtidigt
	model.PrimaryPart = body
	CollectionService:AddTag(model, "Spinner")
	CollectionService:AddTag(model, "Salmon")
	model.Parent = parent
	return model
end

local function foundList(data: DataService.PlayerData): { string }
	local list = {}
	for id in data.Salmon do
		table.insert(list, id)
	end
	return list
end

local function sendState(player: Player)
	local data = DataService.Get(player)
	if data then
		stateRemote:FireClient(player, { Found = foundList(data), Total = #CommunityConfig.Salmon })
	end
end

local function collect(player: Player, id: string, position: Vector3)
	local count = 0
	local isNew = false
	DataService.Update(player, function(data)
		if not data.Salmon[id] then
			data.Salmon[id] = true
			isNew = true
		end
		for _ in data.Salmon do
			count += 1
		end
	end)
	if not isNew then
		return
	end
	local total = #CommunityConfig.Salmon
	EconomyService.AddMoney(player, CommunityConfig.SalmonReward, Locale.Msg("Salmon found! %d/%d", count, total))
	celebrateRemote:FireClient(player, position)
	sendState(player)
	if count >= total then
		player:SetAttribute("Unlock_AllSalmon", true)
		EconomyService.AddMoney(player, CommunityConfig.AllSalmonReward, "You found every salmon in Halmstad!")
		GameEvents.Fire(player, "SalmonFound", 99) -- laxutmaningen blir klar även om det bara fanns en kvar
		GameEvents.Fire(player, "SalmonAll")
	else
		GameEvents.Fire(player, "SalmonFound")
	end
end

function CollectibleService.Init()
	stateRemote = Remotes.Get("CollectibleState")
	celebrateRemote = Remotes.Get("Celebrate")
end

function CollectibleService.Start()
	-- Kartans rutnät avkodas i MapService.Init, så positionerna räknas fram här i Start.
	local folder = Instance.new("Folder")
	folder.Name = "Salmon"
	for _, spot in CommunityConfig.Salmon do
		local p = findSpot(spot)
		local position = Vector3.new(p.X, MapData.GroundHeightAt(p.X, p.Y) + CommunityConfig.SalmonHeight, p.Y)
		buildSalmon(folder, spot.Id, position)
		table.insert(placed, { Id = spot.Id, Position = position })
	end
	folder.Parent = workspace

	local function onPlayer(player: Player)
		task.spawn(function()
			local data = DataService.WaitForData(player)
			if data then
				local count = 0
				for _ in data.Salmon do
					count += 1
				end
				if count >= #CommunityConfig.Salmon then
					player:SetAttribute("Unlock_AllSalmon", true)
				end
				sendState(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end

	local radius = CommunityConfig.SalmonPickupRadius
	task.spawn(function()
		while true do
			task.wait(0.2)
			for player, car in VehicleService.GetCars() do
				local root = car.PrimaryPart
				local data = DataService.Get(player)
				if root and data then
					for _, salmon in placed do
						if not data.Salmon[salmon.Id] then
							local offset = root.Position - salmon.Position
							if Vector2.new(offset.X, offset.Z).Magnitude < radius and math.abs(offset.Y) < radius then
								collect(player, salmon.Id, salmon.Position)
							end
						end
					end
				end
			end
		end
	end)
end

return CollectibleService
