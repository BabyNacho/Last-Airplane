--[[
	LIGHTNING STRIKE
	Clues: the sky darkens, distant flashes and thunder, rain on the windows, static in the
	captain's announcements.
	Event: a direct strike - flash, blackout, instruments dead, autopilot disconnected.
	Players: reset the three tripped electrical buses in different parts of the aircraft
	(co-op: split up!), pull the fuses on sparking wiring, help passengers.
	Decision (vote, once all buses are reset): RESTART NOW (power and autopilot back immediately,
	but while the storm is still strong a surge can knock everything out again) or WAIT for the
	storm cell to pass (safe restart later, the aircraft stays hand-flown and unstable meanwhile).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local Util = require(ReplicatedStorage.Shared.Util)
local DisasterBase = require(script.Parent.DisasterBase)

local LightningStorm = DisasterBase.extend("LightningStorm")

local BUSES = {
	{ Key = "ElectricalPanel", Name = "MAIN BUS 1" },
	{ Key = "EnginePanel", Name = "GENERATOR BUS 2" },
	{ Key = "Avionics", Name = "AVIONICS BUS 3" },
}

function LightningStorm:Setup()
	self.StrikeSide = if self.Rng:NextNumber() < 0.5 then "left" else "right"
	self.BusesReset = {}
	self.PowerRestored = false
	self.StormStrength = 2
	self.Sparking = {}
end

function LightningStorm:Strike(big: boolean)
	self:Effect("Lightning", { Big = big })
	self:Sound(if big then "Thunder" else "ThunderDistant")
	if big then
		self:Shake(2, 1.4)
	end
end

function LightningStorm:Clues()
	self:Flight("Weather", "Storm")
	self:Flight("Storm", 1)
	self:Every({ 6, 10 }, function()
		if self:Phase() ~= Enums.Phase.Flight then
			return false
		end
		self:Strike(false)
		return true
	end)
	self:Delay(6, function()
		self:Captain("Folks, we're... *krrzzt* ...around some weather... *krrzzt* ...seatbelts...", true)
		self.Ctx.Flags.KeepSeatbeltSign = true
		self:Flight("SeatbeltSign", true)
	end)
	self:Delay(12, function()
		self:React("Nervous", 0.25)
		self.S.FlightService:SetLights(Enums.Lights.Flicker)
		self:Delay(1.5, function()
			if self:Phase() == Enums.Phase.Flight then
				self.S.FlightService:SetLights(Enums.Lights.Normal)
			end
		end)
	end)
end

function LightningStorm:Start()
	local flight = self.S.FlightService
	self:Flight("Storm", 2)
	self:Strike(true)
	self:Effect("Flash", { Color = Color3.new(1, 1, 1), Duration = 0.5 })
	self.S.TurbulenceSystem:Impact(self.Ctx, 2, 5)
	self.S.TurbulenceSystem:SetStage(self.Ctx, 1, { Bins = false, Carts = false })
	self:Flight("MainPower", false)
	self:Flight("Autopilot", false)
	self:Flight("InstrumentsFailed", true)
	flight:SetLights(Enums.Lights.Off)
	flight:SetModifier("CaptainHandFlying", 14)
	self:Sound("PowerDown")
	self:Delay(1.5, function()
		flight:SetLights(Enums.Lights.Emergency)
	end)
	self:Warn("ELECTRICAL FAILURE", "ALL MAIN BUSES OFFLINE", "danger")
	self:React("Panic", 0.5)
	self:InjurePassengers(1, "Hit their head in the jolt")
	for _, bus in BUSES do
		self:Panel(bus.Key, "fail")
	end
	self.S.MapService:SetDividerOpen("ServiceDoor", true)
	self:Delay(5, function()
		self:Captain("We took a direct strike. I'm hand-flying on standby instruments. I need all three electrical buses reset - two in the service bay, one at the avionics rack. Split up!")
	end)

	self:Objective({
		Id = "ResetBuses",
		Text = "Reset the tripped electrical buses",
		Kind = Enums.ObjectiveKind.Critical,
		Goal = #BUSES,
		Location = self:Point(BUSES[1].Key),
		Hint = "Electrical panel, engine/APU panel and avionics rack - service bay",
	})
	for _, bus in BUSES do
		self:Prompt(self:Point(bus.Key), {
			Action = "RESET",
			Object = bus.Name,
			Hold = 3,
			Range = 8,
			Kind = "objective",
			Condition = function()
				return not self.BusesReset[bus.Key] and not self.PowerRestored
			end,
			OnTrigger = function(player)
				self:OnBusReset(bus, player)
			end,
		})
	end

	-- sparking wiring hazards in the cabin
	local cells = Util.Shuffle(self.Rng, self:Point("FireCells"))
	local picked = 0
	for _, cell in cells do
		local section = cell:GetAttribute("Section")
		if picked < 2 and (section == "Economy" or section == "FirstClass") then
			picked += 1
			self:AddSparkHazard(cell, picked)
		end
	end
end

function LightningStorm:OnBusReset(bus, player: Player)
	self.BusesReset[bus.Key] = true
	self:Panel(bus.Key, "warn")
	self:Sound("Button", self:Point(bus.Key).Position)
	local objectiveId = if self.Surged then "ResetBuses2" else "ResetBuses"
	self.S.ObjectiveService:Progress(objectiveId, 1, player)
	-- point the waypoint at the next bus still tripped
	for _, other in BUSES do
		if not self.BusesReset[other.Key] then
			self.S.ObjectiveService:SetLocation(objectiveId, self:Point(other.Key))
			break
		end
	end
	if Util.Count(self.BusesReset) >= #BUSES then
		if self.Surged then
			self:Captain("Buses back. I'm waiting a moment before bringing power up.")
			self:Delay(8, function()
				self:RestorePower(nil)
			end)
		else
			self:OfferRestart()
		end
	end
end

function LightningStorm:AddSparkHazard(cell: BasePart, index: number)
	local anchor = Instance.new("Part")
	anchor.Name = "SparkingWire"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = cell.CFrame + Vector3.new(0, 10.5, 0)
	anchor.Parent = self.S.MapService.Airplane
	self.Ctx:Give(anchor)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.15)
	sparks.Speed = NumberRange.new(8, 14)
	sparks.SpreadAngle = Vector2.new(60, 60)
	sparks.Lifetime = NumberRange.new(0.3, 0.6)
	sparks.Acceleration = Vector3.new(0, -40, 0)
	sparks.Rate = 25
	sparks.EmissionDirection = Enum.NormalId.Bottom
	sparks.Parent = anchor
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(180, 200, 255)
	light.Range = 10
	light.Parent = anchor
	local id = "Sparks" .. index
	self.Sparking[id] = true
	if not self.S.ObjectiveService:Get("PullFuses") then
		self:Objective({
			Id = "PullFuses",
			Text = "Pull the fuses on sparking wiring",
			Kind = Enums.ObjectiveKind.Optional,
			Goal = 2,
			Location = anchor,
			Hint = "Crackling ceiling panels in the cabin - it shocks anyone nearby",
		})
	end
	local handle
	handle = self:Prompt(anchor, {
		Action = "PULL FUSE",
		Object = "SPARKING WIRING",
		Hold = 2,
		Range = 12,
		Kind = "danger",
		OnTrigger = function(player)
			self.Sparking[id] = nil
			sparks.Enabled = false
			light.Enabled = false
			handle:SetEnabled(false)
			self.S.ConditionService:MarkHazard(player, 1)
			self.S.ObjectiveService:Progress("PullFuses", 1, player)
		end,
	})
	self:Every(2.5, function()
		if not self.Sparking[id] then
			return false
		end
		for _, player in self:PlayersNear(anchor.Position - Vector3.new(0, 7, 0), 6) do
			self.S.ConditionService:Damage(player, 7, "Electrocuted by sparking wiring")
		end
		return true
	end)
end

function LightningStorm:OfferRestart()
	if self.RestartOffered then
		return
	end
	self.RestartOffered = true
	self:Vote({
		Id = "ElectricalRestart",
		Title = "RESTART ELECTRICAL SYSTEM NOW?",
		Speaker = "Captain",
		Prompt = "Buses are reset. If we restart inside the storm, another strike could surge the system.",
		Duration = 14,
		Default = "Wait",
		Options = {
			{ Id = "Now", Label = "RESTART NOW", Description = "Power and autopilot back immediately. Risk: a surge knocks everything out again.", Risk = "high" },
			{ Id = "Wait", Label = "WAIT FOR THE STORM", Description = "Safe restart in ~35 seconds. The aircraft stays unstable until then.", Risk = "low" },
		},
		OnResolve = function(choice)
			if choice == "Now" then
				local surgeChance = if self.StormStrength >= 2 then 0.5 else 0.2
				if self.Rng:NextNumber() < surgeChance then
					self:Surge()
				else
					self:RestorePower("Restarting early worked - power and autopilot restored immediately.")
					self:AdjustLanding(8, "Early electrical restart")
				end
			else
				self:Captain("Holding off until we're clear of the cell. Hang in there.")
				self:Delay(35, function()
					self.StormStrength = 1
					self:Flight("Storm", 1)
					self:RestorePower("Waiting for the storm to pass made the restart safe, but cost valuable time.")
					self:AdjustLanding(3, "Safe electrical restart")
				end)
			end
		end,
	})
end

function LightningStorm:Surge()
	self.Surged = true
	self:Strike(true)
	self:Effect("Flash", { Color = Color3.fromRGB(200, 220, 255), Duration = 0.6 })
	self:Sound("Sparks")
	self.S.FlightService:SetLights(Enums.Lights.Off)
	self:Delay(1, function()
		self.S.FlightService:SetLights(Enums.Lights.Emergency)
	end)
	self:Warn("POWER SURGE", "BUSES TRIPPED AGAIN", "danger")
	local panel = self:Point("ElectricalPanel")
	self:Effect("Sparks", { Position = panel.Position })
	for _, player in self:PlayersNear(panel.Position, 10) do
		self.S.ConditionService:Damage(player, 20, "Caught in an electrical surge")
	end
	local cell = self.S.FireSystem:CellNear(panel.Position)
	if cell then
		self.S.FireSystem:Ignite(cell, 35)
		self:Objective({
			Id = "ExtinguishFires",
			Text = "Put out the electrical fire",
			Kind = Enums.ObjectiveKind.Critical,
			Goal = 1,
			Location = cell.Part,
			Hint = "Service bay extinguisher is right there",
		})
	end
	-- two of the buses need resetting again
	self.BusesReset = {}
	self.BusesReset[BUSES[self.Rng:NextInteger(1, #BUSES)].Key] = true
	for _, bus in BUSES do
		self:Panel(bus.Key, if self.BusesReset[bus.Key] then "warn" else "fail")
	end
	self.S.ObjectiveService:Remove("ResetBuses")
	self:Objective({
		Id = "ResetBuses2",
		Text = "Reset the buses again (carefully this time)",
		Kind = Enums.ObjectiveKind.Critical,
		Goal = 2,
		Location = self:Point("ElectricalPanel"),
	})
	self:AdjustLanding(-6, "Electrical surge")
	self:Outcome("ElectricalRestart", "Restarting inside the storm caused a surge and a small fire.", false)
end

function LightningStorm:RestorePower(outcome: string?)
	if self.PowerRestored then
		return
	end
	self.PowerRestored = true
	local flight = self.S.FlightService
	self:Flight("MainPower", true)
	self:Flight("Autopilot", true)
	self:Flight("InstrumentsFailed", false)
	flight:SetModifier("CaptainHandFlying", nil)
	flight:SetLights(Enums.Lights.Normal)
	for _, bus in BUSES do
		self:Panel(bus.Key, "ok")
	end
	self:Sound("PowerUp")
	self:Warn("POWER RESTORED", "Autopilot engaged", "info")
	self:Captain("We have power and autopilot. Nice work.")
	if outcome then
		self:Outcome("ElectricalRestart", outcome, true)
	end
end

function LightningStorm:Crisis()
	self:Every({ 16, 26 }, function()
		if self:Phase() ~= Enums.Phase.Crisis then
			return false
		end
		self:Strike(self.StormStrength >= 2 and self.Rng:NextNumber() < 0.4)
		if not self.PowerRestored then
			self.S.FlightService:SetLights(Enums.Lights.Flicker)
			self:Delay(1.2, function()
				if not self.PowerRestored then
					self.S.FlightService:SetLights(Enums.Lights.Emergency)
				end
			end)
		end
		return true
	end)
	if not self.PowerRestored then
		self:Captain("I can't hold her steady like this for long. Those buses - now please!")
	end
end

function LightningStorm:Final()
	self.S.TurbulenceSystem:SetStage(self.Ctx, 1, { Bins = false, Carts = false })
	if not self.PowerRestored then
		self:Warn("NO MAIN POWER", "Landing on standby instruments", "danger")
		self:AdjustLanding(-10, "Landed without main power")
	end
end

function LightningStorm:RevealDetail(): string?
	return "Lightning struck the " .. self.StrikeSide .. " wing root; the surge tripped all three main electrical buses."
end

function LightningStorm:Cleanup()
	self.S.FlightService:SetModifier("CaptainHandFlying", nil)
	self:Flight("InstrumentsFailed", false)
end

return LightningStorm
