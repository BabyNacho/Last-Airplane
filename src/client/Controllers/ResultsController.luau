--[[
	ResultsController
	The flight report: outcome, the revealed disaster and its cause, landing grade with the
	factors behind it, decisions and their consequences, survivors / rescues / passengers,
	your personal credit breakdown, unlocked achievements and your victory effect.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)
local ClientState = require(script.Parent.Parent.ClientState)
local Sfx = require(script.Parent.Parent.UI.Sfx)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local ResultsController = {}

local C = UIKit.Colors
local F = UIKit.Fonts

local gui: ScreenGui
local root: Frame
local screen: Frame?
local effectLayer: Frame

local TIER_COLORS = {
	Perfect = Color3.fromRGB(90, 230, 150),
	Successful = Color3.fromRGB(90, 190, 255),
	Hard = Color3.fromRGB(255, 200, 70),
	Emergency = Color3.fromRGB(255, 150, 60),
	Crash = Color3.fromRGB(255, 70, 70),
}

---------------------------------------------------------------- victory effects

local function particle(text: string, color: Color3, size: number, from: UDim2, to: UDim2, duration: number, rotation: number?)
	local label = UIKit.new("TextLabel", {
		Text = text,
		TextColor3 = color,
		TextSize = size,
		Font = F.Heading,
		Size = UDim2.fromOffset(size * 2, size * 2),
		Position = from,
		Rotation = rotation or 0,
		ZIndex = 40,
		Parent = effectLayer,
	})
	UIKit.Tween(label, duration, { Position = to, Rotation = (rotation or 0) + math.random(-180, 180), TextTransparency = 0.2 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(duration, function()
		label:Destroy()
	end)
end

local function victoryEffect(style: string?)
	if not style then
		return
	end
	local rng = Random.new()
	if style == "VictoryConfetti" then
		for _ = 1, 70 do
			local x = rng:NextNumber()
			particle("▮", Color3.fromHSV(rng:NextNumber(), 0.7, 1), rng:NextInteger(10, 18), UDim2.fromScale(x, -0.05), UDim2.fromScale(x + rng:NextNumber(-0.1, 0.1), 1.1), rng:NextNumber(2, 4), rng:NextNumber(0, 360))
		end
	elseif style == "VictoryPaperPlanes" then
		for _ = 1, 24 do
			local y = rng:NextNumber(0.1, 0.9)
			particle("✈", Color3.new(1, 1, 1), rng:NextInteger(20, 34), UDim2.fromScale(-0.1, y), UDim2.fromScale(1.1, y - rng:NextNumber(0.1, 0.3)), rng:NextNumber(2.5, 4.5), 0)
		end
	elseif style == "VictoryFireworks" then
		for burst = 1, 5 do
			task.delay(burst * 0.5, function()
				local cx, cy = rng:NextNumber(0.2, 0.8), rng:NextNumber(0.15, 0.5)
				local hue = rng:NextNumber()
				Sfx.Play("Impact", nil, 0.5)
				for i = 1, 18 do
					local angle = i / 18 * math.pi * 2
					particle("✦", Color3.fromHSV(hue, 0.6, 1), 16, UDim2.fromScale(cx, cy), UDim2.fromScale(cx + math.cos(angle) * 0.15, cy + math.sin(angle) * 0.2), 1.2, 0)
				end
			end)
		end
	elseif style == "VictoryGoldenWings" then
		for _ = 1, 40 do
			local x = rng:NextNumber(0.3, 0.7)
			particle(if rng:NextNumber() < 0.5 then "❖" else "✧", Color3.fromRGB(255, 210, 90), rng:NextInteger(14, 26), UDim2.fromScale(x, 1.05), UDim2.fromScale(x + rng:NextNumber(-0.3, 0.3), rng:NextNumber(-0.1, 0.4)), rng:NextNumber(2, 3.5), 0)
		end
	end
end

---------------------------------------------------------------- layout helpers

local function section(parent: Instance, title: string, order: number): Frame
	local frame = UIKit.Panel({
		BackgroundColor3 = C.Background,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Padding = { 12, 14, 12, 14 },
		LayoutOrder = order,
		Parent = parent,
	})
	UIKit.List(frame, 6)
	UIKit.Text({ Text = title, Font = F.Heading, TextSize = 14, Accent = "TextColor3", Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 0, Parent = frame })
	return frame
end

local function line(parent: Instance, left: string, right: string?, color: Color3?, order: number?)
	local row = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order or 1, Parent = parent })
	UIKit.Text({ Text = left, TextSize = 15, Size = UDim2.new(if right then 0.72 else 1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextColor3 = color or C.Text, Parent = row })
	local rightLabel: TextLabel? = nil
	if right then
		rightLabel = UIKit.Text({ Text = right, Font = F.Bold, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.28, 0, 0, 18), TextColor3 = color or C.Text, Parent = row })
	end
	return row, rightLabel
end

---------------------------------------------------------------- show

function ResultsController:Close()
	if screen then
		screen:Destroy()
		screen = nil
	end
end

function ResultsController:Show(data)
	self:Close()
	local personal = data.Personal
	local frame = UIKit.new("Frame", {
		Name = "Results",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(6, 8, 12),
		BackgroundTransparency = 0.12,
		ZIndex = 30,
		Parent = root,
	})
	screen = frame
	local scroll = UIKit.Scroll({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
		Size = UDim2.new(0.94, 0, 1, -32),
		ZIndex = 31,
		Parent = frame,
	})
	UIKit.new("UISizeConstraint", { MaxSize = Vector2.new(1100, math.huge), Parent = scroll })
	UIKit.List(scroll, 12, nil, Enum.HorizontalAlignment.Center)

	-- header
	local header = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = scroll })
	UIKit.List(header, 2, nil, Enum.HorizontalAlignment.Center)
	UIKit.Text({ Text = string.format("FLIGHT %s → %s", tostring(data.FlightNumber or ""), string.upper(tostring(data.Destination or ""))), Font = F.Bold, TextSize = 14, TextColor3 = C.SubText, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1, Parent = header })
	local title = UIKit.Text({ Text = data.Title, Font = F.Heading, TextSize = 52, TextColor3 = data.Color or C.Text, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 58), LayoutOrder = 2, Parent = header })
	UIKit.Text({ Text = data.Subtitle, TextSize = 18, TextColor3 = C.SubText, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 3, Parent = header })
	title.TextTransparency = 1
	UIKit.Tween(title, 0.8, { TextTransparency = 0 })

	-- reveal
	local reveal = UIKit.Panel({ BackgroundColor3 = Color3.fromRGB(30, 12, 16), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Padding = { 12, 16, 12, 16 }, Stroke = { Color = C.Danger, Transparency = 0.4 }, LayoutOrder = 2, Parent = scroll })
	UIKit.List(reveal, 4)
	UIKit.Text({ Text = "WHAT HAPPENED" .. (if data.Rare then "   ·   ★ RARE DISASTER" else "") .. (if data.Modifier then "   ·   " .. string.upper(data.Modifier) else ""), Font = F.Bold, TextSize = 13, TextColor3 = C.Danger, LayoutOrder = 1, Parent = reveal })
	UIKit.Text({ Text = string.upper(data.Disaster or ""), Font = F.Heading, TextSize = 28, LayoutOrder = 2, Parent = reveal })
	UIKit.Text({ Text = data.Reveal or "", TextSize = 16, TextColor3 = C.SubText, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, Parent = reveal })

	-- two columns
	local columns = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, Parent = scroll })
	local narrow = UIKit.ViewportSize().X < 900
	UIKit.List(columns, 12, if narrow then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal)
	local left = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(if narrow then 1 else 0.5, if narrow then 0 else -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = columns })
	UIKit.List(left, 12)
	local right = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(if narrow then 1 else 0.5, if narrow then 0 else -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = columns })
	UIKit.List(right, 12)

	local landing = section(left, "LANDING", 1)
	line(landing, string.upper(data.LandingTier or "") .. " LANDING", tostring(data.LandingScore or 0) .. "/100", TIER_COLORS[data.LandingTier] or C.Text, 1)
	for index, note in data.LandingNotes or {} do
		local delta = note.Delta or 0
		line(landing, note.Note, if index == 1 then "" elseif delta > 0 then "+" .. delta elseif delta < 0 then tostring(delta) else "", if index == 1 then C.SubText elseif delta >= 0 then C.Good else C.Danger, index + 1)
	end

	local crew = section(left, "PASSENGERS", 2)
	line(crew, "Survivors", string.format("%d / %d", data.Survivors or 0, data.Total or 0), nil, 1)
	line(crew, "Players revived", tostring(data.Rescued or 0), nil, 2)
	local objectives = data.Objectives or {}
	line(crew, "Objectives completed", string.format("%d / %d", objectives.Completed or 0, objectives.Total or 0), nil, 3)
	line(crew, "Injured passengers left behind", tostring(data.PassengersLost or 0), if (data.PassengersLost or 0) > 0 then C.Warn else C.Good, 4)

	if data.Decisions and #data.Decisions > 0 then
		local decisions = section(left, "DECISIONS & CONSEQUENCES", 3)
		for index, decision in data.Decisions do
			local color = if decision.Good == true then C.Good elseif decision.Good == false then C.Danger else C.Text
			line(decisions, string.format("<b>%s</b> → %s  <font color=\"#96a0b4\">(%s)</font>", decision.Title, decision.Choice or "?", decision.By or ""), nil, nil, index * 2)
			if decision.Outcome then
				line(decisions, "   " .. decision.Outcome, nil, color, index * 2 + 1)
			end
		end
	end

	if personal then
		local you = section(right, "YOUR FLIGHT", 1)
		line(you, if personal.Survived then "✔ YOU SURVIVED" else "✖ YOU DIDN'T MAKE IT", nil, if personal.Survived then C.Good else C.Danger, 1)
		if not personal.Survived and personal.Cause then
			line(you, "Cause: " .. personal.Cause, nil, C.SubText, 2)
		end
		local creditsBox = section(right, "FLIGHT CREDITS EARNED", 2)
		for index, entry in personal.Lines or {} do
			line(creditsBox, entry.Label, (if entry.Amount >= 0 then "+" else "") .. entry.Amount, if entry.Amount >= 0 then C.Text else C.Danger, index)
		end
		local _, totalLabel = line(creditsBox, "<b>TOTAL</b>", "0", C.Credits, 100)
		local amountLabel = totalLabel :: TextLabel
		task.spawn(function()
			local target = personal.Credits or 0
			local start = os.clock()
			while os.clock() - start < 1.2 do
				local ratio = (os.clock() - start) / 1.2
				amountLabel.Text = "+" .. Util.FormatNumber(math.floor(target * ratio)) .. " " .. EconomyConfig.CurrencyShort
				RunService.Heartbeat:Wait()
			end
			amountLabel.Text = "+" .. Util.FormatNumber(target) .. " " .. EconomyConfig.CurrencyShort
			Sfx.Play("Reward")
		end)
		if personal.Achievements and #personal.Achievements > 0 then
			local achievements = section(right, "ACHIEVEMENTS UNLOCKED", 3)
			for index, achievement in personal.Achievements do
				line(achievements, "🏆 " .. achievement.Name, "+" .. (achievement.Reward or 0), C.Credits, index)
			end
		end
		if personal.Survived then
			task.delay(0.6, function()
				victoryEffect(personal.VictoryEffect)
			end)
		end
	end

	local manifest = section(right, "PASSENGER MANIFEST", 4)
	for index, row in data.Players or {} do
		local status = if row.Survived then (if row.Evacuated then "EVACUATED" else "SURVIVED") else "LOST"
		line(manifest, string.format("%s  <font color=\"#96a0b4\">· %d obj · %d helped</font>", row.Name, row.Objectives or 0, row.Rescues or 0), status, if row.Survived then C.Good else C.Danger, index)
	end

	UIKit.Button({
		Text = "CONTINUE",
		Size = UDim2.fromOffset(240, UIKit.TouchSize(54)),
		LayoutOrder = 10,
		Parent = scroll,
		OnClick = function()
			self:Close()
		end,
	})
	Sfx.Play(if personal and personal.Survived then "Achievement" else "Warning")
end

function ResultsController:Init()
	gui = UIKit.Screen("ResultsUI", 25)
	root = UIKit.Root(gui)
	effectLayer = UIKit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 40, Parent = root })
end

function ResultsController:Start()
	Net.Event("Results").OnClientEvent:Connect(function(data)
		self:Show(data)
	end)
	ClientState.PhaseChanged:Connect(function(phase)
		if phase == "Boarding" then
			self:Close()
		end
	end)
end

return ResultsController
