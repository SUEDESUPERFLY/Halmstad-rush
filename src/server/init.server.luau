--!strict
-- Serverns startpunkt. Laddar alla services i Services/, kör Init() på alla
-- och därefter Start() på alla. Init: skapa saker och koppla ihop. Start: börja köra.

local servicesFolder = script:WaitForChild("Services")

type Service = {
	Init: (() -> ())?,
	Start: (() -> ())?,
}

local services: { [string]: Service } = {}

for _, module in servicesFolder:GetChildren() do
	if module:IsA("ModuleScript") then
		services[module.Name] = require(module) :: any
	end
end

for name, service in services do
	if service.Init then
		local ok, err = pcall(service.Init)
		if not ok then
			warn(("[Server] %s.Init misslyckades: %s"):format(name, tostring(err)))
		end
	end
end

for name, service in services do
	if service.Start then
		task.spawn(function()
			local ok, err = pcall(service.Start :: () -> ())
			if not ok then
				warn(("[Server] %s.Start misslyckades: %s"):format(name, tostring(err)))
			end
		end)
	end
end

print("[Server] Halmstad Rush startad")
