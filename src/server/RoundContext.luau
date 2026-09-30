--[[
	RoundContext
	Everything that belongs to one flight: participants, per-player round records, the seeded RNG,
	the chosen disaster, a Maid for cleanup and a round-scoped scheduler.

	All delayed callbacks go through ctx:Delay / ctx:Every so they automatically stop when the
	round ends - a disaster can never "leak" events into the next round.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Maid = require(ReplicatedStorage.Shared.Maid)
local Signal = require(ReplicatedStorage.Shared.Signal)

local RoundContext = {}
RoundContext.__index = RoundContext

export type PlayerRecord = {
	Player: Player,
	UserId: number,
	Name: string,
	Joined: number,
	Alive: boolean,
	Died: boolean,
	Cause: string?,
	Left: boolean,
	Objectives: number,
	CriticalObjectives: number,
	OptionalObjectives: number,
	Rescues: number,
	Aids: number,
	PassengersHelped: number,
	Brave: number,
	FiresExtinguished: number,
	Decisions: { any },
	DecisionsCount: number,
	DamageTaken: number,
	Evacuated: boolean,
	ManualFlightTime: number,
	ManualFlightGood: number,
	Seat: string?,
	Credits: { { Label: string, Amount: number } },
}

local nextId = 0

function RoundContext.new(players: { Player }, seed: number?)
	nextId += 1
	local self = setmetatable({}, RoundContext)
	self.Id = nextId
	self.Seed = seed or math.floor(os.clock() * 1000) % 2147483647
	self.Rng = Random.new(self.Seed)
	self.Active = true
	self.Maid = Maid.new()
	self.StartedAt = os.clock()
	self.Records = {} :: { [Player]: PlayerRecord }
	self.Flags = {} :: { [string]: any } -- disaster / system shared state
	self.DecisionLog = {} :: { any } -- { Id, Prompt, Choice, Outcome, Good }
	self.EventLog = {} :: { string }
	self.Disaster = nil :: any
	self.DisasterId = nil :: string?
	self.DisasterDef = nil :: any
	self.Modifier = nil :: string?
	self.LandingTier = nil :: string?
	self.LandingScore = nil :: number?
	self.Phase = "Boarding"
	self.PhaseChanged = Signal.new()
	self.Maid:Give(self.PhaseChanged)
	for _, player in players do
		self:AddParticipant(player)
	end
	return self
end

function RoundContext:AddParticipant(player: Player)
	self.Records[player] = {
		Player = player,
		UserId = player.UserId,
		Name = player.DisplayName,
		Joined = os.clock(),
		Alive = true,
		Died = false,
		Cause = nil,
		Left = false,
		Objectives = 0,
		CriticalObjectives = 0,
		OptionalObjectives = 0,
		Rescues = 0,
		Aids = 0,
		PassengersHelped = 0,
		Brave = 0,
		FiresExtinguished = 0,
		Decisions = {},
		DecisionsCount = 0,
		DamageTaken = 0,
		Evacuated = false,
		ManualFlightTime = 0,
		ManualFlightGood = 0,
		Seat = nil,
		Credits = {},
	}
end

function RoundContext:IsParticipant(player: Player): boolean
	return self.Records[player] ~= nil
end

function RoundContext:Record(player: Player): PlayerRecord?
	return self.Records[player]
end

-- Adds to a numeric counter on a player's round record.
function RoundContext:Add(player: Player, key: string, amount: number?)
	local record = self.Records[player]
	if record and type((record :: any)[key]) == "number" then
		(record :: any)[key] += amount or 1
	end
end

-- Players still in the server who are part of this round.
function RoundContext:Players(): { Player }
	local list = {}
	for player, record in self.Records do
		if not record.Left and player.Parent then
			table.insert(list, player)
		end
	end
	return list
end

-- Participants that are alive (conscious or unconscious) and still aboard.
function RoundContext:AlivePlayers(): { Player }
	local list = {}
	for player, record in self.Records do
		if record.Alive and not record.Left and player.Parent then
			table.insert(list, player)
		end
	end
	return list
end

function RoundContext:AliveCount(): number
	return #self:AlivePlayers()
end

function RoundContext:Log(text: string)
	table.insert(self.EventLog, text)
end

---------------------------------------------------------------- scheduler

function RoundContext:Delay(seconds: number, callback: (...any) -> (), ...)
	local args = table.pack(...)
	local thread = task.delay(seconds, function()
		if self.Active then
			local ok, err = pcall(callback, table.unpack(args, 1, args.n))
			if not ok then
				warn("[Round] delayed callback error:", err)
			end
		end
	end)
	self.Maid:Give(thread)
	return thread
end

-- Calls `callback` every `interval` seconds (number or {min,max}) until it returns false or the round ends.
function RoundContext:Every(interval: number | { number }, callback: () -> boolean?)
	local thread = task.spawn(function()
		while self.Active do
			local waitTime = if type(interval) == "table" then self.Rng:NextNumber(interval[1], interval[2]) else interval
			task.wait(waitTime)
			if not self.Active then
				break
			end
			local ok, result = pcall(callback)
			if not ok then
				warn("[Round] repeating callback error:", result)
			elseif result == false then
				break
			end
		end
	end)
	self.Maid:Give(thread)
	return thread
end

function RoundContext:Spawn(callback: () -> ())
	local thread = task.spawn(function()
		local ok, err = pcall(callback)
		if not ok then
			warn("[Round] spawned task error:", err)
		end
	end)
	self.Maid:Give(thread)
	return thread
end

-- Waits in round-safe steps. Returns false if the round ended while waiting.
function RoundContext:Wait(seconds: number): boolean
	local deadline = os.clock() + seconds
	while self.Active and os.clock() < deadline do
		task.wait(math.min(0.25, deadline - os.clock()))
	end
	return self.Active
end

function RoundContext:Give(task: any)
	return self.Maid:Give(task)
end

function RoundContext:End()
	if not self.Active then
		return
	end
	self.Active = false
	self.Maid:Clean()
end

return RoundContext
