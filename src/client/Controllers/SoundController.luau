--[[
	SoundController
	Ambience (cabin hum, engines, rain, wind, lobby), alarms driven by FlightState attributes and
	one-shot sounds requested by the server through the Effect remote.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MapConfig = require(ReplicatedStorage.Shared.Config.MapConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local ClientState = require(script.Parent.Parent.ClientState)
local Sfx = require(script.Parent.Parent.UI.Sfx)

local SoundController = {}


local function aboard(): boolean
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end
	return MapConfig.IsInsidePlane(camera.Focus.Position)
end

local function updateAmbience()
	local inPlane = aboard()
	local flight = ClientState.Flight
	local onGround = flight("OnGround") == true
	Sfx.Loop("LobbyAmbience", not inPlane)
	Sfx.Loop("CabinHum", inPlane)
	local thrust = ((flight("EngineL") or 100) + (flight("EngineR") or 100)) / 200
	Sfx.Loop("EngineDrone", inPlane and not onGround, 0.4 + thrust * 0.6)
	Sfx.SetLoopPitch("EngineDrone", 0.8 + thrust * 0.2 + (if flight("Approach") then -0.1 else 0))
	Sfx.Loop("RainLoop", inPlane and (flight("Storm") or 0) > 0)
	local decompressed = flight("OxygenEmergency") == true and (flight("Pressure") or 100) < 50
	Sfx.Loop("WindRush", inPlane and decompressed, 0.6)
	Sfx.Loop("FireAlarm", inPlane and flight("FireAlarmActive") == true, 0.5)
	Sfx.Loop("PressureAlarm", inPlane and flight("PressureAlarm") == true, 0.45)
	local camera = workspace.CurrentCamera
	local inCockpit = camera and MapConfig.SectionAt(MapConfig.ToLocal(camera.Focus.Position).X) == "Cockpit"
	Sfx.Loop("MasterCaution", inPlane and flight("CockpitAlarm") == true and inCockpit == true, 0.5)
end

function SoundController:Start()
	Net.Event("Effect").OnClientEvent:Connect(function(data)
		if data.Name == "Sound" and data.Sound then
			Sfx.Play(data.Sound, data.Position)
		end
	end)
	ClientState.OnFlight("SeatbeltSign", function(on)
		if on ~= nil and aboard() then
			Sfx.Play("SeatbeltChime")
		end
	end)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.5 then
			accumulator = 0
			updateAmbience()
		end
	end)
end

return SoundController
