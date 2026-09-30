local World = require("./World")
local world = World.new()
world:Boot()
world:Advance(1)
local p = world:AddPlayer("Alice")
local gs = world.Game:GetService("ReplicatedStorage"):FindFirstChild("GameState")
local last = nil
for i = 1, 600 do
	world:Advance(1)
	local phase = gs:GetAttribute("Phase")
	if phase ~= last then
		print(string.format("[t=%4d] phase %s", world.Scheduler.Now, tostring(phase)))
		last = phase
	end
	if #world.Errors > 0 then break end
end
print("prints:") for _, l in world.Prints do print("  ", l) end
print("warnings:") for _, l in world.Warnings do print("  ", l) end
print("errors:") for _, l in world.Errors do print("  ", l) end
