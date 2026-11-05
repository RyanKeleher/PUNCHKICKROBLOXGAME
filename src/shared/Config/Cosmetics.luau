-- Cosmetics bought with coins. One item per category can be equipped at once.
--
--   aura    particles around your body           (color, color2)
--   trail   streak behind you when you move      (color, color2)
--   gloves  coloured gloves on both hands        (color, material)
--   title   text under your name tag             (text, color)
--
--   requiresRebirths  only buyable after this many rebirths

local Categories = { "aura", "trail", "gloves", "title" }

local CategoryNames = {
	aura = "Auras",
	trail = "Trails",
	gloves = "Gloves",
	title = "Titles",
}

local list = {
	-- Gloves
	{ id = "gloves_red", category = "gloves", name = "Red Gloves", price = 100, color = Color3.fromRGB(210, 30, 30) },
	{ id = "gloves_blue", category = "gloves", name = "Blue Gloves", price = 100, color = Color3.fromRGB(30, 90, 220) },
	{ id = "gloves_gold", category = "gloves", name = "Golden Gloves", price = 4000, color = Color3.fromRGB(255, 200, 40), material = Enum.Material.Foil },
	{ id = "gloves_neon", category = "gloves", name = "Neon Gloves", price = 9000, color = Color3.fromRGB(60, 255, 200), material = Enum.Material.Neon },
	{ id = "gloves_obsidian", category = "gloves", name = "Obsidian Gloves", price = 25000, color = Color3.fromRGB(25, 20, 35), material = Enum.Material.Glass, requiresRebirths = 1 },

	-- Trails
	{ id = "trail_white", category = "trail", name = "Wind Trail", price = 300, color = Color3.fromRGB(255, 255, 255), color2 = Color3.fromRGB(180, 220, 255) },
	{ id = "trail_fire", category = "trail", name = "Fire Trail", price = 2500, color = Color3.fromRGB(255, 220, 60), color2 = Color3.fromRGB(255, 40, 0) },
	{ id = "trail_toxic", category = "trail", name = "Toxic Trail", price = 6000, color = Color3.fromRGB(180, 255, 40), color2 = Color3.fromRGB(20, 120, 20) },
	{ id = "trail_rainbow", category = "trail", name = "Prism Trail", price = 20000, color = Color3.fromRGB(255, 60, 200), color2 = Color3.fromRGB(60, 200, 255), requiresRebirths = 1 },

	-- Auras
	{ id = "aura_spark", category = "aura", name = "Spark Aura", price = 800, color = Color3.fromRGB(255, 240, 150), color2 = Color3.fromRGB(255, 180, 40) },
	{ id = "aura_frost", category = "aura", name = "Frost Aura", price = 3500, color = Color3.fromRGB(200, 240, 255), color2 = Color3.fromRGB(60, 150, 255) },
	{ id = "aura_inferno", category = "aura", name = "Inferno Aura", price = 12000, color = Color3.fromRGB(255, 200, 50), color2 = Color3.fromRGB(255, 40, 0) },
	{ id = "aura_void", category = "aura", name = "Void Aura", price = 40000, color = Color3.fromRGB(170, 60, 255), color2 = Color3.fromRGB(20, 0, 40), requiresRebirths = 2 },

	-- Titles
	{ id = "title_rookie", category = "title", name = "Rookie", price = 50, text = "Rookie", color = Color3.fromRGB(200, 200, 200) },
	{ id = "title_brawler", category = "title", name = "Brawler", price = 1500, text = "Brawler", color = Color3.fromRGB(255, 140, 60) },
	{ id = "title_champion", category = "title", name = "Champion", price = 15000, text = "Champion", color = Color3.fromRGB(255, 215, 0) },
	{ id = "title_legend", category = "title", name = "Legend", price = 50000, text = "LEGEND", color = Color3.fromRGB(255, 60, 120), requiresRebirths = 3 },
}

local byId = {}
for i, item in list do
	assert(byId[item.id] == nil, "Duplicate cosmetic id " .. item.id)
	assert(CategoryNames[item.category], "Unknown cosmetic category " .. item.category)
	item.requiresRebirths = item.requiresRebirths or 0
	item.order = i
	byId[item.id] = item
end

return {
	Categories = Categories,
	CategoryNames = CategoryNames,
	list = list,
	byId = byId,
}
