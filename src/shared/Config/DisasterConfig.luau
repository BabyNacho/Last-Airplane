--[[
	DisasterConfig
	Selection weights, difficulty and presentation data for every disaster.
	To add a disaster: create a module in ServerScriptService.Server.Disasters with the same Id
	and add an entry here. Nothing else needs to change.
]]

local DisasterConfig = {}

-- Difficulty 1 (easy) .. 3 (hard). Difficulty scales rewards (see EconomyConfig.DifficultyMultiplier).
DisasterConfig.Disasters = {
	EngineFailure = {
		DisplayName = "Engine Failure",
		Weight = 12,
		Difficulty = 2,
		Rare = false,
		Summary = "Engine one lost power mid-flight.",
		Icon = "rbxassetid://0",
	},
	Turbulence = {
		DisplayName = "Severe Turbulence",
		Weight = 12,
		Difficulty = 1,
		Rare = false,
		Summary = "A violent clear-air turbulence zone shook the aircraft.",
	},
	CabinFire = {
		DisplayName = "Cabin Fire",
		Weight = 11,
		Difficulty = 3,
		Rare = false,
		Summary = "An electrical fault started a fire inside the cabin.",
	},
	LightningStorm = {
		DisplayName = "Lightning Strike",
		Weight = 10,
		Difficulty = 2,
		Rare = false,
		Summary = "The aircraft took a direct lightning strike inside a storm cell.",
	},
	BirdStrike = {
		DisplayName = "Bird Strike",
		Weight = 10,
		Difficulty = 2,
		Rare = false,
		Summary = "A flock of birds collided with the aircraft.",
	},
	Depressurization = {
		DisplayName = "Cabin Depressurization",
		Weight = 9,
		Difficulty = 3,
		Rare = false,
		Summary = "The cabin lost pressure at cruising altitude.",
	},
	PilotDisappears = {
		DisplayName = "The Empty Cockpit",
		Weight = 7,
		Difficulty = 3,
		Rare = true,
		Summary = "Both pilots vanished from the flight deck.",
	},
	HydraulicFailure = {
		DisplayName = "Hydraulic Failure",
		Weight = 8,
		Difficulty = 2,
		Rare = false,
		Summary = "A ruptured line drained the hydraulic system.",
	},
	NavigationFailure = {
		DisplayName = "Blind Approach",
		Weight = 6,
		Difficulty = 2,
		Rare = true,
		Summary = "Navigation systems failed during a fog-covered approach.",
	},
}

-- Avoid repeating the same disaster in back-to-back rounds.
DisasterConfig.AvoidRepeatCount = 2

--[[
	Random round modifiers: controlled randomness that changes the feel of a round without
	being unfair. At most MaxModifiers are chosen per round.
]]
DisasterConfig.MaxModifiers = 1
DisasterConfig.ModifierChance = 0.55

DisasterConfig.Modifiers = {
	NightFlight = {
		DisplayName = "Night Flight",
		Description = "It's dark outside. Cabin lights are dimmed.",
		Weight = 10,
		RewardBonus = 0.05,
	},
	FullFlight = {
		DisplayName = "Full Flight",
		Description = "Every seat is booked. More passengers need help.",
		Weight = 10,
		RewardBonus = 0.05,
	},
	RoughAir = {
		DisplayName = "Rough Air",
		Description = "Occasional bumps throughout the flight.",
		Weight = 8,
		RewardBonus = 0.1,
		IncompatibleWith = { "Turbulence" },
	},
	VeteranCrew = {
		DisplayName = "Veteran Crew",
		Description = "An experienced crew keeps the cabin calm. Landings are a bit easier.",
		Weight = 7,
		RewardBonus = -0.05,
	},
	LowFuel = {
		DisplayName = "Low Fuel",
		Description = "Fuel reserves are tight. Less time before the landing.",
		Weight = 6,
		RewardBonus = 0.15,
	},
}

return DisasterConfig
