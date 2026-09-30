--[[
	RewardService
	Turns a finished round into outcomes, Flight Credits, statistics, achievements, challenge
	progress and the results screen. All server-side: clients never report their own rewards.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DisasterConfig = require(ReplicatedStorage.Shared.Config.DisasterConfig)
local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local Enums = require(ReplicatedStorage.Shared.Enums)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)
local Registry = require(script.Parent.Parent.Registry)

local RewardService = {}

local R = EconomyConfig.Rewards
local Tier = Enums.LandingTier

-- Floating "+credits" feedback during the round (credited for real at the end of the round).
function RewardService:Popup(player: Player, label: string, rewardKey: string?)
	local amount = if rewardKey then R[rewardKey] else nil
	Net.Event("Reward"):FireClient(player, { Label = label, Amount = amount })
end

local function outcomeKey(tier: string, survivors: number, total: number): string
	if survivors == 0 then
		return "CompleteDisaster"
	elseif tier == Tier.Crash then
		return "FailedLanding"
	elseif survivors < total then
		return "PartialSurvival"
	end
	local summary = Registry.ObjectiveService:Summary()
	if tier == Tier.Perfect and summary.CriticalCompleted >= summary.CriticalTotal then
		return "PerfectSurvival"
	elseif tier == Tier.Perfect or tier == Tier.Successful then
		return "SuccessfulLanding"
	elseif tier == Tier.Hard then
		return "HardLanding"
	end
	return "EmergencyLanding"
end

local function addLine(lines, label: string, amount: number)
	if amount > 0 then
		table.insert(lines, { Label = label, Amount = math.floor(amount) })
	end
end

function RewardService:FinalizeRound(ctx, landing)
	Registry.LandingService:ResolveUnconscious(ctx)
	local tier = if landing then landing.Tier else Tier.Crash
	local def = ctx.DisasterDef or {}
	local difficulty = def.Difficulty or 1
	local diffMult = EconomyConfig.DifficultyMultiplier[difficulty] or 1
	local modifierDef = ctx.Modifier and DisasterConfig.Modifiers[ctx.Modifier]
	local bonusMult = 1 + (modifierDef and modifierDef.RewardBonus or 0)

	-- who is counted
	local counted = {}
	local survivors = 0
	for player, record in ctx.Records do
		if not record.Left then
			table.insert(counted, record)
			local alive = record.Alive and Registry.ConditionService:GetState(player) ~= Enums.Condition.Dead
			record.Survived = alive
			if alive then
				survivors += 1
			end
		end
	end
	local total = #counted
	local key = outcomeKey(tier, survivors, total)
	local outcome = Enums.Outcome[key]
	local summary = Registry.ObjectiveService:Summary()
	local teamCritical = summary.CriticalCompleted

	local rows = {}
	local personal = {}
	local rescuedTotal = 0
	for _, record in counted do
		rescuedTotal += record.Rescues
	end

	for _, record in counted do
		local player = record.Player
		local survived = record.Survived
		local lines = {}
		addLine(lines, "Flight completed", R.Participation)
		if survived then
			addLine(lines, "Survived (" .. (def.DisplayName or "disaster") .. ")", R.Survived * diffMult)
			local landingBonus = ({ Perfect = R.PerfectLandingBonus, Successful = R.SuccessfulLandingBonus, Hard = R.HardLandingBonus, Emergency = R.EmergencyLandingBonus })[tier]
			addLine(lines, tier .. " landing", landingBonus or 0)
			local assists = math.max(0, teamCritical - record.CriticalObjectives)
			addLine(lines, "Team objectives", assists * R.ObjectiveAssist)
			if total > 1 and survivors == total then
				addLine(lines, "Everyone survived", R.TeamSurvivalBonus)
			end
		end
		addLine(lines, record.CriticalObjectives .. " critical objectives", record.CriticalObjectives * R.ObjectiveCritical * diffMult)
		addLine(lines, record.OptionalObjectives .. " optional objectives", record.OptionalObjectives * R.ObjectiveOptional)
		addLine(lines, record.Rescues .. " rescues", record.Rescues * R.Rescue)
		addLine(lines, record.Aids .. " players treated", record.Aids * R.Aid)
		addLine(lines, record.PassengersHelped .. " passengers helped", record.PassengersHelped * R.PassengerHelped)
		addLine(lines, "Bravery", record.Brave * R.BraveBonus)
		if record.Evacuated then
			addLine(lines, "Evacuated", R.Evacuated)
		end
		-- good decisions: you voted for the option that turned out well
		local goodDecisions = 0
		for _, entry in ctx.DecisionLog do
			if entry.Good == true then
				local vote = entry.Voters and entry.Voters[player]
				if vote == entry.Choice then
					goodDecisions += 1
				end
			end
		end
		addLine(lines, "Good decisions", goodDecisions * R.DecisionSuccess)

		local profile = Registry.DataService:Get(player)
		local today = Util.DayKey()
		if profile and profile.LastDailyBonus ~= today then
			profile.LastDailyBonus = today
			addLine(lines, "First flight of the day", R.FirstFlightOfDay)
		end

		local subtotal = 0
		for _, line in lines do
			subtotal += line.Amount
		end
		local multiplier = bonusMult
		if player.Parent and Registry.MonetizationService:IsVIP(player) then
			multiplier *= EconomyConfig.VIPCreditMultiplier
		end
		local totalCredits = math.min(EconomyConfig.MaxCreditsPerRound, math.floor(subtotal * multiplier))
		if multiplier ~= 1 and totalCredits ~= subtotal then
			table.insert(lines, { Label = if multiplier > 1 then "Bonus multiplier" else "Modifier", Amount = totalCredits - subtotal })
		end

		local unlocked = {}
		if player.Parent and profile then
			Registry.DataService:AddCredits(player, totalCredits, "round")
			unlocked = self:ApplyStats(ctx, player, record, tier, landing)
			task.spawn(Registry.DataService.Save, Registry.DataService, player, false)
		end

		table.insert(rows, {
			Name = record.Name,
			UserId = record.UserId,
			Survived = survived,
			Cause = record.Cause,
			Objectives = record.Objectives,
			Rescues = record.Rescues + record.Aids,
			Evacuated = record.Evacuated,
		})
		personal[player] = {
			Survived = survived,
			Cause = record.Cause,
			Credits = totalCredits,
			Lines = lines,
			Achievements = unlocked,
			Seat = record.Seat,
			VictoryEffect = if survived and profile then profile.Equipped.VictoryEffect else nil,
		}
	end
	table.sort(rows, function(a, b)
		if a.Survived ~= b.Survived then
			return a.Survived
		end
		return a.Objectives + a.Rescues > b.Objectives + b.Rescues
	end)

	local decisions = {}
	for _, entry in ctx.DecisionLog do
		table.insert(decisions, {
			Title = entry.Title,
			Choice = entry.ChoiceLabel,
			By = entry.By,
			Outcome = entry.Outcome,
			Good = entry.Good,
		})
	end

	local shared = {
		Outcome = key,
		Title = outcome.Title,
		Subtitle = outcome.Subtitle,
		Color = outcome.Color,
		Disaster = def.DisplayName or "Unknown",
		DisasterId = ctx.DisasterId,
		Rare = def.Rare == true,
		Difficulty = difficulty,
		Reveal = Registry.DisasterService:RevealDetail(ctx) or def.Summary,
		Modifier = modifierDef and modifierDef.DisplayName or nil,
		LandingTier = tier,
		LandingScore = landing and landing.Score or 0,
		LandingNotes = landing and landing.Notes or {},
		Survivors = survivors,
		Total = total,
		Rescued = rescuedTotal,
		PassengersLost = Registry.NPCService:UnhelpedCount(),
		Objectives = summary,
		Decisions = decisions,
		Players = rows,
		FlightNumber = ReplicatedStorage.GameState:GetAttribute("FlightNumber"),
		Destination = ReplicatedStorage.GameState:GetAttribute("Destination"),
	}
	print(string.format("[Round] result: %s, tier=%s score=%d, %d/%d survived", key, tier, shared.LandingScore, survivors, total))
	return { Shared = shared, Personal = personal }
end

function RewardService:ApplyStats(ctx, player: Player, record, tier: string, landing): { any }
	local data = Registry.DataService
	local profile = data:Get(player)
	if not profile then
		return {}
	end
	local survived = record.Survived
	data:IncrementStat(player, "Flights")
	if survived then
		data:IncrementStat(player, "Survived")
		profile.DisastersSurvived[ctx.DisasterId] = (profile.DisastersSurvived[ctx.DisasterId] or 0) + 1
		local streak = profile.Stats.CurrentStreak + 1
		data:SetStat(player, "CurrentStreak", streak)
		if streak > profile.Stats.BestStreak then
			data:SetStat(player, "BestStreak", streak)
		end
		if tier == Tier.Perfect then
			data:IncrementStat(player, "PerfectLandings")
		end
	else
		data:IncrementStat(player, "Deaths")
		data:SetStat(player, "CurrentStreak", 0)
	end
	local stats = {
		Rescues = record.Rescues,
		Aids = record.Aids,
		PassengersHelped = record.PassengersHelped,
		ObjectivesCompleted = record.Objectives,
		FiresExtinguished = record.FiresExtinguished,
		BraveActions = record.Brave,
		DecisionsMade = record.DecisionsCount,
	}
	for stat, amount in stats do
		if amount > 0 then
			data:IncrementStat(player, stat, amount)
		end
	end
	if record.Evacuated then
		data:IncrementStat(player, "Evacuations")
	end
	local flewApproach = landing and landing.Pilots and landing.Pilots[player]
	if flewApproach and survived then
		data:IncrementStat(player, "ManualApproaches")
		if landing.ApproachQuality and landing.ApproachQuality >= 0.85 then
			data:IncrementStat(player, "PerfectApproaches")
		end
	end

	-- event achievements
	local events = {}
	local def = ctx.DisasterDef or {}
	if survived and def.Rare then
		table.insert(events, "Lucky")
	end
	if survived and record.DamageTaken <= 0 then
		table.insert(events, "Untouchable")
	end
	if survived and tier == Tier.Crash then
		table.insert(events, "AgainstTheOdds")
	end
	local alive, total = 0, 0
	for _, other in ctx.Records do
		if not other.Left then
			total += 1
			if other.Survived then
				alive += 1
			end
		end
	end
	if survived and total >= 3 and alive == 1 then
		table.insert(events, "LastOneStanding")
	end
	local allSurvived = true
	for id in DisasterConfig.Disasters do
		if (profile.DisastersSurvived[id] or 0) == 0 then
			allSurvived = false
			break
		end
	end
	if allSurvived then
		table.insert(events, "DisasterMaster")
	end

	-- challenges
	local challenge = Registry.ChallengeService
	challenge:Progress(player, "Flights", 1)
	if survived then
		challenge:Progress(player, "Survived", 1)
		if (def.Difficulty or 1) >= 3 then
			challenge:Progress(player, "SurvivedHard", 1)
		end
		if tier == Tier.Perfect or tier == Tier.Successful then
			challenge:Progress(player, "GoodLanding", 1)
		end
		challenge:NoteDisaster(player, ctx.DisasterId)
	end
	challenge:Progress(player, "Objectives", record.Objectives)
	challenge:Progress(player, "PlayerHelp", record.Rescues + record.Aids)
	challenge:Progress(player, "PassengersHelped", record.PassengersHelped)
	challenge:Progress(player, "FiresExtinguished", record.FiresExtinguished)
	challenge:Progress(player, "Decisions", record.DecisionsCount)
	challenge:Progress(player, "Brave", record.Brave)

	local unlocked = Registry.AchievementService:Evaluate(player, events)
	data:Push(player)
	return unlocked
end

return RewardService
