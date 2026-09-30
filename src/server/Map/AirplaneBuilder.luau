--[[
	AirplaneBuilder
	Procedurally constructs the passenger aircraft interior section by section and returns a
	registry of gameplay points (panels, seats, exits, fire cells...) used by the game systems.
	Every section is its own function so new cabin layouts can be added later.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage.Shared.Config.MapConfig)
local B = require(script.Parent.BuildUtil)

local AirplaneBuilder = {}

local O = MapConfig.PlaneOrigin
local HW = MapConfig.Cabin.HalfWidth
local H = MapConfig.Cabin.Height

local C = {
	Wall = Color3.fromRGB(232, 229, 220),
	WallLower = Color3.fromRGB(205, 203, 196),
	Floor = Color3.fromRGB(58, 64, 86),
	Aisle = Color3.fromRGB(96, 52, 60),
	Ceiling = Color3.fromRGB(240, 238, 232),
	SeatEconomy = Color3.fromRGB(38, 62, 120),
	SeatFirst = Color3.fromRGB(110, 34, 44),
	Headrest = Color3.fromRGB(210, 214, 222),
	Metal = Color3.fromRGB(150, 155, 162),
	Dark = Color3.fromRGB(38, 41, 48),
	Galley = Color3.fromRGB(196, 198, 204),
	Glass = Color3.fromRGB(170, 205, 230),
	Red = Color3.fromRGB(200, 40, 40),
	Yellow = Color3.fromRGB(255, 200, 30),
	Service = Color3.fromRGB(120, 124, 130),
	Hull = Color3.fromRGB(235, 238, 242),
	Engine = Color3.fromRGB(200, 204, 210),
	Screen = Color3.fromRGB(20, 40, 70),
	Emergency = Color3.fromRGB(60, 20, 20),
	Light = Color3.fromRGB(255, 246, 225),
}

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(O + Vector3.new(x, y, z))
end

local function facing(x: number, y: number, z: number, direction: Vector3): CFrame
	local p = O + Vector3.new(x, y, z)
	return CFrame.lookAt(p, p + direction)
end

export type Points = { [string]: any }

---------------------------------------------------------------------------- shared pieces

local function box(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, extra: { [string]: any }?)
	local props = {
		Name = name,
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Parent = parent,
	}
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return B.Part(props)
end

local function floorAndCeiling(model: Instance, x1: number, x2: number, aisle: boolean, floorColor: Color3?)
	local length = x2 - x1
	local cx = (x1 + x2) / 2
	box(model, "Floor", Vector3.new(length, 1, HW * 2 + 2), at(cx, -0.5, 0), floorColor or C.Floor, Enum.Material.Fabric)
	if aisle then
		box(model, "AisleCarpet", Vector3.new(length, 0.06, 4.6), at(cx, 0.03, 0), C.Aisle, Enum.Material.Fabric, { CanCollide = false })
	end
	box(model, "Ceiling", Vector3.new(length, 1, HW * 2 + 2), at(cx, H + 0.5, 0), C.Ceiling)
	-- Outer skin above the ceiling so light doesn't leak in from the sky.
	box(model, "Skin", Vector3.new(length, 0.5, HW * 2 + 4), at(cx, H + 1.5, 0), C.Hull, nil, { CanCollide = false, CastShadow = false })
end

local function emergencyStrip(model: Instance, x1: number, x2: number)
	for _, z in { -2.55, 2.55 } do
		box(model, "EmergencyStrip", Vector3.new(x2 - x1 - 0.4, 0.08, 0.18), at((x1 + x2) / 2, 0.07, z), C.Emergency, Enum.Material.Neon, {
			CanCollide = false,
			CanQuery = false,
			Tags = { "EmergencyLight" },
		})
	end
end

local function cabinLights(model: Instance, x1: number, x2: number, spacing: number?)
	local length = x2 - x1
	for _, z in { -5.2, 5.2 } do
		box(model, "LightStrip", Vector3.new(length - 0.5, 0.15, 0.5), at((x1 + x2) / 2, H - 0.05, z), C.Light, Enum.Material.Neon, {
			CanCollide = false,
			CanQuery = false,
			Tags = { "CabinLight" },
		})
	end
	local step = spacing or 10
	local x = x2 - step / 2
	while x > x1 do
		local source = B.Point("LightSource", at(x, H - 1, 0), model)
		B.Tag(source, "CabinLightSource")
		B.Light(source, "PointLight", { Range = 18, Brightness = 0.85, Color = C.Light })
		x -= step
	end
end

-- Builds one side wall between x1 and x2. `gaps` are door openings {x, width, bottom, top}.
local function wall(model: Instance, points: Points, side: number, x1: number, x2: number, windows: boolean, gaps: { any }?, color: Color3?)
	local z = side * (HW + 0.5)
	local wallColor = color or C.Wall
	local segments = { { x1, x2 } }
	for _, gap in gaps or {} do
		local nextSegments = {}
		for _, seg in segments do
			local a, b = seg[1], seg[2]
			local g1, g2 = gap.x - gap.width / 2, gap.x + gap.width / 2
			if g2 <= a or g1 >= b then
				table.insert(nextSegments, seg)
			else
				if g1 > a then
					table.insert(nextSegments, { a, g1 })
				end
				if g2 < b then
					table.insert(nextSegments, { g2, b })
				end
			end
		end
		segments = nextSegments
	end

	local wb, wt = MapConfig.Cabin.WindowBottom, MapConfig.Cabin.WindowTop
	local ww, pitch = MapConfig.Cabin.WindowWidth, MapConfig.Cabin.WindowPitch

	for _, seg in segments do
		local a, b = seg[1], seg[2]
		local length = b - a
		if length < 0.05 then
			continue
		end
		local cx = (a + b) / 2
		if not windows or length < ww + 1 then
			box(model, "Wall", Vector3.new(length, H, 1), at(cx, H / 2, z), wallColor)
			continue
		end
		box(model, "WallLower", Vector3.new(length, wb, 1), at(cx, wb / 2, z), C.WallLower)
		box(model, "WallUpper", Vector3.new(length, H - wt, 1), at(cx, (wt + H) / 2, z), wallColor)
		-- windows from the forward end backwards
		local positions = {}
		local wx = b - pitch / 2
		while wx - ww / 2 >= a + 0.4 do
			table.insert(positions, wx)
			wx -= pitch
		end
		local cursor = b
		for _, px in positions do
			local pillarLength = cursor - (px + ww / 2)
			if pillarLength > 0.01 then
				box(model, "Pillar", Vector3.new(pillarLength, wt - wb, 1), at(cursor - pillarLength / 2, (wb + wt) / 2, z), wallColor)
			end
			local glass = box(model, "Window", Vector3.new(ww, wt - wb, 0.3), at(px, (wb + wt) / 2, z + side * 0.2), C.Glass, Enum.Material.Glass, {
				Transparency = 0.55,
				CanCollide = true,
				Tags = { "CabinWindow" },
				Attributes = { Side = side, LocalX = px },
			})
			table.insert(if side < 0 then points.WindowsLeft else points.WindowsRight, glass)
			cursor = px - ww / 2
		end
		local tail = cursor - a
		if tail > 0.01 then
			box(model, "Pillar", Vector3.new(tail, wt - wb, 1), at(a + tail / 2, (wb + wt) / 2, z), wallColor)
		end
	end
end

local function sign(parent: Instance, name: string, cframe: CFrame, size: Vector3, text: string, bg: Color3, fg: Color3?, face: Enum.NormalId?)
	local part = box(parent, name, size, cframe, bg, Enum.Material.SmoothPlastic, { CanCollide = false })
	B.Sign(part, face or Enum.NormalId.Front, text, { TextColor3 = fg or Color3.new(1, 1, 1) })
	return part
end

---------------------------------------------------------------------------- seats

local rowLetters = {
	Economy = { "A", "B", "C", "D", "E", "F" },
	First = { "A", "C", "D", "F" },
}

local function buildSeat(parent: Instance, points: Points, x: number, z: number, width: number, color: Color3, label: string, class: string, row: number)
	local model = B.Model("Seat_" .. label, parent)
	local base = facing(x, 0, z, Vector3.xAxis)
	box(model, "Frame", Vector3.new(width - 0.7, 1.1, 1.3), base * CFrame.new(0, 0.55, 0), C.Dark)
	local seat = B.Seat({
		Name = "Cushion",
		Size = Vector3.new(width - 0.2, 0.7, 2.1),
		CFrame = base * CFrame.new(0, 1.45, 0),
		Color = color,
		Material = Enum.Material.Fabric,
		Parent = model,
		Tags = { "AirplaneSeat" },
		Attributes = { SeatLabel = label, Class = class, Row = row },
	})
	box(model, "Back", Vector3.new(width - 0.2, 3.5, 0.5), base * CFrame.new(0, 3.35, 1.2) * CFrame.Angles(math.rad(-7), 0, 0), color, Enum.Material.Fabric)
	box(model, "Headrest", Vector3.new(width - 0.7, 0.8, 0.55), base * CFrame.new(0, 5.2, 1.4) * CFrame.Angles(math.rad(-7), 0, 0), C.Headrest, Enum.Material.Fabric)
	box(model, "Tray", Vector3.new(width - 0.8, 1.3, 0.08), base * CFrame.new(0, 3.6, 1.5) * CFrame.Angles(math.rad(-7), 0, 0), C.Metal, nil, { CanCollide = false })
	box(model, "Armrest", Vector3.new(0.25, 0.3, 1.8), base * CFrame.new(-(width / 2) + 0.12, 2.35, 0.1), C.Dark)
	table.insert(points.Seats, seat)
	return seat
end

local function buildBinsAndMasks(model: Instance, points: Points, rows: { number }, pitch: number, maskZ: { number })
	for rowIndex, x in rows do
		for _, side in { -1, 1 } do
			box(model, "Bin", Vector3.new(pitch - 0.1, 2.5, 5.8), at(x, 10.35, side * (HW - 2.9)), C.Ceiling)
			local lid = box(model, "BinLid", Vector3.new(pitch - 0.25, 2.3, 0.2), at(x, 10.35, side * 6.05), C.Wall, nil, {
				Tags = { "OverheadBin" },
				Attributes = { Open = false, Side = side, Row = rowIndex },
			})
			table.insert(points.Bins, lid)
			-- oxygen mask drop panel (hidden until deployed)
			local mask = B.Part({
				Name = "MaskGroup",
				Size = Vector3.new(1.4, 0.3, 1.4),
				CFrame = at(x - 0.6, 8.95, side * maskZ[1]),
				Color = C.Yellow,
				Material = Enum.Material.SmoothPlastic,
				Transparency = 1,
				CanCollide = false,
				CanQuery = true,
				Parent = model,
				Tags = { "MaskGroup" },
				Attributes = { Deployed = false, Side = side, Row = rowIndex },
			})
			table.insert(points.MaskGroups, mask)
		end
	end
end

---------------------------------------------------------------------------- doors & exits

local function exitDoor(model: Instance, points: Points, exitDef)
	local side = exitDef.Side
	local overwing = exitDef.Overwing == true
	local bottom = if overwing then 1.2 else 0
	local top = if overwing then 6.8 else 8.8
	local z = side * (HW + 0.35)
	local door = box(model, "Exit_" .. exitDef.Id, Vector3.new(exitDef.Width - 0.2, top - bottom, 0.5), at(exitDef.X, (bottom + top) / 2, z), C.Galley, nil, {
		Tags = { "ExitDoor" },
		Attributes = { ExitId = exitDef.Id, Side = side, Open = false, Overwing = overwing },
	})
	box(model, "DoorHandle", Vector3.new(1.4, 0.3, 0.3), at(exitDef.X, (bottom + top) / 2, z - side * 0.35), C.Red, nil, { CanCollide = false })
	if bottom > 0 then
		box(model, "DoorSill", Vector3.new(exitDef.Width, bottom, 1), at(exitDef.X, bottom / 2, side * (HW + 0.5)), C.WallLower)
	end
	box(model, "DoorHeader", Vector3.new(exitDef.Width, H - top, 1), at(exitDef.X, (top + H) / 2, side * (HW + 0.5)), C.Wall)
	sign(model, "ExitSign", at(exitDef.X, top + 0.7, side * (HW - 0.05)) * CFrame.Angles(0, if side < 0 then 0 else math.pi, 0), Vector3.new(2.2, 0.7, 0.1), "EXIT", C.Red)
	local outside = B.Point("ExitOutside_" .. exitDef.Id, at(exitDef.X, bottom + 2, side * (HW + 4)), model)
	local inside = B.Point("ExitInside_" .. exitDef.Id, at(exitDef.X, bottom + 3, side * (HW - 2)), model, Vector3.new(exitDef.Width, 6, 3))
	table.insert(points.Exits, {
		Id = exitDef.Id,
		Door = door,
		Outside = outside,
		Inside = inside,
		Side = side,
		X = exitDef.X,
		Overwing = overwing,
	})
	return { x = exitDef.X, width = exitDef.Width }
end

local function divider(model: Instance, points: Points, def, color: Color3?)
	local x = def.X
	local doorwayHalf = 2.5
	local sideWidth = HW - doorwayHalf
	for _, side in { -1, 1 } do
		box(model, "Bulkhead", Vector3.new(0.8, H, sideWidth), at(x, H / 2, side * (doorwayHalf + sideWidth / 2)), color or C.Wall)
	end
	box(model, "BulkheadHeader", Vector3.new(0.8, H - 8.4, doorwayHalf * 2), at(x, (8.4 + H) / 2, 0), color or C.Wall)
	local door = box(model, def.Id, Vector3.new(0.35, 8.4, doorwayHalf * 2), at(x + 0.6, 4.2, 0), if def.Locked then C.Galley else C.WallLower, nil, {
		Tags = { "DividerDoor" },
		Attributes = { DoorId = def.Id, Open = not def.Locked and def.Id ~= "ServiceDoor", Locked = def.Locked == true, ClosedZ = 0 },
	})
	if door:GetAttribute("Open") then
		door.CFrame = door.CFrame + Vector3.new(0, 0, doorwayHalf * 2 - 0.2)
		door.CanCollide = false
	end
	points.DividerDoors[def.Id] = door
	return door
end

---------------------------------------------------------------------------- panels

local function panel(model: Instance, points: Points, key: string, label: string, x: number, y: number, z: number, faceDir: Vector3, size: Vector3?, color: Color3?)
	local panelSize = size or Vector3.new(4, 4.5, 0.8)
	local cf = facing(x, y, z, faceDir)
	local part = box(model, key, panelSize, cf, color or C.Dark, Enum.Material.Metal, {
		Tags = { "InteractPanel" },
		Attributes = { PanelKey = key },
	})
	local screen = box(model, key .. "Screen", Vector3.new(panelSize.X - 0.6, 1.2, 0.1), cf * CFrame.new(0, panelSize.Y / 2 - 0.9, -panelSize.Z / 2 - 0.05), C.Screen, Enum.Material.Neon, {
		CanCollide = false,
		Tags = { "PanelScreen" },
	})
	B.Sign(screen, Enum.NormalId.Front, label, { TextColor3 = Color3.fromRGB(140, 220, 255), Font = Enum.Font.RobotoMono })
	local status = box(model, key .. "Status", Vector3.new(0.5, 0.5, 0.12), cf * CFrame.new(panelSize.X / 2 - 0.6, -panelSize.Y / 2 + 0.7, -panelSize.Z / 2 - 0.05), Color3.fromRGB(60, 200, 90), Enum.Material.Neon, {
		CanCollide = false,
	})
	part:SetAttribute("StatusLight", status.Name)
	-- switch rows for visual detail
	for i = 1, 3 do
		box(model, "Switch", Vector3.new(0.3, 0.5, 0.18), cf * CFrame.new(-panelSize.X / 2 + 0.7 + (i - 1) * 0.7, -0.2, -panelSize.Z / 2 - 0.08), C.Metal, nil, { CanCollide = false })
	end
	points[key] = part
	return part
end

local function wallItem(model: Instance, name: string, x: number, z: number, y: number, size: Vector3, color: Color3, tag: string, list: { any }, attributes: { [string]: any }?)
	local part = box(model, name, size, at(x, y, z), color, nil, {
		Tags = { tag },
		Attributes = attributes,
		CanCollide = false,
	})
	table.insert(list, part)
	return part
end

---------------------------------------------------------------------------- sections

local function buildCockpit(root: Instance, points: Points)
	local model = B.Model("Cockpit", root)
	floorAndCeiling(model, 64, 80, false, C.Dark)
	wall(model, points, -1, 64, 80, false, nil, C.Galley)
	wall(model, points, 1, 64, 80, false, nil, C.Galley)
	-- nose taper
	for _, side in { -1, 1 } do
		B.Wedge({
			Name = "NoseTaper",
			Size = Vector3.new(1, H, 8),
			CFrame = at(76, H / 2, side * (HW - 4)) * CFrame.Angles(0, if side < 0 then math.rad(-90) else math.rad(90), 0),
			Color = C.Galley,
			Parent = model,
		})
	end
	-- front wall with windshield
	box(model, "NoseLower", Vector3.new(1, 5.5, HW * 2), at(80.5, 2.75, 0), C.Galley)
	box(model, "NoseUpper", Vector3.new(1, 1.5, HW * 2), at(80.5, H - 0.75, 0), C.Galley)
	box(model, "Windshield", Vector3.new(0.4, H - 7, 18), at(80.3, 5.5 + (H - 7) / 2, 0), C.Glass, Enum.Material.Glass, {
		Transparency = 0.5,
		Tags = { "Windshield" },
	})
	for _, side in { -1, 1 } do
		box(model, "NoseSide", Vector3.new(1, H - 7, 3), at(80.5, 5.5 + (H - 7) / 2, side * (HW - 1.5)), C.Galley)
	end
	-- instrument panel & glareshield
	box(model, "InstrumentPanel", Vector3.new(2.5, 3.2, 17), at(78, 4.2, 0), C.Dark, Enum.Material.Metal)
	for i, z in { -6.5, -3, 3, 6.5 } do
		local screen = box(model, "Display" .. i, Vector3.new(0.1, 2, 2.8), at(76.7, 4.4, z), C.Screen, Enum.Material.Neon, {
			CanCollide = false,
			Tags = { "CockpitScreen" },
		})
		B.Sign(screen, Enum.NormalId.Back, if i <= 2 then "PFD" else "ND", { TextColor3 = Color3.fromRGB(80, 255, 140), Font = Enum.Font.RobotoMono })
	end
	box(model, "Glareshield", Vector3.new(2, 0.6, 17), at(77.6, 6.1, 0), C.Dark)
	box(model, "Overhead", Vector3.new(6, 0.8, 8), at(75, H - 0.6, 0), C.Dark, Enum.Material.Metal)
	box(model, "Pedestal", Vector3.new(4.5, 2.4, 2.4), at(74, 1.2, 0), C.Dark, Enum.Material.Metal)

	-- pilot seats
	for _, z in { -3.4, 3.4 } do
		local seat = B.Seat({
			Name = if z < 0 then "PilotSeat" else "CopilotSeat",
			Size = Vector3.new(2.4, 0.8, 2.4),
			CFrame = facing(73, 1.6, z, Vector3.xAxis),
			Color = Color3.fromRGB(50, 50, 55),
			Material = Enum.Material.Fabric,
			Parent = model,
			Tags = { "CockpitSeat" },
		})
		box(model, "PilotSeatBack", Vector3.new(2.4, 3.8, 0.6), facing(73, 1.6, z, Vector3.xAxis) * CFrame.new(0, 2.2, 1.3), Color3.fromRGB(50, 50, 55), Enum.Material.Fabric)
		box(model, "Yoke", Vector3.new(0.4, 1.2, 1.6), at(75.6, 3.6, z), C.Metal)
		points[seat.Name] = seat
	end

	-- controls (interaction anchors)
	panel(model, points, "Autopilot", "AUTOPILOT", 77.4, 6.9, 0, -Vector3.xAxis, Vector3.new(4, 0.9, 0.5))
	panel(model, points, "GearLever", "GEAR", 76.6, 4.6, 8.4, -Vector3.xAxis, Vector3.new(1.4, 2, 0.5))
	panel(model, points, "NavPanel", "NAV", 76.6, 4.6, -8.4, -Vector3.xAxis, Vector3.new(1.4, 2, 0.5))
	panel(model, points, "Radio", "RADIO / ATC", 74, 2.7, 0, Vector3.yAxis, Vector3.new(1.8, 1.6, 0.4))
	panel(model, points, "FireHandles", "ENG FIRE", 75, H - 1.1, 0, -Vector3.yAxis, Vector3.new(3, 1.2, 0.3), C.Red)
	panel(model, points, "Throttle", "THRUST", 75.8, 2.8, 0, Vector3.xAxis, Vector3.new(1.5, 1.2, 0.4))

	points.InspectCockpit = B.Point("InspectCockpit", at(78.5, 7, 4), model)
	cabinLights(model, 64, 80, 16)
	points.CockpitCenter = B.Point("CockpitCenter", at(72, 3, 0), model)
end

local function buildFrontGalley(root: Instance, points: Points)
	local model = B.Model("FrontGalley", root)
	floorAndCeiling(model, 50, 64, true)
	local gaps = {}
	for _, def in MapConfig.Exits do
		if def.X == 57 then
			table.insert(gaps, exitDoor(model, points, def))
		end
	end
	wall(model, points, -1, 50, 64, false, gaps)
	wall(model, points, 1, 50, 64, false, gaps)
	emergencyStrip(model, 50, 64)
	cabinLights(model, 50, 64, 7)

	-- galley counters
	for _, side in { -1, 1 } do
		box(model, "GalleyCounter", Vector3.new(3.4, 3.6, 5), at(61.7, 1.8, side * (HW - 2.5)), C.Galley, Enum.Material.Metal)
		box(model, "GalleyUpper", Vector3.new(3.4, 3.2, 4), at(61.7, 8.6, side * (HW - 2)), C.Galley, Enum.Material.Metal)
		for i = 0, 1 do
			box(model, "Oven", Vector3.new(0.1, 1.2, 1.6), at(59.95, 2.2, side * (HW - 1.5 - i * 2)), C.Dark, Enum.Material.Glass, { CanCollide = false })
		end
		box(model, "GalleyCounter2", Vector3.new(3, 3.6, 4), at(51.6, 1.8, side * (HW - 2)), C.Galley, Enum.Material.Metal)
	end
	box(model, "JumpSeat", Vector3.new(0.6, 1.8, 2), at(59.4, 3, -5.4), C.Dark)

	-- cockpit bulkhead + door
	local cockpitDoor = divider(model, points, MapConfig.Dividers[1], C.Galley)
	points.CockpitDoor = cockpitDoor
	local reader = box(model, "CardReader", Vector3.new(0.3, 0.9, 0.6), at(63.4, 4.5, 3.2), C.Dark, Enum.Material.Metal)
	box(model, "CardReaderLight", Vector3.new(0.1, 0.2, 0.2), at(63.2, 4.8, 3.2), C.Red, Enum.Material.Neon, { CanCollide = false, Name = "CardReaderLight" })
	points.CardReader = reader

	-- safety equipment
	wallItem(model, "Extinguisher", 60.2, -HW + 0.6, 5.8, Vector3.new(0.8, 1.8, 0.6), C.Red, "ExtinguisherCabinet", points.Extinguishers)
	wallItem(model, "OxygenBottle", 60.2, HW - 0.6, 5.8, Vector3.new(0.8, 1.6, 0.6), Color3.fromRGB(60, 170, 90), "OxygenBottle", points.O2Bottles)
	wallItem(model, "FirstAidKit", 52, HW - 0.7, 6.5, Vector3.new(1.4, 1, 0.6), Color3.fromRGB(240, 240, 240), "FirstAidKit", points.FirstAidKits)

	-- manual gear crank floor hatch
	local hatch = box(model, "GearCrank", Vector3.new(2.4, 0.12, 2.4), at(53, 0.06, 0), Color3.fromRGB(80, 80, 85), Enum.Material.DiamondPlate, {
		CanCollide = false,
		Attributes = { PanelKey = "GearCrank" },
	})
	points.GearCrank = hatch

	table.insert(points.KeycardSpots, B.Point("Keycard_GalleyDrawer", at(61.7, 3.9, -HW + 3), model))
	table.insert(points.FASpots, B.Point("FA_Front", at(58, 3, 0), model))
	sign(model, "GalleySign", at(63.35, 10.5, -6), Vector3.new(0.1, 1, 4), "FORWARD GALLEY", C.Dark, nil, Enum.NormalId.Back)
end

local function buildFirstClass(root: Instance, points: Points)
	local model = B.Model("FirstClass", root)
	floorAndCeiling(model, 32, 50, true)
	wall(model, points, -1, 32, 50, true)
	wall(model, points, 1, 32, 50, true)
	emergencyStrip(model, 32, 50)
	cabinLights(model, 32, 50)
	buildBinsAndMasks(model, points, MapConfig.FirstClassRows, 4.5, { 6.2 })
	for rowIndex, x in MapConfig.FirstClassRows do
		local letters = rowLetters.First
		for i, z in { -8.3, -4.0, 4.0, 8.3 } do
			buildSeat(model, points, x, z, 3.2, C.SeatFirst, rowIndex .. letters[i], "First", rowIndex)
		end
	end
	wallItem(model, "OxygenBottle", 49.2, -HW + 0.6, 6, Vector3.new(0.8, 1.6, 0.6), Color3.fromRGB(60, 170, 90), "OxygenBottle", points.O2Bottles)
	table.insert(points.KeycardSpots, B.Point("Keycard_SeatPocket", at(46.5, 2.6, -8.3), model))
	divider(model, points, MapConfig.Dividers[2], Color3.fromRGB(80, 30, 40))
	sign(model, "ClassSign", at(49.6, 10.5, 0), Vector3.new(0.1, 1, 5), "FIRST CLASS", Color3.fromRGB(80, 30, 40), Color3.fromRGB(255, 220, 150), Enum.NormalId.Back)
end

local function rowNumberFor(index: number): number
	-- rows 5.. (first class uses 1-4); row 13 is skipped like real airlines
	local number = index + 4
	if number >= 13 then
		number += 1
	end
	return number
end

local function buildEconomy(root: Instance, points: Points)
	local model = B.Model("Economy", root)
	floorAndCeiling(model, -38, 32, true)
	local gaps = {}
	for _, def in MapConfig.Exits do
		if def.Overwing then
			table.insert(gaps, exitDoor(model, points, def))
		end
	end
	wall(model, points, -1, -38, 32, true, gaps)
	wall(model, points, 1, -38, 32, true, gaps)
	emergencyStrip(model, -38, 32)
	cabinLights(model, -38, 32)
	buildBinsAndMasks(model, points, MapConfig.EconomyRows, 4, { 5.8 })
	local letters = rowLetters.Economy
	for rowIndex, x in MapConfig.EconomyRows do
		local rowNumber = rowNumberFor(rowIndex)
		for i, z in { -8.0, -5.8, -3.6, 3.6, 5.8, 8.0 } do
			buildSeat(model, points, x, z, 2.15, C.SeatEconomy, rowNumber .. letters[i], "Economy", rowNumber)
		end
	end
	-- mid-cabin safety equipment
	wallItem(model, "Extinguisher", -6.5, HW - 0.6, 2.2, Vector3.new(0.8, 1.8, 0.6), C.Red, "ExtinguisherCabinet", points.Extinguishers)
	points.InspectLeft = B.Point("InspectLeft", at(1.5, 5.5, -HW + 1), model)
	points.InspectRight = B.Point("InspectRight", at(1.5, 5.5, HW - 1), model)
	-- seatbelt signs
	for _, x in { 28, 8, -20 } do
		local part = sign(model, "SeatbeltSign", at(x, H - 0.2, 0) * CFrame.Angles(math.rad(90), 0, 0), Vector3.new(2.2, 0.8, 0.1), "FASTEN SEATBELT", C.Dark, Color3.fromRGB(90, 90, 90), Enum.NormalId.Back)
		B.Tag(part, "SeatbeltSign")
	end
	points.CabinCenter = B.Point("CabinCenter", at(0, 3, 0), model)
end

local function buildAftGalley(root: Instance, points: Points)
	local model = B.Model("AftGalley", root)
	floorAndCeiling(model, -58, -38, true)
	local gaps = {}
	for _, def in MapConfig.Exits do
		if def.X == -49 then
			table.insert(gaps, exitDoor(model, points, def))
		end
	end
	wall(model, points, -1, -58, -38, false, gaps)
	wall(model, points, 1, -58, -38, false, gaps)
	emergencyStrip(model, -58, -38)
	cabinLights(model, -58, -38, 8)
	divider(model, points, MapConfig.Dividers[3])

	-- lavatories
	for _, side in { -1, 1 } do
		local id = if side < 0 then "L" else "R"
		local zInner = side * 6
		local zOuter = side * HW
		local zMid = (zInner + zOuter) / 2
		box(model, "LavWallBack", Vector3.new(0.5, H, HW - 6), at(-45, H / 2, zMid), C.Wall)
		box(model, "LavWallFront", Vector3.new(0.5, H, HW - 6), at(-39.2, H / 2, zMid), C.Wall)
		box(model, "LavWallSide", Vector3.new(5.8, H - 8, 0.5), at(-42.1, 8 + (H - 8) / 2, zInner), C.Wall)
		box(model, "LavWallSide2", Vector3.new(1.4, 8, 0.5), at(-44.1, 4, zInner), C.Wall)
		box(model, "LavWallSide3", Vector3.new(1, 8, 0.5), at(-39.7, 4, zInner), C.Wall)
		local door = box(model, "LavDoor_" .. id, Vector3.new(3.4, 8, 0.3), at(-41.7, 4, zInner + side * 0.1), C.WallLower, nil, {
			Tags = { "LavDoor" },
			Attributes = { Open = false, LavId = id },
		})
		sign(model, "LavSign", at(-41.7, 8.6, zInner - side * 0.2) * CFrame.Angles(0, if side < 0 then 0 else math.pi, 0), Vector3.new(2, 0.6, 0.1), "LAVATORY", C.Dark, Color3.fromRGB(120, 255, 140))
		box(model, "Toilet", Vector3.new(1.6, 1.8, 1.4), at(-43.8, 0.9, zOuter - side * 2.2), Color3.fromRGB(245, 245, 248))
		box(model, "Sink", Vector3.new(1.2, 0.5, 2), at(-39.9, 3, zOuter - side * 2.5), Color3.fromRGB(245, 245, 248))
		box(model, "Mirror", Vector3.new(0.1, 2, 2), at(-39.5, 5.5, zOuter - side * 2.5), C.Glass, Enum.Material.Glass, { CanCollide = false, Reflectance = 0.4 })
		points.Lavatories[id] = { Door = door, Center = B.Point("Lav_" .. id, at(-42, 3, zMid), model) }
	end
	table.insert(points.KeycardSpots, B.Point("Keycard_Lavatory", at(-40, 3.4, -HW + 3), model))

	-- galley counters & carts
	for _, side in { -1, 1 } do
		box(model, "AftCounter", Vector3.new(4, 3.6, 5), at(-55.8, 1.8, side * (HW - 2.5)), C.Galley, Enum.Material.Metal)
		box(model, "AftUpper", Vector3.new(4, 3, 4), at(-55.8, 8.8, side * (HW - 2)), C.Galley, Enum.Material.Metal)
		local cart = box(model, "GalleyCart", Vector3.new(1.8, 3.4, 1.4), at(-53, 1.7, side * 4.4), C.Metal, Enum.Material.Metal, {
			Tags = { "GalleyCart" },
			Attributes = { HomeX = -53, HomeZ = side * 4.4, Secured = true },
		})
		table.insert(points.Carts, cart)
	end
	wallItem(model, "Extinguisher", -54, HW - 0.6, 6.5, Vector3.new(0.8, 1.8, 0.6), C.Red, "ExtinguisherCabinet", points.Extinguishers)
	wallItem(model, "OxygenBottle", -54, -HW + 0.6, 6.5, Vector3.new(0.8, 1.6, 0.6), Color3.fromRGB(60, 170, 90), "OxygenBottle", points.O2Bottles)
	wallItem(model, "FirstAidKit", -52, -HW + 0.7, 7.6, Vector3.new(1.4, 1, 0.6), Color3.fromRGB(240, 240, 240), "FirstAidKit", points.FirstAidKits)
	table.insert(points.KeycardSpots, B.Point("Keycard_JumpSeat", at(-51, 2.6, HW - 4), model))
	table.insert(points.FASpots, B.Point("FA_Aft", at(-50, 3, 0), model))
	divider(model, points, MapConfig.Dividers[4], C.Service)
	sign(model, "CrewOnly", at(-57.5, 9.6, 0), Vector3.new(0.1, 0.8, 4.4), "CREW ONLY", C.Red, nil, Enum.NormalId.Back)
end

local function buildService(root: Instance, points: Points)
	local model = B.Model("ServiceBay", root)
	floorAndCeiling(model, -82, -58, false, Color3.fromRGB(70, 72, 78))
	wall(model, points, -1, -82, -58, false, nil, C.Service)
	wall(model, points, 1, -82, -58, false, nil, C.Service)
	box(model, "TailWall", Vector3.new(1, H, HW * 2 + 2), at(-82.5, H / 2, 0), C.Service)
	emergencyStrip(model, -82, -58)
	cabinLights(model, -82, -58, 12)
	-- floor grating look
	box(model, "Grating", Vector3.new(23, 0.06, 5), at(-70, 0.03, 0), Color3.fromRGB(95, 98, 104), Enum.Material.DiamondPlate, { CanCollide = false })

	panel(model, points, "ElectricalPanel", "ELECTRICAL", -63, 4.5, -HW + 0.4, Vector3.zAxis, Vector3.new(5, 5, 0.8))
	panel(model, points, "EnginePanel", "ENGINE / APU", -63, 4.5, HW - 0.4, -Vector3.zAxis, Vector3.new(5, 5, 0.8))
	panel(model, points, "OutflowValve", "PRESSURIZATION", -71, 4.5, -HW + 0.4, Vector3.zAxis, Vector3.new(4, 4, 0.8))
	panel(model, points, "Avionics", "AVIONICS BAY", -81.4, 4.5, -4, Vector3.xAxis, Vector3.new(5, 6, 1.2))

	points.HydraulicValves = {}
	for i, x in { -68.5, -73, -77.5 } do
		local valve = box(model, "HydraulicValve" .. i, Vector3.new(1.6, 2.6, 0.8), at(x, 3.4, HW - 0.5), Color3.fromRGB(180, 120, 40), Enum.Material.Metal, {
			Attributes = { PanelKey = "HydraulicValve" .. i, ValveIndex = i },
		})
		B.Cylinder({
			Name = "ValveWheel",
			Size = Vector3.new(0.3, 1.8, 1.8),
			CFrame = at(x, 3.8, HW - 1) * CFrame.Angles(0, math.rad(90), 0),
			Color = C.Red,
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = model,
		})
		box(model, "Pipe", Vector3.new(0.5, H - 5, 0.5), at(x, 5 + (H - 5) / 2, HW - 0.4), C.Metal, Enum.Material.Metal, { CanCollide = false })
		table.insert(points.HydraulicValves, valve)
	end

	points.CrashAxe = box(model, "CrashAxe", Vector3.new(0.3, 2.4, 0.9), at(-60, 5, -HW + 0.5), C.Red, Enum.Material.Metal, {
		CanCollide = false,
		Attributes = { PanelKey = "CrashAxe" },
	})
	wallItem(model, "Extinguisher", -60, HW - 0.6, 2.2, Vector3.new(0.8, 1.8, 0.6), C.Red, "ExtinguisherCabinet", points.Extinguishers)

	-- crew rest bunks
	for i = 0, 1 do
		box(model, "Bunk", Vector3.new(6.5, 0.8, 3.2), at(-78, 1.6 + i * 4, -HW + 2), Color3.fromRGB(70, 80, 110), Enum.Material.Fabric)
	end
	box(model, "BunkCurtain", Vector3.new(6.5, 8, 0.2), at(-78, 4, -HW + 3.8), Color3.fromRGB(40, 45, 70), Enum.Material.Fabric, {
		CanCollide = false,
		Transparency = 0.2,
	})
	points.CrewRest = B.Point("CrewRest", at(-78, 3, -HW + 5), model)
	points.CrewRestBunks = { at(-78, 2.6, -HW + 2), at(-78, 6.6, -HW + 2) }

	-- cargo
	for i, pos in { Vector3.new(-76, 1.5, 6), Vector3.new(-79.5, 1.5, 6.5), Vector3.new(-77.5, 4.5, 6.2), Vector3.new(-70, 1.2, 8) } do
		box(model, "Crate" .. i, Vector3.new(3, 3, 3), at(pos.X, pos.Y, pos.Z), Color3.fromRGB(150, 110, 60), Enum.Material.WoodPlanks)
	end
	sign(model, "ServiceSign", at(-58.6, 9.6, 0), Vector3.new(0.1, 0.8, 4.4), "SERVICE / AVIONICS", C.Dark, Color3.fromRGB(255, 200, 60))
end

local function buildExterior(root: Instance, points: Points)
	local model = B.Model("Exterior", root)
	for _, side in { -1, 1 } do
		box(model, "Wing", Vector3.new(15, 1.2, 48), at(MapConfig.WingX - 1, -2.4, side * (HW + 25)) * CFrame.Angles(0, side * math.rad(-12), 0), C.Hull, Enum.Material.Metal, {
			CanCollide = false,
			CanQuery = false,
			CastShadow = true,
		})
		box(model, "WingTipLight", Vector3.new(1, 1, 0.5), at(MapConfig.WingX - 6, -2, side * (HW + 49)), if side < 0 then Color3.fromRGB(255, 40, 40) else Color3.fromRGB(40, 255, 80), Enum.Material.Neon, {
			CanCollide = false,
			Tags = { "WingLight" },
		})
		box(model, "Winglet", Vector3.new(4, 6, 0.6), at(MapConfig.WingX - 8, 0.5, side * (HW + 49.5)), C.Hull, Enum.Material.Metal, { CanCollide = false })
		local engine = B.Cylinder({
			Name = if side < 0 then "EngineL" else "EngineR",
			Size = Vector3.new(12, 6, 6),
			CFrame = at(MapConfig.WingX + 5, -7, side * (HW + 14)),
			Color = C.Engine,
			Material = Enum.Material.Metal,
			CanCollide = false,
			CanQuery = false,
			CastShadow = true,
			Parent = model,
			Tags = { "Engine" },
			Attributes = { Side = side },
		})
		B.Cylinder({
			Name = "Intake",
			Size = Vector3.new(0.4, 5.2, 5.2),
			CFrame = at(MapConfig.WingX + 11.1, -7, side * (HW + 14)),
			Color = Color3.fromRGB(30, 30, 35),
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = model,
		})
		box(model, "Pylon", Vector3.new(8, 3, 0.8), at(MapConfig.WingX + 3, -4, side * (HW + 14)), C.Hull, Enum.Material.Metal, { CanCollide = false })
		local exhaust = B.Point("Exhaust", at(MapConfig.WingX - 1.5, -7, side * (HW + 14)), model)
		exhaust.Name = engine.Name .. "Exhaust"
		points[engine.Name] = engine
		points[engine.Name .. "Exhaust"] = exhaust
	end
	-- lower fuselage visible below the windows
	box(model, "Belly", Vector3.new(170, 2, HW * 2 + 3), at(-1, -2, 0), C.Hull, Enum.Material.Metal, { CanCollide = false, CanQuery = false })
end

---------------------------------------------------------------------------- fire cells & spawns

local function buildFireCells(root: Instance, points: Points)
	local folder = B.Folder("FireCells", root)
	local index = 0
	local x = 70
	while x > -80 do
		for _, z in { -6, 6 } do
			local section = MapConfig.SectionAt(x)
			if section ~= "Outside" and not (section == "Cockpit" and z > 0) then
				index += 1
				local cell = B.Point("FireCell" .. index, at(x, 0.6, if section == "Cockpit" then 0 else z), folder, Vector3.new(5, 1, 5))
				cell:SetAttribute("Section", section)
				cell:SetAttribute("Index", index)
				table.insert(points.FireCells, cell)
			end
		end
		x -= 7
	end
end

local function buildSpawns(root: Instance, points: Points)
	local folder = B.Folder("BoardingSpawns", root)
	local x = 48
	while x >= -34 do
		table.insert(points.BoardingSpawns, B.Point("Spawn", at(x, 3, 0), folder))
		x -= 3
	end
end

---------------------------------------------------------------------------- entry

function AirplaneBuilder.Build(parent: Instance): (Model, Points)
	local root = B.Model("Airplane", parent)
	local points: Points = {
		Seats = {},
		Bins = {},
		MaskGroups = {},
		Exits = {},
		DividerDoors = {},
		Extinguishers = {},
		O2Bottles = {},
		FirstAidKits = {},
		KeycardSpots = {},
		FASpots = {},
		Carts = {},
		FireCells = {},
		BoardingSpawns = {},
		WindowsLeft = {},
		WindowsRight = {},
		Lavatories = {},
	}
	buildCockpit(root, points)
	buildFrontGalley(root, points)
	buildFirstClass(root, points)
	buildEconomy(root, points)
	buildAftGalley(root, points)
	buildService(root, points)
	buildExterior(root, points)
	buildFireCells(root, points)
	buildSpawns(root, points)
	root.WorldPivot = at(0, 0, 0)
	return root, points
end

return AirplaneBuilder
