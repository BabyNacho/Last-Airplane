--[[
	FlightService
	Authoritative aircraft state. Values live as attributes on ReplicatedStorage.FlightState so
	clients can drive visuals (lights, instruments, outside world, shake) without extra remotes.

	Stability (0-100) is the heart of the landing: it trends toward 100 + sum(modifiers).
	Systems and disasters push named modifiers (e.g. EngineL = -18) instead of editing it directly.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local Registry = require(script.Parent.Parent.Registry)

local FlightService = {}

local state: Folder
local modifiers: { [string]: number } = {}
local simThread: thread? = nil
local stabilitySamples: { number } = {}

local CRUISE_ALTITUDE = 35000

local DEFAULTS = {
	Altitude = CRUISE_ALTITUDE,
	TargetAltitude = CRUISE_ALTITUDE,
	VerticalSpeed = 0,
	Speed = 460,
	Stability = 100,
	EngineL = 100,
	EngineR = 100,
	Hydraulics = 100,
	Pressure = 100,
	MainPower = true,
	CabinLights = Enums.Lights.Normal,
	Autopilot = true,
	PilotPresent = true,
	GearDown = false,
	SeatbeltSign = false,
	Weather = "Clear",
	Night = false,
	Fires = 0,
	Turbulence = 0,
	Roll = 0,
	Pitch = 0,
	OxygenEmergency = false,
	Visibility = 1,
	Approach = false,
	OnGround = false,
	Distance = 0,
	Storm = 0,
	Birds = false,
	EngineFireL = false,
	EngineFireR = false,
	CockpitAlarm = false,
	FireAlarmActive = false,
	InstrumentsFailed = false,
	AirspeedUnreliable = false,
	NavFailed = false,
	PressureAlarm = false,
	EngineSmokeL = false,
	EngineSmokeR = false,
	RunwaySide = 0,
	Descent = 0,
}

function FlightService:Init()
	state = Instance.new("Folder")
	state.Name = "FlightState"
	state.Parent = ReplicatedStorage
	self:Reset()
end

function FlightService:Reset()
	modifiers = {}
	stabilitySamples = {}
	for key, value in DEFAULTS do
		state:SetAttribute(key, value)
	end
end

function FlightService:OnRoundStart(ctx)
	self:Reset()
	state:SetAttribute("Night", ctx.Modifier == "NightFlight")
end

function FlightService:Get(key: string): any
	return state:GetAttribute(key)
end

function FlightService:Set(key: string, value: any)
	state:SetAttribute(key, value)
end

function FlightService:Changed(key: string)
	return state:GetAttributeChangedSignal(key)
end

function FlightService:SetModifier(key: string, value: number?)
	modifiers[key] = value
end

function FlightService:GetModifier(key: string): number?
	return modifiers[key]
end

function FlightService:StabilityTarget(): number
	local target = 100
	for _, value in modifiers do
		target += value
	end
	return math.clamp(target, 0, 100)
end

function FlightService:SetLights(mode: string)
	state:SetAttribute("CabinLights", mode)
end

-- Adjusts how fast the aircraft is descending (feet per second) toward TargetAltitude.
function FlightService:SetDescent(targetAltitude: number, feetPerSecond: number)
	state:SetAttribute("TargetAltitude", targetAltitude)
	state:SetAttribute("Descent", feetPerSecond)
end

function FlightService:AverageStability(lastN: number?): number
	local n = math.min(#stabilitySamples, lastN or #stabilitySamples)
	if n == 0 then
		return self:Get("Stability")
	end
	local sum = 0
	for i = #stabilitySamples - n + 1, #stabilitySamples do
		sum += stabilitySamples[i]
	end
	return sum / n
end

local function step(dt: number)
	-- engine-derived penalties
	local engineL, engineR = state:GetAttribute("EngineL"), state:GetAttribute("EngineR")
	local thrust = (engineL + engineR) / 200
	modifiers.Engines = if thrust < 1 then -(1 - thrust) * 35 else nil
	local hyd = state:GetAttribute("Hydraulics")
	modifiers.HydraulicsLow = if hyd < 60 then -(60 - hyd) * 0.45 else nil
	modifiers.Turbulence = if state:GetAttribute("Turbulence") > 0 then -state:GetAttribute("Turbulence") * 6 else nil
	modifiers.Fires = if state:GetAttribute("Fires") > 0 then -math.min(20, state:GetAttribute("Fires") * 3) else nil
	if not state:GetAttribute("Autopilot") then
		local cockpit = Registry.CockpitSystem
		local manual = cockpit and cockpit:ManualBonus() or 0
		modifiers.NoAutopilot = -26 + manual
	else
		modifiers.NoAutopilot = nil
	end

	local stability = state:GetAttribute("Stability")
	local target = FlightService:StabilityTarget()
	local rate = if target < stability then 4 else 2.5
	stability += math.clamp(target - stability, -rate * dt, rate * dt)
	state:SetAttribute("Stability", math.floor(stability * 10 + 0.5) / 10)
	table.insert(stabilitySamples, stability)
	if #stabilitySamples > 600 then
		table.remove(stabilitySamples, 1)
	end

	-- altitude: pushed down by lost thrust, pulled toward the target altitude
	local altitude = state:GetAttribute("Altitude")
	local targetAltitude = state:GetAttribute("TargetAltitude")
	local descent = state:GetAttribute("Descent")
	local sinkFromThrust = if thrust < 1 then (1 - thrust) * 60 else 0
	local vs = 0
	if altitude > targetAltitude then
		vs = -(descent + sinkFromThrust)
	elseif altitude < targetAltitude - 50 then
		vs = math.max(20, descent * 0.5)
	end
	-- never let the aircraft hit the ground outside of the landing sequence
	local floor = if state:GetAttribute("Approach") then 0 else 2500
	altitude = math.max(floor, altitude + vs * dt)
	state:SetAttribute("Altitude", math.floor(altitude))
	state:SetAttribute("VerticalSpeed", math.floor(vs * 60))

	-- cosmetic attitude for camera tilt (worse stability = more wobble)
	local wobble = (100 - stability) / 100
	local t = os.clock()
	state:SetAttribute("Roll", math.floor((math.sin(t * 0.7) * 6 * wobble + (1 - thrust) * (engineL < engineR and -5 or 5)) * 10) / 10)
	state:SetAttribute("Pitch", math.floor((math.sin(t * 0.45) * 3 * wobble + math.clamp(vs / 40, -4, 2)) * 10) / 10)
end

function FlightService:StartSimulation()
	self:StopSimulation()
	simThread = task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.5)
			local now = os.clock()
			local ok, err = pcall(step, now - last)
			if not ok then
				warn("[FlightService] step error:", err)
			end
			last = now
		end
	end)
end

function FlightService:StopSimulation()
	if simThread then
		pcall(task.cancel, simThread)
		simThread = nil
	end
end

return FlightService
