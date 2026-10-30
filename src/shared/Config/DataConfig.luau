--!strict
-- Inställningar för sparad spelardata (DataService).

local DataConfig = {}

DataConfig.StoreName = "HalmstadRush_Players"
DataConfig.KeyPrefix = "Player_"
DataConfig.SchemaVersion = 2

DataConfig.AutosaveInterval = 120 -- sekunder
DataConfig.Retries = 5 -- försök per DataStore-anrop
DataConfig.RetryBaseDelay = 1 -- 1, 2, 4, 8 ... sekunder
DataConfig.LockTimeout = 600 -- ett lås äldre än så räknas som övergivet (servern kraschade)
DataConfig.LockWaitAttempts = 6 -- försök att få låset innan spelaren kickas
DataConfig.LockWaitDelay = 3
DataConfig.LoadTimeout = 20 -- så länge andra services väntar på profilen

return DataConfig
