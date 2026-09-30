--[[
	LAST FLIGHT - server entry point.
	Creates remotes, loads every service into the Registry, then runs Init (synchronous setup)
	and Start (connections / loops) in a fixed order. A failing service is reported but does
	not stop the others from starting.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Registry = require(script.Parent.Registry)

Net.Setup()

local ORDER = {
	-- core
	"DataService",
	"MapService",
	"EffectsService",
	"FlightService",
	"InteractionService",
	"ConditionService",
	"ObjectiveService",
	"DecisionService",
	-- cabin & gameplay systems
	"CabinService",
	"EquipmentService",
	"FireSystem",
	"OxygenSystem",
	"TurbulenceSystem",
	"CockpitSystem",
	"NPCService",
	"RescueService",
	"DisasterService",
	"LandingService",
	-- meta / economy
	"RewardService",
	"AchievementService",
	"ChallengeService",
	"CosmeticService",
	"ShopService",
	"MonetizationService",
	"EmoteService",
	"LobbyService",
	"DevService", -- Studio-only chat commands
	-- round loop last
	"RoundService",
}

local folders = { script.Parent.Services, script.Parent.Systems }

local function find(name: string): ModuleScript?
	for _, folder in folders do
		local module = folder:FindFirstChild(name)
		if module and module:IsA("ModuleScript") then
			return module
		end
	end
	return nil
end

for _, name in ORDER do
	local module = find(name)
	if not module then
		warn("[Main] missing service module:", name)
		continue
	end
	local ok, result = pcall(require, module)
	if ok then
		Registry[name] = result
	else
		warn("[Main] failed to load", name, result)
	end
end

for _, name in ORDER do
	local service = Registry[name]
	if service and type(service.Init) == "function" then
		local ok, err = pcall(service.Init, service)
		if not ok then
			warn("[Main] Init failed:", name, err)
		end
	end
end

for _, name in ORDER do
	local service = Registry[name]
	if service and type(service.Start) == "function" then
		local ok, err = pcall(service.Start, service)
		if not ok then
			warn("[Main] Start failed:", name, err)
		end
	end
end

print("[LAST FLIGHT] server ready")
