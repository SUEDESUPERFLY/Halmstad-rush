--!strict
-- Klientens startpunkt. Ordningen spelar roll: input först, sedan fordon,
-- därefter sådant som lyssnar på fordonet (kamera och UI).

local Controllers = script:WaitForChild("Controllers")
local UI = script:WaitForChild("UI")

local modules = {
	Controllers:WaitForChild("InputController"),
	Controllers:WaitForChild("VehicleController"),
	Controllers:WaitForChild("CameraController"),
	Controllers:WaitForChild("EffectsController"),
	Controllers:WaitForChild("CrashController"),
	Controllers:WaitForChild("RaceController"),
	UI:WaitForChild("HUD"),
	UI:WaitForChild("TouchControls"),
	UI:WaitForChild("DistrictBanner"),
	UI:WaitForChild("LocationMenu"),
	UI:WaitForChild("RaceUI"),
	UI:WaitForChild("GarageUI"),
}

for _, module in modules do
	local controller = require(module :: ModuleScript) :: any
	local ok, err = pcall(controller.Start)
	if not ok then
		warn(("[Client] %s.Start misslyckades: %s"):format(module.Name, tostring(err)))
	end
end

-- Börja leta efter spelarens bil först när alla lyssnare är uppkopplade.
require(Controllers.VehicleController :: ModuleScript).Begin()
