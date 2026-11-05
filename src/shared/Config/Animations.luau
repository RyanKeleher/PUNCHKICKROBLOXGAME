-- Character animations that aren't attacks: fighting stance, hit reactions,
-- emotes, and optional replacements for Roblox's default walk/run/idle.
--
-- Pose format is the same as Config/Moves (degrees per joint, R15 names):
--   +X on a shoulder/hip = swing forward      -X on a knee = bend back
--   +X on an elbow = bend                      +Z right / -Z left shoulder = raise sideways
--   Waist: -X lean forward, +X lean back, +Y twist right shoulder forward
--   Neck:  -X look down, +X look up
--   With an arm raised sideways (shoulder Z = ±90), elbow Z (same sign) bends the forearm UP.
--
-- Any entry can also take an `animationId` (rbxassetid://...) from an animation
-- you published; it then plays that instead of the procedural pose.
-- Use Dev/AnimationExporter to turn these poses into Animation Editor files.

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local Animations = {}

-- Guard stance, blended in while you're fighting (you attacked or got hit
-- recently) and out again when things calm down.
Animations.Stance = {
	enabled = true,
	combatSeconds = 4, -- how long after the last hit the guard stays up
	blendSpeed = 6, -- how fast it blends in/out (per second)
	joints = {
		RightShoulder = v(55, 0, -12),
		RightElbow = v(105, 0, 0),
		LeftShoulder = v(70, 0, 12),
		LeftElbow = v(110, 0, 0),
		Waist = v(-4, -14, 0),
	},
	-- Subtle "bounce" so the guard looks alive: added on top, in degrees.
	bob = { joint = "Waist", axis = "X", amplitude = 2.5, speed = 9 },
}

-- Played on a character when it takes a hit from another player.
Animations.HitReact = {
	animationId = "",
	pose = {
		duration = 0.35,
		frames = {
			{ t = 0, joints = {} },
			{ t = 0.07, joints = { Waist = v(18, 8, 0), Neck = v(22, 0, 0), RightShoulder = v(35, 0, 30), LeftShoulder = v(35, 0, -30) } },
			{ t = 0.35, joints = {} },
		},
	},
}

-- Emotes. `key` is the keyboard shortcut (the emote panel works everywhere).
-- `cancelOnMove` stops the emote as soon as the character starts walking.
Animations.Emotes = {
	{
		id = "flex",
		name = "Flex",
		key = Enum.KeyCode.Five,
		cancelOnMove = true,
		animationId = "",
		pose = {
			duration = 1.6,
			frames = {
				{ t = 0, joints = {} },
				{ t = 0.25, joints = { RightShoulder = v(0, 0, 90), RightElbow = v(0, 0, 100), LeftShoulder = v(0, 0, -90), LeftElbow = v(0, 0, -100), Waist = v(6, 0, 0) } },
				{ t = 0.6, joints = { RightShoulder = v(0, 0, 85), RightElbow = v(0, 0, 120), LeftShoulder = v(0, 0, -85), LeftElbow = v(0, 0, -120), Waist = v(10, 0, 0), Neck = v(8, 0, 0) } },
				{ t = 1.3, joints = { RightShoulder = v(0, 0, 85), RightElbow = v(0, 0, 120), LeftShoulder = v(0, 0, -85), LeftElbow = v(0, 0, -120), Waist = v(10, 0, 0), Neck = v(8, 0, 0) } },
				{ t = 1.6, joints = {} },
			},
		},
	},
	{
		id = "taunt",
		name = "Taunt",
		key = Enum.KeyCode.Six,
		cancelOnMove = true,
		animationId = "",
		pose = {
			duration = 1.6,
			frames = {
				{ t = 0, joints = {} },
				{ t = 0.2, joints = { RightShoulder = v(75, 0, 0), RightElbow = v(20, 0, 0), Waist = v(4, 10, 0), Neck = v(6, 0, 0) } },
				{ t = 0.45, joints = { RightShoulder = v(75, 0, 0), RightElbow = v(95, 0, 0), Waist = v(4, 10, 0), Neck = v(6, 0, 0) } },
				{ t = 0.7, joints = { RightShoulder = v(75, 0, 0), RightElbow = v(20, 0, 0), Waist = v(4, 10, 0), Neck = v(6, 0, 0) } },
				{ t = 0.95, joints = { RightShoulder = v(75, 0, 0), RightElbow = v(95, 0, 0), Waist = v(4, 10, 0), Neck = v(6, 0, 0) } },
				{ t = 1.2, joints = { RightShoulder = v(75, 0, 0), RightElbow = v(20, 0, 0), Waist = v(4, 10, 0), Neck = v(6, 0, 0) } },
				{ t = 1.6, joints = {} },
			},
		},
	},
	{
		id = "bow",
		name = "Bow",
		key = Enum.KeyCode.Seven,
		cancelOnMove = true,
		animationId = "",
		pose = {
			duration = 1.5,
			frames = {
				{ t = 0, joints = {} },
				{ t = 0.4, joints = { Waist = v(-50, 0, 0), Neck = v(-20, 0, 0), RightShoulder = v(10, 0, 0), LeftShoulder = v(10, 0, 0) } },
				{ t = 1.0, joints = { Waist = v(-50, 0, 0), Neck = v(-20, 0, 0), RightShoulder = v(10, 0, 0), LeftShoulder = v(10, 0, 0) } },
				{ t = 1.5, joints = {} },
			},
		},
	},
	{
		id = "victory",
		name = "Victory",
		key = Enum.KeyCode.Eight,
		cancelOnMove = true,
		animationId = "",
		pose = {
			duration = 1.8,
			frames = {
				{ t = 0, joints = {} },
				{ t = 0.2, joints = { RightShoulder = v(165, 0, 20), LeftShoulder = v(165, 0, -20), RightElbow = v(10, 0, 0), LeftElbow = v(10, 0, 0), Waist = v(10, 0, 0), Neck = v(15, 0, 0) } },
				{ t = 0.45, joints = { RightShoulder = v(150, 0, 25), LeftShoulder = v(150, 0, -25), RightElbow = v(60, 0, 0), LeftElbow = v(60, 0, 0), Waist = v(10, 0, 0), Neck = v(15, 0, 0) } },
				{ t = 0.7, joints = { RightShoulder = v(170, 0, 20), LeftShoulder = v(170, 0, -20), RightElbow = v(5, 0, 0), LeftElbow = v(5, 0, 0), Waist = v(12, 0, 0), Neck = v(18, 0, 0) } },
				{ t = 0.95, joints = { RightShoulder = v(150, 0, 25), LeftShoulder = v(150, 0, -25), RightElbow = v(60, 0, 0), LeftElbow = v(60, 0, 0), Waist = v(10, 0, 0), Neck = v(15, 0, 0) } },
				{ t = 1.3, joints = { RightShoulder = v(170, 0, 20), LeftShoulder = v(170, 0, -20), RightElbow = v(5, 0, 0), LeftElbow = v(5, 0, 0), Waist = v(12, 0, 0), Neck = v(18, 0, 0) } },
				{ t = 1.8, joints = {} },
			},
		},
	},
}

Animations.EmotesById = {}
for _, emote in Animations.Emotes do
	assert(Animations.EmotesById[emote.id] == nil, "Duplicate emote id " .. emote.id)
	Animations.EmotesById[emote.id] = emote
end

-- Played automatically for everyone nearby to see.
Animations.Auto = {
	LevelUp = "flex",
	PlayerKO = "victory",
}

-- Replace Roblox's default movement animations. Leave "" to keep the default.
-- Paste ids of animations you own or published (rbxassetid://123...).
Animations.Movement = {
	idle = "",
	walk = "",
	run = "",
	jump = "",
	fall = "",
	climb = "",
}

return Animations
