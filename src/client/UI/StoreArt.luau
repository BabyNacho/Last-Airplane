--[[
	StoreArt
	Visuals for the Sky Shop, all generated from UI frames and parts (no uploaded images):
	  * Art(item)       - the illustration on every store card
	  * Burst(...)      - lightweight 2D particle bursts (purchase celebration, effect previews)
	  * Preview(...)    - the big live preview: your own avatar wearing the item (3D viewport),
	                      a mini aircraft for plane cosmetics, animated 2D overlays for effects
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CosmeticBuilder = require(ReplicatedStorage.Shared.CosmeticBuilder)
local MonetizationConfig = require(ReplicatedStorage.Shared.Config.MonetizationConfig)
local ShopCatalog = require(ReplicatedStorage.Shared.Config.ShopCatalog)
local Util = require(ReplicatedStorage.Shared.Util)
local UIKit = require(script.Parent.UIKit)

local StoreArt = {}

local F = UIKit.Fonts
local DARK = Color3.fromRGB(18, 22, 32)

local GLYPHS = {
	Cap = "🧢", Helmet = "⛑️", Beanie = "🧢", Headset = "🎧", Visor = "🧢", Goggles = "🥽", SleepMask = "😴",
	Shades = "🕶️", NeckPillow = "💤", Vest = "🦺", Backpack = "🎒", JetBackpack = "🎒", Jetpack = "🚀",
	Wings = "🎖️", Pass = "🎫", Roller = "🧳", Trunk = "🧳",
}

local TYPE_GLYPHS = {
	Outfit = "👕", Title = "🏷️", Emote = "🎭", Trail = "💨", Aura = "✨", VictoryEffect = "🎆", Theme = "🎨",
	PlaneSkin = "🛩️", WingEffect = "✈️", PlaneTrail = "☁️", Bundle = "🎁", Pass = "🎫", Credits = "✈",
}

function StoreArt.Glyph(item): string
	if item.Icon then
		return item.Icon
	end
	if item.Data and item.Data.Shape and GLYPHS[item.Data.Shape] then
		return GLYPHS[item.Data.Shape]
	end
	if item.Type == "Emote" and item.Data and item.Data.Bubble then
		return item.Data.Bubble
	end
	return TYPE_GLYPHS[item.Type] or "★"
end

local function frame(parent: Instance, props: { [string]: any }): Frame
	props.BackgroundColor3 = props.BackgroundColor3 or Color3.new(1, 1, 1)
	props.Parent = parent
	return UIKit.new("Frame", props)
end

local function glyph(parent: Instance, text: string, size: UDim2, position: UDim2, z: number?): TextLabel
	return UIKit.new("TextLabel", {
		Text = text,
		TextScaled = true,
		Font = F.Heading,
		Size = size,
		Position = position,
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = z,
		Parent = parent,
	})
end

---------------------------------------------------------------- card illustrations

local function drawPlane(parent: Instance, hull: Color3, stripe: Color3?, wingGlow: Color3?, z: number)
	-- side-ish view: fuselage, swept wings, tail fin
	local body = frame(parent, { Size = UDim2.fromScale(0.74, 0.17), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = hull, Corner = UDim.new(1, 0), ZIndex = z + 1 })
	if stripe then
		frame(body, { Size = UDim2.fromScale(0.86, 0.22), Position = UDim2.fromScale(0.5, 0.42), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = stripe, Corner = UDim.new(1, 0), ZIndex = z + 2 })
	end
	for i = 0, 4 do
		frame(body, { Size = UDim2.fromScale(0.045, 0.2), Position = UDim2.fromScale(0.3 + i * 0.09, 0.22), BackgroundColor3 = Color3.fromRGB(40, 60, 90), Corner = UDim.new(1, 0), ZIndex = z + 3 })
	end
	local wingColor = hull:Lerp(Color3.new(0, 0, 0), 0.12)
	local wing = frame(parent, { Size = UDim2.fromScale(0.34, 0.1), Position = UDim2.fromScale(0.47, 0.64), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 24, BackgroundColor3 = wingColor, Corner = 6, ZIndex = z })
	local far = frame(parent, { Size = UDim2.fromScale(0.26, 0.08), Position = UDim2.fromScale(0.5, 0.38), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = -24, BackgroundColor3 = wingColor:Lerp(Color3.new(0, 0, 0), 0.2), Corner = 6, ZIndex = z })
	if wingGlow then
		for _, w in { wing, far } do
			UIKit.new("UIStroke", { Color = wingGlow, Thickness = 3, Parent = w })
		end
	end
	frame(parent, { Size = UDim2.fromScale(0.1, 0.2), Position = UDim2.fromScale(0.17, 0.36), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = -18, BackgroundColor3 = hull, Corner = 4, ZIndex = z })
	return body
end

local function drawOutfit(parent: Instance, data, z: number)
	local primary, secondary, accent = data.Primary, data.Secondary, data.Accent
	-- legs
	for _, x in { 0.44, 0.56 } do
		frame(parent, { Size = UDim2.fromScale(0.1, 0.3), Position = UDim2.fromScale(x, 0.74), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = secondary, Corner = 4, ZIndex = z })
	end
	-- sleeves
	for _, side in { -1, 1 } do
		frame(parent, { Size = UDim2.fromScale(0.1, 0.36), Position = UDim2.fromScale(0.5 + side * 0.2, 0.44), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = side * -14, BackgroundColor3 = primary, Corner = 6, ZIndex = z })
	end
	local torso = frame(parent, { Size = UDim2.fromScale(0.3, 0.38), Position = UDim2.fromScale(0.5, 0.42), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = primary, Corner = 8, ZIndex = z + 1 })
	if data.Style == "Neon" then
		UIKit.new("UIStroke", { Color = accent, Thickness = 3, Parent = torso })
	end
	frame(torso, { Size = UDim2.fromScale(0.36, 0.14), Position = UDim2.fromScale(0.5, 0.05), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = accent, Corner = 4, ZIndex = z + 2 })
	if data.Style == "Pilot" or data.Style == "Gold" then
		for _, x in { 0.12, 0.88 } do
			frame(torso, { Size = UDim2.fromScale(0.24, 0.06), Position = UDim2.fromScale(x, 0.02), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = accent, ZIndex = z + 2 })
		end
	elseif data.Style == "HiVis" or data.Style == "Retro" then
		for _, y in { 0.45, 0.72 } do
			frame(torso, { Size = UDim2.fromScale(1, 0.08), Position = UDim2.fromScale(0, y), BackgroundColor3 = accent, ZIndex = z + 2 })
		end
	elseif data.Style == "Suit" or data.Style == "Security" then
		frame(torso, { Size = UDim2.fromScale(0.06, 0.7), Position = UDim2.fromScale(0.5, 0.25), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = accent, ZIndex = z + 2 })
	end
	-- head
	frame(parent, { Size = UDim2.fromScale(0.14, 0.14), Position = UDim2.fromScale(0.5, 0.15), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(255, 215, 170), Corner = UDim.new(1, 0), ZIndex = z + 1 })
end

-- Fills `parent` with the card illustration for `item`.
function StoreArt.Art(item, parent: GuiObject, z: number?)
	local zi = z or 1
	local base = item.Color or Color3.fromRGB(70, 150, 255)
	local back = frame(parent, {
		Name = "Art",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = base,
		Corner = 14,
		ClipsDescendants = true,
		ZIndex = zi,
	})
	UIKit.new("UIGradient", {
		Color = ColorSequence.new(base:Lerp(Color3.new(1, 1, 1), 0.15), base:Lerp(DARK, 0.75)),
		Rotation = 115,
		Parent = back,
	})
	-- soft glow disc behind the subject
	local glow = frame(back, { Size = UDim2.fromScale(0.78, 0.78), Position = UDim2.fromScale(0.5, 0.52), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.85, Corner = UDim.new(1, 0), ZIndex = zi })
	UIKit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = glow })
	local data = item.Data or {}
	local t = item.Type
	if t == "Outfit" then
		drawOutfit(back, data, zi + 1)
	elseif t == "PlaneSkin" then
		drawPlane(back, data.Hull, data.Stripe, nil, zi + 1)
	elseif t == "WingEffect" then
		drawPlane(back, Color3.fromRGB(235, 238, 242), Color3.fromRGB(70, 150, 255), data.Strip or data.Tip, zi + 1)
	elseif t == "PlaneTrail" then
		local colors = data.Colors or { base }
		for i, color in colors do
			local streak = frame(back, { Size = UDim2.fromScale(0.5, 0.05), Position = UDim2.fromScale(0.02, 0.44 + (i - #colors / 2) * 0.05), BackgroundColor3 = color, Corner = UDim.new(1, 0), ZIndex = zi + 1 })
			UIKit.new("UIGradient", { Transparency = NumberSequence.new(0.9, 0), Parent = streak })
		end
		local mini = frame(back, { Size = UDim2.fromScale(0.62, 0.62), Position = UDim2.fromScale(0.62, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = zi + 1 })
		drawPlane(mini, Color3.fromRGB(235, 238, 242), Color3.fromRGB(70, 150, 255), nil, zi + 2)
	elseif t == "Trail" then
		local bar = frame(back, { Size = UDim2.fromScale(0.86, 0.16), Position = UDim2.fromScale(0.5, 0.52), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = -12, Corner = UDim.new(1, 0), ZIndex = zi + 1 })
		UIKit.new("UIGradient", { Color = CosmeticBuilder.Sequence(data.Colors or { base }), Transparency = NumberSequence.new(0, 0.85), Parent = bar })
		glyph(back, "🏃", UDim2.fromScale(0.3, 0.3), UDim2.fromScale(0.82, 0.44), zi + 2)
	elseif t == "Aura" then
		local colors = data.Colors or { base }
		for i = 1, 8 do
			local angle = i / 8 * math.pi * 2
			local label = glyph(back, if data.Style == "Confetti" then "▮" elseif data.Style == "Smoke" then "●" else "✦", UDim2.fromScale(0.13, 0.13), UDim2.fromScale(0.5 + math.cos(angle) * 0.32, 0.52 + math.sin(angle) * 0.32), zi + 1)
			label.TextColor3 = colors[(i % #colors) + 1]
			label.Rotation = i * 37
		end
		glyph(back, "🧍", UDim2.fromScale(0.4, 0.4), UDim2.fromScale(0.5, 0.52), zi + 2)
	elseif t == "Title" then
		local plate = frame(back, { Size = UDim2.fromScale(0.9, 0.3), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = DARK, BackgroundTransparency = 0.25, Corner = 10, ZIndex = zi + 1 })
		UIKit.new("TextLabel", { Text = string.upper(item.Name), Font = F.Heading, TextScaled = true, TextColor3 = base, Size = UDim2.fromScale(0.92, 0.8), Position = UDim2.fromScale(0.04, 0.1), ZIndex = zi + 2, Parent = plate })
	elseif t == "Theme" then
		local disc = frame(back, { Size = UDim2.fromScale(0.46, 0.46), Position = UDim2.fromScale(0.5, 0.52), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = data.Accent or base, Corner = UDim.new(1, 0), Stroke = { Color = Color3.new(1, 1, 1), Thickness = 3 }, ZIndex = zi + 1 })
		UIKit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = disc })
	elseif t == "Emote" then
		local bubble = frame(back, { Size = UDim2.fromScale(0.6, 0.5), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), Corner = UDim.new(0.35, 0), ZIndex = zi + 1 })
		glyph(bubble, data.Bubble or "🎭", UDim2.fromScale(0.7, 0.8), UDim2.fromScale(0.5, 0.5), zi + 2)
		local tail = frame(back, { Size = UDim2.fromScale(0.09, 0.09), Position = UDim2.fromScale(0.42, 0.76), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 45, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = zi })
		UIKit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = tail })
	elseif t == "Bundle" then
		glyph(back, StoreArt.Glyph(item), UDim2.fromScale(0.42, 0.42), UDim2.fromScale(0.5, 0.4), zi + 1)
		local row = frame(back, { Size = UDim2.fromScale(0.94, 0.22), Position = UDim2.fromScale(0.5, 0.84), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = zi + 1 })
		UIKit.List(row, 4, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
		for _, id in data.Items or {} do
			local inner = ShopCatalog.Get(id)
			if inner then
				local chip = frame(row, { Size = UDim2.fromScale(0.13, 0.9), BackgroundColor3 = DARK, BackgroundTransparency = 0.35, Corner = 6, ZIndex = zi + 2 })
				UIKit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = chip })
				glyph(chip, StoreArt.Glyph(inner), UDim2.fromScale(0.8, 0.8), UDim2.fromScale(0.5, 0.5), zi + 3)
			end
		end
	elseif t == "Credits" then
		glyph(back, "✈", UDim2.fromScale(0.4, 0.4), UDim2.fromScale(0.5, 0.38), zi + 1).TextColor3 = Color3.fromRGB(255, 225, 120)
		local product = item.ProductKey and MonetizationConfig.Products[item.ProductKey]
		if product and product.Credits then
			UIKit.new("TextLabel", { Text = Util.FormatNumber(product.Credits) .. " FC", Font = F.Heading, TextScaled = true, TextColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(0.8, 0.2), Position = UDim2.fromScale(0.1, 0.68), ZIndex = zi + 1, Parent = back })
		end
	else
		glyph(back, StoreArt.Glyph(item), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.5, 0.52), zi + 1)
	end
	return back
end

---------------------------------------------------------------- 2D particles

-- Spawns `count` glyph particles flying out of `origin` (scale coords) inside `layer`.
function StoreArt.Burst(layer: GuiObject, count: number, colors: { Color3 }, origin: Vector2?, symbols: { string }?, z: number?)
	local rng = Random.new()
	local from = origin or Vector2.new(0.5, 0.5)
	local glyphs = symbols or { "✦", "▮", "●", "★" }
	for _ = 1, count do
		local angle = rng:NextNumber(0, math.pi * 2)
		local distance = rng:NextNumber(0.2, 0.55)
		local size = rng:NextInteger(12, 26)
		local label = UIKit.new("TextLabel", {
			Name = "Particle", -- decoration (not body text)
			Text = glyphs[rng:NextInteger(1, #glyphs)],
			Font = F.Heading,
			TextSize = size,
			TextColor3 = colors[rng:NextInteger(1, #colors)],
			Size = UDim2.fromOffset(size * 2, size * 2),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(from.X, from.Y),
			Rotation = rng:NextNumber(0, 360),
			ZIndex = z or 60,
			Parent = layer,
		})
		local duration = rng:NextNumber(0.7, 1.3)
		UIKit.Tween(label, duration, {
			Position = UDim2.fromScale(from.X + math.cos(angle) * distance, from.Y + math.sin(angle) * distance + 0.15),
			Rotation = label.Rotation + rng:NextNumber(-200, 200),
			TextTransparency = 1,
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		task.delay(duration, function()
			label:Destroy()
		end)
	end
end

---------------------------------------------------------------- live preview

local function upright(position: Vector3, target: Vector3): CFrame
	local look = (target - position).Unit
	local right = look:Cross(Vector3.yAxis)
	if right.Magnitude < 1e-4 then
		right = Vector3.xAxis
	end
	right = right.Unit
	return CFrame.fromMatrix(position, right, right:Cross(look).Unit)
end

local function makeViewport(holder: GuiObject, z: number): (ViewportFrame, WorldModel, Camera)
	local viewport = UIKit.new("ViewportFrame", {
		Name = "Viewport",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(170, 175, 190),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.4, -1, -0.6),
		ZIndex = z,
		Parent = holder,
	}) :: ViewportFrame
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 34
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return viewport, world, camera
end

-- The player's own character, cloned for the preview, wearing `itemsBySlot`.
local function mannequin(itemsBySlot): Model?
	local character = Players.LocalPlayer.Character
	if not character then
		return nil
	end
	local archivable = character.Archivable
	character.Archivable = true
	local ok, clone = pcall(function()
		return character:Clone()
	end)
	character.Archivable = archivable
	if not ok or not clone then
		return nil
	end
	for _, d in clone:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("BillboardGui") or d:IsA("ForceField") or d:IsA("ParticleEmitter") or d:IsA("Trail") then
			d:Destroy()
		end
	end
	CosmeticBuilder.ApplyCharacter(clone, itemsBySlot)
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = d.Name == "HumanoidRootPart"
			d.CanCollide = false
		end
	end
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	clone:PivotTo(CFrame.new())
	return clone
end

local function overlayLoop(layer: GuiObject, alive: () -> boolean, every: number, spawn: () -> ())
	task.spawn(function()
		while alive() do
			spawn()
			task.wait(every)
		end
	end)
	local _ = layer
end

--[[
	Builds the preview for `item` inside `holder`. `context.Equipped` (slot -> item) is what the
	player currently wears, so the preview shows the new item together with their loadout.
	Returns a cleanup function (stops rotation, animations and particles).
]]
function StoreArt.Preview(holder: GuiObject, item, context: { Equipped: { [string]: any } }): () -> ()
	local alive = true
	local connections: { RBXScriptConnection } = {}
	local z = (holder.ZIndex or 1) + 1
	local function isAlive(): boolean
		return alive and holder.Parent ~= nil
	end
	local function cleanup()
		alive = false
		for _, connection in connections do
			connection:Disconnect()
		end
	end
	local t = item.Type
	local data = item.Data or {}
	local overlay = UIKit.new("Frame", { Name = "Overlay", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = z + 2, Parent = holder })

	local isPlane = t == "PlaneSkin" or t == "WingEffect" or t == "PlaneTrail"
	local isCharacter = t == "Outfit" or t == "Accessory" or t == "Badge" or t == "Luggage" or t == "Emote" or t == "Trail" or t == "Aura" or t == "Title"
	local built = false
	if isPlane then
		local ok = pcall(function()
			local _, world, camera = makeViewport(holder, z)
			local plane = CosmeticBuilder.BuildMiniPlane()
			local equipped = context.Equipped
			local skin = if t == "PlaneSkin" then item else equipped.PlaneSkin
			local wing = if t == "WingEffect" then item else equipped.WingEffect
			CosmeticBuilder.ApplyPlane(plane, skin, wing, nil, {})
			plane.Parent = world
			camera.CFrame = upright(Vector3.new(22, 12, 30), Vector3.new(0, 0, 0))
			local angle = 0
			table.insert(connections, RunService.RenderStepped:Connect(function(dt)
				angle += dt * 0.5
				plane:PivotTo(CFrame.Angles(0, angle, 0))
			end))
		end)
		built = ok
		if t == "PlaneTrail" then
			local colors = data.Colors or { item.Color }
			overlayLoop(overlay, isAlive, 0.12, function()
				local rng = Random.new()
				local streak = UIKit.new("Frame", {
					Size = UDim2.fromScale(0.08, 0.025),
					Position = UDim2.fromScale(0.5, 0.5 + rng:NextNumber(-0.06, 0.06)),
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundColor3 = colors[rng:NextInteger(1, #colors)],
					Corner = UDim.new(1, 0),
					ZIndex = z + 3,
					Parent = overlay,
				})
				UIKit.Tween(streak, 1, { Position = UDim2.fromScale(-0.1, streak.Position.Y.Scale), Size = UDim2.fromScale(0.3, 0.05), BackgroundTransparency = 1 }, Enum.EasingStyle.Linear)
				task.delay(1, function()
					streak:Destroy()
				end)
			end)
		end
	elseif isCharacter then
		local ok = pcall(function()
			local items = table.clone(context.Equipped)
			if item.Slot then
				items[item.Slot] = item
			end
			local model = mannequin(items)
			if not model then
				error("no character")
			end
			local _, world, camera = makeViewport(holder, z)
			model.Parent = world
			camera.CFrame = upright(Vector3.new(0, 1.2, -11), Vector3.new(0.4, -0.2, 0))
			local angle = math.rad(-20)
			model:PivotTo(CFrame.Angles(0, angle, 0))
			table.insert(connections, RunService.RenderStepped:Connect(function(dt)
				angle += dt * 0.6
				model:PivotTo(CFrame.Angles(0, angle, 0))
			end))
			if t == "Emote" and data.AnimationId then
				local humanoid = model:FindFirstChildOfClass("Humanoid")
				local animator: Animator? = humanoid and humanoid:FindFirstChildOfClass("Animator")
				if humanoid and not animator then
					local created = Instance.new("Animator")
					created.Parent = humanoid
					animator = created
				end
				if animator then
					local animation = Instance.new("Animation")
					animation.AnimationId = data.AnimationId
					local track = animator:LoadAnimation(animation)
					track.Looped = true
					track:Play(0.1)
					if data.Speed then
						track:AdjustSpeed(data.Speed)
					end
				end
			end
		end)
		built = ok
		if t == "Emote" and data.Bubble then
			local bubble = UIKit.new("TextLabel", {
				Text = if data.BubbleText then data.Bubble .. " " .. data.BubbleText else data.Bubble,
				Font = F.Heading,
				TextScaled = true,
				TextColor3 = Color3.fromRGB(30, 35, 50),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0,
				Size = UDim2.fromScale(if data.BubbleText then 0.6 else 0.24, 0.16),
				Position = UDim2.fromScale(0.5, 0.1),
				AnchorPoint = Vector2.new(0.5, 0),
				Corner = UDim.new(0.4, 0),
				Padding = { 6, 10, 6, 10 },
				ZIndex = z + 4,
				Parent = overlay,
			})
			local scale = UIKit.new("UIScale", { Scale = 0.4, Parent = bubble })
			UIKit.Tween(scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
		elseif t == "Title" then
			UIKit.new("TextLabel", {
				Text = string.upper(item.Name),
				Font = F.Heading,
				TextScaled = true,
				TextColor3 = item.Color,
				TextStrokeTransparency = 0.4,
				Size = UDim2.fromScale(0.8, 0.1),
				Position = UDim2.fromScale(0.5, 0.06),
				AnchorPoint = Vector2.new(0.5, 0),
				ZIndex = z + 4,
				Parent = overlay,
			})
		elseif t == "Aura" then
			local colors = data.Colors or { item.Color }
			overlayLoop(overlay, isAlive, 0.18, function()
				StoreArt.Burst(overlay, 2, colors, Vector2.new(0.5, 0.55), if data.Style == "Confetti" then { "▮" } elseif data.Style == "Smoke" then { "●" } else { "✦", "✧" }, z + 4)
			end)
		elseif t == "Trail" then
			local colors = data.Colors or { item.Color }
			overlayLoop(overlay, isAlive, 0.08, function()
				local rng = Random.new()
				local dot = UIKit.new("Frame", {
					Size = UDim2.fromScale(0.05, 0.05),
					Position = UDim2.fromScale(0.42 + rng:NextNumber(-0.02, 0.02), 0.45 + rng:NextNumber(-0.15, 0.2)),
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundColor3 = colors[rng:NextInteger(1, #colors)],
					Corner = UDim.new(1, 0),
					ZIndex = z + 4,
					Parent = overlay,
				})
				UIKit.Tween(dot, 0.9, { Position = UDim2.fromScale(0.08, dot.Position.Y.Scale), BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
				task.delay(0.9, function()
					dot:Destroy()
				end)
			end)
		end
	end
	if not built then
		-- fallback (or effects with no 3D subject): the big card illustration
		local art = StoreArt.Art(item, holder, z)
		art.ZIndex = z
		if t == "VictoryEffect" then
			local symbols = { Confetti = { "▮" }, PaperPlanes = { "✈" }, Fireworks = { "✦" }, GoldenWings = { "❖", "✧" } }
			overlayLoop(overlay, isAlive, 0.45, function()
				local rng = Random.new()
				StoreArt.Burst(overlay, 8, { item.Color, Color3.new(1, 1, 1), Color3.fromHSV(rng:NextNumber(), 0.6, 1) }, Vector2.new(rng:NextNumber(0.25, 0.75), rng:NextNumber(0.25, 0.6)), symbols[data.Style] or { "✦" }, z + 4)
			end)
		end
	end
	return cleanup
end

return StoreArt
