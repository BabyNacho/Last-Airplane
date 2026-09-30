--[[
	ShopService
	Flight Credit purchases and equipping. Everything is validated server-side:
	item exists, is sold for credits, isn't already owned, player can afford it, slot matches.
	Robux items are never purchasable with credits (and vice versa).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local ShopCatalog = require(ReplicatedStorage.Shared.Config.ShopCatalog)
local RateLimiter = require(script.Parent.Parent.RateLimiter)
local Registry = require(script.Parent.Parent.Registry)

local ShopService = {}

function ShopService:Owns(player: Player, itemId: string): boolean
	local item = ShopCatalog.Get(itemId)
	if not item then
		return false
	end
	if item.Default or Registry.DataService:Owns(player, itemId) then
		return true
	end
	return Registry.MonetizationService:PassGrantedItems(player)[itemId] == true
end

local function result(player: Player, ok: boolean, message: string, itemId: string?)
	Net.Event("PurchaseResult"):FireClient(player, { Ok = ok, Message = message, ItemId = itemId })
end

local function onPurchase(player: Player, itemId: any)
	if type(itemId) ~= "string" or #itemId > 64 then
		return
	end
	if not RateLimiter.Allow(player, "ShopPurchase") then
		return
	end
	local item = ShopCatalog.Get(itemId)
	if not item then
		return result(player, false, "That item doesn't exist.")
	end
	if not item.Price or item.Price <= 0 then
		return result(player, false, "This item can't be bought with Flight Credits.")
	end
	if ShopService:Owns(player, itemId) then
		return result(player, false, "You already own " .. item.Name .. ".")
	end
	if item.Type == "Bundle" then
		local allOwned = true
		for _, inner in item.Data.Items do
			if not ShopService:Owns(player, inner) then
				allOwned = false
			end
		end
		if allOwned then
			return result(player, false, "You already own everything in this bundle.")
		end
	end
	if not Registry.DataService:SpendCredits(player, item.Price) then
		return result(player, false, "Not enough Flight Credits.")
	end
	Registry.DataService:Grant(player, itemId)
	if item.Type == "Bundle" then
		for _, inner in item.Data.Items do
			Registry.DataService:Grant(player, inner)
		end
	end
	Registry.EffectsService:Sound("Purchase", nil, player)
	result(player, true, "Purchased " .. item.Name .. "!", itemId)
end

local function onEquip(player: Player, slot: any, itemId: any)
	if type(slot) ~= "string" or (itemId ~= nil and type(itemId) ~= "string") then
		return
	end
	if not RateLimiter.Allow(player, "Equip") then
		return
	end
	if not table.find(ShopCatalog.Slots, slot) then
		return
	end
	if itemId == nil then
		if slot == "Title" or slot == "Theme" then
			itemId = ShopCatalog.DefaultEquipped[slot]
		end
		Registry.DataService:SetEquipped(player, slot, itemId)
		Registry.CosmeticService:Apply(player)
		return
	end
	local item = ShopCatalog.Get(itemId)
	if not item or item.Slot ~= slot or not ShopService:Owns(player, itemId) then
		return
	end
	Registry.DataService:SetEquipped(player, slot, itemId)
	Registry.CosmeticService:Apply(player)
	Registry.EffectsService:Sound("Equip", nil, player)
end

function ShopService:State(player: Player)
	local owned = {}
	for _, item in ShopCatalog.Items do
		if self:Owns(player, item.Id) then
			table.insert(owned, item.Id)
		end
	end
	local profile = Registry.DataService:Get(player)
	return {
		Owned = owned,
		Equipped = profile and profile.Equipped or {},
		Credits = profile and profile.Credits or 0,
		Availability = Registry.MonetizationService:Availability(),
		Passes = Registry.MonetizationService:PassesFor(player),
	}
end

function ShopService:Start()
	Net.Event("ShopPurchase").OnServerEvent:Connect(onPurchase)
	Net.Event("Equip").OnServerEvent:Connect(onEquip)
	Net.Function("GetShopState").OnServerInvoke = function(player)
		if not RateLimiter.Allow(player, "GetProfile") then
			return nil
		end
		return self:State(player)
	end
end

return ShopService
