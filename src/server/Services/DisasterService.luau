--[[
	DisasterService
	Selects the hidden disaster for each round and drives its hooks through the round phases.
	Every hook runs inside pcall: if a disaster module errors, the round keeps going with a safe
	fallback so players still get a landing and results.

	Adding a disaster: drop a module into Server/Disasters (built with DisasterBase.extend) and add
	a matching entry in DisasterConfig.Disasters. It is picked up automatically.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DisasterConfig = require(ReplicatedStorage.Shared.Config.DisasterConfig)
local Enums = require(ReplicatedStorage.Shared.Enums)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Util = require(ReplicatedStorage.Shared.Util)
local Registry = require(script.Parent.Parent.Registry)

local DisasterService = {}

local modules: { [string]: any } = {}
local history: { string } = {}

function DisasterService:Init()
	local folder = script.Parent.Parent.Disasters
	for id in DisasterConfig.Disasters do
		local module = folder:FindFirstChild(id)
		if module and module:IsA("ModuleScript") then
			local ok, result = pcall(require, module)
			if ok then
				modules[id] = result
			else
				warn("[DisasterService] failed to load disaster", id, result)
			end
		else
			warn("[DisasterService] no module for configured disaster", id)
		end
	end
end

function DisasterService:Available(): { string }
	local list = {}
	for id in modules do
		table.insert(list, id)
	end
	table.sort(list)
	return list
end

function DisasterService:Choose(ctx): (string, any)
	local forced = GameConfig.StudioForceDisaster
	if RunService:IsStudio() and forced and modules[forced] then
		return forced, DisasterConfig.Disasters[forced]
	end
	local weights = {}
	for id in modules do
		local def = DisasterConfig.Disasters[id]
		local weight = def.Weight
		local recent = table.find(history, id)
		if recent then
			weight = 0
		end
		weights[id] = weight
	end
	local chosen = Util.WeightedPick(ctx.Rng, weights)
	if not chosen then
		chosen = Util.Pick(ctx.Rng, self:Available())
	end
	table.insert(history, 1, chosen)
	while #history > DisasterConfig.AvoidRepeatCount do
		table.remove(history)
	end
	return chosen, DisasterConfig.Disasters[chosen]
end

-- Safely calls a hook on the round's disaster. Returns the hook's result (or nil on error).
function DisasterService:Invoke(ctx, hook: string, ...)
	local disaster = ctx.Disaster
	if not disaster or ctx.DisasterFaulted and hook ~= "Cleanup" then
		return nil
	end
	local fn = disaster[hook]
	if type(fn) ~= "function" then
		return nil
	end
	local ok, result = pcall(fn, disaster, ...)
	if not ok then
		warn(string.format("[DisasterService] %s:%s errored: %s", tostring(ctx.DisasterId), hook, tostring(result)))
		if hook ~= "Cleanup" and hook ~= "RevealDetail" and hook ~= "NeedsEvacuation" then
			self:Fallback(ctx)
		end
		return nil
	end
	return result
end

-- Keeps the round playable when a disaster module fails.
function DisasterService:Fallback(ctx)
	if ctx.DisasterFaulted then
		return
	end
	ctx.DisasterFaulted = true
	Registry.EffectsService:Warning("SYSTEMS FAULT", "The crew needs help preparing for an emergency landing", "warn")
	Registry.ObjectiveService:Add({
		Id = "FallbackPrepare",
		Text = "Help the crew prepare the cabin",
		Kind = Enums.ObjectiveKind.Optional,
		Goal = 1,
	})
	Registry.ObjectiveService:Complete("FallbackPrepare")
end

function DisasterService:OnRoundStart(ctx)
	local module = modules[ctx.DisasterId]
	if not module then
		return
	end
	local ok, instance = pcall(module.new, ctx)
	if not ok then
		warn("[DisasterService] failed to create disaster:", instance)
		ctx.DisasterFaulted = true
		return
	end
	ctx.Disaster = instance
	self:Invoke(ctx, "Setup")
end

function DisasterService:OnPhase(ctx, phase: string)
	if phase == Enums.Phase.Disaster then
		self:Invoke(ctx, "Start")
	elseif phase == Enums.Phase.Crisis then
		self:Invoke(ctx, "Crisis")
	elseif phase == Enums.Phase.FinalEvent then
		self:Invoke(ctx, "Final")
	end
end

function DisasterService:LandingModifier(ctx): (number, { any })
	local disaster = ctx.Disaster
	if not disaster then
		return 0, {}
	end
	return disaster.LandingDelta or 0, disaster.LandingNotes or {}
end

function DisasterService:NeedsEvacuation(ctx): boolean
	return self:Invoke(ctx, "NeedsEvacuation") == true
end

function DisasterService:RevealDetail(ctx): string?
	return self:Invoke(ctx, "RevealDetail")
end

function DisasterService:OnRoundEnd(ctx)
	if ctx.Disaster then
		local disaster = ctx.Disaster
		local ok, err = pcall(disaster.Cleanup, disaster)
		if not ok then
			warn("[DisasterService] cleanup error:", err)
		end
	end
end

return DisasterService
