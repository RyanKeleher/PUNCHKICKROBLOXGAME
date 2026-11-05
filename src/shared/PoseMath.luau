-- Pure helpers for the keyframe pose format used by Config/Moves and
-- Config/Animations. Shared by the in-game PoseAnimator (client) and the
-- AnimationExporter dev tool, so both read poses exactly the same way.

local PoseMath = {}

-- Pose joint name -> the R15 body part whose Motor6D has that name.
PoseMath.R15_PARTS = {
	RightShoulder = "RightUpperArm",
	LeftShoulder = "LeftUpperArm",
	RightElbow = "RightLowerArm",
	LeftElbow = "LeftLowerArm",
	RightHip = "RightUpperLeg",
	LeftHip = "LeftUpperLeg",
	RightKnee = "RightLowerLeg",
	LeftKnee = "LeftLowerLeg",
	Waist = "UpperTorso",
	Neck = "Head",
}

local ZERO = Vector3.zero

local jointSets: { [any]: { [string]: boolean } } = setmetatable({}, { __mode = "k" })

-- Set of joint names a pose touches in any keyframe (cached per pose table).
function PoseMath.jointSet(pose): { [string]: boolean }
	local set = jointSets[pose]
	if not set then
		set = {}
		for _, frame in pose.frames do
			for joint in frame.joints do
				set[joint] = true
			end
		end
		jointSets[pose] = set
	end
	return set
end

-- Joint angles (degrees) at time t, smoothstep-interpolated between keyframes.
function PoseMath.sample(pose, t: number, joint: string): Vector3
	local frames = pose.frames
	local prev = frames[1]
	for i = 2, #frames do
		local frame = frames[i]
		if t <= frame.t then
			local span = frame.t - prev.t
			local alpha = if span > 0 then (t - prev.t) / span else 1
			alpha = alpha * alpha * (3 - 2 * alpha)
			local a = prev.joints[joint] or ZERO
			local b = frame.joints[joint] or ZERO
			return a:Lerp(b, alpha)
		end
		prev = frame
	end
	return prev.joints[joint] or ZERO
end

function PoseMath.toCFrame(angles: Vector3): CFrame
	return CFrame.Angles(math.rad(angles.X), math.rad(angles.Y), math.rad(angles.Z))
end

return PoseMath
