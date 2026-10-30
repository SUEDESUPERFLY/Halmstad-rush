--!strict
-- Ljud för den egna bilen och spelhändelser (bara lokalt):
-- fartvind (och motor om ett ID finns i SoundConfig), dunsar vid krock, plask i vattnet
-- och pling vid kontrollpunkter, pengar, takedowns och nära ögat.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local SoundConfig = require(ReplicatedStorage.Shared.Config.SoundConfig)
local VehicleConfig = require(ReplicatedStorage.Shared.Config.VehicleConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local VehicleController = require(script.Parent.VehicleController)

local SoundController = {}

local holder: Folder
local wind: Sound
local engine: Sound?

local function makeSound(id: string, volume: number, looped: boolean): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume * SoundConfig.MasterVolume
	sound.Looped = looped
	sound.Parent = holder
	return sound
end

-- Spelar ett kort ljud en gång (med valfri tonhöjd och volym).
function SoundController.Play(id: string, volume: number?, pitch: number?)
	local sound = makeSound(id, volume or 0.6, false)
	sound.PlaybackSpeed = pitch or 1
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
end

function SoundController.Start()
	holder = Instance.new("Folder")
	holder.Name = "HalmstadRushSounds"
	holder.Parent = SoundService

	wind = makeSound(SoundConfig.Wind, 0, true)
	if SoundConfig.EngineId ~= "" then
		engine = makeSound(SoundConfig.EngineId, SoundConfig.EngineVolume, true)
	end

	VehicleController.Entered:Connect(function()
		wind:Play()
		if engine then
			engine:Play()
		end
	end)
	VehicleController.Exited:Connect(function()
		wind:Stop()
		if engine then
			engine:Stop()
		end
	end)

	VehicleController.Crashed:Connect(function(strength: number)
		SoundController.Play(SoundConfig.Impact, math.clamp(strength / 80, 0.3, 1), 0.7)
	end)
	VehicleController.Wrecked:Connect(function()
		SoundController.Play(SoundConfig.Impact, 1, 0.5)
	end)
	VehicleController.Popup:Connect(function(_message: unknown, kind: string)
		if kind == "nearmiss" then
			SoundController.Play(SoundConfig.Ping, 0.25, 1.6)
		end
	end)

	Remotes.Get("Notify").OnClientEvent:Connect(function(text: unknown, kind: unknown)
		if text == "SPLASH!" then
			SoundController.Play(SoundConfig.Splash, 0.8)
		elseif kind == "money" then
			SoundController.Play(SoundConfig.Ping, 0.5, 1.2)
		end
	end)
	Remotes.Get("Takedown").OnClientEvent:Connect(function()
		SoundController.Play(SoundConfig.Ping, 0.7, 0.8)
	end)
	Remotes.Get("RaceCheckpoint").OnClientEvent:Connect(function()
		SoundController.Play(SoundConfig.Ping, 0.5, 1)
	end)

	local T = VehicleConfig.Tuning
	RunService.RenderStepped:Connect(function()
		if not VehicleController.GetCar() then
			return
		end
		local state = VehicleController.GetState()
		local ratio = math.clamp(math.abs(state.Speed) / T.BoostMaxSpeed, 0, 1)
		wind.Volume = SoundConfig.WindVolume * ratio * ratio * SoundConfig.MasterVolume
		wind.PlaybackSpeed = SoundConfig.WindPitch.Min + (SoundConfig.WindPitch.Max - SoundConfig.WindPitch.Min) * ratio
		local currentEngine = engine
		if currentEngine then
			local pitch = SoundConfig.EnginePitch
			currentEngine.PlaybackSpeed = pitch.Min + (pitch.Max - pitch.Min) * ratio + (if state.Boosting then 0.15 else 0)
		end
	end)
end

return SoundController
