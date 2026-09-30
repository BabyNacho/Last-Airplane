--[[
	BLIND APPROACH (Navigation Failure)
	Clues: thickening fog outside, navigation displays glitching, the captain mentions fog at the
	destination.
	Event: both navigation computers crash while the destination is fogged in.
	Players: reboot the nav computer in the avionics bay, re-align the inertial reference in the
	cockpit, and - the unique part - WATCH THE WINDOWS: runway approach lights flash through gaps
	in the fog on one side of the aircraft. Report the correct side at the overwing windows to
	guide the captain (wrong calls make it worse).
	Decision (vote): HOLD until the fog lifts (clearer approach, but the fuel may run critically
	low) or APPROACH NOW (no fuel risk, land in thick fog).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local DisasterBase = require(script.Parent.DisasterBase)

local NavigationFailure = DisasterBase.extend("NavigationFailure")

function NavigationFailure:Setup()
	self.NavRebooted = false
	self.Aligned = false
	self.Sightings = 0
	self.Correct = 0
	self.CurrentSide = 0
	self.Reported = false
end

function NavigationFailure:Clues()
	self:Flight("Weather", "Fog")
	self:Every(2, function()
		if self:Phase() ~= Enums.Phase.Flight then
			return false
		end
		self:Flight("Visibility", math.max(0.45, self:Flight("Visibility") - 0.05))
		return true
	end)
	self:Delay(6, function()
		self:Effect("InstrumentGlitch", { Duration = 3 })
	end)
	self:Delay(12, function()
		self:Captain("Destination is reporting thick fog. Might be a bit of a tricky approach, but nothing we can't handle.")
	end)
end

function NavigationFailure:Start()
	local flight = self.S.FlightService
	self:Sound("PowerDown")
	self:Effect("InstrumentGlitch", { Duration = 6 })
	self:Flight("Visibility", 0.3)
	self:Flight("NavFailed", true)
	self:Flight("CockpitAlarm", true)
	flight:SetModifier("NavLost", -14)
	self:Panel("Avionics", "fail")
	self:Panel("NavPanel", "fail")
	self:Warn("NAV FAIL", "GPS / ILS LOST - POSITION UNKNOWN", "danger")
	self:React("Nervous", 0.4)
	self.S.MapService:SetDividerOpen("ServiceDoor", true)
	self:Delay(4, function()
		self:Captain("We've lost both nav computers and I can't see a thing. Reboot the nav computer in the avionics bay. And everyone - keep your eyes on the windows for runway lights.")
	end)
	self:Objective({
		Id = "RebootNav",
		Text = "Reboot the navigation computer",
		Kind = Enums.ObjectiveKind.Critical,
		Location = self:Point("Avionics"),
		Hint = "Avionics rack, back of the service bay",
	})
	self:RepairPrompt(self:Point("Avionics"), {
		Objective = "RebootNav",
		Action = "REBOOT",
		Object = "NAV COMPUTER",
		Hold = 5,
		Panel = "Avionics",
		OnDone = function()
			self.NavRebooted = true
			self.S.CockpitSystem:Unlock(false)
			self:Captain("Nav computer is booting. Someone come up and re-align the inertial reference - door's unlocked.")
			self:Objective({
				Id = "AlignIRS",
				Text = "Re-align the inertial reference (cockpit NAV panel)",
				Kind = Enums.ObjectiveKind.Critical,
				Location = self:Point("NavPanel"),
			})
			self:RepairPrompt(self:Point("NavPanel"), {
				Objective = "AlignIRS",
				Action = "ALIGN",
				Object = "INERTIAL REFERENCE",
				Hold = 3,
				Panel = "NavPanel",
				OnDone = function()
					self.Aligned = true
					self:Flight("NavFailed", false)
					self.S.FlightService:SetModifier("NavLost", nil)
					self:Warn("NAV RESTORED", "Position fixed", "info")
					self:AdjustLanding(8, "Navigation restored")
				end,
			})
		end,
	})
	self:InjurePassengers(1, "Fainted from the panic")
end

-- runway light sighting mini-game
function NavigationFailure:SetupReporting()
	self:Objective({
		Id = "SpotRunway",
		Text = "Spot the runway lights and report which side",
		Kind = Enums.ObjectiveKind.Critical,
		Goal = 3,
		Hint = "Lights flash through the fog on ONE side - report at the overwing windows",
	})
	for _, info in { { Key = "InspectLeft", Side = -1, Label = "LEFT" }, { Key = "InspectRight", Side = 1, Label = "RIGHT" } } do
		self:Prompt(self:Point(info.Key), {
			Action = "REPORT LIGHTS",
			Object = info.Label .. " SIDE",
			Hold = 0.5,
			Range = 9,
			Kind = "decision",
			Condition = function()
				if self.CurrentSide == 0 then
					return false, "No lights visible right now - keep watching."
				end
				return not self.Reported
			end,
			OnTrigger = function(player)
				self.Reported = true
				self.Ctx:Add(player, "DecisionsCount")
				if info.Side == self.CurrentSide then
					self.Correct += 1
					self.S.ObjectiveService:Progress("SpotRunway", 1, player)
					self:AdjustLanding(5, nil)
					self:Captain("Got it - I see them on the " .. string.lower(info.Label) .. "! Correcting.")
					self:Notify(player.DisplayName .. " spotted the runway lights!", "good")
				else
					self:AdjustLanding(-4, nil)
					self:Captain("Negative, nothing on the " .. string.lower(info.Label) .. "! We're drifting the wrong way!")
					self:Notify(player.DisplayName .. " called the wrong side!", "danger")
				end
			end,
		})
	end
	self:Every({ 14, 20 }, function()
		if self:Phase() ~= Enums.Phase.Crisis and self:Phase() ~= Enums.Phase.FinalEvent then
			return false
		end
		if self.S.ObjectiveService:IsComplete("SpotRunway") then
			return false
		end
		self.Sightings += 1
		self.CurrentSide = if self.Rng:NextNumber() < 0.5 then -1 else 1
		self.Reported = false
		self:Flight("RunwaySide", self.CurrentSide)
		self:Notify("Something flickers through the fog...", "info")
		self:Delay(9, function()
			self.CurrentSide = 0
			self:Flight("RunwaySide", 0)
		end)
		return true
	end)
end

function NavigationFailure:Crisis()
	self:SetupReporting()
	self:Delay(10, function()
		self:Vote({
			Id = "HoldOrApproach",
			Title = "HOLD OR APPROACH?",
			Speaker = "Captain",
			Prompt = "We can circle until the fog thins, but fuel is getting tight.",
			Duration = 15,
			Default = "Approach",
			Options = {
				{ Id = "Hold", Label = "HOLD FOR THE FOG", Description = "Clearer approach. Risk: fuel runs critically low.", Risk = "high" },
				{ Id = "Approach", Label = "APPROACH NOW", Description = "No fuel risk. Land in thick fog.", Risk = "medium" },
			},
			OnResolve = function(choice)
				if choice == "Hold" then
					self.S.RoundService:AdjustPhaseEnd(20)
					self:Captain("Entering the hold. Fingers crossed.")
					self:Delay(18, function()
						self:Flight("Visibility", 0.7)
						self:AdjustLanding(10, "The fog lifted")
						if self.Rng:NextNumber() < 0.35 then
							self.FuelScare = true
							self:Flight("EngineR", 0)
							self:Warn("FUEL LOW", "ENGINE 2 FLAMEOUT - FUEL STARVATION", "danger")
							self:AdjustLanding(-14, "Ran an engine dry holding for the fog")
							self:Outcome("HoldOrApproach", "The fog lifted, but holding ran an engine out of fuel.", false)
						else
							self:Outcome("HoldOrApproach", "Holding paid off - the fog lifted with fuel to spare.", true)
						end
					end)
				else
					self:AdjustLanding(if self.Aligned then 0 else -6, "Approach flown in thick fog")
					self:Outcome("HoldOrApproach", "The crew committed to the approach in thick fog.", nil)
				end
			end,
		})
	end)
end

function NavigationFailure:Final()
	if not self.Aligned then
		self:Warn("NO NAVIGATION", "Hand-flown approach in fog", "danger")
	end
end

function NavigationFailure:RevealDetail(): string?
	return string.format("A failed power supply crashed both navigation computers as the destination fogged in. Runway lights called correctly: %d/%d.", self.Correct, self.Sightings)
end

function NavigationFailure:Cleanup()
	self.S.FlightService:SetModifier("NavLost", nil)
	self:Flight("NavFailed", false)
	self:Flight("RunwaySide", 0)
end

return NavigationFailure
