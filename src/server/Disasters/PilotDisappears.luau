--[[
	THE EMPTY COCKPIT (Pilot Disappears)
	Clues: the captain's announcement cuts off mid-sentence, a flight attendant knocks on the
	cockpit door, the autopilot chimes... and nobody answers.
	Event: the flight deck is locked and silent. Players must get in - three different ways:
	  * CRASH AXE from the service bay (slow, loud, always works),
	  * the spare CREW KEYCARD hidden somewhere in the cabin (search for it),
	  * the DOOR CODE written in the captain's logbook (find the logbook, share the code!).
	Then: fly the aircraft by hand, raise ATC on the radio, optionally find what happened to the
	pilots (a revived pilot talks you down), and fly the final approach yourselves.
	Decision (vote, after ATC contact): NEAREST airport (short runway, land sooner) vs MAJOR
	airport (long runway, longer flight with a failing autopilot).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local Util = require(ReplicatedStorage.Shared.Util)
local DisasterBase = require(script.Parent.DisasterBase)

local PilotDisappears = DisasterBase.extend("PilotDisappears")

function PilotDisappears:Setup()
	self.Code = tostring(self.Rng:NextInteger(1000, 9999))
	local spots = self:Point("KeycardSpots")
	self.KeycardSpot = spots[self.Rng:NextInteger(1, #spots)]
	local lavs = {}
	for _, lav in self:Point("Lavatories") do
		table.insert(lavs, lav.Center)
	end
	self.LogbookSpot = Util.Pick(self.Rng, lavs)
	self.Inside = false
	self.StabilizeGood = 0
	self.PilotWoken = false
	self.ATC = false
end

function PilotDisappears:Clues()
	self:Sound("Intercom")
	self:Announce("Captain", "Ladies and gentlemen, this is your capt— *click*")
	self:Delay(6, function()
		self.S.NPCService:AttendantWalkTo(self:Point("CockpitDoor").Position - Vector3.new(3, 0, 0), 1)
		self:Sound("Chime")
	end)
	self:Delay(11, function()
		self.S.NPCService:SayAs(self.S.NPCService:Attendants()[1], "Captain? ...Captain?", 4)
		self:Sound("Door", self:Point("CockpitDoor").Position)
	end)
	self:Delay(16, function()
		self:React("Confused", 0.2)
	end)
end

function PilotDisappears:Start()
	self:Flight("PilotPresent", false)
	self.S.NPCService:MovePilotsToCrewRest()
	self:Warn("NO RESPONSE FROM FLIGHT DECK", "The cockpit door is locked from the inside", "danger")
	self:React("Confused", 0.5)
	self:Delay(2, function()
		self:Crew("They're not answering and the door won't open! There's a crash axe in the service bay... and a spare keycard somewhere back here. Help me!")
	end)
	self.S.MapService:SetDividerOpen("ServiceDoor", true)
	self.S.CockpitSystem.LockedHandler = function(player)
		self:EntryDecision(player)
	end

	self:Objective({
		Id = "EnterCockpit",
		Text = "Get into the cockpit",
		Kind = Enums.ObjectiveKind.Critical,
		Location = self:Point("CockpitDoor"),
		Hint = "Crash axe (service bay), the spare keycard, or the door code",
	})
	self:Objective({
		Id = "WherePilots",
		Text = "Find out what happened to the pilots",
		Kind = Enums.ObjectiveKind.Optional,
		Hint = "The captain always carries a logbook...",
	})

	-- crash axe pickup
	self.S.EquipmentService:AddPickup(self.Ctx, self:Point("CrashAxe"), "CrashAxe", 1)
	-- keycard search spots
	for _, spot in self:Point("KeycardSpots") do
		local handle
		handle = self:Prompt(spot, {
			Action = "SEARCH",
			Object = "",
			Hold = 1.5,
			Range = 6,
			Condition = function()
				return not self.Inside
			end,
			OnTrigger = function(player)
				handle:SetEnabled(false)
				if spot == self.KeycardSpot then
					self.S.EquipmentService:Give(player, "Keycard")
					self:Notify(player.DisplayName .. " found the spare crew keycard!", "good")
				else
					self:Notify("Nothing here.", "info", player)
				end
			end,
		})
	end
	-- captain's logbook (door code + clue)
	local logbook
	logbook = self:Prompt(self.LogbookSpot, {
		Action = "READ",
		Object = "CAPTAIN'S LOGBOOK",
		Hold = 2,
		Range = 6,
		Kind = "objective",
		OnTrigger = function(player)
			self:Notify("Logbook: \"Door code " .. self.Code .. ". F/O feeling dizzy in crew rest - heater smells odd. Going to check on him.\"", "good", player)
			self:Notify(player.DisplayName .. " found the captain's logbook - ask them for the door code!", "info")
			self.CodeFoundBy = player
			self:Complete("WherePilots", player)
			self:Objective({
				Id = "FindPilots",
				Text = "Check the crew rest in the service bay",
				Kind = Enums.ObjectiveKind.Optional,
				Location = self:Point("CrewRest"),
			})
			self:SetupPilotRescue()
			logbook:SetEnabled(false)
		end,
	})
	-- the crew rest can also be found without the logbook
	self:Delay(1, function()
		self:SetupPilotRescue()
	end)
end

function PilotDisappears:SetupPilotRescue()
	if self.RescueSetup then
		return
	end
	self.RescueSetup = true
	for index, npc in self.S.NPCService:Pilots() do
		local handle
		handle = self:Prompt(npc.Root, {
			Action = "WAKE",
			Object = if index == 1 then "CAPTAIN (unconscious)" else "FIRST OFFICER (unconscious)",
			Hold = 4,
			Range = 8,
			Kind = "rescue",
			OnTrigger = function(player)
				handle:SetEnabled(false)
				self.Ctx:Add(player, "Rescues")
				self.S.NPCService:SayAs(npc, "*cough* ...carbon monoxide... the heater... I'm too dizzy to fly.", 5)
				if not self.PilotWoken then
					self.PilotWoken = true
					self.Detail = "A faulty heater filled the crew rest with carbon monoxide. The captain went to check on the first officer, collapsed, and the cockpit door locked behind him."
					if self:IsActiveObjective("WherePilots") then
						self:Complete("WherePilots", player)
					end
					if self:IsActiveObjective("FindPilots") then
						self:Complete("FindPilots", player)
					end
					self:AdjustLanding(12, "A revived pilot talked the crew down")
					self:Delay(4, function()
						self:Captain("I can't fly like this... but I can talk you through it. Get in that left seat. Keep the wings level and do exactly what I say.")
					end)
				end
			end,
		})
	end
end

function PilotDisappears:EntryDecision(player: Player)
	if self.Inside then
		return
	end
	local hasAxe = self.S.EquipmentService:HasTool(player, "CrashAxe") ~= nil
	local hasCard = self.S.EquipmentService:HasTool(player, "Keycard") ~= nil
	local options = {
		{ Id = "Axe", Label = "FORCE IT WITH THE AXE", Description = if hasAxe then "Slow and loud, but it will work." else "You need the crash axe from the service bay.", Risk = "medium" },
		{ Id = "Card", Label = "SWIPE THE KEYCARD", Description = if hasCard then "Instant." else "You don't have the keycard.", Risk = "low" },
		{ Id = "Code", Label = "ENTER THE DOOR CODE", Description = "Know the code? Type it in.", Risk = "low" },
	}
	self:Personal(player, {
		Id = "CockpitEntry",
		Title = "THE COCKPIT DOOR",
		Prompt = "Locked from the inside. How do you get in?",
		Duration = 15,
		Options = options,
		OnResolve = function(choice, chooser)
			if choice == "Axe" then
				if not self.S.EquipmentService:HasTool(chooser, "CrashAxe") then
					self:Notify("You need the crash axe (service bay).", "warn", chooser)
					return
				end
				self:ForceDoor(chooser)
			elseif choice == "Card" then
				if not self.S.EquipmentService:HasTool(chooser, "Keycard") then
					self:Notify("You don't have the keycard. Search the cabin for it.", "warn", chooser)
					return
				end
				self:OpenCockpit(chooser, "keycard")
			elseif choice == "Code" then
				self:Personal(chooser, {
					Id = "DoorCode",
					Title = "ENTER DOOR CODE",
					Prompt = "4 digits",
					Input = "Keypad",
					Duration = 25,
					OnResolve = function(code, who)
						if code == self.Code then
							self:OpenCockpit(who, "code")
						else
							self:Sound("Warning")
							self:Notify("ACCESS DENIED", "danger", who)
						end
					end,
				})
			end
		end,
	})
end

function PilotDisappears:ForceDoor(player: Player)
	if self.Forcing then
		return
	end
	self.Forcing = true
	local door = self:Point("CockpitDoor")
	self:Notify(player.DisplayName .. " is forcing the cockpit door!", "info")
	local handle
	handle = self:Prompt(door, {
		Action = "CHOP",
		Object = "COCKPIT DOOR",
		Hold = 8,
		Range = 7,
		Kind = "danger",
		Condition = function(p)
			return not self.Inside and self.S.EquipmentService:HasTool(p, "CrashAxe") ~= nil
		end,
		OnTrigger = function(p)
			handle:Destroy()
			self:Sound("Axe", door.Position)
			self:OpenCockpit(p, "axe")
		end,
	})
	self:Every(1.2, function()
		if self.Inside then
			return false
		end
		self:Sound("Axe", door.Position)
		return true
	end)
end

function PilotDisappears:OpenCockpit(player: Player?, method: string)
	if self.Inside then
		return
	end
	self.Inside = true
	self.S.CockpitSystem.LockedHandler = nil
	self.S.CockpitSystem:Unlock(true)
	if player then
		self:Complete("EnterCockpit", player)
		self.Ctx:Log("Cockpit entered by " .. player.DisplayName .. " using the " .. method)
		local verbs = { axe = "forced the door open", keycard = "swiped the spare keycard", code = "entered the door code" }
		self:Notify(player.DisplayName .. " " .. (verbs[method] or "got in") .. " - THE COCKPIT IS EMPTY!", "danger")
	end
	self:Warn("THE COCKPIT IS EMPTY", "Nobody is flying the aircraft", "danger")
	self:React("Panic", 0.5)
	if method ~= "axe" then
		self:AdjustLanding(3, "Cockpit entered quickly")
	end
	self:Delay(6, function()
		self:AutopilotFailure()
	end)
	self:Objective({
		Id = "ContactATC",
		Text = "Contact Air Traffic Control on the radio",
		Kind = Enums.ObjectiveKind.Critical,
		Location = self:Point("Radio"),
		Hint = "Radio panel on the centre pedestal",
	})
	self:RepairPrompt(self:Point("Radio"), {
		Objective = "ContactATC",
		Action = "TRANSMIT",
		Object = "MAYDAY",
		Hold = 2,
		OnDone = function()
			self.ATC = true
			self:Announce("You", "Mayday, mayday! There's nobody flying this plane!")
			self:Delay(3, function()
				local gameState = ReplicatedStorage:FindFirstChild("GameState")
				local flightNumber = gameState and gameState:GetAttribute("FlightNumber") or "LF"
				self:Announce("ATC", "Flight " .. tostring(flightNumber) .. ", we read you. Stay calm. We're going to talk you down.")
			end)
			self:Delay(8, function()
				self:DivertVote()
			end)
		end,
	})
end

function PilotDisappears:AutopilotFailure()
	self:Flight("Autopilot", false)
	self:Flight("CockpitAlarm", true)
	self:Sound("MasterCaution")
	self:Warn("AUTOPILOT DISCONNECT", "Manual control required", "danger")
	self.S.CockpitSystem:EnableManual(true)
	self:Objective({
		Id = "Stabilize",
		Text = "Take the controls and keep the aircraft level",
		Kind = Enums.ObjectiveKind.Critical,
		Goal = 15,
		Location = self:Point("PilotSeat"),
		Hint = "Sit in the left seat - W/S, stick, or on-screen buttons",
	})
	self:Every(1, function()
		if not self:IsActiveObjective("Stabilize") then
			return false
		end
		local bonus = self.S.CockpitSystem:ManualBonus()
		if self.S.CockpitSystem:HasPilot() and bonus > 18 then
			self.StabilizeGood += 1
			self.S.ObjectiveService:SetProgress("Stabilize", self.StabilizeGood)
		end
		return true
	end)
end

function PilotDisappears:DivertVote()
	self:Vote({
		Id = "Airport",
		Title = "WHERE DO WE LAND?",
		Speaker = "ATC",
		Prompt = "There's a small field nearby, or a major airport further out with a long runway and emergency crews.",
		Duration = 15,
		Default = "Major",
		Options = {
			{ Id = "Nearest", Label = "NEAREST AIRPORT", Description = "Land sooner. Short runway - little room for error.", Risk = "high" },
			{ Id = "Major", Label = "MAJOR AIRPORT", Description = "Long runway, better odds. Fly by hand for longer.", Risk = "medium" },
		},
		OnResolve = function(choice)
			if choice == "Nearest" then
				self.S.RoundService:AdjustPhaseEnd(-25)
				self:AdjustLanding(-8, "Short runway")
				self:Outcome("Airport", "The crew diverted to the nearest field - a short runway.", nil)
			else
				self.S.RoundService:AdjustPhaseEnd(20)
				self:AdjustLanding(8, "Long runway with emergency crews")
				self:Outcome("Airport", "The crew held on for the major airport and its long runway.", true)
				self:Every({ 18, 26 }, function()
					if self:Phase() ~= Enums.Phase.Crisis then
						return false
					end
					self:Shake(0.8, 1)
					self:Warn("AIRCRAFT DRIFTING", "Keep it level!", "warn")
					return true
				end)
			end
		end,
	})
end

function PilotDisappears:Crisis()
	if not self.Inside then
		self:Crew("We HAVE to get into that cockpit!")
		self:Delay(45, function()
			if not self.Inside then
				self:Crew("I found the override! Door's open - GO!")
				self:AdjustLanding(-10, "The crew had to override the door")
				self.S.ObjectiveService:Fail("EnterCockpit", "The crew overrode it")
				self:OpenCockpit(nil, "override")
			end
		end)
	end
end

function PilotDisappears:Final()
	self.Ctx.Flags.ManualApproach = true
	self.Ctx.Flags.GearMethod = "Lever"
	if self.ATC then
		self:Announce("ATC", "Runway in sight. Keep the nose level, lower the gear, and stay on the centreline. You can do this.")
	else
		self:Warn("NO ATC CONTACT", "Landing without guidance", "danger")
		self:AdjustLanding(-8, "No contact with ATC")
	end
end

function PilotDisappears:RevealDetail(): string?
	return self.Detail or "Both pilots were found unconscious in the crew rest - carbon monoxide from a faulty heater."
end

return PilotDisappears
