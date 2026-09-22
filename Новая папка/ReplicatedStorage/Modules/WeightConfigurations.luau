--!strict
-- LOCATION: ReplicatedStorage/Modules/WeightConfigurations

local WeightConfigurations = {}

WeightConfigurations.LiftingTimeSeconds = 0.5
WeightConfigurations.Weights = {
	["Wooden Dumbbell"] = { 
		Power = 2, 
		Price = 100,
		ProductId = 3580373389, 
		ImageId = "rbxassetid://76331768773497",
	},
	["Stone Dumbbell"] = { 
		Power = 5, 
		Price = 2500, 
		ProductId = 3580373522,
		ImageId = "rbxassetid://124554978535935",
	},
	["Normal Dumbbell"] = { 
		Power = 10, 
		Price = 60000,
		ProductId = 3580373682, 
		ImageId = "rbxassetid://115941410594856",
	},
	["Heavy Dumbbell"] = { 
		Power = 25, 
		Price = 200000, 
		ProductId = 3580373824,
		ImageId = "rbxassetid://128158128464774",
	},
	["Gold Dumbbell"] = { 
		Power = 50, 
		Price = 750000,
		ProductId = 3580373992, 
		ImageId = "rbxassetid://116347820050001",
	},
	["Diamond Dumbbell"] = { 
		Power = 80, 
		Price = 2000000, 
		ProductId = 3580374126,
		ImageId = "rbxassetid://107195809633219",
	},
	["Lava Dumbbell"] = { 
		Power = 150, 
		Price = 5000000,
		ProductId = 3580374323, 
		ImageId = "rbxassetid://111852609348378",
	},
	["Frozen Dumbbell"] = { 
		Power = 250, 
		Price = 10000000, 
		ProductId = 3580374487,
		ImageId = "rbxassetid://111059957157986",
	},
}

function WeightConfigurations.GetWeightData(weightName: string)
	return WeightConfigurations.Weights[weightName]
end

return WeightConfigurations