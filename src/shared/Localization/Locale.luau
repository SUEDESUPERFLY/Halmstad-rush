--!strict
-- Språk: engelska är grundspråket, svenska visas för spelare vars Roblox-språk är svenska.
-- Översättningarna ligger i Swedish.luau med den engelska källtexten som nyckel. Källtexten
-- kan vara ett format (%d, %s), som översätts först och formateras sedan.
--
-- Servern översätter aldrig själv. Den skickar `Locale.Msg(format, ...)` (eller en vanlig
-- engelsk sträng), och klienten gör om det till text med `Locale.Resolve`. Argument som
-- själva är Msg översätts också; vanliga strängar (t.ex. spelarnamn) lämnas orörda.

local LocalizationService = game:GetService("LocalizationService")
local RunService = game:GetService("RunService")

local Swedish = require(script.Parent.Swedish)

export type Message = string | { any }

local Locale = {}

local language = "en"
if RunService:IsClient() then
	local ok, localeId = pcall(function()
		return LocalizationService.RobloxLocaleId
	end)
	if ok and typeof(localeId) == "string" and localeId:lower():sub(1, 2) == "sv" then
		language = "sv"
	end
end

function Locale.Language(): string
	return language
end

-- Översätter en engelsk källtext (eller ett format) och formaterar med argumenten.
function Locale.T(source: string, ...: any): string
	local text = if language == "sv" then (Swedish[source] or source) else source
	if select("#", ...) == 0 then
		return text
	end
	local ok, result = pcall(string.format, text, ...)
	if ok then
		return result
	end
	local fallbackOk, fallback = pcall(string.format, source, ...)
	return if fallbackOk then fallback else source
end

-- För text som servern måste visa direkt (t.ex. kick-meddelanden), på spelarens språk.
function Locale.ForPlayer(player: Player, source: string): string
	local isSwedish = player.LocaleId:lower():sub(1, 2) == "sv"
	return if isSwedish then (Swedish[source] or source) else source
end

-- Paketerar en text som ska översättas hos mottagaren.
function Locale.Msg(source: string, ...: any): { any }
	return { source, ... }
end

-- Gör om en sträng eller Msg till text på spelarens språk.
function Locale.Resolve(message: unknown): string
	if typeof(message) == "string" then
		return Locale.T(message)
	end
	if typeof(message) == "table" then
		local parts = message :: { any }
		local source = parts[1]
		if typeof(source) ~= "string" then
			return ""
		end
		local args = {}
		for i = 2, #parts do
			local arg = parts[i]
			args[i - 1] = if typeof(arg) == "table" then Locale.Resolve(arg) else arg
		end
		return Locale.T(source, table.unpack(args, 1, #parts - 1))
	end
	return ""
end

return Locale
