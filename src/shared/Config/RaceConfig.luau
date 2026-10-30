--!strict
-- Race. Banorna följer de genererade rutterna (src/server/Map/Generated/CityRoutes.luau).

export type RaceDefinition = {
	Id: string,
	Name: string,
	Route: string, -- namn i CityRoutes
	StartIndex: number, -- ruttpunkt där start/mål ligger
	CheckpointSpacing: number, -- ruttpunkter mellan kontrollpunkter (≈ 20 studs per punkt)
	Laps: number,
	Rivals: number,
	RivalSpeeds: { number },
	Rewards: { number }, -- kronor per placering (1:a, 2:a, ...), sista värdet gäller resten
}

local RaceConfig = {}

RaceConfig.Races = {
	{
		Id = "StoraRingen",
		Name = "Stora ringen",
		Route = "StoraRingen",
		StartIndex = 3,
		CheckpointSpacing = 22,
		Laps = 1,
		Rivals = 3,
		RivalSpeeds = { 92, 100, 108 },
		Rewards = { 500, 300, 200, 100 },
	},
} :: { RaceDefinition }

RaceConfig.CollisionGroup = "RaceCars" -- deltagare krockar med varandra och trafiken, inte med andra spelare
RaceConfig.StartRadius = 30 -- så nära startmarkeringen man måste vara för att starta/gå med
RaceConfig.LobbyTime = 8 -- sekunder andra kan gå med innan start
RaceConfig.Countdown = 3.5
RaceConfig.CheckpointRadius = 42
RaceConfig.FinishTimeout = 30 -- efter att första bilen gått i mål
RaceConfig.MaxRaceTime = 300
RaceConfig.MaxParticipants = 8 -- spelare + NPC-motståndare
RaceConfig.CooldownAfterRace = 5
RaceConfig.TakedownBonus = 50 -- kronor per takedown under racet
RaceConfig.GridMoveTolerance = 15 -- studs man får rulla från startrutan under nedräkningen
RaceConfig.RubberBand = 0.0015 -- NPC-motståndarnas fartjustering per ruttpunkt efter/före ledande spelare
RaceConfig.RubberBandMax = 0.25
RaceConfig.RivalWreckDuration = 2.5
RaceConfig.PlayerTakedownRadius = 25 -- kvaddad racedeltagare med en annan deltagare så nära = takedown

function RaceConfig.Find(id: string): RaceDefinition?
	for _, race in RaceConfig.Races do
		if race.Id == id then
			return race
		end
	end
	return nil
end

return RaceConfig
