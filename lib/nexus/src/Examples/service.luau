local Lifecycles = require(nil :: any)

local MyService = {
	[Lifecycles.Heartbeat] = true,
}

function MyService:Heartbeat()
	print("hi")
end

function MyService:Start() end

function MyService:Init() end

return MyService
