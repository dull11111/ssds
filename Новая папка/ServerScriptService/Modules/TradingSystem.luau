--!strict
-- LOCATION: ServerScriptService/Modules/TradingSystem

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")

local ItemManager -- Lazy loaded
local ItemGuidUtils = require(ServerScriptService.Modules.ItemGuidUtils)
local PlayerController = require(ServerScriptService.Controllers.PlayerController)

type ItemView = {
	TradeUuid: string,
	Name: string,
	ItemType: string,
	Mutation: string,
	Rarity: string,
	Level: number,
	GUID: string,
	Tool: Tool?
}

type TradeSideState = {
	Player: Player,
	Items: { [string]: Tool },
	Accepted: boolean,
}

type TradeState = "Active" | "Locking" | "Cancelled" | "Completed"

type TradeSession = {
	Id: number,
	A: TradeSideState,
	B: TradeSideState,
	State: TradeState,
	LockFinishTimestamp: number?,
}

type PendingRequest = {
	FromPlayer: Player,
	ToPlayer: Player,
	CreatedAt: number,
	ExpireAt: number,
	Active: boolean,
}

local TradingSystem = {}

local REQUEST_TIMEOUT = 60
local LOCK_DURATION = 5

local nextSessionId = 1

local activeSessionsByPlayer: { [Player]: TradeSession } = {}
local pendingRequestsByTarget: { [Player]: { [Player]: PendingRequest } } = {}

local function isItemTradeable(itemType: string?): boolean
	itemType = itemType or "Main"
	return itemType == "Main" or itemType == "LuckyBlocks"
end

local requestEvent: RemoteEvent?
local sessionEvent: RemoteEvent?
local notificationEvent: RemoteEvent?

local function getEvents(): Instance?
	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		return nil
	end

	if not requestEvent then
		requestEvent = eventsFolder:FindFirstChild("RequestTrade") :: RemoteEvent?
	end
	if not sessionEvent then
		sessionEvent = eventsFolder:FindFirstChild("TradeSessionUpdate") :: RemoteEvent?
	end
	if not notificationEvent then
		notificationEvent = eventsFolder:FindFirstChild("ShowNotification") :: RemoteEvent?
	end

	return eventsFolder
end

local function clearActiveSessionFor(player: Player)
	local existing = activeSessionsByPlayer[player]
	if not existing then
		return
	end

	-- ensure we only cancel once
	local aPlayer = existing.A.Player
	local bPlayer = existing.B.Player

	activeSessionsByPlayer[aPlayer] = nil
	activeSessionsByPlayer[bPlayer] = nil

	existing.State = "Cancelled"

	if sessionEvent then
		local reason = "PlayerLeft"
		if aPlayer.Parent then
			sessionEvent:FireClient(aPlayer, "Session", {
				sessionId = existing.Id,
				status = existing.State,
				reason = reason,
			})
		end
		if bPlayer.Parent then
			sessionEvent:FireClient(bPlayer, "Session", {
				sessionId = existing.Id,
				status = existing.State,
				reason = reason,
			})
		end
	end
end

local function clearPendingFor(player: Player)
	-- remove as target
	pendingRequestsByTarget[player] = nil

	-- remove as sender
	for target, fromMap in pairs(pendingRequestsByTarget) do
		local req = fromMap[player]
		if req then
			req.Active = false
			fromMap[player] = nil
			if not next(fromMap) then
				pendingRequestsByTarget[target] = nil
			end
		end
	end
end

local function onPlayerRemoving(player: Player)
	clearActiveSessionFor(player)
	clearPendingFor(player)
end

local function getSessionForPlayer(player: Player): (TradeSession?, TradeSideState?, TradeSideState?)
	local session = activeSessionsByPlayer[player]
	if not session then
		return nil, nil, nil
	end

	if session.A.Player == player then
		return session, session.A, session.B
	end
	return session, session.B, session.A
end

local function serializeItems(items: { [string]: Tool }): { [string]: ItemView }
	local result: { [string]: ItemView } = {}

	for itemTradeUuid, tool in items do
		if tool.Parent then
			local name = tool:GetAttribute("OriginalName") or tool.Name			
			local itemType = tool:GetAttribute("ItemType") or "Main"			
			local mutation = tool:GetAttribute("Mutation") or "Normal"			
			local rarity = tool:GetAttribute("Rarity") or "Common"			
			local level = tool:GetAttribute("Level") or 1			
			local guid = tool:GetAttribute("GUID")
			if not guid then
				warn(`[TradingSystem] Tool {tool.Name} is missing GUID attribute, cannot be traded!`)
				continue
			end

			result[itemTradeUuid] = {
				TradeUuid = itemTradeUuid,
				Name = name :: string,
				ItemType = itemType :: string,
				Mutation = mutation :: string,
				Rarity = rarity :: string,
				Level = level :: number,
				GUID = guid :: string,
				Tool = tool
			}
		end
	end

	return result
end

local function snapshotFor(session: TradeSession, viewer: Player, reason: string?): any
	local selfSide, otherSide
	if session.A.Player == viewer then
		selfSide = session.A
		otherSide = session.B
	else
		selfSide = session.B
		otherSide = session.A
	end

	local data: any = {
		sessionId = session.Id,
		status = session.State,
		lockFinishTimestamp = session.LockFinishTimestamp,
		self = {
			userId = selfSide.Player.UserId,
			accepted = selfSide.Accepted,
			items = serializeItems(selfSide.Items),
		},
		other = {
			userId = otherSide.Player.UserId,
			accepted = otherSide.Accepted,
			items = serializeItems(otherSide.Items),
		},
	}

	if reason then
		data.reason = reason
	end

	return data
end

local function broadcastSnapshot(session: TradeSession, reason: string?)
	if not sessionEvent then
		return
	end

	local aPlayer = session.A.Player
	local bPlayer = session.B.Player

	if aPlayer.Parent then
		sessionEvent:FireClient(aPlayer, "Session", snapshotFor(session, aPlayer, reason))
	end
	if bPlayer.Parent then
		sessionEvent:FireClient(bPlayer, "Session", snapshotFor(session, bPlayer, reason))
	end
end

local function resetAcceptAndLock(session: TradeSession)
	session.A.Accepted = false
	session.B.Accepted = false
	session.State = "Active"
	session.LockFinishTimestamp = nil
end

local function cancelSession(session: TradeSession, reason: string?, cancelledBy: Player?)
	if session.State == "Cancelled" or session.State == "Completed" then
		return
	end

	local aPlayer = session.A.Player
	local bPlayer = session.B.Player

	if activeSessionsByPlayer[aPlayer] == session then
		activeSessionsByPlayer[aPlayer] = nil
	end
	if activeSessionsByPlayer[bPlayer] == session then
		activeSessionsByPlayer[bPlayer] = nil
	end

	session.State = "Cancelled"
	session.LockFinishTimestamp = nil

	if sessionEvent then
		local cancelInfo = reason or "Cancelled"
		if cancelledBy then
			cancelInfo ..= ":" .. tostring(cancelledBy.UserId)
		end
		broadcastSnapshot(session, cancelInfo)
	end
end

local function beginLock(session: TradeSession)
	if session.State ~= "Active" then
		return
	end

	session.State = "Locking"
	local expectedTimestamp = DateTime.now().UnixTimestampMillis/1000 + LOCK_DURATION
	session.LockFinishTimestamp = expectedTimestamp

	local id = session.Id
	broadcastSnapshot(session, nil)

	task.delay(LOCK_DURATION, function()
		-- re-check state and ownership
		local aPlayer = session.A.Player
		local current = activeSessionsByPlayer[aPlayer]
		if not current or current.Id ~= id then
			return
		end

		if current.State ~= "Locking" then
			return
		end

		if current.LockFinishTimestamp ~= expectedTimestamp then
			return
		end

		if not current.A.Accepted or not current.B.Accepted then
			current.State = "Active"
			current.LockFinishTimestamp = nil
			broadcastSnapshot(current, "LockCancelled")
			return
		end

		-- execute trade
		local ok = true

		for _, side in ipairs({ current.A, current.B }) do
			local owner = side.Player
			if not owner.Parent then
				ok = false
				break
			end

			for _, tool in side.Items do
				if not owner.Parent then
					ok = false
					break
				end

				if not tool.Parent then
					ok = false
					break
				end
				local parent = tool.Parent
				local backpack = owner:FindFirstChild("Backpack")
				local character = owner.Character
				local inBackpack = backpack and tool:IsDescendantOf(backpack)
				local inCharacter = character and tool:IsDescendantOf(character)
				if not inBackpack and not inCharacter then
					ok = false
					break
				end
			end

			if not ok then
				break
			end
		end

		local function cancel()
			cancelSession(current, "ValidationFailed", nil)
			if notificationEvent then
				if current.A.Player.Parent then
					notificationEvent:FireClient(current.A.Player, "Trade failed!", "Error")
				end
				if current.B.Player.Parent then
					notificationEvent:FireClient(current.B.Player, "Trade failed!", "Error")
				end
			end
		end

		if not ok then
			cancel()
			return
		end

		-- move items
		local aPlayer = current.A.Player
		local bPlayer = current.B.Player

		local aBackpack = aPlayer:FindFirstChild("Backpack")
		local bBackpack = bPlayer:FindFirstChild("Backpack")

		if not aBackpack then
			repeat
				if not aPlayer.Parent or not bPlayer.Parent then
					cancel()
					return
				end
				aBackpack = aPlayer:WaitForChild("Backpack", 1)
			until aBackpack
		end

		if not bBackpack then
			repeat
				if not aPlayer.Parent or not bPlayer.Parent then
					cancel()
					return
				end
				bBackpack = bPlayer:WaitForChild("Backpack", 1)
			until bBackpack
		end

		local removedFromA: { Tool } = {}
		local removedFromB: { Tool } = {}
		local revert = false

		local function revertChanges()
			for _, tool in removedFromA do
				tool.Parent = aBackpack
			end
			for _, tool in removedFromB do
				tool.Parent = bBackpack
			end
		end

		for i, tool in current.A.Items do
			if not tool.Parent then
				continue
			end

			if not aPlayer.Parent or not bPlayer.Parent then
				revert = true
				break
			end

			--tool.Parent = tradeItemsTemporaryFolder
			table.insert(removedFromA, tool)
		end

		if revert then
			revertChanges()
			cancel()
			return
		end

		for i, tool in current.B.Items do
			if not tool.Parent then
				continue
			end

			if not aPlayer.Parent or not bPlayer.Parent then
				revert = true
				break
			end

			--tool.Parent = tradeItemsTemporaryFolder
			table.insert(removedFromB, tool)
		end

		if revert then
			revertChanges()
			cancel()
			return
		end
		
		local playerAProfile = PlayerController:GetProfile(aPlayer)
		local playerBProfile = PlayerController:GetProfile(bPlayer)

		-- All tools are safely in limbo, grant fresh items via ItemManager
		for _, tool in ipairs(removedFromA) do
			local name = tool:GetAttribute("OriginalName") or tool.Name			
			local itemType = tool:GetAttribute("ItemType") or "Main"			
			local mutation = tool:GetAttribute("Mutation") or "Normal"			
			local rarity = tool:GetAttribute("Rarity") or "Common"			
			local level = tool:GetAttribute("Level") or 1			
			local guid = tool:GetAttribute("GUID") :: string
			local newGuid = ItemGuidUtils.generateGuid(playerBProfile and playerBProfile.Data and playerBProfile.Data.Inventory);

			if playerAProfile and playerAProfile.Data and playerAProfile.Data.Inventory and guid then
				for i, item in playerAProfile.Data.Inventory do
					if item.GUID == guid then
						table.remove(playerAProfile.Data.Inventory, i)
						break
					end
				end
			end
			
			if playerBProfile and playerBProfile.Data and playerBProfile.Data.Inventory then
				local existsInInventory = false
				for _, item in playerBProfile.Data.Inventory do
					if item.GUID == newGuid then
						existsInInventory = true
						break
					end
				end

				if not existsInInventory then
					table.insert(playerBProfile.Data.Inventory, {
						GUID = newGuid,
						Name = name,
						ItemType = itemType,
						Mutation = mutation,
						Rarity = rarity,
						Level = level,
					})
				end
			end

			tool:Destroy();
			(ItemManager :: any).GiveItemToPlayer(bPlayer, newGuid :: string, name :: string, itemType :: string, mutation :: string, rarity :: string, level :: number, false)
		end

		for _, tool in ipairs(removedFromB) do
			local name = tool:GetAttribute("OriginalName") or tool.Name			
			local itemType = tool:GetAttribute("ItemType") or "Main"			
			local mutation = tool:GetAttribute("Mutation") or "Normal"			
			local rarity = tool:GetAttribute("Rarity") or "Common"			
			local level = tool:GetAttribute("Level") or 1			
			local guid = tool:GetAttribute("GUID")
			local newGuid = ItemGuidUtils.generateGuid(playerAProfile and playerAProfile.Data and playerAProfile.Data.Inventory);

			if playerBProfile and playerBProfile.Data and playerBProfile.Data.Inventory and guid then
				for i, item in playerBProfile.Data.Inventory do
					if item.GUID == guid then
						table.remove(playerBProfile.Data.Inventory, i)
						break
					end
				end
			end
			
			if playerAProfile and playerAProfile.Data and playerAProfile.Data.Inventory then
				local existsInInventory = false
				for _, item in playerAProfile.Data.Inventory do
					if item.GUID == newGuid then
						existsInInventory = true
						break
					end
				end
				
				if not existsInInventory then
					table.insert(playerAProfile.Data.Inventory, {
						GUID = newGuid,
						Name = name,
						ItemType = itemType,
						Mutation = mutation,
						Rarity = rarity,
						Level = level,
					})
				end
			end

			tool:Destroy();
			(ItemManager :: any).GiveItemToPlayer(aPlayer, newGuid :: string, name :: string, itemType :: string, mutation :: string, rarity :: string, level :: number, false)
		end

		activeSessionsByPlayer[aPlayer] = nil
		activeSessionsByPlayer[bPlayer] = nil

		current.State = "Completed"
		current.LockFinishTimestamp = nil
		broadcastSnapshot(current, "Completed")

		if notificationEvent then
			if aPlayer.Parent then
				notificationEvent:FireClient(aPlayer, "Trade completed!", "Success")
			end
			if bPlayer.Parent then
				notificationEvent:FireClient(bPlayer, "Trade completed!", "Success")
			end
		end
	end)
end

local function ensureNotInTrade(player: Player): boolean
	if activeSessionsByPlayer[player] then
		return false
	end
	return true
end

local function addPendingRequest(fromPlayer: Player, toPlayer: Player)
	local eventsFolder = getEvents()
	if not eventsFolder then
		return
	end

	if not ensureNotInTrade(fromPlayer) then
		if notificationEvent then
			notificationEvent:FireClient(fromPlayer, "You are already in a trade!", "Error")
		end

		if sessionEvent then
			sessionEvent:FireClient(toPlayer, "RequestCancelledIncoming", {
				fromUserId = fromPlayer.UserId,
				fromName = fromPlayer.Name,
			})
		end

		return
	end

	if not ensureNotInTrade(toPlayer) then
		if notificationEvent then
			notificationEvent:FireClient(fromPlayer, "Target player is already in a trade!", "Error")
		end

		if sessionEvent then
			sessionEvent:FireClient(fromPlayer, "RequestCancelled", {
				targetUserId = toPlayer.UserId,
				targetName = toPlayer.Name,
			})
		end

		return
	end

	local perTarget = pendingRequestsByTarget[toPlayer]
	if not perTarget then
		perTarget = {}
		pendingRequestsByTarget[toPlayer] = perTarget
	end

	local existing = perTarget[fromPlayer]
	if existing then
		existing.Active = false
	end

	local now = os.clock()
	local req: PendingRequest = {
		FromPlayer = fromPlayer,
		ToPlayer = toPlayer,
		CreatedAt = now,
		ExpireAt = now + REQUEST_TIMEOUT,
		Active = true,
	}
	perTarget[fromPlayer] = req

	if sessionEvent then
		if toPlayer.Parent then
			sessionEvent:FireClient(toPlayer, "Request", {
				fromUserId = fromPlayer.UserId,
				fromName = fromPlayer.Name,
				expiresIn = REQUEST_TIMEOUT,
			})
		end
		if fromPlayer.Parent then
			sessionEvent:FireClient(fromPlayer, "RequestSent", {
				toUserId = toPlayer.UserId,
				toName = toPlayer.Name,
				expiresIn = REQUEST_TIMEOUT,
			})
		end
	end

	if notificationEvent and fromPlayer.Parent then
		notificationEvent:FireClient(fromPlayer, "Trade request sent to " .. toPlayer.Name, "Success")
	end

	task.delay(REQUEST_TIMEOUT, function()
		if not req.Active then
			return
		end

		local map = pendingRequestsByTarget[toPlayer]
		if not map then
			return
		end
		if map[fromPlayer] ~= req then
			return
		end

		req.Active = false
		map[fromPlayer] = nil
		if not next(map) then
			pendingRequestsByTarget[toPlayer] = nil
		end

		if sessionEvent then
			if fromPlayer.Parent then
				sessionEvent:FireClient(fromPlayer, "RequestExpired", {
					targetUserId = toPlayer.UserId,
					targetName = toPlayer.Name,
				})
			end
			if toPlayer.Parent then
				sessionEvent:FireClient(toPlayer, "RequestExpiredIncoming", {
					fromUserId = fromPlayer.UserId,
					fromName = fromPlayer.Name,
				})
			end
		end
	end)
end

local function findPendingRequest(fromPlayer: Player, toPlayer: Player): PendingRequest?
	local map = pendingRequestsByTarget[toPlayer]
	if not map then
		return nil
	end
	local req = map[fromPlayer]
	if not req or not req.Active then
		return nil
	end
	return req
end

local function startTradeSession(aPlayer: Player, bPlayer: Player)
	if not ensureNotInTrade(aPlayer) then
		if notificationEvent then
			notificationEvent:FireClient(bPlayer, "Target player is already in a trade!", "Error")
		end

		if sessionEvent then
			sessionEvent:FireClient(aPlayer, "RequestCancelled", {
				targetUserId = bPlayer.UserId,
				targetName = bPlayer.Name,
			})

			sessionEvent:FireClient(bPlayer, "RequestCancelledIncoming", {
				fromUserId = aPlayer.UserId,
				fromName = aPlayer.Name,
			})
		end

		return
	end

	if not ensureNotInTrade(bPlayer) then
		if sessionEvent then
			sessionEvent:FireClient(aPlayer, "RequestCancelled", {
				targetUserId = bPlayer.UserId,
				targetName = bPlayer.Name,
			})

			sessionEvent:FireClient(bPlayer, "RequestCancelledIncoming", {
				fromUserId = aPlayer.UserId,
				fromName = aPlayer.Name,
			})
		end

		return
	end

	local session: TradeSession = {
		Id = nextSessionId,
		A = {
			Player = aPlayer,
			Items = {},
			Accepted = false,
		},
		B = {
			Player = bPlayer,
			Items = {},
			Accepted = false,
		},
		State = "Active",
		LockFinishTimestamp = nil,
	}
	nextSessionId += 1

	activeSessionsByPlayer[aPlayer] = session
	activeSessionsByPlayer[bPlayer] = session

	if sessionEvent then
		if aPlayer.Parent then
			sessionEvent:FireClient(aPlayer, "Session", snapshotFor(session, aPlayer, "Started"))
		end
		if bPlayer.Parent then
			sessionEvent:FireClient(bPlayer, "Session", snapshotFor(session, bPlayer, "Started"))
		end
	end
end

local function handleAddItem(player: Player, tool: Tool)
	if not tool or not tool:IsA("Tool") then
		return
	end

	local session, selfSide, _ = getSessionForPlayer(player)
	if not session or not selfSide then
		return
	end

	if session.State ~= "Active" then
		return
	end

	if tool:GetAttribute("IsTemporary") == true then
		if notificationEvent then
			notificationEvent:FireClient(player, "This item cannot be traded.", "Error")
		end
		return
	end

	local itemType = tool:GetAttribute("ItemType") or "Main"

	if not isItemTradeable(itemType :: string?) then
		if notificationEvent then
			notificationEvent:FireClient(player, "This item type cannot be traded.", "Error")
		end
		return
	end

	local backpack = player:FindFirstChild("Backpack")
	local character = player.Character
	local inBackpack = backpack and tool:IsDescendantOf(backpack)
	local inCharacter = character and tool:IsDescendantOf(character)
	if not inBackpack and not inCharacter then
		return
	end

	for _, existing in selfSide.Items do
		if existing == tool then
			return
		end
	end

	local toolTradeUuid = HttpService:GenerateGUID()
	if selfSide.Items[toolTradeUuid] then
		repeat toolTradeUuid = HttpService:GenerateGUID()
		until not selfSide.Items[toolTradeUuid]
	end

	selfSide.Items[toolTradeUuid] = tool
	resetAcceptAndLock(session)
	broadcastSnapshot(session, nil)
end

local function handleRemoveItem(player: Player, itemTradeUuid: string)
	local session, selfSide, _ = getSessionForPlayer(player)
	if not session or not selfSide then
		return
	end

	if session.State ~= "Active" and session.State ~= "Locking" then
		return
	end

	selfSide.Items[itemTradeUuid] = nil

	resetAcceptAndLock(session)
	broadcastSnapshot(session, nil)
end

local function handleSetAccept(player: Player, accepted: boolean)
	local session, selfSide, otherSide = getSessionForPlayer(player)
	if not session or not selfSide or not otherSide then
		return
	end

	if session.State ~= "Active" and session.State ~= "Locking" then
		return
	end

	selfSide.Accepted = accepted == true

	if not selfSide.Accepted and session.State == "Locking" then
		session.State = "Active"
		session.LockFinishTimestamp = nil
	end

	broadcastSnapshot(session, nil)

	if selfSide.Accepted and otherSide.Accepted and session.State == "Active" then
		beginLock(session)
	end
end

local function handleCancelTrade(player: Player)
	local session, _, _ = getSessionForPlayer(player)
	if not session then
		return
	end

	cancelSession(session, "CancelledByPlayer", player)

	if notificationEvent then
		local otherPlayer = if session.A.Player == player then session.B.Player else session.A.Player
		if otherPlayer.Parent then
			notificationEvent:FireClient(otherPlayer, "The other player cancelled the trade.", "Error")
		end
	end
end

local function handleRespondRequest(targetPlayer: Player, fromPlayer: Player, accepted: boolean)
	if not fromPlayer or not fromPlayer:IsDescendantOf(Players) then
		return
	end

	local req = findPendingRequest(fromPlayer, targetPlayer)
	if not req then
		return
	end

	req.Active = false
	local map = pendingRequestsByTarget[targetPlayer]
	if map then
		map[fromPlayer] = nil
		if not next(map) then
			pendingRequestsByTarget[targetPlayer] = nil
		end
	end

	if not sessionEvent then
		return
	end

	if not accepted then
		if fromPlayer.Parent then
			sessionEvent:FireClient(fromPlayer, "RequestDeclined", {
				byUserId = targetPlayer.UserId,
				byName = targetPlayer.Name,
			})
		end
		if notificationEvent and fromPlayer.Parent then
			notificationEvent:FireClient(fromPlayer, targetPlayer.Name .. " declined your trade request.", "Error")
		end
		return
	end

	startTradeSession(fromPlayer, targetPlayer)
end

local function handleRequestEvent(player: Player, action: string, ...)
	if action == "SendRequest" then
		local target = select(1, ...) :: Player?
		if not target or not target:IsDescendantOf(Players) then
			return
		end
		if target == player then
			if notificationEvent then
				notificationEvent:FireClient(player, "You cannot trade with yourself.", "Error")
			end
			--return
		end
		addPendingRequest(player, target)

	elseif action == "RespondRequest" then
		local fromPlayer = select(1, ...) :: Player?
		local accepted = select(2, ...) :: boolean?
		if not fromPlayer or not fromPlayer:IsDescendantOf(Players) then
			return
		end
		handleRespondRequest(player, fromPlayer, accepted == true)

	elseif action == "AddItem" then
		local tool = select(1, ...) :: Tool?
		if tool then
			handleAddItem(player, tool)
		end

	elseif action == "RemoveItem" then
		local itemTradeUuid = select(1, ...) :: string?
		if type(itemTradeUuid) == "string" then
			handleRemoveItem(player, itemTradeUuid)
		end

	elseif action == "SetAccept" then
		local accepted = select(1, ...) :: boolean?
		handleSetAccept(player, accepted == true)

	elseif action == "CancelTrade" then
		handleCancelTrade(player)
	end
end

function TradingSystem:Init(_controllers)
	local modulesFolder = ServerScriptService:WaitForChild("Modules")
	ItemManager = require(modulesFolder:WaitForChild("ItemManager"))

	local eventsFolder = ReplicatedStorage:WaitForChild("Events")

	requestEvent = eventsFolder:FindFirstChild("RequestTrade") :: RemoteEvent?
	if not requestEvent then
		requestEvent = Instance.new("RemoteEvent")
		requestEvent.Name = "RequestTrade"
		requestEvent.Parent = eventsFolder
	end

	sessionEvent = eventsFolder:FindFirstChild("TradeSessionUpdate") :: RemoteEvent?
	if not sessionEvent then
		sessionEvent = Instance.new("RemoteEvent")
		sessionEvent.Name = "TradeSessionUpdate"
		sessionEvent.Parent = eventsFolder
	end

	notificationEvent = eventsFolder:FindFirstChild("ShowNotification") :: RemoteEvent?

	requestEvent.OnServerEvent:Connect(function(player: Player, action: string, ...)
		handleRequestEvent(player, action, ...)
	end)
end

function TradingSystem:Start()
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return TradingSystem