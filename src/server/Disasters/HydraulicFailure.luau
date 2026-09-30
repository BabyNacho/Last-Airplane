--[[
	HYDRAULIC FAILURE
	Clues: a dull thunk, controls twitching, a faint drip somewhere in the service bay, the
	hydraulic gauge creeping down.
	Event: a line ruptures - pressure plunges, the aircraft porpoises (heavy, sluggish controls).
	Players: inspect the three hydraulic valves to find the leaking one (it drips), close its
	isolation valve before the system bleeds dry.
	Decision (vote): send the RESERVE fluid to the FLIGHT CONTROLS (stable aircraft, but the
	landing gear must be cranked down by hand - a co-op job) or to the LANDING GEAR (gear drops
	normally, but the aircraft stays heavy and unstable on landing).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local DisasterBase = require(script.Parent.DisasterBase)

local HydraulicFailure = DisasterBase.extend("HydraulicFailure")

function HydraulicFailure:Setup()
	self.LeakIndex = self.Rng:NextInteger(1, 3)
	self.Isolated = false
	self.Found = false
	self.Inspected = {}
end

function HydraulicFailure:AddDrip()
	local valve = self:Point("HydraulicValves")[self.LeakIndex]
	local drip = Instance.new("ParticleEmitter")
	drip.Name = "HydraulicDrip"
	drip.Color = ColorSequence.new(Color3.fromRGB(200, 60, 160))
	drip.Size = NumberSequence.new(0.18)
	drip.Speed = NumberRange.new(0.5, 1.5)
	drip.Acceleration = Vector3.new(0, -30, 0)
	drip.Lifetime = NumberRange.new(0.6, 0.9)
	drip.Rate = 6
	drip.EmissionDirection = Enum.NormalId.Bottom
	drip.Parent = valve
	self.Drip = drip
	self.Ctx:Give(drip)
end

function HydraulicFailure:Clues()
	self:Sound("Impact")
	self:Shake(0.3, 0.5)
	self:AddDrip()
	self:Every(1, function()
		if self:Phase() ~= Enums.Phase.Flight then
			return false
		end
		local hyd = self:Flight("Hydraulics")
		self:Flight("Hydraulics", math.max(82, hyd - 0.6))
		return true
	end)
	self:Delay(7, function()
		self:Shake(0.15, 2)
		self:React("Nervous", 0.15)
	end)
	self:Delay(13, function()
		self:Captain("Just a small twitch in the controls, folks. We're looking into it.")
	end)
end

function HydraulicFailure:Start()
	local flight = self.S.FlightService
	self:Sound("BigImpact")
	self:Shake(1.1, 1.2)
	self:Flight("Hydraulics", 45)
	flight:SetModifier("Phugoid", -12)
	self:Flight("CockpitAlarm", true)
	self.Drip.Rate = 40
	self:Warn("HYD SYS A", "PRESSURE LOW - FLIGHT CONTROLS DEGRADED", "danger")
	self:React("Panic", 0.35)
	self:InjurePassengers(1, "Knocked over when the aircraft lurched")
	self.S.MapService:SetDividerOpen("ServiceDoor", true)
	self:Delay(4, function()
		self:Captain("We've got a hydraulic leak and she's getting heavy. Find which line is leaking in the service bay and isolate it - fast, before we lose it all.")
	end)
	-- pressure keeps bleeding until the leak is isolated
	self:Every(1, function()
		if self.Isolated then
			return false
		end
		self:Flight("Hydraulics", math.max(5, self:Flight("Hydraulics") - 0.45))
		return true
	end)

	self:Objective({
		Id = "FindLeak",
		Text = "Find the leaking hydraulic line",
		Kind = Enums.ObjectiveKind.Critical,
		Location = self:Point("HydraulicValves")[2],
		Hint = "Three valves on the right wall of the service bay - look for dripping fluid",
	})
	for index, valve in self:Point("HydraulicValves") do
		local handle
		handle = self:Prompt(valve, {
			Action = "INSPECT",
			Object = "HYDRAULIC LINE " .. index,
			Hold = 1.5,
			Range = 7,
			Kind = "objective",
			Condition = function()
				return not self.Found and not self.Inspected[index]
			end,
			OnTrigger = function(player)
				self.Inspected[index] = true
				handle:SetEnabled(false)
				if index == self.LeakIndex then
					self:FoundLeak(player)
				else
					self:Notify("Line " .. index .. ": pressure normal, no leak.", "info", player)
				end
			end,
		})
	end
end

function HydraulicFailure:FoundLeak(player: Player)
	self.Found = true
	self:Complete("FindLeak", player)
	self:Warn("LEAK FOUND", "HYDRAULIC LINE " .. self.LeakIndex, "warn")
	local valve = self:Point("HydraulicValves")[self.LeakIndex]
	self:Objective({
		Id = "IsolateLeak",
		Text = "Close the isolation valve on line " .. self.LeakIndex,
		Kind = Enums.ObjectiveKind.Critical,
		Location = valve,
	})
	self:RepairPrompt(valve, {
		Objective = "IsolateLeak",
		Action = "CLOSE",
		Object = "ISOLATION VALVE " .. self.LeakIndex,
		Hold = 4,
		OnDone = function()
			self.Isolated = true
			self.Drip.Rate = 0
			self:Notify("Leak isolated - pressure holding at " .. math.floor(self:Flight("Hydraulics")) .. "%.", "good")
			self:AdjustLanding(5, "Hydraulic leak isolated")
		end,
	})
end

function HydraulicFailure:Crisis()
	self:Delay(14, function()
		self:ReserveVote()
	end)
	self:Every(22, function()
		if self:Phase() ~= Enums.Phase.Crisis then
			return false
		end
		self:Shake(0.7, 2)
		return true
	end)
end

function HydraulicFailure:ReserveVote()
	local leaking = not self.Isolated
	self:Vote({
		Id = "ReserveFluid",
		Title = "WHERE DOES THE RESERVE FLUID GO?",
		Speaker = "Captain",
		Prompt = "I've got one reserve tank. It can power the flight controls or drop the landing gear - not both." .. (if leaking then " (The leak is NOT isolated - it will bleed away!)" else ""),
		Duration = 15,
		Default = "Controls",
		Options = {
			{ Id = "Controls", Label = "FLIGHT CONTROLS", Description = "Steady aircraft. The gear must be cranked down by hand.", Risk = "medium" },
			{ Id = "Gear", Label = "LANDING GEAR", Description = "Gear drops normally. Heavy, unstable controls on landing.", Risk = "medium" },
		},
		OnResolve = function(choice)
			local flight = self.S.FlightService
			if choice == "Controls" then
				self.Choice = "Controls"
				self.Ctx.Flags.GearMethod = "Crank"
				if self.Isolated then
					self:Flight("Hydraulics", 72)
					flight:SetModifier("Phugoid", nil)
					self:Outcome("ReserveFluid", "Reserve fluid restored the flight controls - the gear had to be cranked by hand.", true)
				else
					self:Flight("Hydraulics", 55)
					flight:SetModifier("Phugoid", -6)
					self:Outcome("ReserveFluid", "Reserve fluid went to the controls, but the unisolated leak bled much of it away.", false)
				end
			else
				self.Choice = "Gear"
				self.Ctx.Flags.GearMethod = "Auto"
				self:AdjustLanding(-12, "Heavy flight controls on landing")
				self:Outcome("ReserveFluid", "Reserve fluid was saved for the landing gear; the aircraft stayed heavy to fly.", nil)
			end
		end,
	})
end

function HydraulicFailure:Final()
	if not self.Choice then
		self.Ctx.Flags.GearMethod = "Crank"
	end
	if self.Ctx.Flags.GearMethod == "Crank" then
		self:Captain("The gear won't come down on its own. Someone get to the manual crank in the forward galley floor - more hands, faster!")
	end
end

function HydraulicFailure:RevealDetail(): string?
	return "A chafed line on hydraulic system A ruptured behind valve " .. self.LeakIndex .. "."
end

function HydraulicFailure:Cleanup()
	self.S.FlightService:SetModifier("Phugoid", nil)
end

return HydraulicFailure
