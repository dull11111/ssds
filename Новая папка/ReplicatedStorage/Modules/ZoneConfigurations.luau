--!strict
-- LOCATION: ReplicatedStorage/Modules/ZoneConfigurations

local ZoneConfigurations = {
	["1"] = {
		PowerRequirement = 0,
		Guard = {
			NPCName = "Enemy1",
			WalkSpeed = 8,
		},
		LuckyBlockSpawner = {
			SpawnInterval = 1,
			MaxSpawnedBlocks = 10,
			Blocks = { "YellowLuckyBlock" , "GreenBulkyLuckyBlock" },
		},
	},
	["2"] = {
		PowerRequirement = 100,
		Guard = {
			NPCName = "Enemy2",
			WalkSpeed = 12,
		},
		LuckyBlockSpawner = {
			SpawnInterval = 10,
			MaxSpawnedBlocks = 10,
			Blocks = { "ShieldLuckyBlock" , "Blue67LuckyBlock" },
		},
	},
	["3"] = {
		PowerRequirement = 1000,
		Guard = {
			NPCName = "Enemy3",
			WalkSpeed = 16,
		},
		LuckyBlockSpawner = {
			SpawnInterval = 10,
			MaxSpawnedBlocks = 10,
			Blocks = { "LuckyBlockPlanetYellow" , "PurpleAngelLuckyBlock" },
		},
	},
	["4"] = {
		PowerRequirement = 10000,
		Guard = {
			NPCName = "Enemy4",
			WalkSpeed = 20,
		},
		LuckyBlockSpawner = {
			SpawnInterval = 10,
			MaxSpawnedBlocks = 10,
			Blocks = { "UFOLuckyBlock" , "PurpleDragonLuckyBlock" },
		},
	},
	["5"] = {
		PowerRequirement = 100000,
		Guard = {
			NPCName = "Enemy5",
			WalkSpeed = 24,
		},
		LuckyBlockSpawner = {
			SpawnInterval = 10,
			MaxSpawnedBlocks = 10,
			Blocks = { "HeavenLuckyBlock" , "KingLuckyBlock" },
		},
	},
	["6"] = {
		PowerRequirement = 1000000,
		Guard = {
			NPCName = "Enemy6",
			WalkSpeed = 28,
		},
		LuckyBlockSpawner = {
			SpawnInterval = 10,
			MaxSpawnedBlocks = 10,
			Blocks = { "DarkLuckyBlock" , "DemonLuckyBlock" , "BulkyHeavenLuckyBlock" },
		},
	},
}

return ZoneConfigurations