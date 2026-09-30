--[[
	OxygenSystem
	Cabin oxygen emergencies. While active and above the safe altitude:
	  * Players breathe from a deployed mask (buckled in a seat, or standing at a mask panel
	    after putting it on) or from a portable oxygen bottle.
	  * Without oxygen their O2 meter drains, then hypoxia slowly damages them and slows them
	    down until they pass out - never instantly.
	The emergency ends when the aircraft descends below SafeAltitude or it is ended explicitly.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Registry = require(script.Parent.Parent.Registry)

local OxygenSystem = {}

local CFG = GameConfig.Oxygen
OxygenSystem.SafeAltitude = 14000

local ctxRef: any = nil
local activeEmergency = false
local maskUsers: { [Player]: BasePart } = {}
local bottleUsers: { [Player]: Tool } = {}
local maskHandles: { any } = {}
local maskSupply = math.huge
local drainScale = 1

function OxygenSystem:IsActive(): boolean
	return activeEmergency
end

function OxygenSystem:MaskSupply(): number
	return maskSupply
end

function OxygenSystem:IsBreathing(player: Player): (boolean, string?)
	if bottleUsers[player] then
		return true, "Bottle"
	end
	if maskSupply <= 0 then
		return false, nil
	end
	if Registry.MapService:IsSeated(player) then
		return true, "Seat"
	end
	local mask = maskUsers[player]
	if mask and Registry.MapService:DistanceTo(player, mask) <= CFG.MaskRange then
		return true, "Mask"
	end
	maskUsers[player] = nil
	return false, nil
end

function OxygenSystem:ToggleBottle(player: Player, tool: Tool)
	if not ctxRef or not Registry.ConditionService:IsConscious(player) then
		return
	end
	if bottleUsers[player] then
		bottleUsers[player] = nil
		Registry.EffectsService:Notify("Oxygen bottle closed.", "info", player)
	elseif (tool:GetAttribute("Supply") or 0) > 0 then
		bottleUsers[player] = tool
		Registry.EffectsService:Notify("Breathing from portable oxygen.", "good", player)
	else
		Registry.EffectsService:Notify("This bottle is empty.", "warn", player)
	end
end

local function registerMasks(ctx)
	for _, mask in Registry.MapService.Points.MaskGroups do
		local handle = Registry.InteractionService:Add(mask, {
			Action = "PUT ON",
			Object = "OXYGEN MASK",
			Hold = 0.6,
			Range = CFG.MaskRange,
			Kind = "objective",
			Round = ctx,
			Condition = function()
				if not activeEmergency then
					return false
				end
				if maskSupply <= 0 then
					return false, "The mask supply is exhausted - find a portable oxygen bottle!"
				end
				return true
			end,
			OnTrigger = function(player)
				maskUsers[player] = mask
				Registry.EffectsService:Notify("Mask on. Stay close to breathe.", "good", player)
				if Registry.ObjectiveService:IsActive("UseMasks") then
					OxygenSystem:RefreshMaskObjective(ctx)
				end
			end,
		})
		table.insert(maskHandles, handle)
	end
end

function OxygenSystem:RefreshMaskObjective(ctx)
	if not Registry.ObjectiveService:IsActive("UseMasks") then
		return
	end
	local alive = ctx:AlivePlayers()
	local breathing = 0
	for _, player in alive do
		if self:IsBreathing(player) then
			breathing += 1
		end
	end
	Registry.ObjectiveService:SetGoal("UseMasks", math.max(1, #alive))
	Registry.ObjectiveService:SetProgress("UseMasks", breathing)
end

-- Starts an oxygen emergency. options.Supply = seconds of mask oxygen (default unlimited),
-- options.DrainScale multiplies how fast unmasked players run out.
function OxygenSystem:Begin(ctx, options: { Supply: number?, DrainScale: number? }?)
	ctxRef = ctx
	activeEmergency = true
	maskSupply = options and options.Supply or math.huge
	drainScale = options and options.DrainScale or 1
	Registry.MapService:DeployMasks(true)
	Registry.FlightService:Set("OxygenEmergency", true)
	if #maskHandles == 0 then
		registerMasks(ctx)
	end
end

function OxygenSystem:SetSupply(seconds: number)
	maskSupply = seconds
end

function OxygenSystem:End()
	if not activeEmergency then
		return
	end
	activeEmergency = false
	Registry.FlightService:Set("OxygenEmergency", false)
	if ctxRef then
		for _, player in ctxRef:Players() do
			Registry.ConditionService:SetOnOxygen(player, false)
		end
	end
	table.clear(maskUsers)
	table.clear(bottleUsers)
end

local function step(dt: number)
	local ctx = ctxRef
	if not ctx or not ctx.Active then
		return
	end
	-- bottles drain whenever open
	for player, tool in bottleUsers do
		local supply = (tool:GetAttribute("Supply") or 0) - dt
		tool:SetAttribute("Supply", math.max(0, supply))
		if supply <= 0 or not tool.Parent then
			bottleUsers[player] = nil
			Registry.EffectsService:Notify("Portable oxygen is empty!", "warn", player)
		end
	end
	if not activeEmergency then
		return
	end
	if maskSupply ~= math.huge then
		local before = maskSupply
		maskSupply = math.max(0, maskSupply - dt)
		if before > 20 and maskSupply <= 20 then
			Registry.EffectsService:Warning("MASK OXYGEN LOW", "Chemical generators are nearly spent", "danger")
		elseif before > 0 and maskSupply <= 0 then
			Registry.EffectsService:Warning("MASK OXYGEN DEPLETED", "Get lower - or find portable oxygen!", "danger")
		end
	end
	local altitude = Registry.FlightService:Get("Altitude")
	local safe = altitude < OxygenSystem.SafeAltitude
	for _, player in ctx:AlivePlayers() do
		if not Registry.ConditionService:Get(player) then
			continue
		end
		local breathing, source = OxygenSystem:IsBreathing(player)
		if safe then
			breathing, source = true, "Cabin"
		end
		Registry.ConditionService:SetOnOxygen(player, breathing, source)
		if breathing then
			Registry.ConditionService:ChangeOxygen(player, CFG.RefillPerSecond * dt)
		else
			Registry.ConditionService:ChangeOxygen(player, -CFG.DrainPerSecond * drainScale * dt)
			if Registry.ConditionService:GetOxygen(player) <= 0 then
				Registry.ConditionService:Damage(player, CFG.HypoxiaDamagePerSecond * dt, "Passed out from hypoxia", false)
			end
		end
	end
	OxygenSystem:RefreshMaskObjective(ctx)
end

function OxygenSystem:OnRoundStart(ctx)
	ctxRef = ctx
	activeEmergency = false
	maskSupply = math.huge
	table.clear(maskUsers)
	table.clear(bottleUsers)
	table.clear(maskHandles)
	ctx:Every(0.5, function()
		step(0.5)
		return true
	end)
end

function OxygenSystem:OnRoundEnd()
	self:End()
	table.clear(maskHandles)
	ctxRef = nil
end

function OxygenSystem:Start()
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		maskUsers[player] = nil
		bottleUsers[player] = nil
	end)
end

return OxygenSystem
