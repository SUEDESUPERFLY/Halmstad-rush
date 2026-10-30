--!strict
-- Händelser som servern själv har avgjort (takedown, målgång, aktivitet klar, lax hittad ...).
-- Utmaningar, badges och topplistor lyssnar här, så att spelets services inte behöver
-- känna till dem. Klienten kan aldrig skicka en sådan händelse.
--
-- Fire(player, kind, amount?, info?) – kind enligt ChallengeConfig (t.ex. "Takedown"),
-- amount = hur mycket (standard 1), info = extra data (t.ex. { RaceId, Time, Position }).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local GameEvents = {}

GameEvents.Fired = Signal.new() -- (player: Player, kind: string, amount: number, info: { [string]: any })

function GameEvents.Fire(player: Player, kind: string, amount: number?, info: { [string]: any }?)
	GameEvents.Fired:Fire(player, kind, amount or 1, info or {})
end

return GameEvents
