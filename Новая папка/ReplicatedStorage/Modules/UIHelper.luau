--!strict
-- LOCATION: ReplicatedStorage/Modules/UIHelper

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local RarityConfigurations = require(Modules:WaitForChild("RarityConfigurations"))
local MutationConfigurations = require(Modules:WaitForChild("MutationConfigurations"))

local UIHelper = {}

-- Applies text color, stroke, and gradient based on given configuration table
local function applyStyle(label: TextLabel, config: any)
	if not config then return end
	if not label then return end

	-- 1. Text Color
	if config.TextColor then 
		label.TextColor3 = config.TextColor 
	end

	-- 2. Stroke
	local stroke = label:FindFirstChild("Stroke") :: UIStroke? or label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = config.StrokeColor or Color3.new(0,0,0)
		stroke.Enabled = true
	end

	-- 3. Gradient
	local gradient = label:FindFirstChild("Gradient"):: UIGradient? or label:FindFirstChildOfClass("UIGradient")
	if gradient then
		if config.GradientColor then
			gradient.Color = config.GradientColor
			gradient.Enabled = true
		else
			gradient.Enabled = false
		end
	end
end

-- Applies text color, stroke, and gradient based on rarity configuration
function UIHelper.ApplyRarityStyle(label: TextLabel, rarityName: string)
	if not rarityName then
		return
	end
	
	local config = RarityConfigurations[rarityName]
	if not config then
		warn(`[UIHelper] No rarity config for {rarityName}!`)
		return
	end
	
	applyStyle(label, config)
end

-- Applies text color, stroke, and gradient based on mutation configuration
function UIHelper.ApplyMutationStyle(label: TextLabel, mutationName: string)
	if not mutationName then
		return
	end
	
	local config = MutationConfigurations[mutationName]
	if not config then
		warn(`[UIHelper] No mutation config for {mutationName}!`)
		return
	end
	
	applyStyle(label, config)
end

return UIHelper