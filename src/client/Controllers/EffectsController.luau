--[[
	EffectsController
	Cinematic feedback, always subordinate to gameplay clarity:
	  camera shake (events + ambient turbulence), subtle cabin tilt from aircraft attitude,
	  flashes and lightning, damage vignette, hypoxia tunnel vision + blur, unconscious blackout,
	  decompression fog bursts, sparks, cracked windows/windshield and glitching instruments.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MapConfig = require(ReplicatedStorage.Shared.Config.MapConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local ClientState = require(script.Parent.Parent.ClientState)
local Sfx = require(script.Parent.Parent.UI.Sfx)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local EffectsController = {}

local controllers: any
local overlay: Frame
local flashFrame: Frame
local vignette: CanvasGroup
local tunnel: CanvasGroup
local blackout: Frame
local blackoutText: TextLabel

local shakes: { { Intensity: number, Ends: number, Duration: number } } = {}
local wobbleUntil = 0
local rng = Random.new()

---------------------------------------------------------------- overlays

-- Screen-edge vignette from four gradient strips inside a CanvasGroup (fade via GroupTransparency).
local function makeVignette(color: Color3, zIndex: number, depth: number): CanvasGroup
	local group = UIKit.new("CanvasGroup", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		ZIndex = zIndex,
		Parent = overlay,
	}) :: CanvasGroup
	local edges = {
		{ Size = UDim2.new(1, 0, depth, 0), Position = UDim2.fromScale(0, 0), Rotation = 90 },
		{ Size = UDim2.new(1, 0, depth, 0), Position = UDim2.new(0, 0, 1 - depth, 0), Rotation = -90 },
		{ Size = UDim2.new(depth * 0.6, 0, 1, 0), Position = UDim2.fromScale(0, 0), Rotation = 0 },
		{ Size = UDim2.new(depth * 0.6, 0, 1, 0), Position = UDim2.new(1 - depth * 0.6, 0, 0, 0), Rotation = 180 },
	}
	for _, edge in edges do
		local frame = UIKit.new("Frame", {
			Size = edge.Size,
			Position = edge.Position,
			BackgroundColor3 = color,
			ZIndex = zIndex,
			Parent = group,
		})
		UIKit.new("UIGradient", {
			Rotation = edge.Rotation,
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
			Parent = frame,
		})
	end
	return group
end

local function buildOverlays()
	local gui = UIKit.Screen("EffectsUI", 1, true)
	overlay = UIKit.Root(gui)
	flashFrame = UIKit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = overlay,
	})
	vignette = makeVignette(Color3.fromRGB(200, 0, 0), 2, 0.3)
	tunnel = makeVignette(Color3.new(0, 0, 0), 3, 0.42)
	blackout = UIKit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = overlay,
	})
	blackoutText = UIKit.Text({
		Text = "",
		Font = UIKit.Fonts.Heading,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(220, 200, 255),
		TextTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.new(0.8, 0, 0, 70),
		ZIndex = 5,
		Parent = overlay,
	})
end

function EffectsController:Flash(color: Color3?, duration: number?, strength: number?)
	flashFrame.BackgroundColor3 = color or Color3.new(1, 1, 1)
	flashFrame.BackgroundTransparency = 1 - (strength or 0.85)
	UIKit.Tween(flashFrame, duration or 0.4, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
end

function EffectsController:Shake(intensity: number, duration: number)
	table.insert(shakes, { Intensity = intensity, Ends = os.clock() + duration, Duration = duration })
end

local function hurt(amount: number)
	local strength = math.clamp(amount / 25, 0.15, 0.7)
	vignette.GroupTransparency = 1 - strength
	UIKit.Tween(vignette, 0.8, { GroupTransparency = 1 })
	EffectsController:Shake(math.clamp(amount / 20, 0.2, 1), 0.3)
end

---------------------------------------------------------------- world effects

local function burst(position: Vector3, props: { [string]: any }, lifetime: number)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.new(1, 1, 1)
	holder.Position = position
	holder.Parent = Workspace
	local emitter = Instance.new("ParticleEmitter")
	for key, value in props do
		if key ~= "EmitCount" then
			(emitter :: any)[key] = value
		end
	end
	emitter.Parent = holder
	emitter:Emit(props.EmitCount or 30)
	emitter.Enabled = false
	task.delay(lifetime, function()
		holder:Destroy()
	end)
end

local function sparks(position: Vector3)
	burst(position, {
		Color = ColorSequence.new(Color3.fromRGB(255, 230, 120)),
		LightEmission = 1,
		Size = NumberSequence.new(0.2),
		Speed = NumberRange.new(10, 22),
		SpreadAngle = Vector2.new(80, 80),
		Lifetime = NumberRange.new(0.3, 0.7),
		Acceleration = Vector3.new(0, -50, 0),
		EmitCount = 40,
	}, 2)
	Sfx.Play("Sparks", position)
end

local function decompression(position: Vector3?)
	local center = position or MapConfig.ToWorld(Vector3.new(0, 6, 0))
	for i = -3, 3 do
		burst(MapConfig.ToWorld(Vector3.new(i * 18, 7, 0)), {
			Color = ColorSequence.new(Color3.fromRGB(235, 240, 245)),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) }),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 14) }),
			Speed = NumberRange.new(4, 10),
			SpreadAngle = Vector2.new(180, 180),
			Lifetime = NumberRange.new(2, 4),
			Drag = 2,
			EmitCount = 25,
		}, 5)
	end
	burst(center, {
		Color = ColorSequence.new(Color3.fromRGB(250, 250, 250)),
		Size = NumberSequence.new(0.4),
		Speed = NumberRange.new(20, 40),
		SpreadAngle = Vector2.new(180, 180),
		Lifetime = NumberRange.new(1, 2),
		EmitCount = 60,
	}, 3)
	EffectsController:Flash(Color3.new(1, 1, 1), 1.2, 0.6)
	EffectsController:Shake(1.5, 1.2)
end

local function lightning(big: boolean)
	local camera = Workspace.CurrentCamera
	if not camera or not MapConfig.IsInsidePlane(camera.Focus.Position) then
		return
	end
	EffectsController:Flash(Color3.fromRGB(220, 230, 255), if big then 0.6 else 0.25, if big then 0.9 else 0.35)
	local side = if rng:NextNumber() < 0.5 then -1 else 1
	local bolt = Instance.new("Part")
	bolt.Anchored = true
	bolt.CanCollide = false
	bolt.CanQuery = false
	bolt.Material = Enum.Material.Neon
	bolt.Color = Color3.fromRGB(210, 225, 255)
	bolt.Size = Vector3.new(2, 260, 2)
	bolt.CFrame = CFrame.new(MapConfig.ToWorld(Vector3.new(rng:NextNumber(-80, 60), 30, side * rng:NextNumber(90, 220)))) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-15, 15)))
	bolt.Parent = Workspace
	local light = Instance.new("PointLight")
	light.Range = 60
	light.Brightness = 6
	light.Color = bolt.Color
	light.Parent = bolt
	task.delay(if big then 0.25 else 0.12, function()
		bolt:Destroy()
	end)
end

local function crackWindow(window: BasePart, cracked: boolean)
	local existing = window:FindFirstChild("LF_Crack")
	if not cracked then
		if existing then
			existing:Destroy()
		end
		return
	end
	if existing then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LF_Crack"
	gui.Face = if (window:GetAttribute("Side") or 1) > 0 then Enum.NormalId.Front else Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0
	gui.Parent = window
	for i = 1, 9 do
		local line = Instance.new("Frame")
		line.AnchorPoint = Vector2.new(0, 0.5)
		line.Position = UDim2.fromScale(0.5, 0.5)
		line.Size = UDim2.new(rng:NextNumber(0.3, 0.7), 0, 0, 2)
		line.Rotation = i * 40 + rng:NextNumber(-12, 12)
		line.BackgroundColor3 = Color3.new(1, 1, 1)
		line.BackgroundTransparency = 0.2
		line.BorderSizePixel = 0
		line.Parent = gui
	end
end

local function watchWindows()
	local function watch(window: Instance)
		if not window:IsA("BasePart") then
			return
		end
		window:GetAttributeChangedSignal("Cracked"):Connect(function()
			crackWindow(window, window:GetAttribute("Cracked") == true)
			if window:GetAttribute("Cracked") then
				Sfx.Play("GlassCrack", window.Position)
			end
		end)
		window:GetAttributeChangedSignal("Sealed"):Connect(function()
			window.Color = if window:GetAttribute("Sealed") then Color3.fromRGB(180, 185, 195) else Color3.fromRGB(170, 205, 230)
		end)
	end
	for _, window in CollectionService:GetTagged("CabinWindow") do
		watch(window)
	end
	CollectionService:GetInstanceAddedSignal("CabinWindow"):Connect(watch)
end

local function glitchInstruments(duration: number)
	local screens = CollectionService:GetTagged("CockpitScreen")
	local ends = os.clock() + duration
	task.spawn(function()
		while os.clock() < ends do
			for _, screen in screens do
				if screen:IsA("BasePart") then
					screen.Color = if rng:NextNumber() < 0.5 then Color3.fromRGB(10, 10, 12) else Color3.fromRGB(60, 20, 90)
				end
			end
			task.wait(0.08)
		end
		for _, screen in screens do
			if screen:IsA("BasePart") then
				screen.Color = Color3.fromRGB(20, 40, 70)
			end
		end
	end)
end

local function windshieldCrack()
	for _, windshield in CollectionService:GetTagged("Windshield") do
		if windshield:IsA("BasePart") then
			windshield:SetAttribute("Side", -1)
			crackWindow(windshield, true)
		end
	end
	Sfx.Play("GlassCrack")
end

---------------------------------------------------------------- per-frame

local function conditionOverlays()
	local condition = ClientState.Condition
	local tracked = condition.Tracked and ClientState.InRound()
	local state = condition.State
	-- critical pulse
	if tracked and state == "Critical" then
		local pulse = 0.55 + math.sin(os.clock() * 4) * 0.15
		if vignette.GroupTransparency > pulse then
			vignette.GroupTransparency = pulse
		end
	end
	-- hypoxia
	local oxygen = if tracked then condition.Oxygen or 100 else 100
	local hypoxia = math.clamp((45 - oxygen) / 45, 0, 1)
	tunnel.GroupTransparency = 1 - hypoxia * 0.9
	local blur = controllers.LightingController:GetBlur()
	local target = hypoxia * 10 + (if tracked and state == "Unconscious" then 16 else 0)
	blur.Size += (target - blur.Size) * 0.1
	-- unconscious blackout
	local down = tracked and state == "Unconscious"
	local goal = if down then 0.15 else 1
	blackout.BackgroundTransparency += (goal - blackout.BackgroundTransparency) * 0.08
	blackoutText.TextTransparency = if down then 0 else 1
	if down then
		blackoutText.Text = string.format("YOU'RE UNCONSCIOUS\nA teammate can help you up  ·  %ds", math.ceil(condition.BleedOut or 0))
	end
end

local function cameraStep()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local now = os.clock()
	local intensity = 0
	for i = #shakes, 1, -1 do
		local shake = shakes[i]
		if now >= shake.Ends then
			table.remove(shakes, i)
		else
			local remaining = (shake.Ends - now) / shake.Duration
			intensity = math.max(intensity, shake.Intensity * remaining)
		end
	end
	local inPlane = MapConfig.IsInsidePlane(camera.Focus.Position)
	if inPlane then
		local turbulence = ClientState.Flight("Turbulence") or 0
		intensity = math.max(intensity, turbulence * 0.06)
		if now < wobbleUntil then
			intensity = math.max(intensity, 0.12)
		end
	end
	local offset = CFrame.identity
	if intensity > 0 then
		local amount = intensity * 0.012
		offset = CFrame.Angles(rng:NextNumber(-amount, amount), rng:NextNumber(-amount, amount), rng:NextNumber(-amount, amount) * 0.5)
	end
	if inPlane and ClientState.Flight("OnGround") ~= true then
		local roll = math.rad((ClientState.Flight("Roll") or 0) * 0.35)
		local pitch = math.rad((ClientState.Flight("Pitch") or 0) * 0.25)
		offset *= CFrame.Angles(pitch, 0, roll)
	end
	if offset ~= CFrame.identity then
		camera.CFrame *= offset
	end
end

---------------------------------------------------------------- lifecycle

function EffectsController:Init(all)
	controllers = all
	buildOverlays()
end

function EffectsController:Start()
	Net.Event("Effect").OnClientEvent:Connect(function(data)
		local name = data.Name
		if name == "Shake" then
			self:Shake(data.Intensity or 1, data.Duration or 0.5)
		elseif name == "Flash" then
			self:Flash(data.Color, data.Duration, 0.9)
		elseif name == "Hurt" then
			hurt(data.Amount or 10)
		elseif name == "Lightning" then
			lightning(data.Big == true)
		elseif name == "EngineWobble" then
			wobbleUntil = os.clock() + (data.Duration or 4)
			Sfx.Play("EngineSputter")
		elseif name == "EngineSmoke" then
			controllers.OutsideWorldController:PuffSmoke(data.Side or 1, data.Duration or 4)
		elseif name == "EngineFlameout" then
			self:Flash(Color3.fromRGB(255, 140, 60), 0.5, 0.4)
			controllers.OutsideWorldController:PuffSmoke(data.Side or 1, 8)
		elseif name == "Sparks" and data.Position then
			sparks(data.Position)
		elseif name == "Decompression" then
			decompression(data.Position)
		elseif name == "Whistle" then
			Sfx.Loop("WindRush", true, 0.12)
			task.delay(data.Duration or 15, function()
				if ClientState.Flight("OxygenEmergency") ~= true then
					Sfx.Loop("WindRush", false)
				end
			end)
		elseif name == "WindshieldCrack" then
			windshieldCrack()
		elseif name == "InstrumentGlitch" then
			glitchInstruments(data.Duration or 3)
		elseif name == "FireIgnited" and data.Position then
			sparks(data.Position)
		elseif name == "Touchdown" then
			local tier = data.Tier
			if tier == "Crash" or tier == "Emergency" then
				self:Flash(Color3.new(0, 0, 0), 1.2, 0.8)
			end
		elseif name == "Evacuated" then
			self:Flash(Color3.fromRGB(255, 220, 120), 0.8, 0.5)
		end
	end)
	-- fade through black when the server teleports players (boarding / back to the terminal)
	ClientState.PhaseChanged:Connect(function(phase)
		if phase == "Boarding" or phase == "Results" then
			self:Flash(Color3.new(0, 0, 0), 1.4, 1)
		end
	end)
	watchWindows()
	RunService:BindToRenderStep("LF_CameraEffects", Enum.RenderPriority.Camera.Value + 1, cameraStep)
	RunService.Heartbeat:Connect(conditionOverlays)
end

return EffectsController
