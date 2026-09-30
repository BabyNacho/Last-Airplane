--[[
	EmoteService
	Plays owned emotes on the server (so everyone sees them). Validates ownership, state and
	cooldown. Looping emotes stop when the player starts moving.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local Net = require(ReplicatedStorage.Shared.Net)
local ShopCatalog = require(ReplicatedStorage.Shared.Config.ShopCatalog)
local RateLimiter = require(script.Parent.Parent.RateLimiter)
local Registry = require(script.Parent.Parent.Registry)

local EmoteService = {}

local tracks: { [Player]: AnimationTrack } = {}

local function stop(player: Player)
	local track = tracks[player]
	if track then
		track:Stop(0.2)
		tracks[player] = nil
	end
end

local function onEmote(player: Player, itemId: any)
	if type(itemId) ~= "string" or not RateLimiter.Allow(player, "Emote") then
		return
	end
	local item = ShopCatalog.Get(itemId)
	if not item or item.Type ~= "Emote" or not Registry.ShopService:Owns(player, itemId) then
		return
	end
	local state = Registry.ConditionService:GetState(player)
	if state == Enums.Condition.Unconscious or state == Enums.Condition.Dead then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or humanoid.Sit then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	stop(player)
	local animation = Instance.new("Animation")
	animation.AnimationId = item.Data.AnimationId
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		return
	end
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = item.Data.Looped == true
	track:Play(0.2)
	tracks[player] = track
	if track.Looped then
		local connection
		connection = humanoid.Running:Connect(function(speed)
			if speed > 0.5 then
				connection:Disconnect()
				if tracks[player] == track then
					stop(player)
				end
			end
		end)
		task.delay(20, function()
			if connection.Connected then
				connection:Disconnect()
			end
			if tracks[player] == track then
				stop(player)
			end
		end)
	end
end

function EmoteService:Start()
	Net.Event("PlayEmote").OnServerEvent:Connect(onEmote)
	Players.PlayerRemoving:Connect(function(player)
		tracks[player] = nil
	end)
	Registry.ConditionService.Downed:Connect(stop)
end

return EmoteService
