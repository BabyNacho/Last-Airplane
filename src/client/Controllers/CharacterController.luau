--[[
	CharacterController
	Local character presentation the server decides: turbulence stumbles, the unconscious pose
	(controls disabled until revived) and disabling the reset button (death is a round mechanic).
	The server remains authoritative over damage; this only moves the client-owned character.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Net = require(ReplicatedStorage.Shared.Net)
local ClientState = require(script.Parent.Parent.ClientState)
local Sfx = require(script.Parent.Parent.UI.Sfx)

local CharacterController = {}

local player = Players.LocalPlayer
local controls: any = nil
local downed = false

local function getControls()
	if controls then
		return controls
	end
	local ok, module = pcall(function()
		local playerModule = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
		return require(playerModule :: ModuleScript)
	end)
	if ok and module then
		controls = (module :: any):GetControls()
	end
	return controls
end

local function humanoid(): Humanoid?
	return player.Character and player.Character:FindFirstChildOfClass("Humanoid")
end

local function stumble(data)
	local hum = humanoid()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root or hum.Sit or downed then
		return
	end
	local strength = data.Strength or 1
	local direction = data.Direction or Vector3.new(1, 0, 0)
	if direction.Magnitude > 0 then
		direction = direction.Unit
	end
	hum:ChangeState(Enum.HumanoidStateType.FallingDown)
	root.AssemblyLinearVelocity += direction * (8 + strength * 7) + Vector3.new(0, 6 + strength * 3, 0)
	Sfx.Play("Impact", root.Position, 0.3)
	task.delay(0.9 + strength * 0.25, function()
		local current = humanoid()
		if current and not downed then
			current:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

local function setDowned(value: boolean)
	if downed == value then
		return
	end
	downed = value
	local hum = humanoid()
	local c = getControls()
	if value then
		if c then
			c:Disable()
		end
		if hum then
			hum.Sit = false
			hum.PlatformStand = true
		end
	else
		if hum then
			hum.PlatformStand = false
			hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
		if c then
			c:Enable()
		end
	end
end

-- VIP lounge door: passable locally for VIP pass holders (cosmetic area only).
local function applyVipDoors()
	local vip = player:GetAttribute("VIP") == true
	for _, door in CollectionService:GetTagged("VIPDoor") do
		if door:IsA("BasePart") then
			door.CanCollide = not vip
			door.Transparency = if vip then 0.7 else 0.35
		end
	end
end

function CharacterController:Start()
	applyVipDoors()
	player:GetAttributeChangedSignal("VIP"):Connect(applyVipDoors)
	CollectionService:GetInstanceAddedSignal("VIPDoor"):Connect(applyVipDoors)
	task.spawn(function()
		for _ = 1, 10 do
			local ok = pcall(StarterGui.SetCore, StarterGui, "ResetButtonCallback", false)
			if ok then
				break
			end
			task.wait(1)
		end
	end)
	Net.Event("Stumble").OnClientEvent:Connect(stumble)
	ClientState.ConditionChanged:Connect(function(condition)
		setDowned(condition.Tracked == true and condition.State == "Unconscious")
	end)
	player.CharacterAdded:Connect(function()
		downed = false
		local c = getControls()
		if c then
			c:Enable()
		end
	end)
end

return CharacterController
