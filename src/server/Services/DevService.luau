--[[
	DevService (Roblox Studio only)
	Chat commands for testing, registered only when running in Studio - they never exist on live
	servers:
		/skip               finish the current phase immediately
		/disaster <Id>      force the next round's disaster (e.g. /disaster CabinFire), "/disaster off" to clear
		/credits            +1000 Flight Credits
		/hurt               take 40 damage (test the condition & rescue systems)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Registry = require(script.Parent.Parent.Registry)

local DevService = {}

local function command(name: string, alias: string, handler: (Player, string) -> ())
	local cmd = Instance.new("TextChatCommand")
	cmd.Name = "LF_" .. name
	cmd.PrimaryAlias = alias
	cmd.Parent = TextChatService
	cmd.Triggered:Connect(function(source: TextSource, text: string)
		local player = game:GetService("Players"):GetPlayerByUserId(source.UserId)
		if player then
			local ok, err = pcall(handler, player, text)
			if not ok then
				warn("[DevService]", name, err)
			end
		end
	end)
end

function DevService:Start()
	if not RunService:IsStudio() then
		return
	end
	local ok, err = pcall(function()
		command("Skip", "/skip", function(player)
			Registry.RoundService:SkipPhase()
			Registry.EffectsService:Notify("[DEV] Phase skipped", "info", player)
		end)
		command("Disaster", "/disaster", function(player, text)
			local id = string.match(text, "^/disaster%s+(%S+)")
			if id == "off" then
				GameConfig.StudioForceDisaster = nil
			elseif id and table.find(Registry.DisasterService:Available(), id) then
				GameConfig.StudioForceDisaster = id
			else
				Registry.EffectsService:Notify("[DEV] Unknown disaster. Options: " .. table.concat(Registry.DisasterService:Available(), ", "), "warn", player)
				return
			end
			Registry.EffectsService:Notify("[DEV] Next disaster: " .. tostring(GameConfig.StudioForceDisaster or "random"), "info", player)
		end)
		command("Credits", "/credits", function(player)
			Registry.DataService:AddCredits(player, 1000, "dev")
		end)
		command("Hurt", "/hurt", function(player)
			Registry.ConditionService:Damage(player, 40, "Dev command")
		end)
	end)
	if not ok then
		warn("[DevService] chat commands unavailable:", err)
	end
end

return DevService
