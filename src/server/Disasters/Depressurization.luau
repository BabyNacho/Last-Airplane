--[[
	CABIN DEPRESSURIZATION
	Clues: a thin whistle, ears popping, the captain's announcement starts slurring...
	Event: BANG - fog, masks drop, emergency lights. The pilots are hypoxic and the autopilot is
	holding 35,000 ft, where nobody survives long without oxygen.
	Players: mask up (seat masks, mask panels, portable bottles), get into the cockpit to start the
	emergency descent, put masks on the pilots so they can land, find and fix the leak, and help
	passengers who can't reach their masks. No mask = gradual hypoxia (slow, blurry, then out).
	Decision (vote): RAPID descent (oxygen danger ends fast, but violent shaking and loose objects)
	vs CONTROLLED descent (smooth, but the mask oxygen generators may run dry first).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local DisasterBase = require(script.Parent.DisasterBase)

local Depressurization = DisasterBase.extend("Depressurization")

function Depressurization:Setup()
	self.Cause = if self.Rng:NextNumber() < 0.5 then "Outflow" else "DoorSeal"
	local rearExits = {}
	for _, exit in self:Point("Exits") do
		if not exit.Overwing and exit.X < 0 then
			table.insert(rearExits, exit)
		end
	end
	self.LeakExit = rearExits[self.Rng:NextInteger(1, #rearExits)]
	self.PilotsRevived = 0
	self.DescentStarted = false
end

function Depressurization:Clues()
	self:Effect("Whistle", { Duration = 20 })
	self:Delay(5, function()
		for _, player in self.Ctx:Players() do
			self:Notify("Your ears pop...", "info", player)
		end
	end)
	self:Delay(9, function()
		self:React("Nervous", 0.2)
		self:Sound("Chime")
	end)
	self:Delay(14, function()
		self:Captain("Ah... folks... we're, uh... just going to... *yawn* ...continue our... cruise...")
	end)
end

function Depressurization:Start()
	local flight = self.S.FlightService
	self:Sound("Decompression")
	self:Effect("Decompression", { Position = self.LeakExit.Door.Position })
	self:Shake(1.2, 1)
	self:Flight("Pressure", 0)
	self:Flight("PressureAlarm", true)
	flight:SetLights(Enums.Lights.Emergency)
	self.S.OxygenSystem:Begin(self.Ctx)
	self.S.NPCService:SetMasks(true)
	self:Flight("PilotPresent", false)
	self:Warn("CABIN ALTITUDE", "PRESSURE LOST - OXYGEN MASKS DEPLOYED", "danger")
	self:React("Masked", 0.5)
	self.S.CockpitSystem:Unlock(false)
	self.S.MapService:SetDividerOpen("ServiceDoor", true)
	self:Delay(3, function()
		self:Crew("MASKS ON! Pull it down, put it over your nose and mouth! The captain isn't answering - I've unlocked the cockpit door!")
	end)
	self:InjurePassengers(self.Rng:NextInteger(1, 2), "Can't reach their oxygen mask")

	self:Objective({
		Id = "UseMasks",
		Text = "Put on an oxygen mask",
		Kind = Enums.ObjectiveKind.Critical,
		Goal = math.max(1, self.Ctx:AliveCount()),
		Hint = "Buckle into any seat, use a mask panel, or grab a portable oxygen bottle",
	})
	self:Objective({
		Id = "StartDescent",
		Text = "Get to the cockpit and start the emergency descent",
		Kind = Enums.ObjectiveKind.Critical,
		Location = self:Point("Autopilot"),
		Hint = "Autopilot panel on the glareshield - you'll need oxygen to get there",
	})
	self:Prompt(self:Point("Autopilot"), {
		Action = "EMERGENCY DESCENT",
		Object = "AUTOPILOT",
		Hold = 2,
		Range = 8,
		Kind = "decision",
		Condition = function()
			return not self.DescentStarted and self:IsActiveObjective("StartDescent")
		end,
		OnTrigger = function(player)
			self:Complete("StartDescent", player)
			self:DescentVote()
		end,
	})
	-- hypoxic pilots can be revived with masks
	self:Objective({
		Id = "RevivePilots",
		Text = "Put oxygen masks on the pilots",
		Kind = Enums.ObjectiveKind.Optional,
		Goal = 2,
		Location = self:Point("PilotSeat"),
		Hint = "If the pilots recover, they can land the aircraft",
	})
	for index, npc in self.S.NPCService:Pilots() do
		self.S.NPCService:SayAs(npc, "zzz...", 3)
		local handle
		handle = self:Prompt(npc.Root, {
			Action = "MASK PILOT",
			Object = if index == 1 then "CAPTAIN (unconscious)" else "FIRST OFFICER (unconscious)",
			Hold = 3,
			Range = 7,
			Kind = "rescue",
			OnTrigger = function(player)
				handle:SetEnabled(false)
				self.PilotsRevived += 1
				self.S.ObjectiveService:Progress("RevivePilots", 1, player)
				self.Ctx:Add(player, "Rescues")
				self.S.NPCService:SayAs(npc, "*gasp* ...what happened? Thank you!", 4)
				if self.PilotsRevived == 1 then
					self:Flight("PilotPresent", true)
					self.Ctx.Flags.ManualApproach = false
					self.S.CockpitSystem:EnableManual(false)
					self:Captain("I'm... I'm back. Thank you. I have the aircraft.")
					self:AdjustLanding(10, "A pilot was revived")
				end
			end,
		})
	end

	-- the leak
	self:Objective({
		Id = "FindLeak",
		Text = "Check the pressurization panel to find the leak",
		Kind = Enums.ObjectiveKind.Critical,
		Location = self:Point("OutflowValve"),
		Hint = "Service bay - take portable oxygen with you",
	})
	self:Panel("OutflowValve", "fail")
	self:RepairPrompt(self:Point("OutflowValve"), {
		Objective = "FindLeak",
		Action = "READ",
		Object = "PRESSURIZATION PANEL",
		Hold = 2,
		OnDone = function(player)
			self:RevealLeak(player)
		end,
	})
end

function Depressurization:RevealLeak(player: Player)
	if self.Cause == "Outflow" then
		self.Detail = "The outflow valve jammed fully open and dumped cabin pressure."
		self:Warn("LEAK SOURCE", "OUTFLOW VALVE STUCK OPEN", "warn")
		self:Objective({ Id = "FixLeak", Text = "Manually close the outflow valve", Kind = Enums.ObjectiveKind.Critical, Location = self:Point("OutflowValve") })
		self:RepairPrompt(self:Point("OutflowValve"), {
			Objective = "FixLeak",
			Action = "CRANK CLOSED",
			Object = "OUTFLOW VALVE",
			Hold = 4,
			Panel = "OutflowValve",
			OnDone = function()
				self:Repressurize()
			end,
		})
	else
		local exit = self.LeakExit
		self.Detail = "The seal on door " .. exit.Id .. " failed and the cabin lost pressure."
		self:Warn("LEAK SOURCE", "DOOR " .. exit.Id .. " SEAL FAILURE", "warn")
		self:Objective({ Id = "FixLeak", Text = "Re-inflate the seal on door " .. exit.Id, Kind = Enums.ObjectiveKind.Critical, Location = exit.Door })
		self:RepairPrompt(exit.Door, {
			Objective = "FixLeak",
			Action = "RE-INFLATE SEAL",
			Object = "DOOR " .. exit.Id,
			Hold = 4,
			Kind = "danger",
			OnDone = function()
				self:Repressurize()
			end,
		})
	end
	self:Notify("Leak located - fix it to restore pressure.", "good", player)
end

function Depressurization:Repressurize()
	self.Fixed = true
	self:Flight("Pressure", 100)
	self:Flight("PressureAlarm", false)
	self.S.OxygenSystem:End()
	self.S.NPCService:SetMasks(false)
	self.S.ObjectiveService:Remove("UseMasks")
	self.S.FlightService:SetLights(Enums.Lights.Dim)
	self:Sound("PowerUp")
	self:Warn("CABIN PRESSURE RESTORED", "Masks may be removed", "info")
	self:AdjustLanding(6, "Cabin repressurized")
end

function Depressurization:DescentVote()
	self.DescentStarted = true
	self:Vote({
		Id = "DescentType",
		Title = "HOW FAST DO WE GO DOWN?",
		Speaker = "Flight Attendant",
		Prompt = "The autopilot will take us down. A dive gets us breathable air fastest - but it will be violent.",
		Duration = 14,
		Default = "Controlled",
		Options = {
			{ Id = "Rapid", Label = "RAPID DIVE", Description = "Safe air in under a minute. Violent shaking, flying luggage.", Risk = "high" },
			{ Id = "Controlled", Label = "CONTROLLED DESCENT", Description = "Smooth. Mask oxygen may run out before we get low.", Risk = "medium" },
		},
		OnResolve = function(choice)
			if choice == "Rapid" then
				self.S.FlightService:SetDescent(12000, 420)
				self.S.TurbulenceSystem:SetStage(self.Ctx, 2)
				self.S.FlightService:SetModifier("RapidDive", -10)
				self:Delay(45, function()
					self.S.TurbulenceSystem:SetStage(self.Ctx, 0)
					self.S.FlightService:SetModifier("RapidDive", nil)
				end)
				self:AdjustLanding(-3, "Violent emergency dive")
				self:Outcome("DescentType", "A rapid dive reached breathable air quickly, throwing the cabin around.", true)
			else
				self.S.FlightService:SetDescent(12000, 150)
				self.S.OxygenSystem:SetSupply(80)
				self:AdjustLanding(4, "Smooth controlled descent")
				self:Outcome("DescentType", "A controlled descent kept things smooth while mask oxygen ran low.", nil)
			end
			self:Warn("EMERGENCY DESCENT", if choice == "Rapid" then "DIVING TO 12,000 FT" else "DESCENDING TO 12,000 FT", "warn")
		end,
	})
end

function Depressurization:Crisis()
	if not self.DescentStarted then
		self:Crew("We're still at 35,000 feet! Somebody get to the cockpit and start the descent!")
	end
	-- if nobody starts the descent, the crew eventually does it the hard way
	self:Delay(50, function()
		if not self.DescentStarted then
			self.DescentStarted = true
			self.S.ObjectiveService:Fail("StartDescent", "The crew had to do it")
			self.S.FlightService:SetDescent(12000, 250)
			self:Crew("I've started the descent myself! Hold on!")
			self:AdjustLanding(-8, "Descent started late")
		end
	end)
end

function Depressurization:Final()
	if self.PilotsRevived == 0 then
		self.Ctx.Flags.ManualApproach = true
		self.Ctx.Flags.GearMethod = "Lever"
		self:Crew("The pilots are still out cold. Someone has to fly us in - take the left seat!")
	end
	if self.S.OxygenSystem:IsActive() and self.S.FlightService:Get("Altitude") < 14000 then
		self.S.OxygenSystem:End()
		self.S.NPCService:SetMasks(false)
		self.S.ObjectiveService:Remove("UseMasks")
	end
end

function Depressurization:RevealDetail(): string?
	return self.Detail
		or (if self.Cause == "Outflow" then "The outflow valve jammed open" else "Door " .. self.LeakExit.Id .. "'s seal failed") .. " - the leak was never found."
end

function Depressurization:Cleanup()
	self.S.FlightService:SetModifier("RapidDive", nil)
end

return Depressurization
