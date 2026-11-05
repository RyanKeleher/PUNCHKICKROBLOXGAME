-- Turns every procedural pose in the game (moves, hit react, emotes, stance)
-- into KeyframeSequences that Roblox Studio's Animation Editor can open, so
-- you can polish them by hand and publish them as real animations.
--
-- HOW TO USE (in Studio, in Edit mode, NOT while playing):
--   1. View > Command Bar, paste this, press Enter:
--        require(game.ServerScriptService.Server.Dev.AnimationExporter).run()
--   2. A rig called "PK_AnimRig" appears at the origin, holding the
--      animations in its AnimSaves. (Or select your own R15 rig first; the
--      exporter uses the selected rig if there is one.)
--   3. Avatar tab > Animation Editor > click the rig > "..." menu > Load >
--      pick e.g. PK_Move_uppercut. Tweak it, then "..." > Publish to Roblox.
--   4. Copy the published id into that move's / emote's `animationId` in
--      Config/Moves or Config/Animations, as "rbxassetid://<id>".
--
-- Poses are sampled at 30 fps, so spins and easing come out exactly as they
-- look in game.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Selection = game:GetService("Selection")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Moves = require(Shared.Config.Moves)
local Animations = require(Shared.Config.Animations)
local PoseMath = require(Shared.PoseMath)

local FPS = 30
local RIG_NAME = "PK_AnimRig"

-- R15 part -> its parent part in the joint tree (how Poses must be nested).
local PARENT = {
	LowerTorso = "HumanoidRootPart",
	UpperTorso = "LowerTorso",
	Head = "UpperTorso",
	RightUpperArm = "UpperTorso",
	RightLowerArm = "RightUpperArm",
	RightHand = "RightLowerArm",
	LeftUpperArm = "UpperTorso",
	LeftLowerArm = "LeftUpperArm",
	LeftHand = "LeftLowerArm",
	RightUpperLeg = "LowerTorso",
	RightLowerLeg = "RightUpperLeg",
	RightFoot = "RightLowerLeg",
	LeftUpperLeg = "LowerTorso",
	LeftLowerLeg = "LeftUpperLeg",
	LeftFoot = "LeftLowerLeg",
}

local Exporter = {}

local function findRig(): Model?
	for _, selected in Selection:Get() do
		if selected:IsA("Model") and selected:FindFirstChildOfClass("Humanoid") then
			return selected
		end
	end
	local existing = workspace:FindFirstChild(RIG_NAME)
	if existing and existing:IsA("Model") then
		return existing
	end
	local ok, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	end)
	if not ok or not rig then
		return nil
	end
	rig.Name = RIG_NAME
	rig:PivotTo(CFrame.new(0, 5, 0))
	local root = rig:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = true
	end
	rig.Parent = workspace
	return rig
end

-- Builds one keyframe's Pose tree for the animated parts.
local function buildKeyframe(time: number, partAngles: { [string]: Vector3 }): Keyframe
	local keyframe = Instance.new("Keyframe")
	keyframe.Time = time
	local poses: { [string]: Pose } = {}

	local function poseFor(partName: string): Pose
		local existing = poses[partName]
		if existing then
			return existing
		end
		local pose = Instance.new("Pose")
		pose.Name = partName
		pose.Weight = 0 -- just a link in the chain unless we animate it below
		pose.EasingStyle = Enum.PoseEasingStyle.Linear
		poses[partName] = pose
		local parentName = PARENT[partName]
		pose.Parent = if parentName then poseFor(parentName) else keyframe
		return pose
	end

	poseFor("HumanoidRootPart")
	for partName, angles in partAngles do
		local pose = poseFor(partName)
		pose.Weight = 1
		pose.CFrame = PoseMath.toCFrame(angles)
	end
	return keyframe
end

local function buildSequence(name: string, pose, looped: boolean): KeyframeSequence
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = name
	sequence.Loop = looped
	sequence.Priority = Enum.AnimationPriority.Action

	local joints = PoseMath.jointSet(pose)
	local frameCount = math.max(1, math.ceil(pose.duration * FPS))
	for i = 0, frameCount do
		local t = math.min(i / FPS, pose.duration)
		local partAngles = {}
		for joint in joints do
			local partName = PoseMath.R15_PARTS[joint]
			if partName then
				partAngles[partName] = PoseMath.sample(pose, t, joint)
			end
		end
		buildKeyframe(t, partAngles).Parent = sequence
	end
	return sequence
end

-- A held pose (the stance) as a 1-second looping animation.
local function staticPose(joints: { [string]: Vector3 })
	return {
		duration = 1,
		frames = {
			{ t = 0, joints = joints },
			{ t = 1, joints = joints },
		},
	}
end

function Exporter.run()
	local rig = findRig()
	if not rig then
		warn("[AnimationExporter] Couldn't create a rig. Use Avatar > Rig Builder > R15 > Block Rig, select it, and run again.")
		return
	end

	local saves = rig:FindFirstChild("AnimSaves")
	if not saves then
		saves = Instance.new("ObjectValue")
		saves.Name = "AnimSaves"
		saves.Parent = rig
	end

	local exported = 0
	local function add(name: string, pose, looped: boolean?)
		local old = saves:FindFirstChild(name)
		if old then
			old:Destroy()
		end
		buildSequence(name, pose, looped == true).Parent = saves
		exported += 1
	end

	for _, move in Moves.list do
		add("PK_Move_" .. move.id, move.pose)
		if move.poseAlt then
			add("PK_Move_" .. move.id .. "_alt", move.poseAlt)
		end
	end
	add("PK_HitReact", Animations.HitReact.pose)
	for _, emote in Animations.Emotes do
		add("PK_Emote_" .. emote.id, emote.pose)
	end
	add("PK_Stance", staticPose(Animations.Stance.joints), true)

	Selection:Set({ rig })
	print(`[AnimationExporter] Exported {exported} animations into {rig:GetFullName()}.AnimSaves`)
	print("[AnimationExporter] Open Avatar > Animation Editor, click the rig, then '...' > Load to edit one.")
end

return Exporter
