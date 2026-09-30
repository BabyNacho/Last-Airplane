--[[
	TurbulenceSystem
	Staged turbulence (0 = calm, 1 = light, 2 = moderate, 3 = severe).
	Each jolt shakes every camera; unsecured players (not buckled in) may stumble and take damage,
	buckled players are protected. Stronger stages pop overhead bins (falling luggage) and
	break galley carts loose.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Util = require(ReplicatedStorage.Shared.Util)
local Registry = require(script.Parent.Parent.Registry)

local TurbulenceSystem = {}

TurbulenceSystem.Jolted = Signal.new() -- (stage)

local CFG = GameConfig.Turbulence

local ctxRef: any = nil
local stage = 0
local loopThread: thread? = nil
local options = { Bins = true, Carts = true, DamageScale = 1 }
local luggageHits: { [Player]: number } = {}

function TurbulenceSystem:GetStage(): number
	return stage
end

local function jolt(ctx)
	local def = CFG.Stages[stage]
	if not def then
		return
	end
	Registry.FlightService:Set("Turbulence", stage)
	Registry.EffectsService:Shake(0.35 + stage * 0.45, 0.6 + stage * 0.35)
	if stage >= 2 then
		Registry.EffectsService:Sound("Creak")
	end
	for _, player in ctx:AlivePlayers() do
		if Registry.ConditionService:IsConscious(player) and not Registry.MapService:IsSeated(player) then
			if stage >= 2 then
				-- moving around unbuckled in rough air counts as acting inside a hazard (Brave)
				Registry.ConditionService:MarkHazard(player, def.Interval[2] + 1)
			end
			if ctx.Rng:NextNumber() < def.Stumble then
				local direction = Vector3.new(ctx.Rng:NextNumber(-1, 1), 0, ctx.Rng:NextNumber(-1, 1))
				Net.Event("Stumble"):FireClient(player, { Strength = stage, Direction = direction })
				local damage = def.Damage * ctx.Rng:NextNumber(0.6, 1.25) * options.DamageScale
				if damage > 0 then
					Registry.ConditionService:Damage(player, damage, "Thrown around by turbulence", false)
				end
			end
		end
	end
	if options.Bins and stage >= 2 then
		local bins = Registry.MapService.Points.Bins
		for _ = 1, stage - 1 do
			local lid = Util.Pick(ctx.Rng, bins)
			if lid and not lid:GetAttribute("Open") and ctx.Rng:NextNumber() < 0.55 then
				Registry.CabinService:OpenBin(ctx, lid, true)
			end
		end
	end
	if options.Carts and stage >= 3 then
		for _, cart in Registry.MapService.Points.Carts do
			if cart:GetAttribute("Secured") and ctx.Rng:NextNumber() < 0.5 then
				Registry.CabinService:ReleaseCart(ctx, cart)
			end
		end
	end
	TurbulenceSystem.Jolted:Fire(stage)
end

function TurbulenceSystem:SetStage(ctx, newStage: number, opts: { Bins: boolean?, Carts: boolean?, DamageScale: number? }?)
	ctxRef = ctx
	stage = math.clamp(newStage, 0, #CFG.Stages)
	if opts then
		for key, value in opts do
			(options :: any)[key] = value
		end
	end
	Registry.FlightService:Set("Turbulence", stage)
	if loopThread then
		pcall(task.cancel, loopThread)
		loopThread = nil
	end
	if stage == 0 then
		return
	end
	loopThread = ctx:Spawn(function()
		while ctx.Active and stage > 0 do
			local def = CFG.Stages[stage]
			task.wait(Util.RandomRange(ctx.Rng, def.Interval))
			if ctx.Active and stage > 0 then
				jolt(ctx)
			end
		end
	end)
end

-- Single big jolt (impacts, strikes) regardless of stage.
function TurbulenceSystem:Impact(ctx, strength: number, damage: number?)
	Registry.EffectsService:Shake(strength, 1.2)
	for _, player in ctx:AlivePlayers() do
		if Registry.ConditionService:IsConscious(player) and not Registry.MapService:IsSeated(player) then
			Net.Event("Stumble"):FireClient(player, { Strength = 3, Direction = Vector3.new(ctx.Rng:NextNumber(-1, 1), 0, ctx.Rng:NextNumber(-1, 1)) })
			if damage and damage > 0 then
				Registry.ConditionService:Damage(player, damage * ctx.Rng:NextNumber(0.7, 1.2), "Thrown by the impact", false)
			end
		end
	end
end

function TurbulenceSystem:OnRoundStart(ctx)
	ctxRef = ctx
	stage = 0
	options = { Bins = true, Carts = true, DamageScale = 1 }
	table.clear(luggageHits)
	-- falling luggage hurts
	local folder = Registry.MapService.Airplane:FindFirstChild("LooseObjects")
	if folder then
		ctx:Give(folder.ChildAdded:Connect(function(bag)
			if not bag:IsA("BasePart") then
				return
			end
			bag.Touched:Connect(function(hit)
				if bag.AssemblyLinearVelocity.Magnitude < 9 then
					return
				end
				local character = hit:FindFirstAncestorOfClass("Model")
				local player = character and Players:GetPlayerFromCharacter(character)
				if player and ctx:IsParticipant(player) and os.clock() - (luggageHits[player] or 0) > 1.2 then
					luggageHits[player] = os.clock()
					if not Registry.MapService:IsSeated(player) then
						Registry.ConditionService:Damage(player, 7, "Hit by falling luggage")
					else
						Registry.ConditionService:Damage(player, 2, "Hit by falling luggage")
					end
				end
			end)
		end))
	end
	if ctx.Modifier == "RoughAir" then
		ctx:Every({ 25, 45 }, function()
			if stage == 0 and ctx.Phase ~= "Boarding" then
				Registry.EffectsService:Shake(0.5, 0.8)
				Registry.FlightService:Set("Turbulence", 1)
				task.delay(2, function()
					if stage == 0 then
						Registry.FlightService:Set("Turbulence", 0)
					end
				end)
			end
			return true
		end)
	end
end

function TurbulenceSystem:OnRoundEnd()
	stage = 0
	if loopThread then
		pcall(task.cancel, loopThread)
		loopThread = nil
	end
	ctxRef = nil
end

return TurbulenceSystem
