--!strict
-- Ljud, bara lokalt:
--  * egen bil: motor med låtsasväxlar (om SoundConfig.EngineId finns) och fartvind
--  * andra bilar (spelare och trafik): 3D-motorljud för de närmaste
--  * bakgrundsmusik (SoundConfig.MusicIds), av/på med U eller ♪-knappen
--  * dunsar vid krock, plask i vattnet och pling vid kontrollpunkter, pengar, takedowns och nära ögat

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local SoundConfig = require(ReplicatedStorage.Shared.Config.SoundConfig)
local VehicleConfig = require(ReplicatedStorage.Shared.Config.VehicleConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local InputController = require(script.Parent.InputController)
local VehicleController = require(script.Parent.VehicleController)

local SoundController = {}

SoundController.MusicChanged = Signal.new() -- (enabled: boolean)

local T = VehicleConfig.Tuning
local CAR_TAG = "HalmstadCar"

local holder: Folder
local wind: Sound
local engine: Sound?
local rpm = SoundConfig.EngineIdleRpm

local music: Sound?
local musicIndex = 1
local musicEnabled = true

local otherEngines: { [Model]: Sound } = {}

local function makeSound(id: string, volume: number, looped: boolean, parent: Instance?): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume * SoundConfig.MasterVolume
	sound.Looped = looped
	sound.Parent = parent or holder
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

-- Varvtal 0..1 från farten (andel av toppfarten), med växlar: varvet stiger genom
-- varje växel och sjunker vid uppväxling.
local function gearRpm(ratio: number): number
	local gears = SoundConfig.EngineGears
	local position = math.clamp(ratio, 0, 1) * gears
	local gear = math.min(math.floor(position), gears - 1)
	local within = position - gear
	local low = if gear == 0 then SoundConfig.EngineIdleRpm else 0.45
	return low + (1 - low) * within
end

local function pitchFor(value: number): number
	local pitch = SoundConfig.EnginePitch
	return pitch.Min + (pitch.Max - pitch.Min) * value
end

-- Musik ---------------------------------------------------------------------

local function playTrack()
	local ids = SoundConfig.MusicIds
	if #ids == 0 or not musicEnabled then
		return
	end
	if music then
		music:Destroy()
	end
	local track = makeSound(ids[musicIndex], SoundConfig.MusicVolume, #ids == 1)
	track.Name = "Music"
	music = track
	track.Ended:Connect(function()
		musicIndex = musicIndex % #ids + 1
		playTrack()
	end)
	track:Play()
end

function SoundController.HasMusic(): boolean
	return #SoundConfig.MusicIds > 0
end

function SoundController.IsMusicEnabled(): boolean
	return musicEnabled
end

function SoundController.SetMusicEnabled(enabled: boolean)
	musicEnabled = enabled
	if enabled then
		playTrack()
	elseif music then
		music:Destroy()
		music = nil
	end
	SoundController.MusicChanged:Fire(enabled)
end

-- Andra bilars motorer -------------------------------------------------------

local function updateOtherEngines()
	local camera = workspace.CurrentCamera
	if SoundConfig.EngineId == "" or not camera then
		return
	end
	local own = VehicleController.GetCar()
	local listener = camera.CFrame.Position
	local nearby: { { Model: Model, Distance: number } } = {}
	for _, instance in CollectionService:GetTagged(CAR_TAG) do
		local model = instance :: Model
		local root = model.PrimaryPart
		if model ~= own and root then
			local distance = (root.Position - listener).Magnitude
			if distance < SoundConfig.OtherEngineMaxDistance then
				table.insert(nearby, { Model = model, Distance = distance })
			end
		end
	end
	table.sort(nearby, function(a, b)
		return a.Distance < b.Distance
	end)
	local keep: { [Model]: boolean } = {}
	for i = 1, math.min(#nearby, SoundConfig.OtherEngineLimit) do
		local model = nearby[i].Model
		keep[model] = true
		if not otherEngines[model] then
			local sound = makeSound(SoundConfig.EngineId, SoundConfig.OtherEngineVolume, true, model.PrimaryPart)
			sound.RollOffMode = Enum.RollOffMode.InverseTapered
			sound.RollOffMinDistance = 12
			sound.RollOffMaxDistance = SoundConfig.OtherEngineMaxDistance
			sound:Play()
			otherEngines[model] = sound
		end
	end
	for model, sound in otherEngines do
		if not keep[model] or not model.Parent then
			sound:Destroy()
			otherEngines[model] = nil
		end
	end
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
		rpm = SoundConfig.EngineIdleRpm
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

	-- Musik
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.U and SoundController.HasMusic() then
			SoundController.SetMusicEnabled(not musicEnabled)
		end
	end)
	playTrack()

	-- Andra bilar: välj de närmaste några gånger i sekunden
	task.spawn(function()
		while true do
			task.wait(0.25)
			updateOtherEngines()
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		-- Andra bilars tonhöjd följer deras fart
		for model, sound in otherEngines do
			local root = model.PrimaryPart
			if root then
				local ratio = (root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude / T.MaxSpeed
				sound.PlaybackSpeed = pitchFor(gearRpm(ratio))
			end
		end

		local car = VehicleController.GetCar()
		if not car then
			return
		end
		local state = VehicleController.GetState()
		local topSpeed = T.MaxSpeed * (tonumber(car:GetAttribute("TopSpeedMul")) or 1)
		local speedRatio = math.abs(state.Speed) / topSpeed

		local windRatio = math.clamp(math.abs(state.Speed) / T.BoostMaxSpeed, 0, 1)
		wind.Volume = SoundConfig.WindVolume * windRatio * windRatio * SoundConfig.MasterVolume
		wind.PlaybackSpeed = SoundConfig.WindPitch.Min + (SoundConfig.WindPitch.Max - SoundConfig.WindPitch.Min) * windRatio

		local currentEngine = engine
		if currentEngine then
			local throttle = math.abs(InputController.GetDriveInput().Throttle)
			local target
			if state.Wrecked then
				target = SoundConfig.EngineIdleRpm
			elseif state.Airborne then
				target = SoundConfig.EngineIdleRpm + throttle * 0.8 -- frivarv i luften
			else
				target = gearRpm(speedRatio) + (if throttle > 0.1 then 0.06 else -0.04)
			end
			if state.Boosting then
				target += SoundConfig.EngineBoostRpm
			end
			rpm += (math.clamp(target, 0, 1.15) - rpm) * math.min(1, dt * SoundConfig.EngineRevSpeed)
			currentEngine.PlaybackSpeed = pitchFor(rpm)
			currentEngine.Volume = SoundConfig.EngineVolume * (0.6 + 0.4 * throttle) * SoundConfig.MasterVolume
		end
	end)
end

return SoundController
