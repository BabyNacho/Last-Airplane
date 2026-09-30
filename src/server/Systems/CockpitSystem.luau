--[[
	CockpitSystem
	  * Cockpit door lock state and the default door interactions (knock / open / close).
	  * Manual flying: when manual control is enabled and a player sits in a pilot seat, the server
	    simulates aircraft attitude drift; the client only sends stick input (-1..1). Keeping the
	    attitude centred raises stability and (during the approach) the landing score.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local RateLimiter = require(script.Parent.Parent.RateLimiter)
local Registry = require(script.Parent.Parent.Registry)

local CockpitSystem = {}

local CFG = GameConfig.Manual

local ctxRef: any = nil
local manualEnabled = false
local approachMode = false
local attitude = 0
local inputs: { [Player]: number } = {}
local goodSamples: { boolean } = {}
local approachSamples: { number } = {}
local approachPilots: { [Player]: number } = {}
local phaseOffset = 0
local doorHandle: any = nil

---------------------------------------------------------------- door

function CockpitSystem:IsLocked(): boolean
	local door = Registry.MapService.Points.CockpitDoor
	return door:GetAttribute("Locked") == true
end

function CockpitSystem:Unlock(openDoor: boolean?)
	local map = Registry.MapService
	map:SetDividerLocked("CockpitDoor", false)
	if openDoor then
		map:SetDividerOpen("CockpitDoor", true)
	end
	if doorHandle then
		doorHandle:SetText(if map:IsDividerOpen("CockpitDoor") then "CLOSE" else "OPEN", "COCKPIT DOOR")
	end
end

function CockpitSystem:Lock()
	local map = Registry.MapService
	map:SetDividerOpen("CockpitDoor", false)
	map:SetDividerLocked("CockpitDoor", true)
	if doorHandle then
		doorHandle:SetText("KNOCK", "COCKPIT DOOR (LOCKED)")
	end
end

-- Disasters can replace what happens when a player interacts with the locked door.
CockpitSystem.LockedHandler = nil :: ((Player) -> ())?

local function setupDoor(ctx)
	local map = Registry.MapService
	local door = map.Points.CockpitDoor
	doorHandle = Registry.InteractionService:Add(door, {
		Action = "KNOCK",
		Object = "COCKPIT DOOR (LOCKED)",
		Range = 7,
		Round = ctx,
		Cooldown = 1.2,
		OnTrigger = function(player)
			if CockpitSystem:IsLocked() then
				if CockpitSystem.LockedHandler then
					CockpitSystem.LockedHandler(player)
					return
				end
				Registry.EffectsService:Sound("Door", door.Position)
				if Registry.FlightService:Get("PilotPresent") then
					Registry.EffectsService:Announce("Captain", "Please return to your seat - the flight deck stays locked for your safety.", nil, player)
				else
					Registry.EffectsService:Notify("No answer from inside...", "warn", player)
				end
				return
			end
			local open = not map:IsDividerOpen("CockpitDoor")
			map:SetDividerOpen("CockpitDoor", open)
			doorHandle:SetText(if open then "CLOSE" else "OPEN", "COCKPIT DOOR")
			Registry.EffectsService:Sound("Door", door.Position)
		end,
	})
end

---------------------------------------------------------------- manual flight

local function pilotPlayers(): { Player }
	local list = {}
	local points = Registry.MapService.Points
	for _, seat in { points.PilotSeat, points.CopilotSeat } do
		local occupant = seat and seat.Occupant
		if occupant then
			local player = Players:GetPlayerFromCharacter(occupant.Parent)
			if player and ctxRef and ctxRef:IsParticipant(player) and Registry.ConditionService:IsConscious(player) then
				table.insert(list, player)
			end
		end
	end
	return list
end

function CockpitSystem:HasPilot(): boolean
	return #pilotPlayers() > 0
end

function CockpitSystem:EnableManual(enabled: boolean)
	manualEnabled = enabled
	if not enabled then
		for _, player in pilotPlayers() do
			Net.Event("ManualFlight"):FireClient(player, { Active = false })
		end
	end
end

function CockpitSystem:IsManual(): boolean
	return manualEnabled
end

function CockpitSystem:SetApproach(enabled: boolean)
	approachMode = enabled
	if enabled then
		table.clear(approachSamples)
	end
end

-- Stability bonus from a human flying well (0..26), used by FlightService.
function CockpitSystem:ManualBonus(): number
	if not manualEnabled or #goodSamples == 0 or not self:HasPilot() then
		return 0
	end
	local good = 0
	for _, sample in goodSamples do
		if sample then
			good += 1
		end
	end
	return 30 * (good / #goodSamples)
end

-- 0..1 quality of the manually flown approach, nil if nobody flew it.
function CockpitSystem:ApproachQuality(): number?
	if #approachSamples < 10 then
		return nil
	end
	local sum = 0
	for _, deviation in approachSamples do
		sum += math.clamp(1 - math.abs(deviation) / 100, 0, 1)
	end
	return sum / #approachSamples
end

function CockpitSystem:ApproachPilots(): { [Player]: number }
	return approachPilots
end

local function step(dt: number)
	local ctx = ctxRef
	if not ctx or not manualEnabled then
		return
	end
	local pilots = pilotPlayers()
	local t = os.clock()
	local turbulence = Registry.FlightService:Get("Turbulence") or 0
	local stability = Registry.FlightService:Get("Stability") or 100
	local chaos = 1 + turbulence * 0.35 + (100 - stability) / 200 + (if approachMode then 0.3 else 0)
	local drift = (math.sin(t * 0.8 + phaseOffset) + math.sin(t * 1.9 + phaseOffset * 2) * 0.5) * CFG.DriftStrength * chaos
	drift += ctx.Rng:NextNumber(-1, 1) * CFG.DriftStrength * 0.6 * chaos
	local input = 0
	for _, player in pilots do
		input += inputs[player] or 0
	end
	input = math.clamp(input, -1, 1)
	attitude = math.clamp(attitude + (drift + input * CFG.CorrectionStrength) * dt, -100, 100)
	local good = math.abs(attitude) < CFG.GoodZone
	if #pilots > 0 then
		table.insert(goodSamples, good)
		if #goodSamples > 60 then
			table.remove(goodSamples, 1)
		end
		for _, player in pilots do
			local record = ctx:Record(player)
			if record then
				record.ManualFlightTime += dt
				if good then
					record.ManualFlightGood += dt
				end
			end
			if approachMode then
				approachPilots[player] = (approachPilots[player] or 0) + dt
			end
		end
		if approachMode then
			table.insert(approachSamples, attitude)
		end
	else
		-- nobody flying: the aircraft slowly wanders off
		if #goodSamples > 0 then
			table.remove(goodSamples, 1)
		end
		if approachMode then
			table.insert(approachSamples, 100)
		end
	end
	local payload = {
		Active = true,
		Attitude = math.floor(attitude * 10) / 10,
		GoodZone = CFG.GoodZone,
		Approach = approachMode,
		Altitude = Registry.FlightService:Get("Altitude"),
	}
	for _, player in pilots do
		Net.Event("ManualFlight"):FireClient(player, payload)
	end
end

local function onInput(player: Player, value: any)
	if type(value) ~= "number" or value ~= value then
		return
	end
	if not RateLimiter.Allow(player, "PilotInput") then
		return
	end
	if not manualEnabled or not table.find(pilotPlayers(), player) then
		inputs[player] = nil
		return
	end
	inputs[player] = math.clamp(value, -1, 1)
end

---------------------------------------------------------------- lifecycle

function CockpitSystem:OnRoundStart(ctx)
	ctxRef = ctx
	manualEnabled = false
	approachMode = false
	attitude = 0
	phaseOffset = ctx.Rng:NextNumber(0, 10)
	CockpitSystem.LockedHandler = nil
	table.clear(inputs)
	table.clear(goodSamples)
	table.clear(approachSamples)
	table.clear(approachPilots)
	setupDoor(ctx)
	ctx:Every(0.1, function()
		step(0.1)
		return true
	end)
end

function CockpitSystem:OnRoundEnd()
	manualEnabled = false
	approachMode = false
	CockpitSystem.LockedHandler = nil
	doorHandle = nil
	ctxRef = nil
end

function CockpitSystem:Start()
	Net.Event("PilotInput").OnServerEvent:Connect(onInput)
	Players.PlayerRemoving:Connect(function(player)
		inputs[player] = nil
		approachPilots[player] = nil
	end)
end

return CockpitSystem
