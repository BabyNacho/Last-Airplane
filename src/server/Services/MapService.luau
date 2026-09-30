--[[
	MapService
	Builds the lobby and aircraft at server start, exposes the gameplay point registry and
	resets the aircraft between rounds. Also owns door / bin / mask / panel state helpers.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local MapConfig = require(ReplicatedStorage.Shared.Config.MapConfig)
local Util = require(ReplicatedStorage.Shared.Util)
local AirplaneBuilder = require(script.Parent.Parent.Map.AirplaneBuilder)
local LobbyBuilder = require(script.Parent.Parent.Map.LobbyBuilder)

local MapService = {}

MapService.Points = {} :: { [string]: any }
MapService.LobbyPoints = {} :: { [string]: any }
MapService.Airplane = nil :: Model?
MapService.Lobby = nil :: Model?

local doorHomes: { [BasePart]: CFrame } = {}
local binHomes: { [BasePart]: CFrame } = {}
local maskHomes: { [BasePart]: CFrame } = {}
local cartHomes: { [BasePart]: CFrame } = {}
local luggageFolder: Folder

local STATUS_COLORS = {
	ok = Color3.fromRGB(60, 200, 90),
	warn = Color3.fromRGB(255, 180, 40),
	fail = Color3.fromRGB(255, 50, 50),
	off = Color3.fromRGB(40, 40, 40),
	info = Color3.fromRGB(70, 150, 255),
}

function MapService:Init()
	local world = Workspace:FindFirstChild("World") or Instance.new("Folder")
	world.Name = "World"
	world.Parent = Workspace

	local t0 = os.clock()
	local lobby, lobbyPoints = LobbyBuilder.Build(world)
	local airplane, points = AirplaneBuilder.Build(world)
	self.Lobby = lobby
	self.LobbyPoints = lobbyPoints
	self.Airplane = airplane
	self.Points = points

	luggageFolder = Instance.new("Folder")
	luggageFolder.Name = "LooseObjects"
	luggageFolder.Parent = airplane

	for _, door in CollectionService:GetTagged("DividerDoor") do
		local closed = door.CFrame
		if door:GetAttribute("Open") then
			closed = door.CFrame - Vector3.new(0, 0, 4.8)
		end
		doorHomes[door] = closed
	end
	for _, door in CollectionService:GetTagged("ExitDoor") do
		doorHomes[door] = door.CFrame
	end
	for _, door in CollectionService:GetTagged("LavDoor") do
		doorHomes[door] = door.CFrame
	end
	for _, lid in points.Bins do
		binHomes[lid] = lid.CFrame
	end
	for _, mask in points.MaskGroups do
		maskHomes[mask] = mask.CFrame
	end
	for _, cart in points.Carts do
		cartHomes[cart] = cart.CFrame
	end

	local count = 0
	for _, d in world:GetDescendants() do
		if d:IsA("BasePart") then
			count += 1
		end
	end
	print(string.format("[MapService] World built: %d parts in %.2fs", count, os.clock() - t0))
end

---------------------------------------------------------------- queries

function MapService:GetPoint(key: string): any
	return self.Points[key]
end

function MapService:LobbySpawnCFrame(): CFrame
	local spawn = self.LobbyPoints.Spawn
	local offset = Vector3.new(math.random(-5, 5), 3.5, math.random(-5, 5))
	return CFrame.new(spawn.Position + offset)
end

function MapService:SectionOf(player: Player): string
	local root = Util.GetRoot(player)
	if not root then
		return "None"
	end
	if not MapConfig.IsInsidePlane(root.Position) then
		return "Outside"
	end
	return MapConfig.SectionAt(MapConfig.ToLocal(root.Position).X)
end

function MapService:IsAboard(player: Player): boolean
	local root = Util.GetRoot(player)
	return root ~= nil and MapConfig.IsInsidePlane(root.Position)
end

-- Returns the airplane seat part the player is buckled into, if any.
function MapService:GetSeat(player: Player): Seat?
	local humanoid = Util.GetHumanoid(player)
	if not humanoid then
		return nil
	end
	local seat = humanoid.SeatPart
	if seat and seat:IsA("Seat") and (CollectionService:HasTag(seat, "AirplaneSeat") or CollectionService:HasTag(seat, "CockpitSeat")) then
		return seat
	end
	return nil
end

function MapService:IsSeated(player: Player): boolean
	return self:GetSeat(player) ~= nil
end

function MapService:DistanceTo(player: Player, target: BasePart | Vector3): number
	local root = Util.GetRoot(player)
	if not root then
		return math.huge
	end
	local position = if typeof(target) == "Vector3" then target else (target :: BasePart).Position
	return (root.Position - position).Magnitude
end

function MapService:PlayersNear(position: Vector3, radius: number, candidates: { Player }): { Player }
	local list = {}
	for _, player in candidates do
		local root = Util.GetRoot(player)
		if root and (root.Position - position).Magnitude <= radius then
			table.insert(list, player)
		end
	end
	return list
end

function MapService:Teleport(player: Player, cframe: CFrame)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.SeatPart then
		humanoid.Sit = false
		local weld = humanoid.SeatPart:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end
	character:PivotTo(cframe)
end

---------------------------------------------------------------- doors

local function tween(part: BasePart, cframe: CFrame, time: number?)
	TweenService:Create(part, TweenInfo.new(time or 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = cframe }):Play()
end

function MapService:SetDividerOpen(id: string, open: boolean)
	local door = self.Points.DividerDoors[id]
	if not door then
		return
	end
	door:SetAttribute("Open", open)
	local home = doorHomes[door]
	door.CanCollide = not open
	tween(door, if open then home + Vector3.new(0, 0, 4.8) else home)
end

function MapService:IsDividerOpen(id: string): boolean
	local door = self.Points.DividerDoors[id]
	return door ~= nil and door:GetAttribute("Open") == true
end

function MapService:SetDividerLocked(id: string, locked: boolean)
	local door = self.Points.DividerDoors[id]
	if door then
		door:SetAttribute("Locked", locked)
		local light = door.Parent and door.Parent:FindFirstChild("CardReaderLight")
		if light and light:IsA("BasePart") and id == "CockpitDoor" then
			light.Color = if locked then STATUS_COLORS.fail else STATUS_COLORS.ok
		end
	end
end

function MapService:SetLavDoorOpen(door: BasePart, open: boolean)
	door:SetAttribute("Open", open)
	door.CanCollide = not open
	local home = doorHomes[door]
	tween(door, if open then home * CFrame.new(-3.2, 0, 0) else home)
end

function MapService:OpenExit(exitInfo)
	local door = exitInfo.Door
	if door:GetAttribute("Open") then
		return
	end
	door:SetAttribute("Open", true)
	door.CanCollide = false
	local home = doorHomes[door]
	tween(door, home + Vector3.new(0, 0, exitInfo.Side * 3) + Vector3.new(-(door.Size.X + 0.4), 0, 0), 0.9)
end

---------------------------------------------------------------- cabin props

function MapService:SetBinOpen(lid: BasePart, open: boolean)
	lid:SetAttribute("Open", open)
	local home = binHomes[lid]
	local side = lid:GetAttribute("Side") or 1
	local hinge = home * CFrame.new(0, 1.15, 0)
	local rotated = hinge * CFrame.Angles(side * math.rad(-100), 0, 0) * CFrame.new(0, -1.15, 0)
	tween(lid, if open then rotated else home, 0.35)
	lid.CanCollide = not open
end

function MapService:DeployMasks(deployed: boolean)
	for _, mask in self.Points.MaskGroups do
		mask:SetAttribute("Deployed", deployed)
		local home = maskHomes[mask]
		if deployed then
			mask.Transparency = 0
			tween(mask, home - Vector3.new(0, 2.4, 0), 0.8)
		else
			mask.Transparency = 1
			mask.CFrame = home
		end
	end
end

function MapService:SpawnLuggage(position: Vector3, velocity: Vector3?): BasePart
	local bag = Instance.new("Part")
	bag.Name = "Luggage"
	bag.Size = Vector3.new(1.6, 1.1, 2.2)
	bag.Color = Color3.fromHSV(math.random(), 0.5, 0.6)
	bag.Material = Enum.Material.Fabric
	bag.CFrame = CFrame.new(position) * CFrame.Angles(math.random() * 3, math.random() * 3, 0)
	bag.CustomPhysicalProperties = PhysicalProperties.new(0.5, 0.6, 0.1)
	bag:SetAttribute("Loose", true)
	bag.Parent = luggageFolder
	bag:SetNetworkOwner(nil)
	if velocity then
		bag.AssemblyLinearVelocity = velocity
	end
	return bag
end

function MapService:ClearLooseObjects()
	luggageFolder:ClearAllChildren()
end

function MapService:SetCartLoose(cart: BasePart, loose: boolean)
	cart:SetAttribute("Secured", not loose)
	if loose then
		cart.Anchored = false
		cart:SetNetworkOwner(nil)
	else
		cart.Anchored = true
		cart.AssemblyLinearVelocity = Vector3.zero
		cart.CFrame = cartHomes[cart]
	end
end

function MapService:SetPanelStatus(key: string, status: string)
	local panel = self.Points[key]
	if not panel or not panel.Parent then
		return
	end
	local light = panel.Parent:FindFirstChild(key .. "Status")
	if light and light:IsA("BasePart") then
		light.Color = STATUS_COLORS[status] or STATUS_COLORS.ok
	end
	panel:SetAttribute("Status", status)
end

---------------------------------------------------------------- reset

function MapService:ResetAirplane()
	for door, home in doorHomes do
		if CollectionService:HasTag(door, "DividerDoor") then
			local id = door:GetAttribute("DoorId")
			local startsOpen = id == "FirstClassCurtain" or id == "AftCabinDoor"
			door:SetAttribute("Open", startsOpen)
			door:SetAttribute("Locked", id == "CockpitDoor")
			door.CanCollide = not startsOpen
			door.CFrame = if startsOpen then home + Vector3.new(0, 0, 4.8) else home
		else
			door:SetAttribute("Open", false)
			door.CanCollide = true
			door.CFrame = home
		end
	end
	self:SetDividerLocked("CockpitDoor", true)
	for lid, home in binHomes do
		lid:SetAttribute("Open", false)
		lid.CFrame = home
		lid.CanCollide = true
	end
	self:DeployMasks(false)
	for cart in cartHomes do
		self:SetCartLoose(cart, false)
	end
	self:ClearLooseObjects()
	for key, value in self.Points do
		if typeof(value) == "Instance" and value:IsA("BasePart") and CollectionService:HasTag(value, "InteractPanel") then
			self:SetPanelStatus(key, "ok")
		end
	end
	for _, seat in self.Points.Seats do
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end
end

return MapService
