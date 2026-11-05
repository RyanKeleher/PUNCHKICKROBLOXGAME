-- Ragdolls: swaps a rig's Motor6D joints for limited BallSocketConstraints.
--
-- Players vs. dummies
--   * Dummies are simulated by the server, so the server does everything.
--   * A player's character is simulated by THAT player's client (network
--     ownership). The server flips the joints (those property changes
--     replicate), then tells the owning client to enter the Physics humanoid
--     state and apply the knockback velocity, since the server can't push a
--     client-owned assembly. When the timer ends the server restores the joints
--     and the client stands back up (it watches the "Ragdolled" attribute).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local RagdollService = {}

type Joint = { motor: Motor6D, socket: BallSocketConstraint }

-- Weak keys: when a character/dummy is destroyed its entry is collected.
local rigs: { [Model]: { Joint } } = setmetatable({}, { __mode = "k" })
local tokens: { [Model]: any } = setmetatable({}, { __mode = "k" })

local KEEP_JOINTS = { Root = true, RootJoint = true } -- keep the root so the camera stays sane

local function isStale(joints: { Joint }): boolean
	for _, j in joints do
		if not j.motor.Parent or not j.socket.Parent then
			return true
		end
	end
	return false
end

-- Builds the sockets for a rig (once). Safe to call repeatedly: it rebuilds
-- if the avatar's parts were swapped after spawning (appearance loading).
function RagdollService.ensure(model: Model, includeRoot: boolean?): { Joint }
	local existing = rigs[model]
	if existing and not isStale(existing) then
		return existing
	end
	local old = model:FindFirstChild("RagdollJoints")
	if old then
		old:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "RagdollJoints"
	local joints: { Joint } = {}

	for _, motor in model:GetDescendants() do
		if motor:IsA("Motor6D") and motor.Part0 and motor.Part1 and (includeRoot or not KEEP_JOINTS[motor.Name]) then
			local a0 = Instance.new("Attachment")
			a0.Name = "RagA0_" .. motor.Name
			a0.CFrame = motor.C0
			a0.Parent = motor.Part0

			local a1 = Instance.new("Attachment")
			a1.Name = "RagA1_" .. motor.Name
			a1.CFrame = motor.C1
			a1.Parent = motor.Part1

			local socket = Instance.new("BallSocketConstraint")
			socket.Name = motor.Name
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = true
			socket.UpperAngle = 55
			socket.TwistLimitsEnabled = true
			socket.TwistLowerAngle = -50
			socket.TwistUpperAngle = 50
			socket.Enabled = false
			socket.Parent = folder

			table.insert(joints, { motor = motor, socket = socket })
		end
	end

	folder.Parent = model
	rigs[model] = joints
	return joints
end

function RagdollService.set(model: Model, on: boolean, includeRoot: boolean?)
	local joints = RagdollService.ensure(model, includeRoot)
	for _, j in joints do
		j.motor.Enabled = not on
		j.socket.Enabled = on
	end
	-- Limbs need to collide while floppy or they sink through the floor.
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
			if on then
				if p:GetAttribute("RagOrigCollide") == nil then
					p:SetAttribute("RagOrigCollide", p.CanCollide)
				end
				p.CanCollide = true
			else
				local orig = p:GetAttribute("RagOrigCollide")
				if orig ~= nil then
					p.CanCollide = orig
					p:SetAttribute("RagOrigCollide", nil)
				end
			end
		end
	end
	model:SetAttribute("Ragdolled", on)
end

-- Knock a player over for `seconds` with `velocity`. Re-hitting extends it.
function RagdollService.ragdollPlayer(player: Player, velocity: Vector3, seconds: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return
	end
	RagdollService.set(character, true)
	Remotes.get("Knockback"):FireClient(player, velocity, seconds)

	local token = {}
	tokens[character] = token
	task.delay(seconds, function()
		if tokens[character] ~= token or not character.Parent then
			return
		end
		tokens[character] = nil
		local h = character:FindFirstChildOfClass("Humanoid")
		if h and h.Health > 0 then
			RagdollService.set(character, false)
		end
	end)
end

-- A shove without ragdolling (light hits).
function RagdollService.pushPlayer(player: Player, velocity: Vector3)
	Remotes.get("Knockback"):FireClient(player, velocity, 0)
end

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	-- Don't let disabling the neck joint count as decapitation, and keep joints
	-- intact on death so we can ragdoll the body instead of it exploding apart.
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.Died:Connect(function()
		RagdollService.set(character, true)
	end)
end

function RagdollService.start()
	local function hook(player: Player)
		player.CharacterAdded:Connect(onCharacter)
		if player.Character then
			task.spawn(onCharacter, player.Character)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end
end

return RagdollService
