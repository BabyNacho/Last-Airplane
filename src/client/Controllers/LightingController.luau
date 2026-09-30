--[[
	LightingController
	Client-side cabin lighting (normal / dim / flicker / emergency / off), emergency floor strips,
	seatbelt signs, cockpit screens, weather & time of day (Night Flight, storms, fog) and the
	per-section smoke that reduces visibility near fires. Running this locally keeps flicker
	effects smooth without network traffic.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MapConfig = require(ReplicatedStorage.Shared.Config.MapConfig)
local ClientState = require(script.Parent.Parent.ClientState)

local LightingController = {}

local LIGHT_ON = Color3.fromRGB(255, 246, 225)
local LIGHT_OFF = Color3.fromRGB(70, 70, 72)
local EMERGENCY_ON = Color3.fromRGB(255, 60, 40)
local EMERGENCY_OFF = Color3.fromRGB(60, 20, 20)

local atmosphere: Atmosphere
local colorCorrection: ColorCorrectionEffect
local blur: BlurEffect
local mode = "Normal"
local flickerState = true
local nextFlicker = 0

local function setCabin(brightness: number, color: Color3)
	for _, strip in CollectionService:GetTagged("CabinLight") do
		if strip:IsA("BasePart") then
			strip.Color = color
			strip.Material = if brightness > 0.05 then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end
	for _, source in CollectionService:GetTagged("CabinLightSource") do
		local light = source:FindFirstChildOfClass("PointLight")
		if light then
			light.Brightness = 0.85 * brightness
			light.Enabled = brightness > 0.02
			light.Color = color
		end
	end
end

local function setEmergency(on: boolean)
	for _, strip in CollectionService:GetTagged("EmergencyLight") do
		if strip:IsA("BasePart") then
			strip.Color = if on then EMERGENCY_ON else EMERGENCY_OFF
		end
	end
end

local function applyMode(newMode: string)
	mode = newMode or "Normal"
	if mode == "Normal" then
		setCabin(1, LIGHT_ON)
		setEmergency(false)
	elseif mode == "Dim" then
		setCabin(0.45, Color3.fromRGB(230, 215, 190))
		setEmergency(false)
	elseif mode == "Emergency" then
		setCabin(0.12, Color3.fromRGB(255, 120, 90))
		setEmergency(true)
	elseif mode == "Off" then
		setCabin(0, LIGHT_OFF)
		setEmergency(false)
	elseif mode == "Flicker" then
		setEmergency(false)
	end
end

local function applySeatbelt(on: boolean)
	for _, sign in CollectionService:GetTagged("SeatbeltSign") do
		local gui = sign:FindFirstChildOfClass("SurfaceGui")
		local label = gui and gui:FindFirstChildOfClass("TextLabel")
		if label then
			label.TextColor3 = if on then Color3.fromRGB(255, 200, 60) else Color3.fromRGB(90, 90, 90)
		end
	end
end

local function applyScreens()
	local failed = ClientState.Flight("InstrumentsFailed") == true
	local power = ClientState.Flight("MainPower") ~= false
	for _, screen in CollectionService:GetTagged("CockpitScreen") do
		if screen:IsA("BasePart") then
			screen.Color = if failed then Color3.fromRGB(10, 10, 12) elseif power then Color3.fromRGB(20, 40, 70) else Color3.fromRGB(40, 30, 10)
		end
	end
end

local function environment()
	local inPlane = false
	local camera = workspace.CurrentCamera
	local section = "Outside"
	if camera then
		inPlane = MapConfig.IsInsidePlane(camera.Focus.Position)
		if inPlane then
			section = MapConfig.SectionAt(MapConfig.ToLocal(camera.Focus.Position).X)
		end
	end
	local night = ClientState.Flight("Night") == true or ClientState.GameState:GetAttribute("Modifier") == "Night Flight"
	local weather = ClientState.Flight("Weather") or "Clear"
	local storm = ClientState.Flight("Storm") or 0
	local visibility = ClientState.Flight("Visibility") or 1
	local smoke = if inPlane then (ClientState.Flight("Smoke_" .. section) or 0) else 0

	local targetClock = 14
	local ambient = Color3.fromRGB(90, 90, 100)
	local density = 0.28
	local haze = 1
	local atmoColor = Color3.fromRGB(199, 199, 199)
	if inPlane then
		if night then
			targetClock = 0.5
			ambient = Color3.fromRGB(40, 40, 55)
		end
		if weather == "Storm" or storm > 0 then
			targetClock = if night then 0.5 else 18.2
			ambient = Color3.fromRGB(55, 55, 70)
			density = 0.45
			haze = 3
			atmoColor = Color3.fromRGB(90, 95, 110)
		elseif weather == "Cloudy" then
			density = 0.36
			haze = 2
			atmoColor = Color3.fromRGB(170, 175, 185)
		elseif weather == "Fog" then
			density = 0.35 + (1 - visibility) * 0.55
			haze = 4
			atmoColor = Color3.fromRGB(200, 205, 210)
		end
		if smoke > 0 then
			density = math.max(density, 0.35 + smoke * 0.55)
			haze = 6
			atmoColor = Color3.fromRGB(60, 58, 55)
		end
	end
	Lighting.ClockTime = targetClock
	Lighting.Ambient = ambient
	Lighting.OutdoorAmbient = ambient
	atmosphere.Density = density
	atmosphere.Haze = haze
	atmosphere.Color = atmoColor
	atmosphere.Decay = atmoColor
	colorCorrection.TintColor = if smoke > 0.4 then Color3.fromRGB(255, 225, 200) else Color3.new(1, 1, 1)
end

function LightingController:Init()
	atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.2
	atmosphere.Parent = Lighting
	colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "LF_ColorCorrection"
	colorCorrection.Parent = Lighting
	blur = Instance.new("BlurEffect")
	blur.Name = "LF_Blur"
	blur.Size = 0
	blur.Parent = Lighting
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = 0.6
	bloom.Threshold = 1.6
	bloom.Size = 20
	bloom.Parent = Lighting
end

function LightingController:GetBlur(): BlurEffect
	return blur
end

function LightingController:GetColorCorrection(): ColorCorrectionEffect
	return colorCorrection
end

function LightingController:Start()
	ClientState.OnFlight("CabinLights", applyMode)
	ClientState.OnFlight("SeatbeltSign", function(on)
		applySeatbelt(on == true)
	end)
	ClientState.OnFlight("InstrumentsFailed", applyScreens)
	ClientState.OnFlight("MainPower", applyScreens)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		if mode == "Flicker" then
			local now = os.clock()
			if now >= nextFlicker then
				flickerState = not flickerState
				nextFlicker = now + (if flickerState then math.random(5, 30) / 100 else math.random(3, 15) / 100)
				setCabin(if flickerState then 0.9 else 0.05, if flickerState then LIGHT_ON else LIGHT_OFF)
			end
		end
		accumulator += dt
		if accumulator >= 0.3 then
			accumulator = 0
			environment()
		end
	end)
end

return LightingController
