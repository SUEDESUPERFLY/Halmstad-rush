--!strict
-- Översätter skyltar i världen som servern märkt med taggen "Localize" (engelsk text).
-- Körs bara för spelare med svenska som språk. Skyltar som strömmas in senare fångas också.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locale = require(ReplicatedStorage.Shared.Localization.Locale)

local LocaleController = {}

local function translate(instance: Instance)
	if instance:IsA("TextLabel") and not instance:GetAttribute("Translated") then
		instance:SetAttribute("Translated", true)
		instance.Text = Locale.T(instance.Text)
	end
end

function LocaleController.Start()
	if Locale.Language() == "en" then
		return
	end
	for _, instance in CollectionService:GetTagged("Localize") do
		translate(instance)
	end
	CollectionService:GetInstanceAddedSignal("Localize"):Connect(translate)
end

return LocaleController
