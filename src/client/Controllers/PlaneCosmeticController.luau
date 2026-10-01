--[[
	PlaneCosmeticController
	Shows the local player's equipped plane skin, wing effect and engine trail on the aircraft
	exterior. Client-only and visual-only: the aircraft is shared, so every player sees their
	own look, and the decoration never collides, is never queried and changes no gameplay.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CosmeticBuilder = require(ReplicatedStorage.Shared.CosmeticBuilder)
local ShopCatalog = require(ReplicatedStorage.Shared.Config.ShopCatalog)
local ClientState = require(script.Parent.Parent.ClientState)

local PlaneCosmeticController = {}

local exterior: Instance? = nil
local state: { [string]: any } = {}
local applied = ""

local function equippedItem(slot: string)
	local profile = ClientState.Profile
	if not profile or not profile.Equipped then
		return nil
	end
	local id = profile.Equipped[slot] or ShopCatalog.DefaultEquipped[slot]
	local item = id and ShopCatalog.Get(id)
	if item and (item.Default or table.find(profile.Owned or {}, id)) then
		return item
	end
	return nil
end

local function refresh(force: boolean?)
	if not exterior or not exterior.Parent then
		return
	end
	local skin = equippedItem("PlaneSkin")
	local wing = equippedItem("WingEffect")
	local trail = equippedItem("PlaneTrail")
	local key = (skin and skin.Id or "-") .. "|" .. (wing and wing.Id or "-") .. "|" .. (trail and trail.Id or "-")
	if key == applied and not force then
		return
	end
	applied = key
	local ok, err = pcall(CosmeticBuilder.ApplyPlane, exterior, skin, wing, trail, state)
	if not ok then
		warn("[PlaneCosmetics] could not apply plane look:", err)
	end
end

local function attach(model: Instance)
	if model == exterior then
		return
	end
	exterior = model
	state = {}
	applied = ""
	refresh(true)
end

local function watchAirplane(airplane: Instance)
	local found = airplane:FindFirstChild("Exterior")
	if found then
		attach(found)
	end
	airplane.ChildAdded:Connect(function(child)
		if child.Name == "Exterior" then
			attach(child)
		end
	end)
end

local function watchWorld(world: Instance)
	local airplane = world:FindFirstChild("Airplane")
	if airplane then
		watchAirplane(airplane)
	end
	world.ChildAdded:Connect(function(child)
		if child.Name == "Airplane" then
			watchAirplane(child)
		end
	end)
end

function PlaneCosmeticController:Refresh()
	refresh(true)
end

function PlaneCosmeticController:Start()
	ClientState.ProfileChanged:Connect(function()
		refresh(false)
	end)
	-- the server replaces the baked world with a fresh copy at start-up, so keep watching
	local world = Workspace:FindFirstChild("World")
	if world then
		watchWorld(world)
	end
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "World" then
			watchWorld(child)
		end
	end)
end

return PlaneCosmeticController
