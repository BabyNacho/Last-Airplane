--[[
	PromptController
	Branded UI for every ProximityPrompt (Style = Custom). Works for all inputs:
	  * Keyboard: [E] key chip + hold bar
	  * Gamepad:  (X) chip
	  * Touch:    the whole prompt is a large tap/hold button (InputHoldBegin/End)
	Prompt colour follows its "Kind" attribute (objective, danger, rescue, decision).
	Also opens lobby kiosk windows and hides prompts that target the local player.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")

local Sfx = require(script.Parent.Parent.UI.Sfx)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local PromptController = {}

local player = Players.LocalPlayer
local C = UIKit.Colors
local F = UIKit.Fonts
local controllers: any
local folder: Folder

local KIND_COLORS = {
	default = Color3.fromRGB(235, 238, 245),
	objective = nil, -- accent
	danger = Color3.fromRGB(255, 80, 70),
	rescue = Color3.fromRGB(80, 230, 140),
	decision = Color3.fromRGB(255, 200, 70),
}

local active: { [ProximityPrompt]: { Gui: BillboardGui, Fill: Frame, Holding: boolean, HoldStart: number } } = {}

local function keyText(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Gamepad then
		local map = { ButtonX = "X", ButtonY = "Y", ButtonA = "A", ButtonB = "B" }
		return map[prompt.GamepadKeyCode.Name] or prompt.GamepadKeyCode.Name
	elseif inputType == Enum.ProximityPromptInputType.Touch then
		return "TAP"
	end
	return prompt.KeyboardKeyCode.Name
end

local function accentFor(prompt: ProximityPrompt): Color3
	local kind = prompt:GetAttribute("Kind") or "default"
	if kind == "objective" then
		return C.Accent
	end
	return KIND_COLORS[kind] or KIND_COLORS.default
end

local function show(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	if prompt.Style ~= Enum.ProximityPromptStyle.Custom or active[prompt] then
		return
	end
	local touch = inputType == Enum.ProximityPromptInputType.Touch
	local color = accentFor(prompt)
	local scale = UIKit.Scale()
	local width = (if touch then 280 else 250) * math.max(scale, 0.8)
	local height = (if touch then 84 else 64) * math.max(scale, 0.8)

	local gui = Instance.new("BillboardGui")
	gui.Name = "Prompt"
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(width, height)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 1.2, 0)
	gui.LightInfluence = 0
	gui.Active = touch
	gui.ResetOnSpawn = false
	gui.Adornee = prompt.Parent :: any
	gui.Parent = folder

	local frame = UIKit.new(if touch then "TextButton" else "Frame", {
		Name = "Frame",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(16, 20, 28),
		BackgroundTransparency = 0.12,
		Corner = 12,
		Stroke = { Color = color, Thickness = 2, Transparency = 0.2 },
		Parent = gui,
	})
	if touch then
		(frame :: TextButton).Text = ""
		;(frame :: TextButton).AutoButtonColor = false
	end
	local chipSize = height - 20
	local chip = UIKit.new("Frame", {
		Size = UDim2.fromOffset(chipSize, chipSize),
		Position = UDim2.fromOffset(10, 10),
		BackgroundColor3 = color,
		Corner = if inputType == Enum.ProximityPromptInputType.Gamepad then UDim.new(1, 0) else UDim.new(0, 8),
		Parent = frame,
	})
	UIKit.new("TextLabel", {
		Text = keyText(prompt, inputType),
		Font = F.Heading,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(15, 18, 25),
		Size = UDim2.fromScale(0.8, 0.6),
		Position = UDim2.fromScale(0.1, 0.2),
		Parent = chip,
	})
	local textX = chipSize + 20
	UIKit.new("TextLabel", {
		Name = "Action",
		Text = prompt.ActionText,
		Font = F.Heading,
		TextScaled = true,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0, textX, 0.14, 0),
		Size = UDim2.new(1, -textX - 10, 0.4, 0),
		Parent = frame,
	})
	UIKit.new("TextLabel", {
		Name = "Object",
		Text = prompt.ObjectText,
		Font = F.Body,
		TextScaled = true,
		TextColor3 = C.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0, textX, 0.56, 0),
		Size = UDim2.new(1, -textX - 10, 0.3, 0),
		Parent = frame,
	})
	local barBack = UIKit.new("Frame", {
		Size = UDim2.new(1, -24, 0, 4),
		Position = UDim2.new(0, 12, 1, -7),
		BackgroundColor3 = Color3.fromRGB(50, 55, 70),
		BackgroundTransparency = if prompt.HoldDuration > 0 then 0 else 1,
		Corner = 2,
		Parent = frame,
	})
	local fill = UIKit.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = color,
		Corner = 2,
		Parent = barBack,
	})

	local entry = { Gui = gui, Fill = fill, Holding = false, HoldStart = 0 }
	active[prompt] = entry

	if touch then
		local button = frame :: TextButton
		button.MouseButton1Down:Connect(function()
			prompt:InputHoldBegin()
		end)
		button.MouseButton1Up:Connect(function()
			prompt:InputHoldEnd()
		end)
		button.MouseLeave:Connect(function()
			if entry.Holding then
				prompt:InputHoldEnd()
			end
		end)
	end

	local changed = prompt.Changed:Connect(function(property)
		if property == "ActionText" or property == "ObjectText" then
			(frame:FindFirstChild("Action") :: TextLabel).Text = prompt.ActionText
			;(frame:FindFirstChild("Object") :: TextLabel).Text = prompt.ObjectText
		elseif property == "HoldDuration" then
			barBack.BackgroundTransparency = if prompt.HoldDuration > 0 then 0 else 1
		end
	end)
	gui.Destroying:Connect(function()
		changed:Disconnect()
	end)
	gui.Size = UDim2.fromOffset(width * 0.85, height * 0.85)
	UIKit.Tween(gui, 0.18, { Size = UDim2.fromOffset(width, height) }, Enum.EasingStyle.Back)
end

local function hide(prompt: ProximityPrompt)
	local entry = active[prompt]
	if entry then
		active[prompt] = nil
		entry.Gui:Destroy()
	end
end

local function watchPrompt(prompt: ProximityPrompt)
	local function apply()
		local hideFor = prompt:GetAttribute("HideFor")
		if hideFor and hideFor == player.UserId then
			prompt.Enabled = false
		end
	end
	apply()
	prompt:GetAttributeChangedSignal("HideFor"):Connect(apply)
end

function PromptController:Init(all)
	controllers = all
	folder = Instance.new("Folder")
	folder.Name = "Prompts"
	folder.Parent = player:WaitForChild("PlayerGui")
end

function PromptController:Start()
	ProximityPromptService.PromptShown:Connect(show)
	ProximityPromptService.PromptHidden:Connect(hide)
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
		local entry = active[prompt]
		if entry then
			entry.Holding = true
			entry.HoldStart = os.clock()
		end
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt)
		local entry = active[prompt]
		if entry then
			entry.Holding = false
			UIKit.Tween(entry.Fill, 0.15, { Size = UDim2.fromScale(0, 1) })
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		Sfx.Play("Button")
		local entry = active[prompt]
		if entry then
			entry.Fill.Size = UDim2.fromScale(1, 1)
			UIKit.Tween(entry.Fill, 0.3, { Size = UDim2.fromScale(0, 1) })
		end
		local kiosk = prompt:GetAttribute("Kiosk")
		if kiosk == "Shop" then
			controllers.ShopController:Open()
		elseif kiosk == "Wardrobe" then
			controllers.ProfileController:Open("Wardrobe")
		elseif kiosk == "Records" then
			controllers.ProfileController:Open("Records")
		end
	end)
	-- hide prompts that are about the local player (e.g. "HELP PLAYER" on yourself)
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			watchPrompt(descendant)
		end
	end
	workspace.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("ProximityPrompt") then
			watchPrompt(descendant)
		end
	end)
	RunService.RenderStepped:Connect(function()
		for prompt, entry in active do
			if entry.Holding and prompt.HoldDuration > 0 then
				local ratio = math.clamp((os.clock() - entry.HoldStart) / prompt.HoldDuration, 0, 1)
				entry.Fill.Size = UDim2.fromScale(ratio, 1)
			end
		end
	end)
end

return PromptController
