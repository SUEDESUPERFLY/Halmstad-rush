--!strict
-- Roblox-badges (CommunityConfig.Badges). Delas bara ut av servern, från GameEvents och
-- från bilens position (toppen av Galgberget, Tylösand). Badges med Id = 0 hoppas över.

local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CommunityConfig = require(ReplicatedStorage.Shared.Config.CommunityConfig)
local MapData = require(ReplicatedStorage.Shared.Map.MapData)
local GameEvents = require(script.Parent.Parent.Util.GameEvents)
local DataService = require(script.Parent.DataService)
local VehicleService = require(script.Parent.VehicleService)

local AchievementService = {}

local awarded: { [Player]: { [string]: boolean } } = {}

local function award(player: Player, key: string)
	local badge = CommunityConfig.Badges[key]
	if not badge or badge.Id == 0 or player.Parent ~= Players then
		return
	end
	local mine = awarded[player]
	if not mine or mine[key] then
		return
	end
	mine[key] = true -- försök bara en gång per besök
	task.spawn(function()
		local ok, has = pcall(function()
			return BadgeService:UserHasBadgeAsync(player.UserId, badge.Id)
		end)
		if ok and has then
			return
		end
		local awardOk, err = pcall(function()
			BadgeService:AwardBadge(player.UserId, badge.Id)
		end)
		if not awardOk then
			warn(("[AchievementService] Badge %s kunde inte delas ut: %s"):format(key, tostring(err)))
		end
	end)
end

local function inArea(position: Vector3, name: string): boolean
	for _, area in MapData.SpecialAreas do
		if area.Name == name then
			return position.X >= area.Min.X and position.X <= area.Max.X and position.Z >= area.Min.Y and position.Z <= area.Max.Y
		end
	end
	return false
end

function AchievementService.Start()
	Players.PlayerAdded:Connect(function(player)
		awarded[player] = {}
		award(player, "Welcome")
	end)
	for _, player in Players:GetPlayers() do
		awarded[player] = {}
		award(player, "Welcome")
	end
	Players.PlayerRemoving:Connect(function(player)
		awarded[player] = nil
	end)

	GameEvents.Fired:Connect(function(player: Player, kind: string, _amount: number, info: { [string]: any })
		if kind == "RaceFinished" then
			award(player, "FirstRace")
			if info.Position == 1 then
				award(player, "RaceWin")
			end
		elseif kind == "Takedown" then
			local data = DataService.Get(player)
			if data and data.Takedowns >= 100 then
				award(player, "Takedowns100")
			end
		elseif kind == "SalmonAll" then
			award(player, "AllSalmon")
		elseif kind == "DailyAll" then
			award(player, "DailyAll")
		end
	end)

	-- Platser: toppen av Galgberget (vid utsiktstornet) och Tylösand
	local tower = MapData.Landmarks.LookoutTower
	task.spawn(function()
		while true do
			task.wait(2)
			for player, car in VehicleService.GetCars() do
				local root = car.PrimaryPart
				if root then
					local p = root.Position
					if (Vector2.new(p.X, p.Z) - tower).Magnitude < 80 then
						award(player, "Galgberget")
					end
					if inArea(p, "Tylösand") then
						award(player, "Tylosand")
					end
				end
			end
		end
	end)
end

return AchievementService
