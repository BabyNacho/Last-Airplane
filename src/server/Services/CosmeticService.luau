--[[
	CosmeticService
	Applies equipped character cosmetics for everyone to see: outfits, accessories, badges,
	luggage, trails and auras (built by the shared CosmeticBuilder from plain parts, so they need
	no uploaded assets) plus the overhead title tag. Also publishes Title / Theme attributes the
	client uses for chat tags and HUD accent colours. Plane cosmetics are applied on each
	client (the aircraft is shared). Nothing here changes gameplay.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CosmeticBuilder = require(ReplicatedStorage.Shared.CosmeticBuilder)
local ShopCatalog = require(ReplicatedStorage.Shared.Config.ShopCatalog)
local Registry = require(script.Parent.Parent.Registry)

local CosmeticService = {}

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
	local equipped = profile.Equipped
	local shop = Registry.ShopService
	local function valid(slot: string)
		local id = equipped[slot]
		if id and shop:Owns(player, id) then
			return ShopCatalog.Get(id)
		end
		return nil
	end
	local head = character:FindFirstChild("Head")
	if head then
		local tag = head:FindFirstChild("LF_TitleTag")
		if tag then
			tag:Destroy()
		end
	end
	local itemsBySlot = {}
	for _, slot in { "Outfit", "Hat", "Face", "Body", "Badge", "Luggage", "Trail", "Aura" } do
		itemsBySlot[slot] = valid(slot)
	end
	CosmeticBuilder.ApplyCharacter(character, itemsBySlot, function(itemId, err)
		warn("[Cosmetics] failed to build", itemId, err)
	end)
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
