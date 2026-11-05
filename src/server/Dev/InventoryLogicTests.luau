-- Minimal self-tests for the pure InventoryLogic module. Runs in Studio only
-- (see Main.server). Because InventoryLogic has no Instances or networking,
-- we can test it with plain tables: this is the payoff of keeping logic pure.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InventoryLogic = require(ReplicatedStorage.Shared.InventoryLogic)

local Tests = {}

local ALL = { 1, 2, 3, 4 }

local cases: { { name: string, fn: () -> () } } = {
	{
		name = "add merges into existing stack, then fills empty slots",
		fn = function()
			local s = InventoryLogic.new(4)
			s[2] = { id = "wood", count = 900 }
			local left = InventoryLogic.add(s, "wood", 300, ALL)
			assert(left == 0, "leftover " .. left)
			assert(s[2] and s[2].count == 1000, "slot 2 should be full")
			assert(s[1] and s[1].count == 200, "overflow should go to slot 1")
		end,
	},
	{
		name = "add returns leftover when full",
		fn = function()
			local s = InventoryLogic.new(1)
			local left = InventoryLogic.add(s, "wood", 1500, { 1 })
			assert(left == 500, "expected 500 leftover, got " .. left)
		end,
	},
	{
		name = "move to empty slot",
		fn = function()
			local s = InventoryLogic.new(4)
			s[1] = { id = "stone", count = 5 }
			assert(InventoryLogic.move(s, 1, 3))
			assert(s[1] == false and s[3] and s[3].count == 5)
		end,
	},
	{
		name = "move merges same item and keeps remainder",
		fn = function()
			local s = InventoryLogic.new(4)
			s[1] = { id = "wood", count = 600 }
			s[2] = { id = "wood", count = 700 }
			InventoryLogic.move(s, 1, 2)
			assert(s[2] and s[2].count == 1000)
			assert(s[1] and s[1].count == 300)
		end,
	},
	{
		name = "move swaps different items",
		fn = function()
			local s = InventoryLogic.new(4)
			s[1] = { id = "wood", count = 1 }
			s[2] = { id = "stone", count = 2 }
			InventoryLogic.move(s, 1, 2)
			assert(s[1] and s[1].id == "stone" and s[2] and s[2].id == "wood")
		end,
	},
	{
		name = "split moves amount into first empty slot",
		fn = function()
			local s = InventoryLogic.new(4)
			s[1] = { id = "cloth", count = 10 }
			assert(InventoryLogic.split(s, 1, 4, ALL))
			assert(s[1] and s[1].count == 6 and s[2] and s[2].count == 4)
		end,
	},
	{
		name = "split rejects amount >= stack size",
		fn = function()
			local s = InventoryLogic.new(4)
			s[1] = { id = "cloth", count = 10 }
			assert(not InventoryLogic.split(s, 1, 10, ALL))
		end,
	},
	{
		name = "take clears slot when emptied",
		fn = function()
			local s = InventoryLogic.new(2)
			s[1] = { id = "stone", count = 3 }
			local taken = InventoryLogic.take(s, 1, 3)
			assert(taken and taken.count == 3 and s[1] == false)
		end,
	},
	{
		name = "count and remove across stacks",
		fn = function()
			local s = InventoryLogic.new(3)
			s[1] = { id = "wood", count = 50 }
			s[3] = { id = "wood", count = 30 }
			assert(InventoryLogic.count(s, "wood") == 80)
			assert(InventoryLogic.remove(s, "wood", 60) == 60)
			assert(InventoryLogic.count(s, "wood") == 20)
		end,
	},
}

function Tests.run()
	local passed = 0
	for _, case in cases do
		local ok, err = pcall(case.fn)
		if ok then
			passed += 1
		else
			warn("[InventoryLogicTests] FAIL:", case.name, "-", err)
		end
	end
	print(`[InventoryLogicTests] {passed}/{#cases} passed`)
end

return Tests
