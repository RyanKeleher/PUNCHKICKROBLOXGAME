-- Training targets: things you punch for XP and coins.
--
--   model      "bag"   = hanging punching bag (on a stand)
--              "dummy" = a humanoid-shaped rig that ragdolls when knocked out
--   scale      size multiplier for dummies
--   hp         health per spawn
--   xpPerHit   XP for every hit that lands
--   koXp       bonus XP for the knockout blow
--   koCoins    coins for the knockout blow
--   respawn    seconds until a new one appears
--   color / accent  look

local Targets = {
	bag = {
		name = "Punching Bag",
		model = "bag",
		hp = 40,
		xpPerHit = 2,
		koXp = 10,
		koCoins = 4,
		respawn = 4,
		color = Color3.fromRGB(170, 40, 40),
		accent = Color3.fromRGB(60, 60, 60),
	},
	straw_dummy = {
		name = "Straw Dummy",
		model = "dummy",
		scale = 1,
		hp = 90,
		xpPerHit = 3,
		koXp = 25,
		koCoins = 10,
		respawn = 6,
		color = Color3.fromRGB(215, 185, 110),
		accent = Color3.fromRGB(150, 110, 60),
	},
	heavy_bag = {
		name = "Heavy Bag",
		model = "bag",
		hp = 260,
		xpPerHit = 7,
		koXp = 60,
		koCoins = 25,
		respawn = 6,
		color = Color3.fromRGB(30, 30, 35),
		accent = Color3.fromRGB(200, 160, 40),
	},
	dojo_dummy = {
		name = "Wooden Sparring Dummy",
		model = "dummy",
		scale = 1.15,
		hp = 450,
		xpPerHit = 10,
		koXp = 110,
		koCoins = 45,
		respawn = 8,
		color = Color3.fromRGB(140, 90, 50),
		accent = Color3.fromRGB(90, 55, 30),
	},
	robot = {
		name = "Training Bot",
		model = "dummy",
		scale = 1.3,
		hp = 1600,
		xpPerHit = 24,
		koXp = 400,
		koCoins = 160,
		respawn = 10,
		color = Color3.fromRGB(150, 160, 175),
		accent = Color3.fromRGB(40, 200, 255),
	},
	titan_bag = {
		name = "Titan Bag",
		model = "bag",
		hp = 2400,
		xpPerHit = 30,
		koXp = 500,
		koCoins = 200,
		respawn = 10,
		color = Color3.fromRGB(40, 70, 160),
		accent = Color3.fromRGB(230, 230, 230),
	},
	magma_brute = {
		name = "Magma Brute",
		model = "dummy",
		scale = 1.6,
		hp = 6000,
		xpPerHit = 60,
		koXp = 1500,
		koCoins = 600,
		respawn = 14,
		color = Color3.fromRGB(70, 35, 30),
		accent = Color3.fromRGB(255, 110, 20),
	},
	lava_golem = {
		name = "Lava Golem (Boss)",
		model = "dummy",
		scale = 3,
		hp = 60000,
		xpPerHit = 150,
		koXp = 20000,
		koCoins = 8000,
		respawn = 90,
		color = Color3.fromRGB(45, 25, 20),
		accent = Color3.fromRGB(255, 70, 0),
	},
}

for id, def in Targets do
	def.id = id
	def.scale = def.scale or 1
end

return Targets
