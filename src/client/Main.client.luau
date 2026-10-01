--[[
	LAST FLIGHT - client entry point.
	Loads controllers in order: Init (build UI, no yielding) then Start (connections, loops).
]]

local ClientState = require(script.Parent.ClientState)
local UIKit = require(script.Parent.UI.UIKit)

local ORDER = {
	"SoundController",
	"LightingController",
	"OutsideWorldController",
	"PlaneCosmeticController",
	"EffectsController",
	"CameraController",
	"CharacterController",
	"PromptController",
	"HUDController",
	"DecisionController",
	"CockpitController",
	"ShopController",
	"ProfileController",
	"EmoteController",
	"ResultsController",
	"ChatTagController",
}

UIKit.Init()
ClientState.Init()

local controllers = {}
for _, name in ORDER do
	local module = script.Parent.Controllers:FindFirstChild(name)
	if module then
		local ok, result = pcall(require, module)
		if ok then
			controllers[name] = result
		else
			warn("[Client] failed to load", name, result)
		end
	else
		warn("[Client] missing controller", name)
	end
end

for _, name in ORDER do
	local controller = controllers[name]
	if controller and controller.Init then
		local ok, err = pcall(controller.Init, controller, controllers)
		if not ok then
			warn("[Client] Init failed", name, err)
		end
	end
end

for _, name in ORDER do
	local controller = controllers[name]
	if controller and controller.Start then
		task.spawn(function()
			local ok, err = pcall(controller.Start, controller)
			if not ok then
				warn("[Client] Start failed", name, err)
			end
		end)
	end
end
