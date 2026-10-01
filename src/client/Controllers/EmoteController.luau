--[[
	EmoteController
	Emote picker (lobby button, [B] key or gamepad D-pad up). Lists owned emotes; the server
	validates ownership and plays the animation for everyone.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local ShopCatalog = require(ReplicatedStorage.Shared.Config.ShopCatalog)
local ClientState = require(script.Parent.Parent.ClientState)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local EmoteController = {}

local panel: Frame
local list: ScrollingFrame

local function render()
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local profile = ClientState.Profile
	local owned = profile and profile.Owned or {}
	local favourite = profile and profile.Equipped and profile.Equipped.Emote
	local count = 0
	for _, item in ShopCatalog.Items do
		if item.Type == "Emote" and (item.Default or table.find(owned, item.Id)) then
			count += 1
			local isFavourite = item.Id == favourite
			UIKit.Button({
				Text = (if isFavourite then "★ " else "") .. (item.Data.Bubble and item.Data.Bubble .. "  " or "") .. item.Name,
				Style = if isFavourite then "primary" else "secondary",
				Size = UDim2.new(1, 0, 0, UIKit.TouchSize(46)),
				TextSize = 16,
				LayoutOrder = if isFavourite then -1 else item.Order,
				Parent = list,
				OnClick = function()
					Net.Event("PlayEmote"):FireServer(item.Id)
					panel.Visible = false
				end,
			})
		end
	end
	if count == 0 then
		UIKit.Text({ Text = "No emotes yet", TextColor3 = UIKit.Colors.SubText, Parent = list })
	end
end

function EmoteController:Toggle()
	panel.Visible = not panel.Visible
	if panel.Visible then
		render()
	end
end

function EmoteController:Init()
	local gui = UIKit.Screen("EmoteUI", 7)
	local root = UIKit.Root(gui)
	panel = UIKit.Panel({
		Name = "Emotes",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 224, 0.5, 0),
		Size = UDim2.fromOffset(240, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Padding = { 12, 12, 12, 12 },
		Parent = root,
	})
	UIKit.List(panel, 8)
	UIKit.Text({ Text = "EMOTES  [B]", Font = UIKit.Fonts.Heading, TextSize = 16, Accent = "TextColor3", LayoutOrder = 0, Parent = panel })
	-- scrolls once you own lots of emotes
	list = UIKit.Scroll({ Size = UDim2.new(1, 0, 0, 380), LayoutOrder = 1, Parent = panel })
	UIKit.List(list, 6)
end

function EmoteController:Start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.B or input.KeyCode == Enum.KeyCode.DPadUp then
			self:Toggle()
		end
	end)
	ClientState.ProfileChanged:Connect(function()
		if panel.Visible then
			render()
		end
	end)
end

return EmoteController
