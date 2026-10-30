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
	ReportWreck = "ReportWreck", -- klient -> server, inga argument (min bil är kvaddad, flytta mig)
	Takedown = "Takedown", -- server -> klient, (npcChassis: BasePart) du gjorde en takedown
	CrashEffect = "CrashEffect", -- server -> alla, (position: Vector3, strength: number) NPC-krock
	RaceInvite = "RaceInvite", -- server -> klient, (raceId, raceName, lobbyOpen: boolean) du står vid en startlinje
	RequestJoinRace = "RequestJoinRace", -- klient -> server, (raceId: string)
	LeaveRace = "LeaveRace", -- klient -> server, inga argument
	RaceSetup = "RaceSetup", -- server -> klient, (setup: table) kontrollpunkter och starttid
	RaceCheckpoint = "RaceCheckpoint", -- server -> klient, (passedIndex: number)
	RaceUpdate = "RaceUpdate", -- server -> klient, (position, participants, elapsed)
	RaceFinished = "RaceFinished", -- server -> klient, (results: table)
	GarageAction = "GarageAction", -- klient -> server, (action: "Buy"|"Select"|"Upgrade"|"Paint", carId: string, arg: string?)
	ProfileUpdated = "ProfileUpdated", -- server -> klient, (profile: table) pengar, bilar, uppgraderingar
	ActivityInvite = "ActivityInvite", -- server -> klient, (id, name, description) du står vid en aktivitet
	RequestActivity = "RequestActivity", -- klient -> server, (id: string)
	LeaveActivity = "LeaveActivity", -- klient -> server, inga argument
	ActivityState = "ActivityState", -- server -> klient, (state: table) titel, mål, tid, poäng (bara visning)
	ActivityResult = "ActivityResult", -- server -> klient, (result: table) slutresultat och belöning
	ShopAction = "ShopAction", -- klient -> server, (action: "ClaimDaily"|"StudioTest", key: string?)
	ShopState = "ShopState", -- server -> klient, (state: table) ägda pass och daglig belöning
	Celebrate = "Celebrate", -- server -> alla, (position: Vector3) konfettiregn
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
