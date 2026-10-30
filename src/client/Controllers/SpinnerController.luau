--!strict
-- Snurrar modeller med taggen "Spinner" (vindkraftverkens rotorer) lokalt. Servern bygger
-- dem stillastående med `WorldPivot` i navet och attributet `SpinSpeed` (varv per sekund
-- räknat i radianer). Långt borta snurrar de inte, för att spara prestanda.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local SpinnerController = {}

local MAX_DISTANCE = 1500

local spinners: { [Model]: CFrame } = {}

local function add(instance: Instance)
	if instance:IsA("Model") then
		spinners[instance] = instance:GetPivot()
	end
end

function SpinnerController.Start()
	for _, instance in CollectionService:GetTagged("Spinner") do
		add(instance)
	end
	CollectionService:GetInstanceAddedSignal("Spinner"):Connect(add)
	CollectionService:GetInstanceRemovedSignal("Spinner"):Connect(function(instance)
		spinners[instance :: Model] = nil
	end)

	RunService.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local now = os.clock()
		for model, base in spinners do
			if (base.Position - camera.CFrame.Position).Magnitude < MAX_DISTANCE then
				local speed = model:GetAttribute("SpinSpeed")
				local angle = now * (if typeof(speed) == "number" then speed else 1)
				model:PivotTo(base * CFrame.Angles(0, 0, angle))
			end
		end
	end)
end

return SpinnerController
