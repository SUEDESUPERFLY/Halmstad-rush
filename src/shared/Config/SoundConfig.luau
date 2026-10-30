--!strict
-- Ljud. Standard är Robloxs inbyggda ljud (rbxasset://), som alltid finns och inte kräver
-- uppladdning. Ett riktigt motorljud kan läggas in som ett ljud-ID från Creator Store
-- (Studio: Toolbox → Audio, sök "car engine loop", högerklicka → Copy Asset ID) i EngineId.

local SoundConfig = {}

SoundConfig.EngineId = "" -- t.ex. "rbxassetid://1234567890"; tomt = inget motorljud
SoundConfig.EngineVolume = 0.5
SoundConfig.EnginePitch = { Min = 0.7, Max = 1.8 }

SoundConfig.Wind = "rbxasset://sounds/action_falling.mp3" -- fartvind, stiger med farten
SoundConfig.WindVolume = 0.45
SoundConfig.WindPitch = { Min = 0.6, Max = 1.4 }

SoundConfig.Impact = "rbxasset://sounds/action_jump_land.mp3" -- duns vid krock
SoundConfig.Splash = "rbxasset://sounds/impact_water.mp3"
SoundConfig.Ping = "rbxasset://sounds/electronicpingshort.wav" -- kontrollpunkt, pengar, takedown

SoundConfig.MasterVolume = 1

return SoundConfig
