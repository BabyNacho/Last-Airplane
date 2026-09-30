--[[
	InteractionService
	Wraps ProximityPrompts (which natively support keyboard, gamepad and touch) with server-side
	validation. Prompts use the Custom style; the client PromptController renders the branded UI
	and a large tap target on mobile.

	InteractionService:Add(part, {
		Action = "OPEN", Object = "EMERGENCY DOOR", Hold = 1, Range = 8,
		Kind = "default" | "objective" | "danger" | "rescue" | "decision",
		RequireParticipant = true, -- only round participants who are conscious
		Condition = function(player) return ok, reason end,
		OnTrigger = function(player) end,
		Cooldown = 0.5, -- per player
		HideFor = userId, -- client hides the prompt for this user
		Round = ctx, -- auto-destroy when the round ends
	}) -> handle
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local Registry = require(script.Parent.Parent.Registry)

local InteractionService = {}

export type Handle = {
	Prompt: ProximityPrompt,
	SetText: (Handle, string?, string?) -> (),
	SetEnabled: (Handle, boolean) -> (),
	SetHold: (Handle, number) -> (),
	Destroy: (Handle) -> (),
}

local Handle = {}
Handle.__index = Handle

function Handle:SetText(action: string?, object: string?)
	if not self.Prompt.Parent then
		return
	end
	if action then
		self.Prompt.ActionText = action
	end
	if object then
		self.Prompt.ObjectText = object
	end
end

function Handle:SetEnabled(enabled: boolean)
	if self.Prompt.Parent then
		self.Prompt.Enabled = enabled
	end
end

function Handle:SetHold(seconds: number)
	if self.Prompt.Parent then
		self.Prompt.HoldDuration = seconds
	end
end

function Handle:SetKind(kind: string)
	if self.Prompt.Parent then
		self.Prompt:SetAttribute("Kind", kind)
	end
end

function Handle:Destroy()
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	if self.Prompt then
		self.Prompt:Destroy()
	end
end

local function canAct(player: Player, def): (boolean, string?)
	local round = Registry.RoundService:GetContext()
	if def.RequireParticipant ~= false then
		if not round or not round:IsParticipant(player) then
			return false, nil
		end
		local condition = Registry.ConditionService:GetState(player)
		if condition == Enums.Condition.Unconscious or condition == Enums.Condition.Dead then
			return false, nil
		end
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false, nil
	end
	-- defense in depth: never trust that the triggering client was actually in range
	if def._Anchor and def.Range then
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local anchor = def._Anchor
		local position = if anchor:IsA("BasePart") then anchor.Position elseif anchor:IsA("Attachment") then anchor.WorldPosition else nil
		if root and position and (root.Position - position).Magnitude > def.Range + 6 then
			return false, nil
		end
	end
	if def.Condition then
		local ok, result, reason = pcall(def.Condition, player)
		if not ok then
			warn("[Interaction] condition error:", result)
			return false, nil
		end
		if not result then
			return false, reason
		end
	end
	return true, nil
end

function InteractionService:Add(part: Instance, def): Handle
	def._Anchor = part
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Interaction"
	prompt.ActionText = def.Action or "USE"
	prompt.ObjectText = def.Object or ""
	prompt.HoldDuration = def.Hold or 0
	prompt.MaxActivationDistance = def.Range or 8
	prompt.RequiresLineOfSight = def.LineOfSight == true
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt:SetAttribute("Kind", def.Kind or "default")
	if def.HideFor then
		prompt:SetAttribute("HideFor", def.HideFor)
	end
	if def.UIOffset then
		prompt.UIOffset = def.UIOffset
	end
	prompt.Parent = part

	local handle = setmetatable({ Prompt = prompt, _def = def, _last = {} }, Handle)
	handle._connection = prompt.Triggered:Connect(function(player: Player)
		local now = os.clock()
		if now - (handle._last[player] or 0) < (def.Cooldown or 0.4) then
			return
		end
		handle._last[player] = now
		local ok, reason = canAct(player, def)
		if not ok then
			if reason then
				Registry.EffectsService:Notify(reason, "warn", player)
			end
			return
		end
		local success, err = pcall(def.OnTrigger, player, handle)
		if not success then
			warn("[Interaction] handler error:", err)
		end
	end)
	if def.Round then
		def.Round:Give(handle)
	end
	return handle :: any
end

return InteractionService
