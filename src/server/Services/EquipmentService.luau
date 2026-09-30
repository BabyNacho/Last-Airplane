--[[
	EquipmentService
	Physical emergency equipment players pick up: fire extinguishers, portable oxygen bottles,
	first aid kits, the crew keycard and the crash axe. Tools are created server-side and only
	given to conscious round participants.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Registry = require(script.Parent.Parent.Registry)

local EquipmentService = {}

local TOOL_TAG = "LastFlightTool"

local DEFINITIONS = {
	Extinguisher = {
		Name = "Fire Extinguisher",
		Tip = "Hold click / tap to spray at fires",
		Color = Color3.fromRGB(200, 30, 30),
		Size = Vector3.new(0.9, 2.2, 0.9),
		Shape = "Cylinder",
		Grip = CFrame.new(0, -0.3, 0),
	},
	OxygenBottle = {
		Name = "Portable Oxygen",
		Tip = "Click / tap to breathe (" .. GameConfig.Oxygen.PortableBottleDuration .. "s supply)",
		Color = Color3.fromRGB(60, 170, 90),
		Size = Vector3.new(0.8, 2, 0.8),
		Shape = "Cylinder",
		Grip = CFrame.new(0, -0.2, 0),
	},
	FirstAidKit = {
		Name = "First Aid Kit",
		Tip = "Treating a player with the kit heals much more",
		Color = Color3.fromRGB(240, 240, 240),
		Size = Vector3.new(1.4, 1, 0.6),
		Shape = "Block",
		Grip = CFrame.new(0, 0, 0),
	},
	Keycard = {
		Name = "Crew Keycard",
		Tip = "Opens the cockpit door",
		Color = Color3.fromRGB(70, 150, 255),
		Size = Vector3.new(0.6, 0.05, 0.9),
		Shape = "Block",
		Grip = CFrame.new(0, 0, 0),
	},
	CrashAxe = {
		Name = "Crash Axe",
		Tip = "Can force the cockpit door open",
		Color = Color3.fromRGB(220, 40, 40),
		Size = Vector3.new(0.3, 2.6, 0.9),
		Shape = "Block",
		Grip = CFrame.new(0, -0.8, 0),
	},
}

local spraying: { [Player]: boolean } = {}
local pickupHandles: { any } = {}

function EquipmentService:CreateTool(kind: string): Tool
	local def = DEFINITIONS[kind]
	local tool = Instance.new("Tool")
	tool.Name = def.Name
	tool.ToolTip = def.Tip
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("Kind", kind)
	tool.Grip = def.Grip
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = def.Size
	handle.Color = def.Color
	handle.Material = Enum.Material.SmoothPlastic
	handle.CanCollide = false
	handle.Massless = true
	if def.Shape == "Cylinder" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Cylinder
		mesh.Scale = Vector3.new(1, 1, 1)
		handle.Size = Vector3.new(def.Size.Y, def.Size.X, def.Size.Z)
		mesh.Parent = handle
		tool.Grip = def.Grip * CFrame.Angles(0, 0, math.rad(90))
	end
	handle.Parent = tool
	game:GetService("CollectionService"):AddTag(tool, TOOL_TAG)

	if kind == "Extinguisher" then
		tool:SetAttribute("Charge", GameConfig.Fire.ExtinguisherCharge)
		local nozzle = Instance.new("Attachment")
		nozzle.Name = "Nozzle"
		nozzle.Position = Vector3.new(0, 0, 0)
		nozzle.Parent = handle
		local spray = Instance.new("ParticleEmitter")
		spray.Name = "Spray"
		spray.Enabled = false
		spray.Rate = 120
		spray.Lifetime = NumberRange.new(0.5, 0.8)
		spray.Speed = NumberRange.new(26, 34)
		spray.SpreadAngle = Vector2.new(9, 9)
		spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 3.2) })
		spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		spray.Color = ColorSequence.new(Color3.fromRGB(240, 245, 255))
		spray.EmissionDirection = Enum.NormalId.Front
		spray.Parent = nozzle
		tool.Activated:Connect(function()
			local player = Players:GetPlayerFromCharacter(tool.Parent)
			if player and (tool:GetAttribute("Charge") or 0) > 0 and Registry.ConditionService:IsConscious(player) then
				spraying[player] = true
				spray.Enabled = true
			end
		end)
		local function stop()
			local player = Players:GetPlayerFromCharacter(tool.Parent)
			if player then
				spraying[player] = nil
			end
			spray.Enabled = false
		end
		tool.Deactivated:Connect(stop)
		tool.Unequipped:Connect(function()
			spray.Enabled = false
			for player in spraying do
				if not player.Character or not tool:IsDescendantOf(player.Character) then
					spraying[player] = nil
				end
			end
		end)
	elseif kind == "OxygenBottle" then
		tool:SetAttribute("Supply", GameConfig.Oxygen.PortableBottleDuration)
		tool.Activated:Connect(function()
			local player = Players:GetPlayerFromCharacter(tool.Parent)
			if player and Registry.OxygenSystem then
				Registry.OxygenSystem:ToggleBottle(player, tool)
			end
		end)
	elseif kind == "FirstAidKit" then
		tool:SetAttribute("Uses", 2)
	end
	return tool
end

-- Returns the spray direction info for a spraying player (or nil).
function EquipmentService:GetSprayer(player: Player): (Tool?, Vector3?, Vector3?)
	if not spraying[player] then
		return nil
	end
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if not tool or tool:GetAttribute("Kind") ~= "Extinguisher" then
		spraying[player] = nil
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	return tool, root.Position, root.CFrame.LookVector
end

function EquipmentService:StopSpraying(player: Player, tool: Tool?)
	spraying[player] = nil
	if tool then
		local spray = tool:FindFirstChild("Spray", true)
		if spray and spray:IsA("ParticleEmitter") then
			spray.Enabled = false
		end
	end
end

function EquipmentService:Sprayers(): { Player }
	local list = {}
	for player in spraying do
		table.insert(list, player)
	end
	return list
end

function EquipmentService:HasTool(player: Player, kind: string): Tool?
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

function EquipmentService:Give(player: Player, kind: string): Tool?
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return nil
	end
	local tool = self:CreateTool(kind)
	tool.Parent = backpack
	Registry.EffectsService:Sound("Equip", nil, player)
	return tool
end

function EquipmentService:StripTools(player: Player)
	spraying[player] = nil
	for _, container in { player.Character, player:FindFirstChildOfClass("Backpack") } do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and game:GetService("CollectionService"):HasTag(child, TOOL_TAG) then
					child:Destroy()
				end
			end
		end
	end
end

-- Registers a one-shot pickup on a map part (e.g. an extinguisher cabinet).
function EquipmentService:AddPickup(ctx, part: BasePart, kind: string, uses: number?)
	local remaining = uses or 1
	local def = DEFINITIONS[kind]
	local handle
	handle = Registry.InteractionService:Add(part, {
		Action = "TAKE",
		Object = string.upper(def.Name),
		Range = 7,
		Round = ctx,
		Condition = function(player)
			if self:HasTool(player, kind) then
				return false, "You're already carrying a " .. def.Name .. "."
			end
			return true
		end,
		OnTrigger = function(player)
			if remaining <= 0 then
				return
			end
			remaining -= 1
			self:Give(player, kind)
			Registry.EffectsService:Notify("Picked up: " .. def.Name .. " - " .. def.Tip, "info", player)
			if remaining <= 0 then
				handle:Destroy()
				part.Transparency = 0.7
			end
		end,
	})
	table.insert(pickupHandles, { Part = part })
	return handle
end

function EquipmentService:OnRoundStart(ctx)
	table.clear(spraying)
	table.clear(pickupHandles)
	local points = Registry.MapService.Points
	for _, cabinet in points.Extinguishers do
		cabinet.Transparency = 0
		self:AddPickup(ctx, cabinet, "Extinguisher", 1)
	end
	for _, bottle in points.O2Bottles do
		bottle.Transparency = 0
		self:AddPickup(ctx, bottle, "OxygenBottle", 1)
	end
	for _, kit in points.FirstAidKits do
		kit.Transparency = 0
		self:AddPickup(ctx, kit, "FirstAidKit", 1)
	end
end

function EquipmentService:OnRoundEnd(ctx)
	for _, player in ctx:Players() do
		self:StripTools(player)
	end
	for _, info in pickupHandles do
		info.Part.Transparency = 0
	end
	table.clear(spraying)
end

function EquipmentService:Start()
	Players.PlayerRemoving:Connect(function(player)
		spraying[player] = nil
	end)
	-- unconscious players drop their grip
	Registry.ConditionService.Downed:Connect(function(player)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:UnequipTools()
		end
		spraying[player] = nil
	end)
end

return EquipmentService
