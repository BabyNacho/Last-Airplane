--[[
	BIRD STRIKE
	Clues: a flock of birds visible outside, the captain mentions seabirds, passengers point.
	Event: thump-thump-BANG. Something was hit - but WHAT? The damage is hidden and random:
	  * ENGINE     - one engine runs rough at low power and vibrates.
	  * WINDSHIELD - cracked windshield, the airspeed probe is blocked, instruments unreliable.
	  * WINDOW     - a cabin window is cracked and whistling; left alone it will blow out.
	Players must diagnose: inspect the wings (overwing windows), the cabin windows and the cockpit.
	Each damage type has its own repair and its own decision.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local Util = require(ReplicatedStorage.Shared.Util)
local DisasterBase = require(script.Parent.DisasterBase)

local BirdStrike = DisasterBase.extend("BirdStrike")

function BirdStrike:Setup()
	local roll = self.Rng:NextNumber()
	self.Damage = if roll < 0.4 then "Engine" elseif roll < 0.7 then "Windshield" else "Window"
	self.Side = if self.Rng:NextNumber() < 0.5 then -1 else 1
	self.EngineKey = if self.Side < 0 then "EngineL" else "EngineR"
	self.Found = false
	self.Inspected = {}
	local windows = if self.Side < 0 then self:Point("WindowsLeft") else self:Point("WindowsRight")
	-- pick an economy window away from the doors
	local candidates = {}
	for _, window in windows do
		local x = window:GetAttribute("LocalX")
		if x and x < 30 and x > -36 and math.abs(x + 2) > 4 then
			table.insert(candidates, window)
		end
	end
	self.Window = Util.Pick(self.Rng, candidates)
	if self.Window then
		local best, bestDistance = nil, math.huge
		for _, seat in self:Point("Seats") do
			local distance = (seat.Position - self.Window.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = seat, distance
			end
		end
		self.WindowRow = best and best:GetAttribute("Row")
	end
end

function BirdStrike:Clues()
	self:Flight("Birds", true)
	self:Delay(3, function()
		self:Captain("If you look outside you may spot some seabirds - we're passing a big colony down there.")
	end)
	self:Delay(9, function()
		self:Announce("Passenger", "Whoa, look at all those birds! They're getting really close...")
		self:React("Nervous", 0.2)
	end)
end

function BirdStrike:Start()
	-- impact sequence
	for i = 1, 3 do
		self:Delay((i - 1) * 0.45, function()
			self:Sound(if i == 3 then "BigImpact" else "Impact")
			self:Shake(0.6 + i * 0.4, 0.6)
		end)
	end
	self:Delay(1.5, function()
		self:Flight("Birds", false)
	end)
	self.S.TurbulenceSystem:Impact(self.Ctx, 1.6, 6)
	self:Flight("CockpitAlarm", true)
	self:Warn("IMPACT", "Unknown damage - multiple system cautions", "danger")
	self:React("Panic", 0.5)
	self:InjurePassengers(1, "Cut by flying debris")
	self.Ctx.Flags.KeepSeatbeltSign = true
	self:Flight("SeatbeltSign", true)

	if self.Damage == "Engine" then
		self:Flight(self.EngineKey, 32)
		self:Effect("EngineWobble", { Side = self.Side, Duration = 12 })
		self:Effect("EngineSmoke", { Side = self.Side, Duration = 10 })
		self:Flight(if self.Side < 0 then "EngineSmokeL" else "EngineSmokeR", true)
		self:Every(9, function()
			if self.EngineShutdown or not self.Ctx.Active then
				return false
			end
			self:Shake(0.25, 1.5)
			return true
		end)
	elseif self.Damage == "Windshield" then
		self:Effect("WindshieldCrack", {})
		self:Flight("AirspeedUnreliable", true)
		self.S.FlightService:SetModifier("UnreliableAirspeed", -14)
	elseif self.Damage == "Window" and self.Window then
		self.Window:SetAttribute("Cracked", true)
		self:Sound("GlassCrack", self.Window.Position)
		self:ScheduleBlowout(75)
	end

	self:Delay(4, function()
		self:Captain("We hit birds. I've got cautions everywhere and I don't know what's damaged. I need eyes on it - check the wings through the overwing windows, the cabin windows, and I'm unlocking the cockpit so someone can check up here.")
		self.S.CockpitSystem:Unlock(false)
	end)

	self:Objective({
		Id = "FindDamage",
		Text = "Find the bird strike damage",
		Kind = Enums.ObjectiveKind.Critical,
		Hint = "Inspect: left wing, right wing, cabin windows, cockpit windshield",
	})
	self:InspectPoint(self:Point("InspectLeft"), "LEFT WING", function()
		return self.Damage == "Engine" and self.Side < 0
	end)
	self:InspectPoint(self:Point("InspectRight"), "RIGHT WING", function()
		return self.Damage == "Engine" and self.Side > 0
	end)
	self:InspectPoint(self:Point("InspectCockpit"), "WINDSHIELD", function()
		return self.Damage == "Windshield"
	end)
	if self.Window then
		self:InspectPoint(self.Window, "CABIN WINDOW", function()
			return self.Damage == "Window"
		end)
	end
end

function BirdStrike:InspectPoint(part: BasePart, label: string, isDamage: () -> boolean)
	local handle
	handle = self:Prompt(part, {
		Action = "INSPECT",
		Object = label,
		Hold = 1.5,
		Range = 8,
		Kind = "objective",
		Condition = function()
			return not self.Found and not self.Inspected[label]
		end,
		OnTrigger = function(player)
			self.Inspected[label] = true
			handle:SetEnabled(false)
			if isDamage() then
				self:Found_(player, label)
			else
				self:Notify(label .. ": no damage found.", "info")
			end
		end,
	})
end

function BirdStrike:Found_(player: Player, _label: string)
	self.Found = true
	self:Complete("FindDamage", player)
	if self.Damage == "Engine" then
		local name = if self.Side < 0 then "ENGINE 1" else "ENGINE 2"
		self.Detail = "A bird was ingested into " .. string.lower(name) .. ", damaging the fan blades."
		self:Warn("DAMAGE FOUND", name .. " - FAN BLADE DAMAGE", "warn")
		self:Captain("Damaged engine. It's still turning but it's shaking itself apart. We need to decide what to do with it.")
		self:Delay(3, function()
			self:EngineDecision()
		end)
	elseif self.Damage == "Windshield" then
		self.Detail = "A bird smashed into the windshield and blocked the airspeed probe."
		self:Warn("DAMAGE FOUND", "WINDSHIELD CRACKED - PITOT PROBE BLOCKED", "warn")
		self:Captain("That's why my airspeed is garbage. Switch me to standby air data on the nav panel, quickly.")
		self:Objective({
			Id = "StandbyAir",
			Text = "Switch to standby air data (cockpit NAV panel)",
			Kind = Enums.ObjectiveKind.Critical,
			Location = self:Point("NavPanel"),
		})
		self:RepairPrompt(self:Point("NavPanel"), {
			Objective = "StandbyAir",
			Action = "SWITCH",
			Object = "STANDBY AIR DATA",
			Hold = 2.5,
			Panel = "NavPanel",
			OnDone = function()
				self.S.FlightService:SetModifier("UnreliableAirspeed", nil)
				self:Flight("AirspeedUnreliable", false)
				self:Notify("Standby air data active - speed readings reliable again.", "good")
			end,
		})
		self:Delay(3, function()
			self:WindshieldDecision()
		end)
	else
		self.Detail = "A bird cracked a cabin window at row " .. tostring(self.WindowRow or "?") .. "."
		self:Warn("DAMAGE FOUND", "CABIN WINDOW CRACKED", "danger")
		self:Captain("A cracked window?! Get speed tape from the maintenance kit in the avionics bay and seal it before it blows!")
		self:Objective({
			Id = "SealWindow",
			Text = "Seal the cracked window with speed tape",
			Kind = Enums.ObjectiveKind.Critical,
			Location = self.Window,
			Hint = "Speed tape: maintenance kit in the avionics bay (service bay)",
		})
		self.S.MapService:SetDividerOpen("ServiceDoor", true)
		self.S.EquipmentService:AddPickup(self.Ctx, self:Point("Avionics"), "SpeedTape", 2)
		self:RepairPrompt(self.Window, {
			Objective = "SealWindow",
			Action = "SEAL",
			Object = "CRACKED WINDOW",
			Hold = 3,
			Kind = "danger",
			Condition = function(p)
				if not self.S.EquipmentService:HasTool(p, "SpeedTape") then
					return false, "You need speed tape (maintenance kit, avionics bay)."
				end
				return true
			end,
			OnDone = function()
				self.Sealed = true
				self.Window:SetAttribute("Cracked", false)
				self.Window:SetAttribute("Sealed", true)
				self:Notify("Window sealed. That should hold.", "good")
			end,
		})
		self:Delay(3, function()
			self:WindowDecision()
		end)
	end
end

function BirdStrike:EngineDecision()
	self:Vote({
		Id = "DamagedEngine",
		Title = "SHUT DOWN THE DAMAGED ENGINE?",
		Speaker = "Captain",
		Prompt = "It's giving us some thrust, but it could catch fire.",
		Duration = 15,
		Default = "Shutdown",
		Options = {
			{ Id = "Shutdown", Label = "SHUT IT DOWN", Description = "No fire risk. Rougher one-engine landing.", Risk = "low" },
			{ Id = "Keep", Label = "KEEP IT RUNNING", Description = "Extra thrust for landing. Risk of an engine fire.", Risk = "high" },
		},
		OnResolve = function(choice)
			if choice == "Shutdown" then
				self.EngineShutdown = true
				self:Flight(self.EngineKey, 0)
				self:Flight(if self.Side < 0 then "EngineSmokeL" else "EngineSmokeR", false)
				self.MaxScore = 85
				self:AdjustLanding(-4, "Landing on one engine")
				self:Outcome("DamagedEngine", "The damaged engine was shut down safely.", true)
				self:Objective({
					Id = "FuelValve",
					Text = "Close the damaged engine's fuel valve (engine panel)",
					Kind = Enums.ObjectiveKind.Critical,
					Location = self:Point("EnginePanel"),
				})
				self.S.MapService:SetDividerOpen("ServiceDoor", true)
				self:RepairPrompt(self:Point("EnginePanel"), {
					Objective = "FuelValve",
					Action = "CLOSE",
					Object = "ENGINE FUEL VALVE",
					Hold = 2.5,
					Panel = "EnginePanel",
				})
			else
				self.KeepEngine = true
				self:AdjustLanding(5, "Extra thrust from the damaged engine")
				self:Objective({
					Id = "MonitorEngine",
					Text = "Monitor engine temperatures (engine panel) to reduce fire risk",
					Kind = Enums.ObjectiveKind.Optional,
					Location = self:Point("EnginePanel"),
				})
				self.S.MapService:SetDividerOpen("ServiceDoor", true)
				self:RepairPrompt(self:Point("EnginePanel"), {
					Objective = "MonitorEngine",
					Action = "MONITOR",
					Object = "ENGINE TEMPERATURES",
					Hold = 3,
					OnDone = function()
						self.Monitored = true
						self:Notify("Engine temperatures under control - fire risk reduced.", "good")
					end,
				})
				self:Delay(35, function()
					local chance = if self.Monitored then 0.2 else 0.45
					if self.Rng:NextNumber() < chance then
						self:EngineFire()
					else
						self:Outcome("DamagedEngine", "The damaged engine held together and helped the landing.", true)
					end
				end)
			end
		end,
	})
end

function BirdStrike:EngineFire()
	self.Ctx.Flags.HazardSide = self.Side
	self:Flight(if self.Side < 0 then "EngineFireL" else "EngineFireR", true)
	self:Flight(self.EngineKey, 0)
	self:Sound("BigImpact")
	self:Shake(1.2, 1.2)
	self:Warn("ENGINE FIRE", "Pull the fire handle in the cockpit!", "danger")
	self:AdjustLanding(-12, "Damaged engine caught fire")
	self:Outcome("DamagedEngine", "Keeping the damaged engine running ended in an engine fire.", false)
	self:Objective({
		Id = "FireHandle",
		Text = "Pull the engine fire handle in the cockpit",
		Kind = Enums.ObjectiveKind.Critical,
		Location = self:Point("FireHandles"),
	})
	self:RepairPrompt(self:Point("FireHandles"), {
		Objective = "FireHandle",
		Action = "PULL",
		Object = "ENGINE FIRE HANDLE",
		Hold = 1.5,
		Kind = "danger",
		OnDone = function()
			self.Ctx.Flags.HazardSide = nil
			self:Flight(if self.Side < 0 then "EngineFireL" else "EngineFireR", false)
			self:Warn("FIRE OUT", "Extinguisher discharged", "info")
		end,
	})
end

function BirdStrike:WindshieldDecision()
	self:Vote({
		Id = "Divert",
		Title = "DIVERT TO THE NEAREST AIRPORT?",
		Speaker = "Captain",
		Prompt = "If that windshield lets go we're in trouble. The nearest field is close but short.",
		Duration = 15,
		Default = "Continue",
		Options = {
			{ Id = "Divert", Label = "DIVERT NOW", Description = "Land sooner, less time in danger. Short runway - harder landing.", Risk = "medium" },
			{ Id = "Continue", Label = "CONTINUE", Description = "Long runway. More time for the crack to spread.", Risk = "medium" },
		},
		OnResolve = function(choice)
			if choice == "Divert" then
				self.S.RoundService:AdjustPhaseEnd(-25)
				self:AdjustLanding(-6, "Short runway at the diversion airport")
				self:Outcome("Divert", "The flight diverted to a short runway nearby.", true)
			else
				self:Outcome("Divert", "The flight continued to a long runway.", nil)
				self:Delay(30, function()
					if self.Rng:NextNumber() < 0.5 then
						self:Sound("GlassCrack")
						self:Warn("WINDSHIELD", "Crack spreading - outer ply failed", "danger")
						self:AdjustLanding(-8, "Windshield crack spread")
						self:Outcome("Divert", "Continuing let the windshield crack spread further.", false)
					else
						self:AdjustLanding(4, "Long runway")
						self:Outcome("Divert", "Continuing paid off - the windshield held and the runway was long.", true)
					end
				end)
			end
		end,
	})
end

function BirdStrike:WindowDecision()
	self:Vote({
		Id = "DescendForWindow",
		Title = "DESCEND TO EASE THE PRESSURE?",
		Speaker = "Captain",
		Prompt = "Lower altitude means less stress on that window - but rougher air and more fuel burn.",
		Duration = 14,
		Default = "Descend",
		Options = {
			{ Id = "Descend", Label = "DESCEND NOW", Description = "Window far less likely to blow. Bumpier ride, tighter fuel.", Risk = "low" },
			{ Id = "Stay", Label = "STAY HIGH", Description = "Smooth air, better landing. Seal that window fast!", Risk = "high" },
		},
		OnResolve = function(choice)
			if choice == "Descend" then
				self.Descended = true
				self.S.FlightService:SetDescent(12000, 120)
				self.S.TurbulenceSystem:SetStage(self.Ctx, 1, { Bins = false, Carts = false })
				self:AdjustLanding(-4, "Low-altitude cruise burned extra fuel")
				self:Outcome("DescendForWindow", "Descending took the pressure off the cracked window.", true)
			else
				self:AdjustLanding(3, "Stayed in smooth air")
				self:Outcome("DescendForWindow", "Staying high kept the ride smooth - the window had to be sealed quickly.", nil)
			end
		end,
	})
end

function BirdStrike:ScheduleBlowout(seconds: number)
	self:Delay(seconds, function()
		if self.Sealed or not self.Window then
			return
		end
		if self.Descended and self.Rng:NextNumber() < 0.75 then
			return -- low pressure differential: the crack holds
		end
		self:Blowout()
	end)
	self:Every(8, function()
		if self.Sealed or not self.Window or not self.Ctx.Active then
			return false
		end
		self:Sound("Creak", self.Window.Position)
		return true
	end)
end

function BirdStrike:Blowout()
	local window = self.Window
	window:SetAttribute("Cracked", false)
	window:SetAttribute("Blown", true)
	window.Transparency = 1
	window.CanCollide = true
	self:Sound("Decompression", window.Position)
	self:Effect("Decompression", { Position = window.Position })
	self:Warn("RAPID DECOMPRESSION", "CABIN ALTITUDE - MASKS DEPLOYED", "danger")
	for _, player in self:PlayersNear(window.Position, 10) do
		self.S.ConditionService:Damage(player, 22, "Pulled toward the blown window")
	end
	self.S.OxygenSystem:Begin(self.Ctx)
	self.S.NPCService:SetMasks(true)
	self.S.FlightService:SetDescent(10000, 180)
	self:AdjustLanding(-8, "Window blowout")
	if self.S.ObjectiveService:IsActive("SealWindow") then
		self.S.ObjectiveService:Fail("SealWindow", "The window blew out")
	end
	self:Objective({ Id = "UseMasks", Text = "Put on an oxygen mask", Kind = Enums.ObjectiveKind.Critical, Goal = math.max(1, self.Ctx:AliveCount()) })
	self:Captain("Window's gone! Emergency descent! Masks on, everyone!")
end

function BirdStrike:Crisis()
	if not self.Found then
		self:Captain("We still don't know what's damaged! Check the windows and the cockpit!")
	end
	self:Every(25, function()
		if self:Phase() ~= Enums.Phase.Crisis then
			return false
		end
		self:React("Nervous", 0.2)
		return true
	end)
end

function BirdStrike:Final()
	if not self.Found then
		self:AdjustLanding(-8, "Damage never diagnosed")
	end
	if self.S.OxygenSystem:IsActive() and self.S.FlightService:Get("Altitude") < 14000 then
		self.S.OxygenSystem:End()
		self.S.NPCService:SetMasks(false)
		self.S.ObjectiveService:Remove("UseMasks")
	end
end

function BirdStrike:RevealDetail(): string?
	if self.Detail then
		return self.Detail
	end
	local what = ({ Engine = "an engine", Windshield = "the windshield", Window = "a cabin window" })[self.Damage]
	return "A flock of seabirds hit " .. what .. " - the damage was never found."
end

function BirdStrike:Cleanup()
	self.S.FlightService:SetModifier("UnreliableAirspeed", nil)
	if self.Window then
		self.Window:SetAttribute("Cracked", nil)
		self.Window:SetAttribute("Sealed", nil)
		self.Window:SetAttribute("Blown", nil)
		self.Window.Transparency = 0.55
	end
	self:Flight("AirspeedUnreliable", false)
end

return BirdStrike
