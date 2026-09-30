--[[
	MonetizationConfig
	Robux purchases. All purchases are optional cosmetics or credit packs.

	MANUAL STEP (Roblox requires this): create each Game Pass and Developer Product on the
	Creator Dashboard for your published experience, then paste the numeric ids below.
	Items whose Id is 0 are shown in the shop as "Coming soon" and cannot be bought, so the game
	never presents a purchase that isn't wired to a real product.
]]

local MonetizationConfig = {}

MonetizationConfig.GamePasses = {
	VIP = {
		Id = 0,
		Name = "VIP Boarding Pass",
		PriceHint = 249,
		Description = "VIP title & chat tag, VIP lounge access, Golden Wake trail, Gold interface and +20% Flight Credits.",
		Grants = { "TitleVIP", "TrailGolden", "ThemeGold" },
	},
	EmotePass = {
		Id = 0,
		Name = "Emote Pass",
		PriceHint = 149,
		Description = "Unlocks every dance emote, including the exclusive Victory Shuffle.",
		Grants = { "EmoteDance", "EmoteDance2", "EmoteDance3" },
	},
}

MonetizationConfig.Products = {
	CreditsSmall = {
		Id = 0,
		Name = "Pocket Change",
		PriceHint = 25,
		Credits = 400,
		Description = "400 Flight Credits.",
	},
	CreditsMedium = {
		Id = 0,
		Name = "Duty Free",
		PriceHint = 75,
		Credits = 1400,
		Description = "1,400 Flight Credits (+17% value).",
	},
	CreditsLarge = {
		Id = 0,
		Name = "First Class Upgrade",
		PriceHint = 199,
		Credits = 4200,
		Description = "4,200 Flight Credits (+31% value).",
	},
	FirstClassBundle = {
		Id = 0,
		Name = "First Class Bundle",
		PriceHint = 149,
		GrantItems = { "BundleFirstClass", "TrailRainbow", "VictoryGoldenWings", "TitleFirstClass" },
		OneTime = true,
		Description = "Rainbow Jetstream trail, Golden Wings effect, First Class title.",
	},
	PartyPack = {
		Id = 0,
		Name = "Party Pack",
		PriceHint = 99,
		GrantItems = { "BundleParty", "EmoteDance", "EmoteDance2", "EmoteDance3" },
		OneTime = true,
		Description = "Three dance emotes.",
	},
	JetpackReplica = {
		Id = 0,
		Name = "Jetpack Replica",
		PriceHint = 49,
		GrantItems = { "JetpackReplica" },
		OneTime = true,
		Description = "A cosmetic jetpack with glowing exhausts.",
	},
}

-- Products shown in the Premium tab as credit packs (in display order).
MonetizationConfig.CreditPackOrder = { "CreditsSmall", "CreditsMedium", "CreditsLarge" }

function MonetizationConfig.ProductKeyById(productId: number): string?
	for key, product in MonetizationConfig.Products do
		if product.Id ~= 0 and product.Id == productId then
			return key
		end
	end
	return nil
end

function MonetizationConfig.PassKeyById(passId: number): string?
	for key, pass in MonetizationConfig.GamePasses do
		if pass.Id ~= 0 and pass.Id == passId then
			return key
		end
	end
	return nil
end

return MonetizationConfig
