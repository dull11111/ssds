--!strict
-- LOCATION: ReplicatedStorage/Modules/UpgradesConfiguration

local UpgradesConfiguration = {}

UpgradesConfiguration.Upgrades = {
	["Pull"] = {
		DisplayName = "Pull",
		ImageId = "rbxassetid://119928024915098",
		BaseCost = 50,
		PriceMultiplier = 1.25,
		DefaultValue = 1,
		MaxValue = 5,
		RobuxProductId = 3576717705,
	}
}

function UpgradesConfiguration.GetUpgradeByProductId(productId: number): string?
	for upgradeType, config in pairs(UpgradesConfiguration.Upgrades) do
		if config.RobuxProductId == productId then
			return upgradeType
		end
	end
	return nil
end

return UpgradesConfiguration