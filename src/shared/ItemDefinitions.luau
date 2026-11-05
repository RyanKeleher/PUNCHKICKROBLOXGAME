--!strict
-- Every item in the game is defined here as data. Logic never hard-codes
-- stack sizes, names, or categories; it looks them up by id.
--
-- Fields:
--   id          unique string key (what gets saved / sent over the network)
--   name        display name
--   category    used for sorting, auto-placement (tools go to hotbar), later crafting tabs
--   maxStack    max items per slot
--   short       2-3 letter label drawn on the placeholder icon
--   color       placeholder icon color
--   icon        optional rbxassetid:// image; if set, replaces the placeholder
--   equippable  can be held from the hotbar
--   held        simple visual for the held item (a welded part) until real models exist

export type ItemCategory =
	"Resource"
	| "Tool"
	| "Weapon"
	| "Ammo"
	| "Food"
	| "Medical"
	| "Deployable"
	| "Construction"
	| "Component"
	| "Misc"

export type HeldVisual = {
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	light: boolean?,
}

export type ItemDef = {
	id: string,
	name: string,
	category: ItemCategory,
	maxStack: number,
	description: string,
	short: string,
	color: Color3,
	icon: string?,
	equippable: boolean?,
	held: HeldVisual?,
}

local Items: { [string]: ItemDef } = {}

local function define(def: ItemDef)
	assert(Items[def.id] == nil, "Duplicate item id: " .. def.id)
	assert(def.maxStack >= 1, "maxStack must be >= 1 for " .. def.id)
	Items[def.id] = def
end

-- ===== Starter tools =====
define({
	id = "rock",
	name = "Rock",
	category = "Tool",
	maxStack = 1,
	description = "A fist-sized rock. Slow, but it can chop and mine.",
	short = "RK",
	color = Color3.fromRGB(120, 120, 125),
	equippable = true,
	held = { size = Vector3.new(0.9, 0.8, 0.9), color = Color3.fromRGB(120, 120, 125), material = Enum.Material.Slate },
})

define({
	id = "torch",
	name = "Torch",
	category = "Tool",
	maxStack = 1,
	description = "A burning stick. Lights up the night.",
	short = "TR",
	color = Color3.fromRGB(230, 140, 40),
	equippable = true,
	held = {
		size = Vector3.new(0.3, 2.2, 0.3),
		color = Color3.fromRGB(110, 75, 40),
		material = Enum.Material.Wood,
		light = true,
	},
})

-- ===== Raw resources =====
define({
	id = "wood",
	name = "Wood",
	category = "Resource",
	maxStack = 1000,
	description = "Chopped from trees. Used for building, crafting, and fuel.",
	short = "WD",
	color = Color3.fromRGB(140, 95, 55),
})

define({
	id = "stone",
	name = "Stone",
	category = "Resource",
	maxStack = 1000,
	description = "Mined from rock nodes. Used for tools and stone walls.",
	short = "ST",
	color = Color3.fromRGB(160, 160, 160),
})

define({
	id = "metal_ore",
	name = "Metal Ore",
	category = "Resource",
	maxStack = 1000,
	description = "Smelt in a furnace to get Metal Fragments.",
	short = "MO",
	color = Color3.fromRGB(150, 110, 90),
})

define({
	id = "sulfur_ore",
	name = "Sulfur Ore",
	category = "Resource",
	maxStack = 1000,
	description = "Smelt in a furnace to get Sulfur.",
	short = "SO",
	color = Color3.fromRGB(200, 190, 80),
})

define({
	id = "cloth",
	name = "Cloth",
	category = "Resource",
	maxStack = 1000,
	description = "Gathered from fiber plants. Used for clothing, bags, and bows.",
	short = "CL",
	color = Color3.fromRGB(200, 185, 150),
})

-- ===== Refined resources =====
define({
	id = "metal_fragments",
	name = "Metal Fragments",
	category = "Resource",
	maxStack = 1000,
	description = "Refined metal. Used for better tools and sheet-metal building.",
	short = "MF",
	color = Color3.fromRGB(110, 115, 125),
})

define({
	id = "sulfur",
	name = "Sulfur",
	category = "Resource",
	maxStack = 1000,
	description = "Refined sulfur. A key ingredient in gunpowder.",
	short = "SU",
	color = Color3.fromRGB(240, 225, 60),
})

define({
	id = "charcoal",
	name = "Charcoal",
	category = "Resource",
	maxStack = 1000,
	description = "Left over from burning wood. Used in gunpowder.",
	short = "CH",
	color = Color3.fromRGB(45, 45, 45),
})

-- ===== Food =====
define({
	id = "raw_meat",
	name = "Raw Meat",
	category = "Food",
	maxStack = 20,
	description = "Cook it before eating.",
	short = "RM",
	color = Color3.fromRGB(190, 70, 70),
})

define({
	id = "cooked_meat",
	name = "Cooked Meat",
	category = "Food",
	maxStack = 20,
	description = "Restores a good amount of hunger.",
	short = "CM",
	color = Color3.fromRGB(150, 85, 45),
})

define({
	id = "wild_berries",
	name = "Wild Berries",
	category = "Food",
	maxStack = 20,
	description = "A small snack. Restores a little hunger and thirst.",
	short = "BR",
	color = Color3.fromRGB(120, 50, 140),
})

local ItemDefinitions = {}

ItemDefinitions.Items = Items

function ItemDefinitions.get(id: string): ItemDef?
	return Items[id]
end

function ItemDefinitions.exists(id: any): boolean
	return type(id) == "string" and Items[id] ~= nil
end

return ItemDefinitions
