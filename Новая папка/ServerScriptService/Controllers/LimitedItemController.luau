--!strict
-- LOCATION: ServerScriptService/Controllers/LimitedItemController

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ProductConfigurations = require(ReplicatedStorage.Modules.ProductConfigurations)

local LimitedItemController = {}
local events: Folder

-- DataStore to hold the stock
local stockStore = DataStoreService:GetDataStore("LimitedItemStock_001")

-- Combines ProductId AND your custom StockKey
local STOCK_KEY = "Item_" .. tostring(ProductConfigurations.LimitedItem.ProductId) .. "_" .. (ProductConfigurations.LimitedItem.StockKey or "Default")

local currentStock = 0

-- Function to broadcast stock to all clients
local function broadcastStock()
	if not events then return end
	local remote = events:FindFirstChild("UpdateLimitedItemStock")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireAllClients(currentStock, ProductConfigurations.LimitedItem.MaxStock)
	end
end

-- Refresh stock from DataStore (Polling)
local function refreshStock()
	local success, val = pcall(function()
		return stockStore:GetAsync(STOCK_KEY)
	end)

	if success then
		if val == nil then
			currentStock = ProductConfigurations.LimitedItem.MaxStock
		else
			currentStock = val
		end
	else
		warn("[LimitedItemController] Failed to fetch stock")
	end

	broadcastStock()
end

-- Attempt to buy (Decrement stock)
function LimitedItemController:DecrementStock(): boolean
	local success, newStock = pcall(function()
		return stockStore:UpdateAsync(STOCK_KEY, function(oldVal)
			local val = oldVal
			-- If data doesn't exist yet (New Key), assume MaxStock
			if val == nil then val = ProductConfigurations.LimitedItem.MaxStock end

			if val <= 0 then return nil end
			return val - 1
		end)
	end)

	if success and newStock then
		currentStock = newStock
		broadcastStock()
		return true
	else
		refreshStock()
		return false
	end
end

function LimitedItemController:GetStock()
	return currentStock
end

function LimitedItemController:Init(controllers)
	events = ReplicatedStorage:WaitForChild("Events")

	if not events:FindFirstChild("UpdateLimitedItemStock") then
		local re = Instance.new("RemoteEvent")
		re.Name = "UpdateLimitedItemStock"
		re.Parent = events
	end
	print("[LimitedItemController] Initialized")
end

function LimitedItemController:Start()
	-- 1. Load Data
	refreshStock()

	-- 2. Polling Loop
	task.spawn(function()
		while true do
			task.wait(60)
			refreshStock()
		end
	end)

	-- 3. Sync New Players
	local function sendToPlayer(p: Player)
		task.wait(2) 
		local remote = events:FindFirstChild("UpdateLimitedItemStock")
		if remote and remote:IsA("RemoteEvent") then
			remote:FireClient(p, currentStock, ProductConfigurations.LimitedItem.MaxStock)
		end
	end

	Players.PlayerAdded:Connect(sendToPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(sendToPlayer, p)
	end
end

return LimitedItemController