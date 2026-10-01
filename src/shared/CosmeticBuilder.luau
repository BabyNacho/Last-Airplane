--[[
	CosmeticBuilder
	Builds every cosmetic out of plain parts / particles so nothing needs uploaded assets:
	  * character: accessories, outfits, badges, luggage, trails and auras
	    (server: real characters; client: the store preview mannequin)
	  * aircraft: plane skins, wing effects and engine trails (client only - each player sees
	    their own look on the shared aircraft)
	Everything built here is massless, non-colliding, non-queryable decoration. Nothing touches
	health, movement, physics, flight or any gameplay value.
]]

local CosmeticBuilder = {}

CosmeticBuilder.FolderName = "LF_Cosmetics"

local TEXTURES = {
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
}

local function weldPart(parent: Instance, anchor: BasePart, props: { [string]: any }, offset: CFrame): BasePart
	local part: BasePart
	if props.Shape == "Ball" or props.Shape == "Cylinder" then
		local p = Instance.new("Part")
		p.Shape = if props.Shape == "Ball" then Enum.PartType.Ball else Enum.PartType.Cylinder
		part = p
	elseif props.Shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		part = Instance.new("Part")
	end
	part.Name = props.Name or "Cosmetic"
	part.Size = props.Size
	part.Color = props.Color
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.Transparency = props.Transparency or 0
	part.Reflectance = props.Reflectance or 0
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = anchor.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part
	weld.Part1 = anchor
	weld.Parent = part
	part.Parent = parent
	return part
end
CosmeticBuilder.WeldPart = weldPart

local function sequence(colors: { Color3 }): ColorSequence
	local keypoints = {}
	for i, color in colors do
		table.insert(keypoints, ColorSequenceKeypoint.new(if #colors == 1 then 0 else (i - 1) / (#colors - 1), color))
	end
	if #keypoints == 1 then
		table.insert(keypoints, ColorSequenceKeypoint.new(1, colors[1]))
	end
	return ColorSequence.new(keypoints)
end
CosmeticBuilder.Sequence = sequence

local function sparkles(parent: Instance, color: Color3, rate: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "LF_Sparkle"
	emitter.Texture = TEXTURES.Sparkle
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(0.6, 1.1)
	emitter.Speed = NumberRange.new(0.3, 1)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.35), NumberSequenceKeypoint.new(1, 0) })
	emitter.Parent = parent
	return emitter
end

---------------------------------------------------------------- accessory shapes

-- Offsets are relative to the head (hat/face) or upper torso (body); -Z is forward.
local SHAPES = {}
CosmeticBuilder.Shapes = SHAPES

SHAPES.Cap = function(folder, head, data)
	weldPart(folder, head, { Size = Vector3.new(1.25, 0.45, 1.25), Color = data.Primary, Shape = "Cylinder" }, CFrame.new(0, 0.62, 0) * CFrame.Angles(0, 0, math.rad(90)))
	weldPart(folder, head, { Size = Vector3.new(1.1, 0.08, 0.6), Color = data.Accent }, CFrame.new(0, 0.42, -0.72))
	if data.Badge then
		weldPart(folder, head, { Size = Vector3.new(0.35, 0.22, 0.05), Color = data.Accent, Material = Enum.Material.Neon }, CFrame.new(0, 0.66, -0.63))
	end
end

SHAPES.Helmet = function(folder, head, data)
	weldPart(folder, head, { Size = Vector3.new(1.35, 1.35, 1.35), Color = data.Primary, Shape = "Ball" }, CFrame.new(0, 0.38, 0.02))
	weldPart(folder, head, { Size = Vector3.new(1.5, 0.08, 1.5), Color = data.Primary, Shape = "Cylinder" }, CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.rad(90)))
	weldPart(folder, head, { Size = Vector3.new(0.2, 0.12, 1.1), Color = data.Accent }, CFrame.new(0, 1.03, 0))
end

SHAPES.Beanie = function(folder, head, data)
	weldPart(folder, head, { Size = Vector3.new(1.28, 1.1, 1.28), Color = data.Primary, Shape = "Ball" }, CFrame.new(0, 0.42, 0.02))
	weldPart(folder, head, { Size = Vector3.new(0.1, 0.35, 0.1), Color = Color3.fromRGB(40, 40, 40) }, CFrame.new(0, 1.05, 0))
	weldPart(folder, head, { Size = Vector3.new(1.3, 0.05, 0.18), Color = data.Accent }, CFrame.new(0, 1.24, 0))
	weldPart(folder, head, { Size = Vector3.new(0.18, 0.05, 1.3), Color = data.Accent }, CFrame.new(0, 1.24, 0))
end

SHAPES.Headset = function(folder, head, data)
	weldPart(folder, head, { Size = Vector3.new(0.18, 0.12, 1.4), Color = data.Primary }, CFrame.new(0, 0.66, 0) * CFrame.Angles(0, math.rad(90), 0))
	for _, x in { -0.66, 0.66 } do
		weldPart(folder, head, { Size = Vector3.new(0.2, 0.55, 0.55), Color = data.Primary, Shape = "Cylinder" }, CFrame.new(x, 0.05, 0))
	end
	weldPart(folder, head, { Size = Vector3.new(0.06, 0.06, 0.55), Color = data.Primary }, CFrame.new(0.55, -0.2, -0.35) * CFrame.Angles(0, math.rad(-35), 0))
	weldPart(folder, head, { Size = Vector3.new(0.14, 0.14, 0.14), Color = data.Accent, Shape = "Ball", Material = Enum.Material.Neon }, CFrame.new(0.38, -0.3, -0.6))
end

SHAPES.Visor = function(folder, head, data)
	weldPart(folder, head, { Size = Vector3.new(0.3, 1.3, 1.3), Color = data.Primary, Shape = "Cylinder" }, CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)))
	weldPart(folder, head, { Size = Vector3.new(1.2, 0.08, 0.7), Color = data.Primary }, CFrame.new(0, 0.42, -0.78) * CFrame.Angles(math.rad(-12), 0, 0))
	-- lightning bolt stripe
	weldPart(folder, head, { Size = Vector3.new(0.12, 0.09, 0.4), Color = data.Accent, Material = Enum.Material.Neon }, CFrame.new(-0.2, 0.47, -0.7) * CFrame.Angles(math.rad(-12), math.rad(35), 0))
	weldPart(folder, head, { Size = Vector3.new(0.12, 0.09, 0.4), Color = data.Accent, Material = Enum.Material.Neon }, CFrame.new(0.05, 0.47, -0.85) * CFrame.Angles(math.rad(-12), math.rad(-35), 0))
	weldPart(folder, head, { Size = Vector3.new(0.12, 0.09, 0.35), Color = data.Accent, Material = Enum.Material.Neon }, CFrame.new(0.28, 0.47, -0.95) * CFrame.Angles(math.rad(-12), math.rad(35), 0))
end

SHAPES.Goggles = function(folder, head, data)
	weldPart(folder, head, { Size = Vector3.new(1.3, 0.12, 1.3), Color = data.Primary, Shape = "Cylinder" }, CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)))
	for _, x in { -0.28, 0.28 } do
		weldPart(folder, head, { Size = Vector3.new(0.12, 0.38, 0.38), Color = data.Accent, Shape = "Cylinder", Material = Enum.Material.Glass, Transparency = 0.2 }, CFrame.new(x, 0.2, -0.62) * CFrame.Angles(0, math.rad(90), 0))
	end
end

SHAPES.SleepMask = function(folder, head, data)
	weldPart(folder, head, { Size = Vector3.new(1.05, 0.32, 0.1), Color = data.Primary, Material = Enum.Material.Fabric }, CFrame.new(0, 0.18, -0.6))
	weldPart(folder, head, { Size = Vector3.new(1.3, 0.08, 1.3), Color = data.Primary, Shape = "Cylinder" }, CFrame.new(0, 0.18, 0) * CFrame.Angles(0, 0, math.rad(90)))
end

SHAPES.Shades = function(folder, head, data)
	for _, x in { -0.25, 0.25 } do
		weldPart(folder, head, { Size = Vector3.new(0.38, 0.24, 0.06), Color = data.Accent, Material = Enum.Material.Glass, Transparency = 0.1 }, CFrame.new(x, 0.18, -0.61))
	end
	weldPart(folder, head, { Size = Vector3.new(0.95, 0.05, 0.05), Color = data.Primary, Material = Enum.Material.Metal }, CFrame.new(0, 0.28, -0.62))
end

SHAPES.NeckPillow = function(folder, torso, data)
	for i = 0, 6 do
		local angle = math.rad(-110 + i * 36.6)
		weldPart(folder, torso, { Size = Vector3.new(0.5, 0.5, 0.5), Color = data.Primary, Shape = "Ball", Material = Enum.Material.Fabric }, CFrame.new(math.sin(angle) * 0.62, 1.02, math.cos(angle) * 0.45))
	end
end

SHAPES.Vest = function(folder, torso, data)
	weldPart(folder, torso, { Size = Vector3.new(2.1, 1.3, 0.35), Color = data.Primary }, CFrame.new(0, 0.1, -0.55))
	weldPart(folder, torso, { Size = Vector3.new(2.1, 1.3, 0.3), Color = data.Primary }, CFrame.new(0, 0.1, 0.55))
	weldPart(folder, torso, { Size = Vector3.new(0.2, 0.2, 0.2), Color = data.Accent, Shape = "Ball" }, CFrame.new(0.4, -0.4, -0.75))
end

SHAPES.Backpack = function(folder, torso, data)
	weldPart(folder, torso, { Size = Vector3.new(1.6, 1.8, 0.8), Color = data.Primary, Material = Enum.Material.Fabric }, CFrame.new(0, 0, 0.85))
	weldPart(folder, torso, { Size = Vector3.new(0.3, 0.3, 0.2), Color = data.Accent }, CFrame.new(0.5, -0.4, -0.55))
	for _, x in { -0.55, 0.55 } do
		weldPart(folder, torso, { Size = Vector3.new(0.18, 1.9, 0.12), Color = Color3.fromRGB(40, 40, 40) }, CFrame.new(x, 0, -0.5))
	end
	if data.Cross then
		weldPart(folder, torso, { Size = Vector3.new(0.7, 0.2, 0.05), Color = data.Accent }, CFrame.new(0, 0.1, 1.27))
		weldPart(folder, torso, { Size = Vector3.new(0.2, 0.7, 0.05), Color = data.Accent }, CFrame.new(0, 0.1, 1.27))
	end
end

SHAPES.JetBackpack = function(folder, torso, data)
	weldPart(folder, torso, { Size = Vector3.new(1.3, 1.9, 0.75), Color = data.Primary, Material = Enum.Material.Metal }, CFrame.new(0, 0, 0.82))
	weldPart(folder, torso, { Size = Vector3.new(0.9, 0.25, 0.05), Color = data.Accent, Material = Enum.Material.Neon }, CFrame.new(0, 0.45, 1.21))
	for _, side in { -1, 1 } do
		weldPart(folder, torso, { Size = Vector3.new(0.12, 0.9, 0.7), Color = data.Accent, Shape = "Wedge" }, CFrame.new(side * 0.75, -0.4, 0.9) * CFrame.Angles(0, math.rad(180), 0))
		weldPart(folder, torso, { Size = Vector3.new(0.18, 1.9, 0.12), Color = Color3.fromRGB(40, 40, 40) }, CFrame.new(side * 0.55, 0, -0.5))
	end
end

SHAPES.Jetpack = function(folder, torso, data)
	for _, x in { -0.45, 0.45 } do
		weldPart(folder, torso, { Size = Vector3.new(1.8, 0.7, 0.7), Color = data.Primary, Shape = "Cylinder", Material = Enum.Material.Metal }, CFrame.new(x, 0, 0.85) * CFrame.Angles(0, 0, math.rad(90)))
		local nozzle = weldPart(folder, torso, { Size = Vector3.new(0.4, 0.4, 0.4), Color = data.Accent, Shape = "Ball", Material = Enum.Material.Neon }, CFrame.new(x, -0.95, 0.85))
		local light = Instance.new("PointLight")
		light.Color = data.Accent
		light.Range = 5
		light.Brightness = 1.5
		light.Parent = nozzle
	end
end

---------------------------------------------------------------- badges (chest)

local BADGES = {}

BADGES.Wings = function(folder, torso: BasePart, data)
	local z = -(torso.Size.Z / 2 + 0.1)
	local material = if data.Neon then Enum.Material.Neon elseif data.Shiny then Enum.Material.Foil else Enum.Material.Metal
	local center = CFrame.new(-0.42, 0.42, z)
	weldPart(folder, torso, { Size = Vector3.new(0.16, 0.16, 0.06), Color = data.Accent, Material = material }, center)
	for _, side in { -1, 1 } do
		weldPart(folder, torso, { Size = Vector3.new(0.34, 0.08, 0.04), Color = data.Primary, Material = material }, center * CFrame.new(side * 0.22, 0.02, 0) * CFrame.Angles(0, 0, math.rad(side * 12)))
		weldPart(folder, torso, { Size = Vector3.new(0.24, 0.06, 0.04), Color = data.Primary, Material = material }, center * CFrame.new(side * 0.2, -0.06, 0) * CFrame.Angles(0, 0, math.rad(side * 22)))
	end
	if data.Neon then
		local light = Instance.new("PointLight")
		light.Color = data.Primary
		light.Range = 4
		light.Brightness = 0.8
		light.Parent = folder:GetChildren()[#folder:GetChildren()]
	end
end

BADGES.Pass = function(folder, torso: BasePart, data)
	local z = -(torso.Size.Z / 2 + 0.08)
	for _, side in { -1, 1 } do
		weldPart(folder, torso, { Size = Vector3.new(0.08, 0.95, 0.03), Color = data.Accent }, CFrame.new(side * 0.32, 0.38, z) * CFrame.Angles(0, 0, math.rad(side * -18)))
	end
	local card = weldPart(folder, torso, { Size = Vector3.new(0.52, 0.66, 0.04), Color = data.Primary, Material = if data.Shiny then Enum.Material.Foil else Enum.Material.SmoothPlastic }, CFrame.new(0, -0.18, z - 0.02))
	weldPart(folder, torso, { Size = Vector3.new(0.52, 0.14, 0.05), Color = data.Accent }, CFrame.new(0, 0.05, z - 0.03))
	if data.Sparkle then
		sparkles(card, data.Primary, 3)
	end
end

---------------------------------------------------------------- luggage (rolls along beside you)

local LUGGAGE = {}

LUGGAGE.Roller = function(folder, root: BasePart, data)
	local base = CFrame.new(1.75, -2.25, 0.45)
	local material = if data.Metal then Enum.Material.Metal else Enum.Material.SmoothPlastic
	weldPart(folder, root, { Size = Vector3.new(0.65, 1.45, 1.05), Color = data.Primary, Material = material }, base)
	for _, y in { -0.35, 0.35 } do
		weldPart(folder, root, { Size = Vector3.new(0.7, 0.08, 1.1), Color = data.Accent }, base * CFrame.new(0, y, 0))
	end
	weldPart(folder, root, { Size = Vector3.new(0.08, 0.9, 0.08), Color = Color3.fromRGB(60, 60, 65), Material = Enum.Material.Metal }, base * CFrame.new(0, 1.15, 0.3))
	weldPart(folder, root, { Size = Vector3.new(0.08, 0.9, 0.08), Color = Color3.fromRGB(60, 60, 65), Material = Enum.Material.Metal }, base * CFrame.new(0, 1.15, -0.3))
	weldPart(folder, root, { Size = Vector3.new(0.12, 0.1, 0.7), Color = Color3.fromRGB(40, 40, 45) }, base * CFrame.new(0, 1.6, 0))
	for _, z in { -0.4, 0.4 } do
		weldPart(folder, root, { Size = Vector3.new(0.12, 0.22, 0.22), Color = Color3.fromRGB(30, 30, 30), Shape = "Cylinder" }, base * CFrame.new(0, -0.78, z))
	end
	if data.Stickers then
		local colors = { Color3.fromRGB(255, 90, 120), Color3.fromRGB(90, 200, 255), Color3.fromRGB(255, 220, 60), Color3.fromRGB(120, 230, 140) }
		for i, color in colors do
			weldPart(folder, root, { Size = Vector3.new(0.68, 0.24, 0.24), Color = color }, base * CFrame.new(0, -0.5 + (i % 2) * 0.55, -0.3 + math.floor((i - 1) / 2) * 0.55))
		end
	end
end

LUGGAGE.Trunk = function(folder, root: BasePart, data)
	local base = CFrame.new(1.85, -2.35, 0.4)
	weldPart(folder, root, { Size = Vector3.new(0.8, 1.2, 1.5), Color = data.Primary, Material = Enum.Material.Fabric }, base)
	for _, y in { -0.6, 0.6 } do
		for _, z in { -0.75, 0.75 } do
			weldPart(folder, root, { Size = Vector3.new(0.85, 0.16, 0.16), Color = data.Accent, Material = Enum.Material.Foil }, base * CFrame.new(0, y, z))
		end
	end
	weldPart(folder, root, { Size = Vector3.new(0.86, 0.14, 1.55), Color = Color3.fromRGB(90, 60, 40) }, base * CFrame.new(0, 0.15, 0))
	weldPart(folder, root, { Size = Vector3.new(0.2, 0.18, 0.4), Color = data.Accent, Material = Enum.Material.Foil }, base * CFrame.new(0, 0.7, 0))
end

---------------------------------------------------------------- outfits

local R15_HIPS = { "LowerTorso" }
local R15_ARMS = { "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm" }
local R15_LOWER_ARMS = { "LeftLowerArm", "RightLowerArm" }
local R15_UPPER_ARMS = { "LeftUpperArm", "RightUpperArm" }
local R15_LEGS = { "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" }
local R6_ARMS = { "Left Arm", "Right Arm" }
local R6_LEGS = { "Left Leg", "Right Leg" }

local function parts(character: Model, names: { string }): { BasePart }
	local list = {}
	for _, name in names do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(list, part)
		end
	end
	return list
end

local function shell(folder, part: BasePart, color: Color3, material: Enum.Material?, pad: Vector3): BasePart
	return weldPart(folder, part, { Name = "OutfitShell", Size = part.Size + pad, Color = color, Material = material or Enum.Material.Fabric }, CFrame.identity)
end

-- Thin ring around a limb (cuffs, stripes, bands). y is relative to the limb centre.
local function band(folder, part: BasePart, color: Color3, y: number, height: number, material: Enum.Material?, extra: number?)
	local grow = extra or 0.14
	weldPart(folder, part, { Name = "OutfitTrim", Size = Vector3.new(part.Size.X + grow, height, part.Size.Z + grow), Color = color, Material = material or Enum.Material.SmoothPlastic }, CFrame.new(0, y, 0))
end

function CosmeticBuilder.Outfit(folder: Instance, character: Model, data)
	local r6 = character:FindFirstChild("Torso") ~= nil
	local torso = (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) :: BasePart?
	if not torso then
		return
	end
	local material = data.Material or Enum.Material.Fabric
	local torsoPad = Vector3.new(0.1, 0.05, 0.1)
	shell(folder, torso, data.Primary, material, torsoPad)
	local arms = parts(character, if r6 then R6_ARMS else R15_ARMS)
	for _, arm in arms do
		shell(folder, arm, data.Primary, material, Vector3.new(0.08, 0.02, 0.08))
	end
	for _, hip in parts(character, R15_HIPS) do
		shell(folder, hip, data.Secondary, material, Vector3.new(0.1, 0.02, 0.1))
	end
	for _, leg in parts(character, if r6 then R6_LEGS else R15_LEGS) do
		shell(folder, leg, data.Secondary, material, Vector3.new(0.06, 0, 0.06))
	end
	local cuffs = if r6 then arms else parts(character, R15_LOWER_ARMS)
	local uppers = if r6 then arms else parts(character, R15_UPPER_ARMS)
	local front = -(torso.Size.Z / 2 + 0.06)
	local style = data.Style
	local accent = data.Accent

	if style == "Pilot" then
		for _, arm in cuffs do
			band(folder, arm, accent, -arm.Size.Y / 2 + 0.2, 0.07)
			band(folder, arm, accent, -arm.Size.Y / 2 + 0.34, 0.07)
		end
		for _, side in { -1, 1 } do
			weldPart(folder, torso, { Size = Vector3.new(0.55, 0.08, 0.5), Color = accent }, CFrame.new(side * (torso.Size.X / 2 - 0.25), torso.Size.Y / 2 + 0.05, 0))
		end
		weldPart(folder, torso, { Size = Vector3.new(0.5, 0.7, 0.04), Color = Color3.fromRGB(245, 245, 250) }, CFrame.new(0, torso.Size.Y / 2 - 0.35, front))
		weldPart(folder, torso, { Size = Vector3.new(0.16, 0.65, 0.05), Color = Color3.fromRGB(20, 20, 30) }, CFrame.new(0, torso.Size.Y / 2 - 0.42, front - 0.01))
	elseif style == "Suit" then
		for _, side in { -1, 1 } do
			weldPart(folder, torso, { Size = Vector3.new(0.12, 0.9, 0.04), Color = accent }, CFrame.new(side * 0.22, torso.Size.Y / 2 - 0.45, front) * CFrame.Angles(0, 0, math.rad(side * -20)))
		end
		weldPart(folder, torso, { Size = Vector3.new(0.34, 0.6, 0.04), Color = Color3.fromRGB(245, 245, 250) }, CFrame.new(0, torso.Size.Y / 2 - 0.3, front))
		for i = 0, 1 do
			weldPart(folder, torso, { Size = Vector3.new(0.1, 0.1, 0.05), Color = accent, Shape = "Ball", Material = Enum.Material.Foil }, CFrame.new(0, -0.1 - i * 0.3, front))
		end
		weldPart(folder, torso, { Size = Vector3.new(0.22, 0.14, 0.05), Color = accent }, CFrame.new(-0.55, 0.3, front))
	elseif style == "HiVis" then
		for _, y in { 0.15, -0.35 } do
			band(folder, torso, accent, y, 0.12, Enum.Material.SmoothPlastic, 0.16)
		end
		for _, arm in uppers do
			band(folder, arm, accent, 0, 0.12)
		end
		for _, leg in parts(character, if r6 then R6_LEGS else { "LeftLowerLeg", "RightLowerLeg" }) do
			band(folder, leg, accent, 0, 0.12)
		end
	elseif style == "Security" then
		weldPart(folder, torso, { Size = Vector3.new(0.24, 0.28, 0.05), Color = accent, Material = Enum.Material.Foil }, CFrame.new(-0.5, 0.35, front))
		for _, arm in uppers do
			band(folder, arm, accent, arm.Size.Y / 2 - 0.25, 0.1)
		end
		for _, hip in parts(character, R15_HIPS) do
			band(folder, hip, Color3.fromRGB(25, 25, 30), 0, 0.2)
		end
	elseif style == "Explorer" then
		for _, side in { -1, 1 } do
			weldPart(folder, torso, { Size = Vector3.new(0.45, 0.4, 0.06), Color = data.Primary:Lerp(Color3.new(0, 0, 0), 0.2) }, CFrame.new(side * 0.45, 0.25, front))
			weldPart(folder, torso, { Size = Vector3.new(0.45, 0.08, 0.07), Color = accent }, CFrame.new(side * 0.45, 0.45, front))
		end
		for _, hip in parts(character, R15_HIPS) do
			band(folder, hip, Color3.fromRGB(90, 60, 35), 0.05, 0.18)
		end
		if data.Scarf then
			for i = 0, 6 do
				local angle = math.rad(-110 + i * 36.6)
				weldPart(folder, torso, { Size = Vector3.new(0.34, 0.34, 0.34), Color = accent, Shape = "Ball", Material = Enum.Material.Fabric }, CFrame.new(math.sin(angle) * 0.55, torso.Size.Y / 2 + 0.05, math.cos(angle) * 0.4))
			end
		end
	elseif style == "Casual" then
		weldPart(folder, torso, { Size = Vector3.new(1.2, 0.4, 0.06), Color = data.Primary:Lerp(Color3.new(0, 0, 0), 0.15) }, CFrame.new(0, -0.3, front))
		weldPart(folder, torso, { Size = Vector3.new(1.3, 0.55, 0.5), Color = data.Primary, Material = Enum.Material.Fabric }, CFrame.new(0, torso.Size.Y / 2 + 0.05, torso.Size.Z / 2 - 0.05))
		for _, side in { -1, 1 } do
			weldPart(folder, torso, { Size = Vector3.new(0.05, 0.45, 0.05), Color = accent }, CFrame.new(side * 0.15, 0.2, front))
		end
	elseif style == "Sky" then
		for _, arm in cuffs do
			for _, x in { -0.18, 0.18 } do
				weldPart(folder, arm, { Size = Vector3.new(0.32, 0.32, 0.32), Color = accent, Shape = "Ball" }, CFrame.new(x, -arm.Size.Y / 2 + 0.15, 0))
			end
		end
		for i = -2, 2 do
			weldPart(folder, torso, { Size = Vector3.new(0.42, 0.42, 0.42), Color = accent, Shape = "Ball" }, CFrame.new(i * 0.4, -torso.Size.Y / 2 + 0.1, front + 0.15))
		end
	elseif style == "Retro" then
		for i, y in { 0.35, 0.05, -0.25 } do
			band(folder, torso, if i % 2 == 1 then accent else data.Secondary, y, 0.14, Enum.Material.SmoothPlastic, 0.14)
		end
		weldPart(folder, torso, { Size = Vector3.new(0.6, 0.18, 0.5), Color = accent }, CFrame.new(0, torso.Size.Y / 2 + 0.06, -0.1))
	elseif style == "Neon" then
		local glow = Enum.Material.Neon
		for _, side in { -1, 1 } do
			weldPart(folder, torso, { Size = Vector3.new(0.07, torso.Size.Y, 0.05), Color = accent, Material = glow }, CFrame.new(side * (torso.Size.X / 2 - 0.05), 0, front))
		end
		weldPart(folder, torso, { Size = Vector3.new(0.06, torso.Size.Y * 0.9, 0.05), Color = data.Accent2 or accent, Material = glow }, CFrame.new(0, 0, front))
		for _, arm in arms do
			weldPart(folder, arm, { Size = Vector3.new(0.06, arm.Size.Y, 0.06), Color = accent, Material = glow }, CFrame.new(0, 0, -(arm.Size.Z / 2 + 0.05)))
		end
		for _, leg in parts(character, if r6 then R6_LEGS else R15_LEGS) do
			weldPart(folder, leg, { Size = Vector3.new(0.06, leg.Size.Y, 0.06), Color = data.Accent2 or accent, Material = glow }, CFrame.new(0, 0, -(leg.Size.Z / 2 + 0.04)))
		end
	elseif style == "Gold" then
		for _, arm in cuffs do
			band(folder, arm, accent, -arm.Size.Y / 2 + 0.15, 0.1)
		end
		band(folder, torso, accent, -torso.Size.Y / 2 + 0.1, 0.1, Enum.Material.SmoothPlastic, 0.14)
		weldPart(folder, torso, { Size = Vector3.new(0.5, 0.18, 0.5), Color = accent }, CFrame.new(0, torso.Size.Y / 2 + 0.06, -0.1))
		local shellPart = folder:FindFirstChild("OutfitShell")
		if shellPart then
			sparkles(shellPart, Color3.fromRGB(255, 235, 150), 3)
		end
	end
end

---------------------------------------------------------------- trails & auras

local function rootAttachment(root: BasePart, name: string, position: Vector3): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Position = position
	attachment:SetAttribute("LFCosmetic", true)
	attachment.Parent = root
	return attachment
end

function CosmeticBuilder.Trail(character: Model, data)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local width = data.Width or 1
	local a0 = rootAttachment(root, "TrailTop", Vector3.new(0, 0.8 * width, 0.4))
	local a1 = rootAttachment(root, "TrailBottom", Vector3.new(0, -1.4 * width, 0.4))
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = data.Lifetime or 0.6
	trail.LightEmission = data.LightEmission or 0.2
	trail.FaceCamera = true
	trail.MinLength = 0.1
	if data.Texture and TEXTURES[data.Texture] then
		trail.Texture = TEXTURES[data.Texture]
		trail.TextureMode = Enum.TextureMode.Wrap
		trail.TextureLength = 2
	end
	trail.Color = sequence(data.Colors)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
	trail:SetAttribute("LFCosmetic", true)
	trail.Parent = root
end

-- Gentle particle aura. Rates are deliberately low (a handful of particles per second).
local AURAS = {
	Smoke = { Texture = "Smoke", Rate = 4, Lifetime = { 1.5, 2.2 }, Size = { 1.2, 2.8 }, Speed = { 0.5, 1.2 }, Transparency = 0.55, Light = 0, Up = 1.5 },
	Confetti = { Rate = 9, Lifetime = { 1.2, 1.8 }, Size = { 0.18, 0.18 }, Speed = { 3, 5 }, Transparency = 0, Light = 0.2, Fall = true, Spin = true },
	Stars = { Texture = "Sparkle", Rate = 6, Lifetime = { 0.8, 1.4 }, Size = { 0.2, 0.55 }, Speed = { 0.4, 1 }, Transparency = 0, Light = 1, Twinkle = true },
	Neon = { Texture = "Sparkle", Rate = 8, Lifetime = { 0.6, 1.1 }, Size = { 0.25, 0.5 }, Speed = { 1, 2 }, Transparency = 0, Light = 1 },
	Golden = { Texture = "Sparkle", Rate = 7, Lifetime = { 1, 1.6 }, Size = { 0.2, 0.45 }, Speed = { 0.3, 0.8 }, Transparency = 0, Light = 1, Up = 1 },
	Lightning = { Texture = "Sparkle", Rate = 12, Lifetime = { 0.15, 0.3 }, Size = { 0.4, 0.8 }, Speed = { 5, 9 }, Transparency = 0, Light = 1 },
}
CosmeticBuilder.AuraStyles = AURAS

function CosmeticBuilder.Aura(character: Model, data)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local style = AURAS[data.Style]
	if not root or not style then
		return
	end
	local attachment = rootAttachment(root, "LF_Aura", Vector3.new(0, 0, 0))
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "LF_Aura"
	if style.Texture then
		emitter.Texture = TEXTURES[style.Texture]
	end
	emitter.Color = sequence(data.Colors)
	emitter.LightEmission = style.Light
	emitter.Rate = style.Rate
	emitter.Lifetime = NumberRange.new(style.Lifetime[1], style.Lifetime[2])
	emitter.Speed = NumberRange.new(style.Speed[1], style.Speed[2])
	emitter.SpreadAngle = Vector2.new(180, 180)
	if style.Twinkle then
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, style.Size[2]), NumberSequenceKeypoint.new(1, 0) })
	else
		emitter.Size = NumberSequence.new(style.Size[1], style.Size[2])
	end
	emitter.Transparency = NumberSequence.new(style.Transparency, 1)
	if style.Fall then
		emitter.Acceleration = Vector3.new(0, -9, 0)
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.SpreadAngle = Vector2.new(50, 50)
	elseif style.Up then
		emitter.Acceleration = Vector3.new(0, style.Up, 0)
	end
	if style.Spin then
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-200, 200)
	end
	emitter:SetAttribute("LFCosmetic", true)
	emitter.Parent = attachment
end

---------------------------------------------------------------- character entry points

function CosmeticBuilder.Clear(character: Model)
	local existing = character:FindFirstChild(CosmeticBuilder.FolderName)
	if existing then
		existing:Destroy()
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		for _, child in root:GetChildren() do
			if child:GetAttribute("LFCosmetic") then
				child:Destroy()
			end
		end
	end
end

-- itemsBySlot: { [slot]: catalog item }. Builds everything except the title tag (server-only,
-- it needs the player's name) into the character.
function CosmeticBuilder.ApplyCharacter(character: Model, itemsBySlot: { [string]: any }, onError: ((string, any) -> ())?)
	CosmeticBuilder.Clear(character)
	local folder = Instance.new("Folder")
	folder.Name = CosmeticBuilder.FolderName
	folder.Parent = character
	local head = character:FindFirstChild("Head") :: BasePart?
	local torso = (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) :: BasePart?
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local function try(item, fn: () -> ())
		local ok, err = pcall(fn)
		if not ok and onError then
			onError(item.Id, err)
		end
	end
	local outfit = itemsBySlot.Outfit
	if outfit and outfit.Data then
		try(outfit, function()
			CosmeticBuilder.Outfit(folder, character, outfit.Data)
		end)
	end
	for _, slot in { "Hat", "Face", "Body" } do
		local item = itemsBySlot[slot]
		if item and item.Data and SHAPES[item.Data.Shape] then
			local anchor = if slot == "Body" then torso else head
			if anchor then
				try(item, function()
					SHAPES[item.Data.Shape](folder, anchor, item.Data)
				end)
			end
		end
	end
	local badge = itemsBySlot.Badge
	if badge and badge.Data and BADGES[badge.Data.Shape] and torso then
		try(badge, function()
			BADGES[badge.Data.Shape](folder, torso, badge.Data)
		end)
	end
	local luggage = itemsBySlot.Luggage
	if luggage and luggage.Data and LUGGAGE[luggage.Data.Shape] and root then
		try(luggage, function()
			LUGGAGE[luggage.Data.Shape](folder, root, luggage.Data)
		end)
	end
	local trail = itemsBySlot.Trail
	if trail and trail.Data then
		try(trail, function()
			CosmeticBuilder.Trail(character, trail.Data)
		end)
	end
	local aura = itemsBySlot.Aura
	if aura and aura.Data then
		try(aura, function()
			CosmeticBuilder.Aura(character, aura.Data)
		end)
	end
	return folder
end

---------------------------------------------------------------- aircraft

local HULL_PARTS = { Wing = true, Winglet = true, Belly = true, Pylon = true, Fuselage = true, Nose = true, Tail = true, Stabilizer = true }

local function upright(position: Vector3, look: Vector3): CFrame
	local right = look:Cross(Vector3.yAxis)
	if right.Magnitude < 1e-4 then
		right = Vector3.xAxis
	end
	right = right.Unit
	return CFrame.fromMatrix(position, right, right:Cross(look).Unit)
end

local function decoration(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

--[[
	Applies a plane look to an aircraft model (the real Exterior, or the store's mini plane).
	`state` remembers the original colours so switching or removing a skin restores them.
	Parts named in HULL_PARTS take the hull colour, "EngineL"/"EngineR" the engine colour,
	"WingTipLight" the wing effect tip colour; stripes, wing strips and engine trails are added
	as separate decoration in an "LF_PlaneLook" folder.
]]
function CosmeticBuilder.ApplyPlane(model: Instance, skin, wing, trail, state: { [string]: any })
	state.Originals = state.Originals or {}
	local originals = state.Originals
	local old = model:FindFirstChild("LF_PlaneLook")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "LF_PlaneLook"
	folder.Parent = model
	local skinData = skin and skin.Data or nil
	local wingData = wing and wing.Data or nil
	local trailData = trail and trail.Data or nil
	local bellies = {}
	local wings = {}
	local exhausts = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not part:IsDescendantOf(folder) then
			local name = part.Name
			local role = if HULL_PARTS[name] then "Hull" elseif name == "EngineL" or name == "EngineR" then "Engine" elseif name == "WingTipLight" then "Tip" else nil
			if role then
				if not originals[part] then
					originals[part] = { Color = part.Color, Material = part.Material }
				end
				local original = originals[part]
				local color, material = original.Color, original.Material
				if role == "Hull" and skinData then
					color = skinData.Hull
					material = skinData.Material or original.Material
				elseif role == "Engine" and skinData then
					color = skinData.Engine
					if skinData.Gold then
						material = Enum.Material.Foil
					end
				elseif role == "Tip" and wingData and wingData.Tip then
					color = wingData.Tip
				end
				part.Color = color
				part.Material = material
			end
			if name == "Belly" or name == "Fuselage" then
				table.insert(bellies, part)
			elseif name == "Wing" then
				table.insert(wings, part)
			elseif name == "EngineLExhaust" or name == "EngineRExhaust" then
				table.insert(exhausts, part)
			end
		end
	end
	-- livery stripes along both sides of the fuselage
	if skinData and skinData.Stripe then
		local stripeMaterial = if skinData.Neon then Enum.Material.Neon elseif skinData.Gold then Enum.Material.Foil else Enum.Material.SmoothPlastic
		for _, body in bellies do
			local size = body.Size
			for _, side in { -1, 1 } do
				decoration(folder, "Stripe", Vector3.new(size.X * 0.96, math.max(0.2, size.Y * 0.28), 0.06), body.CFrame * CFrame.new(0, size.Y * 0.18, side * (size.Z / 2 + 0.04)), skinData.Stripe, stripeMaterial)
				if skinData.Stripe2 then
					decoration(folder, "Stripe2", Vector3.new(size.X * 0.96, math.max(0.12, size.Y * 0.14), 0.06), body.CFrame * CFrame.new(0, -size.Y * 0.12, side * (size.Z / 2 + 0.04)), skinData.Stripe2, stripeMaterial)
				end
			end
		end
	end
	-- glowing strips along the wing leading edges (+X is the nose)
	if wingData and wingData.Strip then
		for _, wingPart in wings do
			local size = wingPart.Size
			local strip = decoration(folder, "WingStrip", Vector3.new(math.max(0.3, size.X * 0.05), size.Y + 0.08, size.Z * 0.98), wingPart.CFrame * CFrame.new(size.X / 2 - size.X * 0.025, 0, 0), wingData.Strip, Enum.Material.Neon)
			if wingData.Sparkle then
				sparkles(strip, wingData.Sparkle, 5)
			end
		end
	end
	-- engine trails: emitters pointing backwards (-X); the scrolling sky does the rest
	if trailData then
		for _, exhaust in exhausts do
			local holder = decoration(folder, "TrailEmitter", Vector3.new(0.2, 0.2, 0.2), upright(exhaust.Position, -Vector3.xAxis), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
			holder.Transparency = 1
			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = "LF_PlaneTrail"
			emitter.Texture = TEXTURES[trailData.Texture or "Smoke"] or TEXTURES.Smoke
			emitter.Color = sequence(trailData.Colors)
			emitter.LightEmission = if trailData.Texture == "Sparkle" then 1 else 0.3
			emitter.EmissionDirection = Enum.NormalId.Front
			emitter.Rate = 22
			emitter.Lifetime = NumberRange.new(1.4, 2)
			emitter.Speed = NumberRange.new(45, 55)
			emitter.SpreadAngle = Vector2.new(2, 2)
			emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 4) })
			emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
			emitter.Parent = holder
		end
	end
	return folder
end

-- A small stylised airliner for the store's 3D preview, built from the same part names as the
-- real exterior so ApplyPlane works on it unchanged.
function CosmeticBuilder.BuildMiniPlane(): Model
	local model = Instance.new("Model")
	model.Name = "PreviewPlane"
	local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, shape: Enum.PartType?): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.Size = size
		p.CFrame = cframe
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		if shape then
			p.Shape = shape
		end
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	local hull = Color3.fromRGB(235, 238, 242)
	local fuselage = part("Fuselage", Vector3.new(20, 2.6, 2.6), CFrame.new(0, 0, 0), hull)
	part("Nose", Vector3.new(2.6, 2.6, 2.6), CFrame.new(10, 0, 0), hull, Enum.PartType.Ball)
	part("Cockpit", Vector3.new(1.2, 0.7, 1.8), CFrame.new(10.2, 0.55, 0), Color3.fromRGB(40, 60, 90))
	for _, side in { -1, 1 } do
		part("Wing", Vector3.new(4, 0.3, 9), CFrame.new(0.5, -0.6, side * 5.6) * CFrame.Angles(0, side * math.rad(-14), 0), hull)
		part("WingTipLight", Vector3.new(0.4, 0.4, 0.3), CFrame.new(-0.8, -0.5, side * 10.1), if side < 0 then Color3.fromRGB(255, 40, 40) else Color3.fromRGB(40, 255, 80))
		part(if side < 0 then "EngineL" else "EngineR", Vector3.new(2.6, 1.2, 1.2), CFrame.new(1.2, -1.3, side * 3.8), Color3.fromRGB(200, 204, 210), Enum.PartType.Cylinder)
		local exhaust = part(if side < 0 then "EngineLExhaust" else "EngineRExhaust", Vector3.new(0.2, 0.2, 0.2), CFrame.new(-0.2, -1.3, side * 3.8), hull)
		exhaust.Transparency = 1
		part("Stabilizer", Vector3.new(2, 0.2, 3.4), CFrame.new(-9, 0.4, side * 1.9), hull)
	end
	part("Tail", Vector3.new(2.6, 3.2, 0.3), CFrame.new(-9.2, 2.2, 0), hull)
	-- window row
	for i = -3, 3 do
		for _, side in { -1, 1 } do
			part("Window", Vector3.new(0.5, 0.45, 0.05), CFrame.new(i * 2.2, 0.45, side * 1.31), Color3.fromRGB(40, 60, 90))
		end
	end
	model.PrimaryPart = fuselage
	return model
end

return CosmeticBuilder
