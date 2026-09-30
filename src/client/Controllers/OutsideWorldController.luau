--[[
	OutsideWorldController
	Everything visible through the windows, simulated locally so the aircraft itself never moves:
	  * clouds streaming past (speed from FlightState.Speed), storm-darkened when stormy
	  * the ground rising as altitude drops, and a runway sliding underneath during the landing
	  * bird flocks (Bird Strike clue), runway approach lights in fog (Blind Approach)
	  * engine fire / smoke on the wing engines
	Parts are created client-side only and pooled; nothing here replicates.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MapConfig = require(ReplicatedStorage.Shared.Config.MapConfig)
local ClientState = require(script.Parent.Parent.ClientState)

local OutsideWorldController = {}

local O = MapConfig.PlaneOrigin
local folder: Folder
local clouds: { { Part: BasePart, Speed: number } } = {}
local birds: { { Part: BasePart, Offset: Vector3, Phase: number } } = {}
local beacons: { BasePart } = {}
local ground: Part
local groundTexture: Texture
local runway: Part
local engineFx: { [string]: { Fire: Fire, Smoke: Smoke } } = {}
local runwayOffset = 0
local NOSE, TAIL = 700, -700

local function makeCloud(): Part
	local cloud = Instance.new("Part")
	cloud.Name = "Cloud"
	cloud.Shape = Enum.PartType.Ball
	cloud.Anchored = true
	cloud.CanCollide = false
	cloud.CanQuery = false
	cloud.CanTouch = false
	cloud.CastShadow = false
	cloud.Material = Enum.Material.SmoothPlastic
	cloud.Color = Color3.fromRGB(245, 247, 250)
	cloud.Transparency = 0.25
	local size = math.random(40, 110)
	cloud.Size = Vector3.new(size, size * 0.55, size)
	cloud.Parent = folder
	return cloud
end

local function placeCloud(entry, x: number?)
	local altitude = ClientState.Flight("Altitude") or 35000
	local low = altitude < 12000
	local side = if math.random() < 0.5 then -1 else 1
	local z = side * math.random(45, 420)
	local y
	if low then
		y = math.random(-80, 120)
	else
		y = if math.random() < 0.7 then -math.random(60, 260) else math.random(-30, 60)
	end
	entry.Part.Position = O + Vector3.new(x or math.random(TAIL, NOSE), y, z)
	entry.Speed = math.random(80, 120) / 100
end

local function buildGround()
	ground = Instance.new("Part")
	ground.Name = "Ground"
	ground.Anchored = true
	ground.CanCollide = false
	ground.CanQuery = false
	ground.CastShadow = false
	ground.Size = Vector3.new(2048, 2, 2048)
	ground.Color = Color3.fromRGB(75, 110, 60)
	ground.Material = Enum.Material.Grass
	ground.Parent = folder
	groundTexture = Instance.new("Texture")
	groundTexture.Texture = "rbxasset://textures/terrain/grass.png"
	groundTexture.StudsPerTileU = 60
	groundTexture.StudsPerTileV = 60
	groundTexture.Face = Enum.NormalId.Top
	groundTexture.Color3 = Color3.fromRGB(120, 160, 100)
	groundTexture.Parent = ground

	runway = Instance.new("Part")
	runway.Name = "Runway"
	runway.Anchored = true
	runway.CanCollide = false
	runway.CanQuery = false
	runway.CastShadow = false
	runway.Size = Vector3.new(1400, 1, 70)
	runway.Color = Color3.fromRGB(45, 46, 50)
	runway.Material = Enum.Material.Asphalt
	runway.Parent = folder
	for i = 0, 34 do
		local stripe = Instance.new("Part")
		stripe.Name = "Centreline"
		stripe.Anchored = true
		stripe.CanCollide = false
		stripe.CanQuery = false
		stripe.Size = Vector3.new(18, 0.2, 1.2)
		stripe.Color = Color3.fromRGB(240, 240, 240)
		stripe.Material = Enum.Material.Neon
		stripe:SetAttribute("OffsetX", -680 + i * 40)
		stripe.Parent = runway
	end
	for _, z in { -36, 36 } do
		for i = 0, 27 do
			local light = Instance.new("Part")
			light.Name = "EdgeLight"
			light.Anchored = true
			light.CanCollide = false
			light.CanQuery = false
			light.Size = Vector3.new(1.4, 1.4, 1.4)
			light.Shape = Enum.PartType.Ball
			light.Color = Color3.fromRGB(255, 240, 200)
			light.Material = Enum.Material.Neon
			light:SetAttribute("OffsetX", -680 + i * 50)
			light:SetAttribute("OffsetZ", z)
			light.Parent = runway
		end
	end
end

local runwayVisible = true

local function positionRunway(y: number, xOffset: number, visible: boolean)
	if not visible and not runwayVisible then
		return -- already hidden; skip touching ~90 parts every frame
	end
	runwayVisible = visible
	runway.Transparency = if visible then 0 else 1
	local base = O + Vector3.new(xOffset, y + 1.2, 0)
	runway.Position = base
	for _, child in runway:GetChildren() do
		if child:IsA("BasePart") then
			child.Transparency = if visible then 0 else 1
			child.Position = base + Vector3.new(child:GetAttribute("OffsetX") or 0, 0.6, child:GetAttribute("OffsetZ") or 0)
		end
	end
end

local function buildBirds()
	for i = 1, 26 do
		local bird = Instance.new("WedgePart")
		bird.Name = "Bird"
		bird.Anchored = true
		bird.CanCollide = false
		bird.CanQuery = false
		bird.Size = Vector3.new(0.3, 1.2, 2.6)
		bird.Color = Color3.fromRGB(40, 40, 45)
		bird.Transparency = 1
		bird.Parent = folder
		table.insert(birds, {
			Part = bird,
			Offset = Vector3.new(math.random(-120, 120), math.random(-12, 20), (if i % 2 == 0 then -1 else 1) * math.random(22, 70)),
			Phase = math.random() * 6,
		})
	end
end

local function buildBeacons()
	for i = 1, 12 do
		local beacon = Instance.new("Part")
		beacon.Name = "ApproachLight"
		beacon.Anchored = true
		beacon.CanCollide = false
		beacon.CanQuery = false
		beacon.Shape = Enum.PartType.Ball
		beacon.Size = Vector3.new(4, 4, 4)
		beacon.Material = Enum.Material.Neon
		beacon.Color = if i % 3 == 0 then Color3.fromRGB(255, 60, 60) else Color3.fromRGB(255, 250, 230)
		beacon.Transparency = 1
		beacon:SetAttribute("Index", i)
		beacon.Parent = folder
		table.insert(beacons, beacon)
	end
end

local function engineEffects()
	local airplane = Workspace:FindFirstChild("World") and Workspace.World:FindFirstChild("Airplane")
	local exterior = airplane and airplane:FindFirstChild("Exterior")
	if not exterior then
		return
	end
	for _, key in { "EngineL", "EngineR" } do
		local engine = exterior:FindFirstChild(key)
		if engine and not engineFx[key] then
			local fire = Instance.new("Fire")
			fire.Enabled = false
			fire.Size = 14
			fire.Heat = 20
			fire.Color = Color3.fromRGB(255, 120, 30)
			fire.Parent = engine
			local smoke = Instance.new("Smoke")
			smoke.Enabled = false
			smoke.Size = 12
			smoke.Opacity = 0.35
			smoke.RiseVelocity = 2
			smoke.Color = Color3.fromRGB(40, 40, 40)
			smoke.Parent = engine
			engineFx[key] = { Fire = fire, Smoke = smoke }
		end
	end
end

function OutsideWorldController:PuffSmoke(side: number, duration: number)
	engineEffects()
	local fx = engineFx[if side < 0 then "EngineL" else "EngineR"]
	if fx then
		fx.Smoke.Enabled = true
		task.delay(duration, function()
			local key = if side < 0 then "EngineSmokeL" else "EngineSmokeR"
			if not ClientState.Flight(key) then
				fx.Smoke.Enabled = false
			end
		end)
	end
end

function OutsideWorldController:Init()
	folder = Instance.new("Folder")
	folder.Name = "LF_OutsideWorld"
	folder.Parent = Workspace
	for _ = 1, 26 do
		local entry = { Part = makeCloud(), Speed = 1 }
		placeCloud(entry)
		table.insert(clouds, entry)
	end
	buildGround()
	buildBirds()
	buildBeacons()
end

function OutsideWorldController:Start()
	task.delay(3, engineEffects)
	for _, pair in { { "EngineFireL", "EngineL", "Fire" }, { "EngineFireR", "EngineR", "Fire" }, { "EngineSmokeL", "EngineL", "Smoke" }, { "EngineSmokeR", "EngineR", "Smoke" } } do
		ClientState.OnFlight(pair[1], function(on)
			engineEffects()
			local fx = engineFx[pair[2]]
			if fx then
				(fx :: any)[pair[3]].Enabled = on == true
				if pair[3] == "Fire" and on then
					fx.Smoke.Enabled = true
				end
			end
		end)
	end

	local visible = true
	RunService.RenderStepped:Connect(function(dt)
		local camera = Workspace.CurrentCamera
		local inPlane = camera and MapConfig.IsInsidePlane(camera.Focus.Position)
		if inPlane ~= visible then
			visible = inPlane == true
			folder.Parent = if visible then Workspace else nil
		end
		if not visible then
			return
		end
		local altitude = ClientState.Flight("Altitude") or 35000
		local onGround = ClientState.Flight("OnGround") == true
		local approach = ClientState.Flight("Approach") == true
		local speedKts = ClientState.Flight("Speed") or 460
		local speed = if onGround then 0 else speedKts * 0.55 * (if approach then 0.6 else 1)
		local storm = (ClientState.Flight("Storm") or 0) > 0 or ClientState.Flight("Weather") == "Storm"
		local cloudColor = if storm then Color3.fromRGB(95, 98, 110) else Color3.fromRGB(245, 247, 250)

		-- clouds
		for _, entry in clouds do
			local part = entry.Part
			local position = part.Position - Vector3.new(speed * entry.Speed * dt, 0, 0)
			if position.X < O.X + TAIL then
				placeCloud(entry, NOSE)
			else
				part.Position = position
			end
			part.Color = cloudColor
			part.Transparency = if altitude < 1500 then 1 else 0.25
		end

		-- ground & runway
		local groundDistance = math.clamp(altitude * 0.12, 7, 4500)
		ground.Transparency = if altitude > 20000 then 1 else 0
		ground.Position = O + Vector3.new(0, -groundDistance, 0)
		groundTexture.OffsetStudsU = (groundTexture.OffsetStudsU + speed * dt) % 60
		if approach or onGround then
			if onGround then
				runwayOffset = math.max(runwayOffset - speed * dt * 0.5, -500)
			else
				runwayOffset = math.clamp(altitude * 0.25, 0, 900)
			end
			positionRunway(-groundDistance, runwayOffset, true)
		else
			runwayOffset = 900
			positionRunway(-groundDistance, 0, false)
		end

		-- birds
		local showBirds = ClientState.Flight("Birds") == true
		local t = os.clock()
		for _, bird in birds do
			if showBirds then
				local drift = (t * 30) % 300 - 150
				local wing = math.sin(t * 9 + bird.Phase)
				bird.Part.Transparency = 0
				bird.Part.CFrame = CFrame.new(O + bird.Offset + Vector3.new(drift, math.sin(t + bird.Phase) * 3, 0)) * CFrame.Angles(0, math.rad(-90), wing * 0.6)
			else
				bird.Part.Transparency = 1
			end
		end

		-- runway approach lights in fog
		local side = ClientState.Flight("RunwaySide") or 0
		for _, beacon in beacons do
			if side ~= 0 then
				local index = beacon:GetAttribute("Index")
				local strobe = (math.floor(t * 6) + index) % 4 == 0
				beacon.Transparency = if strobe then 0 else 0.6
				beacon.Position = O + Vector3.new(80 - index * 18, -45, side * 140)
			else
				beacon.Transparency = 1
			end
		end
	end)
end

return OutsideWorldController
