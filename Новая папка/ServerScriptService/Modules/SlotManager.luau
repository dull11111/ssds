--!strict
-- LOCATION: ServerScriptService/Modules/SlotManager

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local SlotManager = {}

-- [ MODULES ]
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local LuckyBlockConfigurations = require(ReplicatedStorage.Modules.LuckyBlockConfigurations)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local ItemGuidUtils = require(ServerScriptService.Modules.ItemGuidUtils)
local PlayerController 
local ItemManager 

-- [ ASSETS ]
local Templates = ReplicatedStorage:WaitForChild("Templates")
local UpgradeGUI_Template = Templates:WaitForChild("UpgradeGUI")
local CollectGUI_Template = Templates:WaitForChild("CollectGUI")
local MoneyTemplate = Templates:WaitForChild("Money")
local Events = ReplicatedStorage:WaitForChild("Events")
local ItemsFolder = ReplicatedStorage.Items
local GlobalSounds = game.Workspace.Sounds

-- [ CONSTANTS ]
local UPGRADE_COST_MULTIPLIER = 1.5
local DEBOUNCE_TIME = 0.5 
local INTERACTION_COOLDOWN = 0.8 

-- [ STATE ]
local lastUpgradeTime = {} 

-- [ HELPERS ]
local function getEventsFolder(): Folder
	local events = ReplicatedStorage:FindFirstChild("Events")

	if not events then
		events = Instance.new("Folder")
		events.Name = "Events"
		events.Parent = ReplicatedStorage
	end

	return events :: Folder
end

local hatchEvent = Instance.new("RemoteEvent", getEventsFolder())
hatchEvent.Name = "HatchEvent"

local function getUpgradeCost(baseIncome: number, level: number): number
	return math.floor(baseIncome * 20 * (UPGRADE_COST_MULTIPLIER ^ (level - 1)))
end

local function doesItemGiveIncome(itemType: string?): boolean
	return if itemType == "Main" or itemType == nil then true
		else false
end

local function normalizeSlotItem(itemData: any, existingItems: {any}?): any?
	if typeof(itemData) ~= "table" then
		return nil
	end

	if typeof(itemData.Name) ~= "string" or itemData.Name == "" then
		return nil
	end

	itemData.ItemType = if typeof(itemData.ItemType) == "string" and itemData.ItemType ~= "" then itemData.ItemType else "Main"
	itemData.Mutation = if typeof(itemData.Mutation) == "string" and itemData.Mutation ~= "" then itemData.Mutation else "Normal"
	itemData.Rarity = if typeof(itemData.Rarity) == "string" and itemData.Rarity ~= "" then itemData.Rarity else "Common"
	itemData.Level = if typeof(itemData.Level) == "number" and itemData.Level > 0 then itemData.Level else 1

	return itemData
end

local function isItemUpgradeable(itemType: string?): boolean
	return if itemType == "Main" or itemType == nil then true
		else false
end

local function updateSlotVisuals(slotModel: Model, itemData: any?, level: number, stored: number, rebirths: number, isVip: boolean?, playConfetti: boolean?)
	-- 1. Collect GUI
	local collectPart = slotModel:FindFirstChild("CollectTouch") :: BasePart
	if collectPart then
		local gui = collectPart:FindFirstChild("CollectGUI") :: SurfaceGui
		if not gui then
			gui = CollectGUI_Template:Clone(); gui.Name = "CollectGUI"; gui.Parent = collectPart
		end

		local frame = gui:FindFirstChild("CollectFrame")
		local label = frame and frame:FindFirstChild("Price") :: TextLabel

		if itemData then
			gui.Enabled = true
			if label then
				label.Text = "$" .. NumberFormatter.Format(stored)
				label.Visible = doesItemGiveIncome(itemData.ItemType)
			end
		else
			gui.Enabled = false
		end
	end

	-- 2. Upgrade GUI
	local upgradePart = slotModel:FindFirstChild("UpgradePart") :: BasePart
	if upgradePart then
		local gui = upgradePart:FindFirstChild("UpgradeGUI") :: SurfaceGui
		if not gui then
			gui = UpgradeGUI_Template:Clone(); gui.Name = "UpgradeGUI"; gui.Parent = upgradePart
			gui:SetAttribute("SlotName", slotModel.Name); gui:SetAttribute("FloorName", slotModel.Parent and slotModel.Parent.Parent.Name)
		end

		local button = gui:FindFirstChild("UpgradeButton") :: TextButton
		if itemData and button and doesItemGiveIncome(itemData.ItemType) then
			gui.Enabled = true
			local levelsLabel = button:FindFirstChild("Levels") :: TextLabel
			local priceLabel = button:FindFirstChild("Price") :: TextLabel
			local itemConf = ItemConfigurations.GetItemData(itemData.Name, itemData.ItemType)
			local baseIncome = itemConf and itemConf.Income or 0
			local cost = getUpgradeCost(baseIncome, level)
			if levelsLabel then levelsLabel.Text = "Level " .. tostring(level) .. " > Level " .. tostring(level + 1) end
			if priceLabel then priceLabel.Text = "$" .. NumberFormatter.Format(cost) end
		else
			gui.Enabled = false
		end
	end

	-- 3. Item Model & Prompt
	local spawnPart = slotModel:FindFirstChild("Spawn") :: BasePart
	if spawnPart then
		local existingItem = spawnPart:FindFirstChild("VisualItem")
		local currentName = existingItem and existingItem:GetAttribute("OriginalName")
		local currentMutation = existingItem and existingItem:GetAttribute("Mutation")
		local currentType = existingItem and (existingItem:GetAttribute("ItemType") or "Main")
		
		if itemData then
			if not existingItem or currentType ~= (itemData.ItemType or "Main") or currentName ~= itemData.Name or currentMutation ~= itemData.Mutation then 
				if existingItem then existingItem:Destroy() end
				ItemManager.SpawnVisualItem(spawnPart, itemData.Name, itemData.ItemType, itemData.Mutation, itemData.Rarity, level, rebirths, isVip, playConfetti)
			else
				ItemManager.UpdateVisualItem(existingItem, level, rebirths, isVip)
			end
		else
			if existingItem then existingItem:Destroy() end
		end

		local prompt = spawnPart:FindFirstChild("ProximityPrompt") :: ProximityPrompt?
		if prompt then
			prompt.ActionText = itemData and "Pick Up / Swap" or "Place Item"
			prompt.Enabled = not slotModel:GetAttribute("IsHatching")
		end
		
		-- Currently only for lucky blocks
		local prompt2 = spawnPart:FindFirstChild("ProximityPromptSecondary") :: ProximityPrompt?
		if prompt2 then
			prompt2.ActionText = "Open"
			prompt2.Enabled = if itemData and itemData.ItemType == "LuckyBlocks" then true else false
		end
	else
		if slotModel.Parent then 
			warn("[SlotManager] Visual Update Failed: 'Spawn' part missing in " .. slotModel.Name)
		end
	end
end

local function getItemTemplate(itemName: string, itemType: string?, mutation: string?): Model?
	local typeFolder = if itemType then ItemsFolder:FindFirstChild(itemType) or ItemsFolder.Main else ItemsFolder.Main
	local mutationFolder = mutation and typeFolder:FindFirstChild(mutation) :: Folder? or typeFolder:FindFirstChild("Normal") or ItemsFolder.Main.Normal
	
	return mutationFolder:FindFirstChild(itemName) :: Model?
end

local function getRandomVisualItem(): Model?
	local allItems = {}
	for name, _ in ItemConfigurations.Items.Main do
		table.insert(allItems, name)
	end

	if #allItems == 0 then return nil end
	local randomName = allItems[math.random(1, #allItems)]
	return getItemTemplate(randomName, "Main", "Normal") 
end

local function playSuspenseSequence(position: CFrame, blockConfig: any)
	local possibleRewards = blockConfig.Rewards

	local spinSoundTemplate = GlobalSounds:FindFirstChild("Spin")
	local TOTAL_SPINS = 19 -- Matches friend's script

	-- Helper to calculate delay curve
	local function getDelay(index: number)
		return 0.05 + 0.08 * ((index - 1) / 18)
	end

	for i = 1, TOTAL_SPINS do
		local randomTemplate = getRandomVisualItem()

		if randomTemplate then
			local tempModel = randomTemplate:Clone()
			tempModel.Name = "Spin_" .. i

			local prim = tempModel.PrimaryPart or tempModel:FindFirstChild("Handle") or tempModel:FindFirstChildWhichIsA("BasePart")
			if not prim then 
				prim = Instance.new("Part"); prim.CFrame = position; prim.Parent = tempModel 
			end
			tempModel.PrimaryPart = prim

			for _, child in ipairs(tempModel:GetDescendants()) do
				if child:IsA("BasePart") then
					child.Anchored = true
					child.CanCollide = false
					child.CastShadow = false
				elseif child:IsA("GuiObject") or child:IsA("BillboardGui") or child:IsA("SurfaceGui") then
					child:Destroy() -- No UI during spin
				end
			end

			local targetScale = tempModel:GetScale()
			tempModel:ScaleTo(0.01)

			local scaleVal = Instance.new("NumberValue")
			scaleVal.Value = 0.01
			scaleVal.Parent = tempModel
			scaleVal.Changed:Connect(function(v) if tempModel.Parent then tempModel:ScaleTo(v) end end)

			local delayTime = getDelay(i)

			local hl = Instance.new("Highlight")
			hl.FillColor = Color3.new(0,0,0)
			hl.OutlineColor = Color3.new(1,1,1)
			hl.FillTransparency = 0
			hl.OutlineTransparency = 1
			hl.Parent = tempModel

			tempModel:PivotTo(position)
			tempModel.Parent = Workspace
			TweenService:Create(scaleVal, TweenInfo.new(delayTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Value = targetScale}):Play()

			if spinSoundTemplate then
				local s = spinSoundTemplate:Clone()
				s.Parent = prim
				s.PlaybackSpeed = 0.8 + (i * 0.02) -- Rise pitch
				s:Play()
				Debris:AddItem(s, 1)
			end

			task.wait(delayTime)
			tempModel:Destroy()
		else
			task.wait(getDelay(i))
		end
	end
end

-- [ ACTIONS ]

function SlotManager.RefreshAllSlots(player: Player)
	local profile = PlayerController:GetProfile(player)
	if not profile then return end

	if not profile.Data.Plots then profile.Data.Plots = {} end

	local rebirths = profile.Data.Rebirths or 0
	local isVip = PlayerController:IsVIP(player)
	local plot = Workspace:FindFirstChild("Plot_" .. player.Name)
	if not plot then return end

	for floorName, floorSlots in pairs(profile.Data.Plots) do
		local floorModel = plot:FindFirstChild(floorName)
		local slotsFolder = floorModel and floorModel:FindFirstChild("Slots")
		if not slotsFolder then
			continue
		end

		for slotName, slotData in pairs(floorSlots) do
			local slotModel = slotsFolder:FindFirstChild(slotName) :: Model?
			if not slotModel then
				continue
			end
			
			if type(slotData.Stored) ~= "number" then slotData.Stored = 0 end
			if slotData.Item then
				normalizeSlotItem(slotData.Item, profile.Data.Inventory)
			end
			local data = slotData.Item and slotData or {Item=nil, Level=1, Stored=0}
			updateSlotVisuals(slotModel, data.Item, data.Level, data.Stored, rebirths, isVip)
		end
	end
end

function SlotManager.HandleInteraction(player: Player, floorName: string, slotName: string, slotModel: Model)
	if slotModel:GetAttribute("IsHatching") then
		return
	end
	
	local profile = PlayerController:GetProfile(player)
	if not profile then warn("[SlotManager] No profile for " .. player.Name); return end

	if not profile.Data.Plots then profile.Data.Plots = {} end
	if not profile.Data.Plots[floorName] then profile.Data.Plots[floorName] = {} end
	local floorData = profile.Data.Plots[floorName]

	local currentSlotData = floorData[slotName]
	local isOccupied = (currentSlotData and currentSlotData.Item ~= nil)
	if currentSlotData and currentSlotData.Item then
		normalizeSlotItem(currentSlotData.Item, profile.Data.Inventory)
	end

	local character = player.Character
	local heldTool = character and character:FindFirstChildWhichIsA("Tool")
	local heldItemName = heldTool and heldTool:GetAttribute("OriginalName")

	if isOccupied then
		-- Collect Money
		if currentSlotData.Stored > 0 then
			PlayerController:AddMoney(player, math.floor(currentSlotData.Stored))
			currentSlotData.Stored = 0
		end

		-- Return Old Item
		local oldItemNew = {
			GUID = ItemGuidUtils.generateGuid(profile.Data.Inventory),
			Name = currentSlotData.Item.Name,
			ItemType = currentSlotData.Item.ItemType,
			Mutation = currentSlotData.Item.Mutation,
			Rarity = currentSlotData.Item.Rarity,
			Level = currentSlotData.Level,
		}
		
		if profile.Data and profile.Data.Inventory then
			local exists = false
			for _, item in profile.Data.Inventory do
				if item.GUID == oldItemNew.GUID then
					exists = true
					break
				end
			end
			
			if not exists then
				table.insert(profile.Data.Inventory, oldItemNew)
			end
		end
		
		ItemManager.GiveItemToPlayer(
			player, 
			oldItemNew.GUID,
			oldItemNew.Name,
			oldItemNew.ItemType,
			oldItemNew.Mutation, 
			oldItemNew.Rarity,
			oldItemNew.Level
		)

		if heldTool and heldItemName then
			-- SWAP
			currentSlotData.Item = {
				Name = heldItemName,
				ItemType = heldTool:GetAttribute("ItemType"),
				Mutation = heldTool:GetAttribute("Mutation"),
				Rarity = heldTool:GetAttribute("Rarity"),
			}
			currentSlotData.Level = heldTool:GetAttribute("Level") or 1
			heldTool:Destroy()
		else
			-- PICK UP (Clear)
			floorData[slotName] = { Item = nil, Level = 1, Stored = 0 }
		end

	else
		-- PLACE
		if heldTool then
			if heldItemName then
				local heldItemGuid = heldTool:GetAttribute("GUID") :: string?
				floorData[slotName] = {
					Item = {
						Name = heldItemName,
						ItemType = heldTool:GetAttribute("ItemType"),
						Mutation = heldTool:GetAttribute("Mutation"),
						Rarity = heldTool:GetAttribute("Rarity"),
					},
					Level = heldTool:GetAttribute("Level"),
					Stored = 0
				}
				
				if heldItemGuid and profile.Data and profile.Data.Inventory then
					for i, item in profile.Data.Inventory do
						if item.GUID == heldItemGuid then
							table.remove(profile.Data.Inventory, i)
							break
						end
					end
				end
				
				heldTool:Destroy()
			else
				warn("[SlotManager] Tool held has no 'OriginalName' Attribute! Cannot place.")
				local notif = Events:FindFirstChild("ShowNotification")
				if notif then notif:FireClient(player, "Invalid Item! (No Data)", "Error") end
				return
			end
		else
			local notif = Events:FindFirstChild("ShowNotification")
			if notif then notif:FireClient(player, "Equip an item to place it!", "Error") end
			return
		end
	end

	local isVip = PlayerController:IsVIP(player)
	local newData = floorData[slotName]
	updateSlotVisuals(slotModel, newData and newData.Item, newData and newData.Level or 1, newData and newData.Stored or 0, profile.Data.Rebirths or 0, isVip)
end

local function getRandomMutation(): string
	local mutationWeights = {
		Neon = 2,
		Ruby = 4,
		Diamond = 10,
		Golden = 25,
		Normal = 100 - 25 - 10 - 4 - 2
	}
	
	local totalWeight = 0
	for _, weight in mutationWeights do
		totalWeight += weight
	end
	
	local roll = math.random(0, totalWeight)
	local currentWeight = 0
	local rolledMutation = "Normal"
	for mutation, weight in mutationWeights do
		if roll <= currentWeight + weight then
			rolledMutation = mutation
			break
		end
		currentWeight += weight
	end
	
	return rolledMutation
end

function SlotManager.HandleSecondaryInteraction(player: Player, floorName: string, slotName: string, slotModel: Model)
	local profile = PlayerController:GetProfile(player)
	if not profile then warn("[SlotManager] No profile for " .. player.Name); return end

	if not profile.Data.Plots then profile.Data.Plots = {} end
	if not profile.Data.Plots[floorName] then profile.Data.Plots[floorName] = {} end
	local floorData = profile.Data.Plots[floorName]

	local currentSlotData = floorData[slotName]
	local isOccupied = (currentSlotData and currentSlotData.Item ~= nil)

	if not isOccupied then
		return
	end

	if currentSlotData.Item.ItemType == "LuckyBlocks" then
		local blockConfig = LuckyBlockConfigurations.Blocks[currentSlotData.Item.Name]
		local randomDrop = LuckyBlockConfigurations.GetRandomDrop(currentSlotData.Item.Name)
		if randomDrop and blockConfig then
			if slotModel:GetAttribute("IsHatching") then
				return
			end

			slotModel:SetAttribute("IsHatching", true)

			local spawnPart = slotModel:FindFirstChild("Spawn")
			local prompt = if spawnPart then spawnPart:FindFirstChild("ProximityPrompt") :: ProximityPrompt? else nil
			local secondaryPrompt = if spawnPart then spawnPart:FindFirstChild("ProximityPromptSecondary") :: ProximityPrompt? else nil

			if prompt then
				prompt.Enabled = false
			end

			if secondaryPrompt then
				secondaryPrompt.Enabled = false
			end

			local randomMutation = getRandomMutation()
			local randomDropConfig = ItemConfigurations.GetItemData(randomDrop)
			local currentModelInSlot = slotModel.Spawn:FindFirstChildOfClass("Model")

			if currentModelInSlot then
				local cframe = currentModelInSlot.PrimaryPart.CFrame
				currentModelInSlot:Destroy()
				playSuspenseSequence(cframe, blockConfig)
			end

			floorData[slotName] = {
				Item = {
					Name = randomDrop,
					ItemType = "Main",
					Mutation = randomMutation,
					Rarity = randomDropConfig.Rarity,
				},
				Level = 1,
				Stored = 0
			}

			-- =========================================================
			-- [BUG FIX]: Manually register the hatched item in the Index
			-- =========================================================
			local discoveryKey = randomMutation .. "_" .. randomDrop
			if not profile.Data.DiscoveredItems[discoveryKey] then
				profile.Data.DiscoveredItems[discoveryKey] = true

				-- Tell the client to update their Index GUI
				local refreshEvent = Events:FindFirstChild("RefreshIndex")
				if refreshEvent then
					refreshEvent:FireClient(player)
				end
			end
			-- =========================================================

			local isVip = PlayerController:IsVIP(player)
			local newData = floorData[slotName]
			slotModel:SetAttribute("IsHatching", nil)
			updateSlotVisuals(slotModel, newData and newData.Item, newData and newData.Level or 1, newData and newData.Stored or 0, profile.Data.Rebirths or 0, isVip, true)
		end
	end
end

function SlotManager.UpgradeItem(player: Player, floorName: string, slotName: string)
	local debounceKey = player.Name .. "_" .. floorName .. "_" .. slotName
	local now = tick()
	if lastUpgradeTime[debounceKey] and (now - lastUpgradeTime[debounceKey] < DEBOUNCE_TIME) then
		return 
	end
	lastUpgradeTime[debounceKey] = now

	local profile = PlayerController:GetProfile(player)
	if not profile then return end
	if not profile.Data.Plots then profile.Data.Plots = {} end
	local floorData = profile.Data.Plots[floorName]
	if not floorData then return end
	local slotData = floorData[slotName]
	if not slotData or not slotData.Item then return end

	local itemConf = ItemConfigurations.GetItemData(slotData.Item.Name, slotData.Item.ItemType)
	if not itemConf then
		warn(`[SlotManager] Cannot upgrade item {slotData.Item.Name}; item not configured!`)
		return
	end
	
	if slotData.Item.ItemType ~= "Main" and slotData.Item.ItemType ~= nil then
		warn(`[SlotManager] Cannot upgrade item {slotData.Item.Name}; items of type {slotData.Item.ItemType} are not upgradeable!`)
		return
	end
	
	local baseIncome = itemConf and itemConf.Income or 10
	local cost = getUpgradeCost(baseIncome, slotData.Level)

	if PlayerController:DeductMoney(player, cost) then
		slotData.Level += 1
		local plot = Workspace:FindFirstChild("Plot_" .. player.Name)
		if plot then
			local floor = plot:FindFirstChild(floorName)
			local slots = floor and floor:FindFirstChild("Slots")
			local slotModel = slots and slots:FindFirstChild(slotName)
			local isVip = PlayerController:IsVIP(player)
			if slotModel then
				updateSlotVisuals(slotModel, slotData.Item, slotData.Level, slotData.Stored, profile.Data.Rebirths or 0, isVip)
			end
		end

		local notif = Events:FindFirstChild("ShowNotification")
		if notif then 
			notif:FireClient(player, "Slot Upgraded!", "Success") 
		end
	else
		local notif = Events:FindFirstChild("ShowNotification")
		if notif then 
			notif:FireClient(player, "Not enough money!", "Error") 
		end
	end
end

function SlotManager.CollectMoney(player: Player, floorName: string, slotName: string, slotModel: Model)
	local profile = PlayerController:GetProfile(player)
	if not profile then return end
	if not profile.Data.Plots then profile.Data.Plots = {} end
	local slotData = profile.Data.Plots[floorName] and profile.Data.Plots[floorName][slotName]
	if not slotData then return end
	if type(slotData.Stored) ~= "number" then slotData.Stored = 0 end
	if slotData.Stored <= 0 then return end

	local amount = math.floor(slotData.Stored)
	slotData.Stored = 0

	PlayerController:AddMoney(player, amount)

	local collectPart = slotModel:FindFirstChild("CollectTouch")
	if collectPart then
		local gui = collectPart:FindFirstChild("CollectGUI")
		local frame = gui and gui:FindFirstChild("CollectFrame")
		local label = frame and frame:FindFirstChild("Price") :: TextLabel
		if label then
			label.Text = "$0"
		end
	end

	local popupEvent = Events:FindFirstChild("ShowCashPopUp")
	if popupEvent then
		popupEvent:FireClient(player, amount)
	end

	if collectPart then
		local moneyEffect = MoneyTemplate:Clone()
		moneyEffect.Parent = collectPart
		for _, child in ipairs(moneyEffect:GetChildren()) do
			if child:IsA("ParticleEmitter") then
				child:Emit(child:GetAttribute("EmitCount") or 10)
			end
		end
		Debris:AddItem(moneyEffect, 3)
	end
end

function SlotManager.RefreshSlot(player: Player, floorName: string, slotName: string)
	local profile = PlayerController:GetProfile(player)
	if not profile then return end

	if not profile.Data.Plots then profile.Data.Plots = {} end
	local slotData = profile.Data.Plots[floorName] and profile.Data.Plots[floorName][slotName]

	local plot = Workspace:FindFirstChild("Plot_" .. player.Name)
	if plot then
		local isVip = PlayerController:IsVIP(player)
		local floor = plot:FindFirstChild(floorName)
		local slots = floor and floor:FindFirstChild("Slots")
		local slotModel = slots and slots:FindFirstChild(slotName)
		if slotModel then
			if slotData and slotData.Item then
				normalizeSlotItem(slotData.Item, profile.Data.Inventory)
			end
			if slotData then
				updateSlotVisuals(slotModel, slotData.Item, slotData.Level, slotData.Stored, profile.Data.Rebirths or 0, isVip)
			else
				updateSlotVisuals(slotModel, nil, 1, 0, profile.Data.Rebirths or 0, isVip)
			end
		end
	end
end

-- [ SETUP LOGIC ]

local function setupSingleSlot(player: Player, floorName: string, slotName: string, slotModel: Model)
	local spawnPart = slotModel:WaitForChild("Spawn", 5)
	local upgradePart = slotModel:WaitForChild("UpgradePart", 5)
	local collectPart = slotModel:WaitForChild("CollectTouch", 5)

	if not spawnPart or not upgradePart or not collectPart then 
		warn("[SlotManager] Slot Setup Failed for: " .. slotName .. " (Missing Parts)")
		return 
	end

	if not spawnPart:FindFirstChild("ProximityPrompt") then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Place Item"
		prompt.ObjectText = "Slot"
		prompt.RequiresLineOfSight = false
		prompt.HoldDuration = 0 
		prompt.MaxActivationDistance = 8
		prompt.Style = Enum.ProximityPromptStyle.Custom
		prompt.Parent = spawnPart

		prompt.Enabled = slotModel:GetAttribute("IsUnlocked") == true
		
		local secondaryPrompt = Instance.new("ProximityPrompt")
		secondaryPrompt.Name = "ProximityPromptSecondary"
		secondaryPrompt.KeyboardKeyCode = Enum.KeyCode.Q
		secondaryPrompt.GamepadKeyCode = Enum.KeyCode.ButtonY
		secondaryPrompt.ActionText = "Open"
		secondaryPrompt.UIOffset = Vector2.new(0, 2)
		secondaryPrompt.RequiresLineOfSight = false
		secondaryPrompt.HoldDuration = 0
		secondaryPrompt.MaxActivationDistance = 8
		secondaryPrompt.Style = Enum.ProximityPromptStyle.Custom
		secondaryPrompt.Parent = spawnPart
		
		secondaryPrompt.Enabled = slotModel:GetAttribute("IsUnlocked") == true

		slotModel:GetAttributeChangedSignal("IsUnlocked"):Connect(function()
			prompt.Enabled = slotModel:GetAttribute("IsUnlocked") == true
			secondaryPrompt.Enabled = slotModel:GetAttribute("IsUnlocked") == true
		end)

		local lastTriggerTime = 0

		prompt.Triggered:Connect(function(triggerPlayer)
			if triggerPlayer ~= player then
				return
			end
			
			local now = tick()
			if now - lastTriggerTime < INTERACTION_COOLDOWN then return end
			lastTriggerTime = now

			SlotManager.HandleInteraction(player, floorName, slotName, slotModel)
		end)
		
		secondaryPrompt.Triggered:Connect(function(triggerPlayer)
			if triggerPlayer ~= player then
				return
			end
			
			local now = tick()
			if now - lastTriggerTime < INTERACTION_COOLDOWN then return end
			lastTriggerTime = now
			
			SlotManager.HandleSecondaryInteraction(player, floorName, slotName, slotModel)
		end)
	end

	if not collectPart:GetAttribute("Connected") then
		collectPart:SetAttribute("Connected", true)
		local db = false
		collectPart.Touched:Connect(function(hit)
			if db then return end
			local char = hit.Parent
			local hum = char and char:FindFirstChild("Humanoid")
			if hum and Players:GetPlayerFromCharacter(char) == player then
				db = true
				SlotManager.CollectMoney(player, floorName, slotName, slotModel)
				task.wait(0.5)
				db = false
			end
		end)
	end

	task.spawn(function()
		local profile = PlayerController:GetProfile(player)
		local retries = 0
		while not profile and retries < 20 do
			task.wait(0.5)
			profile = PlayerController:GetProfile(player)
			retries += 1
		end

		if profile then
			local isVip = PlayerController:IsVIP(player)
			if not profile.Data.Plots then profile.Data.Plots = {} end
			if not profile.Data.Plots[floorName] then 
				profile.Data.Plots[floorName] = {} 
			end
			local data = profile.Data.Plots[floorName][slotName]
			if data and data.Item then
				normalizeSlotItem(data.Item, profile.Data.Inventory)
				if type(data.Stored) ~= "number" then data.Stored = 0 end
				updateSlotVisuals(slotModel, data.Item, data.Level, data.Stored, profile.Data.Rebirths or 0, isVip)
			else
				updateSlotVisuals(slotModel, nil, 1, 0, profile.Data.Rebirths or 0, isVip)
			end
		end
	end)
end

local function monitorFloor(player: Player, floorModel: Model)
	local slotsFolder = floorModel:WaitForChild("Slots", 5)
	if not slotsFolder then return end

	for _, slot in ipairs(slotsFolder:GetChildren()) do
		setupSingleSlot(player, floorModel.Name, slot.Name, slot)
	end
	slotsFolder.ChildAdded:Connect(function(child)
		setupSingleSlot(player, floorModel.Name, child.Name, child)
	end)
end

function SlotManager.MonitorPlot(player: Player, plot: Model)
	for _, child in ipairs(plot:GetChildren()) do
		if child.Name:match("Floor%d+") then
			monitorFloor(player, child)
		end
	end
	plot.ChildAdded:Connect(function(child)
		if child.Name:match("Floor%d+") then
			monitorFloor(player, child)
		end
	end)
end

-- [ INITIALIZATION ]

function SlotManager:Init(controllers)
	PlayerController = controllers.PlayerController
	local Modules = ServerScriptService:WaitForChild("Modules")
	ItemManager = require(Modules:WaitForChild("ItemManager"))

	local upgradeEvent = Events:FindFirstChild("RequestSlotUpgrade")
	if not upgradeEvent then
		upgradeEvent = Instance.new("RemoteEvent")
		upgradeEvent.Name = "RequestSlotUpgrade"
		upgradeEvent.Parent = Events
	end

	if not SlotManager._connected then
		SlotManager._connected = true
		upgradeEvent.OnServerEvent:Connect(function(player, floorName, slotName)
			SlotManager.UpgradeItem(player, floorName, slotName)
		end)
	end

	local popupEvent = Events:FindFirstChild("ShowCashPopUp")
	if not popupEvent then
		popupEvent = Instance.new("RemoteEvent")
		popupEvent.Name = "ShowCashPopUp"
		popupEvent.Parent = Events
	end
end

-- [ START ]

local function setupPlayerMonitoring(player: Player)
	local plotName = "Plot_" .. player.Name
	local existingPlot = Workspace:FindFirstChild(plotName)
	if existingPlot then
		SlotManager.MonitorPlot(player, existingPlot)
	end

	Workspace.ChildAdded:Connect(function(child)
		if child.Name == plotName then
			SlotManager.MonitorPlot(player, child)
		end
	end)
end

function SlotManager:Start()
	Players.PlayerAdded:Connect(setupPlayerMonitoring)

	for _, player in ipairs(Players:GetPlayers()) do
		setupPlayerMonitoring(player)
	end
end

return SlotManager