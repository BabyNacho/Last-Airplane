--[[
	CameraController
	The single owner of the local camera. Roblox's default camera (CameraType Custom, driven by
	the PlayerModule) always does the actual following; this controller only layers on top of it:
	  * flight effects - shake from EffectsController, plus the attitude tilt while this player is
	    flying the aircraft. Applied after the Roblox camera each frame (LF_CameraPost) and removed
	    again before it runs next frame (LF_CameraPre), so nothing accumulates into the view;
	  * recenter - a short orbit tween back to an upright, eye-level view behind the camera
	    subject, after which the Roblox camera simply continues from that orientation. Runs when
	    flight control ends and from the RECENTER button (V / right stick click);
	  * zoom limits (tight inside the aircraft, wider in the lobby) and spectating: players in
	    the lobby during a flight - or who didn't survive - can watch the players still aboard.
	No other script writes Camera.CFrame, CameraType or CameraSubject.
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
local controllers: any
local spectating = false
local targetIndex = 1
local panel: Frame
local nameLabel: TextLabel
local recenterButton: TextButton

local PRE_STEP = "LF_CameraPre"
local POST_STEP = "LF_CameraPost"

-- camera state (all of it lives here)
local piloting = false
local tiltWeight = 0
local recenter: { Started: number, Duration: number, Yaw: number, Pitch: number }? = nil
local effectCamera: Camera? = nil
local effectBase: CFrame? = nil -- camera CFrame before our layer was applied this frame
local effectApplied: CFrame? = nil -- camera CFrame after it was applied
local characterConnections: { RBXScriptConnection } = {}

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

---------------------------------------------------------------- effect layer + recenter

local function sameCFrame(a: CFrame, b: CFrame): boolean
	return (a.Position - b.Position).Magnitude < 1e-3 and a.LookVector:Dot(b.LookVector) > 0.99999 and a.UpVector:Dot(b.UpVector) > 0.99999
end

-- Removes last frame's effect offset so the Roblox camera reads (and keeps) its own orientation.
local function stripEffects()
	local camera = Workspace.CurrentCamera
	if camera and camera == effectCamera and effectBase and effectApplied and sameCFrame(camera.CFrame, effectApplied) then
		camera.CFrame = effectBase
	end
	effectCamera, effectBase, effectApplied = nil, nil, nil
end

local function yawPitchOf(look: Vector3): (number, number)
	return math.atan2(-look.X, -look.Z), math.asin(math.clamp(look.Y, -1, 1))
end

local function lookFrom(yaw: number, pitch: number): Vector3
	return Vector3.new(-math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch))
end

local function subjectHeading(camera: Camera): Vector3?
	local subject = camera.CameraSubject
	local root: Instance? = nil
	if subject and subject:IsA("Humanoid") then
		root = subject.Parent and subject.Parent:FindFirstChild("HumanoidRootPart")
	elseif subject and subject:IsA("BasePart") then
		root = subject
	end
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local flat = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if flat.Magnitude < 0.1 then
		return nil
	end
	return flat.Unit
end

-- Upright camera CFrame at `position` looking along `look` (same as CFrame.lookAt, built explicitly).
local function lookCFrame(position: Vector3, look: Vector3): CFrame
	local right = look:Cross(Vector3.yAxis)
	if right.Magnitude < 1e-4 then
		right = Vector3.xAxis
	end
	right = right.Unit
	return CFrame.fromMatrix(position, right, right:Cross(look).Unit)
end

local function ease(alpha: number): number
	return alpha * alpha * (3 - 2 * alpha) -- smoothstep: gentle start and settle
end

-- Orbits the camera around the Roblox camera's own focus point at the Roblox camera's own
-- distance, only changing the direction it looks from. The Roblox camera derives its next frame
-- from Camera.CFrame's look direction, so when the tween ends it carries on seamlessly.
local function stepRecenter(camera: Camera)
	local state = recenter :: any
	local alpha = math.clamp((os.clock() - state.Started) / state.Duration, 0, 1)
	local e = ease(alpha)
	local heading = subjectHeading(camera)
	local goalYaw = if heading then (yawPitchOf(heading)) else state.Yaw
	local goalPitch = math.rad(GameConfig.Camera.RecenterPitch)
	local deltaYaw = (goalYaw - state.Yaw + math.pi) % (2 * math.pi) - math.pi
	local look = lookFrom(state.Yaw + deltaYaw * e, state.Pitch + (goalPitch - state.Pitch) * e)
	local pivot = camera.Focus.Position
	local distance = (camera.CFrame.Position - pivot).Magnitude
	if distance < 0.6 then
		local position = camera.CFrame.Position -- first person: turn the head only
		camera.CFrame = lookCFrame(position, look)
	else
		camera.CFrame = lookCFrame(pivot - look * distance, look)
	end
	if alpha >= 1 then
		recenter = nil
	end
end

local function preStep()
	stripEffects()
end

local function postStep(dt: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local goal = if piloting then 1 else 0
	local rate = dt / math.max(GameConfig.Camera.FlightTiltBlendTime, 0.01)
	tiltWeight = if tiltWeight < goal then math.min(goal, tiltWeight + rate) else math.max(goal, tiltWeight - rate)
	if recenter then
		stepRecenter(camera)
	end
	local offset = controllers.EffectsController:CameraOffset(camera, tiltWeight, dt)
	if offset ~= CFrame.identity then
		local base = camera.CFrame
		local applied = base * offset
		camera.CFrame = applied
		effectCamera, effectBase, effectApplied = camera, base, applied
	end
end

-- Drops every bit of camera state and leaves the Roblox camera in charge.
local function clearState()
	stripEffects()
	recenter = nil
	piloting = false
	tiltWeight = 0
	local camera = Workspace.CurrentCamera
	if camera and camera.CameraType == Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Custom
	end
end

function CameraController:Recenter()
	local camera = Workspace.CurrentCamera
	if not camera or camera.CameraType == Enum.CameraType.Scriptable then
		return
	end
	stripEffects()
	local yaw, pitch = yawPitchOf(camera.CFrame.LookVector)
	recenter = { Started = os.clock(), Duration = GameConfig.Camera.RecenterTime, Yaw = yaw, Pitch = pitch }
end

function CameraController:IsRecentering(): boolean
	return recenter ~= nil
end

function CameraController:GetTiltWeight(): number
	return tiltWeight
end

-- Called by CockpitController when manual flight control starts / ends for this player.
function CameraController:SetPiloting(active: boolean)
	if active == piloting then
		return
	end
	piloting = active
	if active then
		recenter = nil -- the flight camera takes over; tilt blends in over FlightTiltBlendTime
		if spectating then
			self:StopSpectate()
		end
	else
		self:Recenter() -- tilt blends out while the view glides back to eye level
	end
end

function CameraController:IsPiloting(): boolean
	return piloting
end

local function refreshButton()
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	recenterButton.Visible = spectating or (humanoid ~= nil and humanoid.Health > 0)
end

local function watchCharacter(character: Model)
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	clearState()
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") or player.Character ~= character then
		return
	end
	table.insert(characterConnections, humanoid.Died:Connect(function()
		clearState() -- the Roblox camera handles the death view
		refreshButton()
	end))
	table.insert(characterConnections, humanoid.Seated:Connect(function(seated)
		if not seated and piloting then
			CameraController:SetPiloting(false) -- left (or lost) the pilot seat
		end
	end))
	if not spectating then
		resetCamera()
	end
	refreshButton()
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
	recenter = nil
	spectating = true
	panel.Visible = true
	focus()
	refreshButton()
end

function CameraController:StopSpectate()
	recenter = nil
	spectating = false
	panel.Visible = false
	resetCamera()
	refreshButton()
end

function CameraController:ToggleSpectate()
	if spectating then
		self:StopSpectate()
	else
		self:StartSpectate()
	end
end

function CameraController:Init(all)
	controllers = all
	local gui = UIKit.Screen("SpectateUI", 4)
	local root = UIKit.Root(gui)
	-- RECENTER: bottom right; on touch devices it sits left of the jump button
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	recenterButton = UIKit.Button({
		Name = "Recenter",
		Text = "⟲ RECENTER",
		Style = "ghost",
		TextSize = 14,
		AnchorPoint = Vector2.new(1, 1),
		Size = UDim2.fromOffset(128, UIKit.TouchSize(44)),
		Position = if touch then UDim2.new(1, -190, 1, -20) else UDim2.new(1, -12, 1, -12),
		Visible = false,
		Parent = root,
		OnClick = function()
			CameraController:Recenter()
		end,
	})
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
			clearState() -- round over / aircraft reset: release everything back to Roblox
			if spectating then
				self:StopSpectate()
			end
		end
	end)
	player:GetAttributeChangedSignal("InRound"):Connect(function()
		if not player:GetAttribute("InRound") then
			clearState()
		elseif spectating then
			self:StopSpectate()
		end
	end)
	player.CharacterAdded:Connect(function(character)
		if spectating then
			task.defer(focus)
		end
		task.spawn(watchCharacter, character)
	end)
	player.CharacterRemoving:Connect(function()
		clearState()
		refreshButton()
	end)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	RunService:BindToRenderStep(PRE_STEP, Enum.RenderPriority.Camera.Value - 1, preStep)
	RunService:BindToRenderStep(POST_STEP, Enum.RenderPriority.Camera.Value + 1, postStep)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.V or input.KeyCode == Enum.KeyCode.ButtonR3 then
			self:Recenter()
			return
		end
		if not spectating then
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
