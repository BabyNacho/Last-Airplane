--[[
	HUDController
	The in-game HUD: phase/timer bar, objectives with a 3D waypoint, player condition & oxygen,
	atmospheric warnings, intercom subtitles, toasts, reward popups, achievement banners,
	equipment gauges and the lobby panel (credits, menu buttons, departure countdown).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local UIConfig = require(ReplicatedStorage.Shared.Config.UIConfig)
local Util = require(ReplicatedStorage.Shared.Util)
local ClientState = require(script.Parent.Parent.ClientState)
local Sfx = require(script.Parent.Parent.UI.Sfx)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local HUDController = {}

local player = Players.LocalPlayer
local C = UIKit.Colors
local F = UIKit.Fonts

local gui: ScreenGui
local root: Frame
local controllers: any

-- widgets
local topBar, phaseLabel, timerLabel, flightLabel, modifierChip
local objectivePanel, objectiveList
local conditionPanel, conditionState, setHealth, oxygenRow, setOxygen, oxygenLabel, buckleLabel, bleedLabel
local warningFrame, warningTitle, warningSubtitle
local subtitleFrame, subtitleSpeaker, subtitleText
local toastHolder
local rewardHolder
local lobbyPanel, creditsLabel, countdownLabel, countdownSub
local seatChip, seatLabel
local gaugeFrame, gaugeLabel, setGauge
local waypoint: BillboardGui
local waypointLabel: TextLabel

local objectiveRows: { [string]: Frame } = {}
local warningToken = 0
local subtitleToken = 0

---------------------------------------------------------------- build

local function buildTopBar()
	topBar = UIKit.Panel({
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(420, 64),
		Parent = root,
	})
	phaseLabel = UIKit.Text({
		Text = "WAITING",
		Font = F.Heading,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = topBar,
	})
	UIKit.Accent(phaseLabel, "TextColor3")
	timerLabel = UIKit.Text({
		Text = "",
		Font = F.Mono,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 0, 24),
		Parent = topBar,
	})
	flightLabel = UIKit.Text({
		Text = "",
		TextSize = 14,
		TextColor3 = C.SubText,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 6),
		Size = UDim2.new(1, 40, 0, 18),
		Parent = topBar,
	})
	modifierChip = UIKit.new("TextLabel", {
		Text = "",
		Font = F.Bold,
		TextSize = 13,
		TextColor3 = C.Warn,
		BackgroundColor3 = Color3.fromRGB(60, 45, 10),
		BackgroundTransparency = 0.2,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 28),
		Size = UDim2.fromOffset(220, 22),
		Corner = 11,
		Visible = false,
		Parent = topBar,
	})
end

local function buildObjectives()
	objectivePanel = UIKit.Panel({
		Name = "Objectives",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(330, 60),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Padding = { 12, 14, 12, 14 },
		Parent = root,
	})
	UIKit.List(objectivePanel, 8)
	local header = UIKit.Text({
		Text = "OBJECTIVES",
		Font = F.Heading,
		TextSize = 16,
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 0,
		Parent = objectivePanel,
	})
	UIKit.Accent(header, "TextColor3")
	objectiveList = UIKit.new("Frame", {
		Name = "List",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = objectivePanel,
	})
	UIKit.List(objectiveList, 8)
end

local function buildCondition()
	conditionPanel = UIKit.Panel({
		Name = "Condition",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -12),
		Size = UDim2.fromOffset(280, 96),
		Visible = false,
		Padding = { 10, 14, 10, 14 },
		Parent = root,
	})
	conditionState = UIKit.Text({
		Text = "HEALTHY",
		Font = F.Heading,
		TextSize = 18,
		Size = UDim2.new(1, 0, 0, 22),
		Parent = conditionPanel,
	})
	buckleLabel = UIKit.Text({
		Text = "",
		Font = F.Bold,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.Good,
		Size = UDim2.new(1, 0, 0, 22),
		Parent = conditionPanel,
	})
	local _, set = UIKit.Bar({ Parent = conditionPanel, Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 12), Color = C.Good })
	setHealth = set
	oxygenRow = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 0, 30),
		Visible = false,
		Parent = conditionPanel,
	})
	oxygenLabel = UIKit.Text({ Text = "O₂", Font = F.Bold, TextSize = 14, Size = UDim2.new(1, 0, 0, 14), TextColor3 = Color3.fromRGB(120, 200, 255), Parent = oxygenRow })
	local _, setO2 = UIKit.Bar({ Parent = oxygenRow, Position = UDim2.fromOffset(0, 17), Size = UDim2.new(1, 0, 0, 10), Color = Color3.fromRGB(90, 190, 255) })
	setOxygen = setO2
	bleedLabel = UIKit.Text({
		Text = "",
		Font = F.Bold,
		TextSize = 14,
		TextColor3 = UIConfig.ConditionColors.Unconscious,
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 0, 30),
		Visible = false,
		Parent = conditionPanel,
	})
end

local function buildWarnings()
	warningFrame = UIKit.new("Frame", {
		Name = "Warning",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(640, 110),
		BackgroundColor3 = Color3.fromRGB(40, 5, 8),
		BackgroundTransparency = 0.15,
		Corner = 8,
		Stroke = { Color = C.Danger, Thickness = 2 },
		Visible = false,
		Parent = root,
	})
	warningTitle = UIKit.Text({
		Text = "WARNING",
		Font = F.Heading,
		TextSize = 40,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Danger,
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 44),
		Parent = warningFrame,
	})
	warningSubtitle = UIKit.Text({
		Text = "",
		Font = F.Bold,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Text,
		Position = UDim2.fromOffset(10, 62),
		Size = UDim2.new(1, -20, 0, 40),
		Parent = warningFrame,
	})
end

local function buildSubtitles()
	subtitleFrame = UIKit.new("Frame", {
		Name = "Subtitles",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -120),
		Size = UDim2.fromOffset(700, 60),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		Corner = 10,
		Padding = { 8, 16, 8, 16 },
		Visible = false,
		Parent = root,
	})
	UIKit.List(subtitleFrame, 2)
	subtitleSpeaker = UIKit.Text({ Text = "", Font = F.Heading, TextSize = 14, Size = UDim2.new(1, 0, 0, 16), Parent = subtitleFrame })
	UIKit.Accent(subtitleSpeaker, "TextColor3")
	subtitleText = UIKit.Text({ Text = "", TextSize = 19, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = subtitleFrame })
end

local function buildToasts()
	toastHolder = UIKit.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 120),
		Size = UDim2.fromOffset(460, 300),
		BackgroundTransparency = 1,
		Parent = root,
	})
	UIKit.List(toastHolder, 6, nil, Enum.HorizontalAlignment.Center)
	rewardHolder = UIKit.new("Frame", {
		Name = "Rewards",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -30, 0.55, 0),
		Size = UDim2.fromOffset(260, 200),
		BackgroundTransparency = 1,
		Parent = root,
	})
	UIKit.List(rewardHolder, 4, nil, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Bottom)
end

local function buildSeatChip()
	seatChip = UIKit.Panel({
		Name = "Seat",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 130),
		Size = UDim2.fromOffset(260, 56),
		Visible = false,
		Parent = root,
	})
	UIKit.Text({ Text = "YOUR SEAT", Font = F.Bold, TextSize = 13, TextColor3 = C.SubText, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 14), Parent = seatChip })
	seatLabel = UIKit.Text({ Text = "", Font = F.Heading, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 28), Parent = seatChip })
	UIKit.Accent(seatLabel, "TextColor3")
end

local function buildGauge()
	gaugeFrame = UIKit.Panel({
		Name = "Gauge",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -200),
		Size = UDim2.fromOffset(260, 48),
		Visible = false,
		Padding = { 6, 12, 6, 12 },
		Parent = root,
	})
	gaugeLabel = UIKit.Text({ Text = "", Font = F.Bold, TextSize = 14, Size = UDim2.new(1, 0, 0, 16), Parent = gaugeFrame })
	local _, set = UIKit.Bar({ Parent = gaugeFrame, Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 10) })
	setGauge = set
end

local function lobbyButton(parent, text: string, icon: string, order: number, onClick)
	local size = UIKit.TouchSize(58)
	local button = UIKit.Button({
		Text = icon .. "  " .. text,
		Style = "secondary",
		Size = UDim2.new(1, 0, 0, size),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 18,
		LayoutOrder = order,
		Padding = { 0, 0, 0, 16 },
		Parent = parent,
		OnClick = onClick,
	})
	return button
end

local function buildLobby()
	lobbyPanel = UIKit.new("Frame", {
		Name = "Lobby",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = true,
		Parent = root,
	})
	local credits = UIKit.Panel({
		Name = "Credits",
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(220, 52),
		Parent = lobbyPanel,
	})
	UIKit.Text({ Text = "✈", TextSize = 24, TextColor3 = C.Credits, Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(30, 52), Parent = credits })
	creditsLabel = UIKit.Text({ Text = "0", Font = F.Heading, TextSize = 24, TextColor3 = C.Credits, Position = UDim2.fromOffset(44, 4), Size = UDim2.new(1, -50, 0, 28), Parent = credits })
	UIKit.Text({ Text = string.upper(EconomyConfig.CurrencyName), Font = F.Bold, TextSize = 11, TextColor3 = C.SubText, Position = UDim2.fromOffset(44, 30), Size = UDim2.new(1, -50, 0, 14), Parent = credits })

	local menu = UIKit.new("Frame", {
		Name = "Menu",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(200, 360),
		BackgroundTransparency = 1,
		Parent = lobbyPanel,
	})
	UIKit.List(menu, 8, nil, nil, Enum.VerticalAlignment.Center)
	lobbyButton(menu, "SHOP", "🛒", 1, function()
		controllers.ShopController:Open()
	end)
	lobbyButton(menu, "WARDROBE", "👕", 2, function()
		controllers.ShopController:Open("Loadout")
	end)
	lobbyButton(menu, "RECORDS", "🏆", 3, function()
		controllers.ProfileController:Open("Records")
	end)
	lobbyButton(menu, "EMOTES", "💃", 4, function()
		controllers.EmoteController:Toggle()
	end)
	local spectate = lobbyButton(menu, "SPECTATE", "👁", 5, function()
		controllers.CameraController:ToggleSpectate()
	end)
	spectate.Name = "SpectateButton"

	local countdown = UIKit.Panel({
		Name = "Countdown",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(440, 86),
		Parent = lobbyPanel,
	})
	countdownSub = UIKit.Text({ Text = "NEXT FLIGHT DEPARTS IN", Font = F.Bold, TextSize = 14, TextColor3 = C.SubText, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 0, 16), Parent = countdown })
	countdownLabel = UIKit.Text({ Text = "--:--", Font = F.Heading, TextSize = 40, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 0, 46), Parent = countdown })
	UIKit.Accent(countdownLabel, "TextColor3")
end

local function buildWaypoint()
	waypoint = Instance.new("BillboardGui")
	waypoint.Name = "ObjectiveWaypoint"
	waypoint.AlwaysOnTop = true
	waypoint.Size = UDim2.fromOffset(160, 64)
	waypoint.LightInfluence = 0
	waypoint.MaxDistance = 400
	waypoint.Enabled = false
	local diamond = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(22, 22),
		Rotation = 45,
		BackgroundColor3 = C.Critical,
		Corner = 4,
		Stroke = { Color = Color3.new(1, 1, 1), Thickness = 2 },
		Parent = waypoint,
	})
	diamond.Name = "Diamond"
	waypointLabel = UIKit.Text({
		Text = "",
		Font = F.Bold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.4,
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, 30),
		Parent = waypoint,
	})
	waypoint.Parent = player:WaitForChild("PlayerGui")
end

---------------------------------------------------------------- behaviour

function HUDController:Toast(text: string, kind: string?)
	local colors = { good = C.Good, warn = C.Warn, danger = C.Danger, info = C.Accent }
	local color = colors[kind or "info"] or C.Accent
	local toast = UIKit.Panel({
		Size = UDim2.fromOffset(440, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.1,
		Padding = { 10, 14, 10, 18 },
		Parent = toastHolder,
	})
	UIKit.new("Frame", { Size = UDim2.new(0, 4, 1, 0), Position = UDim2.fromOffset(-12, 0), BackgroundColor3 = color, Corner = 2, Parent = toast })
	UIKit.Text({ Text = text, TextSize = 16, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = toast })
	toast.BackgroundTransparency = 1
	UIKit.Tween(toast, 0.25, { BackgroundTransparency = 0.1 })
	Sfx.Play(if kind == "danger" then "Warning" else "Notify")
	local children = toastHolder:GetChildren()
	local count = 0
	for _, child in children do
		if child:IsA("Frame") then
			count += 1
		end
	end
	if count > 4 then
		for _, child in children do
			if child:IsA("Frame") and child ~= toast then
				child:Destroy()
				break
			end
		end
	end
	task.delay(4.5, function()
		if toast.Parent then
			UIKit.Tween(toast, 0.3, { BackgroundTransparency = 1 })
			for _, d in toast:GetDescendants() do
				if d:IsA("TextLabel") then
					UIKit.Tween(d, 0.3, { TextTransparency = 1 })
				end
			end
			task.wait(0.35)
			toast:Destroy()
		end
	end)
end

function HUDController:ShowWarning(data)
	warningToken += 1
	local token = warningToken
	local severity = data.Severity or "warn"
	local color = if severity == "danger" then C.Danger elseif severity == "info" then C.Accent else C.Warn
	local background = if severity == "danger" then Color3.fromRGB(45, 6, 10) elseif severity == "info" then Color3.fromRGB(8, 20, 40) else Color3.fromRGB(45, 32, 5)
	warningTitle.Text = data.Title or "WARNING"
	warningTitle.TextColor3 = color
	warningSubtitle.Text = data.Subtitle or ""
	warningFrame.BackgroundColor3 = background
	local stroke = warningFrame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
	end
	warningFrame.Visible = true
	warningFrame.Size = UDim2.fromOffset(700, 120)
	UIKit.Tween(warningFrame, 0.35, { Size = UDim2.fromOffset(640, 110) }, Enum.EasingStyle.Back)
	Sfx.Play(if severity == "info" then "Notify" else "Warning")
	-- blink the title for danger warnings
	if severity == "danger" then
		task.spawn(function()
			for i = 1, 6 do
				if warningToken ~= token then
					return
				end
				warningTitle.TextTransparency = if i % 2 == 0 then 0 else 0.45
				task.wait(0.22)
			end
			warningTitle.TextTransparency = 0
		end)
	end
	task.delay(4.2, function()
		if warningToken == token then
			warningFrame.Visible = false
		end
	end)
end

local GARBLE = { "*krzzt*", "*static*", "..." }

function HUDController:ShowSubtitle(data)
	subtitleToken += 1
	local token = subtitleToken
	local text = data.Text or ""
	if data.Garbled then
		local words = string.split(text, " ")
		for i = 1, #words do
			if math.random() < 0.25 then
				words[i] = GARBLE[math.random(1, #GARBLE)]
			end
		end
		text = table.concat(words, " ")
	end
	subtitleSpeaker.Text = string.upper(data.Speaker or "")
	subtitleText.Text = ""
	subtitleFrame.Visible = true
	if data.Speaker == "Captain" or data.Speaker == "Flight Attendant" or data.Speaker == "ATC" then
		Sfx.Play("Intercom")
	end
	-- typewriter
	task.spawn(function()
		local length = utf8.len(text) or #text
		local step = math.clamp(1.2 / math.max(1, length), 0.008, 0.03)
		local i = 0
		for _, codepoint in utf8.codes(text) do
			if subtitleToken ~= token then
				return
			end
			i += 1
			subtitleText.Text ..= utf8.char(codepoint)
			if i % 2 == 0 then
				task.wait(step * 2)
			end
		end
	end)
	local duration = data.Duration or math.clamp(#text / 14, 3.5, 9)
	task.delay(duration, function()
		if subtitleToken == token then
			subtitleFrame.Visible = false
		end
	end)
end

function HUDController:RewardPopup(label: string, amount: number?)
	local text = if amount then string.format("+%d %s  %s", amount, EconomyConfig.CurrencyShort, label) else label
	local pop = UIKit.new("TextLabel", {
		Text = text,
		Font = F.Heading,
		TextSize = 20,
		TextColor3 = if amount then C.Credits else C.Good,
		TextStrokeTransparency = 0.5,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(1, 0, 0, 26),
		Parent = rewardHolder,
	})
	Sfx.Play("Reward")
	pop.Position = UDim2.fromOffset(40, 0)
	task.delay(2.6, function()
		UIKit.Tween(pop, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 })
		task.wait(0.45)
		pop:Destroy()
	end)
end

function HUDController:Banner(title: string, subtitle: string?, color: Color3?)
	local banner = UIKit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(560, 90),
		BackgroundTransparency = 1,
		Parent = root,
	})
	local t = UIKit.Text({ Text = title, Font = F.Heading, TextSize = 34, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = color or C.Text, TextStrokeTransparency = 0.6, Size = UDim2.new(1, 0, 0, 40), Parent = banner })
	local s = UIKit.Text({ Text = subtitle or "", TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.SubText, TextStrokeTransparency = 0.7, Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 40), Parent = banner })
	t.TextTransparency = 1
	s.TextTransparency = 1
	UIKit.Tween(t, 0.4, { TextTransparency = 0 })
	UIKit.Tween(s, 0.6, { TextTransparency = 0 })
	task.delay(3, function()
		UIKit.Tween(t, 0.5, { TextTransparency = 1, TextStrokeTransparency = 1 })
		UIKit.Tween(s, 0.5, { TextTransparency = 1, TextStrokeTransparency = 1 })
		task.wait(0.6)
		banner:Destroy()
	end)
end

local function objectiveRow(obj)
	local row = objectiveRows[obj.Id]
	if not row then
		row = UIKit.new("Frame", {
			Name = obj.Id,
			BackgroundColor3 = C.PanelLight,
			BackgroundTransparency = 0.35,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Corner = 8,
			Padding = { 8, 10, 8, 12 },
			Parent = objectiveList,
		})
		UIKit.new("Frame", { Name = "Stripe", Size = UDim2.new(0, 3, 1, 0), Position = UDim2.fromOffset(-10, 0), Corner = 2, Parent = row })
		UIKit.Text({ Name = "Kind", Font = F.Bold, TextSize = 11, Size = UDim2.new(1, 0, 0, 13), Parent = row })
		UIKit.Text({ Name = "Label", TextSize = 15, Position = UDim2.fromOffset(0, 15), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = row })
		UIKit.Text({ Name = "Count", Font = F.Mono, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.new(1, 0, 0, 13), Parent = row })
		objectiveRows[obj.Id] = row
		row.BackgroundTransparency = 1
		UIKit.Tween(row, 0.3, { BackgroundTransparency = 0.35 })
	end
	local critical = obj.Kind == "Critical"
	local color = if critical then C.Critical else C.Optional
	local stripe = row:FindFirstChild("Stripe") :: Frame
	local kind = row:FindFirstChild("Kind") :: TextLabel
	local label = row:FindFirstChild("Label") :: TextLabel
	local count = row:FindFirstChild("Count") :: TextLabel
	row.LayoutOrder = obj.Order + (if obj.State == "Active" then 0 else 1000)
	stripe.BackgroundColor3 = color
	kind.TextColor3 = color
	kind.Text = if critical then "CRITICAL" else "OPTIONAL"
	count.Text = if obj.Goal > 1 then string.format("%d/%d", obj.Progress, obj.Goal) else ""
	if obj.State == "Completed" then
		label.Text = "✔ " .. obj.Text
		label.TextColor3 = C.Good
		kind.Text = "COMPLETE"
		kind.TextColor3 = C.Good
		stripe.BackgroundColor3 = C.Good
	elseif obj.State == "Failed" then
		label.Text = "<s>" .. obj.Text .. "</s>"
		label.TextColor3 = C.SubText
		kind.Text = "FAILED"
		kind.TextColor3 = C.Danger
	else
		label.Text = obj.Text .. (if obj.Hint then "\n<font size=\"12\" color=\"#96a0b4\">" .. obj.Hint .. "</font>" else "")
		label.TextColor3 = C.Text
	end
	return row
end

local fadeScheduled: { [string]: boolean } = {}

local function refreshObjectives(list)
	local seen = {}
	for _, obj in list do
		seen[obj.Id] = true
		objectiveRow(obj)
		if obj.State ~= "Active" and not fadeScheduled[obj.Id] then
			fadeScheduled[obj.Id] = true
			local id = obj.Id
			task.delay(6, function()
				local row = objectiveRows[id]
				if row then
					row:Destroy()
					objectiveRows[id] = nil
				end
			end)
		end
	end
	for id, row in objectiveRows do
		if not seen[id] then
			row:Destroy()
			objectiveRows[id] = nil
			fadeScheduled[id] = nil
		end
	end
	if #list == 0 then
		table.clear(fadeScheduled)
	end
	objectivePanel.Visible = next(objectiveRows) ~= nil and ClientState.InRound()
end

local function trackedObjective()
	for _, obj in ClientState.Objectives do
		if obj.State == "Active" and obj.Kind == "Critical" and obj.Location then
			return obj
		end
	end
	for _, obj in ClientState.Objectives do
		if obj.State == "Active" and obj.Location then
			return obj
		end
	end
	return nil
end

local function refreshCondition(condition)
	local tracked = condition.Tracked == true and ClientState.InRound()
	conditionPanel.Visible = tracked
	if not tracked then
		return
	end
	local state = condition.State or "Healthy"
	local color = UIConfig.ConditionColors[state] or C.Good
	conditionState.Text = string.upper(state)
	conditionState.TextColor3 = color
	setHealth((condition.Health or 0) / 100, color)
	local oxygenVisible = ClientState.Flight("OxygenEmergency") == true or (condition.Oxygen or 100) < 99
	oxygenRow.Visible = oxygenVisible and state ~= "Unconscious"
	if oxygenVisible then
		local o2 = condition.Oxygen or 100
		setOxygen(o2 / 100, if o2 < 30 then C.Danger else Color3.fromRGB(90, 190, 255))
		local source = condition.OxygenSource
		oxygenLabel.Text = "O₂  " .. math.floor(o2) .. "%" .. (if condition.OnOxygen then "  ·  " .. (if source == "Bottle" then "PORTABLE BOTTLE" elseif source == "Cabin" then "CABIN AIR" else "MASK ON") else "  ·  NO MASK!")
		oxygenLabel.TextColor3 = if condition.OnOxygen then Color3.fromRGB(120, 200, 255) else C.Danger
	end
	bleedLabel.Visible = state == "Unconscious"
	if state == "Unconscious" then
		bleedLabel.Text = string.format("UNCONSCIOUS - waiting for help (%ds)", math.ceil(condition.BleedOut or 0))
	end
end

local lastCountdownSecond = -1

local function updateTopBar()
	local phase = ClientState.Phase()
	local left = ClientState.TimeLeft()
	local inRound = ClientState.InRound()
	local gameState = ClientState.GameState
	topBar.Visible = phase ~= "Lobby"
	phaseLabel.Text = UIConfig.PhaseNames[phase] or phase
	timerLabel.Text = if left > 0 then Util.FormatTime(left) else ""
	local flightNumber = gameState:GetAttribute("FlightNumber")
	if phase ~= "Lobby" and flightNumber then
		local destination = gameState:GetAttribute("Destination") or ""
		local alive = gameState:GetAttribute("Alive") or 0
		local total = gameState:GetAttribute("Participants") or 0
		flightLabel.Text = string.format("FLIGHT %s → %s   ·   %d/%d PASSENGERS OK", flightNumber, string.upper(destination), alive, total)
	else
		flightLabel.Text = ""
	end
	local modifier = gameState:GetAttribute("Modifier") or ""
	modifierChip.Visible = modifier ~= "" and phase ~= "Lobby"
	modifierChip.Text = "◆ " .. string.upper(modifier)

	lobbyPanel.Visible = not inRound
	local countdown = lobbyPanel:FindFirstChild("Countdown") :: Frame
	if phase == "Lobby" then
		countdown.Visible = true
		if (gameState:GetAttribute("PhaseEndsAt") or 0) > 0 then
			countdownSub.Text = "NEXT FLIGHT DEPARTS IN"
			countdownLabel.Text = Util.FormatTime(left)
			local second = math.ceil(left)
			if second ~= lastCountdownSecond and second <= 5 and second > 0 then
				Sfx.Play("Countdown")
			end
			lastCountdownSecond = second
		else
			countdownSub.Text = "STAND BY"
			countdownLabel.Text = "WAITING FOR PASSENGERS"
		end
	else
		countdown.Visible = not inRound
		countdownSub.Text = "FLIGHT IN PROGRESS"
		countdownLabel.Text = if phase == "Results" then "LANDED" else (gameState:GetAttribute("Alive") or 0) .. " ABOARD"
	end
	local menu = lobbyPanel:FindFirstChild("Menu")
	local spectate = menu and menu:FindFirstChild("SpectateButton") :: TextButton?
	if spectate then
		spectate.Visible = gameState:GetAttribute("InProgress") == true and not inRound
	end
end

local function updateWaypoint()
	local obj = trackedObjective()
	local showSeat = ClientState.Phase() == "Boarding" and ClientState.Seat and ClientState.InRound()
	local target: Instance? = nil
	local label = ""
	if showSeat then
		target = ClientState.Seat.Seat
		label = "SEAT " .. tostring(ClientState.Seat.Label)
	elseif obj and ClientState.InRound() then
		target = obj.Location
		label = obj.Text
	end
	if target and target:IsA("BasePart") then
		waypoint.Adornee = target
		waypoint.Enabled = true
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local distance = if rootPart then (rootPart.Position - target.Position).Magnitude else 0
		waypointLabel.Text = string.format("%s\n%dm", label, math.floor(distance / 3.5))
		waypoint.Enabled = distance > 7
		local diamond = waypoint:FindFirstChild("Diamond") :: Frame
		diamond.BackgroundColor3 = if showSeat then C.Accent elseif obj and obj.Kind == "Critical" then C.Critical else C.Optional
	else
		waypoint.Enabled = false
	end
end

local function updateGauge()
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if not tool then
		gaugeFrame.Visible = false
		return
	end
	local kind = tool:GetAttribute("Kind")
	if kind == "Extinguisher" then
		gaugeFrame.Visible = true
		local charge = tool:GetAttribute("Charge") or 0
		gaugeLabel.Text = "EXTINGUISHER  " .. math.floor(charge) .. "%   ·   hold to spray"
		setGauge(charge / 100, if charge < 25 then C.Danger else C.Accent)
	elseif kind == "OxygenBottle" then
		gaugeFrame.Visible = true
		local supply = tool:GetAttribute("Supply") or 0
		gaugeLabel.Text = string.format("PORTABLE OXYGEN  %ds   ·   click to open/close", math.floor(supply))
		setGauge(supply / 60, Color3.fromRGB(90, 190, 255))
	elseif kind == "FirstAidKit" then
		gaugeFrame.Visible = true
		gaugeLabel.Text = "FIRST AID KIT  ·  " .. tostring(tool:GetAttribute("Uses") or 0) .. " uses left"
		setGauge((tool:GetAttribute("Uses") or 0) / 2, C.Good)
	else
		gaugeFrame.Visible = false
	end
end

---------------------------------------------------------------- lifecycle

function HUDController:Init(all)
	controllers = all
	gui = UIKit.Screen("MainUI", 5)
	root = UIKit.Root(gui)
	buildTopBar()
	buildObjectives()
	buildCondition()
	buildSubtitles()
	buildToasts()
	buildSeatChip()
	buildGauge()
	buildLobby()
	buildWarnings()
	buildWaypoint()
end

function HUDController:Start()
	Net.Event("Notify").OnClientEvent:Connect(function(data)
		self:Toast(data.Text, data.Kind)
	end)
	Net.Event("Warning").OnClientEvent:Connect(function(data)
		self:ShowWarning(data)
	end)
	Net.Event("Announcement").OnClientEvent:Connect(function(data)
		self:ShowSubtitle(data)
	end)
	Net.Event("Reward").OnClientEvent:Connect(function(data)
		self:RewardPopup(data.Label, data.Amount)
	end)
	Net.Event("PurchaseResult").OnClientEvent:Connect(function(data)
		self:Toast(data.Message, if data.Ok then "good" else "warn")
	end)
	Net.Event("AchievementUnlocked").OnClientEvent:Connect(function(data)
		Sfx.Play("Achievement")
		self:Banner("🏆 " .. string.upper(data.Name), data.Description .. (if data.Reward then "   +" .. data.Reward .. " FC" else ""), C.Credits)
	end)
	Net.Event("Effect").OnClientEvent:Connect(function(data)
		if data.Name == "ObjectiveAdded" then
			Sfx.Play("ObjectiveNew")
		elseif data.Name == "ObjectiveComplete" then
			Sfx.Play("ObjectiveComplete")
			self:Banner("OBJECTIVE COMPLETE", data.Text .. (if data.By then "  ·  " .. data.By else ""), C.Good)
		elseif data.Name == "ObjectiveFailed" then
			self:Toast("Objective failed: " .. data.Text, "danger")
		elseif data.Name == "DecisionResult" then
			self:Banner("DECISION: " .. string.upper(data.Choice), string.format("%d of %d votes", data.Votes or 0, data.Total or 0), C.Accent)
		elseif data.Name == "Revived" then
			self:Banner("YOU'RE BACK ON YOUR FEET", (data.By or "Someone") .. " helped you up", C.Good)
		elseif data.Name == "Evacuated" then
			self:Banner("YOU MADE IT OUT", "Down the slide and away from the aircraft", C.Good)
		end
	end)

	ClientState.ObjectivesChanged:Connect(refreshObjectives)
	ClientState.ConditionChanged:Connect(refreshCondition)
	ClientState.ProfileChanged:Connect(function(profile)
		creditsLabel.Text = Util.FormatNumber(profile.Credits or 0)
	end)
	if ClientState.Profile then
		creditsLabel.Text = Util.FormatNumber(ClientState.Profile.Credits or 0)
	end
	player:GetAttributeChangedSignal("Credits"):Connect(function()
		creditsLabel.Text = Util.FormatNumber(player:GetAttribute("Credits") or 0)
	end)
	player:GetAttributeChangedSignal("InRound"):Connect(function()
		refreshObjectives(ClientState.Objectives)
		refreshCondition(ClientState.Condition)
	end)
	ClientState.SeatAssigned:Connect(function(info)
		seatLabel.Text = tostring(info.Label)
	end)
	ClientState.PhaseChanged:Connect(function(phase)
		if phase == "Boarding" and ClientState.InRound() then
			self:Banner("NOW BOARDING", "Find your seat. Enjoy the flight.", C.Accent)
		elseif phase == "Flight" and ClientState.InRound() then
			self:Banner("WHEELS UP", "Cruising at 35,000 ft", C.Text)
		elseif phase == "FinalEvent" and ClientState.InRound() then
			self:Banner("PREPARE FOR LANDING", "Get to a seat and buckle up", C.Warn)
		end
	end)
	local seatWasVisible = false
	ClientState.FlightState:GetAttributeChangedSignal("OxygenEmergency"):Connect(function()
		refreshCondition(ClientState.Condition)
	end)
	player:GetAttributeChangedSignal("Buckled"):Connect(function()
		buckleLabel.Text = if player:GetAttribute("Buckled") then "🔒 BUCKLED" else ""
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.2 then
			return
		end
		accumulator = 0
		updateTopBar()
		updateWaypoint()
		updateGauge()
		local showSeat = ClientState.Phase() == "Boarding" and ClientState.InRound() and ClientState.Seat ~= nil and not player:GetAttribute("Buckled")
		if showSeat ~= seatWasVisible then
			seatWasVisible = showSeat
			seatChip.Visible = showSeat
		end
		if ClientState.Condition.State == "Unconscious" then
			refreshCondition(ClientState.Condition)
		end
	end)
end

return HUDController
