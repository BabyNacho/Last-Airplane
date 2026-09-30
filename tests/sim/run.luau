--[[
	LAST FLIGHT server simulation tests.
	Run from the repository root after building the place:
		rojo build default.project.json -o build/LastFlight.rbxl
		lune run tests/sim/run
]]

local process = require("@lune/process")

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
	-- a round where everyone died legitimately skips straight to the landing
	local required = if survived == false then { "Boarding", "Flight", "Landing", "Results" } else { "Boarding", "Flight", "Disaster", "Crisis", "FinalEvent", "Landing", "Results" }
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

print(string.format("\n%d/%d scenarios passed", #results - failures, #results))
process.exit(if failures == 0 then 0 else 1)
