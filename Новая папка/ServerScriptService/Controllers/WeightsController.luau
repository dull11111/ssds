--!strict
-- LOCATION: ServerScriptService/Controllers/WeightsController

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local WeightConfigurations = require(ReplicatedStorage.Modules.WeightConfigurations)
local WeightsFolder = ReplicatedStorage.Weights
local TemplatesFolder = ReplicatedStorage.Templates

local PlayerController

local WeightsController = {}

local PROFILE_WAIT_TIMEOUT = 30
local BACKPACK_WAIT_TIMEOUT = 15
local AUTO_LOAD_RETRY_COUNT = 4
local AUTO_LOAD_RETRY_DELAY = 1.5

local characterConnections: {[Player]: RBXScriptConnection} = {}

local function getEventsFolder(): Folder
	local events = ReplicatedStorage:FindFirstChild("Events")

	if not events then
		events = Instance.new("Folder")
		events.Name = "Events"
		events.Parent = ReplicatedStorage
	end

	return events :: Folder
end

local function getOrCreateRemoteEvent(name: string): RemoteEvent
	local events = getEventsFolder()
	local existing = events:FindFirstChild(name)

	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = events

	return remote
end

local function getOrCreateRemoteFunction(name: string): RemoteFunction
	local events = getEventsFolder()
	local existing = events:FindFirstChild(name)

	if existing and existing:IsA("RemoteFunction") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local remoteFunction = Instance.new("RemoteFunction")
	remoteFunction.Name = name
	remoteFunction.Parent = events

	return remoteFunction
end

local function getProfile(player: Player): any?
	if not PlayerController then
		return nil
	end

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

local function ensureWeightData(profile: any)
	if typeof(profile.Data.UnlockedWeights) ~= "table" then
		profile.Data.UnlockedWeights = {}
	end

	if profile.Data.EquippedWeight ~= nil and typeof(profile.Data.EquippedWeight) ~= "string" then
		profile.Data.EquippedWeight = nil
	end
end

local function clearOldWeights(container: Instance?)
	if not container then
		return
	end

	for _, item in ipairs(container:GetChildren()) do
		if item:IsA("Tool") and item:GetAttribute("IsWeight") then
			print("Removing old weight:", item)
			item:Destroy()
		end
	end
end

local function playerHasWeightTool(player: Player, weightName: string): boolean
	local containers = {
		player.Character,
		player:FindFirstChildOfClass("Backpack"),
		player:FindFirstChild("StarterGear"),
	} :: { Instance }

	for _, container in containers do
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and child:GetAttribute("IsWeight") and child.Name == weightName then
				return true
			end
		end
	end

	return false
end

local function getBestUnlockedWeight(profile: any): string?
	ensureWeightData(profile)

	local equippedWeight = profile.Data.EquippedWeight
	if typeof(equippedWeight) == "string" and profile.Data.UnlockedWeights[equippedWeight] then
		local equippedData = WeightConfigurations.GetWeightData(equippedWeight)
		if equippedData then
			return equippedWeight
		end
	end

	local bestWeight: string? = nil
	local highestPower = -1

	for weightName, isUnlocked in pairs(profile.Data.UnlockedWeights) do
		if isUnlocked then
			local weightData = WeightConfigurations.GetWeightData(weightName)
			if weightData and weightData.Power > highestPower then
				highestPower = weightData.Power
				bestWeight = weightName
			end
		end
	end

	return bestWeight
end

local function canLiftWeight(player: Player): (boolean, string?)
	if (player:GetAttribute("PullCount") :: number? or 0) > 0 then
		return false, "Can't lift while pulling!"
	end
	
	return true, nil
end

function WeightsController.GiveWeightTool(player: Player, weightName: string, powerGain: number): Tool?
	if typeof(weightName) ~= "string" or weightName == "" then
		return nil
	end

	local weightConfigData = WeightConfigurations.GetWeightData(weightName)
	if not weightConfigData then
		warn("[WeightsController] Tried to give invalid weight:", weightName)
		return nil
	end

	local backpack = player:WaitForChild("Backpack", BACKPACK_WAIT_TIMEOUT)
	if not backpack then
		warn("[WeightsController] Backpack was not ready for:", player.Name, "Weight:", weightName)
		return nil
	end

	local starterGear = player:FindFirstChild("StarterGear")
	local char = player.Character

	clearOldWeights(backpack)
	clearOldWeights(starterGear)
	clearOldWeights(char)

	local tool = WeightsFolder:FindFirstChild(weightName) :: Tool
	if tool == nil then
		tool = WeightsFolder["Wooden Dumbbell"]
		warn(`[WeightsController] Weight tool {weightName} not found in ReplicatedStorage.Weights; did you forget to add it? Giving default Wooden Dumbell.`)
	end
	
	tool = tool:Clone()
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool:SetAttribute("IsWeight", true)
	tool:SetAttribute("IsTemporary", true)
	tool:SetAttribute("PowerGain", powerGain)

	if weightConfigData.ImageId then
		tool.TextureId = weightConfigData.ImageId
	end
	
	local animTracks: { [string]: AnimationTrack } = {
		Idle = nil :: any,
		Action = nil :: any,
	}
	local actionAnimPlayTime: number = WeightConfigurations.LiftingTimeSeconds

	local function cleanupEquippedState()
		for animType, animTrack in animTracks do
			animTrack:Stop()
			animTrack:Destroy()
			animTracks[animType] = nil
		end
	end

	tool.Equipped:Connect(function()
		local currentChar = player.Character
		if not currentChar then return end

		local hum = currentChar:FindFirstChild("Humanoid") :: Humanoid?		
		if not hum then
			return
		end

		local animator = hum:FindFirstChild("Animator") :: Animator?
		if not animator then
			return
		end

		local animTemplate = TemplatesFolder:FindFirstChild("DumbellAnimation")
		if animTemplate then
			if animTemplate:IsA("Animation") then
				animTracks.Action = animator:LoadAnimation(animTemplate)
			else
				warn("[WeightsController] DumbellAnimation found but isn't Animation! Make sure that it is an Animation instance.")
			end
		else
			warn("[WeightsController] DumbellAnimation not found in ReplicatedStorage.Templates!")
		end

		local idleAnimTemplate = TemplatesFolder:FindFirstChild("DumbellIdleAnimation")
		if idleAnimTemplate then
			if idleAnimTemplate:IsA("Animation") then
				local track = animator:LoadAnimation(idleAnimTemplate)
				track.Priority = Enum.AnimationPriority.Movement
				animTracks.Idle = track
				track:Play()
			else
				warn("[WeightsController] DumbellIdleAnimation found but isn't Animation! Make sure that it is an Animation instance.")
			end
		else
			warn("[WeightsController] DumbellIdleAnimation not found in ReplicatedStorage.Templates!")
		end
	end)
	
	local cooldown = false
	tool.Activated:Connect(function()
		if cooldown then
			return
		end
		
		cooldown = true
		
		task.delay(actionAnimPlayTime, function()
			cooldown = false
		end)
		
		local canLift, reason = canLiftWeight(player)
		if not canLift then
			local notif = getOrCreateRemoteEvent("ShowNotification")
			notif:FireClient(player, reason, "Error")
			return
		end
		
		local actionTrack = animTracks.Action
		if actionTrack then
			actionTrack:Play(nil, nil, actionTrack.Length / actionAnimPlayTime)
		end
		
		local leaderstats = player:FindFirstChild("leaderstats")
		if not leaderstats then return end
		
		local powerStat = leaderstats:FindFirstChild("Power")
		local rebirthsStat = leaderstats:FindFirstChild("Rebirths")
		
		if powerStat == nil or not powerStat:IsA("NumberValue") then
			return
		end

		local rebirths = if rebirthsStat and rebirthsStat:IsA("NumberValue") then rebirthsStat.Value else 0
		local powerMultiplier = 1 + (rebirths * 0.25)
		local finalPowerGain = math.round(powerGain * powerMultiplier)

		powerStat.Value += finalPowerGain

		local events = ReplicatedStorage:FindFirstChild("Events")
		local powerPopupEvent = events and events:FindFirstChild("ShowPowerPopUp")
		if powerPopupEvent and powerPopupEvent:IsA("RemoteEvent") then
			powerPopupEvent:FireClient(player, finalPowerGain)
		end
	end)

	tool.Unequipped:Connect(cleanupEquippedState)
	tool.Destroying:Once(cleanupEquippedState)

	tool.Parent = backpack

	-- Optional StarterGear mirror:
	-- This helps Roblox/Satchel notice the tool consistently on respawn.
	if starterGear then
		local starterTool = tool:Clone()
		starterTool.Parent = starterGear
	end

	print("[WeightsController] Gave weight tool:", player.Name, weightName)

	return tool
end

local function fireWeightUI(player: Player, weightName: string)
	local updateWeightsUI = getOrCreateRemoteEvent("UpdateWeightsUI")
	updateWeightsUI:FireClient(player, weightName)
end

local function saveEquippedWeight(player: Player, weightName: string)
	local profile = getProfile(player)
	if not profile or not profile.Data then
		return
	end

	ensureWeightData(profile)
	profile.Data.EquippedWeight = weightName
end

local function equipWeight(player: Player, weightName: string, notifyMessage: string?)
	local profile = getProfile(player)
	if not profile or not profile.Data then
		return false
	end

	ensureWeightData(profile)

	local weightData = WeightConfigurations.GetWeightData(weightName)
	if not weightData then
		return false
	end

	profile.Data.UnlockedWeights[weightName] = true
	profile.Data.EquippedWeight = weightName

	local tool = WeightsController.GiveWeightTool(player, weightName, weightData.Power)

	if tool then
		fireWeightUI(player, weightName)

		if notifyMessage then
			local notif = getOrCreateRemoteEvent("ShowNotification")
			notif:FireClient(player, notifyMessage, "Success")
		end

		return true
	end

	return false
end

local function autoLoadWeightForPlayer(player: Player, reason: string)
	task.spawn(function()
		local profile = waitForProfile(player)
		if not profile or not profile.Data then
			warn("[WeightsController] Profile not ready while auto-loading weight for:", player.Name)
			return
		end

		ensureWeightData(profile)

		local character = player.Character or player.CharacterAdded:Wait()
		if not character or not character.Parent then
			return
		end

		local selectedWeight = getBestUnlockedWeight(profile)
		if not selectedWeight then
			return
		end

		local weightData = WeightConfigurations.GetWeightData(selectedWeight)
		if not weightData then
			return
		end

		for attempt = 1, AUTO_LOAD_RETRY_COUNT do
			if player.Parent ~= Players then
				return
			end

			if not player.Character then
				return
			end

			if playerHasWeightTool(player, selectedWeight) then
				fireWeightUI(player, selectedWeight)

				print(
					"[WeightsController] Weight already loaded:",
					player.Name,
					selectedWeight,
					"Reason:",
					reason,
					"Attempt:",
					attempt
				)

				return
			end

			WeightsController.GiveWeightTool(player, selectedWeight, weightData.Power)
			fireWeightUI(player, selectedWeight)

			task.wait(AUTO_LOAD_RETRY_DELAY)
		end

		if not playerHasWeightTool(player, selectedWeight) then
			warn("[WeightsController] Failed to confirm weight load for:", player.Name, selectedWeight)
		else
			print("[WeightsController] Auto-loaded weight:", player.Name, selectedWeight, "Reason:", reason)
		end
	end)
end

function WeightsController:Init(controllers)
	PlayerController = controllers.PlayerController

	local Events = getEventsFolder()

	local buyEvent = getOrCreateRemoteEvent("RequestWeightPurchase")
	getOrCreateRemoteEvent("ShowPowerPopUp")
	getOrCreateRemoteEvent("UpdateWeightsUI")
	getOrCreateRemoteEvent("ResetWeightsUI")

	buyEvent.OnServerEvent:Connect(function(player: Player, weightName: string)
		if typeof(weightName) ~= "string" or weightName == "" then
			return
		end

		local profile = getProfile(player)
		if not profile or not profile.Data then
			return
		end

		ensureWeightData(profile)

		local weightData = WeightConfigurations.GetWeightData(weightName)
		if not weightData then
			return
		end

		local notif = Events:FindFirstChild("ShowNotification") :: RemoteEvent?

		if profile.Data.UnlockedWeights[weightName] then
			local success = equipWeight(player, weightName, "Equipped " .. weightName .. "!")

			if not success and notif then
				notif:FireClient(player, "Could not equip " .. weightName .. ". Try again!", "Error")
			end

			return
		end

		if weightData.Price > 0 then
			local paid = false

			local success, result = pcall(function()
				return PlayerController:DeductMoney(player, weightData.Price)
			end)

			if success and result == true then
				paid = true
			end

			if paid then
				local equipped = equipWeight(player, weightName, "Purchased " .. weightName .. "!")

				if not equipped and notif then
					notif:FireClient(player, "Purchased, but could not equip. Rejoin or try equipping again.", "Error")
				end
			else
				if notif then
					notif:FireClient(player, "Not enough money!", "Error")
				end
			end
		else
			local success = equipWeight(player, weightName, "Equipped " .. weightName .. "!")

			if not success and notif then
				notif:FireClient(player, "Could not equip " .. weightName .. ". Try again!", "Error")
			end
		end
	end)

	print("[WeightsController] Initialized")
end

function WeightsController:Start()
	local function setupPlayer(player: Player)
		if characterConnections[player] then
			characterConnections[player]:Disconnect()
			characterConnections[player] = nil
		end

		characterConnections[player] = player.CharacterAdded:Connect(function()
			task.delay(1.25, function()
				autoLoadWeightForPlayer(player, "CharacterAdded")
			end)
		end)

		task.delay(2, function()
			autoLoadWeightForPlayer(player, "InitialJoin")
		end)
	end

	Players.PlayerAdded:Connect(setupPlayer)

	Players.PlayerRemoving:Connect(function(player)
		if characterConnections[player] then
			characterConnections[player]:Disconnect()
			characterConnections[player] = nil
		end
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		setupPlayer(player)
	end

	print("[WeightsController] Started")
end

function WeightsController.ForceEquipBestWeight(player: Player)
	autoLoadWeightForPlayer(player, "ForceEquipBestWeight")
end

function WeightsController.ClearWeightTools(player: Player)
	clearOldWeights(player.Character)
	clearOldWeights(player:FindFirstChildOfClass("Backpack"))
	clearOldWeights(player:FindFirstChild("StarterGear"))
end

return WeightsController