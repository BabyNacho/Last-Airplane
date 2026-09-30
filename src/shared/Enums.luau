--[[
	Enums
	Shared string constants so server and client agree on names.
]]

local Enums = {}

Enums.Phase = {
	Lobby = "Lobby",
	Boarding = "Boarding",
	Flight = "Flight",
	Disaster = "Disaster",
	Crisis = "Crisis",
	FinalEvent = "FinalEvent",
	Landing = "Landing",
	Evacuation = "Evacuation",
	Results = "Results",
}

-- Phases during which the round is "live" (players are on the aircraft).
Enums.LivePhases = {
	Boarding = true,
	Flight = true,
	Disaster = true,
	Crisis = true,
	FinalEvent = true,
	Landing = true,
	Evacuation = true,
}

Enums.Condition = {
	Healthy = "Healthy",
	Injured = "Injured",
	Critical = "Critical",
	Unconscious = "Unconscious",
	Dead = "Dead",
}

Enums.ObjectiveKind = {
	Critical = "Critical",
	Optional = "Optional",
}

Enums.ObjectiveState = {
	Active = "Active",
	Completed = "Completed",
	Failed = "Failed",
}

Enums.LandingTier = {
	Perfect = "Perfect",
	Successful = "Successful",
	Hard = "Hard",
	Emergency = "Emergency",
	Crash = "Crash",
}

Enums.Outcome = {
	PerfectSurvival = { Title = "PERFECT SURVIVAL", Subtitle = "Everyone walked off that plane.", Color = Color3.fromRGB(90, 230, 150) },
	SuccessfulLanding = { Title = "SUCCESSFUL LANDING", Subtitle = "Shaken, but safe on the ground.", Color = Color3.fromRGB(90, 190, 255) },
	HardLanding = { Title = "HARD LANDING", Subtitle = "The aircraft is down. Hard.", Color = Color3.fromRGB(255, 200, 70) },
	EmergencyLanding = { Title = "EMERGENCY LANDING", Subtitle = "Down in one piece - mostly.", Color = Color3.fromRGB(255, 160, 60) },
	PartialSurvival = { Title = "PARTIAL SURVIVAL", Subtitle = "Not everyone made it.", Color = Color3.fromRGB(255, 130, 80) },
	FailedLanding = { Title = "CRASH LANDING", Subtitle = "The aircraft did not survive the landing.", Color = Color3.fromRGB(255, 80, 70) },
	CompleteDisaster = { Title = "COMPLETE DISASTER", Subtitle = "There were no survivors.", Color = Color3.fromRGB(200, 40, 60) },
}

-- Cabin lighting modes driven by FlightState.CabinLights
Enums.Lights = {
	Normal = "Normal",
	Dim = "Dim",
	Flicker = "Flicker",
	Emergency = "Emergency",
	Off = "Off",
}

return Enums
