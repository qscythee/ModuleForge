local MyService = {}

function MyService.OnPlayerAdded(player: Player)
	print(`${player.Name} joined the game!`)
end

function MyService.Start() end

function MyService.Init() end

return MyService
