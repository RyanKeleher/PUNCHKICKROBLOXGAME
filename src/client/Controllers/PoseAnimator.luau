-- Plays attack animations without any uploaded animation assets.
--
-- Each move has a "pose": keyframes of joint rotations. We rotate each
-- Motor6D's C0 on top of its rest value, interpolating between keyframes with
-- smoothstep. Roblox's walk/idle animations drive Motor6D.Transform, not C0,
-- so our offsets layer on top of walking instead of fighting it.
--
-- Every client animates every nearby character itself (the server just says
-- "X used move Y"). C0 changes made on a client don't replicate, which is
-- exactly what we want: no network cost per frame.
--
-- If a move has an animationId, that uploaded animation plays instead.

local RunService = game:GetService("RunService")

local PoseAnimator = {}

local R15_PARTS = {
	RightShoulder = "RightUpperArm",
	LeftShoulder = "LeftUpperArm",
	RightElbow = "RightLowerArm",
	LeftElbow = "LeftLowerArm",
	RightHip = "RightUpperLeg",
	LeftHip = "LeftUpperLeg",
	RightKnee = "RightLowerLeg",
	LeftKnee = "LeftLowerLeg",
	Waist = "UpperTorso",
}

-- R6 approximation: forward swings of shoulders and hips only.
local R6_JOINTS = {
	RightShoulder = { "Torso", "Right Shoulder", 1 },
	LeftShoulder = { "Torso", "Left Shoulder", -1 },
	RightHip = { "Torso", "Right Hip", 1 },
	LeftHip = { "Torso", "Left Hip", -1 },
}

local ZERO = Vector3.zero

type Entry = { motor: Motor6D, r6: boolean, sign: number }
type Playing = { pose: any, start: number, motors: { [string]: Entry } }

local originals: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" })
local playing: { [Model]: Playing } = {}
local tracks: { [Instance]: { [string]: AnimationTrack } } = setmetatable({}, { __mode = "k" })
local loop: RBXScriptConnection? = nil

local function resolveMotors(character: Model, pose): { [string]: Entry }
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local isR6 = humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R6
	local motors: { [string]: Entry } = {}
	for _, frame in pose.frames do
		for joint in frame.joints do
			if motors[joint] == nil then
				local motor
				local sign = 1
				if isR6 then
					local map = R6_JOINTS[joint]
					if map then
						local p = character:FindFirstChild(map[1])
						motor = p and p:FindFirstChild(map[2])
						sign = map[3]
					end
				else
					local partName = R15_PARTS[joint]
					local p = partName and character:FindFirstChild(partName)
					motor = p and p:FindFirstChild(joint)
				end
				if motor and motor:IsA("Motor6D") then
					motors[joint] = { motor = motor, r6 = isR6, sign = sign }
				end
			end
		end
	end
	return motors
end

local function offset(entry: Entry, angles: Vector3): CFrame
	if entry.r6 then
		return CFrame.Angles(0, 0, math.rad(angles.X) * entry.sign)
	end
	return CFrame.Angles(math.rad(angles.X), math.rad(angles.Y), math.rad(angles.Z))
end

local function sample(pose, t: number, joint: string): Vector3
	local frames = pose.frames
	local prev = frames[1]
	for i = 2, #frames do
		local frame = frames[i]
		if t <= frame.t then
			local span = frame.t - prev.t
			local alpha = if span > 0 then (t - prev.t) / span else 1
			alpha = alpha * alpha * (3 - 2 * alpha) -- smoothstep
			local a = prev.joints[joint] or ZERO
			local b = frame.joints[joint] or ZERO
			return a:Lerp(b, alpha)
		end
		prev = frame
	end
	return prev.joints[joint] or ZERO
end

local function restore(anim: Playing)
	for _, entry in anim.motors do
		local original = originals[entry.motor]
		if original and entry.motor.Parent then
			entry.motor.C0 = original
		end
	end
end

local function step()
	local now = os.clock()
	for character, anim in playing do
		local t = now - anim.start
		if t >= anim.pose.duration or not character.Parent or character:GetAttribute("Ragdolled") then
			restore(anim)
			playing[character] = nil
		else
			for joint, entry in anim.motors do
				local original = originals[entry.motor]
				if original then
					entry.motor.C0 = original * offset(entry, sample(anim.pose, t, joint))
				end
			end
		end
	end
	if next(playing) == nil and loop then
		loop:Disconnect()
		loop = nil
	end
end

function PoseAnimator.playPose(character: Model, pose)
	if not character or not pose or character:GetAttribute("Ragdolled") then
		return
	end
	local existing = playing[character]
	if existing then
		restore(existing)
	end
	local motors = resolveMotors(character, pose)
	for _, entry in motors do
		if originals[entry.motor] == nil then
			originals[entry.motor] = entry.motor.C0
		end
	end
	playing[character] = { pose = pose, start = os.clock(), motors = motors }
	if not loop then
		loop = RunService.RenderStepped:Connect(step)
	end
end

local function playAnimation(character: Model, animationId: string)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local cache = tracks[animator]
	if not cache then
		cache = {}
		tracks[animator] = cache
	end
	local track = cache[animationId]
	if not track then
		local animation = Instance.new("Animation")
		animation.AnimationId = animationId
		track = animator:LoadAnimation(animation)
		track.Priority = Enum.AnimationPriority.Action
		cache[animationId] = track
	end
	track:Play(0.05)
end

-- Plays a move on any character. variant 2 = the alternate (left) punch.
function PoseAnimator.playMove(character: Model, move, variant: number?)
	if move.animationId and move.animationId ~= "" then
		playAnimation(character, move.animationId)
		return
	end
	local pose = if variant == 2 and move.poseAlt then move.poseAlt else move.pose
	PoseAnimator.playPose(character, pose)
end

return PoseAnimator
