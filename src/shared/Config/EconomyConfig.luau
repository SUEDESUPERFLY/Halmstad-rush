--!strict
-- Pengar (kronor). Alla belopp betalas ut av servern, aldrig på klientens begäran.

local EconomyConfig = {}

EconomyConfig.Currency = "Kronor" -- namnet i leaderstats
EconomyConfig.StartMoney = 0
EconomyConfig.MaxSingleReward = 5000 -- skyddsräcke: ingen enskild utbetalning får vara större

-- Fri körning
EconomyConfig.TakedownReward = 25

return EconomyConfig
