--!strict
-- Ljud. Korta effekter är Robloxs inbyggda ljud (rbxasset://). Motor och musik är spelets
-- egna filer (assets/audio/, skapade av tools/audio/make_audio.py) som laddas upp på
-- create.roblox.com. Tomt ID = ljudet spelas inte.

local SoundConfig = {}

-- Motor (egen bil): tonhöjden följer ett låtsasvarvtal med växlar
SoundConfig.EngineId = "" -- t.ex. "rbxassetid://1234567890" (assets/audio/engine_loop.ogg)
SoundConfig.EngineVolume = 0.45
SoundConfig.EnginePitch = { Min = 0.75, Max = 2.1 } -- tomgång och högsta varv
SoundConfig.EngineGears = 5
SoundConfig.EngineIdleRpm = 0.12 -- 0..1
SoundConfig.EngineRevSpeed = 6 -- hur snabbt varvet följer gasen
SoundConfig.EngineBoostRpm = 0.12 -- extra varv under boost

-- Motorljud från andra bilar (spelare och trafik), 3D-ljud som hörs nära
SoundConfig.OtherEngineVolume = 0.3
SoundConfig.OtherEngineMaxDistance = 140
SoundConfig.OtherEngineLimit = 8 -- bara de närmaste bilarna låter

-- Bakgrundsmusik: spelas i tur och ordning och börjar om. Av/på med U eller ♪-knappen.
SoundConfig.MusicIds = {} :: { string } -- t.ex. { "rbxassetid://1234567890" } (assets/audio/music_loop.ogg)
SoundConfig.MusicVolume = 0.25

SoundConfig.Wind = "rbxasset://sounds/action_falling.mp3" -- fartvind, stiger med farten
SoundConfig.WindVolume = 0.35
SoundConfig.WindPitch = { Min = 0.6, Max = 1.4 }

SoundConfig.Impact = "rbxasset://sounds/action_jump_land.mp3" -- duns vid krock
SoundConfig.Splash = "rbxasset://sounds/impact_water.mp3"
SoundConfig.Ping = "rbxasset://sounds/electronicpingshort.wav" -- kontrollpunkt, pengar, takedown

SoundConfig.MasterVolume = 1

return SoundConfig
