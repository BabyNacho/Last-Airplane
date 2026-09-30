--[[
	CockpitController
	Manual flight instrument shown while the local player sits in a pilot seat and the server
	has enabled manual control. The server simulates the aircraft; the client only sends stick
	input: W/Up = nose down, S/Down = nose up, gamepad left stick, or the on-screen buttons.
]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local CockpitController = {}

local controllers: any

local C = UIKit.Colors
local F = UIKit.Fonts

local panel: Frame
local marker: Frame
local band: Frame
local hint: TextLabel
local modeLabel: TextLabel
local altLabel: TextLabel
local lastState: any = nil
local lastReceived = 0
local keyInput = 0
local touchInput = 0
local stickInput = 0
local lastSent = 0
local lastSentValue = 0

local function build(root: Frame)
	panel = UIKit.Panel({
		Name = "ManualFlight",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -24, 0.55, 0),
		Size = UDim2.fromOffset(250, 380),
		Visible = false,
		Padding = { 12, 12, 12, 12 },
		Parent = root,
	})
	modeLabel = UIKit.Text({ Text = "MANUAL CONTROL", Font = F.Heading, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 22), Parent = panel })
	UIKit.Accent(modeLabel, "TextColor3")
	altLabel = UIKit.Text({ Text = "", Font = F.Mono, TextSize = 14, TextColor3 = C.SubText, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 16), Parent = panel })
	local gauge = UIKit.new("Frame", {
		Name = "Gauge",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 48),
		Size = UDim2.fromOffset(90, 220),
		BackgroundColor3 = Color3.fromRGB(12, 16, 26),
		Corner = 10,
		Stroke = { Color = C.Stroke },
		ClipsDescendants = true,
		Parent = panel,
	})
	-- sky / ground halves
	UIKit.new("Frame", { Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = Color3.fromRGB(40, 90, 160), BackgroundTransparency = 0.4, Parent = gauge })
	UIKit.new("Frame", { Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = Color3.fromRGB(120, 80, 40), BackgroundTransparency = 0.4, Parent = gauge })
	band = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0.22, 0),
		BackgroundColor3 = C.Good,
		BackgroundTransparency = 0.6,
		Parent = gauge,
	})
	marker = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -10, 0, 8),
		BackgroundColor3 = Color3.fromRGB(255, 230, 60),
		Corner = 4,
		Parent = gauge,
	})
	hint = UIKit.Text({ Text = "", Font = F.Bold, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 274), Size = UDim2.new(1, 0, 0, 20), Parent = panel })
	local buttonHeight = UIKit.TouchSize(52)
	local function stickButton(text: string, value: number, y: number)
		local button = UIKit.Button({
			Text = text,
			Style = "secondary",
			Size = UDim2.new(0.48, 0, 0, buttonHeight),
			Position = UDim2.new(if value < 0 then 0 else 0.52, 0, 0, y),
			TextSize = 15,
			Parent = panel,
		})
		button.MouseButton1Down:Connect(function()
			touchInput = value
		end)
		button.MouseButton1Up:Connect(function()
			if touchInput == value then
				touchInput = 0
			end
		end)
		button.MouseLeave:Connect(function()
			if touchInput == value then
				touchInput = 0
			end
		end)
	end
	stickButton("▼ NOSE DOWN", -1, 300)
	stickButton("▲ NOSE UP", 1, 300)
end

local function currentInput(): number
	if touchInput ~= 0 then
		return touchInput
	end
	if keyInput ~= 0 then
		return keyInput
	end
	return stickInput
end

local function bindKeys(enabled: boolean)
	if enabled then
		ContextActionService:BindAction("LF_PitchDown", function(_, state)
			keyInput = if state == Enum.UserInputState.Begin then -1 elseif keyInput == -1 then 0 else keyInput
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.W, Enum.KeyCode.Up)
		ContextActionService:BindAction("LF_PitchUp", function(_, state)
			keyInput = if state == Enum.UserInputState.Begin then 1 elseif keyInput == 1 then 0 else keyInput
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.S, Enum.KeyCode.Down)
	else
		ContextActionService:UnbindAction("LF_PitchDown")
		ContextActionService:UnbindAction("LF_PitchUp")
		keyInput = 0
	end
end

function CockpitController:Init(all)
	controllers = all
	local gui = UIKit.Screen("CockpitUI", 6)
	build(UIKit.Root(gui))
end

function CockpitController:Start()
	local visible = false
	Net.Event("ManualFlight").OnClientEvent:Connect(function(state)
		lastState = state
		lastReceived = os.clock()
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Thumbstick1 and visible then
			local y = input.Position.Y
			stickInput = if math.abs(y) > 0.25 then -math.sign(y) else 0
		end
	end)
	RunService.Heartbeat:Connect(function()
		local active = lastState ~= nil and lastState.Active and os.clock() - lastReceived < 0.8
		if active ~= visible then
			visible = active
			panel.Visible = active
			bindKeys(active)
			-- flight camera on while flying; on release CameraController recenters to eye level
			controllers.CameraController:SetPiloting(active)
			if not active then
				touchInput = 0
				stickInput = 0
				Net.Event("PilotInput"):FireServer(0)
			end
		end
		if not active then
			return
		end
		local attitude = lastState.Attitude or 0
		local ratio = math.clamp(attitude / 100, -1, 1)
		marker.Position = UDim2.fromScale(0.5, 0.5 - ratio * 0.45)
		band.Size = UDim2.new(1, 0, (lastState.GoodZone or 22) / 100 * 0.9, 0)
		local good = math.abs(attitude) < (lastState.GoodZone or 22)
		marker.BackgroundColor3 = if good then C.Good else Color3.fromRGB(255, 120, 60)
		hint.Text = if good then "HOLD IT STEADY" elseif attitude > 0 then "NOSE HIGH - PUSH DOWN (W)" else "NOSE LOW - PULL UP (S)"
		hint.TextColor3 = if good then C.Good else C.Warn
		modeLabel.Text = if lastState.Approach then "FINAL APPROACH" else "MANUAL CONTROL"
		altLabel.Text = string.format("ALT %s FT", tostring(lastState.Altitude or 0))
		local value = currentInput()
		local now = os.clock()
		if value ~= lastSentValue or (value ~= 0 and now - lastSent > 0.2) then
			if now - lastSent > 0.08 then
				lastSent = now
				lastSentValue = value
				Net.Event("PilotInput"):FireServer(value)
			end
		end
	end)
end

return CockpitController
