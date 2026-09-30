--[[
	verify-place: opens a built .rbxl and fails unless the complete game is inside it.
	Usage: lune run tools/verify-place <place.rbxl>
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local path = process.args[1] or "LastFlight.rbxl"
local bytes = fs.readFile(path)
local game = roblox.deserializePlace(bytes)
local failures = {}
local report = {}

local function check(label: string, ok: boolean, detail: string)
	table.insert(report, string.format("%s %-44s %s", if ok then "[ok]  " else "[FAIL]", label, detail))
	if not ok then
		table.insert(failures, label)
	end
end

local function find(root, pathString: string)
	local node = root
	for name in string.gmatch(pathString, "[^/]+") do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function count(root, predicate): number
	local n = 0
	if root then
		for _, d in root:GetDescendants() do
			if predicate(d) then
				n += 1
			end
		end
	end
	return n
end

local workspace = game:GetService("Workspace")
local replicated = game:GetService("ReplicatedStorage")
local sss = game:GetService("ServerScriptService")
local starterPlayer = game:GetService("StarterPlayer")
local lighting = game:GetService("Lighting")

local isPart = function(d)
	return d:IsA("BasePart")
end

check("file size", #bytes > 200000, string.format("%d bytes", #bytes))
check("instance count (world baked in)", #game:GetDescendants() > 1800, #game:GetDescendants() .. " instances")
check("Roblox binary header", string.sub(bytes, 1, 8) == "<roblox!", string.sub(bytes, 1, 8))

local airplane = find(workspace, "World/Airplane")
local lobby = find(workspace, "World/Lobby")
check("Workspace/World/Airplane", airplane ~= nil and airplane:IsA("Model"), airplane and airplane.ClassName or "missing")
check("airplane parts", count(airplane, isPart) > 1000, count(airplane, isPart) .. " parts")
for _, section in { "Cockpit", "FrontGalley", "FirstClass", "Economy", "AftGalley", "ServiceBay", "Exterior", "FireCells", "BoardingSpawns" } do
	check("airplane section " .. section, find(airplane, section) ~= nil, if find(airplane, section) then "present" else "missing")
end
check("airplane seats", count(airplane, function(d)
	return d:IsA("Seat")
end) >= 106, count(airplane, function(d)
	return d:IsA("Seat")
end) .. " seats")
check("Workspace/World/Lobby", lobby ~= nil and lobby:IsA("Model"), lobby and lobby.ClassName or "missing")
check("lobby parts", count(lobby, isPart) > 200, count(lobby, isPart) .. " parts")
local spawn = find(workspace, "World/Lobby/LobbySpawn")
check("SpawnLocation", spawn ~= nil and spawn:IsA("SpawnLocation"), spawn and spawn.ClassName or "missing")
check("lobby kiosk prompts", count(lobby, function(d)
	return d:IsA("ProximityPrompt")
end) >= 3, count(lobby, function(d)
	return d:IsA("ProximityPrompt")
end) .. " prompts")
check("tagged cabin seats", count(airplane, function(d)
	return d:HasTag("AirplaneSeat")
end) >= 100, count(airplane, function(d)
	return d:HasTag("AirplaneSeat")
end) .. " seats tagged AirplaneSeat")

local remotes = replicated:FindFirstChild("Remotes")
local events = count(remotes, function(d)
	return d:IsA("RemoteEvent")
end)
local functions = count(remotes, function(d)
	return d:IsA("RemoteFunction")
end)
check("ReplicatedStorage/Remotes", remotes ~= nil and events >= 20 and functions >= 2, string.format("%d RemoteEvents, %d RemoteFunctions", events, functions))
check("ReplicatedStorage/Shared modules", count(find(replicated, "Shared"), function(d)
	return d:IsA("ModuleScript")
end) >= 15, count(find(replicated, "Shared"), function(d)
	return d:IsA("ModuleScript")
end) .. " ModuleScripts")

local serverMain = find(sss, "Server/Main")
check("ServerScriptService/Server/Main (Script)", serverMain ~= nil and serverMain.ClassName == "Script", serverMain and serverMain.ClassName or "missing")
check("server modules", count(find(sss, "Server"), function(d)
	return d:IsA("ModuleScript")
end) >= 40, count(find(sss, "Server"), function(d)
	return d:IsA("ModuleScript")
end) .. " ModuleScripts")
local clientMain = find(starterPlayer, "StarterPlayerScripts/Client/Main")
check("StarterPlayerScripts/Client/Main (LocalScript)", clientMain ~= nil and clientMain.ClassName == "LocalScript", clientMain and clientMain.ClassName or "missing")
check("client controllers", count(find(starterPlayer, "StarterPlayerScripts/Client/Controllers"), function(d)
	return d:IsA("ModuleScript")
end) >= 15, "UI is built by these LocalScripts when you press Play")
check("StarterCharacterScripts/Health override", find(starterPlayer, "StarterCharacterScripts/Health") ~= nil, "present")
local emptySource = count(game, function(d)
	return (d:IsA("LuaSourceContainer")) and #d.Source < 20
end)
check("scripts have source code", emptySource == 0, emptySource .. " empty scripts")
check("Lighting configured", lighting.ClockTime == 14 and lighting.GlobalShadows == true, "ClockTime=" .. tostring(lighting.ClockTime))
check("Workspace.StreamingEnabled = false", workspace.StreamingEnabled == false, tostring(workspace.StreamingEnabled))
check("no harness attributes leaked", count(game, function(d)
	return d:GetAttribute("__SimId") ~= nil
end) == 0, "clean")

print(table.concat(report, "\n"))
print(string.format("\nTotal instances in place: %d", #game:GetDescendants()))
if #failures > 0 then
	print("\nVERIFICATION FAILED: " .. table.concat(failures, ", "))
	process.exit(1)
end
print("\nVERIFICATION PASSED: " .. path .. " contains the complete game.")
