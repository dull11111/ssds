--!strict
-- LOCATION: ServerScriptService/Controllers/PullableController

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local PlayerController = require(ServerScriptService.Controllers.PlayerController)
local RewardHandler = require(ServerScriptService.Modules.RewardHandler)

local RopeTemplate = ReplicatedStorage.Templates.PullRope

local playersByPullable: { [BasePart]: Player } = {}
local pullablesByPlayer: { [Player]: { [BasePart]: boolean } } = {}

local PULLABLE_TAG = "Pullable"

local function getEventsFolder(): Folder
	local events = ReplicatedStorage:FindFirstChild("Events")

	if not events then
		events = Instance.new("Folder")
		events.Name = "Events"
		events.Parent = ReplicatedStorage
	end

	return events :: Folder
end

local StopPullRemote = Instance.new("RemoteFunction", getEventsFolder())
StopPullRemote.Name = "StopPull"

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

local function onPullStart(player: Player, Pullable: BasePart)
	if player:GetAttribute("pullDebounce") then
		return
	end

	player:SetAttribute("pullDebounce", true)
	task.delay(0.5, player.SetAttribute, player, "pullDebounce", false)

	local pullCount = player:GetAttribute("PullCount") :: number? or 0
	local maxPullCount = player:GetAttribute("MaxPullCount") :: number? or 1
	if pullCount >= maxPullCount then
		getOrCreateRemoteEvent("ShowNotification"):FireClient(player, "Max pulls reached!", "Error")
		return
	end

	local Humanoid = player.Character and player.Character:FindFirstChild("Humanoid") :: Humanoid?
	local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart or not Humanoid then
		return
	end

	player:SetAttribute("PullCount", pullCount + 1)

	local prompt = Pullable:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = false
	end

	local playerProfile = PlayerController:GetProfile(player)
	local canPull = playerProfile and playerProfile.Data.Power >= (Pullable:GetAttribute("PowerRequirement") or 0)
	if not canPull then
		getOrCreateRemoteEvent("ShowNotification"):FireClient(player, "You need more strength to pull this!", "Error")
	end

	local density: number = if canPull then 2 else 100
	Pullable.CustomPhysicalProperties = PhysicalProperties.new(density, 0.3, 0.5, 1, 1)

	local Attachment = Instance.new("Attachment", Pullable)
	local RopeConstraint = RopeTemplate:Clone()
	RopeConstraint.Attachment0 = Attachment
	RopeConstraint.Attachment1 = rootPart:FindFirstChild("RootAttachment") :: Attachment?
	RopeConstraint.Parent = Pullable

	Pullable:SetNetworkOwner(player)
	playersByPullable[Pullable] = player
	pullablesByPlayer[player][Pullable] = true

	Humanoid:UnequipTools()
end

local function loadPullable(Pullable: BasePart)
	local prompt = Instance.new("ProximityPrompt", Pullable)
	prompt.ActionText = "Steal"
	prompt.HoldDuration = 0.2
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 10

	prompt.Triggered:Connect(function(player)
		onPullStart(player, Pullable)
	end)
end

local function stopPull(Pullable: BasePart)
	local rope = Pullable:FindFirstChild(RopeTemplate.Name)
	if rope then
		rope:Destroy()
	end

	local prompt = Pullable:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = true
	end

	local player = playersByPullable[Pullable]
	if player then
		player:SetAttribute("PullCount", math.max(0, player:GetAttribute("PullCount") - 1))
		pullablesByPlayer[player][Pullable] = nil

		local despawnTimestamp: number? = Pullable:GetAttribute("DespawnTimestamp")
		if despawnTimestamp and DateTime.now().UnixTimestampMillis / 1000 >= despawnTimestamp then
			getOrCreateRemoteEvent("ShowNotification"):FireClient(player, "Timer ran out!", "Error")
		end
	end

	playersByPullable[Pullable] = nil

	if Pullable.Parent then
		Pullable:SetNetworkOwnershipAuto()
	end
end

local function stopPlayerPulls(player: Player): boolean
	local pullables = pullablesByPlayer[player]
	if not pullables then
		return true
	end

	for Pullable, _ in pullables do
		stopPull(Pullable)
	end
	
	return true
end

local function unloadPullable(Pullable: BasePart)
	stopPull(Pullable)
end

local function onCharacterAdded(player: Player, char: Model)
	stopPlayerPulls(player);
	
	(char:WaitForChild("Humanoid") :: Humanoid).Died:Once(function()
		stopPlayerPulls(player)
	end)
end

local function onPlayerAdded(player: Player)
	pullablesByPlayer[player] = {}
	
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
	
	player.CharacterAdded:Connect(function(char)
		onCharacterAdded(player, char)
	end)
end

local function onPlayerRemoving(player: Player)
	for Pullable, _ in pullablesByPlayer[player] do
		stopPull(Pullable)
	end

	pullablesByPlayer[player] = nil
end

local function processAward(player: Player, Pullable: BasePart)
	if not Pullable.Parent then
		warn(`[PullableHandler] Failed to process award for Pullable {Pullable.Name}, couldn't find Lucky Block model; has no parent!`)
		return
	end

	local luckyBlockName = Pullable.Parent.Name
	RewardHandler:GiveLuckyBlock(player, luckyBlockName)

	local successMsg: string = `Successfully stole {luckyBlockName}!`
	local LuckyBlocksConfigurations = require(ReplicatedStorage.Modules.LuckyBlockConfigurations)
	local luckyBlockData = LuckyBlocksConfigurations.Blocks[luckyBlockName]
	if luckyBlockData and luckyBlockData.Rarity then
		successMsg = `Successfully stole {luckyBlockData.Rarity} {luckyBlockName}!` 
	end

	getOrCreateRemoteEvent("ShowNotification"):FireClient(player, successMsg, "Success")
end

local PullableController = {}

function PullableController:Start()
	for _, Pullable in CollectionService:GetTagged(PULLABLE_TAG) :: { BasePart } do
		loadPullable(Pullable)
	end

	CollectionService:GetInstanceAddedSignal(PULLABLE_TAG):Connect(loadPullable)
	CollectionService:GetInstanceRemovedSignal(PULLABLE_TAG):Connect(unloadPullable)
	
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	
	StopPullRemote.OnServerInvoke = stopPlayerPulls
	
	game.Workspace.CollectPart.Touched:Connect(function(Pullable: BasePart)
		if not Pullable:HasTag(PULLABLE_TAG) then
			return
		end

		local player = playersByPullable[Pullable]
		if player then
			processAward(player, Pullable)
		end

		if Pullable.Parent then
			Pullable.Parent:Destroy()
		end
	end)
end

--[[
	Claims all pullables for a player and awards them their rewards.
	Returns true if successful, false otherwise.
]]
function PullableController:ClaimPullables(player: Player)
	if not pullablesByPlayer[player] then
		return true
	end
	
	if player:GetAttribute("PullableClaimCooldown") then
		return false
	end
	
	player:SetAttribute("PullableClaimCooldown", true)
	task.delay(1, player.SetAttribute, player, "PullableClaimCooldown", false)
	
	for Pullable, _ in pullablesByPlayer[player] do
		processAward(player, Pullable)
		
		if Pullable.Parent then
			Pullable:Destroy()
		end
	end
	
	return true
end

return PullableController