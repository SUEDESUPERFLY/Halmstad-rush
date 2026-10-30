--!strict
-- Gemenskap: badges, Roblox-gruppen, vänbonus, topplistor och de gömda laxarna.

local CommunityConfig = {}

-- Badges skapas på create.roblox.com (spelet → Engagement → Badges). Id = 0 = inte skapad än.
CommunityConfig.Badges = {
	Welcome = { Id = 0, Name = "Welcome to Halmstad" },
	FirstRace = { Id = 0, Name = "First race" },
	RaceWin = { Id = 0, Name = "Race winner" },
	Takedowns100 = { Id = 0, Name = "100 takedowns" },
	Galgberget = { Id = 0, Name = "Top of Galgberget" },
	Tylosand = { Id = 0, Name = "Beach day in Tylösand" },
	AllSalmon = { Id = 0, Name = "Salmon hunter" },
	DailyAll = { Id = 0, Name = "Daily hero" },
} :: { [string]: { Id: number, Name: string } }

-- Roblox-grupp. 0 = ingen grupp (knappen och belöningen syns inte).
CommunityConfig.GroupId = 0
CommunityConfig.GroupCheckCooldown = 10 -- sekunder mellan kontroller när spelaren ber om det

-- Vänbonus: spelar du på samma server som en vän får du mer kronor.
CommunityConfig.FriendBonus = 0.1

-- Topplistor (OrderedDataStore). Hämtas om var RefreshInterval:e sekund.
CommunityConfig.LeaderboardSize = 10
CommunityConfig.LeaderboardRefresh = 60
CommunityConfig.LeaderboardWriteInterval = 60 -- veckans takedowns skrivs högst så här ofta per spelare
CommunityConfig.BoardPosition = Vector3.new(0, 0, -46) -- tavlan på Stora torg (står på stolpar, man kör under)

-- Gömda laxar: kronor per lax och extra när alla är hittade (låser upp lacken "Salmon silver").
CommunityConfig.SalmonReward = 100
CommunityConfig.AllSalmonReward = 2000
CommunityConfig.SalmonPickupRadius = 14
CommunityConfig.SalmonHeight = 5 -- över marken

-- Var laxarna ligger. Inne i staden letar servern upp närmaste park, torg eller gata från
-- punkten, minst MinRadius bort (så att laxen inte hamnar inne i ett landmärke).
-- Exact = punkten används som den är (utanför stadskartan). Namnet är ledtråden i listan.
export type SalmonSpot = { Id: string, Name: string, Position: Vector2, MinRadius: number?, Exact: boolean? }

local v = Vector2.new
CommunityConfig.Salmon = {
	{ Id = "S01", Name = "Stora torg", Position = v(60, 0) },
	{ Id = "S02", Name = "S:t Nikolai kyrka", Position = v(-109, 78), MinRadius = 40 },
	{ Id = "S03", Name = "Halmstads slott", Position = v(-10, 335), MinRadius = 60 },
	{ Id = "S04", Name = "Stadsbiblioteket", Position = v(310, -210), MinRadius = 35 },
	{ Id = "S05", Name = "Norre port", Position = v(86, -408), MinRadius = 12 },
	{ Id = "S06", Name = "Utsiktstornet", Position = v(-394, -1158), MinRadius = 18 },
	{ Id = "S07", Name = "Hallandsgården", Position = v(-212, -1086), MinRadius = 40 },
	{ Id = "S08", Name = "Halmstad C", Position = v(362, 654) },
	{ Id = "S09", Name = "Halmstad Arena", Position = v(2000, -24) },
	{ Id = "S10", Name = "Högskolan", Position = v(1546, 1276) },
	{ Id = "S11", Name = "Östra stranden", Position = v(600, 1776) },
	{ Id = "S12", Name = "Piren", Position = v(-100, 1830) },
	{ Id = "S13", Name = "Tylösand", Position = v(-3700, 1050), Exact = true },
	{ Id = "S14", Name = "Badbryggan", Position = v(-4000, 1230), Exact = true },
	{ Id = "S15", Name = "Sanddynerna", Position = v(-4500, 1120), Exact = true },
	{ Id = "S16", Name = "Vindkraftverken", Position = v(-2980, 620), Exact = true },
	{ Id = "S17", Name = "Galgberget", Position = v(-500, -1180) },
	{ Id = "S18", Name = "Nickedala", Position = v(-2100, -800) },
	{ Id = "S19", Name = "Karlsro", Position = v(-2118, -110) },
	{ Id = "S20", Name = "Rotorp", Position = v(-1538, 188) },
	{ Id = "S21", Name = "Alet", Position = v(-1596, 992) },
	{ Id = "S22", Name = "Söder", Position = v(-684, 1128) },
	{ Id = "S23", Name = "Gamletull", Position = v(402, -510) },
	{ Id = "S24", Name = "Furet", Position = v(1042, -994) },
	{ Id = "S25", Name = "Nyatorp", Position = v(1100, -160) },
	{ Id = "S26", Name = "Nyhem", Position = v(1430, 906) },
	{ Id = "S27", Name = "Östergård", Position = v(2108, 402) },
	{ Id = "S28", Name = "Sannarp", Position = v(2186, -606) },
	{ Id = "S29", Name = "Linehed", Position = v(2166, 1042) },
	{ Id = "S30", Name = "Centrum", Position = v(0, 150) },
} :: { SalmonSpot }

return CommunityConfig
