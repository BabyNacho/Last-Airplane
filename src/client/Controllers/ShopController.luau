--[[
	ShopController - the "Sky Shop"
	A colourful, card-based cosmetics store:
	  * FEATURED home page (always-on highlights, today's picks, starter picks, bundles)
	  * category tabs: Flight Gear, Outfits, Emotes, Plane, Effects, Bundles, Passes & Credits
	  * every category laid out cheapest -> premium, with rarity, price and clear buttons
	  * PREVIEW sheet with a live 3D preview (your avatar / a mini aircraft) or animated effect
	  * MY LOADOUT page to equip owned cosmetics for your character, effects and plane
	  * purchase / equip celebrations and a short first-visit intro

	Purchases stay server-authoritative and use the official Roblox flows only:
	  * Flight Credit items -> ShopPurchase remote (validated on the server)
	  * Robux items / credit packs -> MarketplaceService:PromptProductPurchase
	  * game passes -> MarketplaceService:PromptGamePassPurchase
	Robux products whose id isn't configured show "COMING SOON" instead of a purchase button.
	No timers, no fake discounts, no pop-ups: the store never pressures anyone to buy.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AchievementConfig = require(ReplicatedStorage.Shared.Config.AchievementConfig)
local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local MonetizationConfig = require(ReplicatedStorage.Shared.Config.MonetizationConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local ShopCatalog = require(ReplicatedStorage.Shared.Config.ShopCatalog)
local Util = require(ReplicatedStorage.Shared.Util)
local ClientState = require(script.Parent.Parent.ClientState)
local StoreArt = require(script.Parent.Parent.UI.StoreArt)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local ShopController = {}

local player = Players.LocalPlayer
local C = UIKit.Colors
local F = UIKit.Fonts
local ROBUX_GREEN = Color3.fromRGB(70, 210, 120)
local CARD_BG = Color3.fromRGB(26, 31, 44)
local CONFIRM_WINDOW = 3 -- seconds a "TAP TO CONFIRM" button stays armed

local overlay: Frame
local content: Frame
local tabBar: ScrollingFrame
local body: ScrollingFrame
local creditsLabel: TextLabel
local sheet: Frame
local fxLayer: Frame
local toastLabel: TextLabel
local intro: Frame
local tabs: { [string]: TextButton } = {}

local page = "Featured"
local state: any = { Owned = {}, Equipped = {}, Credits = 0, Availability = { Products = {}, Passes = {} }, Passes = {}, Flags = {}, Day = 0 }
local ultraGradients: { UIGradient } = {}
local ultraConnection: RBXScriptConnection? = nil
local previewCleanup: (() -> ())? = nil
local sheetItem: any = nil
local pendingEquip: { Slot: string, Id: string }? = nil
local armed: { [string]: number } = {}
local introShownThisSession = false
local lastWidth = 0
local animateCards = true -- pop cards in when a page opens, not on every small refresh

local PAGES = { "Featured" }
for _, name in ShopCatalog.Categories do
	table.insert(PAGES, name)
end
table.insert(PAGES, "Loadout")

---------------------------------------------------------------- sizing (readable on phones)

-- Design-space size that renders at least `minPx` real pixels after the UI scale.
local function S(design: number, minPx: number?): number
	local scale = UIKit.Scale()
	return math.max(design, (minPx or 0) / math.max(scale, 0.01))
end

local function contentWidth(): number
	local scale = math.max(UIKit.Scale(), 0.01)
	local absolute = content and content.AbsoluteSize
	local width = if typeof(absolute) == "Vector2" then absolute.X / scale else 0
	if width < 100 then
		-- not laid out yet: estimate from the viewport
		width = UIKit.ViewportSize().X * 0.94 / scale - 40
	end
	return math.min(width, 1140)
end

local function columns(minCard: number): (number, number)
	local width = contentWidth() - 14
	local gap = 12
	local count = math.max(2, math.floor((width + gap) / (minCard + gap)))
	local cardWidth = math.floor((width - gap * (count - 1)) / count)
	return count, cardWidth
end

---------------------------------------------------------------- ownership & prices

local function owns(id: string): boolean
	return table.find(state.Owned, id) ~= nil
end

local function isEquipped(item): boolean
	if not item.Slot then
		return false
	end
	local equipped = state.Equipped[item.Slot] or (if ShopCatalog.SlotInfo[item.Slot] and ShopCatalog.SlotInfo[item.Slot].Required then ShopCatalog.DefaultEquipped[item.Slot] else nil)
	return equipped == item.Id
end

local function productId(key: string?): number?
	return key and state.Availability.Products[key] or nil
end

local function passId(key: string?): number?
	return key and state.Availability.Passes[key] or nil
end

local function robuxPrice(item): number?
	if item.Product and MonetizationConfig.Products[item.Product] then
		return MonetizationConfig.Products[item.Product].PriceHint
	end
	if item.PassKey then
		return MonetizationConfig.GamePasses[item.PassKey].PriceHint
	end
	if item.ProductKey then
		return MonetizationConfig.Products[item.ProductKey].PriceHint
	end
	return nil
end

-- How the item is bought, for the price pill: kind is "FC" | "R$" | "OWNED" | "FREE" | "INFO".
local function priceInfo(item): (string, string)
	if item.Type == "Pass" then
		if state.Passes[item.PassKey] then
			return "OWNED", "OWNED ✔"
		end
		return "R$", "R$ " .. MonetizationConfig.GamePasses[item.PassKey].PriceHint
	elseif item.Type == "Credits" then
		return "R$", "R$ " .. MonetizationConfig.Products[item.ProductKey].PriceHint
	end
	if owns(item.Id) then
		return "OWNED", if isEquipped(item) then "EQUIPPED" else "OWNED ✔"
	end
	if item.Default then
		return "FREE", "FREE"
	end
	if item.Price then
		return "FC", "✈ " .. Util.FormatNumber(item.Price)
	end
	if item.Product and not item.Exclusive then
		return "R$", "R$ " .. MonetizationConfig.Products[item.Product].PriceHint
	end
	if item.Pass and not item.Product then
		return "INFO", "VIP PASS"
	end
	if item.Unlock then
		return "INFO", "🏆 EARN IT"
	end
	local bundles = ShopCatalog.BundlesContaining[item.Id]
	if bundles then
		local bundle = ShopCatalog.Get(bundles[1])
		return "INFO", "IN " .. string.upper(bundle and bundle.Name or "A BUNDLE")
	end
	return "INFO", "EXCLUSIVE"
end

local function tierOf(item): string?
	return ShopCatalog.TierOf(item, robuxPrice(item))
end

local function sortValue(item): number
	if item.Price then
		return item.Price
	end
	local robux = robuxPrice(item)
	if robux then
		return 2000 + robux * 10
	end
	return 100000 + ShopCatalog.RarityRank(item.Rarity) * 100 + (item.Order or 0)
end

---------------------------------------------------------------- feedback

local function toast(text: string, color: Color3?)
	toastLabel.Text = text
	toastLabel.TextColor3 = color or C.Text
	toastLabel.Visible = true
	local scale = toastLabel:FindFirstChildOfClass("UIScale") :: UIScale
	scale.Scale = 0.7
	UIKit.Tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	local stamp = os.clock()
	toastLabel:SetAttribute("Stamp", stamp)
	task.delay(2.4, function()
		if toastLabel:GetAttribute("Stamp") == stamp then
			toastLabel.Visible = false
		end
	end)
end

local function pop(target: GuiObject)
	local scale = target:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = UIKit.new("UIScale", { Parent = target })
	end
	(scale :: UIScale).Scale = 0.85
	UIKit.Tween(scale :: UIScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
end

local refresh: () -> ()
local openSheet: (any) -> ()
local openPage: (string) -> ()
local celebrate: (any, string) -> ()

---------------------------------------------------------------- actions

local function equip(item)
	if not item.Slot then
		return
	end
	pendingEquip = { Slot = item.Slot, Id = item.Id }
	Net.Event("Equip"):FireServer(item.Slot, item.Id)
end

local function unequip(slot: string)
	Net.Event("Equip"):FireServer(slot, nil)
end

-- Returns (label, style, handler?) for the main action button of an item. A nil handler means
-- the button is a status display, never a button that silently does nothing.
local function primaryAction(item): (string, string, (() -> ())?)
	if item.Type == "Pass" then
		if state.Passes[item.PassKey] then
			return "OWNED ✔", "owned", nil
		end
		local id = passId(item.PassKey)
		if id then
			return "BUY  R$ " .. robuxPrice(item), "robux", function()
				MarketplaceService:PromptGamePassPurchase(player, id)
			end
		end
		return "COMING SOON", "disabled", nil
	elseif item.Type == "Credits" then
		local id = productId(item.ProductKey)
		if id then
			return "BUY  R$ " .. robuxPrice(item), "robux", function()
				MarketplaceService:PromptProductPurchase(player, id)
			end
		end
		return "COMING SOON", "disabled", nil
	end
	if owns(item.Id) then
		if item.Slot then
			if isEquipped(item) then
				return "EQUIPPED ✔", "owned", nil
			end
			return "EQUIP", "equip", function()
				equip(item)
			end
		end
		return "OWNED ✔", "owned", nil
	end
	if item.Price then
		local credits = state.Credits or 0
		if credits < item.Price then
			return "NEED ✈ " .. Util.FormatNumber(item.Price - credits) .. " MORE", "disabled", function()
				toast("Earn Flight Credits by surviving flights, finishing objectives and helping others!", C.Credits)
			end
		end
		if armed[item.Id] and os.clock() - armed[item.Id] < CONFIRM_WINDOW then
			return "TAP TO CONFIRM", "confirm", function()
				armed[item.Id] = nil
				Net.Event("ShopPurchase"):FireServer(item.Id)
			end
		end
		return "BUY  ✈ " .. Util.FormatNumber(item.Price), "credits", function()
			armed[item.Id] = os.clock()
			refresh()
			task.delay(CONFIRM_WINDOW + 0.05, function()
				if armed[item.Id] and os.clock() - armed[item.Id] >= CONFIRM_WINDOW then
					armed[item.Id] = nil
					if overlay.Visible then
						refresh()
					end
				end
			end)
		end
	end
	if item.Product and not item.Exclusive then
		local id = productId(item.Product)
		if id then
			return "BUY  R$ " .. robuxPrice(item), "robux", function()
				MarketplaceService:PromptProductPurchase(player, id)
			end
		end
		return "COMING SOON", "disabled", nil
	end
	if item.Pass and not item.Product then
		local id = passId(item.Pass)
		if id then
			return "GET " .. string.upper(MonetizationConfig.GamePasses[item.Pass].Name), "robux", function()
				MarketplaceService:PromptGamePassPurchase(player, id)
			end
		end
		return "WITH " .. string.upper(MonetizationConfig.GamePasses[item.Pass].Name), "disabled", nil
	end
	if item.Unlock then
		return "🏆 EARN IT", "disabled", function()
			local achievement = AchievementConfig.ById[item.Unlock]
			toast("Unlock by earning \"" .. (achievement and achievement.Name or item.Unlock) .. "\"", C.Optional)
		end
	end
	local bundles = ShopCatalog.BundlesContaining[item.Id]
	if bundles then
		return "SEE BUNDLE", "secondary", function()
			local bundle = ShopCatalog.Get(bundles[1])
			if bundle then
				openSheet(bundle)
			end
		end
	end
	return "EXCLUSIVE", "disabled", nil
end

local BUTTON_COLORS = {
	credits = C.Credits,
	confirm = Color3.fromRGB(255, 140, 60),
	robux = ROBUX_GREEN,
	equip = Color3.fromRGB(80, 150, 255),
	owned = Color3.fromRGB(45, 120, 80),
	secondary = C.PanelLight,
	disabled = Color3.fromRGB(48, 54, 70),
}

local function actionButton(parent: Instance, item, size: UDim2, position: UDim2?, z: number): GuiObject
	local label, style, handler = primaryAction(item)
	local textSize = S(16, 12)
	if not handler then
		return UIKit.new("TextLabel", {
			Name = "Action",
			Text = label,
			Font = F.Bold,
			TextSize = textSize,
			TextScaled = false,
			TextWrapped = true,
			TextColor3 = if style == "owned" then Color3.fromRGB(190, 255, 210) else C.SubText,
			BackgroundColor3 = BUTTON_COLORS[style] or BUTTON_COLORS.disabled,
			BackgroundTransparency = 0,
			Size = size,
			Position = position,
			Corner = 12,
			ZIndex = z,
			Parent = parent,
		})
	end
	local button = UIKit.Button({
		Name = "Action",
		Text = label,
		Style = "secondary",
		BackgroundColor3 = BUTTON_COLORS[style] or BUTTON_COLORS.secondary,
		TextColor3 = if style == "credits" then Color3.fromRGB(45, 32, 8) elseif style == "disabled" then C.SubText else C.Text,
		TextSize = textSize,
		TextWrapped = true,
		Size = size,
		Position = position,
		ZIndex = z,
		Parent = parent,
		OnClick = handler,
	})
	if style == "confirm" then
		pop(button)
	end
	return button
end

---------------------------------------------------------------- cards

local function chip(parent: Instance, text: string, color: Color3, anchor: Vector2, position: UDim2, z: number, dark: boolean?): TextLabel
	return UIKit.new("TextLabel", {
		Text = text,
		Font = F.Heading,
		TextSize = S(11, 10),
		TextColor3 = if dark then Color3.fromRGB(30, 25, 10) else Color3.new(1, 1, 1),
		BackgroundColor3 = color,
		BackgroundTransparency = 0,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, S(20, 15)),
		AnchorPoint = anchor,
		Position = position,
		Corner = UDim.new(1, 0),
		Padding = { 0, 8, 0, 8 },
		ZIndex = z,
		Parent = parent,
	})
end

local function gradientOf(colors: { Color3 }): ColorSequence
	local keypoints = {}
	for i, color in colors do
		table.insert(keypoints, ColorSequenceKeypoint.new((i - 1) / math.max(1, #colors - 1), color))
	end
	return ColorSequence.new(keypoints)
end

local function rarityStroke(target: GuiObject, rarity: string, thickness: number)
	local stroke = UIKit.new("UIStroke", {
		Color = if rarity == "Ultra" then Color3.new(1, 1, 1) else ShopCatalog.Rarities[rarity] or C.Stroke,
		Thickness = thickness,
		Transparency = if rarity == "Common" then 0.5 else 0.1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = target,
	})
	if rarity == "Ultra" then
		local gradient = UIKit.new("UIGradient", { Color = gradientOf(ShopCatalog.UltraGradient), Parent = stroke })
		table.insert(ultraGradients, gradient)
	end
	return stroke
end

local function statusChip(item): (string?, Color3?, boolean?)
	local kind, text = priceInfo(item)
	if kind == "OWNED" then
		return if text == "EQUIPPED" then "EQUIPPED" else "OWNED ✔", if text == "EQUIPPED" then Color3.fromRGB(80, 150, 255) else Color3.fromRGB(50, 170, 100), false
	end
	if table.find(ShopCatalog.Featured, item.Id) then
		return "🔥 FEATURED", Color3.fromRGB(255, 110, 70), false
	end
	if item.Exclusive then
		return "EXCLUSIVE", Color3.fromRGB(150, 90, 230), false
	end
	if kind == "R$" then
		return "ROBUX", ROBUX_GREEN, false
	end
	return nil
end

-- One store card. `big` cards (featured) get a taller illustration.
local function card(parent: Instance, item, width: number, height: number, order: number, big: boolean?)
	local z = 24
	local rarity = item.Rarity or "Common"
	local rarityColor = ShopCatalog.Rarities[rarity] or C.Stroke
	local frameButton = UIKit.new("TextButton", {
		Name = item.Id,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = CARD_BG,
		Size = UDim2.fromOffset(width, height),
		Corner = 16,
		LayoutOrder = order,
		ZIndex = z,
		Parent = parent,
	})
	UIKit.new("UIGradient", {
		Color = ColorSequence.new(rarityColor:Lerp(CARD_BG, 0.72), CARD_BG),
		Rotation = 90,
		Parent = frameButton,
	})
	rarityStroke(frameButton, rarity, if big then 3 else 2)
	local scale = UIKit.new("UIScale", { Scale = if animateCards then 0.92 else 1, Parent = frameButton })
	if animateCards then
		task.delay(math.min(order * 0.018, 0.3), function()
			UIKit.Tween(scale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
		end)
	end
	frameButton.MouseEnter:Connect(function()
		UIKit.Tween(scale, 0.12, { Scale = 1.03 })
	end)
	frameButton.MouseLeave:Connect(function()
		UIKit.Tween(scale, 0.12, { Scale = 1 })
	end)
	frameButton.Activated:Connect(function()
		openSheet(item)
	end)

	local pad = 10
	local artHeight = math.floor(width * (if big then 0.7 else 0.6))
	local artHolder = UIKit.new("Frame", {
		Name = "ArtHolder",
		Size = UDim2.new(1, -pad * 2, 0, artHeight),
		Position = UDim2.fromOffset(pad, pad),
		BackgroundTransparency = 1,
		ZIndex = z + 1,
		Parent = frameButton,
	})
	StoreArt.Art(item, artHolder, z + 1)
	chip(artHolder, string.upper(rarity), rarityColor, Vector2.new(0, 0), UDim2.fromOffset(6, 6), z + 6, rarity == "Legendary" or rarity == "Common")
	local statusText, statusColor = statusChip(item)
	if statusText then
		chip(artHolder, statusText, statusColor :: Color3, Vector2.new(1, 0), UDim2.new(1, -6, 0, 6), z + 6)
	end

	local y = pad + artHeight + 6
	local nameSize = S(if big then 20 else 17, 13)
	UIKit.Text({
		Text = item.Name,
		Font = F.Heading,
		TextSize = nameSize,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		Position = UDim2.fromOffset(pad + 2, y),
		Size = UDim2.new(1, -pad * 2, 0, nameSize + 4),
		ZIndex = z + 2,
		Parent = frameButton,
	})
	y += nameSize + 6
	local descSize = S(13, 11)
	UIKit.Text({
		Text = item.Description or "",
		TextSize = descSize,
		TextColor3 = C.SubText,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(pad + 2, y),
		Size = UDim2.new(1, -pad * 2, 0, math.ceil(descSize * 2.5)),
		ZIndex = z + 2,
		Parent = frameButton,
	})
	-- buttons: PREVIEW + the main action, always at the bottom of the card
	local buttonHeight = UIKit.TouchSize(S(42, 30))
	local by = height - pad - buttonHeight
	local kind, priceText = priceInfo(item)
	local priceColor = if kind == "FC" then C.Credits elseif kind == "R$" then ROBUX_GREEN elseif kind == "OWNED" then C.Good else C.SubText
	UIKit.Text({
		Name = "Price",
		Text = priceText,
		Font = F.Heading,
		TextSize = S(16, 12),
		TextColor3 = priceColor,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(pad + 2, by - S(22, 16) - 4),
		Size = UDim2.new(1, -pad * 2, 0, S(22, 16)),
		ZIndex = z + 2,
		Parent = frameButton,
	})
	UIKit.Button({
		Name = "Preview",
		Text = "👁 PREVIEW",
		Style = "secondary",
		TextSize = S(13, 11),
		Size = UDim2.new(0.42, -pad, 0, buttonHeight),
		Position = UDim2.fromOffset(pad, by),
		ZIndex = z + 3,
		Parent = frameButton,
		OnClick = function()
			openSheet(item)
		end,
	})
	actionButton(frameButton, item, UDim2.new(0.58, -pad, 0, buttonHeight), UDim2.new(0.42, 4, 0, by), z + 3)
	return frameButton
end

local function cardHeight(width: number, big: boolean?): number
	local artHeight = math.floor(width * (if big then 0.7 else 0.6))
	local nameSize = S(if big then 20 else 17, 13)
	local descSize = S(13, 11)
	local buttonHeight = UIKit.TouchSize(S(42, 30))
	return 10 + artHeight + 6 + nameSize + 6 + math.ceil(descSize * 2.5) + 6 + S(22, 16) + 4 + buttonHeight + 10
end

---------------------------------------------------------------- page building blocks

local function clearBody()
	for _, child in body:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(ultraGradients)
end

local function header(text: string, hint: string?, order: number, color: Color3?)
	local holder = UIKit.new("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, S(34, 22)),
		LayoutOrder = order,
		ZIndex = 23,
		Parent = body,
	})
	UIKit.List(holder, 12, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	UIKit.new("Frame", { Size = UDim2.new(0, 6, 0.8, 0), BackgroundColor3 = color or C.Accent, Corner = 3, LayoutOrder = 1, ZIndex = 23, Parent = holder })
	UIKit.Text({
		Text = text,
		Font = F.Heading,
		TextSize = S(22, 15),
		TextWrapped = false,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		LayoutOrder = 2,
		ZIndex = 23,
		Parent = holder,
	})
	if hint then
		UIKit.Text({
			Text = hint,
			TextSize = S(14, 11),
			TextColor3 = C.SubText,
			TextWrapped = false,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			LayoutOrder = 3,
			ZIndex = 23,
			Parent = holder,
		})
	end
	return holder
end

local function grid(items: { any }, order: number, big: boolean?)
	local minCard = if big then S(250, 190) else S(200, 150)
	local count, width = columns(minCard)
	if big and #items < count then
		count = math.max(#items, 2)
		width = math.min(math.floor((contentWidth() - 14 - 12 * (count - 1)) / count), S(330, 240))
	end
	local height = cardHeight(width, big)
	local holder = UIKit.new("Frame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		ZIndex = 23,
		Parent = body,
	})
	UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(width, height),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = holder,
	})
	UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 6), Parent = holder })
	for index, item in items do
		card(holder, item, width, height, index, big)
	end
	return holder
end

local function note(text: string, order: number, color: Color3?)
	return UIKit.Text({
		Text = text,
		TextSize = S(14, 11),
		TextColor3 = color or C.SubText,
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		ZIndex = 23,
		Parent = body,
	})
end

local function storeItemsIn(category: string): { any }
	local list = {}
	for _, item in ShopCatalog.Items do
		if item.Category == category then
			table.insert(list, item)
		end
	end
	table.sort(list, function(a, b)
		local va, vb = sortValue(a), sortValue(b)
		if va == vb then
			return (a.Order or 0) < (b.Order or 0)
		end
		return va < vb
	end)
	return list
end

---------------------------------------------------------------- pages

local function renderFeatured()
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local featured = {}
	for _, id in ShopCatalog.Featured do
		local item = ShopCatalog.Get(id)
		if item then
			table.insert(featured, item)
		end
	end
	header("🔥 FEATURED", "Hand-picked looks", nextOrder(), Color3.fromRGB(255, 110, 70))
	grid(featured, nextOrder(), true)

	local picks = {}
	for _, id in ShopCatalog.DailyPicks(state.Day or 0) do
		local item = ShopCatalog.Get(id)
		if item then
			table.insert(picks, item)
		end
	end
	header("📅 TODAY'S PICKS", "New picks every day · everything stays in its category", nextOrder(), Color3.fromRGB(90, 200, 255))
	grid(picks, nextOrder())

	local starters = {}
	for _, item in ShopCatalog.Items do
		if item.Price and item.Price <= ShopCatalog.PriceTiers[1].MaxCredits and item.Type ~= "Bundle" and not owns(item.Id) then
			table.insert(starters, item)
		end
	end
	table.sort(starters, function(a, b)
		return a.Price < b.Price
	end)
	while #starters > 8 do
		table.remove(starters)
	end
	if #starters > 0 then
		header("⭐ STARTER PICKS", "Great first buys under ✈ " .. ShopCatalog.PriceTiers[1].MaxCredits, nextOrder(), C.Credits)
		grid(starters, nextOrder())
	end

	header("🎁 BUNDLES", "See exactly what's inside", nextOrder(), Color3.fromRGB(90, 230, 140))
	grid(storeItemsIn("Bundles"), nextOrder())
	note("✈ Flight Credits are earned by playing: survive flights, finish objectives, rescue teammates and help passengers. Every item with a ✈ price can be earned for free. Everything here is cosmetic - nothing changes your chances of surviving.", nextOrder())
end

local TIER_HEADERS = {
	Starter = { "⭐ STARTER PICKS", "Great first buys", C.Credits },
	Mid = { "🚀 MID-RANGE", "Stand out on the flight", Color3.fromRGB(90, 200, 255) },
	Premium = { "💎 PREMIUM", "Show-stoppers", Color3.fromRGB(200, 120, 255) },
	Exclusive = { "🎁 BUNDLE & PASS EXCLUSIVES", "Only inside bundles or passes", Color3.fromRGB(150, 90, 230) },
	Unlock = { "🏆 EARN IT", "Unlocked by achievements", C.Optional },
	Free = { "✔ INCLUDED FREE", "Everyone has these", C.Good },
}

local function renderCategory(category: string)
	local groups = { Starter = {}, Mid = {}, Premium = {}, Exclusive = {}, Unlock = {}, Free = {} }
	for _, item in storeItemsIn(category) do
		local tier = tierOf(item) or "Free"
		table.insert(groups[tier], item)
	end
	local order = 0
	local info = ShopCatalog.CategoryInfo[category]
	if category == "Plane" then
		order += 1
		note("🛩️ Plane cosmetics are visual only: they change how the aircraft looks on your screen and never change flight, disasters, health or landing.", order, Color3.fromRGB(150, 220, 255))
	elseif category == "Bundles" then
		order += 1
		note("Each bundle lists everything inside. When every item is also sold on its own, you'll see what they cost separately.", order)
	end
	for _, tier in { "Starter", "Mid", "Premium", "Exclusive", "Unlock", "Free" } do
		local list = groups[tier]
		if #list > 0 then
			local h = TIER_HEADERS[tier]
			order += 1
			header(h[1], h[2], order, h[3] or info.Color)
			order += 1
			grid(list, order)
		end
	end
end

local function renderPremium()
	local passes = {}
	for key, pass in MonetizationConfig.GamePasses do
		table.insert(passes, {
			Id = "Pass_" .. key,
			PassKey = key,
			Name = pass.Name,
			Type = "Pass",
			Rarity = "Legendary",
			Description = pass.Description,
			Color = Color3.fromRGB(255, 200, 60),
			Icon = if key == "VIP" then "👑" else "💃",
		})
	end
	table.sort(passes, function(a, b)
		return a.Id < b.Id
	end)
	local packs = {}
	for _, key in MonetizationConfig.CreditPackOrder do
		local product = MonetizationConfig.Products[key]
		table.insert(packs, {
			Id = "Pack_" .. key,
			ProductKey = key,
			Name = product.Name,
			Type = "Credits",
			Rarity = "Rare",
			Description = product.Description,
			Color = C.Credits,
		})
	end
	note("R$ = Robux, Roblox's currency (bought through Roblox's own purchase window). ✈ FC = Flight Credits, earned by playing. Passes and packs are optional and only unlock cosmetics or credits.", 1, Color3.fromRGB(190, 230, 200))
	header("🎫 GAME PASSES", "Yours forever", 2, Color3.fromRGB(255, 200, 60))
	grid(passes, 3)
	header("✈ FLIGHT CREDIT PACKS", "Prefer to earn them? Just play!", 4, C.Credits)
	grid(packs, 5)
end

-- Loadout: equip what you own, grouped as My Character / Effects / My Plane.
local function renderLoadout()
	local order = 0
	local groups = {
		{ Id = "Character", Title = "🧍 MY CHARACTER", Color = Color3.fromRGB(255, 120, 190) },
		{ Id = "Effects", Title = "✨ MY EFFECTS", Color = Color3.fromRGB(190, 120, 255) },
		{ Id = "Plane", Title = "🛩️ MY PLANE", Color = Color3.fromRGB(90, 220, 255) },
	}
	local _, width = columns(S(190, 140))
	local tileHeight = math.floor(width * 0.55) + S(54, 40) + UIKit.TouchSize(S(40, 30)) + 18
	for _, group in groups do
		order += 1
		header(group.Title, nil, order, group.Color)
		order += 1
		local holder = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, ZIndex = 23, Parent = body })
		UIKit.new("UIGridLayout", { CellSize = UDim2.fromOffset(width, tileHeight), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = holder })
		UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingTop = UDim.new(0, 4), Parent = holder })
		for slotOrder, slot in ShopCatalog.Slots do
			local info = ShopCatalog.SlotInfo[slot]
			if info.Group == group.Id then
				local equippedId = state.Equipped[slot] or (if info.Required then ShopCatalog.DefaultEquipped[slot] else nil)
				local item = equippedId and ShopCatalog.Get(equippedId)
				local tile = UIKit.new("TextButton", { Name = slot, Text = "", AutoButtonColor = false, BackgroundColor3 = CARD_BG, Corner = 16, LayoutOrder = slotOrder, ZIndex = 24, Parent = holder })
				rarityStroke(tile, item and item.Rarity or "Common", 2)
				local artHolder = UIKit.new("Frame", { Size = UDim2.new(1, -16, 0, math.floor(width * 0.55)), Position = UDim2.fromOffset(8, 8), BackgroundTransparency = 1, ZIndex = 25, Parent = tile })
				if item then
					StoreArt.Art(item, artHolder, 25)
				else
					local empty = UIKit.new("TextLabel", { Text = info.Icon, TextScaled = true, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(36, 42, 58), BackgroundTransparency = 0, TextTransparency = 0.5, Corner = 14, ZIndex = 25, Parent = artHolder })
					UIKit.new("UIPadding", { PaddingTop = UDim.new(0.2, 0), PaddingBottom = UDim.new(0.2, 0), Parent = empty })
				end
				local textY = 8 + math.floor(width * 0.55) + 4
				UIKit.Text({ Text = info.Icon .. "  " .. info.Label, Font = F.Bold, TextSize = S(12, 10), TextColor3 = C.SubText, Position = UDim2.fromOffset(10, textY), Size = UDim2.new(1, -20, 0, S(16, 12)), TextWrapped = false, ZIndex = 25, Parent = tile })
				UIKit.Text({ Text = item and item.Name or "Nothing equipped", Font = F.Heading, TextSize = S(16, 12), TextColor3 = if item then C.Text else C.SubText, TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false, Position = UDim2.fromOffset(10, textY + S(18, 13)), Size = UDim2.new(1, -20, 0, S(22, 15)), ZIndex = 25, Parent = tile })
				local function pick()
					openSheet({ Picker = slot })
				end
				tile.Activated:Connect(pick)
				UIKit.Button({ Text = "CHANGE", Style = "secondary", TextSize = S(14, 11), Size = UDim2.new(1, -16, 0, UIKit.TouchSize(S(40, 30))), Position = UDim2.new(0, 8, 1, -8 - UIKit.TouchSize(S(40, 30))), ZIndex = 26, Parent = tile, OnClick = pick })
			end
		end
	end
	order += 1
	note("Your loadout is saved to your profile. Character looks are seen by everyone; plane looks show on your screen.", order)
end

function refresh()
	if not body then
		return
	end
	local scroll = body.CanvasPosition
	clearBody()
	for name, tab in tabs do
		local info = ShopCatalog.CategoryInfo[name]
		local active = name == page
		tab.BackgroundColor3 = if active then info.Color else C.PanelLight
		tab.TextColor3 = if active then Color3.fromRGB(20, 22, 30) else C.Text
	end
	creditsLabel.Text = "✈ " .. Util.FormatNumber(state.Credits or 0) .. "  " .. EconomyConfig.CurrencyShort
	if page == "Featured" then
		renderFeatured()
	elseif page == "Premium" then
		renderPremium()
	elseif page == "Loadout" then
		renderLoadout()
	else
		renderCategory(page)
	end
	animateCards = false
	task.defer(function()
		body.CanvasPosition = scroll -- after the canvas has been re-measured
	end)
	if sheet.Visible and sheetItem then
		openSheet(sheetItem)
	end
end

function openPage(name: string)
	if page ~= name then
		page = name
		animateCards = true
		body.CanvasPosition = Vector2.zero
	end
	refresh()
	local tab = tabs[name]
	if tab then
		pop(tab)
	end
end

---------------------------------------------------------------- preview / picker sheet

local function closeSheet()
	if previewCleanup then
		previewCleanup()
		previewCleanup = nil
	end
	sheetItem = nil
	sheet.Visible = false
end

local function clearSheet()
	if previewCleanup then
		previewCleanup()
		previewCleanup = nil
	end
	local panel = sheet:FindFirstChild("Panel") :: Frame
	for _, child in panel:GetChildren() do
		if child:IsA("GuiObject") and child.Name ~= "Close" then
			child:Destroy()
		end
	end
	return panel
end

local function equippedItems(): { [string]: any }
	local items = {}
	for _, slot in ShopCatalog.Slots do
		local info = ShopCatalog.SlotInfo[slot]
		local id = state.Equipped[slot] or (if info.Required then ShopCatalog.DefaultEquipped[slot] else nil)
		if id and owns(id) then
			items[slot] = ShopCatalog.Get(id)
		end
	end
	return items
end

local function renderPicker(panel: Frame, slot: string)
	local info = ShopCatalog.SlotInfo[slot]
	local z = 41
	UIKit.Text({ Text = info.Icon .. "  " .. info.Label, Font = F.Heading, TextSize = S(26, 16), Position = UDim2.fromOffset(20, 16), Size = UDim2.new(1, -90, 0, S(32, 20)), ZIndex = z, Parent = panel })
	local list = UIKit.Scroll({ Position = UDim2.fromOffset(16, S(32, 20) + 30), Size = UDim2.new(1, -32, 1, -(S(32, 20) + 46)), ZIndex = z, Parent = panel })
	local _, width = columns(S(170, 130))
	width = math.min(width, S(200, 150))
	UIKit.new("UIGridLayout", { CellSize = UDim2.fromOffset(width, math.floor(width * 0.6) + S(30, 22) + UIKit.TouchSize(S(40, 30)) + 20), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	local entries = {}
	for _, item in ShopCatalog.Items do
		if item.Slot == slot and owns(item.Id) then
			table.insert(entries, item)
		end
	end
	if not info.Required then
		table.insert(entries, 1, { Id = "__none", Name = "Nothing", Type = "None", Color = Color3.fromRGB(70, 75, 90) })
	end
	for index, item in entries do
		local tile = UIKit.new("Frame", { BackgroundColor3 = CARD_BG, Corner = 14, LayoutOrder = index, ZIndex = z, Parent = list })
		rarityStroke(tile, item.Rarity or "Common", 2)
		local artHolder = UIKit.new("Frame", { Size = UDim2.new(1, -12, 0, math.floor(width * 0.6)), Position = UDim2.fromOffset(6, 6), BackgroundTransparency = 1, ZIndex = z + 1, Parent = tile })
		if item.Type == "None" then
			UIKit.new("TextLabel", { Text = "∅", TextScaled = true, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(36, 42, 58), BackgroundTransparency = 0, TextColor3 = C.SubText, Corner = 12, ZIndex = z + 1, Parent = artHolder })
		else
			StoreArt.Art(item, artHolder, z + 1)
		end
		UIKit.Text({ Text = item.Name, Font = F.Bold, TextSize = S(14, 11), TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false, Position = UDim2.fromOffset(8, math.floor(width * 0.6) + 10), Size = UDim2.new(1, -16, 0, S(20, 14)), ZIndex = z + 1, Parent = tile })
		local on = if item.Type == "None" then state.Equipped[slot] == nil else isEquipped(item)
		local buttonHeight = UIKit.TouchSize(S(40, 30))
		if on then
			UIKit.new("TextLabel", { Text = "EQUIPPED ✔", Font = F.Bold, TextSize = S(13, 11), TextColor3 = Color3.fromRGB(190, 255, 210), BackgroundColor3 = BUTTON_COLORS.owned, BackgroundTransparency = 0, Corner = 10, Size = UDim2.new(1, -12, 0, buttonHeight), Position = UDim2.new(0, 6, 1, -6 - buttonHeight), ZIndex = z + 2, Parent = tile })
		else
			UIKit.Button({
				Text = "EQUIP",
				Style = "secondary",
				BackgroundColor3 = BUTTON_COLORS.equip,
				TextSize = S(13, 11),
				Size = UDim2.new(1, -12, 0, buttonHeight),
				Position = UDim2.new(0, 6, 1, -6 - buttonHeight),
				ZIndex = z + 2,
				Parent = tile,
				OnClick = function()
					if item.Type == "None" then
						unequip(slot)
					else
						equip(item)
					end
				end,
			})
		end
	end
	-- jump to the shop category that sells this slot
	local category = nil
	for _, item in ShopCatalog.Items do
		if item.Slot == slot and item.Category then
			category = item.Category
			break
		end
	end
	if category then
		local shopTile = UIKit.new("Frame", { BackgroundColor3 = CARD_BG, BackgroundTransparency = 0.4, Corner = 14, LayoutOrder = #entries + 1, ZIndex = z, Parent = list })
		UIKit.Button({
			Text = "🛍 SHOP MORE",
			Style = "primary",
			TextSize = S(14, 11),
			Size = UDim2.new(1, -16, 0, UIKit.TouchSize(S(44, 32))),
			Position = UDim2.new(0, 8, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			ZIndex = z + 1,
			Parent = shopTile,
			OnClick = function()
				closeSheet()
				openPage(category)
			end,
		})
	end
end

local function renderItemSheet(panel: Frame, item)
	local z = 41
	local narrow = contentWidth() < S(900, 600) or UIKit.IsTouch()
	local previewBox = UIKit.new("Frame", {
		Name = "PreviewBox",
		BackgroundColor3 = Color3.fromRGB(32, 38, 54),
		Corner = 16,
		ClipsDescendants = true,
		ZIndex = z,
		Parent = panel,
	})
	UIKit.new("UIGradient", { Color = ColorSequence.new((item.Color or C.Accent):Lerp(Color3.fromRGB(32, 38, 54), 0.55), Color3.fromRGB(20, 24, 34)), Rotation = 90, Parent = previewBox })
	local info = UIKit.new("ScrollingFrame", {
		Name = "Info",
		BackgroundTransparency = 1,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = z,
		Parent = panel,
	})
	if narrow then
		previewBox.Position = UDim2.fromOffset(16, 16)
		previewBox.Size = UDim2.new(0.5, -24, 1, -32)
		info.Position = UDim2.new(0.5, 8, 0, 16)
		info.Size = UDim2.new(0.5, -24, 1, -32)
	else
		previewBox.Position = UDim2.fromOffset(20, 20)
		previewBox.Size = UDim2.new(0.55, -30, 1, -40)
		info.Position = UDim2.new(0.55, 10, 0, 20)
		info.Size = UDim2.new(0.45, -30, 1, -40)
	end
	previewCleanup = StoreArt.Preview(previewBox, item, { Equipped = equippedItems() })
	chip(previewBox, "PREVIEW", Color3.fromRGB(20, 24, 34), Vector2.new(0, 1), UDim2.new(0, 10, 1, -10), z + 8)

	UIKit.List(info, 8)
	UIKit.new("UIPadding", { PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 4), Parent = info })
	local rarity = item.Rarity or "Common"
	local chipRow = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, S(22, 16)), LayoutOrder = 1, ZIndex = z, Parent = info })
	UIKit.List(chipRow, 6, Enum.FillDirection.Horizontal)
	local rc = chip(chipRow, string.upper(rarity), ShopCatalog.Rarities[rarity] or C.Stroke, Vector2.zero, UDim2.new(), z + 1, rarity == "Legendary" or rarity == "Common")
	rc.LayoutOrder = 1
	local kindLabel = if item.Slot and ShopCatalog.SlotInfo[item.Slot] then ShopCatalog.SlotInfo[item.Slot].Label elseif item.Type == "Bundle" then "BUNDLE" elseif item.Type == "Pass" then "GAME PASS" elseif item.Type == "Credits" then "CREDIT PACK" else string.upper(item.Type or "")
	local kc = chip(chipRow, kindLabel, Color3.fromRGB(60, 68, 90), Vector2.zero, UDim2.new(), z + 1)
	kc.LayoutOrder = 2
	UIKit.Text({ Text = item.Name, Font = F.Heading, TextSize = S(30, 18), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, ZIndex = z, Parent = info })
	UIKit.Text({ Text = item.Description or "", TextSize = S(16, 12), TextColor3 = C.SubText, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, ZIndex = z, Parent = info })

	if item.Type == "Bundle" and item.Data then
		UIKit.Text({ Text = "INSIDE THIS BUNDLE", Font = F.Heading, TextSize = S(14, 11), TextColor3 = C.Good, LayoutOrder = 4, ZIndex = z, Parent = info })
		for index, id in item.Data.Items do
			local inner = ShopCatalog.Get(id)
			if inner then
				local row = UIKit.new("Frame", { BackgroundColor3 = CARD_BG, Size = UDim2.new(1, 0, 0, S(40, 28)), Corner = 10, LayoutOrder = 4 + index, ZIndex = z, Parent = info })
				UIKit.Text({ Text = StoreArt.Glyph(inner), TextScaled = true, Size = UDim2.fromOffset(S(30, 22), S(30, 22)), Position = UDim2.fromOffset(6, S(5, 3)), ZIndex = z + 1, Parent = row })
				local priceText = if owns(id) then "OWNED ✔" elseif inner.Price then "✈ " .. Util.FormatNumber(inner.Price) elseif inner.Exclusive then "EXCLUSIVE" else ""
				UIKit.Text({ Text = inner.Name, Font = F.Bold, TextSize = S(15, 11), TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(S(42, 30), 0), Size = UDim2.new(0.65, -S(42, 30), 1, 0), ZIndex = z + 1, Parent = row })
				UIKit.Text({ Text = priceText, Font = F.Bold, TextSize = S(13, 10), TextColor3 = if owns(id) then C.Good elseif inner.Price then C.Credits else Color3.fromRGB(190, 150, 255), TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.new(0.35, 0, 1, 0), ZIndex = z + 1, Parent = row })
				row.Size = UDim2.new(1, 0, 0, S(40, 28))
			end
		end
		local value = ShopCatalog.BundleValue(item)
		if value and item.Price then
			UIKit.Text({
				Text = string.format("Bought separately: ✈ %s   ·   Bundle: ✈ %s", Util.FormatNumber(value), Util.FormatNumber(item.Price)),
				Font = F.Bold,
				TextSize = S(14, 11),
				TextColor3 = C.Credits,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 30,
				ZIndex = z,
				Parent = info,
			})
		else
			local exclusives = 0
			for _, id in item.Data.Items do
				local inner = ShopCatalog.Get(id)
				if inner and inner.Exclusive then
					exclusives += 1
				end
			end
			UIKit.Text({
				Text = string.format("%d items%s", #item.Data.Items, if exclusives > 0 then " · " .. exclusives .. " only available in this bundle" else ""),
				Font = F.Bold,
				TextSize = S(14, 11),
				TextColor3 = Color3.fromRGB(190, 150, 255),
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 30,
				ZIndex = z,
				Parent = info,
			})
		end
	end
	if item.Type == "PlaneSkin" or item.Type == "WingEffect" or item.Type == "PlaneTrail" then
		UIKit.Text({ Text = "Visual only - flight, disasters and landing are unchanged.", TextSize = S(13, 10), TextColor3 = Color3.fromRGB(150, 220, 255), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 31, ZIndex = z, Parent = info })
	end

	local kind, priceText = priceInfo(item)
	UIKit.Text({
		Text = priceText,
		Font = F.Heading,
		TextSize = S(26, 16),
		TextColor3 = if kind == "FC" then C.Credits elseif kind == "R$" then ROBUX_GREEN elseif kind == "OWNED" then C.Good else C.SubText,
		Size = UDim2.new(1, 0, 0, S(32, 20)),
		LayoutOrder = 40,
		ZIndex = z,
		Parent = info,
	})
	if kind == "FC" or kind == "R$" then
		UIKit.Text({ Text = if kind == "FC" then "Flight Credits (earned by playing)" else "Robux (Roblox purchase window)", TextSize = S(12, 10), TextColor3 = C.SubText, LayoutOrder = 41, Size = UDim2.new(1, 0, 0, S(16, 12)), ZIndex = z, Parent = info })
	end
	local buttonHeight = UIKit.TouchSize(S(52, 36))
	local action = actionButton(info, item, UDim2.new(1, 0, 0, buttonHeight), nil, z + 1)
	action.LayoutOrder = 50
	if owns(item.Id) and item.Slot and isEquipped(item) and not (ShopCatalog.SlotInfo[item.Slot] and ShopCatalog.SlotInfo[item.Slot].Required) then
		local remove = UIKit.Button({ Text = "UNEQUIP", Style = "secondary", TextSize = S(15, 11), Size = UDim2.new(1, 0, 0, UIKit.TouchSize(S(44, 32))), LayoutOrder = 51, ZIndex = z + 1, Parent = info, OnClick = function()
			unequip(item.Slot)
		end })
		remove.LayoutOrder = 51
	end
	if item.Type == "Emote" and owns(item.Id) then
		UIKit.Button({ Text = "▶ PLAY IT NOW", Style = "secondary", TextSize = S(15, 11), Size = UDim2.new(1, 0, 0, UIKit.TouchSize(S(44, 32))), LayoutOrder = 52, ZIndex = z + 1, Parent = info, OnClick = function()
			Net.Event("PlayEmote"):FireServer(item.Id)
		end })
	end
end

function openSheet(item)
	sheetItem = item
	local panel = clearSheet()
	local wasVisible = sheet.Visible
	sheet.Visible = true
	if item.Picker then
		renderPicker(panel, item.Picker)
	else
		renderItemSheet(panel, item)
	end
	if not wasVisible then
		pop(panel)
	end
end

---------------------------------------------------------------- celebrations & intro

function celebrate(item, title: string)
	for _, child in fxLayer:GetChildren() do
		child:Destroy()
	end
	fxLayer.Visible = true
	local box = UIKit.Panel({
		Size = UDim2.fromOffset(S(360, 250), S(380, 260)),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(24, 28, 40),
		ZIndex = 61,
		Parent = fxLayer,
	})
	rarityStroke(box, item.Rarity or "Common", 3)
	local scale = UIKit.new("UIScale", { Scale = 0.5, Parent = box })
	UIKit.Tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	UIKit.Text({ Text = title, Font = F.Heading, TextSize = S(34, 20), TextColor3 = if title == "PURCHASED!" then C.Credits else C.Good, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, S(40, 24)), ZIndex = 62, Parent = box })
	local artHolder = UIKit.new("Frame", { Size = UDim2.fromOffset(S(190, 130), S(190, 130)), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, S(64, 42)), BackgroundTransparency = 1, ZIndex = 62, Parent = box })
	StoreArt.Art(item, artHolder, 62)
	UIKit.Text({ Text = item.Name, Font = F.Bold, TextSize = S(20, 14), TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 0, 0, S(64, 42) + S(196, 134)), Size = UDim2.new(1, 0, 0, S(26, 18)), ZIndex = 62, Parent = box })
	local buttonHeight = UIKit.TouchSize(S(44, 32))
	local hide = function()
		fxLayer.Visible = false
	end
	if item.Slot and owns(item.Id) and not isEquipped(item) then
		UIKit.Button({ Text = "EQUIP NOW", Style = "secondary", BackgroundColor3 = BUTTON_COLORS.equip, TextSize = S(15, 11), Size = UDim2.new(0.5, -18, 0, buttonHeight), Position = UDim2.new(0, 12, 1, -12 - buttonHeight), ZIndex = 63, Parent = box, OnClick = function()
			equip(item)
			hide()
		end })
		UIKit.Button({ Text = "AWESOME!", Style = "secondary", TextSize = S(15, 11), Size = UDim2.new(0.5, -18, 0, buttonHeight), Position = UDim2.new(0.5, 6, 1, -12 - buttonHeight), ZIndex = 63, Parent = box, OnClick = hide })
	else
		UIKit.Button({ Text = "AWESOME!", Style = "secondary", TextSize = S(15, 11), Size = UDim2.new(1, -24, 0, buttonHeight), Position = UDim2.new(0, 12, 1, -12 - buttonHeight), ZIndex = 63, Parent = box, OnClick = hide })
	end
	StoreArt.Burst(fxLayer, 34, { C.Credits, Color3.fromRGB(255, 120, 200), Color3.fromRGB(90, 200, 255), Color3.fromRGB(120, 230, 140) }, Vector2.new(0.5, 0.45), nil, 64)
	local stamp = os.clock()
	fxLayer:SetAttribute("Stamp", stamp)
	task.delay(4, function()
		if fxLayer:GetAttribute("Stamp") == stamp then
			hide()
		end
	end)
end

local function finishIntro()
	intro.Visible = false
	Net.Event("StoreIntroSeen"):FireServer()
	state.Flags = state.Flags or {}
	state.Flags.StoreIntro = true
end

local function showIntro()
	introShownThisSession = true
	for _, child in intro:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	intro.Visible = true
	local box = UIKit.Panel({ Size = UDim2.new(0.86, 0, 0.84, 0), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(22, 26, 38), ZIndex = 71, Parent = intro })
	UIKit.new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(60, 90, 170), Color3.fromRGB(22, 26, 38)), Rotation = 90, Parent = box })
	local scale = UIKit.new("UIScale", { Scale = 0.7, Parent = box })
	UIKit.Tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	UIKit.Text({ Text = "MAKE YOUR FLIGHT YOURS ✈️", Font = F.Heading, TextSize = S(36, 20), TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, S(44, 26)), ZIndex = 72, Parent = box })
	UIKit.Text({ Text = "Outfits, emotes, plane skins and effects. Just for looks - never pay-to-win. Earn ✈ Flight Credits by playing!", TextSize = S(16, 12), TextColor3 = C.SubText, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0.05, 0, 0, S(64, 40)), Size = UDim2.new(0.9, 0, 0, S(44, 30)), ZIndex = 72, Parent = box })
	local row = UIKit.new("Frame", { BackgroundTransparency = 1, Position = UDim2.new(0.04, 0, 0, S(116, 76)), Size = UDim2.new(0.92, 0, 1, -(S(116, 76) + UIKit.TouchSize(S(52, 36)) + 36)), ZIndex = 72, Parent = box })
	UIKit.List(row, 12, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	for index, id in { "OutfitPilot", "PlaneNeon", "EmoteVictory", "TrailCloud" } do
		local item = ShopCatalog.Get(id)
		if item then
			local tile = UIKit.new("Frame", { Size = UDim2.new(0.23, 0, 1, 0), BackgroundColor3 = CARD_BG, Corner = 16, LayoutOrder = index, ZIndex = 72, Parent = row })
			rarityStroke(tile, item.Rarity, 2)
			local artHolder = UIKit.new("Frame", { Size = UDim2.new(1, -16, 1, -(S(30, 20) + 16)), Position = UDim2.fromOffset(8, 8), BackgroundTransparency = 1, ZIndex = 73, Parent = tile })
			StoreArt.Art(item, artHolder, 73)
			UIKit.Text({ Text = item.Name, Font = F.Bold, TextSize = S(15, 11), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.new(0, 4, 1, -(S(30, 20) + 4)), Size = UDim2.new(1, -8, 0, S(26, 18)), ZIndex = 73, Parent = tile })
			local tileScale = UIKit.new("UIScale", { Scale = 0.6, Parent = tile })
			task.delay(0.15 + index * 0.08, function()
				UIKit.Tween(tileScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			end)
		end
	end
	local buttonHeight = UIKit.TouchSize(S(52, 36))
	UIKit.Button({ Name = "Go", Text = "LET'S GO!", Style = "secondary", BackgroundColor3 = C.Credits, TextColor3 = Color3.fromRGB(45, 32, 8), TextSize = S(18, 13), Size = UDim2.new(0.4, 0, 0, buttonHeight), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(0.5, -6, 1, -18), ZIndex = 73, Parent = box, OnClick = finishIntro })
	UIKit.Button({ Name = "Skip", Text = "SKIP", Style = "secondary", TextSize = S(16, 12), Size = UDim2.new(0.25, 0, 0, buttonHeight), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0.5, 6, 1, -18), ZIndex = 73, Parent = box, OnClick = finishIntro })
end

---------------------------------------------------------------- open / close

local function fetchState()
	local ok, result = pcall(function()
		return Net.Function("GetShopState"):InvokeServer()
	end)
	if ok and result then
		state = result
		state.Flags = state.Flags or {}
	end
end

local function startUltra()
	if ultraConnection then
		return
	end
	ultraConnection = RunService.RenderStepped:Connect(function()
		local rotation = (os.clock() * 90) % 360
		for _, gradient in ultraGradients do
			gradient.Rotation = rotation
		end
	end)
end

local function stopUltra()
	if ultraConnection then
		ultraConnection:Disconnect()
		ultraConnection = nil
	end
end

function ShopController:Open(target: string?)
	fetchState()
	if target and table.find(PAGES, target) then
		page = target
		body.CanvasPosition = Vector2.zero
	end
	animateCards = true
	refresh()
	UIKit.OpenWindow(overlay)
	startUltra()
	if not introShownThisSession and state.Flags.StoreIntro ~= true then
		showIntro()
	end
end

function ShopController:IsOpen(): boolean
	return overlay.Visible
end

function ShopController:Init()
	local gui = UIKit.Screen("ShopUI", 20)
	local root = UIKit.Root(gui)
	overlay, content = UIKit.Window(root, "✈ SKY SHOP", UDim2.new(0.96, 0, 0.94, 0), function()
		closeSheet()
		stopUltra()
		fxLayer.Visible = false
	end)
	local window = overlay:FindFirstChild("Window") :: Frame
	local headerFrame = window:FindFirstChild("Header") :: Frame
	-- currency: Flight Credits pill + a shortcut to the passes & credits page
	local pill = UIKit.new("Frame", {
		Name = "Credits",
		BackgroundColor3 = Color3.fromRGB(60, 48, 18),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(UIKit.TouchSize(44) + 32), 0.5, 0),
		Size = UDim2.fromOffset(S(220, 150), UIKit.TouchSize(S(40, 30))),
		Corner = UDim.new(1, 0),
		Stroke = { Color = C.Credits, Thickness = 2 },
		ZIndex = 23,
		Parent = headerFrame,
	})
	creditsLabel = UIKit.Text({ Text = "", Font = F.Heading, TextSize = S(19, 13), TextColor3 = C.Credits, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, -UIKit.TouchSize(S(40, 30)), 1, 0), Position = UDim2.fromOffset(6, 0), TextWrapped = false, ZIndex = 24, Parent = pill })
	UIKit.Button({
		Name = "GetCredits",
		Text = "+",
		Style = "secondary",
		BackgroundColor3 = C.Credits,
		TextColor3 = Color3.fromRGB(45, 32, 8),
		TextSize = S(22, 15),
		Size = UDim2.fromOffset(UIKit.TouchSize(S(40, 30)) - 6, UIKit.TouchSize(S(40, 30)) - 6),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -3, 0.5, 0),
		Corner = UDim.new(1, 0),
		ZIndex = 25,
		Parent = pill,
		OnClick = function()
			openPage("Premium")
		end,
	})

	local tabHeight = UIKit.TouchSize(S(46, 34))
	tabBar = UIKit.Scroll({
		Name = "Tabs",
		Size = UDim2.new(1, 0, 0, tabHeight + 8),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 3,
		ZIndex = 22,
		Parent = content,
	})
	UIKit.List(tabBar, 8, Enum.FillDirection.Horizontal)
	for index, name in PAGES do
		local info = ShopCatalog.CategoryInfo[name]
		local tab = UIKit.Button({
			Name = name,
			Text = info.Icon .. "  " .. info.Label,
			Style = "secondary",
			TextSize = S(15, 12),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, S(120, 80), 0, tabHeight),
			LayoutOrder = index,
			ZIndex = 23,
			Parent = tabBar,
			OnClick = function()
				openPage(name)
			end,
		})
		UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), Parent = tab })
		tabs[name] = tab
	end

	body = UIKit.Scroll({
		Name = "Body",
		Position = UDim2.fromOffset(0, tabHeight + 16),
		Size = UDim2.new(1, 0, 1, -(tabHeight + 16)),
		ScrollBarThickness = 6,
		ZIndex = 22,
		Parent = content,
	})
	UIKit.List(body, 10)
	UIKit.new("UIPadding", { PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 20), Parent = body })

	-- preview / picker sheet (covers the store body)
	sheet = UIKit.new("TextButton", {
		Name = "Sheet",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 39,
		Parent = window,
	})
	local panel = UIKit.Panel({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -24, 1, -24),
		BackgroundColor3 = Color3.fromRGB(20, 24, 34),
		ZIndex = 40,
		Parent = sheet,
	})
	UIKit.Button({
		Name = "Close",
		Text = "✕",
		Style = "secondary",
		TextSize = S(22, 15),
		Size = UDim2.fromOffset(UIKit.TouchSize(S(44, 32)), UIKit.TouchSize(S(44, 32))),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		ZIndex = 50,
		Parent = panel,
		OnClick = closeSheet,
	})

	fxLayer = UIKit.new("Frame", { Name = "Celebration", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5, Visible = false, ZIndex = 60, Parent = window })
	intro = UIKit.new("Frame", { Name = "Intro", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.3, Visible = false, ZIndex = 70, Parent = window })

	toastLabel = UIKit.new("TextLabel", {
		Name = "Toast",
		Text = "",
		Font = F.Bold,
		TextSize = S(16, 12),
		TextWrapped = true,
		BackgroundColor3 = Color3.fromRGB(14, 17, 24),
		BackgroundTransparency = 0.05,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.new(0.6, 0, 0, S(46, 32)),
		Corner = 14,
		Stroke = { Color = C.Stroke },
		Visible = false,
		ZIndex = 80,
		Parent = window,
	})
	UIKit.new("UIScale", { Parent = toastLabel })

	-- rebuild the grid when the window size class changes (rotation / resize)
	content:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local width = contentWidth()
		if overlay.Visible and math.abs(width - lastWidth) > 40 then
			lastWidth = width
			refresh()
		end
	end)
end

function ShopController:Start()
	ClientState.ProfileChanged:Connect(function(profile)
		state.Owned = profile.Owned or state.Owned
		state.Equipped = profile.Equipped or state.Equipped
		state.Credits = profile.Credits or state.Credits
		state.Passes = profile.Passes or state.Passes
		state.Flags = profile.Flags or state.Flags
		if pendingEquip and state.Equipped[pendingEquip.Slot] == pendingEquip.Id then
			local item = ShopCatalog.Get(pendingEquip.Id)
			pendingEquip = nil
			if item and overlay.Visible then
				toast("EQUIPPED!  " .. StoreArt.Glyph(item) .. "  " .. item.Name, C.Good)
			end
		end
		if overlay.Visible then
			refresh()
		end
	end)
	Net.Event("PurchaseResult").OnClientEvent:Connect(function(result)
		if type(result) ~= "table" then
			return
		end
		if not overlay.Visible then
			return
		end
		if result.Ok then
			local item = result.ItemId and ShopCatalog.Get(result.ItemId)
			task.delay(0.15, function()
				fetchState()
				refresh()
				if item then
					celebrate(item, "PURCHASED!")
				elseif result.Message then
					toast(result.Message, C.Good)
				end
			end)
		elseif result.Message then
			toast(result.Message, C.Danger)
		end
	end)
end

return ShopController
