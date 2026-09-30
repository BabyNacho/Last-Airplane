--[[
	SEVERE TURBULENCE
	Light -> moderate -> severe. Unbuckled players stumble and get hurt; bins pop open and drop
	luggage; galley carts break loose. Players buckle in, secure carts, close bins and reset the
	tripped yaw damper in the avionics bay (walking there in severe turbulence is BRAVE).
	Decision (vote): CLIMB above the storm (turbulence ends fast, but a pressure hiccup drops the
	masks) or DESCEND below it (no pressure risk, but it keeps shaking and the landing is gusty).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local DisasterBase = require(script.Parent.DisasterBase)

local Turbulence = DisasterBase.extend("Turbulence")

function Turbulence:Setup()
	self.Choice = nil
	self.Gusts = self.Rng:NextNumber(2.1, 2.7)
end

function Turbulence:Clues()
	self:Flight("Weather", "Cloudy")
	self:Delay(4, function()
		self.Ctx.Flags.KeepSeatbeltSign = true
		self:Flight("SeatbeltSign", true)
		self:Sound("SeatbeltChime")
		self:Captain("Ladies and gentlemen, the captain has turned on the seatbelt sign. We're expecting a few bumps ahead.")
	end)
	self:Delay(9, function()
		self.S.TurbulenceSystem:SetStage(self.Ctx, 1)
		self:React("Nervous", 0.2)
	end)
end

function Turbulence:UpdateBinGoal()
	local objective = self.S.ObjectiveService:Get("CloseBins")
	if objective and self:IsActiveObjective("CloseBins") then
		local open = self.S.CabinService:OpenBinCount()
		self.S.ObjectiveService:SetGoal("CloseBins", math.max(1, objective.Progress + open))
	end
end

function Turbulence:Start()
	local turbulence = self.S.TurbulenceSystem
	turbulence:SetStage(self.Ctx, 2)
	self:Flight("Weather", "Storm")
	self:Sound("BigImpact")
	self:Shake(1.6, 1.5)
	turbulence:Impact(self.Ctx, 1.6, 10)
	self:Warn("TURBULENCE", "Return to your seat immediately", "danger")
	self:React("Panic", 0.4)
	self:InjurePassengers(self.Rng:NextInteger(1, 3), "Thrown from their seat")
	self:Delay(2, function()
		self:Crew("Everyone sit down and buckle up! Now!")
	end)

	-- galley carts break loose
	for _, cart in self:Point("Carts") do
		self.S.CabinService:ReleaseCart(self.Ctx, cart)
	end
	self:Objective({
		Id = "SecureCarts",
		Text = "Secure the runaway galley carts",
		Kind = Enums.ObjectiveKind.Critical,
		Goal = #self:Point("Carts"),
		Location = self:Point("Carts")[1],
		Hint = "Aft galley - they hurt anyone they hit",
	})
	-- pop a few bins immediately so the objective is visible
	for _ = 1, 3 do
		local lid = self:Point("Bins")[self.Rng:NextInteger(1, #self:Point("Bins"))]
		self.S.CabinService:OpenBin(self.Ctx, lid, true)
	end
	self:Objective({
		Id = "CloseBins",
		Text = "Close the open overhead bins",
		Kind = Enums.ObjectiveKind.Optional,
		Goal = 3,
		Hint = "Falling luggage injures people below",
	})
	self.Ctx:Give(self.S.TurbulenceSystem.Jolted:Connect(function()
		self:UpdateBinGoal()
	end))
	self:Objective({
		Id = "SeatEveryone",
		Text = "Get everyone buckled in",
		Kind = Enums.ObjectiveKind.Optional,
		Goal = math.max(1, self.Ctx:AliveCount()),
	})
	self:Every(1, function()
		if not self:IsActiveObjective("SeatEveryone") then
			return false
		end
		local alive = self.Ctx:AlivePlayers()
		self.S.ObjectiveService:SetGoal("SeatEveryone", math.max(1, #alive))
		self.S.ObjectiveService:SetProgress("SeatEveryone", #self.S.CabinService:SeatedParticipants(self.Ctx))
		self:UpdateBinGoal()
		return self:Phase() ~= Enums.Phase.FinalEvent
	end)
end

function Turbulence:Crisis()
	local flight = self.S.FlightService
	self.S.TurbulenceSystem:SetStage(self.Ctx, 3)
	self:Warn("SEVERE TURBULENCE", "Structural loads exceeded - YAW DAMPER FAULT", "danger")
	self:Shake(2.2, 2)
	flight:SetModifier("YawDamper", -15)
	self:Panel("Avionics", "fail")
	self:InjurePassengers(1, "Hit by falling luggage")
	self.S.MapService:SetDividerOpen("ServiceDoor", true)
	self:Captain("The yaw damper tripped - that's making this much worse. Someone reset it in the avionics bay at the back. Be careful!")
	self:Objective({
		Id = "YawDamper",
		Text = "Reset the yaw damper in the avionics bay",
		Kind = Enums.ObjectiveKind.Critical,
		Location = self:Point("Avionics"),
		Hint = "Back wall of the service bay - hold on to something",
	})
	self:RepairPrompt(self:Point("Avionics"), {
		Objective = "YawDamper",
		Action = "RESET",
		Object = "YAW DAMPER",
		Hold = 3.5,
		Panel = "Avionics",
		OnDone = function(player)
			flight:SetModifier("YawDamper", nil)
			self.S.TurbulenceSystem:SetStage(self.Ctx, self.S.TurbulenceSystem:GetStage(), { DamageScale = 0.5 })
			self:Notify("Yaw damper reset - the aircraft steadies.", "good")
			if self.S.TurbulenceSystem:GetStage() >= 3 then
				self.S.ConditionService:MarkHazard(player, 1)
			end
		end,
	})
	self:Delay(12, function()
		self:Vote({
			Id = "ClimbOrDescend",
			Title = "CLIMB OR DESCEND?",
			Speaker = "Captain",
			Prompt = "I can climb above this storm or drop below it. Your call - quickly!",
			Duration = 15,
			Default = "Descend",
			Options = {
				{ Id = "Climb", Label = "CLIMB ABOVE IT", Description = "Turbulence ends fast. Risk: a pressure surge may drop the oxygen masks.", Risk = "medium" },
				{ Id = "Descend", Label = "DESCEND BELOW IT", Description = "No pressure risk, but the shaking continues and the landing gets gusty.", Risk = "medium" },
			},
			OnResolve = function(choice)
				self.Choice = choice
				if choice == "Climb" then
					self:Climb()
				else
					self:Descend()
				end
			end,
		})
	end)
end

function Turbulence:Climb()
	self:Captain("Climbing. Hold on!")
	self.S.FlightService:SetDescent(38000, 40)
	self:Delay(10, function()
		-- pressure surge during the climb
		self:Sound("Decompression")
		self:Warn("CABIN ALTITUDE", "Pressure surge - masks deployed", "danger")
		self.S.OxygenSystem:Begin(self.Ctx, { DrainScale = 0.7, IgnoreAltitude = true })
		self.S.NPCService:SetMasks(true)
		self:Objective({
			Id = "UseMasks",
			Text = "Put on an oxygen mask",
			Kind = Enums.ObjectiveKind.Optional,
			Goal = math.max(1, self.Ctx:AliveCount()),
		})
		self:Delay(28, function()
			self.S.OxygenSystem:End()
			self.S.NPCService:SetMasks(false)
			self.S.MapService:DeployMasks(false)
			self.S.ObjectiveService:Remove("UseMasks")
			self:Notify("Cabin pressure stable again.", "good")
		end)
	end)
	self:Delay(22, function()
		self.S.TurbulenceSystem:SetStage(self.Ctx, 1)
		self:Flight("Weather", "Cloudy")
		self:Outcome("ClimbOrDescend", "Climbing out of the storm ended the turbulence, at the cost of a pressure scare.", true)
		self:AdjustLanding(4, "Smooth air above the storm")
	end)
	self:Delay(40, function()
		self.S.TurbulenceSystem:SetStage(self.Ctx, 0)
	end)
end

function Turbulence:Descend()
	self:Captain("Descending below the weather. It's going to stay bumpy - stay seated.")
	self.S.TurbulenceSystem:SetStage(self.Ctx, 2)
	self:AdjustLanding(-10, "Gusty crosswind below the storm")
	self:Outcome("ClimbOrDescend", "Descending avoided pressure trouble, but the shaking continued into a gusty landing.", nil)
end

function Turbulence:Final()
	if self.Choice ~= "Climb" then
		self.S.TurbulenceSystem:SetStage(self.Ctx, 1, { Bins = false, Carts = false })
	else
		self.S.TurbulenceSystem:SetStage(self.Ctx, 0)
	end
end

function Turbulence:RevealDetail(): string?
	return string.format("Clear-air turbulence over the ocean with gusts up to %.1f G.", self.Gusts)
end

function Turbulence:Cleanup()
	self.S.FlightService:SetModifier("YawDamper", nil)
end

return Turbulence
