--[[
	RateLimiter
	Token bucket per player per remote. Remotes that exceed their budget are dropped silently.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local RateLimiter = {}

local buckets: { [Player]: { [string]: { tokens: number, last: number } } } = {}

function RateLimiter.Allow(player: Player, key: string): boolean
	local limits = GameConfig.RateLimits[key] or GameConfig.RateLimits.Default
	local capacity, refill = limits[1], limits[2]
	local playerBuckets = buckets[player]
	if not playerBuckets then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end
	local now = os.clock()
	local bucket = playerBuckets[key]
	if not bucket then
		bucket = { tokens = capacity, last = now }
		playerBuckets[key] = bucket
	end
	bucket.tokens = math.min(capacity, bucket.tokens + (now - bucket.last) * refill)
	bucket.last = now
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
end)

return RateLimiter
