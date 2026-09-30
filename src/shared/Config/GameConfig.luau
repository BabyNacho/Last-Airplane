--[[
	GameConfig
	Central tuning for the round loop, players, condition system and security limits.
	Every timing in the game reads from here; do not hard-code durations in scripts.
]]

local GameConfig = {}

GameConfig.Version = "1.0.0"

-- Set true to print verbose state-machine / disaster logs to the output window.
GameConfig.Debug = false

-- In Roblox Studio you can force a specific disaster id (e.g. "CabinFire") for testing.
-- Ignored on live servers.
GameConfig.StudioForceDisaster = nil :: string?

-- Studio-only: multiply every phase duration by this factor for quick test loops.
GameConfig.StudioTimeScale = 1

GameConfig.Players = {
	MinToStart = 1, -- the game is fully playable solo
	MaxPerServer = 20,
	TargetPerServer = 12,
}

-- Phase durations in seconds. Phases with {min, max} pick a random value each round.
-- Total round time lands between ~5 and ~8 minutes.
GameConfig.Phases = {
	Lobby = 30, -- intermission countdown
	LobbyWhenEmpty = 5, -- re-check interval when nobody is ready
	Boarding = 18,
	Flight = { 35, 55 }, -- calm flight; subtle clues play during the second half
	Disaster = { 70, 90 }, -- disaster strikes, first objectives
	Crisis = { 80, 110 }, -- escalation, decisions, secondary events
	FinalEvent = 55, -- landing preparation
	Landing = 14, -- approach + touchdown cinematic
	Evacuation = 30, -- only when the landing requires it
	Results = 16,
}

-- Fraction of the Flight phase after which the disaster's clue sequence begins.
GameConfig.ClueStartFraction = 0.35

GameConfig.Condition = {
	MaxHealth = 100,
	InjuredBelow = 70,
	CriticalBelow = 35,
	BleedOutTime = 28, -- seconds an unconscious player can be revived
	ReviveHealth = 40,
	ReviveHoldTime = 3.2,
	AidHoldTime = 2.2,
	AidHeal = 30,
	AidHealWithKit = 55,
	AidCooldownPerTarget = 12,
	CriticalWalkSpeed = 10,
	InjuredWalkSpeed = 13.5,
	NormalWalkSpeed = 16,
	DownedDamageMultiplier = 1.5, -- extra damage while unconscious shortens the bleed-out
	-- When nobody else aboard can help, an unconscious player recovers on their own once per round.
	SoloRecoveryDelay = 9,
	SoloRecoveryHealth = 25,
}

GameConfig.Oxygen = {
	Max = 100,
	DrainPerSecond = 4.5, -- without a mask during depressurization
	RefillPerSecond = 25,
	HypoxiaDamagePerSecond = 3.5, -- once oxygen is empty
	PortableBottleDuration = 60,
	MaskRange = 7, -- studs from a deployed mask group
}

GameConfig.Fire = {
	TickInterval = 1,
	SpreadInterval = { 9, 14 },
	MaxIntensity = 100,
	StartIntensity = 45,
	GrowthPerTick = 1.6,
	DamageRadius = 6,
	DamagePerTick = 6, -- scaled by intensity
	ExtinguishPerTick = 34,
	ExtinguisherRange = 13,
	ExtinguisherCharge = 100,
	ExtinguisherDrainPerTick = 9,
	ReigniteInterval = 22, -- while the faulty circuit is still powered
	DoorSpreadBlock = true,
}

GameConfig.Turbulence = {
	-- per stage: seconds between jolts, base damage for unsecured players, stumble chance
	Stages = {
		{ Name = "Light", Interval = { 7, 11 }, Damage = 0, Stumble = 0.15 },
		{ Name = "Moderate", Interval = { 5, 8 }, Damage = 6, Stumble = 0.45 },
		{ Name = "Severe", Interval = { 3.5, 6 }, Damage = 12, Stumble = 0.7 },
	},
	SeatedProtection = 1.0, -- fraction of damage prevented while buckled in
}

GameConfig.Landing = {
	-- Landing score thresholds (0-100)
	Perfect = 85,
	Successful = 70,
	Hard = 50,
	Emergency = 30,
	RandomSpread = 5,
	-- touchdown damage {seated, unsecured} ranges per tier
	Damage = {
		Perfect = { { 0, 0 }, { 0, 10 } },
		Successful = { { 0, 0 }, { 5, 20 } },
		Hard = { { 0, 12 }, { 35, 60 } },
		Emergency = { { 10, 28 }, { 55, 85 } },
		Crash = { { 35, 70 }, { 90, 120 } },
	},
	UnresolvedCriticalPenalty = 12,
	ActiveFirePenalty = 14,
}

GameConfig.Manual = {
	-- Cockpit manual-flight minigame (server simulated)
	InputRate = 12, -- max inputs per second accepted
	DriftStrength = 22,
	CorrectionStrength = 55,
	GoodZone = 22, -- |attitude| below this counts as "on target"
}

GameConfig.Camera = {
	FlightMaxZoom = 12,
	LobbyMaxZoom = 28,
}

-- Per-remote rate limits: {tokens, refill per second}
GameConfig.RateLimits = {
	Default = { 10, 5 },
	DecisionVote = { 6, 2 },
	ShopPurchase = { 4, 1 },
	Equip = { 8, 3 },
	PilotInput = { 20, 14 },
	Emote = { 3, 1 },
	GetProfile = { 6, 2 },
}

GameConfig.Data = {
	StoreName = "LastFlight_PlayerData_v1",
	AutosaveInterval = 150,
	MaxRetries = 4,
	RetryDelay = 2,
	ReceiptHistory = 60, -- processed receipt ids kept for idempotency
	SchemaVersion = 1,
}

GameConfig.NPC = {
	Passengers = 14, -- seated passengers (performance friendly)
	FullFlightBonus = 4, -- extra passengers with the "Full Flight" modifier
	FlightAttendants = 2,
	InjuredMin = 1,
	InjuredMax = 3,
	HelpHoldTime = 2.5,
}

return GameConfig
