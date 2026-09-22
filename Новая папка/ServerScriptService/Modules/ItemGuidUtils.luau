--!strict

local HttpService = game:GetService("HttpService")

local ItemGuidUtils = {}

local function tableHasGuid(existingItems: {any}?, guid: string): boolean
	if typeof(existingItems) ~= "table" then
		return false
	end

	for _, item in ipairs(existingItems) do
		if typeof(item) == "table" then
			local existingGuid = item.GUID
			if typeof(existingGuid) == "string" and existingGuid == guid then
				return true
			end
		end
	end

	return false
end

function ItemGuidUtils.generateGuid(existingItems: {any}?): string
	local guid = HttpService:GenerateGUID(false)

	if tableHasGuid(existingItems, guid) then
		return ItemGuidUtils.generateGuid(existingItems)
	end

	return guid
end

function ItemGuidUtils.ensureItemGuid(itemData: {[string]: any}, existingItems: {any}?): string
	local guid = itemData.GUID
	if typeof(guid) == "string" and guid ~= "" then
		return guid
	end

	local generatedGuid = ItemGuidUtils.generateGuid(existingItems)
	itemData.GUID = generatedGuid
	return generatedGuid
end

function ItemGuidUtils.getInstanceGuid(instance: Instance): string?
	local guid = instance:GetAttribute("GUID")
	if typeof(guid) == "string" and guid ~= "" then
		return guid
	end

	return nil
end

function ItemGuidUtils.ensureInstanceGuid(instance: Instance, existingItems: {any}?): string
	local guid = ItemGuidUtils.getInstanceGuid(instance)
	if guid then
		return guid
	end

	local generatedGuid = ItemGuidUtils.generateGuid(existingItems)
	instance:SetAttribute("GUID", generatedGuid)
	return generatedGuid
end

return ItemGuidUtils