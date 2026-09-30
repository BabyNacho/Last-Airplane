--[[
	Maid
	Tracks connections, instances, threads and cleanup callbacks so a round (or a UI screen)
	can be torn down in one call without leaks.
]]

local Maid = {}
Maid.__index = Maid

export type Maid = typeof(setmetatable({} :: { _tasks: { any } }, Maid))

function Maid.new(): Maid
	return setmetatable({ _tasks = {} }, Maid)
end

function Maid.Give(self: Maid, item: any): any
	table.insert(self._tasks, item)
	return item
end

local function cleanup(item: any)
	local kind = typeof(item)
	if kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "thread" then
		if coroutine.status(item) ~= "dead" then
			pcall(task.cancel, item)
		end
	elseif kind == "function" then
		item()
	elseif kind == "table" then
		if type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.Disconnect) == "function" then
			item:Disconnect()
		elseif type(item.Clean) == "function" then
			item:Clean()
		end
	end
end

function Maid.Clean(self: Maid)
	local tasks = self._tasks
	self._tasks = {}
	for index = #tasks, 1, -1 do
		local ok, err = pcall(cleanup, tasks[index])
		if not ok then
			warn("[Maid] cleanup error:", err)
		end
	end
end

Maid.Destroy = Maid.Clean

return Maid
