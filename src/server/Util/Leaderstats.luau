--!strict
-- Gemensam åtkomst till leaderstats (syns i spelarlistan). Skapar mapp och värde vid behov,
-- så att flera services kan använda samma statistik utan att skapa dubbletter.

local Leaderstats = {}

function Leaderstats.Get(player: Player, name: string): IntValue
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "leaderstats"
		folder.Parent = player
	end
	local value = (folder :: Folder):FindFirstChild(name)
	if not value then
		value = Instance.new("IntValue")
		value.Name = name
		value.Parent = folder
	end
	return value :: IntValue
end

return Leaderstats
