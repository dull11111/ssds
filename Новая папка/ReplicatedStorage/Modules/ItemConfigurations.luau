--!strict
-- LOCATION: ReplicatedStorage/Modules/ItemConfigurations

local LuckyBlockConfigurations = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("LuckyBlockConfigurations"))

local ItemConfigurations = {}

ItemConfigurations.Items = {
	Main = {
		["Rhino Toasterino"] = { Rarity = "Common", Income = 20, ImageId = "rbxassetid://79090027652300" },
		["Peant Jarro"] = { Rarity = "Common", Income = 22, ImageId = "rbxassetid://131554490759014" },
		["Dipperi Chiperini"] = { Rarity = "Common", Income = 24, ImageId = "rbxassetid://138415026047381" },
		["Sigma Boy"] = { Rarity = "Common", Income = 26, ImageId = "rbxassetid://97524125419648" },
		["Tralalerita Tralala"] = { Rarity = "Common", Income = 28, ImageId = "rbxassetid://86651648554862" },
		["1x1x1x1"] = { Rarity = "Common", Income = 30, ImageId = "rbxassetid://83029486848462" },

		["Guest666"] = { Rarity = "Uncommon", Income = 35, ImageId = "rbxassetid://126955368721375" },
		["Cactus Pingu"] = { Rarity = "Uncommon", Income = 40, ImageId = "rbxassetid://92237676577047" },
		["L"] = { Rarity = "Uncommon", Income = 45, ImageId = "rbxassetid://110029667456217" },
		["W"] = { Rarity = "Uncommon", Income = 50, ImageId = "rbxassetid://93314796162303" },
		["Ballerina Cappuccina"] = { Rarity = "Uncommon", Income = 55, ImageId = "rbxassetid://75942794174519" },

		["Bombardini Gusini"] = { Rarity = "Rare", Income = 60, ImageId = "rbxassetid://109261438809226" },
		["Fryuro"] = { Rarity = "Rare", Income = 65, ImageId = "rbxassetid://125452082781010" },
		["Burguro"] = { Rarity = "Rare", Income = 75, ImageId = "rbxassetid://135166593136042" },
		["Cacto Hipopotamo"] = { Rarity = "Rare", Income = 85, ImageId = "rbxassetid://83550232331756" },
		["Garamararamararaman"] = { Rarity = "Rare", Income = 95, ImageId = "rbxassetid://102040553926828" },

		["Madung"] = { Rarity = "Epic", Income = 105, ImageId = "rbxassetid://115274192379897" },
		["Waterdino"] = { Rarity = "Epic", Income = 115, ImageId = "rbxassetid://123207669322850" },
		["Tuff Toucan"] = { Rarity = "Epic", Income = 125, ImageId = "rbxassetid://106779222875731" },
		["Torrtuginni Dragonfrutini"] = { Rarity = "Epic", Income = 135, ImageId = "rbxassetid://137266976468922" },
		["Tictac Sahur"] = { Rarity = "Epic", Income = 150, ImageId = "rbxassetid://109495334647445" },

		["SWAGGY BROS"] = { Rarity = "Legendary", Income = 165, ImageId = "rbxassetid://128010655463775" },
		["SWAG SODA"] = { Rarity = "Legendary", Income = 180, ImageId = "rbxassetid://103234531199510" },
		["Stoppo Luminino"] = { Rarity = "Legendary", Income = 195, ImageId = "rbxassetid://71929753328602" },
		["Spaghetti Tualetti"] = { Rarity = "Legendary", Income = 210, ImageId = "rbxassetid://89899737919662" },

		["Smurf Cat"] = { Rarity = "Mythical", Income = 220, ImageId = "rbxassetid://112098475013592" },
		["Skibidi Toilet"] = { Rarity = "Mythical", Income = 230, ImageId = "rbxassetid://128388433730418" },
		["Rinooccio Verdini"] = { Rarity = "Mythical", Income = 240, ImageId = "rbxassetid://96627317527386" },
		["Strawberry Elephant"] = { Rarity = "Mythical", Income = 250, ImageId = "rbxassetid://113176807276149" },
	},
	
	LuckyBlocks = LuckyBlockConfigurations.Blocks,
}


function ItemConfigurations.GetItemsByRarity(itemType: string, rarity: string): {string}
	if not ItemConfigurations.Items[itemType] then
		warn(`[ItemConfigurations] Failed to get Items by Rarity for {itemType} {rarity}; Item type not found in configuration!`)
		return {}
	end
	
	local foundItems = {}
	
	for itemName, data in pairs(ItemConfigurations.Items[itemType]) do
		if data.Rarity == rarity then
			table.insert(foundItems, itemName)
		end
	end
	return foundItems
end

function ItemConfigurations.GetItemData(itemName: string, itemType: string?)
	itemType = itemType or "Main"
	
	if not ItemConfigurations.Items[itemType] then
		warn(`[ItemConfigurations] Failed to get Item Data for {itemType} {itemName}; Item type not found in configuration!`)
		return nil
	end
	return ItemConfigurations.Items[itemType][itemName]
end

return ItemConfigurations