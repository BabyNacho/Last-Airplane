--[[
	bake-place: turns the Rojo output (scripts only) into the complete Studio place.

	Rojo only packages source files. The world (lobby, airplane, spawn, props) and the remotes are
	created by the game's own code (MapService / Net.Setup) when a server starts, so a plain Rojo
	build looks empty in Studio's Edit mode. This step runs that same code at build time and saves
	the resulting Instances into the place file. At runtime MapService replaces the baked world with
	a fresh one, so gameplay is identical.

	Usage: lune run tools/bake-place <rojo-output.rbxl> <final-output.rbxl>
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local World = require("../tests/sim/World")

local input = process.args[1] or "build/LastFlight.rojo.rbxl"
local output = process.args[2] or "LastFlight.rbxl"

local world = World.new({ PlacePath = input })
local rawGame = world.M.unwrap(world.Game)
local replicated = world.Game:GetService("ReplicatedStorage")
local server = world.Game:GetService("ServerScriptService"):FindFirstChild("Server")

-- 1. RemoteEvents / RemoteFunctions (Net.Setup is idempotent at runtime)
world.Require(replicated:FindFirstChild("Shared"):FindFirstChild("Net")).Setup()
-- 2. Lobby, airplane interior/exterior, spawn, props (the same builders the server uses)
world.Require(server:FindFirstChild("Services"):FindFirstChild("MapService")):Init()

if #world.Errors > 0 or #world.Warnings > 0 then
	for _, line in world.Errors do
		print("ERROR: " .. line)
	end
	for _, line in world.Warnings do
		print("WARN: " .. line)
	end
	error("bake failed")
end

-- 3. build stamp (informational only)
local info = roblox.Instance.new("StringValue")
info.Name = "LastFlightBuildInfo"
info.Value = string.format("commit %s", process.env.GITHUB_SHA or "local")
info.Parent = rawGame:GetService("ReplicatedStorage")

-- 4. remove the harness's internal bookkeeping attribute, and store text fonts as proper Font
--    values (Lune keeps a legacy `Font = Enum.Font.X` assignment as an EnumItem in FontFace,
--    which the binary serializer rejects)
local stripped = 0
local function strip(inst)
	if inst:GetAttribute("__SimId") ~= nil then
		inst:SetAttribute("__SimId", nil)
		stripped += 1
	end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		local ok, legacy = pcall(function()
			return inst.Font
		end)
		if ok and typeof(legacy) == "EnumItem" then
			inst.FontFace = roblox.Font.fromEnum(legacy)
		end
	end
end
strip(rawGame)
for _, d in rawGame:GetDescendants() do
	strip(d)
end

fs.writeFile(output, roblox.serializePlace(rawGame))
print(string.format("Baked %s -> %s (%d instances, %d bytes)", input, output, #rawGame:GetDescendants(), #fs.readFile(output)))
