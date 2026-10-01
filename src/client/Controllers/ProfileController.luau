--[[
	ProfileController
	Flight Records (statistics, achievements, daily/weekly challenges, disaster mastery) and the
	Wardrobe (equip owned cosmetics per slot). All data comes from the server profile snapshot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AchievementConfig = require(ReplicatedStorage.Shared.Config.AchievementConfig)
local DisasterConfig = require(ReplicatedStorage.Shared.Config.DisasterConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local ShopCatalog = require(ReplicatedStorage.Shared.Config.ShopCatalog)
local Util = require(ReplicatedStorage.Shared.Util)
local ClientState = require(script.Parent.Parent.ClientState)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local ProfileController = {}

local C = UIKit.Colors
local F = UIKit.Fonts

local overlay: Frame
local body: ScrollingFrame
local tabs: { [string]: TextButton } = {}
local currentTab = "Stats"

local TABS = { "Stats", "Achievements", "Challenges", "Mastery", "Wardrobe" }

local STAT_LABELS = {
	{ "Flights", "Flights" },
	{ "Survived", "Survived" },
	{ "Deaths", "Deaths" },
	{ "Rate", "Survival rate" },
	{ "Rescues", "Players revived" },
	{ "Aids", "Players treated" },
	{ "PassengersHelped", "Passengers helped" },
	{ "ObjectivesCompleted", "Objectives" },
	{ "PerfectLandings", "Perfect landings" },
	{ "ManualApproaches", "Approaches flown" },
	{ "FiresExtinguished", "Fires extinguished" },
	{ "BraveActions", "Brave actions" },
	{ "Evacuations", "Evacuations" },
	{ "DecisionsMade", "Decisions made" },
	{ "BestStreak", "Best survival streak" },
	{ "CreditsEarned", "Credits earned" },
}

local function clearBody()
	for _, child in body:GetChildren() do
		if child:IsA("GuiObject") or child:IsA("UIGridLayout") or child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

local function renderStats(profile)
	UIKit.new("UIGridLayout", { CellSize = UDim2.new(0.25, -10, 0, 86), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body })
	local stats = profile.Stats or {}
	for index, entry in STAT_LABELS do
		local value
		if entry[1] == "Rate" then
			value = if (stats.Flights or 0) > 0 then math.floor((stats.Survived or 0) / stats.Flights * 100) .. "%" else "-"
		else
			value = Util.FormatNumber(stats[entry[1]] or 0)
		end
		local card = UIKit.Panel({ BackgroundColor3 = C.PanelLight, LayoutOrder = index, Parent = body })
		UIKit.Text({ Text = tostring(value), Font = F.Heading, TextSize = 28, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 32), Accent = "TextColor3", Parent = card })
		UIKit.Text({ Text = string.upper(entry[2]), Font = F.Bold, TextSize = 12, TextColor3 = C.SubText, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(4, 52), Size = UDim2.new(1, -8, 0, 24), Parent = card })
	end
end

local function renderAchievements(profile)
	UIKit.List(body, 8)
	local unlocked = profile.Achievements or {}
	local count = 0
	for _ in unlocked do
		count += 1
	end
	UIKit.Text({ Text = string.format("%d / %d UNLOCKED", count, #AchievementConfig.List), Font = F.Heading, TextSize = 16, Accent = "TextColor3", LayoutOrder = 0, Parent = body })
	for index, achievement in AchievementConfig.List do
		local done = unlocked[achievement.Id] ~= nil
		local row = UIKit.Panel({ BackgroundColor3 = if done then Color3.fromRGB(30, 48, 38) else C.PanelLight, Size = UDim2.new(1, -8, 0, 64), LayoutOrder = if done then index else 100 + index, Parent = body })
		UIKit.Text({ Text = if done then "🏆" else "🔒", TextSize = 28, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromOffset(56, 64), Parent = row })
		UIKit.Text({ Text = achievement.Name, Font = F.Heading, TextSize = 17, TextColor3 = if done then C.Good else C.Text, Position = UDim2.fromOffset(60, 10), Size = UDim2.new(1, -200, 0, 22), Parent = row })
		local extra = if achievement.Title then "  ·  Unlocks title \"" .. (ShopCatalog.Get(achievement.Title) and ShopCatalog.Get(achievement.Title).Name or "") .. "\"" else ""
		UIKit.Text({ Text = achievement.Description .. extra, TextSize = 13, TextColor3 = C.SubText, Position = UDim2.fromOffset(60, 34), Size = UDim2.new(1, -200, 0, 20), Parent = row })
		UIKit.Text({ Text = "✈ " .. (achievement.Reward or 0), Font = F.Bold, TextSize = 15, TextColor3 = C.Credits, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 0), Size = UDim2.fromOffset(120, 64), Parent = row })
	end
end

local function challengeRow(challenge, order: number)
	local row = UIKit.Panel({ BackgroundColor3 = if challenge.Done then Color3.fromRGB(30, 48, 38) else C.PanelLight, Size = UDim2.new(1, -8, 0, 70), LayoutOrder = order, Parent = body })
	UIKit.Text({ Text = (if challenge.Done then "✔ " else "") .. challenge.Text, Font = F.Bold, TextSize = 16, TextColor3 = if challenge.Done then C.Good else C.Text, Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -160, 0, 22), Parent = row })
	UIKit.Text({ Text = "✈ " .. challenge.Reward, Font = F.Bold, TextSize = 15, TextColor3 = C.Credits, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 10), Size = UDim2.fromOffset(120, 22), Parent = row })
	local _, set = UIKit.Bar({ Parent = row, Position = UDim2.fromOffset(16, 42), Size = UDim2.new(1, -120, 0, 10), Color = if challenge.Done then C.Good else C.Accent })
	set(challenge.Progress / math.max(1, challenge.Goal))
	UIKit.Text({ Text = string.format("%d/%d", challenge.Progress, challenge.Goal), Font = F.Mono, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 38), Size = UDim2.fromOffset(90, 18), Parent = row })
end

local function renderChallenges(profile)
	UIKit.List(body, 8)
	local view = profile.Challenges
	if not view then
		UIKit.Text({ Text = "Challenges unavailable right now.", TextColor3 = C.SubText, Parent = body })
		return
	end
	local reset = view.DailyResetIn or 0
	UIKit.Text({ Text = string.format("DAILY  ·  resets in %dh %dm", reset // 3600, (reset % 3600) // 60), Font = F.Heading, TextSize = 16, Accent = "TextColor3", LayoutOrder = 0, Parent = body })
	for index, challenge in view.Daily do
		challengeRow(challenge, index)
	end
	UIKit.Text({ Text = "WEEKLY", Font = F.Heading, TextSize = 16, Accent = "TextColor3", LayoutOrder = 50, Parent = body })
	for index, challenge in view.Weekly do
		challengeRow(challenge, 50 + index)
	end
end

local function masteryLevel(count: number): (string, number?)
	local name = "Untested"
	local nextGoal = nil
	for _, level in AchievementConfig.MasteryLevels do
		if count >= level.Goal then
			name = level.Name
		elseif not nextGoal then
			nextGoal = level.Goal
		end
	end
	return name, nextGoal
end

local function renderMastery(profile)
	UIKit.new("UIGridLayout", { CellSize = UDim2.new(0.333, -10, 0, 100), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body })
	local survived = profile.DisastersSurvived or {}
	local ids = {}
	for id in DisasterConfig.Disasters do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		return DisasterConfig.Disasters[a].DisplayName < DisasterConfig.Disasters[b].DisplayName
	end)
	for index, id in ids do
		local def = DisasterConfig.Disasters[id]
		local count = survived[id] or 0
		local level, nextGoal = masteryLevel(count)
		local card = UIKit.Panel({ BackgroundColor3 = if count > 0 then C.PanelLight else C.Background, LayoutOrder = index, Parent = body })
		UIKit.Text({ Text = if count > 0 then string.upper(def.DisplayName) else "???", Font = F.Heading, TextSize = 16, Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 20), Parent = card })
		UIKit.Text({ Text = level .. (if def.Rare then "  ·  RARE" else ""), Font = F.Bold, TextSize = 13, Accent = "TextColor3", Position = UDim2.fromOffset(14, 34), Size = UDim2.new(1, -28, 0, 16), Parent = card })
		local _, set = UIKit.Bar({ Parent = card, Position = UDim2.fromOffset(14, 60), Size = UDim2.new(1, -28, 0, 8) })
		set(if nextGoal then count / nextGoal else 1)
		UIKit.Text({ Text = string.format("Survived %d%s", count, if nextGoal then " / " .. nextGoal else " · MAX"), TextSize = 12, TextColor3 = C.SubText, Position = UDim2.fromOffset(14, 74), Size = UDim2.new(1, -28, 0, 16), Parent = card })
	end
end


local function renderWardrobe(profile)
	UIKit.List(body, 10)
	local owned = profile.Owned or {}
	local equipped = profile.Equipped or {}
	for order, slot in ShopCatalog.Slots do
		local info = ShopCatalog.SlotInfo[slot] or {}
		UIKit.Text({ Text = (info.Icon and info.Icon .. "  " or "") .. (info.Label or slot), Font = F.Heading, TextSize = 15, Accent = "TextColor3", LayoutOrder = order * 2, Parent = body })
		local row = UIKit.Scroll({
			Size = UDim2.new(1, -8, 0, UIKit.TouchSize(50) + 8),
			AutomaticCanvasSize = Enum.AutomaticSize.X,
			ScrollingDirection = Enum.ScrollingDirection.X,
			LayoutOrder = order * 2 + 1,
			Parent = body,
		})
		UIKit.List(row, 8, Enum.FillDirection.Horizontal)
		local count = 0
		local canUnequip = not info.Required
		if canUnequip then
			UIKit.Button({
				Text = "NONE",
				Style = if equipped[slot] == nil then "primary" else "secondary",
				Size = UDim2.fromOffset(110, UIKit.TouchSize(50)),
				TextSize = 14,
				LayoutOrder = 0,
				Parent = row,
				OnClick = function()
					Net.Event("Equip"):FireServer(slot, nil)
				end,
			})
		end
		for _, item in ShopCatalog.Items do
			if item.Slot == slot and table.find(owned, item.Id) then
				count += 1
				local isOn = equipped[slot] == item.Id
				local button = UIKit.Button({
					Text = (if isOn then "✔ " else "") .. item.Name,
					Style = if isOn then "primary" else "secondary",
					Size = UDim2.fromOffset(190, UIKit.TouchSize(50)),
					TextSize = 14,
					LayoutOrder = item.Order,
					Parent = row,
					OnClick = function()
						Net.Event("Equip"):FireServer(slot, item.Id)
					end,
				})
				UIKit.new("Frame", { Size = UDim2.new(0, 4, 0.6, 0), Position = UDim2.new(0, 6, 0.2, 0), BackgroundColor3 = item.Color or C.Accent, Corner = 2, Parent = button })
			end
		end
		if count == 0 then
			UIKit.Text({ Text = "Nothing owned yet - visit the Sky Shop!", TextSize = 14, TextColor3 = C.SubText, Size = UDim2.fromOffset(400, 50), LayoutOrder = 1, Parent = row })
		end
	end
end

local function render()
	clearBody()
	for name, tab in tabs do
		tab.BackgroundColor3 = if name == currentTab then C.Accent else C.PanelLight
	end
	local profile = ClientState.Profile
	if not profile then
		UIKit.List(body, 8)
		UIKit.Text({ Text = "Loading your records...", TextColor3 = C.SubText, Parent = body })
		return
	end
	if profile.Temporary then
		UIKit.Text({ Text = "⚠ Progress is temporarily not saving - it will be merged once the servers recover.", TextColor3 = C.Warn, TextSize = 14, LayoutOrder = -1, Parent = body })
	end
	if currentTab == "Stats" then
		renderStats(profile)
	elseif currentTab == "Achievements" then
		renderAchievements(profile)
	elseif currentTab == "Challenges" then
		renderChallenges(profile)
	elseif currentTab == "Mastery" then
		renderMastery(profile)
	else
		renderWardrobe(profile)
	end
end

function ProfileController:Open(tab: string?)
	if tab == "Records" then
		tab = "Stats"
	end
	currentTab = tab or currentTab
	render()
	UIKit.OpenWindow(overlay)
	task.spawn(function()
		local ok, snapshot = pcall(function()
			return Net.Function("GetProfile"):InvokeServer()
		end)
		if ok and snapshot then
			ClientState.Profile = snapshot
			ClientState.ProfileChanged:Fire(snapshot)
		end
	end)
end

function ProfileController:Init()
	local gui = UIKit.Screen("ProfileUI", 20)
	local root = UIKit.Root(gui)
	local content
	overlay, content = UIKit.Window(root, "FLIGHT RECORDS", UDim2.new(0.9, 0, 0.9, 0))
	local tabHeight = UIKit.TouchSize(44)
	local tabBar = UIKit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, tabHeight), ZIndex = 22, Parent = content })
	UIKit.List(tabBar, 8, Enum.FillDirection.Horizontal)
	for index, name in TABS do
		tabs[name] = UIKit.Button({
			Text = string.upper(name),
			Style = "secondary",
			Size = UDim2.new(0, 150, 1, 0),
			TextSize = 15,
			LayoutOrder = index,
			ZIndex = 23,
			Parent = tabBar,
			OnClick = function()
				currentTab = name
				render()
			end,
		})
	end
	body = UIKit.Scroll({
		Position = UDim2.fromOffset(0, tabHeight + 12),
		Size = UDim2.new(1, 0, 1, -(tabHeight + 12)),
		ZIndex = 22,
		Parent = content,
	})
	UIKit.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 8), Parent = body })
end

function ProfileController:Start()
	ClientState.ProfileChanged:Connect(function(profile)
		if profile.Equipped and profile.Equipped.Theme then
			local theme = ShopCatalog.Get(profile.Equipped.Theme)
			if theme and theme.Data and theme.Data.Accent then
				UIKit.SetAccent(theme.Data.Accent)
			end
		end
		if overlay.Visible then
			render()
		end
	end)
end

return ProfileController
