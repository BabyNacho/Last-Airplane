--[[
	ObjectiveService
	Dynamic round objectives shown in every participant's HUD.

	ObjectiveService:Add({
		Id = "RestorePower", Text = "Restore emergency power", Kind = "Critical" | "Optional",
		Goal = 1, Location = part?, Hint = "Service bay, rear of the aircraft",
	})
	:Progress(id, amount, player) / :SetProgress(id, value) / :Complete(id, player) / :Fail(id)

	Objective completion credits the contributing player (round record + Brave bonus when the
	player completed it inside an active hazard).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Registry = require(script.Parent.Parent.Registry)

local ObjectiveService = {}

ObjectiveService.Completed = Signal.new() -- (objective, player?)
ObjectiveService.Failed = Signal.new() -- (objective)

local objectives: { any } = {}
local byId: { [string]: any } = {}
local dirty = false
local order = 0

local function queueSync()
	if dirty then
		return
	end
	dirty = true
	task.defer(function()
		dirty = false
		ObjectiveService:Sync()
	end)
end

function ObjectiveService:Serialize()
	local list = {}
	for _, obj in objectives do
		if not obj.Hidden then
			table.insert(list, {
				Id = obj.Id,
				Text = obj.Text,
				Kind = obj.Kind,
				Goal = obj.Goal,
				Progress = obj.Progress,
				State = obj.State,
				Location = obj.Location,
				Hint = obj.Hint,
				Order = obj.Order,
				Timer = obj.Deadline,
			})
		end
	end
	return list
end

function ObjectiveService:Sync(target: Player?)
	local payload = self:Serialize()
	if target then
		Net.Event("ObjectivesUpdated"):FireClient(target, payload)
		return
	end
	local round = Registry.RoundService:GetContext()
	local audience = if round then round:Players() else {}
	Net.FireList("ObjectivesUpdated", audience, payload)
end

function ObjectiveService:Add(def)
	assert(def.Id, "objective needs an Id")
	if byId[def.Id] then
		return byId[def.Id]
	end
	order += 1
	local obj = {
		Id = def.Id,
		Text = def.Text,
		Kind = def.Kind or Enums.ObjectiveKind.Critical,
		Goal = def.Goal or 1,
		Progress = 0,
		State = Enums.ObjectiveState.Active,
		Location = def.Location,
		Hint = def.Hint,
		Hidden = def.Hidden == true,
		Contributors = {},
		Order = order,
		Deadline = def.Deadline,
		OnComplete = def.OnComplete,
	}
	table.insert(objectives, obj)
	byId[obj.Id] = obj
	queueSync()
	if not obj.Hidden then
		Registry.EffectsService:Effect("ObjectiveAdded", { Text = obj.Text, Kind = obj.Kind })
	end
	return obj
end

function ObjectiveService:Get(id: string)
	return byId[id]
end

function ObjectiveService:IsActive(id: string): boolean
	local obj = byId[id]
	return obj ~= nil and obj.State == Enums.ObjectiveState.Active
end

function ObjectiveService:IsComplete(id: string): boolean
	local obj = byId[id]
	return obj ~= nil and obj.State == Enums.ObjectiveState.Completed
end

function ObjectiveService:SetText(id: string, text: string, hint: string?)
	local obj = byId[id]
	if obj then
		obj.Text = text
		if hint ~= nil then
			obj.Hint = hint
		end
		queueSync()
	end
end

function ObjectiveService:SetLocation(id: string, location: Instance?)
	local obj = byId[id]
	if obj then
		obj.Location = location
		queueSync()
	end
end

function ObjectiveService:SetGoal(id: string, goal: number)
	local obj = byId[id]
	if obj then
		obj.Goal = math.max(1, goal)
		queueSync()
	end
end

local function credit(obj, player: Player?)
	if not player then
		return
	end
	obj.Contributors[player] = (obj.Contributors[player] or 0) + 1
end

function ObjectiveService:Complete(id: string, player: Player?)
	local obj = byId[id]
	if not obj or obj.State ~= Enums.ObjectiveState.Active then
		return false
	end
	obj.Progress = obj.Goal
	obj.State = Enums.ObjectiveState.Completed
	credit(obj, player)
	local round = Registry.RoundService:GetContext()
	if round then
		-- every contributor gets credit; the finisher always counts
		for contributor in obj.Contributors do
			if round:IsParticipant(contributor) then
				round:Add(contributor, "Objectives")
				round:Add(contributor, if obj.Kind == Enums.ObjectiveKind.Critical then "CriticalObjectives" else "OptionalObjectives")
			end
		end
		if player and Registry.ConditionService:InHazard(player) then
			round:Add(player, "Brave")
			Registry.EffectsService:Notify("BRAVE! You completed an objective under fire.", "good", player)
		end
		round:Log("Objective completed: " .. obj.Text .. (if player then " (" .. player.DisplayName .. ")" else ""))
	end
	queueSync()
	Registry.EffectsService:Effect("ObjectiveComplete", {
		Text = obj.Text,
		Kind = obj.Kind,
		By = if player then player.DisplayName else nil,
	})
	if obj.OnComplete then
		task.spawn(obj.OnComplete, player)
	end
	ObjectiveService.Completed:Fire(obj, player)
	return true
end

function ObjectiveService:Progress(id: string, amount: number, player: Player?)
	local obj = byId[id]
	if not obj or obj.State ~= Enums.ObjectiveState.Active then
		return
	end
	credit(obj, player)
	obj.Progress = math.clamp(obj.Progress + amount, 0, obj.Goal)
	if obj.Progress >= obj.Goal then
		self:Complete(id, player)
	else
		queueSync()
	end
end

function ObjectiveService:SetProgress(id: string, value: number, player: Player?)
	local obj = byId[id]
	if not obj or obj.State ~= Enums.ObjectiveState.Active then
		return
	end
	obj.Progress = math.clamp(value, 0, obj.Goal)
	if obj.Progress >= obj.Goal then
		self:Complete(id, player)
	else
		queueSync()
	end
end

function ObjectiveService:Fail(id: string, reason: string?)
	local obj = byId[id]
	if not obj or obj.State ~= Enums.ObjectiveState.Active then
		return
	end
	obj.State = Enums.ObjectiveState.Failed
	queueSync()
	Registry.EffectsService:Effect("ObjectiveFailed", { Text = obj.Text, Reason = reason })
	ObjectiveService.Failed:Fire(obj)
end

function ObjectiveService:Remove(id: string)
	local obj = byId[id]
	if not obj then
		return
	end
	byId[id] = nil
	local index = table.find(objectives, obj)
	if index then
		table.remove(objectives, index)
	end
	queueSync()
end

function ObjectiveService:CriticalRemaining(): { any }
	local list = {}
	for _, obj in objectives do
		if obj.Kind == Enums.ObjectiveKind.Critical and obj.State == Enums.ObjectiveState.Active then
			table.insert(list, obj)
		end
	end
	return list
end

function ObjectiveService:Summary()
	local total, completed, criticalTotal, criticalDone = 0, 0, 0, 0
	for _, obj in objectives do
		if not obj.Hidden then
			total += 1
			if obj.State == Enums.ObjectiveState.Completed then
				completed += 1
			end
			if obj.Kind == Enums.ObjectiveKind.Critical then
				criticalTotal += 1
				if obj.State == Enums.ObjectiveState.Completed then
					criticalDone += 1
				end
			end
		end
	end
	return { Total = total, Completed = completed, CriticalTotal = criticalTotal, CriticalCompleted = criticalDone }
end

function ObjectiveService:Clear()
	table.clear(objectives)
	table.clear(byId)
	order = 0
	queueSync()
end

return ObjectiveService
