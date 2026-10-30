--!strict
-- Tecknade krockeffekter, bara lokalt på klienten: gnistor, rök, flygande plåtdelar
-- och "slow motion"-känsla (oskärpa + avmättade färger, plåtdelar som svävar sakta).
-- Fysiken saktas aldrig ner på riktigt.

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local EffectsController = {}

local holder: Folder
local blur: BlurEffect
local grade: ColorCorrectionEffect

local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local function emitterPart(position: Vector3): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.CFrame = CFrame.new(position)
	part.Parent = holder
	Debris:AddItem(part, 4)
	return part
end

function EffectsController.Sparks(position: Vector3, strength: number)
	local part = emitterPart(position)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARK_TEXTURE
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120), Color3.fromRGB(255, 120, 30))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.6, 0)
	sparks.Lifetime = NumberRange.new(0.3, 0.7)
	sparks.Speed = NumberRange.new(20, 45)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Acceleration = Vector3.new(0, -60, 0)
	sparks.Rate = 0
	sparks.Parent = part
	sparks:Emit(math.clamp(math.floor(strength / 2), 10, 60))
end

function EffectsController.Smoke(position: Vector3, amount: number)
	local part = emitterPart(position)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = SMOKE_TEXTURE
	smoke.Color = ColorSequence.new(Color3.fromRGB(200, 200, 200), Color3.fromRGB(120, 120, 120))
	smoke.Transparency = NumberSequence.new(0.3, 1)
	smoke.Size = NumberSequence.new(3, 10)
	smoke.Lifetime = NumberRange.new(1, 2)
	smoke.Speed = NumberRange.new(4, 10)
	smoke.SpreadAngle = Vector2.new(60, 60)
	smoke.Rate = 0
	smoke.Parent = part
	smoke:Emit(amount)
end

-- Plåtdelar som flyger iväg. Under `slowTime` sekunder bärs de nästan upp (motverkad
-- gravitation) och rör sig långsamt, sedan faller de som vanligt och tonas bort.
function EffectsController.Debris(position: Vector3, direction: Vector3, color: Color3, count: number, slowTime: number)
	if UserInputService.TouchEnabled then
		count = math.ceil(count / 2) -- färre lösa delar på mobil
	end
	local slow = slowTime > 0
	for _ = 1, count do
		local piece = Instance.new("Part")
		piece.Size = Vector3.new(math.random(10, 30) / 10, 0.2, math.random(8, 25) / 10)
		piece.Color = if math.random() < 0.6 then color else Color3.fromRGB(60, 60, 65)
		piece.Material = Enum.Material.Metal
		piece.CFrame = CFrame.new(position + Vector3.new(math.random() - 0.5, 1 + math.random(), math.random() - 0.5) * 2)
			* CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		piece.CanQuery = false
		piece.CanTouch = false
		piece.CollisionGroup = "Debris" -- krockar inte med bilar (registreras av CrashService)
		piece.Parent = holder

		local spread = Vector3.new(math.random() - 0.5, math.random() * 0.8 + 0.4, math.random() - 0.5) * 2
		local launch = (direction * 0.6 + spread).Unit * math.random(30, 60)
		local scale = if slow then 0.3 else 1
		piece.AssemblyLinearVelocity = launch * scale
		piece.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 20 * scale

		if slow then
			local attachment = Instance.new("Attachment")
			attachment.Parent = piece
			local float = Instance.new("VectorForce")
			float.Attachment0 = attachment
			float.RelativeTo = Enum.ActuatorRelativeTo.World
			float.Force = Vector3.new(0, piece.AssemblyMass * workspace.Gravity * 0.9, 0)
			float.Parent = piece
			task.delay(slowTime, function()
				if piece.Parent then
					float:Destroy()
					piece.AssemblyLinearVelocity *= 3
				end
			end)
		end

		task.delay(slowTime + 2, function()
			if piece.Parent then
				TweenService:Create(piece, TweenInfo.new(1), { Transparency = 1 }):Play()
			end
		end)
		Debris:AddItem(piece, slowTime + 3.2)
	end
end

-- Konfettiregn (developer product). Syns för alla i närheten.
function EffectsController.Confetti(position: Vector3)
	local part = emitterPart(position + Vector3.new(0, 12, 0))
	local confetti = Instance.new("ParticleEmitter")
	confetti.Texture = SPARK_TEXTURE
	confetti.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 60)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 220, 120)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 160, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 90, 255)),
	})
	confetti.Size = NumberSequence.new(0.8)
	confetti.Lifetime = NumberRange.new(2, 3.5)
	confetti.Speed = NumberRange.new(25, 45)
	confetti.SpreadAngle = Vector2.new(70, 70)
	confetti.Acceleration = Vector3.new(0, -25, 0)
	confetti.RotSpeed = NumberRange.new(-200, 200)
	confetti.Rate = 0
	confetti.Parent = part
	confetti:Emit(150)
end

-- Oskärpa och avmättade färger under krockkameran (känns som slow motion).
function EffectsController.SlowMotionLook(duration: number)
	local fadeIn = TweenInfo.new(0.15)
	local fadeOut = TweenInfo.new(0.4)
	TweenService:Create(blur, fadeIn, { Size = 8 }):Play()
	TweenService:Create(grade, fadeIn, { Saturation = -0.35, Contrast = 0.15 }):Play()
	task.delay(math.max(duration - 0.3, 0.1), function()
		TweenService:Create(blur, fadeOut, { Size = 0 }):Play()
		TweenService:Create(grade, fadeOut, { Saturation = 0, Contrast = 0 }):Play()
	end)
end

function EffectsController.Start()
	holder = Instance.new("Folder")
	holder.Name = "LocalEffects"
	holder.Parent = workspace

	blur = Instance.new("BlurEffect")
	blur.Size = 0
	blur.Parent = Lighting

	grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "CrashGrade"
	grade.Parent = Lighting
end

return EffectsController
