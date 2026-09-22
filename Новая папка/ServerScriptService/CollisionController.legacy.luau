--!strict
-- LOCATION: ServerScriptService/CollisionController

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local Workspace = game:GetService("Workspace")

local GROUP_CHAR = "PlayerCharacters"
local GROUP_COLLECTABLES = "Collectables"
local GROUP_GUARDS = "Guards"

-- 1. Create the Collision Groups
local function setupCollisionGroups()
	pcall(function()
		-- Register the groups
		PhysicsService:RegisterCollisionGroup(GROUP_CHAR)
		PhysicsService:RegisterCollisionGroup(GROUP_COLLECTABLES)
		PhysicsService:RegisterCollisionGroup(GROUP_GUARDS)

		-- Disable self-collisions (Players ignore Players)
		PhysicsService:CollisionGroupSetCollidable(GROUP_CHAR, GROUP_CHAR, false)

		-- Make Collectables ignore Players, Zones and Collectables
		PhysicsService:CollisionGroupSetCollidable(GROUP_COLLECTABLES, GROUP_CHAR, false)
		PhysicsService:CollisionGroupSetCollidable(GROUP_COLLECTABLES, GROUP_COLLECTABLES, false)
		
		PhysicsService:CollisionGroupSetCollidable(GROUP_GUARDS, GROUP_CHAR, false)
		PhysicsService:CollisionGroupSetCollidable(GROUP_GUARDS, GROUP_COLLECTABLES, false)
	end)
end

-- 2. Function to apply the group to character parts
local function setCharacterCollisionGroup(object: Instance)
	if object:IsA("BasePart") then
		pcall(function()
			object.CollisionGroup = GROUP_CHAR
		end)
	end
end

-- 3. Handler for when a character loads
local function onCharacterAdded(character: Model)
	-- Apply to existing parts (Head, Torso, Legs)
	for _, descendant in ipairs(character:GetDescendants()) do
		setCharacterCollisionGroup(descendant)
	end

	-- Listen for new parts (Tools, Hats/Accessories loaded after spawn)
	character.DescendantAdded:Connect(setCharacterCollisionGroup)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(onCharacterAdded)

	-- If character already exists (edge case)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

-- Initialize Player Collisions
setupCollisionGroups()

Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end
