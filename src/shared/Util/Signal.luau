-- Minimal Lua-side event (no Instances). Handlers run in their own thread so
-- one handler yielding or erroring can't block the others.

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ handlers = {} }, Signal)
end

function Signal:Connect(fn: (...any) -> ())
	table.insert(self.handlers, fn)
	local handlers = self.handlers
	return {
		Disconnect = function()
			local i = table.find(handlers, fn)
			if i then
				table.remove(handlers, i)
			end
		end,
	}
end

function Signal:Fire(...)
	for _, fn in table.clone(self.handlers) do
		task.spawn(fn, ...)
	end
end

return Signal
