--[[
	RoundService
	The round state machine:

	LOBBY -> BOARDING -> FLIGHT (clues) -> DISASTER -> CRISIS -> FINAL EVENT -> LANDING
	      -> [EVACUATION] -> RESULTS -> LOBBY ...

	Replicates phase info through attributes on ReplicatedStorage.GameState. Systems that care
	about rounds implement any of OnRoundStart(ctx), OnPhase(ctx, phase), OnRoundEnd(ctx) and are
	listed in ROUND_SYSTEMS. Every hook is pcall-protected so one failing system never stops the loop.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DisasterConfig = require(ReplicatedStorage.Shared.Config.DisasterConfig)
local Enums = require(ReplicatedStorage.Shared.Enums)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MapConfig = require(ReplicatedStorage.Shared.Config.MapConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)
local Registry = require(script.Parent.Parent.Registry)
local RoundContext = require(script.Parent.Parent.RoundContext)

local RoundService = {}

local Phase = Enums.Phase

-- Systems receiving round lifecycle hooks, in call order.
local ROUND_SYSTEMS = {
	"FlightService",
	"CabinService",
	"EquipmentService",
	"FireSystem",
	"OxygenSystem",
	"TurbulenceSystem",
	"CockpitSystem",
	"NPCService",
	"RescueService",
	"DecisionService",
	"LandingService",
	"DisasterService",
}

local DESTINATIONS = {
	"Reykjavik",
	"Honolulu",
	"Tokyo Haneda",
	"Sydney",
	"Cape Town",
	"Vancouver",
	"Lisbon",
	"Singapore",
	"Anchorage",
	"Buenos Aires",
	"Oslo",
	"Dubai",
	"Nairobi",
	"Auckland",
}

local gameState: Folder
local context: any = nil
local roundNumber = 0
local skipRequested = false

---------------------------------------------------------------- helpers

local function phaseDuration(name: string, rng: Random?): number
	local value = GameConfig.Phases[name]
	local seconds = if type(value) == "table" then (rng or Random.new()):NextNumber(value[1], value[2]) else value
	if RunService:IsStudio() then
		seconds *= GameConfig.StudioTimeScale
	end
	return seconds
end

local function log(...)
	if GameConfig.Debug then
		print("[Round]", ...)
	end
end

local function callSystems(hook: string, ...)
	for _, name in ROUND_SYSTEMS do
		local system = Registry[name]
		if system and type(system[hook]) == "function" then
			local ok, err = pcall(system[hook], system, ...)
			if not ok then
				warn(string.format("[Round] %s:%s failed: %s", name, hook, tostring(err)))
			end
		end
	end
end

local function setPhase(name: string, duration: number?)
	gameState:SetAttribute("Phase", name)
	gameState:SetAttribute("PhaseDuration", duration or 0)
	gameState:SetAttribute("PhaseEndsAt", if duration then Workspace:GetServerTimeNow() + duration else 0)
	if context then
		context.Phase = name
		context.PhaseChanged:Fire(name)
		callSystems("OnPhase", context, name)
	end
	log("phase ->", name, duration)
end

function RoundService:GetContext()
	return if context and context.Active then context else nil
end

function RoundService:GetPhase(): string
	return gameState:GetAttribute("Phase")
end

function RoundService:IsLive(): boolean
	return Enums.LivePhases[self:GetPhase()] == true and self:GetContext() ~= nil
end

-- Extends/shortens the current phase (e.g. a disaster buying time). Clamped to sane values.
function RoundService:AdjustPhaseEnd(deltaSeconds: number)
	local endsAt = gameState:GetAttribute("PhaseEndsAt")
	if endsAt and endsAt > 0 then
		local newEnd = math.max(Workspace:GetServerTimeNow() + 5, endsAt + deltaSeconds)
		gameState:SetAttribute("PhaseEndsAt", newEnd)
	end
end

-- Studio / admin helper: finish the current phase now.
function RoundService:SkipPhase()
	skipRequested = true
end

-- Waits until the phase end time, returning early (false) if the round must abort.
local function waitPhase(): boolean
	skipRequested = false
	while true do
		task.wait(0.25)
		if skipRequested then
			skipRequested = false
			return true
		end
		if context then
			if #context:Players() == 0 then
				return false
			end
			if context:AliveCount() == 0 and context.Phase ~= Phase.Results then
				return false
			end
		end
		if Workspace:GetServerTimeNow() >= gameState:GetAttribute("PhaseEndsAt") then
			return true
		end
	end
end

local function readyPlayers(): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		local humanoid = Util.GetHumanoid(player)
		if humanoid and humanoid.Health > 0 and player:GetAttribute("DataLoaded") ~= nil then
			table.insert(list, player)
		end
	end
	return list
end

local function chooseModifier(rng: Random, disasterId: string): string?
	if rng:NextNumber() > DisasterConfig.ModifierChance then
		return nil
	end
	local weights = {}
	for id, modifier in DisasterConfig.Modifiers do
		local allowed = true
		for _, blocked in modifier.IncompatibleWith or {} do
			if blocked == disasterId then
				allowed = false
			end
		end
		if allowed then
			weights[id] = modifier.Weight
		end
	end
	return Util.WeightedPick(rng, weights)
end

---------------------------------------------------------------- participants

local function assignSeats(ctx)
	local seats = {}
	for _, seat in Registry.MapService.Points.Seats do
		table.insert(seats, seat)
	end
	seats = Util.Shuffle(ctx.Rng, seats)
	local reserved = {}
	for _, player in ctx:Players() do
		local seat = table.remove(seats)
		if seat then
			reserved[seat] = true
			local record = ctx:Record(player)
			record.Seat = seat:GetAttribute("SeatLabel")
			Net.Event("SeatAssigned"):FireClient(player, { Seat = seat, Label = record.Seat })
		end
	end
	ctx.Flags.ReservedSeats = reserved
end

local function boardPlayers(ctx)
	local spawns = Registry.MapService.Points.BoardingSpawns
	local index = 0
	for _, player in ctx:Players() do
		index += 1
		local spawnPoint = spawns[((index - 1) % #spawns) + 1]
		Registry.ConditionService:Track(player)
		Registry.MapService:Teleport(player, spawnPoint.CFrame * CFrame.new(0, 0, ((index % 2) * 2 - 1) * 1.2))
		player:SetAttribute("InRound", true)
	end
end

local function returnToLobby(player: Player)
	player:SetAttribute("InRound", nil)
	Registry.ConditionService:Untrack(player)
	local humanoid = Util.GetHumanoid(player)
	if humanoid and humanoid.Health > 0 then
		Registry.MapService:Teleport(player, Registry.MapService:LobbySpawnCFrame())
	end
	Registry.EquipmentService:StripTools(player)
end

---------------------------------------------------------------- watchdogs

local function startWatchdogs(ctx)
	ctx:Every(1, function()
		gameState:SetAttribute("Alive", ctx:AliveCount())
		local livePhase = ctx.Phase ~= Phase.Boarding and ctx.Phase ~= Phase.Results
		for _, player in ctx:AlivePlayers() do
			local record = ctx:Record(player)
			local root = Util.GetRoot(player)
			if root and livePhase and not record.Evacuated then
				local localPos = MapConfig.ToLocal(root.Position)
				if localPos.Y < -30 or not MapConfig.IsInsidePlane(root.Position) and localPos.Y < -6 then
					Registry.ConditionService:Kill(player, "Fell from the aircraft")
				end
			end
		end
		return true
	end)
end

---------------------------------------------------------------- round flow

local function runLobby()
	local ready: { Player } = {}
	while true do
		ready = readyPlayers()
		if #ready >= GameConfig.Players.MinToStart then
			break
		end
		setPhase(Phase.Lobby, nil)
		gameState:SetAttribute("Status", "Waiting for passengers...")
		task.wait(GameConfig.Phases.LobbyWhenEmpty)
	end
	gameState:SetAttribute("Status", "")
	local duration = phaseDuration("Lobby")
	setPhase(Phase.Lobby, duration)
	skipRequested = false
	while Workspace:GetServerTimeNow() < gameState:GetAttribute("PhaseEndsAt") do
		task.wait(0.5)
		if skipRequested then
			skipRequested = false
			break
		end
		if #readyPlayers() < GameConfig.Players.MinToStart then
			return false
		end
	end
	return true
end

local function runRound()
	local players = readyPlayers()
	if #players == 0 then
		return
	end
	roundNumber += 1
	local ctx = RoundContext.new(players)
	context = ctx
	gameState:SetAttribute("Round", roundNumber)
	gameState:SetAttribute("InProgress", true)
	gameState:SetAttribute("Participants", #players)
	gameState:SetAttribute("Alive", #players)

	-- choose the hidden disaster + modifier (never replicated until results)
	local disasterId, disasterDef = Registry.DisasterService:Choose(ctx)
	ctx.DisasterId = disasterId
	ctx.DisasterDef = disasterDef
	ctx.Modifier = chooseModifier(ctx.Rng, disasterId)
	local modifierDef = ctx.Modifier and DisasterConfig.Modifiers[ctx.Modifier]
	gameState:SetAttribute("Modifier", if modifierDef then modifierDef.DisplayName else "")
	gameState:SetAttribute("ModifierDescription", if modifierDef then modifierDef.Description else "")
	gameState:SetAttribute("FlightNumber", string.format("LF%d", ctx.Rng:NextInteger(100, 989)))
	gameState:SetAttribute("Destination", Util.Pick(ctx.Rng, DESTINATIONS))
	print(string.format("[Round] #%d starting: %d players, disaster=%s, modifier=%s", roundNumber, #players, disasterId, tostring(ctx.Modifier)))

	-- BOARDING
	Registry.MapService:ResetAirplane()
	Registry.ObjectiveService:Clear()
	assignSeats(ctx) -- reserve player seats before NPCs sit down
	callSystems("OnRoundStart", ctx)
	boardPlayers(ctx)
	startWatchdogs(ctx)
	setPhase(Phase.Boarding, phaseDuration("Boarding", ctx.Rng))
	Registry.ObjectiveService:Add({
		Id = "FindSeat",
		Text = "Find your seat",
		Kind = Enums.ObjectiveKind.Optional,
		Goal = #players,
		Hint = "Your seat number is shown on screen",
	})
	Registry.FlightService:StartSimulation()
	local continueRound = waitPhase()

	local phases = {
		{ Phase.Flight, "Flight" },
		{ Phase.Disaster, "Disaster" },
		{ Phase.Crisis, "Crisis" },
		{ Phase.FinalEvent, "FinalEvent" },
	}
	for _, entry in phases do
		if not continueRound then
			break
		end
		local phaseName, configKey = entry[1], entry[2]
		local duration = phaseDuration(configKey, ctx.Rng)
		if ctx.Modifier == "LowFuel" and (phaseName == Phase.Crisis or phaseName == Phase.Disaster) then
			duration *= 0.8
		end
		if phaseName == Phase.Flight then
			Registry.ObjectiveService:Remove("FindSeat")
		end
		setPhase(phaseName, duration)
		if phaseName == Phase.Flight then
			-- clue sequence starts part-way through the calm flight
			ctx:Delay(duration * GameConfig.ClueStartFraction, function()
				Registry.DisasterService:Invoke(ctx, "Clues")
			end)
		end
		continueRound = waitPhase()
	end

	-- LANDING (always resolves, even if the round aborted, so outcomes stay consistent)
	local landing
	if #ctx:Players() > 0 then
		setPhase(Phase.Landing, phaseDuration("Landing", ctx.Rng))
		landing = Registry.LandingService:Touchdown(ctx, continueRound)
		waitPhase()
		if landing and landing.NeedsEvacuation and ctx:AliveCount() > 0 then
			setPhase(Phase.Evacuation, phaseDuration("Evacuation", ctx.Rng))
			Registry.LandingService:BeginEvacuation(ctx)
			waitPhase()
			Registry.LandingService:EndEvacuation(ctx)
		end
	end

	-- RESULTS
	Registry.FlightService:StopSimulation()
	local results = Registry.RewardService:FinalizeRound(ctx, landing)
	setPhase(Phase.Results, phaseDuration("Results", ctx.Rng))
	for _, player in ctx:Players() do
		returnToLobby(player)
	end
	if results then
		Net.FireList("Results", Players:GetPlayers(), results)
	end
	waitPhase()

	-- CLEANUP
	callSystems("OnRoundEnd", ctx)
	Registry.ObjectiveService:Clear()
	ctx:End()
	context = nil
	gameState:SetAttribute("InProgress", false)
	gameState:SetAttribute("Modifier", "")
	Registry.MapService:ResetAirplane()
	Registry.FlightService:Reset()
	for _, player in Players:GetPlayers() do
		player:SetAttribute("InRound", nil)
	end
end

---------------------------------------------------------------- lifecycle

function RoundService:Init()
	gameState = Instance.new("Folder")
	gameState.Name = "GameState"
	gameState:SetAttribute("Phase", Phase.Lobby)
	gameState:SetAttribute("PhaseEndsAt", 0)
	gameState:SetAttribute("PhaseDuration", 0)
	gameState:SetAttribute("Round", 0)
	gameState:SetAttribute("InProgress", false)
	gameState:SetAttribute("Status", "")
	gameState:SetAttribute("Modifier", "")
	gameState.Parent = ReplicatedStorage
end

function RoundService:Start()
	Players.PlayerRemoving:Connect(function(player)
		local ctx = self:GetContext()
		if ctx then
			local record = ctx:Record(player)
			if record then
				record.Left = true
				if record.Alive then
					record.Alive = false
					record.Cause = "Left the flight"
				end
			end
		end
	end)

	task.spawn(function()
		while true do
			local ok, err = pcall(function()
				if runLobby() then
					runRound()
				end
			end)
			if not ok then
				warn("[Round] round loop error (recovering):", err)
				-- hard recovery: end whatever round was running and return everyone to the lobby
				if context then
					pcall(callSystems, "OnRoundEnd", context)
					for _, player in context:Players() do
						pcall(returnToLobby, player)
					end
					context:End()
					context = nil
				end
				pcall(function()
					Registry.ObjectiveService:Clear()
					Registry.MapService:ResetAirplane()
					Registry.FlightService:StopSimulation()
					Registry.FlightService:Reset()
				end)
				gameState:SetAttribute("InProgress", false)
				task.wait(3)
			end
		end
	end)
end

return RoundService
