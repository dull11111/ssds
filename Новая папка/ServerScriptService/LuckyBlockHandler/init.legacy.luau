--!strict
-- LOCATION: ServerScriptService/LuckyBlockHandler
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage.Modules
local ZoneConfigurations = require(Modules.ZoneConfigurations)
local LuckyBlockConfigurations = require(Modules.LuckyBlockConfigurations)
local ItemManager = require(game:GetService("ServerScriptService").Modules.ItemManager)

local LuckyBlocksFolder = ReplicatedStorage:WaitForChild("Items"):WaitForChild("LuckyBlocks"):WaitForChild("Normal")

local ZonesFolder = game.Workspace:WaitForChild("Zones")

local Spawner = require(script.Spawner)

local function initSpawner(spawnPart: BasePart)
	if not spawnPart:IsA("BasePart") then
		warn(`[LuckyBlockSpawner] Failed to initialize spawner; {spawnPart.Name} is not a BasePart!`)
		return
	end
	
	local zone = spawnPart.Name
	local zoneConfig = ZoneConfigurations[zone]
	if not zoneConfig then
		warn(`[LuckyBlockSpawnHandler] Zone {zone} not configured in ZoneConfigurations, skipping!`)
		return
	end
	
	local spawnerConfig = zoneConfig.LuckyBlockSpawner
	local spawnerSample = {}
	local spawnerSampleDespawnTimes = {}
	
	for _, luckyBlockName in spawnerConfig.Blocks do
		local blockConfig = LuckyBlockConfigurations.Blocks[luckyBlockName]
		if not blockConfig then
			warn(`[LuckyBlockSpawnHandler] Lucky Block {luckyBlockName} not configured in LuckyBlockConfigurations, skipping!`)
			continue
		end
		
		local sample = LuckyBlocksFolder:FindFirstChild(luckyBlockName) :: Model?
		if not sample then
			warn(`[LuckyBlockSpawnHandler] Lucky Block {luckyBlockName} model not found, skipping!`)
			continue
		end
		
		table.insert(spawnerSample, sample)
		spawnerSampleDespawnTimes[sample] = blockConfig.DespawnTime
	end
	
	local spawner = Spawner.new(spawnPart, spawnerSample, spawnerSampleDespawnTimes, spawnerConfig.SpawnInterval, spawnerConfig.MaxSpawnedBlocks)
	spawner:OnBlockSpawn(function(block: Model)
		for _, part in block:GetDescendants() do
			if part:IsA("BasePart") then
				part.CollisionGroup = "Collectables"
			end
		end
		
		if not block.PrimaryPart then
			warn(`[LuckyBlockHandler] Lucky Block {block.Name} does not have a PrimaryPart set! Please set it to a part that is parented to the model to make it pullable!`)
			return
		end
		
		local blockConfig = LuckyBlockConfigurations.Blocks[block.Name]
		block:SetAttribute("OriginalName", block.Name)
		block:SetAttribute("Rarity", blockConfig.Rarity)
		block:SetAttribute("ItemType", "LuckyBlocks")
		
		ItemManager.SetupItemGUI(block)
		
		block.PrimaryPart.CustomPhysicalProperties = PhysicalProperties.new(20, 0.3, 0, 1, 1)
		block.PrimaryPart:SetAttribute("PowerRequirement", zoneConfig.PowerRequirement)
		block.PrimaryPart:SetAttribute("DespawnTimestamp", block:GetAttribute("DespawnTimestamp"))
		block.PrimaryPart:AddTag("Pullable")
	end)
end

for _, zone in ZonesFolder:GetChildren() :: { BasePart } do
	initSpawner(zone)
end
