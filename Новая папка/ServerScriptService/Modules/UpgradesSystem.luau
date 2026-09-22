--!strict
-- LOCATION: ServerScriptService/Modules/UpgradesSystem

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local UpgradesSystem = {}

local PlayerController 
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local UpgradesConfiguration = require(ReplicatedStorage.Modules.UpgradesConfiguration)

local function getBulkPrice(upgradeType: string, currentValue: number, amount: number): number
	local config = UpgradesConfiguration.Upgrades[upgradeType]
	if not config then return 0 end

	local totalPrice = 0
	local tempValue = currentValue

	for i = 1, amount do
		local upgradesBought = math.max(0, tempValue - config.DefaultValue)
		local cost = config.BaseCost * (config.PriceMultiplier ^ upgradesBought)
		totalPrice += cost
		tempValue += 1
	end

	return math.floor(totalPrice)
end

function UpgradesSystem.PurchaseUpgrade(player: Player, upgradeType: string, amount: number)
	local profile = PlayerController:GetProfile(player)
	local config = UpgradesConfiguration.Upgrades[upgradeType]
	if not profile or not config then return end

	local currentValue = profile.Data[upgradeType] or config.DefaultValue

	local actualAmount = if config.MaxValue then math.min(amount, config.MaxValue - currentValue) else amount
	local price = getBulkPrice(upgradeType, currentValue, actualAmount)
	
	if actualAmount <= 0 then
		local Events = ReplicatedStorage:FindFirstChild("Events")
		local notif = Events and Events:FindFirstChild("ShowNotification")
		if notif then notif:FireClient(player, "Upgrade maxxed out!", "Error") end
		return
	end

	if PlayerController:DeductMoney(player, price) then
		profile.Data[upgradeType] = currentValue + actualAmount

		if player:FindFirstChild("UpgradesData") then
			local stat = player.UpgradesData:FindFirstChild(upgradeType)
			if stat then stat.Value = profile.Data[upgradeType] end
		end

		local Events = ReplicatedStorage:FindFirstChild("Events")
		local notif = Events and Events:FindFirstChild("ShowNotification")
		if notif then notif:FireClient(player, "+" .. actualAmount .. " " .. config.DisplayName .. " Upgraded!", "Success") end

		UpgradesSystem.UpdateClientUI(player)
	else
		local Events = ReplicatedStorage:FindFirstChild("Events")
		local notif = Events and Events:FindFirstChild("ShowNotification")
		if notif then notif:FireClient(player, "Not enough money!", "Error") end
	end
end

function UpgradesSystem.UpdateClientUI(player: Player)
	local profile = PlayerController:GetProfile(player)
	if not profile then return end

	local uiData = {}
	for upgradeType, config in pairs(UpgradesConfiguration.Upgrades) do
		local currentVal = profile.Data[upgradeType] or config.DefaultValue
		uiData[upgradeType] = { 
			Current = currentVal, 
			Cost = getBulkPrice(upgradeType, currentVal, 1),
			IsMax = if config.MaxValue then currentVal >= config.MaxValue else false
		}
	end

	local Events = ReplicatedStorage:FindFirstChild("Events")
	local updateEvent = Events and Events:FindFirstChild("UpdateUpgradesUI")
	if updateEvent then updateEvent:FireClient(player, uiData) end
end

function UpgradesSystem:Init(controllers)
	print("[UpgradesSystem] Initialized")
	PlayerController = controllers.PlayerController

	local Events = ReplicatedStorage:WaitForChild("Events")
	local purchaseEvent = Events:FindFirstChild("PurchaseUpgrade") or Instance.new("RemoteEvent")
	purchaseEvent.Name = "PurchaseUpgrade"
	purchaseEvent.Parent = Events

	local updateEvent = Events:FindFirstChild("UpdateUpgradesUI") or Instance.new("RemoteEvent")
	updateEvent.Name = "UpdateUpgradesUI"
	updateEvent.Parent = Events

	purchaseEvent.OnServerEvent:Connect(function(player, upgradeType, amount)
		UpgradesSystem.PurchaseUpgrade(player, upgradeType, amount)
	end)

	updateEvent.OnServerEvent:Connect(function(player)
		local retries = 0
		local profile = PlayerController:GetProfile(player)
		while not profile and retries < 10 do
			task.wait(0.5)
			profile = PlayerController:GetProfile(player)
			retries += 1
		end
		if profile then UpgradesSystem.UpdateClientUI(player) end
	end)
end

function UpgradesSystem:Start()
	local function onPlayerAdded(player: Player)
		local UpgradesData = player:WaitForChild("UpgradesData")
		local PullUpgrade = UpgradesData:WaitForChild("Pull") :: IntValue
		
		player:SetAttribute("MaxPullCount", PullUpgrade.Value)
		PullUpgrade.Changed:Connect(function(newValue: number)
			player:SetAttribute("MaxPullCount", newValue)
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded, p) end
end

return UpgradesSystem