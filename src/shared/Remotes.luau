--!strict
-- Alla RemoteEvents definieras här. Bara servern skapar dem; klienten väntar in dem.
-- Varje handler på servern MÅSTE validera argument och takt (rate limit).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

Remotes.Names = {
	ResetVehicle = "ResetVehicle", -- klient -> server, inga argument
	TeleportToLocation = "TeleportToLocation", -- klient -> server, (locationId: string)
	Notify = "Notify", -- server -> klient, (text: string, kind: string)
}

local FOLDER_NAME = "Remotes"

local function getFolder(): Folder
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
		return folder :: Folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

function Remotes.Get(name: string): RemoteEvent
	assert(Remotes.Names[name], "Okänd remote: " .. name)
	local folder = getFolder()
	if RunService:IsServer() then
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		return remote :: RemoteEvent
	end
	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
