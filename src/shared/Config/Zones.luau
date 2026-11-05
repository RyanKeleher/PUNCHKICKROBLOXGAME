-- The world is a set of floating platforms ("zones") linked by bridges.
-- Higher zones need higher levels and hold tougher, more rewarding targets.
--
--   center      X/Z of the platform centre (Y comes from GameConfig.World.Height)
--   size        X/Z size of the platform
--   minLevel    level needed to enter (the server enforces this)
--   pvp         true = players can hit each other here
--   targets     { type = <Targets id>, count, ring = 0..1 (distance from centre) }
--   theme       floor + trim colours and material

local Zones = {
	{
		id = "gym",
		name = "Starter Gym",
		center = Vector3.new(0, 0, 0),
		size = Vector3.new(150, 0, 150),
		minLevel = 1,
		pvp = false,
		theme = { floor = Color3.fromRGB(70, 75, 90), trim = Color3.fromRGB(255, 200, 60), material = Enum.Material.WoodPlanks },
		targets = {
			{ type = "bag", count = 10, ring = 0.32 },
			{ type = "straw_dummy", count = 6, ring = 0.42 },
		},
	},
	{
		id = "arena",
		name = "Brawl Arena",
		center = Vector3.new(0, 0, 200),
		size = Vector3.new(120, 0, 120),
		minLevel = 3,
		pvp = true,
		theme = { floor = Color3.fromRGB(60, 25, 30), trim = Color3.fromRGB(255, 60, 60), material = Enum.Material.Concrete },
		targets = {},
	},
	{
		id = "dojo",
		name = "Mountain Dojo",
		center = Vector3.new(200, 0, 0),
		size = Vector3.new(150, 0, 150),
		minLevel = 8,
		pvp = false,
		theme = { floor = Color3.fromRGB(150, 110, 70), trim = Color3.fromRGB(200, 40, 40), material = Enum.Material.Wood },
		targets = {
			{ type = "heavy_bag", count = 8, ring = 0.32 },
			{ type = "dojo_dummy", count = 6, ring = 0.42 },
		},
	},
	{
		id = "rooftop",
		name = "Neon Rooftop",
		center = Vector3.new(400, 0, 0),
		size = Vector3.new(150, 0, 150),
		minLevel = 18,
		pvp = false,
		theme = { floor = Color3.fromRGB(35, 35, 45), trim = Color3.fromRGB(60, 220, 255), material = Enum.Material.Metal },
		targets = {
			{ type = "titan_bag", count = 6, ring = 0.3 },
			{ type = "robot", count = 6, ring = 0.42 },
		},
	},
	{
		id = "volcano",
		name = "Volcano Crater",
		center = Vector3.new(600, 0, 0),
		size = Vector3.new(170, 0, 170),
		minLevel = 30,
		pvp = false,
		theme = { floor = Color3.fromRGB(45, 30, 28), trim = Color3.fromRGB(255, 90, 20), material = Enum.Material.Basalt },
		targets = {
			{ type = "magma_brute", count = 6, ring = 0.38 },
			{ type = "lava_golem", count = 1, ring = 0 },
		},
	},
}

-- Bridges between zones (pairs of zone ids). Bridges are axis-aligned, so
-- connected zones must share an X or Z centre coordinate.
local Connections = {
	{ "gym", "dojo" },
	{ "dojo", "rooftop" },
	{ "rooftop", "volcano" },
	{ "gym", "arena" },
}

local byId = {}
for _, zone in Zones do
	assert(byId[zone.id] == nil, "Duplicate zone id " .. zone.id)
	byId[zone.id] = zone
end

return {
	list = Zones,
	byId = byId,
	connections = Connections,
}
