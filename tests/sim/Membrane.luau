--[[
	Membrane: wraps Lune's Roblox instances in proxies that add what Lune doesn't simulate
	(events, property/attribute signals, PivotTo, seats, humanoid death, remotes, services).
	Property writes still go through Lune, so invalid property names or types raise real errors.
]]

local roblox = require("@lune/roblox")

local Membrane = {}

local EVENT_NAMES = {
	Touched = true, TouchEnded = true, Triggered = true, TriggerEnded = true, Activated = true, Deactivated = true,
	Equipped = true, Unequipped = true, Died = true, Running = true, Heartbeat = true, Stepped = true,
	RenderStepped = true, Ended = true, Completed = true, Destroying = true, Changed = true, AttributeChanged = true,
	ChildAdded = true, ChildRemoved = true, DescendantAdded = true, DescendantRemoving = true, CharacterAdded = true,
	CharacterRemoving = true, PlayerAdded = true, PlayerRemoving = true, OnServerEvent = true, OnClientEvent = true,
	PromptGamePassPurchaseFinished = true, PromptProductPurchaseFinished = true, Event = true, MoveToFinished = true,
	PromptShown = true, PromptHidden = true, PromptTriggered = true, AncestryChanged = true,
	MouseEnter = true, MouseLeave = true, MouseButton1Down = true, MouseButton1Up = true, MouseButton1Click = true,
	FocusLost = true, InputBegan = true, InputEnded = true, InputChanged = true, Seated = true,
}

local SHADOW_OK = {
	OnServerInvoke = true, OnClientInvoke = true, ProcessReceipt = true, OnIncomingMessage = true, OnInvoke = true,
	Occupant = true, SeatPart = true, Character = true, UserId = true, DisplayName = true,
	LocalPlayer = true, ViewportSize = true,
}

function Membrane.new(scheduler, hooks)
	local M = {}
	local lib = scheduler:Library()
	local proxies: { [number]: any } = {}
	local raws: { [any]: any } = setmetatable({}, { __mode = "k" })
	local shadows: { [number]: { [string]: any } } = {}
	local signals: { [number]: { [string]: any } } = {}
	local methodCache: { [number]: { [string]: any } } = {}
	local nextId = 0
	local destroyed: { [number]: boolean } = {}
	M.ShadowWrites = {} :: { string }

	---------------------------------------------------------------- signals
	local Signal = {}
	Signal.__index = Signal
	function Signal.new(name: string?)
		return setmetatable({ Handlers = {}, Waiting = {}, Name = name }, Signal)
	end
	function Signal:Connect(fn)
		local connection = { Connected = true }
		function connection.Disconnect(c)
			c.Connected = false
			local index = table.find(self.Handlers, c)
			if index then
				table.remove(self.Handlers, index)
			end
		end
		connection.Fn = fn
		table.insert(self.Handlers, connection)
		return connection
	end
	function Signal:Once(fn)
		local connection
		connection = self:Connect(function(...)
			connection:Disconnect()
			fn(...)
		end)
		return connection
	end
	function Signal:Wait()
		local thread = coroutine.running()
		table.insert(self.Waiting, thread)
		return coroutine.yield()
	end
	function Signal:Fire(...)
		for _, connection in table.clone(self.Handlers) do
			if connection.Connected then
				lib.spawn(connection.Fn, ...)
			end
		end
		local waiting = self.Waiting
		self.Waiting = {}
		for _, thread in waiting do
			lib.spawn(thread, ...)
		end
	end
	M.Signal = Signal

	---------------------------------------------------------------- identity
	local function idOf(inst): number
		local id = inst:GetAttribute("__SimId")
		if not id then
			nextId += 1
			id = nextId
			inst:SetAttribute("__SimId", id)
		end
		return id
	end

	local wrap

	local function isInstance(value): boolean
		return typeof(value) == "Instance"
	end

	function M.unwrap(value)
		local raw = raws[value]
		if raw ~= nil then
			return raw
		end
		return value
	end

	local function unwrapAll(...)
		local out = table.pack(...)
		for i = 1, out.n do
			local v = out[i]
			if type(v) == "table" and raws[v] == nil and getmetatable(v) == nil then
				-- plain tables (e.g. goal tables) pass through; lists of proxies are unwrapped
				local copy = {}
				for k, inner in v do
					copy[k] = M.unwrap(inner)
				end
				out[i] = copy
			else
				out[i] = M.unwrap(v)
			end
		end
		return out
	end

	local function wrapValue(value)
		if isInstance(value) then
			return wrap(value)
		elseif type(value) == "table" and raws[value] == nil then
			local isList = true
			for _, inner in value do
				if not isInstance(inner) then
					isList = false
					break
				end
			end
			if isList and next(value) ~= nil then
				local out = {}
				for k, inner in value do
					out[k] = wrap(inner)
				end
				return out
			end
		end
		return value
	end

	local function wrapAll(...)
		local out = table.pack(...)
		for i = 1, out.n do
			out[i] = wrapValue(out[i])
		end
		return table.unpack(out, 1, out.n)
	end

	local function signalFor(inst, key: string)
		local id = idOf(inst)
		signals[id] = signals[id] or {}
		local signal = signals[id][key]
		if not signal then
			signal = Signal.new(key)
			signals[id][key] = signal
		end
		return signal
	end
	M.signalFor = function(proxy, key)
		return signalFor(M.unwrap(proxy), key)
	end

	local function fireChanged(inst, key: string, _value: any?)
		local id = idOf(inst)
		local set = signals[id]
		if set then
			local specific = set["prop:" .. key]
			if specific then
				specific:Fire()
			end
			local changed = set.Changed
			if changed then
				changed:Fire(key)
			end
		end
	end

	local function shadowGet(inst, key)
		local set = shadows[idOf(inst)]
		if set then
			return set[key]
		end
		return nil
	end

	local function shadowSet(inst, key, value)
		local id = idOf(inst)
		shadows[id] = shadows[id] or {}
		shadows[id][key] = value
	end

	---------------------------------------------------------------- overrides
	local overrides: { [string]: (any, ...any) -> ...any } = {}
	M.Overrides = overrides

	local function allParts(inst)
		local list = {}
		if inst:IsA("BasePart") then
			table.insert(list, inst)
		end
		for _, d in inst:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
		return list
	end

	local function pivotOf(inst)
		if inst:IsA("BasePart") then
			return inst.CFrame
		end
		local root = inst:FindFirstChild("HumanoidRootPart") or inst.PrimaryPart
		if root then
			return root.CFrame
		end
		return inst.WorldPivot
	end

	overrides.GetPivot = function(proxy)
		return pivotOf(M.unwrap(proxy))
	end
	overrides.PivotTo = function(proxy, cframe)
		local inst = M.unwrap(proxy)
		local current = pivotOf(inst)
		local delta = cframe * current:Inverse()
		for _, part in allParts(inst) do
			part.CFrame = delta * part.CFrame
		end
		if inst:IsA("Model") then
			inst.WorldPivot = cframe
		end
	end
	overrides.SetNetworkOwner = function() end
	overrides.SetNetworkOwnershipAuto = function() end
	overrides.GetPropertyChangedSignal = function(proxy, prop)
		return signalFor(M.unwrap(proxy), "prop:" .. prop)
	end
	overrides.GetAttributeChangedSignal = function(proxy, attr)
		return signalFor(M.unwrap(proxy), "attr:" .. attr)
	end
	overrides.SetAttribute = function(proxy, name, value)
		local inst = M.unwrap(proxy)
		inst:SetAttribute(name, M.unwrap(value))
		local set = signals[idOf(inst)]
		if set then
			if set["attr:" .. name] then
				set["attr:" .. name]:Fire()
			end
			if set.AttributeChanged then
				set.AttributeChanged:Fire(name)
			end
		end
	end
	overrides.Destroy = function(proxy)
		local inst = M.unwrap(proxy)
		local id = idOf(inst)
		if destroyed[id] then
			return
		end
		destroyed[id] = true
		local set = signals[id]
		if set and set.Destroying then
			set.Destroying:Fire()
		end
		for _, d in inst:GetDescendants() do
			local did = d:GetAttribute("__SimId")
			if did then
				destroyed[did] = true
			end
		end
		pcall(function()
			inst.Parent = nil
		end)
	end
	overrides.WaitForChild = function(proxy, name, timeout)
		local inst = M.unwrap(proxy)
		local waited = 0
		while true do
			local child = inst:FindFirstChild(name)
			if child then
				return wrap(child)
			end
			if timeout and waited >= timeout then
				return nil
			end
			lib.wait(0.1)
			waited += 0.1
			if waited > 30 and not timeout then
				error("infinite WaitForChild on " .. inst.Name .. "." .. name)
			end
		end
	end
	overrides.FireClient = function(proxy, player, ...)
		hooks.OnFireClient(M.unwrap(proxy).Name, player, ...)
	end
	overrides.FireServer = function(proxy, ...)
		hooks.OnFireServer(proxy, ...)
	end
	overrides.InvokeServer = function(proxy, ...)
		return hooks.OnInvokeServer(proxy, ...)
	end
	overrides.FireAllClients = function(proxy, ...)
		hooks.OnFireClient(M.unwrap(proxy).Name, "all", ...)
	end
	overrides.Sit = function(proxy, humanoidProxy)
		local seat = M.unwrap(proxy)
		local humanoid = M.unwrap(humanoidProxy)
		if shadowGet(seat, "Occupant") then
			return
		end
		shadowSet(seat, "Occupant", humanoid)
		shadowSet(humanoid, "SeatPart", seat)
		humanoid.Sit = true
		fireChanged(seat, "Occupant")
		fireChanged(humanoid, "SeatPart")
		signalFor(humanoid, "Seated"):Fire(true, proxy)
	end
	overrides.LoadAnimation = function(_proxy, animation)
		local track = { Looped = false, Priority = nil, IsPlaying = false, Animation = animation }
		function track.Play(t)
			t.IsPlaying = true
		end
		function track.Stop(t)
			t.IsPlaying = false
		end
		function track.AdjustSpeed(t, speed)
			t.Speed = speed
		end
		track.Stopped = Signal.new("Stopped")
		return track
	end
	overrides.MoveTo = function(proxy, position)
		local inst = M.unwrap(proxy)
		local model = inst.Parent
		if model then
			overrides.PivotTo(wrap(model), roblox.CFrame.new(position + roblox.Vector3.new(0, 3, 0)))
		end
	end
	overrides.ChangeState = function() end
	overrides.SetStateEnabled = function() end
	overrides.GetState = function()
		return roblox.Enum.HumanoidStateType.Running
	end
	overrides.UnequipTools = function(proxy)
		local humanoid = M.unwrap(proxy)
		local character = humanoid.Parent
		local player = hooks.PlayerFromCharacter(character)
		local backpack = player and player:FindFirstChildOfClass("Backpack")
		if character and backpack then
			for _, child in character:GetChildren() do
				if child:IsA("Tool") then
					child.Parent = backpack
				end
			end
		end
	end
	overrides.GetServerTimeNow = function()
		return scheduler.Now + 1000
	end
	overrides.BindToClose = function(_proxy, fn)
		hooks.OnBindToClose(fn)
	end
	overrides.GetService = function(_proxy, name)
		return hooks.GetService(name)
	end
	overrides.GetPlayers = function(proxy)
		local list = {}
		for _, child in M.unwrap(proxy):GetChildren() do
			if child.ClassName == "Player" then
				table.insert(list, wrap(child))
			end
		end
		return list
	end
	overrides.GetPlayerFromCharacter = function(_proxy, character)
		local player = hooks.PlayerFromCharacter(M.unwrap(character))
		return player and wrap(player)
	end
	overrides.GetPlayerByUserId = function(proxy, userId)
		for _, child in M.unwrap(proxy):GetChildren() do
			if child.ClassName == "Player" and shadowGet(child, "UserId") == userId then
				return wrap(child)
			end
		end
		return nil
	end
	overrides.CreateHumanoidModelFromDescription = function(_proxy, _description, _rigType)
		return wrap(hooks.BuildRig("NPC"))
	end
	overrides.Kick = function() end
	-- media playback has no effect server-side in the simulation
	overrides.Play = function() end
	overrides.Stop = function() end
	overrides.Pause = function() end
	overrides.Resume = function() end
	overrides.Emit = function() end
	overrides.Clear = function() end

	---------------------------------------------------------------- proxy
	local ProxyMeta = {}

	function ProxyMeta.__index(proxy, key)
		local inst = raws[proxy]
		local shadow = shadowGet(inst, key)
		if shadow ~= nil then
			return wrapValue(shadow)
		end
		if SHADOW_OK[key] and (key == "Occupant" or key == "SeatPart" or key == "Character" or key == "LocalPlayer") then
			return nil
		end
		local override = overrides[key]
		-- Seat:Sit() is a method, but Humanoid.Sit is a boolean property
		if override and not (key == "Sit" and inst:IsA("Humanoid")) then
			return override
		end
		if key == "Position" and inst:IsA("BasePart") then
			return inst.CFrame.Position
		end
		local ok, value = pcall(function()
			return inst[key]
		end)
		if ok then
			if type(value) == "function" then
				local id = idOf(inst)
				methodCache[id] = methodCache[id] or {}
				local cached = methodCache[id][key]
				if not cached then
					cached = function(_self, ...)
						local args = unwrapAll(...)
						return wrapAll(value(inst, table.unpack(args, 1, args.n)))
					end
					methodCache[id][key] = cached
				end
				return cached
			end
			return wrapValue(value)
		end
		if EVENT_NAMES[key] then
			return signalFor(inst, key)
		end
		local child = inst:FindFirstChild(key)
		if child then
			return wrap(child)
		end
		if string.find(tostring(value), "missing default value") then
			return nil
		end
		error(tostring(key) .. " is not a valid member of " .. inst.ClassName .. " \"" .. inst.Name .. "\" (sim)", 2)
	end

	function ProxyMeta.__newindex(proxy, key, value)
		local inst = raws[proxy]
		local raw = M.unwrap(value)
		if SHADOW_OK[key] then
			-- callbacks & engine-managed properties live in the shadow table
			local ok = pcall(function()
				inst[key] = raw
			end)
			if not ok or key == "Occupant" or key == "SeatPart" or key == "Character" or key == "UserId" or key == "LocalPlayer" or key == "ViewportSize" then
				shadowSet(inst, key, raw)
			end
			fireChanged(inst, key, raw)
			return
		end
		if key == "Position" and inst:IsA("BasePart") then
			local rotation = inst.CFrame - inst.CFrame.Position
			inst.CFrame = roblox.CFrame.new(raw) * rotation
			fireChanged(inst, "CFrame")
			return
		end
		local oldParent = if key == "Parent" then inst.Parent else nil
		local ok, err = pcall(function()
			inst[key] = raw
		end)
		if not ok then
			error("sim: failed to set " .. inst.ClassName .. "." .. tostring(key) .. ": " .. tostring(err), 2)
		end
		if key == "Health" and inst:IsA("Humanoid") and raw <= 0 and not shadowGet(inst, "__Dead") then
			shadowSet(inst, "__Dead", true)
			signalFor(inst, "Died"):Fire()
		elseif key == "Sit" and inst:IsA("Humanoid") and raw == false then
			-- like the engine, the seat releases the humanoid on the next step, not synchronously
			lib.defer(function()
				local seat = shadowGet(inst, "SeatPart")
				if seat and not inst.Sit then
					shadows[idOf(inst)].SeatPart = nil
					local seatShadow = shadows[idOf(seat)]
					if seatShadow then
						seatShadow.Occupant = nil
					end
					fireChanged(seat, "Occupant")
					signalFor(inst, "Seated"):Fire(false, nil)
				end
			end)
		elseif key == "Parent" then
			if raw then
				signalFor(raw, "ChildAdded"):Fire(proxy)
				local ancestor = raw
				while ancestor do
					local set = signals[idOf(ancestor)]
					if set and set.DescendantAdded then
						set.DescendantAdded:Fire(proxy)
					end
					ancestor = ancestor.Parent
				end
			elseif oldParent then
				signalFor(oldParent, "ChildRemoved"):Fire(proxy)
			end
		end
		fireChanged(inst, key, raw)
	end

	function ProxyMeta.__tostring(proxy)
		return raws[proxy].Name
	end

	function ProxyMeta.__eq(a, b)
		return rawequal(a, b)
	end

	function wrap(inst)
		if inst == nil then
			return nil
		end
		local id = idOf(inst)
		local proxy = proxies[id]
		if proxy then
			return proxy
		end
		proxy = setmetatable({}, ProxyMeta)
		proxies[id] = proxy
		raws[proxy] = inst
		return proxy
	end
	M.wrap = wrap
	M.wrapValue = wrapValue

	function M.isProxy(value): boolean
		return type(value) == "table" and raws[value] ~= nil
	end

	function M.isDestroyed(proxy): boolean
		local inst = raws[proxy]
		return inst ~= nil and destroyed[idOf(inst)] == true
	end

	function M.Instance(className: string, parent)
		local inst = roblox.Instance.new(className)
		local proxy = wrap(inst)
		if parent then
			proxy.Parent = parent
		end
		return proxy
	end

	function M.shadow(proxy, key, value)
		shadowSet(M.unwrap(proxy), key, M.unwrap(value))
	end

	function M.getShadow(proxy, key)
		return shadowGet(M.unwrap(proxy), key)
	end

	M.Library = lib
	return M
end

return Membrane
