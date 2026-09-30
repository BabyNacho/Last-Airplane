--[[
	CABIN FIRE
	Clues: a faint haze and a chirping smoke detector somewhere in the cabin, flickering lights,
	a passenger asking if anyone smells burning.
	Event: an electrical fault ignites. Fire grows and spreads cell by cell; smoke fills sections.
	Players: grab extinguishers, close cabin doors to contain it, help passengers with smoke
	inhalation, and cut power to the faulty circuit - otherwise it keeps re-igniting.
	Decisions:
	  * Personal at the electrical panel: CUT ALL CABIN POWER (guaranteed, but the cabin goes dark and
	    systems suffer) or ISOLATE one circuit (keeps power - pick the wrong one and it sparks).
	    Working out which circuit feeds the fire's location is the puzzle.
	  * Vote (if the fire is spreading): VENT THE CABIN (starves the fire, but everyone needs masks)
	    or KEEP PRESSURE.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local MapConfig = require(ReplicatedStorage.Shared.Config.MapConfig)
local Util = require(ReplicatedStorage.Shared.Util)
local DisasterBase = require(script.Parent.DisasterBase)

local CabinFire = DisasterBase.extend("CabinFire")

local ORIGINS = {
	AftGalley = { Zone = "AFT GALLEY", Circuit = "GALLEY OVENS", Story = "A galley oven overheated and ignited a stack of napkins." },
	Lavatory = { Zone = "AFT LAVATORY", Circuit = "LAV WATER HEATER", Story = "An overheating lavatory water heater shorted and lit the insulation." },
	Cabin = { Zone = "MID CABIN", Circuit = "CABIN LIGHTING", Story = "Chafed wiring behind the cabin lighting arced and caught fire." },
	Electrical = { Zone = "SERVICE BAY", Circuit = "AVIONICS COOLING", Story = "An avionics cooling fan seized and its motor caught fire." },
	FrontGalley = { Zone = "FORWARD GALLEY", Circuit = "COFFEE MAKERS", Story = "A faulty coffee maker in the forward galley burst into flames." },
}

function CabinFire:Setup()
	local keys = {}
	for key in ORIGINS do
		table.insert(keys, key)
	end
	table.sort(keys)
	self.OriginKey = Util.Pick(self.Rng, keys)
	self.Origin = ORIGINS[self.OriginKey]
	self.Detail = self.Origin.Story
	self.CircuitPowered = true
	-- the breaker choice shows the correct circuit and two decoys
	local decoys = {}
	for key, def in ORIGINS do
		if key ~= self.OriginKey then
			table.insert(decoys, def.Circuit)
		end
	end
	decoys = Util.Shuffle(self.Rng, decoys)
	self.Circuits = Util.Shuffle(self.Rng, { self.Origin.Circuit, decoys[1], decoys[2] })
	self.OriginCell = self.S.FireSystem:NearestCell(self.S.FireSystem.Origins[self.OriginKey])
end

function CabinFire:Clues()
	local cell = self.OriginCell
	if not cell then
		return
	end
	local originPart: BasePart = cell.Part
	local haze = Instance.new("Smoke")
	haze.Name = "Haze"
	haze.Color = Color3.fromRGB(90, 90, 90)
	haze.Opacity = 0.05
	haze.Size = 3
	haze.RiseVelocity = 1
	haze.Parent = cell.Part
	self.Haze = haze
	self.Ctx:Give(haze)
	self:Every(6, function()
		if self:Phase() ~= Enums.Phase.Flight then
			return false
		end
		self:Sound("Chime", originPart.Position)
		return true
	end)
	self:Delay(5, function()
		self.S.FlightService:SetLights(Enums.Lights.Flicker)
		self:Delay(2.5, function()
			if self:Phase() == Enums.Phase.Flight then
				self.S.FlightService:SetLights(Enums.Lights.Normal)
			end
		end)
	end)
	self:Delay(10, function()
		self.S.NPCService:React("Nervous", 0.2)
		self:Announce("Passenger", "Does anyone else smell something burning?")
	end)
end

function CabinFire:Start()
	local fire = self.S.FireSystem
	local cell = self.OriginCell
	if self.Haze then
		self.Haze:Destroy()
	end
	if cell then
		fire:Ignite(cell, 55)
		fire:SetOrigin(cell, function()
			return self.CircuitPowered
		end)
	end
	self:Sound("Sparks", cell and cell.Part.Position)
	self:Flight("FireAlarmActive", true)
	self:Warn("SMOKE DETECTED", "ZONE: " .. self.Origin.Zone, "danger")
	self:React("Panic", 0.5)
	self:InjurePassengers(2, "Smoke inhalation")
	self.S.MapService:SetDividerOpen("ServiceDoor", true)
	self:Delay(3, function()
		self:Crew("FIRE! Extinguishers are in the galleys and mid-cabin - grab one!")
	end)
	self:Delay(8, function()
		self:Captain("Smoke detector in the " .. string.lower(self.Origin.Zone) .. ". Get that fire out and kill power to the faulty circuit at the electrical panel, or it will keep coming back.")
	end)

	self:Objective({
		Id = "ExtinguishFires",
		Text = "Extinguish the fire",
		Kind = Enums.ObjectiveKind.Critical,
		Goal = 1,
		Location = cell and cell.Part,
		Hint = "Fire extinguishers: galleys, mid-cabin, service bay",
	})
	self:Objective({
		Id = "CutCircuit",
		Text = "Cut power to the faulty circuit (electrical panel)",
		Kind = Enums.ObjectiveKind.Critical,
		Location = self:Point("ElectricalPanel"),
		Hint = "Which circuit feeds the " .. string.lower(self.Origin.Zone) .. "?",
	})
	self:Panel("ElectricalPanel", "fail")
	self.PanelHandle = self:Prompt(self:Point("ElectricalPanel"), {
		Action = "OPEN BREAKERS",
		Object = "ELECTRICAL PANEL",
		Hold = 1,
		Range = 8,
		Kind = "decision",
		Condition = function()
			return self:IsActiveObjective("CutCircuit")
		end,
		OnTrigger = function(player)
			self:BreakerDecision(player)
		end,
	})

	-- containment: close the doors around the fire's section
	local section = cell and cell.Section or "Economy"
	self.ContainDoors = {}
	for _, divider in MapConfig.Dividers do
		if (divider.Between[1] == section or divider.Between[2] == section) and divider.Id ~= "CockpitDoor" then
			table.insert(self.ContainDoors, divider.Id)
		end
	end
	if #self.ContainDoors > 0 then
		self:Objective({
			Id = "ContainSmoke",
			Text = "Close the cabin doors to contain the fire",
			Kind = Enums.ObjectiveKind.Optional,
			Goal = #self.ContainDoors,
			Hint = "Closed doors stop fire and smoke spreading",
		})
	end

	self:Every(1, function()
		local active = fire:ActiveCount()
		local obj = self.S.ObjectiveService:Get("ExtinguishFires")
		if obj and self:IsActiveObjective("ExtinguishFires") then
			self.S.ObjectiveService:SetGoal("ExtinguishFires", math.max(1, obj.Progress + active))
			if active == 0 and not self.CircuitPowered then
				self:Complete("ExtinguishFires")
			elseif active == 0 then
				self.S.ObjectiveService:SetText("ExtinguishFires", "Extinguish the fire (it will re-ignite until the circuit is cut)")
			end
		end
		if self:IsActiveObjective("ContainSmoke") then
			local closed = 0
			for _, id in self.ContainDoors do
				if not self.S.MapService:IsDividerOpen(id) then
					closed += 1
				end
			end
			self.S.ObjectiveService:SetProgress("ContainSmoke", closed)
		end
		return true
	end)
end

function CabinFire:BreakerDecision(player: Player)
	local options = {
		{ Id = "CutAll", Label = "CUT ALL CABIN POWER", Description = "Guaranteed to stop re-ignition. Cabin goes dark; systems degrade.", Risk = "medium" },
	}
	for i, circuit in self.Circuits do
		table.insert(options, { Id = "Circuit" .. i, Label = "ISOLATE: " .. circuit, Description = "Keep everything else powered. Wrong breaker = sparks.", Risk = "low" })
	end
	self:Personal(player, {
		Id = "Breaker",
		Title = "WHICH BREAKER?",
		Prompt = "Smoke detector zone: " .. self.Origin.Zone .. ". Choose carefully.",
		Duration = 20,
		Options = options,
		OnResolve = function(choice, chooser)
			if not self:IsActiveObjective("CutCircuit") then
				return
			end
			if choice == "CutAll" then
				self.CircuitPowered = false
				self:Flight("MainPower", false)
				self.S.FlightService:SetLights(Enums.Lights.Emergency)
				self.S.FlightService:SetModifier("CabinPowerCut", -6)
				self:Sound("PowerDown")
				self:Complete("CutCircuit", chooser)
				self:Panel("ElectricalPanel", "off")
				self:AdjustLanding(-5, "Cabin power cut - reduced systems")
				self:Outcome("Breaker", chooser.DisplayName .. " cut all cabin power: the fire source died, but the cabin went dark.", true)
				self:Notify("All cabin power cut. The source is dead - now put out what's left.", "info")
				return
			end
			local index = tonumber(string.sub(choice, 8))
			local circuit = index and self.Circuits[index]
			if circuit == self.Origin.Circuit then
				self.CircuitPowered = false
				self:Sound("PowerDown")
				self:Complete("CutCircuit", chooser)
				self:Panel("ElectricalPanel", "ok")
				self:AdjustLanding(4, "Faulty circuit isolated cleanly")
				self:Outcome("Breaker", chooser.DisplayName .. " isolated the right circuit (" .. circuit .. ") and kept the cabin powered.", true)
				self:Notify("Correct breaker! The fire source is isolated.", "good")
			else
				self:Sound("Sparks", self:Point("ElectricalPanel").Position)
				self:Effect("Sparks", { Position = self:Point("ElectricalPanel").Position })
				self.S.ConditionService:Damage(chooser, 15, "Electrocuted at the breaker panel")
				local sparkCell = self.S.FireSystem:CellNear(self:Point("ElectricalPanel").Position)
				if sparkCell then
					self.S.FireSystem:Ignite(sparkCell, 30)
				end
				self:Warn("WRONG BREAKER", tostring(circuit) .. " was not the faulty circuit!", "danger")
				self:Outcome("Breaker", chooser.DisplayName .. " pulled the wrong breaker (" .. tostring(circuit) .. ") and started a second fire.", false)
				self:AdjustLanding(-3, "Wrong breaker pulled")
			end
		end,
	})
end

function CabinFire:Crisis()
	self:Delay(15, function()
		if self.S.FireSystem:ActiveCount() >= 2 then
			self:OfferVent()
		end
	end)
	self:Delay(35, function()
		if self.S.FireSystem:ActiveCount() >= 2 and not self.VentOffered then
			self:OfferVent()
		end
	end)
	self:Every(20, function()
		if self.S.FireSystem:ActiveCount() >= 3 then
			self:React("Panic", 0.3)
			self:Warn("FIRE SPREADING", self.S.FireSystem:ActiveCount() .. " fires burning", "danger")
		end
		return self:Phase() == Enums.Phase.Crisis
	end)
end

function CabinFire:OfferVent()
	if self.VentOffered then
		return
	end
	self.VentOffered = true
	self:Vote({
		Id = "VentCabin",
		Title = "VENT THE CABIN?",
		Speaker = "Captain",
		Prompt = "I can depressurize to starve the fire of oxygen and clear the smoke. Everyone will need a mask.",
		Duration = 15,
		Default = "Keep",
		Options = {
			{ Id = "Vent", Label = "VENT THE CABIN", Description = "Fires shrink and stop spreading for a while. Masks drop - no mask, no air.", Risk = "high" },
			{ Id = "Keep", Label = "KEEP PRESSURE", Description = "No oxygen emergency. The fire keeps growing.", Risk = "medium" },
		},
		OnResolve = function(choice)
			if choice == "Vent" then
				self:Captain("Venting now. MASKS ON!")
				self:Sound("Decompression")
				for _, cell in self.S.FireSystem:ActiveCells() do
					cell.Intensity *= 0.45
				end
				self.S.OxygenSystem:Begin(self.Ctx, { DrainScale = 0.8, IgnoreAltitude = true })
				self.S.NPCService:SetMasks(true)
				self:Objective({ Id = "UseMasks", Text = "Put on an oxygen mask", Kind = Enums.ObjectiveKind.Optional, Goal = math.max(1, self.Ctx:AliveCount()) })
				self:Delay(30, function()
					self.S.OxygenSystem:End()
					self.S.NPCService:SetMasks(false)
					self.S.MapService:DeployMasks(false)
					self.S.ObjectiveService:Remove("UseMasks")
					self:Captain("Repressurizing. Masks can come off.")
				end)
				self:AdjustLanding(3, "Cabin vented to fight the fire")
				self:Outcome("VentCabin", "Venting the cabin knocked the fire back - everyone needed masks for a while.", true)
			else
				self:Outcome("VentCabin", "The cabin stayed pressurized; the fire kept burning.", nil)
			end
		end,
	})
end

function CabinFire:Final()
	if self.S.FireSystem:ActiveCount() > 0 then
		self:Warn("FIRE STILL BURNING", "Put it out before we land!", "danger")
	end
	self:Flight("FireAlarmActive", self.S.FireSystem:ActiveCount() > 0)
end

function CabinFire:Cleanup()
	self.S.FlightService:SetModifier("CabinPowerCut", nil)
end

return CabinFire
