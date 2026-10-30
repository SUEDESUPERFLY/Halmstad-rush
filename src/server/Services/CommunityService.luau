--!strict
-- Spela tillsammans:
--  * Vänbonus: spelar du på samma server som en Roblox-vän får du CommunityConfig.FriendBonus
--    mer kronor (attributet FriendBonus, läses av EconomyService).
--  * Roblox-gruppen: medlemmar får lacken "Rush blue" (attributet Unlock_Group). Klienten kan be
--    servern kontrollera igen efter att ha gått med (CommunityAction "CheckGroup", med cooldown).
-- Inbjudningar till vänner sköts helt på klienten (SocialService), servern behövs inte.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CommunityConfig = require(ReplicatedStorage.Shared.Config.CommunityConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local CommunityService = {}

local friendCache: { [string]: boolean } = {}
local lastGroupCheck: { [Player]: number } = {}
local notifyRemote: RemoteEvent

local function areFriends(a: Player, b: Player): boolean
	local low, high = math.min(a.UserId, b.UserId), math.max(a.UserId, b.UserId)
	local key = low .. ":" .. high
	local cached = friendCache[key]
	if cached ~= nil then
		return cached
	end
	local ok, result = pcall(function()
		return a:IsFriendsWith(b.UserId)
	end)
	local friends = ok and result == true
	friendCache[key] = friends
	return friends
end

local function updateFriendBonus()
	local players = Players:GetPlayers()
	for _, player in players do
		local hasFriend = false
		for _, other in players do
			if other ~= player and areFriends(player, other) then
				hasFriend = true
				break
			end
		end
		local had = player:GetAttribute("FriendBonus") == true
		player:SetAttribute("FriendBonus", hasFriend)
		if hasFriend and not had then
			notifyRemote:FireClient(player, "Playing with friends: +10% kronor!", "money")
		end
	end
end

local function checkGroup(player: Player)
	if CommunityConfig.GroupId == 0 then
		return
	end
	local ok, inGroup = pcall(function()
		return player:IsInGroup(CommunityConfig.GroupId)
	end)
	if ok then
		local had = player:GetAttribute("Unlock_Group") == true
		player:SetAttribute("Unlock_Group", inGroup == true)
		if inGroup and not had then
			notifyRemote:FireClient(player, "Thanks for joining the group! Paint unlocked: Rush blue", "money")
		end
	end
end

function CommunityService.Init()
	notifyRemote = Remotes.Get("Notify")
	-- Klienten ber servern kontrollera gruppen igen (efter att ha gått med)
	Remotes.Get("CommunityAction").OnServerEvent:Connect(function(player: Player, action: unknown)
		if action ~= "CheckGroup" then
			return
		end
		local now = os.clock()
		if now - (lastGroupCheck[player] or -math.huge) < CommunityConfig.GroupCheckCooldown then
			return
		end
		lastGroupCheck[player] = now
		task.spawn(checkGroup, player)
	end)
end

function CommunityService.Start()
	local function onPlayer(player: Player)
		player:SetAttribute("GroupId", CommunityConfig.GroupId) -- klienten visar gruppknappen om den inte är 0
		task.spawn(checkGroup, player)
		task.spawn(updateFriendBonus)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastGroupCheck[player] = nil
		task.defer(updateFriendBonus)
	end)
end

return CommunityService
