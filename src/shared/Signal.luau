--[[
	Signal
	Lightweight in-process event (no Instance allocation). Handlers run in their own threads
	so one erroring listener can't break the others.
]]

local Signal = {}
Signal.__index = Signal

export type Connection = { Connected: boolean, Disconnect: (Connection) -> () }

function Signal.new()
	return setmetatable({ _handlers = {} :: { any } }, Signal)
end

function Signal:Connect(handler: (...any) -> ())
	local connection
	connection = {
		Connected = true,
		_handler = handler,
		Disconnect = function(self)
			self.Connected = false
			local index = table.find((connection :: any)._signal._handlers, self)
			if index then
				table.remove((connection :: any)._signal._handlers, index)
			end
		end,
		_signal = self,
	}
	table.insert(self._handlers, connection)
	return connection
end

function Signal:Fire(...)
	for _, connection in table.clone(self._handlers) do
		if connection.Connected then
			task.spawn(connection._handler, ...)
		end
	end
end

function Signal:Once(handler: (...any) -> ())
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

function Signal:DisconnectAll()
	for _, connection in self._handlers do
		connection.Connected = false
	end
	table.clear(self._handlers)
end

Signal.Destroy = Signal.DisconnectAll

return Signal
