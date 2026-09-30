--[[
	CameraController
	Camera zoom limits (tight inside the aircraft, wider in the lobby) and spectating: players in
	the lobby during a flight - or who didn't survive - can watch the players still aboard.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MapConfig = require(ReplicatedStorage.Shared.Config.MapConfig)
local ClientState = require(script.Parent.Parent.ClientState)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local CameraController = {}

local player = Players.LocalPlayer
local spectating = false
local targetIndex = 1
local panel: Frame
local nameLabel: TextLabel

local function candidates(): { Player }
	local list = {}
	for _, other in Players:GetPlayers() do
		if other ~= player and other:GetAttribute("InRound") and other:GetAttribute("Condition") ~= "Dead" then
			local humanoid = other.Character and other.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				table.insert(list, other)
			end
		end
	end
	return list
end

local function resetCamera()
	local camera = Workspace.CurrentCamera
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if camera and humanoid then
		camera.CameraSubject = humanoid
	end
end

local function focus()
	local list = candidates()
	if #list == 0 then
		CameraController:StopSpectate()
		return
	end
	targetIndex = ((targetIndex - 1) % #list) + 1
	local target = list[targetIndex]
	local humanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		Workspace.CurrentCamera.CameraSubject = humanoid
		nameLabel.Text = "SPECTATING  " .. target.DisplayName .. "  (" .. string.upper(target:GetAttribute("Condition") or "Healthy") .. ")"
	end
end

function CameraController:StartSpectate()
	if #candidates() == 0 then
		return
	end
	spectating = true
	panel.Visible = true
	focus()
end

function CameraController:StopSpectate()
	spectating = false
	panel.Visible = false
	resetCamera()
end

function CameraController:ToggleSpectate()
	if spectating then
		self:StopSpectate()
	else
		self:StartSpectate()
	end
end

function CameraController:Init()
	local gui = UIKit.Screen("SpectateUI", 4)
	local root = UIKit.Root(gui)
	panel = UIKit.Panel({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -130),
		Size = UDim2.fromOffset(520, 64),
		Visible = false,
		Parent = root,
	})
	local size = UIKit.TouchSize(48)
	UIKit.Button({
		Text = "◀",
		Style = "secondary",
		Size = UDim2.fromOffset(size, size),
		Position = UDim2.new(0, 8, 0.5, -size / 2),
		Parent = panel,
		OnClick = function()
			targetIndex -= 1
			focus()
		end,
	})
	UIKit.Button({
		Text = "▶",
		Style = "secondary",
		Size = UDim2.fromOffset(size, size),
		Position = UDim2.new(1, -size - 8 - size - 8, 0.5, -size / 2),
		Parent = panel,
		OnClick = function()
			targetIndex += 1
			focus()
		end,
	})
	UIKit.Button({
		Text = "✕",
		Style = "danger",
		Size = UDim2.fromOffset(size, size),
		Position = UDim2.new(1, -size - 8, 0.5, -size / 2),
		Parent = panel,
		OnClick = function()
			CameraController:StopSpectate()
		end,
	})
	nameLabel = UIKit.Text({
		Text = "",
		Font = UIKit.Fonts.Bold,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, size + 16, 0, 0),
		Size = UDim2.new(1, -(size * 3 + 48), 1, 0),
		Parent = panel,
	})
end

function CameraController:Start()
	ClientState.PhaseChanged:Connect(function(phase)
		if phase == "Results" or phase == "Lobby" then
			if spectating then
				self:StopSpectate()
			end
		end
	end)
	player:GetAttributeChangedSignal("InRound"):Connect(function()
		if player:GetAttribute("InRound") and spectating then
			self:StopSpectate()
		end
	end)
	player.CharacterAdded:Connect(function()
		if spectating then
			task.defer(focus)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not spectating then
			return
		end
		if input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.ButtonL1 then
			targetIndex -= 1
			focus()
		elseif input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.ButtonR1 then
			targetIndex += 1
			focus()
		end
	end)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.5 then
			return
		end
		accumulator = 0
		local camera = Workspace.CurrentCamera
		local inPlane = camera and MapConfig.IsInsidePlane(camera.Focus.Position)
		local maxZoom = if inPlane then GameConfig.Camera.FlightMaxZoom else GameConfig.Camera.LobbyMaxZoom
		if player.CameraMaxZoomDistance ~= maxZoom then
			player.CameraMaxZoomDistance = maxZoom
		end
		if spectating then
			local subject = camera and camera.CameraSubject
			local owner = subject and subject:IsA("Humanoid") and Players:GetPlayerFromCharacter(subject.Parent)
			if not owner or owner:GetAttribute("Condition") == "Dead" or not owner:GetAttribute("InRound") then
				focus()
			end
		end
	end)
end

return CameraController
