--!strict
-- Minimal signal för kommunikation mellan moduler på samma sida (klient eller server).

export type Connection = {
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	Connect: (self: Signal, callback: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
}

local Signal = {}

function Signal.new(): Signal
	local listeners: { [number]: ((...any) -> ())? } = {}
	local nextId = 0
	local self = {}

	function self:Connect(callback: (...any) -> ()): Connection
		nextId += 1
		local id = nextId
		listeners[id] = callback
		local connection = {}
		function connection:Disconnect()
			listeners[id] = nil
		end
		return connection :: Connection
	end

	function self:Fire(...: any)
		for _, callback in listeners do
			if callback then
				task.spawn(callback, ...)
			end
		end
	end

	return self :: Signal
end

return Signal
