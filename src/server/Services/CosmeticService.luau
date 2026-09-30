--[[
	CosmeticService
	Applies equipped cosmetics to characters: procedural accessories (built from parts so they
	need no uploaded assets), trails, and the overhead title tag. Also publishes Title / Theme
	attributes that the client uses for chat tags and HUD accent colours.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopCatalog = require(ReplicatedStorage.Shared.Config.ShopCatalog)
local Registry = require(script.Parent.Parent.Registry)

local CosmeticService = {}

local FOLDER_NAME = "LF_Cosmetics"

local function weldPart(parent: Instance, anchor: BasePart, props: { [string]: any }, offset: CFrame): BasePart
	local part: BasePart
	if props.Shape == "Ball" or props.Shape == "Cylinder" then
		local p = Instance.new("Part")
		p.Shape = if props.Shape == "Ball" then Enum.PartType.Ball else Enum.PartType.Cylinder
		part = p
	elseif props.Shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		part = Instance.new("Part")
	end
	part.Name = props.Name or "Cosmetic"
	part.Size = props.Size
	part.Color = props.Color
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.Transparency = props.Transparency or 0
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = anchor.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part
	weld.Part1 = anchor
	weld.Parent = part
	part.Parent = parent
	return part
end

-- Accessory shapes. Offsets are relative to the head (hat/face) or upper torso (body); -Z is forward.
local SHAPES = {}

SHAPES.Cap = function(folder, head, data)
	weldPart(folder, head, { Size = Vector3.new(1.25, 0.45, 1.25), Color = data.Primary, Shape = "Cylinder" }, CFrame.new(0, 0.62, 0) * CFrame.Angles(0, 0, math.rad(90)))
	weldPart(folder, head, { Size = Vector3.new(1.1, 0.08, 0.6), Color = data.Accent }, CFrame.new(0, 0.42, -0.72))
	if data.Badge then
		weldPart(folder, head, { Size = Vector3.new(0.35, 0.22, 0.05), Color = data.Accent, Material = Enum.Material.Neon }, CFrame.new(0, 0.66, -0.63))
	end
end

SHAPES.Helmet = function(folder, head, data)
	weldPart(folder, head, { Size = Vector3.new(1.35, 1.35, 1.35), Color = data.Primary, Shape = "Ball" }, CFrame.new(0, 0.38, 0.02))
	weldPart(folder, head, { Size = Vector3.new(1.5, 0.08, 1.5), Color = data.Primary, Shape = "Cylinder" }, CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.rad(90)))
	weldPart(folder, head, { Size = Vector3.new(0.2, 0.12, 1.1), Color = data.Accent }, CFrame.new(0, 1.03, 0))
end

SHAPES.Beanie = function(folder, head, data)
	weldPart(folder, head, { Size = Vector3.new(1.28, 1.1, 1.28), Color = data.Primary, Shape = "Ball" }, CFrame.new(0, 0.42, 0.02))
	weldPart(folder, head, { Size = Vector3.new(0.1, 0.35, 0.1), Color = Color3.fromRGB(40, 40, 40) }, CFrame.new(0, 1.05, 0))
	weldPart(folder, head, { Size = Vector3.new(1.3, 0.05, 0.18), Color = data.Accent }, CFrame.new(0, 1.24, 0))
	weldPart(folder, head, { Size = Vector3.new(0.18, 0.05, 1.3), Color = data.Accent }, CFrame.new(0, 1.24, 0))
end

SHAPES.Headset = function(folder, head, data)
	weldPart(folder, head, { Size = Vector3.new(0.18, 0.12, 1.4), Color = data.Primary }, CFrame.new(0, 0.66, 0) * CFrame.Angles(0, math.rad(90), 0))
	for _, x in { -0.66, 0.66 } do
		weldPart(folder, head, { Size = Vector3.new(0.2, 0.55, 0.55), Color = data.Primary, Shape = "Cylinder" }, CFrame.new(x, 0.05, 0))
	end
	weldPart(folder, head, { Size = Vector3.new(0.06, 0.06, 0.55), Color = data.Primary }, CFrame.new(0.55, -0.2, -0.35) * CFrame.Angles(0, math.rad(-35), 0))
	weldPart(folder, head, { Size = Vector3.new(0.14, 0.14, 0.14), Color = data.Accent, Shape = "Ball", Material = Enum.Material.Neon }, CFrame.new(0.38, -0.3, -0.6))
end

SHAPES.Goggles = function(folder, head, data)
	weldPart(folder, head, { Size = Vector3.new(1.3, 0.12, 1.3), Color = data.Primary, Shape = "Cylinder" }, CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)))
	for _, x in { -0.28, 0.28 } do
		weldPart(folder, head, { Size = Vector3.new(0.12, 0.38, 0.38), Color = data.Accent, Shape = "Cylinder", Material = Enum.Material.Glass, Transparency = 0.2 }, CFrame.new(x, 0.2, -0.62) * CFrame.Angles(0, math.rad(90), 0))
	end
end

SHAPES.SleepMask = function(folder, head, data)
	weldPart(folder, head, { Size = Vector3.new(1.05, 0.32, 0.1), Color = data.Primary, Material = Enum.Material.Fabric }, CFrame.new(0, 0.18, -0.6))
	weldPart(folder, head, { Size = Vector3.new(1.3, 0.08, 1.3), Color = data.Primary, Shape = "Cylinder" }, CFrame.new(0, 0.18, 0) * CFrame.Angles(0, 0, math.rad(90)))
end

SHAPES.Shades = function(folder, head, data)
	for _, x in { -0.25, 0.25 } do
		weldPart(folder, head, { Size = Vector3.new(0.38, 0.24, 0.06), Color = data.Accent, Material = Enum.Material.Glass, Transparency = 0.1 }, CFrame.new(x, 0.18, -0.61))
	end
	weldPart(folder, head, { Size = Vector3.new(0.95, 0.05, 0.05), Color = data.Primary, Material = Enum.Material.Metal }, CFrame.new(0, 0.28, -0.62))
end

SHAPES.NeckPillow = function(folder, torso, data)
	for i = 0, 6 do
		local angle = math.rad(-110 + i * 36.6)
		weldPart(folder, torso, { Size = Vector3.new(0.5, 0.5, 0.5), Color = data.Primary, Shape = "Ball", Material = Enum.Material.Fabric }, CFrame.new(math.sin(angle) * 0.62, 1.02, math.cos(angle) * 0.45))
	end
end

SHAPES.Vest = function(folder, torso, data)
	weldPart(folder, torso, { Size = Vector3.new(2.1, 1.3, 0.35), Color = data.Primary }, CFrame.new(0, 0.1, -0.55))
	weldPart(folder, torso, { Size = Vector3.new(2.1, 1.3, 0.3), Color = data.Primary }, CFrame.new(0, 0.1, 0.55))
	weldPart(folder, torso, { Size = Vector3.new(0.2, 0.2, 0.2), Color = data.Accent, Shape = "Ball" }, CFrame.new(0.4, -0.4, -0.75))
end

SHAPES.Backpack = function(folder, torso, data)
	weldPart(folder, torso, { Size = Vector3.new(1.6, 1.8, 0.8), Color = data.Primary, Material = Enum.Material.Fabric }, CFrame.new(0, 0, 0.85))
	weldPart(folder, torso, { Size = Vector3.new(0.3, 0.3, 0.2), Color = data.Accent }, CFrame.new(0.5, -0.4, -0.55))
	for _, x in { -0.55, 0.55 } do
		weldPart(folder, torso, { Size = Vector3.new(0.18, 1.9, 0.12), Color = Color3.fromRGB(40, 40, 40) }, CFrame.new(x, 0, -0.5))
	end
end

SHAPES.Jetpack = function(folder, torso, data)
	for _, x in { -0.45, 0.45 } do
		weldPart(folder, torso, { Size = Vector3.new(1.8, 0.7, 0.7), Color = data.Primary, Shape = "Cylinder", Material = Enum.Material.Metal }, CFrame.new(x, 0, 0.85) * CFrame.Angles(0, 0, math.rad(90)))
		local nozzle = weldPart(folder, torso, { Size = Vector3.new(0.4, 0.4, 0.4), Color = data.Accent, Shape = "Ball", Material = Enum.Material.Neon }, CFrame.new(x, -0.95, 0.85))
		local light = Instance.new("PointLight")
		light.Color = data.Accent
		light.Range = 5
		light.Brightness = 1.5
		light.Parent = nozzle
	end
end

local function clear(character: Model)
	local existing = character:FindFirstChild(FOLDER_NAME)
	if existing then
		existing:Destroy()
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		for _, child in root:GetChildren() do
			if child:GetAttribute("LFCosmetic") then
				child:Destroy()
			end
		end
	end
	local head = character:FindFirstChild("Head")
	if head then
		local tag = head:FindFirstChild("LF_TitleTag")
		if tag then
			tag:Destroy()
		end
	end
end

local function addTrail(character: Model, data)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailTop"
	a0.Position = Vector3.new(0, 0.8, 0.4)
	a0:SetAttribute("LFCosmetic", true)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailBottom"
	a1.Position = Vector3.new(0, -1.4, 0.4)
	a1:SetAttribute("LFCosmetic", true)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = data.Lifetime or 0.6
	trail.LightEmission = data.LightEmission or 0.2
	trail.FaceCamera = true
	trail.MinLength = 0.1
	local keypoints = {}
	local colors = data.Colors
	for i, color in colors do
		table.insert(keypoints, ColorSequenceKeypoint.new(if #colors == 1 then 0 else (i - 1) / (#colors - 1), color))
	end
	if #keypoints == 1 then
		table.insert(keypoints, ColorSequenceKeypoint.new(1, colors[1]))
	end
	trail.Color = ColorSequence.new(keypoints)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
	trail:SetAttribute("LFCosmetic", true)
	trail.Parent = root
end

local function addTitle(player: Player, character: Model, titleItem, vip: boolean)
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "LF_TitleTag"
	gui.Size = UDim2.fromOffset(220, 46)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	gui.Adornee = head
	local name = Instance.new("TextLabel")
	name.Name = "PlayerName"
	name.Size = UDim2.new(1, 0, 0.55, 0)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBold
	name.TextScaled = true
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 0.5
	name.Text = (if vip then "★ " else "") .. player.DisplayName
	name.Parent = gui
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0.42, 0)
	title.Position = UDim2.new(0, 0, 0.58, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamMedium
	title.TextScaled = true
	title.TextColor3 = titleItem and titleItem.Color or Color3.fromRGB(200, 200, 210)
	title.TextStrokeTransparency = 0.6
	title.Text = titleItem and string.upper(titleItem.Name) or ""
	title.Parent = gui
	gui.Parent = head
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
end

function CosmeticService:Apply(player: Player)
	local character = player.Character
	local profile = Registry.DataService:Get(player)
	if not character or not profile then
		return
	end
	clear(character)
	local equipped = profile.Equipped
	local shop = Registry.ShopService
	local function valid(slot: string)
		local id = equipped[slot]
		if id and shop:Owns(player, id) then
			return ShopCatalog.Get(id)
		end
		return nil
	end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = character
	local head = character:FindFirstChild("Head") :: BasePart?
	local torso = (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) :: BasePart?
	for _, slot in { "Hat", "Face", "Body" } do
		local item = valid(slot)
		if item and item.Data and SHAPES[item.Data.Shape] then
			local anchor = if slot == "Body" then torso else head
			if anchor then
				local ok, err = pcall(SHAPES[item.Data.Shape], folder, anchor, item.Data)
				if not ok then
					warn("[Cosmetics] failed to build", item.Id, err)
				end
			end
		end
	end
	local trail = valid("Trail")
	if trail then
		addTrail(character, trail.Data)
	end
	local title = valid("Title")
	local vip = Registry.MonetizationService:IsVIP(player)
	addTitle(player, character, title, vip)
	player:SetAttribute("Title", title and title.Name or nil)
	player:SetAttribute("TitleColor", title and title.Color or nil)
	local theme = valid("Theme")
	player:SetAttribute("ThemeAccent", theme and theme.Data.Accent or nil)
end

function CosmeticService:Start()
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Head", 10)
			task.wait(0.2)
			self:Apply(player)
		end)
		if player.Character then
			task.spawn(self.Apply, self, player)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Registry.DataService.ProfileLoaded:Connect(function(player)
		self:Apply(player)
	end)
end

return CosmeticService
