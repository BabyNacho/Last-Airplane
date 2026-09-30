--[[
	DecisionService
	Interactive decisions with real consequences.

	Group vote (everyone conscious aboard votes, majority wins, ties -> default):
		DecisionService:Vote(ctx, {
			Id = "EngineRestart", Title = "ATTEMPT EMERGENCY RESTART?", Prompt = "...",
			Options = { { Id = "Restart", Label = "RESTART NOW", Description = "..." , Risk = "high" }, ... },
			Duration = 15, Default = "Prepare",
			OnResolve = function(optionId, tally) ... end,
		})

	Personal decision (one player at an interaction point, e.g. an electrical panel):
		DecisionService:Personal(ctx, player, { same fields, plus Input = "Keypad" for code entry,
			OnResolve = function(optionId|code, player) end, OnCancel = function() end })

	The disaster later reports how it turned out with :SetOutcome(id, text, good) - shown on the
	results screen and used for the DecisionSuccess reward.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.Parent.RateLimiter)
local Registry = require(script.Parent.Parent.Registry)

local DecisionService = {}

type Decision = {
	Key: string,
	Id: string,
	Kind: string, -- "Vote" | "Personal"
	Def: any,
	Audience: { Player },
	Votes: { [Player]: string },
	EndsAt: number,
	Resolved: boolean,
	Ctx: any,
	Owner: Player?,
}

local open: { [string]: Decision } = {}

local function optionById(def, optionId: string)
	for _, option in def.Options or {} do
		if option.Id == optionId then
			return option
		end
	end
	return nil
end

local function tally(decision: Decision)
	local counts = {}
	for _, option in decision.Def.Options or {} do
		counts[option.Id] = 0
	end
	for _, choice in decision.Votes do
		counts[choice] = (counts[choice] or 0) + 1
	end
	return counts
end

local function publicPayload(decision: Decision)
	local options = {}
	for _, option in decision.Def.Options or {} do
		table.insert(options, {
			Id = option.Id,
			Label = option.Label,
			Description = option.Description,
			Risk = option.Risk,
		})
	end
	return {
		Key = decision.Key,
		Id = decision.Id,
		Kind = decision.Kind,
		Title = decision.Def.Title,
		Prompt = decision.Def.Prompt,
		Speaker = decision.Def.Speaker,
		Options = options,
		Input = decision.Def.Input,
		EndsAt = decision.EndsAt,
		Duration = decision.Def.Duration,
		Voters = #decision.Audience,
	}
end

local function logDecision(decision: Decision, choice: string, label: string)
	local ctx = decision.Ctx
	if not ctx or decision.Def.NoLog then
		return
	end
	table.insert(ctx.DecisionLog, {
		Id = decision.Id,
		Title = decision.Def.Title,
		Choice = choice,
		ChoiceLabel = label,
		By = if decision.Kind == "Personal" and decision.Owner then decision.Owner.DisplayName else "Group vote",
		Outcome = nil,
		Good = nil,
		Voters = (function()
			local voters = {}
			for player, vote in decision.Votes do
				voters[player] = vote
			end
			return voters
		end)(),
	})
end

local function close(decision: Decision)
	open[decision.Key] = nil
	Net.FireList("DecisionClosed", decision.Audience, { Key = decision.Key })
end

local function resolveVote(decision: Decision)
	if decision.Resolved then
		return
	end
	decision.Resolved = true
	local counts = tally(decision)
	local best, bestCount, tied = nil, -1, {}
	for _, option in decision.Def.Options do
		local count = counts[option.Id] or 0
		if count > bestCount then
			best, bestCount, tied = option.Id, count, { option.Id }
		elseif count == bestCount then
			table.insert(tied, option.Id)
		end
	end
	if bestCount <= 0 then
		best = decision.Def.Default or decision.Def.Options[1].Id
	elseif #tied > 1 then
		best = if table.find(tied, decision.Def.Default) then decision.Def.Default else tied[decision.Ctx.Rng:NextInteger(1, #tied)]
	end
	local option = optionById(decision.Def, best)
	local label = option and option.Label or best
	close(decision)
	for player in decision.Votes do
		decision.Ctx:Add(player, "DecisionsCount")
		local record = decision.Ctx:Record(player)
		if record then
			table.insert(record.Decisions, { Id = decision.Id, Choice = decision.Votes[player] })
		end
	end
	logDecision(decision, best, label)
	Registry.EffectsService:Effect("DecisionResult", {
		Title = decision.Def.Title,
		Choice = label,
		Votes = counts[best] or 0,
		Total = #decision.Audience,
	}, decision.Audience)
	decision.Ctx:Log("Decision: " .. decision.Def.Title .. " -> " .. label)
	local ok, err = pcall(decision.Def.OnResolve, best, counts)
	if not ok then
		warn("[DecisionService] OnResolve error:", err)
	end
end

function DecisionService:Vote(ctx, def)
	if not ctx or not ctx.Active then
		return nil
	end
	local audience = {}
	for _, player in ctx:AlivePlayers() do
		if Registry.ConditionService:IsConscious(player) then
			table.insert(audience, player)
		end
	end
	local decision: Decision = {
		Key = HttpService:GenerateGUID(false),
		Id = def.Id,
		Kind = "Vote",
		Def = def,
		Audience = audience,
		Votes = {},
		EndsAt = workspace:GetServerTimeNow() + (def.Duration or 15),
		Resolved = false,
		Ctx = ctx,
		Owner = nil,
	}
	open[decision.Key] = decision
	if #audience == 0 then
		resolveVote(decision)
		return decision
	end
	Registry.EffectsService:Sound("Decision")
	Net.FireList("DecisionOpened", audience, publicPayload(decision))
	ctx:Delay(def.Duration or 15, function()
		resolveVote(decision)
	end)
	return decision
end

function DecisionService:Personal(ctx, player: Player, def)
	if not ctx or not ctx.Active then
		return nil
	end
	-- only one personal decision per player at a time
	for _, existing in open do
		if existing.Kind == "Personal" and existing.Owner == player then
			return nil
		end
	end
	local decision: Decision = {
		Key = HttpService:GenerateGUID(false),
		Id = def.Id,
		Kind = "Personal",
		Def = def,
		Audience = { player },
		Votes = {},
		EndsAt = workspace:GetServerTimeNow() + (def.Duration or 20),
		Resolved = false,
		Ctx = ctx,
		Owner = player,
	}
	open[decision.Key] = decision
	Net.Event("DecisionOpened"):FireClient(player, publicPayload(decision))
	ctx:Delay(def.Duration or 20, function()
		if not decision.Resolved then
			decision.Resolved = true
			close(decision)
			if def.OnCancel then
				pcall(def.OnCancel, player)
			end
		end
	end)
	return decision
end

function DecisionService:SetOutcome(ctx, decisionId: string, text: string, good: boolean?)
	if not ctx then
		return
	end
	for i = #ctx.DecisionLog, 1, -1 do
		local entry = ctx.DecisionLog[i]
		if entry.Id == decisionId and entry.Outcome == nil then
			entry.Outcome = text
			entry.Good = good
			return
		end
	end
end

function DecisionService:IsOpen(decisionId: string): boolean
	for _, decision in open do
		if decision.Id == decisionId then
			return true
		end
	end
	return false
end

local function onVote(player: Player, key: any, choice: any)
	if type(key) ~= "string" or (type(choice) ~= "string" and type(choice) ~= "number") then
		return
	end
	if not RateLimiter.Allow(player, "DecisionVote") then
		return
	end
	local decision = open[key]
	if not decision or decision.Resolved or not table.find(decision.Audience, player) then
		return
	end
	if not Registry.ConditionService:IsConscious(player) then
		return
	end
	if decision.Kind == "Personal" then
		local def = decision.Def
		local value: string
		if def.Input == "Keypad" then
			value = string.sub(tostring(choice), 1, 8)
			if not string.match(value, "^%d+$") then
				return
			end
		else
			if type(choice) ~= "string" or not optionById(def, choice) then
				return
			end
			value = choice
		end
		decision.Resolved = true
		decision.Votes[player] = value
		close(decision)
		local option = optionById(def, value)
		if def.Input ~= "Keypad" then
			decision.Ctx:Add(player, "DecisionsCount")
			table.insert(decision.Ctx:Record(player).Decisions, { Id = def.Id, Choice = value })
			logDecision(decision, value, option and option.Label or value)
		end
		local ok, err = pcall(def.OnResolve, value, player)
		if not ok then
			warn("[DecisionService] personal OnResolve error:", err)
		end
		return
	end
	if type(choice) ~= "string" or not optionById(decision.Def, choice) then
		return
	end
	decision.Votes[player] = choice
	local counts = tally(decision)
	Net.FireList("DecisionUpdated", decision.Audience, { Key = decision.Key, Counts = counts, Voted = decision.Votes[player] and #decision.Audience or 0 })
	-- everyone still able to vote has voted -> resolve early
	local allVoted = true
	for _, member in decision.Audience do
		if member.Parent and Registry.ConditionService:IsConscious(member) and not decision.Votes[member] then
			allVoted = false
			break
		end
	end
	if allVoted then
		task.delay(0.8, resolveVote, decision)
	end
end

function DecisionService:OnRoundEnd()
	for _, decision in open do
		decision.Resolved = true
		Net.FireList("DecisionClosed", decision.Audience, { Key = decision.Key })
	end
	table.clear(open)
end

function DecisionService:Start()
	Net.Event("DecisionVote").OnServerEvent:Connect(onVote)
end

return DecisionService
