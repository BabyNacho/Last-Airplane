--[[
	ChatTagController
	Adds the sender's equipped title (and a VIP star) in front of chat messages using
	TextChatService. Titles come from player attributes set by the server's CosmeticService.
]]

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local ChatTagController = {}

function ChatTagController:Start()
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		return
	end
	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local properties = Instance.new("TextChatMessageProperties")
		local source = message.TextSource
		local sender = source and Players:GetPlayerByUserId(source.UserId)
		if sender then
			local prefix = ""
			if sender:GetAttribute("VIP") then
				prefix ..= "<font color=\"#FFC832\">★ VIP</font> "
			end
			local title = sender:GetAttribute("Title")
			local color = sender:GetAttribute("TitleColor")
			if title and title ~= "Passenger" then
				local hex = if typeof(color) == "Color3" then color:ToHex() else "C8C8D2"
				prefix ..= string.format("<font color=\"#%s\">[%s]</font> ", hex, title)
			end
			properties.PrefixText = prefix .. message.PrefixText
		end
		return properties
	end
end

return ChatTagController
