--[[
	Bots: simulated players that behave like real ones - they find their seats, wander, grab
	equipment, trigger interaction prompts, fight fires, breathe from bottles, vote in decisions,
	fly the approach, buckle up for landing and evacuate. Policies make some bots cooperative and
	some selfish/idle so the game is exercised the way a real server would be.
]]

local roblox = require("@lune/roblox")

local Bots = {}

local SKIP_ACTIONS = { KNOCK = true }

function Bots.attach(world, options: { Seed: number? }?)
	local M = world.M
	local lib = M.Library
	local seed = (options and options.Seed) or 7
	local state = { Seed = seed }
	local function rand(): number
		state.Seed = (state.Seed * 48271) % 2147483647
		return state.Seed / 2147483647
	end
	local function randInt(a: number, b: number): number
		return math.min(b, a + math.floor(rand() * (b - a + 1)))
	end

	local bots = {}
	local registry = nil
	local function R()
		if not registry then
			local server = world.Game:GetService("ServerScriptService"):FindFirstChild("Server")
			registry = world.Require(server:FindFirstChild("Registry"))
		end
		return registry
	end

	local latestManual: { [any]: any } = {}
	local seats: { [any]: any } = {}

	table.insert(world.ClientHandlers, function(remote, player, ...)
		local payload = ...
		if remote == "SeatAssigned" then
			seats[player] = payload.Seat
		elseif remote == "ManualFlight" then
			latestManual[player] = payload
		elseif remote == "DecisionOpened" then
			local bot = bots[player]
			if not bot or bot.Policy == "idle" then
				return
			end
			lib.delay(1 + rand() * 4, function()
				if payload.Input == "Keypad" then
					local code = tostring(randInt(1000, 9999))
					local ctx = R().RoundService:GetContext()
					if ctx and ctx.Disaster and ctx.Disaster.Code and rand() < 0.6 then
						code = ctx.Disaster.Code
					end
					world:ClientFire("DecisionVote", player, payload.Key, code)
				elseif payload.Options and #payload.Options > 0 then
					local option = payload.Options[randInt(1, #payload.Options)]
					world:ClientFire("DecisionVote", player, payload.Key, option.Id)
				end
			end)
		end
	end)

	local function humanoidOf(player)
		local character = player.Character
		return character and character:FindFirstChildOfClass("Humanoid")
	end

	local function rootOf(player)
		local character = player.Character
		return character and character:FindFirstChild("HumanoidRootPart")
	end

	local function teleportNear(player, position: Vector3)
		local character = player.Character
		local humanoid = humanoidOf(player)
		if humanoid and humanoid.Sit then
			humanoid.Sit = false
		end
		if character then
			character:PivotTo(roblox.CFrame.new(position + roblox.Vector3.new(0.5, 0.5, 0.5)))
		end
	end

	local function conscious(player): boolean
		return R().ConditionService:IsConscious(player)
	end

	local function sitIn(player, seat)
		local humanoid = humanoidOf(player)
		if humanoid and seat and not seat.Occupant then
			teleportNear(player, seat.Position + roblox.Vector3.new(0, 2, 0))
			seat:Sit(humanoid)
			return true
		end
		return false
	end

	local function freeSeat()
		local list = R().MapService.Points.Seats
		for _ = 1, 30 do
			local seat = list[randInt(1, #list)]
			if not seat.Occupant then
				return seat
			end
		end
		return nil
	end

	local function prompts()
		local list = {}
		for _, d in world.Game:GetService("Workspace"):GetDescendants() do
			if d.ClassName == "ProximityPrompt" and d.Enabled and d.Parent then
				table.insert(list, d)
			end
		end
		return list
	end

	local function trigger(bot, prompt)
		local parent = prompt.Parent
		if not parent then
			return
		end
		local position = if parent:IsA("BasePart") then parent.Position elseif parent:IsA("Attachment") then parent.WorldPosition else nil
		if position then
			teleportNear(bot.Player, position)
		end
		lib.wait(prompt.HoldDuration + 0.1)
		if prompt.Parent and prompt.Enabled and conscious(bot.Player) then
			M.signalFor(prompt, "Triggered"):Fire(bot.Player)
			bot.Actions += 1
		end
	end

	local function choosePrompt(bot, list, phase: string)
		local weighted = {}
		local total = 0
		for _, prompt in list do
			local action = prompt.ActionText
			if SKIP_ACTIONS[action] or prompt:GetAttribute("HideFor") == bot.Player.UserId then
				continue
			end
			if prompt:GetAttribute("Kiosk") then
				continue
			end
			local kind = prompt:GetAttribute("Kind") or "default"
			local weight = 1
			if kind == "objective" or kind == "decision" then
				weight = 6
			elseif kind == "rescue" then
				weight = 7
			elseif kind == "danger" then
				weight = if phase == "Evacuation" then 10 else 4
			elseif action == "TAKE" then
				weight = 3
			elseif action == "OPEN" or action == "CLOSE" then
				weight = 0.4
			end
			if action == "PUT ON" and bot.HasMask then
				weight = 0
			end
			total += weight
			table.insert(weighted, { Prompt = prompt, Weight = weight })
		end
		if total <= 0 then
			return nil
		end
		local roll = rand() * total
		for _, entry in weighted do
			roll -= entry.Weight
			if roll <= 0 then
				return entry.Prompt
			end
		end
		return weighted[#weighted].Prompt
	end

	local function tool(bot, kind: string)
		local player = bot.Player
		for _, container in { player.Character, player:FindFirstChildOfClass("Backpack") } do
			if container then
				for _, child in container:GetChildren() do
					if child:IsA("Tool") and child:GetAttribute("Kind") == kind then
						return child
					end
				end
			end
		end
		return nil
	end

	local function fightFire(bot): boolean
		local fire = R().FireSystem
		if fire:ActiveCount() == 0 then
			return false
		end
		local extinguisher = tool(bot, "Extinguisher")
		if not extinguisher or (extinguisher:GetAttribute("Charge") or 0) <= 0 then
			return false
		end
		local cells = fire:ActiveCells()
		local cell = cells[randInt(1, #cells)]
		local character = bot.Player.Character
		extinguisher.Parent = character
		local target = cell.Part.Position
		local from = target + roblox.Vector3.new(-4, 2, 0)
		character:PivotTo(roblox.CFrame.lookAt(from, roblox.Vector3.new(target.X, from.Y, target.Z)))
		M.signalFor(extinguisher, "Activated"):Fire()
		lib.wait(2.5)
		M.signalFor(extinguisher, "Deactivated"):Fire()
		return true
	end

	local function act(bot)
		local player = bot.Player
		if not player.Parent or not player:GetAttribute("InRound") or not conscious(player) then
			return
		end
		local phase = world.Game:GetService("ReplicatedStorage"):FindFirstChild("GameState"):GetAttribute("Phase")
		local humanoid = humanoidOf(player)
		if not humanoid then
			return
		end
		if phase == "Boarding" then
			if not humanoid.Sit and seats[player] and rand() < 0.7 then
				sitIn(player, seats[player])
			end
			return
		end
		if bot.Policy == "idle" then
			if phase == "FinalEvent" and not humanoid.Sit and rand() < 0.3 then
				sitIn(player, freeSeat())
			end
			return
		end
		-- flying the aircraft
		local manual = latestManual[player]
		if manual and manual.Active and humanoid.SeatPart then
			world:ClientFire("PilotInput", player, if manual.Attitude > 5 then -1 elseif manual.Attitude < -5 then 1 else 0)
			return
		end
		if phase == "FinalEvent" then
			local objectives = R().ObjectiveService
			if objectives:IsActive("FlyApproach") and not bot.Selfish and rand() < 0.5 then
				local pilotSeat = R().MapService.Points.PilotSeat
				if not pilotSeat.Occupant then
					sitIn(player, pilotSeat)
					return
				end
			end
			if (objectives:IsActive("LowerGear") and rand() < 0.5) or humanoid.Sit then
				-- fall through to prompts for the gear, otherwise stay seated
				if humanoid.Sit then
					return
				end
			elseif rand() < 0.75 then
				sitIn(player, freeSeat())
				return
			end
		end
		if phase == "Flight" then
			if humanoid.Sit and rand() < 0.3 then
				humanoid.Sit = false
			end
			return
		end
		if phase == "Landing" then
			return
		end
		-- oxygen
		local flight = world.Game:GetService("ReplicatedStorage"):FindFirstChild("FlightState")
		if flight:GetAttribute("OxygenEmergency") then
			local bottle = tool(bot, "OxygenBottle")
			if bottle and not bot.BottleOpen then
				bottle.Parent = player.Character
				M.signalFor(bottle, "Activated"):Fire()
				bot.BottleOpen = true
			end
		end
		if rand() < 0.5 and fightFire(bot) then
			return
		end
		local prompt = choosePrompt(bot, prompts(), phase)
		if prompt then
			trigger(bot, prompt)
		end
		if phase == "Evacuation" then
			for _, exit in R().MapService.Points.Exits do
				if exit.Door:GetAttribute("Open") and rand() < 0.8 then
					teleportNear(player, exit.Inside.Position)
					break
				end
			end
		end
	end

	function state.Add(player, policy: string?)
		local bot = { Player = player, Policy = policy or "cooperative", Actions = 0, Selfish = policy == "selfish" }
		bots[player] = bot
		lib.spawn(function()
			while player.Parent do
				lib.wait(0.8 + rand() * 0.8)
				local ok, err = pcall(act, bot)
				if not ok then
					table.insert(world.Errors, "BOT ERROR: " .. tostring(err))
				end
			end
		end)
		return bot
	end

	state.Bots = bots
	state.Registry = R
	return state
end

return Bots
