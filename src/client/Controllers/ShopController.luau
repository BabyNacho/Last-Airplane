--[[
	ShopController
	"Duty Free" shop: categories, item grid with previews, details and purchase/equip actions.
	  * Flight Credit items -> ShopPurchase remote (validated on the server)
	  * Robux items / credit packs -> MarketplaceService:PromptProductPurchase (official flow)
	  * Game passes -> MarketplaceService:PromptGamePassPurchase
	Products whose id isn't configured yet show "COMING SOON" instead of a fake purchase button.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AchievementConfig = require(ReplicatedStorage.Shared.Config.AchievementConfig)
local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local MonetizationConfig = require(ReplicatedStorage.Shared.Config.MonetizationConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local ShopCatalog = require(ReplicatedStorage.Shared.Config.ShopCatalog)
local Util = require(ReplicatedStorage.Shared.Util)
local ClientState = require(script.Parent.Parent.ClientState)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local ShopController = {}

local player = Players.LocalPlayer
local C = UIKit.Colors
local F = UIKit.Fonts

local overlay: Frame
local grid: ScrollingFrame
local detail: Frame
local creditsLabel: TextLabel
local tabs: { [string]: TextButton } = {}
local category = "Cosmetics"
local selected: any = nil
local state: any = { Owned = {}, Equipped = {}, Credits = 0, Availability = { Products = {}, Passes = {} }, Passes = {} }

local GLYPHS = {
	Hat = "🎩",
	Face = "🕶",
	Body = "🎒",
	Emote = "💃",
	VictoryEffect = "🎆",
	Bundle = "🎁",
	Pass = "🎫",
	Credits = "✈",
}

local function owns(id: string): boolean
	return table.find(state.Owned, id) ~= nil
end

local function isEquipped(item): boolean
	return item.Slot ~= nil and state.Equipped[item.Slot] == item.Id
end

-- Virtual entries for the Premium tab (passes & credit packs) that aren't catalog items.
local function premiumExtras()
	local list = {}
	for key, pass in MonetizationConfig.GamePasses do
		table.insert(list, {
			Id = "Pass_" .. key,
			PassKey = key,
			Name = pass.Name,
			Type = "Pass",
			Category = "Premium",
			Rarity = "Legendary",
			Description = pass.Description,
			Color = Color3.fromRGB(255, 200, 60),
			Order = -10,
		})
	end
	for index, key in MonetizationConfig.CreditPackOrder do
		local product = MonetizationConfig.Products[key]
		table.insert(list, {
			Id = "Pack_" .. key,
			ProductKey = key,
			Name = product.Name,
			Type = "Credits",
			Category = "Premium",
			Rarity = "Rare",
			Description = product.Description,
			Color = C.Credits,
			Order = -5 + index,
		})
	end
	return list
end

local function itemsFor(cat: string)
	local list = {}
	for _, item in ShopCatalog.Items do
		if item.Category == cat and not (item.Type == "Title" and item.Default) then
			table.insert(list, item)
		end
	end
	if cat == "Premium" then
		for _, extra in premiumExtras() do
			table.insert(list, extra)
		end
	end
	table.sort(list, function(a, b)
		return (a.Order or 0) < (b.Order or 0)
	end)
	return list
end

local function preview(parent: Instance, item, size: number)
	local tile = UIKit.new("Frame", {
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Color3.fromRGB(28, 33, 46),
		Corner = 10,
		Parent = parent,
	})
	UIKit.new("UIGradient", {
		Color = ColorSequence.new(item.Color or C.Accent, Color3.fromRGB(28, 33, 46)),
		Rotation = 135,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) }),
		Parent = tile,
	})
	if item.Type == "Title" then
		UIKit.new("TextLabel", { Text = string.upper(item.Name), Font = F.Heading, TextScaled = true, TextColor3 = item.Color, Size = UDim2.fromScale(0.9, 0.4), Position = UDim2.fromScale(0.05, 0.3), Parent = tile })
	elseif item.Type == "Trail" then
		local bar = UIKit.new("Frame", { Size = UDim2.fromScale(0.8, 0.22), Position = UDim2.fromScale(0.1, 0.39), BackgroundColor3 = Color3.new(1, 1, 1), Corner = UDim.new(1, 0), Parent = tile })
		local keypoints = {}
		local colors = item.Data and item.Data.Colors or { item.Color, item.Color }
		for i, color in colors do
			table.insert(keypoints, ColorSequenceKeypoint.new((i - 1) / math.max(1, #colors - 1), color))
		end
		if #keypoints == 1 then
			table.insert(keypoints, ColorSequenceKeypoint.new(1, colors[1]))
		end
		UIKit.new("UIGradient", { Color = ColorSequence.new(keypoints), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.9) }), Parent = bar })
	elseif item.Type == "Theme" then
		UIKit.new("Frame", { Size = UDim2.fromScale(0.5, 0.5), Position = UDim2.fromScale(0.25, 0.25), BackgroundColor3 = item.Data.Accent, Corner = UDim.new(1, 0), Stroke = { Color = Color3.new(1, 1, 1), Thickness = 2 }, Parent = tile })
	else
		local glyph = GLYPHS[item.Slot or ""] or GLYPHS[item.Type] or "★"
		UIKit.new("TextLabel", { Text = glyph, TextScaled = true, Size = UDim2.fromScale(0.6, 0.6), Position = UDim2.fromScale(0.2, 0.2), Parent = tile })
	end
	return tile
end

local function priceText(item): (string, Color3)
	if item.Type == "Pass" then
		local id = state.Availability.Passes[item.PassKey]
		if state.Passes[item.PassKey] then
			return "OWNED", C.Good
		end
		return if id then "R$ " .. MonetizationConfig.GamePasses[item.PassKey].PriceHint else "COMING SOON", if id then C.Good else C.SubText
	elseif item.Type == "Credits" then
		local id = state.Availability.Products[item.ProductKey]
		local product = MonetizationConfig.Products[item.ProductKey]
		return if id then "R$ " .. product.PriceHint else "COMING SOON", if id then C.Good else C.SubText
	end
	if owns(item.Id) then
		return if isEquipped(item) then "EQUIPPED" else "OWNED", C.Good
	end
	if item.Price then
		return "✈ " .. Util.FormatNumber(item.Price), C.Credits
	elseif item.Product then
		local id = state.Availability.Products[item.Product]
		return if id then "R$ " .. MonetizationConfig.Products[item.Product].PriceHint else "COMING SOON", if id then C.Good else C.SubText
	elseif item.Pass then
		return "PASS", C.Warn
	elseif item.Unlock then
		return "ACHIEVEMENT", C.Optional
	end
	return "", C.SubText
end

local refreshGrid

-- A status line when there is nothing to do (never a clickable button that does nothing).
local function actionButton(parent: Instance, text: string, style: string, onClick): GuiObject
	if not onClick then
		return UIKit.new("TextLabel", {
			Text = text,
			Font = F.Bold,
			TextSize = 16,
			TextColor3 = C.SubText,
			BackgroundColor3 = C.Background,
			BackgroundTransparency = 0.3,
			Size = UDim2.new(1, 0, 0, UIKit.TouchSize(44)),
			Corner = 12,
			Parent = parent,
		})
	end
	return UIKit.Button({
		Text = text,
		Style = style,
		Size = UDim2.new(1, 0, 0, UIKit.TouchSize(52)),
		Parent = parent,
		OnClick = onClick,
	})
end

local function showDetail(item)
	selected = item
	for _, child in detail:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	if not item then
		UIKit.Text({ Text = "Select an item", TextColor3 = C.SubText, TextXAlignment = Enum.TextXAlignment.Center, Parent = detail })
		return
	end
	local holder = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 150), LayoutOrder = 1, Parent = detail })
	local tile = preview(holder, item, 150)
	tile.AnchorPoint = Vector2.new(0.5, 0)
	tile.Position = UDim2.fromScale(0.5, 0)
	UIKit.Text({ Text = item.Name, Font = F.Heading, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = detail })
	UIKit.Text({ Text = string.upper(item.Rarity or ""), Font = F.Bold, TextSize = 13, TextColor3 = ShopCatalog.Rarities[item.Rarity or "Common"] or C.SubText, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 3, Parent = detail })
	UIKit.Text({ Text = item.Description or "", TextSize = 15, TextColor3 = C.SubText, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4, Parent = detail })
	if item.Type == "Bundle" and item.Data then
		local names = {}
		for _, id in item.Data.Items do
			local inner = ShopCatalog.Get(id)
			if inner then
				table.insert(names, (if owns(id) then "✔ " else "• ") .. inner.Name)
			end
		end
		UIKit.Text({ Text = table.concat(names, "\n"), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 5, Parent = detail })
	end
	local price, color = priceText(item)
	UIKit.Text({ Text = price, Font = F.Heading, TextSize = 22, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 6, Parent = detail })
	local actions = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 7, Parent = detail })
	UIKit.List(actions, 6)

	if item.Type == "Pass" then
		local id = state.Availability.Passes[item.PassKey]
		if state.Passes[item.PassKey] then
			actionButton(actions, "OWNED ✔", "secondary", nil)
		elseif id then
			actionButton(actions, "GET PASS", "good", function()
				MarketplaceService:PromptGamePassPurchase(player, id)
			end)
		else
			actionButton(actions, "COMING SOON", "secondary", nil)
		end
		return
	elseif item.Type == "Credits" then
		local id = state.Availability.Products[item.ProductKey]
		if id then
			actionButton(actions, "BUY  ·  R$ " .. MonetizationConfig.Products[item.ProductKey].PriceHint, "good", function()
				MarketplaceService:PromptProductPurchase(player, id)
			end)
		else
			actionButton(actions, "COMING SOON", "secondary", nil)
		end
		return
	end

	if owns(item.Id) then
		if item.Slot then
			if isEquipped(item) then
				if item.Slot ~= "Theme" and item.Slot ~= "Title" then
					actionButton(actions, "UNEQUIP", "secondary", function()
						Net.Event("Equip"):FireServer(item.Slot, nil)
					end)
				else
					actionButton(actions, "EQUIPPED ✔", "secondary", nil)
				end
			else
				actionButton(actions, "EQUIP", "primary", function()
					Net.Event("Equip"):FireServer(item.Slot, item.Id)
				end)
			end
		elseif item.Type == "Emote" then
			actionButton(actions, "PLAY EMOTE", "primary", function()
				Net.Event("PlayEmote"):FireServer(item.Id)
			end)
		else
			actionButton(actions, "OWNED ✔", "secondary", nil)
		end
		return
	end
	if item.Price then
		local affordable = (state.Credits or 0) >= item.Price
		actionButton(actions, if affordable then "BUY  ·  ✈ " .. Util.FormatNumber(item.Price) else "NEED ✈ " .. Util.FormatNumber(item.Price - (state.Credits or 0)) .. " MORE", if affordable then "gold" else "secondary", function()
			if affordable then
				Net.Event("ShopPurchase"):FireServer(item.Id)
			end
		end)
	end
	if item.Product then
		local id = state.Availability.Products[item.Product]
		if id then
			actionButton(actions, "BUY  ·  R$ " .. MonetizationConfig.Products[item.Product].PriceHint, "good", function()
				MarketplaceService:PromptProductPurchase(player, id)
			end)
		elseif not item.Price then
			actionButton(actions, "COMING SOON", "secondary", nil)
		end
	end
	if item.Pass and not item.Price then
		local id = state.Availability.Passes[item.Pass]
		if id then
			actionButton(actions, "INCLUDED WITH " .. string.upper(MonetizationConfig.GamePasses[item.Pass].Name), "good", function()
				MarketplaceService:PromptGamePassPurchase(player, id)
			end)
		end
	elseif item.Pass then
		UIKit.Text({ Text = "Also included with the " .. MonetizationConfig.GamePasses[item.Pass].Name, TextSize = 13, TextColor3 = C.SubText, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 8, Parent = detail })
	end
	if item.Unlock then
		local achievement = AchievementConfig.ById[item.Unlock]
		UIKit.Text({ Text = "🏆 Unlock by earning \"" .. (achievement and achievement.Name or item.Unlock) .. "\"", TextSize = 14, TextColor3 = C.Optional, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 9, Parent = detail })
	end
end

function refreshGrid()
	for _, child in grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for name, tab in tabs do
		tab.BackgroundColor3 = if name == category then C.Accent else C.PanelLight
	end
	creditsLabel.Text = "✈ " .. Util.FormatNumber(state.Credits or 0) .. " " .. EconomyConfig.CurrencyShort
	for index, item in itemsFor(category) do
		local card = UIKit.new("TextButton", {
			Name = item.Id,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = C.PanelLight,
			BackgroundTransparency = 0.2,
			Corner = 12,
			Stroke = { Color = ShopCatalog.Rarities[item.Rarity or "Common"] or C.Stroke, Thickness = if selected and selected.Id == item.Id then 3 else 1, Transparency = 0.2 },
			LayoutOrder = index,
			Parent = grid,
		})
		local tile = preview(card, item, 86)
		tile.AnchorPoint = Vector2.new(0.5, 0)
		tile.Position = UDim2.new(0.5, 0, 0, 10)
		UIKit.Text({ Text = item.Name, Font = F.Bold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(4, 100), Size = UDim2.new(1, -8, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd, Parent = card })
		local price, color = priceText(item)
		UIKit.Text({ Text = price, Font = F.Heading, TextSize = 13, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(4, 120), Size = UDim2.new(1, -8, 0, 16), Parent = card })
		card.Activated:Connect(function()
			showDetail(item)
			refreshGrid()
		end)
	end
	if selected then
		-- keep the detail pane in sync with ownership changes
		for _, item in itemsFor(category) do
			if item.Id == selected.Id then
				showDetail(item)
				return
			end
		end
	end
	showDetail(nil)
end

local function fetchState()
	local ok, result = pcall(function()
		return Net.Function("GetShopState"):InvokeServer()
	end)
	if ok and result then
		state = result
	end
end

function ShopController:Open()
	fetchState()
	refreshGrid()
	UIKit.OpenWindow(overlay)
end

function ShopController:Init()
	local gui = UIKit.Screen("ShopUI", 20)
	local root = UIKit.Root(gui)
	local content
	overlay, content = UIKit.Window(root, "DUTY FREE", UDim2.new(0.92, 0, 0.9, 0))
	creditsLabel = UIKit.Text({
		Text = "",
		Font = F.Heading,
		TextSize = 20,
		TextColor3 = C.Credits,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -80, 0, -52),
		Size = UDim2.fromOffset(260, 30),
		ZIndex = 23,
		Parent = content,
	})
	local tabBar = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, UIKit.TouchSize(44)), ZIndex = 22, Parent = content })
	UIKit.List(tabBar, 8, Enum.FillDirection.Horizontal)
	for index, name in ShopCatalog.Categories do
		local tab = UIKit.Button({
			Text = string.upper(name),
			Style = "secondary",
			Size = UDim2.new(0, 150, 1, 0),
			TextSize = 15,
			LayoutOrder = index,
			ZIndex = 23,
			Parent = tabBar,
			OnClick = function()
				category = name
				selected = nil
				refreshGrid()
			end,
		})
		tabs[name] = tab
	end
	local tabHeight = UIKit.TouchSize(44)
	grid = UIKit.Scroll({
		Position = UDim2.fromOffset(0, tabHeight + 12),
		Size = UDim2.new(0.66, -10, 1, -(tabHeight + 12)),
		ZIndex = 22,
		Parent = content,
	})
	UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(140, 144),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	UIKit.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), Parent = grid })
	detail = UIKit.Panel({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, tabHeight + 12),
		Size = UDim2.new(0.34, 0, 1, -(tabHeight + 12)),
		BackgroundColor3 = C.Background,
		Padding = { 14, 14, 14, 14 },
		ZIndex = 22,
		Parent = content,
	})
	UIKit.List(detail, 8, nil, Enum.HorizontalAlignment.Center)
end

function ShopController:Start()
	ClientState.ProfileChanged:Connect(function(profile)
		state.Owned = profile.Owned or state.Owned
		state.Equipped = profile.Equipped or state.Equipped
		state.Credits = profile.Credits or state.Credits
		state.Passes = profile.Passes or state.Passes
		if overlay.Visible then
			refreshGrid()
		end
	end)
	Net.Event("PurchaseResult").OnClientEvent:Connect(function()
		if overlay.Visible then
			task.delay(0.2, function()
				fetchState()
				refreshGrid()
			end)
		end
	end)
end

return ShopController
