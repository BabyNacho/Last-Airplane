--[[
	AchievementConfig
	Stat-threshold achievements are checked automatically after every stat change.
	Event achievements (Stat = nil) are awarded by AchievementService from round summaries.
]]

local AchievementConfig = {}

AchievementConfig.List = {
	{ Id = "FirstFlight", Name = "First Flight", Description = "Survive your first disaster.", Stat = "Survived", Goal = 1, Reward = 50 },
	{ Id = "Survivor", Name = "Survivor", Description = "Survive 10 flights.", Stat = "Survived", Goal = 10, Reward = 150, Title = "TitleSurvivor" },
	{ Id = "Veteran", Name = "Veteran Flyer", Description = "Survive 50 flights.", Stat = "Survived", Goal = 50, Reward = 400 },
	{ Id = "FrequentFlyer", Name = "Frequent Flyer", Description = "Board 25 flights.", Stat = "Flights", Goal = 25, Reward = 150 },
	{ Id = "Lifesaver", Name = "Lifesaver", Description = "Revive another player.", Stat = "Rescues", Goal = 1, Reward = 75 },
	{ Id = "Guardian", Name = "Guardian Angel", Description = "Revive 10 players.", Stat = "Rescues", Goal = 10, Reward = 250, Title = "TitleLifesaver" },
	{ Id = "Medic", Name = "Field Medic", Description = "Treat 10 injured players.", Stat = "Aids", Goal = 10, Reward = 150 },
	{ Id = "GoodSamaritan", Name = "Good Samaritan", Description = "Help 25 passengers.", Stat = "PassengersHelped", Goal = 25, Reward = 200 },
	{ Id = "Brave", Name = "Brave", Description = "Complete an objective inside an active hazard.", Stat = "BraveActions", Goal = 1, Reward = 75 },
	{ Id = "Firefighter", Name = "Firefighter", Description = "Extinguish 25 fires.", Stat = "FiresExtinguished", Goal = 25, Reward = 200 },
	{ Id = "Pilot", Name = "Pilot", Description = "Fly the aircraft during an emergency landing and survive.", Stat = "ManualApproaches", Goal = 1, Reward = 100 },
	{ Id = "AcePilot", Name = "Ace Pilot", Description = "Fly 5 near-perfect manual approaches.", Stat = "PerfectApproaches", Goal = 5, Reward = 350, Title = "TitleCaptain" },
	{ Id = "Butter", Name = "Butter", Description = "Be aboard for a Perfect Landing.", Stat = "PerfectLandings", Goal = 1, Reward = 75 },
	{ Id = "Taskmaster", Name = "Taskmaster", Description = "Complete 100 objectives.", Stat = "ObjectivesCompleted", Goal = 100, Reward = 300 },
	{ Id = "SlideDown", Name = "Slide Down", Description = "Evacuate an aircraft.", Stat = "Evacuations", Goal = 1, Reward = 50 },
	{ Id = "DecisionMaker", Name = "Decision Maker", Description = "Take part in 20 critical decisions.", Stat = "DecisionsMade", Goal = 20, Reward = 150 },
	{ Id = "Lucky", Name = "Lucky", Description = "Survive a rare disaster.", Reward = 150 },
	{ Id = "Untouchable", Name = "Untouchable", Description = "Survive a disaster without taking any damage.", Reward = 150 },
	{ Id = "LastOneStanding", Name = "Last One Standing", Description = "Be the only survivor of a flight with 3+ players.", Reward = 200 },
	{ Id = "DisasterMaster", Name = "Disaster Master", Description = "Survive every type of disaster.", Reward = 750, Title = "TitleLegend" },
	{ Id = "AgainstTheOdds", Name = "Against the Odds", Description = "Survive a Crash Landing.", Reward = 150 },
}

AchievementConfig.ById = {}
for _, achievement in AchievementConfig.List do
	AchievementConfig.ById[achievement.Id] = achievement
end

-- Disaster mastery levels (per disaster, by times survived).
AchievementConfig.MasteryLevels = {
	{ Name = "Novice", Goal = 1 },
	{ Name = "Trained", Goal = 3 },
	{ Name = "Expert", Goal = 7 },
	{ Name = "Master", Goal = 15 },
}

return AchievementConfig
