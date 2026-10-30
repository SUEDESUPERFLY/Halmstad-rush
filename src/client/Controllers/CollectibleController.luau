--!strict
-- De gömda laxarna på klienten: döljer laxar som spelaren redan hittat (bara lokalt, andra
-- spelare ser dem fortfarande) och håller reda på antalet för gränssnittet.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local CollectibleController = {}

CollectibleController.Changed = Signal.new() -- (found: { [string]: boolean }, total: number)

local found: { [string]: boolean } = {}
local total = 0

local function apply(model: Instance)
	local id = model:GetAttribute("SalmonId")
	if typeof(id) ~= "string" or not found[id] then
		return
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Transparency = 1
		elseif descendant:IsA("Light") then
			descendant.Enabled = false
		end
	end
end

function CollectibleController.GetFound(): ({ [string]: boolean }, number)
	return found, total
end

function CollectibleController.Start()
	Remotes.Get("CollectibleState").OnClientEvent:Connect(function(state: any)
		if typeof(state) ~= "table" or typeof(state.Found) ~= "table" then
			return
		end
		found = {}
		for _, id in state.Found do
			if typeof(id) == "string" then
				found[id] = true
			end
		end
		total = if typeof(state.Total) == "number" then state.Total else 0
		for _, model in CollectionService:GetTagged("Salmon") do
			apply(model)
		end
		CollectibleController.Changed:Fire(found, total)
	end)
	CollectionService:GetInstanceAddedSignal("Salmon"):Connect(function(model)
		-- Strömmade modeller kan komma utan alla delar; vänta en bildruta
		task.defer(apply, model)
	end)
end

return CollectibleController
