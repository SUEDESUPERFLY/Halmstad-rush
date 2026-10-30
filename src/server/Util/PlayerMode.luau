--!strict
-- Vilket läge en spelare är i (race, aktivitet, kull). Bara ett läge åt gången:
-- den som kör ett race kan inte samtidigt starta ett budjobb, öppna garaget osv.

local PlayerMode = {}

local modes: { [Player]: string } = {}

function PlayerMode.Get(player: Player): string?
	return modes[player]
end

function PlayerMode.IsFree(player: Player): boolean
	return modes[player] == nil
end

-- Returnerar false om spelaren redan är upptagen i ett annat läge.
function PlayerMode.Set(player: Player, mode: string): boolean
	local current = modes[player]
	if current and current ~= mode then
		return false
	end
	modes[player] = mode
	return true
end

function PlayerMode.Clear(player: Player, mode: string)
	if modes[player] == mode then
		modes[player] = nil
	end
end

game:GetService("Players").PlayerRemoving:Connect(function(player)
	modes[player] = nil
end)

return PlayerMode
