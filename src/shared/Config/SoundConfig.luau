--[[
	SoundConfig
	Every sound in the game, by category. The defaults use audio that ships with the Roblox
	client (rbxasset://sounds/...) so the game is never silent. For a production release,
	replace SoundId values with uploaded/licensed rbxassetid:// audio - nothing else changes.
	An empty SoundId simply disables that sound.
]]

local SoundConfig = {}

SoundConfig.Groups = {
	Ambience = 0.55,
	Alerts = 0.7,
	Disasters = 0.8,
	Interaction = 0.6,
	UI = 0.5,
}

SoundConfig.Sounds = {
	-- AMBIENCE (looped)
	CabinHum = { Group = "Ambience", SoundId = "rbxasset://sounds/action_falling.mp3", Volume = 0.35, Pitch = 0.32, Looped = true },
	EngineDrone = { Group = "Ambience", SoundId = "rbxasset://sounds/action_swim.mp3", Volume = 0.18, Pitch = 0.25, Looped = true },
	LobbyAmbience = { Group = "Ambience", SoundId = "rbxasset://sounds/action_falling.mp3", Volume = 0.06, Pitch = 0.6, Looped = true },
	WindRush = { Group = "Ambience", SoundId = "rbxasset://sounds/action_falling.mp3", Volume = 0.7, Pitch = 0.8, Looped = true },
	RainLoop = { Group = "Ambience", SoundId = "rbxasset://sounds/action_swim.mp3", Volume = 0.25, Pitch = 1.4, Looped = true },

	-- ALERTS
	Chime = { Group = "Alerts", SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6, Pitch = 0.8 },
	SeatbeltChime = { Group = "Alerts", SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6, Pitch = 1.1 },
	MasterCaution = { Group = "Alerts", SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.8, Pitch = 1.6, Looped = true, PlaybackGap = true },
	FireAlarm = { Group = "Alerts", SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.7, Pitch = 2.2, Looped = true },
	PressureAlarm = { Group = "Alerts", SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.7, Pitch = 1.3, Looped = true },
	PullUp = { Group = "Alerts", SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.8, Pitch = 0.6, Looped = true },
	Intercom = { Group = "Alerts", SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.45, Pitch = 0.55 },

	-- DISASTERS
	Impact = { Group = "Disasters", SoundId = "rbxasset://sounds/collide.wav", Volume = 1, Pitch = 0.6 },
	BigImpact = { Group = "Disasters", SoundId = "rbxasset://sounds/Rocket shot.wav", Volume = 1, Pitch = 0.45 },
	Thunder = { Group = "Disasters", SoundId = "rbxasset://sounds/Launching rocket.wav", Volume = 1, Pitch = 0.35 },
	ThunderDistant = { Group = "Disasters", SoundId = "rbxasset://sounds/Launching rocket.wav", Volume = 0.35, Pitch = 0.3 },
	GlassCrack = { Group = "Disasters", SoundId = "rbxasset://sounds/glassbreak.wav", Volume = 0.8, Pitch = 1.2 },
	Decompression = { Group = "Disasters", SoundId = "rbxasset://sounds/Rocket whoosh 01.wav", Volume = 1, Pitch = 0.5 },
	FireLoop = { Group = "Disasters", SoundId = "rbxasset://sounds/Rocket whoosh 01.wav", Volume = 0.35, Pitch = 0.3, Looped = true },
	Sparks = { Group = "Disasters", SoundId = "rbxasset://sounds/snap.wav", Volume = 0.7, Pitch = 1.4 },
	PowerDown = { Group = "Disasters", SoundId = "rbxasset://sounds/switch.wav", Volume = 0.8, Pitch = 0.5 },
	PowerUp = { Group = "Disasters", SoundId = "rbxasset://sounds/switch.wav", Volume = 0.8, Pitch = 1.2 },
	EngineSputter = { Group = "Disasters", SoundId = "rbxasset://sounds/action_swim.mp3", Volume = 0.5, Pitch = 0.18, Looped = true },
	Creak = { Group = "Disasters", SoundId = "rbxasset://sounds/uuhhh.mp3", Volume = 0.25, Pitch = 0.3 },
	Touchdown = { Group = "Disasters", SoundId = "rbxasset://sounds/Rocket shot.wav", Volume = 1, Pitch = 0.3 },
	Extinguisher = { Group = "Disasters", SoundId = "rbxasset://sounds/Rocket whoosh 01.wav", Volume = 0.45, Pitch = 1.6 },

	-- INTERACTION
	Button = { Group = "Interaction", SoundId = "rbxasset://sounds/switch.wav", Volume = 0.6, Pitch = 1 },
	Door = { Group = "Interaction", SoundId = "rbxasset://sounds/swoosh.wav", Volume = 0.6, Pitch = 0.7 },
	Equip = { Group = "Interaction", SoundId = "rbxasset://sounds/clickfast.wav", Volume = 0.6, Pitch = 1 },
	Revive = { Group = "Interaction", SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6, Pitch = 1.4 },
	Axe = { Group = "Interaction", SoundId = "rbxasset://sounds/collide.wav", Volume = 0.8, Pitch = 1.3 },

	-- UI
	Click = { Group = "UI", SoundId = "rbxasset://sounds/button.wav", Volume = 0.5, Pitch = 1 },
	Hover = { Group = "UI", SoundId = "rbxasset://sounds/clickfast.wav", Volume = 0.2, Pitch = 1.6 },
	Notify = { Group = "UI", SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.35, Pitch = 1.2 },
	ObjectiveNew = { Group = "UI", SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.45, Pitch = 0.9 },
	ObjectiveComplete = { Group = "UI", SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.55, Pitch = 1.5 },
	Reward = { Group = "UI", SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.5, Pitch = 1.9 },
	Purchase = { Group = "UI", SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6, Pitch = 2.1 },
	Achievement = { Group = "UI", SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6, Pitch = 1.7 },
	Warning = { Group = "UI", SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6, Pitch = 0.7 },
	Countdown = { Group = "UI", SoundId = "rbxasset://sounds/clickfast.wav", Volume = 0.4, Pitch = 1.2 },
	Decision = { Group = "UI", SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6, Pitch = 0.65 },
}

return SoundConfig
