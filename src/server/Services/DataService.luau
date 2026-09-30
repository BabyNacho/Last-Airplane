--[[
	DataService
	Persistent player profiles with safe DataStore handling.

	Safety rules:
	  * Data is only ever written after a successful load. If loading fails the player gets a
	    temporary profile that is NEVER saved over their real data; the service keeps retrying and
	    merges session progress into the real profile once it loads.
	  * Writes use UpdateAsync with a light session lock so a stale server can't overwrite newer data.
	  * Every call is retried with backoff; BindToClose flushes all profiles on shutdown.
	  * Only persistent data is stored (no transient round state).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ShopCatalog = require(ReplicatedStorage.Shared.Config.ShopCatalog)
local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Util = require(ReplicatedStorage.Shared.Util)
local RateLimiter = require(script.Parent.Parent.RateLimiter)
local Registry = require(script.Parent.Parent.Registry)

local DataService = {}

DataService.ProfileLoaded = Signal.new() -- (player, profile)
DataService.StatChanged = Signal.new() -- (player, key, value)

local CFG = GameConfig.Data
local SESSION_TIMEOUT = 330 -- seconds before a stale session lock is ignored

local store: DataStore? = nil
local profiles: { [Player]: any } = {}
local meta: { [Player]: { Temporary: boolean, Dirty: boolean, Saving: boolean, Baseline: any? } } = {}
local pushQueued: { [Player]: boolean } = {}

local function defaultStats()
	return {
		Flights = 0,
		Survived = 0,
		Deaths = 0,
		Rescues = 0,
		Aids = 0,
		PassengersHelped = 0,
		ObjectivesCompleted = 0,
		PerfectLandings = 0,
		ManualApproaches = 0,
		PerfectApproaches = 0,
		FiresExtinguished = 0,
		BraveActions = 0,
		Evacuations = 0,
		DecisionsMade = 0,
		CreditsEarned = 0,
		CurrentStreak = 0,
		BestStreak = 0,
	}
end

function DataService.Template()
	local owned = {}
	for _, id in ShopCatalog.DefaultOwned() do
		owned[id] = true
	end
	return {
		Version = CFG.SchemaVersion,
		Credits = EconomyConfig.StartingCredits,
		Owned = owned,
		Equipped = table.clone(ShopCatalog.DefaultEquipped),
		Stats = defaultStats(),
		DisastersSurvived = {},
		Achievements = {},
		Challenges = { Day = 0, Daily = {}, DailyClaimed = {}, Week = 0, Weekly = {}, WeeklyClaimed = {}, WeekDisasters = {} },
		LastDailyBonus = 0,
		Receipts = {},
		FirstJoin = os.time(),
		LastJoin = os.time(),
	}
end

local function migrate(data)
	Util.Reconcile(data, DataService.Template())
	Util.Reconcile(data.Stats, defaultStats())
	data.Version = CFG.SchemaVersion
	-- drop equipped items that no longer exist in the catalog
	for slot, id in data.Equipped do
		if not ShopCatalog.Get(id) then
			data.Equipped[slot] = ShopCatalog.DefaultEquipped[slot]
		end
	end
	return data
end

local function key(player: Player): string
	return "u_" .. player.UserId
end

local function retry<T>(label: string, fn: () -> T): (boolean, T | string)
	local lastErr
	for attempt = 1, CFG.MaxRetries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		warn(string.format("[DataService] %s failed (attempt %d/%d): %s", label, attempt, CFG.MaxRetries, tostring(result)))
		task.wait(CFG.RetryDelay * attempt)
	end
	return false, lastErr
end

---------------------------------------------------------------- loading

local function loadFromStore(player: Player): (boolean, any)
	if not store then
		return false, "DataStore unavailable"
	end
	local loaded = nil
	local ok, err = retry("load " .. player.UserId, function()
		return (store :: DataStore):UpdateAsync(key(player), function(old)
			old = old or DataService.Template()
			local session = old.Session
			if session and session.JobId ~= game.JobId and os.time() - (session.Time or 0) < SESSION_TIMEOUT then
				-- another server still holds this profile; take it anyway only if it went stale
				error("session locked by another server")
			end
			old.Session = { JobId = game.JobId, Time = os.time() }
			loaded = old
			return old
		end)
	end)
	if not ok then
		return false, err
	end
	return true, migrate(loaded)
end

local function mergeTemporary(real, temp)
	local template = DataService.Template()
	real.Credits += math.max(0, temp.Credits - template.Credits)
	for id in temp.Owned do
		real.Owned[id] = true
	end
	for stat, value in temp.Stats do
		if type(value) == "number" and stat ~= "CurrentStreak" and stat ~= "BestStreak" then
			real.Stats[stat] = (real.Stats[stat] or 0) + value
		end
	end
	for disaster, count in temp.DisastersSurvived do
		real.DisastersSurvived[disaster] = (real.DisastersSurvived[disaster] or 0) + count
	end
	for id, stamp in temp.Achievements do
		real.Achievements[id] = real.Achievements[id] or stamp
	end
	for _, receipt in temp.Receipts do
		table.insert(real.Receipts, receipt)
	end
	return real
end

local function onPlayerAdded(player: Player)
	local ok, result = loadFromStore(player)
	if not player.Parent then
		return
	end
	if ok then
		profiles[player] = result
		meta[player] = { Temporary = false, Dirty = true, Saving = false }
		result.LastJoin = os.time()
		player:SetAttribute("DataLoaded", true)
	else
		warn("[DataService] using temporary profile for", player.Name, result)
		profiles[player] = DataService.Template()
		meta[player] = { Temporary = true, Dirty = false, Saving = false }
		player:SetAttribute("DataLoaded", false)
		task.delay(3, function()
			if player.Parent then
				Registry.EffectsService:Notify("Your progress can't be loaded right now. We'll keep trying - nothing will be lost.", "warn", player)
			end
		end)
		-- keep retrying in the background
		task.spawn(function()
			for _ = 1, 20 do
				task.wait(45)
				if not player.Parent or not meta[player] or not meta[player].Temporary then
					return
				end
				local retryOk, real = loadFromStore(player)
				if retryOk and player.Parent then
					profiles[player] = mergeTemporary(real, profiles[player])
					meta[player] = { Temporary = false, Dirty = true, Saving = false }
					player:SetAttribute("DataLoaded", true)
					DataService:Push(player)
					Registry.EffectsService:Notify("Progress restored and saving again.", "good", player)
					return
				end
			end
		end)
	end
	DataService.ProfileLoaded:Fire(player, profiles[player])
	DataService:Push(player)
end

---------------------------------------------------------------- saving

function DataService:Save(player: Player, release: boolean?): boolean
	local profile = profiles[player]
	local m = meta[player]
	if not profile or not m or m.Temporary or not store then
		return false
	end
	if m.Saving then
		-- wait for the in-flight save, then save again with the latest data
		local waited = 0
		while m.Saving and waited < 15 do
			task.wait(0.25)
			waited += 0.25
		end
	end
	m.Saving = true
	local snapshot = Util.DeepCopy(profile)
	snapshot.Session = if release then nil else { JobId = game.JobId, Time = os.time() }
	local ok, err = retry("save " .. player.UserId, function()
		return (store :: DataStore):UpdateAsync(key(player), function(old)
			if old and old.Session and old.Session.JobId ~= game.JobId and os.time() - (old.Session.Time or 0) < SESSION_TIMEOUT then
				-- someone else owns the profile now; never overwrite their newer data
				return nil
			end
			return snapshot
		end)
	end)
	m.Saving = false
	if ok then
		m.Dirty = false
	else
		warn("[DataService] save failed for", player.Name, err)
	end
	return ok
end

function DataService:MarkDirty(player: Player)
	local m = meta[player]
	if m then
		m.Dirty = true
	end
end

---------------------------------------------------------------- accessors

function DataService:Get(player: Player)
	return profiles[player]
end

function DataService:IsTemporary(player: Player): boolean
	local m = meta[player]
	return m == nil or m.Temporary
end

function DataService:Snapshot(player: Player)
	local profile = profiles[player]
	if not profile then
		return nil
	end
	local owned = {}
	for id in profile.Owned do
		table.insert(owned, id)
	end
	return {
		Credits = profile.Credits,
		Owned = owned,
		Equipped = profile.Equipped,
		Stats = profile.Stats,
		DisastersSurvived = profile.DisastersSurvived,
		Achievements = profile.Achievements,
		Challenges = Registry.ChallengeService and Registry.ChallengeService:View(player) or nil,
		Passes = Registry.MonetizationService and Registry.MonetizationService:PassesFor(player) or {},
		Temporary = self:IsTemporary(player),
	}
end

-- Sends the latest profile snapshot to the client (batched per frame).
function DataService:Push(player: Player)
	if pushQueued[player] then
		return
	end
	pushQueued[player] = true
	task.defer(function()
		pushQueued[player] = nil
		if player.Parent and profiles[player] then
			Net.Event("ProfileUpdated"):FireClient(player, self:Snapshot(player))
			player:SetAttribute("Credits", profiles[player].Credits)
		end
	end)
end

function DataService:AddCredits(player: Player, amount: number, _reason: string?): number
	local profile = profiles[player]
	if not profile or amount == 0 then
		return 0
	end
	amount = math.floor(amount)
	profile.Credits = math.max(0, profile.Credits + amount)
	if amount > 0 then
		profile.Stats.CreditsEarned += amount
	end
	self:MarkDirty(player)
	self:Push(player)
	return amount
end

function DataService:SpendCredits(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or amount < 0 or profile.Credits < amount then
		return false
	end
	profile.Credits -= amount
	self:MarkDirty(player)
	self:Push(player)
	return true
end

function DataService:Owns(player: Player, itemId: string): boolean
	local profile = profiles[player]
	return profile ~= nil and profile.Owned[itemId] == true
end

function DataService:Grant(player: Player, itemId: string)
	local profile = profiles[player]
	if not profile or not ShopCatalog.Get(itemId) then
		return
	end
	profile.Owned[itemId] = true
	self:MarkDirty(player)
	self:Push(player)
end

function DataService:SetEquipped(player: Player, slot: string, itemId: string?)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.Equipped[slot] = itemId
	self:MarkDirty(player)
	self:Push(player)
end

function DataService:IncrementStat(player: Player, stat: string, amount: number?)
	local profile = profiles[player]
	if not profile then
		return
	end
	local value = (profile.Stats[stat] or 0) + (amount or 1)
	profile.Stats[stat] = value
	self:MarkDirty(player)
	DataService.StatChanged:Fire(player, stat, value)
end

function DataService:SetStat(player: Player, stat: string, value: number)
	local profile = profiles[player]
	if profile then
		profile.Stats[stat] = value
		self:MarkDirty(player)
		DataService.StatChanged:Fire(player, stat, value)
	end
end

function DataService:HasReceipt(player: Player, receiptId: string): boolean
	local profile = profiles[player]
	return profile ~= nil and table.find(profile.Receipts, receiptId) ~= nil
end

function DataService:AddReceipt(player: Player, receiptId: string)
	local profile = profiles[player]
	if not profile then
		return
	end
	table.insert(profile.Receipts, receiptId)
	while #profile.Receipts > CFG.ReceiptHistory do
		table.remove(profile.Receipts, 1)
	end
	self:MarkDirty(player)
end

---------------------------------------------------------------- lifecycle

function DataService:Init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(CFG.StoreName)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStore unavailable (enable Studio API access to test saving):", result)
	end
end

function DataService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		if profiles[player] then
			self:Save(player, true)
		end
		profiles[player] = nil
		meta[player] = nil
	end)

	-- autosave
	task.spawn(function()
		while true do
			task.wait(CFG.AutosaveInterval)
			for player, m in meta do
				if m.Dirty and not m.Temporary and player.Parent then
					task.spawn(self.Save, self, player, false)
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				self:Save(player, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + (if RunService:IsStudio() then 5 else 25)
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)

	Net.Function("GetProfile").OnServerInvoke = function(player)
		if not RateLimiter.Allow(player, "GetProfile") then
			return nil
		end
		return self:Snapshot(player)
	end
end

return DataService
