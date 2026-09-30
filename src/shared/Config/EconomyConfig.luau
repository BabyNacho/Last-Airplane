--[[
	EconomyConfig
	Flight Credits rewards. A typical survived round pays roughly 120-220 credits,
	so a common cosmetic is 2-4 rounds away and nothing requires Robux.
]]

local EconomyConfig = {}

EconomyConfig.CurrencyName = "Flight Credits"
EconomyConfig.CurrencyShort = "FC"
EconomyConfig.StartingCredits = 150

EconomyConfig.Rewards = {
	Participation = 20,
	Survived = 45,
	ObjectiveCritical = 22,
	ObjectiveOptional = 12,
	ObjectiveAssist = 6, -- teammates alive when a critical objective completes
	Rescue = 30, -- reviving an unconscious player
	Aid = 12, -- treating an injured player
	PassengerHelped = 10, -- helping an NPC passenger
	DecisionSuccess = 15, -- your vote matched a decision that turned out well
	BraveBonus = 20, -- completing an objective inside an active hazard
	Evacuated = 15,
	PerfectLandingBonus = 40,
	SuccessfulLandingBonus = 25,
	HardLandingBonus = 12,
	EmergencyLandingBonus = 8,
	TeamSurvivalBonus = 20, -- every participant survived (multiplayer only)
	FirstFlightOfDay = 50,
}

-- Rewards multiplied by disaster difficulty.
EconomyConfig.DifficultyMultiplier = {
	[1] = 1.0,
	[2] = 1.2,
	[3] = 1.4,
}

-- Game pass bonus (convenience only - credits only buy cosmetics).
EconomyConfig.VIPCreditMultiplier = 1.2

-- Hard cap per round to protect against unexpected stacking.
EconomyConfig.MaxCreditsPerRound = 900

return EconomyConfig
