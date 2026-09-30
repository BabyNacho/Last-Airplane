--[[
	Virtual-time scheduler that replaces Roblox's `task` library, os.clock/os.time and tick()
	inside the simulation sandbox. Minutes of game time run in milliseconds, deterministically.
]]

local Scheduler = {}
Scheduler.__index = Scheduler

type Entry = { Time: number, Seq: number, Thread: thread, Args: { any }?, N: number }

function Scheduler.new(errorHandler: (string, thread) -> ())
	local self = setmetatable({}, Scheduler)
	self.Now = 0
	self.Epoch = 1_760_000_000
	self.Queue = {} :: { Entry }
	self.Seq = 0
	self.Cancelled = {} :: { [thread]: boolean }
	self.OnError = errorHandler
	self.Managed = {} :: { [thread]: boolean }
	return self
end

function Scheduler:_push(time: number, thread: thread, ...)
	self.Seq += 1
	local entry = { Time = time, Seq = self.Seq, Thread = thread, Args = table.pack(...), N = select("#", ...) }
	-- insertion keeps the queue sorted by (time, seq)
	local queue = self.Queue
	local index = #queue + 1
	for i = #queue, 1, -1 do
		local other = queue[i]
		if other.Time < time or (other.Time == time and other.Seq < entry.Seq) then
			break
		end
		index = i
	end
	table.insert(queue, index, entry)
end

function Scheduler:_resume(thread: thread, ...)
	if self.Cancelled[thread] or coroutine.status(thread) == "dead" then
		return
	end
	self.Managed[thread] = true
	local ok, err = coroutine.resume(thread, ...)
	if not ok then
		self.OnError(tostring(err) .. "\n" .. debug.traceback(thread), thread)
	end
end

function Scheduler:Library()
	local scheduler = self
	local lib = {}
	function lib.spawn(fn: any, ...)
		local thread = if type(fn) == "thread" then fn else coroutine.create(fn)
		scheduler:_resume(thread, ...)
		return thread
	end
	function lib.defer(fn: any, ...)
		local thread = if type(fn) == "thread" then fn else coroutine.create(fn)
		scheduler:_push(scheduler.Now, thread, ...)
		return thread
	end
	function lib.delay(seconds: number?, fn: any, ...)
		local thread = if type(fn) == "thread" then fn else coroutine.create(fn)
		scheduler:_push(scheduler.Now + math.max(0, seconds or 0), thread, ...)
		return thread
	end
	function lib.wait(seconds: number?)
		local thread = coroutine.running()
		local start = scheduler.Now
		scheduler:_push(scheduler.Now + math.max(1 / 60, seconds or 0), thread)
		coroutine.yield()
		return scheduler.Now - start
	end
	function lib.cancel(thread: thread)
		scheduler.Cancelled[thread] = true
		if coroutine.status(thread) == "suspended" then
			pcall(coroutine.close, thread)
		end
	end
	function lib.synchronize() end
	function lib.desynchronize() end
	return lib
end

function Scheduler:Clock(): number
	return self.Now
end

function Scheduler:Time(): number
	return self.Epoch + math.floor(self.Now)
end

-- Runs queued work until virtual time reaches `untilTime` (or the queue empties).
function Scheduler:RunUntil(untilTime: number)
	while #self.Queue > 0 do
		local entry = self.Queue[1]
		if entry.Time > untilTime then
			break
		end
		table.remove(self.Queue, 1)
		self.Now = math.max(self.Now, entry.Time)
		local args = entry.Args :: { any }
		self:_resume(entry.Thread, table.unpack(args, 1, entry.N))
	end
	self.Now = math.max(self.Now, untilTime)
end

function Scheduler:Advance(seconds: number)
	self:RunUntil(self.Now + seconds)
end

return Scheduler
