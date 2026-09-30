--[[
	BuildUtil
	Helpers for procedural level construction.
]]

local CollectionService = game:GetService("CollectionService")

local BuildUtil = {}

type Props = { [string]: any }

local function apply(instance: Instance, props: Props?)
	if not props then
		return
	end
	local parent = props.Parent
	for key, value in props do
		if key ~= "Parent" and key ~= "Tags" and key ~= "Attributes" then
			(instance :: any)[key] = value
		end
	end
	if props.Tags then
		for _, tag in props.Tags do
			CollectionService:AddTag(instance, tag)
		end
	end
	if props.Attributes then
		for name, value in props.Attributes do
			instance:SetAttribute(name, value)
		end
	end
	if parent then
		instance.Parent = parent
	end
end

local function basePart(part: BasePart, props: Props?)
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	part.CastShadow = false
	apply(part, props)
	return part
end

function BuildUtil.Part(props: Props?): Part
	return basePart(Instance.new("Part"), props) :: Part
end

function BuildUtil.Wedge(props: Props?): WedgePart
	return basePart(Instance.new("WedgePart"), props) :: WedgePart
end

function BuildUtil.Cylinder(props: Props?): Part
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	return basePart(part, props) :: Part
end

function BuildUtil.Ball(props: Props?): Part
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	return basePart(part, props) :: Part
end

function BuildUtil.Seat(props: Props?): Seat
	return basePart(Instance.new("Seat"), props) :: Seat
end

function BuildUtil.Folder(name: string, parent: Instance?): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

function BuildUtil.Model(name: string, parent: Instance?): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

function BuildUtil.Instance(className: string, props: Props?): Instance
	local instance = Instance.new(className)
	apply(instance, props)
	return instance
end

-- Invisible anchor used for interactions, spawn points and effect origins.
function BuildUtil.Point(name: string, cframe: CFrame, parent: Instance, size: Vector3?): Part
	return BuildUtil.Part({
		Name = name,
		CFrame = cframe,
		Size = size or Vector3.new(1, 1, 1),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = parent,
	})
end

-- SurfaceGui text sign on a face of a part.
function BuildUtil.Sign(part: BasePart, face: Enum.NormalId, text: string, props: Props?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = (props and props.PixelsPerStud) or 40
	gui.LightInfluence = (props and props.LightInfluence) or 0
	gui.Brightness = (props and props.Brightness) or 1.5
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = (props and props.Font) or Enum.Font.GothamBold
	label.TextColor3 = (props and props.TextColor3) or Color3.new(1, 1, 1)
	label.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.06, 0)
	padding.PaddingRight = UDim.new(0.06, 0)
	padding.PaddingTop = UDim.new(0.1, 0)
	padding.PaddingBottom = UDim.new(0.1, 0)
	padding.Parent = label
	return label
end

function BuildUtil.Light(parent: Instance, className: string, props: Props?): Light
	local light = Instance.new(className) :: Light
	light.Shadows = false
	apply(light, props)
	light.Parent = parent
	return light
end

function BuildUtil.Tag(instance: Instance, tag: string)
	CollectionService:AddTag(instance, tag)
end

return BuildUtil
