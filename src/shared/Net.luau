--[[
	Net
	Single source of truth for every RemoteEvent / RemoteFunction.
	The server creates all remotes at boot (Net.Setup) so clients never race a missing remote.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.Events = {
	-- server -> client
	"Notify", -- toast message {Text, Kind}
	"Warning", -- big atmospheric alert {Title, Subtitle, Severity}
	"Announcement", -- intercom subtitle {Speaker, Text, Garbled}
	"Effect", -- one-shot visual/audio effect {Name, ...}
	"ObjectivesUpdated", -- full objective list
	"ConditionUpdated", -- own condition snapshot
	"DecisionOpened",
	"DecisionUpdated",
	"DecisionClosed",
	"Results",
	"ProfileUpdated", -- persistent data snapshot (credits, owned, stats...)
	"AchievementUnlocked",
	"Reward", -- floating credit popup
	"Stumble", -- turbulence impulse for the local character
	"ManualFlight", -- cockpit minigame state
	"SeatAssigned",
	"PurchaseResult",
	-- client -> server
	"DecisionVote",
	"ShopPurchase",
	"Equip",
	"PlayEmote",
	"PilotInput",
	"UseTool",
	"SpectateRequest",
	"ClientReady",
}

Net.Functions = {
	"GetProfile",
	"GetShopState",
}

local folder: Folder? = nil

local function getFolder(): Folder
	if folder then
		return folder
	end
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild("Remotes")
		if existing and existing:IsA("Folder") then
			folder = existing
		else
			local created = Instance.new("Folder")
			created.Name = "Remotes"
			created.Parent = ReplicatedStorage
			folder = created
		end
	else
		folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	end
	return folder :: Folder
end

function Net.Setup()
	assert(RunService:IsServer(), "Net.Setup is server only")
	local root = getFolder()
	for _, name in Net.Events do
		if not root:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = root
		end
	end
	for _, name in Net.Functions do
		if not root:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = root
		end
	end
end

function Net.Event(name: string): RemoteEvent
	local root = getFolder()
	local remote = if RunService:IsServer() then root:FindFirstChild(name) else root:WaitForChild(name, 30)
	assert(remote and remote:IsA("RemoteEvent"), "Missing RemoteEvent " .. name)
	return remote
end

function Net.Function(name: string): RemoteFunction
	local root = getFolder()
	local remote = if RunService:IsServer() then root:FindFirstChild(name) else root:WaitForChild(name, 30)
	assert(remote and remote:IsA("RemoteFunction"), "Missing RemoteFunction " .. name)
	return remote
end

-- Convenience: fire to every player in a list (skips players who already left).
function Net.FireList(name: string, players: { Player }, ...)
	local remote = Net.Event(name)
	for _, player in players do
		if player.Parent then
			remote:FireClient(player, ...)
		end
	end
end

return Net
