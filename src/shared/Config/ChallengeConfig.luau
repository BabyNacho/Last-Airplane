--[[
	ChallengeConfig
	Rotating daily and weekly challenges. The rotation is deterministic from the UTC date,
	so every server shows the same challenges on the same day.
	Keys match the round-summary counters produced by RewardService.
]]

local ChallengeConfig = {}

ChallengeConfig.DailyCount = 3

ChallengeConfig.Daily = {
	{ Id = "d_survive2", Text = "Survive 2 flights", Key = "Survived", Goal = 2, Reward = 90 },
	{ Id = "d_objectives5", Text = "Complete 5 objectives", Key = "Objectives", Goal = 5, Reward = 90 },
	{ Id = "d_help2", Text = "Revive or treat 2 players", Key = "PlayerHelp", Goal = 2, Reward = 110 },
	{ Id = "d_passengers3", Text = "Help 3 passengers", Key = "PassengersHelped", Goal = 3, Reward = 80 },
	{ Id = "d_fires4", Text = "Extinguish 4 fires", Key = "FiresExtinguished", Goal = 4, Reward = 100 },
	{ Id = "d_decisions3", Text = "Vote in 3 decisions", Key = "Decisions", Goal = 3, Reward = 70 },
	{ Id = "d_hard1", Text = "Survive a difficulty 3 disaster", Key = "SurvivedHard", Goal = 1, Reward = 120 },
	{ Id = "d_flights3", Text = "Board 3 flights", Key = "Flights", Goal = 3, Reward = 60 },
	{ Id = "d_brave1", Text = "Complete an objective inside a hazard", Key = "Brave", Goal = 1, Reward = 100 },
	{ Id = "d_goodlanding", Text = "Survive a Successful or Perfect landing", Key = "GoodLanding", Goal = 1, Reward = 90 },
}

ChallengeConfig.Weekly = {
	{ Id = "w_survive15", Text = "Survive 15 flights this week", Key = "Survived", Goal = 15, Reward = 500 },
	{ Id = "w_objectives40", Text = "Complete 40 objectives this week", Key = "Objectives", Goal = 40, Reward = 500 },
	{ Id = "w_help12", Text = "Revive or treat 12 players this week", Key = "PlayerHelp", Goal = 12, Reward = 550 },
	{ Id = "w_variety5", Text = "Survive 5 different disasters this week", Key = "UniqueDisasters", Goal = 5, Reward = 600 },
}

return ChallengeConfig
