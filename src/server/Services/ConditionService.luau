--[[
	ConditionService
	Healthy -> Injured -> Critical -> Unconscious (revivable, bleeding out) -> Dead.
	Health is server-authoritative; the Humanoid health bar mirrors it. Also tracks oxygen and
	"hazard" exposure (used for the Brave bonus).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Util = require(ReplicatedStorage.Shared.Util)
local Registry = require(script.Parent.Parent.Registry)

local ConditionService = {}

local CFG = GameConfig.Condition

type Info = {
	Health: number,
	State: string,
	DownedAt: number?,
	BleedOut: number,
	Oxygen: number,
	OnOxygen: boolean,
	OxygenSource: string?,
	HazardUntil: number,
	LastDamage: number,
	LastCause: string?,
	Tracked: boolean,
	LastSent: number,
}

local infos: { [Player]: Info } = {}

ConditionService.StateChanged = Signal.new() -- (player, newState, oldState)
ConditionService.Downed = Signal.new() -- (player)
ConditionService.Died = Signal.new() -- (player, cause)

local function stateFor(health: number): string
	if health >= CFG.InjuredBelow then
		return Enums.Condition.Healthy
	elseif health >= CFG.CriticalBelow then
		return Enums.Condition.Injured
	end
	return Enums.Condition.Critical
end

local function snapshot(info: Info)
	return {
		Health = math.floor(info.Health + 0.5),
		State = info.State,
		BleedOut = if info.DownedAt then math.max(0, info.BleedOut - (os.clock() - info.DownedAt)) else nil,
		Oxygen = math.floor(info.Oxygen),
		OnOxygen = info.OnOxygen,
		OxygenSource = info.OxygenSource,
		Tracked = info.Tracked,
	}
end

local function send(player: Player, info: Info)
	info.LastSent = os.clock()
	Net.Event("ConditionUpdated"):FireClient(player, snapshot(info))
end

local function applyMovement(player: Player, info: Info)
	local humanoid = Util.GetHumanoid(player)
	if not humanoid then
		return
	end
	player:SetAttribute("Condition", info.State)
	local speed = CFG.NormalWalkSpeed
	if info.State == Enums.Condition.Injured then
		speed = CFG.InjuredWalkSpeed
	elseif info.State == Enums.Condition.Critical then
		speed = CFG.CriticalWalkSpeed
	elseif info.State == Enums.Condition.Unconscious or info.State == Enums.Condition.Dead then
		speed = 0
	end
	-- hypoxia slows players down gradually
	if info.Tracked and info.Oxygen < 40 and info.State ~= Enums.Condition.Unconscious then
		speed *= 0.55 + info.Oxygen / 40 * 0.45
	end
	humanoid.WalkSpeed = speed
	humanoid.JumpPower = if speed > 0 then 40 else 0
	if info.State ~= Enums.Condition.Dead then
		humanoid.Health = math.clamp(info.Health, 1, humanoid.MaxHealth)
	end
end

local function setState(player: Player, info: Info, newState: string)
	local old = info.State
	if old == newState then
		return
	end
	info.State = newState
	applyMovement(player, info)
	send(player, info)
	ConditionService.StateChanged:Fire(player, newState, old)
end

function ConditionService:Get(player: Player): Info?
	return infos[player]
end

function ConditionService:GetState(player: Player): string
	local info = infos[player]
	return if info then info.State else Enums.Condition.Healthy
end

function ConditionService:GetHealth(player: Player): number
	local info = infos[player]
	return if info then info.Health else CFG.MaxHealth
end

function ConditionService:IsConscious(player: Player): boolean
	local state = self:GetState(player)
	return state ~= Enums.Condition.Unconscious and state ~= Enums.Condition.Dead
end

-- Starts tracking a player for a round (fresh health).
function ConditionService:Track(player: Player)
	local info: Info = {
		Health = CFG.MaxHealth,
		State = Enums.Condition.Healthy,
		DownedAt = nil,
		BleedOut = CFG.BleedOutTime,
		Oxygen = GameConfig.Oxygen.Max,
		OnOxygen = false,
		OxygenSource = nil,
		HazardUntil = 0,
		LastDamage = 0,
		LastCause = nil,
		Tracked = true,
		LastSent = 0,
	}
	infos[player] = info
	applyMovement(player, info)
	send(player, info)
end

function ConditionService:Untrack(player: Player)
	local info = infos[player]
	infos[player] = nil
	if player.Parent then
		player:SetAttribute("Condition", nil)
		Net.Event("ConditionUpdated"):FireClient(player, { State = Enums.Condition.Healthy, Health = CFG.MaxHealth, Tracked = false })
		local humanoid = Util.GetHumanoid(player)
		if humanoid and humanoid.Health > 0 and info then
			humanoid.WalkSpeed = CFG.NormalWalkSpeed
			humanoid.JumpPower = 40
			humanoid.Health = humanoid.MaxHealth
			humanoid.PlatformStand = false
		end
	end
end

function ConditionService:MarkHazard(player: Player, seconds: number?)
	local info = infos[player]
	if info then
		info.HazardUntil = math.max(info.HazardUntil, os.clock() + (seconds or 2))
	end
end

function ConditionService:InHazard(player: Player): boolean
	local info = infos[player]
	return info ~= nil and os.clock() < info.HazardUntil
end

function ConditionService:Damage(player: Player, amount: number, cause: string?, isHazard: boolean?)
	local info = infos[player]
	if not info or amount <= 0 or info.State == Enums.Condition.Dead then
		return
	end
	local round = Registry.RoundService:GetContext()
	if isHazard ~= false then
		info.HazardUntil = math.max(info.HazardUntil, os.clock() + 2.5)
	end
	info.LastDamage = os.clock()
	info.LastCause = cause
	if round then
		round:Add(player, "DamageTaken", amount)
	end
	if info.State == Enums.Condition.Unconscious then
		-- damage while downed shortens the remaining bleed-out time
		info.BleedOut -= amount * 0.25 * CFG.DownedDamageMultiplier
		send(player, info)
		return
	end
	info.Health = math.max(0, info.Health - amount)
	if info.Health <= 0 then
		self:Down(player, cause)
		return
	end
	local newState = stateFor(info.Health)
	if newState ~= info.State then
		setState(player, info, newState)
	else
		applyMovement(player, info)
		if os.clock() - info.LastSent > 0.15 then
			send(player, info)
		end
	end
	Net.Event("Effect"):FireClient(player, { Name = "Hurt", Amount = amount })
end

function ConditionService:Heal(player: Player, amount: number)
	local info = infos[player]
	if not info or info.State == Enums.Condition.Dead or info.State == Enums.Condition.Unconscious then
		return
	end
	info.Health = math.min(CFG.MaxHealth, info.Health + amount)
	setState(player, info, stateFor(info.Health))
	applyMovement(player, info)
	send(player, info)
end

function ConditionService:Down(player: Player, cause: string?)
	local info = infos[player]
	if not info or info.State == Enums.Condition.Unconscious or info.State == Enums.Condition.Dead then
		return
	end
	info.Health = 0
	info.DownedAt = os.clock()
	info.BleedOut = CFG.BleedOutTime
	info.LastCause = cause or info.LastCause
	local humanoid = Util.GetHumanoid(player)
	if humanoid then
		humanoid.Sit = false
	end
	setState(player, info, Enums.Condition.Unconscious)
	ConditionService.Downed:Fire(player)
	Registry.EffectsService:Notify(player.DisplayName .. " is unconscious! Help them up.", "danger")
end

function ConditionService:Revive(player: Player, health: number?)
	local info = infos[player]
	if not info or info.State ~= Enums.Condition.Unconscious then
		return false
	end
	info.DownedAt = nil
	info.Health = health or CFG.ReviveHealth
	info.Oxygen = math.max(info.Oxygen, 45)
	setState(player, info, stateFor(info.Health))
	return true
end

function ConditionService:Kill(player: Player, cause: string?)
	local info = infos[player]
	if not info or info.State == Enums.Condition.Dead then
		return
	end
	info.Health = 0
	info.DownedAt = nil
	info.LastCause = cause or info.LastCause or "Unknown"
	setState(player, info, Enums.Condition.Dead)
	local round = Registry.RoundService:GetContext()
	if round then
		local record = round:Record(player)
		if record and record.Alive then
			record.Alive = false
			record.Died = true
			record.Cause = info.LastCause
		end
	end
	ConditionService.Died:Fire(player, info.LastCause)
	local humanoid = Util.GetHumanoid(player)
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = 0
	end
end

---------------------------------------------------------------- oxygen

function ConditionService:SetOnOxygen(player: Player, on: boolean, source: string?)
	local info = infos[player]
	if info and (info.OnOxygen ~= on or info.OxygenSource ~= source) then
		info.OnOxygen = on
		info.OxygenSource = if on then source else nil
		send(player, info)
	end
end

function ConditionService:ChangeOxygen(player: Player, delta: number)
	local info = infos[player]
	if not info then
		return
	end
	local before = info.Oxygen
	info.Oxygen = math.clamp(info.Oxygen + delta, 0, GameConfig.Oxygen.Max)
	if math.floor(before / 5) ~= math.floor(info.Oxygen / 5) then
		applyMovement(player, info)
		send(player, info)
	end
end

function ConditionService:GetOxygen(player: Player): number
	local info = infos[player]
	return if info then info.Oxygen else GameConfig.Oxygen.Max
end

---------------------------------------------------------------- lifecycle

function ConditionService:Start()
	-- bleed-out ticker
	task.spawn(function()
		while true do
			task.wait(0.5)
			for player, info in infos do
				if info.State == Enums.Condition.Unconscious and info.DownedAt then
					local remaining = info.BleedOut - (os.clock() - info.DownedAt)
					if remaining <= 0 then
						self:Kill(player, info.LastCause)
					elseif os.clock() - info.LastSent > 1 then
						send(player, info)
					end
				end
			end
		end
	end)

	local function onCharacter(player: Player, character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if not humanoid then
			return
		end
		humanoid.BreakJointsOnDeath = false
		humanoid.Died:Connect(function()
			if infos[player] and infos[player].State ~= Enums.Condition.Dead then
				self:Kill(player, infos[player].LastCause or "Fell")
			end
		end)
	end

	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			onCharacter(player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		infos[player] = nil
	end)
end

return ConditionService
