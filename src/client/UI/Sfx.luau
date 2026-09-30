--[[
	Sfx
	Plays sounds from SoundConfig. 2D sounds are pooled under SoundService; positional sounds
	are parented to a temporary attachment at the given world position.
]]

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SoundConfig = require(ReplicatedStorage.Shared.Config.SoundConfig)

local Sfx = {}

local groups: { [string]: SoundGroup } = {}
local loops: { [string]: Sound } = {}
local lastPlayed: { [string]: number } = {}

local function group(name: string): SoundGroup
	local existing = groups[name]
	if existing then
		return existing
	end
	local g = Instance.new("SoundGroup")
	g.Name = name
	g.Volume = SoundConfig.Groups[name] or 0.6
	g.Parent = SoundService
	groups[name] = g
	return g
end

local function make(key: string): Sound?
	local def = SoundConfig.Sounds[key]
	if not def or def.SoundId == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = key
	sound.SoundId = def.SoundId
	sound.Volume = def.Volume or 0.5
	sound.PlaybackSpeed = def.Pitch or 1
	sound.Looped = def.Looped == true
	sound.SoundGroup = group(def.Group or "UI")
	return sound
end

-- One-shot. Rapid repeats of the same key are throttled.
function Sfx.Play(key: string, position: Vector3?, pitchJitter: number?)
	local now = os.clock()
	if now - (lastPlayed[key] or 0) < 0.05 then
		return
	end
	lastPlayed[key] = now
	local sound = make(key)
	if not sound then
		return
	end
	if pitchJitter then
		sound.PlaybackSpeed *= 1 + (math.random() - 0.5) * pitchJitter
	end
	if position then
		local holder = Instance.new("Attachment")
		holder.WorldPosition = position
		holder.Parent = Workspace.Terrain
		sound.RollOffMaxDistance = 90
		sound.Parent = holder
		sound.Ended:Once(function()
			holder:Destroy()
		end)
		task.delay(12, function()
			if holder.Parent then
				holder:Destroy()
			end
		end)
	else
		sound.Parent = SoundService
		sound.Ended:Once(function()
			sound:Destroy()
		end)
	end
	sound:Play()
end

-- Starts/stops a named loop. `volumeScale` lets callers fade loops (0..1).
function Sfx.Loop(key: string, on: boolean, volumeScale: number?)
	local sound = loops[key]
	if on then
		if not sound then
			local created = make(key)
			if not created then
				return
			end
			created.Looped = true
			created.Parent = SoundService
			created:Play()
			loops[key] = created
			sound = created
		end
		local def = SoundConfig.Sounds[key]
		;(sound :: Sound).Volume = (def and def.Volume or 0.5) * (volumeScale or 1)
	elseif sound then
		sound:Stop()
		sound:Destroy()
		loops[key] = nil
	end
end

function Sfx.SetLoopPitch(key: string, multiplier: number)
	local sound = loops[key]
	local def = SoundConfig.Sounds[key]
	if sound and def then
		sound.PlaybackSpeed = (def.Pitch or 1) * multiplier
	end
end

function Sfx.IsLooping(key: string): boolean
	return loops[key] ~= nil
end

return Sfx
