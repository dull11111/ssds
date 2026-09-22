--!strict
-- LOCATION: ServerScriptService/PlayerDensity

-- Important for the player to be able to pull many lucky blocks!

local Players = game:GetService("Players")

local function onCharacterAdded(player: Player, char: Model)
	local root = char:WaitForChild("HumanoidRootPart") :: BasePart
	root.CustomPhysicalProperties = PhysicalProperties.new(10, 0.3, 0.5, 1, 1)
end

local function onPlayerAdded(player: Player)
	local char = player.Character
	if char then
		onCharacterAdded(player, char)
	end
	
	player.CharacterAdded:Connect(function(char)
		onCharacterAdded(player, char)
	end)
end

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)