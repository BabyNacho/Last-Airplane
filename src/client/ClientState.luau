--[[
	ClientState
	Single place the client reads replicated game state from: round phase (GameState attributes),
	aircraft state (FlightState attributes), own condition, objectives and persistent profile.
	Controllers subscribe to the change signals instead of listening to remotes directly.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Signal)

local ClientState = {}

ClientState.Player = Players.LocalPlayer
ClientState.GameState = ReplicatedStorage:WaitForChild("GameState") :: Folder
ClientState.FlightState = ReplicatedStorage:WaitForChild("FlightState") :: Folder

ClientState.Profile = nil :: any
ClientState.Condition = { State = "Healthy", Health = 100, Oxygen = 100, Tracked = false } :: any
ClientState.Objectives = {} :: { any }
ClientState.Seat = nil :: any

ClientState.ProfileChanged = Signal.new()
ClientState.ConditionChanged = Signal.new()
ClientState.ObjectivesChanged = Signal.new()
ClientState.PhaseChanged = Signal.new()
ClientState.SeatAssigned = Signal.new()

function ClientState.Phase(): string
	return ClientState.GameState:GetAttribute("Phase") or "Lobby"
end

function ClientState.TimeLeft(): number
	local endsAt = ClientState.GameState:GetAttribute("PhaseEndsAt") or 0
	if endsAt <= 0 then
		return 0
	end
	return math.max(0, endsAt - Workspace:GetServerTimeNow())
end

function ClientState.InRound(): boolean
	return ClientState.Player:GetAttribute("InRound") == true
end

function ClientState.Flight(key: string): any
	return ClientState.FlightState:GetAttribute(key)
end

function ClientState.OnFlight(key: string, callback: (any) -> ())
	ClientState.FlightState:GetAttributeChangedSignal(key):Connect(function()
		callback(ClientState.FlightState:GetAttribute(key))
	end)
	task.spawn(callback, ClientState.FlightState:GetAttribute(key))
end

function ClientState.Owns(itemId: string): boolean
	local profile = ClientState.Profile
	return profile ~= nil and table.find(profile.Owned, itemId) ~= nil
end

function ClientState.Init()
	Net.Event("ProfileUpdated").OnClientEvent:Connect(function(snapshot)
		if snapshot then
			ClientState.Profile = snapshot
			ClientState.ProfileChanged:Fire(snapshot)
		end
	end)
	Net.Event("ConditionUpdated").OnClientEvent:Connect(function(condition)
		ClientState.Condition = condition
		ClientState.ConditionChanged:Fire(condition)
	end)
	Net.Event("ObjectivesUpdated").OnClientEvent:Connect(function(list)
		table.sort(list, function(a, b)
			return a.Order < b.Order
		end)
		ClientState.Objectives = list
		ClientState.ObjectivesChanged:Fire(list)
	end)
	Net.Event("SeatAssigned").OnClientEvent:Connect(function(info)
		ClientState.Seat = info
		ClientState.SeatAssigned:Fire(info)
	end)
	ClientState.GameState:GetAttributeChangedSignal("Phase"):Connect(function()
		local phase = ClientState.Phase()
		if phase == "Lobby" then
			ClientState.Seat = nil
		end
		ClientState.PhaseChanged:Fire(phase)
	end)
	task.spawn(function()
		local ok, snapshot = pcall(function()
			return Net.Function("GetProfile"):InvokeServer()
		end)
		if ok and snapshot and not ClientState.Profile then
			ClientState.Profile = snapshot
			ClientState.ProfileChanged:Fire(snapshot)
		end
	end)
end

return ClientState
