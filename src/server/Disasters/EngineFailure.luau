--[[
	ENGINE FAILURE
	Clues: vibration, a puff of smoke from one engine, nervous passengers, a reassuring captain.
	Event: the engine flames out - power drops, the aircraft starts sinking.
	Players: diagnose the fault at the aft engine panel, start the APU, help passengers, optionally
	open the fuel crossfeed (improves restart odds for a fuel fault).
	Decision (vote): RESTART NOW (chance of a much better landing, risk of an engine fire)
	vs PREPARE FOR EMERGENCY LANDING (safe, cockpit checklist, but a perfect landing is off the table).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local DisasterBase = require(script.Parent.DisasterBase)

local EngineFailure = DisasterBase.extend("EngineFailure")

local CAUSES = {
	FuelPump = { Name = "Fuel pump failure", Base = 0.35, CrossfeedBonus = 0.35 },
	CompressorStall = { Name = "Compressor stall", Base = 0.55, CrossfeedBonus = 0 },
}

function EngineFailure:Setup()
	self.Side = if self.Rng:NextNumber() < 0.5 then -1 else 1
	self.EngineKey = if self.Side < 0 then "EngineL" else "EngineR"
	self.EngineName = if self.Side < 0 then "ENGINE 1 (LEFT)" else "ENGINE 2 (RIGHT)"
	self.CauseKey = if self.Rng:NextNumber() < 0.5 then "FuelPump" else "CompressorStall"
	self.Diagnosed = false
	self.Crossfeed = false
	self.ApuRunning = false
	self.Decided = false
end

function EngineFailure:Clues()
	self:Effect("EngineWobble", { Side = self.Side, Duration = 6 })
	self:Shake(0.18, 3)
	self:Delay(7, function()
		self:Effect("EngineSmoke", { Side = self.Side, Duration = 5 })
		self:Sound("Creak")
	end)
	self:Delay(11, function()
		self:React("Nervous", 0.25)
	end)
	self:Delay(15, function()
		self:Captain("Folks, you may feel a little vibration. We're keeping an eye on it - nothing to worry about.")
	end)
end

function EngineFailure:Start()
	local flight = self.S.FlightService
	self:Sound("BigImpact")
	self:Shake(1.8, 2)
	self:Flight(self.EngineKey, 0)
	self:Flight(if self.Side < 0 then "EngineFireL" else "EngineFireR", true)
	self:Effect("EngineFlameout", { Side = self.Side })
	self:Delay(7, function()
		if not self.EngineFireLit then
			self:Flight(if self.Side < 0 then "EngineFireL" else "EngineFireR", false)
		end
	end)
	self:Flight("MainPower", false)
	flight:SetLights(Enums.Lights.Flicker)
	self:Delay(3, function()
		if not self.ApuRunning then
			flight:SetLights(Enums.Lights.Dim)
		end
	end)
	flight:SetModifier("PowerLoss", -8)
	self:Flight("SeatbeltSign", true)
	self:Flight("CockpitAlarm", true)
	self:Warn("MASTER CAUTION", self.EngineName .. " - N1 ZERO", "danger")
	self:Panel("EnginePanel", "fail")
	self:Panel("ElectricalPanel", "warn")
	self:React("Panic", 0.5)
	self.S.TurbulenceSystem:Impact(self.Ctx, 1.4, 6)
	self:InjurePassengers(self.Rng:NextInteger(1, 2), "Hurt in the jolt")

	self:Delay(4, function()
		self:Captain("We've lost an engine. We can fly on one, but I need help back there. Someone check the engine control panel in the service bay - and get the APU running for power.")
	end)

	self:Objective({
		Id = "CheckEngine",
		Text = "Check engine systems at the aft engine panel",
		Kind = Enums.ObjectiveKind.Critical,
		Location = self:Point("EnginePanel"),
		Hint = "Service bay, rear of the aircraft",
	})
	self:RepairPrompt(self:Point("EnginePanel"), {
		Objective = "CheckEngine",
		Action = "RUN DIAGNOSTIC",
		Object = "ENGINE CONTROL",
		Hold = 3,
		OnDone = function(player)
			self:Diagnose(player)
		end,
	})

	self:Objective({
		Id = "StartAPU",
		Text = "Start the APU to restore emergency power",
		Kind = Enums.ObjectiveKind.Critical,
		Location = self:Point("ElectricalPanel"),
		Hint = "Electrical panel, service bay",
	})
	self:RepairPrompt(self:Point("ElectricalPanel"), {
		Objective = "StartAPU",
		Action = "START APU",
		Object = "AUXILIARY POWER",
		Hold = 4,
		Panel = "ElectricalPanel",
		OnDone = function()
			self.ApuRunning = true
			self:Flight("MainPower", true)
			flight:SetLights(Enums.Lights.Normal)
			flight:SetModifier("PowerLoss", nil)
			self:Sound("PowerUp")
			self:Notify("APU running - emergency power restored.", "good")
		end,
	})
	-- open the service bay for the crew
	self.S.MapService:SetDividerOpen("ServiceDoor", true)
end

function EngineFailure:Diagnose(player: Player?)
	self.Diagnosed = true
	local cause = CAUSES[self.CauseKey]
	self.Detail = self.EngineName .. " flamed out - " .. string.lower(cause.Name) .. "."
	self:Warn("DIAGNOSIS", string.upper(cause.Name), "info")
	self:Panel("EnginePanel", "warn")
	if player then
		self:Notify("Diagnostic complete: " .. cause.Name, "good", player)
	end
	if self.CauseKey == "FuelPump" then
		self:Objective({
			Id = "Crossfeed",
			Text = "Open the fuel crossfeed (improves restart odds)",
			Kind = Enums.ObjectiveKind.Optional,
			Location = self:Point("Avionics"),
			Hint = "Avionics bay, back wall of the service area",
		})
		self:RepairPrompt(self:Point("Avionics"), {
			Objective = "Crossfeed",
			Action = "OPEN",
			Object = "FUEL CROSSFEED",
			Hold = 2.5,
			OnDone = function()
				self.Crossfeed = true
				self:Notify("Fuel crossfeed open - fuel reaching the dead engine.", "good")
			end,
		})
	end
	if self:Phase() == Enums.Phase.Crisis then
		self:Delay(4, function()
			self:OfferRestart()
		end)
	end
end

function EngineFailure:Crisis()
	self:Captain("We're losing altitude. Decision time, everyone - I can try a restart or we prepare for an emergency landing.")
	if self.Rng:NextNumber() < 0.5 then
		self:Delay(15, function()
			local other = if self.EngineKey == "EngineL" then "EngineR" else "EngineL"
			self:Flight(other, 75)
			self:Effect("EngineWobble", { Side = -self.Side, Duration = 5 })
			self:Warn("CAUTION", "Remaining engine running rough", "warn")
		end)
	end
	-- offer the decision once the fault is understood, or after a while regardless
	if self.Diagnosed then
		self:Delay(8, function()
			self:OfferRestart()
		end)
	else
		self:Delay(28, function()
			self:OfferRestart()
		end)
	end
end

function EngineFailure:RestartChance(): number
	local cause = CAUSES[self.CauseKey]
	local chance = cause.Base
	if self.Crossfeed then
		chance += cause.CrossfeedBonus
	end
	if not self.Diagnosed then
		chance -= 0.15
	end
	if not self.ApuRunning then
		chance *= 0.5
	end
	return math.clamp(chance, 0.05, 0.9)
end

function EngineFailure:OfferRestart()
	if self.Decided or self:Phase() ~= Enums.Phase.Crisis then
		return
	end
	self.Decided = true
	local apuNote = if self.ApuRunning then "" else " WARNING: without the APU there's little bleed air - poor odds."
	self:Vote({
		Id = "EngineRestart",
		Title = "ATTEMPT EMERGENCY RESTART?",
		Speaker = "Captain",
		Prompt = "Restarting could save the landing - or set the engine on fire." .. apuNote,
		Duration = 16,
		Default = "Prepare",
		Options = {
			{ Id = "Restart", Label = "RESTART NOW", Description = "Chance of full power and a smooth landing. Risk: engine fire.", Risk = "high" },
			{ Id = "Prepare", Label = "PREPARE FOR LANDING", Description = "No restart. Safer, but a rougher landing on one engine.", Risk = "low" },
		},
		OnResolve = function(choice)
			if choice == "Restart" then
				self:AttemptRestart()
			else
				self:PrepareLanding()
			end
		end,
	})
end

function EngineFailure:AttemptRestart()
	self:Captain("Attempting restart. Hold on...")
	self:Effect("EngineWobble", { Side = self.Side, Duration = 4 })
	self:Sound("EngineSputter")
	self:Delay(5, function()
		if self.Rng:NextNumber() < self:RestartChance() then
			self:Flight(self.EngineKey, 72)
			self:Flight("CockpitAlarm", false)
			self:Panel("EnginePanel", "ok")
			self:Sound("PowerUp")
			self:Warn("ENGINE RESTARTED", self.EngineName .. " - POWER RESTORED", "info")
			self:Captain("We have the engine back! Great work, everyone.")
			self:React("Relief", 0.4)
			self:AdjustLanding(12, "Engine restarted")
			self:Outcome("EngineRestart", "The restart worked - engine power restored.", true)
		else
			self:EngineFire()
			self:AdjustLanding(-8, "Failed restart")
			self:Outcome("EngineRestart", "The restart failed and the engine caught fire.", false)
		end
	end)
end

function EngineFailure:EngineFire()
	self.EngineFireLit = true
	self.Ctx.Flags.HazardSide = self.Side
	self:Flight(if self.Side < 0 then "EngineFireL" else "EngineFireR", true)
	self:Sound("BigImpact")
	self:Shake(1.4, 1.5)
	self:Flight("FireAlarmActive", true)
	self:Warn("ENGINE FIRE", self.EngineName, "danger")
	self:React("Panic", 0.6)
	self.S.CockpitSystem:Unlock(true)
	self:Captain("ENGINE FIRE! I can't leave the controls - someone get up here and pull the fire handle! The door is open!")
	self:Objective({
		Id = "FireHandle",
		Text = "Pull the engine fire handle in the cockpit",
		Kind = Enums.ObjectiveKind.Critical,
		Location = self:Point("FireHandles"),
		Hint = "Red handles on the cockpit ceiling panel",
	})
	self:RepairPrompt(self:Point("FireHandles"), {
		Objective = "FireHandle",
		Action = "PULL",
		Object = "ENGINE FIRE HANDLE",
		Hold = 1.5,
		Kind = "danger",
		OnDone = function()
			self.EngineFireLit = false
			self.Ctx.Flags.HazardSide = nil
			self:Flight(if self.Side < 0 then "EngineFireL" else "EngineFireR", false)
			self:Flight("FireAlarmActive", false)
			self:Warn("FIRE OUT", "Extinguisher bottles discharged", "info")
			self:Captain("Fire's out. Thank you. Now let's get this thing on the ground.")
		end,
	})
	-- left burning, the fire works its way into the cabin
	self:Delay(40, function()
		if self.EngineFireLit then
			self:Warn("FIRE SPREADING", "Flames entering the cabin", "danger")
			local cell = self.S.FireSystem:NearestCell(Vector3.new(-2, 0, self.Side * 6))
			if cell then
				self.S.FireSystem:Ignite(cell, 50)
			end
			self:AdjustLanding(-10, "Engine fire reached the cabin")
			self:Objective({
				Id = "ExtinguishFires",
				Text = "Put out the fire in the cabin",
				Kind = Enums.ObjectiveKind.Critical,
				Goal = 1,
				Hint = "Grab a fire extinguisher",
			})
		end
	end)
end

function EngineFailure:PrepareLanding()
	self.MaxScore = 80 -- one engine, heavy aircraft: a perfect landing is no longer possible
	self:Captain("Understood. No restart. I need a second pair of hands up front to run the emergency checklist - I'm unlocking the door.")
	self.S.CockpitSystem:Unlock(false)
	self:AdjustLanding(6, "Crew prepared for a single-engine landing")
	self:Outcome("EngineRestart", "The crew prepared for a single-engine landing instead of risking a restart.", true)
	self:Objective({
		Id = "Checklist",
		Text = "Run the emergency checklist in the cockpit",
		Kind = Enums.ObjectiveKind.Critical,
		Location = self:Point("Throttle"),
		Hint = "Centre pedestal between the pilot seats",
	})
	self:RepairPrompt(self:Point("Throttle"), {
		Objective = "Checklist",
		Action = "RUN CHECKLIST",
		Object = "SINGLE ENGINE PROCEDURE",
		Hold = 5,
		OnDone = function()
			self:AdjustLanding(6, "Single-engine checklist complete")
			self.S.FlightService:SetModifier("Checklist", 6)
			self:Captain("Checklist complete. Thank you - we're set up for landing.")
		end,
	})
end

function EngineFailure:Final()
	if self.EngineFireLit then
		self:Warn("ENGINE STILL BURNING", "Pull the fire handle!", "danger")
	end
end

function EngineFailure:NeedsEvacuation(): boolean
	return self.EngineFireLit == true or self.S.FireSystem:ActiveCount() > 0
end

function EngineFailure:RevealDetail(): string?
	return self.Detail or (self.EngineName .. " flamed out - " .. string.lower(CAUSES[self.CauseKey].Name) .. " (never diagnosed).")
end

function EngineFailure:Cleanup()
	self.S.FlightService:SetModifier("PowerLoss", nil)
	self.S.FlightService:SetModifier("Checklist", nil)
end

return EngineFailure
