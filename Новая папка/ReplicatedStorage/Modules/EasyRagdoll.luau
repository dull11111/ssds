---@module Easy Ragdoll by theonlyflare
-- modified by munj12

--- Services ---
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

--- Module ---
local RagdollModule = {}

--- Constants ---
-- Names of instances created by the ragdoll system, used for cleanup.
local RAGDOLL_INSTANCE_NAMES = {
	["RagdollAttachment"] = true,
	["RagdollConstraint"] = true,
	["ColliderPart"] = true, -- Keep this for cleanup in case old ragdolls had them
	["TorsoWeld"] = true
}

--- Helper Functions ---

--[[
	@param character: Model -- The character model to ragdoll.
	@param humanoid: Humanoid -- The humanoid object within the character.
	@brief Converts Motor6D joints into BallSocketConstraints to enable ragdolling.
	This process involves disabling existing Motor6D joints and replacing them
	with physics-based constraints.
]]
local function replaceJoints(character: Model, humanoid: Humanoid)
	-- Necessary for Ragdolling to function properly
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = true

	-- Disable the 'Animate' script to stop character animations
	local animateScript = character:FindFirstChild("Animate")
	if animateScript and animateScript:IsA("LocalScript") then
		animateScript.Enabled = false
	end

	-- Stop all playing animations on the humanoid's animator
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			track:Stop()
		end
	end

	-- Iterate through all descendants to find Motor6D joints
	for _, motor: Motor6D in pairs(character:GetDescendants()) do
		if not motor:IsA("Motor6D") or motor.Part0 == nil or motor.Part1 == nil then
			continue
		end

		motor.Enabled = false -- Disable the Motor6D to allow physics to take over

		if motor.Name:find("Root") then
			-- Weld the HumanoidRootPart to the Torso to prevent disconnection during ragdoll
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = motor.Part0
			weld.Part1 = motor.Part1
			weld.Name = "TorsoWeld"
			weld.Parent = motor.Parent
			continue
		end

		-- Create attachments for the BallSocketConstraint
		local attachment0 = Instance.new("Attachment")
		local attachment1 = Instance.new("Attachment")

		-- Set Attachment CFrames based on Motor6D's C0 and C1
		attachment0.CFrame = motor.C0
		attachment1.CFrame = motor.C1

		attachment0.Name = "RagdollAttachment"
		attachment1.Name = "RagdollAttachment"

		-- Create the BallSocketConstraint
		local ballSocketConstraint = Instance.new("BallSocketConstraint")
		ballSocketConstraint.Attachment0 = attachment0
		ballSocketConstraint.Attachment1 = attachment1
		ballSocketConstraint.Name = "RagdollConstraint"

		-- Generic BallSocketConstraint properties. These can be fine-tuned
		-- for specific joints for more realistic ragdoll behavior.
		ballSocketConstraint.LimitsEnabled = true
		ballSocketConstraint.TwistLimitsEnabled = true -- Allow some twist, but with limits
		ballSocketConstraint.MaxFrictionTorque = 0.5
		ballSocketConstraint.UpperAngle = 0
		ballSocketConstraint.TwistLowerAngle = 0
		ballSocketConstraint.TwistUpperAngle = 0

		-- Apply specific overrides for certain joints for better control
		if motor.Name:find("Neck") then
			ballSocketConstraint.UpperAngle = 0
			ballSocketConstraint.TwistLowerAngle = 0
			ballSocketConstraint.TwistUpperAngle = 0
		elseif motor.Name:find("Hip") then
			ballSocketConstraint.UpperAngle = 60
			ballSocketConstraint.TwistLowerAngle = -30
			ballSocketConstraint.TwistUpperAngle = 30
		elseif motor.Name:find("Shoulder") then
			ballSocketConstraint.UpperAngle = 75
			ballSocketConstraint.TwistLowerAngle = -60
			ballSocketConstraint.TwistUpperAngle = 60
		end

		-- Parent the attachments and constraint
		attachment0.Parent = motor.Part0
		attachment1.Parent = motor.Part1
		ballSocketConstraint.Parent = motor.Parent
	end

	humanoid.AutoRotate = false -- Disabling AutoRotate prevents the Character rotating in first person or Shift-Lock
	character:SetAttribute("LastRag", tick()) -- Used for anti-cheats to prevent flying Ragdolls from getting flagged
end

--[[
	@param character: Model -- The character model to unragdoll.
	@param humanoid: Humanoid -- The humanoid object within the character.
	@brief Destroys all Ragdoll-related instances (attachments, constraints, colliders)
	and re-enables the original Motor6D's to restore normal character animation.
]]
local function resetJoints(character: Model, humanoid: Humanoid)
	-- Do not unragdoll if the humanoid is dead
	if humanoid.Health < 1 then return end

	for _, instance in pairs(character:GetDescendants()) do
		-- Destroy instances created by the ragdoll system
		if RAGDOLL_INSTANCE_NAMES[instance.Name] then
			instance:Destroy()
		end

		-- Re-enable original Motor6D joints
		if instance:IsA("Motor6D") then
			instance.Enabled = true
		end
	end

	humanoid.AutoRotate = true

	-- Re-enable the 'Animate' script
	local animateScript = character:FindFirstChild("Animate")
	if animateScript and animateScript:IsA("LocalScript") then
		animateScript.Enabled = true
	end
end

--[[
	@param character: Model -- The character model to push.
	@param magnitude: number -- The magnitude of the push to apply.
	@brief Applies an impulse to the character's HumanoidRootPart or Torso.
]]
local function applyPush(character: Model, pushVector: Vector3)
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end

	local RootAttachment = hrp:FindFirstChild("RootAttachment") :: Attachment?
	if not RootAttachment then
		return
	end

	local Force = Instance.new("VectorForce", hrp)
	Force.Attachment0 = RootAttachment

	Force.RelativeTo = Enum.ActuatorRelativeTo.World
	Force.Force = pushVector
	Debris:AddItem(Force, 0.2)
end

local function standUp(character: Model)
	local charCFrame = character:GetPivot()
	character:PivotTo(CFrame.new(charCFrame.Position + Vector3.new(0, 5, 0)) * CFrame.Angles(0, charCFrame.Y, 0))
end

--- Module Functions ---

--[[
	@param character: Model -- The character model to apply or remove ragdoll from.
	@param value: boolean -- True to ragdoll, false to unragdoll.
	@param applyPushOnRagdoll: boolean? -- Optional: Whether to apply a push when ragdolling. Defaults to false.
	@param pushMagnitude: number? -- Optional: The magnitude of the push if applyPushOnRagdoll is true. Defaults to 100.
	@brief Toggles the ragdoll state of the given character, with an option to apply an extra push.
]]
function RagdollModule.SetRagdoll(character: Model, value: boolean, pushVector: Vector3?)
	-- Validate inputs
	if not character then
		warn("RagdollModule.SetRagdoll: No character provided.")
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("RagdollModule.SetRagdoll: Character does not have a Humanoid.")
		return
	end

	if value then -- Ragdoll the character
		replaceJoints(character, humanoid)

		-- character.PrimaryPart.CanCollide = false
		humanoid.PlatformStand = true

		-- Check to see if the module is being called from client/server
		if RunService:IsClient() then
			humanoid:ChangeState(Enum.HumanoidStateType.Ragdoll)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)

		elseif RunService:IsServer() then
			character.PrimaryPart:SetNetworkOwner(nil)

			humanoid:ChangeState(Enum.HumanoidStateType.Ragdoll)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
		end

		-- Apply push only if explicitly requested
		if pushVector then
			applyPush(character, pushVector)
		end
	else -- Unragdoll the character
		resetJoints(character, humanoid)

		-- character.PrimaryPart.CanCollide = false
		humanoid.PlatformStand = false

		if RunService:IsClient() then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

		elseif RunService:IsServer() then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

			-- Fix network ownership for players
			local player: Player? = Players:GetPlayerFromCharacter(character)
			if player then
				character.PrimaryPart:SetNetworkOwner(player)
			end
		end

		standUp(character)
	end
end

-- Return the module
return RagdollModule