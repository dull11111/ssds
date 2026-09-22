--!strict
-- LOCATION: ServerScriptService/Modules/RewardHandler

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemManager = require(ServerScriptService.Modules.ItemManager)
local ItemGuidUtils = require(ServerScriptService.Modules.ItemGuidUtils)
local PlayerController = require(ServerScriptService.Controllers.PlayerController)

type SavedItemData = {
	Name: string,
	ItemType: string,
	Mutation: string,
	Rarity: string,
	Level: number,
	GUID: string,
}

local function getProfile(player: Player): any?
	local success, profile = pcall(function()
		return PlayerController:GetProfile(player)
	end)

	if success then
		return profile
	end

	return nil
end

local function itemAlreadySaved(inventory: {any}, guid: string): boolean
	for _, itemData in inventory do
		if itemData.GUID == guid then
			return true
		end
	end

	return false
end

local function saveItemToProfile(player: Player, itemName: string, itemType: string?, mutation: string, rarity: string, level: number, guid: string?): string?
	local profile = getProfile(player)

	if not profile or not profile.Data :: any then
		warn("[RewardHandler] Could not save item because profile is missing for:", player.Name)
		return
	end

	if typeof(profile.Data.Inventory) ~= "table" then
		profile.Data.Inventory = {}
	end

	if typeof(profile.Data.DiscoveredItems) ~= "table" then
		profile.Data.DiscoveredItems = {}
	end
	
	itemType = itemType or "Main"
	local savedGuid = if typeof(guid) == "string" and guid ~= "" then guid else ItemGuidUtils.generateGuid(profile.Data.Inventory)

	if not itemAlreadySaved(profile.Data.Inventory, savedGuid) then
		local savedItem: SavedItemData = {
			Name = itemName,
			ItemType = itemType,
			Mutation = mutation,
			Rarity = rarity,
			Level = level,
			GUID = savedGuid,
		}

		table.insert(profile.Data.Inventory, savedItem)
	end

	local discoveryKey = mutation .. "_" .. itemName
	profile.Data.DiscoveredItems[discoveryKey] = true

	print("[RewardHandler] Saved item to profile:", player.Name, itemName, itemType, mutation, rarity, level)
	return savedGuid
end

local RewardHandler = {}
type RewardHandler = typeof(RewardHandler)

function RewardHandler.GiveReward(self: RewardHandler, player: Player, itemName: string, itemType: string, rarity: string?)
	if typeof(itemName) ~= "string" or itemName == "" then
		return
	end

	local safeRarity = if typeof(rarity) == "string" and rarity ~= "" then rarity else "Common"
	local defaultMutation = "Normal"
	local defaultLevel = 1
	local isTemporary = false
	local profile = getProfile(player)
	local guid = ItemGuidUtils.generateGuid((profile and profile.Data.Inventory) or {})

	print("[RewardHandler] Giving reward:", player.Name, itemName, safeRarity)

	local savedGuid = saveItemToProfile(player, itemName, itemType, defaultMutation, safeRarity, defaultLevel, guid)

	local success, err = pcall(function()
		ItemManager.GiveItemToPlayer(player, savedGuid or guid, itemName, itemType, defaultMutation, safeRarity, defaultLevel, isTemporary)
	end)

	if not success then
		warn("[RewardHandler] ItemManager.GiveItemToPlayer failed:", err)
	end
end

function RewardHandler.GiveLuckyBlock(self: RewardHandler, player: Player, luckyBlockName: string)
	local LuckyBlocksConfigurations = require(ReplicatedStorage.Modules.LuckyBlockConfigurations)
	local luckyBlockData = LuckyBlocksConfigurations.Blocks[luckyBlockName]
	self:GiveReward(player, luckyBlockName, "LuckyBlocks", if luckyBlockData then luckyBlockData.Rarity else nil)
end

return RewardHandler