--!strict
-- Dagliga utmaningar, kom igång-guiden för nya spelare och veckans race.
-- Allt räknas på servern (ChallengeService) från händelser som servern själv avgör.
--
-- Händelsetyper (Kind):
--   Takedown, RaceFinished, RacePodium (topp 3), ActivityFinished, Delivery,
--   StuntMedal, DriftMedal, TagFinished, SalmonFound, Distance (meter),
--   Drift (sekunder i sladd), Boost (sekunder över normal toppfart)

export type Goal = {
	Id: string,
	Kind: string,
	Goal: number,
	Reward: number,
	Text: string, -- engelsk text, %d = målet (översätts i Swedish.luau)
}

local ChallengeConfig = {}

ChallengeConfig.PerDay = 3
ChallengeConfig.AllDoneBonus = 500 -- extra när alla dagens utmaningar är klara
ChallengeConfig.MetersPerStud = 0.28 -- samma omräkning som avståndsskyltarna i spelet

ChallengeConfig.Pool = {
	{ Id = "Takedowns5", Kind = "Takedown", Goal = 5, Reward = 250, Text = "Takedown %d traffic cars" },
	{ Id = "Takedowns12", Kind = "Takedown", Goal = 12, Reward = 450, Text = "Takedown %d traffic cars" },
	{ Id = "RaceFinish", Kind = "RaceFinished", Goal = 1, Reward = 250, Text = "Finish %d race" },
	{ Id = "RacePodium", Kind = "RacePodium", Goal = 1, Reward = 400, Text = "Finish top 3 in %d race" },
	{ Id = "Activities3", Kind = "ActivityFinished", Goal = 3, Reward = 350, Text = "Complete %d activities" },
	{ Id = "Deliveries2", Kind = "Delivery", Goal = 2, Reward = 300, Text = "Complete %d pizza or taxi jobs" },
	{ Id = "StuntMedal", Kind = "StuntMedal", Goal = 1, Reward = 300, Text = "Win a medal in %d beach jump" },
	{ Id = "DriftMedal", Kind = "DriftMedal", Goal = 1, Reward = 300, Text = "Win a medal in Drift King %d time" },
	{ Id = "Tag", Kind = "TagFinished", Goal = 1, Reward = 250, Text = "Play %d round of Car Tag" },
	{ Id = "Drive5km", Kind = "Distance", Goal = 5000, Reward = 250, Text = "Drive %d m" },
	{ Id = "Drive10km", Kind = "Distance", Goal = 10000, Reward = 400, Text = "Drive %d m" },
	{ Id = "Salmon2", Kind = "SalmonFound", Goal = 2, Reward = 300, Text = "Find %d hidden salmon" },
	{ Id = "Drift20", Kind = "Drift", Goal = 20, Reward = 250, Text = "Drift for %d seconds" },
} :: { Goal }

-- Kom igång (nya spelare). Belöningen betalas efter varje steg.
ChallengeConfig.Tutorial = {
	{ Id = "T1", Kind = "Distance", Goal = 300, Reward = 50, Text = "Drive %d m (W / GAS)" },
	{ Id = "T2", Kind = "Drift", Goal = 2, Reward = 50, Text = "Drift for %d seconds (hold Space / DRIFT in a turn)" },
	{ Id = "T3", Kind = "Boost", Goal = 2, Reward = 50, Text = "Boost for %d seconds (Shift / BOOST)" },
	{ Id = "T4", Kind = "Takedown", Goal = 1, Reward = 350, Text = "Bump a traffic car until it wrecks: %d takedown" },
} :: { Goal }

-- Hur servern känner igen sladd och boost (från bilens replikerade fart)
ChallengeConfig.DriftMinSpeed = 40 -- studs/s
ChallengeConfig.DriftMinLateral = 18 -- studs/s i sidled
ChallengeConfig.BoostOverTopSpeed = 1.05 -- fart över toppfarten × detta = boost
ChallengeConfig.SampleInterval = 0.25
ChallengeConfig.MaxStudsPerSample = 70 -- längre hopp (teleport) räknas inte som körd sträcka

-- Veckans race: slå måltiden en gång per vecka för en bonus. Veckan börjar måndag (UTC).
ChallengeConfig.Weekly = {
	RaceId = "StoraRingen",
	TargetTime = 115, -- sekunder
	Reward = 600,
}

-- Veckonummer (måndag–söndag, UTC). Unix-tid 0 var en torsdag.
function ChallengeConfig.Week(time: number): number
	return (time + 3 * 86400) // (7 * 86400)
end

function ChallengeConfig.Day(time: number): number
	return time // 86400
end

-- Dagens utmaningar är samma för alla spelare (slumpas från dagnumret).
function ChallengeConfig.ForDay(day: number): { Goal }
	local rng = Random.new(day * 7919 + 13)
	local pool = table.clone(ChallengeConfig.Pool)
	local picked = {}
	local usedKinds: { [string]: boolean } = {}
	while #picked < ChallengeConfig.PerDay and #pool > 0 do
		local goal = table.remove(pool, rng:NextInteger(1, #pool)) :: Goal
		if not usedKinds[goal.Kind] then
			usedKinds[goal.Kind] = true
			table.insert(picked, goal)
		end
	end
	return picked
end

return ChallengeConfig
