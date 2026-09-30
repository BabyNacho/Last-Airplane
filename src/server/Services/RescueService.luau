--[[
	RescueService
	Co-op rescue: revive unconscious players ([E] HELP PLAYER) and treat injured players
	([E] TREAT INJURIES). First aid kits make treatment much stronger. Rescuers are credited
	in their round record (rewards, stats, achievements).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Util = require(ReplicatedStorage.Shared.Util)
local Registry = require(script.Parent.Parent.Registry)

local RescueService = {}

local CFG = GameConfig.Condition

local revivePrompts: { [Player]: any } = {}
local soloRecovered: { [Player]: boolean } = {}
local aidPrompts: { [Player]: any } = {}
local lastAid: { [Player]: number } = {}

local function clear(map: { [Player]: any }, player: Player)
	local handle = map[player]
	if handle then
		handle:Destroy()
		map[player] = nil
	end
end

local function addRevive(ctx, target: Player)
	clear(revivePrompts, target)
	clear(aidPrompts, target)
	local root = Util.GetRoot(target)
	if not root then
		return
	end
	revivePrompts[target] = Registry.InteractionService:Add(root, {
		Action = "HELP PLAYER",
		Object = target.DisplayName .. " (unconscious)",
		Hold = CFG.ReviveHoldTime,
		Range = 8,
		Kind = "rescue",
		HideFor = target.UserId,
		Round = ctx,
		Condition = function(helper)
			if helper == target then
				return false
			end
			return Registry.ConditionService:GetState(target) == Enums.Condition.Unconscious
		end,
		OnTrigger = function(helper)
			local kit = Registry.EquipmentService:HasTool(helper, "FirstAidKit")
			local health = CFG.ReviveHealth + (if kit then 20 else 0)
			if Registry.ConditionService:Revive(target, health) then
				if kit then
					local uses = (kit:GetAttribute("Uses") or 1) - 1
					kit:SetAttribute("Uses", uses)
					if uses <= 0 then
						kit:Destroy()
					end
				end
				ctx:Add(helper, "Rescues")
				ctx:Log(helper.DisplayName .. " revived " .. target.DisplayName)
				Registry.EffectsService:Notify(helper.DisplayName .. " revived " .. target.DisplayName .. "!", "good")
				Registry.EffectsService:Sound("Revive", root.Position)
				Registry.EffectsService:Effect("Revived", { By = helper.DisplayName }, target)
				Registry.RewardService:Popup(helper, "RESCUE", "Rescue")
				clear(revivePrompts, target)
			end
		end,
	})
end

local function addAid(ctx, target: Player)
	if aidPrompts[target] then
		return
	end
	local root = Util.GetRoot(target)
	if not root then
		return
	end
	aidPrompts[target] = Registry.InteractionService:Add(root, {
		Action = "TREAT INJURIES",
		Object = target.DisplayName,
		Hold = CFG.AidHoldTime,
		Range = 7,
		Kind = "rescue",
		HideFor = target.UserId,
		Round = ctx,
		Condition = function(helper)
			if helper == target then
				return false
			end
			local state = Registry.ConditionService:GetState(target)
			if state ~= Enums.Condition.Injured and state ~= Enums.Condition.Critical then
				return false
			end
			if os.clock() - (lastAid[target] or 0) < CFG.AidCooldownPerTarget then
				return false, target.DisplayName .. " was just treated. Give it a moment."
			end
			return true
		end,
		OnTrigger = function(helper)
			local kit = Registry.EquipmentService:HasTool(helper, "FirstAidKit")
			local amount = if kit then CFG.AidHealWithKit else CFG.AidHeal
			if kit then
				local uses = (kit:GetAttribute("Uses") or 1) - 1
				kit:SetAttribute("Uses", uses)
				if uses <= 0 then
					kit:Destroy()
				end
			end
			lastAid[target] = os.clock()
			Registry.ConditionService:Heal(target, amount)
			ctx:Add(helper, "Aids")
			Registry.EffectsService:Notify(helper.DisplayName .. " treated your injuries (+" .. amount .. ")", "good", target)
			Registry.EffectsService:Notify("You treated " .. target.DisplayName, "good", helper)
			Registry.RewardService:Popup(helper, "FIRST AID", "Aid")
		end,
	})
end

-- If no conscious teammate is aboard, a downed player pulls themselves up once per round,
-- so solo players (or the last player standing) aren't doomed by a single knockdown.
local function scheduleSoloRecovery(ctx, target: Player)
	if soloRecovered[target] then
		return
	end
	ctx:Delay(CFG.SoloRecoveryDelay, function()
		if Registry.ConditionService:GetState(target) ~= Enums.Condition.Unconscious or soloRecovered[target] then
			return
		end
		for _, other in ctx:AlivePlayers() do
			if other ~= target and Registry.ConditionService:IsConscious(other) then
				return -- someone can still help
			end
		end
		soloRecovered[target] = true
		if Registry.ConditionService:Revive(target, CFG.SoloRecoveryHealth) then
			clear(revivePrompts, target)
			Registry.EffectsService:Notify("Nobody's coming... you drag yourself back up. (once per flight)", "warn", target)
		end
	end)
end

function RescueService:OnRoundStart(ctx)
	table.clear(lastAid)
	table.clear(soloRecovered)
	ctx:Give(Registry.ConditionService.StateChanged:Connect(function(player, newState)
		if not ctx.Active or not ctx:IsParticipant(player) then
			return
		end
		if newState == Enums.Condition.Unconscious then
			addRevive(ctx, player)
			scheduleSoloRecovery(ctx, player)
		elseif newState == Enums.Condition.Injured or newState == Enums.Condition.Critical then
			clear(revivePrompts, player)
			addAid(ctx, player)
		else
			clear(revivePrompts, player)
			clear(aidPrompts, player)
		end
	end))
end

function RescueService:OnRoundEnd()
	for player in revivePrompts do
		clear(revivePrompts, player)
	end
	for player in aidPrompts do
		clear(aidPrompts, player)
	end
end

function RescueService:Start()
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		clear(revivePrompts, player)
		clear(aidPrompts, player)
		lastAid[player] = nil
		soloRecovered[player] = nil
	end)
end

return RescueService
