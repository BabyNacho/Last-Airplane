--[[
	LandingService
	FINAL EVENT: universal landing preparation (brace, landing gear, manual approach when needed).
	LANDING: computes a landing score from aircraft state + player actions + decisions, picks a
	tier (Perfect / Successful / Hard / Emergency / Crash) and applies touchdown damage - buckled
	players are far safer than players standing in the aisle.
	EVACUATION: after rough landings or with fire aboard, players must open exits and get out.
	Exits on the burning side are dangerous - look outside before you open a door.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Util = require(ReplicatedStorage.Shared.Util)
local Registry = require(script.Parent.Parent.Registry)

local LandingService = {}

local CFG = GameConfig.Landing
local Tier = Enums.LandingTier

local slides: { Instance } = {}
local evacuationThread: thread? = nil
local lastResult: any = nil

---------------------------------------------------------------- final event

local function braceObjective(ctx)
	Registry.ObjectiveService:Add({
		Id = "Brace",
		Text = "BRACE: Buckle up in any seat before touchdown",
		Kind = Enums.ObjectiveKind.Optional,
		Goal = math.max(1, ctx:AliveCount()),
		Hint = "Unsecured passengers are badly hurt on landing",
	})
	ctx:Every(1, function()
		if not Registry.ObjectiveService:IsActive("Brace") then
			return false
		end
		local alive = ctx:AlivePlayers()
		local seated = Registry.CabinService:SeatedParticipants(ctx)
		Registry.ObjectiveService:SetGoal("Brace", math.max(1, #alive))
		Registry.ObjectiveService:SetProgress("Brace", #seated)
		return ctx.Phase == Enums.Phase.FinalEvent
	end)
end

local function gearDown(player: Player?)
	Registry.FlightService:Set("GearDown", true)
	Registry.EffectsService:Sound("PowerUp")
	Registry.EffectsService:Shake(0.4, 0.8)
	Registry.EffectsService:Notify("Landing gear down and locked.", "good")
	if Registry.ObjectiveService:IsActive("LowerGear") then
		Registry.ObjectiveService:Complete("LowerGear", player)
	end
end

local function gearObjective(ctx)
	local method = ctx.Flags.GearMethod or "Auto"
	if method == "Auto" then
		ctx:Delay(GameConfig.Phases.FinalEvent * 0.55, function()
			if not Registry.FlightService:Get("GearDown") then
				gearDown(nil)
			end
		end)
		return
	end
	if method == "Lever" then
		local lever = Registry.MapService.Points.GearLever
		Registry.ObjectiveService:Add({
			Id = "LowerGear",
			Text = "Lower the landing gear (cockpit)",
			Kind = Enums.ObjectiveKind.Critical,
			Location = lever,
			Hint = "Gear lever on the right side of the instrument panel",
		})
		Registry.InteractionService:Add(lever, {
			Action = "LOWER",
			Object = "LANDING GEAR",
			Hold = 1.2,
			Range = 7,
			Kind = "objective",
			Round = ctx,
			Condition = function()
				return not Registry.FlightService:Get("GearDown")
			end,
			OnTrigger = function(player)
				if ctx.Flags.GearJammed then
					Registry.EffectsService:Notify("The lever won't move - no hydraulic pressure! Use the manual crank.", "warn", player)
					return
				end
				gearDown(player)
			end,
		})
	elseif method == "Crank" then
		local crank = Registry.MapService.Points.GearCrank
		local progress = 0
		Registry.ObjectiveService:Add({
			Id = "LowerGear",
			Text = "Crank the landing gear down by hand",
			Kind = Enums.ObjectiveKind.Critical,
			Goal = 100,
			Location = crank,
			Hint = "Floor hatch in the forward galley - more hands crank faster",
		})
		Registry.InteractionService:Add(crank, {
			Action = "CRANK",
			Object = "MANUAL GEAR EXTENSION",
			Hold = 2,
			Range = 7,
			Kind = "objective",
			Round = ctx,
			Cooldown = 0.2,
			Condition = function()
				return not Registry.FlightService:Get("GearDown")
			end,
			OnTrigger = function(player)
				-- co-op: more players at the crank means bigger progress per turn
				local helpers = #Registry.MapService:PlayersNear(crank.Position, 8, ctx:AlivePlayers())
				local amount = 18 + math.min(3, helpers - 1) * 8
				progress = math.min(100, progress + amount)
				Registry.ObjectiveService:SetProgress("LowerGear", progress, player)
				Registry.EffectsService:Sound("Button", crank.Position)
				if progress >= 100 then
					gearDown(player)
				end
			end,
		})
	end
end

local function approachObjective(ctx)
	if not ctx.Flags.ManualApproach then
		return
	end
	local seat = Registry.MapService.Points.PilotSeat
	Registry.CockpitSystem:EnableManual(true)
	Registry.CockpitSystem:SetApproach(true)
	Registry.ObjectiveService:Add({
		Id = "FlyApproach",
		Text = "Fly the approach: take the pilot seat and keep the aircraft level",
		Kind = Enums.ObjectiveKind.Critical,
		Location = seat,
		Hint = "Sit in the left cockpit seat - use W/S, the stick, or the on-screen buttons",
	})
	ctx:Every(1, function()
		if Registry.CockpitSystem:HasPilot() and Registry.ObjectiveService:IsActive("FlyApproach") then
			local occupant = seat.Occupant
			local player = occupant and game:GetService("Players"):GetPlayerFromCharacter(occupant.Parent)
			Registry.ObjectiveService:Complete("FlyApproach", player)
		end
		return ctx.Phase == Enums.Phase.FinalEvent
	end)
end

function LandingService:OnPhase(ctx, phase: string)
	if phase == Enums.Phase.FinalEvent then
		local flight = Registry.FlightService
		local current = flight:Get("Altitude")
		flight:SetDescent(3000, math.max(60, (current - 3000) / (GameConfig.Phases.FinalEvent * 0.9)))
		braceObjective(ctx)
		gearObjective(ctx)
		approachObjective(ctx)
		Registry.EffectsService:Warning("PREPARE FOR LANDING", "Return to a seat and fasten your seatbelt", "warn")
		if flight:Get("PilotPresent") then
			ctx:Delay(2, function()
				Registry.EffectsService:Sound("Intercom")
				Registry.EffectsService:Announce("Captain", "Cabin crew, prepare for landing. Everyone - seatbelts on, now.")
			end)
		end
	elseif phase == Enums.Phase.Landing then
		local flight = Registry.FlightService
		flight:Set("Approach", true)
		flight:SetDescent(0, math.max(250, flight:Get("Altitude") / (GameConfig.Phases.Landing * 0.7)))
		Registry.ObjectiveService:Remove("Brace")
	end
end

---------------------------------------------------------------- touchdown

function LandingService:ComputeScore(ctx, aborted: boolean): (number, { any })
	local notes = {}
	if aborted then
		return 0, { { Delta = -100, Note = "Nobody was left to help" } }
	end
	local flight = Registry.FlightService
	local avg = flight:AverageStability(110)
	local current = flight:Get("Stability")
	local score = 20 + avg * 0.55 + current * 0.25
	table.insert(notes, { Delta = math.floor(score), Note = string.format("Aircraft stability %d%%", math.floor(avg)) })

	if not flight:Get("GearDown") then
		score -= 35
		table.insert(notes, { Delta = -35, Note = "Belly landing - gear not down" })
	end
	local unresolved = 0
	for _, obj in Registry.ObjectiveService:CriticalRemaining() do
		if obj.Id ~= "LowerGear" and obj.Id ~= "FlyApproach" then
			unresolved += 1
		end
	end
	if unresolved > 0 then
		local penalty = math.min(3, unresolved) * CFG.UnresolvedCriticalPenalty
		score -= penalty
		table.insert(notes, { Delta = -penalty, Note = unresolved .. " critical objective(s) unresolved" })
	end
	local fires = Registry.FireSystem:ActiveCount()
	if fires > 0 then
		local penalty = CFG.ActiveFirePenalty + (fires - 1) * 2
		score -= penalty
		table.insert(notes, { Delta = -penalty, Note = "Fire still burning aboard" })
	end
	if ctx.Flags.ManualApproach then
		local quality = Registry.CockpitSystem:ApproachQuality()
		if quality then
			local delta = math.floor((quality - 0.5) * 40)
			score += delta
			table.insert(notes, { Delta = delta, Note = string.format("Manual approach accuracy %d%%", math.floor(quality * 100)) })
		else
			score -= 30
			table.insert(notes, { Delta = -30, Note = "Nobody flew the approach" })
		end
	end
	local disasterDelta, disasterNotes = Registry.DisasterService:LandingModifier(ctx)
	score += disasterDelta
	for _, note in disasterNotes do
		table.insert(notes, note)
	end
	if ctx.Modifier == "VeteranCrew" then
		score += 6
		table.insert(notes, { Delta = 6, Note = "Veteran crew" })
	end
	score += ctx.Rng:NextNumber(-CFG.RandomSpread, CFG.RandomSpread)
	local cap = ctx.Disaster and ctx.Disaster.MaxScore
	if cap and score > cap then
		score = cap
		table.insert(notes, { Delta = 0, Note = "Best possible outcome was limited by an earlier decision" })
	end
	return math.clamp(math.floor(score), 0, 100), notes
end

function LandingService:TierFor(score: number): string
	if score >= CFG.Perfect then
		return Tier.Perfect
	elseif score >= CFG.Successful then
		return Tier.Successful
	elseif score >= CFG.Hard then
		return Tier.Hard
	elseif score >= CFG.Emergency then
		return Tier.Emergency
	end
	return Tier.Crash
end

local function applyTouchdown(ctx, tier: string)
	local ranges = CFG.Damage[tier]
	Registry.FlightService:Set("OnGround", true)
	Registry.FlightService:Set("Altitude", 0)
	Registry.EffectsService:Sound("Touchdown")
	Registry.EffectsService:Effect("Touchdown", { Tier = tier })
	local shake = ({ Perfect = 0.6, Successful = 1, Hard = 2.2, Emergency = 3, Crash = 4 })[tier] or 1
	Registry.EffectsService:Shake(shake, 2.5)
	for _, player in ctx:AlivePlayers() do
		local seated = Registry.MapService:IsSeated(player)
		local range = if seated then ranges[1] else ranges[2]
		local damage = ctx.Rng:NextNumber(range[1], range[2])
		if damage > 0 then
			Registry.ConditionService:Damage(player, damage, if tier == Tier.Crash then "Crash landing" else "Thrown on touchdown", false)
		end
		if not seated and damage > 20 then
			Registry.EffectsService:Notify("You weren't buckled in!", "danger", player)
		end
	end
	if tier == Tier.Crash or tier == Tier.Emergency then
		if tier == Tier.Crash or ctx.Rng:NextNumber() < 0.4 then
			local origins = { "AftGalley", "Cabin", "FrontGalley" }
			Registry.FireSystem:StartAt(origins[ctx.Rng:NextInteger(1, #origins)], 55)
		end
	end
	Registry.DisasterService:Invoke(ctx, "OnTouchdown", tier)
end

-- Called at the start of the LANDING phase. Returns the landing result.
function LandingService:Touchdown(ctx, continued: boolean)
	local aborted = not continued and ctx:AliveCount() == 0
	local score, notes = self:ComputeScore(ctx, aborted)
	local tier = self:TierFor(score)
	ctx.LandingScore = score
	ctx.LandingTier = tier
	local result = {
		Tier = tier,
		Score = score,
		Notes = notes,
		NeedsEvacuation = false,
		GearDown = Registry.FlightService:Get("GearDown"),
		ApproachQuality = if ctx.Flags.ManualApproach then Registry.CockpitSystem:ApproachQuality() else nil,
		Pilots = {},
	}
	for player, seconds in Registry.CockpitSystem:ApproachPilots() do
		if seconds >= 6 then
			result.Pilots[player] = true
		end
	end
	lastResult = result
	if not aborted then
		Registry.EffectsService:Warning(if tier == Tier.Crash or tier == Tier.Emergency then "BRACE! BRACE! BRACE!" else "FINAL APPROACH", if tier == Tier.Crash then "Heads down! Stay down!" else "Stay in your seat", "danger")
		local impactDelay = math.max(3, GameConfig.Phases.Landing - 5)
		ctx:Delay(impactDelay, function()
			applyTouchdown(ctx, tier)
		end)
		-- evacuation decision needs the post-impact state, but the tier already tells us most of it
		result.NeedsEvacuation = tier == Tier.Emergency or tier == Tier.Crash or Registry.FireSystem:ActiveCount() > 0 or Registry.DisasterService:NeedsEvacuation(ctx)
	end
	return result
end

---------------------------------------------------------------- evacuation

local function addSlide(exit)
	local door = exit.Door
	local side = exit.Side
	local slide = Instance.new("WedgePart")
	slide.Name = "EvacSlide"
	slide.Anchored = true
	slide.CanCollide = false
	slide.Color = Color3.fromRGB(255, 200, 40)
	slide.Material = Enum.Material.Plastic
	slide.Size = Vector3.new(4, 6, 12)
	slide.CFrame = CFrame.lookAt(door.Position + Vector3.new(0, -4, side * 7), door.Position + Vector3.new(0, -4, side * 20))
	slide.Parent = Registry.MapService.Airplane
	table.insert(slides, slide)
end

function LandingService:OpenExit(ctx, exit, player: Player)
	Registry.MapService:OpenExit(exit)
	Registry.EffectsService:Sound("Door", exit.Door.Position)
	addSlide(exit)
	ctx:Log(player.DisplayName .. " opened exit " .. exit.Id)
	local hazard = ctx.Flags.HazardSide
	if hazard and hazard == exit.Side then
		Registry.EffectsService:Warning("FIRE OUTSIDE!", "Exit " .. exit.Id .. " opens onto the burning side!", "danger")
		Registry.ConditionService:Damage(player, 18, "Burned by fire outside the exit")
		local cell = Registry.FireSystem:CellNear(exit.Door.Position)
		if cell then
			Registry.FireSystem:Ignite(cell, 40)
		end
		exit.Hazard = true
	else
		Registry.EffectsService:Notify("Exit " .. exit.Id .. " open - go, go, go!", "good")
	end
end

function LandingService:BeginEvacuation(ctx)
	Registry.EffectsService:Warning("EVACUATE! EVACUATE!", "Open an emergency exit and get out", "danger")
	Registry.EffectsService:Sound("MasterCaution")
	Registry.FlightService:SetLights(Enums.Lights.Emergency)
	Registry.NPCService:CrewSay("Leave everything! Come this way! Check outside before opening a door!")
	Registry.NPCService:React("Panic", 0.6)
	Registry.ObjectiveService:Add({
		Id = "Evacuate",
		Text = "EVACUATE: open an exit and get out",
		Kind = Enums.ObjectiveKind.Critical,
		Goal = math.max(1, ctx:AliveCount()),
		Hint = "Exits are marked in red. Fire outside? Use the other side.",
	})
	local hazard = ctx.Flags.HazardSide
	if hazard then
		Registry.FlightService:Set(if hazard < 0 then "EngineFireL" else "EngineFireR", true)
	end
	local evacuatedCount = 0
	evacuationThread = ctx:Every(0.25, function()
		for _, player in ctx:AlivePlayers() do
			local record = ctx:Record(player)
			if record and not record.Evacuated and Registry.ConditionService:IsConscious(player) then
				local root = Util.GetRoot(player)
				if root then
					for _, exit in Registry.MapService.Points.Exits do
						if exit.Door:GetAttribute("Open") and (root.Position - exit.Inside.Position).Magnitude < 4.2 then
							record.Evacuated = true
							evacuatedCount += 1
							if exit.Hazard then
								Registry.ConditionService:Damage(player, 15, "Burned escaping through the fire")
							end
							Registry.EffectsService:Effect("Evacuated", {}, player)
							Registry.EffectsService:Notify(player.DisplayName .. " made it out!", "good")
							Registry.ObjectiveService:SetProgress("Evacuate", evacuatedCount, player)
							Registry.EquipmentService:StripTools(player)
							-- slide down to the tarmac (lobby) - out of danger
							Registry.MapService:Teleport(player, Registry.MapService:LobbySpawnCFrame())
							break
						end
					end
				end
			end
		end
		return true
	end)
end

function LandingService:EndEvacuation(ctx)
	if evacuationThread then
		pcall(task.cancel, evacuationThread)
		evacuationThread = nil
	end
	local deadly = Registry.FireSystem:ActiveCount() > 0 or ctx.LandingTier == Tier.Crash
	for _, player in ctx:AlivePlayers() do
		local record = ctx:Record(player)
		if record and not record.Evacuated then
			if deadly then
				Registry.ConditionService:Damage(player, 65, "Trapped in the burning aircraft", false)
			end
			if Registry.ConditionService:GetState(player) == Enums.Condition.Unconscious and deadly then
				Registry.ConditionService:Kill(player, "Trapped in the burning aircraft")
			end
		end
	end
	Registry.ObjectiveService:Remove("Evacuate")
end

-- Players still unconscious at the end: paramedics save them after a controlled landing.
function LandingService:ResolveUnconscious(ctx)
	local safe = ctx.LandingTier ~= Tier.Crash and Registry.FireSystem:ActiveCount() == 0
	for _, player in ctx:AlivePlayers() do
		if Registry.ConditionService:GetState(player) == Enums.Condition.Unconscious then
			if safe then
				Registry.ConditionService:Revive(player, 10)
				Registry.EffectsService:Notify("Paramedics reached you in time.", "good", player)
			else
				Registry.ConditionService:Kill(player, "Never regained consciousness")
			end
		end
	end
end

function LandingService:LastResult()
	return lastResult
end

function LandingService:OnRoundStart(ctx)
	lastResult = nil
	for _, slide in slides do
		slide:Destroy()
	end
	table.clear(slides)
	ctx.Flags.GearMethod = "Auto"
end

function LandingService:OnRoundEnd()
	for _, slide in slides do
		slide:Destroy()
	end
	table.clear(slides)
	if evacuationThread then
		pcall(task.cancel, evacuationThread)
		evacuationThread = nil
	end
end

return LandingService
