-- The local half of player ragdolls/knockback. Your character's physics run
-- on YOUR machine, so when the server says "you got hit", this applies the
-- velocity and flips the humanoid into Physics state (go limp). When the server
-- clears the "Ragdolled" attribute, we stand back up.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Util.Signal)

local player = Players.LocalPlayer

local RagdollClient = {}
RagdollClient.KnockedBack = Signal.new() -- (strength) for camera shake

local MAX_SPEED = 400 -- ignore absurd values

local function onCharacter(character: Model)
	character:GetAttributeChangedSignal("Ragdolled"):Connect(function()
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 and not character:GetAttribute("Ragdolled") then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

function RagdollClient.start()
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end

	Remotes.get("Knockback").OnClientEvent:Connect(function(velocity, seconds)
		if typeof(velocity) ~= "Vector3" or type(seconds) ~= "number" then
			return
		end
		if velocity.Magnitude ~= velocity.Magnitude or velocity.Magnitude > MAX_SPEED then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
			return
		end

		if seconds > 0 then
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
			for _, p in character:GetDescendants() do
				if p:IsA("BasePart") then
					p.AssemblyLinearVelocity = velocity
				end
			end
		else
			-- A shove: briefly airborne so ground friction doesn't eat it.
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
			root.AssemblyLinearVelocity = velocity
		end
		RagdollClient.KnockedBack:Fire(math.clamp(velocity.Magnitude / 120, 0.1, 1))
	end)
end

return RagdollClient
