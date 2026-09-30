--[[
	World: loads the built place, provides the sandboxed Roblox environment for server scripts
	(services, globals, virtual time) and fake players with characters.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Membrane = require("./Membrane")
local Scheduler = require("./Scheduler")

local World = {}

function World.new(options: { StoreFailures: number?, Seed: number? }?)
	options = options or {}
	local self = {}
	self.Errors = {} :: { string }
	self.Warnings = {} :: { string }
	self.Prints = {} :: { string }
	self.ClientLog = {} :: { any }
	self.ClientHandlers = {} :: { (string, any, ...any) -> () }
	self.BindToClose = {} :: { any }
	self.Store = {} :: { [string]: any }
	self.StoreFailures = options.StoreFailures or 0
	self.StoreCalls = 0

	local scheduler = Scheduler.new(function(message)
		table.insert(self.Errors, message)
	end)
	self.Scheduler = scheduler

	local rawGame = roblox.deserializePlace(fs.readFile("build/LastFlight.rbxl"))
	local playersByCharacter: { [number]: any } = {}

	local M
	local services: { [string]: any } = {}
	M = Membrane.new(scheduler, {
		OnFireClient = function(remote, player, ...)
			local entry = { Remote = remote, Player = player, Args = table.pack(...), Time = scheduler.Now }
			table.insert(self.ClientLog, entry)
			for _, handler in self.ClientHandlers do
				handler(remote, player, ...)
			end
		end,
		OnBindToClose = function(fn)
			table.insert(self.BindToClose, fn)
		end,
		GetService = function(name)
			return services[name] or M.wrap(rawGame:GetService(name))
		end,
		PlayerFromCharacter = function(character)
			if character == nil then
				return nil
			end
			local id = character:GetAttribute("__SimId")
			return id and playersByCharacter[id]
		end,
		BuildRig = function(name)
			return self:BuildRigRaw(name)
		end,
	})
	self.M = M
	self.Game = M.wrap(rawGame)
	local lib = M.Library

	---------------------------------------------------------------- services
	local tagCache: { [string]: { any } } = {}
	local tagSignals: { [string]: any } = {}
	services.CollectionService = {
		AddTag = function(_, inst, tag)
			M.unwrap(inst):AddTag(tag)
			tagCache[tag] = nil
			if tagSignals[tag] then
				tagSignals[tag]:Fire(inst)
			end
		end,
		RemoveTag = function(_, inst, tag)
			M.unwrap(inst):RemoveTag(tag)
			tagCache[tag] = nil
		end,
		HasTag = function(_, inst, tag)
			return M.unwrap(inst):HasTag(tag)
		end,
		GetTagged = function(_, tag)
			local cached = tagCache[tag]
			if not cached then
				cached = {}
				for _, d in rawGame:GetDescendants() do
					if d:HasTag(tag) then
						table.insert(cached, d)
					end
				end
				tagCache[tag] = cached
			end
			local out = {}
			for _, inst in cached do
				if inst:IsDescendantOf(rawGame) then
					table.insert(out, M.wrap(inst))
				end
			end
			return out
		end,
		GetInstanceAddedSignal = function(_, tag)
			tagSignals[tag] = tagSignals[tag] or M.Signal.new(tag)
			return tagSignals[tag]
		end,
	}
	services.TweenService = {
		Create = function(_, inst, _info, goals)
			local tween = { Completed = M.Signal.new("Completed") }
			function tween.Play()
				for key, value in goals do
					inst[key] = value
				end
				tween.Completed:Fire(roblox.Enum.PlaybackState.Completed)
			end
			function tween.Cancel() end
			function tween.Pause() end
			return tween
		end,
	}
	services.RunService = {
		IsServer = function()
			return true
		end,
		IsClient = function()
			return false
		end,
		IsStudio = function()
			return true
		end,
		Heartbeat = M.Signal.new("Heartbeat"),
		Stepped = M.Signal.new("Stepped"),
	}
	local guid = 0
	services.HttpService = {
		GenerateGUID = function()
			guid += 1
			return string.format("guid-%06d", guid)
		end,
		JSONEncode = function(_, v)
			return tostring(v)
		end,
	}
	local function storeCall(fn)
		self.StoreCalls += 1
		if self.StoreFailures > 0 then
			self.StoreFailures -= 1
			error("simulated DataStore outage")
		end
		lib.wait(0.05)
		return fn()
	end
	local deepCopy
	function deepCopy(v)
		if type(v) ~= "table" then
			return v
		end
		local out = {}
		for k, inner in v do
			out[k] = deepCopy(inner)
		end
		return out
	end
	services.DataStoreService = {
		GetDataStore = function(_, _name)
			return {
				UpdateAsync = function(_, key, transform)
					return storeCall(function()
						local result = transform(deepCopy(self.Store[key]))
						if result ~= nil then
							self.Store[key] = deepCopy(result)
						end
						return result
					end)
				end,
				GetAsync = function(_, key)
					return storeCall(function()
						return deepCopy(self.Store[key])
					end)
				end,
				SetAsync = function(_, key, value)
					return storeCall(function()
						self.Store[key] = deepCopy(value)
					end)
				end,
			}
		end,
	}
	local marketplace = {
		PromptGamePassPurchaseFinished = M.Signal.new("PromptGamePassPurchaseFinished"),
		UserOwnsGamePassAsync = function()
			return false
		end,
	}
	services.MarketplaceService = setmetatable({}, {
		__index = marketplace,
		__newindex = function(_, key, value)
			marketplace[key] = value
		end,
	})
	self.Marketplace = marketplace

	---------------------------------------------------------------- environment
	local vtask = lib
	local Random = {}
	Random.__index = Random
	function Random.new(seed: number?)
		local state = math.floor(math.abs(seed or scheduler.Now * 1000 + 12345)) % 2147483647
		if state == 0 then
			state = 1
		end
		return setmetatable({ State = state }, Random)
	end
	function Random:_next(): number
		self.State = (self.State * 48271) % 2147483647
		return self.State / 2147483647
	end
	function Random:NextNumber(min: number?, max: number?): number
		local r = self:_next()
		if min == nil then
			return r
		end
		return (min :: number) + r * ((max :: number) - (min :: number))
	end
	function Random:NextInteger(min: number, max: number): number
		return math.min(max, min + math.floor(self:_next() * (max - min + 1)))
	end

	local TweenInfo = {
		new = function(...)
			return { ... }
		end,
	}
	local vos = table.clone(os)
	vos.clock = function()
		return scheduler.Now
	end
	vos.time = function(t)
		if t then
			return os.time(t)
		end
		return scheduler:Time()
	end

	local moduleCache: { [number]: any } = {}
	local loading: { [number]: boolean } = {}
	local env
	local function simRequire(target)
		if type(target) ~= "table" or not M.isProxy(target) then
			error("sim require: unsupported target " .. tostring(target))
		end
		local inst = M.unwrap(target)
		local id = inst:GetAttribute("__SimId")
		if moduleCache[id] ~= nil then
			return moduleCache[id]
		end
		if loading[id] then
			error("cyclic require of " .. inst:GetFullName())
		end
		loading[id] = true
		local fn = luau.load(inst.Source, { debugName = inst:GetFullName(), environment = env(target) })
		local result = fn()
		loading[id] = nil
		moduleCache[id] = result
		return result
	end

	function env(scriptProxy)
		local globals = {
			script = scriptProxy,
			game = self.Game,
			workspace = self.Game:GetService("Workspace"),
			require = simRequire,
			task = vtask,
			wait = vtask.wait,
			delay = vtask.delay,
			spawn = vtask.spawn,
			tick = function()
				return scheduler:Time()
			end,
			os = vos,
			Random = Random,
			TweenInfo = TweenInfo,
			typeof = function(v)
				if M.isProxy(v) then
					return "Instance"
				end
				return typeof(v)
			end,
			Instance = {
				new = function(className, parent)
					return M.Instance(className, parent)
				end,
			},
			print = function(...)
				local parts = {}
				for i = 1, select("#", ...) do
					table.insert(parts, tostring((select(i, ...))))
				end
				table.insert(self.Prints, table.concat(parts, " "))
			end,
			warn = function(...)
				local parts = {}
				for i = 1, select("#", ...) do
					table.insert(parts, tostring((select(i, ...))))
				end
				table.insert(self.Warnings, table.concat(parts, " "))
			end,
		}
		for _, name in { "Vector3", "Vector2", "CFrame", "Color3", "UDim", "UDim2", "Enum", "NumberSequence", "NumberSequenceKeypoint", "ColorSequence", "ColorSequenceKeypoint", "NumberRange", "PhysicalProperties", "BrickColor", "Rect", "Font" } do
			globals[name] = (roblox :: any)[name]
		end
		return setmetatable(globals, { __index = _G })
	end
	self.Env = env
	self.Require = simRequire

	---------------------------------------------------------------- players
	local nextUserId = 1000
	function self:BuildRigRaw(name: string)
		local model = roblox.Instance.new("Model")
		model.Name = name
		local root = roblox.Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = roblox.Vector3.new(2, 2, 1)
		root.Parent = model
		local torso = roblox.Instance.new("Part")
		torso.Name = "UpperTorso"
		torso.Size = roblox.Vector3.new(2, 1.6, 1)
		torso.Parent = model
		local head = roblox.Instance.new("Part")
		head.Name = "Head"
		head.Size = roblox.Vector3.new(1.2, 1.2, 1.2)
		head.CFrame = roblox.CFrame.new(0, 2, 0)
		head.Parent = model
		local neck = roblox.Instance.new("Motor6D")
		neck.Name = "Neck"
		neck.Parent = head
		local humanoid = roblox.Instance.new("Humanoid")
		humanoid.MaxHealth = 100
		humanoid.Health = 100
		humanoid.WalkSpeed = 16
		humanoid.JumpPower = 50
		humanoid.Parent = model
		local animator = roblox.Instance.new("Animator")
		animator.Parent = humanoid
		model.PrimaryPart = root
		return model
	end

	function self:Spawn(playerProxy)
		local player = M.unwrap(playerProxy)
		local rig = self:BuildRigRaw(player.Name)
		local rigProxy = M.wrap(rig)
		playersByCharacter[rig:GetAttribute("__SimId")] = player
		rigProxy.Parent = self.Game:GetService("Workspace")
		local spawnPart = rawGame:GetService("Workspace"):FindFirstChild("World"):FindFirstChild("Lobby"):FindFirstChild("LobbySpawn")
		rigProxy:PivotTo(spawnPart.CFrame + roblox.Vector3.new(0, 4, 0))
		local backpack = player:FindFirstChildOfClass("Backpack")
		if backpack then
			backpack:ClearAllChildren()
		else
			M.Instance("Backpack", playerProxy)
		end
		M.shadow(playerProxy, "Character", rig)
		M.signalFor(playerProxy, "CharacterAdded"):Fire(rigProxy)
		-- auto respawn after death (CharacterAutoLoads)
		local humanoid = rigProxy:FindFirstChildOfClass("Humanoid")
		humanoid.Died:Connect(function()
			lib.delay(4, function()
				if playerProxy.Parent then
					self:Spawn(playerProxy)
				end
			end)
		end)
		return rigProxy
	end

	function self:AddPlayer(name: string)
		nextUserId += 1
		local playerProxy = M.Instance("Player")
		playerProxy.Name = name
		M.shadow(playerProxy, "UserId", nextUserId)
		M.shadow(playerProxy, "DisplayName", name)
		local playersService = self.Game:GetService("Players")
		playerProxy.Parent = playersService
		M.signalFor(playersService, "PlayerAdded"):Fire(playerProxy)
		self:Spawn(playerProxy)
		return playerProxy
	end

	function self:RemovePlayer(playerProxy)
		local playersService = self.Game:GetService("Players")
		M.signalFor(playersService, "PlayerRemoving"):Fire(playerProxy)
		lib.wait(0.1)
		local character = playerProxy.Character
		if character then
			character:Destroy()
		end
		playerProxy.Parent = nil
	end

	function self:Boot()
		local main = rawGame:GetService("ServerScriptService"):FindFirstChild("Server"):FindFirstChild("Main")
		local mainProxy = M.wrap(main)
		local fn = luau.load(main.Source, { debugName = "Main", environment = env(mainProxy) })
		lib.spawn(fn)
	end

	-- Invoke a client->server remote as if a client sent it.
	function self:ClientFire(remoteName: string, player, ...)
		local remotes = self.Game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
		local remote = remotes:FindFirstChild(remoteName)
		M.signalFor(remote, "OnServerEvent"):Fire(player, ...)
	end

	function self:ClientInvoke(functionName: string, player, ...)
		local remotes = self.Game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
		local remote = remotes:FindFirstChild(functionName)
		local callback = M.getShadow(remote, "OnServerInvoke")
		return callback(player, ...)
	end

	function self:Advance(seconds: number)
		if coroutine.isyieldable() then
			lib.wait(seconds)
		else
			scheduler:Advance(seconds)
		end
	end

	return self
end

return World
