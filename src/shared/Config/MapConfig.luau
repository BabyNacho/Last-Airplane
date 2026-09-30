--[[
	MapConfig
	World layout constants. The aircraft interior runs along the X axis with the nose at +X.
	Local airplane coordinates: y = 0 is the cabin floor surface, z = 0 is the aisle centre.
]]

local MapConfig = {}

MapConfig.LobbyOrigin = Vector3.new(0, 0, 0)
MapConfig.PlaneOrigin = Vector3.new(0, 700, 3000) -- far from the lobby so neither can see the other

MapConfig.Cabin = {
	HalfWidth = 12, -- inner half width
	Height = 12, -- ceiling height
	NoseX = 80,
	TailX = -82,
	WindowBottom = 4.5,
	WindowTop = 7,
	WindowWidth = 1.8,
	WindowPitch = 4,
}

-- Sections from nose to tail. Divider doors sit on the boundaries listed in Dividers.
MapConfig.Sections = {
	{ Id = "Cockpit", From = 64, To = 80 },
	{ Id = "FrontGalley", From = 50, To = 64 },
	{ Id = "FirstClass", From = 32, To = 50 },
	{ Id = "Economy", From = -38, To = 32 },
	{ Id = "AftGalley", From = -58, To = -38 },
	{ Id = "Service", From = -82, To = -58 },
}

MapConfig.Dividers = {
	{ Id = "CockpitDoor", X = 64, Between = { "FrontGalley", "Cockpit" }, Locked = true },
	{ Id = "FirstClassCurtain", X = 32, Between = { "FirstClass", "Economy" } },
	{ Id = "AftCabinDoor", X = -38, Between = { "Economy", "AftGalley" } },
	{ Id = "ServiceDoor", X = -58, Between = { "AftGalley", "Service" } },
}

MapConfig.Exits = {
	{ Id = "L1", X = 57, Side = -1, Width = 4 },
	{ Id = "R1", X = 57, Side = 1, Width = 4 },
	{ Id = "L2", X = -2, Side = -1, Width = 3, Overwing = true },
	{ Id = "R2", X = -2, Side = 1, Width = 3, Overwing = true },
	{ Id = "L3", X = -49, Side = -1, Width = 4 },
	{ Id = "R3", X = -49, Side = 1, Width = 4 },
}

-- Seat rows (row number, x centre, class)
MapConfig.FirstClassRows = { 46.5, 42, 37.5, 33 }
MapConfig.EconomyRows = {}
for i = 0, 6 do
	table.insert(MapConfig.EconomyRows, 29.5 - i * 4)
end
for i = 0, 7 do
	table.insert(MapConfig.EconomyRows, -8.5 - i * 4)
end

MapConfig.WingX = -2 -- wing root centre (visible from the overwing windows)

function MapConfig.SectionAt(x: number): string
	for _, section in MapConfig.Sections do
		if x >= section.From and x <= section.To then
			return section.Id
		end
	end
	return "Outside"
end

function MapConfig.ToWorld(localPos: Vector3): Vector3
	return MapConfig.PlaneOrigin + localPos
end

function MapConfig.ToLocal(worldPos: Vector3): Vector3
	return worldPos - MapConfig.PlaneOrigin
end

-- True when a world position is inside the aircraft cabin volume.
function MapConfig.IsInsidePlane(worldPos: Vector3): boolean
	local p = worldPos - MapConfig.PlaneOrigin
	local cabin = MapConfig.Cabin
	return p.X <= cabin.NoseX + 1
		and p.X >= cabin.TailX - 1
		and math.abs(p.Z) <= cabin.HalfWidth + 1.5
		and p.Y >= -4
		and p.Y <= cabin.Height + 4
end

return MapConfig
