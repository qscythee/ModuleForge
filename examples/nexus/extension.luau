local Players = game:GetService("Players")

local PlayerExtension = {}

function PlayerExtension.BeforeStart(provider)
	local playerAddedFn = provider.OnPlayerAdded
	if typeof(playerAddedFn) == "function" then
		for _, player in Players:GetPlayers() do
			task.spawn(playerAddedFn, provider, player)
		end

		Players.PlayerAdded:Connect(function(player)
			task.spawn(playerAddedFn, provider, player)
		end)
	end
end

return PlayerExtension
