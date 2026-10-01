--[[
	EmoteService
	Plays owned emotes on the server (so everyone sees them). Validates ownership, state and
	cooldown. Looping emotes stop when the player starts moving. Each emote can also show an
	emoji bubble above the player's head (purely visual).
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

local function bubble(character: Model, data)
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head or not data.Bubble then
		return
	end
	local old = head:FindFirstChild("LF_EmoteBubble")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "LF_EmoteBubble"
	gui.Size = UDim2.fromOffset(if data.BubbleText then 190 else 70, 64)
	gui.StudsOffset = Vector3.new(0, 4.2, 0)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	gui.Adornee = head
	local frame = Instance.new("TextLabel")
	frame.Name = "Bubble"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	frame.BackgroundTransparency = 0.05
	frame.Font = Enum.Font.GothamBlack
	frame.TextScaled = true
	frame.TextColor3 = Color3.fromRGB(30, 35, 50)
	frame.Text = if data.BubbleText then data.Bubble .. " " .. data.BubbleText else data.Bubble
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.4, 0)
	corner.Parent = frame
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = frame
	gui.Parent = head
	task.delay(data.BubbleTime or 2.5, function()
		gui:Destroy()
	end)
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
	stop(player)
	bubble(character :: Model, item.Data)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator or not item.Data.AnimationId then
		return
	end
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
	if item.Data.Speed then
		track:AdjustSpeed(item.Data.Speed)
	end
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
