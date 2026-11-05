-- Studio-only test helper: scatters a few item stacks near the spawn so you can
-- test pickup, stacking, splitting and the "inventory full" path.
-- Main.server only calls this when RunService:IsStudio() is true, so it can
-- never run in a live server.

local WorldItemService = require(script.Parent.Parent.Services.WorldItemService)

local DevSpawner = {}

local TEST_DROPS = {
	{ { id = "wood", count = 750 } },
	{ { id = "wood", count = 600 } }, -- 750 + 600 > 1000: tests overflow into a 2nd stack
	{ { id = "stone", count = 300 } },
	{ { id = "metal_ore", count = 120 } },
	{ { id = "cloth", count = 40 } },
	{ { id = "rock", count = 1 } },
	{ { id = "wild_berries", count = 12 } },
	-- A multi-stack bag, like the death bags coming in Phase 4:
	{ { id = "sulfur_ore", count = 200 }, { id = "charcoal", count = 50 }, { id = "raw_meat", count = 5 } },
}

function DevSpawner.run()
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local center = if spawn then spawn.Position else Vector3.new(0, 1, 0)

	for i, stacks in TEST_DROPS do
		local angle = (i / #TEST_DROPS) * math.pi * 2
		local offset = Vector3.new(math.cos(angle) * 10, 0, math.sin(angle) * 10)
		local origin = center + offset + Vector3.new(0, 20, 0)
		local hit = workspace:Raycast(origin, Vector3.new(0, -60, 0))
		local position = if hit then hit.Position else center + offset
		WorldItemService.spawnDrop(stacks, position)
	end

	print("[DevSpawner] Spawned", #TEST_DROPS, "test drops around spawn")
end

return DevSpawner
