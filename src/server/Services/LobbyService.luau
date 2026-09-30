--[[
	LobbyService
	Keeps the terminal alive: departure board & gate sign countdown, server leaderboard
	(top flyers by flights survived) and lobby-side player attributes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Util = require(ReplicatedStorage.Shared.Util)
local Registry = require(script.Parent.Parent.Registry)

local LobbyService = {}

local function setScreen(part: BasePart?, title: string, subtitle: string)
	if not part then
		return
	end
	local gui = part:FindFirstChild("Display")
	local frame = gui and gui:FindFirstChildOfClass("Frame")
	if not frame then
		return
	end
	local titleLabel = frame:FindFirstChild("Title") :: TextLabel?
	local subLabel = frame:FindFirstChild("Subtitle") :: TextLabel?
	if titleLabel and titleLabel.Text ~= title then
		titleLabel.Text = title
	end
	if subLabel and subLabel.Text ~= subtitle then
		subLabel.Text = subtitle
	end
end

local function updateBoards()
	local gameState = ReplicatedStorage:FindFirstChild("GameState")
	if not gameState then
		return
	end
	local points = Registry.MapService.LobbyPoints
	local phase = gameState:GetAttribute("Phase")
	local remaining = math.max(0, (gameState:GetAttribute("PhaseEndsAt") or 0) - Workspace:GetServerTimeNow())
	local flight = gameState:GetAttribute("FlightNumber") or "LF---"
	local destination = gameState:GetAttribute("Destination") or "TBA"
	if phase == "Lobby" then
		if (gameState:GetAttribute("PhaseEndsAt") or 0) > 0 then
			setScreen(points.DepartureBoard, "NEXT DEPARTURE", "Boarding in " .. Util.FormatTime(remaining) .. "  ·  Destination: Unknown")
			setScreen(points.GateSign, "GATE 7", "BOARDING IN " .. Util.FormatTime(remaining))
		else
			setScreen(points.DepartureBoard, "NEXT DEPARTURE", gameState:GetAttribute("Status") or "Waiting for passengers")
			setScreen(points.GateSign, "GATE 7", "WAITING FOR PASSENGERS")
		end
	elseif phase == "Results" then
		setScreen(points.DepartureBoard, flight .. "  " .. string.upper(destination), "ARRIVED · Next flight boarding soon")
		setScreen(points.GateSign, "GATE 7", "ARRIVALS")
	else
		local alive = gameState:GetAttribute("Alive") or 0
		local total = gameState:GetAttribute("Participants") or 0
		setScreen(points.DepartureBoard, flight .. "  →  " .. string.upper(destination), string.format("IN FLIGHT · %d/%d passengers OK", alive, total))
		setScreen(points.GateSign, "GATE 7", "DEPARTED · " .. flight)
	end
end

local function updateLeaderboard()
	local entries = {}
	for _, player in Players:GetPlayers() do
		local profile = Registry.DataService:Get(player)
		if profile then
			table.insert(entries, { Name = player.DisplayName, Survived = profile.Stats.Survived, Flights = profile.Stats.Flights })
		end
	end
	table.sort(entries, function(a, b)
		return a.Survived > b.Survived
	end)
	local lines = {}
	for i = 1, math.min(6, #entries) do
		local e = entries[i]
		table.insert(lines, string.format("%d. %s  —  %d survived / %d flights", i, e.Name, e.Survived, e.Flights))
	end
	setScreen(Registry.MapService.LobbyPoints.Leaderboard, "TOP FLYERS", if #lines > 0 then table.concat(lines, "\n") else "Survive a flight to get on the board")
	-- leaderstats for the player list
	for _, player in Players:GetPlayers() do
		local profile = Registry.DataService:Get(player)
		local stats = player:FindFirstChild("leaderstats")
		if profile and stats then
			local survived = stats:FindFirstChild("Survived") :: IntValue?
			local credits = stats:FindFirstChild("Credits") :: IntValue?
			if survived then
				survived.Value = profile.Stats.Survived
			end
			if credits then
				credits.Value = profile.Credits
			end
		end
	end
end

function LobbyService:Start()
	local function onPlayer(player: Player)
		local stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		local survived = Instance.new("IntValue")
		survived.Name = "Survived"
		survived.Parent = stats
		local credits = Instance.new("IntValue")
		credits.Name = "Credits"
		credits.Parent = stats
		stats.Parent = player
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	task.spawn(function()
		local tick = 0
		while true do
			task.wait(1)
			tick += 1
			pcall(updateBoards)
			if tick % 5 == 0 then
				pcall(updateLeaderboard)
			end
		end
	end)
end

return LobbyService
