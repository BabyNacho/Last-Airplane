--[[
	AchievementService
	Awards achievements from stat thresholds (checked whenever stats change) and round events.
	Achievements pay a one-time credit reward and can unlock exclusive titles.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AchievementConfig = require(ReplicatedStorage.Shared.Config.AchievementConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Registry = require(script.Parent.Parent.Registry)

local AchievementService = {}

local function award(player: Player, achievement): boolean
	local profile = Registry.DataService:Get(player)
	if not profile or profile.Achievements[achievement.Id] then
		return false
	end
	profile.Achievements[achievement.Id] = os.time()
	Registry.DataService:MarkDirty(player)
	if achievement.Reward and achievement.Reward > 0 then
		Registry.DataService:AddCredits(player, achievement.Reward, "achievement")
	end
	if achievement.Title then
		Registry.DataService:Grant(player, achievement.Title)
	end
	Net.Event("AchievementUnlocked"):FireClient(player, {
		Id = achievement.Id,
		Name = achievement.Name,
		Description = achievement.Description,
		Reward = achievement.Reward,
		Title = achievement.Title,
	})
	return true
end

-- Checks stat achievements plus the given event ids. Returns newly unlocked achievements.
function AchievementService:Evaluate(player: Player, events: { string }?): { any }
	local profile = Registry.DataService:Get(player)
	if not profile then
		return {}
	end
	local unlocked = {}
	for _, achievement in AchievementConfig.List do
		if not profile.Achievements[achievement.Id] then
			local earned = false
			if achievement.Stat then
				earned = (profile.Stats[achievement.Stat] or 0) >= achievement.Goal
			elseif events and table.find(events, achievement.Id) then
				earned = true
			end
			if earned and award(player, achievement) then
				table.insert(unlocked, { Id = achievement.Id, Name = achievement.Name, Reward = achievement.Reward })
			end
		end
	end
	return unlocked
end

function AchievementService:Start()
	-- repair: grant titles for achievements earned before a title was attached to them
	Registry.DataService.ProfileLoaded:Connect(function(player, profile)
		for id in profile.Achievements do
			local achievement = AchievementConfig.ById[id]
			if achievement and achievement.Title and not profile.Owned[achievement.Title] then
				profile.Owned[achievement.Title] = true
			end
		end
		self:Evaluate(player, nil)
	end)
end

return AchievementService
