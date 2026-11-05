--!strict
-- Global tuning values shared by server and client.
-- Balance lives in data (here + ItemDefinitions), not in service logic.

local Config = {}

Config.Inventory = {
	HotbarSize = 6, -- slots 1..6 are the hotbar
	MainSize = 24, -- slots 7..30 are the main grid
}

Config.StarterKit = {
	{ id = "rock", count = 1, slot = 1 },
	{ id = "torch", count = 1, slot = 2 },
}

Config.WorldItems = {
	PickupRange = 8, -- studs; ProximityPrompt range AND server re-check
	DespawnSeconds = 300, -- dropped items vanish after 5 minutes
	MaxActive = 300, -- hard cap on dropped items in the server (oldest evicted)
}

-- Token-bucket rate limits per player, per remote: rate = tokens/sec, burst = bucket size.
Config.RateLimits = {
	InventoryMove = { rate = 15, burst = 25 },
	InventorySplit = { rate = 6, burst = 10 },
	InventoryDrop = { rate = 5, burst = 8 },
	EquipSlot = { rate = 10, burst = 15 },
	RequestSync = { rate = 0.5, burst = 2 },
	Pickup = { rate = 6, burst = 8 },
}

Config.UI = {
	HidePlayerList = true, -- frees up Tab for the inventory, survival-game convention
}

Config.Dev = {
	-- Only ever runs inside Roblox Studio (RunService:IsStudio()).
	SpawnTestItems = true,
}

return Config
