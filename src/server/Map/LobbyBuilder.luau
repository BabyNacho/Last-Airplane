--[[
	LobbyBuilder
	Builds the airport terminal: departure gate, departure board, shop / wardrobe / records kiosks,
	server leaderboard, VIP lounge, a parked aircraft on the apron and the spawn.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage.Shared.Config.MapConfig)
local B = require(script.Parent.BuildUtil)

local LobbyBuilder = {}

local O = MapConfig.LobbyOrigin

local C = {
	Floor = Color3.fromRGB(215, 214, 208),
	FloorAccent = Color3.fromRGB(60, 80, 120),
	Wall = Color3.fromRGB(235, 236, 238),
	Roof = Color3.fromRGB(245, 245, 245),
	Glass = Color3.fromRGB(160, 200, 225),
	Steel = Color3.fromRGB(120, 128, 138),
	Seat = Color3.fromRGB(40, 60, 100),
	Carpet = Color3.fromRGB(50, 58, 80),
	Gold = Color3.fromRGB(230, 185, 70),
	Tarmac = Color3.fromRGB(70, 72, 76),
	Grass = Color3.fromRGB(90, 140, 70),
	Hull = Color3.fromRGB(240, 242, 246),
	Livery = Color3.fromRGB(40, 90, 170),
	Plant = Color3.fromRGB(60, 140, 70),
}

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(O + Vector3.new(x, y, z))
end

local function box(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, extra: { [string]: any }?)
	local props = { Name = name, Size = size, CFrame = cframe, Color = color, Material = material or Enum.Material.SmoothPlastic, Parent = parent }
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return B.Part(props)
end

local function screen(parent: Instance, name: string, cframe: CFrame, size: Vector3, title: string, subtitle: string?, accent: Color3?): Part
	local part = box(parent, name, size, cframe, Color3.fromRGB(15, 20, 30), Enum.Material.Neon, { CanCollide = false })
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Display"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = part
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(14, 18, 28)
	frame.Parent = gui
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0.06, 0)
	bar.BackgroundColor3 = accent or Color3.fromRGB(70, 150, 255)
	bar.BorderSizePixel = 0
	bar.Parent = frame
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(0.9, 0, 0.4, 0)
	titleLabel.Position = UDim2.new(0.05, 0, 0.14, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.Text = title
	titleLabel.Parent = frame
	local sub = Instance.new("TextLabel")
	sub.Name = "Subtitle"
	sub.Size = UDim2.new(0.9, 0, 0.28, 0)
	sub.Position = UDim2.new(0.05, 0, 0.6, 0)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamMedium
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(170, 185, 210)
	sub.Text = subtitle or ""
	sub.Parent = frame
	return part
end

local function kiosk(parent: Instance, points, key: string, x: number, z: number, title: string, subtitle: string, action: string, accent: Color3)
	local model = B.Model(key, parent)
	box(model, "Base", Vector3.new(5, 3.2, 3), at(x, 1.6, z), Color3.fromRGB(30, 34, 44), Enum.Material.Metal)
	box(model, "Trim", Vector3.new(5.2, 0.3, 3.2), at(x, 3.3, z), accent, Enum.Material.Neon)
	box(model, "Post", Vector3.new(1, 5, 1), at(x, 5.7, z + 0.8), Color3.fromRGB(30, 34, 44), Enum.Material.Metal)
	local display = screen(model, "Screen", at(x, 8.4, z + 0.8) * CFrame.Angles(0, math.pi, 0), Vector3.new(7, 4, 0.3), title, subtitle, accent)
	B.Sign(display, Enum.NormalId.Back, title, { TextColor3 = accent })
	local promptPart = B.Point(key .. "Prompt", at(x, 3, z - 1), model, Vector3.new(4, 4, 2))
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "KioskPrompt"
	prompt.ActionText = action
	prompt.ObjectText = title
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("Kiosk", key)
	prompt.Parent = promptPart
	B.Light(promptPart, "PointLight", { Range = 12, Brightness = 1.2, Color = accent })
	points.Kiosks[key] = promptPart
end

local function gateSeats(parent: Instance, x: number, z: number, count: number, facingDir: number)
	local model = B.Model("GateSeats", parent)
	box(model, "Beam", Vector3.new(count * 2.6, 0.4, 0.6), at(x, 1.2, z), C.Steel, Enum.Material.Metal)
	for i = 0, count - 1 do
		local sx = x - (count - 1) * 1.3 + i * 2.6
		local cf = CFrame.lookAt(O + Vector3.new(sx, 1.8, z), O + Vector3.new(sx, 1.8, z + facingDir))
		B.Seat({
			Name = "GateSeat",
			Size = Vector3.new(2.2, 0.5, 2.2),
			CFrame = cf,
			Color = C.Seat,
			Material = Enum.Material.Fabric,
			Parent = model,
		})
		box(model, "Back", Vector3.new(2.2, 2.4, 0.4), cf * CFrame.new(0, 1.3, 1.1), C.Seat, Enum.Material.Fabric)
	end
	for _, dx in { -1, 1 } do
		box(model, "Leg", Vector3.new(0.4, 1.2, 0.4), at(x + dx * (count * 1.2), 0.6, z), C.Steel, Enum.Material.Metal)
	end
end

local function plant(parent: Instance, x: number, z: number)
	box(parent, "Planter", Vector3.new(3, 2, 3), at(x, 1, z), Color3.fromRGB(60, 60, 66), Enum.Material.Concrete)
	B.Ball({ Name = "Foliage", Size = Vector3.new(4, 4, 4), CFrame = at(x, 4, z), Color = C.Plant, Material = Enum.Material.Grass, Parent = parent })
	B.Ball({ Name = "Foliage", Size = Vector3.new(3, 3, 3), CFrame = at(x + 0.6, 5.6, z - 0.4), Color = C.Plant, Material = Enum.Material.Grass, Parent = parent })
end

local function parkedAircraft(parent: Instance)
	local model = B.Model("ParkedAircraft", parent)
	local cx, cy, cz = -10, 12, 120
	B.Cylinder({ Name = "Fuselage", Size = Vector3.new(150, 22, 22), CFrame = at(cx, cy, cz), Color = C.Hull, Material = Enum.Material.Metal, Parent = model })
	box(model, "LiveryStripe", Vector3.new(146, 2.2, 22.4), at(cx, cy - 2, cz), C.Livery, Enum.Material.Metal)
	B.Ball({ Name = "Nose", Size = Vector3.new(22, 22, 22), CFrame = at(cx + 75, cy, cz), Color = C.Hull, Material = Enum.Material.Metal, Parent = model })
	box(model, "CockpitWindows", Vector3.new(4, 2.4, 12), at(cx + 80, cy + 5, cz), Color3.fromRGB(30, 40, 55), Enum.Material.Glass)
	B.Wedge({ Name = "Tailcone", Size = Vector3.new(22, 14, 30), CFrame = at(cx - 88, cy + 2, cz) * CFrame.Angles(0, math.rad(90), 0), Color = C.Hull, Material = Enum.Material.Metal, Parent = model })
	B.Wedge({ Name = "Fin", Size = Vector3.new(1.4, 26, 26), CFrame = at(cx - 88, cy + 24, cz) * CFrame.Angles(0, math.rad(90), 0), Color = C.Livery, Material = Enum.Material.Metal, Parent = model })
	for _, side in { -1, 1 } do
		box(model, "Wing", Vector3.new(26, 1.6, 60), at(cx - 5, cy - 6, cz + side * 38) * CFrame.Angles(0, side * math.rad(-14), 0), C.Hull, Enum.Material.Metal)
		B.Cylinder({ Name = "Engine", Size = Vector3.new(16, 9, 9), CFrame = at(cx + 5, cy - 11, cz + side * 26), Color = Color3.fromRGB(205, 208, 214), Material = Enum.Material.Metal, Parent = model })
		box(model, "Stabilizer", Vector3.new(12, 1, 22), at(cx - 90, cy + 4, cz + side * 14) * CFrame.Angles(0, side * math.rad(-18), 0), C.Hull, Enum.Material.Metal)
		box(model, "Gear", Vector3.new(2, 8, 2), at(cx - 8, cy - 15, cz + side * 8), Color3.fromRGB(40, 40, 45), Enum.Material.Metal)
		B.Cylinder({ Name = "Wheel", Size = Vector3.new(3, 5, 5), CFrame = at(cx - 8, cy - 19, cz + side * 8) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(25, 25, 25), Parent = model })
	end
	box(model, "NoseGear", Vector3.new(1.6, 8, 1.6), at(cx + 62, cy - 15, cz), Color3.fromRGB(40, 40, 45), Enum.Material.Metal)
	-- window row
	for i = 0, 28 do
		for _, side in { -1, 1 } do
			box(model, "Window", Vector3.new(1.4, 1.8, 0.3), at(cx + 60 - i * 4.4, cy + 3, cz + side * 11), Color3.fromRGB(30, 40, 55), Enum.Material.Glass, { CanCollide = false })
		end
	end
	-- jet bridge from the gate
	box(model, "JetBridge", Vector3.new(10, 9, 58), at(cx + 55, 13, 78), Color3.fromRGB(190, 192, 196), Enum.Material.Metal)
	box(model, "JetBridgeLeg", Vector3.new(2, 9, 2), at(cx + 55, 4.5, 95), C.Steel, Enum.Material.Metal)
end

function LobbyBuilder.Build(parent: Instance)
	local root = B.Model("Lobby", parent)
	local points = { Kiosks = {} }

	-- ground
	box(root, "Tarmac", Vector3.new(700, 2, 500), at(0, -1.2, 260), C.Tarmac, Enum.Material.Asphalt)
	box(root, "Grass", Vector3.new(1600, 2, 1600), at(0, -1.6, 0), C.Grass, Enum.Material.Grass)
	for i = -6, 6 do
		box(root, "TaxiLine", Vector3.new(12, 0.1, 1), at(i * 30, -0.15, 170), Color3.fromRGB(240, 200, 40), nil, { CanCollide = false })
	end

	-- terminal shell (80 wide on x, 100 deep on z: back wall z=-50, glass facade z=50)
	local terminal = B.Model("Terminal", root)
	box(terminal, "Floor", Vector3.new(170, 1, 104), at(0, -0.5, 0), C.Floor, Enum.Material.Marble)
	box(terminal, "CarpetGate", Vector3.new(70, 0.08, 40), at(-45, 0.04, 20), C.Carpet, Enum.Material.Fabric, { CanCollide = false })
	box(terminal, "FloorInlay", Vector3.new(160, 0.06, 2), at(0, 0.03, -8), C.FloorAccent, nil, { CanCollide = false })
	box(terminal, "BackWall", Vector3.new(170, 26, 2), at(0, 13, -52), C.Wall, Enum.Material.Concrete)
	box(terminal, "LeftWall", Vector3.new(2, 26, 104), at(-85, 13, 0), C.Wall, Enum.Material.Concrete)
	box(terminal, "RightWall", Vector3.new(2, 26, 104), at(85, 13, 0), C.Wall, Enum.Material.Concrete)
	box(terminal, "Roof", Vector3.new(172, 2, 106), at(0, 27, 0), C.Roof, Enum.Material.Concrete)
	for i = -3, 3 do
		box(terminal, "Skylight", Vector3.new(14, 2.2, 60), at(i * 22, 27, 0), C.Glass, Enum.Material.Glass, { Transparency = 0.5, CanCollide = false })
	end
	-- glass facade
	box(terminal, "Facade", Vector3.new(170, 24, 0.6), at(0, 13, 52), C.Glass, Enum.Material.Glass, { Transparency = 0.7 })
	for i = -8, 8 do
		box(terminal, "Mullion", Vector3.new(0.8, 26, 1), at(i * 10, 13, 52), C.Steel, Enum.Material.Metal)
		box(terminal, "Column", Vector3.new(2, 26, 2), at(i * 20, 13, -20), C.Wall, Enum.Material.Concrete)
	end
	for i = -4, 4 do
		local lamp = box(terminal, "CeilingLamp", Vector3.new(10, 0.4, 3), at(i * 18, 25.6, 10), Color3.fromRGB(255, 250, 235), Enum.Material.Neon, { CanCollide = false })
		B.Light(lamp, "PointLight", { Range = 30, Brightness = 0.7, Color = Color3.fromRGB(255, 244, 225) })
	end

	-- spawn
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = at(0, 0.05, -30)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = root
	box(root, "SpawnDisc", Vector3.new(14, 0.1, 14), at(0, 0.06, -30), Color3.fromRGB(70, 150, 255), Enum.Material.Neon, { CanCollide = false, Transparency = 0.6 })
	points.Spawn = spawn

	-- departure gate
	local gate = B.Model("Gate", root)
	box(gate, "GateDesk", Vector3.new(10, 3.6, 3), at(-45, 1.8, 40), Color3.fromRGB(30, 34, 44), Enum.Material.Metal)
	box(gate, "GateDeskTop", Vector3.new(10.4, 0.3, 3.4), at(-45, 3.7, 40), C.Gold, Enum.Material.Metal)
	local gateSign = screen(gate, "GateSign", at(-45, 11, 44), Vector3.new(16, 5, 0.4), "GATE 7", "LAST FLIGHT  ·  NOW BOARDING SOON")
	points.GateSign = gateSign
	box(gate, "BoardingDoor", Vector3.new(8, 10, 0.4), at(-45, 5, 51.4), Color3.fromRGB(60, 65, 75), Enum.Material.Metal)
	box(gate, "BoardingDoorFrame", Vector3.new(9, 11, 0.3), at(-45, 5.5, 51.6), C.Gold, Enum.Material.Metal)
	for row = 0, 3 do
		gateSeats(gate, -45, 30 - row * 7, 8, 1)
	end
	points.GatePoint = B.Point("GatePoint", at(-45, 3, 46), gate)

	-- departure board (updated by LobbyService)
	local board = screen(root, "DepartureBoard", at(0, 15, -50.7), Vector3.new(44, 12, 0.4), "NEXT DEPARTURE", "--:--")
	points.DepartureBoard = board

	-- leaderboard wall
	local leaderboard = screen(root, "Leaderboard", at(-83.7, 12, -20) * CFrame.Angles(0, math.rad(-90), 0), Vector3.new(30, 16, 0.4), "TOP FLYERS", "")
	points.Leaderboard = leaderboard

	-- kiosks
	kiosk(root, points, "Shop", 30, -32, "DUTY FREE", "Cosmetics · Emotes · Effects", "OPEN SHOP", Color3.fromRGB(255, 190, 60))
	kiosk(root, points, "Wardrobe", 45, -32, "WARDROBE", "Equip your cosmetics", "CUSTOMIZE", Color3.fromRGB(200, 110, 255))
	kiosk(root, points, "Records", 15, -32, "FLIGHT RECORDS", "Stats · Achievements · Challenges", "VIEW RECORDS", Color3.fromRGB(80, 200, 255))

	-- VIP lounge (right side, glass room)
	local vip = B.Model("VIPLounge", root)
	box(vip, "LoungeFloor", Vector3.new(30, 0.1, 30), at(66, 0.06, -34), Color3.fromRGB(40, 32, 20), Enum.Material.WoodPlanks, { CanCollide = false })
	box(vip, "LoungeGlassSide", Vector3.new(30, 12, 0.5), at(66, 6, -19), C.Glass, Enum.Material.Glass, { Transparency = 0.6 })
	local vipDoor = box(vip, "VIPDoor", Vector3.new(0.6, 10, 6), at(51, 5, -24), C.Gold, Enum.Material.Glass, {
		Transparency = 0.35,
		Tags = { "VIPDoor" },
	})
	B.Sign(vipDoor, Enum.NormalId.Left, "VIP", { TextColor3 = Color3.fromRGB(40, 30, 10) })
	box(vip, "LoungeGlassFrontA", Vector3.new(0.5, 12, 24), at(51, 6, -39), C.Glass, Enum.Material.Glass, { Transparency = 0.6 })
	box(vip, "LoungeHeader", Vector3.new(0.5, 2, 6), at(51, 11, -24), C.Gold, Enum.Material.Metal)
	for i = 0, 2 do
		for j = 0, 1 do
			local cx, cz = 58 + i * 8, -44 + j * 12
			B.Seat({ Name = "LoungeChair", Size = Vector3.new(3, 1.2, 3), CFrame = at(cx, 1.2, cz), Color = Color3.fromRGB(120, 60, 30), Material = Enum.Material.Fabric, Parent = vip })
			box(vip, "ChairBack", Vector3.new(3, 3, 0.8), at(cx, 2.6, cz - 1.6), Color3.fromRGB(120, 60, 30), Enum.Material.Fabric)
		end
	end
	box(vip, "Bar", Vector3.new(3, 4, 18), at(79, 2, -34), Color3.fromRGB(50, 35, 20), Enum.Material.Wood)
	box(vip, "BarTop", Vector3.new(3.4, 0.3, 18.4), at(79, 4.1, -34), C.Gold, Enum.Material.Metal)
	local vipSign = screen(vip, "VIPSign", at(66, 14, -19.4) * CFrame.Angles(0, math.pi, 0), Vector3.new(14, 3.5, 0.3), "VIP LOUNGE", "Boarding pass holders only", C.Gold)
	B.Light(vipSign, "PointLight", { Range = 20, Brightness = 1, Color = C.Gold })
	points.VIPDoor = vipDoor

	-- decoration
	for _, pos in { { -78, -44 }, { 78, 44 }, { -78, 44 }, { 5, 44 }, { -20, -44 } } do
		plant(root, pos[1], pos[2])
	end
	box(root, "Carousel", Vector3.new(24, 2, 8), at(-45, 1, -38), Color3.fromRGB(70, 70, 76), Enum.Material.Metal)
	box(root, "CarouselBelt", Vector3.new(23, 0.2, 7), at(-45, 2.1, -38), Color3.fromRGB(30, 30, 30), Enum.Material.Rubber)
	for i = 0, 4 do
		box(root, "Suitcase", Vector3.new(2, 1.4, 3), at(-54 + i * 4.5, 2.9, -38), Color3.fromHSV(i / 5, 0.55, 0.75), Enum.Material.Plastic)
	end
	screen(root, "BaggageSign", at(-45, 9, -49) , Vector3.new(14, 3, 0.3), "BAGGAGE CLAIM", "Belt 3")

	parkedAircraft(root)

	return root, points
end

return LobbyBuilder
