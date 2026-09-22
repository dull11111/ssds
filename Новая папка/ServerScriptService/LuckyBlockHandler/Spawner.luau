--!strict
-- LOCATION: ServerScriptService/LuckyBlockHandler/Spawner
local Debris = game:GetService("Debris")

local Spawner = {}
Spawner.__index = Spawner

local SpawnedFolder = Instance.new("Folder", game.Workspace)
SpawnedFolder.Name = "SpawnedBlocks"

type OnBlockSpawnListener = (block: Model) -> ()

type self = {
	SpawnPart: BasePart,
	spawnInterval: number,
	maxSpawnedBlocks: number,
	nextSpawnTimestamp: number,
	sample: { Model },
	sampleDespawnTimes: { [Model]: number },
	spawnedBlocks: { Model },
	_blockSpawnListeners: { OnBlockSpawnListener }
}

export type Spawner = typeof(setmetatable({} :: self, Spawner))

local RNG = Random.new()
local Spawners: { Spawner } = {}

function Spawner.new(spawnPart: BasePart, sample: { Model }, despawnTimes: { [Model]: number }, spawnInterval: number?, maxSpawnedBlocks: number?)
	local self = setmetatable({} :: self, Spawner)
	self.nextSpawnTimestamp = 0
	
	self.SpawnPart = spawnPart
	self.spawnInterval = spawnInterval or 10
	self.maxSpawnedBlocks = maxSpawnedBlocks or 10
	self.nextSpawnTimestamp = DateTime.now().UnixTimestampMillis / 1000 + self.spawnInterval
	self.sample = sample
	self.sampleDespawnTimes = despawnTimes
	self.spawnedBlocks = {}
	self._blockSpawnListeners = {}
	
	table.insert(Spawners, self)
	
	return self
end

function Spawner.CanSpawn(self: Spawner)
	return #self.spawnedBlocks < self.maxSpawnedBlocks and DateTime.now().UnixTimestampMillis / 1000 > self.nextSpawnTimestamp
end

function Spawner.OnBlockSpawn(self: Spawner, listenerFunc: OnBlockSpawnListener)
	table.insert(self._blockSpawnListeners, listenerFunc)
end

function Spawner.Spawn(self: Spawner, blockSample: Model)
	local currentTime = DateTime.now().UnixTimestampMillis / 1000
	self.nextSpawnTimestamp = currentTime + self.spawnInterval
	
	local despawnTime = self.sampleDespawnTimes[blockSample]
	
	local clone = blockSample:Clone()
	local randomLocalVector = RNG:NextUnitVector() * Vector3.new(1, 0, 1) * self.SpawnPart.Size/2
	local spawnCFrame = self.SpawnPart.CFrame * CFrame.new(randomLocalVector)
	
	clone.Destroying:Once(function()
		table.remove(self.spawnedBlocks, table.find(self.spawnedBlocks, clone))
	end)
	
	clone:PivotTo(spawnCFrame)
	
	if despawnTime then
		clone:SetAttribute("DespawnTimestamp", currentTime + despawnTime)
		Debris:AddItem(clone, despawnTime)
	end
	
	clone.Parent = SpawnedFolder
	
	table.insert(self.spawnedBlocks, clone)
	
	for _, listenerFunc in self._blockSpawnListeners do
		task.spawn(listenerFunc, clone)
	end
end

function Spawner.SpawnRandom(self: Spawner)
	local randomSample = self.sample[RNG:NextInteger(1, #self.sample)]
	if not randomSample then
		return
	end
	
	self:Spawn(randomSample)
end

function Spawner.UpdateSpawnedBlocksTimers(self: Spawner)
	local currentTime = DateTime.now().UnixTimestampMillis / 1000
	
	for _, block in self.spawnedBlocks do
		local infoGui = block:FindFirstChild("InfoGUI") :: BillboardGui?
		if not infoGui then
			continue
		end
		
		local textLabels = infoGui:FindFirstChild("TextLabels") :: Frame?
		if not textLabels then
			continue
		end
		
		local timerLabel = textLabels:FindFirstChild("Timer") :: TextLabel?
		if not timerLabel then
			continue
		end
		
		local despawnTimestamp = block:GetAttribute("DespawnTimestamp")
		if despawnTimestamp then
			timerLabel.Text = ("⏰ %.1f"):format(math.max(0, despawnTimestamp - currentTime))
			timerLabel.Visible = true
		else
			timerLabel.Visible = false
		end
	end
end

local CHECK_TIME_INTERVAL_MS = 1000
local TIMER_UPDATE_INTERVAL_MS = 100
local nextSpawnCheck: number = 0
local nextTimerUpdate: number = 0
game:GetService("RunService").Heartbeat:Connect(function()
	local currentTime = DateTime.now()

	if currentTime.UnixTimestampMillis >= nextSpawnCheck then
		nextSpawnCheck = currentTime.UnixTimestampMillis + CHECK_TIME_INTERVAL_MS

		for _, spawner in Spawners do
			if spawner:CanSpawn() then
				spawner:SpawnRandom()
			end
		end
	end

	if currentTime.UnixTimestampMillis >= nextTimerUpdate then
		nextTimerUpdate = currentTime.UnixTimestampMillis + TIMER_UPDATE_INTERVAL_MS
		
		for _, spawner in Spawners do
			spawner:UpdateSpawnedBlocksTimers()
		end
	end
end)

return Spawner