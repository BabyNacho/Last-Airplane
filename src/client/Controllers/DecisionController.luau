--[[
	DecisionController
	Decision cards: group votes (live tallies), personal choices and keypad code entry.
	Players keep moving while a decision is open. Choose with a tap/click, number keys 1-4,
	or the gamepad (the first option is auto-selected).
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local Sfx = require(script.Parent.Parent.UI.Sfx)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local DecisionController = {}

local C = UIKit.Colors
local F = UIKit.Fonts
local root: Frame
local card: Frame?
local current: any = nil
local optionButtons: { [string]: TextButton } = {}
local timerFill: Frame?
local queue: { any } = {}

local RISK_COLORS = {
	low = Color3.fromRGB(80, 220, 140),
	medium = Color3.fromRGB(255, 190, 60),
	high = Color3.fromRGB(255, 80, 70),
}

local function closeCard()
	if card then
		card:Destroy()
		card = nil
	end
	current = nil
	table.clear(optionButtons)
	timerFill = nil
	if GuiService.SelectedObject and not GuiService.SelectedObject:IsDescendantOf(game) then
		GuiService.SelectedObject = nil
	end
end

local function vote(optionId: string | number)
	if not current then
		return
	end
	Net.Event("DecisionVote"):FireServer(current.Key, optionId)
	Sfx.Play("Click")
	current.MyVote = optionId
	for id, button in optionButtons do
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Thickness = if id == optionId then 3 else 1.5
			stroke.Transparency = if id == optionId then 0 else 0.5
		end
		button.BackgroundTransparency = if id == optionId then 0 else 0.25
	end
	if current.Kind == "Personal" then
		closeCard()
		DecisionController:ShowNext()
	end
end

local function buildKeypad(parent: Frame)
	local entry = ""
	local display = UIKit.Text({
		Text = "_ _ _ _",
		Font = F.Mono,
		TextSize = 34,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 44),
		LayoutOrder = 3,
		Parent = parent,
	})
	local grid = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 4 * 62),
		LayoutOrder = 4,
		Parent = parent,
	})
	UIKit.new("UIGridLayout", {
		CellSize = UDim2.new(1 / 3, -8, 0, 56),
		CellPadding = UDim2.fromOffset(8, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	local function refresh()
		local shown = {}
		for i = 1, 4 do
			shown[i] = string.sub(entry, i, i)
			if shown[i] == "" then
				shown[i] = "_"
			end
		end
		display.Text = table.concat(shown, " ")
	end
	local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "CLR", "0", "OK" }
	for index, key in keys do
		local button = UIKit.Button({
			Text = key,
			Style = if key == "OK" then "good" elseif key == "CLR" then "danger" else "secondary",
			Size = UDim2.fromOffset(100, 56),
			TextSize = 22,
			LayoutOrder = index,
			Parent = grid,
			OnClick = function()
				if key == "CLR" then
					entry = ""
				elseif key == "OK" then
					if #entry > 0 then
						vote(entry)
					end
					return
				elseif #entry < 4 then
					entry ..= key
				end
				refresh()
			end,
		})
		if index == 5 then
			button.Name = "First"
		end
	end
	return grid
end

local function open(data)
	closeCard()
	current = data
	local touch = UIKit.IsTouch()
	local newCard = UIKit.Panel({
		Name = "Decision",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(if data.Input == "Keypad" then 380 else 620, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.04,
		Stroke = { Color = C.Credits, Thickness = 2 },
		Padding = { 14, 18, 16, 18 },
		ZIndex = 10,
		Parent = root,
	})
	card = newCard
	UIKit.List(newCard, 10, nil, Enum.HorizontalAlignment.Center)
	UIKit.Text({
		Text = (if data.Kind == "Vote" then "GROUP DECISION  ·  " else "YOUR DECISION  ·  ") .. string.upper(data.Speaker or ""),
		Font = F.Bold,
		TextSize = 13,
		TextColor3 = C.Credits,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = 0,
		Parent = newCard,
	})
	UIKit.Text({
		Text = data.Title,
		Font = F.Heading,
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = newCard,
	})
	if data.Prompt and data.Prompt ~= "" then
		UIKit.Text({
			Text = data.Prompt,
			TextSize = 16,
			TextColor3 = C.SubText,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			Parent = newCard,
		})
	end
	local firstButton: GuiObject? = nil
	if data.Input == "Keypad" then
		local grid = buildKeypad(newCard)
		firstButton = grid:FindFirstChild("First") :: GuiObject?
	else
		local options = UIKit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 3,
			Parent = newCard,
		})
		local count = #data.Options
		local horizontal = count <= 2 and not touch
		UIKit.List(options, 10, if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Center)
		for index, option in data.Options do
			local riskColor = RISK_COLORS[option.Risk or "medium"] or C.Accent
			local height = UIKit.TouchSize(if horizontal then 104 else 70)
			local button = UIKit.new("TextButton", {
				Name = option.Id,
				Text = "",
				AutoButtonColor = false,
				Size = if horizontal then UDim2.new(0.5, -5, 0, height) else UDim2.new(1, 0, 0, height),
				BackgroundColor3 = C.PanelLight,
				BackgroundTransparency = 0.25,
				Corner = 10,
				Stroke = { Color = riskColor, Thickness = 1.5, Transparency = 0.5 },
				LayoutOrder = index,
				Padding = { 8, 12, 8, 12 },
				Parent = options,
			}) :: TextButton
			UIKit.Text({
				Text = string.format("<font color=\"#%s\">[%d]</font>  %s", riskColor:ToHex(), index, option.Label),
				Font = F.Heading,
				TextSize = 17,
				Size = UDim2.new(1, -50, 0, 22),
				Parent = button,
			})
			UIKit.Text({
				Name = "Count",
				Text = "",
				Font = F.Mono,
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Right,
				Size = UDim2.new(1, 0, 0, 22),
				Parent = button,
			})
			UIKit.Text({
				Text = option.Description or "",
				TextSize = 14,
				TextColor3 = C.SubText,
				Position = UDim2.fromOffset(0, 24),
				Size = UDim2.new(1, 0, 1, -24),
				TextYAlignment = Enum.TextYAlignment.Top,
				Parent = button,
			})
			button.Activated:Connect(function()
				vote(option.Id)
			end)
			optionButtons[option.Id] = button
			if index == 1 then
				firstButton = button
			end
		end
	end
	local barBack = UIKit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = Color3.fromRGB(45, 50, 65),
		Corner = 3,
		LayoutOrder = 10,
		Parent = newCard,
	})
	timerFill = UIKit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Credits,
		Corner = 3,
		Parent = barBack,
	})
	Sfx.Play("Decision")
	newCard.Position = UDim2.new(0.5, 0, 1, 80)
	UIKit.Tween(newCard, 0.35, { Position = UDim2.new(0.5, 0, 1, -24) }, Enum.EasingStyle.Back)
	if UIKit.IsGamepad() and firstButton then
		GuiService.SelectedObject = firstButton
	end
end

function DecisionController:ShowNext()
	if current or #queue == 0 then
		return
	end
	local data = table.remove(queue, 1)
	if data and data.EndsAt > Workspace:GetServerTimeNow() then
		open(data)
	else
		self:ShowNext()
	end
end

function DecisionController:Init()
	local gui = UIKit.Screen("DecisionUI", 8)
	root = UIKit.Root(gui)
end

function DecisionController:Start()
	Net.Event("DecisionOpened").OnClientEvent:Connect(function(data)
		if current and current.Kind == "Vote" and data.Kind == "Personal" then
			table.insert(queue, 1, current)
			closeCard()
		end
		if current then
			table.insert(queue, data)
		else
			open(data)
		end
	end)
	Net.Event("DecisionUpdated").OnClientEvent:Connect(function(data)
		if current and current.Key == data.Key then
			for id, button in optionButtons do
				local count = button:FindFirstChild("Count") :: TextLabel?
				if count then
					count.Text = tostring(data.Counts[id] or 0) .. " ✋"
				end
			end
		end
	end)
	Net.Event("DecisionClosed").OnClientEvent:Connect(function(data)
		for i = #queue, 1, -1 do
			if queue[i].Key == data.Key then
				table.remove(queue, i)
			end
		end
		if current and current.Key == data.Key then
			closeCard()
			self:ShowNext()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not current or current.Input == "Keypad" then
			return
		end
		local map = { [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4 }
		local index = map[input.KeyCode]
		if index and current.Options[index] then
			vote(current.Options[index].Id)
		end
	end)
	RunService.RenderStepped:Connect(function()
		if current and timerFill then
			local duration = current.Duration or 15
			local left = math.max(0, current.EndsAt - Workspace:GetServerTimeNow())
			timerFill.Size = UDim2.fromScale(left / duration, 1)
			if left <= 0 and current.Kind == "Personal" then
				closeCard()
				self:ShowNext()
			end
		end
	end)
end

return DecisionController
