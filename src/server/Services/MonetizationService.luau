--[[
	MonetizationService
	Roblox-official purchase flow only (MarketplaceService):
	  * Game Passes: ownership checked with UserOwnsGamePassAsync (cached) and refreshed when a
	    purchase finishes in-game. Pass perks are cosmetic / convenience only.
	  * Developer Products: ProcessReceipt is idempotent - every receipt id is stored in the
	    player's profile and the grant is only acknowledged after the profile saves successfully.
	    Purchases are never granted into a temporary (unsaved) profile.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonetizationConfig = require(ReplicatedStorage.Shared.Config.MonetizationConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Registry = require(script.Parent.Parent.Registry)

local MonetizationService = {}

local passCache: { [Player]: { [string]: boolean } } = {}

local function checkPass(player: Player, key: string): boolean
	local pass = MonetizationConfig.GamePasses[key]
	if not pass or pass.Id == 0 then
		return false
	end
	local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.Id)
	return ok and owns == true
end

local function refreshPasses(player: Player)
	local cache = {}
	for key in MonetizationConfig.GamePasses do
		cache[key] = checkPass(player, key)
	end
	passCache[player] = cache
	player:SetAttribute("VIP", cache.VIP == true)
	return cache
end

function MonetizationService:PassesFor(player: Player): { [string]: boolean }
	return passCache[player] or {}
end

function MonetizationService:OwnsPass(player: Player, key: string): boolean
	local cache = passCache[player]
	return cache ~= nil and cache[key] == true
end

function MonetizationService:IsVIP(player: Player): boolean
	return self:OwnsPass(player, "VIP")
end

-- Items granted by owned passes (not stored as purchases - the pass is the source of truth).
function MonetizationService:PassGrantedItems(player: Player): { [string]: boolean }
	local granted = {}
	for key, pass in MonetizationConfig.GamePasses do
		if self:OwnsPass(player, key) then
			for _, itemId in pass.Grants or {} do
				granted[itemId] = true
			end
		end
	end
	return granted
end

-- Which Robux products are actually configured (id ~= 0). The client only offers these.
function MonetizationService:Availability()
	local products, passes = {}, {}
	for key, product in MonetizationConfig.Products do
		products[key] = if product.Id ~= 0 then product.Id else nil
	end
	for key, pass in MonetizationConfig.GamePasses do
		passes[key] = if pass.Id ~= 0 then pass.Id else nil
	end
	return { Products = products, Passes = passes }
end

local function grantProduct(player: Player, key: string)
	local product = MonetizationConfig.Products[key]
	if product.Credits then
		Registry.DataService:AddCredits(player, product.Credits, "purchase")
	end
	for _, itemId in product.GrantItems or {} do
		Registry.DataService:Grant(player, itemId)
	end
end

local function processReceipt(receipt): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local key = MonetizationConfig.ProductKeyById(receipt.ProductId)
	if not key then
		warn("[Monetization] unknown product id", receipt.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = Registry.DataService
	if not data:Get(player) or data:IsTemporary(player) then
		-- never grant into a profile we can't save; Roblox will retry later
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local receiptId = tostring(receipt.PurchaseId)
	if data:HasReceipt(player, receiptId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	grantProduct(player, key)
	data:AddReceipt(player, receiptId)
	if not data:Save(player, false) then
		-- the grant is in memory with the receipt recorded; acknowledge only once it persists
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local product = MonetizationConfig.Products[key]
	Net.Event("PurchaseResult"):FireClient(player, { Ok = true, Message = "Purchased " .. product.Name .. "! Thank you for supporting the game." })
	Registry.EffectsService:Sound("Purchase", nil, player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationService:Start()
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		local key = MonetizationConfig.PassKeyById(passId)
		if key then
			passCache[player] = passCache[player] or {}
			passCache[player][key] = true
			if key == "VIP" then
				player:SetAttribute("VIP", true)
			end
			Registry.DataService:Push(player)
			Registry.CosmeticService:Apply(player)
			Net.Event("PurchaseResult"):FireClient(player, { Ok = true, Message = MonetizationConfig.GamePasses[key].Name .. " unlocked! Thank you!" })
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		refreshPasses(player)
		Registry.DataService:Push(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(refreshPasses, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		passCache[player] = nil
	end)
end

return MonetizationService
