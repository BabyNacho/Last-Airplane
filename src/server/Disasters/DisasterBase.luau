--[[
	DisasterBase
	Shared toolkit for disaster modules. A disaster subclasses this and overrides any of:

		:Setup()        boarding - pick hidden variants, prepare the map (nothing visible yet)
		:Clues()        second half of the calm flight - subtle hints only
		:Start()        DISASTER phase - the main event and first objectives
		:Crisis()       CRISIS phase - escalation, decisions, secondary events
		:Final()        FINAL EVENT phase - disaster-specific landing complications
		:OnTouchdown(tier)  after the landing resolves
		:NeedsEvacuation() -> boolean
		:RevealDetail() -> string  shown on the results screen ("THE CAUSE: ...")
		:Cleanup()

	Landing influence goes through self:AdjustLanding(delta, note); LandingService sums it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local Registry = require(script.Parent.Parent.Registry)

local DisasterBase = {}
DisasterBase.__index = DisasterBase

function DisasterBase.extend(id: string)
	local class = setmetatable({}, { __index = DisasterBase })
	class.__index = class
	class.Id = id
	function class.new(ctx)
		local self = setmetatable({}, class)
		self.Ctx = ctx
		self.Rng = ctx.Rng
		self.S = Registry
		self.LandingDelta = 0
		self.LandingNotes = {}
		self.Evacuate = false
		self.Detail = nil
		return self
	end
	return class
end

---------------------------------------------------------------- default hooks

function DisasterBase:Setup() end
function DisasterBase:Clues() end
function DisasterBase:Start() end
function DisasterBase:Crisis() end
function DisasterBase:Final() end
function DisasterBase:OnTouchdown(_tier: string) end
function DisasterBase:Cleanup() end

function DisasterBase:NeedsEvacuation(): boolean
	return self.Evacuate or Registry.FireSystem:ActiveCount() > 0
end

function DisasterBase:RevealDetail(): string?
	return self.Detail
end

---------------------------------------------------------------- helpers

function DisasterBase:AdjustLanding(delta: number, note: string?)
	self.LandingDelta += delta
	if note then
		table.insert(self.LandingNotes, { Delta = delta, Note = note })
	end
end

function DisasterBase:Phase(): string
	return self.Ctx.Phase
end

function DisasterBase:Delay(seconds: number, fn: () -> ())
	return self.Ctx:Delay(seconds, fn)
end

function DisasterBase:Every(interval: number | { number }, fn: () -> boolean?)
	return self.Ctx:Every(interval, fn)
end

function DisasterBase:Warn(title: string, subtitle: string?, severity: string?)
	Registry.EffectsService:Warning(title, subtitle, severity)
end

function DisasterBase:Captain(text: string, garbled: boolean?)
	Registry.EffectsService:Sound("Intercom")
	Registry.EffectsService:Announce("Captain", text, { Garbled = garbled })
end

function DisasterBase:Crew(text: string)
	Registry.NPCService:CrewSay(text)
end

function DisasterBase:Announce(speaker: string, text: string, garbled: boolean?)
	Registry.EffectsService:Announce(speaker, text, { Garbled = garbled })
end

function DisasterBase:Notify(text: string, kind: string?, target: any)
	Registry.EffectsService:Notify(text, kind, target)
end

function DisasterBase:Sound(key: string, position: Vector3?)
	Registry.EffectsService:Sound(key, position)
end

function DisasterBase:Effect(name: string, data: { [string]: any }?)
	Registry.EffectsService:Effect(name, data)
end

function DisasterBase:Shake(intensity: number, duration: number)
	Registry.EffectsService:Shake(intensity, duration)
end

function DisasterBase:React(mood: string, fraction: number?)
	Registry.NPCService:React(mood, fraction)
end

function DisasterBase:Objective(def)
	return Registry.ObjectiveService:Add(def)
end

function DisasterBase:Complete(id: string, player: Player?)
	return Registry.ObjectiveService:Complete(id, player)
end

function DisasterBase:IsDone(id: string): boolean
	return Registry.ObjectiveService:IsComplete(id)
end

function DisasterBase:IsActiveObjective(id: string): boolean
	return Registry.ObjectiveService:IsActive(id)
end

function DisasterBase:Prompt(part: Instance, def)
	def.Round = self.Ctx
	return Registry.InteractionService:Add(part, def)
end

function DisasterBase:Vote(def)
	return Registry.DecisionService:Vote(self.Ctx, def)
end

function DisasterBase:Personal(player: Player, def)
	return Registry.DecisionService:Personal(self.Ctx, player, def)
end

function DisasterBase:Outcome(decisionId: string, text: string, good: boolean?)
	Registry.DecisionService:SetOutcome(self.Ctx, decisionId, text, good)
	self.Ctx:Log(text)
end

function DisasterBase:Point(key: string): any
	return Registry.MapService.Points[key]
end

function DisasterBase:Flight(key: string, value: any?)
	if value ~= nil then
		Registry.FlightService:Set(key, value)
	end
	return Registry.FlightService:Get(key)
end

function DisasterBase:Panel(key: string, status: string)
	Registry.MapService:SetPanelStatus(key, status)
end

-- Adds the standard "help injured passengers" optional objective.
function DisasterBase:InjurePassengers(count: number, reason: string?)
	local injured = Registry.NPCService:InjurePassengers(self.Ctx, count, reason)
	if #injured > 0 then
		local existing = Registry.ObjectiveService:Get("HelpPassengers")
		if existing and existing.State == Enums.ObjectiveState.Active then
			Registry.ObjectiveService:SetGoal("HelpPassengers", existing.Goal + #injured)
		elseif not existing then
			self:Objective({
				Id = "HelpPassengers",
				Text = "Help injured passengers",
				Kind = Enums.ObjectiveKind.Optional,
				Goal = #injured,
				Hint = "Look for passengers calling for help",
			})
		end
	end
	return injured
end

-- A hold-to-repair interaction that completes an objective and flips a panel light.
function DisasterBase:RepairPrompt(part: Instance, def: {
	Objective: string,
	Action: string?,
	Object: string?,
	Hold: number?,
	Panel: string?,
	Kind: string?,
	Condition: ((Player) -> (boolean, string?))?,
	OnDone: ((Player) -> ())?,
})
	local handle
	handle = self:Prompt(part, {
		Action = def.Action or "REPAIR",
		Object = def.Object or "",
		Hold = def.Hold or 3,
		Range = 8,
		Kind = def.Kind or "objective",
		Condition = function(player)
			if not Registry.ObjectiveService:IsActive(def.Objective) then
				return false
			end
			if def.Condition then
				return def.Condition(player)
			end
			return true
		end,
		OnTrigger = function(player)
			if Registry.ObjectiveService:Complete(def.Objective, player) then
				if def.Panel then
					Registry.MapService:SetPanelStatus(def.Panel, "ok")
				end
				Registry.EffectsService:Sound("Button", (part :: any).Position)
				handle:SetEnabled(false)
				if def.OnDone then
					def.OnDone(player)
				end
			end
		end,
	})
	return handle
end

-- Players standing within `radius` of a point (alive + conscious).
function DisasterBase:PlayersNear(position: Vector3, radius: number): { Player }
	local list = {}
	for _, player in Registry.MapService:PlayersNear(position, radius, self.Ctx:AlivePlayers()) do
		if Registry.ConditionService:IsConscious(player) then
			table.insert(list, player)
		end
	end
	return list
end

return DisasterBase
