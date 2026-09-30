--[[
	CabinService
	Round-scoped cabin interactions shared by every disaster: cabin doors, lavatory doors,
	emergency exits, seatbelts (seat occupancy), overhead bins and galley carts.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enums = require(ReplicatedStorage.Shared.Enums)
local Registry = require(script.Parent.Parent.Registry)

local CabinService = {}

local seatedPlayers: { [Player]: Seat } = {}
local binHandles: { [BasePart]: any } = {}
local cartHandles: { [BasePart]: any } = {}

local DOOR_LABELS = {
	FirstClassCurtain = "CABIN DIVIDER",
	AftCabinDoor = "AFT CABIN DOOR",
	ServiceDoor = "SERVICE BAY DOOR",
}

function CabinService:IsBuckled(player: Player): boolean
	return seatedPlayers[player] ~= nil
end

function CabinService:SeatedParticipants(ctx): { Player }
	local list = {}
	for _, player in ctx:AlivePlayers() do
		if seatedPlayers[player] then
			table.insert(list, player)
		end
	end
	return list
end

local function refreshSeatObjective(ctx)
	if ctx.Phase == Enums.Phase.Boarding and Registry.ObjectiveService:IsActive("FindSeat") then
		local count = 0
		for _, player in ctx:Players() do
			local seat = seatedPlayers[player]
			if seat then
				count += 1
			end
		end
		Registry.ObjectiveService:SetProgress("FindSeat", count)
	end
end

local function watchSeats(ctx)
	for _, seat in CollectionService:GetTagged("AirplaneSeat") do
		ctx:Give(seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			-- rebuild occupancy for this seat
			for player, current in seatedPlayers do
				if current == seat then
					seatedPlayers[player] = nil
					player:SetAttribute("Buckled", nil)
				end
			end
			local occupant = seat.Occupant
			if occupant then
				local player = game:GetService("Players"):GetPlayerFromCharacter(occupant.Parent)
				if player and ctx:IsParticipant(player) then
					seatedPlayers[player] = seat
					player:SetAttribute("Buckled", true)
					local record = ctx:Record(player)
					if record and record.Seat == seat:GetAttribute("SeatLabel") and not ctx.Flags["SeatBonus_" .. player.UserId] then
						ctx.Flags["SeatBonus_" .. player.UserId] = true
						Registry.EffectsService:Notify("Seat " .. record.Seat .. " - welcome aboard!", "good", player)
					end
				end
			end
			refreshSeatObjective(ctx)
		end))
	end
end

---------------------------------------------------------------- doors

local function setupDoors(ctx)
	local map = Registry.MapService
	for id, label in DOOR_LABELS do
		local door = map.Points.DividerDoors[id]
		if door then
			local handle
			handle = Registry.InteractionService:Add(door, {
				Action = if door:GetAttribute("Open") then "CLOSE" else "OPEN",
				Object = label,
				Hold = 0,
				Range = 7,
				Round = ctx,
				Cooldown = 0.8,
				OnTrigger = function(player)
					local open = not map:IsDividerOpen(id)
					map:SetDividerOpen(id, open)
					handle:SetText(if open then "CLOSE" else "OPEN")
					Registry.EffectsService:Sound("Door", door.Position)
					if Registry.FireSystem then
						Registry.FireSystem:OnDoorChanged(id, open, player)
					end
				end,
			})
		end
	end
	for _, info in map.Points.Lavatories do
		local door = info.Door
		local handle
		handle = Registry.InteractionService:Add(door, {
			Action = "OPEN",
			Object = "LAVATORY",
			Range = 6,
			Round = ctx,
			Cooldown = 0.8,
			OnTrigger = function()
				local open = not door:GetAttribute("Open")
				map:SetLavDoorOpen(door, open)
				handle:SetText(if open then "CLOSE" else "OPEN")
				Registry.EffectsService:Sound("Door", door.Position)
			end,
		})
	end
	for _, exit in map.Points.Exits do
		Registry.InteractionService:Add(exit.Door, {
			Action = "OPEN",
			Object = "EMERGENCY EXIT " .. exit.Id,
			Hold = 1.6,
			Range = 7,
			Kind = "danger",
			Round = ctx,
			Condition = function()
				if exit.Door:GetAttribute("Open") then
					return false, nil
				end
				if ctx.Phase ~= Enums.Phase.Evacuation then
					return false, "The door won't budge - cabin pressure is holding it shut."
				end
				return true
			end,
			OnTrigger = function(player)
				Registry.LandingService:OpenExit(ctx, exit, player)
			end,
		})
	end
end

---------------------------------------------------------------- bins & carts

function CabinService:OpenBin(ctx, lid: BasePart, spill: boolean?)
	if lid:GetAttribute("Open") then
		return
	end
	local map = Registry.MapService
	map:SetBinOpen(lid, true)
	if spill then
		local side = lid:GetAttribute("Side") or 1
		for _ = 1, ctx.Rng:NextInteger(1, 2) do
			map:SpawnLuggage(lid.Position + Vector3.new(ctx.Rng:NextNumber(-1, 1), -0.5, -side * 1.2), Vector3.new(0, -5, -side * ctx.Rng:NextNumber(8, 16)))
		end
	end
	if not binHandles[lid] then
		binHandles[lid] = Registry.InteractionService:Add(lid, {
			Action = "CLOSE",
			Object = "OVERHEAD BIN",
			Range = 7,
			Round = ctx,
			OnTrigger = function(player)
				self:CloseBin(ctx, lid, player)
			end,
		})
	end
	binHandles[lid]:SetEnabled(true)
end

function CabinService:CloseBin(_ctx, lid: BasePart, player: Player?)
	if not lid:GetAttribute("Open") then
		return
	end
	Registry.MapService:SetBinOpen(lid, false)
	if binHandles[lid] then
		binHandles[lid]:SetEnabled(false)
	end
	Registry.EffectsService:Sound("Door", lid.Position)
	if player and Registry.ObjectiveService:IsActive("CloseBins") then
		Registry.ObjectiveService:Progress("CloseBins", 1, player)
	end
end

function CabinService:OpenBinCount(): number
	local count = 0
	for _, lid in Registry.MapService.Points.Bins do
		if lid:GetAttribute("Open") then
			count += 1
		end
	end
	return count
end

function CabinService:ReleaseCart(ctx, cart: BasePart)
	if not cart:GetAttribute("Secured") then
		return
	end
	Registry.MapService:SetCartLoose(cart, true)
	cart.AssemblyLinearVelocity = Vector3.new(ctx.Rng:NextNumber(10, 22), 0, 0)
	if not cartHandles[cart] then
		cartHandles[cart] = Registry.InteractionService:Add(cart, {
			Action = "SECURE",
			Object = "GALLEY CART",
			Hold = 1.2,
			Range = 7,
			Kind = "objective",
			Round = ctx,
			OnTrigger = function(player)
				Registry.MapService:SetCartLoose(cart, false)
				cartHandles[cart]:SetEnabled(false)
				Registry.EffectsService:Sound("Equip", cart.Position)
				if Registry.ObjectiveService:IsActive("SecureCarts") then
					Registry.ObjectiveService:Progress("SecureCarts", 1, player)
				end
			end,
		})
	end
	cartHandles[cart]:SetEnabled(true)
	-- a runaway cart hurts whoever it slams into
	local hitCooldown: { [Player]: number } = {}
	ctx:Give(cart.Touched:Connect(function(hit)
		if cart:GetAttribute("Secured") or cart.AssemblyLinearVelocity.Magnitude < 7 then
			return
		end
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and game:GetService("Players"):GetPlayerFromCharacter(character)
		if player and ctx:IsParticipant(player) and os.clock() - (hitCooldown[player] or 0) > 1.5 then
			hitCooldown[player] = os.clock()
			Registry.ConditionService:Damage(player, 12, "Hit by a runaway cart")
		end
	end))
end

---------------------------------------------------------------- lifecycle

function CabinService:OnRoundStart(ctx)
	table.clear(seatedPlayers)
	table.clear(binHandles)
	table.clear(cartHandles)
	watchSeats(ctx)
	setupDoors(ctx)
end

function CabinService:OnPhase(ctx, phase: string)
	local flight = Registry.FlightService
	if phase == Enums.Phase.Boarding then
		flight:Set("SeatbeltSign", true)
	elseif phase == Enums.Phase.Flight then
		ctx:Delay(12, function()
			if ctx.Phase == Enums.Phase.Flight and not ctx.Flags.KeepSeatbeltSign then
				flight:Set("SeatbeltSign", false)
				Registry.EffectsService:Sound("SeatbeltChime")
				Registry.EffectsService:Announce("Captain", "Good day, everyone. We've reached cruising altitude - feel free to move about the cabin.")
			end
		end)
	elseif phase == Enums.Phase.FinalEvent then
		flight:Set("SeatbeltSign", true)
	end
end

function CabinService:OnRoundEnd()
	for player in seatedPlayers do
		if player.Parent then
			player:SetAttribute("Buckled", nil)
		end
	end
	table.clear(seatedPlayers)
	table.clear(binHandles)
	table.clear(cartHandles)
end

return CabinService
