-- Procedural character animation, no uploaded assets required.
--
-- Two layers per character, mixed every frame:
--   1. STANCE  a held guard pose that blends in while the character is "in
--              combat" (attacked or got hit recently) and out afterwards.
--   2. ACTION  one-shot keyframed poses: attacks, hit flinches, emotes.
--              On the joints an action uses, it smoothly takes over from the
--              stance (and hands back at the end); other joints keep the stance.
--
-- We rotate each Motor6D's C0 on top of its rest value. Roblox's walk/idle
-- animations drive Motor6D.Transform, a separate property, so everything here
-- LAYERS ON TOP of walking instead of fighting it.
--
-- Every client animates every nearby character itself (the server only says
-- "X used move Y"). C0 edits made on a client don't replicate, so this costs
-- no network traffic per frame.
--
-- If a move or emote has an `animationId`, that uploaded animation plays instead.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Animations = require(Shared.Config.Animations)
local PoseMath = require(Shared.PoseMath)

local PoseAnimator = {}

local R15_PARTS = PoseMath.R15_PARTS

-- R6 approximation: forward swings of shoulders and hips only.
local R6_JOINTS = {
	RightShoulder = { "Torso", "Right Shoulder", 1 },
	LeftShoulder = { "Torso", "Left Shoulder", -1 },
	RightHip = { "Torso", "Right Hip", 1 },
	LeftHip = { "Torso", "Left Hip", -1 },
}

local ZERO = Vector3.zero
local FADE_IN = 0.06 -- seconds for an action to take a joint over from the stance
local FADE_OUT = 0.1 -- seconds to hand it back
local STANCE = Animations.Stance

type Entry = { motor: Motor6D, original: CFrame, r6: boolean, sign: number }
type Action = { pose: any, start: number, cancelOnMove: boolean }
type State = {
	character: Model,
	entries: { [string]: Entry },
	action: Action?,
	stanceWeight: number,
	combatUntil: number,
	applied: { [string]: boolean },
}

local states: { [Model]: State } = {}
local tracks: { [Instance]: { [string]: AnimationTrack } } = setmetatable({}, { __mode = "k" })
local loop: RBXScriptConnection? = nil

-- ===== Helpers =====

local jointSet = PoseMath.jointSet
local sample = PoseMath.sample

local function resolve(state: State, joint: string): Entry?
	local cached = state.entries[joint]
	if cached and cached.motor.Parent then
		return cached
	end
	local character = state.character
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local isR6 = humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R6
	local motor, sign = nil, 1
	if isR6 then
		local map = R6_JOINTS[joint]
		if map then
			local part = character:FindFirstChild(map[1])
			motor = part and part:FindFirstChild(map[2])
			sign = map[3]
		end
	else
		local partName = R15_PARTS[joint]
		local part = partName and character:FindFirstChild(partName)
		motor = part and part:FindFirstChild(joint)
	end
	if not motor or not motor:IsA("Motor6D") then
		-- Not on this rig (R6 has no elbows), or not streamed in yet: try again next frame.
		return nil
	end
	local entry: Entry = { motor = motor, original = motor.C0, r6 = isR6, sign = sign }
	state.entries[joint] = entry
	return entry
end

local function toCFrame(entry: Entry, angles: Vector3): CFrame
	if entry.r6 then
		return CFrame.Angles(0, 0, math.rad(angles.X) * entry.sign)
	end
	return PoseMath.toCFrame(angles)
end

local function restoreJoint(state: State, joint: string)
	local entry = state.entries[joint]
	if entry and entry.motor.Parent then
		entry.motor.C0 = entry.original
	end
	state.applied[joint] = nil
end

local function restoreAll(state: State)
	for joint in state.applied do
		restoreJoint(state, joint)
	end
end

local function getState(character: Model): State
	local state = states[character]
	if not state then
		state = {
			character = character,
			entries = {},
			action = nil,
			stanceWeight = 0,
			combatUntil = 0,
			applied = {},
		}
		states[character] = state
	end
	return state
end

-- ===== Per-frame update =====

local function isDisabled(character: Model): boolean
	if character:GetAttribute("Ragdolled") then
		return true
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health <= 0
end

local function horizontalSpeed(character: Model): number
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local v = root.AssemblyLinearVelocity
		return Vector3.new(v.X, 0, v.Z).Magnitude
	end
	return 0
end

local function updateState(state: State, now: number, dt: number): boolean
	local character = state.character
	if not character.Parent then
		return false -- gone; nothing to restore
	end
	if isDisabled(character) then
		restoreAll(state)
		state.action = nil
		state.stanceWeight = 0
		return false
	end

	-- Stance weight eases toward 1 while in combat, 0 otherwise.
	local target = if STANCE.enabled and now < state.combatUntil then 1 else 0
	local step = dt * STANCE.blendSpeed
	if state.stanceWeight < target then
		state.stanceWeight = math.min(target, state.stanceWeight + step)
	else
		state.stanceWeight = math.max(target, state.stanceWeight - step)
	end
	local w = state.stanceWeight

	-- Action lifetime.
	local action = state.action
	local t = 0
	if action then
		t = now - action.start
		if t >= action.pose.duration or (action.cancelOnMove and t > 0.15 and horizontalSpeed(character) > 3) then
			state.action = nil
			action = nil
		end
	end

	-- Work out the angles for every joint either layer touches.
	local wanted: { [string]: Vector3 } = {}
	if w > 0 then
		for joint, angles in STANCE.joints do
			wanted[joint] = angles * w
		end
		local bob = STANCE.bob
		if bob then
			local offset = math.sin(now * bob.speed) * bob.amplitude * w
			local base = wanted[bob.joint] or ZERO
			local delta = if bob.axis == "X" then Vector3.new(offset, 0, 0) else Vector3.new(0, offset, 0)
			wanted[bob.joint] = base + delta
		end
	end
	if action then
		local duration = action.pose.duration
		local alpha = math.clamp(math.min(t / FADE_IN, (duration - t) / FADE_OUT), 0, 1)
		for joint in jointSet(action.pose) do
			local under = wanted[joint] or ZERO
			wanted[joint] = under:Lerp(sample(action.pose, t, joint), alpha)
		end
	end

	-- Apply, and put back any joint we touched last frame but not this one.
	for joint in state.applied do
		if not wanted[joint] then
			restoreJoint(state, joint)
		end
	end
	for joint, angles in wanted do
		local entry = resolve(state, joint)
		if entry then
			entry.motor.C0 = entry.original * toCFrame(entry, angles)
			state.applied[joint] = true
		end
	end

	-- Keep the state alive while anything is happening or fading.
	return action ~= nil or w > 0 or now < state.combatUntil
end

local function step(dt: number)
	local now = os.clock()
	for character, state in states do
		if not updateState(state, now, dt) then
			restoreAll(state)
			states[character] = nil
		end
	end
	if next(states) == nil and loop then
		loop:Disconnect()
		loop = nil
	end
end

local function ensureLoop()
	if not loop then
		loop = RunService.RenderStepped:Connect(step)
	end
end

-- ===== Public API =====

-- Play a procedural pose as the character's current action.
function PoseAnimator.playPose(character: Model, pose, cancelOnMove: boolean?)
	if not character or not pose or isDisabled(character) then
		return
	end
	local state = getState(character)
	state.action = { pose = pose, start = os.clock(), cancelOnMove = cancelOnMove == true }
	ensureLoop()
end

-- Raise the guard for a few seconds (refreshed by every attack/hit).
function PoseAnimator.markCombat(character: Model)
	if not character or not STANCE.enabled then
		return
	end
	local state = getState(character)
	state.combatUntil = os.clock() + STANCE.combatSeconds
	ensureLoop()
end

local function playAnimation(character: Model, animationId: string): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return false
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
		local ok, loaded = pcall(animator.LoadAnimation, animator, animation)
		if not ok or not loaded then
			warn("[PoseAnimator] Could not load animation", animationId, loaded)
			return false
		end
		track = loaded
		track.Priority = Enum.AnimationPriority.Action
		cache[animationId] = track
	end
	track:Play(0.05)
	return true
end

-- Attacks. variant 2 = the alternate (left) punch.
function PoseAnimator.playMove(character: Model, move, variant: number?)
	PoseAnimator.markCombat(character)
	if move.animationId and move.animationId ~= "" and playAnimation(character, move.animationId) then
		return
	end
	local pose = if variant == 2 and move.poseAlt then move.poseAlt else move.pose
	PoseAnimator.playPose(character, pose, false)
end

-- Flinch when hit by another player.
function PoseAnimator.playHitReact(character: Model)
	PoseAnimator.markCombat(character)
	local react = Animations.HitReact
	if react.animationId ~= "" and playAnimation(character, react.animationId) then
		return
	end
	PoseAnimator.playPose(character, react.pose, false)
end

-- Emotes by id (see Config/Animations).
function PoseAnimator.playEmote(character: Model, emoteId: string): boolean
	local emote = Animations.EmotesById[emoteId]
	if not emote then
		return false
	end
	if emote.animationId ~= "" and playAnimation(character, emote.animationId) then
		return true
	end
	PoseAnimator.playPose(character, emote.pose, emote.cancelOnMove)
	return true
end

return PoseAnimator
