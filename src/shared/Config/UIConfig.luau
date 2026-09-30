--[[
	UIConfig
	Visual language for every interface.
]]

local UIConfig = {}

UIConfig.Colors = {
	Background = Color3.fromRGB(14, 17, 24),
	Panel = Color3.fromRGB(22, 27, 38),
	PanelLight = Color3.fromRGB(34, 41, 56),
	Stroke = Color3.fromRGB(60, 70, 92),
	Text = Color3.fromRGB(236, 240, 248),
	SubText = Color3.fromRGB(150, 160, 180),
	Accent = Color3.fromRGB(70, 150, 255),
	Good = Color3.fromRGB(70, 220, 130),
	Warn = Color3.fromRGB(255, 190, 50),
	Danger = Color3.fromRGB(255, 70, 70),
	Critical = Color3.fromRGB(255, 50, 90),
	Credits = Color3.fromRGB(255, 205, 80),
	Optional = Color3.fromRGB(140, 180, 255),
}

UIConfig.ConditionColors = {
	Healthy = Color3.fromRGB(70, 220, 130),
	Injured = Color3.fromRGB(255, 190, 50),
	Critical = Color3.fromRGB(255, 80, 60),
	Unconscious = Color3.fromRGB(190, 90, 255),
	Dead = Color3.fromRGB(120, 120, 130),
}

UIConfig.Fonts = {
	Heading = Enum.Font.GothamBlack,
	Bold = Enum.Font.GothamBold,
	Body = Enum.Font.GothamMedium,
	Mono = Enum.Font.RobotoMono,
}

-- Reference resolution for UIScale; everything scales from this.
UIConfig.ReferenceSize = Vector2.new(1280, 720)
UIConfig.MinScale = 0.5
UIConfig.MaxScale = 1.35
UIConfig.MinTouchTarget = 44 -- pixels, applied after scaling

UIConfig.PhaseNames = {
	Lobby = "WAITING FOR NEXT FLIGHT",
	Boarding = "BOARDING",
	Flight = "IN FLIGHT",
	Disaster = "IN FLIGHT",
	Crisis = "EMERGENCY",
	FinalEvent = "PREPARE FOR LANDING",
	Landing = "LANDING",
	Evacuation = "EVACUATE",
	Results = "FLIGHT REPORT",
}

return UIConfig
