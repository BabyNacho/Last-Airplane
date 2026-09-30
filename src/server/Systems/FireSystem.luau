--[[
	FireSystem
	Real spreading fire on a grid of cells through the cabin.
	  * Fires grow, spread to neighbouring cells and hurt players standing in them (not instantly lethal).
	  * Closed cabin doors stop fire and smoke spreading between sections.
	  * Extinguisher sprayers knock intensity down in a cone in front of them.
	  * A powered faulty circuit re-ignites its origin until someone cuts the power.
	Smoke density per section is replicated as FlightState attributes (Smoke_<Section>) so the
	client can reduce visibility locally.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MapConfig = require(ReplicatedStorage.Shared.Config.MapConfig)
local SoundConfig = require(ReplicatedStorage.Shared.Config.SoundConfig)
local Util = require(ReplicatedStorage.Shared.Util)
local Registry = require(script.Parent.Parent.Registry)

local FireSystem = {}

local CFG = GameConfig.Fire

type Cell = {
	Part: BasePart,
	Section: string,
	Intensity: number,
	NextSpread: number,
	Fire: Fire?,
	Smoke: Smoke?,
	Light: PointLight?,
	Sound: Sound?,
	Neighbors: { any },
}

local cells: { Cell } = {}
local active: { [Cell]: boolean } = {}
local ctxRef: any = nil
local origin: Cell? = nil
local reigniteCheck: (() -> boolean)? = nil
local nextReignite = 0
local tickThread: thread? = nil

local DOOR_BETWEEN: { [string]: string } = {}
for _, divider in MapConfig.Dividers do
	DOOR_BETWEEN[divider.Between[1] .. "|" .. divider.Between[2]] = divider.Id
	DOOR_BETWEEN[divider.Between[2] .. "|" .. divider.Between[1]] = divider.Id
end

local function blocked(a: Cell, b: Cell): boolean
	if a.Section == b.Section then
		return false
	end
	local doorId = DOOR_BETWEEN[a.Section .. "|" .. b.Section]
	if not doorId then
		return false
	end
	return not Registry.MapService:IsDividerOpen(doorId)
end

local function visuals(cell: Cell)
	local intensity = cell.Intensity
	if intensity <= 0 then
		for _, key in { "Fire", "Smoke", "Light", "Sound" } do
			local inst = (cell :: any)[key]
			if inst then
				inst:Destroy()
				;(cell :: any)[key] = nil
			end
		end
		return
	end
	local ratio = intensity / CFG.MaxIntensity
	if not cell.Fire then
		local fire = Instance.new("Fire")
		fire.Heat = 12
		fire.Color = Color3.fromRGB(255, 120, 30)
		fire.SecondaryColor = Color3.fromRGB(255, 40, 0)
		fire.Parent = cell.Part
		cell.Fire = fire
		local smoke = Instance.new("Smoke")
		smoke.Color = Color3.fromRGB(40, 40, 40)
		smoke.RiseVelocity = 4
		smoke.Parent = cell.Part
		cell.Smoke = smoke
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 130, 50)
		light.Shadows = false
		light.Parent = cell.Part
		cell.Light = light
		local def = SoundConfig.Sounds.FireLoop
		if def.SoundId ~= "" then
			local sound = Instance.new("Sound")
			sound.SoundId = def.SoundId
			sound.Volume = def.Volume
			sound.PlaybackSpeed = def.Pitch
			sound.Looped = true
			sound.RollOffMaxDistance = 40
			sound.Parent = cell.Part
			sound:Play()
			cell.Sound = sound
		end
	end
	local fire = cell.Fire :: Fire
	fire.Size = 3 + ratio * 9
	fire.Heat = 8 + ratio * 14
	local smoke = cell.Smoke :: Smoke
	smoke.Size = 2 + ratio * 6
	smoke.Opacity = 0.08 + ratio * 0.25
	local light = cell.Light :: PointLight
	light.Range = 8 + ratio * 12
	light.Brightness = 1 + ratio * 2
end

local function publishCounts()
	local count = 0
	local sectionHeat: { [string]: number } = {}
	for cell in active do
		count += 1
		sectionHeat[cell.Section] = (sectionHeat[cell.Section] or 0) + cell.Intensity
	end
	local flight = Registry.FlightService
	flight:Set("Fires", count)
	for _, section in MapConfig.Sections do
		local heat = sectionHeat[section.Id] or 0
		flight:Set("Smoke_" .. section.Id, math.floor(math.clamp(heat / 260, 0, 1) * 100) / 100)
	end
end

function FireSystem:Ignite(cell: Cell, intensity: number?)
	if not ctxRef or not ctxRef.Active then
		return
	end
	local wasActive = active[cell]
	cell.Intensity = math.max(cell.Intensity, intensity or CFG.StartIntensity)
	cell.NextSpread = os.clock() + Util.RandomRange(ctxRef.Rng, CFG.SpreadInterval)
	active[cell] = true
	visuals(cell)
	publishCounts()
	if not wasActive then
		Registry.EffectsService:Effect("FireIgnited", { Position = cell.Part.Position, Section = cell.Section })
	end
end

function FireSystem:NearestCell(localPosition: Vector3): Cell?
	local worldPos = MapConfig.ToWorld(localPosition)
	local best, bestDist = nil, math.huge
	for _, cell in cells do
		local d = (cell.Part.Position - worldPos).Magnitude
		if d < bestDist then
			best, bestDist = cell, d
		end
	end
	return best
end

function FireSystem:CellNear(worldPosition: Vector3): Cell?
	return self:NearestCell(MapConfig.ToLocal(worldPosition))
end

-- Named fire origins used by disasters.
FireSystem.Origins = {
	FrontGalley = Vector3.new(59, 0, 6),
	AftGalley = Vector3.new(-54, 0, -6),
	Lavatory = Vector3.new(-42, 0, 6),
	Cabin = Vector3.new(12, 0, -6),
	Electrical = Vector3.new(-63, 0, -6),
	FirstClass = Vector3.new(40, 0, 6),
}

function FireSystem:StartAt(originKey: string, intensity: number?): Cell?
	local position = self.Origins[originKey] or self.Origins.Cabin
	local cell = self:NearestCell(position)
	if cell then
		self:Ignite(cell, intensity)
	end
	return cell
end

-- Sets the cell that re-ignites while `check()` returns true (faulty circuit still powered).
function FireSystem:SetOrigin(cell: Cell?, check: (() -> boolean)?)
	origin = cell
	reigniteCheck = check
	nextReignite = os.clock() + CFG.ReigniteInterval
end

function FireSystem:ActiveCount(): number
	local n = 0
	for _ in active do
		n += 1
	end
	return n
end

function FireSystem:ActiveCells(): { Cell }
	local list = {}
	for cell in active do
		table.insert(list, cell)
	end
	return list
end

function FireSystem:IsCellBurning(cell: Cell): boolean
	return active[cell] == true
end

function FireSystem:ExtinguishAll()
	for cell in active do
		cell.Intensity = 0
		visuals(cell)
	end
	table.clear(active)
	publishCounts()
end

function FireSystem:OnDoorChanged(_doorId: string, _open: boolean, _player: Player?)
	-- spread checks read door state live; nothing to cache
end

local function extinguish(cell: Cell, amount: number, player: Player)
	cell.Intensity -= amount
	Registry.ConditionService:MarkHazard(player, 2)
	if cell.Intensity <= 0 then
		cell.Intensity = 0
		active[cell] = nil
		visuals(cell)
		ctxRef:Add(player, "FiresExtinguished")
		Registry.EffectsService:Notify("Fire extinguished!", "good", player)
		Registry.RewardService:Popup(player, "FIRE OUT", nil)
		if Registry.ObjectiveService:IsActive("ExtinguishFires") then
			Registry.ObjectiveService:Progress("ExtinguishFires", 1, player)
		end
	else
		visuals(cell)
	end
end

local function step(dt: number)
	local now = os.clock()
	local round = ctxRef
	-- extinguishers
	for _, player in Registry.EquipmentService:Sprayers() do
		local tool, position, look = Registry.EquipmentService:GetSprayer(player)
		if tool and position and look then
			local charge = (tool:GetAttribute("Charge") or 0) - CFG.ExtinguisherDrainPerTick * dt
			tool:SetAttribute("Charge", math.max(0, charge))
			if charge <= 0 then
				Registry.EquipmentService:StopSpraying(player, tool)
				Registry.EffectsService:Notify("Extinguisher empty - find another one!", "warn", player)
			end
			for cell in active do
				local offset = cell.Part.Position - position
				local flat = Vector3.new(offset.X, 0, offset.Z)
				local distance = flat.Magnitude
				if distance <= CFG.ExtinguisherRange and (distance < 3 or flat.Unit:Dot(look) > 0.55) then
					extinguish(cell, CFG.ExtinguishPerTick * dt, player)
				end
			end
		end
	end

	-- growth, spread and damage
	for cell in active do
		cell.Intensity = math.min(CFG.MaxIntensity, cell.Intensity + CFG.GrowthPerTick * dt)
		visuals(cell)
		if now >= cell.NextSpread then
			cell.NextSpread = now + Util.RandomRange(round.Rng, CFG.SpreadInterval)
			if cell.Intensity > 35 then
				local candidates = {}
				for _, neighbor in cell.Neighbors do
					if not active[neighbor] and not blocked(cell, neighbor) then
						table.insert(candidates, neighbor)
					end
				end
				local target = Util.Pick(round.Rng, candidates)
				if target then
					FireSystem:Ignite(target, 25)
				end
			end
		end
	end

	for _, player in round:AlivePlayers() do
		local root = Util.GetRoot(player)
		if root then
			local total = 0
			for cell in active do
				local distance = (root.Position - cell.Part.Position).Magnitude
				if distance <= CFG.DamageRadius then
					total += CFG.DamagePerTick * (cell.Intensity / CFG.MaxIntensity) * (1 - distance / (CFG.DamageRadius + 2))
				end
			end
			if total > 0.2 then
				Registry.ConditionService:Damage(player, total * dt, "Burned in the fire")
			end
		end
	end

	-- faulty circuit re-ignition
	if origin and reigniteCheck and not active[origin] and now >= nextReignite then
		nextReignite = now + CFG.ReigniteInterval
		local ok, powered = pcall(reigniteCheck)
		if ok and powered then
			FireSystem:Ignite(origin, 30)
			Registry.EffectsService:Sound("Sparks", origin.Part.Position)
			Registry.EffectsService:Warning("FIRE RE-IGNITED", "The faulty circuit is still powered", "danger")
		end
	end
	publishCounts()
end

function FireSystem:Init()
	for _, section in MapConfig.Sections do
		Registry.FlightService:Set("Smoke_" .. section.Id, 0)
	end
end

function FireSystem:Start()
	for _, part in Registry.MapService.Points.FireCells do
		table.insert(cells, {
			Part = part,
			Section = part:GetAttribute("Section"),
			Intensity = 0,
			NextSpread = 0,
			Neighbors = {},
		})
	end
	for _, cell in cells do
		for _, other in cells do
			if other ~= cell and (other.Part.Position - cell.Part.Position).Magnitude <= 13 then
				table.insert(cell.Neighbors, other)
			end
		end
	end
end

function FireSystem:OnRoundStart(ctx)
	ctxRef = ctx
	self:ExtinguishAll()
	origin = nil
	reigniteCheck = nil
	if tickThread then
		pcall(task.cancel, tickThread)
	end
	tickThread = ctx:Every(0.5, function()
		if next(active) or (origin and reigniteCheck) or #Registry.EquipmentService:Sprayers() > 0 then
			step(0.5)
		end
		return true
	end)
end

function FireSystem:OnRoundEnd()
	self:ExtinguishAll()
	origin = nil
	reigniteCheck = nil
	ctxRef = nil
	tickThread = nil
end

return FireSystem
