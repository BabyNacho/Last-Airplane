--[[
	LAST FLIGHT server simulation tests.
	Run from the repository root after building the place:
		rojo build default.project.json -o build/LastFlight.rbxl
		lune run tests/sim/run
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Bots = require("./Bots")
local World = require("./World")

local DISASTERS = {
	"EngineFailure", "Turbulence", "CabinFire", "LightningStorm", "BirdStrike",
	"Depressurization", "PilotDisappears", "HydraulicFailure", "NavigationFailure",
}

-- warnings that are expected in specific scenarios
local ALLOWED_WARNINGS = {
	"simulated DataStore outage",
	"using temporary profile",
}

local results = {}
local failures = 0

local function allowed(message: string, extra: { string }?): boolean
	for _, pattern in ALLOWED_WARNINGS do
		if string.find(message, pattern, 1, true) then
			return true
		end
	end
	for _, pattern in extra or {} do
		if string.find(message, pattern, 1, true) then
			return true
		end
	end
	return false
end

local filter = process.args[1]

local function scenario(name: string, fn: (any) -> ({ string }?), options: any?)
	if filter and not string.find(string.lower(name), string.lower(filter), 1, true) then
		return nil
	end
	local world = World.new(options)
	-- run the body inside the virtual scheduler so it may yield (DataStore calls, waits...)
	local done, ok, err = false, false, nil
	world.M.Library.spawn(function()
		ok, err = pcall(fn, world)
		done = true
	end)
	while not done and world.Scheduler.Now < 20000 do
		world.Scheduler:Advance(1)
	end
	if not done then
		ok, err = false, "scenario timed out"
	end
	local problems = {}
	if not ok then
		table.insert(problems, "scenario error: " .. tostring(err))
	elseif type(err) == "table" then
		for _, p in err do
			table.insert(problems, p)
		end
	end
	for _, e in world.Errors do
		table.insert(problems, "ERROR: " .. e)
	end
	local extra = options and options.AllowWarnings
	for _, w in world.Warnings do
		if not allowed(w, extra) then
			table.insert(problems, "WARN: " .. w)
		end
	end
	local passed = #problems == 0
	if not passed then
		failures += 1
	end
	print(string.format("%s  %s", if passed then "PASS" else "FAIL", name))
	if not passed then
		local seen = {}
		for _, p in problems do
			local key = string.sub(p, 1, 160)
			if not seen[key] then
				seen[key] = true
				print("      " .. string.sub(p, 1, 600))
			end
		end
	end
	table.insert(results, { Name = name, Passed = passed })
	return world
end

local function gameState(world)
	return world.Game:GetService("ReplicatedStorage"):FindFirstChild("GameState")
end

local function registry(world)
	local server = world.Game:GetService("ServerScriptService"):FindFirstChild("Server")
	return world.Require(server:FindFirstChild("Registry"))
end

local function config(world, name: string)
	local shared = world.Game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
	return world.Require(shared:FindFirstChild("Config"):FindFirstChild(name))
end

-- Runs until `count` Results phases were observed (or timeout). Returns phase history.
local function runRounds(world, count: number, timeout: number?, onPhase: ((string) -> ())?)
	local history = {}
	local last = nil
	local finished = 0
	local limit = world.Scheduler.Now + (timeout or 600 * count)
	while world.Scheduler.Now < limit do
		world:Advance(0.5)
		local phase = gameState(world):GetAttribute("Phase")
		if phase ~= last then
			table.insert(history, phase)
			if onPhase then
				onPhase(phase)
			end
			if last == "Results" then
				finished += 1
				if finished >= count then
					break
				end
			end
			last = phase
		end
	end
	return history, finished
end

local function resultsFor(world, player)
	local found = nil
	for _, entry in world.ClientLog do
		if entry.Remote == "Results" and entry.Player == player then
			found = entry.Args[1]
		end
	end
	return found
end

local function expectPhases(history, problems, survived: boolean?)
	-- a round where everyone died legitimately skips ahead; with nobody alive the landing resolves
	-- instantly, often between two 0.5s polls, so it isn't required in that case
	local required = if survived == false then { "Boarding", "Flight", "Results" } else { "Boarding", "Flight", "Disaster", "Crisis", "FinalEvent", "Landing", "Results" }
	local index = 1
	for _, phase in history do
		if phase == required[index] then
			index += 1
		end
	end
	if index <= #required then
		table.insert(problems, "phase sequence incomplete: " .. table.concat(history, " > "))
	end
end

---------------------------------------------------------------- scenarios

for _, disaster in DISASTERS do
	scenario("Solo round: " .. disaster, function(world)
		local problems = {}
		world:Boot()
		world:Advance(1)
		config(world, "GameConfig").StudioForceDisaster = disaster
		local bots = Bots.attach(world, { Seed = #disaster * 131 })
		local player = world:AddPlayer("Solo")
		bots.Add(player, "cooperative")
		local history = runRounds(world, 1, 700)
		local result = resultsFor(world, player)
		expectPhases(history, problems, result and result.Personal and result.Personal.Survived)
		if not result then
			table.insert(problems, "no Results payload received")
		else
			if result.DisasterId ~= disaster then
				table.insert(problems, "wrong disaster in results: " .. tostring(result.DisasterId))
			end
			if not result.Personal or not result.Personal.Credits or result.Personal.Credits <= 0 then
				table.insert(problems, "no credits awarded")
			end
			print(string.format("      -> %s | landing %s (%d) | survived %s | credits %d | objectives %d/%d | decisions %d%s",
				result.Title, result.LandingTier, result.LandingScore, tostring(result.Personal and result.Personal.Survived),
				result.Personal and result.Personal.Credits or 0, result.Objectives.Completed, result.Objectives.Total, #result.Decisions,
				if result.Personal and not result.Personal.Survived then " | cause: " .. tostring(result.Personal.Cause) else ""))
			if process.env.SIM_VERBOSE then
				for _, note in result.LandingNotes do
					print(string.format("         %+4d  %s", note.Delta or 0, note.Note))
				end
				for _, decision in result.Decisions do
					print("         decision: " .. tostring(decision.Title) .. " -> " .. tostring(decision.Choice) .. " | " .. tostring(decision.Outcome))
				end
			end
		end
		local profile = registry(world).DataService:Get(player)
		if not profile or profile.Stats.Flights ~= 1 then
			table.insert(problems, "Flights stat not incremented")
		end
		-- the loop must continue into the next round
		local nextHistory = runRounds(world, 0, 60)
		if not table.find(nextHistory, "Boarding") and not table.find(nextHistory, "Lobby") then
			table.insert(problems, "server did not return to the lobby/next round")
		end
		return problems
	end)
end

scenario("Multiplayer: 6 players, 3 random rounds, mixed behaviour", function(world)
	local problems = {}
	world:Boot()
	world:Advance(1)
	local bots = Bots.attach(world, { Seed = 99 })
	local players = {}
	local policies = { "cooperative", "cooperative", "cooperative", "selfish", "idle", "cooperative" }
	for i = 1, 6 do
		local player = world:AddPlayer("Player" .. i)
		bots.Add(player, policies[i])
		table.insert(players, player)
	end
	local seen = {}
	local _, finished = runRounds(world, 3, 2000, function(phase)
		if phase == "Disaster" then
			local ctx = registry(world).RoundService:GetContext()
			if ctx then
				table.insert(seen, ctx.DisasterId)
			end
		end
	end)
	if finished < 3 then
		table.insert(problems, "only " .. finished .. " rounds finished")
	end
	for _, player in players do
		local result = resultsFor(world, player)
		if not result then
			table.insert(problems, player.Name .. " got no results")
		end
	end
	local last = resultsFor(world, players[1])
	if last then
		print(string.format("      disasters: %s | last: %s, %d/%d survived, rescues %d", table.concat(seen, ", "), last.Title, last.Survivors, last.Total, last.Rescued))
	end
	if #seen >= 2 and seen[1] == seen[2] then
		table.insert(problems, "same disaster twice in a row")
	end
	return problems
end)

for index, disaster in DISASTERS do
	scenario("Squad of 4: " .. disaster, function(world)
		local problems = {}
		world:Boot()
		world:Advance(1)
		config(world, "GameConfig").StudioForceDisaster = disaster
		local bots = Bots.attach(world, { Seed = index * 977 })
		local players = {}
		for i = 1, 4 do
			local player = world:AddPlayer("Squad" .. i)
			bots.Add(player, if i == 4 then "selfish" else "cooperative")
			table.insert(players, player)
		end
		local _, finished = runRounds(world, 1, 800)
		if finished < 1 then
			table.insert(problems, "round did not finish")
		end
		local result = resultsFor(world, players[1])
		if result then
			print(string.format("      -> %s | %s (%d) | %d/%d survived | rescues %d | objectives %d/%d", result.Title, result.LandingTier, result.LandingScore, result.Survivors, result.Total, result.Rescued, result.Objectives.Completed, result.Objectives.Total))
		else
			table.insert(problems, "no results")
		end
		return problems
	end)
end

for seed = 1, 4 do
	scenario("Stress: random disasters, seed " .. seed, function(world)
		local problems = {}
		world:Boot()
		world:Advance(1)
		local bots = Bots.attach(world, { Seed = seed * 7919 })
		local count = 6 + seed * 2
		local policies = { "cooperative", "selfish", "idle" }
		for i = 1, count do
			bots.Add(world:AddPlayer("S" .. seed .. "_" .. i), policies[(i % 3) + 1])
		end
		local _, finished = runRounds(world, 2, 1600)
		if finished < 2 then
			table.insert(problems, "only " .. finished .. " rounds finished")
		end
		return problems
	end)
end

local function visible(gui): boolean
	local node = gui
	while node do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		if node:IsA("ScreenGui") then
			return node.Enabled
		end
		node = node.Parent
	end
	return false
end

local CLIENT_RUNS = {
	{ Disaster = "CabinFire", Device = nil, Label = "desktop" },
	{ Disaster = "Depressurization", Device = nil, Label = "desktop" },
	{ Disaster = "PilotDisappears", Device = { Touch = true, Viewport = roblox.Vector2.new(812, 375) }, Label = "phone" },
	{ Disaster = "BirdStrike", Device = { Touch = true, Viewport = roblox.Vector2.new(1024, 768) }, Label = "tablet" },
	{ Disaster = "LightningStorm", Device = { Touch = true, Viewport = roblox.Vector2.new(740, 360) }, Label = "small phone" },
}

for _, run in CLIENT_RUNS do
	local disaster = run.Disaster
	scenario("Client UI (" .. run.Label .. ") + button fuzzing during a full round: " .. disaster, function(world)
		local problems = {}
		world:Boot()
		world:Advance(1)
		config(world, "GameConfig").StudioForceDisaster = disaster
		local bots = Bots.attach(world, { Seed = 4242 + #disaster })
		local me = world:AddPlayer("ClientPlayer")
		local buddy = world:AddPlayer("Buddy")
		bots.Add(me)
		bots.Add(buddy)
		world:AttachClient(me, run.Device)
		world:Advance(2)
		local gui = me:FindFirstChildOfClass("PlayerGui")
		local screens = {}
		for _, child in gui:GetChildren() do
			table.insert(screens, child.Name)
		end
		for _, required in { "MainUI", "DecisionUI", "ShopUI", "ProfileUI", "ResultsUI", "EffectsUI", "CockpitUI" } do
			if not table.find(screens, required) then
				table.insert(problems, "missing ScreenGui " .. required)
			end
		end
		local clientFolder = world.Game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client")
		local controllers = clientFolder:FindFirstChild("Controllers")
		local shop = world.Require(controllers:FindFirstChild("ShopController"))
		local profile = world.Require(controllers:FindFirstChild("ProfileController"))
		local pps = world.Game:GetService("ProximityPromptService")
		local lib = world.M.Library
		local clicks = 0
		local rng = 12345
		local function rand(n: number): number
			rng = (rng * 48271) % 2147483647
			return (rng % n) + 1
		end
		-- open windows and fuzz buttons while the round plays out
		lib.spawn(function()
			shop:Open()
			lib.wait(1)
			profile:Open("Records")
			for _, tab in { "Stats", "Achievements", "Challenges", "Mastery", "Wardrobe" } do
				profile:Open(tab)
				lib.wait(0.3)
			end
			while true do
				lib.wait(1.5)
				local buttons = {}
				for _, d in gui:GetDescendants() do
					if d:IsA("TextButton") and visible(d) then
						table.insert(buttons, d)
					end
				end
				if #buttons > 0 then
					local button = buttons[rand(#buttons)]
					world.M.signalFor(button, "MouseButton1Down"):Fire()
					world.M.signalFor(button, "Activated"):Fire()
					world.M.signalFor(button, "MouseButton1Up"):Fire()
					clicks += 1
				end
				-- show custom prompt UI for a random nearby prompt
				local prompts = {}
				for _, d in world.Game:GetService("Workspace"):GetDescendants() do
					if d.ClassName == "ProximityPrompt" and d.Enabled then
						table.insert(prompts, d)
					end
				end
				if #prompts > 0 then
					local prompt = prompts[rand(#prompts)]
					pps.PromptShown:Fire(prompt, roblox.Enum.ProximityPromptInputType.Keyboard)
					pps.PromptButtonHoldBegan:Fire(prompt)
					lib.wait(0.2)
					pps.PromptButtonHoldEnded:Fire(prompt)
					pps.PromptHidden:Fire(prompt)
					local touchPrompt = prompts[rand(#prompts)]
					if touchPrompt.Parent then -- the list is 0.2s old; the engine never shows a destroyed prompt
						pps.PromptShown:Fire(touchPrompt, roblox.Enum.ProximityPromptInputType.Touch)
						pps.PromptHidden:Fire(touchPrompt)
					end
				end
			end
		end)
		local resultsRendered = 0
		table.insert(world.ClientHandlers, function(remote, player)
			if remote == "Results" and player == me then
				lib.delay(0.3, function()
					local results = gui:FindFirstChild("ResultsUI")
					resultsRendered = if results then #results:GetDescendants() else 0
				end)
			end
		end)
		local _, finished = runRounds(world, 1, 800)
		if finished < 1 then
			table.insert(problems, "round did not finish")
		end
		world:Advance(3)
		if resultsRendered < 40 then
			table.insert(problems, "results screen did not render (" .. resultsRendered .. " elements)")
		end
		print(string.format("      clicks fuzzed: %d | ScreenGuis: %d | results screen elements: %d", clicks, #screens, resultsRendered))
		return problems
	end)
end

scenario("Baked place (LastFlight.rbxl): world replaced, not duplicated, round plays", function(world)
	local problems = {}
	local workspaceProxy = world.Game:GetService("Workspace")
	local function worlds()
		local n = 0
		for _, child in workspaceProxy:GetChildren() do
			if child.Name == "World" then
				n += 1
			end
		end
		return n
	end
	if worlds() ~= 1 then
		table.insert(problems, "baked place should contain exactly one World before boot, found " .. worlds())
	end
	world:Boot()
	world:Advance(2)
	if worlds() ~= 1 then
		table.insert(problems, "expected exactly one World after boot, found " .. worlds())
	end
	local remotes = world.Game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
	local seen = {}
	for _, remote in remotes:GetChildren() do
		if seen[remote.Name] then
			table.insert(problems, "duplicate remote " .. remote.Name)
		end
		seen[remote.Name] = true
	end
	config(world, "GameConfig").StudioForceDisaster = "EngineFailure"
	local bots = Bots.attach(world, { Seed = 3 })
	local player = world:AddPlayer("BakedTester")
	bots.Add(player)
	local _, finished = runRounds(world, 1, 800)
	if finished < 1 or not resultsFor(world, player) then
		table.insert(problems, "round did not complete on the baked place")
	end
	return problems
end, { PlacePath = "LastFlight.rbxl" })

---------------------------------------------------------------- camera (cases A-G)

local function advanceUntil(world, predicate: () -> boolean, timeout: number): boolean
	local limit = world.Scheduler.Now + timeout
	while world.Scheduler.Now < limit do
		if predicate() then
			return true
		end
		world:Advance(0.25)
	end
	return predicate()
end

local function cameraKit(world, me)
	local clientFolder = world.Game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client")
	local kit = {}
	kit.Cam = world.Require(clientFolder:FindFirstChild("Controllers"):FindFirstChild("CameraController"))
	kit.ClientState = world.Require(clientFolder:FindFirstChild("ClientState"))
	kit.Camera = world.Game:GetService("Workspace").CurrentCamera
	-- deterministic aircraft attitude as seen by the client
	local attitude = { Roll = 0, Pitch = 0 }
	kit.Attitude = attitude
	local realFlight = kit.ClientState.Flight
	kit.ClientState.Flight = function(key)
		if key == "Roll" or key == "Pitch" then
			return attitude[key]
		elseif key == "OnGround" then
			return false
		elseif key == "Turbulence" then
			return 0
		end
		return realFlight(key)
	end
	function kit.Pitch(): number
		return math.deg(math.asin(math.clamp(kit.Camera.CFrame.LookVector.Y, -1, 1)))
	end
	function kit.Roll(): number
		return math.deg(math.asin(math.clamp(kit.Camera.CFrame.RightVector.Y, -1, 1)))
	end
	function kit.HeadingDot(): number
		local root = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
		local a = kit.Camera.CFrame.LookVector * roblox.Vector3.new(1, 0, 1)
		local b = root.CFrame.LookVector * roblox.Vector3.new(1, 0, 1)
		return a.Unit:Dot(b.Unit)
	end
	-- points the camera somewhere awkward, like a player who looked down from above mid-flight
	function kit.Mess(pitchDegrees: number, yawDegrees: number)
		local cf = kit.Camera.CFrame
		local focus = kit.Camera.Focus.Position
		local root = me.Character:FindFirstChild("HumanoidRootPart")
		local heading = (root.CFrame.LookVector * roblox.Vector3.new(1, 0, 1)).Unit
		local yawed = roblox.CFrame.Angles(0, math.rad(yawDegrees), 0) * heading
		local look = yawed * math.cos(math.rad(pitchDegrees)) + roblox.Vector3.new(0, math.sin(math.rad(pitchDegrees)), 0)
		local right = look:Cross(roblox.Vector3.new(0, 1, 0)).Unit
		kit.Camera.CFrame = roblox.CFrame.fromMatrix(focus - look * (cf.Position - focus).Magnitude, right, right:Cross(look)) * roblox.CFrame.Angles(0, 0, math.rad(20))
	end
	-- samples the camera after every rendered frame
	function kit.Record(): { number }
		local samples = {}
		world.Game:GetService("RunService"):BindToRenderStep("SimCameraProbe", 10000, function()
			table.insert(samples, kit.Pitch())
		end)
		return samples
	end
	function kit.StopRecord()
		world.Game:GetService("RunService"):UnbindFromRenderStep("SimCameraProbe")
	end
	-- the view Roblox's camera should settle into: upright, eye level, facing the character's heading
	function kit.ExpectNatural(problems, label: string)
		local goal = config(world, "GameConfig").Camera.RecenterPitch
		if kit.Cam:IsRecentering() then
			table.insert(problems, label .. ": still recentering")
		end
		if kit.Cam:GetTiltWeight() ~= 0 then
			table.insert(problems, label .. ": flight tilt still applied (" .. kit.Cam:GetTiltWeight() .. ")")
		end
		if math.abs(kit.Pitch() - goal) > 2 then
			table.insert(problems, string.format("%s: camera pitch %.1f, expected about %d (eye level)", label, kit.Pitch(), goal))
		end
		if math.abs(kit.Roll()) > 0.5 then
			table.insert(problems, string.format("%s: camera still rolled %.1f degrees", label, kit.Roll()))
		end
		if kit.HeadingDot() < 0.98 then
			table.insert(problems, string.format("%s: camera not behind the character (heading dot %.3f)", label, kit.HeadingDot()))
		end
	end
	function kit.ExpectSmooth(problems, label: string, samples: { number })
		local biggest = 0
		for i = 2, #samples do
			biggest = math.max(biggest, math.abs(samples[i] - samples[i - 1]))
		end
		-- 15 simulated fps: a ~60 degree swing over the recenter time moves < 20 degrees per frame
		if #samples < 5 or biggest > 20 then
			table.insert(problems, string.format("%s: recenter not smooth (%d frames, biggest step %.1f deg)", label, #samples, biggest))
		end
	end
	return kit
end

local function boardAndTakeControl(world, me, kit, problems)
	advanceUntil(world, function()
		return gameState(world):GetAttribute("Phase") == "Flight" and me:GetAttribute("InRound") == true
	end, 300)
	local reg = registry(world)
	local humanoid = me.Character:FindFirstChildOfClass("Humanoid")
	humanoid.Sit = false
	local seat = reg.MapService.Points.PilotSeat
	if seat.Occupant then
		seat.Occupant.Sit = false -- the NPC captain gives up the seat
	end
	world:Advance(0.1)
	seat:Sit(humanoid)
	reg.CockpitSystem:EnableManual(true)
	if not advanceUntil(world, function()
		return kit.Cam:IsPiloting()
	end, 3) then
		table.insert(problems, "A: taking the pilot seat with manual flight enabled did not start the flight camera")
	end
end

scenario("Camera: flight camera, release recenter, RECENTER button, death, respawn (A-F)", function(world)
	local problems = {}
	world:Boot()
	world:Advance(1)
	config(world, "GameConfig").StudioForceDisaster = "NavigationFailure"
	local bots = Bots.attach(world, { Seed = 77 })
	local me = world:AddPlayer("Pilot")
	local buddy = world:AddPlayer("Buddy")
	bots.Add(buddy)
	world:AttachClient(me, { Touch = true, Viewport = roblox.Vector2.new(812, 375) })
	world:Advance(1)
	local kit = cameraKit(world, me)
	local bindings = {}
	for name in world.RenderBindings do
		table.insert(bindings, name)
	end
	table.sort(bindings)
	if table.concat(bindings, ",") ~= "LF_CameraPost,LF_CameraPre" then
		table.insert(problems, "expected exactly the CameraController render steps, got: " .. table.concat(bindings, ","))
	end

	-- A: enter control -> flight camera (tilt) blends in
	boardAndTakeControl(world, me, kit, problems)
	kit.Attitude.Roll, kit.Attitude.Pitch = 10, 4
	world:Advance(1.5)
	if kit.Cam:GetTiltWeight() ~= 1 then
		table.insert(problems, "A: flight tilt did not blend in (" .. kit.Cam:GetTiltWeight() .. ")")
	end
	if math.abs(kit.Roll()) < 4 then
		table.insert(problems, string.format("A: flight camera shows no roll (%.1f)", kit.Roll()))
	end

	-- B: the camera follows the attitude, and a held attitude never accumulates into the view
	local pitchBefore = kit.Pitch()
	world:Advance(4)
	if math.abs(kit.Pitch() - pitchBefore) > 1.5 then
		table.insert(problems, string.format("B: camera pitch drifted from %.1f to %.1f while the attitude was held", pitchBefore, kit.Pitch()))
	end
	local rollRight = kit.Roll()
	kit.Attitude.Roll = -10
	world:Advance(1.5)
	if math.sign(kit.Roll()) == math.sign(rollRight) or math.abs(kit.Roll()) < 4 then
		table.insert(problems, string.format("B: camera roll did not follow the aircraft (%.1f -> %.1f)", rollRight, kit.Roll()))
	end
	print(string.format("      flight: roll %.1f -> %.1f, pitch held %.1f -> %.1f", rollRight, kit.Roll(), pitchBefore, kit.Pitch()))

	-- C: release control while looking down from above -> smooth return to eye level
	kit.Mess(-70, 120)
	local samples = kit.Record()
	registry(world).CockpitSystem:EnableManual(false)
	world:Advance(2)
	kit.StopRecord()
	if kit.Cam:IsPiloting() then
		table.insert(problems, "C: flight camera still active after control ended")
	end
	kit.ExpectNatural(problems, "C")
	kit.ExpectSmooth(problems, "C", samples)
	world:Advance(2)
	kit.ExpectNatural(problems, "C (2s after, Roblox camera in charge)")
	print(string.format("      release: %d frames, pitch %.1f, roll %.1f", #samples, kit.Pitch(), kit.Roll()))

	-- D: RECENTER button, not piloting
	local button = me:FindFirstChildOfClass("PlayerGui"):FindFirstChild("SpectateUI"):FindFirstChild("Root"):FindFirstChild("Recenter")
	if not button or not button.Visible then
		table.insert(problems, "D: RECENTER button missing or hidden while playing")
	end
	kit.Mess(65, -150)
	samples = kit.Record()
	world.M.signalFor(button, "Activated"):Fire()
	world:Advance(2)
	kit.StopRecord()
	kit.ExpectNatural(problems, "D")
	kit.ExpectSmooth(problems, "D", samples)
	-- D2: RECENTER while flying keeps the flight camera and does not touch the controls
	reg = registry(world)
	reg.CockpitSystem:EnableManual(true)
	advanceUntil(world, function()
		return kit.Cam:IsPiloting()
	end, 3)
	world.M.signalFor(button, "Activated"):Fire()
	world:Advance(1.5)
	if not kit.Cam:IsPiloting() or kit.Cam:GetTiltWeight() ~= 1 or kit.Cam:IsRecentering() then
		table.insert(problems, "D: RECENTER while flying broke the flight camera")
	end
	local cas = world.Game:GetService("ContextActionService")
	local cockpitUI = me:FindFirstChildOfClass("PlayerGui"):FindFirstChild("CockpitUI")
	if not cockpitUI:FindFirstChild("Root"):FindFirstChild("ManualFlight").Visible then
		table.insert(problems, "D: flight controls hidden after RECENTER")
	end
	local _ = cas

	-- E: die while flying -> camera state released at once
	local humanoid = me.Character:FindFirstChildOfClass("Humanoid")
	humanoid.Health = 0
	world:Advance(0.25)
	if kit.Cam:IsPiloting() or kit.Cam:GetTiltWeight() ~= 0 or kit.Cam:IsRecentering() then
		table.insert(problems, "E: camera state not reset on death")
	end
	if button.Visible then
		table.insert(problems, "E: RECENTER button still shown while dead")
	end

	-- F: respawn -> normal camera on the new character, recenter works
	local old = me.Character
	advanceUntil(world, function()
		return me.Character ~= old and me.Character ~= nil
	end, 10)
	world:Advance(1)
	local newHumanoid = me.Character:FindFirstChildOfClass("Humanoid")
	if kit.Camera.CameraSubject ~= newHumanoid then
		table.insert(problems, "F: camera subject is not the respawned character")
	end
	if not button.Visible then
		table.insert(problems, "F: RECENTER button hidden after respawn")
	end
	if kit.Cam:IsPiloting() or kit.Cam:GetTiltWeight() ~= 0 then
		table.insert(problems, "F: stale flight camera state after respawn")
	end
	kit.Mess(-60, 90)
	world.M.signalFor(button, "Activated"):Fire()
	world:Advance(2)
	kit.ExpectNatural(problems, "F")
	return problems
end)

scenario("Camera: round ends while flying -> camera released to Roblox (G)", function(world)
	local problems = {}
	world:Boot()
	world:Advance(1)
	config(world, "GameConfig").StudioForceDisaster = "NavigationFailure"
	local bots = Bots.attach(world, { Seed = 78 })
	local me = world:AddPlayer("Pilot")
	world:AttachClient(me)
	world:Advance(1)
	local kit = cameraKit(world, me)
	boardAndTakeControl(world, me, kit, problems)
	kit.Attitude.Roll, kit.Attitude.Pitch = 8, 3
	bots.Add(me) -- let the bot play the rest of the round
	local checked = false
	local _, finished = runRounds(world, 1, 900, function(phase)
		if phase == "Landing" then
			kit.Cam:SetPiloting(true) -- still flying when the round ends
		elseif phase == "Results" and not checked then
			checked = true
			if kit.Cam:IsPiloting() or kit.Cam:GetTiltWeight() ~= 0 or kit.Cam:IsRecentering() then
				table.insert(problems, "G: camera state not released when the round ended")
			end
			local humanoid = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
			if kit.Camera.CameraSubject ~= humanoid then
				table.insert(problems, "G: camera subject is not the player's character after the round")
			end
		end
	end)
	if finished < 1 or not checked then
		table.insert(problems, "round did not finish")
	end
	world:Advance(1)
	if math.abs(kit.Roll()) > 0.5 then
		table.insert(problems, string.format("G: camera still rolled %.1f degrees after the round", kit.Roll()))
	end
	return problems
end)

scenario("Player leaves mid-round (Crisis)", function(world)
	local problems = {}
	world:Boot()
	world:Advance(1)
	local bots = Bots.attach(world, { Seed = 5 })
	local a = world:AddPlayer("Stays1")
	local b = world:AddPlayer("Leaves")
	local c = world:AddPlayer("Stays2")
	bots.Add(a)
	bots.Add(b)
	bots.Add(c)
	local left = false
	local _, finished = runRounds(world, 1, 800, function(phase)
		if phase == "Crisis" and not left then
			left = true
			world.M.Library.spawn(function()
				world:RemovePlayer(b)
			end)
		end
	end)
	if finished < 1 then
		table.insert(problems, "round did not finish after a player left")
	end
	local result = resultsFor(world, a)
	if result and result.Total ~= 2 then
		table.insert(problems, "leaver should not count toward totals (Total=" .. tostring(result.Total) .. ")")
	end
	return problems
end)

scenario("One player dies: leaves the flight UI, respawns at the terminal, round continues", function(world)
	local problems = {}
	world:Boot()
	world:Advance(1)
	local bots = Bots.attach(world, { Seed = 31 })
	local victim = world:AddPlayer("Victim")
	local survivor = world:AddPlayer("Survivor")
	bots.Add(survivor)
	local killedAt = nil
	local checked = false
	local _, finished = runRounds(world, 1, 800, function(phase)
		if phase == "Disaster" and not killedAt then
			killedAt = world.Scheduler.Now
			registry(world).ConditionService:Kill(victim, "Test")
		elseif phase == "Crisis" and killedAt and not checked then
			checked = true
			if victim:GetAttribute("InRound") then
				table.insert(problems, "dead player still flagged InRound")
			end
			local character = victim.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not root or root.Position.Z > 1000 then
				table.insert(problems, "dead player did not respawn in the terminal")
			end
		end
	end)
	if finished < 1 then
		table.insert(problems, "round did not finish")
	end
	local result = resultsFor(world, victim)
	if not result or not result.Personal or result.Personal.Survived then
		table.insert(problems, "victim should get a results screen marked as not survived")
	end
	return problems
end)

scenario("Late joiner waits in the terminal and boards the next flight", function(world)
	local problems = {}
	world:Boot()
	world:Advance(1)
	local bots = Bots.attach(world, { Seed = 77 })
	bots.Add(world:AddPlayer("Early"))
	local late = nil
	local boardedLate = false
	local _, finished = runRounds(world, 2, 1400, function(phase)
		if phase == "Crisis" and not late then
			late = world:AddPlayer("Late")
			bots.Add(late)
		elseif phase == "Boarding" and late then
			world.M.Library.delay(2, function()
				if late:GetAttribute("InRound") then
					boardedLate = true
				end
			end)
		elseif phase == "Disaster" and late and not boardedLate and late:GetAttribute("InRound") then
			table.insert(problems, "late joiner was pulled into a flight already in progress")
		end
	end)
	if finished < 2 then
		table.insert(problems, "only " .. finished .. " rounds finished")
	end
	if not boardedLate then
		table.insert(problems, "late joiner never boarded the next flight")
	end
	return problems
end)

scenario("Everyone dies mid-round -> Complete Disaster, loop continues", function(world)
	local problems = {}
	world:Boot()
	world:Advance(1)
	local p1 = world:AddPlayer("Doomed1")
	local p2 = world:AddPlayer("Doomed2")
	local killed = false
	local history, finished = runRounds(world, 1, 800, function(phase)
		if phase == "Disaster" and not killed then
			killed = true
			local R = registry(world)
			R.ConditionService:Kill(p1, "Test")
			R.ConditionService:Kill(p2, "Test")
		end
	end)
	if finished < 1 then
		table.insert(problems, "round did not finish: " .. table.concat(history, " > "))
	end
	local result = resultsFor(world, p1)
	if not result or result.Outcome ~= "CompleteDisaster" then
		table.insert(problems, "expected CompleteDisaster, got " .. tostring(result and result.Outcome))
	end
	local more = runRounds(world, 0, 90)
	if not table.find(more, "Boarding") then
		table.insert(problems, "next round did not start after total wipe")
	end
	return problems
end)

scenario("Disaster module crash -> safe fallback", function(world)
	local problems = {}
	world:Boot()
	world:Advance(1)
	config(world, "GameConfig").StudioForceDisaster = "Turbulence"
	local server = world.Game:GetService("ServerScriptService"):FindFirstChild("Server")
	local turbulence = world.Require(server:FindFirstChild("Disasters"):FindFirstChild("Turbulence"))
	turbulence.Start = function()
		error("intentional test failure")
	end
	local bots = Bots.attach(world, { Seed = 11 })
	local player = world:AddPlayer("Crash")
	bots.Add(player)
	local _, finished = runRounds(world, 1, 700)
	if finished < 1 then
		table.insert(problems, "round did not finish after disaster error")
	end
	if not resultsFor(world, player) then
		table.insert(problems, "no results after disaster error")
	end
	return problems
end, { AllowWarnings = { "intentional test failure" } })

scenario("DataStore outage: temporary profile, then recovery merges progress", function(world)
	local problems = {}
	world:Boot()
	world:Advance(1)
	local player = world:AddPlayer("Offline")
	world:Advance(40)
	local R = registry(world)
	if player:GetAttribute("DataLoaded") ~= false then
		table.insert(problems, "expected a temporary profile during the outage")
	end
	if world.Store["u_" .. player.UserId] ~= nil then
		table.insert(problems, "temporary profile was written to the DataStore")
	end
	R.DataService:AddCredits(player, 500, "test")
	local before = R.DataService:Get(player).Credits
	world:Advance(120)
	if player:GetAttribute("DataLoaded") ~= true then
		table.insert(problems, "profile never recovered after the outage")
	end
	local after = R.DataService:Get(player).Credits
	if after < before then
		table.insert(problems, string.format("session credits lost in merge (%d -> %d)", before, after))
	end
	-- the temporary profile must never have been written to the store before recovery
	return problems
end, { StoreFailures = 6, AllowWarnings = { "load", "failed (attempt" } })

scenario("Developer product receipts are idempotent and saved", function(world)
	local problems = {}
	world:Boot()
	world:Advance(1)
	local monetization = config(world, "MonetizationConfig")
	monetization.Products.CreditsSmall.Id = 123456
	local player = world:AddPlayer("Buyer")
	world:Advance(3)
	local R = registry(world)
	local start = R.DataService:Get(player).Credits
	local receipt = { PlayerId = player.UserId, ProductId = 123456, PurchaseId = "receipt-1" }
	local first = world.Marketplace.ProcessReceipt(receipt)
	local second = world.Marketplace.ProcessReceipt(receipt)
	local credits = R.DataService:Get(player).Credits
	if tostring(first) ~= "Enum.ProductPurchaseDecision.PurchaseGranted" or tostring(second) ~= "Enum.ProductPurchaseDecision.PurchaseGranted" then
		table.insert(problems, "unexpected decisions: " .. tostring(first) .. ", " .. tostring(second))
	end
	if credits - start ~= 400 then
		table.insert(problems, "expected +400 credits exactly once, got +" .. (credits - start))
	end
	local stored = world.Store["u_" .. player.UserId]
	if not stored or not table.find(stored.Receipts, "receipt-1") then
		table.insert(problems, "receipt not persisted before acknowledging")
	end
	return problems
end)

scenario("Shop: buy, insufficient funds, equip, reject Robux-only item", function(world)
	local problems = {}
	world:Boot()
	world:Advance(1)
	local player = world:AddPlayer("Shopper")
	world:Advance(3)
	local R = registry(world)
	local profile = R.DataService:Get(player)
	profile.Credits = 350
	world:ClientFire("ShopPurchase", player, "PilotCap") -- 300
	world:Advance(1)
	if not R.DataService:Owns(player, "PilotCap") or profile.Credits ~= 50 then
		table.insert(problems, "PilotCap purchase failed (credits " .. profile.Credits .. ")")
	end
	world:ClientFire("ShopPurchase", player, "CaptainHat") -- 750, can't afford
	world:Advance(1)
	if R.DataService:Owns(player, "CaptainHat") then
		table.insert(problems, "bought an item without enough credits")
	end
	world:ClientFire("ShopPurchase", player, "TrailRainbow") -- Robux only
	world:Advance(1)
	if R.DataService:Owns(player, "TrailRainbow") then
		table.insert(problems, "bought a Robux-only item with credits")
	end
	world:ClientFire("Equip", player, "Hat", "PilotCap")
	world:Advance(1)
	if profile.Equipped.Hat ~= "PilotCap" then
		table.insert(problems, "equip failed")
	end
	world:ClientFire("Equip", player, "Hat", "CaptainHat") -- not owned
	world:Advance(1)
	if profile.Equipped.Hat ~= "PilotCap" then
		table.insert(problems, "equipped an unowned item")
	end
	world:ClientFire("ShopPurchase", player, { "exploit" })
	world:ClientFire("Equip", player, 5, nil)
	world:Advance(1)
	return problems
end)

---------------------------------------------------------------- Sky Shop

-- Data keys that would mean an item changes gameplay. No store item may carry any of them.
local GAMEPLAY_KEYS = { "Health", "MaxHealth", "WalkSpeed", "JumpPower", "Speed_Gameplay", "Damage", "Armor", "Survival", "Immunity", "Oxygen", "Revive", "Objective", "Landing", "Credits", "Multiplier", "Shield" }
local COSMETIC_TYPES = { Accessory = true, Outfit = true, Badge = true, Luggage = true, Title = true, Emote = true, Trail = true, Aura = true, VictoryEffect = true, Theme = true, PlaneSkin = true, WingEffect = true, PlaneTrail = true, Bundle = true }

scenario("Sky Shop catalog: integrity, rarity, price progression, honest bundles, no pay-to-win", function(world)
	local problems = {}
	world:Boot()
	local catalog = config(world, "ShopCatalog")
	local monetization = config(world, "MonetizationConfig")
	local seen = {}
	local starters, mids, premiums, robuxCheap = 0, 0, 0, 0
	local perCategory = {}
	for _, item in catalog.Items do
		if seen[item.Id] then
			table.insert(problems, "duplicate id " .. item.Id)
		end
		seen[item.Id] = true
		perCategory[item.Category] = (perCategory[item.Category] or 0) + 1
		if not COSMETIC_TYPES[item.Type] then
			table.insert(problems, item.Id .. " has non-cosmetic type " .. tostring(item.Type))
		end
		if not catalog.Rarities[item.Rarity] then
			table.insert(problems, item.Id .. " has unknown rarity " .. tostring(item.Rarity))
		end
		if item.Slot and not table.find(catalog.Slots, item.Slot) then
			table.insert(problems, item.Id .. " uses unknown slot " .. item.Slot)
		end
		if item.Type ~= "Bundle" and item.Type ~= "Title" and item.Type ~= "Emote" and not item.Slot then
			table.insert(problems, item.Id .. " is equippable but has no slot")
		end
		if item.Product and not monetization.Products[item.Product] then
			table.insert(problems, item.Id .. " references missing product " .. item.Product)
		end
		if item.Pass and not monetization.GamePasses[item.Pass] then
			table.insert(problems, item.Id .. " references missing pass " .. item.Pass)
		end
		if not item.Description or #item.Description < 5 then
			table.insert(problems, item.Id .. " has no description")
		end
		if not item.Default and not item.Price and not item.Product and not item.Pass and not item.Unlock and not catalog.BundlesContaining[item.Id] then
			table.insert(problems, item.Id .. " can never be obtained")
		end
		for _, key in GAMEPLAY_KEYS do
			if item.Data and item.Data[key] ~= nil then
				table.insert(problems, item.Id .. " carries gameplay key " .. key)
			end
		end
		if item.Price then
			local tier = catalog.TierOf(item)
			if tier == "Starter" then
				starters += 1
			elseif tier == "Mid" then
				mids += 1
			else
				premiums += 1
			end
		end
		if item.Product and not item.Exclusive and monetization.Products[item.Product].PriceHint <= 25 then
			robuxCheap += 1
		end
		if item.Type == "Bundle" then
			for _, inner in item.Data.Items do
				if not catalog.Get(inner) then
					table.insert(problems, item.Id .. " contains missing item " .. inner)
				end
			end
			if item.Description:find("Save") or item.Description:find("%%") then
				table.insert(problems, item.Id .. " claims a discount in its description")
			end
			local value = catalog.BundleValue(item)
			if value and item.Price and value <= item.Price then
				table.insert(problems, item.Id .. " costs as much as its contents bought separately")
			end
		end
	end
	for _, category in catalog.Categories do
		if category ~= "Premium" and (perCategory[category] or 0) < 3 then
			table.insert(problems, "category " .. category .. " has too few items")
		end
	end
	for _, rarity in catalog.RarityOrder do
		local count = 0
		for _, item in catalog.Items do
			if item.Rarity == rarity then
				count += 1
			end
		end
		if count == 0 then
			table.insert(problems, "no " .. rarity .. " items")
		end
	end
	if starters < 10 or mids < 10 or premiums < 6 then
		table.insert(problems, string.format("price progression too thin (starter %d, mid %d, premium %d)", starters, mids, premiums))
	end
	if robuxCheap < 1 then
		table.insert(problems, "no low-cost Robux cosmetic")
	end
	for _, id in catalog.Featured do
		if not catalog.Get(id) then
			table.insert(problems, "featured item missing: " .. id)
		end
	end
	if #catalog.Featured < 3 or #catalog.Featured > 5 then
		table.insert(problems, "featured should show 3-5 items")
	end
	for _, id in catalog.DailyPool do
		if not catalog.Get(id) then
			table.insert(problems, "daily pool item missing: " .. id)
		end
	end
	local a, b = catalog.DailyPicks(20000), catalog.DailyPicks(20000)
	if table.concat(a, ",") ~= table.concat(b, ",") or #a ~= catalog.DailyCount then
		table.insert(problems, "daily picks are not deterministic")
	end
	local distinct = {}
	for _, id in a do
		if distinct[id] then
			table.insert(problems, "daily picks repeat an item")
		end
		distinct[id] = true
	end
	-- Robux products may only grant cosmetics or Flight Credits
	for key, product in monetization.Products do
		for _, id in product.GrantItems or {} do
			local item = catalog.Get(id)
			if not item or not COSMETIC_TYPES[item.Type] then
				table.insert(problems, "product " .. key .. " grants non-cosmetic " .. id)
			end
		end
	end
	print(string.format("      %d items | starter %d, mid %d, premium %d credit items | %d cheap Robux items", #catalog.Items, starters, mids, premiums, robuxCheap))
	return problems
end)

scenario("Sky Shop server: bundles, derived ownership, new loadout slots, intro flag, Robux pack, visual-only", function(world)
	local problems = {}
	world:Boot()
	world:Advance(1)
	local player = world:AddPlayer("Collector")
	world:Advance(3)
	local R = registry(world)
	local profile = R.DataService:Get(player)
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	local before = { WalkSpeed = humanoid.WalkSpeed, JumpPower = humanoid.JumpPower, MaxHealth = humanoid.MaxHealth, Health = humanoid.Health }
	profile.Credits = 5000
	local function buy(id: string)
		world:ClientFire("ShopPurchase", player, id)
		world:Advance(1.2)
	end
	-- a bundle grants its contents, then the contents can't be bought again
	buy("BundleFirstFlight")
	for _, id in { "PilotCap", "EmotePilotSalute", "LuggageCarryOn" } do
		if not R.ShopService:Owns(player, id) then
			table.insert(problems, "First Flight Pack did not grant " .. id)
		end
	end
	local credits = profile.Credits
	buy("PilotCap")
	if profile.Credits ~= credits then
		table.insert(problems, "charged again for an item already owned through a bundle")
	end
	buy("BundleFirstFlight")
	if profile.Credits ~= credits then
		table.insert(problems, "bought the same bundle twice")
	end
	-- older purchases: owning a bundle id implies everything inside it (incl. new additions)
	R.DataService:Grant(player, "BundleFirstClass")
	for _, id in { "OutfitFirstClass", "LuggageFirstClass", "BadgeGoldBoardingPass", "EmoteFirstClassToast", "TrailRainbow" } do
		if not R.ShopService:Owns(player, id) then
			table.insert(problems, "First Class Pack owner does not own " .. id)
		end
	end
	-- exclusive / Robux items can't be bought with credits
	credits = profile.Credits
	buy("StormVisor")
	buy("PlaneLuxury")
	if R.ShopService:Owns(player, "StormVisor") or R.ShopService:Owns(player, "PlaneLuxury") or profile.Credits ~= credits then
		table.insert(problems, "an exclusive / Robux item was sold for credits")
	end
	-- new slots: buy + equip one of each
	local equips = {
		{ "Outfit", "OutfitCasualFlyer" }, { "Badge", "BadgeJuniorWings" }, { "Aura", "AuraSmoke" },
		{ "PlaneSkin", "PlaneSkyBlue" }, { "WingEffect", "WingColorTips" }, { "PlaneTrail", "PlaneTrailContrail" },
		{ "Trail", "TrailSkyStreak" }, { "Emote", "EmoteNervous" },
	}
	for _, pair in equips do
		buy(pair[2])
		world:ClientFire("Equip", player, pair[1], pair[2])
		world:Advance(0.6)
		if profile.Equipped[pair[1]] ~= pair[2] then
			table.insert(problems, "could not equip " .. pair[2] .. " in " .. pair[1])
		end
	end
	world:ClientFire("Equip", player, "Luggage", "LuggageCarryOn")
	world:ClientFire("Equip", player, "Hat", "PilotCap")
	world:Advance(1)
	-- wrong slot / unowned are rejected
	world:ClientFire("Equip", player, "Hat", "OutfitPilot")
	world:ClientFire("Equip", player, "Outfit", "OutfitGoldenTraveler")
	world:Advance(1)
	if profile.Equipped.Hat ~= "PilotCap" or profile.Equipped.Outfit ~= "OutfitCasualFlyer" then
		table.insert(problems, "server accepted a wrong-slot or unowned equip")
	end
	-- required slots fall back to their default instead of becoming empty
	world:ClientFire("Equip", player, "PlaneSkin", nil)
	world:Advance(1)
	if profile.Equipped.PlaneSkin ~= "PlaneClassic" then
		table.insert(problems, "unequipping the plane skin should restore the classic skin")
	end
	-- cosmetics are built on the character, decoration only
	R.CosmeticService:Apply(player)
	local character = player.Character
	local folder = character:FindFirstChild("LF_Cosmetics")
	local shells, nonDecor = 0, 0
	if folder then
		for _, d in folder:GetDescendants() do
			if d:IsA("BasePart") then
				if d.Name == "OutfitShell" then
					shells += 1
				end
				if d.CanCollide or d.CanQuery or d.CanTouch or not d.Massless then
					nonDecor += 1
				end
			end
		end
	end
	if shells == 0 then
		table.insert(problems, "outfit was not built on the character")
	end
	if nonDecor > 0 then
		table.insert(problems, nonDecor .. " cosmetic parts can collide / be queried / have mass")
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root:FindFirstChild("LF_Aura") then
		table.insert(problems, "aura was not attached")
	end
	for key, value in before do
		if humanoid[key] ~= value then
			table.insert(problems, "equipping cosmetics changed humanoid " .. key)
		end
	end
	-- emote with bubble
	world:ClientFire("PlayEmote", player, "EmoteNervous")
	world:Advance(0.5)
	if not character:FindFirstChild("Head"):FindFirstChild("LF_EmoteBubble") then
		table.insert(problems, "emote bubble not shown")
	end
	-- first store visit flag persists in the profile
	world:ClientFire("StoreIntroSeen", player)
	world:Advance(0.5)
	if profile.Flags.StoreIntro ~= true then
		table.insert(problems, "store intro flag not saved")
	end
	-- Robux bundle receipt grants the bundle and everything inside
	local monetization = config(world, "MonetizationConfig")
	monetization.Products.StormRiderPack.Id = 777001
	local decision = world.Marketplace.ProcessReceipt({ PlayerId = player.UserId, ProductId = 777001, PurchaseId = "storm-1" })
	if tostring(decision) ~= "Enum.ProductPurchaseDecision.PurchaseGranted" then
		table.insert(problems, "storm pack receipt not granted: " .. tostring(decision))
	end
	for _, id in { "BundleStormRider", "StormVisor", "PlaneStorm", "WingLightning", "AuraLightning", "EmoteStormDance" } do
		if not R.ShopService:Owns(player, id) then
			table.insert(problems, "Storm Rider Pack did not grant " .. id)
		end
	end
	-- persisted
	R.DataService:Save(player, false)
	local stored = world.Store["u_" .. player.UserId]
	if not stored or stored.Equipped.Outfit ~= "OutfitCasualFlyer" or stored.Equipped.PlaneTrail ~= "PlaneTrailContrail" or not stored.Owned.AuraSmoke or stored.Flags.StoreIntro ~= true then
		table.insert(problems, "loadout / ownership / flags not saved to the DataStore")
	end
	-- snapshot sent to the client lists derived bundle contents
	local snapshot = R.DataService:Snapshot(player)
	if not table.find(snapshot.Owned, "OutfitFirstClass") then
		table.insert(problems, "client snapshot misses items owned through a bundle")
	end
	return problems
end)

local STORE_DEVICES = {
	{ Label = "phone", Device = { Touch = true, Viewport = roblox.Vector2.new(812, 375) } },
	{ Label = "small phone", Device = { Touch = true, Viewport = roblox.Vector2.new(740, 360) } },
	{ Label = "tablet", Device = { Touch = true, Viewport = roblox.Vector2.new(1024, 768) } },
	{ Label = "desktop", Device = nil },
}

for _, run in STORE_DEVICES do
	scenario("Sky Shop UI (" .. run.Label .. "): intro, every page, previews, buy + celebrate, equip, loadout, plane look, readable", function(world)
		local problems = {}
		world:Boot()
		world:Advance(1)
		local me = world:AddPlayer("ShopFan")
		world:AttachClient(me, run.Device)
		world:Advance(3)
		local R = registry(world)
		R.DataService:AddCredits(me, 3000, "test")
		world:Advance(1)
		local clientFolder = world.Game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client")
		local shop = world.Require(clientFolder:FindFirstChild("Controllers"):FindFirstChild("ShopController"))
		local UIKit = world.Require(clientFolder:FindFirstChild("UI"):FindFirstChild("UIKit"))
		local gui = me:FindFirstChildOfClass("PlayerGui"):FindFirstChild("ShopUI")
		local function click(button)
			world.M.signalFor(button, "MouseButton1Down"):Fire()
			world.M.signalFor(button, "Activated"):Fire()
			world.M.signalFor(button, "MouseButton1Up"):Fire()
		end
		local function find(root, name: string)
			for _, d in root:GetDescendants() do
				if d.Name == name then
					return d
				end
			end
			return nil
		end
		shop:Open()
		world:Advance(0.5)
		local window = find(gui, "Window")
		local intro = window:FindFirstChild("Intro")
		if not intro or not intro.Visible then
			table.insert(problems, "first-time intro not shown")
		else
			local text = {}
			for _, d in intro:GetDescendants() do
				if d:IsA("TextLabel") then
					table.insert(text, d.Text)
				end
			end
			if not table.concat(text, " "):find("MAKE YOUR FLIGHT YOURS") then
				table.insert(problems, "intro headline missing")
			end
			click(find(intro, "Skip"))
			world:Advance(0.5)
			if intro.Visible or R.DataService:Get(me).Flags.StoreIntro ~= true then
				table.insert(problems, "skipping the intro did not close it / save the flag")
			end
		end
		local content = window:FindFirstChild("Content")
		local body = content:FindFirstChild("Body")
		local tabs = content:FindFirstChild("Tabs")
		local sheet = window:FindFirstChild("Sheet")
		local scale = UIKit.Scale()
		local tinyText, smallButtons = {}, {}
		local function audit(root)
			for _, d in root:GetDescendants() do
				if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Name ~= "Particle" and visible(d) and not d.TextScaled and d.Text ~= "" then
					if d.TextSize * scale < 9.9 then
						tinyText[d.Text] = d.TextSize * scale
					end
				end
				if d:IsA("TextButton") and visible(d) and d.Text ~= "" and d.Size.Y.Scale == 0 and d.Size.Y.Offset * scale < 29.5 then
					smallButtons[d.Name .. ":" .. d.Text] = d.Size.Y.Offset * scale
				end
			end
		end
		local pagesSeen = 0
		for _, name in { "Featured", "FlightGear", "Outfits", "Emotes", "Plane", "Effects", "Bundles", "Premium", "Loadout" } do
			local tab = tabs:FindFirstChild(name)
			if not tab then
				table.insert(problems, "missing tab " .. name)
			else
				click(tab)
				world:Advance(0.4)
				local cards, previews, actions = 0, 0, 0
				for _, d in body:GetDescendants() do
					if d.Name == "ArtHolder" then
						cards += 1
					elseif d.Name == "Preview" and d:IsA("TextButton") then
						previews += 1
					elseif d.Name == "Action" then
						actions += 1
					end
				end
				if name ~= "Loadout" and (cards == 0 or previews ~= cards or actions ~= cards) then
					table.insert(problems, string.format("%s page: %d cards, %d preview buttons, %d action buttons", name, cards, previews, actions))
				end
				-- grid cells must fit the body width
				for _, d in body:GetDescendants() do
					if d:IsA("UIGridLayout") then
						local width = d.CellSize.X.Offset
						if width * scale < 120 then
							table.insert(problems, string.format("%s page: cards only %.0fpx wide", name, width * scale))
							break
						end
					end
				end
				audit(window)
				pagesSeen += 1
			end
		end
		-- previews of different kinds of items
		local catalog = config(world, "ShopCatalog")
		for _, id in { "OutfitPilot", "PlaneNeon", "EmoteVictory", "AuraStars", "BundleFirstClass", "TitleCaptain", "VictoryFireworks", "PlaneTrailRainbow" } do
			click(tabs:FindFirstChild(catalog.Get(id).Category))
			world:Advance(0.3)
			local cardFrame = find(body, id)
			if not cardFrame then
				table.insert(problems, "no card for " .. id)
			else
				click(cardFrame:FindFirstChild("Preview"))
				world:Advance(0.6)
				if not sheet.Visible or not find(sheet, "PreviewBox") then
					table.insert(problems, "preview did not open for " .. id)
				end
				audit(sheet)
				click(find(sheet, "Close"))
				world:Advance(0.2)
			end
		end
		-- buy with the confirm step, then the celebration, then equip
		click(tabs:FindFirstChild("Outfits"))
		world:Advance(0.3)
		local cardFrame = find(body, "OutfitAdventurer")
		click(cardFrame:FindFirstChild("Action"))
		world:Advance(0.2)
		if R.ShopService:Owns(me, "OutfitAdventurer") then
			table.insert(problems, "a single tap bought the item (no confirm step)")
		end
		cardFrame = find(body, "OutfitAdventurer")
		click(cardFrame:FindFirstChild("Action"))
		world:Advance(1)
		if not R.ShopService:Owns(me, "OutfitAdventurer") then
			table.insert(problems, "confirmed purchase did not go through")
		end
		local celebration = window:FindFirstChild("Celebration")
		local celebrated = false
		for _, d in celebration:GetDescendants() do
			if d:IsA("TextLabel") and d.Text == "PURCHASED!" then
				celebrated = true
			end
		end
		if not celebration.Visible or not celebrated then
			table.insert(problems, "no PURCHASED! celebration")
		end
		local equipNow = nil
		for _, d in celebration:GetDescendants() do
			if d:IsA("TextButton") and d.Text == "EQUIP NOW" then
				equipNow = d
			end
		end
		if equipNow then
			click(equipNow)
			world:Advance(1)
		end
		if R.DataService:Get(me).Equipped.Outfit ~= "OutfitAdventurer" then
			table.insert(problems, "EQUIP NOW did not equip the outfit")
		end
		cardFrame = find(body, "OutfitAdventurer")
		local action = cardFrame and cardFrame:FindFirstChild("Action")
		if not action or action.Text ~= "EQUIPPED ✔" then
			table.insert(problems, "card does not show EQUIPPED after equipping (" .. tostring(action and action.Text) .. ")")
		end
		-- loadout picker equips a plane skin; the aircraft exterior changes on this client only
		R.DataService:Grant(me, "PlaneMint")
		world:Advance(0.5)
		click(tabs:FindFirstChild("Loadout"))
		world:Advance(0.3)
		local slotTile = find(body, "PlaneSkin")
		click(slotTile)
		world:Advance(0.4)
		local picked = false
		for _, d in sheet:GetDescendants() do
			if d:IsA("TextButton") and d.Text == "EQUIP" and not picked then
				click(d)
				picked = true
			end
		end
		world:Advance(1)
		if R.DataService:Get(me).Equipped.PlaneSkin ~= "PlaneMint" then
			table.insert(problems, "loadout picker did not equip the plane skin")
		end
		world:Advance(0.5)
		local exterior = world.Game:GetService("Workspace"):FindFirstChild("World"):FindFirstChild("Airplane"):FindFirstChild("Exterior")
		local wing = exterior:FindFirstChild("Wing")
		local mint = catalog.Get("PlaneMint").Data.Hull
		if not wing or (wing.Color.R - mint.R) ^ 2 + (wing.Color.G - mint.G) ^ 2 > 0.001 or not exterior:FindFirstChild("LF_PlaneLook") then
			table.insert(problems, "plane skin not shown on the aircraft exterior")
		end
		for _, d in exterior:FindFirstChild("LF_PlaneLook"):GetDescendants() do
			if d:IsA("BasePart") and (d.CanCollide or d.CanQuery) then
				table.insert(problems, "plane decoration " .. d.Name .. " can collide / be queried")
				break
			end
		end
		audit(window)
		for text, px in tinyText do
			table.insert(problems, string.format("text too small (%.1fpx): %s", px, text))
		end
		for name, px in smallButtons do
			table.insert(problems, string.format("button too small (%.0fpx tall): %s", px, name))
		end
		print(string.format("      scale %.2f | pages %d", scale, pagesSeen))
		return problems
	end, { AllowWarnings = { "[PlaneCosmetics]" } })
end

print(string.format("\n%d/%d scenarios passed", #results - failures, #results))
process.exit(if failures == 0 then 0 else 1)
