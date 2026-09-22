--!strict
-- LOCATION: ServerScriptService/InventoryController
--
-- PURPOSE:
-- Fixes item Tools not appearing after rejoining when using Satchel.
--
-- WHY THIS IS NEEDED:
-- Your PlayerController loads inventory inside CharacterAdded.
-- Sometimes the character already exists before the profile is ready, so CharacterAdded has already fired.
-- That means loadInventory() can be skipped on first join.
--
-- This script waits for the profile, waits for the character/backpack, then loads saved Inventory tools
-- only if they are missing.
--
-- IMPORTANT:
-- Delete/disable older ToolPersistenceController scripts before using this.
-- This script does NOT overwrite profile.Data.Inventory with empty data.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Controllers = ServerScriptService:WaitForChild("Controllers")
local ServerModules = ServerScriptService:WaitForChild("Modules")

local PlayerController = require(Controllers:WaitForChild("PlayerController"))
local ItemManager = require(ServerModules:WaitForChild("ItemManager"))
local ItemGuidUtils = require(ServerModules:WaitForChild("ItemGuidUtils"))

type SavedItemData = {
	Name: string,
	ItemType: string,
	Mutation: string?,
	Rarity: string?,
	Level: number?,
	GUID: string,
}

local PROFILE_WAIT_TIMEOUT = 30
local BACKPACK_WAIT_TIMEOUT = 15
local LOAD_DELAY_AFTER_CHARACTER = 1.25

local loadedOnce: {[Player]: boolean} = {}

local function getProfile(player: Player): any?
	local success, profile = pcall(function()
		return PlayerController:GetProfile(player)
	end)

	if success then
		return profile
	end

	return nil
end

local function waitForProfile(player: Player): any?
	local started = os.clock()

	while player.Parent == Players and os.clock() - started < PROFILE_WAIT_TIMEOUT do
		local profile = getProfile(player)
		if profile and profile.Data then
			return profile
		end

		task.wait(0.1)
	end

	return nil
end

local function toolMatchesSavedItem(tool: Tool, savedItem: SavedItemData): boolean
	local toolGuid = tool:GetAttribute("GUID")
	return typeof(toolGuid) == "string" and toolGuid == savedItem.GUID
end

local function playerAlreadyHasItem(player: Player, savedItem: SavedItemData): boolean
	local containers = {
		player:FindFirstChildOfClass("Backpack"),
		player:FindFirstChild("StarterGear"),
		player.Character,
	}

	for _, container in ipairs(containers) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and toolMatchesSavedItem(child, savedItem) then
					return true
				end
			end
		end
	end

	return false
end

local function normalizeSavedItem(itemData: any, existingItems: {any}): SavedItemData?
	if typeof(itemData) ~= "table" then
		return nil
	end

	if typeof(itemData.Name) ~= "string" or itemData.Name == "" then
		return nil
	end

	return {
		Name = itemData.Name,
		ItemType = itemData.ItemType,
		Mutation = if typeof(itemData.Mutation) == "string" and itemData.Mutation ~= "" then itemData.Mutation else "Normal",
		GUID = if typeof(itemData.GUID) == "string" and itemData.GUID ~= "" then itemData.GUID else ItemGuidUtils.generateGuid(existingItems),
		Rarity = if typeof(itemData.Rarity) == "string" and itemData.Rarity ~= "" then itemData.Rarity else "Common",
		Level = if typeof(itemData.Level) == "number" and itemData.Level > 0 then itemData.Level else 1,
	}
end

local function loadMissingInventoryTools(player: Player, reason: string)
	if player.Parent ~= Players then
		return
	end

	local profile = waitForProfile(player)
	if not profile or not profile.Data then
		warn("[InventoryLoadFixController] Profile not ready for", player.Name)
		return
	end

	local savedInventory = profile.Data.Inventory
	if typeof(savedInventory) ~= "table" then
		warn("[InventoryLoadFixController] profile.Data.Inventory is not a table for", player.Name)
		return
	end

	local backpack = player:WaitForChild("Backpack", BACKPACK_WAIT_TIMEOUT)
	if not backpack then
		warn("[InventoryLoadFixController] Backpack not ready for", player.Name)
		return
	end

	player:WaitForChild("StarterGear", BACKPACK_WAIT_TIMEOUT)

	local loadedCount = 0
	local skippedCount = 0

	for _, rawItemData in ipairs(savedInventory) do
		local itemData = normalizeSavedItem(rawItemData, savedInventory)

		if itemData then
			if playerAlreadyHasItem(player, itemData) then
				skippedCount += 1
			else
				local success, err = pcall(function()
					ItemManager.GiveItemToPlayer(
						player,
						itemData.GUID,
						itemData.Name,
						itemData.ItemType,
						itemData.Mutation or "Normal",
						itemData.Rarity or "Common",
						itemData.Level,
						false
					)
				end)

				if success then
					loadedCount += 1
				else
					warn("[InventoryLoadFixController] Failed to load item:", itemData.Name, "for", player.Name, err)
				end
			end
		end
	end

	if #savedInventory > 0 then
		print(
			"[InventoryLoadFixController] Inventory checked for",
			player.Name,
			"Reason:",
			reason,
			"Saved:",
			#savedInventory,
			"Loaded missing:",
			loadedCount,
			"Already had:",
			skippedCount
		)
	end
end

local function setupPlayer(player: Player)
	loadedOnce[player] = false

	task.spawn(function()
		local profile = waitForProfile(player)
		if not profile then
			warn("[InventoryLoadFixController] Could not get profile for", player.Name)
			return
		end

		local character = player.Character or player.CharacterAdded:Wait()
		if not character then
			return
		end

		task.wait(LOAD_DELAY_AFTER_CHARACTER)

		if player.Parent == Players then
			loadedOnce[player] = true
			loadMissingInventoryTools(player, "InitialJoin")
		end
	end)

	player.CharacterAdded:Connect(function()
		task.delay(LOAD_DELAY_AFTER_CHARACTER, function()
			if player.Parent == Players then
				loadMissingInventoryTools(player, "CharacterAdded")
			end
		end)
	end)
end

local function cleanupPlayer(player: Player)
	loadedOnce[player] = nil
end

Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(cleanupPlayer)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayer, player)
end