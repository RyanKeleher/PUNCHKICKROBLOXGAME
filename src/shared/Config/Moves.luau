-- Every attack in the game, as data.
--
-- Fields
--   id, name, description, order      identity + menu sorting
--   basic          true = the always-available click attack (not in the 4-slot loadout)
--   unlockLevel    level required to buy it
--   price          coins to unlock
--   cooldown       seconds (shortened by Agility)
--   damage         base damage (multiplied by Power + level)
--   hitDelay       seconds between pressing and the hit landing (wind-up)
--   hitbox         { kind = "box", size, forward } in front of you, or { kind = "radius", radius } around you
--   maxTargets     how many things one use can hit
--   knockback      { forward, up } studs/sec applied to what you hit
--   ragdoll        seconds a hit PLAYER stays ragdolled (0 = just a shove)
--   dash           optional { speed, duration }: you lunge forward when using it
--   shake          camera shake strength for the attacker (0..1)
--   shockwave      draw an expanding ring (for radius moves)
--   color          effect colour
--   short          2-4 letter label for the hotbar
--   animationId    optional uploaded animation (rbxassetid://...). When set it is
--                  played instead of the procedural pose below.
--   pose / poseAlt procedural animation: keyframes of joint rotations (degrees,
--                  applied on top of the rig's rest pose). Joint names use R15
--                  names; R6 rigs get an approximation for shoulders and hips.
--                  For R15: +X on a shoulder/hip swings the limb forward,
--                  +X on an elbow bends it, -X on a knee bends it back,
--                  +Z on a right shoulder/hip lifts it out sideways (-Z for left),
--                  Waist: -X leans forward, +X leans back, +Y twists the right
--                  shoulder forward (use it for right-hand punches).

local Moves = {}

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local list = {
	{
		id = "punch",
		name = "Punch",
		description = "A quick jab. Hold click to keep swinging.",
		order = 1,
		basic = true,
		unlockLevel = 1,
		price = 0,
		cooldown = 0.35,
		damage = 8,
		hitDelay = 0.08,
		hitbox = { kind = "box", size = v(5, 5, 5), forward = 3 },
		maxTargets = 2,
		knockback = { forward = 8, up = 4 },
		ragdoll = 0,
		shake = 0,
		color = Color3.fromRGB(255, 230, 140),
		short = "PCH",
		animationId = "",
		pose = {
			duration = 0.26,
			frames = {
				{ t = 0, joints = {} },
				{ t = 0.07, joints = { RightShoulder = v(95, 0, 0), RightElbow = v(5, 0, 0), Waist = v(0, 25, 0), LeftShoulder = v(25, 0, 0) } },
				{ t = 0.26, joints = {} },
			},
		},
		poseAlt = {
			duration = 0.26,
			frames = {
				{ t = 0, joints = {} },
				{ t = 0.07, joints = { LeftShoulder = v(95, 0, 0), LeftElbow = v(5, 0, 0), Waist = v(0, -25, 0), RightShoulder = v(25, 0, 0) } },
				{ t = 0.26, joints = {} },
			},
		},
	},
	{
		id = "kick",
		name = "Front Kick",
		description = "A solid kick that shoves enemies back.",
		order = 2,
		unlockLevel = 1,
		price = 0,
		cooldown = 0.9,
		damage = 18,
		hitDelay = 0.16,
		hitbox = { kind = "box", size = v(5, 5, 6), forward = 3.5 },
		maxTargets = 2,
		knockback = { forward = 30, up = 10 },
		ragdoll = 0.8,
		shake = 0.1,
		color = Color3.fromRGB(140, 220, 255),
		short = "KCK",
		animationId = "",
		pose = {
			duration = 0.45,
			frames = {
				{ t = 0, joints = {} },
				{ t = 0.08, joints = { RightHip = v(45, 0, 0), RightKnee = v(-80, 0, 0), Waist = v(5, 0, 0) } },
				{ t = 0.18, joints = { RightHip = v(95, 0, 0), RightKnee = v(0, 0, 0), Waist = v(15, 0, 0), LeftShoulder = v(-20, 0, 0), RightShoulder = v(-20, 0, 0) } },
				{ t = 0.45, joints = {} },
			},
		},
	},
	{
		id = "uppercut",
		name = "Uppercut",
		description = "Launches the target into the air.",
		order = 3,
		unlockLevel = 5,
		price = 250,
		cooldown = 3,
		damage = 32,
		hitDelay = 0.2,
		hitbox = { kind = "box", size = v(5, 7, 5), forward = 3 },
		maxTargets = 2,
		knockback = { forward = 10, up = 70 },
		ragdoll = 1.6,
		shake = 0.25,
		color = Color3.fromRGB(255, 170, 60),
		short = "UPC",
		animationId = "",
		pose = {
			duration = 0.55,
			frames = {
				{ t = 0, joints = {} },
				{ t = 0.12, joints = { RightShoulder = v(-20, 0, 0), RightElbow = v(95, 0, 0), Waist = v(-20, -15, 0), RightHip = v(20, 0, 0), RightKnee = v(-30, 0, 0) } },
				{ t = 0.24, joints = { RightShoulder = v(170, 0, 0), RightElbow = v(15, 0, 0), Waist = v(20, 15, 0) } },
				{ t = 0.55, joints = {} },
			},
		},
	},
	{
		id = "roundhouse",
		name = "Roundhouse",
		description = "A spinning kick that hits everything around you.",
		order = 4,
		unlockLevel = 10,
		price = 800,
		cooldown = 5,
		damage = 36,
		hitDelay = 0.25,
		hitbox = { kind = "radius", radius = 9 },
		maxTargets = 6,
		knockback = { forward = 45, up = 20 },
		ragdoll = 1.5,
		shake = 0.3,
		shockwave = true,
		color = Color3.fromRGB(120, 255, 160),
		short = "RND",
		animationId = "",
		pose = {
			duration = 0.55,
			frames = {
				{ t = 0, joints = {} },
				{ t = 0.15, joints = { Waist = v(0, 150, 0), RightHip = v(10, 0, 80), LeftShoulder = v(0, 0, -60), RightShoulder = v(0, 0, 60) } },
				{ t = 0.3, joints = { Waist = v(0, 300, 0), RightHip = v(10, 0, 85), LeftShoulder = v(0, 0, -60), RightShoulder = v(0, 0, 60) } },
				{ t = 0.55, joints = { Waist = v(0, 360, 0) } },
			},
		},
	},
	{
		id = "dropkick",
		name = "Dropkick",
		description = "Lunge forward feet-first and send them flying.",
		order = 5,
		unlockLevel = 15,
		price = 2000,
		cooldown = 6,
		damage = 50,
		hitDelay = 0.3,
		hitbox = { kind = "box", size = v(6, 6, 7), forward = 3 },
		maxTargets = 3,
		knockback = { forward = 85, up = 25 },
		ragdoll = 2,
		dash = { speed = 70, duration = 0.28 },
		shake = 0.35,
		color = Color3.fromRGB(255, 90, 90),
		short = "DRP",
		animationId = "",
		pose = {
			duration = 0.6,
			frames = {
				{ t = 0, joints = {} },
				{ t = 0.12, joints = { RightHip = v(90, 0, 0), LeftHip = v(80, 0, 0), Waist = v(35, 0, 0), RightShoulder = v(-40, 0, 0), LeftShoulder = v(-40, 0, 0) } },
				{ t = 0.4, joints = { RightHip = v(90, 0, 0), LeftHip = v(80, 0, 0), Waist = v(35, 0, 0), RightShoulder = v(-40, 0, 0), LeftShoulder = v(-40, 0, 0) } },
				{ t = 0.6, joints = {} },
			},
		},
	},
	{
		id = "groundpound",
		name = "Ground Pound",
		description = "Slam the floor. Everyone nearby gets launched.",
		order = 6,
		unlockLevel = 22,
		price = 5000,
		cooldown = 8,
		damage = 60,
		hitDelay = 0.35,
		hitbox = { kind = "radius", radius = 14 },
		maxTargets = 10,
		knockback = { forward = 30, up = 80 },
		ragdoll = 2.2,
		shake = 0.6,
		shockwave = true,
		color = Color3.fromRGB(200, 140, 255),
		short = "GND",
		animationId = "",
		pose = {
			duration = 0.7,
			frames = {
				{ t = 0, joints = {} },
				{ t = 0.18, joints = { RightShoulder = v(175, 0, 0), LeftShoulder = v(175, 0, 0), Waist = v(15, 0, 0) } },
				{ t = 0.33, joints = { RightShoulder = v(50, 0, 0), LeftShoulder = v(50, 0, 0), Waist = v(-35, 0, 0), RightHip = v(40, 0, 0), RightKnee = v(-60, 0, 0), LeftHip = v(40, 0, 0), LeftKnee = v(-60, 0, 0) } },
				{ t = 0.7, joints = {} },
			},
		},
	},
	{
		id = "megapunch",
		name = "Mega Punch",
		description = "Wind up a devastating punch. Huge damage and knockback.",
		order = 7,
		unlockLevel = 30,
		price = 12000,
		cooldown = 12,
		damage = 140,
		hitDelay = 0.4,
		hitbox = { kind = "box", size = v(7, 7, 9), forward = 4.5 },
		maxTargets = 4,
		knockback = { forward = 140, up = 40 },
		ragdoll = 3,
		shake = 0.8,
		color = Color3.fromRGB(255, 60, 200),
		short = "MEGA",
		animationId = "",
		pose = {
			duration = 0.75,
			frames = {
				{ t = 0, joints = {} },
				{ t = 0.3, joints = { RightShoulder = v(-45, 0, 0), RightElbow = v(85, 0, 0), Waist = v(0, -40, 0), LeftShoulder = v(60, 0, 0) } },
				{ t = 0.42, joints = { RightShoulder = v(95, 0, 0), RightElbow = v(0, 0, 0), Waist = v(10, 40, 0), LeftShoulder = v(-30, 0, 0) } },
				{ t = 0.75, joints = {} },
			},
		},
	},
	{
		id = "cyclone",
		name = "Cyclone Kick",
		description = "Spin like a tornado and blast everything away.",
		order = 8,
		unlockLevel = 40,
		price = 30000,
		cooldown = 10,
		damage = 110,
		hitDelay = 0.45,
		hitbox = { kind = "radius", radius = 13 },
		maxTargets = 10,
		knockback = { forward = 110, up = 50 },
		ragdoll = 2.5,
		shake = 0.7,
		shockwave = true,
		color = Color3.fromRGB(90, 255, 255),
		short = "CYC",
		animationId = "",
		pose = {
			duration = 0.8,
			frames = {
				{ t = 0, joints = {} },
				{ t = 0.2, joints = { Waist = v(0, 240, 0), RightHip = v(0, 0, 85), LeftHip = v(0, 0, -30), RightShoulder = v(0, 0, 80), LeftShoulder = v(0, 0, -80) } },
				{ t = 0.45, joints = { Waist = v(0, 540, 0), RightHip = v(0, 0, 85), LeftHip = v(0, 0, -30), RightShoulder = v(0, 0, 80), LeftShoulder = v(0, 0, -80) } },
				{ t = 0.8, joints = { Waist = v(0, 720, 0) } },
			},
		},
	},
}

Moves.list = list
Moves.byId = {}
for _, move in list do
	assert(Moves.byId[move.id] == nil, "Duplicate move id " .. move.id)
	Moves.byId[move.id] = move
end
table.sort(list, function(a, b)
	return a.order < b.order
end)

Moves.BASIC_ID = "punch"

return Moves
