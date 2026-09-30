--[[
	UIKit
	Small declarative helpers for building the game's branded interface in code.
	Every ScreenGui gets automatic resolution scaling (UIScale) and safe-area insets.
	The accent colour follows the player's equipped UI theme.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Signal = require(ReplicatedStorage.Shared.Signal)
local UIConfig = require(ReplicatedStorage.Shared.Config.UIConfig)
local Sfx = require(script.Parent.Sfx)

local UIKit = {}

UIKit.Colors = table.clone(UIConfig.Colors)
UIKit.Fonts = UIConfig.Fonts
UIKit.AccentChanged = Signal.new()

local accentTargets: { { Instance: Instance, Property: string } } = {}
local scales: { UIScale } = {}

local SPECIAL = { Corner = true, Stroke = true, Padding = true, Children = true, Parent = true, OnClick = true, Accent = true, Gradient = true, AspectRatio = true, TextMax = true }

function UIKit.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	props = props or {}
	if instance:IsA("GuiObject") then
		(instance :: GuiObject).BorderSizePixel = 0
	end
	if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
		local text = instance :: any
		text.Font = UIKit.Fonts.Body
		text.TextColor3 = UIKit.Colors.Text
		text.BackgroundTransparency = 1
		text.TextScaled = false
		text.RichText = true
	end
	for key, value in props :: any do
		if not SPECIAL[key] then
			(instance :: any)[key] = value
		end
	end
	if props.Corner then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = if typeof(props.Corner) == "UDim" then props.Corner else UDim.new(0, props.Corner)
		corner.Parent = instance
	end
	if props.Stroke then
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = props.Stroke.Color or UIKit.Colors.Stroke
		stroke.Thickness = props.Stroke.Thickness or 1.5
		stroke.Transparency = props.Stroke.Transparency or 0
		stroke.Parent = instance
		if props.Stroke.Accent then
			UIKit.Accent(stroke, "Color")
		end
	end
	if props.Padding then
		local padding = Instance.new("UIPadding")
		local p = props.Padding
		if type(p) == "number" then
			p = { p, p, p, p }
		end
		padding.PaddingTop = UDim.new(0, p[1])
		padding.PaddingRight = UDim.new(0, p[2])
		padding.PaddingBottom = UDim.new(0, p[3])
		padding.PaddingLeft = UDim.new(0, p[4])
		padding.Parent = instance
	end
	if props.Gradient then
		local gradient = Instance.new("UIGradient")
		gradient.Color = props.Gradient.Color
		gradient.Rotation = props.Gradient.Rotation or 90
		if props.Gradient.Transparency then
			gradient.Transparency = props.Gradient.Transparency
		end
		gradient.Parent = instance
	end
	if props.AspectRatio then
		local ratio = Instance.new("UIAspectRatioConstraint")
		ratio.AspectRatio = props.AspectRatio
		ratio.Parent = instance
	end
	if props.TextMax then
		local constraint = Instance.new("UITextSizeConstraint")
		constraint.MaxTextSize = props.TextMax
		constraint.Parent = instance
	end
	if props.Accent then
		UIKit.Accent(instance, props.Accent)
	end
	for _, child in children or props.Children or {} do
		child.Parent = instance
	end
	if props.OnClick and (instance:IsA("TextButton") or instance:IsA("ImageButton")) then
		(instance :: any).Activated:Connect(props.OnClick)
	end
	if props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

---------------------------------------------------------------- theme

function UIKit.Accent(instance: Instance, property: string)
	table.insert(accentTargets, { Instance = instance, Property = property });
	(instance :: any)[property] = UIKit.Colors.Accent
end

function UIKit.SetAccent(color: Color3)
	UIKit.Colors.Accent = color
	for _, target in accentTargets do
		pcall(function()
			(target.Instance :: any)[target.Property] = color
		end)
	end
	UIKit.AccentChanged:Fire(color)
end

---------------------------------------------------------------- device

function UIKit.IsTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function UIKit.IsGamepad(): boolean
	return UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled and not UserInputService.TouchEnabled
end

function UIKit.ViewportSize(): Vector2
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize else UIConfig.ReferenceSize
end

local function computeScale(): number
	local viewport = UIKit.ViewportSize()
	local ref = UIConfig.ReferenceSize
	local scale = math.min(viewport.X / ref.X, viewport.Y / ref.Y)
	if UIKit.IsTouch() then
		scale *= 1.12 -- slightly larger UI for fingers
	end
	return math.clamp(scale, UIConfig.MinScale, UIConfig.MaxScale)
end

function UIKit.Scale(): number
	return computeScale()
end

-- Size (in design pixels) that ends up at least the minimum comfortable touch target.
function UIKit.TouchSize(designPixels: number): number
	local scale = computeScale()
	return math.max(designPixels, UIConfig.MinTouchTarget / scale)
end

local function refreshScales()
	local scale = computeScale()
	for i = #scales, 1, -1 do
		local s = scales[i]
		if s.Parent then
			s.Scale = scale
		else
			table.remove(scales, i)
		end
	end
end

function UIKit.Screen(name: string, displayOrder: number?, ignoreInset: boolean?): ScreenGui
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = displayOrder or 0
	gui.IgnoreGuiInset = ignoreInset == true
	gui.ScreenInsets = if ignoreInset then Enum.ScreenInsets.None else Enum.ScreenInsets.DeviceSafeInsets
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = computeScale()
	scale.Parent = root
	-- UIScale shrinks the root; compensate so the root still fills the screen
	local function fit()
		local s = scale.Scale
		root.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	scale:GetPropertyChangedSignal("Scale"):Connect(fit)
	fit()
	table.insert(scales, scale)
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui
end

function UIKit.Root(gui: ScreenGui): Frame
	return gui:FindFirstChild("Root") :: Frame
end

---------------------------------------------------------------- building blocks

function UIKit.Tween(instance: Instance, time: number, goals: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local tween = TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out), goals)
	tween:Play()
	return tween
end

function UIKit.Text(props: { [string]: any }): TextLabel
	local defaults = {
		Size = UDim2.new(1, 0, 0, 24),
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	}
	for k, v in props do
		defaults[k] = v
	end
	return UIKit.new("TextLabel", defaults)
end

function UIKit.Panel(props: { [string]: any }): Frame
	local defaults = {
		BackgroundColor3 = UIKit.Colors.Panel,
		BackgroundTransparency = 0.08,
		Corner = 14,
		Stroke = { Color = UIKit.Colors.Stroke, Transparency = 0.35 },
	}
	for k, v in props do
		defaults[k] = v
	end
	return UIKit.new("Frame", defaults)
end

-- Animated button. style: "primary" (accent), "secondary", "danger", "good", "ghost".
function UIKit.Button(props: { [string]: any }): TextButton
	local style = props.Style or "primary"
	local colors = {
		primary = UIKit.Colors.Accent,
		secondary = UIKit.Colors.PanelLight,
		danger = UIKit.Colors.Danger,
		good = UIKit.Colors.Good,
		ghost = UIKit.Colors.Panel,
		gold = UIKit.Colors.Credits,
	}
	local defaults = {
		Size = UDim2.fromOffset(180, 52),
		BackgroundColor3 = colors[style] or colors.primary,
		Font = UIKit.Fonts.Bold,
		TextSize = 18,
		TextColor3 = if style == "gold" then Color3.fromRGB(40, 30, 10) else UIKit.Colors.Text,
		AutoButtonColor = false,
		Corner = 12,
		BackgroundTransparency = 0,
	}
	for k, v in props do
		if k ~= "Style" then
			defaults[k] = v
		end
	end
	local button = UIKit.new("TextButton", defaults) :: TextButton
	if style == "primary" and not props.BackgroundColor3 then
		UIKit.Accent(button, "BackgroundColor3")
	end
	local scale = Instance.new("UIScale")
	scale.Parent = button
	button.MouseEnter:Connect(function()
		UIKit.Tween(scale, 0.15, { Scale = 1.04 })
		Sfx.Play("Hover")
	end)
	button.MouseLeave:Connect(function()
		UIKit.Tween(scale, 0.15, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		UIKit.Tween(scale, 0.08, { Scale = 0.96 })
	end)
	button.MouseButton1Up:Connect(function()
		UIKit.Tween(scale, 0.12, { Scale = 1.02 })
	end)
	button.Activated:Connect(function()
		Sfx.Play("Click")
	end)
	return button
end

function UIKit.List(parent: Instance, padding: number?, direction: Enum.FillDirection?, horizontalAlign: Enum.HorizontalAlignment?, verticalAlign: Enum.VerticalAlignment?): UIListLayout
	return UIKit.new("UIListLayout", {
		Padding = UDim.new(0, padding or 8),
		FillDirection = direction or Enum.FillDirection.Vertical,
		HorizontalAlignment = horizontalAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = verticalAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

function UIKit.Scroll(props: { [string]: any }): ScrollingFrame
	local defaults = {
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = UIKit.Colors.Stroke,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
	}
	for k, v in props do
		defaults[k] = v
	end
	return UIKit.new("ScrollingFrame", defaults)
end

-- Full-screen modal window with title and close button. Returns (overlay, content frame, closeFn).
function UIKit.Window(parent: Instance, title: string, size: UDim2, onClose: (() -> ())?): (Frame, Frame, () -> ())
	local overlay = UIKit.new("Frame", {
		Name = title .. "Window",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Visible = false,
		ZIndex = 20,
		Parent = parent,
	})
	local window = UIKit.Panel({
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = size,
		BackgroundTransparency = 0.02,
		ZIndex = 21,
		Parent = overlay,
	})
	UIKit.new("UISizeConstraint", { MaxSize = Vector2.new(1180, 680), Parent = window })
	local header = UIKit.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundTransparency = 1,
		ZIndex = 22,
		Parent = window,
	})
	UIKit.new("Frame", {
		Size = UDim2.new(0, 6, 0, 30),
		Position = UDim2.new(0, 22, 0.5, -15),
		Accent = "BackgroundColor3",
		Corner = 3,
		ZIndex = 22,
		Parent = header,
	})
	UIKit.Text({
		Text = title,
		Font = UIKit.Fonts.Heading,
		TextSize = 28,
		Position = UDim2.new(0, 40, 0, 0),
		Size = UDim2.new(1, -120, 1, 0),
		ZIndex = 22,
		Parent = header,
	})
	local closeSize = UIKit.TouchSize(44)
	local function closeFn()
		UIKit.Tween(window, 0.15, { Size = size - UDim2.fromOffset(20, 20) })
		task.delay(0.12, function()
			overlay.Visible = false
			window.Size = size
		end)
		if onClose then
			onClose()
		end
	end
	UIKit.Button({
		Text = "✕",
		Style = "secondary",
		Size = UDim2.fromOffset(closeSize, closeSize),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		TextSize = 22,
		ZIndex = 23,
		Parent = header,
		OnClick = closeFn,
	})
	local content = UIKit.new("Frame", {
		Name = "Content",
		Size = UDim2.new(1, -40, 1, -84),
		Position = UDim2.fromOffset(20, 68),
		BackgroundTransparency = 1,
		ZIndex = 22,
		Parent = window,
	})
	return overlay, content, closeFn
end

function UIKit.OpenWindow(overlay: Frame)
	local window = overlay:FindFirstChild("Window") :: Frame
	overlay.Visible = true
	local target = window.Size
	window.Size = target - UDim2.fromOffset(30, 30)
	UIKit.Tween(window, 0.25, { Size = target }, Enum.EasingStyle.Back)
	Sfx.Play("Click")
end

-- Horizontal progress bar. Returns (frame, setFn(ratio, color?)).
function UIKit.Bar(props: { [string]: any }): (Frame, (number, Color3?) -> ())
	local back = UIKit.new("Frame", {
		Size = props.Size or UDim2.new(1, 0, 0, 10),
		Position = props.Position,
		BackgroundColor3 = Color3.fromRGB(40, 45, 58),
		Corner = UDim.new(1, 0),
		Parent = props.Parent,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
	})
	local fill = UIKit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = props.Color or UIKit.Colors.Accent,
		Corner = UDim.new(1, 0),
		ZIndex = props.ZIndex,
		Parent = back,
	})
	local function set(ratio: number, color: Color3?)
		UIKit.Tween(fill, 0.25, { Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1) })
		if color then
			fill.BackgroundColor3 = color
		end
	end
	return back, set
end

function UIKit.Init()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScales)
	end
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local cam = Workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScales)
			refreshScales()
		end
	end)
end

return UIKit
