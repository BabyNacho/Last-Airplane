--[[
	EffectsService
	Server-side front door for everything the players see and hear: warnings, intercom
	announcements, toasts, camera shakes and sounds. Visuals run on clients; the server decides.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Registry = require(script.Parent.Parent.Registry)

local EffectsService = {}

local function audience(target: any): { Player }
	if target == nil then
		local round = Registry.RoundService and Registry.RoundService:GetContext()
		if round then
			return round:Players()
		end
		return Players:GetPlayers()
	elseif target == "all" then
		return Players:GetPlayers()
	elseif typeof(target) == "Instance" then
		return { target }
	end
	return target
end

-- Big atmospheric alert. severity: "info" | "warn" | "danger"
function EffectsService:Warning(title: string, subtitle: string?, severity: string?, target: any)
	Net.FireList("Warning", audience(target), { Title = title, Subtitle = subtitle, Severity = severity or "warn" })
end

-- Intercom subtitles. speaker: "Captain", "Flight Attendant", "ATC", "Passenger"...
function EffectsService:Announce(speaker: string, text: string, options: { Garbled: boolean?, Duration: number? }?, target: any)
	Net.FireList("Announcement", audience(target), {
		Speaker = speaker,
		Text = text,
		Garbled = options and options.Garbled or false,
		Duration = options and options.Duration,
	})
end

function EffectsService:Notify(text: string, kind: string?, target: any)
	Net.FireList("Notify", audience(target), { Text = text, Kind = kind or "info" })
end

-- One-shot effect. See client EffectsController for the list of effect names.
function EffectsService:Effect(name: string, data: { [string]: any }?, target: any)
	local payload = data and table.clone(data) or {}
	payload.Name = name
	Net.FireList("Effect", audience(target), payload)
end

function EffectsService:Shake(intensity: number, duration: number, target: any)
	self:Effect("Shake", { Intensity = intensity, Duration = duration }, target)
end

function EffectsService:Sound(soundKey: string, position: Vector3?, target: any)
	self:Effect("Sound", { Sound = soundKey, Position = position }, target)
end

function EffectsService:Flash(color: Color3?, duration: number?, target: any)
	self:Effect("Flash", { Color = color or Color3.new(1, 1, 1), Duration = duration or 0.3 }, target)
end

return EffectsService
