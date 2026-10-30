--!strict
-- Butik: game passes, developer products och daglig belöning.
--
-- Rättvisa (se CLAUDE.md): Robux ger bara kosmetik eller bekvämlighet. Inga kronor,
-- bilar, uppgraderingar eller fartfördelar säljs för Robux, och inget är slumpat.
--
-- ID:n skapas på create.roblox.com (spelet → Monetization → Passes / Developer Products)
-- och skrivs in här. Med Id = 0 är köpet avstängt i spelet, men kan provas i Studio
-- med knappen "Testa (Studio)" (servern tillåter det bara när RunService:IsStudio()).

export type Pass = { Key: string, Id: number, Name: string, Description: string }
export type Product = { Key: string, Id: number, Name: string, Description: string }

local ShopConfig = {}

ShopConfig.Passes = {
	{ Key = "VipPaint", Id = 2062667574, Name = "VIP Paint", Description = "6 exclusive paint colours: gold, chrome, pearl white, neon pink, neon green and midnight." },
	{ Key = "Underglow", Id = 2061401929, Name = "Neon Underglow", Description = "Neon lights under all your cars. Looks only." },
	{ Key = "FastTravel", Id = 2062127808, Name = "Fast Travel+", Description = "No waiting between fast travels. Convenience, no speed advantage." },
} :: { Pass }

ShopConfig.Products = {
	{ Key = "Confetti", Id = 3724218944, Name = "Confetti Shower", Description = "Celebrate with confetti over your car – everyone nearby sees it." },
	{ Key = "Support", Id = 3724219257, Name = "Support the Developer", Description = "A big thank you! Gives no advantage in the game." },
} :: { Product }

ShopConfig.StudioTestPurchases = true

-- Daglig belöning: Base + PerStreakDay för varje dag i rad (max MaxStreakBonusDays dagar).
ShopConfig.Daily = {
	Base = 100,
	PerStreakDay = 50,
	MaxStreakBonusDays = 6,
}

function ShopConfig.DailyReward(streak: number): number
	local daily = ShopConfig.Daily
	return daily.Base + daily.PerStreakDay * math.clamp(streak - 1, 0, daily.MaxStreakBonusDays)
end

function ShopConfig.FindPass(key: string): Pass?
	for _, pass in ShopConfig.Passes do
		if pass.Key == key then
			return pass
		end
	end
	return nil
end

function ShopConfig.FindProduct(key: string): Product?
	for _, product in ShopConfig.Products do
		if product.Key == key then
			return product
		end
	end
	return nil
end

function ShopConfig.PassAttribute(key: string): string
	return "Pass_" .. key
end

return ShopConfig
