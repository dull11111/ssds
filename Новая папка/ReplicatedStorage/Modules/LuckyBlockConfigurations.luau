--!strict
-- LOCATION: ReplicatedStorage/Modules/LuckyBlockConfigurations

local LuckyBlockConfigurations = {}

export type BlockConfig = {
	DisplayName: string?,
	Rarity: string,
	DespawnTime: number,
	Drops: { string }
}

LuckyBlockConfigurations.Blocks = {
	["YellowLuckyBlock"] = {
		DisplayName = "Yellow Lucky Block",
		Rarity = "Common",
		DespawnTime = 30, -- seconds
		Drops = {"Rhino Toasterino", "Peant Jarro"} -- Low Commons
	},
	["GreenBulkyLuckyBlock"] = {
		DisplayName = "Green Bulky Lucky Block",
		Rarity = "Common",
		DespawnTime = 30,
		Drops = {"Dipperi Chiperini", "Sigma Boy"} -- Mid Commons
	},
	["ShieldLuckyBlock"] = {
		DisplayName = "Shield Lucky Block",
		Rarity = "Common",
		DespawnTime = 30,
		Drops = {"Tralalerita Tralala", "1x1x1x1"} -- High Commons
	},
	["Blue67LuckyBlock"] = {
		DisplayName = "Blue 67 Lucky Block",
		Rarity = "Common",
		DespawnTime = 30,
		Drops = {"Guest666", "Cactus Pingu"} -- Low Uncommons
	},
	["LuckyBlockPlanetYellow"] = {
		DisplayName = "Lucky Block Planet Yellow",
		Rarity = "Common",
		DespawnTime = 30,
		Drops = {"L", "W"} -- Mid Uncommons
	},
	["PurpleAngelLuckyBlock"] = {
		DisplayName = "Purple Angel Lucky Block",
		Rarity = "Common",
		DespawnTime = 30,
		Drops = {"Ballerina Cappuccina", "Bombardini Gusini"} -- High Uncommon / Low Rare
	},
	["UFOLuckyBlock"] = {
		DisplayName = "UFO Lucky Block",
		Rarity = "Common",
		DespawnTime = 30,
		Drops = {"Fryuro", "Burguro"} -- Mid Rares
	},
	["PurpleDragonLuckyBlock"] = {
		DisplayName = "Purple Dragon Lucky Block",
		Rarity = "Common",
		DespawnTime = 30,
		Drops = {"Cacto Hipopotamo", "Garamararamararaman"} -- High Rares
	},
	["HeavenLuckyBlock"] = {
		DisplayName = "Heaven Lucky Block",
		Rarity = "Common",
		DespawnTime = 30,
		Drops = {"Madung", "Waterdino"} -- Low Epics
	},
	["KingLuckyBlock"] = {
		DisplayName = "King Lucky Block",
		Rarity = "Common",
		DespawnTime = 30,
		Drops = {"Tuff Toucan", "Torrtuginni Dragonfrutini"} -- Mid Epics
	},
	["DarkLuckyBlock"] = {
		DisplayName = "Dark Lucky Block",
		Rarity = "Common",
		DespawnTime = 30,
		Drops = {"Tictac Sahur", "SWAGGY BROS"} -- High Epic / Low Legendary
	},
	["DemonLuckyBlock"] = {
		DisplayName = "Demon Lucky Block",
		Rarity = "Common",
		DespawnTime = 30,
		Drops = {"SWAG SODA", "Stoppo Luminino", "Spaghetti Tualetti"} -- High Legendaries
	},
	["BulkyHeavenLuckyBlock"] = {
		DisplayName = "Bulky Heaven Lucky Block",
		Rarity = "Common",
		DespawnTime = 30,
		Drops = {"Smurf Cat", "Skibidi Toilet", "Rinooccio Verdini"} -- Mythicals
	},
} :: { [string]: BlockConfig }

function LuckyBlockConfigurations.GetRandomDrop(blockName: string): string?
	local blockData = LuckyBlockConfigurations.Blocks[blockName]
	if not blockData or not blockData.Drops or #blockData.Drops == 0 then return nil end

	return blockData.Drops[math.random(1, #blockData.Drops)]
end

return LuckyBlockConfigurations