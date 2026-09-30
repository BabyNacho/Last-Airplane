--[[
	ChallengeService
	Daily (3) and weekly (1) challenges, rotated deterministically from the UTC date so every server
	agrees. Progress persists in the profile; completion pays credits automatically.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChallengeConfig = require(ReplicatedStorage.Shared.Config.ChallengeConfig)
local Util = require(ReplicatedStorage.Shared.Util)
local Registry = require(script.Parent.Parent.Registry)

local ChallengeService = {}

local function pick(list, count: number, seed: number)
	local rng = Random.new(seed)
	local shuffled = Util.Shuffle(rng, list)
	local result = {}
	for i = 1, math.min(count, #shuffled) do
		table.insert(result, shuffled[i])
	end
	return result
end

function ChallengeService:Today()
	return pick(ChallengeConfig.Daily, ChallengeConfig.DailyCount, Util.DayKey() * 31 + 7)
end

function ChallengeService:ThisWeek()
	return pick(ChallengeConfig.Weekly, 1, Util.WeekKey() * 17 + 3)
end

-- Resets stored progress when the day / week rolls over.
local function rollover(profile)
	local c = profile.Challenges
	local day, week = Util.DayKey(), Util.WeekKey()
	if c.Day ~= day then
		c.Day = day
		c.Daily = {}
		c.DailyClaimed = {}
	end
	if c.Week ~= week then
		c.Week = week
		c.Weekly = {}
		c.WeeklyClaimed = {}
		c.WeekDisasters = {}
	end
	return c
end

local function advance(player: Player, list, progress, claimed, key: string, amount: number, label: string)
	for _, challenge in list do
		if challenge.Key == key and not claimed[challenge.Id] then
			local value = math.min(challenge.Goal, (progress[challenge.Id] or 0) + amount)
			progress[challenge.Id] = value
			if value >= challenge.Goal then
				claimed[challenge.Id] = true
				Registry.DataService:AddCredits(player, challenge.Reward, "challenge")
				Registry.EffectsService:Notify(label .. " complete: " .. challenge.Text .. " (+" .. challenge.Reward .. " FC)", "good", player)
			end
		end
	end
end

function ChallengeService:Progress(player: Player, key: string, amount: number)
	if amount <= 0 then
		return
	end
	local profile = Registry.DataService:Get(player)
	if not profile then
		return
	end
	local c = rollover(profile)
	advance(player, self:Today(), c.Daily, c.DailyClaimed, key, amount, "Daily challenge")
	advance(player, self:ThisWeek(), c.Weekly, c.WeeklyClaimed, key, amount, "Weekly challenge")
	Registry.DataService:MarkDirty(player)
end

function ChallengeService:NoteDisaster(player: Player, disasterId: string)
	local profile = Registry.DataService:Get(player)
	if not profile then
		return
	end
	local c = rollover(profile)
	if not c.WeekDisasters[disasterId] then
		c.WeekDisasters[disasterId] = true
		self:Progress(player, "UniqueDisasters", 1)
	end
end

-- Client-facing view of today's challenges.
function ChallengeService:View(player: Player)
	local profile = Registry.DataService:Get(player)
	if not profile then
		return nil
	end
	local c = rollover(profile)
	local function describe(list, progress, claimed)
		local out = {}
		for _, challenge in list do
			table.insert(out, {
				Id = challenge.Id,
				Text = challenge.Text,
				Goal = challenge.Goal,
				Progress = progress[challenge.Id] or 0,
				Reward = challenge.Reward,
				Done = claimed[challenge.Id] == true,
			})
		end
		return out
	end
	local now = os.time()
	return {
		Daily = describe(self:Today(), c.Daily, c.DailyClaimed),
		Weekly = describe(self:ThisWeek(), c.Weekly, c.WeeklyClaimed),
		DailyResetIn = 86400 - (now % 86400),
	}
end

return ChallengeService
